import 'dart:math' as math;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/expense_pie_chart.dart';
import 'package:audyt/features/accounting/presentation/widgets/sales_profit_chart.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quarter includes July through September and cost-only days', () {
    final points = salesTrendPoints(
      activities: [
        SalesTrendActivity(date: DateTime.utc(2026, 7, 2), costMinor: 1500),
        SalesTrendActivity(
          date: DateTime.utc(2026, 8, 14),
          invoicedMinor: 8000,
        ),
        SalesTrendActivity(date: DateTime.utc(2026, 9, 9), invoicedMinor: 9000),
      ],
      asOf: DateTime.utc(2026, 9, 25),
      period: SalesTrendPeriod.quarterly,
      receivedSales: false,
      allCosts: true,
    );
    expect(points.first.date, DateTime.utc(2026, 7, 2));
    expect(points.last.date, DateTime.utc(2026, 9, 9));
    expect(points.fold<int>(0, (sum, day) => sum + day.salesMinor), 17000);
    expect(points.fold<int>(0, (sum, day) => sum + day.costMinor), 1500);
    expect(
      salesTrendDisplayPoints(points).first.date,
      DateTime.utc(2026, 7, 2),
    );
  });

  test('each selected range plots from its first to last recorded entry', () {
    final activities = [
      SalesTrendActivity(date: DateTime.utc(2026, 3, 2), invoicedMinor: 100),
      SalesTrendActivity(date: DateTime.utc(2026, 8, 30), invoicedMinor: 200),
      SalesTrendActivity(date: DateTime.utc(2026, 9, 24), costMinor: 50),
    ];
    for (final (period, expectedFirst) in [
      (SalesTrendPeriod.quarterly, DateTime.utc(2026, 8, 30)),
      (SalesTrendPeriod.sixMonths, DateTime.utc(2026, 8, 30)),
      (SalesTrendPeriod.yearly, DateTime.utc(2026, 3, 2)),
    ]) {
      final points = salesTrendPoints(
        activities: activities,
        asOf: DateTime.utc(2026, 9, 25),
        period: period,
        receivedSales: false,
        allCosts: true,
      );
      expect(points.first.date, expectedFirst, reason: period.name);
      expect(points.first.salesMinor, greaterThan(0), reason: period.name);
      expect(points.last.date, DateTime.utc(2026, 9, 24), reason: period.name);
      expect(points.last.costMinor, 50, reason: period.name);
    }
  });

  test('trend buckets use actual movements and independent series modes', () {
    final activities = [
      SalesTrendActivity(
        date: DateTime.utc(2026, 8, 1),
        invoicedMinor: 10000,
        receivedMinor: 7000,
        costMinor: 3000,
        directCostMinor: 1000,
        invoiceCount: 1,
        receiptCount: 1,
      ),
      SalesTrendActivity(
        date: DateTime.utc(2026, 9, 5),
        invoicedMinor: 20000,
        receivedMinor: 9000,
        costMinor: 5000,
        directCostMinor: 2000,
        invoiceCount: 2,
        receiptCount: 1,
      ),
    ];
    final monthly = salesTrendPoints(
      activities: activities,
      asOf: DateTime.utc(2026, 9, 25),
      period: SalesTrendPeriod.monthly,
      receivedSales: false,
      allCosts: true,
    );
    expect(monthly.first.label, '5 Sep 2026');
    expect(monthly.last.label, '5 Sep 2026');
    expect(monthly.first.salesMinor, 20000);
    final monthlySale = monthly.singleWhere(
      (point) => point.date == DateTime.utc(2026, 9, 5),
    );
    expect(monthlySale.salesMinor, 20000);
    expect(monthlySale.costMinor, 5000);
    expect(monthlySale.profitMinor, 15000);
    expect(monthlySale.saleCount, 2);
    final received = salesTrendPoints(
      activities: activities,
      asOf: DateTime.utc(2026, 9, 25),
      period: SalesTrendPeriod.monthly,
      receivedSales: true,
      allCosts: false,
    );
    final receivedSale = received.singleWhere(
      (point) => point.date == DateTime.utc(2026, 9, 5),
    );
    expect(receivedSale.salesMinor, 9000);
    expect(receivedSale.costMinor, 2000);
    expect(receivedSale.saleCount, 1);
    final quarter = salesTrendPoints(
      activities: activities,
      asOf: DateTime.utc(2026, 9, 25),
      period: SalesTrendPeriod.quarterly,
      receivedSales: false,
      allCosts: true,
    );
    expect(quarter.first.label, '1 Aug 2026');
    expect(quarter.last.label, '5 Sep 2026');
    expect(quarter.fold<int>(0, (sum, day) => sum + day.salesMinor), 30000);
    expect(quarter.fold<int>(0, (sum, day) => sum + day.costMinor), 8000);
    final year = salesTrendPoints(
      activities: activities,
      asOf: DateTime.utc(2026, 9, 25),
      period: SalesTrendPeriod.yearly,
      receivedSales: false,
      allCosts: true,
    );
    expect(year.first.label, '1 Aug 2026');
    expect(year.last.label, '5 Sep 2026');
    final saleDate = DateTime.utc(2026, 8, 1);
    expect(
      salesTrendDateFraction(
        DateTime.utc(2026, 9, 5),
        monthly.first.date,
        monthly.last.date,
      ),
      0.5,
    );
    expect(
      salesTrendDateFraction(saleDate, quarter.first.date, quarter.last.date),
      0,
    );
    expect(
      salesTrendDateFraction(saleDate, year.first.date, year.last.date),
      0,
    );
    expect(
      salesTrendDateFraction(year.last.date, year.first.date, year.last.date),
      1,
    );
    final now = DateTime(2026, 9, 30);
    final future = DateTime.utc(now.year + 2, 1, 1);
    final bounded = salesTrendPoints(
      activities: [
        SalesTrendActivity(date: now, invoicedMinor: 100),
        SalesTrendActivity(date: future, invoicedMinor: 900),
      ],
      asOf: future,
      period: SalesTrendPeriod.yearly,
      receivedSales: false,
      allCosts: true,
    );
    expect(bounded.last.date.isBefore(future), isTrue);
    expect(bounded.fold<int>(0, (sum, day) => sum + day.salesMinor), 100);
  });

  testWidgets(
    'two chart cards and all six cycling controls use the real demo',
    (tester) async {
      final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
      addTearDown(workspace.dispose);
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: WorkspaceAccountingHome(
              asOf: DateTime(2026, 9, 30),
              workspace: workspace,
              includeTopSafeArea: false,
              onRecordExpense: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingIcon>(
              find.descendant(
                of: find.byKey(const ValueKey('expense-cycle-grouping')),
                matching: find.byType(AccountingIcon),
              ),
            )
            .icon,
        Icons.category_outlined,
      );
      final expenseCard = tester.getRect(
        find
            .ancestor(
              of: find.text('Expenses').first,
              matching: find.byType(Card),
            )
            .first,
      );
      final salesCard = tester.getRect(
        find
            .ancestor(
              of: find.text('Sales & Profit'),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(expenseCard.top, salesCard.top);
      expect(expenseCard.height, closeTo(salesCard.height, 0.1));
      expect(salesCard.left - expenseCard.right, accountingContentInset);
      expect(expenseCard.width, closeTo(salesCard.width, 0.1));
      expect(
        tester.getRect(find.byKey(const ValueKey('expense-cycle-chart'))).top -
            expenseCard.top,
        closeTo(accountingContentInset, 0.1),
      );
      expect(
        tester
                .getRect(find.byKey(const ValueKey('sales-chart-sales-mode')))
                .top -
            salesCard.top,
        closeTo(accountingContentInset, 0.1),
      );
      final plotBounds = tester.getRect(
        find.byKey(const ValueKey('sales-profit-plot')),
      );
      final axisLabel = TextPainter(
        text: const TextSpan(
          text: '1 Sep',
          style: TextStyle(fontSize: 10, fontFamily: 'Inter'),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final axisBottom =
          plotBounds.top +
          salesTrendPlotRect(plotBounds.size).bottom +
          7 +
          axisLabel.height;
      axisLabel.dispose();
      expect(salesCard.bottom - axisBottom, closeTo(accountingContentInset, 2));
      final chart = tester.widget<SalesProfitChart>(
        find.byType(SalesProfitChart),
      );
      final report = await workspace.report(
        from: DateTime.utc(
          DateTime(2026, 9, 30).year,
          DateTime(2026, 9, 30).month,
        ),
        through: DateTime(2026, 9, 30),
      );
      final points = salesTrendPoints(
        activities: chart.activities,
        asOf: chart.asOf,
        period: SalesTrendPeriod.monthly,
        receivedSales: false,
        allCosts: true,
      );
      expect(
        points.fold<int>(0, (sum, day) => sum + day.salesMinor),
        report.revenue.toInt(),
      );
      expect(
        points.fold<int>(0, (sum, day) => sum + day.costMinor),
        report.expenses.toInt(),
      );
      if (DateTime(2026, 9, 30).day >= 9) {
        final tradingDays = points.where((point) => point.salesMinor > 0);
        expect(tradingDays.length, greaterThanOrEqualTo(5));
        expect(tradingDays.where((point) => point.profitMinor < 0).length, 2);
        expect(
          tradingDays.where((point) => point.profitMinor > 0).length,
          greaterThan(2),
        );
      }

      await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
      await tester.pumpAndSettle();
      expect(find.text('This Year'), findsOneWidget);
      final homeData = tester
          .widget<AccountingHomePage>(find.byType(AccountingHomePage))
          .data;
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-kpi-This Year')),
          matching: find.text(
            formatAccountingMoney(
              tester.element(find.byType(AccountingHomePage)),
              homeData.salesThisYear,
            ),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-cycle-grouping')));
      await tester.pumpAndSettle();
      expect(find.text('Expenses by payee'), findsOneWidget);
      expect(
        tester
            .widget<AccountingIcon>(
              find.descendant(
                of: find.byKey(const ValueKey('expense-cycle-grouping')),
                matching: find.byType(AccountingIcon),
              ),
            )
            .icon,
        Icons.person_outline,
      );
      await tester.tap(find.byKey(const ValueKey('expense-cycle-chart')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-pie-circle')), findsNothing);
      final barCard = find
          .ancestor(
            of: find.text('Expenses').first,
            matching: find.byType(Card),
          )
          .first;
      final bars = find.descendant(
        of: barCard,
        matching: find.byType(AccountingProgressBar),
      );
      final postedPayees = homeData
          .expenseAccounts(month: true, grouping: 'Payee')
          .entries
          .where((entry) => !entry.value.isZero)
          .toList();
      expect(postedPayees, isNotEmpty);
      expect(bars, findsNWidgets(postedPayees.length));
      for (final payee in postedPayees) {
        expect(
          find.descendant(of: barCard, matching: find.text(payee.key)),
          findsOneWidget,
        );
      }
      expect(
        tester.getRect(barCard).bottom - tester.getRect(bars.last).bottom,
        closeTo(accountingContentInset, 2),
      );
      expect(
        tester.getRect(barCard).height,
        closeTo(
          tester
              .getRect(
                find
                    .ancestor(
                      of: find.text('Sales & Profit'),
                      matching: find.byType(Card),
                    )
                    .first,
              )
              .height,
          0.1,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sales-chart-sales-mode')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SalesProfitChart>(find.byType(SalesProfitChart))
            .receivedSales,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('sales-chart-cost-mode')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SalesProfitChart>(find.byType(SalesProfitChart)).allCosts,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('sales-chart-period')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SalesProfitChart>(find.byType(SalesProfitChart)).period,
        SalesTrendPeriod.quarterly,
      );
      final activeChart = tester.widget<SalesProfitChart>(
        find.byType(SalesProfitChart),
      );
      final activePoints = salesTrendPoints(
        activities: activeChart.activities,
        asOf: activeChart.asOf,
        period: activeChart.period,
        receivedSales: activeChart.receivedSales,
        allCosts: activeChart.allCosts,
      );
      final displayPoints = salesTrendDisplayPoints(activePoints);
      expect(displayPoints, isNotEmpty);
      expect(
        displayPoints.every(
          (point) => point.salesMinor != 0 || point.costMinor != 0,
        ),
        isTrue,
      );
      final dayIndex = displayPoints.lastIndexWhere(
        (point) => point.salesMinor != 0,
      );
      expect(dayIndex, greaterThanOrEqualTo(0));
      final values = [
        for (final point in displayPoints) ...[
          point.salesMinor,
          point.costMinor,
        ],
      ];
      final low = math.min(0, values.reduce(math.min));
      final high = math.max(1, values.reduce(math.max));
      final plot = tester.getRect(
        find.byKey(const ValueKey('sales-profit-plot')),
      );
      final drawing = salesTrendPlotRect(plot.size);
      final linePoint = Offset(
        plot.left +
            drawing.left +
            drawing.width *
                salesTrendDateFraction(
                  displayPoints[dayIndex].date,
                  activePoints.first.date,
                  activePoints.last.date,
                ),
        plot.top +
            drawing.top +
            drawing.height *
                (1 - (displayPoints[dayIndex].salesMinor - low) / (high - low)),
      );
      await tester.tapAt(linePoint);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sales-profit-point-tooltip')),
        findsOneWidget,
      );
      final tooltip = find.byKey(const ValueKey('sales-profit-point-tooltip'));
      expect(
        find.descendant(of: tooltip, matching: find.byType(Text)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: tooltip,
          matching: find.textContaining('Received sales'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tooltip,
          matching: find.textContaining('Direct costs'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tooltip, matching: find.textContaining('receipts')),
        findsNothing,
      );
      final blankIndex = activePoints.indexWhere(
        (point) => point.salesMinor == 0,
      );
      expect(blankIndex, greaterThanOrEqualTo(0));
      await tester.tapAt(Offset(plot.left + plot.width / 2, plot.bottom - 32));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sales-profit-point-tooltip')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: WorkspaceAccountingHome(
              asOf: DateTime(2026, 9, 30),
              workspace: workspace,
              includeTopSafeArea: false,
              onRecordExpense: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expenses by payee'), findsOneWidget);
      expect(find.text('This Year'), findsOneWidget);
      expect(
        tester.widget<ExpensePieChart>(find.byType(ExpensePieChart)).barChart,
        isTrue,
      );
      final remembered = tester.widget<SalesProfitChart>(
        find.byType(SalesProfitChart),
      );
      expect(remembered.receivedSales, isTrue);
      expect(remembered.allCosts, isFalse);
      expect(remembered.period, SalesTrendPeriod.quarterly);
    },
  );
}
