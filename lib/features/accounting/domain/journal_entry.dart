import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

enum JournalEntryState { draft, posted, voided }

enum JournalLineKind { debit, credit }

final class JournalLine {
  const JournalLine._({
    required this.accountId,
    required this.amount,
    required this.kind,
  });

  factory JournalLine.debit({
    required EntityId accountId,
    required Money amount,
  }) {
    return JournalLine._(
      accountId: accountId,
      amount: amount,
      kind: JournalLineKind.debit,
    );
  }

  factory JournalLine.credit({
    required EntityId accountId,
    required Money amount,
  }) {
    return JournalLine._(
      accountId: accountId,
      amount: amount,
      kind: JournalLineKind.credit,
    );
  }

  final EntityId accountId;
  final Money amount;
  final JournalLineKind kind;

  bool get isDebit => kind == JournalLineKind.debit;
  bool get isCredit => kind == JournalLineKind.credit;
}

final class JournalEntry {
  JournalEntry._({
    required this.id,
    required this.date,
    required this.memo,
    required List<JournalLine> lines,
    required this.state,
    this.reversesId,
    this.closingEquityAccountId,
  }) : lines = List.unmodifiable(lines);

  factory JournalEntry.draft({
    required EntityId id,
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
    EntityId? closingEquityAccountId,
  }) {
    return JournalEntry._(
      id: id,
      date: date,
      memo: memo,
      lines: lines,
      state: JournalEntryState.draft,
      closingEquityAccountId: closingEquityAccountId,
    );
  }

  factory JournalEntry.restore({
    required EntityId id,
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
    required JournalEntryState state,
    EntityId? reversesId,
    EntityId? closingEquityAccountId,
  }) {
    return JournalEntry._(
      id: id,
      date: date.toUtc(),
      memo: memo,
      lines: lines,
      state: state,
      reversesId: reversesId,
      closingEquityAccountId: closingEquityAccountId,
    );
  }

  final EntityId id;
  final DateTime date;
  final String memo;
  final List<JournalLine> lines;
  final JournalEntryState state;
  final EntityId? reversesId;
  final EntityId? closingEquityAccountId;
  bool get isClosing => closingEquityAccountId != null;

  JournalEntry reversal({
    required EntityId id,
    required DateTime date,
    required String memo,
  }) {
    if (state != JournalEntryState.posted) {
      throw StateError('Only posted journal entries can be reversed.');
    }
    return JournalEntry._(
      id: id,
      date: date,
      memo: memo,
      lines: lines
          .map(
            (line) => line.isDebit
                ? JournalLine.credit(
                    accountId: line.accountId,
                    amount: line.amount,
                  )
                : JournalLine.debit(
                    accountId: line.accountId,
                    amount: line.amount,
                  ),
          )
          .toList(),
      state: JournalEntryState.draft,
      reversesId: this.id,
      closingEquityAccountId: closingEquityAccountId,
    );
  }

  List<String> get validationErrors {
    final errors = <String>[];
    if (lines.length < 2) {
      errors.add('A journal entry requires at least two lines.');
    }
    if (memo.trim().isEmpty) {
      errors.add('A journal entry memo is required.');
    }

    final currencies = lines.map((line) => line.amount.currency).toSet();
    if (currencies.length > 1) {
      errors.add('All journal lines must use one currency.');
    }

    for (final line in lines) {
      if (!line.amount.isPositive) {
        errors.add('Journal line amounts must be positive.');
        break;
      }
    }

    final debitMinorUnits = _totalMinorUnits(JournalLineKind.debit);
    final creditMinorUnits = _totalMinorUnits(JournalLineKind.credit);
    if (debitMinorUnits != creditMinorUnits) {
      errors.add('Total debits must equal total credits.');
    }
    return List.unmodifiable(errors);
  }

  JournalEntry post() {
    if (state != JournalEntryState.draft) {
      throw StateError('Only draft journal entries can be posted.');
    }
    final errors = validationErrors;
    if (errors.isNotEmpty) {
      throw JournalValidationException(errors);
    }
    return JournalEntry._(
      id: id,
      date: date,
      memo: memo,
      lines: lines,
      state: JournalEntryState.posted,
      reversesId: reversesId,
      closingEquityAccountId: closingEquityAccountId,
    );
  }

  BigInt _totalMinorUnits(JournalLineKind kind) {
    return lines
        .where((line) => line.kind == kind)
        .fold(
          BigInt.zero,
          (total, line) => total + BigInt.from(line.amount.minorUnits),
        );
  }
}

final class JournalValidationException implements Exception {
  const JournalValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'JournalValidationException: ${errors.join(' ')}';
}
