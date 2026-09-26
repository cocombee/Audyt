import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope;
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;

Future<StoredAccount> payableAccount(AccountingWorkspace w) async {
  await w.createAccount(
    code: '2100',
    name: 'Fictional Payables',
    type: AccountType.liability,
  );
  return (await w.accounts()).firstWhere((a) => a.account.code == '2100');
}

Future<void> saveManualDraft(AccountingWorkspace w, JournalEntry entry) =>
    w.database.save(
      StoredJournalEntry(
        entry: entry,
        metadata: RecordMetadata.initial(
          recordId: entry.id,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 28),
        ),
      ),
    );

void main() {
  test('mixed purchase recognition is exact, retry-safe and survives reopen/restore without losing evidence or revisions', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-posting-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    var w = await AccountingWorkspace.open(path);
    final (vendor, expense) = await setupBill(w);
    final payable = await payableAccount(w);
    await w.createAccount(
      code: '1500',
      name: 'Fictional Purchased Asset',
      type: AccountType.asset,
    );
    final asset = (await w.accounts()).firstWhere(
      (a) => a.account.code == '1500',
    );
    final initial = billFixture(w, vendor, expense.account.id);
    final json = initial.toJson();
    final assetLine = SalesLineItem.category(
      id: EntityId.random(),
      categoryId: asset.account.id,
      description: 'Fictional equipment',
      quantity: SalesQuantity.fromDecimal('1'),
      rate: Money.fromMinor(5000, 'MYR'),
    );
    json['lines'] = [
      ...initial.lines.map((l) => l.toJson()),
      assetLine.toJson(),
    ];
    json['bill'] = <String, Object?>{
      ...(json['bill'] as Map<String, Object?>),
      'amountMinor': 20120,
    };
    final bill = PurchaseBillDraft.fromJson(json);
    w.saveBillDraft(bill, expectedRevision: 0);
    final request = EntityId.random();
    final approvedAt = DateTime.utc(2026, 9, 28, 1);
    EntityId post({EntityId? requestId, int revision = 1, DateTime? at}) =>
        w.postBill(
          requestId: requestId ?? request,
          billId: bill.id,
          expectedRevision: revision,
          payableAccountId: payable.account.id,
          approvedAt: at ?? approvedAt,
        );
    final before = tables(w);
    expect(() => post(revision: 2), throwsStateError);
    expect(tables(w), before);
    expect(post(), request);
    final saved = tables(w);
    expect(post(), request);
    expect(tables(w), saved);
    expect(() => post(requestId: EntityId.random()), throwsStateError);
    expect(tables(w), saved);
    expect(() => post(at: DateTime.utc(2026, 9, 28, 2)), throwsStateError);
    expect(tables(w), saved);
    expect(
      w.database.billDraftPage(businessId: w.identity.businessId).total,
      0,
    );
    expect(
      w.database
          .billDraftPage(businessId: w.identity.businessId, posted: true)
          .total,
      1,
    );
    expect(
      w.database
          .billDraftPage(businessId: EntityId.random(), posted: true)
          .total,
      0,
    );
    final posting = w.database.readBillPosting(w.identity.businessId, bill.id)!;
    expect(posting.source.toJson(), bill.toJson());
    expect(posting.payableAccountId, payable.account.id);
    expect((await w.journals()), hasLength(1));
    final journal = (await w.journals()).single.entry;
    expect(journal.date, bill.bill.issueDate);
    expect(
      journal.lines.map(
        (l) => [l.kind.name, l.accountId.value, l.amount.minorUnits],
      ),
      [
        ['debit', expense.account.id.value, 15120],
        ['debit', asset.account.id.value, 5000],
        ['credit', payable.account.id.value, 20120],
      ],
    );
    final report = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(report.periodProfit, BigInt.from(-15120));
    expect(report.assets, BigInt.from(5000));
    expect(report.liabilities, BigInt.from(20120));
    expect(report.isBalanced, true);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 28, 3),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(tables(w), saved);
    expect(
      w.database
          .readBillPosting(w.identity.businessId, bill.id)!
          .source
          .toJson(),
      bill.toJson(),
    );
    expect(post(), request);
    expect(tables(w), saved);
    final edits = bill.toJson()
      ..['revision'] = 2
      ..['updatedAt'] = DateTime.utc(2026, 9, 28, 4).toIso8601String()
      ..['memo'] = 'Unapproved edit';
    expect(
      () => w.saveBillDraft(
        PurchaseBillDraft.fromJson(edits),
        expectedRevision: 1,
      ),
      throwsStateError,
    );
    expect(tables(w), saved);
    w.dispose();
    w = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    expect(tables(w), saved);
    expect(post(), request);
    expect(tables(w), saved);
    final restored = w.database.readBillPosting(
      w.identity.businessId,
      bill.id,
    )!;
    expect(restored.source.total, bill.total);
    expect(
      restored.source.attachments.single.originalSha256,
      bill.attachments.single.originalSha256,
    );
    expect(restored.source.attachments.single.originalBytes, isEmpty);
    final restoredReport = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(restoredReport.periodProfit, report.periodProfit);
    expect(restoredReport.assets, report.assets);
    expect(restoredReport.liabilities, report.liabilities);
    expect(restoredReport.isBalanced, true);
    w.dispose();
  });

  for (final failure in [
    'locked purchase',
    'locked payable',
    'parent payable',
    'wrong payable type',
    'missing payable',
    'foreign currency',
    'closed period',
    'wrong actor',
    'wrong company',
    'journal collision',
    'approval before save',
  ]) {
    test(
      '$failure rejects posting without any journal or audit changes',
      () async {
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final (vendor, expense) = await setupBill(w);
        final payable = await payableAccount(w);
        final bill = billFixture(
          w,
          vendor,
          expense.account.id,
          currency: failure == 'foreign currency' ? 'SGD' : 'MYR',
        );
        w.saveBillDraft(bill, expectedRevision: 0);
        if (failure.startsWith('locked') ||
            failure == 'parent payable' ||
            failure == 'wrong payable type') {
          final target = failure == 'locked purchase' ? expense : payable;
          await w.database.saveAccount(
            StoredAccount(
              account: Account.create(
                id: target.account.id,
                code: target.account.code,
                name: target.account.name,
                type: failure == 'wrong payable type'
                    ? AccountType.income
                    : target.account.type,
                status: failure.startsWith('locked')
                    ? AccountStatus.locked
                    : AccountStatus.active,
                isParent: failure == 'parent payable',
              ),
              metadata: target.metadata.nextRevision(
                updatedAt: target.metadata.updatedAt.add(
                  const Duration(seconds: 1),
                ),
              ),
            ),
          );
        }
        if (failure == 'closed period') {
          await w.database.closeThrough(
            businessId: w.identity.businessId,
            actorId: w.identity.ownerId,
            date: DateTime.utc(2026, 9, 1),
            changedAt: DateTime.utc(2026, 9, 28),
            reason: 'Fictional closed period',
          );
        }
        final request = EntityId.random();
        if (failure == 'journal collision') {
          await saveManualDraft(
            w,
            JournalEntry.draft(
              id: request,
              date: DateTime.utc(2026, 9, 1),
              memo: 'Existing manual draft',
              lines: [
                JournalLine.debit(
                  accountId: expense.account.id,
                  amount: Money.fromMinor(1, 'MYR'),
                ),
                JournalLine.credit(
                  accountId: payable.account.id,
                  amount: Money.fromMinor(1, 'MYR'),
                ),
              ],
            ),
          );
        }
        final before = tables(w);
        expect(
          () => w.database.postBill(
            businessId: failure == 'wrong company'
                ? EntityId.random()
                : w.identity.businessId,
            actorId: failure == 'wrong actor'
                ? EntityId.random()
                : w.identity.ownerId,
            requestId: request,
            billId: bill.id,
            expectedRevision: 1,
            payableAccountId: failure == 'missing payable'
                ? EntityId.random()
                : payable.account.id,
            approvedAt: failure == 'approval before save'
                ? DateTime.utc(2026, 9, 27)
                : DateTime.utc(2026, 9, 28, 1),
          ),
          throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
        );
        expect(tables(w), before);
        expect(
          w.database.readBillPosting(w.identity.businessId, bill.id),
          isNull,
        );
      },
    );
  }

  test(
    'unlinked manual reversal cannot detach bill balances from its record',
    () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final (vendor, expense) = await setupBill(w);
      final payable = await payableAccount(w);
      final bill = billFixture(w, vendor, expense.account.id);
      w.saveBillDraft(bill, expectedRevision: 0);
      final posted = w.postBill(
        requestId: EntityId.random(),
        billId: bill.id,
        expectedRevision: 1,
        payableAccountId: payable.account.id,
        approvedAt: DateTime.utc(2026, 9, 28, 1),
      );
      final reversal = EntityId.random();
      await saveManualDraft(
        w,
        (await w.journals()).single.entry.reversal(
          id: reversal,
          date: DateTime.utc(2026, 9, 28),
          memo: 'Unlinked manual reversal',
        ),
      );
      final before = tables(w);
      await expectLater(
        w.database.approve(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: w.identity.businessId,
            journalId: reversal,
            expectedRevision: 1,
            actorId: w.identity.ownerId,
            approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
          ),
        ),
        throwsStateError,
      );
      expect(tables(w), before);
      expect(
        w.database.readBillPosting(w.identity.businessId, bill.id)!.journalId,
        posted,
      );
    },
  );

  test(
    'immutable posting links and corrupt restored recognition reject tampering',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-bill-post-corrupt-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final w = await AccountingWorkspace.open('${root.path}/source.sqlite');
      addTearDown(w.dispose);
      final (vendor, expense) = await setupBill(w);
      final payable = await payableAccount(w);
      final bill = billFixture(w, vendor, expense.account.id);
      w.saveBillDraft(bill, expectedRevision: 0);
      w.postBill(
        requestId: EntityId.random(),
        billId: bill.id,
        expectedRevision: 1,
        payableAccountId: payable.account.id,
        approvedAt: DateTime.utc(2026, 9, 28, 1),
      );
      final archive = w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 9, 28, 3),
      );
      final before = tables(w);
      for (final missing in [
        'bill_postings',
        'bill_drafts',
        'bill.draft_saved',
        'bill.posted',
      ]) {
        final data = body(archive);
        final dataTables = data['tables'] as Map;
        if (missing == 'bill_postings') {
          ((dataTables['bill_postings'] as Map)['rows'] as List).clear();
        } else if (missing == 'bill_drafts') {
          for (final table in [
            'bill_postings',
            'bill_drafts',
            'bill_draft_history',
          ]) {
            ((dataTables[table] as Map)['rows'] as List).clear();
          }
        } else {
          final audit = dataTables['ledger_audit'] as Map;
          final columns = audit['columns'] as List;
          (audit['rows'] as List).removeWhere(
            (row) => row[columns.indexOf('kind')] == missing,
          );
        }
        await expectLater(
          AccountingWorkspace.emptyRestore(
            '${root.path}/missing-$missing.sqlite',
            envelope(data),
          ),
          throwsFormatException,
        );
        expect(tables(w), before);
      }
      for (final field in [
        'revision',
        'signature',
        'payable_account_id',
        'actor_id',
        'approved_at',
      ]) {
        final data = body(archive);
        final table = (data['tables'] as Map)['bill_postings'] as Map;
        final columns = table['columns'] as List;
        final row = (table['rows'] as List).single as List;
        row[columns.indexOf(field)] = switch (field) {
          'revision' => 2,
          'signature' => 'fabricated',
          'payable_account_id' => expense.account.id.value,
          'actor_id' => EntityId.random().value,
          _ => DateTime.utc(2026, 9, 28, 4).toIso8601String(),
        };
        await expectLater(
          AccountingWorkspace.emptyRestore(
            '${root.path}/$field.sqlite',
            envelope(data),
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
        expect(tables(w), before);
      }
      final raw = sqlite3.open('${root.path}/source.sqlite');
      addTearDown(raw.dispose);
      expect(
        () => raw.execute('DELETE FROM bill_postings'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute("UPDATE bill_drafts SET payload='{}'"),
        throwsA(isA<SqliteException>()),
      );
      expect(tables(w), before);
    },
  );
}
