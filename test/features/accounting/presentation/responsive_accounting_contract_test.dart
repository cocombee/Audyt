import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the contract width bands at every navigation boundary', () {
    expect(AccountingResponsive.widthBandFor(599), AccountingWidthBand.compact);
    expect(AccountingResponsive.widthBandFor(600), AccountingWidthBand.medium);
    expect(AccountingResponsive.widthBandFor(959), AccountingWidthBand.medium);
    expect(
      AccountingResponsive.widthBandFor(960),
      AccountingWidthBand.expanded,
    );
    expect(
      AccountingResponsive.widthBandFor(1279),
      AccountingWidthBand.expanded,
    );
    expect(AccountingResponsive.widthBandFor(1280), AccountingWidthBand.wide);
    expect(
      AccountingResponsive.navigationModeFor(599),
      AccountingNavigationMode.compactRail,
    );
    expect(
      AccountingResponsive.navigationModeFor(600),
      AccountingNavigationMode.compactRail,
    );
    final expandedRailBoundary =
        AccountingResponsive.extendedRailMinWidth +
        AccountingResponsive.desktopMainContentMinWidth +
        AccountingResponsive.navigationDividerWidth;
    expect(
      AccountingResponsive.navigationModeFor(expandedRailBoundary - 1),
      AccountingNavigationMode.compactRail,
    );
    expect(
      AccountingResponsive.navigationModeFor(expandedRailBoundary),
      AccountingNavigationMode.extendedRail,
    );
    expect(
      AccountingResponsive.navigationModeFor(959),
      AccountingNavigationMode.extendedRail,
    );
    expect(
      AccountingResponsive.navigationModeFor(960),
      AccountingNavigationMode.extendedRail,
    );
    expect(
      AccountingResponsive.navigationModeFor(1280),
      AccountingNavigationMode.extendedRail,
    );
    expect(AccountingResponsive.fitsWithContentGap(499, [240, 240]), isFalse);
    expect(AccountingResponsive.fitsWithContentGap(500, [240, 240]), isTrue);
    expect(
      AccountingResponsive.balancedColumnCount(660, 3, minItemWidth: 220),
      2,
    );
    expect(
      AccountingResponsive.balancedColumnCount(439, 3, minItemWidth: 220),
      1,
    );
  });

  testWidgets('keeps the shell usable across the required viewport matrix', (
    tester,
  ) async {
    const viewports = <Size>[
      Size(320, 568),
      Size(390, 844),
      Size(600, 720),
      Size(768, 1024),
      Size(960, 720),
      Size(1280, 800),
      Size(1366, 768),
    ];

    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final viewport in viewports) {
      await tester.binding.setSurfaceSize(viewport);
      await tester.pumpWidget(const AudytApp());
      await tester.pump();

      final expectedMode = AccountingResponsive.navigationModeFor(
        viewport.width,
      );
      expect(
        find.byKey(const ValueKey('accounting-main-scroll')),
        findsOneWidget,
        reason: 'Missing main scroll at $viewport',
      );
      expect(
        find.byTooltip('Open Accounting Navigation'),
        findsNothing,
        reason: 'Desktop navigation turned into a drawer at $viewport',
      );
      if (expectedMode == AccountingNavigationMode.drawer) {
        expect(
          find.byTooltip('Open Accounting Navigation'),
          findsOneWidget,
          reason: 'Missing Drawer trigger at $viewport',
        );
      } else {
        expect(
          find.byKey(
            ValueKey<String>(
              expectedMode == AccountingNavigationMode.compactRail
                  ? 'accounting-navigation-compact-rail'
                  : 'accounting-navigation-extended-rail',
            ),
          ),
          findsOneWidget,
          reason: 'Wrong navigation mode at $viewport',
        );
      }
      expect(tester.takeException(), isNull, reason: 'Exception at $viewport');
    }
  });

  testWidgets('Home totals split into reminder-style cards before stacking', (
    tester,
  ) async {
    final data = AccountingHomeData.fromExpenses(
      currencyCode: 'MYR',
      asOf: DateTime(2026, 9, 24),
      expenses: [
        AccountingExpense(
          occurredOn: DateTime(2026, 9, 3),
          category: 'Rent',
          amount: Money.fromMinor(151500, 'MYR'),
        ),
      ],
    );
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final (width, compact) in [
      (1280.0, false),
      (900.0, true),
      (390.0, true),
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(home: AccountingHomePage(data: data)),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('home-kpi-strip')),
        compact ? findsNothing : findsOneWidget,
      );
      for (final index in [0, 2]) {
        expect(
          find.byKey(ValueKey('home-kpi-card-$index')),
          compact ? findsOneWidget : findsNothing,
        );
      }
      expect(
        find.byKey(const ValueKey('home-kpi-card-1')),
        compact ? findsOneWidget : findsNothing,
      );
      expect(find.text('All Balance'), findsOneWidget);
      if (width == 900) {
        final first = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-0')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-2')),
        );
        expect(first.top, second.top);
        final balance = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-1')),
        );
        final sst = tester.getRect(find.byKey(const ValueKey('SST Return')));
        final income = tester.getRect(find.byKey(const ValueKey('Income Tax')));
        final annual = tester.getRect(
          find.byKey(const ValueKey('Annual Return')),
        );
        expect(balance.top, sst.top);
        expect(balance.left, lessThan(sst.left));
        expect(income.top, annual.top);
      }
      if (width == 390) {
        final first = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-0')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-2')),
        );
        expect(second.top, greaterThan(first.bottom));
        final balance = tester.getRect(
          find.byKey(const ValueKey('home-kpi-card-1')),
        );
        final sst = tester.getRect(find.byKey(const ValueKey('SST Return')));
        expect(sst.top, greaterThan(balance.bottom));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reminder cards stack before their titles truncate', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final width in [900.0, 600.0, 430.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(body: DemoReminderPanel()),
        ),
      );
      await tester.pump();
      final first = tester.getRect(find.text('SST Return'));
      final second = tester.getRect(find.text('Income Tax'));
      final third = tester.getRect(find.text('Annual Return'));
      if (width == 900) {
        expect(first.top, second.top);
        expect(second.top, third.top);
      } else if (width == 600) {
        expect(first.top, second.top);
        expect(third.top, greaterThan(first.bottom));
      } else {
        expect(second.top, greaterThan(first.bottom));
        expect(third.top, greaterThan(second.bottom));
      }
      for (final title in ['SST Return', 'Income Tax', 'Annual Return']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(title))
              .didExceedMaxLines,
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('collapsed sidebar expands in place without opening a dialog', (
    tester,
  ) async {
    const channel = MethodChannel('audyt/window-layout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    await tester.pump();
    final expandedBrandTop = tester
        .getTopLeft(find.byKey(const ValueKey('accounting-brand-icon-box')))
        .dy;

    await tester.tap(
      find.byKey(const ValueKey('collapse-accounting-navigation')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('accounting-compact-brand-icon-box')),
          )
          .dy,
      closeTo(expandedBrandTop, 0.1),
    );

    await tester.tap(
      find.byKey(const ValueKey('expand-accounting-navigation')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('uses a table only when the resolved Home card can fit it', (
    tester,
  ) async {
    final data = AccountingHomeData.fromExpenses(
      currencyCode: 'USD',
      asOf: DateTime(2026, 8, 30),
      expenses: <AccountingExpense>[
        AccountingExpense(
          occurredOn: DateTime(2026, 8, 29),
          payee: 'A very long localized stationery supplier name',
          category: 'A very long category and account description',
          amount: Money.fromMinor(123456, 'USD'),
        ),
        AccountingExpense(
          occurredOn: DateTime(2026, 8, 28),
          category: 'Utilities',
          amount: Money.fromMinor(-2500, 'USD'),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AccountingHomePage(data: data, includeTopSafeArea: false),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('recent-expenses-stack')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-expenses-table')), findsNothing);
    expect(find.text('No payee'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('recent-expenses-stack')),
        matching: find.text('\$1,234.56'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('recent-expenses-three-column')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recent-expenses-stack')), findsNothing);
    expect(
      find.text('A very long localized stationery supplier name'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stacks recent expenses when the Home card is below table minimum',
    (tester) async {
      final data = AccountingHomeData.fromExpenses(
        currencyCode: 'USD',
        asOf: DateTime(2026, 8, 30),
        expenses: <AccountingExpense>[
          AccountingExpense(
            occurredOn: DateTime(2026, 8, 29),
            payee: 'Stationery shop',
            category: 'Office Operations',
            amount: Money.fromMinor(1250, 'USD'),
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(600, 720));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AccountingHomePage(data: data, includeTopSafeArea: false),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('recent-expenses-three-column')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recent-expenses-table')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('recent-expenses-table')),
        findsOneWidget,
      );
    },
  );

  testWidgets('reflows Home and Record Expense at 200% text scale', (
    tester,
  ) async {
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize / tester.view.devicePixelRatio,
          textScaler: TextScaler.linear(2),
        ),
        child: const MaterialApp(home: AudytApp()),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('accounting-main-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize / tester.view.devicePixelRatio,
          textScaler: TextScaler.linear(2),
        ),
        child: const MaterialApp(home: RecordExpensePage()),
      ),
    );
    await tester.pump();
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.byKey(const ValueKey('record-expense-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps Record Expense scrollable at the 320px floor with keyboard insets',
    (tester) async {
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 568),
            textScaler: TextScaler.linear(2),
            viewPadding: const EdgeInsets.only(bottom: 24),
            viewInsets: const EdgeInsets.only(bottom: 240),
          ),
          child: const MaterialApp(home: RecordExpensePage()),
        ),
      );
      await tester.pump();

      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('accounting-main-scroll')),
      );
      expect((scroll.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(280));
      expect(tester.takeException(), isNull);
    },
  );
}
