import 'dart:typed_data';

import '../../support/accounting_text_input.dart';

import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/app/naming_setup.dart';

import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:audyt/features/purchases/domain/claim_category.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
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
            'loadFolder' => '/Example/claims',
            'saveDocument' => '/Example/claims/receipt.jpg',
            _ => null,
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  test('claim categories are a populated catalog with explicit mappings', () {
    expect(ClaimCategoryCatalog.catalogId, isNot('expense-category-catalog'));
    expect(ClaimCategoryCatalog.seeded, isNotEmpty);
    for (final category in ClaimCategoryCatalog.seeded) {
      expect(category.expenseCategoryCode, isNotEmpty);
      expect(
        category.mappedExpenseCategory,
        isNotNull,
        reason: 'Missing mapped expense category for ${category.code}',
      );
      expect(category.mappingNeedsReview, isFalse);
    }
  });

  testWidgets(
    'uses the shared two-column shell and stacks at the narrow breakpoint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(store: ClaimStore(claims: const [])),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('claim-editor-form-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('claim-editor-two-column')),
        findsWidgets,
      );
      expect(find.byKey(const ValueKey('claim-editor-stacked')), findsNothing);
      expect(find.text('Receipt or document name'), findsNothing);
      expect(find.text('Submit For Review'), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(390, 1200));
      await tester.pump();
      expect(find.byKey(const ValueKey('claim-editor-stacked')), findsWidgets);
      expect(
        find.byKey(const ValueKey('claim-editor-two-column')),
        findsNothing,
      );
    },
  );

  testWidgets('filters claimant and merchant from the shared Payee directory', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ClaimsPage(
          store: ClaimStore(claims: const []),
          payees: const <Payee>[
            Payee(id: 'staff', name: 'Aina Rahman', type: PayeeType.staff),
            Payee(id: 'director', name: 'Daniel Lim', type: PayeeType.director),
            Payee(
              id: 'supplier',
              name: 'Acme Office Supplies',
              type: PayeeType.supplier,
            ),
            Payee(id: 'other', name: 'Other Contact', type: PayeeType.other),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('claims-create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('claim-claimant')),
      'Aina',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('claim-claimant-option-staff')),
      findsOneWidget,
    );
    expect(find.text('Acme Office Supplies'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('claim-claimant-option-staff')));

    await tester.enterText(find.byKey(const ValueKey('claim-payee')), 'Acme');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('claim-merchant-option-supplier')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('claim-claimant-option-staff')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('claim-merchant-option-supplier')),
    );
  });

  testWidgets(
    'keeps resolved MYR currency internal while retaining date and category controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1400));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(store: ClaimStore(claims: const [])),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('claim-currency-selector')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('claim-currency-field')), findsNothing);
      expect(find.byKey(const ValueKey('claim-currency-menu')), findsNothing);
      expect(find.text('Currency'), findsNothing);
      expect(find.text('RM · Malaysian Ringgit'), findsNothing);
      expect(
        find.text('Required. MYR is the default claim currency.'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('claim-editor-two-column')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('claim-date')))
            .controller!
            .text,
        matches(RegExp(r'^\d{2}-\d{2}-\d{4}$')),
      );

      await tester.ensureVisible(find.byKey(const ValueKey('claim-category')));
      await tester.tap(find.byKey(const ValueKey('claim-category')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('claim-category-option-office-supplies')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('claim-category-option-office-supplies')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('claim-category-mapping')),
        findsNothing,
      );
      expect(
        find.textContaining('Office Supplies & Small Equipment'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'uses the shared attachment pipeline and rejects filename-only submission',
    (tester) async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 64, height: 48)),
      );
      final store = ClaimStore(claims: const []);
      await tester.binding.setSurfaceSize(const Size(960, 1600));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(
            store: store,
            onAttachmentsPick: (_) async => <PickedExpenseAttachment>[
              PickedExpenseAttachment(
                name: 'claim-receipt.jpg',
                mimeType: 'image/jpeg',
                bytes: bytes,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('claim-upload-file-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('claim-receipt-dropzone')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('claim-receipt-name')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('claim-claimant')),
        'Aina Rahman',
      );
      await tester.enterText(
        find.byKey(const ValueKey('claim-payee')),
        'Acme Office Supplies',
      );
      await tester.enterText(
        find.byKey(const ValueKey('claim-amount')),
        '42.50',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('claim-purpose')));
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('claim-purpose')),
        'Client workshop refreshments',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('claim-category')));
      await tester.tap(find.byKey(const ValueKey('claim-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('claim-category-option-office-supplies')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('claim-submit')));
      await tester.pump();
      expect(
        find.text('Receipt or document is required to submit.'),
        findsOneWidget,
      );
      expect(store.all, isEmpty);

      await tester.ensureVisible(
        find.byKey(const ValueKey('claim-upload-file-action')),
      );
      await realAction(
        tester,
        () =>
            tester.tap(find.byKey(const ValueKey('claim-upload-file-action'))),
      );
      await waitForReviewIdle(tester);
      expect(find.text('Receipt Review'), findsOneWidget);
      expect(find.text('claim-receipt.jpg'), findsWidgets);
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
      expect(find.text('claim-receipt.jpg'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith(
                'claim-attachment-row-',
              ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('claim-submit')));
      await tester.pumpAndSettle();
      expect(store.all, hasLength(1));
      final claim = store.all.single;
      expect(claim.status, ClaimStatus.submitted);
      expect(claim.attachments, hasLength(1));
      expect(claim.attachments.single.originalBytes, orderedEquals(bytes));
      expect(claim.expenseCategoryCode, 'office-supplies-small-equipment');
      expect(
        ClaimCategoryCatalog.byCode(claim.claimCategoryCode!)
            ?.mappingNeedsReview,
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('the existing review queue keeps crop history independent per claim attachment', () {
    ReceiptAttachment attachment(String id) => ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: id,
        batchId: 'claim-batch',
        filename: '$id.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[
      attachment('one'),
      attachment('two'),
    ]);
    const crop = NormalizedCropRect(
      left: 0.1,
      top: 0.1,
      right: 0.9,
      bottom: 0.9,
    );

    queue.current.cropHistory.apply(crop);
    queue.moveNext();
    expect(queue.current.cropHistory.present, NormalizedCropRect.full);
    queue.movePrevious();
    expect(queue.current.cropHistory.present, crop);
  });
}
