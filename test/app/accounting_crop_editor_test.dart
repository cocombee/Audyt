import 'dart:typed_data';

import 'package:audyt/app/accounting_crop_editor.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets(
    'renders the shared crop frame, handles, compact history controls, and labels',
    (tester) async {
      final history = CropEditHistory();
      addTearDown(history.dispose);
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 40, height: 30)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AccountingCropReviewEditor(
                imageBytes: bytes,
                cropHistory: history,
                imageWidth: 40,
                imageHeight: 30,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('accounting-crop-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-frame')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-top-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-top-right')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-right')),
        findsOneWidget,
      );

      final undo = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('accounting-crop-undo')),
      );
      final redo = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('accounting-crop-redo')),
      );
      expect(undo.onPressed, isNull);
      expect(redo.onPressed, isNull);
      expect(find.byTooltip('Undo crop change'), findsOneWidget);
      expect(find.byTooltip('Redo crop change'), findsOneWidget);
      expect(find.bySemanticsLabel('Crop frame'), findsOneWidget);
      expect(find.bySemanticsLabel('Top left crop handle'), findsOneWidget);
    },
  );

  testWidgets(
    'shared crop controls update history and undo/redo the exact draft',
    (tester) async {
      final history = CropEditHistory();
      addTearDown(history.dispose);
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 40, height: 30)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingCropReviewEditor(
              imageBytes: bytes,
              cropHistory: history,
              imageWidth: 40,
              imageHeight: 30,
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-right')),
        const Offset(-24, -18),
      );
      await tester.pump();
      final edited = history.present;
      expect(history.canUndo, isTrue);
      expect(edited, isNot(NormalizedCropRect.full));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('accounting-crop-redo')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
      await tester.pump();
      expect(history.present, NormalizedCropRect.full);

      await tester.tap(find.byKey(const ValueKey('accounting-crop-redo')));
      await tester.pump();
      expect(history.present, edited);
    },
  );

  testWidgets('shared crop geometry stays contained at a narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final history = CropEditHistory();
    addTearDown(history.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountingCropReviewEditor(
            imageBytes: Uint8List.fromList(
              image.encodeJpg(image.Image(width: 120, height: 80)),
            ),
            cropHistory: history,
            imageWidth: 120,
            imageHeight: 80,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final preview = tester.getRect(
      find.byKey(const ValueKey('accounting-crop-preview')),
    );
    final frame = tester.getRect(
      find.byKey(const ValueKey('accounting-crop-frame')),
    );
    expect(frame.left, greaterThanOrEqualTo(preview.left));
    expect(frame.top, greaterThanOrEqualTo(preview.top));
    expect(frame.right, lessThanOrEqualTo(preview.right));
    expect(frame.bottom, lessThanOrEqualTo(preview.bottom));
  });
}
