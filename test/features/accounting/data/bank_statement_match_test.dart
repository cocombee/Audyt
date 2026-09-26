import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/bank_statement_match.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';

import 'bank_statement_import_test.dart' show parse;
import 'ledger_report_test.dart' show id, metadata;

void main() {
  test('match suggestions preserve ambiguity and exclude drafts, wrong signs and dates', () {
    final statement = parse(
      'Date,Description,Amount\n2026-09-10,Shop,-10.00\n2026-09-10,Shop,-10.00',
    );
    final account = Account.create(
      id: id(1),
      code: '1000',
      name: 'Bank',
      type: AccountType.asset,
    );
    StoredJournalEntry entry(
      int n,
      int day, {
      bool debit = false,
      bool posted = true,
    }) {
      final amount = Money.fromMinor(1000, 'MYR');
      final journal = JournalEntry.draft(
        id: id(n),
        date: DateTime.utc(2026, 9, day),
        memo: 'Movement $n',
        lines: [
          if (debit)
            JournalLine.debit(accountId: account.id, amount: amount)
          else
            JournalLine.credit(accountId: account.id, amount: amount),
          if (debit)
            JournalLine.credit(accountId: id(2), amount: amount)
          else
            JournalLine.debit(accountId: id(2), amount: amount),
        ],
      );
      return StoredJournalEntry(
        entry: posted ? journal.post() : journal,
        metadata: metadata(n, DateTime.utc(2026, 9, day)),
      );
    }

    final entries = [
      entry(15, -30),
      entry(10, 10),
      entry(11, 12),
      entry(12, 14),
      entry(13, 10, debit: true),
      entry(14, 10, posted: false),
    ];
    final suggestions = suggestStatementMatches(
      businessId: id(90),
      ledgerAccount: account,
      statement: statement,
      journals: entries,
    );
    expect(suggestions, hasLength(2));
    final expanded = suggestStatementMatches(
      businessId: id(90),
      ledgerAccount: account,
      statement: statement,
      journals: entries,
      includeOlderMovements: true,
    );
    expect(expanded.first.candidates.map((c) => c.journalId), [
      id(10),
      id(11),
      id(15),
    ]);
    expect(expanded.first.candidates.last.daysApart, 40);
    for (final row in suggestions) {
      expect(row.candidates.map((c) => c.journalId), [id(10), id(11)]);
      expect(row.candidates.map((c) => c.daysApart), [0, 2]);
    }
    expect(
      suggestions.first.candidates.first.movementId,
      suggestions.last.candidates.first.movementId,
    );
    final card = Account.create(
      id: account.id,
      code: '2000',
      name: 'Card',
      type: AccountType.liability,
    );
    final cardSuggestions = suggestStatementMatches(
      businessId: id(90),
      ledgerAccount: card,
      statement: parse('Date,Description,Amount\n2026-09-10,Charge,10.00'),
      journals: entries,
    );
    expect(cardSuggestions.single.candidates.map((c) => c.journalId), [
      id(10),
      id(11),
    ]);
    expect(
      () => suggestStatementMatches(
        businessId: id(89),
        ledgerAccount: account,
        statement: statement,
        journals: entries,
      ),
      throwsStateError,
    );
    expect(
      () => suggestStatementMatches(
        businessId: id(90),
        ledgerAccount: account,
        statement: statement,
        journals: [entries.first, entries.first],
      ),
      throwsStateError,
    );
  });
}
