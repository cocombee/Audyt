import 'dart:typed_data';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('import keeps exact source size and pixels without a derivative', () async {
    final source = image.Image(width: 240, height: 320);
    final bytes = Uint8List.fromList(image.encodeJpg(source, quality: 95));
    final pipeline = ReceiptDocumentPipeline();
    final original = await pipeline.process(ReceiptAttachmentInput(originalId: 'original', batchId: 'batch', filename: 'receipt.jpg', mimeType: 'image/jpeg', bytes: bytes));
    expect(original.derivativeBytes, isNull);
    expect(original.preferredBytes, orderedEquals(bytes));
    expect(original.originalByteSize, bytes.length);
    expect(original.originalWidth, 240);
    expect(original.originalHeight, 320);
    final cropped = await pipeline.crop(original, const NormalizedCropRect(left: 0, top: 0, right: .5, bottom: 1));
    expect(cropped.status, AttachmentProcessingStatus.ready);
    expect(image.decodeImage(cropped.preferredBytes)!.width, 120);
    expect(cropped.originalBytes, orderedEquals(bytes));
    final pdf = await pipeline.convertToPdf(original);
    expect(pdf.pdfBytes!.take(4), orderedEquals('%PDF'.codeUnits));
  });
}
