import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';

ReceiptAttachment attachment(String id, int byte) =>
    ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: id,
            batchId: 'batch',
            filename: '$id.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([byte, 2, 3]),
          ),
        )
        .withDerivative(
          derivativeId: '$id-derivative',
          bytes: Uint8List.fromList([byte, 4]),
          mimeType: 'image/png',
          width: 200,
          height: 300,
          printReadyAt300Dpi: false,
        )
        .withPdf(Uint8List.fromList([37, 80, 68, 70, byte]));
const cropA = NormalizedCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);
const cropB = NormalizedCropRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
void main() {
  test('two receipts preserve original bytes, derivatives, PDF and independent history on disk reopen', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-receipt-snapshot-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = attachment('first', 1);
    final second = attachment('second', 9);
    final queue = ReceiptReviewQueue([first, second]);
    queue.current.cropHistory.apply(cropA);
    queue.current.cropHistory.apply(cropB);
    queue.current.cropHistory.undo();
    queue.moveNext();
    queue.current.cropHistory.apply(cropB);
    final file = File('${dir.path}/review.json');
    await file.writeAsString(jsonEncode(queue.toJson()));
    queue.dispose();
    final restored = ReceiptReviewQueue.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
    addTearDown(restored.dispose);
    expect(restored.index, 1);
    expect(restored.current.cropHistory.present, cropB);
    expect(restored.items.first.cropHistory.present, cropA);
    expect(restored.items.first.cropHistory.canRedo, isTrue);
    restored.items.first.cropHistory.redo();
    expect(restored.items.first.cropHistory.present, cropB);
    restored.current.cropHistory.undo();
    expect(restored.current.cropHistory.present, NormalizedCropRect.full);
    expect(restored.items.first.cropHistory.present, cropB);
    expect(restored.items.first.attachment.originalBytes, first.originalBytes);
    expect(restored.items.last.attachment.originalBytes, second.originalBytes);
    expect(
      restored.items.first.attachment.derivativeBytes,
      first.derivativeBytes,
    );
    expect(restored.items.first.attachment.pdfBytes, first.pdfBytes);
    expect(
      () => restored.items.first.attachment.originalBytes[0] = 99,
      throwsUnsupportedError,
    );
  });
  test('changed bytes and mismatched review originals fail instead of replacing evidence', () {
    final item = attachment('same', 1);
    final json = item.toJson();
    json['originalBytes'] = base64Encode([9, 9, 9]);
    expect(() => ReceiptAttachment.fromJson(json), throwsFormatException);
    final review = ReceiptReviewItem(item);
    addTearDown(review.dispose);
    expect(
      () => review.applyWorkingAttachment(attachment('same', 9)),
      throwsArgumentError,
    );
    final snapshot = review.toJson();
    snapshot['workingAttachment'] = attachment('different', 9).toJson();
    expect(() => ReceiptReviewItem.fromJson(snapshot), throwsFormatException);
  });
  test('snapshot during drag preserves one undo step without changing live history', () {
    final history = CropEditHistory();
    addTearDown(history.dispose);
    history.beginResize();
    history.updateResize(CropHandle.topLeft, deltaX: 0.1, deltaY: 0.1);
    expect(history.canUndo, isFalse);
    final restored = CropEditHistory.fromJson(
      jsonDecode(jsonEncode(history.toJson())) as Map<String, dynamic>,
    );
    addTearDown(restored.dispose);
    expect(history.canUndo, isFalse);
    expect(restored.canUndo, isTrue);
    restored.undo();
    expect(restored.present, NormalizedCropRect.full);
    restored.redo();
    expect(restored.present, history.present);
  });
  test('unknown versions, invalid rectangles and duplicate review identity are rejected', () {
    expect(
      () => CropEditHistory.fromJson({'version': 2}),
      throwsFormatException,
    );
    final history = CropEditHistory();
    addTearDown(history.dispose);
    final json = history.toJson();
    json['present'] = [0.8, 0.0, 0.2, 1.0];
    expect(() => CropEditHistory.fromJson(json), throwsFormatException);
    final queue = ReceiptReviewQueue([attachment('first', 1)]);
    addTearDown(queue.dispose);
    final snapshot = queue.toJson();
    snapshot['items'] = [queue.current.toJson(), queue.current.toJson()];
    expect(() => ReceiptReviewQueue.fromJson(snapshot), throwsFormatException);
  });
}
