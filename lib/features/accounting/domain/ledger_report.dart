import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

/// Accrual ledger report. Amounts are exact minor units in one functional currency.
/// Cash-basis conversion and subledger ageing are separate reports.
final class LedgerReport {
  LedgerReport._({
    required this.businessId,
    required this.currency,
    required this.from,
    required this.through,
    required this.rows,
    required this.pendingDrafts,
    required this.postedJournalIds,
    required this.postedEntries,
  });

  factory LedgerReport.build({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
    required Iterable<StoredAccount> accounts,
    required Iterable<StoredJournalEntry> journals,
  }) {
    final start = _day(from);
    final end = _day(through);
    if (start.isAfter(end)) {
      throw ArgumentError('Report start must not follow its end.');
    }
    final chart = <EntityId, Account>{};
    for (final record in accounts) {
      if (record.metadata.businessId != businessId) {
        throw StateError('The report chart contains another business.');
      }
      if (chart.containsKey(record.account.id)) {
        throw StateError('The report chart contains duplicate account IDs.');
      }
      chart[record.account.id] = record.account;
    }
    final opening = <EntityId, BigInt>{};
    final debits = <EntityId, BigInt>{};
    final credits = <EntityId, BigInt>{};
    final activity = <EntityId, BigInt>{};
    final seen = <EntityId>{};
    final postedIds = <EntityId>[];
    final postedEntries = <JournalEntry>[];
    var pending = 0;
    for (final record in journals) {
      if (record.metadata.businessId != businessId) {
        throw StateError('The report contains another business.');
      }
      if (!seen.add(record.entry.id)) {
        throw StateError('A journal appears more than once in the report.');
      }
      final entry = record.entry;
      final day = _day(entry.date);
      if (day.isAfter(end)) continue;
      if (record.metadata.isTombstone) {
        if (entry.state == JournalEntryState.posted) {
          throw StateError(
            'A posted journal was deleted; accounting review is required.',
          );
        }
        continue;
      }
      if (entry.state == JournalEntryState.draft) {
        pending++;
        continue;
      }
      if (entry.state != JournalEntryState.posted) continue;
      if (entry.validationErrors.isNotEmpty) {
        throw StateError(
          'A posted journal is invalid; repair requires accounting review.',
        );
      }
      postedIds.add(entry.id);
      postedEntries.add(entry);
      for (final line in entry.lines) {
        if (!chart.containsKey(line.accountId)) {
          throw StateError('A posted journal references an unmapped account.');
        }
        if (line.amount.currency != currency) {
          throw StateError(
            'Posted currency does not match the report currency.',
          );
        }
        final amount = BigInt.from(line.amount.minorUnits);
        if (day.isBefore(start)) {
          opening.update(
            line.accountId,
            (value) => value + (line.isDebit ? amount : -amount),
            ifAbsent: () => line.isDebit ? amount : -amount,
          );
        } else {
          if (!entry.isClosing) {
            activity.update(
              line.accountId,
              (value) => value + (line.isDebit ? amount : -amount),
              ifAbsent: () => line.isDebit ? amount : -amount,
            );
          }
          final target = line.isDebit ? debits : credits;
          target.update(
            line.accountId,
            (value) => value + amount,
            ifAbsent: () => amount,
          );
        }
      }
    }
    final rows =
        chart.values
            .map(
              (account) => LedgerAccountBalance(
                account: account,
                openingNetDebit: opening[account.id] ?? BigInt.zero,
                periodDebits: debits[account.id] ?? BigInt.zero,
                periodCredits: credits[account.id] ?? BigInt.zero,
                operatingNetDebit: activity[account.id] ?? BigInt.zero,
              ),
            )
            .toList()
          ..sort((a, b) => a.account.code.compareTo(b.account.code));
    return LedgerReport._(
      businessId: businessId,
      currency: currency,
      from: start,
      through: end,
      rows: List.unmodifiable(rows),
      pendingDrafts: pending,
      postedJournalIds: List.unmodifiable(postedIds),
      postedEntries: List.unmodifiable(postedEntries),
    );
  }

  final EntityId businessId;
  final String currency;
  final DateTime from;
  final DateTime through;
  final List<LedgerAccountBalance> rows;
  final int pendingDrafts;
  final List<EntityId> postedJournalIds;

  /// Immutable entries read in the same database snapshot as the totals.
  final List<JournalEntry> postedEntries;

  List<JournalEntry> activityFor(
    EntityId accountId, {
    bool operatingOnly = false,
  }) {
    if (!rows.any((row) => row.account.id == accountId)) {
      throw ArgumentError('Account is not part of this report.');
    }
    final entries =
        postedEntries
            .where(
              (entry) =>
                  !_day(entry.date).isBefore(from) &&
                  (!operatingOnly || !entry.isClosing) &&
                  entry.lines.any((line) => line.accountId == accountId),
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            return byDate == 0 ? a.id.value.compareTo(b.id.value) : byDate;
          });
    return List.unmodifiable(entries);
  }

  BigInt get trialBalanceDebits => rows.fold(
    BigInt.zero,
    (sum, row) =>
        sum +
        (row.endingNetDebit > BigInt.zero ? row.endingNetDebit : BigInt.zero),
  );
  BigInt get trialBalanceCredits => rows.fold(
    BigInt.zero,
    (sum, row) =>
        sum +
        (row.endingNetDebit < BigInt.zero ? -row.endingNetDebit : BigInt.zero),
  );
  BigInt get assets => _ending(AccountType.asset);
  BigInt get liabilities => -_ending(AccountType.liability);
  BigInt get contributedAndRetainedEquity => -_ending(AccountType.equity);

  /// Income and expense balances not yet closed to equity. This is a presentation
  /// calculation from actual journal lines, never a generated balancing entry.
  BigInt get unclosedEarnings =>
      -_ending(AccountType.income) - _ending(AccountType.expense);
  BigInt get totalEquity => contributedAndRetainedEquity + unclosedEarnings;
  BigInt get balanceSheetDifference => assets - liabilities - totalEquity;
  BigInt get revenue => -_movement(AccountType.income);
  BigInt get expenses => _movement(AccountType.expense);
  BigInt get periodProfit => revenue - expenses;
  bool get isBalanced =>
      trialBalanceDebits == trialBalanceCredits &&
      balanceSheetDifference == BigInt.zero;

  BigInt _ending(AccountType type) => rows
      .where((r) => r.account.type == type)
      .fold(BigInt.zero, (sum, row) => sum + row.endingNetDebit);
  BigInt _movement(AccountType type) => rows
      .where((r) => r.account.type == type)
      .fold(BigInt.zero, (sum, row) => sum + row.operatingNetDebit);
  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}

final class LedgerAccountBalance {
  const LedgerAccountBalance({
    required this.account,
    required this.openingNetDebit,
    required this.periodDebits,
    required this.periodCredits,
    required this.operatingNetDebit,
  });
  final Account account;
  final BigInt openingNetDebit;
  final BigInt periodDebits;
  final BigInt periodCredits;
  final BigInt operatingNetDebit;
  BigInt get endingNetDebit => openingNetDebit + periodDebits - periodCredits;
}
