import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates one timestamped batch payment for multiple claims', () {
    final claimOne = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a91'),
      vendorName: 'Acme Office Supplies',
      amount: Money.fromMinor(1250, 'USD'),
      claimantName: 'Test Claimant',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: 'Office Supplies',
      claimCategoryCode: 'office-supplies',
      expenseAccountCode: '5000',
      businessPurpose: 'Office purchase',
      attachments: ClaimStore.demo().all.first.attachments,
    ).submit();
    final claimTwo = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a92'),
      vendorName: 'Northwind Cafe',
      amount: Money.fromMinor(750, 'USD'),
      claimantName: 'Test Claimant',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: 'Office Supplies',
      claimCategoryCode: 'office-supplies',
      expenseAccountCode: '5000',
      businessPurpose: 'Office purchase',
      attachments: ClaimStore.demo().all.first.attachments,
    ).submit();

    final batch = ClaimPaymentBatch.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a93'),
      claims: [claimOne, claimTwo],
      paidAt: DateTime.utc(2026, 8, 30, 12),
    );

    final referenced = ClaimPaymentBatch.create(
      id: batch.id,
      claims: [claimOne, claimTwo],
      paidAt: batch.paidAt,
      paymentReference: '  TRANSFER-001  ',
    );
    final restoredClaims = referenced.claims
        .map(
          (claim) => Claim.fromJson(Map<String, dynamic>.from(claim.toJson())),
        )
        .toList();
    expect(
      ClaimPaymentBatch.restore(
        id: batch.id,
        claims: restoredClaims,
        paidAt: batch.paidAt,
      ).reference,
      'TRANSFER-001',
    );
    final conflicting = Map<String, dynamic>.from(restoredClaims.last.toJson());
    conflicting['paymentReference'] = 'TRANSFER-002';
    expect(
      () => ClaimPaymentBatch.restore(
        id: batch.id,
        claims: [restoredClaims.first, Claim.fromJson(conflicting)],
        paidAt: batch.paidAt,
      ),
      throwsStateError,
    );
    expect(
      ClaimPaymentBatch.restore(
        id: batch.id,
        claims: batch.claims,
        paidAt: batch.paidAt,
      ).reference,
      isNull,
    );
    for (final reference in ['', '   ', 'x' * 121]) {
      expect(
        () => claimOne.markPaid(
          paymentBatchId: batch.id,
          paidAt: batch.paidAt,
          paymentReference: reference,
        ),
        throwsArgumentError,
      );
      final invalid = Map<String, dynamic>.from(restoredClaims.first.toJson());
      invalid['paymentReference'] = reference;
      expect(() => Claim.fromJson(invalid), throwsFormatException);
    }
    final unpaid = Map<String, dynamic>.from(claimOne.toJson());
    unpaid['paymentReference'] = 'TRANSFER-001';
    expect(() => Claim.fromJson(unpaid), throwsFormatException);

    expect(batch.claimIds, [claimOne.id, claimTwo.id]);
    expect(batch.total, Money.fromMinor(2000, 'USD'));
    expect(batch.paidAt, DateTime.utc(2026, 8, 30, 12));
    expect(
      batch.claims.every((claim) => claim.status == ClaimStatus.paid),
      isTrue,
    );
    expect(
      batch.claims.every((claim) => claim.paymentBatchId == batch.id),
      isTrue,
    );
  });
}
