import 'dart:convert';
import 'package:audyt/core/documents/document_vector_trace.dart';
import 'package:audyt/app/accounting_crop_editor.dart';
import 'dart:io';
import 'package:audyt/core/documents/crop_edit.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/document_optimization.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/document_optimization_dialog.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/core/documents/receipt_review_queue.dart';

void main() {
  testWidgets('repeated saves retain session original until close', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'save-session', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 30, height: 40))));
    final queue = ReceiptReviewQueue([attachment]); addTearDown(queue.dispose);
    final saves = <ReceiptAttachment>[];
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue, onSave: (value) async { saves.add(value); }))));
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-trace')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-trace'))); await tester.pump();
    for (var i=0; i<20; i++) { await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25))); await tester.pump(const Duration(milliseconds: 25)); }
    await tester.tap(find.byKey(const ValueKey('receipt-review-save'))); await tester.pumpAndSettle();
    expect(saves.single.preferredMimeType, 'image/svg+xml');
    expect(find.byKey(const ValueKey('receipt-review-save')), findsOneWidget);
    expect(queue.current.isResolved, isFalse);
    await tester.tap(find.byKey(const ValueKey('receipt-review-save'))); await tester.pumpAndSettle();
    expect(saves.length, 2);
    await tester.tap(find.byKey(const ValueKey('receipt-review-cancel-crop'))); await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.preferredBytes, orderedEquals(attachment.originalBytes));
    expect(tester.widget<DocumentOptimizationDialog>(find.byType(DocumentOptimizationDialog)).vectorPreview, isFalse);
    await tester.tap(find.byKey(const ValueKey('receipt-review-close'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-review-leave-review'))); await tester.pumpAndSettle();
    expect(queue.current.state, ReceiptReviewItemState.saved);
    expect(queue.current.attachment.preferredMimeType, 'image/svg+xml');
    expect(queue.current.attachment.preferredBytes, orderedEquals(saves.last.preferredBytes));
    await tester.pumpWidget(const SizedBox());
  });

  test('trace exports genuine SVG unless PDF selected', () async {
    final image = img.Image(width: 20, height: 30);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(image, x1: 4, y1: 5, x2: 12, y2: 20, color: img.ColorRgb8(0, 0, 0));
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'svg', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(image)));
    final trace = await DocumentVectorTrace().trace(attachment.preferredBytes, const DocumentTraceSettings());
    final svg = trace.attachTo(attachment, asPdf: false);
    expect(svg.preferredMimeType, 'image/svg+xml');
    expect(svg.pdfBytes, isNull);
    expect(utf8.decode(svg.preferredBytes), contains('<path'));
    expect(utf8.decode(svg.preferredBytes), isNot(contains('<image')));
    expect(ascii.decode(trace.attachTo(attachment, asPdf: true).pdfBytes!.take(4).toList()), '%PDF');
  });

  testWidgets('slider release is one undo and panel reset is scoped', (tester) async {
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'slider', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 80, height: 100))));
    final queue = ReceiptReviewQueue([attachment]); addTearDown(queue.dispose);
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue))));
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-contrast')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-contrast'))); await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('optimize-contrast')));
    final state = tester.state<DocumentOptimizationDialogState>(find.byType(DocumentOptimizationDialog));
    slider.onChangeStart!(1);
    for (final value in [1.1, 1.2, 1.3, 1.5]) { slider.onChanged!(value); }
    expect(state.canUndo, isFalse);
    slider.onChangeEnd!(1.5); await tester.pump();
    expect(state.canUndo, isTrue);
    state.undo(); await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('optimize-contrast'))).value, 1);
    expect(state.canUndo, isFalse);
    state.redo(); await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('optimize-contrast'))).value, 1.5);
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-levels')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-levels'))); await tester.pump();
    tester.widget<Slider>(find.byKey(const ValueKey('optimize-black-point'))).onChanged!(25); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('adjustment-panel-reset'))); await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('optimize-black-point'))).value, 0);
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-contrast')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-contrast'))); await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('optimize-contrast'))).value, 1.5);
    expect(find.descendant(of: find.byKey(const ValueKey('adjustment-panel-drag')), matching: find.text('Receipt.png')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-trace')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-trace'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('receipt-review-cancel-crop'))); await tester.pumpAndSettle();
    expect(tester.widget<DocumentOptimizationDialog>(find.byType(DocumentOptimizationDialog)).vectorPreview, isFalse);
    expect(queue.current.workingAttachment.preferredBytes, orderedEquals(attachment.originalBytes));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('corner handle resizes while outside corner rotates', (tester) async {
    final history = CropEditHistory();
    addTearDown(history.dispose);
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 500, height: 500,
      child: AccountingCropReviewEditor(imageBytes: img.encodePng(img.Image(width: 200, height: 200)), cropHistory: history, imageWidth: 200, imageHeight: 200, showHistoryControls: false, maxPreviewHeight: 500)))));
    final frame = tester.getRect(find.byKey(const ValueKey('accounting-crop-frame')));
    final drag = await tester.startGesture(frame.topLeft + const Offset(2, 2));
    await drag.moveBy(const Offset(35, 25)); await drag.up(); await tester.pump();
    expect(history.present.left, greaterThan(0));
    expect(history.present.top, greaterThan(0));
    expect(history.present.rotation, 0);
    final rotation = find.byKey(const ValueKey('crop-rotate--1--1'));
    final updated = tester.getRect(find.byKey(const ValueKey('accounting-crop-frame')));
    expect(tester.getRect(rotation).overlaps(updated), isFalse);
    final rotate = await tester.startGesture(tester.getCenter(rotation));
    await rotate.moveBy(const Offset(20, -10)); await rotate.up(); await tester.pump();
    expect(history.present.rotation, isNot(0));
  });

  testWidgets('crop and cancel preserve vector preview', (tester) async {
    tester.view.physicalSize=const Size(1100,1000); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'vector-crop', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 80, height: 100))));
    final queue = ReceiptReviewQueue([attachment]); addTearDown(queue.dispose);
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue))));
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-trace')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-trace'))); await tester.pumpAndSettle();
    final editor = tester.widget<DocumentOptimizationDialog>(find.byType(DocumentOptimizationDialog));
    expect(editor.vectorPreview, isTrue);
    await tester.tap(find.byKey(const ValueKey('receipt-review-start-crop'))); await tester.pumpAndSettle();
    final crop = tester.widget<AccountingCropReviewEditor>(find.byType(AccountingCropReviewEditor));
    expect(crop.previewImage, isA<ColorFiltered>());
    final filter = (crop.previewImage! as ColorFiltered).colorFilter;
    expect(filter, (tester.state<DocumentOptimizationDialogState>(find.byType(DocumentOptimizationDialog, skipOffstage: false)).buildCropPreview() as ColorFiltered).colorFilter);
    await tester.tap(find.byKey(const ValueKey('receipt-review-dismiss-crop'))); await tester.pumpAndSettle();
    expect(tester.widget<DocumentOptimizationDialog>(find.byType(DocumentOptimizationDialog)).vectorPreview, isTrue);
    expect(find.byKey(const ValueKey('receipt-review-apply-crop')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tool panels preview size and defer edits until Save', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final source = img.encodePng(img.Image(width: 80, height: 100));
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'tools', batchId: 'tools', filename: 'Receipt.png', mimeType: 'image/png', bytes: source));
    final queue = ReceiptReviewQueue([attachment]); addTearDown(queue.dispose);
    ReceiptAttachment? saved;
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue, onSave: (value) async { saved = value; }))));
    await tester.ensureVisible(find.byKey(const ValueKey('receipt-review-levels')));
    await tester.tap(find.byKey(const ValueKey('receipt-review-levels'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('optimize-black-point')), findsOneWidget);
    expect(find.byKey(const ValueKey('optimize-sharpen')), findsNothing);
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('optimize-black-point')));
    slider.onChanged!(20); await tester.pump(const Duration(milliseconds: 200));
    for (var i=0; i<20; i++) { await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25))); await tester.pump(); }
    expect(queue.current.workingAttachment.preferredBytes, orderedEquals(source));
    expect(saved, isNull);
    expect(tester.widget<Text>(find.byKey(const ValueKey('receipt-review-file-metadata'))).data, startsWith('JPEG ·'));
    expect(find.byKey(const ValueKey('receipt-review-sharpen')), findsNothing);
    expect(find.byKey(const ValueKey('optimize-jpeg-quality')), findsNothing);
    final right = find.byKey(const ValueKey('receipt-right-toolbar'));
    for (final key in ['receipt-zoom-in', 'receipt-zoom-out', 'receipt-zoom-fit', 'accounting-crop-undo', 'accounting-crop-redo', 'receipt-review-cancel-crop']) {
      expect(find.descendant(of: right, matching: find.byKey(ValueKey(key))), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('receipt-review-save'))); await tester.pumpAndSettle();
    expect(saved, isNotNull); expect(saved!.preferredMimeType, 'image/jpeg');
    expect(saved!.originalBytes, orderedEquals(source));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rotate changes an already edited image and undo restores it', (tester) async {
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'rotate-edited', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 30, height: 60))));
    final edited = (await tester.runAsync(() => const DocumentOptimizationEngine().optimize(attachment, const DocumentOptimizationRecipe())))!;
    final queue = ReceiptReviewQueue([attachment]);
    addTearDown(queue.dispose);
    queue.current.applyWorkingAttachment(edited);
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.byKey(const ValueKey('receipt-review-rotate'))); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.derivativeSha256, isNot(edited.derivativeSha256));
    await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.derivativeSha256, edited.derivativeSha256);
    await tester.tap(find.byKey(const ValueKey('receipt-review-start-crop'))); await tester.pumpAndSettle();
    final corner = find.byKey(const ValueKey('crop-rotate-1--1'));
    expect(corner, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(corner));
    await gesture.moveBy(const Offset(20, 5));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 15));
    await tester.pump();
    await tester.runAsync(() async { await gesture.up(); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.byKey(const ValueKey('receipt-review-apply-crop'))); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.derivativeSha256, isNot(edited.derivativeSha256));
    await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.derivativeSha256, edited.derivativeSha256);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crop mode after optimization starts fresh and Apply disappears after crop', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'recrop', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 40, height: 60))));
    final edited = (await tester.runAsync(() => const DocumentOptimizationEngine().optimize(attachment, const DocumentOptimizationRecipe())))!;
    final queue = ReceiptReviewQueue([attachment]);
    addTearDown(queue.dispose);
    queue.current.cropHistory.apply(const NormalizedCropRect(left: .25, top: .25, right: .75, bottom: .75));
    queue.current.applyWorkingAttachment(edited);
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue))));
    await tester.pumpAndSettle();
    final apply = find.byKey(const ValueKey('receipt-review-apply-crop'));
    expect(apply, findsNothing);
    await tester.tap(find.byKey(const ValueKey('receipt-review-start-crop')));
    await tester.pumpAndSettle();
    expect(apply, findsOneWidget);
    await tester.runAsync(() async { await tester.tap(apply); await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.derivativeWidth, 40);
    expect(queue.current.workingAttachment.derivativeHeight, 60);
    expect(tester.widget<Text>(find.byKey(const ValueKey('receipt-review-file-metadata'))).data, startsWith('JPEG ·'));
    expect(apply, findsNothing);
    expect(queue.current.workingAttachment.originalSha256, attachment.originalSha256);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('levels keep fixed tracks and JPEG quality updates preview before apply', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pixels = img.Image(width: 80, height: 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 80; x++) { pixels.setPixelRgb(x, y, (x * 17 + y * 3) % 256, (x * 5 + y * 19) % 256, (x * 11 + y * 7) % 256); }
    }
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'quality', batchId: 'test', filename: 'Quality.png', mimeType: 'image/png', bytes: img.encodePng(pixels)));
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: DocumentOptimizationDialog(attachment: attachment, initialRecipe: const DocumentOptimizationRecipe(), batchCount: 1)));
    Future<void> waitPreview() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }
    await waitPreview();
    Slider slider(String name) => tester.widget<Slider>(find.byKey(ValueKey('optimize-$name')));
    slider('black-point').onChanged!(40);
    await tester.pump();
    expect(slider('white-point').min, 0);
    expect(slider('white-point').max, 255);
    expect(slider('white-point').value, 255);
    slider('white-point').onChanged!(210);
    await tester.pump();
    expect(slider('black-point').max, 255);
    expect(slider('black-point').value, 40);
    Uint8List preview() => (tester.widget<Image>(find.byType(Image).first).image as MemoryImage).bytes;
    final before = List<int>.of(preview());
    expect(slider('jpeg-quality').min, 30);
    slider('jpeg-quality').onChanged!(30);
    await tester.pump(const Duration(milliseconds: 20));
    await waitPreview();
    expect(preview(), isNot(orderedEquals(before)));
    expect(find.byType(DocumentOptimizationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PDF conversion remains undoable through the photo toolbar', (tester) async {
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'pdf-undo', batchId: 'test', filename: 'Receipt.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 30, height: 40))));
    final converted = await const ReceiptDocumentPipeline().convertToPdf(attachment);
    final queue = ReceiptReviewQueue([attachment]);
    addTearDown(queue.dispose);
    queue.current.applyWorkingAttachment(converted);
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: ReceiptReviewDialog(queue: queue))));
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.pdfBytes, isNotNull);
    await tester.tap(find.byKey(const ValueKey('accounting-crop-undo')));
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.pdfBytes, isNull);
    await tester.tap(find.byKey(const ValueKey('accounting-crop-redo')));
    await tester.pumpAndSettle();
    expect(queue.current.workingAttachment.pdfSha256, converted.pdfSha256);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [430.0, 1100.0]) {
    testWidgets('rotated crop review fits at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      final pixels = img.Image(width: 400, height: 500);
      img.fill(pixels, color: img.ColorRgb8(245, 244, 235));
      img.drawString(
        pixels,
        'RECEIPT 001',
        font: img.arial24,
        x: 30,
        y: 40,
        color: img.ColorRgb8(20, 20, 20),
      );
      final attachment = await const ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'visual',
          batchId: 'visual',
          filename: 'Receipt.png',
          mimeType: 'image/png',
          bytes: img.encodePng(pixels),
        ),
      );
      final queue = ReceiptReviewQueue([attachment]);
      addTearDown(queue.dispose);
      queue.current.cropHistory.updateRotation(12);
      queue.current.cropHistory.endResize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light().copyWith(
              textTheme: AccountingTheme.light().textTheme.apply(
                fontFamily: 'Arial',
              ),
            ),
            home: Scaffold(body: ReceiptReviewDialog(queue: queue)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('receipt-review-batch-optimize')),
        findsNothing,
      );
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      await captureUi(tester, 'Rotated Crop ${width.toInt()}');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'optimization editor fits and offers explicit batch apply at $width',
      (tester) async {
        if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
          await (FontLoader('Arial')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('/System/Library/Fonts/Supplemental/Arial.ttf')
                        .readAsBytesSync(),
                  ),
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final image = img.Image(width: 400, height: 240);
        img.fill(image, color: img.ColorRgb8(232, 232, 225));
        img.drawString(
          image,
          'RECEIPT 001\nTOTAL MYR 123.45',
          font: img.arial24,
          x: 25,
          y: 40,
          color: img.ColorRgb8(35, 35, 35),
        );
        final attachment = ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'a',
            batchId: 'b',
            filename: 'Receipt.png',
            mimeType: 'image/png',
            bytes: img.encodePng(image),
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: DocumentOptimizationDialog(
                  attachment: attachment,
                  initialRecipe: const DocumentOptimizationRecipe(),
                  batchCount: 3,
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Apply to All (3)'), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('optimize-apply-all')))
              .right,
          lessThanOrEqualTo(width),
        );
        expect(tester.takeException(), isNull);
        await captureUi(tester, 'Optimization Editor ${width.toInt()}');
        await tester.scrollUntilVisible(
          find.text('Detail preserving'),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureUi(tester, 'Optimization Controls ${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
