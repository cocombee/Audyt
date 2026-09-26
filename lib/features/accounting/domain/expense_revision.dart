import '../../../core/ids/entity_id.dart';
import 'expense_draft.dart';

/// A saved current edit awaiting explicit posting review. Its source Expense
/// and journal remain intact until the linked correction is approved.
final class ExpenseRevision {
  const ExpenseRevision({
    required this.requestId,
    required this.expenseId,
    required this.sourceJournalId,
    required this.sourceExpenseRevision,
    required this.revision,
    required this.actorId,
    required this.savedAt,
    required this.before,
    required this.draft,
  });

  final EntityId requestId, expenseId, sourceJournalId, actorId;
  final int sourceExpenseRevision, revision;
  final DateTime savedAt;
  final RecordExpenseDraft before, draft;
}

/// Approves the exact saved current Expense and reviewed balanced journal.
/// The request ID also identifies the retained reversal of the prior posting.
final class ExpenseRevisionApproval {
  const ExpenseRevisionApproval({
    required this.requestId,
    required this.businessId,
    required this.expenseId,
    required this.expectedRevision,
    required this.expectedSourceJournalId,
    required this.journalId,
    required this.expectedJournalRevision,
    required this.actorId,
    required this.approvedAt,
  });
  final EntityId requestId,
      businessId,
      expenseId,
      expectedSourceJournalId,
      journalId,
      actorId;
  final int expectedRevision, expectedJournalRevision;
  final DateTime approvedAt;
}

final class ExpenseRevisionPosting {
  const ExpenseRevisionPosting({
    required this.requestId,
    required this.expenseId,
    required this.revision,
    required this.sourceJournalId,
    required this.journalId,
    required this.reversalJournalId,
    required this.actorId,
    required this.approvedAt,
  });
  final EntityId requestId,
      expenseId,
      sourceJournalId,
      journalId,
      reversalJournalId,
      actorId;
  final int revision;
  final DateTime approvedAt;
}

/// Claim recognition review explicitly owns the cost account for every current
/// Expense row. It never derives an account from a category's displayed text.
final class ClaimExpenseRevisionApproval {
  ClaimExpenseRevisionApproval({
    required this.approval,
    required Map<String, EntityId> lineAccounts,
  }) : lineAccounts = Map.unmodifiable(lineAccounts);
  final ExpenseRevisionApproval approval;
  final Map<String, EntityId> lineAccounts;
}
