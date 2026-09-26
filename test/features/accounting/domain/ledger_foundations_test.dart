import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates an auditable draft reversal without mutating the posted entry',
    () {
      final posted = JournalEntry.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a11'),
        date: DateTime.utc(2026, 8, 30),
        memo: 'Opening cash',
        lines: [
          JournalLine.debit(
            accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a12'),
            amount: Money.fromMinor(1250, 'USD'),
          ),
          JournalLine.credit(
            accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a13'),
            amount: Money.fromMinor(1250, 'USD'),
          ),
        ],
      ).post();

      final reversal = posted.reversal(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a14'),
        date: DateTime.utc(2026, 8, 31),
        memo: 'Reverse opening cash',
      );

      expect(reversal.state, JournalEntryState.draft);
      expect(reversal.reversesId, posted.id);
      expect(reversal.lines.first.isCredit, isTrue);
      expect(reversal.lines.last.isDebit, isTrue);
      expect(reversal.validationErrors, isEmpty);
      expect(posted.state, JournalEntryState.posted);
      expect(posted.lines.first.isDebit, isTrue);
    },
  );

  test('posts a balanced journal using integer minor-unit money', () {
    final journal = JournalEntry.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a01'),
      date: DateTime.utc(2026, 8, 30),
      memo: 'Opening cash',
      lines: [
        JournalLine.debit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a02'),
          amount: Money.fromMinor(1250, 'USD'),
        ),
        JournalLine.credit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a03'),
          amount: Money.fromMinor(1250, 'USD'),
        ),
      ],
    );

    expect(journal.validationErrors, isEmpty);
    expect(journal.post().state, JournalEntryState.posted);
  });

  test('reports a deterministic error for unbalanced totals', () {
    final journal = JournalEntry.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a31'),
      date: DateTime.utc(2026, 8, 30),
      memo: 'Unbalanced entry',
      lines: [
        JournalLine.debit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a32'),
          amount: Money.fromMinor(1000, 'USD'),
        ),
        JournalLine.credit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a33'),
          amount: Money.fromMinor(999, 'USD'),
        ),
      ],
    );

    expect(journal.validationErrors, [
      'Total debits must equal total credits.',
    ]);
    expect(() => journal.post(), throwsA(isA<JournalValidationException>()));
  });

  test('rejects zero or negative lines and mixed currencies', () {
    final journal = JournalEntry.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a41'),
      date: DateTime.utc(2026, 8, 30),
      memo: 'Invalid entry',
      lines: [
        JournalLine.debit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a42'),
          amount: Money.fromMinor(0, 'USD'),
        ),
        JournalLine.credit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a43'),
          amount: Money.fromMinor(-1, 'EUR'),
        ),
      ],
    );

    expect(
      journal.validationErrors,
      containsAll([
        'All journal lines must use one currency.',
        'Journal line amounts must be positive.',
      ]),
    );
    expect(() => journal.post(), throwsA(isA<JournalValidationException>()));
  });

  test('does not reverse a draft entry', () {
    final draft = JournalEntry.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a51'),
      date: DateTime.utc(2026, 8, 30),
      memo: 'Draft entry',
      lines: [
        JournalLine.debit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a52'),
          amount: Money.fromMinor(100, 'USD'),
        ),
        JournalLine.credit(
          accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a53'),
          amount: Money.fromMinor(100, 'USD'),
        ),
      ],
    );

    expect(
      () => draft.reversal(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a54'),
        date: DateTime.utc(2026, 8, 31),
        memo: 'Invalid reversal',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
