import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Users keep equal frames with a larger check and smaller reject X',
    (tester) async {
      const capture = ValueKey('users-icons-capture');
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Builder(
                      builder: (context) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AccountingButton.iconOnly(
                            context,
                            key: const ValueKey('approve-peer'),
                            onPressed: () {},
                            icon: Icons.check,
                            iconAsset: '088-approval-check.svg',
                            iconPaintedSizeAdjustment: 2,
                            tooltip: 'Approve',
                            compact: true,
                          ),
                          const SizedBox(width: accountingRecordIconGap),
                          AccountingButton.iconOnly(
                            context,
                            key: const ValueKey('reject-peer'),
                            onPressed: () {},
                            icon: Icons.close,
                            iconAsset: '028-close.svg',
                            iconPaintedSizeAdjustment: -1,
                            tooltip: 'Reject',
                            compact: true,
                          ),
                          const SizedBox(width: 20),
                          AccountingButton.iconOnly(
                            context,
                            key: const ValueKey('approve-disabled-peer'),
                            onPressed: null,
                            icon: Icons.check,
                            iconAsset: '088-approval-check.svg',
                            iconPaintedSizeAdjustment: 2,
                            tooltip: 'Approve disabled',
                            compact: true,
                          ),
                          const SizedBox(width: accountingRecordIconGap),
                          AccountingButton.iconOnly(
                            context,
                            key: const ValueKey('reject-disabled-peer'),
                            onPressed: null,
                            icon: Icons.close,
                            iconAsset: '028-close.svg',
                            iconPaintedSizeAdjustment: -1,
                            tooltip: 'Reject disabled',
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'approve-peer',
        'reject-peer',
        'approve-disabled-peer',
        'reject-disabled-peer',
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))), const Size(32, 32));
      }
      // Measure the marks independently of unchanged button and SVG frames.
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 8);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final pixels = data!.buffer.asUint8List();
        Rect ink(String key) {
          final frame = tester.getRect(find.byKey(ValueKey(key)));
          final origin = tester.getRect(find.byKey(capture)).topLeft;
          final inner = frame.shift(-origin).deflate(7);
          var left = image.width, right = 0, top = image.height, bottom = 0;
          for (
            var y = (inner.top * 8).ceil();
            y < (inner.bottom * 8).floor();
            y++
          ) {
            for (
              var x = (inner.left * 8).ceil();
              x < (inner.right * 8).floor();
              x++
            ) {
              final i = (y * image.width + x) * 4;
              if (pixels[i] < 210 &&
                  pixels[i + 1] < 210 &&
                  pixels[i + 2] < 210) {
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                if (y > bottom) bottom = y;
              }
            }
          }
          return Rect.fromLTRB(
            left / 8,
            top / 8,
            (right + 1) / 8,
            (bottom + 1) / 8,
          );
        }

        final check = ink('approve-peer'), reject = ink('reject-peer');
        expect(check.width, closeTo(15.5, .25));
        expect(reject.width, closeTo(12.5, .25));
        const output = String.fromEnvironment('AUDYT_USERS_RENDER_DIR');
        if (output.isNotEmpty) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Users Approval Icons.png')
              .writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
      });
    },
  );

  testWidgets('metric artwork retains breathing room in its shared box', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: Row(
            children: [
              AccountingMetricIconBox(
                Icons.account_balance_outlined,
                iconSize: 19,
              ),
              AccountingMetricIconBox(Icons.payments_outlined, iconSize: 23),
              AccountingMetricIconBox(Icons.link_off_outlined, iconSize: 19),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxes = find.byType(AccountingMetricIconBox);
    final expected = [19.0, 23.0, 19.0];
    for (var i = 0; i < expected.length; i++) {
      final box = boxes.at(i);
      expect(tester.getSize(box), const Size(42, 42));
      final icon = find.descendant(
        of: box,
        matching: find.byType(AccountingIcon),
      );
      expect(tester.getSize(icon), Size.square(expected[i]));
      final frame = tester.getRect(box);
      final artwork = tester.getRect(
        find.descendant(of: icon, matching: find.byType(SvgPicture)),
      );
      // Check actual constrained SVG bounds as well as the requested size.
      // Doubling the money mark filled the frame and clipped its corners.
      expect(artwork.center, frame.center);
      expect(artwork.left - frame.left, greaterThanOrEqualTo(9.5));
      expect(frame.right - artwork.right, greaterThanOrEqualTo(9.5));
      expect(artwork.top - frame.top, greaterThanOrEqualTo(9.5));
      expect(frame.bottom - artwork.bottom, greaterThanOrEqualTo(9.5));
    }
  });

  test(
    'small icons follow the baseline, optical offsets, and exclusions',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const excluded = {22, 25, 26, 27, 62, 63, 68, 70};
      final assets =
          Directory('assets/icons/small')
              .listSync()
              .whereType<File>()
              .map((file) => file.uri.pathSegments.last)
              .where((name) {
                final number = int.tryParse(name.split('-').first);
                return number == 7 ||
                    (number != null &&
                        number >= 20 &&
                        number <= 77 &&
                        !excluded.contains(number));
              })
              .toList()
            ..sort();
      expect(assets.length, 51);
      for (final asset in assets) {
        final source = await rootBundle.loadString('assets/icons/small/$asset');
        final info = await vg.loadPicture(SvgStringLoader(source), null);
        final size = AccountingIcon.smallCanvasSizeForAsset(asset);
        final longestViewBoxSide = info.size.width > info.size.height
            ? info.size.width
            : info.size.height;
        final scale = size / longestViewBoxSide;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..scale(32)
          ..translate(
            4 + (size - info.size.width * scale) / 2,
            4 + (size - info.size.height * scale) / 2,
          )
          ..scale(scale);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        final image = await picture.toImage(768, 768);
        final data = (await image.toByteData())!.buffer.asUint8List();
        int left = 768, top = 768, right = -1, bottom = -1;
        for (var y = 0; y < 768; y++) {
          for (var x = 0; x < 768; x++) {
            if (data[(y * 768 + x) * 4 + 3] < 128) continue;
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        final longest =
            ((right - left) > (bottom - top)
                ? right - left + 1
                : bottom - top + 1) /
            32;
        final target = AccountingIcon.smallPaintedExtentForAsset(asset);
        expect(longest, inInclusiveRange(target - 0.1, target), reason: asset);
        info.picture.dispose();
        picture.dispose();
        image.dispose();
      }
    },
  );

  testWidgets('record and normal trash actions are exact squares', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('normal-trash'),
                  onPressed: () {},
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                ),
                AccountingButtonSizeScope(
                  child: AccountingButton.iconOnly(
                    context,
                    key: const ValueKey('small-trash'),
                    onPressed: () {},
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('normal-trash'))),
      const Size(44, 44),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('small-trash'))),
      const Size(32, 32),
    );
    for (final key in const ['normal-trash', 'small-trash']) {
      final style = tester.widget<IconButton>(find.byKey(ValueKey(key))).style!;
      expect(
        style.backgroundColor!.resolve({WidgetState.hovered}),
        AccountingColorLibrary.grapefruitDeep,
      );
      expect(
        style.foregroundColor!.resolve({WidgetState.hovered}),
        Colors.white,
      );
      expect(
        style.side!.resolve({WidgetState.hovered})!.color,
        AccountingColorLibrary.grapefruitDeep,
      );
      final mark = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AccountingIcon),
      );
      expect(tester.widget<AccountingIcon>(mark).icon, Icons.delete_outline);
      final expectedCanvas = AccountingIcon.rowCanvasSize(Icons.delete_outline);
      expect(tester.getSize(mark).width, closeTo(expectedCanvas, 0.01));
      expect(tester.getSize(mark).height, closeTo(expectedCanvas, 0.01));
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    for (final key in const ['normal-trash', 'small-trash']) {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pumpAndSettle();
      final mark = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AccountingIcon),
      );
      expect(tester.widget<AccountingIcon>(mark).color, Colors.white);
    }
  });
}
