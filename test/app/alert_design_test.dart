import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/sidebar_settings_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (tone, icon, asset) in <(AccountingAlertTone, IconData, String)>[
    (AccountingAlertTone.positive, Icons.info_rounded, '033-info.svg'),
    (
      AccountingAlertTone.warning,
      Icons.warning_rounded,
      '032-warning-sign.svg',
    ),
    (AccountingAlertTone.critical, Icons.error_rounded, '035-error.svg'),
  ]) {
    testWidgets('${tone.name} alert has a filled surface and centred mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => AccountingAlert.build(
                context,
                key: const ValueKey('alert'),
                title: 'Notice',
                description: 'A useful message.',
                tone: tone,
              ),
            ),
          ),
        ),
      );
      final alert = tester.widget<Container>(
        tone == AccountingAlertTone.warning
            ? find
                  .descendant(
                    of: find.byKey(const ValueKey('alert')),
                    matching: find.byType(Container),
                  )
                  .first
            : find.byKey(const ValueKey('alert')),
      );
      final decoration = alert.decoration! as BoxDecoration;
      expect(decoration.color, isNot(Colors.white));
      expect(decoration.border, isNull);
      if (tone == AccountingAlertTone.warning) {
        expect(decoration.color, const Color(0xFFFFF6E2));
        expect(
          tester.widget<Text>(find.text('Notice')).style?.color,
          const Color(0xFF8B5E00),
        );
      }
      final mark = find.byWidgetPredicate(
        (widget) => widget is AccountingIcon && widget.icon == icon,
      );
      expect(mark, findsOneWidget);
      expect(AccountingIcon.assets[icon], asset);
      expect(tester.widget<AccountingIcon>(mark).size, 18);
      expect(tester.widget<AccountingIcon>(mark).color, Colors.white);
      final circle = tester.widget<Container>(
        find.ancestor(of: mark, matching: find.byType(Container)).first,
      );
      expect((circle.decoration! as BoxDecoration).shape, BoxShape.circle);
      if (tone == AccountingAlertTone.critical) {
        expect(
          (circle.decoration! as BoxDecoration).color,
          const Color(0xFFED5565),
        );
        expect(
          tester.widget<Text>(find.text('Notice')).style?.color,
          const Color(0xFFED5565),
        );
        expect(
          tester.widget<Text>(find.text('A useful message.')).style?.color,
          const Color(0xFFED5565),
        );
      }

      expect(
        tester.getCenter(mark).dx,
        closeTo(
          tester
                  .getCenter(
                    find
                        .ancestor(of: mark, matching: find.byType(Container))
                        .first,
                  )
                  .dx +
              (tone == AccountingAlertTone.warning ? 0.25 : 0),
          0.1,
        ),
      );
      expect(
        tester.getCenter(mark).dy,
        closeTo(
          tester
                  .getCenter(
                    find
                        .ancestor(of: mark, matching: find.byType(Container))
                        .first,
                  )
                  .dy +
              0,
          0.1,
        ),
      );
      expect(find.text('Notice'), findsOneWidget);
      expect(find.text('A useful message.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('A useful message.')).dy -
            tester.getBottomLeft(find.text('Notice')).dy,
        4,
      );
    });
  }

  testWidgets('settings uses the supplied controls at the sidebar size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(body: SidebarSettingsIcon()),
      ),
    );
    final icon = tester.widget<AccountingIcon>(find.byType(AccountingIcon));
    expect(icon.size, 17);
    expect(AccountingIcon.assets[icon.icon], '034-controls.svg');
    expect(AccountingIcon.assets[Icons.tune], '034-controls.svg');
  });
}
