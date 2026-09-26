import '../../../support/receipt_editor_actions.dart' show realAction;

import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/app/naming_setup.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';

import '../data/expense_intake_test.dart' show draft;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async => switch (call.method) {
            'load' => '[{"type":"day","text":""}]',
            'loadFolder' => '/Example/expense',
            'saveDocument' => '/Example/expense/receipt.png',
            _ => null,
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  testWidgets('saved form preserves identity and original bytes on resave', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = PaymentAccount.create(
      id: 'cash-id',
      name: 'Cash',
      type: PaymentAccountType.cash,
      currencyCode: 'MYR',
    );
    final attachments = [
      for (var index = 0; index < 2; index++)
        ReceiptAttachment.queued(
              ReceiptAttachmentInput(
                originalId: 'original-$index',
                batchId: 'batch-one',
                filename: 'receipt-$index.png',
                mimeType: 'image/png',
                bytes: Uint8List.fromList(
                  img.encodePng(img.Image(width: 20 + index, height: 30)),
                ),
              ),
            )
            .withDerivative(
              derivativeId: 'derivative-$index',
              bytes: Uint8List.fromList(
                img.encodePng(img.Image(width: 20 + index, height: 30)),
              ),
              mimeType: 'image/png',
              width: 20 + index,
              height: 30,
              printReadyAt300Dpi: false,
            )
            .withStatus(AttachmentProcessingStatus.ready),
    ];
    final histories = attachments.map(ReceiptReviewItem.new).toList();
    addTearDown(() {
      for (final item in histories) {
        item.dispose();
      }
    });
    histories[0].cropHistory.apply(
      const NormalizedCropRect(left: .1, top: .1, right: .9, bottom: .9),
    );
    histories[1].cropHistory.apply(
      const NormalizedCropRect(left: .2, top: .2, right: .8, bottom: .8),
    );
    histories[1].cropHistory.undo();
    for (final item in histories) {
      item.save();
    }
    final saved = RecordExpenseDraft.fromJson({
      ...draft(
        paymentAccountId: account.id,
        attachments: attachments,
        reviews: histories
            .map((item) => Map<String, dynamic>.from(item.toJson()))
            .toList(),
      ).toJson(),
      'tax': 'No tax',
    });
    RecordExpenseDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordExpensePage(
            savedDraft: saved,
            accounts: [account],
            categories: const ['Office Operations'],
            onSave: (value) async {
              result = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('expense-field-amount')),
          )
          .controller!
          .text,
      '25.50',
    );
    for (var index = 0; index < 2; index++) {
      final crop = find.byKey(
        ValueKey('expense-attachment-crop-original-$index'),
      );
      await tester.ensureVisible(crop);
      await realAction(tester, () => tester.tap(crop));
      final review = tester.widget<ReceiptReviewDialog>(
        find.byType(ReceiptReviewDialog),
      );
      expect(review.queue.current.attachment.originalId, 'original-$index');
      expect(review.queue.current.cropHistory.canUndo, isFalse);
      expect(review.queue.current.cropHistory.canRedo, isFalse);
      expect(
        review.queue.current.cropHistory.present,
        const NormalizedCropRect(left: 0, top: 0, right: 1, bottom: 1),
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
        closesEditor: true,
      );
    }
    final save = find.byKey(const ValueKey('record-expense-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result, isNotNull);
    expect(result!.submissionId, saved.submissionId);
    expect(result!.paymentAccountId, account.id);
    expect(
      result!.attachments.map((item) => item.originalSha256).toList(),
      attachments.map((item) => item.originalSha256).toList(),
    );
    expect(result!.reviewSnapshots, hasLength(2));
    final first = ReceiptReviewItem.fromJson(result!.reviewSnapshots[0]);
    final second = ReceiptReviewItem.fromJson(result!.reviewSnapshots[1]);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(first.cropHistory.canUndo, isFalse);
    expect(second.cropHistory.canRedo, isFalse);
    expect(first.cropHistory.present, second.cropHistory.present);
    expect(result!.notes, saved.notes);
    await tester.pumpWidget(const SizedBox());
    result = null;
    final stale = RecordExpenseDraft.fromJson({
      ...saved.toJson(),
      'tax': 'Retired Tax Code',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordExpensePage(
            savedDraft: stale,
            accounts: [account],
            categories: const ['Office Operations'],
            onSave: (value) async {
              result = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
      find.textContaining(
        'Saved tax treatment "Retired Tax Code" needs review',
      ),
      findsOneWidget,
    );
  });
}
