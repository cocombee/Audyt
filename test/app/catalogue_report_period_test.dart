import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    for (final title in [
      'Cash Flow',
      'Changes In Equity',
      'Management Report Pack',
    ]) {
      testWidgets('$title applies only valid reviewed periods at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 809));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadJournalLayoutFonts();
        final root = Directory.systemTemp.createTempSync(
          'audyt-report-period-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = await createDemoWorkspace(
          databasePath: '${root.path}/book.sqlite',
        );
        addTearDown(workspace.dispose);
        final before = tables(workspace);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: workspace,
                initialPath: '/reports',
                showInitialSetup: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tap(find.text(title).first);
        final tableFinder = find.byKey(ValueKey('report-preview-table-$title'));
        AccountingSummaryTableCard table() =>
            tester.widget<AccountingSummaryTableCard>(tableFinder);
        final allDatesRows = table().rows.toList();
        final open = find.byKey(const ValueKey('design-open-form'));
        final review = find.byKey(const ValueKey('design-review'));
        Future<void> period(String value) async {
          await tap(find.byKey(const ValueKey('design-field-Period')));
          await tap(find.text(value).last);
        }

        await tap(open);
        await period('This Month');
        expect(
          find.byKey(const ValueKey('design-field-From Date')),
          findsNothing,
        );
        await tap(review);
        final now = DateTime.now();
        final from = DateTime.utc(now.year, now.month);
        final through = DateTime.utc(now.year, now.month, now.day);
        expect(find.text(formatAccountingInputDate(from)), findsOneWidget);
        await captureUi(
          tester,
          'Report Period $title Month Review ${width.toInt()}',
        );
        await tap(review);
        expect(
          table().description,
          'Posted ledger activity · ${formatAccountingInputDate(from)}–${formatAccountingInputDate(through)}',
        );
        final monthRows = table().rows.toList();
        await captureUi(
          tester,
          'Report Period $title Applied Month ${width.toInt()}',
        );

        await tap(open);
        await period('Custom');
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-From Date')),
          '31-02-${now.year + 1}',
        );
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Through Date')),
          '31-01-${now.year + 1}',
        );
        await tap(review);
        expect(
          find.textContaining(
            'Enter valid dates with the start on or before the end.',
          ),
          findsOneWidget,
        );
        expect(table().rows.toList(), monthRows);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('design-field-From Date')),
              )
              .controller!
              .text,
          '31-02-${now.year + 1}',
        );
        await captureUi(
          tester,
          'Report Period $title Invalid Custom ${width.toInt()}',
        );

        final futureFrom = DateTime.utc(now.year + 2);
        final futureThrough = DateTime.utc(now.year + 2, 1, 31);
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-From Date')),
          formatAccountingInputDate(futureFrom),
        );
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Through Date')),
          formatAccountingInputDate(futureThrough),
        );
        await tap(review);
        expect(
          find.text(formatAccountingInputDate(futureFrom)),
          findsOneWidget,
        );
        expect(
          find.text(formatAccountingInputDate(futureThrough)),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Report Period $title Custom Review ${width.toInt()}',
        );
        await tap(review);
        final expected = await workspace.report(
          from: futureFrom,
          through: futureThrough,
        );
        final expectedLabel = title == 'Cash Flow'
            ? 'Net Change In Cash'
            : title == 'Changes In Equity'
            ? 'Profit / Loss'
            : 'Profit And Loss';
        final amount = title == 'Cash Flow'
            ? BigInt.zero
            : expected.periodProfit;
        expect(
          table().rows.singleWhere((row) => row.$1 == expectedLabel).$2,
          formatAccountingMoney(
            tester.element(tableFinder),
            Money.fromMinor(amount.toInt(), workspace.identity.currency),
          ),
        );
        expect(
          table().description,
          'Posted ledger activity · ${formatAccountingInputDate(futureFrom)}–${formatAccountingInputDate(futureThrough)}',
        );
        expect(table().rows.toList(), isNot(allDatesRows));
        await captureUi(
          tester,
          'Report Period $title Applied Future ${width.toInt()}',
        );
        final futureRows = table().rows.toList();

        await tap(open);
        await period('This Quarter');
        await tap(find.byKey(const ValueKey('design-close')));
        await tap(find.text('Keep Editing'));
        expect(find.text('This Quarter'), findsWidgets);
        await tap(find.byKey(const ValueKey('design-close')));
        await tap(find.text('Discard'));
        expect(table().rows.toList(), futureRows);
        expect(tables(workspace), before);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
