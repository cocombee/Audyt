import 'bank_statement_import.dart';
import '../../../../core/documents/receipt_document.dart';
import '../../../../core/money/money.dart';
import 'bank_statement_match.dart';

/// Resumable form inputs only. A draft never stores an approval or trusts an
/// old match snapshot; Review must calculate again from the current ledger.
final class StatementReconciliationDraft {
  StatementReconciliationDraft({
    required this.paymentAccountId,
    required this.startsOn,
    required this.endsOn,
    required this.openingBalance,
    required this.closingBalance,
    required this.openingEvidence,
    required Set<String> openingOutstandingIds,
    required this.revision,
    required this.savedAt,
    List<ReceiptAttachment> attachments = const [],
  }) : openingOutstandingIds = Set.unmodifiable(openingOutstandingIds),
       attachments = List.unmodifiable(
         attachments.map((item) => ReceiptAttachment.fromJson(item.toJson())),
       );

  final String paymentAccountId;
  final DateTime startsOn;
  final DateTime endsOn;
  final Money openingBalance;
  final Money closingBalance;
  final String openingEvidence;
  final Set<String> openingOutstandingIds;
  final int revision;
  final DateTime savedAt;
  final List<ReceiptAttachment> attachments;
}

/// A review of one imported statement, not a completion or posting command.
/// Opening balance must later be verified against the prior reconciliation.
final class StatementReconciliationReview {
  StatementReconciliationReview._({
    required this.statementMovement,
    required this.matchedMovement,
    required this.statementDifference,
    required this.matchDifference,
    required List<int> unmatchedRows,
    required List<int> invalidMatchRows,
    required List<int> outsidePeriodRows,
  }) : unmatchedRows = List.unmodifiable(unmatchedRows),
       invalidMatchRows = List.unmodifiable(invalidMatchRows),
       outsidePeriodRows = List.unmodifiable(outsidePeriodRows);

  final Money statementMovement;
  final Money matchedMovement;

  /// Closing balance minus opening balance and all statement movements.
  final Money statementDifference;

  /// Closing balance minus opening balance and verified matched movements.
  final Money matchDifference;
  final List<int> unmatchedRows;
  final List<int> invalidMatchRows;
  final List<int> outsidePeriodRows;

  /// Arithmetic and row coverage only; does not establish a reconciled account.
  bool get rowsAndBalancesAgree =>
      statementDifference.isZero &&
      matchDifference.isZero &&
      unmatchedRows.isEmpty &&
      invalidMatchRows.isEmpty &&
      outsidePeriodRows.isEmpty;

  static StatementReconciliationReview evaluate({
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    required List<StatementRowSuggestions> rows,
    required Map<int, String> acceptedMatches,
    Map<int, String> acceptanceIds = const {},
    Map<String, Money> groupedMovementAmounts = const {},
    Map<String, List<StatementPostedMovement>> combinedMovements = const {},
  }) {
    DateTime day(DateTime value) =>
        DateTime.utc(value.year, value.month, value.day);
    final start = day(startsOn);
    final end = day(endsOn);
    if (end.isBefore(start)) {
      throw ArgumentError('Statement end must not precede its start.');
    }
    if (openingBalance.currency != closingBalance.currency) {
      throw ArgumentError('Statement balances must use one currency.');
    }
    if (rows.isEmpty) {
      throw ArgumentError('The imported statement has no transaction rows.');
    }
    var total = BigInt.zero;
    var matched = BigInt.zero;
    final seenRows = <int>{};
    final usedMovements = <String>{};
    final unmatched = <int>[];
    final invalid = <int>[];
    final outside = <int>[];
    final groupRows = <String, List<BankStatementRow>>{};
    for (final suggestion in rows) {
      final id = acceptanceIds[suggestion.row.sourceRow];
      if (id != null && groupedMovementAmounts.containsKey(id)) {
        groupRows.putIfAbsent(id, () => []).add(suggestion.row);
      }
    }
    final validGroups = <String, bool>{};
    for (final entry in groupRows.entries) {
      final movement = groupedMovementAmounts[entry.key]!;
      validGroups[entry.key] =
          entry.value.length >= 2 &&
          entry.value.every(
            (row) => row.amount.currency == movement.currency,
          ) &&
          entry.value.fold<BigInt>(
                BigInt.zero,
                (sum, row) => sum + BigInt.from(row.amount.minorUnits),
              ) ==
              BigInt.from(movement.minorUnits) &&
          acceptanceIds.entries
                  .where((item) => item.value == entry.key)
                  .length ==
              entry.value.length &&
          entry.value
                  .map((row) => acceptedMatches[row.sourceRow])
                  .toSet()
                  .length ==
              1;
    }
    final countedGroups = <String>{};
    final conflictedGroups = <String>{};
    for (final suggestion in rows) {
      final row = suggestion.row;
      if (!seenRows.add(row.sourceRow)) {
        throw ArgumentError('A statement row appears more than once.');
      }
      if (row.amount.currency != openingBalance.currency) {
        throw ArgumentError(
          'Statement row currency differs from its balances.',
        );
      }
      final date = day(row.date);
      if (date.isBefore(start) || date.isAfter(end)) {
        outside.add(row.sourceRow);
      }
      total += BigInt.from(row.amount.minorUnits);
      final movement = acceptedMatches[row.sourceRow];
      final groupId = acceptanceIds[row.sourceRow];
      if (movement == null) {
        unmatched.add(row.sourceRow);
      } else if (groupId != null && combinedMovements.containsKey(groupId)) {
        final components = combinedMovements[groupId]!;
        final identities = components
            .map((part) => part.candidate.movementId)
            .toSet();
        final valid =
            components.length >= 2 &&
            identities.length == components.length &&
            identities.contains(movement) &&
            components.every(
              (part) =>
                  part.amount.currency == row.amount.currency &&
                  !part.amount.isZero &&
                  (part.amount.minorUnits > 0) == (row.amount.minorUnits > 0),
            ) &&
            components.fold<BigInt>(
                  BigInt.zero,
                  (sum, part) => sum + BigInt.from(part.amount.minorUnits),
                ) ==
                BigInt.from(row.amount.minorUnits) &&
            identities.every((id) => !usedMovements.contains(id)) &&
            acceptanceIds.values.where((id) => id == groupId).length == 1;
        if (!valid) {
          invalid.add(row.sourceRow);
        } else {
          usedMovements.addAll(identities);
          matched += BigInt.from(row.amount.minorUnits);
        }
      } else if (groupId != null &&
          groupedMovementAmounts.containsKey(groupId)) {
        final first = countedGroups.add(groupId);
        if (first && !usedMovements.add(movement)) {
          conflictedGroups.add(groupId);
        }
        if (validGroups[groupId] != true ||
            conflictedGroups.contains(groupId)) {
          invalid.add(row.sourceRow);
        } else {
          matched += BigInt.from(row.amount.minorUnits);
        }
      } else if (!suggestion.candidates.any((c) => c.movementId == movement) ||
          !usedMovements.add(movement)) {
        invalid.add(row.sourceRow);
      } else {
        matched += BigInt.from(row.amount.minorUnits);
      }
    }
    invalid.addAll(
      acceptedMatches.keys.where((row) => !seenRows.contains(row)),
    );
    // Accumulate in BigInt: intermediate sums must not wrap or round.
    Money exact(BigInt value) {
      if (value < BigInt.parse('-9223372036854775808') ||
          value > BigInt.parse('9223372036854775807')) {
        throw RangeError('Statement amount exceeds the exact monetary range.');
      }
      return Money.fromMinor(value.toInt(), openingBalance.currency);
    }

    final change =
        BigInt.from(closingBalance.minorUnits) -
        BigInt.from(openingBalance.minorUnits);
    return StatementReconciliationReview._(
      statementMovement: exact(total),
      matchedMovement: exact(matched),
      statementDifference: exact(change - total),
      matchDifference: exact(change - matched),
      unmatchedRows: unmatched,
      invalidMatchRows: invalid,
      outsidePeriodRows: outside,
    );
  }
}

/// Immutable inputs and identities from the same authoritative review snapshot.
final class StatementReconciliationSnapshot {
  StatementReconciliationSnapshot({
    required this.review,
    required this.startsOn,
    required this.endsOn,
    required this.openingBalance,
    required this.closingBalance,
    required this.previousId,
    required this.recordedOpening,
    required this.requiredStart,
    required this.previousLedgerUnchanged,
    required List<OpeningLedgerMovement> openingMovements,
    required Set<String> openingOutstandingIds,
    required Map<int, String> acceptanceIds,
  }) : acceptanceIds = Map.unmodifiable(acceptanceIds),
       openingMovements = List.unmodifiable(openingMovements),
       openingOutstandingIds = Set.unmodifiable(openingOutstandingIds);
  final List<OpeningLedgerMovement> openingMovements;
  final Set<String> openingOutstandingIds;
  final StatementReconciliationReview review;
  final DateTime startsOn;
  final DateTime endsOn;
  final Money openingBalance;
  final Money closingBalance;
  final String? previousId;
  final Money recordedOpening;
  final DateTime? requiredStart;
  final bool previousLedgerUnchanged;
  Money get openingDifference => openingBalance - recordedOpening;
  bool get periodContinues =>
      requiredStart == null ||
      DateTime.utc(startsOn.year, startsOn.month, startsOn.day) ==
          requiredStart;
  bool get readyForApproval =>
      review.rowsAndBalancesAgree &&
      openingDifference.isZero &&
      periodContinues &&
      previousLedgerUnchanged;
  final Map<int, String> acceptanceIds;
}

final class StatementReconciliationHistory {
  const StatementReconciliationHistory({
    required this.id,
    required this.paymentAccountId,
    required this.startsOn,
    required this.endsOn,
    required this.openingBalance,
    required this.closingBalance,
    required this.actorId,
    required this.approvedAt,
    required this.openingEvidence,
    required this.previousId,
    required this.reopenedAt,
    required this.reopenedBy,
    required this.reopeningReason,
  });
  final String id;
  final String paymentAccountId;
  final DateTime startsOn;
  final DateTime endsOn;
  final Money openingBalance;
  final Money closingBalance;
  final String actorId;
  final DateTime approvedAt;
  final String openingEvidence;
  final String? previousId;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final String? reopeningReason;
}

final class ReconciliationMatchedEvidence {
  const ReconciliationMatchedEvidence({
    required this.statementRow,
    required this.acceptanceId,
    required this.journalId,
    required this.lineIndex,
    required this.journalDate,
    required this.journalMemo,
    this.combinedMovements = const [],
  });
  final List<StatementPostedMovement> combinedMovements;
  final BankStatementRow statementRow;
  final String acceptanceId;
  final String journalId;
  final int lineIndex;
  final DateTime journalDate;
  final String journalMemo;
}

final class ReconciliationEvidence {
  ReconciliationEvidence({
    required this.filename,
    required this.sourceDigest,
    required List<ReconciliationMatchedEvidence> matches,
    required List<OpeningLedgerMovement> openingOutstanding,
    this.isAccountPeriod = false,
    List<OpeningLedgerMovement> selectedMovements = const [],
    List<ReceiptAttachment> attachments = const [],
  }) : matches = List.unmodifiable(matches),
       selectedMovements = List.unmodifiable(selectedMovements),
       openingOutstanding = List.unmodifiable(openingOutstanding),
       attachments = List.unmodifiable(
         attachments.map((item) => ReceiptAttachment.fromJson(item.toJson())),
       );
  final List<OpeningLedgerMovement> openingOutstanding;
  final String filename;
  final String sourceDigest;
  final List<ReconciliationMatchedEvidence> matches;
  final List<ReceiptAttachment> attachments;
  final bool isAccountPeriod;
  final List<OpeningLedgerMovement> selectedMovements;
}

final class OpeningLedgerMovement {
  const OpeningLedgerMovement({
    required this.id,
    required this.date,
    required this.memo,
    required this.amount,
  });
  final String id;
  final DateTime date;
  final String memo;
  final Money amount;
}

final class ReconciliationLedgerSnapshot {
  ReconciliationLedgerSnapshot({
    required List<OpeningLedgerMovement> movements,
    required this.balance,
  }) : movements = List.unmodifiable(movements);
  final List<OpeningLedgerMovement> movements;
  final Money balance;
}

final class ReconciliationLedgerChanges {
  ReconciliationLedgerChanges({
    required this.snapshotAvailable,
    required List<OpeningLedgerMovement> added,
    required List<OpeningLedgerMovement> missing,
    required Set<String> changed,
  }) : added = List.unmodifiable(added),
       missing = List.unmodifiable(missing),
       changed = Set.unmodifiable(changed);
  final bool snapshotAvailable;
  final List<OpeningLedgerMovement> added;
  final List<OpeningLedgerMovement> missing;
  final Set<String> changed;
  bool get unchanged =>
      snapshotAvailable && added.isEmpty && missing.isEmpty && changed.isEmpty;
}

final class ReconciliationClassification {
  ReconciliationClassification({
    required List<OpeningLedgerMovement> cleared,
    required List<OpeningLedgerMovement> outstanding,
    required Set<String> unresolved,
    required this.clearedBalance,
    required this.outstandingBalance,
    required this.closingDifference,
  }) : cleared = List.unmodifiable(cleared),
       outstanding = List.unmodifiable(outstanding),
       unresolved = Set.unmodifiable(unresolved);
  final List<OpeningLedgerMovement> cleared;
  final List<OpeningLedgerMovement> outstanding;
  final Set<String> unresolved;
  final Money clearedBalance;
  final Money outstandingBalance;
  final Money closingDifference;
  bool get agrees => closingDifference.isZero && unresolved.isEmpty;
}

final class ReconciliationReportSnapshot {
  const ReconciliationReportSnapshot({
    required this.approval,
    required this.evidence,
    required this.ledger,
    required this.classification,
    required this.changes,
    required this.generatedAt,
  });
  final StatementReconciliationHistory approval;
  final ReconciliationEvidence evidence;
  final ReconciliationLedgerSnapshot? ledger;
  final ReconciliationClassification? classification;
  final ReconciliationLedgerChanges changes;
  final DateTime generatedAt;
}
