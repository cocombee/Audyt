import 'ledger_fixture.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'round-trips a posted journal and revision metadata through SQLite',
    () async {
      final database = LocalAccountingDatabase.inMemory();
      addTearDown(database.close);
      final entryId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a81');
      final record = StoredJournalEntry(
        entry: JournalEntry.draft(
          id: entryId,
          date: DateTime.utc(2026, 8, 30),
          memo: 'Opening cash',
          lines: [
            JournalLine.debit(
              accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a82'),
              amount: Money.fromMinor(1250, 'USD'),
            ),
            JournalLine.credit(
              accountId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a83'),
              amount: Money.fromMinor(1250, 'USD'),
            ),
          ],
        ),
        metadata: RecordMetadata.initial(
          recordId: entryId,
          businessId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a84'),
          originDeviceId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a85',
          ),
          createdAt: DateTime.utc(2026, 8, 30, 1),
        ),
      );

      await approveFixture(database, record);
      final loaded = await database.getJournal(entryId);

      expect(loaded?.entry.state, JournalEntryState.posted);
      expect(loaded?.entry.lines, hasLength(2));
      expect(loaded?.entry.lines.first.amount, Money.fromMinor(1250, 'USD'));
      expect(loaded?.metadata.revision, 2);
      expect(loaded?.metadata.businessId, record.metadata.businessId);
    },
  );
}
