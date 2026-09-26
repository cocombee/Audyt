import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'account_reconciliation_persistence_test.dart' as period;
import 'journal_editability_test.dart' show importPayment, reopen;
import 'archive_upgrade_test.dart' show body, envelope;
import 'expense_revision_test.dart' as expense;

import 'package:audyt/core/storage/record_metadata.dart';

String archive(Fixture f) =>
    f.w.database.exportDataArchive(f.business, DateTime.utc(2027));
Future<StoredManualJournalRevision> save(
  Fixture f,
  EntityId root, {
  int amount = 12000,
  EntityId? request,
  EntityId? actor,
  int? expectedRevision,
}) async {
  final database = f.w.database;
  final source = (await database.getById(
    database.manualJournalCurrentPostingId(f.business, root),
  ))!;
  final prior = database.manualJournalCurrentRevision(f.business, root);
  final id = request ?? EntityId.random();
  final previousSavedAt = prior?.draft.metadata.updatedAt;
  final latestAt =
      previousSavedAt != null &&
          previousSavedAt.isAfter(source.metadata.updatedAt)
      ? previousSavedAt
      : source.metadata.updatedAt;
  final at = latestAt.add(const Duration(seconds: 1));
  return database.saveManualJournalCurrentRevision(
    rootId: root,
    expectedSource: source,
    expectedCurrentRevision: expectedRevision ?? prior?.revision ?? 0,
    replacement: JournalEntry.draft(
      id: id,
      date: source.entry.date,
      memo: 'Fictional manual correction $amount',
      lines: [
        JournalLine.credit(
          accountId: f.bank,
          amount: Money.fromMinor(amount, 'MYR'),
        ),
        JournalLine.debit(
          accountId: f.expense,
          amount: Money.fromMinor(amount, 'MYR'),
        ),
      ],
    ),
    requestId: id,
    actorId: actor ?? f.w.identity.ownerId,
    deviceId: f.w.identity.deviceId,
    savedAt: at,
  );
}

JournalApproval approval(Fixture f, StoredManualJournalRevision revision) =>
    JournalApproval(
      requestId: EntityId.random(),
      businessId: f.business,
      journalId: revision.draft.entry.id,
      expectedRevision: 1,
      actorId: f.w.identity.ownerId,
      approvedAt: revision.draft.metadata.updatedAt.add(
        const Duration(seconds: 1),
      ),
    );

void main() {
  test('actual current correction retains root and originals, reports, retry, restart and restore', () async {
    final f = Fixture();
    await f.open();
    final root = await f.post(9, 14, -10000);
    final original = (await f.w.database.getById(root))!;
    final first = await save(f, root);
    final second = await save(f, root, amount: 15000);
    final before = archive(f);
    expect(
      () =>
          f.w.database.approveManualJournalCurrentRevision(approval(f, first)),
      throwsStateError,
    );
    expect(archive(f), before);
    final command = approval(f, second);
    expect(
      f.w.database.approveManualJournalCurrentRevision(command).entry.state,
      JournalEntryState.posted,
    );
    final once = archive(f);
    f.w.database.approveManualJournalCurrentRevision(command);
    expect(archive(f), once);
    expect(
      f.w.database.manualJournalCurrentPostingId(f.business, root),
      second.draft.entry.id,
    );
    final report = await f.w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2027),
    );
    expect(
      report.rows.singleWhere((row) => row.account.id == f.bank).endingNetDebit,
      BigInt.from(-15000),
    );
    final retained = (await f.w.database.getById(root))!;
    expect(retained.entry.memo, original.entry.memo);
    expect(retained.metadata.revision, original.metadata.revision);
    expect(
      retained.entry.lines.map((l) => (l.accountId, l.kind, l.amount)),
      original.entry.lines.map((l) => (l.accountId, l.kind, l.amount)),
    );
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    expect(f.w.database.isCurrentManualJournalRoot(f.business, root), true);
    final third = await save(f, root, amount: 18000);
    f.w.database.approveManualJournalCurrentRevision(approval(f, third));
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive(f));
    expect(
      restored.manualJournalCurrentRevision(f.business, root)!.revision,
      3,
    );
    expect(
      restored.manualJournalCurrentPostingId(f.business, root),
      third.draft.entry.id,
    );
    expect(restored.isCurrentManualJournalRoot(f.business, root), true);
  });
  test('saved revision cannot bypass raw draft save or generic approval; stale and foreign actor reject atomically', () async {
    final f = Fixture();
    await f.open();
    final root = await f.post(9, 14, -10000);
    final revision = await save(f, root);
    final before = archive(f);
    await expectLater(
      f.w.database.approve(approval(f, revision)),
      throwsStateError,
    );
    await expectLater(
      f.w.database.save(
        StoredJournalEntry(
          entry: revision.draft.entry,
          metadata: revision.draft.metadata.nextRevision(
            updatedAt: revision.draft.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      save(f, root, actor: EntityId.random()),
      throwsStateError,
    );
    await expectLater(save(f, root, expectedRevision: 0), throwsStateError);
    expect(archive(f), before);
  });
  for (final imported in [false, true]) {
    test(
      '${imported ? 'imported' : 'account'} completion after revision save rejects actual approval; reopening allows correction',
      () async {
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final root = await f.post(9, 2, -1000);
        final revision = await save(f, root, amount: 1500);
        final EntityId completion;
        if (imported) {
          final statement = importPayment(f);
          f.w.database.acceptStatementMatch(
            businessId: f.business,
            statementId: statement,
            sourceRow: 2,
            journalId: root,
            lineIndex: 0,
            actorId: f.w.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
          completion = EntityId.random();
          f.w.database.approveStatementReconciliation(
            requestId: completion,
            businessId: f.business,
            statementId: statement,
            actorId: f.w.identity.ownerId,
            approvedAt: DateTime.now(),
            startsOn: DateTime.utc(2026, 9, 1),
            endsOn: DateTime.utc(2026, 9, 30),
            openingBalance: Money.fromMinor(10000, 'MYR'),
            closingBalance: Money.fromMinor(9000, 'MYR'),
            expectedAcceptanceIds: {
              2: f.w.database.statementMatchAcceptanceId(
                f.business,
                statement,
                2,
              )!,
            },
            expectedPreviousId: null,
            firstOpeningEvidence: 'Fictional opening verified',
          );
        } else {
          final review = f.review(selected: {'${root.value}:0'});
          final draft = period.save(f, review);
          completion = period.approve(f, review, revision: draft.revision);
        }
        final before = archive(f);
        final command = approval(f, revision);
        expect(
          () => f.w.database.approveManualJournalCurrentRevision(command),
          throwsStateError,
        );
        await expectLater(save(f, root, amount: 1700), throwsStateError);
        expect(archive(f), before);
        reopen(f, completion);
        expect(
          f.w.database.approveManualJournalCurrentRevision(command).entry.state,
          JournalEntryState.posted,
        );
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(archive(f));
        expect(restored.isJournalReconciled(f.business, root), false);
        expect(
          restored.manualJournalCurrentPostingId(f.business, root),
          revision.draft.entry.id,
        );
      },
    );
  }
  for (final imported in [false, true]) {
    test(
      '${imported ? 'imported' : 'account'} approved zero difference guards the latest posting under the original current identity',
      () async {
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final root = await f.post(9, 2, -1000);
        final revision = await save(f, root, amount: 1500);
        final command = approval(f, revision);
        f.w.database.approveManualJournalCurrentRevision(command);
        final currentId = revision.draft.entry.id;
        final EntityId completion;
        if (imported) {
          final statement = importPayment(f, amount: '-15.00');
          f.w.database.acceptStatementMatch(
            businessId: f.business,
            statementId: statement,
            sourceRow: 2,
            journalId: currentId,
            lineIndex: 0,
            actorId: f.w.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
          completion = EntityId.random();
          f.w.database.approveStatementReconciliation(
            requestId: completion,
            businessId: f.business,
            statementId: statement,
            actorId: f.w.identity.ownerId,
            approvedAt: DateTime.now(),
            startsOn: DateTime.utc(2026, 9, 1),
            endsOn: DateTime.utc(2026, 9, 30),
            openingBalance: Money.fromMinor(10000, 'MYR'),
            closingBalance: Money.fromMinor(8500, 'MYR'),
            expectedAcceptanceIds: {
              2: f.w.database.statementMatchAcceptanceId(
                f.business,
                statement,
                2,
              )!,
            },
            expectedPreviousId: null,
            firstOpeningEvidence: 'Fictional opening verified',
          );
        } else {
          final review = f.review(
            selected: {
              '${root.value}:0',
              '${command.requestId.value}:0',
              '${currentId.value}:0',
            },
            closing: 8500,
          );
          expect(review.reviewAgrees, isTrue);
          final draft = period.save(f, review);
          completion = period.approve(f, review, revision: draft.revision);
        }
        expect(
          f.w.database.journalReconciliationId(f.business, currentId),
          completion,
        );
        expect(
          f.w.database.manualJournalCurrentRootForEntry(f.business, currentId),
          root,
        );
        final before = archive(f);
        await expectLater(save(f, root, amount: 1700), throwsStateError);
        expect(archive(f), before);
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        await expectLater(save(f, root, amount: 1700), throwsStateError);
        reopen(f, completion);
        final next = await save(f, root, amount: 1700);
        expect(next.rootId, root);
        expect(next.source.entry.id, currentId);
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(archive(f));
        expect(
          restored.manualJournalCurrentRevision(f.business, root)!.revision,
          2,
        );
        expect(restored.isJournalReconciled(f.business, currentId), false);
      },
    );
  }
  for (final status in [AccountStatus.locked, AccountStatus.archived]) {
    test(
      'current saved ${status.name} selections survive Memo edits without permitting changed or duplicated unavailable rows',
      () async {
        final f = Fixture();
        await f.open();
        final root = await f.post(9, 14, -10000);
        final current = await save(f, root, amount: 12000);
        final account = (await f.w.accounts()).singleWhere(
          (r) => r.account.id == f.expense,
        );
        await f.w.database.saveAccount(
          StoredAccount(
            account: Account.create(
              id: account.account.id,
              code: account.account.code,
              name: account.account.name,
              type: account.account.type,
              status: status,
            ),
            metadata: account.metadata.nextRevision(
              updatedAt: account.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            ),
          ),
        );
        expect(
          f.w.database.isJournalReconciled(f.business, current.source.entry.id),
          false,
        );
        final request = EntityId.random();
        final at = current.draft.metadata.updatedAt.add(
          const Duration(seconds: 1),
        );
        final replacement = JournalEntry.draft(
          id: request,
          date: current.draft.entry.date,
          memo: 'Fictional Memo correction only',
          lines: current.draft.entry.lines,
        );
        final saved = f.w.database.saveManualJournalCurrentRevision(
          rootId: root,
          expectedSource: current.source,
          expectedCurrentRevision: current.revision,
          replacement: replacement,
          requestId: request,
          actorId: f.w.identity.ownerId,
          deviceId: f.w.identity.deviceId,
          savedAt: at,
        );
        expect(saved.draft.entry.memo, replacement.memo);
        expect(saved.draft.entry.lines.map((l) => l.amount.minorUnits), [
          12000,
          12000,
        ]);
        final once = archive(f);
        f.w.database.saveManualJournalCurrentRevision(
          rootId: root,
          expectedSource: current.source,
          expectedCurrentRevision: current.revision,
          replacement: replacement,
          requestId: request,
          actorId: f.w.identity.ownerId,
          deviceId: f.w.identity.deviceId,
          savedAt: at,
        );
        expect(archive(f), once);
        await expectLater(save(f, root, amount: 13000), throwsStateError);
        expect(archive(f), once);
        final duplicateId = EntityId.random();
        expect(
          () => f.w.database.saveManualJournalCurrentRevision(
            rootId: root,
            expectedSource: current.source,
            expectedCurrentRevision: saved.revision,
            replacement: JournalEntry.draft(
              id: duplicateId,
              date: saved.draft.entry.date,
              memo: 'Fictional duplicated unavailable row',
              lines: [
                JournalLine.credit(
                  accountId: f.bank,
                  amount: Money.fromMinor(24000, 'MYR'),
                ),
                ...saved.draft.entry.lines.where((l) => l.isDebit),
                ...saved.draft.entry.lines.where((l) => l.isDebit),
              ],
            ),
            requestId: duplicateId,
            actorId: f.w.identity.ownerId,
            deviceId: f.w.identity.deviceId,
            savedAt: at.add(const Duration(seconds: 1)),
          ),
          throwsStateError,
        );
        expect(archive(f), once);
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        final next = await save(f, root, amount: 12000);
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(archive(f));
        expect(
          restored
              .manualJournalCurrentRevision(f.business, root)!
              .draft
              .entry
              .id,
          next.draft.entry.id,
        );
        expect(restored.isCurrentManualJournalRoot(f.business, root), true);
      },
    );
  }
  test('restore rejects changed current revision facts atomically', () async {
    final f = Fixture();
    await f.open();
    final root = await f.post(9, 14, -10000);
    await save(f, root);
    final data = body(archive(f));
    final table = data['tables']['ledger_audit'];
    final columns = (table['columns'] as List).cast<String>();
    final kind = columns.indexOf('kind');
    final detail = columns.indexOf('detail');
    final row = (table['rows'] as List).cast<List>().singleWhere(
      (r) => r[kind] == 'journal.current_saved',
    );
    final payload = jsonDecode(row[detail] as String);
    payload['draft']['memo'] = 'Forged current memo';
    row[detail] = jsonEncode(payload);
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    expect(
      () => restored.restoreDataArchive(envelope(data)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'retained current revision facts',
          contains('Journal current revision history differs'),
        ),
      ),
    );
    restored.restoreDataArchive(archive(f));
    expect(restored.isCurrentManualJournalRoot(f.business, root), true);
  });
  test('source-owned Expense cannot enter manual current correction', () async {
    final f = Fixture();
    await f.open();
    final source = await expense.source(f);
    final root = source.summary.journalId!;
    final before = archive(f);
    expect(f.w.database.isCurrentManualJournalRoot(f.business, root), false);
    await expectLater(save(f, root), throwsStateError);
    expect(archive(f), before);
  });
  test('pending match is corrected with history; raw reversal cannot bypass current source owner', () async {
    final f = Fixture();
    await f.open();
    final root = await f.post(9, 2, -1000);
    final original = (await f.w.database.getById(root))!;
    final statement = importPayment(f);
    f.w.database.acceptStatementMatch(
      businessId: f.business,
      statementId: statement,
      sourceRow: 2,
      journalId: root,
      lineIndex: 0,
      actorId: f.w.identity.ownerId,
      acceptedAt: original.metadata.updatedAt,
    );
    final accepted = f.w.database.statementMatchAcceptanceId(
      f.business,
      statement,
      2,
    )!;
    final revision = await save(f, root, amount: 1500);
    final rawId = EntityId.random();
    final at = revision.draft.metadata.updatedAt.add(
      const Duration(seconds: 1),
    );
    await f.w.database.save(
      StoredJournalEntry(
        entry: original.entry.reversal(
          id: rawId,
          date: original.entry.date,
          memo: 'Fictional generic reversal',
        ),
        metadata: RecordMetadata.initial(
          recordId: rawId,
          businessId: f.business,
          originDeviceId: f.w.identity.deviceId,
          createdAt: at,
        ),
      ),
    );
    final before = archive(f);
    await expectLater(
      f.w.database.approve(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: f.business,
          journalId: rawId,
          expectedRevision: 1,
          actorId: f.w.identity.ownerId,
          approvedAt: at.add(const Duration(seconds: 1)),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'typed correction ownership',
          contains('linked current Journal correction'),
        ),
      ),
    );
    expect(archive(f), before);
    f.w.database.approveManualJournalCurrentRevision(approval(f, revision));
    expect(
      f.w.database.statementMatchAcceptanceId(f.business, statement, 2),
      null,
    );
    final archiveBody = body(archive(f));
    final table = archiveBody['tables']['bank_match_retractions'];
    final columns = (table['columns'] as List).cast<String>();
    expect(
      (table['rows'] as List).cast<List>().single[columns.indexOf(
        'acceptance_id',
      )],
      accepted,
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive(f));
    expect(
      restored.manualJournalCurrentPostingId(f.business, root),
      revision.draft.entry.id,
    );
    expect(restored.statementMatchAcceptanceId(f.business, statement, 2), null);
  });
  test('posted current draft without linked correction history rejects restore atomically', () async {
    final f = Fixture();
    await f.open();
    final root = await f.post(9, 14, -10000);
    final revision = await save(f, root);
    f.w.database.approveManualJournalCurrentRevision(approval(f, revision));
    final data = body(archive(f));
    final table = data['tables']['ledger_audit'];
    final columns = (table['columns'] as List).cast<String>();
    final kind = columns.indexOf('kind');
    (table['rows'] as List).removeWhere(
      (r) => r[kind] == 'journal.current_posted',
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    expect(
      () => restored.restoreDataArchive(envelope(data)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'retained approval link',
          contains('no linked correction approval'),
        ),
      ),
    );
    restored.restoreDataArchive(archive(f));
    expect(
      restored.manualJournalCurrentPostingId(f.business, root),
      revision.draft.entry.id,
    );
  });
}
