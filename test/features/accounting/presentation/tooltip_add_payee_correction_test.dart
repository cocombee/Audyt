import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shares one subordinate helper and tooltip typography hierarchy', () {
    final theme = AccountingTheme.light();
    final helperStyle = theme.inputDecorationTheme.helperStyle!;
    final valueStyle = theme.textTheme.bodyMedium!;
    final tooltipStyle = theme.tooltipTheme.textStyle!;
    final tokens = theme.extension<AccountingTokens>()!;

    expect(helperStyle.fontSize, lessThan(valueStyle.fontSize!));
    expect(helperStyle.fontWeight, FontWeight.w400);
    expect(helperStyle.color, tokens.mutedForeground);
    expect(helperStyle.height, lessThanOrEqualTo(1.3));
    expect(tooltipStyle.fontSize, helperStyle.fontSize);
    expect(tooltipStyle.fontWeight, helperStyle.fontWeight);
    expect(tooltipStyle.height, helperStyle.height);
    expect(tooltipStyle.color, Colors.white);
    final tooltipDecoration = theme.tooltipTheme.decoration! as BoxDecoration;
    expect(tooltipDecoration.color, Colors.black.withValues(alpha: 0.8));
  });

  testWidgets('Record Expense keeps ordinary guidance in title help', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    expect(find.text('Optional. Choose a payee.'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Optional. Choose a payee.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Payee keeps its compact creation action inside suggestions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );
    expect(find.byKey(const ValueKey('expense-add-payee')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('expense-add-payee'));
    final button = tester.widget<MenuItemButton>(action);
    expect(button.onPressed, isNotNull);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(of: action, matching: find.text('Add Payee')),
      findsOneWidget,
    );
    final semantics = tester.getSemantics(action).getSemanticsData();
    expect(semantics.label, contains('Add Payee'));
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets(
    'Payee suggestions retain rounded clipping without bottom guidance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const RecordExpensePage(),
        ),
      );

      final payeeField = find.byKey(
        const ValueKey<String>('expense-field-payee'),
      );
      await tester.enterText(payeeField, 'Aina');
      await tester.pumpAndSettle();

      final helper = find.byKey(const ValueKey<String>('expense-payee-helper'));
      final menu = find.byKey(const ValueKey<String>('expense-payee-menu'));
      expect(helper, findsNothing);
      expect(menu, findsOneWidget);
      expect(
        find.descendant(
          of: payeeField,
          matching: find.text('Optional. Choose a payee.'),
        ),
        findsNothing,
      );

      final fieldRect = tester.getRect(payeeField);
      final menuRect = tester.getRect(menu);
      expect(menuRect.left, closeTo(fieldRect.left, 1));
      expect(menuRect.width, closeTo(fieldRect.width, 1));
      expect(menuRect.top, closeTo(fieldRect.bottom + 4, 4));

      final material = tester.widget<Material>(menu);
      expect(material.borderRadius, BorderRadius.circular(10));
      expect(material.clipBehavior, Clip.antiAlias);
      final option = find.byKey(
        const ValueKey<String>('expense-payee-option-demo-payee-aina-rahman'),
      );
      final optionRect = tester.getRect(option);
      expect(menuRect.contains(optionRect.topLeft), isTrue);
      expect(menuRect.contains(optionRect.bottomRight), isTrue);

      final fieldSemantics = tester.getSemantics(payeeField).getSemanticsData();
      expect(fieldSemantics.label, contains('Who was paid?'));
      expect(fieldSemantics.flagsCollection.isTextField, isTrue);
    },
  );

  testWidgets(
    'Payee autocomplete retains mounted typing, selection, Escape, and semantics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const RecordExpensePage(),
        ),
      );

      final payeeField = find.byKey(
        const ValueKey<String>('expense-field-payee'),
      );
      await tester.tap(payeeField);
      await tester.enterText(payeeField, 'Aina');
      await tester.pumpAndSettle();
      final ainaOption = find.byKey(
        const ValueKey<String>('expense-payee-option-demo-payee-aina-rahman'),
      );
      expect(ainaOption, findsOneWidget);
      final openSemantics = tester.getSemantics(payeeField).getSemanticsData();
      expect(openSemantics.flagsCollection.isTextField, isTrue);
      expect(openSemantics.label, contains('Who was paid?'));

      await tester.tap(ainaOption);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: payeeField,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Aina Rahman',
      );
      expect(find.byKey(const ValueKey('expense-payee-menu')), findsNothing);

      await tester.tap(payeeField);
      await tester.enterText(payeeField, 'Daniel');
      await tester.pumpAndSettle();
      expect(find.text('Daniel Lim'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-payee-menu')), findsNothing);
      expect(find.byKey(const ValueKey('expense-payee-helper')), findsNothing);
    },
  );

  testWidgets('compact field actions retain mounted tap behavior', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payee-name-field')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payee-name-field')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('expense-field-payment-account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-account-bank')), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-account-name')), findsNothing);
  });
}
