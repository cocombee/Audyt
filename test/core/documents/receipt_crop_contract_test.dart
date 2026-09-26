import 'dart:typed_data';

import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('applies the exact normalized crop to a separate derivative', () async {
    final original = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 100, height: 80)),
    );
    final processed = await const ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'exact-crop',
        batchId: 'exact-crop-batch',
        filename: 'receipt.jpg',
        mimeType: 'image/jpeg',
        bytes: original,
      ),
    );
    const crop = NormalizedCropRect(
      left: 0.1,
      top: 0.2,
      right: 0.8,
      bottom: 0.9,
    );

    final result = await const ReceiptDocumentPipeline().crop(processed, crop);

    expect(result.originalBytes, orderedEquals(processed.originalBytes));
    expect(result.originalSha256, processed.originalSha256);
    expect(result.derivativeId, isNot(processed.derivativeId));
    final repeated = await const ReceiptDocumentPipeline().crop(processed, crop);
    expect(repeated.derivativeId, result.derivativeId);
    expect(repeated.derivativeSha256, result.derivativeSha256);
    expect(result.derivativeWidth, 70);
    expect(result.derivativeHeight, 56);
    expect(result.derivativeBytes, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
