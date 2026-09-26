import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/account_reconciliation.dart';
import 'package:audyt/features/accounting/domain/statement_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OpeningLedgerMovement movement(
    String id,
    int minor, {
    String currency = 'MYR',
  }) => OpeningLedgerMovement(
    id: id,
    date: DateTime.utc(2026, 9, 2),
    memo: 'Fictional transaction',
    amount: Money.fromMinor(minor, currency),
  );
  AccountReconciliationReview review(
    List<OpeningLedgerMovement> rows,
    Set<String> selected, {
    int opening = 10000,
    int closing = 9000,
  }) => AccountReconciliationReview.evaluate(
    openingBalance: Money.fromMinor(opening, 'MYR'),
    closingBalance: Money.fromMinor(closing, 'MYR'),
    eligibleMovements: rows,
    selectedIds: selected,
  );

  test(
    'only selected transactions clear; unchecked entries remain outstanding',
    () {
      final result = review([movement('a', -1000), movement('b', 500)], {'a'});
      expect(result.balancesAndSelectionAgree, isTrue);
      expect(result.clearedBalance, Money.fromMinor(9000, 'MYR'));
      expect(result.selected.single.id, 'a');
      expect(result.outstanding.single.id, 'b');
      expect(() => result.selected.clear(), throwsUnsupportedError);
      expect(() => result.outstanding.clear(), throwsUnsupportedError);
    },
  );
  test('zero difference cannot hide stale or foreign selection', () {
    final selected = {'a', 'missing'};
    final result = review([movement('a', -1000)], selected);
    selected.clear();
    expect(result.closingDifference.isZero, isTrue);
    expect(result.unresolved, {'missing'});
    expect(result.balancesAndSelectionAgree, isFalse);
    expect(() => result.unresolved.clear(), throwsUnsupportedError);
  });
  test('empty period can agree without fabricating statement rows', () {
    expect(review([], {}, closing: 10000).balancesAndSelectionAgree, isTrue);
    expect(review([], {}).balancesAndSelectionAgree, isFalse);
  });
  test('duplicate identities and mixed currencies are rejected', () {
    expect(
      () => review([movement('a', -500), movement('a', -500)], {'a'}),
      throwsArgumentError,
    );
    expect(
      () => review([movement('a', -1000, currency: 'USD')], {'a'}),
      throwsArgumentError,
    );
    expect(
      () => AccountReconciliationReview.evaluate(
        openingBalance: Money.zero('MYR'),
        closingBalance: Money.zero('USD'),
        eligibleMovements: [],
        selectedIds: {},
      ),
      throwsArgumentError,
    );
  });
  test('offsetting large exact movements never wrap intermediate sums', () {
    const max = 9223372036854775807;
    final result = review(
      [
        movement('a', max),
        movement('b', max),
        movement('c', -max),
        movement('d', -max),
      ],
      {'a', 'b', 'c', 'd'},
      opening: 0,
      closing: 0,
    );
    expect(result.balancesAndSelectionAgree, isTrue);
    expect(result.clearedMovement.isZero, isTrue);
  });
  test('unrepresentable cleared totals or differences reject review', () {
    const max = 9223372036854775807;
    expect(
      () => review([movement('a', max)], {'a'}, opening: 1, closing: 0),
      throwsRangeError,
    );
    expect(() => review([], {}, opening: -max, closing: max), throwsRangeError);
  });
}
