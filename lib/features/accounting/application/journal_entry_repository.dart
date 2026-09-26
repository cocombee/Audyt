import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

final class StoredJournalEntry {
  const StoredJournalEntry({required this.entry, required this.metadata});

  final JournalEntry entry;
  final RecordMetadata metadata;
}

/// Immutable current revision of a posted manual Journal; the root identity
/// remains stable while original postings and reviewed drafts stay retained.
final class StoredManualJournalRevision {
  const StoredManualJournalRevision({
    required this.rootId,
    required this.revision,
    required this.source,
    required this.draft,
  });
  final EntityId rootId;
  final int revision;
  final StoredJournalEntry source;
  final StoredJournalEntry draft;
}

/// Complete records from one coherent, bounded read of a company's journals.
final class StoredJournalPage {
  StoredJournalPage({
    required Iterable<StoredJournalEntry> records,
    required this.total,
    required this.offset,
    required this.limit,
  }) : records = List.unmodifiable(records);

  final List<StoredJournalEntry> records;
  final int total;
  final int offset;
  final int limit;
}

abstract interface class JournalEntryRepository {
  Future<StoredJournalEntry?> getById(EntityId id);

  /// Saves drafts only. Posting must approve the exact persisted revision.
  Future<void> save(StoredJournalEntry record);

  Future<StoredJournalEntry> approve(JournalApproval command);
}

/// A retry must reuse every field, including the request ID and approval time.
final class JournalApproval {
  const JournalApproval({
    required this.requestId,
    required this.businessId,
    required this.journalId,
    required this.expectedRevision,
    required this.actorId,
    required this.approvedAt,
    this.expenseIntakeId,
  });
  final EntityId requestId;
  final EntityId businessId;
  final EntityId journalId;
  final int expectedRevision;
  final EntityId actorId;
  final DateTime approvedAt;
  final EntityId? expenseIntakeId;
}
