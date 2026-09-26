import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

import 'ledger_fixture.dart';

EntityId id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
StoredJournalEntry draft({
  String currency = 'MYR',
  int credit = 1200,
  int revision = 1,
}) => StoredJournalEntry(
  entry: JournalEntry.draft(
    id: id(1),
    date: DateTime.utc(2026, 9, 13),
    memo: 'Reviewed Expense',
    lines: [
      JournalLine.debit(
        accountId: id(2),
        amount: Money.fromMinor(1200, currency),
      ),
      JournalLine.credit(
        accountId: id(3),
        amount: Money.fromMinor(credit, currency),
      ),
    ],
  ),
  metadata: RecordMetadata.restore(
    recordId: id(1),
    businessId: id(4),
    originDeviceId: id(5),
    createdAt: DateTime.utc(2026, 9, 13),
    updatedAt: DateTime.utc(2026, 9, 13, revision - 1),
    revision: revision,
    deletedAt: null,
  ),
);
JournalApproval approval({
  int request = 6,
  int revision = 1,
  int business = 4,
}) => JournalApproval(
  requestId: id(request),
  businessId: id(business),
  journalId: id(1),
  expectedRevision: revision,
  actorId: id(5),
  approvedAt: DateTime.utc(2026, 9, 13, 12),
);
void main() {
  test(
    'approval is durable and retry returns same journal with one audit event',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-approval-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var db = LocalAccountingDatabase.open(path);
      await seedLedger(db, draft());
      await db.save(draft());
      final second = LocalAccountingDatabase.open(path);
      final posted = await db.approve(approval());
      final retry = await second.approve(approval());
      expect(retry.metadata.revision, posted.metadata.revision);
      await expectLater(second.approve(approval(request: 7)), throwsStateError);
      await expectLater(
        second.approve(approval(revision: 2)),
        throwsStateError,
      );
      second.close();
      db.close();
      db = LocalAccountingDatabase.open(path);
      addTearDown(db.close);
      expect(
        (await db.approve(approval())).entry.state,
        JournalEntryState.posted,
      );
      expect(await db.auditEvents(id(4)), hasLength(1));
    },
  );
  test(
    'posting cannot bypass persisted review and rejects stale approval',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await seedLedger(db, draft());
      await expectLater(
        db.save(
          StoredJournalEntry(
            entry: draft().entry.post(),
            metadata: draft().metadata,
          ),
        ),
        throwsStateError,
      );
      await db.save(draft());
      await db.save(draft(revision: 2));
      await expectLater(db.approve(approval()), throwsStateError);
      expect((await db.getById(id(1)))!.entry.state, JournalEntryState.draft);
      expect(await db.auditEvents(id(4)), isEmpty);
      expect((await db.approve(approval(revision: 2))).metadata.revision, 3);
    },
  );
  for (final invalid in [
    'missing',
    'foreign',
    'locked',
    'archived',
    'parent',
  ]) {
    test(
      'rejects $invalid posting account without committing approval',
      () async {
        final db = LocalAccountingDatabase.inMemory();
        addTearDown(db.close);
        await db.configureLedger(businessId: id(4), currencyCode: 'MYR');
        if (invalid != 'missing') {
          await db.saveAccount(
            StoredAccount(
              account: Account.create(
                id: id(2),
                code: '100',
                name: 'Cash',
                type: AccountType.asset,
                isParent: invalid == 'parent',
                status: invalid == 'locked'
                    ? AccountStatus.locked
                    : invalid == 'archived'
                    ? AccountStatus.archived
                    : AccountStatus.active,
              ),
              metadata: RecordMetadata.initial(
                recordId: id(2),
                businessId: id(invalid == 'foreign' ? 8 : 4),
                originDeviceId: id(5),
                createdAt: DateTime.utc(2026, 9, 13),
              ),
            ),
          );
        }
        await db.save(draft());
        await expectLater(db.approve(approval()), throwsStateError);
        expect((await db.getById(id(1)))!.metadata.revision, 1);
        expect(await db.auditEvents(id(4)), isEmpty);
      },
    );
  }
  test('closed-through date is inclusive and rejected approval leaves only closing audit', () async {
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    await seedLedger(db, draft());
    await db.save(draft());
    await db.closeThrough(
      businessId: id(4),
      date: DateTime.utc(2026, 9, 13),
      actorId: id(5),
      changedAt: DateTime.utc(2026, 9, 14),
      reason: 'Period reconciled',
    );
    await expectLater(db.approve(approval()), throwsStateError);
    expect((await db.getById(id(1)))!.entry.state, JournalEntryState.draft);
    final events = await db.auditEvents(id(4));
    expect(events, hasLength(1));
    expect(events.single['kind'], 'period_closed');
    await expectLater(
      db.closeThrough(
        businessId: id(4),
        date: DateTime.utc(2026, 9, 12),
        actorId: id(5),
        changedAt: DateTime.utc(2026, 9, 15),
        reason: 'Earlier',
      ),
      throwsStateError,
    );
  });
  test(
    'balanced foreign amounts are not relabelled into ledger currency',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await seedLedger(db, draft());
      await db.save(draft(currency: 'USD'));
      await expectLater(db.approve(approval()), throwsStateError);
      await expectLater(
        db.configureLedger(businessId: id(4), currencyCode: 'USD'),
        throwsStateError,
      );
      expect(await db.auditEvents(id(4)), isEmpty);
    },
  );
  test('unbalanced and cross-business approvals fail atomically', () async {
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    await seedLedger(db, draft());
    await db.save(draft(credit: 1199));
    await expectLater(db.approve(approval(business: 8)), throwsStateError);
    await expectLater(
      db.approve(approval()),
      throwsA(isA<JournalValidationException>()),
    );
    expect((await db.getById(id(1)))!.metadata.revision, 1);
    expect(await db.auditEvents(id(4)), isEmpty);
  });

  test('audit insert failure rolls back journal and approval receipt, allowing retry', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-rollback-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    final db = LocalAccountingDatabase.open(path);
    addTearDown(db.close);
    await seedLedger(db, draft());
    await db.save(draft());
    final raw = sqlite3.open(path);
    addTearDown(raw.dispose);
    raw.execute(
      "CREATE TRIGGER simulated_failure BEFORE INSERT ON ledger_audit BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END",
    );
    await expectLater(db.approve(approval()), throwsA(isA<SqliteException>()));
    expect((await db.getById(id(1)))!.entry.state, JournalEntryState.draft);
    expect((await db.getById(id(1)))!.metadata.revision, 1);
    expect(raw.select('SELECT * FROM journal_approvals'), isEmpty);
    raw.execute('DROP TRIGGER simulated_failure');
    await db.approve(approval());
    expect(await db.auditEvents(id(4)), hasLength(1));
    expect(
      () => raw.execute("UPDATE ledger_audit SET kind='changed'"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute('DELETE FROM ledger_audit'),
      throwsA(isA<SqliteException>()),
    );
  });
  test(
    'duplicate or altered reversals cannot create an extra offset',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await seedLedger(db, draft());
      await db.save(draft());
      final original = await db.approve(approval());
      Future<void> reverse(int n, {bool alter = false}) async {
        final entry = original.entry.reversal(
          id: id(n),
          date: DateTime.utc(2026, 9, 14),
          memo: 'Reverse Error',
        );
        final candidate = alter
            ? JournalEntry.restore(
                id: entry.id,
                date: entry.date,
                memo: entry.memo,
                lines: draft().entry.lines,
                state: JournalEntryState.draft,
                reversesId: original.entry.id,
              )
            : entry;
        await db.save(
          StoredJournalEntry(
            entry: candidate,
            metadata: RecordMetadata.initial(
              recordId: id(n),
              businessId: id(4),
              originDeviceId: id(5),
              createdAt: DateTime.utc(2026, 9, 14),
            ),
          ),
        );
        await db.approve(
          JournalApproval(
            requestId: id(n + 100),
            businessId: id(4),
            journalId: id(n),
            expectedRevision: 1,
            actorId: id(5),
            approvedAt: DateTime.utc(2026, 9, 14, 1),
          ),
        );
      }

      await expectLater(reverse(10, alter: true), throwsStateError);
      await reverse(11);
      await expectLater(reverse(12), throwsStateError);
      expect(await db.auditEvents(id(4)), hasLength(2));
    },
  );
  test('large totals cannot wrap and falsely pass balance validation', () {
    final amount = Money.fromMinor(1 << 62, 'MYR');
    final entry = JournalEntry.draft(
      id: id(1),
      date: DateTime.utc(2026, 9, 13),
      memo: 'Overflow Check',
      lines: [
        for (var n = 0; n < 4; n++)
          JournalLine.debit(accountId: id(2), amount: amount),
        for (var n = 0; n < 8; n++)
          JournalLine.credit(accountId: id(3), amount: amount),
      ],
    );
    expect(
      entry.validationErrors,
      contains('Total debits must equal total credits.'),
    );
    expect(entry.post, throwsA(isA<JournalValidationException>()));
  });
}
