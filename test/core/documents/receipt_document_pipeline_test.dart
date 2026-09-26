import 'package:audyt/core/documents/document_optimization.dart';
import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'imports JPEG without creating or selecting an encoded derivative',
    () async {
      final original = _jpeg(width: 1200, height: 900, quality: 100);
      final processed = await ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'original-1',
          batchId: 'batch-1',
          filename: 'receipt.jpg',
          mimeType: 'image/jpeg',
          bytes: original,
        ),
      );

      expect(processed.status, AttachmentProcessingStatus.ready);
      expect(processed.originalId, 'original-1');
      expect(processed.derivativeId, 'original-1-derivative');
      expect(processed.batchId, 'batch-1');
      expect(processed.originalBytes, orderedEquals(original));
      expect(processed.originalSha256, isNotEmpty);
      expect(processed.derivativeBytes, isNull);
      expect(processed.derivativeByteSize, isNull);
      expect(processed.derivativeSha256, isNull);
      expect(
        processed.preferredBytes,
        orderedEquals(original),
      );
      expect(processed.originalWidth, 1200);
      expect(processed.originalHeight, 900);
      expect(processed.originalBytes, isNot(equals(processed.derivativeBytes)));
    },
  );

  test('keeps print-safe original dimensions without encoding', () async {
    final original = _jpeg(width: 2480, height: 3508, quality: 92);
    final processed = await ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'print-safe-original',
        batchId: 'print-safe-batch',
        filename: 'print-safe.jpg',
        mimeType: 'image/jpeg',
        bytes: original,
      ),
    );

    expect(processed.printReadyAt300Dpi, isTrue);
    expect(processed.originalWidth, 2480);
    expect(processed.originalHeight, 3508);
    expect(processed.preferredBytes, orderedEquals(original));
    expect(processed.derivativeBytes, isNull);
    expect(processed.reductionPercent, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('does not upscale an insufficient source', () async {
    final original = _jpeg(width: 640, height: 480, quality: 90);
    final processed = await ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'small-original',
        batchId: 'small-batch',
        filename: 'small.jpg',
        mimeType: 'image/jpeg',
        bytes: original,
      ),
    );

    expect(processed.originalWidth, 640);
    expect(processed.originalHeight, 480);
    expect(processed.printReadyAt300Dpi, isFalse);
    expect(processed.preferredBytes, orderedEquals(original));
    expect(processed.derivativeBytes, isNull);
  });

  test(
    'explicit optimization caps an unchanged oversized upload to A4 bounds',
    () async {
      final processed = await ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'oversized-original',
          batchId: 'oversized-batch',
          filename: 'oversized.jpg',
          mimeType: 'image/jpeg',
          bytes: _jpeg(width: 4000, height: 5000, quality: 90),
        ),
      );

      expect(processed.originalWidth, 4000);
      expect(processed.originalHeight, 5000);
      expect(processed.derivativeBytes, isNull);
      expect(processed.preferredBytes, orderedEquals(processed.originalBytes));
      final optimized = DocumentOptimizationEngine.renderSync(processed.preferredBytes, const DocumentOptimizationRecipe());
      expect(optimized.width, lessThanOrEqualTo(1754));
      expect(optimized.height, lessThanOrEqualTo(2480));
      expect(optimized.width, lessThan(4000));
      expect(optimized.height, lessThan(5000));
      expect(image.decodeJpg(optimized.jpeg)!.width, optimized.width);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('keeps portrait source intact and fits its aspect ratio only on optimization', () async {
    final processed = await ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'a4-bounded-original',
        batchId: 'a4-bounded-batch',
        filename: 'a4-bounded.jpg',
        mimeType: 'image/jpeg',
        bytes: _jpeg(width: 4000, height: 5000, quality: 90),
      ),
    );

    expect(processed.originalWidth, 4000);
    expect(processed.originalHeight, 5000);
    expect(processed.derivativeBytes, isNull);
    expect(processed.preferredBytes, orderedEquals(processed.originalBytes));
    expect(processed.printReadyAt300Dpi, isTrue);
    final fitted = a4OutputSize(processed.originalWidth!, processed.originalHeight!);
    expect(fitted.width, 1754);
    expect(fitted.height, 2193);
    expect(fitted.height, lessThan(2480));
    expect(fitted.width / fitted.height, closeTo(4000 / 5000, 0.001));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('preserves PDFs and only exposes PDF conversion for images', () async {
    final original = Uint8List.fromList('%PDF-1.7\nlocal receipt'.codeUnits);
    final processed = await ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'pdf-original',
        batchId: 'pdf-batch',
        filename: 'receipt.pdf',
        mimeType: 'application/pdf',
        bytes: original,
      ),
    );

    expect(processed.status, AttachmentProcessingStatus.ready);
    expect(processed.originalBytes, orderedEquals(original));
    expect(processed.derivativeBytes, isNull);
    expect(processed.canConvertToPdf, isFalse);
    expect(processed.preferredBytes, orderedEquals(original));
  });

  test(
    'keeps batch lineage across multiple independently processed files',
    () async {
      final batch = await ReceiptDocumentPipeline().processBatch(
        <ReceiptAttachmentInput>[
          ReceiptAttachmentInput(
            originalId: 'batch-original-1',
            batchId: 'ignored-by-batch',
            filename: 'one.jpg',
            mimeType: 'image/jpeg',
            bytes: _jpeg(width: 320, height: 240, quality: 90),
          ),
          ReceiptAttachmentInput(
            originalId: 'batch-original-2',
            batchId: 'ignored-by-batch',
            filename: 'two.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
          ),
        ],
        batchId: 'batch-lineage',
      );

      expect(batch.id, 'batch-lineage');
      expect(batch.attachments, hasLength(2));
      expect(
        batch.attachments.map((item) => item.batchId),
        everyElement('batch-lineage'),
      );
      expect(
        batch.attachments.map((item) => item.originalId),
        containsAll(<String>['batch-original-1', 'batch-original-2']),
      );
    },
  );

  test('crop and PDF conversion create separate local derivatives', () async {
    final processed = await ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'actions-original',
        batchId: 'actions-batch',
        filename: 'actions.jpg',
        mimeType: 'image/jpeg',
        bytes: _jpeg(width: 800, height: 600, quality: 95),
      ),
    );

    final cropped = await ReceiptDocumentPipeline().cropCenter(processed);
    expect(cropped.originalBytes, orderedEquals(processed.originalBytes));
    expect(cropped.derivativeWidth, lessThan(processed.originalWidth!));
    expect(cropped.derivativeHeight, lessThan(processed.originalHeight!));
    expect(cropped.derivativeId, contains('crop'));

    final converted = await ReceiptDocumentPipeline().convertToPdf(processed);
    expect(converted.originalBytes, orderedEquals(processed.originalBytes));
    expect(converted.pdfBytes, isNotNull);
    expect(converted.pdfBytes!.take(4), orderedEquals('%PDF'.codeUnits));
    expect(converted.pdfSha256, isNotNull);
    expect(converted.canConvertToPdf, isTrue);
  });
}

Uint8List _jpeg({
  required int width,
  required int height,
  required int quality,
}) {
  final source = image.Image(width: width, height: height);
  for (final pixel in source) {
    pixel
      ..r = (pixel.x * 13 + pixel.y * 7) % 256
      ..g = (pixel.x * 3 + pixel.y * 17) % 256
      ..b = (pixel.x * 19 + pixel.y * 5) % 256;
  }
  return Uint8List.fromList(
    image.encodeJpg(source, quality: quality, chroma: image.JpegChroma.yuv444),
  );
}
