import '../support/receipt_editor_actions.dart' show realAction;

import 'package:audyt/core/documents/crop_edit.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/receipt_edit_files.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

Future<void> open(WidgetTester tester, ReceiptReviewDialog dialog) async {
  tester.view.physicalSize = const Size(1100, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AccountingTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => dialog,
            ),
          ),
        ),
      ),
    ),
  );
  await realAction(tester, () => tester.tap(find.text('Open')));
  for (
    var i = 0;
    i < 30 &&
        tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('receipt-review-close')),
                )
                .onPressed ==
            null;
    i++
  ) {
    await realAction(tester, () async {});
  }
  expect(
    tester
        .widget<IconButton>(find.byKey(const ValueKey('receipt-review-close')))
        .onPressed,
    isNotNull,
  );
}

Future<ReceiptAttachment> source() async => ReceiptDocumentPipeline().process(
  ReceiptAttachmentInput(
    originalId: 'a',
    batchId: 'b',
    filename: 'source.png',
    mimeType: 'image/png',
    bytes: image.encodePng(image.Image(width: 40, height: 60)),
  ),
);

void main() {
  testWidgets(
    'failed destination save retains temporary file, retry saves and removes it',
    (tester) async {
      final attachment = await source();
      final queue = ReceiptReviewQueue([attachment]);
      final files = ReceiptEditFiles();
      addTearDown(queue.dispose);
      final destination = await tester.runAsync(
        () => Directory.systemTemp.createTemp('destination-test-'),
      );
      var fail = true, callbackCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, (call) async {
            if (call.method == 'load') {
              return jsonEncode([
                {'type': 'custom', 'text': 'RECEIPT'},
              ]);
            }
            if (call.method == 'loadFolder') return destination!.path;
            if (call.method == 'saveDocument') {
              if (fail) throw PlatformException(code: 'disk_full');
              final file = File('${destination!.path}/saved.png');
              await file.writeAsBytes(
                call.arguments['bytes'] as List<int>,
                flush: true,
              );
              return file.path;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(namingSettingsChannel, null),
      );
      await open(
        tester,
        ReceiptReviewDialog(
          queue: queue,
          editFiles: files,
          setupKind: SetupKind.expense,
          destinationDate: DateTime(2026, 9, 14),
          onSave: (_) async {
            callbackCalled = true;
          },
        ),
      );
      queue.current.cropHistory.beginResize();
      queue.current.cropHistory.updateResize(
        CropHandle.right,
        deltaX: -.5,
        deltaY: 0,
      );
      queue.current.cropHistory.endResize();
      await tester.pump();
      await realAction(
        tester,
        () =>
            tester.tap(find.byKey(const ValueKey('receipt-review-apply-crop'))),
      );
      await tester.runAsync(() async {
        expect(image.decodePng(await files.read('a'))!.width, 20);
      });
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('accounting-crop-undo'))),
      );
      await tester.runAsync(() async {
        expect(await files.read('a'), attachment.originalBytes);
      });
      final temporary = File(files.temporaryPath('a'));
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      expect(queue.current.isResolved, false);
      expect(callbackCalled, false);
      await tester.runAsync(() async {
        expect(await temporary.exists(), true);
        expect(await files.read('a'), attachment.originalBytes);
      });
      fail = false;
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      expect(callbackCalled, true);
      expect(queue.current.state, ReceiptReviewItemState.needsReview);
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
        closesEditor: true,
      );
      expect(queue.current.state, ReceiptReviewItemState.saved);
      await tester.runAsync(() async {
        expect(await temporary.exists(), false);
        expect(
          await File('${destination!.path}/saved.png').readAsBytes(),
          attachment.originalBytes,
        );
        await destination.delete(recursive: true);
        await files.discardAll();
      });
    },
  );

  testWidgets(
    'Keep Editing preserves temporary file; explicit Discard deletes it',
    (tester) async {
      final attachment = await source();
      final queue = ReceiptReviewQueue([attachment]);
      final files = ReceiptEditFiles();
      addTearDown(queue.dispose);
      await open(tester, ReceiptReviewDialog(queue: queue, editFiles: files));
      final temporary = File(files.temporaryPath('a'));
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your changes haven’t been saved and will be lost.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();
      expect(queue.current.isResolved, false);
      await tester.runAsync(() async {
        expect(await temporary.exists(), true);
      });
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
      );
      await tester.pumpAndSettle();
      await realAction(tester, () => tester.tap(find.text('Discard')));
      expect(queue.current.state, ReceiptReviewItemState.discarded);
      await tester.runAsync(() async {
        expect(await temporary.exists(), false);
        await files.discardAll();
      });
      expect(attachment.preferredBytes, attachment.originalBytes);
    },
  );
  testWidgets(
    'missing setup opens warning and cancelling keeps temporary edit',
    (tester) async {
      final attachment = await source();
      final queue = ReceiptReviewQueue([attachment]);
      final files = ReceiptEditFiles();
      addTearDown(queue.dispose);
      var saved = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(namingSettingsChannel, null),
      );
      await open(
        tester,
        ReceiptReviewDialog(
          queue: queue,
          editFiles: files,
          setupKind: SetupKind.expense,
          destinationDate: DateTime(2026, 9, 14),
          onSave: (_) async {
            saved = true;
          },
        ),
      );
      final temporary = File(files.temporaryPath('a'));
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      expect(
        find.text(
          'Set up a destination folder and naming format before saving. Your edit will stay open until setup is complete.',
        ),
        findsOneWidget,
      );
      expect(saved, false);
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('naming-cancel'))),
      );
      expect(queue.current.isResolved, false);
      await tester.runAsync(() async {
        expect(await temporary.exists(), true);
        await files.discardAll();
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
}
