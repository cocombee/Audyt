import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

final class LedgerService {
  const LedgerService(this.repository);
  final JournalEntryRepository repository;

  Future<void> saveDraft(StoredJournalEntry record) {
    if (record.entry.state != JournalEntryState.draft) {
      throw StateError('Save a draft before requesting approval.');
    }
    return repository.save(record);
  }

  Future<StoredJournalEntry> approve(JournalApproval command) =>
      repository.approve(command);
}
