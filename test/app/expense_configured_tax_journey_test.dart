import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/expense_tax_persistence_test.dart'
    show configureExpenseTaxes;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final basis in ['Exclusive', 'Inclusive']) {
      testWidgets(
        'Expense configured mixed tax, $basis, cancel/save/amend/restart at $width',
        (tester) async {
          installFixedPopoutHost(tester);
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final root = Directory.systemTemp.createTempSync(
            'expense-configured-tax-',
          );
          addTearDown(() => root.deleteSync(recursive: true));
          final path = '${root.path}/books.sqlite';
          var w = await AccountingWorkspace.open(path);
          addTearDown(() => w.dispose());
          final codes = await configureExpenseTaxes(w);
          final salesOnly = w.saveTaxRate(
            CompanyTaxRate(
              id: codes[2].id,
              name: codes[2].name,
              percent: codes[2].percent,
              effectiveFrom: codes[2].effectiveFrom,
              effectiveThrough: codes[2].effectiveThrough,
              application: TaxApplication.sales,
              accountId: codes[2].accountId,
              revision: codes[2].revision,
            ),
          );
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          Widget app() => RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: w,
              initialPath: '/expenses-vendors',
              showInitialSetup: false,
            ),
          );
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          Future<void> tap(Finder f) async {
            await tester.ensureVisible(f);
            await tester.pumpAndSettle();
            await tester.tap(f);
            await tester.pumpAndSettle();
          }

          Future<void> key(String value) => tap(find.byKey(ValueKey(value)));
          Future<void> choose(Finder f, String label) async {
            await tap(f);
            await tap(find.textContaining(label).last);
          }

          Finder rows(String suffix, Type type) => find.byWidgetPredicate(
            (v) =>
                (type == AccountingSelector
                    ? v is AccountingSelector<String>
                    : v is TextFormField) &&
                ((v is AccountingSelector<String> ? v.triggerKey : v.key)
                            as ValueKey?)
                        ?.value
                        .toString()
                        .endsWith('-$suffix') ==
                    true,
          );
          Future<void> populate() async {
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
              'Tax $basis',
            );
            await choose(
              rows('category', AccountingSelector).first,
              'Office Operations',
            );
            await choose(rows('tax', AccountingSelector).first, codes[0].label);
            await enterAccountingText(
              tester,
              rows('amount', TextFormField).first,
              basis == 'Inclusive' ? '108' : '100',
            );
            await key('expense-add-line');
            await choose(
              rows('category', AccountingSelector).last,
              'Office Operations',
            );
            await choose(rows('tax', AccountingSelector).last, codes[1].label);
            await enterAccountingText(
              tester,
              rows('amount', TextFormField).last,
              basis == 'Inclusive' ? '55' : '50',
            );
            await key('expense-add-line');
            await choose(
              rows('category', AccountingSelector).last,
              'Office Operations',
            );
            await enterAccountingText(
              tester,
              rows('amount', TextFormField).last,
              '20',
            );
            await tester.pumpAndSettle();
          }

          final before = tables(w);
          await key('intake-record-expense');
          expect(find.text('Amounts Are'), findsOneWidget);
          expect(find.text('Tax Basis'), findsNothing);
          expect(
            find.byKey(const ValueKey('expense-row-tax-basis')),
            findsNothing,
          );
          expect(find.text('Tax Treatment'), findsNothing);
          final selector = tester.widget<AccountingSelector<String>>(
            rows('tax', AccountingSelector).first,
          );
          expect(selector.value, '0');
          expect(
            selector.options.map((o) => o.value),
            isNot(contains(salesOnly.choice)),
          );
          expect(
            selector.options.map((o) => o.label),
            isNot(contains('Withholding Tax')),
          );
          final categoryWidth = tester
              .getSize(rows('category', AccountingSelector).first)
              .width;
          final taxWidth = tester
              .getSize(rows('tax', AccountingSelector).first)
              .width;
          await populate();
          final populatedTaxWidth = tester
              .getSize(rows('tax', AccountingSelector).first)
              .width;
          expect(populatedTaxWidth, greaterThan(taxWidth));
          final taxContext = tester.element(
            rows('tax', AccountingSelector).first,
          );
          expect(
            populatedTaxWidth,
            closeTo(
              accountingSelectorMinimumWidth(taxContext, [
                'Select Tax',
              ], stackedLine: true),
              .1,
            ),
          );
          for (final row in rows('category', AccountingSelector).evaluate()) {
            expect(
              tester.getSize(find.byWidget(row.widget)).width,
              categoryWidth,
            );
          }
          for (final row in rows('tax', AccountingSelector).evaluate()) {
            expect(
              tester.getSize(find.byWidget(row.widget)).width,
              populatedTaxWidth,
            );
          }
          final taxText = find
              .descendant(
                of: rows('tax', AccountingSelector).first,
                matching: find.byType(Text),
              )
              .first;
          expect(tester.widget<Text>(taxText).data, codes[0].label);
          expect(
            tester.renderObject<RenderParagraph>(taxText).didExceedMaxLines,
            isTrue,
          );
          expect(find.text('170.00'), findsOneWidget);
          expect(find.text('13.00'), findsOneWidget);
          expect(find.text('183.00'), findsOneWidget);
          expect(tables(w), before);
          await enterAccountingText(
            tester,
            find.byKey(const ValueKey('expense-field-date')),
            '01-01-2027',
          );
          await tester.pumpAndSettle();
          expect(find.text('—'), findsWidgets);
          await key('record-expense-save');
          expect(find.byType(RecordExpensePage), findsOneWidget);
          expect(
            find.byKey(const ValueKey('record-expense-save-error')),
            findsOneWidget,
          );
          expect(tables(w), before);
          await enterAccountingText(
            tester,
            find.byKey(const ValueKey('expense-field-date')),
            '01-10-2026',
          );
          await tester.pumpAndSettle();
          expect(find.text('13.00'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('record-expense-save-error')),
            findsNothing,
          );
          await captureUi(
            tester,
            'Expense Configured Tax $basis ${width.toInt()}',
          );
          await key('record-expense-cancel');
          expect(tables(w), before);
          // Re-enter through the actual route after cancellation.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          await key('intake-record-expense');
          await populate();
          await key('record-expense-save');
          expect(find.byType(RecordExpensePage), findsNothing);
          final summaries = await w.expenses();
          expect(summaries, hasLength(1));
          final id = summaries.single.id;
          final saved = (await w.expense(id))!.draft;
          expect(saved.taxMode, basis);
          expect(saved.taxTotals!.total.minorUnits, 18300);
          expect(saved.lines.map((l) => l.taxSnapshot?.choice).toList(), [
            codes[0].choice,
            codes[1].choice,
            null,
          ]);
          expect(saved.lines.last.tax, '0');
          w.saveTaxRate(
            CompanyTaxRate.fromJson({
              ...codes[0].toJson(),
              'percent': '9',
              'active': false,
            }),
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          await key('open-expense-${id.value}');
          expect(find.text(codes[0].label), findsOneWidget);
          expect(find.text('13.00'), findsOneWidget);
          await enterAccountingText(
            tester,
            find.byKey(const ValueKey('expense-field-notes')),
            'Retained old tax memo',
          );
          await tester.pumpAndSettle();
          await key('record-expense-save');
          expect(find.byType(RecordExpensePage), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          w.dispose();
          w = await AccountingWorkspace.open(path);
          final reopened = (await w.expense(id))!.draft;
          expect(reopened.notes, 'Retained old tax memo');
          expect(reopened.taxMode, basis);
          expect(reopened.taxTotals!.tax.minorUnits, 1300);
          expect(reopened.lines.first.taxSnapshot!.percent, '8');
          expect(reopened.lines.last.taxSnapshot, isNull);
          expect(await w.journals(), isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
