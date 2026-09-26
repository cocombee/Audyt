import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

import 'account.dart';
import 'journal_entry.dart';
import 'ledger_report.dart';

/// Calculation only. Persistence must revalidate the ledger snapshot atomically
/// and classify the approved journal as closing before it can be posted.
final class ClosingProposal {
  ClosingProposal._(
    this.businessId,
    this.through,
    this.equityAccountId,
    List<JournalLine> lines,
    List<EntityId> sourceJournalIds,
  ) : lines = List.unmodifiable(lines),
      sourceJournalIds = List.unmodifiable(sourceJournalIds);

  factory ClosingProposal.fromReport(
    LedgerReport report, {
    required EntityId equityAccountId,
  }) {
    if (!report.isBalanced || report.pendingDrafts != 0) {
      throw StateError(
        'Resolve ledger differences and pending drafts before closing.',
      );
    }
    final destination = report.rows.where(
      (r) => r.account.id == equityAccountId,
    );
    if (destination.length != 1 ||
        destination.single.account.type != AccountType.equity ||
        destination.single.account.status != AccountStatus.active ||
        destination.single.account.isParent) {
      throw StateError(
        'Select an active posting equity account from this business.',
      );
    }
    final lines = <JournalLine>[];
    var equityCredit = BigInt.zero;
    void add(EntityId account, BigInt debit) {
      if (debit == BigInt.zero) return;
      final magnitude = debit.abs();
      if (!magnitude.isValidInt) {
        throw RangeError(
          'Closing balance exceeds the supported journal line range.',
        );
      }
      final amount = Money.fromMinor(magnitude.toInt(), report.currency);
      lines.add(
        debit > BigInt.zero
            ? JournalLine.debit(accountId: account, amount: amount)
            : JournalLine.credit(accountId: account, amount: amount),
      );
    }

    for (final row in report.rows) {
      if (row.account.type != AccountType.income &&
          row.account.type != AccountType.expense) {
        continue;
      }
      final balance = row.endingNetDebit;
      if (balance == BigInt.zero) continue;
      if (row.account.status != AccountStatus.active || row.account.isParent) {
        throw StateError(
          'A nominal balance belongs to an unavailable posting account.',
        );
      }
      add(row.account.id, -balance);
      equityCredit -= balance;
    }
    add(equityAccountId, -equityCredit);
    return ClosingProposal._(
      report.businessId,
      report.through,
      equityAccountId,
      lines,
      report.postedJournalIds,
    );
  }

  final EntityId businessId;
  final DateTime through;
  final EntityId equityAccountId;
  final List<JournalLine> lines;
  final List<EntityId> sourceJournalIds;
  bool get isEmpty => lines.isEmpty;
}
