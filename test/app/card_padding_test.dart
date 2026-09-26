import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [220.0, 300.0, 600.0]) {
    testWidgets('reminder card aligns outer content at $width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AccountingDashboardCard(
                  title: 'Income Tax',
                  icon: Icons.notifications_none,
                  detail: Text(
                    '23h 55m 06s',
                    style: const TextStyle(fontSize: 16, height: 1),
                  ),
                  value: const SizedBox(
                    key: ValueKey('reminder-badge'),
                    width: 70,
                    height: 20,
                    child: Text('Due Soon'),
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final card = tester.getRect(find.byType(Card));
      final icon = tester.getRect(find.byType(AccountingMetricIconBox));
      final title = tester.getRect(find.text('Income Tax'));
      final countdown = tester.getRect(find.text('23h 55m 06s'));
      final chevron = tester.getRect(
        find.descendant(
          of: find.byType(AccountingSelectorChevron),
          matching: find.byType(CustomPaint),
        ),
      );
      final hoverTarget = tester.getRect(
        find.byType(AccountingSelectorChevron),
      );
      final badge = tester.getRect(
        find.byKey(const ValueKey('reminder-badge')),
      );

      expect(icon.left - card.left, closeTo(20, 0.1));
      expect(icon.top - card.top, closeTo(20, 0.1));
      expect(chevron.top, closeTo(icon.top, 0.1));
      expect(card.right - chevron.right, closeTo(20, 0.1));
      expect(hoverTarget.center, chevron.center);
      expect(card.right - badge.right, closeTo(20, 0.1));
      if (badge.top >= icon.bottom) {
        expect(badge.top - icon.bottom, closeTo(20, 0.1));
      } else {
        expect(badge.bottom, closeTo(icon.bottom, 0.1));
      }
      expect(
        countdown.top - title.bottom,
        closeTo(accountingMetricLineGap, 0.1),
      );
      expect(card.bottom - badge.bottom, closeTo(20, 0.1));
      expect(countdown.left, closeTo(title.left, 0.1));
      expect(tester.takeException(), isNull);
    });
  }
}
