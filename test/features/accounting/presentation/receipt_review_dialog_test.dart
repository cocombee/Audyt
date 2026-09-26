import 'dart:typed_data';

import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  ReceiptAttachment pdf(String id, String name) {
    return ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: id,
        batchId: 'batch-1',
        filename: name,
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
      ),
    ).withStatus(AttachmentProcessingStatus.ready);
  }

  Future<void> openReview(
    WidgetTester tester,
    ReceiptReviewQueue queue, {
    Future<ReceiptAttachment> Function(ReceiptAttachment attachment)? onRetry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('background-action'),
              onPressed: () {},
              child: const Text('Background'),
            ),
          ),
        ),
      ),
    );
    final context = tester.element(
      find.byKey(const ValueKey('background-action')),
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptReviewDialog(queue: queue, onRetry: onRetry),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'blocks background interaction and preserves unresolved state on leave',
    (tester) async {
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[
        pdf('one', 'one.pdf'),
      ]);
      var backgroundPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const ValueKey('background-action'),
              onPressed: () => backgroundPressed = true,
              child: const Text('Background'),
            ),
          ),
        ),
      );
      final context = tester.element(
        find.byKey(const ValueKey('background-action')),
      );
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReceiptReviewDialog(queue: queue),
      );
      await tester.pumpAndSettle();

      expect(find.text('Receipt Review'), findsOneWidget);
      expect(find.text('Receipt 1 of 1'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('background-action')),
        warnIfMissed: false,
      );
      expect(backgroundPressed, isFalse);

      await tester.tap(find.byKey(const ValueKey('receipt-review-close')));
      await tester.pumpAndSettle();
      expect(find.text('Keep Editing'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      final discard = tester.widget<FilledButton>(
        find.byKey(const ValueKey('receipt-review-leave-review')),
      );
      expect(
        discard.style!.backgroundColor!.resolve({}),
        AccountingTheme.of(tester.element(find.text('Discard'))).destructive,
      );
      await tester.tap(
        find.byKey(const ValueKey('receipt-review-keep-reviewing')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Receipt Review'), findsOneWidget);
      expect(queue.remainingCount, 1);

      await tester.tap(find.byKey(const ValueKey('receipt-review-close')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('receipt-review-leave-review')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Receipt Review'), findsNothing);
      expect(queue.current.state, ReceiptReviewItemState.discarded);
    },
  );

  testWidgets(
    'moves through items without implicit save and resolves each item explicitly',
    (tester) async {
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[
        pdf('one', 'one.pdf'),
        pdf('two', 'two.pdf'),
      ]);
      await openReview(tester, queue);

      await tester.tap(find.byKey(const ValueKey('receipt-review-next')));
      await tester.pumpAndSettle();
      expect(find.text('Receipt 2 of 2'), findsOneWidget);
      expect(queue.remainingCount, 2);

      await tester.tap(find.byKey(const ValueKey('receipt-review-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Receipt 1 of 2'), findsOneWidget);
      expect(queue.remainingCount, 2);

      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-skip')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-review-skip')));
      await tester.pumpAndSettle();
      expect(queue.skippedCount, 1);
      expect(queue.remainingCount, 1);
      expect(find.text('Receipt 2 of 2'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-save')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-review-save')));
      await tester.pumpAndSettle();
      expect(queue.savedCount, 0);
      await tester.tap(find.byKey(const ValueKey('receipt-review-close')));
      await tester.pumpAndSettle();
      expect(queue.savedCount, 1);
      expect(queue.remainingCount, 0);
      expect(find.text('Receipt Review'), findsNothing);
    },
  );

  testWidgets('requires confirmation for Skip All', (tester) async {
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[
      pdf('one', 'one.pdf'),
      pdf('two', 'two.pdf'),
    ]);
    await openReview(tester, queue);

    await tester.ensureVisible(
      find.byKey(const ValueKey('receipt-review-skip-all')),
    );
    await tester.tap(find.byKey(const ValueKey('receipt-review-skip-all')));
    await tester.pumpAndSettle();
    expect(find.text('Skip All Receipts?'), findsOneWidget);
    expect(queue.remainingCount, 2);

    await tester.tap(
      find.byKey(const ValueKey('receipt-review-confirm-skip-all')),
    );
    await tester.pumpAndSettle();
    expect(queue.skippedCount, 2);
    expect(queue.remainingCount, 0);
    expect(find.text('Receipt Review'), findsNothing);
  });

  testWidgets('shows retry and skip instead of Save for a failed item', (
    tester,
  ) async {
    final failed = pdf(
      'failed',
      'failed.pdf',
    ).withFailure('Could not decode receipt.');
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[failed]);
    final recovered = pdf('failed', 'failed.pdf');
    await openReview(tester, queue, onRetry: (_) async => recovered);

    expect(find.text('Could not decode receipt.'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-review-save')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('receipt-review-save')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('receipt-review-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-review-skip')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('receipt-review-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-review-status')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('receipt-review-save')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('saves an image only after explicit Save', (tester) async {
    final processed = await const ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'image-save-1',
        batchId: 'batch-save',
        filename: 'receipt.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(
          image.encodeJpg(image.Image(width: 40, height: 30)),
        ),
      ),
    );
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[processed]);
    await openReview(tester, queue);

    await tester.ensureVisible(
      find.byKey(const ValueKey('receipt-review-save')),
    );
    await tester.tap(find.byKey(const ValueKey('receipt-review-save')));
    await tester.pumpAndSettle();
    expect(queue.savedCount, 0);
    await tester.tap(find.byKey(const ValueKey('receipt-review-close')));
    await tester.pumpAndSettle();
    expect(queue.savedCount, 1);
    expect(queue.remainingCount, 0);
    expect(find.text('Receipt Review'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('keeps crop and conversion explicit in the review surface', (
    tester,
  ) async {
    final source = image.Image(width: 40, height: 30);
    final processed = await const ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'image-1',
        batchId: 'batch-1',
        filename: 'receipt.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(image.encodeJpg(source)),
      ),
    );
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[processed]);
    await openReview(tester, queue);

    expect(
      find.byKey(const ValueKey('receipt-review-apply-crop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receipt-review-convert-pdf')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('receipt-review-apply-crop')),
    );
    await tester.tap(find.byKey(const ValueKey('receipt-review-apply-crop')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(queue.current.state, ReceiptReviewItemState.needsReview);
    expect(
      find.byKey(const ValueKey('receipt-review-dismiss-crop')),
      findsNothing,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'uses shared crop controls and applies the exact draft as a separate derivative',
    (tester) async {
      final source = image.Image(width: 80, height: 60);
      final processed = await const ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'crop-review-1',
          batchId: 'crop-review-batch',
          filename: 'receipt.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList(image.encodeJpg(source)),
        ),
      );
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[processed]);
      await openReview(tester, queue);

      expect(
        find.byKey(const ValueKey('accounting-crop-frame')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-top-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-right')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(const ValueKey('accounting-crop-undo')),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(const ValueKey('accounting-crop-redo')),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.bySemanticsLabel('Undo'), findsOneWidget);
      expect(find.bySemanticsLabel('Redo'), findsOneWidget);
      final undoRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('accounting-crop-undo')),
          matching: find.byType(OutlinedButton),
        ),
      );
      final redoRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('accounting-crop-redo')),
          matching: find.byType(OutlinedButton),
        ),
      );
      final applyRect = tester.getRect(
        find.byKey(const ValueKey('receipt-review-apply-crop')),
      );
      final photoRect = tester.getRect(
        find.byKey(const ValueKey('accounting-crop-preview')),
      );
      expect(undoRect.left, greaterThan(photoRect.right));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('receipt-review-start-crop')))
            .top,
        lessThanOrEqualTo(photoRect.top),
      );
      expect(redoRect.left, undoRect.left);
      expect((applyRect.left - undoRect.left).abs(), lessThan(8));
      expect(redoRect.top, greaterThan(undoRect.bottom));
      expect(applyRect.top, greaterThan(redoRect.bottom));

      expect(find.bySemanticsLabel('Crop frame'), findsOneWidget);
      final rotationCorner = find.byKey(const ValueKey('crop-rotate-1--1'));
      final rotationGesture = await tester.startGesture(
        tester.getCenter(rotationCorner),
      );
      await rotationGesture.moveBy(const Offset(20, 5));
      await tester.pump();
      await rotationGesture.moveBy(const Offset(20, 15));
      await rotationGesture.up();
      await tester.pumpAndSettle();
      expect(queue.current.cropHistory.present.rotation, isNot(0));
      await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
      await tester.pumpAndSettle();
      expect(queue.current.cropHistory.present.rotation, 0);

      await tester.drag(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-right')),
        const Offset(-18, -12),
      );
      await tester.pump();
      final editedDraft = queue.current.cropHistory.present;
      expect(queue.current.cropHistory.canUndo, isTrue);

      await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
      await tester.pump();
      expect(queue.current.cropHistory.present, NormalizedCropRect.full);

      await tester.tap(find.byKey(const ValueKey('accounting-crop-redo')));
      await tester.pump();
      expect(queue.current.cropHistory.present, editedDraft);

      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-apply-crop')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-review-apply-crop')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(queue.current.workingAttachment.derivativeId, contains('-crop-'));
      expect(
        queue.current.workingAttachment.originalBytes,
        orderedEquals(processed.originalBytes),
      );
      expect(
        queue.current.workingAttachment.originalSha256,
        processed.originalSha256,
      );
      expect(queue.current.workingAttachment.derivativeBytes, isNotNull);
      expect(queue.current.attachment.derivativeId, processed.derivativeId);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Skip preserves the original review derivative and makes no crop derivative',
    (tester) async {
      final processed = await const ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'crop-skip-1',
          batchId: 'crop-skip-batch',
          filename: 'receipt.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList(
            image.encodeJpg(image.Image(width: 80, height: 60)),
          ),
        ),
      );
      final queue = ReceiptReviewQueue(<ReceiptAttachment>[processed]);
      await openReview(tester, queue);

      await tester.drag(
        find.byKey(const ValueKey('accounting-crop-handle-bottom-right')),
        const Offset(-18, -12),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-review-skip')));
      await tester.pumpAndSettle();

      expect(queue.current.state, ReceiptReviewItemState.skipped);
      expect(
        queue.current.workingAttachment.derivativeId,
        processed.derivativeId,
      );
      expect(
        queue.current.workingAttachment.derivativeId,
        isNot(contains('-crop-')),
      );
      expect(
        queue.current.workingAttachment.originalBytes,
        orderedEquals(processed.originalBytes),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
