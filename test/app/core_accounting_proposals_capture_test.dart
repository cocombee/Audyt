// Isolated fictional evidence rendered from the current operational routes and editors.
// Page/list/report/popout styling remains owned by the production components.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:audyt/features/accounting/presentation/ledger_reports_page.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/accounting/presentation/recurring_transactions_dialog.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';

import '../support/sales_report_fixture.dart';

import '../support/accounting_test_finders.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('proposal-capture');
Widget _taxRates(BuildContext context, AccountingWorkspace workspace) =>
    FrontendAreaPage(
      area: 'taxes',
      title: 'Tax',
      existingLabel: 'Deadlines',
      existing: const SizedBox.shrink(),
      initialPage: 'Tax Codes',
      extraPages: {'Tax Codes': TaxRatesPage(workspace: workspace)},
    );
Widget _recurring(BuildContext context, AccountingWorkspace workspace) =>
    RecurringTransactionsDialog(workspace: workspace);

// Use the current operational Ledger Reports page, never a copied report shell.
Widget _sales(BuildContext context, AccountingWorkspace workspace) =>
    FrontendAreaPage(
      area: 'reports',
      title: 'Reports',
      existingLabel: 'Ledger Reports',
      existing: LedgerReportsPage(workspace: workspace, compact: true),
    );

Future<void> _selectSales(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('report-from')),
    '01-01-2026',
  );
  await tester.enterText(
    find.byKey(const ValueKey('report-through')),
    '30-09-2026',
  );
  await tester.tap(find.byKey(const ValueKey('run-report')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Sales'));
  await tester.tap(find.text('Sales'));
  await tester.pumpAndSettle();
}

void main() {
  test('sales shares preserve exact large totals and show zero/negative periods honestly', () {
    final scale = BigInt.parse('1000000000000000000000000000000');
    final share = AccountingReportQualityMeasure.salesShare(
      'Video',
      scale * BigInt.from(73),
      scale * BigInt.from(100),
    );
    expect(share.display, '73%');
    expect(share.fraction, closeTo(0.73, 0.000001));
    expect(
      AccountingReportQualityMeasure.salesShare(
        'Returns',
        -scale,
        scale,
      ).display,
      '-100%',
    );
    expect(
      AccountingReportQualityMeasure.salesShare(
        'Returns',
        -scale,
        scale,
      ).fraction,
      0,
    );
    expect(
      AccountingReportQualityMeasure.salesShare(
        'Video',
        scale,
        BigInt.zero,
      ).display,
      '—',
    );
    expect(
      AccountingReportQualityMeasure.salesShare(
        'Video',
        -scale,
        -scale,
      ).display,
      '—',
    );
  });
  for (final width in [720.0, 1124.0]) {
    testWidgets(
      'recurring amounts stay above action icons at $width without a page wrapper',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final workspace = await createDemoWorkspace(
          asOf: DateTime(2026, 9, 30),
          includeRowReview: true,
        );
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => _recurring(context, workspace),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final visible = workspace.database
            .documentSchedules(workspace.identity.businessId)
            .take(5);
        for (final item in visible) {
          final row = find.ancestor(
            of: find.text(item.name),
            matching: find.byType(AccountingRecordRow),
          );
          final price = tester.getRect(
            find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Text && widget.data?.startsWith('RM ') == true,
              ),
            ),
          );
          final view = tester.getRect(find.byTooltip('View ${item.name}'));
          final edit = tester.getRect(find.byTooltip('Edit ${item.name}'));
          expect(
            view.top - price.bottom,
            closeTo(accountingRecordPriceActionGap, 0.1),
          );
          expect(edit.top, view.top);
          expect(edit.right, closeTo(price.right, 0.1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [620.0, 1124.0]) {
    testWidgets('Sales keeps percentages above values and opens items at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width + 100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await salesReportFixture();
      final workspace = fixture.workspace;
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 100),
                Expanded(
                  child: Builder(
                    builder: (context) => _sales(context, workspace),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectSales(tester);
      for (final title in [
        'Posted Journals',
        'Pending Drafts',
        'Accounts Tracked',
        'Needs Review',
      ]) {
        final texts = find.descendant(
          of: find.byKey(ValueKey('report-summary-$title')),
          matching: find.byType(Text),
        );
        for (final element in texts.evaluate()) {
          final richText = find.descendant(
            of: find.byElementPredicate(
              (candidate) => identical(candidate, element),
            ),
            matching: find.byType(RichText),
          );
          expect(
            tester.renderObject<RenderParagraph>(richText).didExceedMaxLines,
            isFalse,
          );
        }
      }
      expect(find.text('Cash Flow'), findsOneWidget);
      expect(find.text('Changes In Equity'), findsOneWidget);
      expect(find.text('Tax Reconciliation'), findsOneWidget);
      expect(find.text('Group By'), findsNothing);
      expect(find.text('Sales By Item / Category'), findsNothing);
      final card = tester.getRect(
        find.byKey(const ValueKey('report-quality-card')),
      );
      final category = find.byKey(
        ValueKey(
          'sales-category-${workspace.catalogueCategories.singleWhere((c) => c.name == 'Video').id.value}',
        ),
      );
      expect(tester.getRect(category).top, greaterThan(card.bottom));
      if (width == 1124) {
        final selector = tester.getRect(
          find.byKey(const ValueKey('report-view-selector')),
        );
        expect(card.bottom, greaterThanOrEqualTo(selector.bottom));
        final label = tester.getRect(find.text('Sales'));
        expect(label.bottom, lessThanOrEqualTo(card.bottom));
      }
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(find.text('Corporate Video'), findsOneWidget);
      expect(find.text('Event Video'), findsOneWidget);
      expect(find.text('RM 12,000.00'), findsOneWidget);
      await tester.tap(find.text('Corporate Video'));
      await tester.pumpAndSettle();
      expect(find.text('Source ID'), findsOneWidget);
      expect(find.text('Invoice'), findsOneWidget);
      expect(
        find.text(
          workspace.invoiceDrafts().isEmpty
              ? fixture.invoices.first.id.value
              : 'unexpected draft',
        ),
        findsOneWidget,
      );
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      await tester.tap(accountingCloseIcon());
      await tester.pumpAndSettle();
      expect(find.text('Corporate Video'), findsNothing);
      expect(
        find.byKey(
          ValueKey(
            'sales-category-${workspace.catalogueCategories.singleWhere((c) => c.name == 'Video').id.value}',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('render core proposals with accepted component owners', (
    tester,
  ) async {
    final output = Platform.environment['AUDYT_PROPOSAL_CAPTURE'];
    if (output == null) return;
    await tester.runAsync(() async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await Directory(output).create(recursive: true);
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = await tester.runAsync(salesReportFixture);
    final workspace = fixture!.workspace;
    addTearDown(workspace.dispose);
    final reviewWorkspace = await createDemoWorkspace(
      asOf: DateTime(2026, 9, 30),
      includeRowReview: true,
    );
    addTearDown(reviewWorkspace.dispose);
    final taxEditor = await taxRateEditor(
      reviewWorkspace,
      reviewWorkspace.taxRates.first,
    );
    final scheduleEditor = recurringScheduleEditor(
      reviewWorkspace,
      reviewWorkspace.database
          .documentSchedules(reviewWorkspace.identity.businessId)
          .first
          .kind,
      original: reviewWorkspace.database
          .documentSchedules(reviewWorkspace.identity.businessId)
          .first,
    );
    final views = <String, Widget Function(BuildContext)>{
      'Proposed Tax Rates': (context) => _taxRates(context, reviewWorkspace),
      'Proposed Recurring Transactions': (context) =>
          _recurring(context, reviewWorkspace),
      'Proposed Sales By Category': (context) => _sales(context, workspace),
      'Proposed Sales By Item': (context) => _sales(context, workspace),
      'Proposed Tax Rate Editor': (context) => taxEditor,
      'Proposed Recurring Schedule': (context) => scheduleEditor,
    };
    for (final entry in views.entries) {
      final editor =
          entry.key.endsWith('Editor') || entry.key.endsWith('Schedule');
      final manager =
          entry.key == 'Proposed Recurring Transactions' ||
          entry.key == 'Proposed Sales By Item';
      for (final width
          in editor
              ? [848.0]
              : manager
              ? [1124.0, 720.0]
              : [1124.0, 620.0]) {
        debugPrint('Rendering ${entry.key} at $width');
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: Builder(builder: entry.value)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (entry.key.startsWith('Proposed Sales')) {
          await _selectSales(tester);
          if (entry.key == 'Proposed Sales By Item') {
            await tester.ensureVisible(find.text('Video').last);
            await tester.tap(find.text('Video').last);
            await tester.pumpAndSettle();
          }
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} at $width',
        );
        final headerAction = find.byKey(
          const ValueKey('proposal-header-action'),
        );
        if (headerAction.evaluate().isNotEmpty) {
          final header = tester.getRect(find.byType(AccountingPageHeader));
          final button = tester.getRect(headerAction);
          expect(button.right, lessThanOrEqualTo(header.right + 0.01));
          expect(button.left, greaterThanOrEqualTo(header.left - 0.01));
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_captureKey),
        );
        final suffix = width == 620
            ? ' Minimum Content'
            : width == 720
            ? ' Minimum Desktop'
            : '';
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/${entry.key}$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
