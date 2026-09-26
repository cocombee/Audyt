import 'package:audyt/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fixed_popout_host.dart';

void main() {
  testWidgets('saves an expense and returns to Accounting Home', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    installFixedPopoutHost(tester);

    await tester.pumpWidget(const AudytApp(paymentAccounts: <String>['Cash']));
    await tester.tap(find.byKey(const ValueKey('home-record-expense-action')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '25.50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'Local stationery shop',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-payment-account'),
      'Cash',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-category'),
      'Office Operations',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-title-home')), findsOneWidget);
    expect(find.text('Expense saved'), findsOneWidget);
    expect(find.text('Local stationery shop'), findsOneWidget);
    expect(find.text('RM 25.50'), findsWidgets);
  });
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  Key fieldKey,
  String option,
) async {
  await tester.ensureVisible(find.byKey(fieldKey));
  await tester.tap(find.byKey(fieldKey));
  await tester.pumpAndSettle();
  if (find.textContaining(option).evaluate().isEmpty &&
      find.byKey(fieldKey).evaluate().isNotEmpty) {
    tester.widget<OutlinedButton>(find.byKey(fieldKey)).onPressed?.call();
    await tester.pumpAndSettle();
  }
  final optionFinder = find.textContaining(option).last;
  await tester.ensureVisible(optionFinder);
  await tester.tap(optionFinder);
  await tester.pumpAndSettle();
}
