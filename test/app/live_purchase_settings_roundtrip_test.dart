import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../support/fixed_popout_host.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final pathKind in ['Saved', 'Recurring']) {
      testWidgets(
        '$pathKind expense applies saved purchase settings at $width',
        (tester) async {
          installFixedPopoutHost(tester);
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final root = Directory.systemTemp.createTempSync(
            'audyt-purchase-settings-',
          );
          addTearDown(() => root.deleteSync(recursive: true));
          final sourcePath = '${root.path}/source.sqlite';
          final original = await createDemoWorkspace(databasePath: sourcePath);
          final now = DateTime.now();
          final yesterday = DateTime(now.year, now.month, now.day - 1);
          RecordExpenseDraft draft({
            bool tags = false,
            bool recurring = false,
          }) => RecordExpenseDraft(
            submissionId: EntityId.random().value,
            amount: '25.50',
            date: formatAccountingInputDate(yesterday),
            payee: tags ? 'Retained Supplier' : 'Settings Supplier',
            paymentAccount: 'Demo Bank',
            paymentAccountId: 'demo-bank',
            category: 'Office Operations',
            tax: 'No tax',
            customer: tags ? 'Retained Client' : '',
            billable: tags,
            dimensions: tags ? 'Retained Class' : '',
            itemOrSplitDetails: tags ? 'Retained Item' : '',
            notes: 'Unchanged saved expense',
            recurrence: recurring
                ? RecurrenceRule(
                    startsOn: yesterday,
                    unit: RecurrenceUnit.days,
                    occurrenceCount: 3,
                  )
                : null,
          );
          final blank = draft(), tagged = draft(tags: true);
          final blankId = await original.saveExpenseIntake(blank);
          final taggedId = await original.saveExpenseIntake(tagged);
          await original.saveExpenseIntake(draft(recurring: true));
          await original.database.prepareDueRecurringExpenses(
            original.identity.businessId,
            through: now,
          );
          final pending = original.database
              .recurringExpenseSuggestions(original.identity.businessId)
              .singleWhere((entry) => entry.savedExpenseId == null);
          final archive = original.database.exportDataArchive(
            original.identity.businessId,
            now,
          );
          final originalTables = tables(original);
          original.dispose();
          final sourceBytes = File(sourcePath).readAsBytesSync();
          final path = '${root.path}/restored.sqlite';
          var workspace = await AccountingWorkspace.emptyRestore(path, archive);
          addTearDown(() => workspace.dispose());
          expect(tables(workspace), originalTables);
          final savedBlank = (await workspace.expense(blankId))!.draft.toJson();
          final savedTagged = (await workspace.expense(taggedId))!.draft
              .toJson();
          var revision = workspace.preferences.revision;

          Future<void> pumpApp() async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: DemoCompany(
                  child: AudytApp(
                    workspace: workspace,
                    showInitialSetup: false,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          Future<void> tap(Finder target) async {
            await revealAccountingRecord(tester, target);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          Future<void> settings(bool enabled) async {
            await tap(find.byKey(const ValueKey('accounting-settings')));
            await tap(find.text('Purchase Preferences').first);
            for (final field
                in enabled
                    ? ['Track Items', 'Link To Customer', 'Billable Expenses']
                    : [
                        'Billable Expenses',
                        'Link To Customer',
                        'Track Items',
                      ]) {
              await tap(find.byKey(ValueKey('design-field-$field')));
            }
            await tap(find.byKey(const ValueKey('design-save-settings')));
            expect(workspace.preferences.revision, ++revision);
            for (final field in [
              'Track Items',
              'Link To Customer',
              'Billable Expenses',
            ]) {
              expect(
                workspace.preferences.enabled('Purchase Preferences', field),
                enabled,
              );
            }
            await captureUi(
              tester,
              'Settings Purchase Saved $enabled ${width.toInt()}',
            );
            await tester.tap(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.label == 'Close',
                  )
                  .last,
            );
            await tester.pumpAndSettle();
          }

          Future<void> inspect(
            String state, {
            required bool shown,
            bool retained = false,
          }) async {
            expect(find.byType(RecordExpensePage), findsOneWidget);
            await captureUi(
              tester,
              'Settings Purchase $pathKind $state Top ${width.toInt()}',
            );
            if (find
                    .byKey(const ValueKey('expense-field-customer'))
                    .evaluate()
                    .isEmpty &&
                !retained) {
              await tap(find.text('Advanced Accounting Details'));
            }
            expect(
              find.byKey(const ValueKey('expense-field-customer')),
              shown ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('expense-field-billable')),
              shown ? findsOneWidget : findsNothing,
            );

            expect(
              find.byKey(const ValueKey('expense-field-item-or-split')),
              shown ? findsOneWidget : findsNothing,
            );
            await captureUi(
              tester,
              'Settings Purchase $pathKind $state Details ${width.toInt()}',
            );
            if (retained) {
              expect(find.text('Retained Client'), findsOneWidget);
              expect(
                accountingDescriptionText('Retained Item'),
                findsOneWidget,
              );
            }
          }

          Future<void> cancel() =>
              tap(find.byKey(const ValueKey('record-expense-cancel')));
          Future<void> entry(bool enabled) async {
            await tap(find.byKey(const ValueKey('navigation-item-home')));
            await tap(find.byKey(const ValueKey('home-record-expense-action')));
            await inspect('New $enabled', shown: enabled);
            await cancel();
          }

          Future<void> target(bool enabled) async {
            await tap(
              find.byKey(const ValueKey('navigation-item-expenses-vendors')),
            );
            if (pathKind == 'Saved') {
              await tap(find.byKey(ValueKey('open-expense-${blankId.value}')));
            } else {
              await tap(find.byKey(ValueKey('open-expense-${taggedId.value}')));
              await tap(find.byKey(const ValueKey('record-expense-cancel')));
              await tap(find.byKey(const ValueKey('expense-open-recurring')));
              await tap(
                find.byKey(const ValueKey('recurring-saved-suggestions')),
              );
              await tap(
                find.byKey(ValueKey('review-recurring-${pending.identity}')),
              );
            }
            await inspect('Target $enabled', shown: enabled);
            await cancel();
            if (pathKind == 'Recurring') {
              expect(find.text('Recurring Expenses'), findsOneWidget);
              await tester.tap(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is Semantics &&
                          widget.properties.label == 'Close',
                    )
                    .last,
              );
              await tester.pumpAndSettle();
            }
          }

          await pumpApp();
          if (pathKind == 'Saved') {
            final beforePreview = tables(workspace);
            await tap(find.byKey(const ValueKey('accounting-settings')));
            await tap(find.text('Purchase Preferences').first);
            await tap(find.byKey(const ValueKey('design-field-Show Rate')));
            await tap(find.byKey(const ValueKey('design-preview')));
            final preview = find.byKey(const ValueKey('expense-live-dialog'));
            expect(preview, findsOneWidget);
            final page = tester.widget<RecordExpensePage>(
              find.byType(RecordExpensePage),
            );
            expect(page.includeTopSafeArea, false);
            expect(page.readOnly, true);
            expect(page.onCancel, isNotNull);
            expect(find.text('Quantity'), findsOneWidget);
            expect(find.text('Rate (RM)'), findsOneWidget);
            final amount = find.byKey(const ValueKey('expense-field-amount'));
            await Scrollable.ensureVisible(
              tester.element(amount),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            final amountRect = tester.getRect(amount);
            final windowWidth =
                tester.view.physicalSize.width / tester.view.devicePixelRatio;
            expect(amountRect.right, lessThan(windowWidth));
            expect(amountRect.left, greaterThan(0));
            expect(tester.takeException(), isNull);
            await captureUi(
              tester,
              'Purchase Preferences Forced Preview ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('record-expense-cancel')));
            expect(preview, findsNothing);
            await tester.tap(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.label == 'Close',
                  )
                  .last,
            );
            await tester.pumpAndSettle();
            expect(tables(workspace), beforePreview);
          }
          await settings(false);
          await entry(false);
          await tap(
            find.byKey(const ValueKey('navigation-item-expenses-vendors')),
          );
          await tap(find.byKey(ValueKey('open-expense-${taggedId.value}')));
          await inspect('Retained', shown: true, retained: true);
          await cancel();
          await target(false);
          final disabledTables = tables(workspace);
          expect(
            (await workspace.expense(blankId))!.draft.toJson(),
            savedBlank,
          );
          expect(
            (await workspace.expense(taggedId))!.draft.toJson(),
            savedTagged,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          workspace.dispose();
          workspace = await AccountingWorkspace.open(path);
          expect(tables(workspace), disabledTables);
          expect(File(sourcePath).readAsBytesSync(), sourceBytes);
          await pumpApp();
          await entry(false);
          await target(false);
          await settings(true);
          await entry(true);
          await target(true);
          expect(
            (await workspace.expense(blankId))!.draft.toJson(),
            savedBlank,
          );
          expect(
            (await workspace.expense(taggedId))!.draft.toJson(),
            savedTagged,
          );
          final enabledTables = tables(workspace);
          await tester.pumpWidget(const SizedBox.shrink());
          workspace.dispose();
          workspace = await AccountingWorkspace.open(path);
          expect(tables(workspace), enabledTables);
          expect(File(sourcePath).readAsBytesSync(), sourceBytes);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
