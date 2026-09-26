import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/app/naming_setup.dart';

import 'dart:typed_data';

import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  Future<void> realAction(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(() async {
      await action();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> waitForReviewIdle(WidgetTester tester) async {
    final close = find.byKey(const ValueKey('receipt-review-close'));
    for (
      var attempt = 0;
      attempt < 30 && tester.widget<IconButton>(close).onPressed == null;
      attempt++
    ) {
      await realAction(tester, () async {});
    }
    expect(tester.widget<IconButton>(close).onPressed, isNotNull);
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async => switch (call.method) {
            'load' => '[{"type":"day","text":""}]',
            'loadFolder' => '/Example/expense',
            'saveDocument' => '/Example/expense/receipt.jpg',
            _ => null,
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  testWidgets(
    'opens a non-dismissible receipt review before final attachment save',
    (tester) async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 64, height: 48)),
      );
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(
            onAttachmentsPick: (_) async => <PickedExpenseAttachment>[
              PickedExpenseAttachment(
                name: 'receipt.jpg',
                mimeType: 'image/jpeg',
                bytes: bytes,
              ),
            ],
          ),
        ),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
      );
      await realAction(
        tester,
        () =>
            tester.tap(find.byKey(const ValueKey('expense-receipt-dropzone'))),
      );
      await waitForReviewIdle(tester);

      expect(
        find.byKey(const ValueKey('expense-receipt-review-dialog')),
        findsOneWidget,
      );
      expect(find.text('Receipt Review'), findsOneWidget);
      final barriers = tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      );
      expect(barriers.any((barrier) => !barrier.dismissible), isTrue);
      expect(find.text('receipt.jpg'), findsWidgets);

      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-save')),
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      await waitForReviewIdle(tester);
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
      );
      expect(find.text('Receipt Review'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('expense-attachment-row-original-'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'routes the row crop action through the existing receipt review history',
    (tester) async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 64, height: 48)),
      );
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(
            onAttachmentsPick: (_) async => <PickedExpenseAttachment>[
              PickedExpenseAttachment(
                name: 'crop-review.jpg',
                mimeType: 'image/jpeg',
                bytes: bytes,
              ),
            ],
          ),
        ),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
      );
      await realAction(
        tester,
        () =>
            tester.tap(find.byKey(const ValueKey('expense-receipt-dropzone'))),
      );
      await waitForReviewIdle(tester);
      final firstReview = tester.widget<ReceiptReviewDialog>(
        find.byType(ReceiptReviewDialog),
      );
      const acceptedCrop = NormalizedCropRect(
        left: 0.1,
        top: 0.1,
        right: 0.9,
        bottom: 0.9,
      );
      firstReview.queue.current.cropHistory.apply(acceptedCrop);
      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-review-save')),
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      await waitForReviewIdle(tester);
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
      );

      final editAttachment = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'expense-attachment-crop-',
            ),
      );
      await tester.ensureVisible(editAttachment);
      await realAction(tester, () => tester.tap(editAttachment));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('expense-receipt-review-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-undo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-crop-redo')),
        findsOneWidget,
      );
      final reopened = tester.widget<ReceiptReviewDialog>(
        find.byType(ReceiptReviewDialog),
      );
      expect(
        reopened.queue.current.cropHistory.present,
        NormalizedCropRect.full,
      );
      expect(reopened.queue.current.cropHistory.canUndo, isFalse);
      reopened.queue.cancelWorkingAttachment();
      expect(
        reopened.queue.current.cropHistory.present,
        NormalizedCropRect.full,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
