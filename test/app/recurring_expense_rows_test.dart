import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audyt/features/accounting/presentation/expense_recurrence_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import '../support/accounting_test_finders.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  setUp(AccountingRecordPageSizes.reset);
  for (final width in [720.0, 1162.0]) {
    testWidgets('empty recurring parent fits without list shell at $width', (
      t,
    ) async {
      await prepare(t, width);
      t.view.physicalSize = Size(width, 809);
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: ExpenseIntakePage(workspace: w, onRecordExpense: () {}),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('expense-open-recurring')));
      final popup = find.ancestor(
        of: find.text(
          'Set recurrence when recording an expense to add a schedule.',
        ),
        matching: find.byType(AlertDialog),
      );
      expect(
        find.descendant(of: popup, matching: find.byType(AccountingRecordList)),
        findsNothing,
      );
      final frame = find
          .descendant(
            of: popup,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material && widget.type == MaterialType.card,
            ),
          )
          .first;
      expect(t.getSize(frame).width, lessThanOrEqualTo(448));
      final saved = find.byKey(const ValueKey('recurring-saved-suggestions'));
      expect(t.getSize(saved).width, lessThan(400));
      await captureUi(t, 'Expense Recurrence Empty Parent ${width.toInt()}');
      await tap(t, saved);
      expect(
        find.text('No recurring suggestions have been prepared.'),
        findsOneWidget,
      );
      await tap(t, accountingCloseIcon().last);
      expect(
        find.text(
          'Set recurrence when recording an expense to add a schedule.',
        ),
        findsOneWidget,
      );
      await tap(t, accountingCloseIcon().last);
      expect(tables(w), before);
      expect(t.takeException(), isNull);
    });
  }
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'actual expense schedule field titles align in all ending branches at $width',
      (t) async {
        await prepare(t, width);
        t.view.physicalSize = Size(width, 809);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final source = (await w.expenses()).first;
        w.database.saveRecurringExpenseTemplate(
          w.identity.businessId,
          RecurringExpenseTemplate(
            id: 'label-review',
            revision: 1,
            sourceExpenseId: source.id.value,
            defaults: (await w.expense(source.id))!.draft,
            schedule: RecurrenceRule(
              startsOn: DateTime(2030),
              unit: RecurrenceUnit.months,
            ),
            paused: true,
          ),
        );
        final before = tables(w);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ExpenseIntakePage(workspace: w, onRecordExpense: () {}),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('expense-open-recurring')));
        await tap(t, find.byKey(const ValueKey('recurring-edit-label-review')));
        Finder selector(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector && widget.semanticsLabel == label,
        );
        for (final ending in ['Never', 'On Date', 'After Occurrences']) {
          if (ending != 'Never') {
            await tap(t, selector('Ends'));
            await tap(t, find.text(ending).last);
          }
          for (final label in ['Repeat Unit', 'Ends']) {
            expectPopupFieldTitleAligned(t, label, selector(label));
          }
          expectPopupFieldTitleAligned(
            t,
            'Every',
            find.byKey(const ValueKey('recurrence-every')),
          );
          if (ending == 'On Date') {
            expectPopupFieldTitleAligned(
              t,
              'End Date',
              find.byKey(const ValueKey('recurrence-end')),
            );
          }
          if (ending == 'After Occurrences') {
            expectPopupFieldTitleAligned(
              t,
              'Occurrences',
              find.byKey(const ValueKey('recurrence-count')),
            );
          }
          expect(find.text('Keep Month End'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AccountingFieldHelp &&
                  widget.label == 'Repeat Unit',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await captureUi(
            t,
            'Expense Schedule Label Frames $ending ${width.toInt()}',
          );
        }
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard'));
        expect(tables(w), before);
      },
    );
  }
  for (final width in [720.0, 1162.0]) {
    for (final dismissal in ['Close', 'Escape', 'Backdrop']) {
      testWidgets(
        'schedule edits survive $dismissal until explicit discard at $width',
        (t) async {
          await prepare(t, width);
          t.view.physicalSize = Size(width, 809);
          RecurrenceRule? returned;
          var completions = 0;
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        returned = await showExpenseRecurrenceDialog(
                          context,
                          startsOn: DateTime(2030),
                          initial: RecurrenceRule(
                            startsOn: DateTime(2030),
                            unit: RecurrenceUnit.months,
                          ),
                        );
                        completions++;
                      },
                      child: const Text('Open Schedule'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tap(t, find.text('Open Schedule'));
          // Untouched dismissals need no warning.
          await tap(t, accountingCloseIcon().last);
          expect(completions, 1);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          await tap(t, find.text('Open Schedule'));
          final interval = find.byKey(const ValueKey('recurrence-every'));
          await t.enterText(interval, '2');
          await t.pumpAndSettle();
          Future<void> dismiss() async {
            if (dismissal == 'Close') {
              await tap(t, accountingCloseIcon().last);
            } else if (dismissal == 'Escape') {
              await t.tap(interval);
              await t.sendKeyDownEvent(LogicalKeyboardKey.escape);
              await t.sendKeyUpEvent(LogicalKeyboardKey.escape);
              await t.pumpAndSettle();
            } else {
              await t.tapAt(const Offset(8, 200));
              await t.pumpAndSettle();
            }
          }

          await dismiss();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          expect(completions, 1);
          await captureUi(
            t,
            'Expense Schedule $dismissal Dirty ${width.toInt()}',
          );
          await tap(t, find.text('Keep Editing'));
          expect(t.widget<TextField>(interval).controller!.text, '2');
          expect(
            find.byKey(const ValueKey('recurrence-apply')),
            findsOneWidget,
          );
          await dismiss();
          await tap(t, find.text('Discard'));
          expect(completions, 2);
          expect(returned, isNull);
          await tap(t, find.text('Open Schedule'));
          expect(t.widget<TextField>(interval).controller!.text, '1');
          await t.enterText(interval, '3');
          await t.enterText(interval, '1');
          await tap(t, accountingCloseIcon().last);
          expect(completions, 3);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          await tap(t, find.text('Open Schedule'));
          await t.enterText(interval, '0');
          await tap(t, find.byKey(const ValueKey('recurrence-apply')));
          expect(
            find.byKey(const ValueKey('recurrence-error')),
            findsOneWidget,
          );
          expect(completions, 3);
          await t.enterText(interval, '3');
          await tap(t, find.byKey(const ValueKey('recurrence-apply')));
          expect(returned!.every, 3);
          expect(returned!.unit, RecurrenceUnit.months);
          expect(completions, 4);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
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
      expect(list, count == 0 ? findsNothing : findsOneWidget);
      if (count == 0) {
        expect(
          find.text('Set recurrence when recording an expense to add a schedule.'),
          findsOneWidget,
        );
      }
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
