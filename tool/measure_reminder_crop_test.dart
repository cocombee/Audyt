// Run explicitly with AUDYT_REMINDER_CROP_BOUNDS set to the canonical JSON.
// Measure the actual SVG renderer, including strokes/transforms/clips, rather
// than estimating the crop from path control points or nominal viewBoxes.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('measure transparent margins of the 44 original reminder SVGs', (
    tester,
  ) async {
    final results = <String, Object>{};
    await tester.runAsync(() async {
      for (final name in reminderSelectableIcons.values) {
        final source = File('assets/icons/reminder_originals/$name')
            .readAsStringSync();
        final tag = RegExp(r'<svg\b[^>]*>').firstMatch(source)!;
        final view = RegExp(r'viewBox="([^"]+)"')
            .firstMatch(tag.group(0)!)!
            .group(1)!
            .split(RegExp(r'[ ,]+'))
            .map(double.parse)
            .toList();
        // Reveal outer strokes too, without modifying explicit internal clips.
        final padding = math.max(view[2], view[3]) / 4;
        final expanded = [
          view[0] - padding,
          view[1] - padding,
          view[2] + padding * 2,
          view[3] + padding * 2,
        ];
        final newTag = tag
            .group(0)!
            .replaceAll(RegExp(r'\s(?:width|height)="[^"]*"'), '')
            .replaceFirst(
              RegExp(r'viewBox="[^"]+"'),
              'viewBox="${expanded.join(' ')}"',
            );
        final input = source.replaceRange(tag.start, tag.end, newTag);
        final info = await vg.loadPicture(SvgStringLoader(input), null);
        final scale = 4096 / math.max(info.size.width, info.size.height);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(scale);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        final width = (info.size.width * scale).ceil();
        final height = (info.size.height * scale).ceil();
        final image = await picture.toImage(width, height);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var left = width, top = height, right = -1, bottom = -1;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            if (data.getUint8((y * width + x) * 4 + 3) == 0) continue;
            left = math.min(left, x);
            top = math.min(top, y);
            right = math.max(right, x);
            bottom = math.max(bottom, y);
          }
        }
        expect(right, greaterThan(left), reason: name);
        expect(
          left,
          greaterThan(2),
          reason: 'Expanded canvas must contain $name',
        );
        expect(top, greaterThan(2), reason: name);
        expect(right, lessThan(width - 3), reason: name);
        expect(bottom, lessThan(height - 3), reason: name);
        // Retain a two-raster-pixel guard for antialiasing at every display size.
        results[name] = [
          expanded[0] + (left - 2) / scale,
          expanded[1] + (top - 2) / scale,
          (right - left + 5) / scale,
          (bottom - top + 5) / scale,
        ];
        image.dispose();
        picture.dispose();
        info.picture.dispose();
      }
      final destination = Platform.environment['AUDYT_REMINDER_CROP_BOUNDS'];
      if (destination == null) {
        throw StateError('Set AUDYT_REMINDER_CROP_BOUNDS');
      }
      File(destination).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(results)}\n',
      );
    });
    expect(results, hasLength(44));
  });
}
