import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'claim_receipts_proposal_test.dart' show prepare, capture;

Future<ReceiptReviewQueue> openReview(
  WidgetTester tester,
  double width, {
  bool many = false,
  String filename = 'Fictional Receipt.jpg',
}) async {
  await prepare(tester, width);
  final pixels = image.Image(width: 400, height: 520);
  image.fill(pixels, color: image.ColorRgb8(245, 244, 235));
  for (final line in [
    ('FICTIONAL RECEIPT', 40),
    ('Business Travel', 110),
    ('14-09-2026', 180),
    ('Total RM 182.00', 250),
  ]) {
    image.drawString(
      pixels,
      line.$1,
      font: image.arial24,
      x: 30,
      y: line.$2,
      color: image.ColorRgb8(20, 20, 20),
    );
  }
  final original = await const ReceiptDocumentPipeline().process(
    ReceiptAttachmentInput(
      originalId: 'footer-fit',
      batchId: 'fit',
      filename: filename,
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList(image.encodeJpg(pixels)),
    ),
  );
  final queue = ReceiptReviewQueue([
    original,
    if (many)
      ReceiptAttachment.fromJson({
        ...original.toJson(),
        'originalId': 'footer-fit-2',
        'derivativeId': 'footer-fit-2-output',
      }),
  ]);
  addTearDown(queue.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ReceiptReviewDialog(queue: queue),
              ),
              child: const Text('Review'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Review'));
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      MemoryImage(original.preferredBytes),
      tester.element(find.byType(ReceiptReviewDialog)),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('receipt-review-preview')),
      matching: find.byWidgetPredicate((w) => w is RawImage && w.image != null),
    ),
    findsWidgets,
    reason: 'The actual receipt pixels must decode before visual verification.',
  );
  return queue;
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final variant in ['Single', 'Batch', 'Long Filename']) {
      testWidgets('receipt footer uses actual content at $width / $variant', (
        tester,
      ) async {
        final long = variant == 'Long Filename';
        final many = variant == 'Batch';
        await openReview(
          tester,
          width,
          many: many,
          filename: long
              ? 'FictionalSeptemberBusinessTravelSupportingReceiptDocument.jpg'
              : 'Fictional Receipt.jpg',
        );
        final footer = find.byKey(const ValueKey('receipt-review-footer'));
        expect(tester.widget(footer), isA<AccountingRecordBodyLayout>());
        final filename = find.byKey(const ValueKey('receipt-review-filename'));
        final metadata = find.byKey(
          const ValueKey('receipt-review-file-metadata'),
        );
        final details = find
            .ancestor(of: filename, matching: find.byType(Column))
            .first;
        final save = find.byKey(const ValueKey('receipt-review-save'));
        final actions = find
            .ancestor(of: save, matching: find.byType(Column))
            .first;
        final detailRect = tester.getRect(details);
        final actionRect = tester.getRect(actions);
        await capture(tester, 'Receipt Footer $variant ${width.toInt()}');
        if (width == 720 && (many || long)) {
          expect(
            actionRect.top,
            closeTo(detailRect.bottom + 12, .01),
            reason: 'The full metadata group precedes actions when both cannot fit.',
          );
        } else {
          expect(
            actionRect.center.dy,
            closeTo(detailRect.center.dy, .01),
            reason: 'Fitting groups stay inline and share a centerline.',
          );
          expect(
            actionRect.left,
            greaterThanOrEqualTo(
              detailRect.right + accountingContentInset - .01,
            ),
          );
        }
        expect(
          tester.getRect(metadata).left,
          closeTo(tester.getRect(filename).left, .01),
        );
        expect(filename.hitTestable(), findsOneWidget);
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    for (final clean in [false, true]) {
      testWidgets(
        'receipt processing owner has shared notice geometry at $width / $clean',
        (tester) async {
          await openReview(tester, width);
          final context = tester.element(find.byType(ReceiptReviewDialog));
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ReceiptProcessingNotice(
              message: clean ? 'Cleaning scan…' : 'Optimizing…',
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final notice = find.byKey(
            const ValueKey('receipt-processing-notice'),
          );
          expect(tester.widget(notice), isA<AlertDialog>());
          final surface = tester.getRect(
            find
                .descendant(
                  of: notice,
                  matching: find.byWidgetPredicate(
                    (w) => w is Material && w.type == MaterialType.card,
                  ),
                )
                .first,
          );
          final close = find.byKey(const ValueKey('receipt-processing-close'));
          final closeRect = tester.getRect(close);
          expect(
            closeRect.top - surface.top,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
          expect(
            surface.right - closeRect.right,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
          expect(tester.widget<IconButton>(close).onPressed, isNull);
          expect(
            find.byKey(const ValueKey('accounting-form-dialog-footer')),
            findsNothing,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(notice, findsOneWidget);
          await capture(
            tester,
            'Receipt ${clean ? 'Clean Scan' : 'Optimize'} Processing Owner ${width.toInt()}',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final clean in [false, true]) {
    testWidgets(
      'actual receipt processing retains blocking and original evidence / $clean',
      (tester) async {
        final queue = await openReview(tester, 720);
        final action = find.byKey(
          ValueKey(clean ? 'receipt-clean-scan' : 'receipt-review-optimize'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        expect(find.byType(ReceiptProcessingNotice), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('receipt-processing-close')),
              )
              .onPressed,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(ReceiptProcessingNotice), findsOneWidget);
        // Scan work runs in real native isolates. Under the full suite, the
        // original five-second polling budget could end while that work was
        // still live; fake-time pumpAndSettle cannot advance the native job.
        final processingDeadline = Stopwatch()..start();
        while (processingDeadline.elapsed < const Duration(seconds: 30)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          final perspectiveCancel = find.byKey(
            const ValueKey('perspective-cancel'),
          );
          if (perspectiveCancel.evaluate().isNotEmpty) {
            await tester.tap(perspectiveCancel);
            await tester.pump(const Duration(milliseconds: 400));
          }
          final close = find.byKey(const ValueKey('receipt-review-close'));
          if (close.evaluate().isNotEmpty &&
              tester.widget<IconButton>(close).onPressed != null) {
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(ReceiptProcessingNotice), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('receipt-review-close')),
              )
              .onPressed,
          isNotNull,
          reason: 'Native receipt processing must finish within 30 seconds.',
        );
        await tester.pumpAndSettle();
        expect(
          queue.current.workingAttachment.originalBytes,
          orderedEquals(queue.current.attachment.originalBytes),
        );
        expect(queue.savedCount, 0);
        expect(queue.skippedCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
