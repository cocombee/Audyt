import 'dart:typed_data';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'claim_receipts_proposal_test.dart' show prepare, capture;

void main() {
  for (final width in [720.0, 900.0, 1224.0]) {
    for (final many in [false, true]) {
      testWidgets(
        'receipt actions fit actual metadata and count at $width / $many',
        (tester) async {
          await prepare(tester, width);
          final original = await const ReceiptDocumentPipeline().process(
            ReceiptAttachmentInput(
              originalId: 'receipt-fit',
              batchId: 'fit',
              filename: 'Fictional September Business Travel Receipt With Supporting Information.jpg',
              mimeType: 'image/jpeg',
              bytes: Uint8List.fromList(
                image.encodeJpg(image.Image(width: 80, height: 120)),
              ),
            ),
          );
          final queue = ReceiptReviewQueue([
            original,
            if (many)
              ReceiptAttachment.fromJson({
                ...original.toJson(),
                'originalId': 'receipt-fit-2',
                'derivativeId': 'receipt-fit-2-output',
              }),
            if (many)
              ReceiptAttachment.fromJson({
                ...original.toJson(),
                'originalId': 'receipt-fit-3',
                'derivativeId': 'receipt-fit-3-output',
              }),
          ]);
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
                        barrierDismissible: false,
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
          final frame = tester.getRect(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('expense-receipt-review-dialog'),
                  ),
                  matching: find.byWidgetPredicate(
                    (w) => w is Material && w.type == MaterialType.card,
                  ),
                )
                .first,
          );
          final footerKeys = [
            'receipt-review-convert-pdf',
            'receipt-review-skip',
            'receipt-review-save',
            if (many) ...[
              'receipt-review-previous',
              'receipt-review-next',
              'receipt-review-batch-optimize',
              'receipt-clean-scan-all',
              'receipt-review-skip-all',
            ],
          ];
          await capture(
            tester,
            'Receipt Review ${many ? 'Batch' : 'Single'} Fit ${width.toInt()}',
          );
          for (final key in footerKeys) {
            final rect = tester.getRect(find.byKey(ValueKey(key)));
            expect(
              rect.bottom,
              lessThanOrEqualTo(frame.bottom - 24 + .01),
              reason: '$key must be visible without scrolling past the image',
            );
            expect(rect.left, greaterThanOrEqualTo(frame.left + 24 - .01));
            expect(rect.right, lessThanOrEqualTo(frame.right - 24 + .01));
          }
          expect(tester.takeException(), isNull);
          expect(queue.savedCount, 0);
          expect(queue.skippedCount, 0);
          if (many) {
            await tester.tap(find.byKey(const ValueKey('receipt-review-next')));
            await tester.pumpAndSettle();
            expect(queue.index, 1);
            await tester.tap(
              find.byKey(const ValueKey('receipt-review-previous')),
            );
            await tester.pumpAndSettle();
            expect(queue.index, 0);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  for (final many in [false, true]) {
    testWidgets('receipt toolbars stay reachable in a short window / $many', (
      tester,
    ) async {
      await prepare(tester, 720);
      tester.view.physicalSize = const Size(720, 600);
      final original = await const ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'short',
          batchId: 'fit',
          filename: 'Fictional Receipt.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList(
            image.encodeJpg(image.Image(width: 80, height: 120)),
          ),
        ),
      );
      final queue = ReceiptReviewQueue([
        original,
        if (many)
          ReceiptAttachment.fromJson({
            ...original.toJson(),
            'originalId': 'short-2',
            'derivativeId': 'short-2-output',
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
      final preview = tester.getRect(
        find.byKey(const ValueKey('receipt-review-preview')),
      );
      for (final key in [
        'receipt-left-toolbar',
        'receipt-right-toolbar-viewport',
      ]) {
        final toolbar = tester.getRect(find.byKey(ValueKey(key)));
        expect(toolbar.top, greaterThanOrEqualTo(preview.top + 12));
        expect(toolbar.bottom, lessThanOrEqualTo(preview.bottom - 12 + .01));
      }
      for (final key in [
        'receipt-review-dismiss-crop',
        'receipt-review-apply-crop',
      ]) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      for (final key in [
        'receipt-review-start-crop',
        'receipt-perspective',
        'receipt-review-rotate',
        'receipt-review-optimize',
        'receipt-clean-scan',
        'receipt-review-contrast',
        'receipt-review-levels',
        'receipt-review-trace',
        'receipt-zoom-in',
        'receipt-zoom-out',
        'receipt-zoom-fit',
      ]) {
        final button = find.byKey(ValueKey(key));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(
          button.hitTestable(),
          findsOneWidget,
          reason: '$key must be reachable through its existing toolbar scroll',
        );
      }
      await capture(
        tester,
        'Receipt Review ${many ? 'Batch' : 'Single'} Short Fit 720',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-levels')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-review-levels')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('optimize-black-point')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(queue.savedCount, 0);
      expect(queue.skippedCount, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
