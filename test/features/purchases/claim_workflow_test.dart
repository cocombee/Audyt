import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_category.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('claim retains personal payment context and follows review states', () {
    final category = ClaimCategoryCatalog.byCode('office-supplies')!;
    final claim = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a01'),
      vendorName: 'Acme Office Supplies',
      amount: Money.fromMinor(1250, 'MYR'),
      claimantName: 'Aina Rahman',
      incurredOn: DateTime(2026, 8, 31),
      category: category.displayName,
      claimCategoryCode: category.code,
      expenseCategoryCode: category.expenseCategoryCode,
      expenseAccountCode: category.expenseAccountCode,
      businessPurpose: 'Stationery for the client workshop',
      receiptDocumentNames: const <String>['receipt.jpg'],
      attachments: <ReceiptAttachment>[
        _readyAttachment('workflow-one', 'receipt.jpg'),
      ],
    );

    expect(claim.personallyPaid, isTrue);
    expect(claim.claimantName, 'Aina Rahman');
    expect(claim.receiptDocumentNames, ['receipt.jpg']);
    expect(claim.status, ClaimStatus.draft);
    expect(claim.submit().status, ClaimStatus.submitted);
    expect(claim.submit().approve().status, ClaimStatus.approved);
  });

  test(
    'local claim store pays only a reviewed claim through ClaimPaymentBatch',
    () {
      final store = ClaimStore.demo();
      final draft = store.all.singleWhere(
        (claim) => claim.status == ClaimStatus.draft,
      );
      final submitted = store.submit(draft.id);
      final approved = store.approve(submitted.id);
      expect(approved.status, ClaimStatus.approved);

      final batch = store.markPaid(
        approved.id,
        paymentBatchId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a02'),
        paidAt: DateTime.utc(2026, 8, 31, 10),
      );
      expect(batch, isA<ClaimPaymentBatch>());
      expect(store.byId(approved.id)?.status, ClaimStatus.paid);
      expect(store.byId(approved.id)?.paymentBatchId, batch.id);
      expect(
        () => store.markPaid(
          approved.id,
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a03',
          ),
          paidAt: DateTime.utc(2026, 8, 31),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'claim payment batch preserves existing mixed-currency and void guards',
    () {
      final one = Claim.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a04'),
        vendorName: 'One',
        amount: Money.fromMinor(100, 'MYR'),
        claimantName: 'Aina Rahman',
        incurredOn: DateTime(2026, 8, 31),
        category: 'Office Supplies & Small Equipment',
        claimCategoryCode: 'office-supplies',
        expenseCategoryCode: 'office-supplies-small-equipment',
        expenseAccountCode: 'expense.office-supplies-small-equipment',
        businessPurpose: 'Stationery for a workshop',
        attachments: <ReceiptAttachment>[
          _readyAttachment('workflow-one-payment', 'one.pdf'),
        ],
      );
      final two = Claim.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a05'),
        vendorName: 'Two',
        amount: Money.fromMinor(100, 'USD'),
      );
      expect(
        () => ClaimPaymentBatch.create(
          id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a06'),
          claims: [one, two],
          paidAt: DateTime.utc(2026, 8, 31),
        ),
        throwsArgumentError,
      );
      final voided = one.voidClaim();
      expect(
        () => voided.markPaid(
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a07',
          ),
          paidAt: DateTime.utc(2026, 8, 31),
        ),
        throwsStateError,
      );
      final paid = one.submit().approve().markPaid(
        paymentBatchId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a08'),
        paidAt: DateTime.utc(2026, 8, 31),
      );
      expect(
        () => paid.markPaid(
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5a09',
          ),
          paidAt: DateTime.utc(2026, 8, 31),
        ),
        throwsStateError,
      );
    },
  );
}

ReceiptAttachment _readyAttachment(String id, String filename) {
  return ReceiptAttachment.queued(
    ReceiptAttachmentInput(
      originalId: id,
      batchId: 'workflow-batch',
      filename: filename,
      mimeType: filename.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg',
      bytes: Uint8List.fromList(<int>[37, 80, 68, 70, 45, 49, 46, 55]),
    ),
  ).withStatus(AttachmentProcessingStatus.ready);
}
