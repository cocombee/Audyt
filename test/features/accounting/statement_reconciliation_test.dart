import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/bank_statement_match.dart';
import 'package:audyt/features/accounting/domain/statement_reconciliation.dart';

void main() {
  final journal = EntityId.random();
  StatementRowSuggestions row(
    int number,
    int amount, {
    int day = 2,
    int line = 0,
  }) => StatementRowSuggestions(
    row: BankStatementRow(
      sourceRow: number,
      date: DateTime.utc(2026, 9, day),
      description: 'Movement',
      amount: Money.fromMinor(amount, 'MYR'),
      reference: '',
    ),
    candidates: [
      StatementMatchCandidate(
        journalId: journal,
        lineIndex: line,
        date: DateTime.utc(2026, 9, day),
        memo: 'Movement',
        daysApart: 0,
      ),
    ],
  );
  StatementReconciliationReview review(
    List<StatementRowSuggestions> rows,
    Map<int, String> matches, {
    int opening = 10000,
    int closing = 9000,
  }) => StatementReconciliationReview.evaluate(
    startsOn: DateTime.utc(2026, 9, 1),
    endsOn: DateTime.utc(2026, 9, 30),
    openingBalance: Money.fromMinor(opening, 'MYR'),
    closingBalance: Money.fromMinor(closing, 'MYR'),
    rows: rows,
    acceptedMatches: matches,
  );

  test('exact statement movement and verified coverage agree', () {
    final result = review([row(2, -1000)], {2: '$journal:0'});
    expect(result.rowsAndBalancesAgree, isTrue);
    expect(result.statementMovement.minorUnits, -1000);
    expect(result.matchedMovement.minorUnits, -1000);
    expect(() => result.unmatchedRows.add(3), throwsUnsupportedError);
  });
  test('offsetting unmatched rows cannot disappear behind zero difference', () {
    final result = review(
      [row(2, -1000), row(3, 1000, line: 1)],
      {},
      closing: 10000,
    );
    expect(result.statementDifference.isZero, isTrue);
    expect(result.matchDifference.isZero, isTrue);
    expect(result.unmatchedRows, [2, 3]);
    expect(result.rowsAndBalancesAgree, isFalse);
  });
  test('duplicate, stale and nonexistent row matches block agreement', () {
    final duplicate = review(
      [row(2, -1000), row(3, -1000)],
      {2: '$journal:0', 3: '$journal:0'},
      closing: 8000,
    );
    expect(duplicate.invalidMatchRows, [3]);
    expect(duplicate.rowsAndBalancesAgree, isFalse);
    final stale = review([row(2, -1000)], {2: '$journal:99', 77: '$journal:0'});
    expect(stale.invalidMatchRows, [2, 77]);
    expect(stale.rowsAndBalancesAgree, isFalse);
  });
  test(
    'out-of-period evidence and mismatched closing balance stay visible',
    () {
      final result = review(
        [row(2, -1000, day: 31)],
        {2: '$journal:0'},
        closing: 9001,
      );
      expect(result.outsidePeriodRows, [2]);
      expect(result.statementDifference.minorUnits, 1);
      expect(result.matchDifference.minorUnits, 1);
      expect(result.rowsAndBalancesAgree, isFalse);
    },
  );
  test('duplicate evidence and out-of-range exact totals reject', () {
    expect(
      () => review([row(2, -1000), row(2, -1000)], {}),
      throwsArgumentError,
    );
    expect(
      () => review([row(2, 9223372036854775807), row(3, 1)], {}),
      throwsRangeError,
    );
  });
}
