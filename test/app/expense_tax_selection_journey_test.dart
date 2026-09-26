import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/expense_tax_persistence_test.dart'
    show configureExpenseTaxes, taxedExpense;
import '../features/accounting/data/expense_intake_test.dart' show draft;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'complete Expense resolves recurring tax selections without a reviewer at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        for (final font in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
        final dir = Directory.systemTemp.createTempSync(
          'expense-tax-selection-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final w = await AccountingWorkspace.open('${dir.path}/books.sqlite');
        addTearDown(w.dispose);
        final codes = await configureExpenseTaxes(w);
        final originalSuggestion = taxedExpense(codes, 'Exclusive');
        final suggestion = RecordExpenseDraft.fromJson({
          ...originalSuggestion.toJson(),
          'lines': [
            for (final line in originalSuggestion.lines)
              ExpenseDraftLine(
                id: line.id,
                category: line.category,
                description: line.description,
                tax: line.tax,
                taxSnapshot: line.taxSnapshot,
                amount: line.amount,
              ).toJson(),
          ],
        });
        EntityId? saved;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => AccountingButton.primary(
                    context,
                    key: null,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => RecordExpensePage(
                        settingsWorkspace: w,
                        accounts: w.paymentAccounts,
                        recurringSuggestion: suggestion,
                        includeTopSafeArea: false,
                        onSave: (value) async {
                          saved = await w.saveExpenseIntake(value);
                        },
                        onCancel: () => Navigator.pop(context),
                      ),
                    ),
                    child: const Text('Open Expense'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Expense'));
        await tester.pumpAndSettle();
        Finder taxRows() => find.byWidgetPredicate(
          (v) =>
              v is AccountingSelector<String> &&
              (v.controlKey as ValueKey?)?.value.toString().startsWith(
                    'expense-tax-control',
                  ) ==
                  true,
        );
        expect(find.text('Tax Selection Required'), findsOneWidget);
        expect(find.text('Select Tax'), findsNWidgets(3));
        for (final control in tester.widgetList<AccountingSelector<String>>(
          taxRows(),
        )) {
          expect(control.value, isNull);
          expect(
            control.options.any((o) => o.label.contains('Review Needed')),
            isFalse,
          );
        }
        final original = tables(w);
        await captureUi(
          tester,
          'Proposed Expense Unresolved Full ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('record-expense-save')));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(tables(w), original);
        Future<void> choose(Finder f, String label) async {
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, label).last);
          await tester.pumpAndSettle();
        }

        final taxWidth = tester.getSize(taxRows().first).width;
        await choose(taxRows().first, codes[0].label);
        await choose(taxRows().at(1), codes[1].label);
        await choose(taxRows().last, 'No Tax');
        expect(find.text('Tax Selection Required'), findsNothing);
        for (final row in taxRows().evaluate()) {
          expect(tester.getSize(find.byWidget(row.widget)).width, taxWidth);
        }
        await choose(
          find.byKey(const ValueKey('expense-field-payment-account')),
          'Cash · Cash · RM',
        );
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('expense-field-date')),
          '01-10-2026',
        );
        await captureUi(
          tester,
          'Proposed Expense Resolved Full ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('record-expense-save')));
        await tester.pumpAndSettle();
        expect(
          saved,
          isNotNull,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((v) => v.data)
              .whereType<String>()
              .join(' | '),
        );
        final retained = (await w.expense(saved!))!.draft;
        expect(retained.taxMode, 'Exclusive');
        expect(retained.lines.map((l) => l.tax), [
          codes[0].choice,
          codes[1].choice,
          '0',
        ]);
        expect(retained.taxTotals!.total.minorUnits, 18300);
        expect(await w.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'legacy and unavailable Expense tax remain unresolved, while saved inactive snapshots stay readable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('expense-tax-history-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final w = await AccountingWorkspace.open('${dir.path}/books.sqlite');
        addTearDown(w.dispose);
        final codes = await configureExpenseTaxes(w);
        final before = tables(w);
        Future<void> show(
          RecordExpenseDraft? source, {
          bool readOnly = false,
        }) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: RecordExpensePage(
                  key: UniqueKey(),
                  settingsWorkspace: w,
                  accounts: w.paymentAccounts,
                  savedDraft: source,
                  readOnly: readOnly,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(null);
        expect(find.text('Tax Selection Required'), findsNothing);
        await show(draft(paymentAccountId: 'cash'), readOnly: true);
        // A historical view retains the unresolved code without an editing
        // instruction. The same facts in Edit still require a selection.
        expect(find.text('Tax Selection Required'), findsNothing);
        final tax = tester.widget<AccountingSelector<String>>(
          find.byWidgetPredicate(
            (v) =>
                v is AccountingSelector<String> &&
                v.controlKey == const ValueKey('expense-tax-control'),
          ),
        );
        expect(tax.value, isNull);
        expect(tax.enabled, isFalse);
        expect(find.text('Review Needed'), findsNothing);
        expect(tables(w), before);
        await show(draft(paymentAccountId: 'cash'));
        expect(find.text('Tax Selection Required'), findsOneWidget);
        expect(tables(w), before);
        final original = taxedExpense(codes, 'Exclusive');
        w.saveTaxRate(
          CompanyTaxRate.fromJson({
            ...codes[0].toJson(),
            'active': false,
            'percent': '9',
          }),
        );
        final afterMaster = tables(w);
        await show(original, readOnly: true);
        expect(find.text('Tax Selection Required'), findsNothing);
        expect(find.text('183.00'), findsWidgets);
        expect(tables(w), afterMaster);
        await show(original);
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('expense-field-date')),
          '01-01-2027',
        );
        await tester.pumpAndSettle();
        expect(find.text('Tax Selection Required'), findsOneWidget);
        expect(tables(w), afterMaster);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
