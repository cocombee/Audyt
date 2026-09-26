import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final right in [false, true]) {
    testWidgets(
      'menu stays below ${right ? 'right' : 'left'} trigger in a short window',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(640, 360));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var chosen = '';
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    top: 220,
                    left: right ? null : 20,
                    right: right ? 20 : null,
                    child: AccountingMenuAnchor(
                      menuWidth: 220,
                      maxHeight: 520,
                      menuChildren: [
                        for (var i = 0; i < 15; i++)
                          MenuItemButton(
                            key: ValueKey('choice-$i'),
                            onPressed: () => chosen = '$i',
                            child: Text('Choice $i'),
                          ),
                      ],
                      builder: (context, controller, child) => SizedBox(
                        width: 32,
                        height: 32,
                        child: TextButton(
                          key: const ValueKey('trigger'),
                          onPressed: () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                          child: const Text('…'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('trigger')));
        await tester.pumpAndSettle();
        final trigger = tester.getRect(find.byKey(const ValueKey('trigger')));
        final first = tester.getRect(find.byKey(const ValueKey('choice-0')));
        expect(first.top, greaterThanOrEqualTo(trigger.bottom));
        final panel = find
            .ancestor(
              of: find.byKey(const ValueKey('choice-0')),
              matching: find.byType(Material),
            )
            .first;
        final surface = tester.getRect(panel);
        expect(surface.top, closeTo(trigger.bottom + 4, 0.1));
        expect(surface.bottom, lessThanOrEqualTo(352));
        expect(
          right ? surface.right : surface.left,
          closeTo(right ? trigger.right : trigger.left, 0.1),
        );
        await tester.tap(find.byKey(const ValueKey('choice-0')));
        await tester.pumpAndSettle();
        expect(chosen, '0');
        expect(find.byKey(const ValueKey('choice-0')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('trigger')));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -1000),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('choice-14')));
        await tester.pumpAndSettle();
        expect(chosen, '14');

        expect(tester.takeException(), isNull);
      },
    );
  }
}
