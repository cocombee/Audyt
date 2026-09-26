import 'dart:typed_data';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/receipt_review_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReceiptReviewItem item(String id) => ReceiptReviewItem(ReceiptAttachment.queued(ReceiptAttachmentInput(originalId: id, batchId: 'batch', filename: 'one.pdf', mimeType: 'application/pdf', bytes: Uint8List.fromList([1]))).withStatus(AttachmentProcessingStatus.ready));
  test('discard resolves unsaved review without marking it saved or skipped', () {
    final receipt = item('a');
    addTearDown(receipt.dispose);
    receipt.discard();
    expect(receipt.isResolved, true);
    expect(receipt.state, ReceiptReviewItemState.discarded);
    final restored = ReceiptReviewItem.fromJson(Map<String, dynamic>.from(receipt.toJson()));
    addTearDown(restored.dispose);
    expect(restored.state, ReceiptReviewItemState.discarded);
  });
  test('discard cannot remove an already saved receipt', () {
    final receipt = item('b');
    addTearDown(receipt.dispose);
    receipt.save();
    receipt.discard();
    expect(receipt.state, ReceiptReviewItemState.saved);
  });
}
