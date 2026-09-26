import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'archive_upgrade_test.dart' show body, envelope;

JournalEntry replacement(
  StoredJournalEntry old,
  Fixture f, {
  int amount = 12000,
  String currency = 'MYR',
  EntityId? account,
}) => JournalEntry.draft(
  id: old.entry.id,
  date: old.entry.date,
  memo: 'Fictional revised memo',
  lines: [
    JournalLine.credit(
      accountId: f.bank,
      amount: Money.fromMinor(amount, currency),
    ),
    JournalLine.debit(
      accountId: account ?? f.expense,
      amount: Money.fromMinor(amount, currency),
    ),
  ],
);
StoredJournalEntry save(
  Fixture f,
  StoredJournalEntry old, {
  EntityId? request,
  JournalEntry? entry,
  EntityId? actor,
}) => f.w.database.reviseManualJournalDraft(
  expected: old,
  replacement: entry ?? replacement(old, f),
  requestId: request ?? EntityId.random(),
  actorId: actor ?? f.w.identity.ownerId,
  savedAt: old.metadata.updatedAt.add(const Duration(seconds: 1)),
);
String archive(Fixture f) =>
    f.w.database.exportDataArchive(f.business, DateTime.utc(2027));

void main() {
  test('same ID retains every saved draft and survives archive restore and posting', () async {
    final f = Fixture();
    await f.open();
    final id = await f.post(9, 14, -10000, approve: false);
    final old = (await f.w.database.getById(id))!;
    final changed = save(f, old);
    final next = save(
      f,
      changed,
      entry: replacement(changed, f, amount: 15000),
    );
    expect(await f.w.journals(), hasLength(1));
    final history = f.w.database.manualJournalDraftHistory(f.business, id);
    expect(history, hasLength(2));
    expect(history.first.before.entry.lines.first.amount.minorUnits, 10000);
    expect(history.first.after.entry.lines.first.amount.minorUnits, 12000);
    expect(history.last.after.entry.lines.first.amount.minorUnits, 15000);
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive(f));
    expect(restored.manualJournalDraftHistory(f.business, id), hasLength(2));
    expect(
      (await restored.getById(id))!.metadata.revision,
      next.metadata.revision,
    );
    await f.w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: f.business,
        journalId: id,
        expectedRevision: next.metadata.revision,
        actorId: f.w.identity.ownerId,
        approvedAt: next.metadata.updatedAt.add(const Duration(seconds: 1)),
      ),
    );
    expect(
      (await f.w.database.getById(id))!.entry.state,
      JournalEntryState.posted,
    );
    final posted = LocalAccountingDatabase.inMemory();
    addTearDown(posted.close);
    posted.restoreDataArchive(archive(f));
    expect(
      posted.manualJournalDraftHistory(f.business, id).first.before.entry.memo,
      old.entry.memo,
    );
    expect(
      (await posted.getById(id))!.entry.lines.first.amount.minorUnits,
      15000,
    );
  });
  test(
    'retry retains exact command identity and cannot create another revision',
    () async {
      final f = Fixture();
      await f.open();
      final id = await f.post(9, 14, -10000, approve: false);
      final old = (await f.w.database.getById(id))!;
      final request = EntityId.random();
      final changed = save(f, old, request: request);
      final expectedArchive = archive(f);
      expect(
        save(f, old, request: request).metadata.revision,
        changed.metadata.revision,
      );
      expect(archive(f), expectedArchive);
      expect(
        () => save(
          f,
          old,
          request: request,
          entry: replacement(old, f, amount: 16000),
        ),
        throwsStateError,
      );
      expect(archive(f), expectedArchive);
    },
  );
  test('stale revision, wrong owner, wrong company account and currency are atomic', () async {
    final f = Fixture();
    await f.open();
    final id = await f.post(9, 14, -10000, approve: false);
    final old = (await f.w.database.getById(id))!;
    final changed = save(f, old);
    final expectedArchive = archive(f);
    for (final action in [
      () => save(f, old),
      () => save(f, changed, actor: EntityId.random()),
      () => save(
        f,
        changed,
        entry: replacement(changed, f, account: EntityId.random()),
      ),
      () => save(f, changed, entry: replacement(changed, f, currency: 'USD')),
      () => save(f, changed, entry: replacement(changed, f, amount: 0)),
    ]) {
      expect(
        action,
        throwsA(anyOf(isA<StateError>(), isA<JournalValidationException>())),
      );
      expect(archive(f), expectedArchive);
    }
    await expectLater(
      f.w.database.save(
        StoredJournalEntry(
          entry: replacement(changed, f),
          metadata: changed.metadata.nextRevision(
            updatedAt: changed.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        ),
      ),
      throwsStateError,
    );
    expect(archive(f), expectedArchive);
  });
  test('posted, reversal and closing journals cannot enter a generic draft command', () async {
    final f = Fixture();
    await f.open();
    final id = await f.post(9, 14, -10000);
    final old = (await f.w.database.getById(id))!;
    expect(f.w.database.isManualJournalDraft(f.business, id), false);
    final expectedArchive = archive(f);
    expect(() => save(f, old), throwsStateError);
    expect(archive(f), expectedArchive);
    final closing = JournalEntry.draft(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 14),
      memo: 'Fictional closing',
      lines: old.entry.lines,
      closingEquityAccountId: f.bank,
    );
    final raw = StoredJournalEntry(entry: closing, metadata: old.metadata);
    expect(
      () => f.w.database.reviseManualJournalDraft(
        expected: old,
        replacement: closing,
        requestId: EntityId.random(),
        actorId: f.w.identity.ownerId,
        savedAt: old.metadata.updatedAt.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    expect(raw.entry.isClosing, true);
    expect(archive(f), expectedArchive);
  });
  test('inactive saved selections remain facts but changed inactive amounts reject', () async {
    final f = Fixture();
    await f.open();
    final id = await f.post(9, 14, -10000, approve: false);
    final old = (await f.w.database.getById(id))!;
    final accounts = await f.w.accounts();
    final expense = accounts.singleWhere((r) => r.account.id == f.expense);
    await f.w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: expense.account.id,
          code: expense.account.code,
          name: expense.account.name,
          type: expense.account.type,
          status: AccountStatus.locked,
        ),
        metadata: expense.metadata.nextRevision(
          updatedAt: expense.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
    final unchanged = JournalEntry.draft(
      id: id,
      date: old.entry.date,
      memo: 'Fictional memo only',
      lines: old.entry.lines,
    );
    final saved = save(f, old, entry: unchanged);
    expect(saved.entry.lines[1].accountId, f.expense);
    final before = archive(f);
    expect(() => save(f, saved), throwsStateError);
    final duplicate = JournalEntry.draft(
      id: id,
      date: saved.entry.date,
      memo: saved.entry.memo,
      lines: [
        JournalLine.credit(
          accountId: f.bank,
          amount: Money.fromMinor(20000, 'MYR'),
        ),
        JournalLine.debit(
          accountId: f.expense,
          amount: Money.fromMinor(10000, 'MYR'),
        ),
        JournalLine.debit(
          accountId: f.expense,
          amount: Money.fromMinor(10000, 'MYR'),
        ),
      ],
    );
    expect(() => save(f, saved, entry: duplicate), throwsStateError);
    expect(archive(f), before);
  });
  for (final corruption in ['owner', 'revision', 'current']) {
    test(
      'restore rejects tampered Journal draft $corruption without partial import',
      () async {
        final f = Fixture();
        await f.open();
        final id = await f.post(9, 14, -10000, approve: false);
        save(f, (await f.w.database.getById(id))!);
        final data = body(archive(f));
        final tables = data['tables'] as Map;
        final audit = tables['ledger_audit'] as Map;
        final columns = audit['columns'] as List;
        final row = (audit['rows'] as List).single as List;
        if (corruption == 'owner') {
          row[columns.indexOf('actor_id')] = EntityId.random().value;
        }
        if (corruption == 'revision') {
          final detail =
              jsonDecode(row[columns.indexOf('detail')] as String) as Map;
          detail['after']['revision'] = 50;
          row[columns.indexOf('detail')] = jsonEncode(detail);
        }
        if (corruption == 'current') {
          final journals = tables['journal_entries'] as Map;
          final jc = journals['columns'] as List;
          ((journals['rows'] as List).single as List)[jc.indexOf('memo')] =
              'Fictional corrupted current memo';
        }
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        expect(
          () => restored.restoreDataArchive(envelope(data)),
          throwsStateError,
        );
        expect(await restored.getById(id), isNull);
      },
    );
  }
}
