import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_claim_source.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'archive_upgrade_test.dart' show body, envelope;
import 'claim_receipt_tax_test.dart' show fixture, report, Fixture;

EntityId approve(Fixture f, {EntityId? request}) {
  final claim = f.claim();
  f.w.claims.saveAndSubmit(claim);
  return f.w.approveClaim(
    reviewedClaim: f.w.claims.byId(claim.id)!,
    requestId: request ?? EntityId.random(),
    liabilityAccountId: f.accounts['2100']!,
    approvedAt: DateTime.utc(2026, 9, 15),
  );
}

void main() {
  test('approved mixed receipt Claim creates one Expense with exact frozen facts and no second posting', () async {
    final dir = Directory.systemTemp.createTempSync('approved-claim-expense-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(path: path);
    final w = f.w;
    final journal = approve(f);
    final claim = w.claims.all.single;
    final saved = (await w.expense(journal))!;
    final draft = saved.draft;
    expect(saved.summary.isPosted, isTrue);
    expect(saved.summary.journalId, journal);
    expect(await w.journals(), hasLength(1));
    expect(await w.expenses(), hasLength(1));
    expect(draft.claimSource!.claimId, claim.id);
    expect(draft.claimSource!.claimantName, claim.claimantName);
    expect(draft.claimSource!.claimantId, claim.claimantIdentity?.payeeId);
    expect(draft.claimSource!.claimantType, claim.claimantIdentity?.type.name);
    expect(draft.paymentAccountId, isNull);
    expect(draft.claimSource!.liabilityAccountId, f.accounts['2100']);
    expect(draft.taxMode, ExpenseClaimSource.mixedBasis);
    expect(draft.taxTotals!.net.minorUnits, 17000);
    expect(draft.taxTotals!.tax.minorUnits, 1200);
    expect(draft.taxTotals!.total.minorUnits, 18200);
    expect(draft.lines.map((l) => l.toJson()), [
      for (final r in claim.receipts)
        for (final l in r.lines) l.item.toJson(),
    ]);
    expect(
      draft.attachments.single.originalSha256,
      claim.attachments.single.originalSha256,
    );
    expect((await report(w)).rows, hasLength(3));
    expect(
      w.database.readVoucherSources(w.identity.businessId),
      isEmpty,
      reason: 'Recognition is not a second direct payment source.',
    );
    await expectLater(
      w.database.saveExpenseIntake(
        id: EntityId.random(),
        businessId: w.identity.businessId,
        draft: draft,
        createdAt: DateTime.utc(2026, 9, 16),
      ),
      throwsStateError,
    );
    await expectLater(
      w.updateExpenseIntake(id: journal, expected: draft, replacement: draft),
      throwsStateError,
    );
    expect(
      () => w.setExpenseIntakeArchived(
        id: journal,
        expectedRevision: saved.summary.revision,
        archived: true,
      ),
      throwsStateError,
    );
    w.dispose();
    final reopened = await AccountingWorkspace.open(path);
    addTearDown(reopened.dispose);
    expect((await reopened.expense(journal))!.draft.toJson(), draft.toJson());
    expect(await reopened.journals(), hasLength(1));
    expect((await report(reopened)).rows, hasLength(3));
  });

  test('Expense identity collision rolls back Claim approval and its entire journal', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final id = EntityId.random();
    const ordinary = RecordExpenseDraft(
      amount: '1.00',
      date: '01-09-2026',
      payee: 'Existing Supplier',
      paymentAccount: 'Existing Account',
      category: 'Office',
      tax: 'Not Recorded',
      customer: '',
      billable: false,
      dimensions: '',
      itemOrSplitDetails: '',
      notes: '',
      submissionId: 'existing-expense',
    );
    await f.w.database.saveExpenseIntake(
      id: id,
      businessId: f.w.identity.businessId,
      draft: ordinary,
      createdAt: DateTime.utc(2026, 9, 1),
    );
    expect(() => approve(f, request: id), throwsFormatException);
    expect(await f.w.journals(), isEmpty);
    expect(f.w.claims.all.single.status, ClaimStatus.submitted);
    expect((await f.w.expense(id))!.draft.toJson(), ordinary.toJson());
  });

  test('data-only recovery retains Claim Expense provenance and rejects changed, missing or duplicate links', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final id = approve(f);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 9, 16),
    );
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    db.restoreDataArchive(archive);
    final saved = (await db.getExpenseIntake(f.w.identity.businessId, id))!;
    expect(saved.draft.claimSource!.recognitionId, id);
    expect(saved.draft.taxTotals!.total.minorUnits, 18200);
    expect(saved.draft.attachments.single.originalBytes, isEmpty);
    for (final mutate in [
      'claimant',
      'claimId',
      'basis',
      'amount',
      'missing',
      'duplicate',
      'hideSource',
    ]) {
      final data = body(archive);
      final table = (data['tables'] as Map)['expense_intakes'] as Map;
      final columns = (table['columns'] as List).cast<String>();
      final rows = table['rows'] as List;
      final row = rows.single as List;
      final payload = jsonDecode(
        row[columns.indexOf('payload')] as String,
      ) as Map<String, dynamic>;
      final source = payload['claimSource'] as Map;
      switch (mutate) {
        case 'claimant':
          source['claimantName'] = 'Someone Else';
        case 'claimId':
          source['claimId'] = EntityId.random().value;
        case 'basis':
          (source['lineBases'] as Map).updateAll((k, v) => 'Inclusive');
        case 'amount':
          payload['amount'] = '183.00';
        case 'missing':
          rows.clear();
        case 'duplicate':
          final other = List<Object?>.from(row);
          other[columns.indexOf('id')] = EntityId.random().value;
          other[columns.indexOf('request_id')] = 'another-request';
          rows.add(other);
        case 'hideSource':
          payload.remove('claimSource');
          payload['version'] = 2;
          payload['taxMode'] = 'Exclusive';
      }
      if (rows.isNotEmpty) {
        row[columns.indexOf('payload')] = jsonEncode(payload);
      }
      final rejected = LocalAccountingDatabase.inMemory();
      try {
        expect(
          () => rejected.restoreDataArchive(envelope(data)),
          throwsA(isA<Exception>()),
          reason: mutate,
        );
        expect(
          () => rejected.exportDataArchive(
            f.w.identity.businessId,
            DateTime.utc(2026, 9, 16),
          ),
          throwsStateError,
          reason: 'Recovery must roll back: $mutate',
        );
      } finally {
        rejected.close();
      }
    }
  });

  test('genuine schema 56 upgrade backfills from immutable recognition without rewriting journals', () async {
    final dir = Directory.systemTemp.createTempSync('claim-expense-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(path: path);
    final id = approve(f);
    final before =
        body(
              f.w.database.exportDataArchive(
                f.w.identity.businessId,
                DateTime.utc(2026, 9, 16),
              ),
            )['tables']
            as Map;
    final expected = (await f.w.expense(id))!.draft.toJson();
    f.w.dispose();
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    old.execute('DELETE FROM expense_intakes');
    old.execute(
      'ALTER TABLE bank_reconciliation_drafts DROP COLUMN attachments',
    );
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version=56');
    old.dispose();
    final upgraded = await AccountingWorkspace.open(path);
    addTearDown(upgraded.dispose);
    final after =
        body(
              upgraded.database.exportDataArchive(
                upgraded.identity.businessId,
                DateTime.utc(2026, 9, 16),
              ),
            )['tables']
            as Map;
    expect(after['journal_entries'], before['journal_entries']);
    expect(after['journal_lines'], before['journal_lines']);
    expect((await upgraded.expense(id))!.draft.toJson(), expected);
    expect(await upgraded.expenses(), hasLength(1));
    expect((await report(upgraded)).rows, hasLength(3));
  });
}
