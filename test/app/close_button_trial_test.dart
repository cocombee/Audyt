import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'summary_action_wiring_test.dart' show view;

void main() {
  testWidgets(
    'Remove matches the add glyph inside the shared compact action frame',
    (tester) async {
      await view(tester, 720);
      tester.view.physicalSize = const Size(720, 260);
      var closes = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const SizedBox(height: 30),
                    const Text('Previous Close / Close / Remove / Add'),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox.square(
                          dimension: 28,
                          child: Center(
                            child: AccountingIcon(
                              Icons.close,
                              size: 15.3,
                              color: AccountingColorLibrary.grapefruitDeep,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                        accountingCompactClose(
                          context,
                          key: const ValueKey('trial-close'),
                          onPressed: () => closes++,
                        ),
                        const SizedBox(width: 40),
                        accountingCompactRemove(
                          context,
                          key: const ValueKey('trial-remove'),
                          onPressed: () => closes += 10,
                        ),
                        const SizedBox(width: 40),
                        accountingCompactAdd(
                          context,
                          key: const ValueKey('trial-add'),
                          onPressed: () {},
                        ),
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
      final trial = find.byKey(const ValueKey('trial-close'));
      final add = find.byKey(const ValueKey('trial-add'));
      expect(
        tester.getSize(trial),
        tester.getSize(find.byKey(const ValueKey('trial-remove'))),
      );
      expect(tester.getSize(trial), tester.getSize(add));
      expect(tester.getSize(trial), const Size(20, 20));
      final button = tester.widget<IconButton>(trial);
      expect(
        button.constraints,
        const BoxConstraints.tightFor(width: 28, height: 28),
      );
      expect(button.visualDensity, VisualDensity.compact);
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      expect(
        button.style!.backgroundColor!.resolve({}),
        AccountingColorLibrary.grapefruit,
      );
      final old = find.byType(AccountingIcon);
      final replacement = find.byType(AccountingCloseIcon);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('workspace-capture')),
        );
        const factor = 16;
        final image = await boundary.toImage(pixelRatio: factor.toDouble());
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        bool ink(double x, double y, {bool white = false}) {
          final i =
              ((y * factor).floor() * image.width + (x * factor).floor()) * 4;
          return white
              ? pixels.getUint8(i + 1) > 210 && pixels.getUint8(i + 2) > 210
              : pixels.getUint8(i) - pixels.getUint8(i + 1) > 75;
        }

        double longest(Finder item) {
          final box = tester.getRect(item);
          var left = image.width, right = 0, top = image.height, bottom = 0;
          for (
            var y = (box.top * factor).floor();
            y < (box.bottom * factor).ceil();
            y++
          ) {
            for (
              var x = (box.left * factor).floor();
              x < (box.right * factor).ceil();
              x++
            ) {
              if (!ink(x / factor, y / factor, white: item != old)) continue;
              left = math.min(left, x);
              right = math.max(right, x);
              top = math.min(top, y);
              bottom = math.max(bottom, y);
            }
          }
          return math.max(right - left + 1, bottom - top + 1) / factor;
        }

        double line(Finder item, {bool dash = false}) {
          final svg = find.descendant(
            of: item,
            matching: find.byType(SvgPicture),
          );
          final box = tester.getRect(svg);
          final point =
              box.topLeft +
              Offset(
                box.width * (dash ? 12 : 7.2) / 24,
                box.height * (dash ? 12 : 7.2) / 24,
              );
          var count = 0;
          for (var step = -3 * factor; step <= 3 * factor; step++) {
            final d = step / factor;
            if (ink(
              point.dx + (dash ? 0 : d / math.sqrt(2)),
              point.dy - (dash ? d : d / math.sqrt(2)),
              white: item != old,
            )) {
              count++;
            }
          }
          return count / factor;
        }

        double horizontalStroke(Finder item) {
          final box = tester.getRect(item);
          final x = box.center.dx + 2.5;
          var count = 0;
          for (var step = -3 * factor; step <= 3 * factor; step++) {
            if (ink(x, box.center.dy + step / factor, white: true)) count++;
          }
          return count / factor;
        }

        expect(longest(replacement) / longest(old), closeTo(.75, .025));
        expect(line(replacement) / line(old), closeTo(1.5, .08));
        final remove = find.byType(AccountingRemoveIcon);
        expect(longest(remove), closeTo(longest(replacement), .25));
        expect(
          longest(find.byType(AccountingAddIcon)),
          closeTo(longest(replacement), .25),
        );
        expect(line(remove, dash: true), closeTo(line(replacement), .6));
        expect(horizontalStroke(remove), closeTo(horizontalStroke(add), .6));
        image.dispose();
      });
      await captureUi(tester, 'Close And Remove Family');
      await tester.tap(trial);
      expect(closes, 1);
      await tester.tap(find.byKey(const ValueKey('trial-remove')));
      expect(closes, 11);
      expect(tester.takeException(), isNull);
    },
  );
}
