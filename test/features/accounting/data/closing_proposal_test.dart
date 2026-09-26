import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/ledger_report.dart';
import 'package:audyt/features/accounting/domain/closing_proposal.dart';

import 'ledger_report_test.dart' show id, metadata;

void main() {
  LedgerReport report(int sale, int cost, {bool draft = false}) {
    final at = DateTime.utc(2026, 9, 30);
    final types = [
      AccountType.asset,
      AccountType.equity,
      AccountType.income,
      AccountType.expense,
    ];
    StoredJournalEntry entry(int n, int debit, int credit, int amount) {
      final value = JournalEntry.draft(
        id: id(n),
        date: at,
        memo: 'Evidence $n',
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
      );
      return StoredJournalEntry(
        entry: draft ? value : value.post(),
        metadata: metadata(n, at),
      );
    }

    return LedgerReport.build(
      businessId: id(90),
      currency: 'MYR',
      from: DateTime.utc(2026, 9),
      through: at,
      accounts: [
        for (var i = 0; i < types.length; i++)
          StoredAccount(
            account: Account.create(
              id: id(i + 1),
              code: '${i + 1}',
              name: 'Account',
              type: types[i],
            ),
            metadata: metadata(i + 1, at),
          ),
      ],
      journals: [
        if (sale > 0) entry(10, 1, 3, sale),
        if (cost > 0) entry(11, 4, 1, cost),
      ],
    );
  }

  test(
    'profit closes nominal balances into selected equity without cash movement',
    () {
      final result = ClosingProposal.fromReport(
        report(10000, 3000),
        equityAccountId: id(2),
      );
      expect(result.lines.map((l) => l.accountId), [id(3), id(4), id(2)]);
      expect(result.lines.map((l) => l.amount.minorUnits), [10000, 3000, 7000]);
      expect(result.lines.map((l) => l.isDebit), [true, false, false]);
      expect(result.sourceJournalIds, [id(10), id(11)]);
    },
  );
  test(
    'loss debits equity and a zero-profit close still clears nominal balances',
    () {
      final loss = ClosingProposal.fromReport(
        report(3000, 10000),
        equityAccountId: id(2),
      );
      expect(loss.lines.last.isDebit, isTrue);
      expect(loss.lines.last.amount.minorUnits, 7000);
      final zero = ClosingProposal.fromReport(
        report(10000, 10000),
        equityAccountId: id(2),
      );
      expect(zero.lines.length, 2);
      expect(
        ClosingProposal.fromReport(
          report(0, 0),
          equityAccountId: id(2),
        ).isEmpty,
        isTrue,
      );
    },
  );
  test(
    'pending review and invalid equity destination cannot produce a close',
    () {
      expect(
        () => ClosingProposal.fromReport(
          report(100, 0, draft: true),
          equityAccountId: id(2),
        ),
        throwsStateError,
      );
      expect(
        () =>
            ClosingProposal.fromReport(report(100, 0), equityAccountId: id(1)),
        throwsStateError,
      );
      expect(
        () =>
            ClosingProposal.fromReport(report(100, 0), equityAccountId: id(99)),
        throwsStateError,
      );
    },
  );
}
