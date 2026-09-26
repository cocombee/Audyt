import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/domain/vendor.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'vendor_persistence_test.dart' show vendorFixture;

Future<(Vendor, StoredAccount)> setupBill(AccountingWorkspace w) async {
  await w.createAccount(
    code: '5000',
    name: 'Fictional Purchase',
    type: AccountType.expense,
  );
  final payee = w.payees.add(
    id: 'legacy-supplier-string',
    name: 'Fictional Supplier',
    type: PayeeType.supplier,
  );
  final vendor = vendorFixture(w, payee: payee);
  w.saveVendor(vendor, expectedRevision: 0, expectedPayee: payee);
  return (
    vendor,
    (await w.accounts()).singleWhere((a) => a.account.code == '5000'),
  );
}

PurchaseBillDraft billFixture(
  AccountingWorkspace w,
  Vendor vendor,
  EntityId account, {
  PurchaseBillDraft? previous,
  EntityId? id,
  String memo = 'Saved purchase',
  String? number,
  String currency = 'MYR',
  DateTime? at,
  List<ReceiptAttachment>? attachments,
}) {
  final recordId = previous?.id ?? id ?? EntityId.random();
  return PurchaseBillDraft(
    metadata:
        previous?.metadata.nextRevision(
          updatedAt: at ?? DateTime.utc(2026, 9, 28, 1),
        ) ??
        RecordMetadata.initial(
          recordId: recordId,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: at ?? DateTime.utc(2026, 9, 28),
        ),
    vendorSnapshot: vendor,
    documentNumber:
        number ??
        previous?.documentNumber ??
        w.database.allocateDocumentNumber(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          recordId: recordId,
          documentType: 'bill',
          allocatedAt: DateTime.utc(2026, 9, 28),
        ),
    issueDate: DateTime.utc(2026, 9, 1),
    dueDate: DateTime.utc(2026, 10, 1),
    terms: PaymentTerms.netDays(30),
    lines: [
      SalesLineItem.category(
        id: previous?.lines.single.id ?? EntityId.random(),
        categoryId: account,
        description: 'Fictional supply',
        quantity: SalesQuantity.fromDecimal('1.5'),
        rate: Money.fromMinor(10000, currency),
        discount: Money.fromMinor(1000, currency),
        taxRatePercent: '8',
      ),
    ],
    supplierReference: 'SUP-001',
    memo: memo,
    classification: 'Saved Class',
    location: 'Saved Branch',
    attachments:
        attachments ??
        previous?.attachments ??
        [
          ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: 'bill-source',
              batchId: 'bill-batch',
              filename: 'fictional-bill.pdf',
              mimeType: 'application/pdf',
              bytes: Uint8List.fromList([37, 80, 68, 70]),
            ),
          ),
        ],
  );
}

void main() {
  test('two SQLite connections reject a competing edit while retaining the winning snapshot and number', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-concurrent-');
    addTearDown(() => root.deleteSync(recursive: true));
    final first = await AccountingWorkspace.open('${root.path}/books.sqlite');
    addTearDown(first.dispose);
    final (vendor, account) = await setupBill(first);
    final draft = billFixture(first, vendor, account.account.id);
    first.saveBillDraft(draft, expectedRevision: 0);
    final second = await AccountingWorkspace.open('${root.path}/books.sqlite');
    addTearDown(second.dispose);
    final reviewed = second.database.readBillDraft(
      second.identity.businessId,
      draft.id,
    )!;
    final winning = billFixture(
      first,
      vendor,
      account.account.id,
      previous: draft,
      memo: 'First connection saved',
    );
    first.saveBillDraft(winning, expectedRevision: 1);
    final stale = billFixture(
      second,
      vendor,
      account.account.id,
      previous: reviewed,
      memo: 'Second connection stale',
    );
    final before = tables(first);
    expect(
      () => second.saveBillDraft(stale, expectedRevision: 1),
      throwsStateError,
    );
    expect(tables(second), before);
    expect(tables(first), before);
    expect(
      second.database
          .readBillDraft(second.identity.businessId, draft.id)!
          .toJson(),
      winning.toJson(),
    );
    expect(
      second.database.billDraftHistory(second.identity.businessId, draft.id),
      hasLength(2),
    );
  });

  test('draft line arithmetic, strict snapshots and unordered JSON objects preserve facts', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, account) = await setupBill(w);
    final bill = billFixture(w, vendor, account.account.id);
    expect(bill.total.minorUnits, 15120);
    final json = bill.toJson();
    expect(PurchaseBillDraft.fromJson(json).toJson(), json);
    expect(
      PurchaseBillDraft.fromJson({
        for (final key in json.keys.toList().reversed) key: json[key],
      }).toJson(),
      json,
    );
    for (final mutation in [
      {...json, 'extra': true},
      {
        ...json,
        'bill': {...(json['bill'] as Map), 'amountMinor': 1},
      },
      {
        ...json,
        'bill': {...(json['bill'] as Map), 'vendorId': EntityId.random().value},
      },
      {
        ...json,
        'lines': [...json['lines'] as List, ...json['lines'] as List],
      },
      {
        ...json,
        'attachments': [
          {
            ...((json['attachments'] as List).single as Map),
            'secretBytes': 'unexpected',
          },
        ],
      },
    ]) {
      expect(
        () => PurchaseBillDraft.fromJson(
          jsonDecode(jsonEncode(mutation)) as Map<String, dynamic>,
        ),
        throwsFormatException,
      );
    }
  });

  test('exact retries, historical supplier and line IDs survive reopen and data-only restore without posting', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-draft-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    var w = await AccountingWorkspace.open(path);
    final (vendor, account) = await setupBill(w);
    final bill = billFixture(w, vendor, account.account.id);
    final before = tables(w);
    final beforeReport = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    w.saveBillDraft(bill, expectedRevision: 0);
    final first = tables(w);
    w.saveBillDraft(bill, expectedRevision: 0);
    expect(tables(w), first);
    var changed = vendorFixture(
      w,
      original: vendor,
      name: 'Fictional Supplier Renamed',
      at: DateTime.utc(2026, 9, 28, 0, 30),
    );
    w.saveVendor(changed, expectedRevision: 1);
    final second = billFixture(
      w,
      vendor,
      account.account.id,
      previous: bill,
      memo: 'Revised memo',
    );
    w.saveBillDraft(second, expectedRevision: 1);
    expect(
      w.database
          .billDraftHistory(w.identity.businessId, bill.id)
          .map((b) => b.vendorSnapshot.name),
      [vendor.name, vendor.name],
    );
    expect(second.lines.single.id, bill.lines.single.id);
    final saved = tables(w);
    for (final name in before.keys.where(
      (n) => !{
        'bill_drafts',
        'bill_draft_history',
        'ledger_audit',
        'payees',
        'vendor_profiles',
        'vendor_history',
      }.contains(n),
    )) {
      expect(saved[name], before[name], reason: name);
    }
    final afterReport = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(afterReport.periodProfit, beforeReport.periodProfit);
    expect(afterReport.assets, beforeReport.assets);
    expect(afterReport.isBalanced, true);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 28, 2),
    );
    w.dispose();
    final hash = sha256.convert(File(path).readAsBytesSync()).toString();
    w = await AccountingWorkspace.open(path);
    expect(tables(w), saved);
    expect(
      w.database.readBillDraft(w.identity.businessId, bill.id)!.toJson(),
      second.toJson(),
    );
    w.dispose();
    w = await AccountingWorkspace.emptyRestore(
      '${root.path}/restore.sqlite',
      archive,
    );
    expect(tables(w), saved);
    final restored = w.database.readBillDraft(w.identity.businessId, bill.id)!;
    expect(restored.vendorSnapshot.payeeId, 'legacy-supplier-string');
    expect(restored.memo, second.memo);
    expect(restored.classification, 'Saved Class');
    expect(restored.location, 'Saved Branch');
    expect(
      restored.attachments.single.originalSha256,
      bill.attachments.single.originalSha256,
    );
    expect(restored.attachments.single.originalBytes, isEmpty);
    expect(
      restored.attachments.single.status,
      AttachmentProcessingStatus.failed,
    );
    expect(
      w.database.billDraftHistory(w.identity.businessId, bill.id),
      hasLength(2),
    );
    expect(
      (await w.report(
        from: DateTime.utc(2026),
        through: DateTime.utc(2026, 12, 31),
      )).periodProfit,
      beforeReport.periodProfit,
    );
    expect(sha256.convert(File(path).readAsBytesSync()).toString(), hash);
    w.dispose();
  });

  for (final change in ['locked', 'archived', 'parent', 'income', 'missing']) {
    test('draft save rejects $change purchase accounts atomically', () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final (vendor, stored) = await setupBill(w);
      final bill = billFixture(w, vendor, stored.account.id);
      w.saveBillDraft(bill, expectedRevision: 0);
      if (change != 'missing') {
        await w.database.saveAccount(
          StoredAccount(
            account: Account.create(
              id: stored.account.id,
              code: stored.account.code,
              name: stored.account.name,
              type: change == 'income'
                  ? AccountType.income
                  : AccountType.expense,
              status: change == 'locked'
                  ? AccountStatus.locked
                  : change == 'archived'
                  ? AccountStatus.archived
                  : AccountStatus.active,
              isParent: change == 'parent',
            ),
            metadata: stored.metadata.nextRevision(
              updatedAt: stored.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            ),
          ),
        );
      }
      final bad = billFixture(
        w,
        vendor,
        change == 'missing' ? EntityId.random() : stored.account.id,
        previous: bill,
      );
      final before = tables(w);
      expect(() => w.saveBillDraft(bad, expectedRevision: 1), throwsStateError);
      expect(tables(w), before);
      expect(
        w.database.readBillDraft(w.identity.businessId, bill.id)!.toJson(),
        bill.toJson(),
      );
    });
  }

  test('stale revisions, supplier races, number identity, changed creation and unauthorized actors reject unchanged', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, account) = await setupBill(w);
    final bill = billFixture(w, vendor, account.account.id);
    w.saveBillDraft(bill, expectedRevision: 0);
    final second = billFixture(w, vendor, account.account.id, previous: bill);
    w.saveBillDraft(second, expectedRevision: 1);
    final stale = billFixture(
      w,
      vendor,
      account.account.id,
      previous: bill,
      memo: 'Competing memo',
    );
    final before = tables(w);
    expect(() => w.saveBillDraft(stale, expectedRevision: 1), throwsStateError);
    expect(
      () => w.database.saveBillDraft(
        businessId: w.identity.businessId,
        actorId: EntityId.random(),
        bill: second,
        expectedRevision: 1,
      ),
      throwsStateError,
    );
    expect(
      () => w.database.saveBillDraft(
        businessId: EntityId.random(),
        actorId: w.identity.ownerId,
        bill: second,
        expectedRevision: 1,
      ),
      throwsStateError,
    );
    expect(
      () => w.saveBillDraft(
        billFixture(
          w,
          vendor,
          account.account.id,
          previous: second,
          number: 'BILL-OTHER',
          at: DateTime.utc(2026, 9, 28, 2),
        ),
        expectedRevision: 2,
      ),
      throwsStateError,
    );
    final changedCreation = second.toJson();
    changedCreation['createdAt'] = DateTime.utc(2026, 9, 27).toIso8601String();
    changedCreation['updatedAt'] = DateTime.utc(
      2026,
      9,
      28,
      2,
    ).toIso8601String();
    changedCreation['revision'] = 3;
    expect(
      () => w.saveBillDraft(
        PurchaseBillDraft.fromJson(changedCreation),
        expectedRevision: 2,
      ),
      throwsStateError,
    );
    expect(tables(w), before);
    final pending = billFixture(w, vendor, account.account.id);
    w.saveVendor(
      vendorFixture(
        w,
        original: vendor,
        name: 'Changed while open',
        at: DateTime.utc(2026, 9, 28, 0, 30),
      ),
      expectedRevision: 1,
    );
    final current = tables(w);
    expect(
      () => w.saveBillDraft(pending, expectedRevision: 0),
      throwsStateError,
    );
    expect(tables(w), current);
  });

  test(
    'bounded SQL queries clamp pages and preserve foreign draft amounts',
    () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final (vendor, account) = await setupBill(w);
      for (var n = 0; n < 13; n++) {
        w.saveBillDraft(
          billFixture(
            w,
            vendor,
            account.account.id,
            memo: 'Record $n',
            currency: 'SGD',
          ),
          expectedRevision: 0,
        );
      }
      final page = w.database.billDraftPage(
        businessId: w.identity.businessId,
        offset: 9999,
        limit: 10,
      );
      expect(page.total, 13);
      expect(page.offset, 10);
      expect(page.records, hasLength(3));
      expect(page.records.every((b) => b.total.currency == 'SGD'), true);
      expect(
        w.database
            .billDraftPage(
              businessId: w.identity.businessId,
              search: 'no match',
            )
            .total,
        0,
      );
      expect(
        w.database
            .billDraftPage(
              businessId: w.identity.businessId,
              search: vendor.name.toUpperCase(),
            )
            .total,
        13,
      );
      expect(
        w.database
            .billDraftPage(
              businessId: w.identity.businessId,
              search: 'record 12',
            )
            .total,
        1,
      );
      expect(
        w.database
            .billDraftPage(
              businessId: w.identity.businessId,
              search: 'bill-source',
            )
            .total,
        0,
      );
      expect(
        w.database
            .billDraftPage(businessId: w.identity.businessId, search: 'SUP-001')
            .total,
        13,
      );
      expect(
        w.database.billDraftPage(businessId: EntityId.random()).records,
        isEmpty,
      );
      expect(
        () => w.database.billDraftPage(
          businessId: w.identity.businessId,
          limit: 101,
        ),
        throwsArgumentError,
      );
      expect(await w.journals(), isEmpty);
    },
  );

  test(
    'schema 40 upgrade retains every old row and adds empty bill tables',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-bill-upgrade-');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = await AccountingWorkspace.open(':memory:');
      final (vendor, _) = await setupBill(source);
      final data = historical(
        source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.utc(2026, 9, 28),
        ),
        40,
      );
      source.dispose();
      final restored = await AccountingWorkspace.emptyRestore(
        '${root.path}/old.sqlite',
        envelope(data),
      );
      final current = tables(restored);
      for (final name in (data['tables'] as Map).keys) {
        final oldTable = (data['tables'] as Map)[name] as Map;
        final newTable = current[name] as Map;
        final oldColumns = List<String>.from(oldTable['columns'] as List);
        final newColumns = List<String>.from(newTable['columns'] as List);
        // Compare every historical field unchanged after the schema-49
        // recoverable-removal metadata is added; column additions are expected.
        final retainedRows = [
          for (final row in newTable['rows'] as List)
            [
              for (final column in oldColumns)
                (row as List)[newColumns.indexOf(column)],
            ],
        ];
        expect(retainedRows, oldTable['rows'], reason: name);
        if (name == 'expense_intakes') {
          expect(
            newColumns,
            containsAll(['revision', 'archived_at', 'state_changed_at']),
          );
          for (final row in newTable['rows'] as List) {
            expect((row as List)[newColumns.indexOf('revision')], 1);
            expect(row[newColumns.indexOf('archived_at')], isNull);
          }
        } else if (name == 'accounts') {
          expect(newColumns, [...oldColumns, 'profile'], reason: name);
          for (final row in newTable['rows'] as List) {
            expect((row as List)[newColumns.indexOf('profile')], isNull);
          }
        } else {
          expect(newColumns, oldColumns, reason: name);
        }
      }
      expect((current['bill_drafts'] as Map)['rows'], isEmpty);
      expect((current['bill_draft_history'] as Map)['rows'], isEmpty);
      expect(
        restored.database
            .readVendor(restored.identity.businessId, vendor.id)!
            .payeeId,
        'legacy-supplier-string',
      );
      restored.dispose();
    },
  );

  test('corrupt bill history and supplier snapshots reject restore and history cannot be rewritten', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-corrupt-');
    addTearDown(() => root.deleteSync(recursive: true));
    final w = await AccountingWorkspace.open('${root.path}/source.sqlite');
    final (vendor, account) = await setupBill(w);
    final bill = billFixture(w, vendor, account.account.id);
    w.saveBillDraft(bill, expectedRevision: 0);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 28),
    );
    final before = tables(w);
    for (final target in ['bill_draft_history', 'bill_drafts']) {
      final data = body(archive);
      final table = (data['tables'] as Map)[target] as Map;
      if (target == 'bill_draft_history') {
        (table['rows'] as List).clear();
      } else {
        final cols = table['columns'] as List;
        final row = (table['rows'] as List).single as List;
        final payload = jsonDecode(
          row[cols.indexOf('payload')] as String,
        ) as Map<String, dynamic>;
        (payload['vendor'] as Map)['name'] = 'Fabricated supplier';
        row[cols.indexOf('payload')] = jsonEncode(payload);
      }
      await expectLater(
        AccountingWorkspace.emptyRestore(
          '${root.path}/$target.sqlite',
          envelope(data),
        ),
        throwsFormatException,
      );
    }
    final raw = sqlite3.open('${root.path}/source.sqlite');
    expect(
      () => raw.execute("UPDATE bill_draft_history SET payload='{}'"),
      throwsA(isA<SqliteException>()),
    );
    raw.dispose();
    expect(tables(w), before);
    w.dispose();
  });
}
