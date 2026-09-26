import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// An expanded reference retains the exact paths and their painted size while
// removing the source viewBox clip. Any clipped stroke would appear only there.
void main() {
  for (final entry in <(String, String, Widget, double)>[
    (
      'Restore',
      '051-restore.svg',
      const AccountingIcon.smallAction(Icons.restore, color: Colors.black),
      accountingRecordVisibleIconExtent,
    ),
    (
      'Reset',
      '051-restore.svg',
      const AccountingIcon(Icons.restart_alt, size: 15.3, color: Colors.black),
      15.3,
    ),
    (
      'History',
      '042-history.svg',
      const AccountingIcon.smallAction(
        Icons.history_outlined,
        color: Colors.black,
      ),
      accountingRecordVisibleIconExtent,
    ),
  ]) {
    testWidgets('${entry.$1} retains every painted edge of the approved SVG', (
      tester,
    ) async {
      final source = (await tester.runAsync(
        () => rootBundle.loadString(
          'assets/icons/small/${entry.$2}',
          cache: false,
        ),
      ))!;
      final match = RegExp('viewBox="([^"]+)"').firstMatch(source)!;
      final box = match.group(1)!.split(' ').map(double.parse).toList();
      const margin = 4.0;
      final expanded = source.replaceFirst(
        match.group(0)!,
        'viewBox="${box[0] - margin} ${box[1] - margin} ${box[2] + 2 * margin} ${box[3] + 2 * margin}"',
      );
      final size = entry.$4 * (box[2] + 2 * margin) / box[2];
      final actualKey = GlobalKey();
      final referenceKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                RepaintBoundary(
                  key: actualKey,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(child: entry.$3),
                  ),
                ),
                RepaintBoundary(
                  key: referenceKey,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: SizedBox.square(
                        dimension: size,
                        child: SvgPicture.string(
                          expanded,
                          colorFilter: const ColorFilter.mode(
                            Colors.black,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final actual =
            await (actualKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 16);
        final reference =
            await (referenceKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 16);
        final a = (await actual.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        final b = (await reference.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var missing = 0;
        var excess = 0;
        var ink = 0;
        for (var i = 3; i < a.length; i += 4) {
          ink += b[i];
          if (b[i] > a[i]) missing += b[i] - a[i];
          if (a[i] > b[i]) excess += a[i] - b[i];
        }
        expect(
          missing / ink,
          lessThan(.002),
          reason: 'Expanded reference must not reveal clipped strokes',
        );
        expect(
          excess / ink,
          lessThan(.002),
          reason: 'Approved paths and physical weight must be preserved',
        );
        final dir = Platform.environment['AUDYT_RESET_ICON_DIR'];
        if (dir != null) {
          await File('$dir/${entry.$1} Actual.png').writeAsBytes(
            (await actual.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          await File('$dir/${entry.$1} Expanded Reference.png').writeAsBytes(
            (await reference.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          await File('$dir/${entry.$1} Edge Check.txt').writeAsString(
            'Approved asset: ${entry.$2}\nPainted target: ${entry.$4}px\nMissing ink fraction: ${missing / ink}\nExcess ink fraction: ${excess / ink}\n',
          );
        }
        actual.dispose();
        reference.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
