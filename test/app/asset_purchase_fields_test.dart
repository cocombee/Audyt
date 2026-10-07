import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/asset_purchase_fields.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/frontend_review.dart';

import 'frontend_catalog_test.dart' show openForm;
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import '../support/fixed_popout_host.dart';
import 'restored_page_routes_test.dart' show tables;

InputDecoration? inputDecoration(WidgetTester tester, Finder input) => tester
    .widget<TextField>(
      find.descendant(of: input, matching: find.byType(TextField)),
    )
    .decoration;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final (currency, symbol, costValue, expenseValue, residualValue) in [
      ('MYR', 'RM', '1,234,567.00', '250.00', '12.00'),
      ('JPY', '¥', '1,234,567', '250', '12'),
      ('KWD', 'KWD', '1,234,567.000', '250.000', '12.000'),
    ]) {
      testWidgets(
        'Home Expense split purchase review retains $currency facts and real insets at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          installFixedPopoutHost(tester);
          await loadJournalLayoutFonts();
          final directory = Directory.systemTemp.createTempSync(
            'asset-real-caller-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final workspace = await createDemoWorkspace(
            databasePath: '${directory.path}/ledger.sqlite',
          );
          addTearDown(workspace.dispose);
          final baseline = tables(workspace);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: AudytApp(
                workspace: workspace,
                accountCurrencyCode: currency,
                showInitialSetup: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final primary = find.byKey(const ValueKey('record-expense-primary'));
          final entry = primary.evaluate().isNotEmpty
              ? primary
              : find.byKey(const ValueKey('home-record-expense-action'));
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('expense-live-dialog')),
            findsOneWidget,
          );
          final advanced = find.byKey(
            const ValueKey('expense-advanced-details'),
          );
          await tester.ensureVisible(advanced);
          await tester.tap(advanced);
          await tester.pumpAndSettle();
          final treatment = find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.hintText == 'Select Purchase Treatment',
          );
          await tester.ensureVisible(treatment);
          await tester.tap(treatment);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Split Expense / Asset').last);
          await tester.pumpAndSettle();
          final fields = find.byType(AssetPurchaseFields);
          expect(
            find.textContaining('Link this purchase to Fixed Assets.'),
            findsNothing,
          );
          expect(
            find.textContaining('Use Supporting Documents below'),
            findsNothing,
          );
          for (final label in [
            'Purchase Treatment',
            'Acquisition Cost ($symbol)',
            'Tax Policy',
          ]) {
            final help = find.descendant(
              of: fields,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is AccountingFieldHelp && widget.label == label,
              ),
            );
            final message = tester.widget<AccountingFieldHelp>(help).message;
            expect(find.text(message), findsNothing);
            await tester.ensureVisible(help);
            await tester.tap(help);
            await tester.pumpAndSettle();
            expect(find.text(message), findsOneWidget);
            if (currency == 'MYR') {
              await captureUi(
                tester,
                'Asset Purchase $label Helper ${width.toInt()}',
              );
            }
            Tooltip.dismissAllToolTips();
            await tester.pumpAndSettle();
            expect(find.text(message), findsNothing);
          }
          final cost = find.byKey(
            const ValueKey('asset-purchase-field-Acquisition Cost'),
          );
          final dimensions = find.byKey(
            const ValueKey('expense-field-dimensions'),
          );
          final frame = tester.getRect(
            find.byKey(const ValueKey('expense-live-dialog')),
          );
          expect(
            tester.getRect(cost).left,
            closeTo(tester.getRect(dimensions).left, .1),
          );
          expect(
            tester.getRect(fields).left - frame.left,
            greaterThanOrEqualTo(accountingContentInset),
          );
          expect(
            frame.right - tester.getRect(fields).right,
            greaterThanOrEqualTo(accountingContentInset),
          );
          await tester.ensureVisible(treatment);
          await tester.pumpAndSettle();
          await captureUi(
            tester,
            'Expense Split Asset Actual Caller Top $currency ${width.toInt()}',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('asset-purchase-field-Residual Value')),
          );
          await tester.pumpAndSettle();
          await captureUi(
            tester,
            'Expense Split Asset Actual Caller Lower $currency ${width.toInt()}',
          );
          Future<void> tap(Finder target) async {
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          final review = find.byKey(const ValueKey('record-expense-save'));
          final back = find.byKey(const ValueKey('asset-purchase-review-back'));
          List<(String, String)> reviewRows() => tester
              .widget<AccountingInformationRows>(
                find.byType(AccountingInformationRows).last,
              )
              .rows;
          await tap(review);
          expect(reviewRows(), [
            ('Purchase Treatment', 'Split Expense / Asset'),
            ('Asset Category', 'Equipment'),
            ('Book Method', 'Straight Line'),
            ('Tax Policy', 'Accountant Review Required'),
          ]);
          expect(find.textContaining('Frontend'), findsNothing);
          expect(find.textContaining('posting is unavailable'), findsOneWidget);
          final action = tester.widget<ButtonStyleButton>(back);
          expect(action.onPressed, isNotNull);
          expect(
            action.style!.backgroundColor!.resolve({}),
            AccountingTheme.of(tester.element(back)).primary,
          );
          expect(tester.getSize(back).width, lessThan(300));
          await captureUi(
            tester,
            'Asset Purchase Review Empty $currency ${width.toInt()}',
          );
          await tap(back);
          for (final (name, value) in [
            ('Asset Name', 'Inspection Equipment'),
            ('Acquisition Cost', '1234567'),
            ('Expense Portion', '250'),
            ('Residual Value', '12'),
            ('Useful Life In Months', '18'),
          ]) {
            final input = find.byKey(ValueKey('asset-purchase-field-$name'));
            await tester.ensureVisible(input);
            await tester.enterText(input, value);
            await tester.pumpAndSettle();
          }
          await tap(review);
          expect(
            reviewRows(),
            contains(('Acquisition Cost ($symbol)', costValue)),
          );
          expect(
            reviewRows(),
            contains(('Expense Portion ($symbol)', expenseValue)),
          );
          expect(
            reviewRows(),
            contains(('Residual Value ($symbol)', residualValue)),
          );
          expect(reviewRows(), contains(('Useful Life In Months', '18')));
          expect(
            reviewRows().where(
              (r) => r.$1 == 'Useful Life In Months ($symbol)',
            ),
            isEmpty,
          );
          expect(tables(workspace), baseline);
          await captureUi(
            tester,
            'Asset Purchase Review Entered $currency ${width.toInt()}',
          );
          await tap(back);
          final retained = tester.widget<TextFormField>(
            find.byKey(const ValueKey('asset-purchase-field-Asset Name')),
          );
          expect(retained.initialValue, 'Inspection Equipment');
          final costInput = tester.widget<TextField>(
            find.descendant(of: cost, matching: find.byType(TextField)),
          );
          expect(costInput.controller!.text, '1,234,567');
          await tester.ensureVisible(cost);
          await tester.tap(cost);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(find.text('Keep Editing'));
          expect(find.byType(AssetPurchaseFields), findsOneWidget);
          final close = find.bySemanticsLabel('Close').last;
          await tap(close);
          await tap(find.text('Discard'));
          expect(
            find.byKey(const ValueKey('expense-live-dialog')),
            findsNothing,
          );
          expect(tables(workspace), baseline);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets('fixed asset amount fields use session currency at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      final form = frontendAreas.values
          .expand((forms) => forms)
          .singleWhere((form) => form.title == 'Fixed Assets');
      await openForm(tester, form);
      for (final label in ['Cost', 'Residual Value']) {
        final input = find.byKey(ValueKey('design-field-$label'));
        expect(inputDecoration(tester, input)?.prefixText, isNull);
        expect(inputDecoration(tester, input)?.hintText, '0.00');
        expect(find.text('$label (RM)'), findsOneWidget);
      }
      await captureUi(tester, 'Fixed Assets Monetary Empty ${width.toInt()}');
      await tester.enterText(
        find.byKey(const ValueKey('design-field-Cost')),
        '1234567.89',
      );
      await tester.pumpAndSettle();
      expect(find.text('1,234,567.89'), findsOneWidget);
      await captureUi(tester, 'Fixed Assets Monetary Entered ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
  for (final currency in ['USD', 'JPY']) {
    testWidgets('split asset monetary fields follow $currency precision', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(720, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      Map<String, String> values = {};
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AssetPurchaseFields(
                  ordinaryPopup: true,
                  currencyCode: currency,
                  onChanged: (value) => values = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split Expense / Asset').last);
      await tester.pumpAndSettle();
      for (final label in [
        'Acquisition Cost',
        'Expense Portion',
        'Residual Value',
      ]) {
        final input = find.byKey(ValueKey('asset-purchase-field-$label'));
        expect(inputDecoration(tester, input)?.prefixText, isNull);
        expect(
          inputDecoration(tester, input)?.hintText,
          currency == 'JPY' ? '0' : '0.00',
        );
        expect(
          find.text('$label (${currency == 'JPY' ? '¥' : '\$'})'),
          findsOneWidget,
        );
      }
      expect(values.containsKey('Acquisition Cost'), isFalse);
      expect(
        inputDecoration(
          tester,
          find.byKey(
            const ValueKey('asset-purchase-field-Useful Life In Months'),
          ),
        )?.hintText,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-purchase-field-Acquisition Cost')),
        '1234567',
      );
      await tester.pumpAndSettle();
      expect(values['Acquisition Cost'], '1,234,567');
      // This isolated component verifies formatting only. It is not popout
      // acceptance: the real Home > Expense caller owns the outer insets.
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'popup treatment fills its responsive track without losing choices',
    (tester) async {
      var width = 720.0;
      late StateSetter resize;
      Map<String, String> values = {};
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  resize = setState;
                  return SizedBox(
                    width: width,
                    child: AssetPurchaseFields(
                      ordinaryPopup: true,
                      onChanged: (v) => values = v,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final treatment = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            widget.hintText == 'Select Purchase Treatment',
      );
      expect(tester.getSize(treatment).width, closeTo((width - 20) / 2, .1));
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split Expense / Asset').last);
      await tester.pumpAndSettle();
      expect(values['Purchase Treatment'], 'Split Expense / Asset');
      expect(find.text('Expense Portion (RM)'), findsOneWidget);
      resize(() => width = 350);
      await tester.pumpAndSettle();
      expect(tester.getSize(treatment).width, closeTo(width, .1));
      expect(find.text('Split Expense / Asset'), findsOneWidget);
      final category = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            widget.hintText == 'Select Asset Category',
      );
      expect(tester.getSize(category).width, closeTo(width, .1));
      await tester.tap(find.text('Equipment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Land').last);
      await tester.pumpAndSettle();
      expect(values['Asset Category'], 'Land');
      expect(find.text('Useful Life In Months'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'asset purchase expands inline and land omits depreciation inputs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Map<String, String> values = {};
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssetPurchaseFields(onChanged: (v) => values = v),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asset Purchase').last);
      await tester.pumpAndSettle();
      expect(values['Purchase Treatment'], 'Asset Purchase');
      expect(find.text('Useful Life In Months'), findsOneWidget);
      await tester.tap(find.text('Equipment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Land').last);
      await tester.pumpAndSettle();
      expect(find.text('Useful Life In Months'), findsNothing);
      expect(find.text('Ownership / Registration Reference'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
