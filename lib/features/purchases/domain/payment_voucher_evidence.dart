import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

/// A reviewed payment already posted by the linked source's accounting owner.
/// The bank movement can cover several claims; the voucher remains one source.
final class PaymentVoucherPaymentEvidence {
  PaymentVoucherPaymentEvidence({
    required this.journalId,
    required this.lineIndex,
    required this.movementAmount,
    required this.paymentDate,
  }) {
    if (lineIndex < 0 || movementAmount.minorUnits <= 0) {
      throw ArgumentError('A positive posted payment movement is required.');
    }
  }

  final EntityId journalId;
  final int lineIndex;
  final Money movementAmount;
  final DateTime paymentDate;

  Map<String, Object?> toJson() => {
    'version': 1,
    'journalId': journalId.value,
    'lineIndex': lineIndex,
    'amountMinor': movementAmount.minorUnits,
    'currency': movementAmount.currency,
    'paymentDate': paymentDate.toUtc().toIso8601String(),
  };

  factory PaymentVoucherPaymentEvidence.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported voucher payment evidence.');
    }
    return PaymentVoucherPaymentEvidence(
      journalId: EntityId.parse(json['journalId'] as String),
      lineIndex: json['lineIndex'] as int,
      movementAmount: Money.fromMinor(
        json['amountMinor'] as int,
        json['currency'] as String,
      ),
      paymentDate: DateTime.parse(json['paymentDate'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentVoucherPaymentEvidence &&
      journalId == other.journalId &&
      lineIndex == other.lineIndex &&
      movementAmount == other.movementAmount &&
      paymentDate.isAtSameMomentAs(other.paymentDate);
  @override
  int get hashCode => Object.hash(
    journalId,
    lineIndex,
    movementAmount,
    paymentDate.microsecondsSinceEpoch,
  );
}

/// The completed bank review containing this exact source payment movement.
final class PaymentVoucherReconciliationEvidence {
  const PaymentVoucherReconciliationEvidence({
    required this.acceptanceId,
    required this.completionId,
    required this.approvedAt,
  });
  final EntityId acceptanceId, completionId;
  final DateTime approvedAt;

  Map<String, Object?> toJson() => {
    'version': 1,
    'acceptanceId': acceptanceId.value,
    'completionId': completionId.value,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
  };
  factory PaymentVoucherReconciliationEvidence.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['version'] != 1) {
      throw const FormatException(
        'Unsupported voucher reconciliation evidence.',
      );
    }
    return PaymentVoucherReconciliationEvidence(
      acceptanceId: EntityId.parse(json['acceptanceId'] as String),
      completionId: EntityId.parse(json['completionId'] as String),
      approvedAt: DateTime.parse(json['approvedAt'] as String),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is PaymentVoucherReconciliationEvidence &&
      acceptanceId == other.acceptanceId &&
      completionId == other.completionId &&
      approvedAt.isAtSameMomentAs(other.approvedAt);
  @override
  int get hashCode => Object.hash(
    acceptanceId,
    completionId,
    approvedAt.microsecondsSinceEpoch,
  );
}
