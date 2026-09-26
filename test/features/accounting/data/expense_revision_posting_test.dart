import '../../../support/historical_sqlite_fixture.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_intake.dart';
import 'package:audyt/features/accounting/domain/expense_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'archive_upgrade_test.dart' show historical, envelope;
import 'claim_receipt_tax_test.dart' show report;
import 'expense_revision_test.dart'
    show source, change, line, save, stamp, archive;
import 'journal_editability_test.dart'
    show importPayment, completeImported, reopen;

Future<ExpenseRevisionApproval> review(
  Fixture f,
  ExpenseIntakeRecord root, {
  int amount = 1100,
  int revision = 1,
  EntityId? sourceJournal,
}) async {
  final id = await f.post(9, 2, -amount, approve: false);
  final journal = (await f.w.database.getJournal(id))!;
  return ExpenseRevisionApproval(
    requestId: EntityId.random(),
    businessId: f.business,
    expenseId: root.summary.id,
    expectedRevision: revision,
    expectedSourceJournalId: sourceJournal ?? root.summary.journalId!,
    journalId: id,
    expectedJournalRevision: journal.metadata.revision,
    actorId: f.w.identity.ownerId,
    approvedAt: stamp.add(const Duration(minutes: 1)),
  );
}

void main() {
  test('pending row changes reach current editor/list/search without changing posted totals', () async {
    final f = Fixture();
    await f.open();
    final root = await source(f);
    final after = change(
      root.draft,
      [line('original', '6'), line('added', '5')],
      '11',
      fields: {'payee': 'Revised payee'},
    );
    save(f, root, after);
    final current = (await f.w.expense(root.summary.id))!;
    expect(current.draft.toJson(), after.toJson());
    expect(current.summary.pendingRevision, 1);
    expect(current.currentRevision!.revision, 1);
    final listed = (await f.w.database.listExpenseIntakes(f.business)).single;
    expect(listed.amount.minorUnits, 1100);
    expect(listed.payee, 'Revised payee');
    expect(
      f.w.database
          .searchExpenseIntakes(businessId: f.business, query: 'Revised')
          .single
          .id,
      root.summary.id,
    );
    final financial = f.w.database
        .readRecentPostedExpenseIntakes(businessId: f.business, through: stamp)
        .single;
    expect(financial.amount.minorUnits, 1000);
    expect(financial.pendingRevision, 0);
    expect(
      (await f.w.originalExpense(root.summary.id))!.draft.toJson(),
      root.draft.toJson(),
    );
    expect(await f.w.journals(), hasLength(1));
  });

  test('exact reviewed revision reverses prior posting, retains original, recovers and retries once', () async {
    final f = Fixture();
    await f.open();
    final root = await source(f);
    final after = change(root.draft, [line('added', '11')], '11');
    save(f, root, after);
    final command = await review(f, root);
    final posting = f.w.approveExpenseRevision(command);
    expect(posting.revision, 1);
    final current = (await f.w.expense(root.summary.id))!;
    expect(current.draft.toJson(), after.toJson());
    expect(current.summary.pendingRevision, 0);
    expect(current.summary.journalId, command.journalId);
    expect(
      (await f.w.originalExpense(root.summary.id))!.draft.toJson(),
      root.draft.toJson(),
    );
    expect(
      f.w.database
          .readRecentPostedExpenseIntakes(
            businessId: f.business,
            through: stamp,
          )
          .single
          .amount
          .minorUnits,
      1100,
    );
    final activity = await report(f.w);
    expect(
      activity.rows.fold<BigInt>(
        BigInt.zero,
        (total, row) => total + row.grossMinor,
      ),
      BigInt.from(1100),
    );
    final journals = await f.w.journals();
    expect(journals, hasLength(3));
    final reversal = journals.singleWhere(
      (j) => j.entry.id == command.requestId,
    );
    expect(reversal.entry.reversesId, root.summary.journalId);
    expect(
      reversal.entry.date,
      journals
          .singleWhere((j) => j.entry.id == root.summary.journalId)
          .entry
          .date,
    );
    final committed = archive(f);
    expect(f.w.approveExpenseRevision(command).journalId, posting.journalId);
    expect(archive(f), committed);
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      committed,
    );
    addTearDown(recovered.dispose);
    expect(
      (await recovered.expense(root.summary.id))!.draft.toJson(),
      after.toJson(),
    );
    expect(
      (await recovered.originalExpense(root.summary.id))!.draft.toJson(),
      root.draft.toJson(),
    );
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    expect(
      (await f.w.expense(root.summary.id))!.summary.journalId,
      posting.journalId,
    );
  });

  test('wrong reviewed total and late reconciliation reject atomically; reopening permits correction', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final root = await source(f);
    save(f, root, change(root.draft, [line('original', '11')], '11'));
    final wrong = await review(f, root, amount: 1200);
    final before = archive(f);
    expect(() => f.w.approveExpenseRevision(wrong), throwsStateError);
    expect(archive(f), before);
    final right = await review(f, root);
    final statement = importPayment(f);
    f.w.database.acceptStatementMatch(
      businessId: f.business,
      statementId: statement,
      sourceRow: 2,
      journalId: root.summary.journalId!,
      lineIndex: 0,
      actorId: f.w.identity.ownerId,
      acceptedAt: DateTime.now(),
    );
    final completion = completeImported(f, statement);
    final locked = archive(f);
    expect(() => f.w.approveExpenseRevision(right), throwsStateError);
    expect(archive(f), locked);
    reopen(f, completion);
    f.w.approveExpenseRevision(right);
    expect(
      f.w.database.statementMatchAcceptanceId(f.business, statement, 2),
      isNull,
    );
  });

  test(
    'posting audit failure rolls back both postings and current financial view',
    () async {
      final f = Fixture();
      await f.open();
      final root = await source(f);
      save(f, root, change(root.draft, [line('original', '11')], '11'));
      final command = await review(f, root);
      final raw = sqlite3.open(f.path);
      raw.execute(
        "CREATE TRIGGER fail_expense_posting BEFORE INSERT ON ledger_audit WHEN NEW.kind='expense.revision_posted' BEGIN SELECT RAISE(ABORT,'Injected audit failure'); END",
      );
      raw.dispose();
      final before = archive(f);
      expect(
        () => f.w.approveExpenseRevision(command),
        throwsA(isA<SqliteException>()),
      );
      expect(archive(f), before);
      expect(
        f.w.database.expenseRevisionPosting(f.business, root.summary.id),
        isNull,
      );
      expect(
        (await f.w.journals()).where((j) => j.entry.reversesId != null),
        isEmpty,
      );
      expect(
        f.w.database
            .readRecentPostedExpenseIntakes(
              businessId: f.business,
              through: stamp,
            )
            .single
            .amount
            .minorUnits,
        1000,
      );
    },
  );

  test('second correction uses current posting and retains complete report and approval lineage', () async {
    final f = Fixture();
    await f.open();
    final root = await source(f);
    final first = change(
      root.draft,
      [line('original', '11')],
      '11',
      fields: {'payee': 'First payee'},
    );
    save(f, root, first);
    final approved = f.w.approveExpenseRevision(await review(f, root));
    final second = change(
      first,
      [line('second', '7')],
      '7',
      fields: {'payee': 'Second payee'},
    );
    save(
      f,
      root,
      second,
      revision: 1,
      before: first,
      journal: approved.journalId,
      at: stamp.add(const Duration(minutes: 2)),
    );
    final journal = await f.post(9, 2, -700, approve: false);
    final stored = (await f.w.database.getJournal(journal))!;
    final command = ExpenseRevisionApproval(
      requestId: EntityId.random(),
      businessId: f.business,
      expenseId: root.summary.id,
      expectedRevision: 2,
      expectedSourceJournalId: approved.journalId,
      journalId: journal,
      expectedJournalRevision: stored.metadata.revision,
      actorId: f.w.identity.ownerId,
      approvedAt: stamp.add(const Duration(minutes: 3)),
    );
    f.w.approveExpenseRevision(command);
    final activity = await report(f.w);
    expect(
      activity.rows.fold<BigInt>(
        BigInt.zero,
        (total, row) => total + row.grossMinor,
      ),
      BigInt.from(700),
    );
    final labels = f.w.database.expenseSourceLabelsForJournals(
      businessId: f.business,
      journalIds: [root.summary.journalId!, approved.journalId, journal],
    );
    expect(labels[approved.journalId.value]!.payee, 'First payee');
    expect(labels[journal.value]!.payee, 'Second payee');
    expect((await f.w.expense(root.summary.id))!.summary.journalId, journal);
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      archive(f),
    );
    addTearDown(recovered.dispose);
    expect(
      (await recovered.expense(root.summary.id))!.draft.toJson(),
      second.toJson(),
    );
    expect(
      (await recovered.originalExpense(root.summary.id))!.draft.toJson(),
      root.draft.toJson(),
    );
    expect(
      recovered.database.expenseRevisionHistory(f.business, root.summary.id),
      hasLength(2),
    );
  });

  test('populated schema61 upgrades and restores pending edits without rewriting evidence', () async {
    final f = Fixture();
    await f.open();
    final root = await source(f);
    final edited = change(root.draft, [
      line('original', '6'),
      line('added', '5'),
    ], '11');
    save(f, root, edited);
    final historicalArchive = envelope(historical(archive(f), 61));
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    dropCurrentQuotationFixtureOwner(raw);
    raw.execute('DROP VIEW current_expense_intakes');
    raw.execute('DROP VIEW financial_expense_intakes');
    raw.execute('DROP TABLE expense_revision_postings');
    raw.execute('DROP TRIGGER expense_revision_no_update');
    for (final column in [
      'occurred_on',
      'amount_minor',
      'currency',
      'payee',
      'category',
    ]) {
      raw.execute('ALTER TABLE expense_revision_drafts DROP COLUMN $column');
    }
    raw.execute(
      "CREATE TRIGGER expense_revision_no_update BEFORE UPDATE ON expense_revision_drafts BEGIN SELECT RAISE(ABORT,'Expense revisions are immutable'); END",
    );
    raw.execute('PRAGMA user_version=61');
    raw.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    expect(
      (await f.w.expense(root.summary.id))!.draft.toJson(),
      edited.toJson(),
    );
    expect(
      (await f.w.originalExpense(root.summary.id))!.draft.toJson(),
      root.draft.toJson(),
    );
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      historicalArchive,
    );
    addTearDown(recovered.dispose);
    expect(
      (await recovered.expense(root.summary.id))!.draft.toJson(),
      edited.toJson(),
    );
    expect(
      recovered.database
          .readRecentPostedExpenseIntakes(
            businessId: f.business,
            through: stamp,
          )
          .single
          .amount
          .minorUnits,
      1000,
    );
    final protected = sqlite3.open(f.path);
    expect(
      () =>
          protected.execute("UPDATE expense_revision_drafts SET payload='{}'"),
      throwsA(isA<SqliteException>()),
    );
    protected.dispose();
  });
}
