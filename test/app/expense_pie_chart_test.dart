import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/widgets/expense_pie_chart.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/core/ids/entity_id.dart';

List<Rect> legendContent(WidgetTester tester, Finder legend) {
  final bounds = <Rect>[];
  for (final element
      in find
          .descendant(of: legend, matching: find.byType(RichText))
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ),
    )) {
      bounds.add(box.toRect().shift(paragraph.localToGlobal(Offset.zero)));
    }
  }
  for (final element
      in find
          .descendant(
            of: legend,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'expense-legend-dot-',
                  ),
            ),
          )
          .evaluate()) {
    final box = element.renderObject! as RenderBox;
    bounds.add(box.localToGlobal(Offset.zero) & box.size);
  }
  return bounds;
}

double circleClearance(Rect circle, Rect content) {
  final nearest = Offset(
    circle.center.dx.clamp(content.left, content.right),
    circle.center.dy.clamp(content.top, content.bottom),
  );
  return (circle.center - nearest).distance - circle.width / 2;
}

void expectBottomClearance(WidgetTester tester, Finder chart, int count) {
  final circle = tester.getRect(
    find.descendant(
      of: chart,
      matching: find.byKey(const ValueKey('expense-pie-circle')),
    ),
  );
  final card = tester.getRect(chart);
  final gaps = [card.bottom - circle.bottom];
  for (var index = 0; index < count; index++) {
    final legend = find.descendant(
      of: chart,
      matching: find.byKey(ValueKey('expense-legend-$index')),
    );
    for (final rect in legendContent(tester, legend)) {
      final gap = circleClearance(circle, rect);
      expect(
        gap,
        greaterThanOrEqualTo(19.9),
        reason: 'Legend content must clear the painted circumference.',
      );
      gaps.add(gap);
    }
  }
  expect(
    gaps.reduce(math.min),
    closeTo(20, 0.1),
    reason:
        'Stop shrinking only at circle-to-legend or circle-to-card clearance.',
  );
}

void main() {
  testWidgets(
    'single-category Home card shrinks into the free bottom corners',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      await workspace.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '6000',
        name: 'Operating Expenses',
        type: AccountType.expense,
      );
      final accounts = {
        for (final a in await workspace.accounts())
          a.account.code: a.account.id,
      };
      final now = DateTime(2026, 9, 30);
      await workspace.saveJournal(
        date: DateTime.utc(now.year, now.month, now.day),
        memo: 'Fictional single-category expense',
        lines: [
          JournalLine.debit(
            accountId: accounts['6000']!,
            amount: Money.fromMinor(10000, 'MYR'),
          ),
          JournalLine.credit(
            accountId: accounts['1000']!,
            amount: Money.fromMinor(10000, 'MYR'),
          ),
        ],
      );
      final journal = (await workspace.journals()).single;
      await workspace.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: workspace.identity.businessId,
          journalId: journal.entry.id,
          expectedRevision: journal.metadata.revision,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now().toUtc(),
        ),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [
        720.0,
        1024.0,
        1080.0,
        1100.0,
        1119.0,
        1120.0,
        1121.0,
        1224.0,
      ]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              asOf: DateTime(2026, 9, 30),
              child: AudytApp(
                key: ValueKey(width),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/home',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chart = find.byType(ExpensePieChart);
        final circle = tester.getRect(
          find.byKey(const ValueKey('expense-pie-circle')),
        );
        final legend = tester.getRect(
          find.byKey(const ValueKey('expense-legend-0')),
        );
        expectBottomClearance(tester, chart, 1);
        if (width == 720 || width == 1024) {
          expect(
            legend.top,
            lessThan(circle.bottom),
            reason:
                'The free curved corners must not retain square-box padding.',
          );
        }
        final ink = legendContent(
          tester,
          find.byKey(const ValueKey('expense-legend-0')),
        ).first;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(Offset(ink.right - 2, ink.center.dy));
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          find.text('Uncategorized · RM 100.00'),
          findsOneWidget,
          reason:
              'Legend tooltip stays reachable in a transparent circle corner.',
        );
        await mouse.removePointer();
        await tester.pumpAndSettle();
        await captureUi(tester, 'Expense Pie Single Category ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('expense-cycle-chart')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('expense-pie-circle')), findsNothing);
        expect(find.text('100.0%'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('expense-cycle-chart')));
        await tester.pumpAndSettle();
        expectBottomClearance(tester, find.byType(ExpensePieChart), 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('wrapped and scaled legends retain circle clearance', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [360.0, 720.0, 1000.0]) {
      for (final scale in [1.0, 1.5]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RepaintBoundary(
                  key: const ValueKey('workspace-capture'),
                  child: ExpensePieChart(
                    amounts: {
                      'Office Supplies & Small Equipment': Money.fromMinor(
                        7000,
                        'MYR',
                      ),
                      'Professional Services With A Long Description':
                          Money.fromMinor(2000, 'MYR'),
                      'Travel': Money.fromMinor(1000, 'MYR'),
                    },
                    total: Money.fromMinor(10000, 'MYR'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expectBottomClearance(tester, find.byType(ExpensePieChart), 3);
        await captureUi(
          tester,
          'Expense Pie Wrapped ${width.toInt()} Scale $scale',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
    'Home pie uses circle clearance above and below through the paired-card break',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
      addTearDown(workspace.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var reachedTop = false;
      for (final width in [
        720.0,
        900.0,
        1024.0,
        1080.0,
        1100.0,
        1119.0,
        1120.0,
        1121.0,
        1224.0,
        1440.0,
      ]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              asOf: DateTime(2026, 9, 30),
              child: AudytApp(
                key: ValueKey(width),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/home',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chart = find.byType(ExpensePieChart);
        final card = tester.getRect(chart);
        final circle = tester.getRect(
          find.byKey(const ValueKey('expense-pie-circle')),
        );
        final title = tester.getRect(
          find.descendant(of: chart, matching: find.text('Expenses')),
        );
        final subtitle = tester.getRect(
          find.descendant(
            of: chart,
            matching: find.text('Expenses by category'),
          ),
        );
        final controls = [
          'expense-cycle-chart',
          'expense-cycle-grouping',
          'expense-cycle-period',
        ].map((key) => tester.getRect(find.byKey(ValueKey(key)))).toList();
        final heading = Rect.fromLTRB(
          title.left,
          title.top,
          subtitle.right > title.right ? subtitle.right : title.right,
          subtitle.bottom,
        );
        expect(circle.width, closeTo(circle.height, 0.1));
        expect(
          circle.width,
          greaterThan(200),
          reason: 'Available corner space should grow the old 200px cap.',
        );
        expect(circle.top - card.top, greaterThanOrEqualTo(20 - 0.1));
        if ((circle.top - card.top - 20).abs() < 0.1) reachedTop = true;
        expect(
          circle.bottom,
          closeTo(heading.bottom + 20 + 200, 0.1),
          reason: 'Preserve the accepted upward-growth geometry.',
        );
        for (final rect in [heading, ...controls]) {
          final expanded = rect.inflate(20);
          final nearest = Offset(
            circle.center.dx.clamp(expanded.left, expanded.right),
            circle.center.dy.clamp(expanded.top, expanded.bottom),
          );
          expect(
            (circle.center - nearest).distance,
            greaterThanOrEqualTo(circle.width / 2 - 0.1),
            reason: 'The painted pie must clear heading/control content.',
          );
        }
        final amounts = tester.widget<ExpensePieChart>(chart).amounts;
        expectBottomClearance(
          tester,
          chart,
          amounts.values.where((amount) => amount.isPositive).length,
        );
        await captureUi(
          tester,
          'Expense Pie Circle Clearance ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      }
      expect(
        reachedTop,
        true,
        reason: 'A wide supported card must reach its 20px top inset.',
      );
    },
  );
  testWidgets('demo category chart reconciles all posted expense movements', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    addTearDown(workspace.dispose);
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    await captureUi(tester, 'Updated Expense Chart');
    if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
      await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
      await tester.pumpAndSettle();
      await captureUi(tester, 'Updated Expense Chart Year');
      await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
      await tester.pumpAndSettle();
    }
    final chart = tester.widget<ExpensePieChart>(find.byType(ExpensePieChart));
    expect(chart.amounts['Rent']!.minorUnits, 120000);
    expect(chart.amounts['Fuel']!.minorUnits, 8000);
    expect(chart.amounts['Office Supplies']!.minorUnits, 37000);
    expect(
      chart.amounts['Office Supplies & Small Equipment']!.minorUnits,
      5000,
    );
    expect(chart.amounts.containsKey('Uncategorized'), isFalse);
    expect(chart.amounts.containsKey('Cost of Sales'), isFalse);
    final home = tester.widget<AccountingHomePage>(
      find.byType(AccountingHomePage),
    );
    for (final month in [true, false]) {
      final now = DateTime(2026, 9, 30);
      final report = await workspace.report(
        from: DateTime.utc(now.year, month ? now.month : 1),
        through: DateTime.utc(now.year, now.month, now.day),
      );
      final expected = report.rows
          .where(
            (row) =>
                row.account.type == AccountType.expense &&
                !row.account.name.toLowerCase().contains('cost of sales'),
          )
          .fold<int>(
            0,
            (sum, row) => sum + (row.periodDebits - row.periodCredits).toInt(),
          );
      for (final grouping in ['Category', 'Payee', 'Account']) {
        final amounts = home.data.expenseAccounts(
          month: month,
          grouping: grouping,
        );
        expect(
          amounts.values.fold<int>(0, (sum, m) => sum + m.minorUnits),
          expected,
          reason:
              '$grouping/$month must reconcile to the same ledger population',
        );
      }
    }
    final legend = List.generate(
      chart.amounts.length,
      (index) => tester.getRect(find.byKey(ValueKey('expense-legend-$index'))),
    );
    expectBottomClearance(
      tester,
      find.byType(ExpensePieChart),
      chart.amounts.length,
    );
    expect(legend[0].left, lessThan(legend[1].left));
    expect(legend[0].top, legend[1].top);
    final dot = tester.getRect(
      find.byKey(const ValueKey('expense-legend-dot-0')),
    );
    expect(
      dot.height,
      closeTo(tester.getRect(find.text('Rent').last).height * 0.9, 2),
    );

    expect(
      chart.amounts.values.fold<int>(0, (sum, m) => sum + m.minorUnits),
      chart.total.minorUnits,
    );
    final recentCard = tester.getRect(
      find.byKey(const ValueKey('recent-expenses-card')),
    );
    final table = tester.widget<Table>(
      find.byKey(const ValueKey('recent-expenses-table')),
    );
    final headerBottom = tester
        .getRect(find.byWidget(table.children.first.children.first))
        .bottom;
    final firstRowTextTop = tester
        .getRect(
          find.byWidget((table.children[1].children.first as Padding).child!),
        )
        .top;
    expect(firstRowTextTop - headerBottom, closeTo(20, 0.1));
    final lastRowBottom = table.children.last.children
        .map(
          (cell) =>
              tester.getRect(find.byWidget((cell as Padding).child!)).bottom,
        )
        .reduce((a, b) => a > b ? a : b);
    expect(recentCard.bottom - lastRowBottom, closeTo(20, 0.1));
    await tester.tap(find.byKey(const ValueKey('expense-cycle-period')));
    await tester.pumpAndSettle();
    final yearChart = tester.widget<ExpensePieChart>(
      find.byType(ExpensePieChart),
    );
    final yearLegend = List.generate(
      yearChart.amounts.values.where((amount) => amount.isPositive).length,
      (index) => tester.getRect(find.byKey(ValueKey('expense-legend-$index'))),
    );
    final yearChartRect = tester.getRect(find.byType(ExpensePieChart));
    for (final item in yearLegend) {
      expect(item.left, greaterThanOrEqualTo(yearChartRect.left - 0.1));
      expect(item.right, lessThanOrEqualTo(yearChartRect.right + 0.1));
    }
    for (var first = 0; first < yearLegend.length; first++) {
      for (var next = first + 1; next < yearLegend.length; next++) {
        final left = yearLegend[first], right = yearLegend[next];
        expect(left.overlaps(right), isFalse);
        if ((left.top - right.top).abs() < 0.1) {
          expect(right.left - left.right, greaterThanOrEqualTo(19.9));
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'shares use exact allocation and do not invent percentages for zero',
    () {
      expect(expensePercentTenths([1, 1, 1]), [334, 333, 333]);
      expect(expensePercentTenths([0, 0]), [0, 0]);
      expect(expensePercentTenths([25, 75]), [250, 750]);
      expect(() => expensePercentTenths([-1, 3]), throwsArgumentError);
    },
  );
  testWidgets('legend uses three content-sized columns when they fit', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(720, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ExpensePieChart(
            amounts: {
              'Rent': Money.fromMinor(5440, 'MYR'),
              'Professional Services': Money.fromMinor(2040, 'MYR'),
              'Travel': Money.fromMinor(1090, 'MYR'),
              'Office Supplies': Money.fromMinor(840, 'MYR'),
              'Fuel': Money.fromMinor(360, 'MYR'),
              'Uncategorized': Money.fromMinor(230, 'MYR'),
            },
            total: Money.fromMinor(10000, 'MYR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getRect(
      find.byKey(const ValueKey('expense-legend-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('expense-legend-1')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('expense-legend-2')),
    );
    expect(first.top, second.top);
    expect(second.top, third.top);
    expect(second.left - first.right, greaterThanOrEqualTo(20));
    expect(third.left - second.right, greaterThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });
  testWidgets('chart fits narrow/wide layouts and discloses credits', (
    tester,
  ) async {
    for (final width in [360.0, 1000.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: ExpensePieChart(
                  amounts: {
                    'Office & Administration': Money.fromMinor(2500, 'MYR'),
                    'Travel': Money.fromMinor(7500, 'MYR'),
                  },
                  total: Money.fromMinor(10000, 'MYR'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('Expenses'));
      final subtitle = tester.getRect(find.text('Expenses by category'));
      expect(subtitle.top - title.bottom, closeTo(6, 0.1));
      expect(find.text('Total Expenses'), findsNothing);
      if (width == 1000) {
        final card = tester.getRect(
          find.ancestor(of: find.text('Expenses'), matching: find.byType(Card)),
        );
        final lastLegend = tester.getRect(
          find.byKey(const ValueKey('expense-legend-1')),
        );
        expectBottomClearance(tester, find.byType(ExpensePieChart), 2);
        expect(card.bottom - lastLegend.bottom, closeTo(20, 0.1));
      }
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ExpensePieChart(
            amounts: {
              'Expense': Money.fromMinor(100, 'MYR'),
              'Credit': Money.fromMinor(-20, 'MYR'),
            },
            total: Money.fromMinor(80, 'MYR'),
          ),
        ),
      ),
    );
    expect(find.textContaining('Net credits'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
