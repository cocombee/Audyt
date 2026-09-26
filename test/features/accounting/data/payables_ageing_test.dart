import 'dart:io';

import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;
import 'bill_posting_test.dart' show payableAccount, saveManualDraft;
import 'bill_settlement_test.dart' show settlementFixture, allocation;

PurchaseBillDraft datedBill(
  PurchaseBillDraft original,
  DateTime issue,
  DateTime due, {
  int? amount,
}) => PurchaseBillDraft(
  metadata: original.metadata,
  vendorSnapshot: original.vendorSnapshot,
  documentNumber: original.documentNumber,
  issueDate: issue,
  dueDate: due,
  terms: PaymentTerms.netDays(due.difference(issue).inDays),
  lines: amount == null
      ? original.lines
      : [
          SalesLineItem.category(
            id: original.lines.first.id,
            categoryId: original.lines.first.categoryId!,
            description: 'Fictional exact amount',
            quantity: SalesQuantity.fromDecimal('1'),
            rate: Money.fromMinor(amount, 'MYR'),
          ),
        ],
  supplierReference: original.supplierReference,
  memo: original.memo,
  classification: original.classification,
  location: original.location,
  attachments: original.attachments,
);

PayablesAgeingSnapshot report(
  AccountingWorkspace w,
  DateTime asOf, {
  int offset = 0,
  int limit = 5,
}) => w.database.payablesAgeing(
  businessId: w.identity.businessId,
  currency: w.identity.currency,
  asOf: asOf,
  offset: offset,
  limit: limit,
);

Object balances(PayablesAgeingSnapshot r) => [
  r.buckets,
  r.total,
  r.outstandingMinor,
  r.controls
      .map((c) => [c.accountId.value, c.billMinor, c.ledgerMinor])
      .toList(),
  r.records
      .map((r) => [r.posting.source.id.value, r.remaining.minorUnits, r.bucket])
      .toList(),
];

void main() {
  test('dated partial/full settlements reconcile year boundaries and survive read-only reopen/restore', () async {
    final root = Directory.systemTemp.createTempSync('audyt-payables-ageing-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    var (w, ids, bank, payable) = await settlementFixture(path);
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [allocation(ids[0], 15120, 120)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional year-end',
      paidOn: DateTime.utc(2026, 12, 31),
      approvedAt: DateTime.utc(2027, 1, 2),
    );
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [
        allocation(ids[0], 15000, 15000),
        allocation(ids[1], 15120, 15120),
      ],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional next-year',
      paidOn: DateTime.utc(2027, 1, 1),
      approvedAt: DateTime.utc(2027, 1, 2, 1),
    );
    final before = tables(w);
    expect(report(w, DateTime.utc(2026, 8, 31)).outstandingMinor, BigInt.zero);
    expect(
      report(w, DateTime.utc(2026, 12, 30)).outstandingMinor,
      BigInt.from(30240),
    );
    final yearEnd = report(w, DateTime.utc(2026, 12, 31, 23, 59));
    expect(yearEnd.outstandingMinor, BigInt.from(30120));
    expect(yearEnd.controls.single.differenceMinor, BigInt.zero);
    expect(yearEnd.controls.single.accountId, payable);
    expect(yearEnd.records.map((r) => r.remaining.minorUnits).toSet(), {
      15000,
      15120,
    });
    final nextYear = report(w, DateTime.utc(2027, 1, 1));
    expect(nextYear.total, 0);
    expect(nextYear.controls.single.ledgerMinor, BigInt.zero);
    expect(tables(w), before);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2027, 1, 3),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(balances(report(w, DateTime.utc(2026, 12, 31))), balances(yearEnd));
    expect(tables(w), before);
    w.dispose();
    w = await AccountingWorkspace.emptyRestore(
      '${root.path}/restore.sqlite',
      archive,
    );
    addTearDown(w.dispose);
    expect(tables(w), before);
    expect(balances(report(w, DateTime.utc(2026, 12, 31))), balances(yearEnd));
    expect(report(w, DateTime.utc(2027, 1, 1)).total, 0);
    expect(tables(w), before);
  });

  test('all boundaries, stable bounded pages, historical controls and full-day manual differences', () async {
    final root = Directory.systemTemp.createTempSync('audyt-payables-buckets-');
    addTearDown(() => root.deleteSync(recursive: true));
    final w = await AccountingWorkspace.open('${root.path}/book.sqlite');
    addTearDown(w.dispose);
    final (vendor, expense) = await setupBill(w);
    final oldControl = await payableAccount(w);
    await w.createAccount(
      code: '2110',
      name: 'Fictional New Payables',
      type: AccountType.liability,
    );
    await w.createAccount(
      code: '2120',
      name: 'Fictional Default Payables',
      type: AccountType.liability,
    );
    final accounts = await w.accounts();
    final newControl = accounts
        .firstWhere((a) => a.account.code == '2110')
        .account
        .id;
    final defaultControl = accounts
        .firstWhere((a) => a.account.code == '2120')
        .account
        .id;
    w.savePreferences(
      w.preferences.change('Default Accounts', {
        'Payables Account': defaultControl.value,
      }),
    );
    final asOf = DateTime.utc(2026, 12, 31);
    for (final age in [-1, 0, 1, 30, 31, 60, 61, 90, 91]) {
      final b = datedBill(
        billFixture(w, vendor, expense.account.id),
        DateTime.utc(2026, 1, 1),
        asOf.subtract(Duration(days: age)),
      );
      w.saveBillDraft(b, expectedRevision: 0);
      w.postBill(
        requestId: EntityId.random(),
        billId: b.id,
        expectedRevision: 1,
        payableAccountId: age <= 30 ? oldControl.account.id : newControl,
        approvedAt: DateTime.utc(2027, 1, 2),
      );
    }
    // A draft and a posted future Bill never contribute to the historical total.
    w.saveBillDraft(
      billFixture(w, vendor, expense.account.id),
      expectedRevision: 0,
    );
    final future = datedBill(
      billFixture(w, vendor, expense.account.id),
      DateTime.utc(2027, 1, 1),
      DateTime.utc(2027, 2, 1),
    );
    w.saveBillDraft(future, expectedRevision: 0);
    w.postBill(
      requestId: EntityId.random(),
      billId: future.id,
      expectedRevision: 1,
      payableAccountId: newControl,
      approvedAt: DateTime.utc(2027, 1, 2),
    );
    final entry = JournalEntry.draft(
      id: EntityId.random(),
      date: DateTime.utc(2026, 12, 31, 23, 59),
      memo: 'Fictional other payable',
      lines: [
        JournalLine.debit(
          accountId: expense.account.id,
          amount: Money.fromMinor(75, 'MYR'),
        ),
        JournalLine.credit(
          accountId: newControl,
          amount: Money.fromMinor(75, 'MYR'),
        ),
      ],
    );
    await saveManualDraft(w, entry);
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: entry.id,
        expectedRevision: 1,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.utc(2027, 1, 3),
      ),
    );
    final before = tables(w);
    final first = report(w, asOf), last = report(w, asOf, offset: 999);
    expect(first.total, 9);
    expect(first.records, hasLength(5));
    expect(last.offset, 5);
    expect(last.records, hasLength(4));
    expect(first.buckets, {
      'Current': BigInt.from(30240),
      '1–30 Days': BigInt.from(30240),
      '31–60 Days': BigInt.from(30240),
      '61–90 Days': BigInt.from(30240),
      'Over 90 Days': BigInt.from(15120),
    });
    final all = [...first.records, ...last.records];
    expect(all.map((r) => r.posting.source.id).toSet(), hasLength(9));
    final dates = all
        .map((r) => formatAccountingInputDate(r.posting.source.bill.dueDate))
        .toList();
    expect(dates.first, '01-10-2026');
    expect(dates.last, '01-01-2027');
    expect(first.controls.map((c) => c.code), ['2100', '2110', '2120']);
    expect(first.controls.first.differenceMinor, BigInt.zero);
    expect(first.controls[1].differenceMinor, BigInt.from(75));
    expect(first.controls.last.billMinor, BigInt.zero);
    expect(first.controls.last.ledgerMinor, BigInt.zero);
    expect(tables(w), before);
    final lastCalendarDate = report(w, DateTime.utc(9999, 12, 31));
    expect(lastCalendarDate.outstandingMinor, BigInt.from(151200));
    expect(
      lastCalendarDate.controls.fold(
        BigInt.zero,
        (sum, c) => sum + c.ledgerMinor,
      ),
      BigInt.from(151275),
    );
    expect(() => report(w, asOf, offset: -1), throwsArgumentError);
    expect(() => report(w, asOf, limit: 51), throwsArgumentError);
  });

  test('exact totals exceed int without overflow and invalid off-page financial links fail honestly', () async {
    final root = Directory.systemTemp.createTempSync('audyt-payables-exact-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final (vendor, expense) = await setupBill(w);
    final payable = await payableAccount(w);
    for (var i = 0; i < 2; i++) {
      final b = datedBill(
        billFixture(w, vendor, expense.account.id),
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        amount: 6000000000000000000,
      );
      w.saveBillDraft(b, expectedRevision: 0);
      w.postBill(
        requestId: EntityId.random(),
        billId: b.id,
        expectedRevision: 1,
        payableAccountId: payable.account.id,
        approvedAt: DateTime.utc(2026, 9, 28, 1),
      );
    }
    final before = tables(w);
    final r = report(w, DateTime.utc(2026, 12, 31), limit: 1);
    expect(r.outstandingMinor, BigInt.parse('12000000000000000000'));
    expect(r.controls.single.ledgerMinor, r.outstandingMinor);
    expect(r.controls.single.differenceMinor, BigInt.zero);
    expect(tables(w), before);
    final sql = sqlite3.open(path);
    addTearDown(sql.dispose);
    final offPage = sql
        .select('SELECT journal_id FROM bill_postings ORDER BY bill_id DESC')
        .first['journal_id'];
    sql.execute(
      "UPDATE journal_lines SET amount_minor=amount_minor-1 WHERE journal_id=? AND kind='credit'",
      [offPage],
    );
    expect(
      () => report(w, DateTime.utc(2026, 12, 31), limit: 1),
      throwsFormatException,
    );
    sql.execute(
      "UPDATE journal_lines SET amount_minor=amount_minor+1 WHERE journal_id=? AND kind='credit'",
      [offPage],
    );
    expect(
      () => sql.execute('DELETE FROM bill_postings WHERE journal_id=?', [
        offPage,
      ]),
      throwsA(isA<SqliteException>()),
    );
    // Damage only this disposable fixture; normal storage forbids deletion.
    sql.execute('DROP TRIGGER bill_postings_no_delete');
    sql.execute('DELETE FROM bill_postings WHERE journal_id=?', [offPage]);
    expect(
      () => report(w, DateTime.utc(2026, 12, 31), limit: 1),
      throwsFormatException,
    );
  });

  test(
    'orphan/deleted payment journals are not silently counted as settlements',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-payables-payment-links-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/book.sqlite';
      final (w, ids, _, _) = await settlementFixture(path);
      addTearDown(w.dispose);
      final payment = w.settleRecognizedBills(
        requestId: EntityId.random(),
        allocations: [allocation(ids.first, 15120, 120)],
        paymentAccountId: 'fictional-bank',
        paymentReference: 'Fictional link check',
        paidOn: DateTime.utc(2026, 9, 15),
        approvedAt: DateTime.utc(2026, 9, 29),
      );
      final sql = sqlite3.open(path);
      addTearDown(sql.dispose);
      sql.execute('UPDATE journal_entries SET deleted_at=? WHERE id=?', [
        DateTime.utc(2026, 9, 30).toIso8601String(),
        payment.journalId.value,
      ]);
      expect(
        () => report(w, DateTime.utc(2026, 12, 31)),
        throwsFormatException,
      );
    },
  );
}
