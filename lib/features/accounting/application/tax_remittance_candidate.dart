import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import 'journal_entry_repository.dart';

/// A read-only choice; linking rechecks this exact journal and current budget.
final class TaxRemittanceCandidate {
  TaxRemittanceCandidate({
    required this.journal,
    required this.paymentAccountId,
    required this.bankAccountId,
    required Map<EntityId, Money> remaining,
  }) : remaining = Map.unmodifiable(remaining) {
    if (paymentAccountId.isEmpty ||
        this.remaining.isEmpty ||
        this.remaining.values.any((v) => !v.isPositive) ||
        this.remaining.values.map((v) => v.currency).toSet().length != 1) {
      throw StateError(
        'Eligible remittance choice needs a remaining payment amount.',
      );
    }
  }
  final StoredJournalEntry journal;
  final String paymentAccountId;
  final EntityId bankAccountId;
  final Map<EntityId, Money> remaining;
  Money get available => remaining.values.reduce((a, b) => a + b);
}
