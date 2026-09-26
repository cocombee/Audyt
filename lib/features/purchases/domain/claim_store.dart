import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_category.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';

/// Small local-first claim repository used by the Accounting Core workflow.
///
/// It intentionally keeps claims separate from direct expense records. A
/// payment changes the claim through [ClaimPaymentBatch]; it does not post a
/// second expense.
final class ClaimStore extends ChangeNotifier {
  ClaimStore({
    Iterable<Claim> claims = const <Claim>[],
    this.persistChanges,
    this.loadClaims,
    this.allowDemoDeletion = false,
  }) : _claims = <Claim>[...claims];

  factory ClaimStore.demo() {
    final officeSupplies = ClaimCategoryCatalog.byCode('office-supplies')!;
    final professionalServices = ClaimCategoryCatalog.byCode(
      'professional-services',
    )!;
    final advertising = ClaimCategoryCatalog.byCode('advertising-marketing')!;
    final draft = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5b01'),
      vendorName: 'Acme Office Supplies',
      amount: Money.fromMinor(1250, 'MYR'),
      claimantName: 'Aina Rahman',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: officeSupplies.displayName,
      claimCategoryCode: officeSupplies.code,
      expenseCategoryCode: officeSupplies.expenseCategoryCode,
      expenseAccountCode: officeSupplies.expenseAccountCode,
      businessPurpose: 'Stationery for the client workshop',
      attachments: <ReceiptAttachment>[
        _demoAttachment('claim-demo-original-1', 'aina-receipt.jpg'),
      ],
    );
    final submitted = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5b02'),
      vendorName: 'Northwind Services',
      amount: Money.fromMinor(2300, 'MYR'),
      claimantName: 'Daniel Lim',
      incurredOn: DateTime.utc(2026, 8, 30),
      category: professionalServices.displayName,
      claimCategoryCode: professionalServices.code,
      expenseCategoryCode: professionalServices.expenseCategoryCode,
      expenseAccountCode: professionalServices.expenseAccountCode,
      businessPurpose: 'Director-paid compliance consultation',
      attachments: <ReceiptAttachment>[
        _demoAttachment('claim-demo-original-2', 'northwind-invoice.pdf'),
      ],
    ).submit();
    final paid =
        Claim.draft(
          id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5b03'),
          vendorName: 'Kecil Studio',
          amount: Money.fromMinor(850, 'MYR'),
          claimantName: 'Aina Rahman',
          incurredOn: DateTime.utc(2026, 8, 27),
          category: advertising.displayName,
          claimCategoryCode: advertising.code,
          expenseCategoryCode: advertising.expenseCategoryCode,
          expenseAccountCode: advertising.expenseAccountCode,
          businessPurpose: 'Small provider design work',
          attachments: <ReceiptAttachment>[
            _demoAttachment('claim-demo-original-3', 'kecil-invoice.pdf'),
          ],
        ).submit().approve().markPaid(
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5b04',
          ),
          paidAt: DateTime.utc(2026, 8, 30, 15),
        );
    return ClaimStore(
      claims: <Claim>[draft, submitted, paid],
      allowDemoDeletion: true,
    );
  }

  final bool allowDemoDeletion;

  bool canDeleteDemo(Claim claim) =>
      allowDemoDeletion &&
      persistChanges == null &&
      claim.status == ClaimStatus.draft &&
      claim.paymentBatchId == null;

  void deleteDemoDraft(EntityId id) {
    final claim = _required(id);
    if (!canDeleteDemo(claim)) {
      throw StateError('Only isolated demo drafts can be deleted here.');
    }
    _claims.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  final List<Claim> _claims;

  /// Commit all changed claims atomically before publishing them in memory.
  final void Function(List<Claim>)? persistChanges;

  final List<Claim> Function()? loadClaims;

  void reload() {
    final loaded = loadClaims?.call();
    if (loaded == null) {
      throw StateError('This claim store has no persistence loader.');
    }
    _claims
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  List<Claim> get all => List<Claim>.unmodifiable(_claims);

  Claim? byId(EntityId id) {
    for (final claim in _claims) {
      if (claim.id == id) return claim;
    }
    return null;
  }

  void _requireCurrent(Claim claim, Claim? expectedCurrent) {
    if (expectedCurrent != null && expectedCurrent.id != claim.id) {
      throw ArgumentError('The reviewed claim must match the edited claim.');
    }
    if (expectedCurrent != null &&
        jsonEncode(byId(expectedCurrent.id)?.toJson()) !=
            jsonEncode(expectedCurrent.toJson())) {
      throw StateError(
        'Claim changed since it was opened. Reopen before saving.',
      );
    }
    byId(claim.id)?.validateClaimantReplacement(claim);
    byId(claim.id)?.validateExpenseOriginalReplacement(claim);
  }

  Claim saveDraft(Claim claim, {Claim? expectedCurrent}) {
    _requireCurrent(claim, expectedCurrent);
    if (claim.status != ClaimStatus.draft &&
        claim.status != ClaimStatus.returned) {
      throw StateError(
        'Only draft or returned claims can be saved as a draft.',
      );
    }
    final existing = byId(claim.id);
    if (existing != null &&
        existing.status != ClaimStatus.draft &&
        existing.status != ClaimStatus.returned) {
      throw StateError('Only draft or returned claims can be edited.');
    }
    _upsert(claim);
    return claim;
  }

  Claim saveAndSubmit(Claim claim, {Claim? expectedCurrent}) {
    _requireCurrent(claim, expectedCurrent);
    final existing = byId(claim.id);
    if (existing != null &&
        existing.status != ClaimStatus.draft &&
        existing.status != ClaimStatus.returned) {
      throw StateError(
        'Only draft or returned claims can be edited and submitted.',
      );
    }
    final submitted = claim.submit();
    _upsert(submitted);
    return submitted;
  }

  Claim submit(EntityId id, {Claim? expectedCurrent}) {
    final current = _required(id);
    _requireCurrent(current, expectedCurrent);
    final updated = current.submit();
    _upsert(updated);
    return updated;
  }

  Claim approve(EntityId id) {
    final updated = _required(id).approve();
    _upsert(updated);
    return updated;
  }

  Claim returnForCorrection(EntityId id, {Claim? expectedCurrent}) {
    final current = _required(id);
    _requireCurrent(current, expectedCurrent);
    final updated = current.returnForCorrection();
    _upsert(updated);
    return updated;
  }

  Claim decline(EntityId id, {Claim? expectedCurrent}) {
    final current = _required(id);
    _requireCurrent(current, expectedCurrent);
    final updated = current.decline();
    _upsert(updated);
    return updated;
  }

  Claim voidClaim(EntityId id, {Claim? expectedCurrent}) {
    final current = _required(id);
    _requireCurrent(current, expectedCurrent);
    final updated = current.voidClaim();
    _upsert(updated);
    return updated;
  }

  ClaimPaymentBatch markPaid(
    EntityId id, {
    required EntityId paymentBatchId,
    required DateTime paidAt,
  }) {
    return markPaidBatch(
      claimIds: <EntityId>[id],
      paymentBatchId: paymentBatchId,
      paidAt: paidAt,
    );
  }

  ClaimPaymentBatch markPaidBatch({
    required List<EntityId> claimIds,
    required EntityId paymentBatchId,
    required DateTime paidAt,
    String? paymentReference,
  }) {
    paymentReference = paymentReference?.trim();
    if (paymentReference != null &&
        (paymentReference.isEmpty || paymentReference.length > 120)) {
      throw ArgumentError('Payment reference must contain 1–120 characters.');
    }
    if (claimIds.isEmpty) {
      throw ArgumentError.value(
        claimIds,
        'claimIds',
        'At least one claim is required.',
      );
    }
    final existingBatch = _claims
        .where((claim) => claim.paymentBatchId == paymentBatchId)
        .toList(growable: false);
    if (existingBatch.isNotEmpty) {
      final requestedIds = claimIds.toSet();
      if (requestedIds.length != claimIds.length ||
          existingBatch.length != requestedIds.length ||
          existingBatch.any((claim) => !requestedIds.contains(claim.id)) ||
          existingBatch.any(
            (claim) =>
                claim.paidAt != paidAt.toUtc() ||
                claim.paymentReference != paymentReference,
          )) {
        throw StateError(
          'Payment batch ID was already used for another payment.',
        );
      }
      return ClaimPaymentBatch.restore(
        id: paymentBatchId,
        claims: existingBatch,
        paidAt: paidAt,
      );
    }
    final claims = claimIds.map(_required).toList(growable: false);
    if (claims.any(
      (claim) =>
          claim.status != ClaimStatus.submitted &&
          claim.status != ClaimStatus.approved,
    )) {
      throw StateError('Only submitted or approved claims can be paid.');
    }
    final batch = ClaimPaymentBatch.create(
      id: paymentBatchId,
      claims: claims,
      paidAt: paidAt,
      paymentReference: paymentReference,
    );
    persistChanges?.call(List.unmodifiable(batch.claims));
    for (final claim in batch.claims) {
      _replaceInMemory(claim);
    }
    notifyListeners();
    return batch;
  }

  Claim _required(EntityId id) {
    final claim = byId(id);
    if (claim == null) throw StateError('Claim $id was not found.');
    return claim;
  }

  void _upsert(Claim claim) {
    persistChanges?.call(List.unmodifiable([claim]));
    _replaceInMemory(claim);
    notifyListeners();
  }

  void _replaceInMemory(Claim claim) {
    final index = _claims.indexWhere((item) => item.id == claim.id);
    if (index == -1) {
      _claims.add(claim);
    } else {
      _claims[index] = claim;
    }
  }
}

ReceiptAttachment _demoAttachment(String originalId, String filename) {
  final input = ReceiptAttachmentInput(
    originalId: originalId,
    batchId: 'claim-demo-batch',
    filename: filename,
    mimeType: filename.endsWith('.jpg') ? 'image/jpeg' : 'application/pdf',
    bytes: Uint8List.fromList(<int>[37, 80, 68, 70, 45, 49, 46, 55]),
  );
  return ReceiptAttachment.queued(input)
      .withStatus(AttachmentProcessingStatus.ready);
}
