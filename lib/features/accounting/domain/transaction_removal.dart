import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';

enum TransactionRecordKind {
  claim,
  paymentVoucher,
  bill,
  quotation,
  invoiceCredit,
}

/// Review token for recoverable removal, separate from source lifecycle/revision.
/// Original records, receipts and financial histories are retained unchanged.
final class TransactionRemovalReview {
  const TransactionRemovalReview({
    required this.businessId,
    required this.kind,
    required this.recordId,
    required this.sourceFingerprint,
    required this.revision,
    required this.removed,
    required this.label,
    required this.status,
    required this.restriction,
    required this.amount,
    this.changedAt,
  });
  final EntityId businessId;
  final TransactionRecordKind kind;
  final String recordId, sourceFingerprint, label, status;
  final int revision;
  final bool removed;
  final String? restriction;
  final Money amount;
  final DateTime? changedAt;
  bool get canRemove => !removed && restriction == null;
  bool get canRestore => removed && restriction == null;
}
