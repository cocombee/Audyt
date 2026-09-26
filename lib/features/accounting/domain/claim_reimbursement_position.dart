import '../../../core/ids/entity_id.dart';
import 'claimant_statement.dart';

/// One Claim's dated, source-attributed liability. The employee's other Claims,
/// pending edits and manual control-account movements do not own this balance.
final class ClaimReimbursementPosition {
  ClaimReimbursementPosition({
    required this.businessId,
    required this.claimId,
    required this.currency,
    required this.through,
    required Iterable<ClaimantStatementEvent> activity,
  }) : activity = List.unmodifiable(activity) {
    if (this.activity.any(
      (event) =>
          event.claim.id != claimId || event.claim.amount.currency != currency,
    )) {
      throw StateError('Claim balance activity belongs to a different source.');
    }
  }

  final EntityId businessId, claimId;
  final String currency;
  final DateTime through;
  final List<ClaimantStatementEvent> activity;

  BigInt get recognizedMinor => activity
      .where(
        (event) => switch (event.kind) {
          ClaimantEventKind.recognition ||
          ClaimantEventKind.recognitionReversal => true,
          _ => false,
        },
      )
      .fold(BigInt.zero, (total, event) => total + event.balanceChangeMinor);

  BigInt get reimbursedMinor => -activity
      .where(
        (event) => switch (event.kind) {
          ClaimantEventKind.reimbursement ||
          ClaimantEventKind.reimbursementReversal => true,
          _ => false,
        },
      )
      .fold(BigInt.zero, (total, event) => total + event.balanceChangeMinor);

  /// Signed: positive is due to the claimant; negative is due back to the company.
  /// Never clamp or replace this with the mutable Claim status/approved amount.
  BigInt get outstandingMinor => recognizedMinor - reimbursedMinor;
}
