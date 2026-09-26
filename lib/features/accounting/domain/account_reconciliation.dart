import '../../../../core/money/money.dart';
import '../../../../core/documents/receipt_document.dart';
import 'statement_reconciliation.dart';

/// Account-period clearing review, independent of imported bank rows.
/// This is arithmetic evidence, never an approval or posting command.
final class AccountReconciliationReview {
  AccountReconciliationReview._({
    required this.clearedMovement,
    required this.clearedBalance,
    required this.closingDifference,
    required List<OpeningLedgerMovement> selected,
    required List<OpeningLedgerMovement> outstanding,
    required Set<String> unresolved,
  }) : selected = List.unmodifiable(selected),
       outstanding = List.unmodifiable(outstanding),
       unresolved = Set.unmodifiable(unresolved);

  final Money clearedMovement;
  final Money clearedBalance;
  final Money closingDifference;
  final List<OpeningLedgerMovement> selected;
  final List<OpeningLedgerMovement> outstanding;
  final Set<String> unresolved;
  bool get balancesAndSelectionAgree =>
      closingDifference.isZero && unresolved.isEmpty;

  static AccountReconciliationReview evaluate({
    required Money openingBalance,
    required Money closingBalance,
    required List<OpeningLedgerMovement> eligibleMovements,
    required Set<String> selectedIds,
  }) {
    if (openingBalance.currency != closingBalance.currency) {
      throw ArgumentError('Reconciliation balances must use one currency.');
    }
    final seen = <String>{};
    final selected = <OpeningLedgerMovement>[];
    final outstanding = <OpeningLedgerMovement>[];
    var total = BigInt.zero;
    for (final movement in eligibleMovements) {
      if (movement.id.isEmpty || !seen.add(movement.id)) {
        throw ArgumentError('Ledger movement identity is inconsistent.');
      }
      if (movement.amount.currency != openingBalance.currency) {
        throw ArgumentError('Ledger movement currency differs.');
      }
      if (selectedIds.contains(movement.id)) {
        selected.add(movement);
        total += BigInt.from(movement.amount.minorUnits);
      } else {
        outstanding.add(movement);
      }
    }
    Money exact(BigInt value) {
      if (value < BigInt.parse('-9223372036854775808') ||
          value > BigInt.parse('9223372036854775807')) {
        throw RangeError('Reconciliation exceeds the exact monetary range.');
      }
      return Money.fromMinor(value.toInt(), openingBalance.currency);
    }

    final cleared = BigInt.from(openingBalance.minorUnits) + total;
    return AccountReconciliationReview._(
      clearedMovement: exact(total),
      clearedBalance: exact(cleared),
      closingDifference: exact(
        BigInt.from(closingBalance.minorUnits) - cleared,
      ),
      selected: selected,
      outstanding: outstanding,
      unresolved: selectedIds.difference(seen),
    );
  }
}

/// Fresh company/account-scoped ledger facts for the proposed period.
/// Approval reloads these facts and validates their exact fingerprint at commit.
final class AccountReconciliationSnapshot {
  AccountReconciliationSnapshot({
    required this.paymentAccountId,
    required this.startsOn,
    required this.endsOn,
    required this.openingBalance,
    required this.closingBalance,
    required this.recordedOpening,
    required this.previousId,
    required this.requiredStart,
    required this.previousLedgerUnchanged,
    required this.review,
    required this.ledgerFingerprint,
    required List<OpeningLedgerMovement> ledgerMovements,
    required Set<String> openingOutstandingIds,
  }) : ledgerMovements = List.unmodifiable(ledgerMovements),
       openingOutstandingIds = Set.unmodifiable(openingOutstandingIds);

  final String paymentAccountId;
  final DateTime startsOn;
  final DateTime endsOn;
  final Money openingBalance;
  final Money closingBalance;
  final Money recordedOpening;
  final String? previousId;
  final DateTime? requiredStart;
  final bool previousLedgerUnchanged;
  final AccountReconciliationReview review;
  final String ledgerFingerprint;
  final List<OpeningLedgerMovement> ledgerMovements;
  final Set<String> openingOutstandingIds;
  bool get periodContinues =>
      requiredStart == null || startsOn == requiredStart;
  bool get reviewAgrees =>
      openingBalance == recordedOpening &&
      periodContinues &&
      previousLedgerUnchanged &&
      review.balancesAndSelectionAgree;
}

/// Resumable inputs. Current ledger facts are reloaded by Review and approval.
final class AccountReconciliationDraft {
  AccountReconciliationDraft({
    required this.paymentAccountId,
    required this.startsOn,
    required this.endsOn,
    required this.openingBalance,
    required this.closingBalance,
    required this.openingEvidence,
    required this.expectedPreviousId,
    required this.revision,
    required this.savedAt,
    required Set<String> selectedIds,
    required Set<String> openingOutstandingIds,
    List<ReceiptAttachment> attachments = const [],
  }) : selectedIds = Set.unmodifiable(selectedIds),
       openingOutstandingIds = Set.unmodifiable(openingOutstandingIds),
       attachments = List.unmodifiable(
         attachments.map((file) => ReceiptAttachment.fromJson(file.toJson())),
       );
  final String paymentAccountId;
  final DateTime startsOn;
  final DateTime endsOn;
  final Money openingBalance;
  final Money closingBalance;
  final String openingEvidence;
  final String? expectedPreviousId;
  final int revision;
  final DateTime savedAt;
  final Set<String> selectedIds;
  final Set<String> openingOutstandingIds;
  final List<ReceiptAttachment> attachments;
}
