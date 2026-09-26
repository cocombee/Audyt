import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';

final class ClaimPaymentBatch {
  ClaimPaymentBatch._({
    required this.id,
    required List<Claim> claims,
    required this.paidAt,
    required this.total,
  }) : claims = List.unmodifiable(claims);

  factory ClaimPaymentBatch.create({
    required EntityId id,
    required List<Claim> claims,
    required DateTime paidAt,
    String? paymentReference,
  }) {
    if (claims.isEmpty) {
      throw ArgumentError.value(
        claims,
        'claims',
        'At least one claim is required.',
      );
    }
    final claimIds = claims.map((claim) => claim.id).toSet();
    if (claimIds.length != claims.length) {
      throw ArgumentError.value(
        claims,
        'claims',
        'A claim cannot be included twice.',
      );
    }
    if (claims.any((claim) => claim.status == ClaimStatus.paid)) {
      throw StateError('Already-paid claims cannot enter a new batch.');
    }
    if (claims.any((claim) => claim.status == ClaimStatus.voided)) {
      throw StateError('Voided claims cannot enter a payment batch.');
    }

    final currencies = claims.map((claim) => claim.amount.currency).toSet();
    if (currencies.length != 1) {
      throw ArgumentError.value(
        claims,
        'claims',
        'A payment batch must use one currency.',
      );
    }
    final currency = claims.first.amount.currency;
    final total = claims.fold(
      Money.zero(currency),
      (sum, claim) => sum + claim.amount,
    );
    final normalizedPaidAt = paidAt.toUtc();
    return ClaimPaymentBatch._(
      id: id,
      claims: claims
          .map(
            (claim) => claim.markPaid(
              paymentBatchId: id,
              paidAt: normalizedPaidAt,
              paymentReference: paymentReference,
            ),
          )
          .toList(),
      paidAt: normalizedPaidAt,
      total: total,
    );
  }

  factory ClaimPaymentBatch.restore({
    required EntityId id,
    required List<Claim> claims,
    required DateTime paidAt,
  }) {
    if (claims.isEmpty) {
      throw ArgumentError.value(
        claims,
        'claims',
        'At least one claim is required.',
      );
    }
    final claimIds = claims.map((claim) => claim.id).toSet();
    if (claimIds.length != claims.length) {
      throw ArgumentError.value(
        claims,
        'claims',
        'A claim cannot be included twice.',
      );
    }
    final normalizedPaidAt = paidAt.toUtc();
    if (claims.any(
      (claim) =>
          claim.status != ClaimStatus.paid ||
          claim.paymentBatchId != id ||
          claim.paidAt != normalizedPaidAt,
    )) {
      throw StateError('Stored claims do not match the payment batch.');
    }
    final currencies = claims.map((claim) => claim.amount.currency).toSet();
    if (currencies.length != 1) {
      throw ArgumentError.value(
        claims,
        'claims',
        'A payment batch must use one currency.',
      );
    }
    if (claims.map((claim) => claim.paymentReference).toSet().length != 1) {
      throw StateError('Stored claims disagree on the payment reference.');
    }
    final total = claims.fold(
      Money.zero(claims.first.amount.currency),
      (sum, claim) => sum + claim.amount,
    );
    return ClaimPaymentBatch._(
      id: id,
      claims: claims,
      paidAt: normalizedPaidAt,
      total: total,
    );
  }

  final EntityId id;
  final List<Claim> claims;
  final DateTime paidAt;
  final Money total;

  String? get reference => claims.first.paymentReference;

  List<EntityId> get claimIds => claims.map((claim) => claim.id).toList();
}
