import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/expense_intake.dart';
import 'package:audyt/features/accounting/domain/expense_revision.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'account_reconciliation_persistence_test.dart' as reconciliation;
import 'approved_claim_expense_test.dart' as claim;
import 'claim_receipt_tax_test.dart' as claim_fixture;
import 'expense_intake_test.dart' show draft;
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'journal_editability_test.dart' show reopen;

final stamp = DateTime.utc(2027, 1, 1);

ExpenseDraftLine line(String id, String amount) => ExpenseDraftLine(
  id: id,
  category: 'Office Operations',
  description: 'Fictional $id',
  tax: '0',
  amount: amount,
);

RecordExpenseDraft change(
  RecordExpenseDraft old,
  List<ExpenseDraftLine> lines,
  String amount, {
  Map<String, Object?> fields = const {},
}) => RecordExpenseDraft.fromJson({
  ...old.toJson(),
  'version': old.claimSource == null ? 2 : 3,
  'taxMode': old.taxMode ?? 'Exclusive',
  'amount': amount,
  'lines': lines.map((l) => l.toJson()).toList(),
  ...fields,
});

Future<ExpenseIntakeRecord> source(Fixture f, {bool evidence = false}) async {
  final initial = RecordExpenseDraft.fromJson({
    ...draft(amount: '10', paymentAccountId: 'bank').toJson(),
    'version': 2,
    'date': '02-09-2026',
    'taxMode': 'Exclusive',
    'paymentAccount': 'Fictional Bank',
    'lines': [line('original', '10').toJson()],
    'attachments': evidence
        ? [
            file([1, 2, 3]).toJson(),
          ]
        : [],
  });
  final id = EntityId.random();
  await f.w.database.saveExpenseIntake(
    id: id,
    businessId: f.business,
    draft: initial,
    createdAt: DateTime.utc(2026, 9, 1),
  );
  final journal = await f.post(9, 2, -1000, approve: false);
  final stored = await f.w.database.getJournal(journal);
  await f.w.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: f.business,
      journalId: journal,
      expectedRevision: stored!.metadata.revision,
      actorId: f.w.identity.ownerId,
      approvedAt: DateTime.now(),
      expenseIntakeId: id,
    ),
  );
  return (await f.w.expense(id))!;
}

ReceiptAttachment file(List<int> bytes) => ReceiptAttachment.queued(
  ReceiptAttachmentInput(
    originalId: 'original-file',
    batchId: 'fictional',
    filename: 'Fictional receipt.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList(bytes),
  ),
);

ExpenseRevision save(
  Fixture f,
  ExpenseIntakeRecord original,
  RecordExpenseDraft after, {
  int revision = 0,
  RecordExpenseDraft? before,
  EntityId? request,
  EntityId? actor,
  EntityId? business,
  EntityId? journal,
  int? sourceRevision,
  DateTime? at,
}) => f.w.database.saveExpenseRevision(
  businessId: business ?? f.business,
  expenseId: original.summary.id,
  requestId: request ?? EntityId.random(),
  actorId: actor ?? f.w.identity.ownerId,
  expectedSourceJournalId: journal ?? original.summary.journalId!,
  expectedSourceExpenseRevision: sourceRevision ?? original.summary.revision,
  expectedRevision: revision,
  expected: before ?? original.draft,
  replacement: after,
  savedAt: at ?? stamp,
);

String archive(Fixture f) => f.w.database.exportDataArchive(f.business, stamp);

void main() {
  test('identity, currency and unavailable payment accounts cannot be smuggled into a revision', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    final snapshot = archive(f);
    for (final fields in [
      {'submissionId': EntityId.random().value},
      {'currencyCode': 'USD'},
      {'paymentAccountId': 'missing'},
    ]) {
      final forged = change(after, after.lines, after.amount, fields: fields);
      expect(() => save(f, original, forged), throwsStateError);
      expect(archive(f), snapshot);
    }
  });

  test(
    'new line tax selections must belong to actual company history',
    () async {
      final f = await claim_fixture.fixture();
      addTearDown(f.w.dispose);
      final journal = claim.approve(f);
      final original = (await f.w.expense(journal))!;
      final code = CompanyTaxRate.fromJson({
        ...f.code.toJson(),
        'percent': '9',
      });
      final lines = [...original.draft.lines];
      lines[0] = ExpenseDraftLine.fromJson({
        ...lines[0].toJson(),
        'tax': code.choice,
        'taxSnapshot': code.toJson(),
      });
      final forged = change(original.draft, lines, '183');
      final snapshot = f.w.database.exportDataArchive(
        f.w.identity.businessId,
        stamp,
      );
      expect(
        () => f.w.saveExpenseRevision(
          expenseId: journal,
          requestId: EntityId.random(),
          expectedSourceJournalId: journal,
          expectedSourceExpenseRevision: original.summary.revision,
          expectedRevision: 0,
          expected: original.draft,
          replacement: forged,
          savedAt: stamp,
        ),
        throwsStateError,
      );
      expect(
        f.w.database.exportDataArchive(f.w.identity.businessId, stamp),
        snapshot,
      );
    },
  );

  test('current line add/edit/remove revisions persist across restart without rewriting the posting', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final posted = (await f.w.journals()).single;
    final added = change(original.draft, [
      line('original', '12'),
      line('added', '5'),
    ], '17');
    var notifications = 0;
    f.w.addListener(() => notifications++);
    final first = f.w.saveExpenseRevision(
      expenseId: original.summary.id,
      requestId: EntityId.random(),
      expectedSourceJournalId: original.summary.journalId!,
      expectedSourceExpenseRevision: original.summary.revision,
      expectedRevision: 0,
      expected: original.draft,
      replacement: added,
      savedAt: stamp,
    );
    expect(first.revision, 1);
    expect(notifications, 1);
    final removed = change(added, [line('added', '6')], '6');
    final second = save(
      f,
      original,
      removed,
      revision: 1,
      before: added,
      at: stamp.add(const Duration(seconds: 1)),
    );
    expect(second.before.lines, hasLength(2));
    expect(second.draft.lines.single.id, 'added');
    expect(
      (await f.w.originalExpense(original.summary.id))!.draft.toJson(),
      original.draft.toJson(),
    );
    final unchanged = (await f.w.journals()).single;
    expect(unchanged.metadata.revision, posted.metadata.revision);
    expect(unchanged.entry.id, posted.entry.id);
    expect(unchanged.entry.date, posted.entry.date);
    expect(unchanged.entry.memo, posted.entry.memo);
    expect(
      unchanged.entry.lines.map((l) => (l.accountId, l.amount, l.kind)),
      posted.entry.lines.map((l) => (l.accountId, l.amount, l.kind)),
    );
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    expect(
      f.w.expenseRevision(original.summary.id)!.draft.toJson(),
      removed.toJson(),
    );
    expect(
      f.w.database.expenseRevisionHistory(f.business, original.summary.id),
      hasLength(2),
    );
    expect(
      (await f.w.expense(original.summary.id))!.summary.journalId,
      posted.entry.id,
    );
  });

  test('exact command retries do not duplicate revisions; reused requests cannot change facts', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    final request = EntityId.random();
    final saved = save(f, original, after, request: request);
    final before = archive(f);
    expect(
      save(f, original, after, request: request).requestId,
      saved.requestId,
    );
    expect(archive(f), before);
    expect(
      () => save(
        f,
        original,
        change(after, [line('original', '12')], '12'),
        request: request,
      ),
      throwsStateError,
    );
    expect(archive(f), before);
  });

  test('fresh source, current revision and owner checks reject stale edits atomically', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    save(f, original, after);
    final snapshot = archive(f);
    for (final attempt in <void Function()>[
      () => save(f, original, after),
      () => save(f, original, after, revision: 1),
      () => save(
        f,
        original,
        after,
        revision: 1,
        before: after,
        actor: EntityId.random(),
      ),
      () => save(
        f,
        original,
        after,
        revision: 1,
        before: after,
        business: EntityId.random(),
      ),
      () => save(
        f,
        original,
        after,
        revision: 1,
        before: after,
        journal: EntityId.random(),
      ),
      () => save(
        f,
        original,
        after,
        revision: 1,
        before: after,
        sourceRevision: 8,
      ),
      () => save(
        f,
        original,
        after,
        revision: 1,
        before: after,
        at: stamp.subtract(const Duration(seconds: 1)),
      ),
    ]) {
      expect(attempt, throwsStateError);
      expect(archive(f), snapshot);
    }
  });

  test('reconciliation completed after opening blocks revision save; reopening permits it', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    final completion = reconciliation.approve(
      f,
      f.review(selected: {'${original.summary.journalId!.value}:0'}),
    );
    final before = archive(f);
    expect(() => save(f, original, after), throwsStateError);
    expect(archive(f), before);
    reopen(f, completion);
    expect(save(f, original, after).revision, 1);
    expect(
      f.w.database
          .reconciliationEvidence(f.business, completion.value)
          .selectedMovements,
      hasLength(1),
    );
  });

  test('imported reconciliation also blocks revisions; uncompleted matching alone does not', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    final completed = await f.approveImportedSeptember(
      original.summary.journalId!,
    );
    expect(() => save(f, original, after), throwsStateError);
    reopen(f, completed);
    expect(save(f, original, after).revision, 1);
    expect(
      f.w.database.reconciliationEvidence(f.business, completed.value).matches,
      hasLength(1),
    );
  });

  test('original evidence cannot be replaced after removal and re-add; restore retains metadata honestly', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f, evidence: true);
    final removed = change(
      original.draft,
      [line('original', '11')],
      '11',
      fields: {'attachments': []},
    );
    save(f, original, removed);
    final snapshot = archive(f);
    final forged = change(
      removed,
      [line('original', '12')],
      '12',
      fields: {
        'attachments': [
          file([9, 9, 9]).toJson(),
        ],
      },
    );
    expect(
      () => save(f, original, forged, revision: 1, before: removed),
      throwsStateError,
    );
    expect(archive(f), snapshot);
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      snapshot,
    );
    addTearDown(recovered.dispose);
    final previous = recovered.database
        .expenseRevisionHistory(f.business, original.summary.id)
        .single
        .before;
    expect(previous.attachments.single.originalBytes, isEmpty);
    expect(
      previous.attachments.single.originalSha256,
      original.draft.attachments.single.originalSha256,
    );
    expect(
      recovered.expenseRevision(original.summary.id)!.draft.attachments,
      isEmpty,
    );
  });

  test('audit failure rolls revision persistence back; retained versions reject update and delete', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    raw.execute(
      "CREATE TRIGGER fail_revision_audit BEFORE INSERT ON ledger_audit WHEN NEW.kind='expense.revision_saved' BEGIN SELECT RAISE(ABORT,'Injected audit failure'); END",
    );
    final before = archive(f);
    expect(() => save(f, original, after), throwsA(isA<SqliteException>()));
    expect(archive(f), before);
    raw.execute('DROP TRIGGER fail_revision_audit');
    save(f, original, after);
    expect(
      () => raw.execute("UPDATE expense_revision_drafts SET payload='{}'"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute('DELETE FROM expense_revision_drafts'),
      throwsA(isA<SqliteException>()),
    );
  });

  test('Claim revisions retain claimant/recognition and original liability without another posting', () async {
    final f = await claim_fixture.fixture();
    addTearDown(f.w.dispose);
    final journal = claim.approve(f);
    final original = (await f.w.expense(journal))!;
    final claimBefore = f.w.claims.all.single.toJson();
    final newLines = [...original.draft.lines, line('new-line', '5')];
    final sourceJson = {
      ...original.draft.claimSource!.toJson(),
      'lineBases': {
        ...original.draft.claimSource!.lineBases,
        'new-line': 'Exclusive',
      },
    };
    final after = change(
      original.draft,
      newLines,
      '187',
      fields: {'claimSource': sourceJson},
    );
    ExpenseRevision command(
      RecordExpenseDraft value, {
      int revision = 0,
      RecordExpenseDraft? before,
    }) => f.w.saveExpenseRevision(
      expenseId: journal,
      requestId: EntityId.random(),
      expectedSourceJournalId: journal,
      expectedSourceExpenseRevision: original.summary.revision,
      expectedRevision: revision,
      expected: before ?? original.draft,
      replacement: value,
      savedAt: stamp,
    );
    final saved = command(after);
    expect(saved.draft.lines, hasLength(4));
    expect(saved.draft.taxTotals!.total.minorUnits, 18700);
    expect(
      saved.draft.claimSource!.claimId,
      original.draft.claimSource!.claimId,
    );
    expect(
      saved.draft.claimSource!.claimantName,
      original.draft.claimSource!.claimantName,
    );
    expect(f.w.claims.all.single.toJson(), claimBefore);
    expect((await f.w.journals()), hasLength(1));
    expect(
      (await f.w.originalExpense(journal))!.draft.toJson(),
      original.draft.toJson(),
    );
    final impostor = change(
      after,
      newLines,
      '187',
      fields: {
        'claimSource': {...sourceJson, 'claimantName': 'Another claimant'},
      },
    );
    expect(
      () => command(impostor, revision: 1, before: after),
      throwsStateError,
    );
    final data = f.w.database.exportDataArchive(f.w.identity.businessId, stamp);
    final restored = await AccountingWorkspace.emptyRestore(':memory:', data);
    addTearDown(restored.dispose);
    expect(
      restored.expenseRevision(journal)!.draft.claimSource!.claimantName,
      original.draft.claimSource!.claimantName,
    );
    final restoredOriginal = (await restored.originalExpense(journal))!.draft;
    expect(
      restoredOriginal.claimSource!.toJson(),
      original.draft.claimSource!.toJson(),
    );
    expect(
      restoredOriginal.lines.map((l) => l.toJson()),
      original.draft.lines.map((l) => l.toJson()),
    );
    expect(restoredOriginal.amount, original.draft.amount);
    expect(
      restoredOriginal.attachments.single.originalSha256,
      original.draft.attachments.single.originalSha256,
    );
    expect(
      restoredOriginal.attachments.single.originalBytes,
      isEmpty,
      reason: 'Data-only recovery retains checksums and honestly unavailable bytes.',
    );
  });

  test('archive recovery rejects altered source, chain, claimant and missing audit evidence', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final after = change(original.draft, [line('original', '11')], '11');
    save(f, original, after);
    final clean = archive(f);
    for (final column in [
      'actor_id',
      'source_journal_id',
      'revision',
      'before_payload',
    ]) {
      final data = body(clean);
      final table = (data['tables'] as Map)['expense_revision_drafts'] as Map;
      final index = (table['columns'] as List).indexOf(column);
      final row = (table['rows'] as List).single as List;
      row[index] = column == 'revision'
          ? 2
          : column == 'before_payload'
          ? jsonEncode(after.toJson())
          : EntityId.random().value;
      await expectLater(
        AccountingWorkspace.emptyRestore(':memory:', envelope(data)),
        throwsA(anything),
      );
    }
    final missingAudit = body(clean);
    final audit = (missingAudit['tables'] as Map)['ledger_audit'] as Map;
    final kind = (audit['columns'] as List).indexOf('kind');
    (audit['rows'] as List).removeWhere(
      (row) => (row as List)[kind] == 'expense.revision_saved',
    );
    await expectLater(
      AccountingWorkspace.emptyRestore(':memory:', envelope(missingAudit)),
      throwsA(anything),
    );
  });

  test('populated schema60 upgrade and historical recovery preserve all existing data', () async {
    final f = Fixture();
    await f.open();
    final original = await source(f);
    final prior = body(archive(f));
    final oldArchive = envelope(historical(archive(f), 60));
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    dropCurrentQuotationFixtureOwner(raw);
    raw.execute('DROP VIEW current_expense_intakes');
    raw.execute('DROP VIEW financial_expense_intakes');
    raw.execute('DROP TABLE expense_revision_postings');
    raw.execute('DROP TABLE expense_revision_drafts');
    raw.execute('PRAGMA user_version=60');
    raw.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    final upgraded = body(archive(f));
    for (final entry in (prior['tables'] as Map).entries) {
      expect(
        (upgraded['tables'] as Map)[entry.key],
        entry.value,
        reason: '${entry.key}',
      );
    }
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      oldArchive,
    );
    addTearDown(recovered.dispose);
    expect(
      (await recovered.expense(original.summary.id))!.draft.toJson(),
      original.draft.toJson(),
    );
    expect(
      save(
        f,
        original,
        change(original.draft, [line('original', '11')], '11'),
      ).revision,
      1,
    );
  });
}
