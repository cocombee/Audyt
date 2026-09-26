import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReceiptAttachment attachment(String id, String name) {
    return ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: id,
        batchId: 'batch-1',
        filename: name,
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ).withStatus(AttachmentProcessingStatus.ready);
  }

  test('resolves one review item without mutating its raw bytes', () {
    final first = attachment('original-1', 'one.pdf');
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[first]);

    expect(queue.current.state, ReceiptReviewItemState.needsReview);
    expect(queue.remainingCount, 1);
    expect(queue.current.rawBytes, orderedEquals(<int>[1, 2, 3]));

    queue.markSaved();

    expect(queue.current.state, ReceiptReviewItemState.saved);
    expect(queue.savedCount, 1);
    expect(queue.remainingCount, 0);
    expect(queue.current.rawBytes, orderedEquals(<int>[1, 2, 3]));
    expect(
      queue.current.attachment.originalBytes,
      orderedEquals(first.originalBytes),
    );
  });

  test('previous and next only move focus and never resolve an item', () {
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[
      attachment('original-1', 'one.pdf'),
      attachment('original-2', 'two.pdf'),
    ]);

    expect(queue.moveNext(), isTrue);
    expect(queue.index, 1);
    expect(queue.current.state, ReceiptReviewItemState.needsReview);
    expect(queue.movePrevious(), isTrue);
    expect(queue.index, 0);
    expect(queue.current.state, ReceiptReviewItemState.needsReview);
    expect(queue.remainingCount, 2);
  });

  test(
    'skip all requires explicit confirmation and resolves only remaining items',
    () {
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[
        attachment('original-1', 'one.pdf'),
        attachment('original-2', 'two.pdf'),
        attachment('original-3', 'three.pdf'),
      ]);

      queue.markSkipped();
      expect(queue.skipAll(confirmed: false), isFalse);
      expect(queue.remainingCount, 2);

      expect(queue.skipAll(confirmed: true), isTrue);
      expect(queue.items.map((item) => item.state), <ReceiptReviewItemState>[
        ReceiptReviewItemState.skipped,
        ReceiptReviewItemState.skipped,
        ReceiptReviewItemState.skipped,
      ]);
      expect(queue.remainingCount, 0);
    },
  );

  test('keeps skipped attachment metadata available while marking it non-persistable', () {
    final original = attachment('original-1', 'one.pdf');
    final skipped = original.withReviewSkipped();

    expect(skipped.filename, original.filename);
    expect(skipped.reviewSkipped, isTrue);
    expect(original.reviewSkipped, isFalse);
  });

  test(
    'keeps an applied derivative in memory until save and can cancel it',
    () {
      final original = attachment('original-1', 'one.pdf');
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[original]);
      final derivative = original.withPdf(Uint8List.fromList(<int>[9, 8, 7]));

      queue.applyWorkingAttachment(derivative);

      expect(queue.current.state, ReceiptReviewItemState.needsReview);
      expect(
        queue.current.workingAttachment.pdfBytes,
        orderedEquals(<int>[9, 8, 7]),
      );
      expect(queue.current.attachment.pdfBytes, isNull);

      queue.cancelWorkingAttachment();

      expect(queue.current.workingAttachment.pdfBytes, isNull);
      expect(queue.current.rawBytes, orderedEquals(original.originalBytes));
    },
  );
}
