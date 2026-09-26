import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/menu_visual_geometry.dart';

void main() {
  for (final width in [1440.0, 500.0]) {
    for (final withIcons in [false, true]) {
      testWidgets(
        'longest choice has symmetric insets and regular font at $width, icons $withIcons',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 720));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: withIcons
                          ? AccountingOverflowMenu(
                              triggerKey: const ValueKey('trigger'),
                              compact: true,
                              actions: [
                                AccountingOverflowAction(
                                  key: const ValueKey('short'),
                                  label: 'View Original',
                                  icon: Icons.visibility_outlined,
                                  onPressed: () {},
                                ),
                                AccountingOverflowAction(
                                  key: const ValueKey('longest'),
                                  label: 'Reconciliation History',
                                  icon: Icons.history_outlined,
                                  onPressed: () {},
                                ),
                              ],
                            )
                          : AccountingCompactChoiceMenu<String>(
                              triggerKey: const ValueKey('trigger'),
                              value: 'bank',
                              onChanged: (_) {},
                              options: const [
                                AccountingSelectorOption(
                                  value: 'bank',
                                  label: 'Demo Bank',
                                  key: ValueKey('short'),
                                ),
                                AccountingSelectorOption(
                                  value: 'saving',
                                  label: 'Demo Savings',
                                  key: ValueKey('longest'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('trigger')));
          await tester.pumpAndSettle();
          final choice = find.byKey(const ValueKey('longest'));
          final label = find.descendant(
            of: choice,
            matching: find.byType(Text),
          );
          final panel = tester.getRect(
            find.ancestor(of: choice, matching: find.byType(Material)).first,
          );
          final actualLabel = labelRect(tester, label);
          final left = withIcons
              ? tester
                    .getRect(
                      find.descendant(
                        of: choice,
                        matching: find.byType(AccountingIcon),
                      ),
                    )
                    .left
              : actualLabel.left;
          expect(left - panel.left, closeTo(16, 0.3));
          expect(
            panel.right - actualLabel.right,
            closeTo(left - panel.left, 0.3),
          );
          final inherited = DefaultTextStyle.of(tester.element(label)).style;
          expect(inherited.fontWeight, FontWeight.w400);
          expect(
            inherited.fontSize,
            AccountingTypography.value(tester.element(label)).fontSize,
          );
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(choice));
          await tester.pumpAndSettle();
          await capture(
            key,
            'Menu Font Padding ${withIcons ? 'Actions' : 'Selector'} ${width.toInt()}',
            tester,
          );
          await mouse.removePointer();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'small switch stroke group and enlarged date modes render together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final item in <(String, Widget)>[
                      (
                        'Original',
                        const AccountingSmallAssetIcon(
                          '076-change-account.svg',
                        ),
                      ),
                      (
                        'Switch',
                        const AccountingSmallAssetIcon(
                          '086-change-account-normalized.svg',
                        ),
                      ),
                      (
                        'Back',
                        const AccountingIcon.smallAction(
                          Icons.undo,
                          key: ValueKey('centered-back'),
                        ),
                      ),
                      (
                        'Reference',
                        const AccountingSmallAssetIcon('051-restore.svg'),
                      ),
                      (
                        'Reconcile',
                        const AccountingSmallAssetIcon('080-sync.svg'),
                      ),
                      (
                        'Settings',
                        const AccountingSmallAssetIcon(
                          '082-banking-setting.svg',
                        ),
                      ),
                      (
                        '07',
                        const AccountingSmallAssetIcon(
                          '083-seven-days.svg',
                          paintedSizeAdjustment: 1,
                        ),
                      ),
                      (
                        '30',
                        const AccountingSmallAssetIcon(
                          '067-month-clock.svg',
                          paintedSizeAdjustment: 1,
                        ),
                      ),
                      (
                        '90',
                        const AccountingSmallAssetIcon(
                          '084-all-statement-days.svg',
                          paintedSizeAdjustment: 1,
                        ),
                      ),
                    ])
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(dimension: 32, child: item.$2),
                          const SizedBox(height: 10),
                          Text(item.$1),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(AccountingIcon.smallAssetFor(Icons.swap_horiz), '062-swap.svg');
      expect(AccountingIcon.assets[Icons.swap_horiz], '062-swap.svg');
      expect(
        AccountingIcon.smallAssetFor(Icons.undo),
        '087-return-centered.svg',
      );
      final back = find.byKey(const ValueKey('centered-back'));
      final frame = tester.getRect(
        find
            .ancestor(
              of: back,
              matching: find.byWidgetPredicate(
                (w) => w is SizedBox && w.width == 32 && w.height == 32,
              ),
            )
            .first,
      );
      final ink = await paintedBounds(tester, key, back);
      expect(ink.center.dy, closeTo(frame.center.dy, 0.15));
      await capture(key, 'Small Switch And Calendar Review', tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('one overflow action is direct and performs its operation', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: AccountingOverflowMenu(
            compact: true,
            triggerKey: const ValueKey('trigger'),
            actions: [
              AccountingOverflowAction(
                key: const ValueKey('refresh'),
                label: 'Refresh Documents',
                icon: Icons.restore,
                onPressed: () => refreshes++,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(AccountingMenuAnchor), findsNothing);
    expect(find.byTooltip('Refresh Documents'), findsOneWidget);
    expect(
      tester.widget<AccountingIcon>(find.byType(AccountingIcon)).icon,
      Icons.restore,
    );
    await tester.tap(find.byKey(const ValueKey('trigger')));
    expect(refreshes, 1);
  });
  testWidgets('widened field selector keeps popup at its field width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: AccountingSelector<String>(
            hintText: 'Select account',
            assignedWidth: 340,
            triggerKey: const ValueKey('field'),
            value: 'bank',
            onChanged: (_) {},
            options: const [
              AccountingSelectorOption(
                value: 'bank',
                label: 'Demo Bank',
                key: ValueKey('choice'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('choice')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      panel.width,
      tester.getSize(find.byKey(const ValueKey('field'))).width,
    );
    expect(
      panel.right -
          labelRect(
            tester,
            find.descendant(
              of: find.byKey(const ValueKey('choice')),
              matching: find.byType(Text),
            ),
          ).right,
      greaterThanOrEqualTo(16),
    );
  });
}
