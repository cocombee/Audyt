import 'dart:convert';
import 'dart:io';

import '../../../support/historical_sqlite_fixture.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'quotation_persistence_test.dart'
    show quotationWorkspace, quotationDraft;

class CurrentQuotationFixture {
  late Directory dir;
  late AccountingWorkspace w;
  late Customer customer;
  late StoredAccount account;
  late EntityId id;

  Future<void> open({bool accepted = false, bool converted = false}) async {
    dir = Directory.systemTemp.createTempSync('audyt-current-quotation-');
    final fixture = await quotationWorkspace('${dir.path}/source.sqlite');
    w = fixture.$1;
    customer = fixture.$2;
    account = fixture.$3;
    final draft = quotationDraft(customer, account);
    id = draft.id;
    w.saveQuotationDraft(draft, expectedRevision: 0, savedAt: at(1));
    w.changeQuotationState(
      id,
      expectedRevision: 1,
      action: QuotationAction.shared,
      changedAt: at(2),
    );
    if (accepted || converted) {
      w.changeQuotationState(
        id,
        expectedRevision: 2,
        action: QuotationAction.accepted,
        changedAt: at(3),
      );
    }
    if (converted) {
      w.convertQuotationToInvoice(
        id,
        expectedRevision: 3,
        invoiceId: EntityId.random(),
        documentNumber: 'INV-CURRENT-QUOTE',
        issueDate: at(4),
        dueDate: DateTime.utc(2026, 10, 19),
        convertedAt: at(4),
      );
    }
  }

  DateTime at(int day) => DateTime.utc(2026, 9, day);
  StoredQuotation get current =>
      w.database.readQuotation(w.identity.businessId, id)!;
  Estimate replacement({
    String memo = 'Changed current memo',
    String number = 'QT-000001',
  }) => quotationDraft(customer, account, id: id, memo: memo, number: number);
  int save(
    StoredQuotation expected,
    Estimate replacement,
    EntityId request,
    DateTime time,
  ) => w.database.saveCurrentQuotation(
    businessId: w.identity.businessId,
    actorId: w.identity.ownerId,
    requestId: request,
    expected: expected,
    replacement: replacement,
    reviewedCustomer:
        w
            .customers()
            .where((c) => c.id == replacement.customerId && c.isActive)
            .firstOrNull ??
        expected.customerSnapshot,
    savedAt: time,
  );
  void close() {
    w.dispose();
    dir.deleteSync(recursive: true);
  }

  Estimate retainingLines({String memo = 'Retained current facts'}) {
    final value = current.quotation.snapshot();
    final pricing = Map<String, dynamic>.from(value['pricing'] as Map);
    pricing['memo'] = memo;
    return Estimate.fromSnapshot({
      ...value,
      'pricing': pricing,
      'status': 'draft',
      'convertedInvoiceId': null,
    });
  }
}

void main() {
  test('customer changed after document review rejects current save atomically until reviewed again', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    final expected = f.current;
    f.w.saveCustomer(
      f.customer.revise(
        displayName: 'Renamed current customer',
        updatedAt: f.at(5),
      ),
    );
    final before = tables(f.w);
    expect(
      () => f.w.database.saveCurrentQuotation(
        businessId: f.w.identity.businessId,
        actorId: f.w.identity.ownerId,
        requestId: EntityId.random(),
        expected: expected,
        replacement: f.retainingLines(),
        reviewedCustomer: f.customer,
        savedAt: f.at(6),
      ),
      throwsStateError,
    );
    expect(tables(f.w), before);
    f.save(expected, f.retainingLines(), EntityId.random(), f.at(6));
    expect(f.current.customerSnapshot.displayName, 'Renamed current customer');
  });
  for (final action in [
    null,
    QuotationAction.declined,
    QuotationAction.closed,
  ]) {
    test(
      'current ${action?.name ?? 'shared'} quotation saves line replacement without resetting lifecycle',
      () async {
        final f = CurrentQuotationFixture();
        await f.open();
        addTearDown(f.close);
        if (action != null) {
          f.w.changeQuotationState(
            f.id,
            expectedRevision: 2,
            action: action,
            changedAt: f.at(3),
          );
        }
        final original = f.current;
        final changed = f.replacement();
        f.save(original, changed, EntityId.random(), f.at(5));
        expect(f.current.quotation.status, original.quotation.status);
        expect(f.current.quotation.lines.single.id, changed.lines.single.id);
        expect(
          f.current.quotation.lines.single.id,
          isNot(original.quotation.lines.single.id),
        );
        expect(await f.w.journals(), isEmpty);
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(
          f.w.database.exportDataArchive(f.w.identity.businessId, f.at(6)),
        );
        expect(
          restored
              .readQuotation(f.w.identity.businessId, f.id)!
              .quotation
              .status,
          original.quotation.status,
        );
      },
    );
  }
  test('schema-62 database and data-only archive upgrade retain original conversion and gain current revision owner', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    final identity = f.w.identity;
    final original = f.current;
    final oldArchive = envelope(
      historical(
        f.w.database.exportDataArchive(identity.businessId, f.at(5)),
        62,
      ),
    );
    f.w.dispose();
    final raw = sqlite3.open('${f.dir.path}/source.sqlite');
    raw.execute('DROP VIEW current_quotations');
    raw.execute('DROP TABLE converted_quotation_revisions');
    dropCurrentAccountFixtureOwner(raw);
    dropCurrentPaymentMethodFixtureOwner(raw);
    raw.execute('PRAGMA user_version=62');
    raw.dispose();
    f.w = await AccountingWorkspace.open('${f.dir.path}/source.sqlite');
    expect(f.current.quotation.snapshot(), original.quotation.snapshot());
    expect(
      f.save(f.current, f.retainingLines(), EntityId.random(), f.at(6)),
      original.revision + 1,
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(oldArchive);
    final old = restored.readQuotation(identity.businessId, f.id)!;
    expect(old.revision, original.revision);
    expect(
      old.quotation.convertedInvoiceId,
      original.quotation.convertedInvoiceId,
    );
    expect(
      restored.saveCurrentQuotation(
        businessId: identity.businessId,
        actorId: identity.ownerId,
        requestId: EntityId.random(),
        expected: old,
        replacement: f.retainingLines(),
        reviewedCustomer: old.customerSnapshot,
        savedAt: f.at(6),
      ),
      original.revision + 1,
    );
  });

  test('retained inactive customer and income account survive current Memo save; new unavailable-account lines reject', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    f.w.saveCustomer(f.customer.deactivate(updatedAt: f.at(5)));
    await f.w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: f.account.account.id,
          code: f.account.account.code,
          name: f.account.account.name,
          type: AccountType.income,
          status: AccountStatus.locked,
        ),
        metadata: f.account.metadata.nextRevision(
          updatedAt: f.account.metadata.updatedAt.add(
            const Duration(seconds: 1),
          ),
        ),
      ),
    );
    f.save(f.current, f.retainingLines(), EntityId.random(), f.at(6));
    final saved = tables(f.w);
    expect(f.current.customerSnapshot.isActive, isTrue);
    expect(f.current.quotation.memo, 'Retained current facts');
    expect(
      () => f.save(f.current, f.replacement(), EntityId.random(), f.at(7)),
      throwsStateError,
    );
    expect(tables(f.w), saved);
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(
      f.w.database.exportDataArchive(f.w.identity.businessId, f.at(8)),
    );
    expect(
      restored.readQuotation(f.w.identity.businessId, f.id)!.quotation.memo,
      'Retained current facts',
    );
  });

  for (final converted in [false, true]) {
    test(
      'current ${converted ? 'converted' : 'accepted'} quotation retains state, original versions and exact retry through restart and data-only recovery',
      () async {
        final f = CurrentQuotationFixture();
        await f.open(accepted: true, converted: converted);
        addTearDown(f.close);
        final before = f.current;
        final original = tables(f.w);
        final request = EntityId.random();
        final replacement = f.replacement();
        expect(
          f.save(before, replacement, request, f.at(5)),
          before.revision + 1,
        );
        final saved = tables(f.w);
        expect(
          f.save(before, replacement, request, f.at(5)),
          before.revision + 1,
        );
        expect(tables(f.w), saved);
        expect(f.current.quotation.status, before.quotation.status);
        expect(
          f.current.quotation.convertedInvoiceId,
          before.quotation.convertedInvoiceId,
        );
        expect(f.current.quotation.memo, 'Changed current memo');
        expect(f.w.quotations().single.revision, before.revision + 1);
        for (final name in [
          'invoice_drafts',
          'invoice_draft_history',
          'invoice_postings',
          'journal_entries',
        ]) {
          expect(saved[name], original[name], reason: name);
        }
        if (converted) {
          expect(saved['quotation_drafts'], original['quotation_drafts']);
          expect(saved['quotation_history'], original['quotation_history']);
        }
        expect(await f.w.journals(), isEmpty);
        final identity = f.w.identity;
        final archive = f.w.database.exportDataArchive(
          identity.businessId,
          f.at(6),
        );
        final decoded = body(archive);
        expect(
          jsonEncode(decoded),
          isNot(contains('iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB')),
        );
        f.w.dispose();
        f.w = await AccountingWorkspace.open('${f.dir.path}/source.sqlite');
        expect(f.current.quotation.memo, 'Changed current memo');
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(archive);
        final recovered = restored.readQuotation(identity.businessId, f.id)!;
        expect(recovered.revision, before.revision + 1);
        expect(recovered.quotation.memo, 'Changed current memo');
        expect(recovered.quotation.attachments.single.originalBytes, isEmpty);
        expect(
          recovered.quotation.convertedInvoiceId,
          before.quotation.convertedInvoiceId,
        );
        expect(
          restored.readQuotations(identity.businessId).single.revision,
          recovered.revision,
        );
      },
    );
  }

  test('stale, conflicting retry and foreign actor current saves reject without changing any table', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    final before = f.current;
    final request = EntityId.random();
    f.save(before, f.replacement(), request, f.at(5));
    final saved = tables(f.w);
    expect(
      () => f.save(before, f.replacement(memo: 'Conflict'), request, f.at(5)),
      throwsStateError,
    );
    expect(
      () => f.save(before, f.replacement(), EntityId.random(), f.at(6)),
      throwsStateError,
    );
    expect(
      () => f.w.database.saveCurrentQuotation(
        businessId: f.w.identity.businessId,
        actorId: EntityId.random(),
        requestId: EntityId.random(),
        expected: f.current,
        replacement: f.replacement(),
        reviewedCustomer: f.customer,
        savedAt: f.at(6),
      ),
      throwsStateError,
    );
    expect(tables(f.w), saved);
  });

  test('current converted number participates in original allocator without losing occupied original number', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    f.save(
      f.current,
      f.replacement(number: 'QT-000002'),
      EntityId.random(),
      f.at(5),
    );
    final number = f.w.database.allocateDocumentNumber(
      businessId: f.w.identity.businessId,
      actorId: f.w.identity.ownerId,
      recordId: EntityId.random(),
      documentType: 'quotation',
      allocatedAt: f.at(6),
    );
    expect(number, 'QT-000003');
  });

  test('damaged current converted request, actor, before facts or missing audit reject recovery atomically', () async {
    final f = CurrentQuotationFixture();
    await f.open(converted: true);
    addTearDown(f.close);
    f.save(f.current, f.replacement(), EntityId.random(), f.at(5));
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      f.at(6),
    );
    for (final defect in [
      'request_id',
      'actor_id',
      'before_payload',
      'audit',
    ]) {
      final data = body(archive);
      final table = data['tables']['converted_quotation_revisions'] as Map;
      final row = (table['rows'] as List).single as List;
      if (defect == 'audit') {
        final audit = data['tables']['ledger_audit'] as Map;
        final index = (audit['columns'] as List).indexOf('kind');
        (audit['rows'] as List).removeWhere(
          (r) => r[index] == 'quotation_current_saved',
        );
      } else {
        final index = (table['columns'] as List).indexOf(defect);
        if (defect == 'before_payload') {
          final payload = jsonDecode(row[index] as String) as Map;
          payload['pricing']['memo'] = 'Forged earlier facts';
          row[index] = jsonEncode(payload);
        } else {
          row[index] = EntityId.random().value;
        }
      }
      final target = LocalAccountingDatabase.inMemory();
      expect(
        () => target.restoreDataArchive(envelope(data)),
        throwsFormatException,
        reason: defect,
      );
      target.restoreDataArchive(archive);
      expect(
        target.readQuotation(f.w.identity.businessId, f.id)!.quotation.memo,
        'Changed current memo',
      );
      target.close();
    }
  });
}
