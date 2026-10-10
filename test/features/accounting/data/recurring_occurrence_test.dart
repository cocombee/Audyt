import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter/material.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';

import 'expense_intake_test.dart' show draft;

import '../../../app/journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  testWidgets(
    'recurring suggestion excludes source date and retries across restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      final dir = Directory.systemTemp.createTempSync('recurring-occurrence-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'recurring-cash',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      await workspace.saveExpenseIntake(
        draft(
          recurrence: RecurrenceRule(
            startsOn: DateTime.utc(2026, 9, 13),
            unit: RecurrenceUnit.months,
          ),
        ),
      );
      final template = workspace.database
          .recurringExpenseTemplates(workspace.identity.businessId)
          .single;
      expect(
        () => workspace.database.prepareRecurringExpenseOccurrence(
          workspace.identity.businessId,
          template.id,
          expectedRevision: 1,
          index: 0,
        ),
        throwsStateError,
      );
      final proposal = workspace.database.prepareRecurringExpenseOccurrence(
        workspace.identity.businessId,
        template.id,
        expectedRevision: 1,
        index: 1,
      );
      expect(proposal.date, '13-10-2026');
      expect(proposal.submissionId, isNull);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(
            workspace: workspace,
            initialPath: '/expenses-vendors',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final expense = (await workspace.expenses()).single;
      final openExpense = find.byKey(
        ValueKey('open-expense-${expense.id.value}'),
      );
      await tester.ensureVisible(openExpense);
      await tester.tap(openExpense);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('expense-manage-recurrences')),
        findsNothing,
      );
      expect(find.text('Manage Saved Schedules'), findsNothing);
      expect(
        find.byKey(const ValueKey('expense-recurring-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-recurrence-period')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-recurrence-options')),
        findsOneWidget,
      );
      final headerFields = find.ancestor(
        of: find.byKey(const ValueKey('expense-recurring-control')),
        matching: find.byType(AccountingOrdinaryFields),
      );
      final recurrenceFields = find.ancestor(
        of: find.byKey(const ValueKey('expense-recurrence-period')),
        matching: find.byType(AccountingOrdinaryFields),
      );
      expect(headerFields, findsOneWidget);
      expect(recurrenceFields, findsOneWidget);
      expect(
        tester.getRect(recurrenceFields).top -
            tester.getRect(headerFields).bottom,
        closeTo(accountingContentInset, 0.5),
      );
      final repeat = tester.getRect(
        find.byKey(const ValueKey('expense-recurrence-period')),
      );
      final repeatLabel = tester.getRect(
        find.byKey(const ValueKey('expense-recurrence-label')),
      );
      final options = tester.getRect(
        find.byKey(const ValueKey('expense-recurrence-options')),
      );
      final summary = tester.getRect(
        find.byKey(const ValueKey('expense-recurrence-information')),
      );
      final itemsLabel = tester.getRect(
        find.byKey(const ValueKey('expense-items-label')),
      );
      final itemsDivider = tester.getRect(
        find.byKey(const ValueKey('expense-items-divider')),
      );
      expect(
        repeat.top - repeatLabel.bottom,
        closeTo(accountingFieldLabelGap, 0.5),
      );
      expect(options.top, closeTo(repeat.top, 0.5));
      expect(options.left, greaterThan(repeat.right));
      expect(
        summary.top - tester.getRect(recurrenceFields).bottom,
        closeTo(accountingFieldLabelGap, 0.5),
      );
      expect(
        itemsDivider.top - itemsLabel.bottom,
        closeTo(accountingFieldLabelGap, 0.5),
      );
      await Scrollable.ensureVisible(
        tester.element(
          find.byKey(const ValueKey('expense-recurrence-options')),
        ),
        alignment: 0.45,
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Expense Saved Form Without Duplicate Shortcut');
      final liveFields = tester.widget<AccountingOrdinaryFields>(
        recurrenceFields,
      );
      const narrowRunKey = ValueKey('expense-recurrence-narrow-run');
      final narrowOverlay = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: ColoredBox(
            color: Colors.white,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 64),
                child: SizedBox(
                  key: narrowRunKey,
                  width: 300,
                  child: AccountingOrdinaryFields(
                    fields: liveFields.fields,
                    crossAxisAlignment: liveFields.crossAxisAlignment,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(tester.element(recurrenceFields)).insert(narrowOverlay);
      await tester.binding.setSurfaceSize(const Size(440, 400));
      await tester.pumpAndSettle();
      final narrowRun = find.byKey(narrowRunKey);
      final narrowRepeat = tester.getRect(
        find.descendant(
          of: narrowRun,
          matching: find.byKey(const ValueKey('expense-recurrence-period')),
        ),
      );
      final narrowOptions = tester.getRect(
        find.descendant(
          of: narrowRun,
          matching: find.byKey(const ValueKey('expense-recurrence-options')),
        ),
      );
      expect(narrowOptions.top, greaterThan(narrowRepeat.bottom));
      await captureUi(tester, 'Expense Repeat Options Narrow Stack');
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      narrowOverlay.remove();
      narrowOverlay.dispose();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-expense-cancel')));
      await tester.pumpAndSettle();
      final manage = find.byKey(const ValueKey('expense-open-recurring'));
      expect(manage, findsOneWidget);
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('prepare-recurring-${template.id}-0')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('prepare-recurring-${template.id}-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recurring Suggestion'), findsOneWidget);
      expect(find.text('13-10-2026'), findsOneWidget);
      Navigator.of(tester.element(find.text('Recurring Suggestion'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('recurring-later-${template.id}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('prepare-recurring-${template.id}-6')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('prepare-recurring-${template.id}-1')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('recurring-earlier-${template.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('prepare-recurring-${template.id}-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(ValueKey('recurring-toggle-${template.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.byKey(ValueKey('prepare-recurring-${template.id}-1')),
        findsNothing,
      );
      expect(
        workspace.database
            .recurringExpenseTemplates(workspace.identity.businessId)
            .single
            .paused,
        isTrue,
      );
      await tester.tap(find.byKey(ValueKey('recurring-toggle-${template.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);
      expect(
        workspace.database
            .recurringExpenseTemplateHistory(
              workspace.identity.businessId,
              template.id,
            )
            .length,
        3,
      );
      await tester.tap(find.byKey(ValueKey('recurring-edit-${template.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('After Occurrences').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recurrence-count')),
        '5',
      );
      await tester.tap(find.byKey(const ValueKey('recurrence-apply')));
      await tester.pumpAndSettle();
      expect(
        workspace.database
            .recurringExpenseTemplates(workspace.identity.businessId)
            .single
            .schedule
            .occurrenceCount,
        5,
      );
      expect(
        workspace.database
            .recurringExpenseTemplateHistory(
              workspace.identity.businessId,
              template.id,
            )
            .length,
        4,
      );
      await tester.tap(
        find.byKey(const ValueKey('recurring-saved-suggestions')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Recurring Suggestions'), findsOneWidget);
      expect(find.textContaining('Schedule revision 1'), findsOneWidget);
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .single
            .suggestion
            .toJson(),
        proposal.toJson(),
      );
      await captureUi(tester, 'Expense Recurrence Saved Suggestion 1224');
      await tester.tap(find.byTooltip('Review Expense'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-amount')),
            )
            .controller!
            .text,
        '25.50',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-date')),
            )
            .controller!
            .text,
        '13-10-2026',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-payee')),
            )
            .controller!
            .text,
        'Stationery Shop',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash · Cash · RM').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Review the tax code on each recurring expense row.'),
        findsOneWidget,
      );
      expect(await workspace.expenses(), hasLength(1));
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-field-tax')),
      );
      await tester.tap(find.byKey(const ValueKey('expense-field-tax')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No Tax').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pumpAndSettle();
      expect(await workspace.expenses(), hasLength(2));
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .single
            .savedExpenseId,
        isNotNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('recurring-saved-suggestions')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expense Saved'), findsOneWidget);
      await captureUi(tester, 'Expense Recurrence Recorded Suggestion 1224');
      expect(find.byTooltip('Review Expense'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .single
            .savedExpenseId,
        isNotNull,
      );
      expect(
        workspace.database
            .prepareRecurringExpenseOccurrence(
              workspace.identity.businessId,
              template.id,
              expectedRevision: 4,
              index: 1,
            )
            .toJson(),
        proposal.toJson(),
      );
      expect(
        () => workspace.database.prepareRecurringExpenseOccurrence(
          workspace.identity.businessId,
          template.id,
          expectedRevision: 2,
          index: 2,
        ),
        throwsStateError,
      );
    },
  );
}
