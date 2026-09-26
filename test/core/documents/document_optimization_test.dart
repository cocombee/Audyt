import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_optimization.dart';
import 'package:audyt/core/documents/receipt_document.dart';

void main() {
  Uint8List fixture() {
    final image = img.Image(width: 120, height: 80);
    for (final p in image) {
      final v = p.x < 60 ? 40 : 220;
      p.setRgb(v, v, v);
    }
    return img.encodePng(image);
  }

  test('levels clean grey paper and retain crop/rotation geometry', () {
    final source = fixture();
    final result = DocumentOptimizationEngine.renderSync(
      source,
      const DocumentOptimizationRecipe(
        black: 40,
        white: 220,
        rotation: 90,
        quality: 100,
      ),
    );
    expect(result.width, 80);
    expect(result.height, 120);
    final decoded = img.decodeJpg(result.jpeg)!;
    expect(decoded.getPixel(40, 10).r, lessThan(3));
    expect(decoded.getPixel(40, 110).r, greaterThan(252));
    expect(result.histogram.reduce((a, b) => a + b), 120 * 80);
    final crop = DocumentOptimizationEngine.renderSync(
      source,
      const DocumentOptimizationRecipe(right: 0.5),
    );
    expect(crop.width, 60);
    expect(crop.height, 80);
  });
  test('transparent white paper exports white rather than black in JPEG', () {
    final transparent = img.Image(width: 16, height: 16, numChannels: 4);
    final result = DocumentOptimizationEngine.renderSync(
      img.encodePng(transparent),
      const DocumentOptimizationRecipe(),
    );
    final decoded = img.decodeJpg(result.jpeg)!;
    expect(decoded.getPixel(8, 8).r, greaterThan(250));
  });
  test('invalid levels and crop fail before processing', () {
    for (final recipe in [
      const DocumentOptimizationRecipe(black: 220, white: 100),
      const DocumentOptimizationRecipe(gamma: 0),
      const DocumentOptimizationRecipe(left: 0.8, right: 0.2),
    ]) {
      expect(
        () => DocumentOptimizationEngine.renderSync(fixture(), recipe),
        throwsFormatException,
      );
    }
  });
  test(
    'editing keeps originals, persists recipe and invalidates stale PDF',
    () async {
      final source = fixture();
      final original = await const ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'scan',
          batchId: 'batch',
          filename: 'scan.png',
          mimeType: 'image/png',
          bytes: source,
        ),
      );
      final pdf = await const ReceiptDocumentPipeline().convertToPdf(original);
      expect(pdf.pdfBytes, isNotNull);
      const recipe = DocumentOptimizationRecipe(
        black: 35,
        white: 225,
        gamma: 1.2,
        rotation: 90,
      );
      final edited = await const DocumentOptimizationEngine().optimize(
        pdf,
        recipe,
      );
      expect(edited.originalBytes, source);
      expect(edited.originalSha256, original.originalSha256);
      expect(edited.preferredMimeType, 'image/jpeg');
      expect(edited.preferredBytes, edited.derivativeBytes);
      expect(edited.pdfBytes, isNull);
      final restored = ReceiptAttachment.fromJson(
        Map<String, dynamic>.from(edited.toJson()),
      );
      expect(restored.optimizationRecipe, recipe.toJson());
      final rerendered = await const DocumentOptimizationEngine().optimize(
        restored,
        recipe,
      );
      final expectedCurrentPixels = await const DocumentOptimizationEngine().render(restored.preferredBytes, recipe);
      expect(rerendered.preferredBytes, orderedEquals(expectedCurrentPixels.jpeg));
      expect(rerendered.originalSha256, original.originalSha256);
      final exported = await const ReceiptDocumentPipeline().convertToPdf(
        restored,
      );
      expect(exported.pdfBytes, isNotNull);
    },
  );
}
