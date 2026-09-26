import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'record expense has no duplicate currency selector and uses account currency',
    (tester) async {
      final account = PaymentAccount.create(
        id: 'usd-account',
        name: 'USD Account',
        type: PaymentAccountType.bank,
        currencyCode: 'USD',
      );
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(accounts: <PaymentAccount>[account]),
        ),
      );

      expect(
        find.byKey(const ValueKey('expense-currency-selector')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('USD Account').last);
      await tester.pumpAndSettle();
      expect(find.text(r'$'), findsOneWidget);
    },
  );
}
