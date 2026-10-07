import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  testWidgets('global search suggests typed records with their categories', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-search-field')),
      'Northwind',
    );
    await tester.pumpAndSettle();
    expect(find.text('Northwind Services'), findsOneWidget);
    expect(find.text('Northwind Office Supplies'), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('Payment Voucher'), findsOneWidget);
    expect(find.text('This Month'), findsWidgets);

    await tester.tap(find.text('Northwind Office Supplies'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('area-tabs-expenses-vendors')),
      findsOneWidget,
    );
  });

  testWidgets('pending demo reviews roll from tabs into sidebar and bell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(initialPath: '/expenses-vendors'));

    final expenses = find.byKey(
      const ValueKey('navigation-item-expenses-vendors'),
    );
    expect(
      find.descendant(of: expenses, matching: find.text('2')),
      findsOneWidget,
    );
    final tabs = find.byKey(const ValueKey('area-tabs-expenses-vendors'));
    expect(
      find.descendant(of: tabs, matching: find.text('Claims')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabs, matching: find.text('Payment Vouchers')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabs, matching: find.text('1')),
      findsNWidgets(2),
    );

    final bellBadge = tester.widget<Container>(
      find.byKey(const ValueKey('global-notification-badge')),
    );
    final search = tester.getRect(
      find.byKey(const ValueKey('global-search-box')),
    );
    final notificationControl = find.byKey(
      const ValueKey('global-notifications'),
    );
    final bell = tester.getRect(
      find.descendant(
        of: notificationControl,
        matching: find.byType(SvgPicture),
      ),
    );
    final badge = tester.getRect(
      find.byKey(const ValueKey('global-notification-badge')),
    );
    final profile = tester.getRect(find.byType(CircleAvatar));
    final bellButton = tester.getRect(notificationControl);
    final topBar = tester.getRect(find.byKey(const ValueKey('global-top-bar')));
    expect(bell.left - search.right, greaterThanOrEqualTo(20));
    expect(profile.left - badge.right, greaterThanOrEqualTo(20));
    expect(profile.left - bellButton.right, closeTo(24, 0.1));
    // The shared page container now owns the outer inset.
    expect(topBar.right - profile.right, closeTo(0, 0.1));
    expect(find.byTooltip('Notifications'), findsNothing);
    expect(
      (bellBadge.decoration! as BoxDecoration).color,
      AccountingColorLibrary.grapefruitDeep,
    );

    await tester.tap(find.byKey(const ValueKey('global-notifications')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-panel')), findsOneWidget);
    expect(find.text('Claims needing review (1)'), findsNothing);
    expect(find.text('Vouchers pending approval (1)'), findsNothing);
    expect(find.text('Claim needs review ·'), findsNothing);
    expect(find.textContaining('Claim needs review'), findsOneWidget);
    expect(find.textContaining('Voucher pending approval'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('notification-panel'))).top,
      greaterThan(tester.getRect(notificationControl).bottom),
    );
    await tester.tapAt(const Offset(500, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('global-profile')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('global-top-bar'))).right -
          tester
              .getRect(find.byKey(const ValueKey('profile-menu-profile')))
              .right,
      // Profile choices use the shared selector's 4px popup inset.
      closeTo(4, 0.1),
    );
    expect(find.byKey(const ValueKey('profile-menu-google')), findsOneWidget);
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('profile-menu-google')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('profile-menu-settings')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-menu-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
  });

  testWidgets('tab badge grows for 99+ without reducing outer padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountingTabs(
            labels: const ['Claims'],
            notificationCounts: const {'Claims': 1},
            selectedIndex: 0,
            onChanged: (_) {},
            keyPrefix: 'count-tab',
          ),
        ),
      ),
    );
    final singleWidth = tester
        .getSize(find.byKey(const ValueKey('count-tab-0')))
        .width;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountingTabs(
            labels: const ['Claims'],
            notificationCounts: const {'Claims': 105},
            selectedIndex: 0,
            onChanged: (_) {},
            keyPrefix: 'count-tab',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('count-tab-0'))).width,
      greaterThan(singleWidth),
    );
  });
}
