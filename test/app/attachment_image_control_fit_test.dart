import 'dart:typed_data';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_image_zoom.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'claim_receipts_proposal_test.dart' show prepare, capture;
import '../support/attachment_preview_pump.dart';

ReceiptAttachment original(int width, int height) {
  final pixels = image.Image(width: width, height: height)
    ..clear(image.ColorRgb8(255, 255, 255));
  if (width >= 64 && height >= 32) {
    image.drawString(
      pixels,
      'Receipt',
      font: image.arial14,
      x: 3,
      y: 1,
      color: image.ColorRgb8(45, 45, 45),
    );
    image.drawString(
      pixels,
      '182.00',
      font: image.arial14,
      x: 3,
      y: 16,
      color: image.ColorRgb8(45, 45, 45),
    );
  }
  return ReceiptAttachment.queued(
    ReceiptAttachmentInput(
      originalId: 'fictional-$width-$height',
      batchId: 'isolated',
      filename: 'Fictional receipt.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList(image.encodePng(pixels)),
    ),
  );
}

Future<void> host(
  WidgetTester tester,
  ReceiptAttachment attachment, {
  bool embedded = false,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              if (embedded) {
                return AttachmentPreviewDialog(
                  attachment: attachment,
                  embedded: true,
                );
              }
              return AccountingButton.primary(
                context,
                key: const ValueKey('open-original'),
                onPressed: () => showAttachmentPreview(context, attachment),
                child: const Text('View Original'),
              );
            },
          ),
        ),
      ),
    ),
  );
  if (!embedded) {
    await tester.tap(find.byKey(const ValueKey('open-original')));
    await tester.pump();
  }
  await pumpDecodedAttachment(tester);
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final (sourceWidth, sourceHeight, name) in [
      (120, 80, 'Existing Thumbnail'),
      (64, 32, 'Tiny Landscape'),
      (32, 64, 'Tiny Portrait'),
      (1, 1, 'Single Pixel'),
      (2000, 1, 'Thin Landscape'),
      (1, 2000, 'Thin Portrait'),
    ]) {
      testWidgets('original $name keeps Close reachable at $width', (
        tester,
      ) async {
        await prepare(tester, width);
        final attachment = original(sourceWidth, sourceHeight);
        final before = attachment.toJson();
        await host(tester, attachment);
        final picture = find.byKey(const ValueKey('attachment-image-preview'));
        final frame = tester.getRect(picture);
        final closeFinder = find.byType(IconButton);
        expect(closeFinder, findsOneWidget);
        final close = tester.getRect(closeFinder);
        final shell = find.byKey(
          const ValueKey('attachment-control-fit-dialog'),
        );
        if (shell.evaluate().isEmpty) {
          expect(
            frame.contains(close.topLeft),
            isTrue,
            reason: 'Close must not be clipped by the image boundary.',
          );
          expect(close.right, lessThanOrEqualTo(frame.right));
          expect(close.bottom, lessThanOrEqualTo(frame.bottom));
          expect(
            close.top - frame.top,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
          expect(
            frame.right - close.right,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
        } else {
          final surface = tester.getRect(shell);
          expect(surface.contains(close.topLeft), isTrue);
          expect(close.bottom, lessThan(frame.top));
          expect(find.text(attachment.filename), findsOneWidget);
        }
        expect(
          frame.width / frame.height,
          closeTo(sourceWidth / sourceHeight, .01),
        );
        if (sourceWidth < 400 && sourceHeight < 400) {
          expect(
            frame.size,
            Size(sourceWidth.toDouble(), sourceHeight.toDouble()),
            reason: 'A control-fit correction must not enlarge tiny originals.',
          );
        }
        if (name == 'Existing Thumbnail') {
          expect(shell, findsNothing);
        }
        expect(frame.left, greaterThanOrEqualTo(0));
        expect(frame.right, lessThanOrEqualTo(width));
        expect(frame.top, greaterThanOrEqualTo(0));
        expect(frame.bottom, lessThanOrEqualTo(1000));
        expect(tester.widget<Image>(picture).image, isA<MemoryImage>());
        expect(
          (tester.widget<Image>(picture).image as MemoryImage).bytes,
          attachment.originalBytes,
        );
        expect(find.byType(AccountingImageZoom), findsOneWidget);
        expect(
          find.byKey(const ValueKey('accounting-form-footer')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'Attachment $name Control Fit ${width.toInt()}');
        // The portion previously clipped must also be clickable, not merely
        // present in the layout tree or accessible from the upper half.
        await tester.tapAt(Offset(close.center.dx, close.bottom - 2));
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentPreviewDialog), findsNothing);
        expect(attachment.toJson(), before);
      });
    }
    testWidgets('embedded tiny original retains its pixel size at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      final attachment = original(64, 32);
      await host(tester, attachment, embedded: true);
      expect(
        tester.getSize(find.byKey(const ValueKey('attachment-image-preview'))),
        const Size(64, 32),
      );
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
