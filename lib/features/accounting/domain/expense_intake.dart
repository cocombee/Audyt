import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

import 'expense_draft.dart';
import 'expense_revision.dart';

final class ExpenseIntakeSummary {
  const ExpenseIntakeSummary({
    required this.id,
    required this.occurredOn,
    required this.createdAt,
    required this.amount,
    required this.payee,
    required this.category,
    required this.journalId,
    this.revision = 1,
    this.archivedAt,
    this.pendingRevision = 0,
  });
  final EntityId id;
  final DateTime occurredOn;
  final DateTime createdAt;
  final Money amount;
  final String payee;
  final String category;
  final EntityId? journalId;
  final int revision;
  final DateTime? archivedAt;
  final int pendingRevision;
  bool get hasPendingRevision => pendingRevision > 0;
  bool get isPosted => journalId != null;
  bool get isArchived => archivedAt != null;
}

final class ExpenseIntakeRecord {
  const ExpenseIntakeRecord({
    required this.summary,
    required this.draft,
    this.currentRevision,
  });
  final ExpenseIntakeSummary summary;
  final RecordExpenseDraft draft;
  final ExpenseRevision? currentRevision;
}

final class ExpenseIntakePageResult {
  const ExpenseIntakePageResult({
    required this.records,
    required this.total,
    required this.offset,
  });
  final List<ExpenseIntakeSummary> records;
  final int total;
  final int offset;
}
