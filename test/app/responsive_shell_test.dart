import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;

void main() {
  for (final width in [720.0, 1162.0, 1224.0, 2056.0]) {
    for (final path in [
      '/home',
      '/expenses-vendors',
      '/banking',
      '/accounting',
      '/reports',
    ]) {
      testWidgets('actual $path keeps date tabs and body together at $width', (
        t,
      ) async {
        await prepare(t, width);
        t.view.physicalSize = Size(width, 809);
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(initialPath: path, workspace: workspace),
          ),
        );
        await t.pumpAndSettle();
        final shell = t.widget<AccountingPageShell>(
          find.byType(AccountingPageShell),
        );
        final viewport = t.getRect(
          find.byKey(const ValueKey('accounting-main-scroll')),
        );
        final content = t.getRect(find.byWidget(shell.child));
        final inset = AccountingResponsive.pageInsetFor(width);
        final expectedWidth = (viewport.width - inset * 2).clamp(
          0.0,
          AccountingResponsive.pageMaxWidth,
        );
        expect(content.width, closeTo(expectedWidth, .1));
        expect(
          content.left - viewport.left,
          closeTo(viewport.right - content.right, .1),
        );
        final date = t.getRect(find.byKey(const ValueKey('global-date-box')));
        final topBar = t.getRect(find.byKey(const ValueKey('global-top-bar')));
        expect(date.left, closeTo(content.left, .1));
        expect(topBar.left, closeTo(content.left, .1));
        expect(topBar.right, closeTo(content.right, .1));
        final header = t.widget<AccountingPageHeader>(
          find.byType(AccountingPageHeader).first,
        );
        if (header.action != null) {
          final action = t.getRect(find.byWidget(header.action!));
          expect(action.right, closeTo(content.right, .1));
          final tabs = find.byType(AccountingTabs);
          if (tabs.evaluate().isNotEmpty) {
            final band = t.getRect(tabs.first);
            expect(band.left, closeTo(content.left, .1));
            expect(band.right, lessThanOrEqualTo(action.right + .1));
            if (width == 2056 && path == '/expenses-vendors') {
              expect(
                band.right,
                lessThan(action.right - 1),
                reason: 'A short grey band must not stretch to the right limit',
              );
            }
          }
        }
        expect(t.takeException(), isNull);
        await capture(
          t,
          'Shared Page Alignment ${path.substring(1)} ${width.toInt()}',
        );
      });
    }
  }

  testWidgets('navigation destinations preserve the expanded sidebar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    for (final id in [
      'expenses-vendors',
      'sales-customers',
      'banking',
      'reports',
    ]) {
      await tester.tap(find.byKey(ValueKey('navigation-item-$id')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('accounting-navigation-extended-rail')),
        findsOneWidget,
        reason: 'Selecting $id retracted the sidebar',
      );
    }
    await tester.tap(
      find.byKey(const ValueKey('collapse-accounting-navigation')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
  });

  testWidgets('Home summary and reminders reflow without changing sidebar', (
    tester,
  ) async {
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final width in [
      1600.0,
      1400.0,
      1300.0,
      1200.0,
      1100.0,
      1000.0,
      900.0,
      800.0,
      720.0,
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(const AudytApp());
      await tester.pump();
      final joined = find
          .byKey(const ValueKey('home-kpi-strip'))
          .evaluate()
          .isNotEmpty;
      final firstReminder = tester.getRect(
        find.byKey(const ValueKey('SST Return')),
      );
      final lastReminder = tester.getRect(
        find.byKey(const ValueKey('Annual Return')),
      );
      expect(firstReminder.top == lastReminder.top, joined);
      final compactRail = find.byKey(
        const ValueKey('accounting-navigation-compact-rail'),
      );
      if (width == 1600) {
        expect(
          find.byKey(const ValueKey('accounting-navigation-extended-rail')),
          findsOneWidget,
        );
      }
      if (width == 720) expect(compactRail, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Reports bar reflows without retracting the sidebar', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('report-order-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final width in [1800.0, 1450.0, 1400.0, 1350.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        AudytApp(initialPath: '/reports', workspace: workspace),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('report-summary-strip')),
        findsOneWidget,
        reason: 'Reports cards split before the sidebar at $width',
      );
      if (width == 1800) {
        expect(
          find.byKey(const ValueKey('accounting-navigation-extended-rail')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
    await tester.binding.setSurfaceSize(const Size(960, 900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-summary-strip')), findsNothing);
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
  });

  testWidgets('dragging the sidebar border caps its width at 130 percent', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    final border = find.byKey(
      const ValueKey('accounting-navigation-resize-border'),
    );
    await tester.drag(border, const Offset(200, 0));
    await tester.pump();
    final rail = find.byKey(
      const ValueKey('accounting-navigation-extended-rail'),
    );
    expect(
      tester.getSize(rail).width,
      AccountingResponsive.extendedRailResizableMaxWidth,
    );
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pump();
    expect(
      tester.getSize(rail).width,
      lessThanOrEqualTo(AccountingResponsive.extendedRailResizableMaxWidth),
    );
    expect(find.byKey(const ValueKey('home-kpi-card-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thin divider can expand the compact rail by dragging', (
    tester,
  ) async {
    const channel = MethodChannel('audyt/window-layout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requestedWidths = <double>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'growToWidth') return null;
      final width = (call.arguments as Map)['width'] as double;
      requestedWidths.add(width);
      await tester.binding.setSurfaceSize(Size(width, 900));
      return width;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    final divider = find.byKey(
      const ValueKey('accounting-navigation-divider-line'),
    );
    final dragTarget = find.byKey(
      const ValueKey('accounting-navigation-resize-border'),
    );
    expect(tester.getSize(divider).width, 1);
    expect(tester.getSize(dragTarget).width, 8);
    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    await tester.drag(dragTarget, const Offset(45, 0));
    await tester.pumpAndSettle();

    expect(requestedWidths, hasLength(1));
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('accounting-main-scroll')))
          .width,
      closeTo(AccountingResponsive.desktopMainContentMinWidth, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('joined Home totals stay readable after sidebar resizing', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(1028, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AudytApp(
        homeData: AccountingHomeData(
          currencyCode: 'MYR',
          recentExpenses: const [],
          postedMonthTotal: Money.fromMinor(151500, 'MYR'),
          postedYearTotal: Money.fromMinor(220500, 'MYR'),
          postedMonthSales: Money.fromMinor(68291473, 'MYR'),
          postedYearSales: Money.fromMinor(429736518, 'MYR'),
          postedBankBalance: Money.fromMinor(429736518, 'MYR'),
          needsReviewCount: 36,
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('accounting-navigation-resize-border')),
      const Offset(70, 0),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-kpi-card-0')), findsOneWidget);
    for (final (metric, value) in [
      ('This Month', 'RM 682,914.73'),
      ('All Balance', 'RM 4,297,365.18'),
    ]) {
      final text = find.descendant(
        of: find.byKey(ValueKey('home-kpi-$metric')),
        matching: find.text(value),
      );
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expanding at minimum width grows the window and preserves content',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      const channel = MethodChannel('audyt/window-layout');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final requestedWidths = <double>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'loadSidebarWidth') {
          return AccountingResponsive.extendedRailResizableMaxWidth;
        }
        if (call.method != 'growToWidth') return null;
        final width = (call.arguments as Map)['width'] as double;
        requestedWidths.add(width);
        await tester.binding.setSurfaceSize(Size(width, 900));
        return width;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.binding.setSurfaceSize(const Size(720, 900));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AudytApp(
          homeData: AccountingHomeData(
            currencyCode: 'MYR',
            recentExpenses: const [],
            postedMonthTotal: Money.fromMinor(151500, 'MYR'),
            postedYearTotal: Money.fromMinor(220500, 'MYR'),
            needsReviewCount: 36,
          ),
        ),
      );
      await tester.pump();
      final expand = find.byKey(const ValueKey('expand-accounting-navigation'));
      expect(
        find.byKey(const ValueKey('accounting-navigation-compact-rail')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-kpi-strip')), findsNothing);
      expect(find.byKey(const ValueKey('home-kpi-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-kpi-card-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-kpi-card-1')), findsOneWidget);
      final first = tester.getRect(
        find.byKey(const ValueKey('home-kpi-card-0')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('home-kpi-card-2')),
      );
      expect(first.top, second.top);
      final reminderOne = tester.getRect(
        find.byKey(const ValueKey('SST Return')),
      );
      final reminderTwo = tester.getRect(
        find.byKey(const ValueKey('Income Tax')),
      );
      final reminderThree = tester.getRect(
        find.byKey(const ValueKey('Annual Return')),
      );
      final year = tester.getRect(
        find.byKey(const ValueKey('home-kpi-card-1')),
      );
      expect(year.top, reminderOne.top);
      expect(year.left, lessThan(reminderOne.left));
      expect(reminderTwo.top, reminderThree.top);
      expect(reminderTwo.top, greaterThan(reminderOne.bottom));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Annual Return'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<InkWell>(expand).onTap, isNotNull);

      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(requestedWidths, hasLength(1));
      expect(
        requestedWidths.single,
        AccountingResponsive.extendedRailResizableMaxWidth +
            AccountingResponsive.navigationDividerWidth +
            AccountingResponsive.desktopMainContentMinWidth,
      );
      expect(
        find.byKey(const ValueKey('accounting-navigation-extended-rail')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('accounting-navigation-extended-rail')),
            )
            .width,
        AccountingResponsive.extendedRailResizableMaxWidth,
      );
      expect(find.byKey(const ValueKey('home-kpi-strip')), findsNothing);
      expect(find.byKey(const ValueKey('home-kpi-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-kpi-card-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-kpi-card-1')), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('accounting-main-scroll')))
            .width,
        closeTo(AccountingResponsive.desktopMainContentMinWidth, 0.1),
      );

      await tester.binding.setSurfaceSize(const Size(720, 900));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('accounting-navigation-compact-rail')),
        findsOneWidget,
      );
      expect(tester.widget<InkWell>(expand).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanding the rail uses free window space before growing it', (
    tester,
  ) async {
    const channel = MethodChannel('audyt/window-layout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requestedWidths = <double>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'growToWidth') {
        requestedWidths.add((call.arguments as Map)['width'] as double);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(1224, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(initialPath: '/expenses-vendors'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('collapse-accounting-navigation')),
    );
    await tester.pumpAndSettle();
    final before = tester
        .getSize(find.byKey(const ValueKey('accounting-main-scroll')))
        .width;
    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('expand-accounting-navigation')),
    );
    await tester.pumpAndSettle();
    expect(requestedWidths, isEmpty);
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('accounting-main-scroll')))
          .width,
      closeTo(
        before -
            (AccountingResponsive.extendedRailMaxWidth -
                AccountingResponsive.compactRailWidth),
        0.1,
      ),
    );
  });

  testWidgets('compact Settings aligns with the navigation icons', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 800));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    final rail = tester.getRect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
    );
    final settings = tester.getRect(
      find.byKey(const ValueKey('accounting-settings')),
    );
    expect(settings.width, 44);
    expect(settings.center.dx, closeTo(rail.center.dx, 0.1));
    expect(find.text('Settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders the production shell with a painted expanded rail at desktop width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const AudytApp());
      await tester.pump();

      final rail = find.byKey(
        const ValueKey('accounting-navigation-extended-rail'),
      );
      final main = find.byKey(const ValueKey('accounting-main-scroll'));
      final railRect = tester.getRect(rail);
      final mainRect = tester.getRect(main);

      expect(railRect.width, AccountingResponsive.extendedRailWidthFor(1280));
      expect(
        railRect.width,
        greaterThan(AccountingResponsive.compactRailWidth),
      );
      expect(find.text('Daily Work'), findsOneWidget);
      expect(find.text('Expenses'), findsWidgets);
      expect(
        find.byKey(const ValueKey('navigation-item-claims')),
        findsNothing,
      );
      expect(
        mainRect.left,
        closeTo(
          railRect.right + AccountingResponsive.navigationDividerWidth,
          0.001,
        ),
      );

      await tester.binding.setSurfaceSize(const Size(600, 720));
      await tester.pump();

      final compactRail = find.byKey(
        const ValueKey('accounting-navigation-compact-rail'),
      );
      expect(
        tester.getRect(compactRail).width,
        AccountingResponsive.compactRailWidth,
      );
      expect(find.text('Daily Work'), findsNothing);
      expect(
        find.byKey(const ValueKey('navigation-item-claims')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('expand-accounting-navigation')),
        findsOneWidget,
      );
    },
  );

  test('starts the macOS production host at the expanded-shell width', () {
    final xib = File('macos/Runner/Base.lproj/MainMenu.xib').readAsStringSync();
    final contentRect = RegExp(
      r'<rect key="contentRect" x="[^"]+" y="[^"]+" width="([^"]+)" height="([^"]+)"/>',
    ).firstMatch(xib);
    final contentViewFrame = RegExp(
      r'<rect key="frame" x="[^"]+" y="[^"]+" width="([^"]+)" height="([^"]+)"/>',
    ).firstMatch(xib);

    expect(contentRect, isNotNull);
    expect(contentViewFrame, isNotNull);
    expect(double.parse(contentRect!.group(1)!), 1162);
    expect(double.parse(contentRect.group(2)!), 809);
    expect(
      double.parse(contentRect.group(1)!),
      greaterThanOrEqualTo(AccountingResponsive.expandedMinWidth),
    );
    expect(contentViewFrame!.group(1), contentRect.group(1));
    expect(contentViewFrame.group(2), contentRect.group(2));
  });

  testWidgets(
    'opens expanded labels at full desktop width and collapses rail before content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const AudytApp());

      expect(
        find.byKey(const ValueKey('accounting-navigation-extended-rail')),
        findsOneWidget,
      );
      expect(find.text('Daily Work'), findsOneWidget);
      expect(find.text('Expenses'), findsWidgets);
      expect(
        find.byKey(const ValueKey('navigation-item-claims')),
        findsNothing,
      );
      expect(find.byTooltip('Expand Accounting Navigation'), findsNothing);

      await tester.binding.setSurfaceSize(const Size(600, 720));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('accounting-navigation-compact-rail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expand-accounting-navigation')),
        findsOneWidget,
      );
      expect(find.text('Daily Work'), findsNothing);
      expect(
        find.byKey(const ValueKey('navigation-item-claims')),
        findsNothing,
      );
    },
  );

  testWidgets('keeps the icon rail at the 600px boundary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 720));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AudytApp());

    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    expect(find.byTooltip('Open Accounting Navigation'), findsNothing);
  });

  testWidgets('uses one vertical fluid page shell at the 320px floor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AudytApp());

    expect(
      find.byKey(const ValueKey('accounting-main-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a destination directly from the compact rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AudytApp());
    expect(find.byTooltip('Open Accounting Navigation'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-title-sales-customers')),
      findsOneWidget,
    );
    expect(find.text('Route Not Found'), findsNothing);
    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the icon rail at 768px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    expect(find.text('Daily Work'), findsNothing);
    expect(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
      findsOneWidget,
    );
  });
}
