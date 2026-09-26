import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/money.dart';
import '../application/journal_entry_repository.dart';
import 'account.dart';
import 'bank_statement_import.dart';
import 'journal_entry.dart';

/// Calendar modes describe discovery only; explicit acceptance still verifies
/// the source account, currency, posted movement and exact amount.
enum StatementMatchWindow {
  seven,
  thirty,
  statement;

  String get number => switch (this) {
    seven => '07',
    thirty => '30',
    statement => '90',
  };
  StatementMatchWindow get next => values[(index + 1) % values.length];
  String get nextTooltip => switch (next) {
    seven => 'Switch to 7 days',
    thirty => 'Switch to 30 days',
    statement => 'Switch to Search All',
  };
  String get iconAsset => switch (this) {
    seven => '083-seven-days.svg',
    thirty => '067-month-clock.svg',
    statement => '084-all-statement-days.svg',
  };
  bool includes(
    DateTime candidate,
    DateTime bankDate,
    BankStatementImport source,
  ) {
    DateTime day(DateTime date) =>
        DateTime.utc(date.year, date.month, date.day);
    if (this == statement) {
      final period = source.period;
      return !day(candidate).isBefore(day(period.start)) &&
          !day(candidate).isAfter(day(period.end));
    }
    return day(candidate).difference(day(bankDate)).inDays.abs() <=
        (this == seven ? 7 : 30);
  }
}

final class StatementMatchCandidate {
  const StatementMatchCandidate({
    required this.journalId,
    required this.lineIndex,
    required this.date,
    required this.memo,
    required this.daysApart,
  });
  final EntityId journalId;
  final int lineIndex;
  final DateTime date;
  final String memo;
  final int daysApart;
  String get movementId => '${journalId.value}:$lineIndex';
}

/// A verified posted movement offered for explicit single or combined matching.
final class StatementPostedMovement {
  const StatementPostedMovement({
    required this.candidate,
    required this.amount,
  });
  final StatementMatchCandidate candidate;
  final Money amount;
}

final class StatementRowSuggestions {
  const StatementRowSuggestions({required this.row, required this.candidates});
  final BankStatementRow row;
  final List<StatementMatchCandidate> candidates;
}

/// Suggestions only. Equal amount/date does not establish transaction identity.
/// Positive CSV amounts increase bank assets or card liabilities respectively.
List<StatementRowSuggestions> suggestStatementMatches({
  required EntityId businessId,
  required Account ledgerAccount,
  required BankStatementImport statement,
  required Iterable<StoredJournalEntry> journals,
  int dateToleranceDays = 3,
  bool includeOlderMovements = false,
  StatementMatchWindow? window,
  bool unrestrictedDates = false,
}) {
  if (dateToleranceDays < 0 || dateToleranceDays > 31) {
    throw RangeError.range(dateToleranceDays, 0, 31);
  }
  if (ledgerAccount.isParent ||
      (ledgerAccount.type != AccountType.asset &&
          ledgerAccount.type != AccountType.liability)) {
    throw ArgumentError(
      'Statement matching needs a bank or card posting account.',
    );
  }
  final byAmount = <BigInt, List<StatementMatchCandidate>>{};
  final seen = <EntityId>{};
  for (final record in journals) {
    if (record.metadata.businessId != businessId ||
        !seen.add(record.entry.id)) {
      throw StateError(
        'Statement matching received mixed ownership or duplicate journals.',
      );
    }
    final entry = record.entry;
    if (entry.state != JournalEntryState.posted) continue;
    if (record.metadata.isTombstone || entry.validationErrors.isNotEmpty) {
      throw StateError('Invalid posted journal requires accounting review.');
    }
    for (var i = 0; i < entry.lines.length; i++) {
      final line = entry.lines[i];
      if (line.accountId != ledgerAccount.id) continue;
      if (line.amount.currency != statement.currency) {
        throw StateError('Statement and ledger movement currencies differ.');
      }
      var signed =
          BigInt.from(line.amount.minorUnits) *
          BigInt.from(line.isDebit ? 1 : -1);
      if (ledgerAccount.type == AccountType.liability) signed = -signed;
      byAmount
          .putIfAbsent(signed, () => [])
          .add(
            StatementMatchCandidate(
              journalId: entry.id,
              lineIndex: i,
              date: DateTime.utc(
                entry.date.year,
                entry.date.month,
                entry.date.day,
              ),
              memo: entry.memo,
              daysApart: 0,
            ),
          );
    }
  }
  return List.unmodifiable(
    statement.rows.map((row) {
      final candidates = <StatementMatchCandidate>[];
      if (!row.amount.isZero) {
        for (final candidate
            in byAmount[BigInt.from(row.amount.minorUnits)] ??
                const <StatementMatchCandidate>[]) {
          final days = candidate.date.difference(row.date).inDays.abs();
          if (unrestrictedDates ||
              (window != null
                  ? window.includes(candidate.date, row.date, statement)
                  : days <= dateToleranceDays ||
                        (includeOlderMovements &&
                            candidate.date.isBefore(row.date)))) {
            candidates.add(
              StatementMatchCandidate(
                journalId: candidate.journalId,
                lineIndex: candidate.lineIndex,
                date: candidate.date,
                memo: candidate.memo,
                daysApart: days,
              ),
            );
          }
        }
      }
      candidates.sort((a, b) {
        final byDays = a.daysApart.compareTo(b.daysApart);
        if (byDays != 0) return byDays;
        final byReference = a.memo.compareTo(b.memo);
        return byReference != 0
            ? byReference
            : a.movementId.compareTo(b.movementId);
      });
      return StatementRowSuggestions(
        row: row,
        candidates: List.unmodifiable(candidates),
      );
    }),
  );
}
