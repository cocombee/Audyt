import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/app/accounting_image_zoom.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:image/image.dart' as image;

import '../../../support/attachment_preview_pump.dart';
import '../../../app/journal_workspace_integration_test.dart' show captureUi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('audyt/document-preview');
  for (final width in [720.0, 1224.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'attachment failures stay inline or below the card at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          ReceiptAttachment failed(String id, String reason) =>
              ReceiptAttachment.queued(
                ReceiptAttachmentInput(
                  originalId: id,
                  batchId: 'failure-test',
                  filename: '$id.png',
                  mimeType: 'image/png',
                  bytes: Uint8List(32),
                ),
              ).withFailure(reason);
          const fullReason =
              'The attachment could not be processed because its image data is incomplete. Choose the original file again, then retry without deleting the saved record or its document reference.';
          final short = failed('short', 'File missing');
          final long = failed('long', fullReason);
          final readonly = failed('readonly', 'File missing');
          var viewClicks = 0;
          Widget surface({bool ready = false}) => MaterialApp(
            theme: AccountingTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1100),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('workspace-capture'),
                  child: Center(
                    child: SizedBox(
                      width: width - 280,
                      child: Builder(
                        builder: (context) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AccountingAttachmentRecordRow(
                              attachment: ready
                                  ? short.withStatus(
                                      AttachmentProcessingStatus.ready,
                                    )
                                  : short,
                              actions: [
                                AccountingButton.outline(
                                  context,
                                  key: const ValueKey('failure-short-view'),
                                  onPressed: () => viewClicks++,
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            AccountingAttachmentRecordRow(
                              attachment: ready
                                  ? long.withStatus(
                                      AttachmentProcessingStatus.ready,
                                    )
                                  : long,
                              actions: [
                                AccountingButton.outline(
                                  context,
                                  key: const ValueKey('failure-long-view'),
                                  onPressed: () => viewClicks++,
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ReadonlyAttachmentRow(
                              attachment: ready
                                  ? readonly.withStatus(
                                      AttachmentProcessingStatus.ready,
                                    )
                                  : readonly,
                              keyPrefix: 'failure-test',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          expect(find.text('Failed - File missing'), findsNWidgets(2));
          final inline = tester.renderObject<RenderParagraph>(
            find.text('Failed - File missing').first,
          );
          expect(inline.size.height, lessThan(12 * 1.43 * scale + 1));
          expect(inline.didExceedMaxLines, false);
          final alert = find.byKey(const ValueKey('attachment-failure-long'));
          final card = find.byKey(const ValueKey('attachment-card-long'));
          expect(alert, findsOneWidget);
          expect(
            find.descendant(of: card, matching: find.textContaining('Failed')),
            findsNothing,
          );
          expect(
            tester.getRect(alert).top,
            greaterThan(tester.getRect(card).bottom),
          );
          expect(tester.getRect(alert).left, tester.getRect(card).left);
          expect(tester.getRect(alert).right, tester.getRect(card).right);
          final description = tester.renderObject<RenderParagraph>(
            find.text(fullReason),
          );
          expect(description.didExceedMaxLines, false);
          expect(description.size.height, greaterThan(inline.size.height));
          await tester.tap(find.byKey(const ValueKey('failure-short-view')));
          await tester.tap(find.byKey(const ValueKey('failure-long-view')));
          expect(viewClicks, 2);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureUi(
            tester,
            'Attachment Failure Family ${width.toInt()} Scale $scale',
          );
          await tester.pumpWidget(surface(ready: true));
          await tester.pumpAndSettle();
          expect(find.textContaining('Failed'), findsNothing);
          expect(find.text(fullReason), findsNothing);
          expect(
            find.byKey(const ValueKey('failure-short-view')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('failure-long-view')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('failure-test-attachment-view-readonly')),
            findsOneWidget,
          );
        },
      );
    }
  }
  testWidgets('PDF preview requests pages without changing attachment bytes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final portrait = Uint8List.fromList(
      image.encodePng(image.Image(width: 500, height: 750)),
    );
    final landscape = Uint8List.fromList(
      image.encodePng(image.Image(width: 750, height: 500)),
    );
    final requested = <int>[];
    final attachment = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'pdf',
        batchId: 'test',
        filename: 'invoice.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    );
    final before = List<int>.from(attachment.originalBytes);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requested.add((call.arguments as Map)['page'] as int);
      return {
        'bytes': (call.arguments as Map)['page'] == 0 ? portrait : landscape,
        'pages': 2,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
      ),
    );
    await tester.pump();
    await pumpDecodedAttachment(tester);
    expect(find.text('Page 1 Of 2'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final firstPage = tester.getRect(
      find.byKey(const ValueKey('attachment-image-preview')),
    );
    expect(firstPage.height, closeTo(852, .1));
    expect(firstPage.width / firstPage.height, closeTo(500 / 750, .01));
    final firstZoom = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(firstZoom.minScale, 1);
    await tester.tapAt(firstPage.center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(firstPage.center);
    await tester.pumpAndSettle();
    expect(
      firstZoom.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(2.5, .01),
    );
    await tester.tap(find.text('Next'));
    await tester.pump();
    await pumpDecodedAttachment(tester);
    expect(find.text('Page 2 Of 2'), findsOneWidget);
    final secondPage = tester.getRect(
      find.byKey(const ValueKey('attachment-image-preview')),
    );
    expect(secondPage.width / secondPage.height, closeTo(750 / 500, .01));
    expect(secondPage.width, closeTo(1152, .1));
    final secondZoom = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(secondZoom.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(requested, [0, 1]);
    expect(attachment.originalBytes, before);
    expect(find.text('Remove'), findsNothing);
  });
  testWidgets('readonly metadata shows the currently viewed derivative size', (
    tester,
  ) async {
    final original = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'size',
        batchId: 'test',
        filename: 'scan.png',
        mimeType: 'image/png',
        bytes: Uint8List(4096),
      ),
    );
    final edited = original.withDerivative(
      derivativeId: 'size-derivative-edit-test',
      bytes: Uint8List(2048),
      mimeType: 'image/jpeg',
      width: 10,
      height: 10,
      printReadyAt300Dpi: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: ReadonlyAttachmentRow(
                attachment: edited,
                keyPrefix: 'size',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('JPEG · 2.0 KB'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsNothing);
    final row = find.byType(AccountingAttachmentRecordRow);
    final action = find.byKey(const ValueKey('size-attachment-view-size'));
    final surfaceFinder = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(20),
      ),
    );
    expect(row, findsOneWidget);
    expect(tester.getSize(action).height, 32);
    final title = tester.getRect(find.text('scan.png'));
    final summary = tester.getRect(find.text('JPEG · 2.0 KB'));
    final actionCenter = tester.getCenter(action).dy;
    expect(actionCenter, inInclusiveRange(title.top, summary.bottom));
    expect(surfaceFinder, findsOneWidget);
    final surface = tester.widget<DecoratedBox>(surfaceFinder);
    expect((surface.decoration as BoxDecoration).color, Colors.white);
  });
  testWidgets('PDF failure stays explicit', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'preview_unavailable'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final attachment = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'bad',
        batchId: 'test',
        filename: 'bad.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to preview'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'metadata-only restored attachment previews its verified native filed copy',
    (tester) async {
      const links = MethodChannel('audyt/naming-settings');
      final bytes = Uint8List.fromList(
        image.encodePng(image.Image(width: 600, height: 800)),
      );
      final requested = <String>[];
      final attachment = _restored(
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'restored-link',
            batchId: 'restored',
            filename: 'linked.png',
            mimeType: 'image/png',
            bytes: bytes,
          ),
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(links, (
        call,
      ) async {
        expect(call.method, 'readDocument');
        requested.add((call.arguments as Map)['attachmentId'] as String);
        expect(
          (call.arguments as Map)['expectedSha256'],
          attachment.originalSha256,
        );
        return {'bytes': bytes, 'mimeType': 'image/png'};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          links,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(requested, ['restored-link']);
      expect(
        find.byKey(const ValueKey('attachment-image-preview')),
        findsOneWidget,
      );
      expect(attachment.originalBytes, isEmpty);
      expect(find.textContaining('Linked filed copy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restored cropped output cannot silently use its original', (
    tester,
  ) async {
    final captureDir = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (captureDir != null) {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    }
    const links = MethodChannel('audyt/naming-settings');
    final original = Uint8List.fromList(
      image.encodePng(image.Image(width: 600, height: 800)),
    );
    final cropped = Uint8List.fromList(
      image.encodePng(image.Image(width: 600, height: 400)),
    );
    final attachment = _restored(
      ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'edited-link',
          batchId: 'restored',
          filename: 'edited.png',
          mimeType: 'image/png',
          bytes: original,
        ),
      ).withDerivative(
        derivativeId: 'edited-link-derivative-crop-1',
        bytes: cropped,
        mimeType: 'image/png',
        width: 600,
        height: 400,
        printReadyAt300Dpi: false,
      ),
    );
    var linkedBytes = original;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(links, (
      call,
    ) async {
      expect(
        (call.arguments as Map)['expectedSha256'],
        attachment.derivativeSha256,
      );
      // A valid image with the same original ID is still the wrong revision.
      return {'bytes': linkedBytes, 'mimeType': 'image/png'};
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        links,
        null,
      ),
    );
    Widget preview() => RepaintBoundary(
      key: const ValueKey('attachment-capture'),
      child: MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
      ),
    );
    Future<void> capture(String label) async {
      if (captureDir == null) return;
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('attachment-capture')),
      );
      await tester.runAsync(() async {
        final frame = await boundary.toImage(pixelRatio: 1);
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        await File('$captureDir/$label.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        frame.dispose();
      });
    }

    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not match this saved record version'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(attachment.originalBytes, isEmpty);
    expect(attachment.derivativeBytes, isNull);
    for (final width in [720.0, 1224.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('Filed Version Unavailable ${width.toInt()}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    linkedBytes = cropped;
    await tester.pumpWidget(preview());
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('attachment-image-preview')),
      findsOneWidget,
    );
    expect(find.textContaining('Linked filed copy'), findsOneWidget);
    for (final width in [720.0, 1224.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final frame = tester.getRect(
        find.byKey(const ValueKey('attachment-image-preview')),
      );
      expect(frame.width / frame.height, closeTo(600 / 400, .01));
      expect(frame.left, greaterThanOrEqualTo(23.9));
      expect(frame.right, lessThanOrEqualTo(width - 23.9));
      expect(tester.takeException(), isNull);
      await capture('Filed Version Matching ${width.toInt()}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored image converted to PDF verifies and renders the filed PDF',
    (tester) async {
      const links = MethodChannel('audyt/naming-settings');
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 600, height: 800)),
      );
      final pdf = Uint8List.fromList(
        utf8.encode('%PDF-1.4 fictional test output'),
      );
      final attachment = _restored(
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'converted-link',
            batchId: 'restored',
            filename: 'converted.png',
            mimeType: 'image/png',
            bytes: png,
          ),
        ).withPdf(pdf),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(links, (
        call,
      ) async {
        expect((call.arguments as Map)['expectedSha256'], attachment.pdfSha256);
        return {'bytes': pdf, 'mimeType': 'application/pdf'};
      });
      final pages = <int>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect((call.arguments as Map)['bytes'], orderedEquals(pdf));
        pages.add((call.arguments as Map)['page'] as int);
        return {'bytes': png, 'pages': 2};
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          links,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1 Of 2'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 2 Of 2'), findsOneWidget);
      expect(pages, [0, 1]);
      expect(attachment.originalBytes, isEmpty);
      expect(attachment.pdfBytes, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing native filed copy stays explicit without an endless spinner',
    (tester) async {
      const links = MethodChannel('audyt/naming-settings');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        links,
        (_) async => throw PlatformException(
          code: 'document_unavailable',
          message: 'Reconnect the document folder.',
        ),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          links,
          null,
        ),
      );
      final attachment = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'missing-link',
          batchId: 'restored',
          filename: 'missing.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List(0),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reconnect the document folder.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'single image preview hugs the image with an inset close button',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAIAAABd+SbeAAAAx0lEQVR4nO3QQREAIAzAsIF/z0MFfSUGetezu8N/N2hgdMfoiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yexgPfMgOdjzE9jgAAAABJRU5ErkJggg==',
      );
      final attachment = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'image',
          batchId: 'test',
          filename: 'sample.png',
          mimeType: 'image/png',
          bytes: bytes,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAttachmentPreview(context, attachment),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      final preview = tester.getRect(
        find.byKey(const ValueKey('attachment-image-preview')),
      );
      final close = tester.getRect(find.byType(IconButton));
      expect(preview.size, const Size(120, 80));
      expect(close.top - preview.top, AccountingPopoutTokens.closeInset);
      expect(preview.right - close.right, AccountingPopoutTokens.closeInset);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('sample.png'), findsNothing);
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('attachment-image-preview')),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.circular(accountingSectionRadius));
      expect(find.byType(AccountingImageZoom), findsOneWidget);

      final zoom = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = zoom.transformationController!;
      await tester.tapAt(preview.center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(preview.center);
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, .01));

      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(preview.center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(preview.center);
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: preview.center,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: preview.center,
          scrollDelta: const Offset(0, 1200),
        ),
      );
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
    },
  );

  testWidgets('document-sized image fills the viewport without a gutter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'large-image',
        batchId: 'test',
        filename: 'document.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(
          image.encodePng(image.Image(width: 500, height: 750)),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttachmentPreviewDialog(attachment: attachment)),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();

    final preview = tester.getRect(
      find.byKey(const ValueKey('attachment-image-preview')),
    );
    expect(preview.height, closeTo(852, 0.1));
    expect(preview.width / preview.height, closeTo(500 / 750, 0.01));
    expect(preview.width, greaterThan(500));
  });
}

ReceiptAttachment _restored(ReceiptAttachment attachment) =>
    ReceiptAttachment.fromJson({
      ...attachment.toJson(),
      '_evidenceUnavailable': true,
      'originalBytes': null,
      'derivativeBytes': null,
      'pdfBytes': null,
    });
