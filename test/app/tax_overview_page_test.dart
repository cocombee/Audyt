import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';

import 'journal_workspace_integration_test.dart' show loadJournalLayoutFonts;

import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sales_report_fixture.dart';
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('one title action on every affected live route at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadJournalLayoutFonts();
      final fixture = await salesReportFixture();
      addTearDown(fixture.workspace.dispose);
      final visited = <String>{};
      for (final area in [
        'taxes',
        'expenses-vendors',
        'sales-customers',
        'accounting',
      ]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              key: ValueKey(area),
              workspace: fixture.workspace,
              initialPath: '/$area',
              showInitialSetup: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = tester.widget<AccountingTabs>(
          find.byKey(ValueKey('area-tabs-$area')),
        );
        const affected = {
          'Tax Overview',
          'Tax Codes',
          'Expenses',
          'Claims',
          'Bills',
          'Payment Vouchers',
          'Invoices',
          'Quotations',
          'Deadlines',
          'Chart Of Accounts',
          'Journal Review',
        };
        for (var i = 0; i < tabs.labels.length; i++) {
          final label = tabs.labels[i];
          if (!affected.contains(label)) continue;
          visited.add(label);
          final tab = find.byKey(ValueKey('preview-tab-$area-$i'));
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          final titleRow = find.byKey(
            const ValueKey('accounting-page-title-row'),
          );
          expect(titleRow, findsOneWidget, reason: label);
          final buttons = find.descendant(
            of: titleRow,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(
            buttons,
            findsOneWidget,
            reason: '$label has only its principal action beside its title',
          );
          final button = tester.widget<ButtonStyleButton>(buttons);
          expect(button, isA<FilledButton>(), reason: label);
          expect(
            find.descendant(
              of: buttons,
              matching: find.byType(AccountingButtonIcon),
            ),
            findsNothing,
            reason: '$label title action is text-only',
          );
          final frame = tester.getRect(buttons);
          final rowFrame = tester.getRect(titleRow);
          expect(frame.right, closeTo(rowFrame.right, 0.1), reason: label);
          expect(frame.width, lessThan(rowFrame.width), reason: label);
          final content = tester.getRect(find.byWidget(button.child!));
          expect(
            frame.width,
            closeTo(content.width + accountingContentInset * 2, 0.1),
            reason: label,
          );
          if (button.onPressed != null) {
            expect(
              button.style!.backgroundColor!.resolve({}),
              AccountingTheme.of(tester.element(buttons)).primary,
              reason: label,
            );
          }
          for (final bar in tester.widgetList<AccountingPageFilterBar>(
            find.byType(AccountingPageFilterBar),
          )) {
            for (final secondary in bar.actions) {
              final action = find.byWidget(secondary);
              expect(
                tester.getTopLeft(action).dy,
                greaterThanOrEqualTo(
                  tester.getBottomLeft(titleRow).dy +
                      accountingContentInset -
                      0.1,
                ),
              );
              final button = find
                  .descendant(
                    of: action,
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first;
              expect(tester.widget(button), isA<OutlinedButton>());
            }
          }
          await captureUi(
            tester,
            'Single Title Action $label ${width.toInt()}',
          );
          expect(tester.takeException(), isNull, reason: label);
        }
      }
      expect(
        visited,
        hasLength(11),
        reason: 'All eleven affected live route owners must be visited',
      );
    });
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'real Tax Overview route, period, source and account trace are read-only at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = await salesReportFixture();
        final w = fixture.workspace;
        addTearDown(w.dispose);
        final code = w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '8',
            effectiveFrom: DateTime.utc(2026),
            application: TaxApplication.both,
            accountId: fixture.tax,
          ),
        );
        final invoice = Invoice.draft(
          id: EntityId.random(),
          customerId: fixture.customer.id,
          documentNumber: 'INV-TAX-1',
          issueDate: DateTime.utc(2026, 9, 1),
          taxMode: 'Exclusive',
          lines: [
            SalesLineItem.category(
              id: EntityId.random(),
              categoryId: fixture.income,
              description: 'Reviewed service',
              quantity: SalesQuantity.fromInt(1),
              rate: Money.fromMinor(10000, 'MYR'),
              taxRatePercent: code.percent,
              taxSnapshot: code,
            ),
          ],
        );
        w.saveInvoiceDraft(
          invoice,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 2),
        );
        w.postInvoice(
          requestId: EntityId.random(),
          invoiceId: invoice.id,
          expectedRevision: 1,
          expectedCustomerRevision: fixture.customer.metadata.revision,
          documentNumber: invoice.documentNumber,
          receivableAccountId: fixture.receivable,
          incomeAccountId: fixture.income,
          taxAccountId: fixture.tax,
          approvedAt: DateTime.utc(2026, 9, 3),
        );
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final before = tables(w);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: w,
              initialPath: '/taxes',
              showInitialSetup: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TaxOverviewPage), findsOneWidget);
        expect(
          find.text(
            'Explore this accounting workflow before backend approval.',
          ),
          findsNothing,
        );
        await tester.enterText(
          find.byKey(const ValueKey('tax-overview-from')),
          '01-09-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('tax-overview-through')),
          '30-09-2026',
        );
        await tester.tap(find.byKey(const ValueKey('tax-overview-run')));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSummaryTableCard &&
                widget.title == 'Book Tax Activity',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await captureUi(tester, 'Tax Overview ${width.toInt()}');
        final report = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(report.salesTax, BigInt.from(800));
        final source = report.rows.singleWhere((r) => r.code != null);
        final view = find.byKey(
          ValueKey(
            'tax-source-view-${source.journalId.value}-${source.lineId}',
          ),
        );
        await tester.ensureVisible(view);
        await tester.tap(view);
        await tester.pumpAndSettle();
        expect(find.byType(AccountingInformationRows), findsOneWidget);
        expect(find.text(source.journalId.value), findsOneWidget);
        expect(
          find.text(
            'SST filing, relief and remittances require separate review.',
          ),
          findsNothing,
        );
        expect(find.text('Save'), findsNothing);
        await captureUi(tester, 'Tax Source Details ${width.toInt()}');
        await tester.tap(accountingCloseIcon());
        await tester.pumpAndSettle();
        final accountView = find.byKey(
          ValueKey('tax-account-view-${fixture.tax.value}'),
        );
        await tester.ensureVisible(accountView);
        await tester.tap(accountView);
        await tester.pumpAndSettle();
        expect(find.text('Opening Balance'), findsOneWidget);
        expect(find.text('Closing Balance'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(accountingCloseIcon());
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tax-overview-from')),
          '31-10-2026',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('tax-overview-run')),
        );
        await tester.tap(find.byKey(const ValueKey('tax-overview-run')));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter valid dates with the start on or before the end.'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('tax-overview-refresh')),
        );
        await tester.tap(find.byKey(const ValueKey('tax-overview-refresh')));
        await tester.pumpAndSettle();
        expect(
          find.text('01-09-2026 – 30-09-2026'),
          findsWidgets,
          reason: 'Refresh keeps the applied range.',
        );
        expect(tables(w), before);
        expect(tester.takeException(), isNull);
        await Scrollable.ensureVisible(
          tester.element(find.text('No recorded tax payments.')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Tax Payments Empty ${width.toInt()}');
        await tester.ensureVisible(
          find.byKey(const ValueKey('tax-overview-from')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('tax-overview-from')),
          '01-10-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('tax-overview-through')),
          '31-10-2026',
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const ValueKey('tax-overview-run'))),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tax-overview-run')));
        await tester.pumpAndSettle();
        final emptySource = find.text(
          'No posted source tax activity in this period.',
        );
        expect(emptySource, findsOneWidget);
        await tester.ensureVisible(emptySource);
        await tester.pumpAndSettle();
        await captureUi(tester, 'Tax Source Activity Empty ${width.toInt()}');
        expect(tables(w), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
