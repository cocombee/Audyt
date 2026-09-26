import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed account persistence does not select an unsaved account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordExpensePage(
            onPaymentAccountSave: (_) =>
                throw StateError('Storage unavailable'),
          ),
        ),
      ),
    );
    await _openAddAccount(tester);
    await _chooseSelector(
      tester,
      const ValueKey('payment-account-bank'),
      const ValueKey('payment-account-bank-option-maybank'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-account-name')),
      'Unsaved Account',
    );
    await tester.tap(find.byKey(const ValueKey('payment-account-create')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Payment account could not be saved. Check storage and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Unsaved Account'), findsNothing);
    expect(find.text('No payment accounts yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'keeps account configuration out of Record Expense and starts Add Account with bank selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(find.byKey(const ValueKey('payment-account-bank')), findsNothing);
      expect(
        find.byKey(const ValueKey('payment-account-number')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('payment-account-name')), findsNothing);

      await _openAddAccount(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Add Account'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-bank')),
        findsOneWidget,
      );
      expect(find.text('Choose a Malaysian bank to continue.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment-account-number')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('payment-account-name')), findsNothing);
      expect(
        find.byKey(const ValueKey('payment-account-currency')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment-account-create')),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsNothing);
      expect(find.bySemanticsLabel('Close'), findsWidgets);
    },
  );

  testWidgets(
    'reveals bank account fields and filters currencies when the bank changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));
      await _openAddAccount(tester);

      await _chooseSelector(
        tester,
        const ValueKey('payment-account-bank'),
        const ValueKey('payment-account-bank-option-maybank'),
      );

      expect(
        find.byKey(const ValueKey('payment-account-number')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-currency')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-type')),
        findsOneWidget,
      );
      expect(
        find.text('Local Malaysian bank catalogue; no live connection.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('payment-account-currency')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-MYR')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-USD')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-SGD')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-EUR')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('payment-account-currency-option-USD')),
      );
      await tester.pumpAndSettle();

      await _chooseSelector(
        tester,
        const ValueKey('payment-account-bank'),
        const ValueKey('payment-account-bank-option-bank-islam'),
      );
      expect(find.text('account currency'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payment-account-currency')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-MYR')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment-account-currency-option-USD')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'normalizes and persists the account name without destroying intentional case',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));
      await _openAddAccount(tester);
      await _chooseSelector(
        tester,
        const ValueKey('payment-account-bank'),
        const ValueKey('payment-account-bank-option-maybank'),
      );

      final nameField = find.byKey(const ValueKey('payment-account-name'));
      await tester.enterText(nameField, 'mYBank');
      expect(tester.widget<TextField>(nameField).controller!.text, 'MYBank');
      await tester.enterText(
        find.byKey(const ValueKey('payment-account-number')),
        '1234567890',
      );
      await tester.tap(find.byKey(const ValueKey('payment-account-create')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('MYBank'), findsWidgets);
      expect(find.textContaining('mYBank'), findsNothing);
    },
  );
}

Future<void> _openAddAccount(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('expense-field-payment-account')),
  );
  await tester.tap(find.byKey(const ValueKey('expense-field-payment-account')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('expense-add-account')));
  await tester.pumpAndSettle();
}

Future<void> _chooseSelector(
  WidgetTester tester,
  Key triggerKey,
  Key optionKey,
) async {
  await tester.tap(find.byKey(triggerKey));
  await tester.pumpAndSettle();
  expect(find.byKey(optionKey), findsOneWidget);
  await tester.tap(find.byKey(optionKey));
  await tester.pumpAndSettle();
}
