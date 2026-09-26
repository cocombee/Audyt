import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final height in [600.0, 1100.0]) {
      testWidgets('actual saved Tax Code facts fit at $width by $height', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadJournalLayoutFonts();
        final w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
        addTearDown(w.dispose);
        await w.createAccount(
          code: '2200',
          name: 'Tax Payable',
          type: AccountType.liability,
        );
        final account = (await w.accounts())
            .singleWhere((r) => r.account.code == '2200')
            .account;
        w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '8',
            effectiveFrom: DateTime(2026, 1, 1),
            application: TaxApplication.both,
            accountId: account.id,
          ),
        );
        final saved = w.taxRates.single;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: TaxRatesPage(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('tax-rate-view-${saved.id.value}')),
        );
        await tester.pumpAndSettle();
        for (final value in [
          '01-01-2026',
          'Sales & Purchases',
          'Unassigned Agency',
        ]) {
          final text = find.descendant(
            of: find.byType(AccountingInformationRows),
            matching: find.text(value),
          );
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: paragraph.size.width);
          expect(painter.computeLineMetrics(), hasLength(1), reason: value);
          painter.dispose();
        }
        expect(
          find.byKey(const ValueKey('accounting-form-dialog-footer')),
          findsNothing,
        );
        await captureUi(
          tester,
          'Tax Code Saved Facts ${width.toInt()} ${height.toInt()}',
        );
        final close = find
            .ancestor(
              of: find.byType(AccountingCloseIcon),
              matching: find.byType(IconButton),
            )
            .first;
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(w.taxRates.single.toJson(), saved.toJson());
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Tax Codes add, edit and cancel use saved owner at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
        addTearDown(w.dispose);
        await w.createAccount(
          code: '2200',
          name: 'Tax Payable',
          type: AccountType.liability,
        );
        final account = (await w.accounts())
            .singleWhere((r) => r.account.code == '2200')
            .account;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: TaxRatesPage(workspace: w)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordPagination), findsNothing);
        await tester.tap(find.byKey(const ValueKey('tax-rate-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Name')),
          'Service Tax',
        );
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Rate (%)')),
          '8',
        );
        await tester.tap(
          find.byKey(const ValueKey('design-field-Tax Account')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(account.displayName).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(w.taxRates.single.percent, '8');
        final saved = w.taxRates.single;
        await tester.tap(
          find.byKey(ValueKey('tax-rate-edit-${saved.id.value}')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Rate (%)')),
          '9',
        );
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-discard-changes')));
        await tester.pumpAndSettle();
        expect(w.taxRates.single.revision, 1);
        await tester.tap(
          find.byKey(ValueKey('tax-rate-edit-${saved.id.value}')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Rate (%)')),
          '9',
        );
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(w.taxRates.single.revision, 2);
        expect(w.taxRates.single.percent, '9');
        // A name and percentage typed in the actual Tax Codes page feed the
        // operational transaction row; there is no separate tax-option list.
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: RecordExpensePage(settingsWorkspace: w)),
          ),
        );
        await tester.pumpAndSettle();
        final inlineTax = tester
            .widgetList<AccountingSelector<String>>(
              find.byWidgetPredicate(
                (v) =>
                    v is AccountingSelector<String> &&
                    (v.triggerKey as ValueKey?)?.value.toString().endsWith(
                          '-tax',
                        ) ==
                        true,
              ),
            )
            .single;
        expect(
          inlineTax.options.any(
            (o) =>
                o.value == w.taxRates.single.choice &&
                o.label == w.taxRates.single.label,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
