import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';

import '../data/ledger_fixture.dart';

import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/application/ledger_service.dart';
import 'package:audyt/core/money/money.dart';

void main() {
  test(
    'posts through the repository with metadata and blocks invalid journals',
    () async {
      final repository = LocalAccountingDatabase.inMemory();
      addTearDown(repository.close);
      final service = LedgerService(repository);
      final businessId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a71');
      final deviceId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a72');
      final entryId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a73');

      final draft = StoredJournalEntry(
        entry: JournalEntry.draft(
          id: entryId,
          date: DateTime.utc(2026, 8, 30),
          memo: 'Opening cash',
          lines: [
            JournalLine.debit(
              accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a74'),
              amount: Money.fromMinor(100, 'USD'),
            ),
            JournalLine.credit(
              accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a75'),
              amount: Money.fromMinor(100, 'USD'),
            ),
          ],
        ),
        metadata: RecordMetadata.initial(
          recordId: entryId,
          businessId: businessId,
          originDeviceId: deviceId,
          createdAt: DateTime.utc(2026, 8, 30, 1),
        ),
      );

      await seedLedger(repository, draft);
      await service.saveDraft(draft);
      final record = await service.approve(
        JournalApproval(
          requestId: entryId,
          businessId: businessId,
          journalId: entryId,
          expectedRevision: 1,
          actorId: deviceId,
          approvedAt: DateTime.utc(2026, 8, 30, 2),
        ),
      );
      expect(record.entry.state, JournalEntryState.posted);
      expect(record.metadata.revision, 2);
      expect(await repository.auditEvents(businessId), hasLength(1));
      expect(
        (await repository.getById(entryId))!.entry.state,
        JournalEntryState.posted,
      );
    },
  );
}
