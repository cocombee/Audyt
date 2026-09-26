import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'summary_action_wiring_test.dart' show view;
import 'restored_page_routes_test.dart' show tables;

const actionIcons = <IconData>[
  Icons.add_rounded,
  Icons.assignment_turned_in_outlined,
  Icons.attach_money,
  Icons.calendar_today_outlined,
  Icons.check,
  Icons.check_rounded,
  Icons.chevron_left_rounded,
  Icons.chevron_right_rounded,
  Icons.close,
  Icons.close_rounded,
  Icons.delete_outline,
  Icons.description_outlined,
  Icons.edit_note_outlined,
  Icons.edit_outlined,
  Icons.fact_check_outlined,
  Icons.file_upload_outlined,
  Icons.filter_alt_off_outlined,
  Icons.folder_open_outlined,
  Icons.history_outlined,
  Icons.image_outlined,
  Icons.inventory_2_outlined,
  Icons.link_outlined,
  Icons.more_horiz,
  Icons.note_add_outlined,
  Icons.preview_outlined,
  Icons.rate_review_outlined,
  Icons.receipt_long,
  Icons.refresh_outlined,
  Icons.restore,
  Icons.savings_outlined,
  Icons.settings_outlined,
  Icons.sync,
  Icons.undo,
  Icons.visibility_outlined,
  Icons.logout,
];
const notificationIcons = <IconData>[
  Icons.person_outline,
  Icons.shopping_bag_outlined,
  Icons.assignment_turned_in_outlined,
  Icons.receipt_long_outlined,
  Icons.account_balance_outlined,
];

void main() {
  testWidgets('all button members use the established vectors and states', (
    tester,
  ) async {
    await view(tester, 1224);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Builder(
                builder: (context) => Column(
                  children: [
                    const Text('Button family: enabled / disabled'),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < actionIcons.length; i++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AccountingButton.outline(
                                context,
                                key: ValueKey('family-$i'),
                                onPressed: () {},
                                leadingIcon: actionIcons[i],
                                child: Text('$i'),
                              ),
                              const SizedBox(width: 4),
                              AccountingButton.outline(
                                context,
                                key: null,
                                onPressed: null,
                                leadingIcon: actionIcons[i],
                                child: Text('$i'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < actionIcons.length; i++) {
      final button = find.byKey(ValueKey('family-$i'));
      expect(
        find.descendant(of: button, matching: find.byType(SvgPicture)),
        findsOneWidget,
        reason: 'Button family member $i',
      );
      expect(
        find.descendant(of: button, matching: find.byType(Icon)),
        findsNothing,
        reason: 'No unmatched framework glyph for member $i',
      );
    }
    await captureUi(tester, 'Button Icon Family');
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification comparison contains notification members only', (
    tester,
  ) async {
    await view(tester, 1224);
    tester.view.physicalSize = const Size(1224, 260);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Notification Icons: original / equalized'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final icon in notificationIcons)
                      Row(
                        children: [
                          AccountingIcon(icon, color: Colors.black),
                          const SizedBox(width: 20),
                          AccountingNotificationIcon(icon, color: Colors.black),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureUi(tester, 'Notification Icon Family');
    expect(tester.takeException(), isNull);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('notification heading stays visible at list bottom $width', (
      tester,
    ) async {
      await view(tester, width);
      tester.view.physicalSize = Size(width, width == 720 ? 620 : 900);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final before = tables(workspace);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notifications-read-more')));
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('notifications-fixed-heading'));
      final footer = find.byKey(const ValueKey('notifications-read-more'));
      final headingRect = tester.getRect(heading);
      final footerRect = tester.getRect(footer);
      final panel = tester.getRect(
        find.byKey(const ValueKey('notification-panel')),
      );
      final bell = tester.getRect(
        find.byKey(const ValueKey('global-notifications')),
      );
      expect(panel.top, greaterThanOrEqualTo(bell.bottom));
      expect(
        panel.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 8),
      );
      final list = find.byKey(const ValueKey('notifications-scroll-list'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.maxScrollExtent, .01),
      );
      expect(tester.getRect(heading), headingRect);
      expect(tester.getRect(footer), footerRect);
      expect(find.text('Notifications').hitTestable(), findsOneWidget);
      expect(find.text('Show less').hitTestable(), findsOneWidget);
      await captureUi(tester, 'Notification List Bottom ${width.toInt()}');
      await tester.tap(footer);
      await tester.pumpAndSettle();
      expect(find.text('Read more').hitTestable(), findsOneWidget);
      expect(tables(workspace), before);
      expect(tester.takeException(), isNull);
    });
  }
}
