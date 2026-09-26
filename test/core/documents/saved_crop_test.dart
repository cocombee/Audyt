import 'package:audyt/core/documents/document_optimization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/crop_edit.dart';

void main() {
  test(
    'rotation shares crop undo and preserves upright output geometry',
    () async {
      final history = CropEditHistory();
      history.updateRotation(45);
      history.updateRotation(90);
      history.endResize();
      final restored = CropEditHistory.fromJson(history.toJson());
      expect(restored.present.rotation, 90);
      restored.undo();
      expect(restored.present.rotation, 0);
      expect(restored.canUndo, false);
      restored.redo();
      final source = image.Image(width: 20, height: 20);
      image.fill(source, color: image.ColorRgb8(255, 0, 0));
      image.fillRect(
        source,
        x1: 10,
        y1: 0,
        x2: 19,
        y2: 19,
        color: image.ColorRgb8(0, 255, 0),
      );
      const pipeline = ReceiptDocumentPipeline();
      final attachment = await pipeline.process(
        ReceiptAttachmentInput(
          originalId: 'rotation',
          batchId: 'batch',
          filename: 'rotation.png',
          mimeType: 'image/png',
          bytes: image.encodePng(source),
        ),
      );
      final result = await pipeline.crop(attachment, restored.present);
      final pixels = image.decodeImage(result.preferredBytes)!;
      expect(pixels.width, 20);
      expect(pixels.height, 20);
      expect(pixels.getPixel(10, 3).r, greaterThan(240));
      expect(pixels.getPixel(10, 16).g, greaterThan(240));
      expect(result.originalSha256, attachment.originalSha256);
      history.dispose();
      restored.dispose();
    },
  );
  test('recrop stays inside saved pixels without another JPEG pass', () async {
    final source = image.Image(width: 100, height: 80);
    image.fill(source, color: image.ColorRgb8(255, 0, 0));
    image.fillRect(
      source,
      x1: 50,
      y1: 0,
      x2: 99,
      y2: 79,
      color: image.ColorRgb8(0, 255, 0),
    );
    const pipeline = ReceiptDocumentPipeline();
    final original = await pipeline.process(
      ReceiptAttachmentInput(
        originalId: 'crop',
        batchId: 'batch',
        filename: 'scan.png',
        mimeType: 'image/png',
        bytes: image.encodePng(source),
      ),
    );
    final first = await pipeline.crop(
      original,
      const NormalizedCropRect(left: .5, top: 0, right: 1, bottom: 1),
    );
    final saved = ReceiptAttachment.fromJson(first.toJson());
    final second = await pipeline.crop(
      saved,
      const NormalizedCropRect(left: 0, top: 0, right: .5, bottom: 1),
    );
    final decoded = image.decodeImage(second.preferredBytes)!;
    expect(decoded.width, 25);
    expect(decoded.height, 80);
    expect(decoded.getPixel(0, 0).g, 255);
    expect(decoded.getPixel(0, 0).r, 0);
    expect(second.preferredMimeType, 'image/png');
    expect(second.originalSha256, original.originalSha256);
    final optimized = await const DocumentOptimizationEngine().optimize(
      second,
      const DocumentOptimizationRecipe(gamma: 1.1),
    );
    final optimizedPixels = image.decodeImage(optimized.preferredBytes)!;
    expect(optimizedPixels.width, 25);
    expect(optimizedPixels.height, 80);
    expect(optimizedPixels.getPixel(0, 0).r, lessThan(10));
    expect(optimized.originalSha256, original.originalSha256);
    final third = await pipeline.crop(
      second,
      const NormalizedCropRect(left: 0, top: 0, right: .5, bottom: 1),
    );
    expect(third.derivativeId, isNot(second.derivativeId));
    expect(
      image.decodeImage(third.preferredBytes)!.width,
      lessThan(decoded.width),
    );
  });
}
