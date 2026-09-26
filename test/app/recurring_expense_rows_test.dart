import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  setUp(AccountingRecordPageSizes.reset);
  for (final count in [0, 5, 6]) {
    testWidgets('actual recurring expenses use five-row threshold at $count', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1224, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      for (final (i, summary) in (await w.expenses()).take(count).indexed) {
        final draft = (await w.expense(summary.id))!.draft;
        w.database.saveRecurringExpenseTemplate(
          w.identity.businessId,
          RecurringExpenseTemplate(
            id: 'row-example-$i',
            revision: 1,
            sourceExpenseId: summary.id.value,
            defaults: draft,
            schedule: RecurrenceRule(
              startsOn: DateTime(2030),
              unit: RecurrenceUnit.months,
            ),
            paused: true,
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ExpenseIntakePage(workspace: w, onRecordExpense: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-open-recurring')));
      await tester.pumpAndSettle();
      final list = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingRecordList &&
            widget.paginationKey == 'recurring-expenses',
      );
      expect(list, findsOneWidget);
      final footer = find.descendant(
        of: list,
        matching: find.byType(AccountingRecordPagination),
      );
      expect(footer, count > 5 ? findsOneWidget : findsNothing);
      for (var i = 0; i < count.clamp(0, 5); i++) {
        expect(
          find.byKey(ValueKey('recurring-expense-row-row-example-$i')),
          findsOneWidget,
        );
      }
      if (count > 5) {
        final next = find.byKey(const ValueKey('recurring-expenses-page-next'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('recurring-expense-row-row-example-5')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [720.0, 1224.0]) {
    for (final paused in [false, true]) {
      testWidgets(
        'actual expense recurrence record geometry $width paused=$paused',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadJournalLayoutFonts();
          final w = await createDemoWorkspace();
          addTearDown(w.dispose);
          final summary = (await w.expenses()).first;
          final draft = (await w.expense(summary.id))!.draft;
          final template = RecurringExpenseTemplate(
            id: 'geometry-example',
            revision: 1,
            sourceExpenseId: summary.id.value,
            defaults: draft,
            schedule: RecurrenceRule(
              startsOn: DateTime(2030),
              unit: RecurrenceUnit.months,
            ),
            paused: paused,
          );
          w.database.saveRecurringExpenseTemplate(
            w.identity.businessId,
            template,
          );
          final beforeExpenses = (await w.expenses()).length;
          final beforeJournals = (await w.journals()).length;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  body: ExpenseIntakePage(workspace: w, onRecordExpense: () {}),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('expense-open-recurring')),
          );
          await tester.pumpAndSettle();
          final row = find.byKey(
            const ValueKey('recurring-expense-row-geometry-example'),
          );
          expect(
            find.descendant(
              of: row,
              matching: find.byType(AccountingRecordRow),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.byType(AccountingRecordActions),
            ),
            findsOneWidget,
          );
          final edit = find.byKey(
            const ValueKey('recurring-edit-geometry-example'),
          );
          final toggle = find.byKey(
            const ValueKey('recurring-toggle-geometry-example'),
          );
          expect(tester.getRect(edit).height, 32);
          expect(tester.getRect(toggle).height, 32);
          expect(
            tester.getTopLeft(edit).dy,
            closeTo(tester.getTopLeft(toggle).dy, .1),
          );
          expect(
            find.byKey(const ValueKey('prepare-recurring-geometry-example-1')),
            paused ? findsNothing : findsOneWidget,
          );
          if (!paused) {
            final prepare = find.byKey(
              const ValueKey('prepare-recurring-geometry-example-0'),
            );
            final title = find.descendant(
              of: row,
              matching: find.text(template.payee),
            );
            final details = find.descendant(
              of: row,
              matching: find.textContaining('Starts '),
            );
            expect(
              tester.getTopLeft(prepare).dx,
              closeTo(tester.getTopLeft(title).dx, .1),
            );
            expect(
              tester.getTopLeft(prepare).dy - tester.getBottomLeft(details).dy,
              closeTo(accountingContentInset, .1),
            );
          }
          await captureUi(
            tester,
            'Expense Recurrence ${paused ? 'Paused' : 'Active'} ${width.toInt()}',
          );
          await tester.tap(
            find.byKey(const ValueKey('recurring-saved-suggestions')),
          );
          await tester.pumpAndSettle();
          final emptyDialog = find.ancestor(
            of: find.text('No recurring suggestions have been prepared.'),
            matching: find.byType(AlertDialog),
          );
          expect(emptyDialog, findsOneWidget);
          expect(
            find.descendant(
              of: emptyDialog,
              matching: find.byType(AccountingRecordList),
            ),
            findsNothing,
          );
          expect(
            tester
                .getSize(
                  find
                      .descendant(
                        of: emptyDialog,
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is Material &&
                              widget.type == MaterialType.card,
                        ),
                      )
                      .first,
                )
                .width,
            lessThanOrEqualTo(448),
          );
          await captureUi(
            tester,
            'Expense Recurrence Empty Suggestions ${width.toInt()}',
          );

          expect((await w.expenses()).length, beforeExpenses);
          expect((await w.journals()).length, beforeJournals);
          expect(
            w.database
                .recurringExpenseTemplates(w.identity.businessId)
                .single
                .toJson(),
            template.toJson(),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
