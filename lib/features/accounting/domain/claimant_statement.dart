import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../purchases/domain/claim.dart';
import 'ledger_report.dart';

enum ClaimantEventKind {
  recognition,
  recognitionReversal,
  reimbursement,
  reimbursementReversal,
}

final class ClaimantStatementEvent {
  const ClaimantStatementEvent({
    required this.claim,
    required this.journalId,
    required this.accountId,
    required this.date,
    required this.kind,
    required this.balanceChangeMinor,
    this.reference = '',
  });
  final Claim claim;
  final EntityId journalId, accountId;
  final DateTime date;
  final ClaimantEventKind kind;

  /// Positive increases what the company owes; negative reduces it.
  final BigInt balanceChangeMinor;
  final String reference;
  String get claimantKey => claim.claimantIdentity == null
      ? 'unlinked:${claim.id.value}'
      : 'payee:${claim.claimantIdentity!.payeeId}';
  String get label => switch (kind) {
    ClaimantEventKind.recognition => 'Approved Claim',
    ClaimantEventKind.recognitionReversal => 'Claim Recognition Reversal',
    ClaimantEventKind.reimbursement => 'Reimbursement',
    ClaimantEventKind.reimbursementReversal => 'Reimbursement Reversal',
  };
}

final class ClaimantStatement {
  ClaimantStatement({
    required this.key,
    required this.claimantName,
    required this.identity,
    required this.openingMinor,
    required Iterable<ClaimantStatementEvent> events,
  }) : events = List.unmodifiable(events);
  final String key, claimantName;
  final ClaimantIdentity? identity;
  final BigInt openingMinor;
  final List<ClaimantStatementEvent> events;
  BigInt get movementMinor =>
      events.fold(BigInt.zero, (n, e) => n + e.balanceChangeMinor);
  BigInt get closingMinor => openingMinor + movementMinor;
}

final class ClaimantControlBalance {
  const ClaimantControlBalance({
    required this.ledgerBalance,
    required this.attributedOpeningMinor,
    required this.attributedMovementMinor,
  });
  final LedgerAccountBalance ledgerBalance;
  final BigInt attributedOpeningMinor, attributedMovementMinor;
  BigInt get attributedClosingMinor =>
      attributedOpeningMinor + attributedMovementMinor;
  BigInt get otherOpeningMinor =>
      -ledgerBalance.openingNetDebit - attributedOpeningMinor;
  BigInt get otherMovementMinor =>
      ledgerBalance.periodCredits -
      ledgerBalance.periodDebits -
      attributedMovementMinor;
  BigInt get otherClosingMinor =>
      -ledgerBalance.endingNetDebit - attributedClosingMinor;
}

/// Dated liability activity from immutable recognition/settlement sources.
/// Current workflow status never decides an historical outstanding balance.
final class ClaimantStatementReport {
  ClaimantStatementReport.build({
    required this.ledger,
    required Iterable<ClaimantStatementEvent> activity,
    required Iterable<Claim> currentlyAwaitingReview,
    Iterable<EntityId> controlAccountIds = const [],
  }) {
    final all = activity.toList()
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.journalId.value.compareTo(b.journalId.value);
      });
    final seen = <String>{};
    final attributed = <String, BigInt>{};
    for (final e in all) {
      if (!ledger.postedJournalIds.contains(e.journalId) ||
          accountingCalendarDate(e.date).isAfter(ledger.through) ||
          e.claim.amount.currency != ledger.currency ||
          !seen.add('${e.journalId}:${e.claim.id}')) {
        throw StateError('Claimant activity does not match its posted source.');
      }
      final k = '${e.journalId}:${e.accountId}';
      attributed.update(
        k,
        (n) => n + e.balanceChangeMinor,
        ifAbsent: () => e.balanceChangeMinor,
      );
    }
    for (final pair in attributed.entries) {
      final ids = pair.key.split(':');
      final journal = ledger.postedEntries.singleWhere(
        (j) => j.id.value == ids[0],
      );
      final actual = journal.lines
          .where((l) => l.accountId.value == ids[1])
          .fold(
            BigInt.zero,
            (n, l) =>
                n +
                BigInt.from(l.amount.minorUnits) *
                    (l.isDebit ? -BigInt.one : BigInt.one),
          );
      if (actual != pair.value) {
        throw StateError(
          'Claimant allocations do not reconcile to the liability journal.',
        );
      }
    }
    final groups = <String, List<ClaimantStatementEvent>>{};
    for (final e in all) {
      groups.putIfAbsent(e.claimantKey, () => []).add(e);
    }
    statements = List.unmodifiable([
      for (final group in groups.entries)
        ClaimantStatement(
          key: group.key,
          claimantName: group.value.last.claim.claimantName,
          identity: group.value.last.claim.claimantIdentity,
          openingMinor: group.value
              .where(
                (e) => accountingCalendarDate(e.date).isBefore(ledger.from),
              )
              .fold(BigInt.zero, (n, e) => n + e.balanceChangeMinor),
          events: group.value.where(
            (e) => !accountingCalendarDate(e.date).isBefore(ledger.from),
          ),
        ),
    ]);
    // A known control account can have manual opening/period movements before
    // its first dated claim. Retain its ledger reconciliation even when no
    // claimant event falls through this report date. Membership never attributes
    // those movements to a person or imports future claim amounts.
    final accountIds = {...controlAccountIds, ...all.map((e) => e.accountId)};
    controls = List.unmodifiable([
      for (final balance in ledger.rows)
        if (accountIds.contains(balance.account.id))
          ClaimantControlBalance(
            ledgerBalance: balance,
            attributedOpeningMinor: all
                .where(
                  (e) =>
                      e.accountId == balance.account.id &&
                      accountingCalendarDate(e.date).isBefore(ledger.from),
                )
                .fold(BigInt.zero, (n, e) => n + e.balanceChangeMinor),
            attributedMovementMinor: all
                .where(
                  (e) =>
                      e.accountId == balance.account.id &&
                      !accountingCalendarDate(e.date).isBefore(ledger.from),
                )
                .fold(BigInt.zero, (n, e) => n + e.balanceChangeMinor),
          ),
    ]);
    awaitingReview = List.unmodifiable(currentlyAwaitingReview);
  }
  final LedgerReport ledger;
  late final List<ClaimantStatement> statements;
  late final List<ClaimantControlBalance> controls;

  /// Current submitted claims, distinct from dated recognized liabilities.
  late final List<Claim> awaitingReview;
}
