import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'account_reconciliation_persistence_test.dart' show approve, save;
import 'bank_statement_import_test.dart' show parse;

EntityId importPayment(Fixture f, {String amount = '-10.00'}) =>
    f.w.database.importBankStatement(
      id: EntityId.random(),
      businessId: f.business,
      paymentAccountId: 'bank',
      importedAt: DateTime.now(),
      statement: parse(
        'Date,Description,Amount\n2026-09-02,Fictional supplies,$amount',
      ),
    );

void reopen(Fixture f, EntityId completion) =>
    f.w.database.reopenStatementReconciliation(
      businessId: f.business,
      completionId: completion.value,
      actorId: f.w.identity.ownerId,
      reopenedAt: DateTime.now(),
      reason: 'Fictional correction',
    );

EntityId completeImported(Fixture f, EntityId statement) {
  final completion = EntityId.random();
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
      2: f.w.database.statementMatchAcceptanceId(f.business, statement, 2)!,
    },
    expectedPreviousId: null,
    firstOpeningEvidence: 'Fictional verified opening',
  );
  return completion;
}

void main() {
  test(
    'imported reconciliation locks only after zero-difference approval',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final payment = await f.post(9, 2, -1000);
      final statement = importPayment(f);
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: payment,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      void saveDraft(int closing, int revision) =>
          f.w.database.saveReconciliationDraft(
            businessId: f.business,
            statementId: statement,
            actorId: f.w.identity.ownerId,
            expectedRevision: revision,
            startsOn: DateTime.utc(2026, 9, 1),
            endsOn: DateTime.utc(2026, 9, 30),
            openingBalance: Money.fromMinor(10000, 'MYR'),
            closingBalance: Money.fromMinor(closing, 'MYR'),
            openingEvidence: 'Fictional verified opening',
            savedAt: DateTime.now(),
          );
      saveDraft(9001, 0);
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2026, 10, 3),
      );
      expect(
        () => f.w.database.approveStatementReconciliation(
          requestId: EntityId.random(),
          businessId: f.business,
          statementId: statement,
          actorId: f.w.identity.ownerId,
          approvedAt: DateTime.now(),
          startsOn: DateTime.utc(2026, 9, 1),
          endsOn: DateTime.utc(2026, 9, 30),
          openingBalance: Money.fromMinor(10000, 'MYR'),
          closingBalance: Money.fromMinor(9001, 'MYR'),
          expectedAcceptanceIds: {
            2: f.w.database.statementMatchAcceptanceId(
              f.business,
              statement,
              2,
            )!,
          },
          expectedPreviousId: null,
          firstOpeningEvidence: 'Fictional verified opening',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'nonzero difference rejection',
            contains('Resolve statement differences'),
          ),
        ),
      );
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2026, 10, 3)),
        before,
      );
      f.w.database.requireJournalUnreconciled(f.business, payment);
      saveDraft(9000, 1);
      f.w.dispose();
      f.w = await AccountingWorkspace.open(f.path);
      f.w.database.requireJournalUnreconciled(f.business, payment);
      expect(
        f.w.database
            .readReconciliationDraft(f.business, statement)!
            .closingBalance
            .minorUnits,
        9000,
      );
      final completion = completeImported(f, statement);
      expect(
        f.w.database.journalReconciliationId(f.business, payment),
        completion,
      );
      reopen(f, completion);
      f.w.database.requireJournalUnreconciled(f.business, payment);
    },
  );

  test(
    'account-period reconciliation locks only after zero-difference approval',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final payment = await f.post(9, 2, -1000);
      final selected = {'${payment.value}:0'};
      final wrong = f.review(selected: selected, closing: 9001);
      expect(wrong.review.closingDifference.minorUnits, 1);
      expect(wrong.reviewAgrees, isFalse);
      save(f, wrong);
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2026, 10, 3),
      );
      expect(
        () => approve(f, wrong, revision: 1),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'nonzero difference rejection',
            contains('closing differences'),
          ),
        ),
      );
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2026, 10, 3)),
        before,
      );
      f.w.database.requireJournalUnreconciled(f.business, payment);
      final balanced = f.review(selected: selected);
      expect(balanced.review.closingDifference.isZero, isTrue);
      expect(balanced.reviewAgrees, isTrue);
      save(f, balanced, revision: 1);
      f.w.dispose();
      f.w = await AccountingWorkspace.open(f.path);
      f.w.database.requireJournalUnreconciled(f.business, payment);
      final completion = approve(f, f.review(selected: selected), revision: 2);
      expect(
        f.w.database.journalReconciliationId(f.business, payment),
        completion,
      );
      reopen(f, completion);
      f.w.database.requireJournalUnreconciled(f.business, payment);
    },
  );

  test(
    'posting and an unapproved match do not create a reconciliation lock',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final posted = await f.post(9, 2, -1000);
      final draft = await f.post(9, 3, -100, approve: false);
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2026, 10, 3),
      );
      expect(f.w.database.isJournalReconciled(f.business, posted), isFalse);
      expect(f.w.database.isJournalReconciled(f.business, draft), isFalse);
      f.w.database.requireJournalUnreconciled(f.business, posted);
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2026, 10, 3)),
        before,
      );
      final statement = importPayment(f);
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: posted,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      expect(f.w.database.isJournalReconciled(f.business, posted), isFalse);
      f.w.database.requireJournalUnreconciled(f.business, posted);
    },
  );

  test(
    'journal ownership fails closed for a foreign or missing source',
    () async {
      final f = Fixture();
      await f.open();
      final posted = await f.post(9, 2, -1000);
      expect(
        () => f.w.database.isJournalReconciled(EntityId.random(), posted),
        throwsStateError,
      );
      expect(
        () => f.w.database.requireJournalUnreconciled(
          f.business,
          EntityId.random(),
        ),
        throwsStateError,
      );
      f.w.dispose();
      expect(
        () => f.w.database.isJournalReconciled(f.business, posted),
        throwsStateError,
      );
      f.w = await AccountingWorkspace.open(f.path);
    },
  );

  test('imported completion locks exact journal, survives restart and releases on reopening', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final payment = await f.post(9, 2, -1000);
    final unrelated = await f.post(10, 1, -200);
    final completion = await f.approveImportedSeptember(payment);
    expect(
      f.w.database.journalReconciliationId(f.business, payment),
      completion,
    );
    expect(f.w.database.isJournalReconciled(f.business, unrelated), isFalse);
    expect(
      () => f.w.database.requireJournalUnreconciled(f.business, payment),
      throwsStateError,
    );
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    expect(
      f.w.database.journalReconciliationId(f.business, payment),
      completion,
    );
    reopen(f, completion);
    expect(f.w.database.isJournalReconciled(f.business, payment), isFalse);
    f.w.database.requireJournalUnreconciled(f.business, payment);
    expect(
      f.w.database.reconciliationEvidence(f.business, completion.value).matches,
      hasLength(1),
    );
  });

  test('account-period completion locks only selected movements, not outstanding or later journals', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final payment = await f.post(9, 2, -1000);
    final outstanding = await f.post(9, 3, -500);
    final future = await f.post(10, 1, -100);
    final completion = approve(f, f.review(selected: {'${payment.value}:0'}));
    expect(
      f.w.database.journalReconciliationId(f.business, payment),
      completion,
    );
    expect(f.w.database.isJournalReconciled(f.business, outstanding), isFalse);
    expect(f.w.database.isJournalReconciled(f.business, future), isFalse);
    reopen(f, completion);
    f.w.database.requireJournalUnreconciled(f.business, payment);
    expect(
      f.w.database
          .reconciliationEvidence(f.business, completion.value)
          .selectedMovements,
      hasLength(1),
    );
  });

  test(
    'completed combined import locks every member and reopening releases both',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final first = await f.post(9, 2, -400);
      final second = await f.post(9, 2, -600);
      final statement = importPayment(f);
      f.w.database.acceptStatementCombinedMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        movementIds: {'${first.value}:0', '${second.value}:0'},
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      expect(f.w.database.isJournalReconciled(f.business, first), isFalse);
      expect(f.w.database.isJournalReconciled(f.business, second), isFalse);
      final completion = completeImported(f, statement);
      expect(
        f.w.database.journalReconciliationId(f.business, first),
        completion,
      );
      expect(
        f.w.database.journalReconciliationId(f.business, second),
        completion,
      );
      f.w.dispose();
      f.w = await AccountingWorkspace.open(f.path);
      expect(f.w.database.isJournalReconciled(f.business, second), isTrue);
      reopen(f, completion);
      f.w.database.requireJournalUnreconciled(f.business, first);
      f.w.database.requireJournalUnreconciled(f.business, second);
    },
  );

  test('saved correction rechecks reconciliation at actual approval after source becomes locked', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final payment = await f.post(9, 2, -1000);
    final source = (await f.w.journals()).singleWhere(
      (j) => j.entry.id == payment,
    );
    final correction = EntityId.random();
    await f.w.database.save(
      StoredJournalEntry(
        entry: source.entry.reversal(
          id: correction,
          date: DateTime.utc(2026, 10, 2),
          memo: 'Fictional reviewed correction',
        ),
        metadata: RecordMetadata.initial(
          recordId: correction,
          businessId: f.business,
          originDeviceId: f.w.identity.deviceId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    f.w.database.requireJournalUnreconciled(f.business, payment);
    final completion = approve(f, f.review(selected: {'${payment.value}:0'}));
    final before = f.w.database.exportDataArchive(
      f.business,
      DateTime.utc(2026, 10, 3),
    );
    final command = JournalApproval(
      requestId: EntityId.random(),
      businessId: f.business,
      journalId: correction,
      expectedRevision: 1,
      actorId: f.w.identity.ownerId,
      approvedAt: DateTime.now(),
    );
    await expectLater(
      f.w.database.approve(command),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reconciliation message',
          contains('Reopen its reconciliation'),
        ),
      ),
    );
    expect(
      f.w.database.exportDataArchive(f.business, DateTime.utc(2026, 10, 3)),
      before,
    );
    expect(
      (await f.w.database.getById(correction))!.entry.state,
      JournalEntryState.draft,
    );
    reopen(f, completion);
    expect(
      (await f.w.database.approve(command)).entry.state,
      JournalEntryState.posted,
    );
    List<List<Object>> facts(JournalEntry entry) => [
      for (final line in entry.lines)
        [
          line.accountId.value,
          line.kind.name,
          line.amount.minorUnits,
          line.amount.currency,
        ],
    ];
    expect(
      facts((await f.w.database.getById(payment))!.entry),
      facts(source.entry),
    );
  });
}
