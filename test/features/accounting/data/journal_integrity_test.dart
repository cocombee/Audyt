import 'ledger_fixture.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

EntityId id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
StoredJournalEntry draft() => StoredJournalEntry(
  entry: JournalEntry.draft(
    id: id(1),
    date: DateTime.utc(2026, 9, 13),
    memo: 'Expense',
    lines: [
      JournalLine.debit(accountId: id(2), amount: Money.fromMinor(1200, 'MYR')),
      JournalLine.credit(
        accountId: id(3),
        amount: Money.fromMinor(1200, 'MYR'),
      ),
    ],
  ),
  metadata: RecordMetadata.initial(
    recordId: id(1),
    businessId: id(4),
    originDeviceId: id(5),
    createdAt: DateTime.utc(2026, 9, 13),
  ),
);
void main() {
  test('posted journal cannot be overwritten or tombstoned', () async {
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    final original = draft();
    final posted = await approveFixture(db, original);
    await expectLater(db.save(original), throwsStateError);
    await expectLater(
      db.save(
        StoredJournalEntry(
          entry: posted.entry,
          metadata: posted.metadata.delete(
            deletedAt: DateTime.utc(2026, 9, 14),
          ),
        ),
      ),
      throwsStateError,
    );
    expect((await db.getById(id(1)))!.entry.state, JournalEntryState.posted);
  });
  test(
    'draft update requires next revision and rejects stale writer',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      final original = draft();
      await db.save(original);
      final next = StoredJournalEntry(
        entry: original.entry,
        metadata: original.metadata.nextRevision(
          updatedAt: DateTime.utc(2026, 9, 14),
        ),
      );
      await db.save(next);
      await expectLater(db.save(next), throwsStateError);
      expect((await db.getById(id(1)))!.metadata.revision, 2);
    },
  );
  test(
    'reversal preserves original linkage after posting and restart',
    () async {
      final directory = Directory.systemTemp.createTempSync('audyt-journal-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/ledger.sqlite';
      var db = LocalAccountingDatabase.open(path);
      final original = draft();
      final posted = (await approveFixture(db, original)).entry;
      final reversal = posted.reversal(
        id: id(6),
        date: DateTime.utc(2026, 9, 14),
        memo: 'Reverse duplicate',
      );
      await approveFixture(
        db,
        StoredJournalEntry(
          entry: reversal,
          metadata: RecordMetadata.initial(
            recordId: id(6),
            businessId: id(4),
            originDeviceId: id(5),
            createdAt: DateTime.utc(2026, 9, 14),
          ),
        ),
      );
      db.close();
      db = LocalAccountingDatabase.open(path);
      addTearDown(db.close);
      final loaded = (await db.getById(id(6)))!.entry;
      expect(loaded.reversesId, posted.id);
      expect(loaded.lines.first.isCredit, isTrue);
      expect(loaded.validationErrors, isEmpty);
    },
  );
}
