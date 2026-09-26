import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/ledger_report.dart';

EntityId id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
RecordMetadata metadata(int n, DateTime at) => RecordMetadata.initial(
  recordId: id(n),
  businessId: id(90),
  originDeviceId: id(91),
  createdAt: at,
);
void main() {
  test('persisted reports reconcile contributions, loans, sales, expenses and settlement', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-reports-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var db = LocalAccountingDatabase.open(path);
    await db.configureLedger(businessId: id(90), currencyCode: 'MYR');
    final types = [
      AccountType.asset,
      AccountType.liability,
      AccountType.equity,
      AccountType.income,
      AccountType.expense,
    ];
    for (var n = 0; n < types.length; n++) {
      await db.saveAccount(
        StoredAccount(
          account: Account.create(
            id: id(n + 1),
            code: '${n + 1}',
            name: 'Account ${n + 1}',
            type: types[n],
          ),
          metadata: metadata(n + 1, DateTime.utc(2026, 8, 1)),
        ),
      );
    }
    Future<void> add(
      int n,
      DateTime date,
      int debit,
      int credit,
      int amount, {
      bool post = true,
    }) async {
      await db.save(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: id(n),
            date: date,
            memo: 'Transaction $n',
            lines: [
              JournalLine.debit(
                accountId: id(debit),
                amount: Money.fromMinor(amount, 'MYR'),
              ),
              JournalLine.credit(
                accountId: id(credit),
                amount: Money.fromMinor(amount, 'MYR'),
              ),
            ],
          ),
          metadata: metadata(n, DateTime.utc(2026, 9, 13)),
        ),
      );
      if (post) {
        await db.approve(
          JournalApproval(
            requestId: id(n + 100),
            businessId: id(90),
            journalId: id(n),
            expectedRevision: 1,
            actorId: id(91),
            approvedAt: DateTime.utc(2026, 9, 13, 1),
          ),
        );
      }
    }

    await add(10, DateTime.utc(2026, 8, 31), 1, 3, 10000);
    await add(11, DateTime.utc(2026, 9, 2), 1, 2, 5000);
    await add(12, DateTime.utc(2026, 9, 3), 1, 4, 4000);
    await add(13, DateTime.utc(2026, 9, 4), 5, 1, 1500);
    await add(14, DateTime.utc(2026, 9, 5), 5, 2, 1000);
    await add(15, DateTime.utc(2026, 9, 6), 2, 1, 500);
    await add(16, DateTime.utc(2026, 10, 1), 1, 4, 9000);
    await add(17, DateTime.utc(2026, 9, 7), 5, 1, 800, post: false);
    db.close();
    db = LocalAccountingDatabase.open(path);
    addTearDown(db.close);
    final report = await db.report(
      businessId: id(90),
      from: DateTime.utc(2026, 9, 1),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(report.assets, BigInt.from(17000));
    expect(report.liabilities, BigInt.from(5500));
    expect(report.contributedAndRetainedEquity, BigInt.from(10000));
    expect(report.unclosedEarnings, BigInt.from(1500));
    expect(report.revenue, BigInt.from(4000));
    expect(report.expenses, BigInt.from(2500));
    expect(report.periodProfit, BigInt.from(1500));
    expect(report.trialBalanceDebits, BigInt.from(19500));
    expect(report.trialBalanceCredits, report.trialBalanceDebits);
    expect(report.isBalanced, isTrue);
    expect(report.pendingDrafts, 1);
    expect(report.postedJournalIds, hasLength(6));
    expect(report.rows.first.openingNetDebit, BigInt.from(10000));
    final original = (await db.getJournal(id(13)))!;
    final reversal = original.entry.reversal(
      id: id(18),
      date: DateTime.utc(2026, 9, 8),
      memo: 'Correct Duplicate Expense',
    );
    await db.save(
      StoredJournalEntry(
        entry: reversal,
        metadata: metadata(18, DateTime.utc(2026, 9, 13, 2)),
      ),
    );
    await db.approve(
      JournalApproval(
        requestId: id(118),
        businessId: id(90),
        journalId: id(18),
        expectedRevision: 1,
        actorId: id(91),
        approvedAt: DateTime.utc(2026, 9, 13, 3),
      ),
    );
    final corrected = await db.report(
      businessId: id(90),
      from: DateTime.utc(2026, 9, 1),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(corrected.assets, BigInt.from(18500));
    expect(corrected.periodProfit, BigInt.from(3000));
    expect(corrected.balanceSheetDifference, BigInt.zero);
  });
  test('unknown historical posting accounts are not silently dropped', () {
    final entry = JournalEntry.draft(
      id: id(1),
      date: DateTime.utc(2026, 9, 1),
      memo: 'Legacy',
      lines: [
        JournalLine.debit(
          accountId: id(2),
          amount: Money.fromMinor(100, 'MYR'),
        ),
        JournalLine.credit(
          accountId: id(3),
          amount: Money.fromMinor(100, 'MYR'),
        ),
      ],
    ).post();
    expect(
      () => LedgerReport.build(
        businessId: id(90),
        currency: 'MYR',
        from: DateTime.utc(2026, 1, 1),
        through: DateTime.utc(2026, 12, 31),
        accounts: [],
        journals: [
          StoredJournalEntry(
            entry: entry,
            metadata: metadata(1, DateTime.utc(2026, 9, 1)),
          ),
        ],
      ),
      throwsStateError,
    );
  });
  test(
    'saving a local calendar date retains its visible accounting day',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await db.save(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: id(1),
            date: DateTime(2026, 9, 13),
            memo: 'Calendar Date',
            lines: [],
          ),
          metadata: metadata(1, DateTime.utc(2026, 9, 13)),
        ),
      );
      expect(
        (await db.getJournal(id(1)))!.entry.date,
        DateTime.utc(2026, 9, 13),
      );
    },
  );
}
