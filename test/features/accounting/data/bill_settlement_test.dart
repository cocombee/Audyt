import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;
import 'bill_posting_test.dart' show payableAccount, saveManualDraft;

Future<(AccountingWorkspace, List<EntityId>, EntityId, EntityId)>
settlementFixture(
  String path, {
  DateTime? createdAt,
  DateTime? approvedAt,
}) async {
  final w = await AccountingWorkspace.open(path);
  final (vendor, expense) = await setupBill(w);
  final payable = await payableAccount(w);
  await w.createAccount(
    code: '1000',
    name: 'Fictional Settlement Bank',
    type: AccountType.asset,
  );
  final bank = (await w.accounts()).firstWhere((a) => a.account.code == '1000');
  w.database.savePaymentAccount(
    w.identity.businessId,
    PaymentAccount.create(
      id: 'fictional-bank',
      name: 'Fictional Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    ),
  );
  w.database.linkPaymentLedgerAccount(
    w.identity.businessId,
    'fictional-bank',
    bank.account.id,
  );
  final ids = <EntityId>[];
  for (var i = 0; i < 2; i++) {
    final bill = billFixture(w, vendor, expense.account.id, at: createdAt);
    w.saveBillDraft(bill, expectedRevision: 0);
    w.postBill(
      requestId: EntityId.random(),
      billId: bill.id,
      expectedRevision: 1,
      payableAccountId: payable.account.id,
      approvedAt: approvedAt ?? DateTime.utc(2026, 9, 28, 1),
    );
    ids.add(bill.id);
  }
  return (w, ids, bank.account.id, payable.account.id);
}

BillSettlementAllocation allocation(
  EntityId id,
  int before,
  int paid, {
  int revision = 1,
  String currency = 'MYR',
}) => BillSettlementAllocation(
  billId: id,
  revision: revision,
  expectedRemaining: Money.fromMinor(before, currency),
  amount: Money.fromMinor(paid, currency),
);

void main() {
  test('payable directory filters before bounded pagination and preserves payment history totals', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-payable-directory-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final (w, ids, bank, payable) = await settlementFixture(
      '${root.path}/source.sqlite',
    );
    addTearDown(w.dispose);
    final source = w.database.readBillDraft(w.identity.businessId, ids.first)!;
    final account = source.lines.first.categoryId!;
    for (var i = 0; i < 12; i++) {
      final bill = billFixture(w, source.vendorSnapshot, account);
      w.saveBillDraft(bill, expectedRevision: 0);
      w.postBill(
        requestId: EntityId.random(),
        billId: bill.id,
        expectedRevision: 1,
        payableAccountId: payable,
        approvedAt: DateTime.utc(2026, 9, 28, 1),
      );
      ids.add(bill.id);
    }
    final draft = billFixture(w, source.vendorSnapshot, account);
    w.saveBillDraft(draft, expectedRevision: 0);
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [
        for (final id in ids.take(8)) allocation(id, 15120, 15120),
        allocation(ids[8], 15120, 120),
      ],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional directory payment',
      paidOn: DateTime.utc(2026, 9, 28),
      approvedAt: DateTime.utc(2026, 9, 28, 2),
    );
    final first = w.database.payableBillPage(
      businessId: w.identity.businessId,
      limit: 5,
    );
    final last = w.database.payableBillPage(
      businessId: w.identity.businessId,
      limit: 5,
      offset: 1000,
    );
    expect(first.total, 6);
    expect(first.records, hasLength(5));
    expect(last.offset, 5);
    expect(last.records, hasLength(1));
    expect({
      ...first.records.map((r) => r.source.id),
      ...last.records.map((r) => r.source.id),
    }, ids.skip(8).toSet());
    expect(
      w.database
          .payableBillPage(
            businessId: w.identity.businessId,
            status: PayableBillStatus.paid,
          )
          .total,
      8,
    );
    expect(
      w.database
          .payableBillPage(
            businessId: w.identity.businessId,
            status: PayableBillStatus.unpaid,
          )
          .total,
      5,
    );
    final partial = w.database.payableBillPage(
      businessId: w.identity.businessId,
      status: PayableBillStatus.partiallyPaid,
    );
    expect(partial.total, 1);
    expect(partial.records.single.remaining, Money.fromMinor(15000, 'MYR'));
    expect(partial.records.single.status, 'Partially Paid');
    expect(
      w.database
          .payableBillPage(businessId: w.identity.businessId, status: null)
          .total,
      14,
    );
    expect(
      w.database
          .payableBillPage(businessId: EntityId.random(), status: null)
          .total,
      0,
    );
    expect(
      w.database
          .payableBillPage(
            businessId: w.identity.businessId,
            search: draft.documentNumber,
            status: null,
          )
          .total,
      0,
    );
    expect(
      w.database
          .payableBillPage(
            businessId: w.identity.businessId,
            search: source.documentNumber,
            status: null,
          )
          .records
          .single
          .source
          .id,
      source.id,
    );
    expect(w.database.billSettlementCount(w.identity.businessId, ids[8]), 1);
    expect(w.database.billSettlementCount(EntityId.random(), ids[8]), 0);
    expect(
      () => w.database.payableBillPage(
        businessId: w.identity.businessId,
        limit: 101,
      ),
      throwsArgumentError,
    );
  });

  test('partial/full bill payments settle payables once, retain dated balances and all metadata through reopen and restore', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-settlement-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    var (w, ids, bank, payable) = await settlementFixture(path);
    final originalSources = ids
        .map(
          (id) => w.database.readBillDraft(w.identity.businessId, id)!.toJson(),
        )
        .toList();
    final firstId = EntityId.random();
    final reviewed = [
      allocation(ids[0], 15120, 6000),
      allocation(ids[1], 15120, 4000),
    ];
    StoredBillSettlement payFirst() => w.settleRecognizedBills(
      requestId: firstId,
      allocations: reviewed,
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional first payment',
      paidOn: DateTime.utc(2026, 9, 15),
      approvedAt: DateTime.utc(2026, 9, 29, 1),
    );
    final first = payFirst();
    expect(first.total, Money.fromMinor(10000, 'MYR'));
    final saved = tables(w);
    expect(payFirst().id, firstId);
    expect(tables(w), saved);
    expect(
      w.database.billOutstanding(w.identity.businessId, ids[0]),
      Money.fromMinor(9120, 'MYR'),
    );
    expect(
      w.database.billOutstanding(w.identity.businessId, ids[1]),
      Money.fromMinor(11120, 'MYR'),
    );
    expect(
      w.database.billOutstanding(
        w.identity.businessId,
        ids[0],
        asOf: DateTime.utc(2026, 8, 31),
      ),
      Money.zero('MYR'),
    );
    expect(
      w.database.billOutstanding(
        w.identity.businessId,
        ids[0],
        asOf: DateTime.utc(2026, 9, 14),
      ),
      Money.fromMinor(15120, 'MYR'),
    );
    final report = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(report.periodProfit, BigInt.from(-30240));
    expect(report.assets, BigInt.from(-10000));
    expect(report.liabilities, BigInt.from(20240));
    expect(report.isBalanced, true);
    final beforeReport = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 9, 14),
    );
    expect(beforeReport.assets, BigInt.zero);
    expect(beforeReport.liabilities, BigInt.from(30240));
    final second = w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [
        allocation(ids[0], 9120, 9120),
        allocation(ids[1], 11120, 11120),
      ],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional final payment',
      paidOn: DateTime.utc(2026, 9, 30),
      approvedAt: DateTime.utc(2026, 9, 30, 2),
    );
    expect(second.total, Money.fromMinor(20240, 'MYR'));
    final finalReport = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(finalReport.periodProfit, BigInt.from(-30240));
    expect(finalReport.assets, BigInt.from(-30240));
    expect(finalReport.liabilities, BigInt.zero);
    expect(finalReport.isBalanced, true);
    for (var i = 0; i < ids.length; i++) {
      expect(
        w.database.billOutstanding(w.identity.businessId, ids[i]),
        Money.zero('MYR'),
      );
      expect(
        w.database.readBillDraft(w.identity.businessId, ids[i])!.toJson(),
        originalSources[i],
      );
      expect(
        w.database.billSettlementsForBill(w.identity.businessId, ids[i]),
        hasLength(2),
      );
    }
    final all = tables(w);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 1),
    );
    w.dispose();
    final sourceBytes = File(path).readAsBytesSync();
    w = await AccountingWorkspace.open(path);
    expect(tables(w), all);
    expect(
      w.database.readBillSettlement(w.identity.businessId, firstId)!.total,
      first.total,
    );
    w.dispose();
    final targetPath = '${root.path}/restore.sqlite';
    final restore = await AccountingWorkspace.emptyRestore(targetPath, archive);
    expect(tables(restore), all);
    expect(
      restore.database.billOutstanding(restore.identity.businessId, ids[0]),
      Money.zero('MYR'),
    );
    expect(
      restore.database
          .readBillSettlement(restore.identity.businessId, second.id)!
          .bankAccountId,
      bank,
    );
    restore.dispose();
    final again = await AccountingWorkspace.open(targetPath);
    expect(tables(again), all);
    again.dispose();
    expect(File(path).readAsBytesSync(), sourceBytes);
    final raw = sqlite3.open(targetPath, mode: OpenMode.readOnly);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    expect(raw.select('PRAGMA integrity_check').single.values.first, 'ok');
    expect(
      raw
          .select(
            'SELECT sum(amount_minor) AS paid FROM bill_settlement_allocations',
          )
          .single['paid'],
      30240,
    );
    expect(
      raw.select(
        "SELECT sum(amount_minor) AS debit FROM journal_lines WHERE account_id=? AND kind='debit'",
        [payable.value],
      ).single['debit'],
      30240,
    );
    raw.dispose();
  });

  test('a concurrent partial payment invalidates reviewed balances and all rejected requests remain atomic', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bill-payment-review-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    final (w, ids, bank, payable) = await settlementFixture(path);
    addTearDown(w.dispose);
    final competing = await AccountingWorkspace.open(path);
    addTearDown(competing.dispose);
    final request = EntityId.random();
    w.settleRecognizedBills(
      requestId: request,
      allocations: [allocation(ids[0], 15120, 6000)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Winning payment',
      paidOn: DateTime.utc(2026, 9, 28),
      approvedAt: DateTime.utc(2026, 9, 29),
    );
    final winner = tables(w);
    void pay(
      List<BillSettlementAllocation> allocations, {
      EntityId? requestId,
      String account = 'fictional-bank',
      EntityId? company,
      EntityId? actor,
      String reference = 'Rejected payment',
      DateTime? at,
      DateTime? date,
    }) => competing.database.settleRecognizedBills(
      businessId: company ?? w.identity.businessId,
      actorId: actor ?? w.identity.ownerId,
      requestId: requestId ?? EntityId.random(),
      allocations: allocations,
      paymentAccountId: account,
      paymentReference: reference,
      paidOn: date ?? DateTime.utc(2026, 9, 28),
      approvedAt: at ?? DateTime.utc(2026, 9, 29, 2),
    );
    final stale = [allocation(ids[0], 15120, 1000)];
    for (final fail in <void Function()>[
      () => pay(stale),
      () => pay([allocation(ids[0], 9120, 9121)]),
      () => pay([allocation(ids[0], 9120, 1000, revision: 2)]),
      () => pay([allocation(ids[0], 9120, 1000, currency: 'SGD')]),
      () => pay([allocation(ids[0], 9120, 1000)], company: EntityId.random()),
      () => pay([allocation(ids[0], 9120, 1000)], actor: EntityId.random()),
      () => pay([allocation(EntityId.random(), 9120, 1000)]),
      () => pay([allocation(ids[0], 9120, 1000)], account: 'missing-bank'),
      () => pay([
        allocation(ids[0], 9120, 1000),
      ], date: DateTime.utc(2026, 8, 31)),
      () =>
          pay([allocation(ids[0], 9120, 1000)], at: DateTime.utc(2026, 9, 28)),
      () => pay([allocation(ids[0], 9120, 1000)], requestId: request),
      () =>
          pay([allocation(ids[0], 9120, 1000), allocation(ids[0], 9120, 1000)]),
    ]) {
      expect(fail, throwsA(anything));
      expect(tables(w), winner);
    }
    final journal = (await w.database.listJournals(w.identity.businessId))
        .firstWhere((j) => j.entry.id == request);
    final reversal = journal.entry.reversal(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 30),
      memo: 'Fictional unlinked payment reversal',
    );
    await saveManualDraft(w, reversal);
    final beforeReverse = tables(w);
    await expectLater(
      w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: reversal.id,
          expectedRevision: 1,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.utc(2026, 9, 30),
        ),
      ),
      throwsStateError,
    );
    expect(tables(w), beforeReverse);
    await w.database.closeThrough(
      businessId: w.identity.businessId,
      actorId: w.identity.ownerId,
      date: DateTime.utc(2026, 9, 28),
      changedAt: DateTime.utc(2026, 9, 30),
      reason: 'Fictional closed period',
    );
    final closed = tables(w);
    expect(() => pay([allocation(ids[0], 9120, 1000)]), throwsStateError);
    expect(tables(w), closed);
  });

  test('settlement recovery rejects missing, altered and detached payment evidence without changing the destination', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bill-payment-archive-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final (w, ids, bank, payable) = await settlementFixture(
      '${root.path}/source.sqlite',
    );
    addTearDown(w.dispose);
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [allocation(ids[0], 15120, 6000)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'First payment',
      paidOn: DateTime.utc(2026, 9, 28),
      approvedAt: DateTime.utc(2026, 9, 29),
    );
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [allocation(ids[0], 9120, 9120)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Last payment',
      paidOn: DateTime.utc(2026, 9, 30),
      approvedAt: DateTime.utc(2026, 9, 30),
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 1),
    );
    for (final failure in [
      'missing header',
      'missing allocation',
      'missing audit',
      'missing approval',
      'altered amount',
      'altered review balance',
      'altered bank',
      'altered date',
    ]) {
      final data = body(archive), table = data['tables'] as Map;
      final payments = (table['bill_settlements'] as Map),
          allocations = (table['bill_settlement_allocations'] as Map);
      final paymentRows = payments['rows'] as List,
          allocationRows = allocations['rows'] as List;
      final request = paymentRows
          .first[(payments['columns'] as List).indexOf('request_id')];
      if (failure == 'missing header') paymentRows.removeAt(0);
      if (failure == 'missing allocation') allocationRows.removeAt(0);
      if (failure == 'missing audit' || failure == 'missing approval') {
        final owner =
            table[failure == 'missing audit'
                    ? 'ledger_audit'
                    : 'journal_approvals']
                as Map;
        final columns = owner['columns'] as List;
        (owner['rows'] as List).removeWhere(
          (r) =>
              r[columns.indexOf(
                failure == 'missing audit' ? 'subject_id' : 'request_id',
              )] ==
              request,
        );
      }
      if (failure == 'altered amount' || failure == 'altered review balance') {
        allocationRows.first[(allocations['columns'] as List).indexOf(
              failure == 'altered amount'
                  ? 'amount_minor'
                  : 'expected_remaining_minor',
            )] =
            7000;
      }
      if (failure == 'altered bank') {
        paymentRows.first[(payments['columns'] as List).indexOf(
              'bank_account_id',
            )] =
            payable.value;
      }
      if (failure == 'altered date') {
        paymentRows.first[(payments['columns'] as List).indexOf('paid_on')] =
            '2026-08-01T00:00:00.000Z';
      }
      final targetPath = '${root.path}/$failure.sqlite';
      final target = LocalAccountingDatabase.open(targetPath);
      expect(
        () => target.restoreDataArchive(envelope(data)),
        throwsA(anything),
        reason: failure,
      );
      target.close();
      final raw = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      for (final row in raw.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )) {
        expect(
          raw.select('SELECT count(*) AS n FROM "${row['name']}"').single['n'],
          0,
          reason: failure,
        );
      }
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      raw.dispose();
    }
  });

  test('schema 41 archived and on-disk books upgrade without rewriting any existing record', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bill-payment-upgrade-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    final (w, ids, bank, payable) = await settlementFixture(path);
    final original = tables(w);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 28, 3),
    );
    final oldArchive = envelope(historical(archive, 41));
    w.dispose();
    final raw = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(raw);
    removeExpenseRemovalSchema(raw);
    raw.execute('DROP TABLE bill_settlement_allocations');
    raw.execute('DROP TABLE bill_settlements');
    raw.execute('DROP INDEX bill_settlement_audit');
    raw.execute('DROP TABLE IF EXISTS catalogue_items');
    raw.execute('DROP TABLE IF EXISTS catalogue_categories');
    raw.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    raw.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    raw.execute('DROP TABLE IF EXISTS recurring_document_template_history');
    raw.execute('DROP TABLE IF EXISTS recurring_document_templates');
    raw.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_rates');
    raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    raw.execute('DROP TABLE IF EXISTS tax_remittances');
    raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=41');
    raw.dispose();
    final reopened = await AccountingWorkspace.open(path);
    expect(tables(reopened), original);
    reopened.dispose();
    final recovered = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      oldArchive,
    );
    expect(tables(recovered), original);
    expect(
      recovered.database.billOutstanding(recovered.identity.businessId, ids[0]),
      Money.fromMinor(15120, 'MYR'),
    );
    recovered.dispose();
  });
}
