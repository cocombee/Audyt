import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/application/reconciliation_report.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account_reconciliation.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'bank_statement_import_test.dart' show parse;

ReceiptAttachment file() => ReceiptAttachment.queued(
  ReceiptAttachmentInput(
    originalId: 'fictional-support',
    batchId: 'fictional',
    filename: 'Fictional evidence.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList(utf8.encode('%PDF-fictional-original')),
  ),
).withStatus(AttachmentProcessingStatus.ready);

AccountReconciliationDraft save(
  Fixture f,
  AccountReconciliationSnapshot s, {
  int revision = 0,
  EntityId? actor,
  List<ReceiptAttachment> files = const [],
}) => f.w.database.saveAccountReconciliationDraft(
  businessId: f.business,
  paymentAccountId: 'bank',
  actorId: actor ?? f.w.identity.ownerId,
  expectedRevision: revision,
  expectedPreviousId: s.previousId,
  startsOn: s.startsOn,
  endsOn: s.endsOn,
  openingBalance: s.openingBalance,
  closingBalance: s.closingBalance,
  savedAt: DateTime.now(),
  openingEvidence: 'Fictional verified opening',
  selectedIds: s.review.selected.map((m) => m.id).toSet(),
  openingOutstandingIds: s.openingOutstandingIds,
  attachments: files,
);
EntityId approve(
  Fixture f,
  AccountReconciliationSnapshot s, {
  EntityId? request,
  EntityId? actor,
  int? revision,
  List<ReceiptAttachment> files = const [],
  String evidence = 'Fictional verified opening',
}) {
  final id = request ?? EntityId.random();
  f.w.database.approveAccountReconciliation(
    requestId: id,
    businessId: f.business,
    paymentAccountId: 'bank',
    actorId: actor ?? f.w.identity.ownerId,
    approvedAt: DateTime.now(),
    startsOn: s.startsOn,
    endsOn: s.endsOn,
    openingBalance: s.openingBalance,
    closingBalance: s.closingBalance,
    selectedMovementIds: s.review.selected.map((m) => m.id).toSet(),
    expectedLedgerFingerprint: s.ledgerFingerprint,
    expectedPreviousId: s.previousId,
    expectedDraftRevision: revision,
    firstOpeningEvidence: evidence,
    openingOutstandingIds: s.openingOutstandingIds,
    attachments: files,
  );
  return id;
}

Future<(Fixture, EntityId, AccountReconciliationSnapshot)> first() async {
  final f = Fixture();
  await f.open();
  await f.post(8, 31, 10000);
  final payment = await f.post(9, 2, -1000);
  return (f, payment, f.review(selected: {'${payment.value}:0'}));
}

Map<String, List<Map<String, Object?>>> facts(Database db) => {
  for (final t in [
    'bank_reconciliations',
    'bank_reconciliation_allocations',
    'bank_reconciliation_reopenings',
    'bank_reconciliation_ledger_snapshots',
    'bank_statement_imports',
    'bank_match_history',
    'journal_entries',
    'journal_lines',
  ])
    t: db
        .select('SELECT * FROM $t')
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
};

/// Reconstruct the actual schema-59 parent constraint and remove the two new
/// empty owners. A version-number-only fixture would not exercise this upgrade.
void schema59(Database db) {
  dropCurrentQuotationFixtureOwner(db);
  final objects = db
      .select(
        "SELECT sql FROM sqlite_master WHERE tbl_name='bank_reconciliations' AND type IN ('index','trigger') AND sql IS NOT NULL",
      )
      .map((r) => r['sql'] as String)
      .toList();
  final sql =
      (db
                  .select(
                    "SELECT sql FROM sqlite_master WHERE name='bank_reconciliations'",
                  )
                  .single['sql']
              as String)
          .replaceFirst(
            RegExp(r'CREATE TABLE "?bank_reconciliations"?'),
            'CREATE TABLE legacy_reconciliations',
          )
          .replaceFirst(
            'statement_id TEXT REFERENCES',
            'statement_id TEXT NOT NULL REFERENCES',
          );
  db.execute('PRAGMA foreign_keys=OFF');
  db.execute('BEGIN');
  try {
    db.execute('DROP TABLE account_reconciliation_drafts');
    db.execute('DROP TABLE bank_reconciliation_cleared_movements');
    db.execute(sql);
    db.execute(
      'INSERT INTO legacy_reconciliations SELECT * FROM bank_reconciliations',
    );
    db.execute('DROP TABLE bank_reconciliations');
    db.execute(
      'ALTER TABLE legacy_reconciliations RENAME TO bank_reconciliations',
    );
    for (final object in objects) {
      db.execute(object);
    }
    db.execute('DROP VIEW IF EXISTS current_expense_intakes');
    db.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    db.execute('DROP TABLE IF EXISTS expense_revision_postings');
    db.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    db.execute('PRAGMA user_version=59');
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    db.execute('PRAGMA foreign_keys=ON');
  }
  expect(
    db
        .select('PRAGMA table_info(bank_reconciliations)')
        .singleWhere((r) => r['name'] == 'statement_id')['notnull'],
    1,
  );
  expect(db.select('PRAGMA foreign_key_check'), isEmpty);
}

void main() {
  test('account drafts retain inputs and originals across restart with owner and revision checks', () async {
    final (f, _, s) = await first();
    final draft = save(f, s, files: [file()]);
    expect(draft.revision, 1);
    expect(() => save(f, s, files: [file()]), throwsStateError);
    expect(
      () => save(f, s, revision: 1, actor: EntityId.random()),
      throwsStateError,
    );
    expect(() => draft.selectedIds.clear(), throwsUnsupportedError);
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    final recovered = f.w.database.readAccountReconciliationDraft(
      f.business,
      'bank',
    )!;
    expect(recovered.selectedIds, draft.selectedIds);
    expect(recovered.attachments.single.originalBytes, file().originalBytes);
    expect(
      f.w.database.readAccountReconciliationDraft(EntityId.random(), 'bank'),
      isNull,
    );
    expect(save(f, s, revision: 1, files: [file()]).revision, 2);
  });
  test('approval commits one immutable account clearance and snapshot, removes only reviewed draft, and retries exactly', () async {
    final (f, _, s) = await first();
    save(f, s, files: [file()]);
    final before = (await f.w.journals()).map((j) => j.entry.id).toList();
    final id = approve(f, s, revision: 1, files: [file()]);
    approve(f, s, request: id, revision: 1, files: [file()]);
    expect(
      () => approve(f, s, request: id, revision: 1, evidence: 'Changed'),
      throwsStateError,
    );
    expect(
      f.w.database.readAccountReconciliationDraft(f.business, 'bank'),
      isNull,
    );
    expect(
      f.w.database.accountReconciliationHistory(f.business, 'bank'),
      hasLength(1),
    );
    expect((await f.w.journals()).map((j) => j.entry.id).toList(), before);
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    final report = f.w.database.reconciliationReportSnapshot(
      f.business,
      id.value,
    );
    expect(report.evidence.isAccountPeriod, isTrue);
    expect(report.evidence.matches, isEmpty);
    expect(
      report.evidence.selectedMovements.single.amount,
      Money.fromMinor(-1000, 'MYR'),
    );
    expect(
      report.evidence.attachments.single.originalBytes,
      file().originalBytes,
    );
    expect(report.classification!.agrees, isTrue);
    expect(report.changes.unchanged, isTrue);
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    expect(raw.select('SELECT * FROM bank_statement_imports'), isEmpty);
    expect(raw.select('SELECT * FROM bank_match_history'), isEmpty);
    expect(
      () => raw.execute('DELETE FROM bank_reconciliations'),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute(
        'UPDATE bank_reconciliation_cleared_movements SET line_index=1',
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute('DELETE FROM bank_reconciliation_ledger_snapshots'),
      throwsA(isA<SqliteException>()),
    );
    final html = reconciliationReportHtml(
      businessId: f.business.value,
      generatedAt: DateTime.now(),
      approval: report.approval,
      evidence: report.evidence,
      ledger: report.ledger,
      classification: report.classification,
      changes: report.changes,
    );
    expect(html, contains('Approved Cleared Transactions'));
    expect(html, isNot(contains('Original File:')));
    expect(html, contains('-RM 10.00'));
  });
  test('stale ledger, draft, owner, missing evidence and mismatched totals reject atomically', () async {
    final (f, _, s) = await first();
    final at = DateTime.utc(2026, 10, 3);
    final before = f.w.database.exportDataArchive(f.business, at);
    expect(() => approve(f, s, actor: EntityId.random()), throwsStateError);
    expect(() => approve(f, s, evidence: ''), throwsArgumentError);
    expect(f.w.database.exportDataArchive(f.business, at), before);
    save(f, s);
    save(f, s, revision: 1);
    expect(() => approve(f, s, revision: 1), throwsStateError);
    expect(() => approve(f, s), throwsStateError);
    await f.post(9, 3, 500);
    expect(() => approve(f, s, revision: 2), throwsStateError);
    expect(
      f.w.database.accountReconciliationHistory(f.business, 'bank'),
      isEmpty,
    );
    expect(
      f.w.database.readAccountReconciliationDraft(f.business, 'bank')!.revision,
      2,
    );
    final fresh = f.review(
      selected: s.review.selected.map((m) => m.id).toSet(),
    );
    approve(f, fresh, revision: 2);
    expect(() => approve(f, fresh), throwsStateError);
  });
  test('imported and account periods share continuity, classification and latest-first reopening', () async {
    final (f, _, s) = await first();
    final september = approve(f, s);
    final october = await f.post(10, 2, -1000);
    final statement = f.w.database.importBankStatement(
      id: EntityId.random(),
      businessId: f.business,
      paymentAccountId: 'bank',
      importedAt: DateTime.now(),
      statement: parse('Date,Description,Amount\n2026-10-02,Fictional,-10.00'),
    );
    f.w.database.acceptStatementMatch(
      businessId: f.business,
      statementId: statement,
      sourceRow: 2,
      journalId: october,
      lineIndex: 0,
      actorId: f.w.identity.ownerId,
      acceptedAt: DateTime.now(),
    );
    final imported = EntityId.random();
    f.w.database.approveStatementReconciliation(
      requestId: imported,
      businessId: f.business,
      statementId: statement,
      actorId: f.w.identity.ownerId,
      approvedAt: DateTime.now(),
      startsOn: DateTime.utc(2026, 10, 1),
      endsOn: DateTime.utc(2026, 10, 31),
      openingBalance: Money.fromMinor(9000, 'MYR'),
      closingBalance: Money.fromMinor(8000, 'MYR'),
      expectedAcceptanceIds: {
        2: f.w.database.statementMatchAcceptanceId(f.business, statement, 2)!,
      },
      expectedPreviousId: september.value,
    );
    expect(
      f.w.database.accountReconciliationHistory(f.business, 'bank'),
      hasLength(2),
    );
    expect(
      f.w.database
          .reconciliationClassification(f.business, imported.value)!
          .cleared,
      hasLength(3),
    );
    final november = f.review(month: 11, opening: 8000, closing: 8000);
    expect(november.reviewAgrees, isTrue);
    expect(november.review.outstanding, isEmpty);
    expect(
      () => f.w.database.reopenStatementReconciliation(
        businessId: f.business,
        completionId: september.value,
        actorId: f.w.identity.ownerId,
        reopenedAt: DateTime.now(),
        reason: 'Fictional correction',
      ),
      throwsStateError,
    );
    f.w.database.reopenStatementReconciliation(
      businessId: f.business,
      completionId: imported.value,
      actorId: f.w.identity.ownerId,
      reopenedAt: DateTime.now(),
      reason: 'Fictional correction',
    );
    f.w.database.reopenStatementReconciliation(
      businessId: f.business,
      completionId: september.value,
      actorId: f.w.identity.ownerId,
      reopenedAt: DateTime.now(),
      reason: 'Fictional correction',
    );
    expect(f.w.database.latestReconciliationId(f.business, 'bank'), isNull);
    expect(
      f.w.database
          .reconciliationEvidence(f.business, september.value)
          .selectedMovements,
      hasLength(1),
    );
  });
  test('imported predecessor can be continued by account clearance without duplicate movements', () async {
    final (f, payment, _) = await first();
    final imported = await f.approveImportedSeptember(payment);
    final october = await f.post(10, 2, -1000);
    final s = f.review(
      month: 10,
      opening: 9000,
      closing: 8000,
      selected: {'${october.value}:0'},
    );
    final manual = approve(f, s);
    expect(s.previousId, imported.value);
    expect(
      f.w.database
          .reconciliationClassification(f.business, manual.value)!
          .cleared,
      hasLength(3),
    );
    expect(
      f
          .review(
            month: 11,
            opening: 8000,
            closing: 8000,
            selected: {'${payment.value}:0'},
          )
          .reviewAgrees,
      isFalse,
    );
  });
  test('injected allocation failure rolls back approval, snapshot, audit and draft deletion', () async {
    final (f, _, s) = await first();
    save(f, s);
    final at = DateTime.utc(2026, 10, 3);
    final before = f.w.database.exportDataArchive(f.business, at);
    final raw = sqlite3.open(f.path);
    raw.execute(
      "CREATE TRIGGER fail_clearance BEFORE INSERT ON bank_reconciliation_cleared_movements BEGIN SELECT RAISE(ABORT,'Injected failure'); END",
    );
    expect(() => approve(f, s, revision: 1), throwsA(isA<SqliteException>()));
    expect(f.w.database.exportDataArchive(f.business, at), before);
    raw.execute('DROP TRIGGER fail_clearance');
    raw.dispose();
    approve(f, s, revision: 1);
  });
  test('populated genuine schema-59 parent upgrades without changing any historical facts or child links', () async {
    final (f, payment, _) = await first();
    await f.approveImportedSeptember(payment);
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    schema59(raw);
    final before = facts(raw);
    raw.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    final upgraded = sqlite3.open(f.path);
    addTearDown(upgraded.dispose);
    expect(facts(upgraded), before);
    expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      upgraded
          .select('PRAGMA table_info(bank_reconciliations)')
          .singleWhere((r) => r['name'] == 'statement_id')['notnull'],
      0,
    );
    expect(
      upgraded.select('PRAGMA user_version').single['user_version'],
      LocalAccountingDatabase.schemaVersion,
    );
    final next = await f.post(10, 2, -1000);
    approve(
      f,
      f.review(
        month: 10,
        opening: 9000,
        closing: 8000,
        selected: {'${next.value}:0'},
      ),
    );
  });
  test('failed parent migration retains schema-59 rows and version and succeeds after conflict is removed', () async {
    final (f, payment, _) = await first();
    await f.approveImportedSeptember(payment);
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    schema59(raw);
    final before = facts(raw);
    raw.execute('CREATE TABLE bank_reconciliations_v60(conflict TEXT)');
    raw.dispose();
    await expectLater(
      AccountingWorkspace.open(f.path),
      throwsA(isA<SqliteException>()),
    );
    final after = sqlite3.open(f.path);
    expect(facts(after), before);
    expect(after.select('PRAGMA user_version').single['user_version'], 59);
    expect(after.select('PRAGMA foreign_key_check'), isEmpty);
    after.execute('DROP TABLE bank_reconciliations_v60');
    after.dispose();
    f.w = await AccountingWorkspace.open(f.path);
  });
  test('data-only restore preserves account facts and missing file bytes honestly; forged evidence rolls back', () async {
    final (f, _, s) = await first();
    final id = approve(f, s, files: [file()]);
    final archive = f.w.database.exportDataArchive(
      f.business,
      DateTime.utc(2026, 10, 3),
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive);
    final evidence = restored.reconciliationEvidence(f.business, id.value);
    expect(evidence.attachments.single.originalBytes, isEmpty);
    expect(evidence.attachments.single.originalSha256, file().originalSha256);
    expect(evidence.isAccountPeriod, isTrue);
    for (final mode in ['allocation', 'fingerprint', 'duplicate', 'source']) {
      final envelope = jsonDecode(archive) as Map<String, dynamic>;
      final data =
          jsonDecode(envelope['data'] as String) as Map<String, dynamic>;
      final tables = data['tables'] as Map;
      final approvals = tables['bank_reconciliations'] as Map;
      final columns = approvals['columns'] as List;
      final row = approvals['rows'][0] as List;
      final pIndex = columns.indexOf('payload');
      final payload = jsonDecode(row[pIndex] as String) as Map<String, dynamic>;
      if (mode == 'allocation') {
        tables['bank_reconciliation_cleared_movements']['rows'] = [];
      }
      if (mode == 'fingerprint') {
        payload['ledgerFingerprint'] = 'forged';
      }
      if (mode == 'duplicate') {
        payload['selected'] = [...payload['selected'], ...payload['selected']];
      }
      if (mode == 'source') {
        final snapshot = tables['bank_reconciliation_ledger_snapshots'] as Map;
        final i = (snapshot['columns'] as List).indexOf('payload');
        final ledger = jsonDecode(
          snapshot['rows'][0][i] as String,
        ) as Map<String, dynamic>;
        ledger['movements'][1]['memo'] = 'Forged posted source memo';
        snapshot['rows'][0][i] = jsonEncode(ledger);
        payload['ledgerFingerprint'] = sha256
            .convert(utf8.encode(jsonEncode(ledger)))
            .toString();
      }
      row[pIndex] = jsonEncode(payload);
      envelope['data'] = jsonEncode(data);
      envelope['sha256'] = sha256
          .convert(utf8.encode(envelope['data'] as String))
          .toString();
      expect(
        () => restored.restoreDataArchive(jsonEncode(envelope)),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
      expect(
        restored
            .reconciliationEvidence(f.business, id.value)
            .selectedMovements
            .single
            .memo,
        s.review.selected.single.memo,
      );
    }
  });
  test('account-cleared journal reversal requires reopening and then uses the existing posting command', () async {
    final (f, payment, s) = await first();
    final completion = approve(f, s);
    final source = (await f.w.journals()).singleWhere(
      (j) => j.entry.id == payment,
    );
    final id = EntityId.random();
    final reversal = source.entry.reversal(
      id: id,
      date: DateTime.utc(2026, 10, 2),
      memo: 'Fictional correction',
    );
    await f.w.database.save(
      StoredJournalEntry(
        entry: reversal,
        metadata: RecordMetadata.initial(
          recordId: id,
          businessId: f.business,
          originDeviceId: f.w.identity.deviceId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    final command = JournalApproval(
      requestId: EntityId.random(),
      businessId: f.business,
      journalId: id,
      expectedRevision: 1,
      actorId: f.w.identity.ownerId,
      approvedAt: DateTime.now(),
    );
    await expectLater(f.w.database.approve(command), throwsStateError);
    f.w.database.reopenStatementReconciliation(
      businessId: f.business,
      completionId: completion.value,
      actorId: f.w.identity.ownerId,
      reopenedAt: DateTime.now(),
      reason: 'Fictional correction',
    );
    expect(
      (await f.w.database.approve(command)).entry.state,
      JournalEntryState.posted,
    );
  });
}
