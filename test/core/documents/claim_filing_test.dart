import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/claim_filing.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a paid batch to configured rename, stamp, and move changes', () {
    final claimOne = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ca111'),
      vendorName: 'Acme Office Supplies',
      amount: Money.fromMinor(1250, 'USD'),
      claimantName: 'Reviewer',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: 'Office Supplies',
      claimCategoryCode: 'office-supplies',
      expenseAccountCode: 'expense.office-supplies',
      businessPurpose: 'Business purchase',
      attachments: [
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'receipt-1250',
            batchId: 'batch',
            filename: 'receipt.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ).withStatus(AttachmentProcessingStatus.ready),
      ],
    ).submit();
    final claimTwo = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ca112'),
      vendorName: 'Northwind Cafe',
      amount: Money.fromMinor(750, 'USD'),
      claimantName: 'Reviewer',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: 'Office Supplies',
      claimCategoryCode: 'office-supplies',
      expenseAccountCode: 'expense.office-supplies',
      businessPurpose: 'Business purchase',
      attachments: [
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'receipt-750',
            batchId: 'batch',
            filename: 'receipt.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ).withStatus(AttachmentProcessingStatus.ready),
      ],
    ).submit();
    final batch = ClaimPaymentBatch.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ca113'),
      claims: [claimOne, claimTwo],
      paidAt: DateTime.utc(2026, 8, 30, 12),
    );

    final plan = PaidClaimFilingPlan.build(
      batch: batch,
      sourcePaths: {
        claimOne.id: 'Claims/Acme/claim-one',
        claimTwo.id: 'Claims/Northwind/claim-two',
      },
      destinationPaths: {
        claimOne.id: 'C4 - Monthly Expenses/2026/08/claim-one',
        claimTwo.id: 'C4 - Monthly Expenses/2026/08/claim-two',
      },
      paidStamp: 'PAID',
    );

    expect(plan.batchId, batch.id);
    expect(plan.changes, hasLength(2));
    expect(plan.changes.first.claimId, claimOne.id);
    expect(plan.changes.first.paidStamp, 'PAID');
    expect(plan.changes.first.sourceRelativePath, contains('Claims'));
    expect(
      plan.changes.first.destinationRelativePath,
      contains('C4 - Monthly Expenses'),
    );
    expect(
      plan.changes.every((change) => change.paidAt == batch.paidAt),
      isTrue,
    );
  });
}
