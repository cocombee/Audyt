import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final grouped in [false, true]) {
    testWidgets(
      'search hover and keyboard share one active option, grouped=$grouped',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(720, 895));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        int? selected;
        final options = [
          for (var index = 0; index < 10; index++)
            AccountingSelectorOption<int>(
              value: index,
              label: 'Item $index',
              key: ValueKey('search-hover-$index'),
              group: grouped ? (index.isEven ? 'Even' : 'Odd') : null,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  child: StatefulBuilder(
                    builder: (context, setState) => AccountingSelector<int>(
                      value: selected,
                      options: options,
                      searchable: true,
                      searchKey: const ValueKey('search-hover-input'),
                      triggerKey: const ValueKey('search-hover-trigger'),
                      hintText: 'Choose item',
                      onChanged: (value) => setState(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final trigger = find.byKey(const ValueKey('search-hover-trigger'));
        final input = find.byKey(const ValueKey('search-hover-input'));
        Finder row(int index) => find.byKey(ValueKey('search-hover-$index'));
        Color? background(int index, [Set<WidgetState> states = const {}]) =>
            tester
                .widget<MenuItemButton>(row(index))
                .style!
                .backgroundColor!
                .resolve(states);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(input));
        await tester.enterText(input, 'Item');
        await tester.pumpAndSettle();
        expect(background(0), AccountingTokens.light.accent);
        await mouse.moveTo(tester.getCenter(row(2)));
        await tester.pumpAndSettle();
        expect(background(0), Colors.transparent);
        expect(background(2), AccountingTokens.light.accent);
        final search = tester.widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        );
        expect(search.focusNode.hasFocus, isTrue);
        // A stationary pointer must not keep its row grey after keyboard moves.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final next = grouped ? 4 : 3;
        expect(background(2, {WidgetState.hovered}), Colors.transparent);
        expect(background(next), AccountingTokens.light.accent);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selected, next);
        expect(input, findsNothing);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(input));
        await tester.enterText(input, 'Item');
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(row(2)));
        await tester.pumpAndSettle();
        expect(background(0), Colors.transparent);
        expect(background(2), AccountingTokens.light.accent);
        expect(
          background(next),
          AccountingTokens.light.primary.withValues(alpha: 0.10),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          selected,
          2,
          reason: 'Hover commits the same displayed identity',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact chart choices stay on one line when opened', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: AccountingSelector<String>(
              compactToolbar: true,
              value: 'Pie',
              hintText: 'Chart type',
              triggerKey: const ValueKey('compact-chart-trigger'),
              options: const [
                AccountingSelectorOption(value: 'Pie', label: 'Pie'),
                AccountingSelectorOption(value: 'Bar', label: 'Bar'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('compact-chart-trigger'));
    final width = tester.getSize(trigger).width;
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    for (final label in ['Pie', 'Bar']) {
      final text = find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text(label),
      );
      expect(
        tester.getSize(text).height,
        lessThan(30),
        reason: '$label must not wrap vertically',
      );
    }
    expect(tester.getSize(trigger).width, width);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selector uses light green selection without a checkmark and stable width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: const <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'alpha',
                  label: 'Alpha',
                  key: ValueKey<String>('selector-correction-alpha'),
                ),
                AccountingSelectorOption<String>(
                  value: 'beta',
                  label: 'Beta',
                  key: ValueKey<String>('selector-correction-beta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'gamma',
                  label: 'Gamma',
                  key: ValueKey<String>('selector-correction-gamma'),
                ),
                AccountingSelectorOption<String>(
                  value: 'delta',
                  label: 'Delta',
                  key: ValueKey<String>('selector-correction-delta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'epsilon',
                  label: 'Epsilon',
                  key: ValueKey<String>('selector-correction-epsilon'),
                ),
              ],
              value: 'alpha',
              onChanged: (_) {},
              hintText: 'Select value',
              triggerKey: const ValueKey<String>('selector-correction-trigger'),
              menuKey: const ValueKey<String>('selector-correction-menu'),
              menuTitle: 'Choose a value',
              menuTitleKey: const ValueKey<String>(
                'selector-correction-heading',
              ),
            ),
          ),
        ),
      );

      final closedWidth = tester
          .getSize(
            find.byKey(const ValueKey<String>('selector-correction-trigger')),
          )
          .width;
      await tester.tap(
        find.byKey(const ValueKey<String>('selector-correction-trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('selector-correction-heading')),
        findsNothing,
      );
      final openWidth = tester
          .getSize(
            find.byKey(const ValueKey<String>('selector-correction-trigger')),
          )
          .width;
      final menuWidth = tester
          .getSize(
            find.byKey(const ValueKey<String>('selector-correction-menu')),
          )
          .width;
      expect(openWidth, closeTo(closedWidth, 0.1));
      // Menu content excludes its four-pixel inset on either side.
      expect(menuWidth + 8, closeTo(closedWidth, 0.1));
      final selected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey<String>('selector-correction-alpha')),
      );
      final unselected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey<String>('selector-correction-beta')),
      );
      expect(
        selected.style!.backgroundColor!.resolve(<WidgetState>{}),
        isNot(AccountingTokens.light.accent),
      );
      expect(
        unselected.style!.backgroundColor!.resolve(<WidgetState>{}),
        Colors.transparent,
      );
      expect(selected.leadingIcon, isNull);
      expect(
        selected.style!.backgroundColor!.resolve(<WidgetState>{}),
        AccountingTokens.light.primary.withValues(alpha: 0.10),
      );
    },
  );

  testWidgets(
    'selector hover styling follows one row and clears after leaving it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: const <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'alpha',
                  label: 'Alpha',
                  key: ValueKey<String>('selector-hover-alpha'),
                ),
                AccountingSelectorOption<String>(
                  value: 'beta',
                  label: 'Beta',
                  key: ValueKey<String>('selector-hover-beta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'gamma',
                  label: 'Gamma',
                  key: ValueKey<String>('selector-hover-gamma'),
                ),
                AccountingSelectorOption<String>(
                  value: 'delta',
                  label: 'Delta',
                  key: ValueKey<String>('selector-hover-delta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'epsilon',
                  label: 'Epsilon',
                  key: ValueKey<String>('selector-hover-epsilon'),
                ),
              ],
              value: null,
              onChanged: (_) {},
              hintText: 'Select value',
              triggerKey: const ValueKey<String>('selector-hover-trigger'),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('selector-hover-trigger')),
      );
      await tester.pumpAndSettle();

      final first = find.byKey(const ValueKey<String>('selector-hover-alpha'));
      final second = find.byKey(const ValueKey<String>('selector-hover-beta'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(first));
      await tester.pump();
      expect(
        tester
            .widget<MenuItemButton>(first)
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        AccountingTokens.light.accent,
      );
      expect(
        tester
            .widget<MenuItemButton>(second)
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        Colors.transparent,
      );

      await mouse.moveTo(tester.getCenter(second));
      await tester.pump();
      expect(
        tester
            .widget<MenuItemButton>(first)
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        Colors.transparent,
      );
      expect(
        tester
            .widget<MenuItemButton>(second)
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        AccountingTokens.light.accent,
      );
    },
  );
}
