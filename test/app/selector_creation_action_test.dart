import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final grouped in [false, true]) {
    testWidgets(
      'creation row remains available without selecting a data value; grouped=$grouped',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(720, 895));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var selected = 0;
        var invocations = 0;
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
                      assignedWidth: 360,
                      menuMaxHeight: 280,
                      value: selected,
                      hintText: 'Choose item',
                      triggerKey: const ValueKey('trigger'),
                      searchKey: const ValueKey('search'),
                      options: [
                        for (var i = 0; i < 10; i++)
                          AccountingSelectorOption(
                            value: i,
                            label: 'Item $i',
                            key: ValueKey('item-$i'),
                            group: grouped ? 'Items' : null,
                          ),
                        AccountingSelectorOption(
                          value: -1,
                          label: 'Add Item',
                          key: const ValueKey('add'),
                          leading: const AccountingIcon(Icons.add_rounded),
                          onPressed: () => invocations++,
                        ),
                      ],
                      onChanged: (value) => setState(() => selected = value!),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final add = find.byKey(const ValueKey('add'));
        final input = find.byKey(const ValueKey('search'));
        await tester.tap(find.byKey(const ValueKey('trigger')));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(add));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MenuItemButton>(find.byKey(const ValueKey('item-0')))
              .style!
              .backgroundColor!
              .resolve({}),
          AccountingTokens.light.primary.withValues(alpha: 0.10),
        );
        expect(
          tester
              .widget<MenuItemButton>(add)
              .style!
              .backgroundColor!
              .resolve({}),
          AccountingTokens.light.accent,
        );
        final addTop = tester.getTopLeft(add).dy;
        expect(
          addTop,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('item-0'))).dy),
        );
        await tester.drag(
          find.byKey(const ValueKey('accounting-selector-menu-scroll')),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(add).dy, lessThan(addTop));
        await tester.drag(
          find.byKey(const ValueKey('accounting-selector-menu-scroll')),
          const Offset(0, 250),
        );
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(invocations, 1);
        expect(selected, 0);
        await tester.tap(find.byKey(const ValueKey('trigger')));
        await tester.pumpAndSettle();
        await tester.enterText(input, 'Item 1');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(invocations, 1);
        await tester.tap(find.byKey(const ValueKey('trigger')));
        await tester.pumpAndSettle();
        await tester.enterText(input, 'A new item that does not exist');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('item-0')), findsNothing);
        expect(add, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(invocations, 2);
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
