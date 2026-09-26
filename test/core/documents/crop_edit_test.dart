import 'package:audyt/core/documents/crop_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clamps crop edits to normalized image bounds', () {
    final history = CropEditHistory();

    history.apply(NormalizedCropRect.fromLTRB(-0.2, 0.1, 1.2, 1.4));

    expect(
      history.present,
      const NormalizedCropRect(left: 0, top: 0.1, right: 1, bottom: 1),
    );
  });

  test('undo and redo restore the exact crop draft', () {
    final history = CropEditHistory();
    const edited = NormalizedCropRect(
      left: 0.1,
      top: 0.15,
      right: 0.82,
      bottom: 0.88,
    );

    history.apply(edited);
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    history.undo();
    expect(history.present, NormalizedCropRect.full);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isTrue);

    history.redo();
    expect(history.present, edited);
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);
  });

  test(
    'a new edit after undo clears redo history and reset clears all history',
    () {
      final history = CropEditHistory();
      const first = NormalizedCropRect(
        left: 0.05,
        top: 0.05,
        right: 0.9,
        bottom: 0.9,
      );
      const second = NormalizedCropRect(
        left: 0.2,
        top: 0.1,
        right: 0.75,
        bottom: 0.8,
      );

      history.apply(first);
      history.undo();
      history.apply(second);

      expect(history.present, second);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      history.reset();
      expect(history.present, NormalizedCropRect.full);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    },
  );

  test('corner resizing keeps a usable crop inside the image', () {
    final history = CropEditHistory();

    history.resize(CropHandle.topLeft, deltaX: -2, deltaY: -2);
    expect(history.present.left, greaterThanOrEqualTo(0));
    expect(history.present.top, greaterThanOrEqualTo(0));
    expect(
      history.present.right - history.present.left,
      greaterThanOrEqualTo(0.1),
    );
    expect(
      history.present.bottom - history.present.top,
      greaterThanOrEqualTo(0.1),
    );

    history.resize(CropHandle.bottomRight, deltaX: 2, deltaY: 2);
    expect(history.present.right, lessThanOrEqualTo(1));
    expect(history.present.bottom, lessThanOrEqualTo(1));
  });
}
