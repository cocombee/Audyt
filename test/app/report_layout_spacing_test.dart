import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [480.0, 960.0]) {
    testWidgets(
      'headed summaries keep the amount on the right axis at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: AccountingSummaryTableCard(
                title: 'Cash Flow',
                description: 'Posted ledger activity',
                labelHeader: 'Cash movement',
                valueHeader: 'Amount',
                rows: const [
                  ('Operating Activities', 'RM 678,320.00'),
                  ('Investing Activities', 'RM 0.00'),
                  ('Financing Activities', 'RM 50,000.00'),
                ],
              ),
            ),
          ),
        );
        final card = tester.getRect(find.byType(Card));
        final leftEdge = card.left + accountingContentInset;
        final rightEdge = card.right - accountingContentInset;
        for (final label in [
          'Cash movement',
          'Operating Activities',
          'Investing Activities',
          'Financing Activities',
        ]) {
          expect(tester.getRect(find.text(label)).left, closeTo(leftEdge, 0.1));
        }
        for (final value in [
          'Amount',
          'RM 678,320.00',
          'RM 0.00',
          'RM 50,000.00',
        ]) {
          expect(
            tester.getRect(find.text(value)).right,
            closeTo(rightEdge, 0.1),
          );
        }
        final first = tester.getRect(find.text('Operating Activities'));
        final heading = tester.getRect(find.text('Cash movement'));
        final second = tester.getRect(find.text('Investing Activities'));
        expect(
          first.top - heading.bottom,
          closeTo(accountingContentInset * 2, 1),
        );
        expect(
          second.top - first.bottom,
          closeTo(accountingUndividedRowVerticalInset * 2, 1),
        );
        expect(
          card.bottom -
              tester.getRect(find.text('Financing Activities')).bottom,
          greaterThan(accountingContentInset),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final title in [
    'Changes In Equity',
    'Payables Ageing',
    'Tax Reconciliation',
    'Management Report Pack',
  ]) {
    testWidgets('$title uses the shared report table and headers', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: FrontendAreaPage(
              area: 'reports',
              title: 'Reports',
              initialPage: title,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final note = tester.getRect(
        find.text(
          'Report layout preview · Figures will come from the ledger after integration.',
        ),
      );
      final firstLabel = title == 'Management Report Pack'
          ? 'Cover Page'
          : title == 'Changes In Equity'
          ? 'Opening Equity'
          : title == 'Payables Ageing'
          ? 'Current'
          : 'Taxable Amount';
      final first = tester.getRect(find.text(firstLabel));
      final card = tester.getRect(
        find.byKey(ValueKey('report-preview-table-$title')),
      );
      final labelHeader = switch (title) {
        'Changes In Equity' => 'Equity movement',
        'Payables Ageing' => 'Ageing bucket',
        'Tax Reconciliation' => 'Tax measure',
        _ => 'Section',
      };
      final header = tester.getRect(find.text(labelHeader));
      expect(note.left - card.left, accountingContentInset);
      expect(header.left, note.left);
      expect(first.left, note.left);
      expect(header.top, greaterThan(note.bottom));
      expect(first.top - header.bottom, closeTo(accountingContentInset * 2, 1));
      expect(find.byType(AccountingSummaryTableCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('equity preview displays posted ledger figures', (tester) async {
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: FrontendAreaPage(
            area: 'reports',
            title: 'Reports',
            initialPage: 'Changes In Equity',
            workspace: workspace,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final table = find.byKey(
      const ValueKey('report-preview-table-Changes In Equity'),
    );
    final report = await workspace.report(
      from: DateTime.utc(1),
      through: DateTime.now(),
    );
    final capital = report.rows
        .firstWhere((row) => row.account.code == '3000')
        .endingNetDebit
        .abs()
        .toInt();
    final capitalLabel = formatAccountingMoney(
      tester.element(table),
      Money.fromMinor(capital, report.currency),
    );
    expect(
      find.descendant(of: table, matching: find.text(capitalLabel)),
      findsOneWidget,
    );
    expect(find.descendant(of: table, matching: find.text('—')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
