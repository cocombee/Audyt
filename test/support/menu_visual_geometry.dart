import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> capture(GlobalKey key, String name, WidgetTester tester) async {
  final output = Platform.environment['AUDYT_VISUAL_OUTPUT'];
  if (output == null) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Rect labelRect(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final label = tester.widget<Text>(text).data!;
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      )
      .single;
  return box.toRect().shift(paragraph.localToGlobal(Offset.zero));
}

/// Locate the actual flat highlight colour, excluding transparent hit padding.
Future<Rect> paintedSurfaceBounds(
  WidgetTester tester,
  GlobalKey key,
  Finder area,
  Color color,
) async {
  await tester.pumpAndSettle();
  late Rect result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final origin = boundary.localToGlobal(Offset.zero);
    final crop = tester.getRect(area).shift(-origin);
    const scale = 2.0;
    final image = await boundary.toImage(pixelRatio: scale);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final argb = color.toARGB32();
    final red = (argb >> 16) & 255;
    final green = (argb >> 8) & 255;
    final blue = argb & 255;
    var x0 = image.width, y0 = image.height, x1 = -1, y1 = -1;
    for (
      var y = (crop.top * scale).floor().clamp(0, image.height - 1);
      y < (crop.bottom * scale).ceil().clamp(0, image.height);
      y++
    ) {
      for (
        var x = (crop.left * scale).floor().clamp(0, image.width - 1);
        x < (crop.right * scale).ceil().clamp(0, image.width);
        x++
      ) {
        final i = (y * image.width + x) * 4;
        if ((bytes[i] - red).abs() <= 1 &&
            (bytes[i + 1] - green).abs() <= 1 &&
            (bytes[i + 2] - blue).abs() <= 1 &&
            bytes[i + 3] == 255) {
          x0 = x0 < x ? x0 : x;
          y0 = y0 < y ? y0 : y;
          x1 = x1 > x ? x1 : x;
          y1 = y1 > y ? y1 : y;
        }
      }
    }
    image.dispose();
    expect(
      x1,
      greaterThanOrEqualTo(x0),
      reason: 'The agreed highlight colour must be painted',
    );
    result = Rect.fromLTRB(
      x0 / scale,
      y0 / scale,
      (x1 + 1) / scale,
      (y1 + 1) / scale,
    ).shift(origin);
  });
  return result;
}

/// Measure real painted pixels. Text line boxes and transparent SVG margins
/// deliberately do not count as visible edges.
Future<Rect> paintedBounds(
  WidgetTester tester,
  GlobalKey key,
  Finder area, {
  int cutoff = 180,
}) async {
  Rect? result;
  for (var attempt = 0; attempt < 3 && result == null; attempt++) {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final origin = boundary.localToGlobal(Offset.zero);
      final crop = tester.getRect(area).shift(-origin);
      const scale = 8.0;
      final image = await boundary.toImage(pixelRatio: scale);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      var x0 = image.width, y0 = image.height, x1 = -1, y1 = -1;
      for (
        var y = (crop.top * scale).floor().clamp(0, image.height - 1);
        y < (crop.bottom * scale).ceil().clamp(0, image.height);
        y++
      ) {
        for (
          var x = (crop.left * scale).floor().clamp(0, image.width - 1);
          x < (crop.right * scale).ceil().clamp(0, image.width);
          x++
        ) {
          final i = (y * image.width + x) * 4;
          if (bytes[i] < cutoff &&
              bytes[i + 1] < cutoff &&
              bytes[i + 2] < cutoff &&
              bytes[i + 3] >= 128) {
            x0 = x0 < x ? x0 : x;
            y0 = y0 < y ? y0 : y;
            x1 = x1 > x ? x1 : x;
            y1 = y1 > y ? y1 : y;
          }
        }
      }
      if (x1 >= x0) {
        result = Rect.fromLTRB(
          x0 / scale,
          y0 / scale,
          (x1 + 1) / scale,
          (y1 + 1) / scale,
        ).shift(origin);
      }
      image.dispose();
    });
  }
  expect(
    result,
    isNotNull,
    reason: 'The requested area must contain visible ink after vector loading',
  );
  return result!;
}
