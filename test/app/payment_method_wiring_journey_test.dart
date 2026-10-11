import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_payment_method.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/expense_tax_persistence_test.dart'
    show configureExpenseTaxes, taxedExpense;
import '../support/accounting_text_input.dart' show enterAccountingText;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import 'claim_receipts_proposal_test.dart' show capture, prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'load' || call.method == 'loadFolder') return null;
          throw StateError('Unexpected Settings mutation: ${call.method}');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );

  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'Settings and ordinary Expense use saved payment methods at $width',
      (tester) async {
        await prepare(tester, width);
        final root = Directory.systemTemp.createTempSync(
          'payment-method-wiring-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = await AccountingWorkspace.open(
          '${root.path}/books.sqlite',
        );
        addTearDown(workspace.dispose);
        final taxes = await configureExpenseTaxes(workspace);

        Widget app({required String initialPath}) => RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(
            workspace: workspace,
            initialPath: initialPath,
            showInitialSetup: false,
          ),
        );

        Finder key(String value) => find.byKey(ValueKey(value)).last;
        Future<void> choose(Finder selector, String label) async {
          await tap(tester, selector);
          await tap(tester, find.textContaining(label).last);
        }

        Finder lineFields(String suffix, Type type) => find.byWidgetPredicate(
          (widget) =>
              (type == AccountingSelector
                  ? widget is AccountingSelector<String>
                  : widget is TextFormField) &&
              ((widget is AccountingSelector<String>
                              ? widget.triggerKey
                              : widget.key)
                          as ValueKey?)
                      ?.value
                      .toString()
                      .endsWith('-$suffix') ==
                  true,
        );

        Future<void> saveMethodForm() async {
          await tap(tester, key('design-review'));
          await tap(tester, key('design-review'));
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(app(initialPath: '/accounting'));
        await tester.pumpAndSettle();
        await tap(tester, key('accounting-settings'));
        await tap(tester, key('settings-editor-Payment Methods'));
        await tap(tester, key('settings-manage-payment-methods'));
        await tap(tester, key('payment-method-new'));
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Fictional Office Card',
        );
        final directoryCard = key(
          'design-field-This Is A Credit Or Debit Card',
        );
        await tap(tester, directoryCard);
        expect(tester.widget<Checkbox>(directoryCard).value, isTrue);
        await saveMethodForm();
        expect(workspace.paymentMethods, hasLength(1));
        var method = workspace.paymentMethods.single;
        expect(method.name, 'Fictional Office Card');
        expect(method.cardPayment, isTrue);
        expect(method.revision, 1);

        await tap(tester, key('payment-method-edit-${method.id.value}'));
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Fictional Office Card Revised',
        );
        final editCard = key('design-field-This Is A Credit Or Debit Card');
        await tap(tester, editCard);
        await saveMethodForm();
        method = workspace.paymentMethods.single;
        expect(method.name, 'Fictional Office Card Revised');
        expect(method.cardPayment, isFalse);
        expect(method.revision, 2);

        await tap(tester, key('payment-method-activation-${method.id.value}'));
        await tap(tester, key('payment-method-deactivate-confirm'));
        method = workspace.paymentMethods.single;
        expect(method.active, isFalse);
        expect(method.revision, 3);
        await tap(tester, key('payment-method-include-inactive'));
        expect(find.text('Fictional Office Card Revised'), findsWidgets);
        await captureUi(
          tester,
          'Payment Method Managed Directory ${width.toInt()}',
        );
        await tap(tester, key('payment-method-activation-${method.id.value}'));
        await tap(tester, key('payment-method-activate-confirm'));
        method = workspace.paymentMethods.single;
        expect(method.active, isTrue);
        expect(method.revision, 4);
        expect(
          workspace
              .paymentMethodHistory(method.id)
              .map((snapshot) => snapshot.revision),
          [1, 2, 3, 4],
        );

        await tap(tester, key('payment-method-new'));
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Fictional Office Card Revised',
        );
        await saveMethodForm();
        expect(
          find.textContaining('This payment method name already exists.'),
          findsOneWidget,
        );
        expect(workspace.paymentMethods, hasLength(1));
        if (width == 720) {
          await capture(tester, 'Payment Method Duplicate Name Error 720');
        }
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, key('design-discard-changes'));
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, accountingCloseIcon().last);

        // Re-enter through the installed Expenses page and its ordinary
        // Record Expense action, then use the existing inline method creator.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(initialPath: '/expenses-vendors'));
        await tester.pumpAndSettle();
        await tap(tester, key('intake-record-expense'));
        await tester.pumpAndSettle();
        final paymentMethodSelector = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.controlKey ==
                  const ValueKey('expense-field-payment-method'),
        );
        expect(paymentMethodSelector, findsOneWidget);
        final activeMethods = tester
            .widget<AccountingSelector<String>>(paymentMethodSelector)
            .options;
        expect(
          activeMethods.any(
            (option) => option.value == method.choice && option.enabled,
          ),
          isTrue,
        );
        await tap(tester, paymentMethodSelector);
        await tap(tester, key('expense-payment-method-${method.id.value}'));
        expect(
          tester
              .widget<AccountingSelector<String>>(paymentMethodSelector)
              .value,
          method.choice,
        );
        await tap(tester, paymentMethodSelector);
        await tap(tester, key('expense-add-payment-method'));
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Fictional Expense Card',
        );
        final inlineCard = key('design-field-This Is A Credit Card');
        await tap(tester, inlineCard);
        expect(tester.widget<Checkbox>(inlineCard).value, isTrue);
        await saveMethodForm();
        final expenseMethod = workspace.paymentMethods.singleWhere(
          (candidate) => candidate.name == 'Fictional Expense Card',
        );
        expect(expenseMethod.cardPayment, isTrue);
        expect(
          tester
              .widget<AccountingSelector<String>>(paymentMethodSelector)
              .value,
          expenseMethod.choice,
        );
        await captureUi(
          tester,
          'Payment Method Expense Selector ${width.toInt()}',
        );

        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('expense-field-payee')),
          'Fictional Receipt Vendor',
        );
        await choose(
          find.byKey(const ValueKey('expense-field-payment-account')),
          'Cash',
        );
        await choose(
          find.byKey(const ValueKey('expense-tax-treatment')),
          'Tax Exclusive',
        );
        await choose(
          lineFields('category', AccountingSelector).first,
          'Office Operations',
        );
        await choose(
          lineFields('tax', AccountingSelector).first,
          taxes.last.label,
        );
        await enterAccountingText(
          tester,
          lineFields('amount', TextFormField).first,
          '12.34',
        );
        await tap(tester, key('record-expense-save'));
        final expenses = await workspace.expenses();
        expect(expenses, hasLength(1));
        final expenseId = expenses.single.id;
        final savedExpense = (await workspace.expense(expenseId))!;
        expect(
          savedExpense.draft.paymentMethod!.toJson(),
          expenseMethod.toJson(),
        );

        await tap(tester, key('open-expense-${expenseId.value}'));
        expect(paymentMethodSelector, findsOneWidget);
        expect(
          tester
              .widget<AccountingSelector<String>>(paymentMethodSelector)
              .value,
          expenseMethod.choice,
        );
        await captureUi(
          tester,
          'Payment Method Expense Saved ${width.toInt()}',
        );
        await tap(tester, key('record-expense-cancel'));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Deactivation affects new selections. The saved Expense keeps its
        // exact prior method snapshot and does not silently relink.
        await tap(tester, key('accounting-settings'));
        await tap(tester, key('settings-editor-Payment Methods'));
        await tap(tester, key('settings-manage-payment-methods'));
        await tap(
          tester,
          key('payment-method-activation-${expenseMethod.id.value}'),
        );
        await tap(tester, key('payment-method-deactivate-confirm'));
        expect(
          workspace.paymentMethods
              .singleWhere((candidate) => candidate.id == expenseMethod.id)
              .active,
          isFalse,
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, accountingCloseIcon().last);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(initialPath: '/expenses-vendors'));
        await tester.pumpAndSettle();
        await tap(tester, key('open-expense-${expenseId.value}'));
        final reopenedSelector = tester.widget<AccountingSelector<String>>(
          paymentMethodSelector,
        );
        expect(reopenedSelector.value, expenseMethod.choice);
        final historyOption = reopenedSelector.options.singleWhere(
          (option) => option.value == expenseMethod.choice,
        );
        expect(historyOption.label, 'Fictional Expense Card');
        expect(historyOption.enabled, isFalse);
        expect(
          reopenedSelector.options.any(
            (option) => option.value == method.choice && option.enabled,
          ),
          isTrue,
        );
        await captureUi(
          tester,
          'Payment Method Historical Expense ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'actual recurring suggestion retains its payment method and requires a current selection',
    (tester) async {
      await prepare(tester, 1162);
      final root = Directory.systemTemp.createTempSync(
        'payment-method-recurring-journey-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${root.path}/books.sqlite',
      );
      addTearDown(workspace.dispose);
      final taxes = await configureExpenseTaxes(workspace);
      final originalMethod = workspace.savePaymentMethod(
        CompanyPaymentMethod(
          id: EntityId.random(),
          name: 'Fictional Recurring Card',
          cardPayment: true,
        ),
      );
      final recurrence = RecurrenceRule(
        startsOn: DateTime.utc(2026, 9, 1),
        unit: RecurrenceUnit.months,
        occurrenceCount: 2,
      );
      final source = RecordExpenseDraft.fromJson({
        ...taxedExpense(taxes, 'Exclusive').toJson(),
        'date': '31-08-2026',
        'paymentMethod': originalMethod.toJson(),
        'recurrence': recurrence.toJson(),
      });
      await workspace.saveExpenseIntake(source);
      final prepared = await workspace.database.prepareDueRecurringExpenses(
        workspace.identity.businessId,
        through: DateTime.utc(2026, 10, 11),
      );
      expect(prepared.prepared, 2);
      final suggestion = workspace.database
          .recurringExpenseSuggestions(workspace.identity.businessId)
          .first;
      expect(
        suggestion.suggestion.paymentMethod?.toJson(),
        originalMethod.toJson(),
      );
      expect(suggestion.savedExpenseId, isNull);

      Widget app() => RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: AudytApp(
          workspace: workspace,
          initialPath: '/expenses-vendors',
          showInitialSetup: false,
        ),
      );
      Finder key(String value) => find.byKey(ValueKey(value)).last;
      final methodSelector = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            widget.controlKey == const ValueKey('expense-field-payment-method'),
      );

      Future<void> reviewSuggestion(String identity) async {
        await tap(tester, key('expense-open-recurring'));
        await tap(tester, key('recurring-saved-suggestions'));
        await tap(tester, key('review-recurring-$identity'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await reviewSuggestion(suggestion.identity);
      var selector = tester.widget<AccountingSelector<String>>(methodSelector);
      expect(selector.value, originalMethod.choice);
      expect(
        selector.options
            .singleWhere((option) => option.value == originalMethod.choice)
            .enabled,
        isTrue,
      );
      await tap(tester, key('record-expense-cancel'));
      await tester.pumpAndSettle();
      await tap(tester, accountingCloseIcon().last);
      await tester.pumpAndSettle();

      workspace.savePaymentMethod(
        CompanyPaymentMethod(
          id: originalMethod.id,
          name: originalMethod.name,
          cardPayment: originalMethod.cardPayment,
          active: false,
          revision: originalMethod.revision,
        ),
      );
      final replacement = workspace.savePaymentMethod(
        CompanyPaymentMethod(
          id: EntityId.random(),
          name: 'Fictional Current Card',
          cardPayment: true,
        ),
      );
      await reviewSuggestion(suggestion.identity);
      selector = tester.widget<AccountingSelector<String>>(methodSelector);
      expect(selector.value, originalMethod.choice);
      final historical = selector.options.singleWhere(
        (option) => option.value == originalMethod.choice,
      );
      expect(historical.label, originalMethod.name);
      expect(historical.enabled, isFalse);
      expect(
        selector.options
            .singleWhere((option) => option.value == replacement.choice)
            .enabled,
        isTrue,
      );

      await tap(tester, key('record-expense-save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Select a current payment method before saving this recurring expense.',
        ),
        findsOneWidget,
      );
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .firstWhere((row) => row.identity == suggestion.identity)
            .savedExpenseId,
        isNull,
      );
      await tap(tester, methodSelector);
      await tap(tester, key('expense-payment-method-${replacement.id.value}'));
      expect(
        tester.widget<AccountingSelector<String>>(methodSelector).value,
        replacement.choice,
      );
      await tap(tester, key('record-expense-save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Select a current payment method before saving this recurring expense.',
        ),
        findsNothing,
      );
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .firstWhere((row) => row.identity == suggestion.identity)
            .savedExpenseId,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
