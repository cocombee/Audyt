import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_crop_editor.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/profile_photo_editor.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('every handle preserves square pixels and stays inside portrait and landscape', () {
    for (final ratio in [0.5, 2.0, 1.0]) {
      final w = ratio < 1 ? ratio : 1.0;
      final h = w / ratio;
      for (final handle in CropHandle.values) {
        final history = CropEditHistory(
          normalizedAspectRatio: ratio,
          initial: NormalizedCropRect(
            left: (1 - w) / 2,
            top: (1 - h) / 2,
            right: (1 + w) / 2,
            bottom: (1 + h) / 2,
          ),
        );
        history.resize(handle, deltaX: .12, deltaY: -.15);
        history.updateTranslation(.7, -.8);
        history.updateRotation(42);
        history.endResize();
        final crop = history.present;
        expect(
          (crop.right - crop.left) / (crop.bottom - crop.top),
          closeTo(ratio, 1e-8),
        );
        expect(crop.left, greaterThanOrEqualTo(0));
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.right, lessThanOrEqualTo(1));
        expect(crop.bottom, lessThanOrEqualTo(1));
        expect(crop.rotation, 42);
        final restored = CropEditHistory.fromJson(history.toJson());
        expect(restored.normalizedAspectRatio, ratio);
        restored.dispose();
        history.dispose();
      }
    }
  });
  testWidgets(
    'minimal photo editor cancels without a result and saves square crop',
    (tester) async {
      final source = raster.Image(width: 240, height: 160);
      for (var y = 0; y < 160; y++) {
        for (var x = 0; x < 240; x++) {
          source.setPixelRgb(x, y, x, y, 120);
        }
      }
      final bytes = Uint8List.fromList(raster.encodePng(source));
      final original = List<int>.from(bytes);
      Completer<String?> result = Completer();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const capture = ValueKey('crop-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (_) => ProfilePhotoEditor(bytes: bytes),
                  ).then(result.complete),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      expect(find.byKey(const ValueKey('accounting-crop-undo')), findsNothing);
      final editor = tester.widget<AccountingCropReviewEditor>(
        find.byType(AccountingCropReviewEditor),
      );
      expect(editor.circularPreview, isTrue);
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(ProfilePhotoEditor)),
        ),
      );
      await tester.pumpAndSettle();
      for (final width in [900.0, 390.0]) {
        await tester.binding.setSurfaceSize(Size(width, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('AUDYT_USERS_RENDER_DIR');
        if (output.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/Profile Photo Editor $width.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.tap(find.byKey(const ValueKey('cancel-profile-crop')));
      await tester.pumpAndSettle();
      expect(await result.future, isNull);
      expect(bytes, original);
      result = Completer();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-profile-crop')));
      for (var attempt = 0; attempt < 40 && !result.isCompleted; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(
        result.isCompleted,
        isTrue,
        reason: 'Crop should complete without blocking the UI',
      );
      if (result.isCompleted) {
        final saved = await result.future;
        final image = raster.decodeImage(base64Decode(saved!))!;
        expect(image.width, 256);
        expect(image.height, 256);
        expect(bytes, original);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-photo-editor')), findsNothing);
    },
  );
}
