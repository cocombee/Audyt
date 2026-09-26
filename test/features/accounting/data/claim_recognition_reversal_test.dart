import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import '../../../app/restored_page_routes_test.dart' show tables;

Future<
  ({
    AccountingWorkspace w,
    String path,
    Claim approved,
    EntityId source,
    EntityId expense,
    EntityId payable,
    EntityId bank,
  })
>
claimFixture() async {
  final dir = Directory.systemTemp.createTempSync('claim-reversal-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/books.sqlite';
  final w = await AccountingWorkspace.open(path);
  addTearDown(w.dispose);
  for (final item in [
    ('5000', AccountType.expense),
    ('2100', AccountType.liability),
    ('1000', AccountType.asset),
  ]) {
    await w.createAccount(code: item.$1, name: item.$1, type: item.$2);
  }
  final accounts = await w.accounts();
  EntityId id(String code) =>
      accounts.singleWhere((a) => a.account.code == code).account.id;
  final draft = Claim.fromJson({
    ...ClaimStore.demo().all.first.toJson(),
    'incurredOn': '2026-09-01T00:00:00.000Z',
  });
  w.claims.saveAndSubmit(draft);
  final source = w.approveClaim(
    reviewedClaim: w.claims.byId(draft.id)!,
    requestId: EntityId.random(),
    expenseAccountId: id('5000'),
    liabilityAccountId: id('2100'),
    approvedAt: DateTime.utc(2026, 9, 14),
  );
  return (
    w: w,
    path: path,
    approved: w.claims.byId(draft.id)!,
    source: source,
    expense: id('5000'),
    payable: id('2100'),
    bank: id('1000'),
  );
}

Future<int> net(AccountingWorkspace w, EntityId account) async =>
    (await w.journals())
        .where((j) => j.entry.state == JournalEntryState.posted)
        .expand((j) => j.entry.lines)
        .where((l) => l.accountId == account)
        .fold<int>(
          0,
          (sum, l) =>
              sum + (l.isDebit ? l.amount.minorUnits : -l.amount.minorUnits),
        );

Future<void> expectClaimReports(
  AccountingWorkspace w, {
  required int expense,
  required int payable,
  required int bank,
  int year = 2026,
  int? periodExpense,
}) async {
  final report = await w.report(
    from: DateTime.utc(year),
    through: DateTime.utc(year, 12, 31),
  );
  expect(report.revenue, BigInt.zero);
  expect(report.expenses, BigInt.from(periodExpense ?? expense));
  expect(report.periodProfit, BigInt.from(-(periodExpense ?? expense)));
  expect(report.assets, BigInt.from(bank));
  expect(report.liabilities, BigInt.from(payable));
  expect(report.totalEquity, BigInt.from(-expense));
  expect(report.balanceSheetDifference, BigInt.zero);
  expect(report.trialBalanceDebits, BigInt.from(expense));
  expect(report.trialBalanceCredits, BigInt.from(expense));
  expect(report.isBalanced, isTrue);
}

void main() {
  test('return/correct/resubmit/reapprove/pay preserves immutable recognition cycles, restart and archive', () async {
    final f = await claimFixture();
    var w = f.w;
    final originalRoot = tables(w)['claim_postings'];
    await expectClaimReports(
      w,
      expense: f.approved.amount.minorUnits,
      payable: f.approved.amount.minorUnits,
      bank: 0,
    );
    final request = EntityId.random();
    EntityId reverse() => w.reverseClaimRecognition(
      reviewedClaim: f.approved,
      requestId: request,
      expectedRecognitionJournalId: f.source,
      decision: ClaimRecognitionDecision.returnForCorrection,
      reversedOn: DateTime.utc(2026, 9, 15),
      reason: 'Correct expense amount',
      changedAt: DateTime.utc(2026, 9, 15, 12),
    );
    expect(reverse(), request);
    final returned = w.claims.byId(f.approved.id)!;
    expect(returned.status, ClaimStatus.returned);
    expect(await net(w, f.expense), 0);
    expect(await net(w, f.payable), 0);
    expect(w.activeClaimRecognitionId(returned.id), isNull);
    await expectClaimReports(w, expense: 0, payable: 0, bank: 0);
    final after = tables(w);
    expect(reverse(), request);
    expect(tables(w), after);
    final corrected = Claim.fromJson({
      ...returned.toJson(),
      'amountMinor': 21000,
      'businessPurpose': 'Corrected actual cost',
    });
    w.claims.saveDraft(corrected, expectedCurrent: returned);
    w.claims.submit(corrected.id);
    final cycle = w.approveClaim(
      reviewedClaim: w.claims.byId(corrected.id)!,
      requestId: EntityId.random(),
      expenseAccountId: f.expense,
      liabilityAccountId: f.payable,
      approvedAt: DateTime.utc(2026, 9, 16),
    );
    expect(w.activeClaimRecognitionId(corrected.id), cycle);
    expect(tables(w)['claim_postings'], originalRoot);
    expect((tables(w)['claim_posting_cycles']['rows'] as List), hasLength(1));
    expect(w.claimRecognitionSnapshots.keys, containsAll([f.source, cycle]));
    expect(await net(w, f.expense), 21000);
    expect(await net(w, f.payable), -21000);
    await expectClaimReports(w, expense: 21000, payable: 21000, bank: 0);
    final claimantBeforePayment = await w.claimantStatements(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(claimantBeforePayment.statements.single.events, hasLength(3));
    expect(
      claimantBeforePayment.statements.single.closingMinor,
      BigInt.from(21000),
    );
    expect(
      claimantBeforePayment.controls.single.otherClosingMinor,
      BigInt.zero,
    );
    final taxActivity = await w.taxActivity(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(
      taxActivity.rows,
      hasLength(3),
      reason: 'Both original and corrected recognition cycles are retained.',
    );
    expect(taxActivity.unresolved, hasLength(3));
    expect(
      taxActivity.rows.where((r) => r.journalId == f.source).single.grossMinor,
      BigInt.from(f.approved.amount.minorUnits),
    );
    expect(
      taxActivity.rows.where((r) => r.isReversal).single.grossMinor,
      -BigInt.from(f.approved.amount.minorUnits),
    );
    expect(
      taxActivity.rows.fold(BigInt.zero, (sum, r) => sum + r.grossMinor),
      BigInt.from(21000),
    );
    final approved = w.claims.byId(corrected.id)!;
    // An old reviewed approval cannot target a later recognition, including an ABA status cycle.
    final beforeStale = tables(w);
    expect(
      () => w.reverseClaimRecognition(
        reviewedClaim: approved,
        requestId: EntityId.random(),
        expectedRecognitionJournalId: f.source,
        decision: ClaimRecognitionDecision.voidClaim,
        reversedOn: DateTime.utc(2026, 9, 17),
        reason: 'Stale review',
        changedAt: DateTime.utc(2026, 9, 17),
      ),
      throwsStateError,
    );
    expect(tables(w), beforeStale);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 17),
    );
    final copiedPath = '${File(f.path).parent.path}/copy.sqlite';
    final copy = await AccountingWorkspace.emptyRestore(copiedPath, archive);
    addTearDown(copy.dispose);
    final historical = copy.claims.byId(approved.id)!;
    expect(historical.submissionErrors, isNotEmpty);
    expect(copy.activeClaimRecognitionId(historical.id), cycle);
    copy.settleClaims(
      reviewedClaims: [historical],
      requestId: EntityId.random(),
      bankAccountId: f.bank,
      paymentReference: 'COPY-PAY',
      paidAt: DateTime.utc(2026, 9, 18),
    );
    expect(await net(copy, f.payable), 0);
    expect(await net(copy, f.expense), 21000);
    await expectClaimReports(copy, expense: 21000, payable: 0, bank: -21000);
    final restoredClaimant = await copy.claimantStatements(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(restoredClaimant.statements.single.events, hasLength(4));
    expect(restoredClaimant.statements.single.closingMinor, BigInt.zero);
    w.settleClaims(
      reviewedClaims: [approved],
      requestId: EntityId.random(),
      bankAccountId: f.bank,
      paymentReference: 'PAY-CORRECTED',
      paidAt: DateTime.utc(2026, 9, 18),
    );
    expect(await net(w, f.payable), 0);
    expect(await net(w, f.bank), -21000);
    expect(await net(w, f.expense), 21000);
    await expectClaimReports(w, expense: 21000, payable: 0, bank: -21000);
    final finalTables = tables(w);
    w.dispose();
    w = await AccountingWorkspace.open(f.path);
    addTearDown(w.dispose);
    expect(tables(w), finalTables);
    expect(w.claims.byId(approved.id)!.status, ClaimStatus.paid);
    await expectClaimReports(w, expense: 21000, payable: 0, bank: -21000);
    await expectClaimReports(
      w,
      year: 2027,
      expense: 21000,
      payable: 0,
      bank: -21000,
      periodExpense: 0,
    );
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    for (final table in [
      'claim_postings',
      'claim_posting_cycles',
      'claim_posting_reversals',
    ]) {
      expect(
        () => raw.execute('DELETE FROM $table'),
        throwsA(isA<SqliteException>()),
      );
    }
  });

  for (final failure in [
    'unauthorized',
    'foreign company',
    'wrong source',
    'stale payload',
    'earlier date',
    'closed period',
    'inactive account',
    'paid',
    'request reused',
    'injected failure',
  ]) {
    test('recognized claim correction rejects $failure atomically', () async {
      final f = await claimFixture();
      final w = f.w;
      final request = EntityId.random();
      if (failure == 'closed period') {
        await w.database.closeThrough(
          businessId: w.identity.businessId,
          date: DateTime.utc(2026, 9, 15),
          actorId: w.identity.ownerId,
          changedAt: DateTime.utc(2026, 9, 16),
          reason: 'Period review',
        );
      }
      final raw = sqlite3.open(f.path);
      addTearDown(raw.dispose);
      if (failure == 'inactive account') {
        raw.execute("UPDATE accounts SET status='archived' WHERE id=?", [
          f.expense.value,
        ]);
      }
      if (failure == 'paid') {
        w.settleClaims(
          reviewedClaims: [f.approved],
          requestId: EntityId.random(),
          bankAccountId: f.bank,
          paymentReference: 'PAID',
          paidAt: DateTime.utc(2026, 9, 15),
        );
      }
      EntityId attempt({String reason = 'Correct claim'}) =>
          w.database.reverseClaimRecognition(
            businessId: failure == 'foreign company'
                ? EntityId.random()
                : w.identity.businessId,
            actorId: failure == 'unauthorized'
                ? EntityId.random()
                : w.identity.ownerId,
            requestId: request,
            reviewedClaim: failure == 'stale payload'
                ? Claim.fromJson({
                    ...f.approved.toJson(),
                    'vendorName': 'Unreviewed',
                  })
                : f.approved,
            expectedRecognitionJournalId: failure == 'wrong source'
                ? EntityId.random()
                : f.source,
            decision: ClaimRecognitionDecision.voidClaim,
            reversedOn: failure == 'earlier date'
                ? DateTime.utc(2026, 8, 31)
                : DateTime.utc(2026, 9, 15),
            reason: reason,
            changedAt: DateTime.utc(2026, 9, 16),
          );
      if (failure == 'request reused') attempt();
      if (failure == 'injected failure') {
        raw.execute(
          "CREATE TRIGGER fail_claim_correction BEFORE INSERT ON claim_posting_reversals BEGIN SELECT RAISE(ABORT,'injected reversal failure'); END",
        );
      }
      final before = tables(w);
      expect(
        () => attempt(
          reason: failure == 'request reused'
              ? 'Different work'
              : 'Correct claim',
        ),
        failure == 'injected failure'
            ? throwsA(isA<SqliteException>())
            : throwsStateError,
      );
      expect(tables(w), before);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('void uses the exact linked reversal, cannot pay, generic manual reversal stays blocked', () async {
    final f = await claimFixture();
    final w = f.w;
    final original = (await w.journals()).single;
    final manual = original.entry.reversal(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 15),
      memo: 'Unlinked reversal',
    );
    await w.database.save(
      StoredJournalEntry(
        entry: manual,
        metadata: RecordMetadata.initial(
          recordId: manual.id,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 15),
        ),
      ),
    );
    final before = tables(w);
    await expectLater(
      w.database.approve(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: manual.id,
          expectedRevision: 1,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.utc(2026, 9, 16),
        ),
      ),
      throwsStateError,
    );
    expect(tables(w), before);
    w.reverseClaimRecognition(
      reviewedClaim: f.approved,
      requestId: EntityId.random(),
      expectedRecognitionJournalId: f.source,
      decision: ClaimRecognitionDecision.voidClaim,
      reversedOn: DateTime.utc(2026, 9, 16),
      reason: 'Claim cancelled',
      changedAt: DateTime.utc(2026, 9, 16),
    );
    expect(w.claims.byId(f.approved.id)!.status, ClaimStatus.voided);
    expect(await net(w, f.expense), 0);
    expect(await net(w, f.payable), 0);
    await expectClaimReports(w, expense: 0, payable: 0, bank: 0);
    expect(
      () => w.settleClaims(
        reviewedClaims: [f.approved],
        requestId: EntityId.random(),
        bankAccountId: f.bank,
        paymentReference: 'NO-PAY',
        paidAt: DateTime.utc(2026, 9, 17),
      ),
      throwsStateError,
    );
  });

  test('version 37 upgrade preserves every existing row and adds empty immutable correction history', () async {
    final f = await claimFixture();
    final old = tables(f.w);
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    dropCurrentQuotationFixtureOwner(raw);
    removeExpenseRemovalSchema(raw);
    raw.execute('DROP VIEW all_claim_postings');
    raw.execute('DROP TABLE claim_posting_reversals');
    raw.execute('DROP TABLE claim_posting_cycles');
    raw.execute('DROP TABLE IF EXISTS catalogue_items');
    raw.execute('DROP TABLE IF EXISTS catalogue_categories');
    raw.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    raw.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    raw.execute('DROP TABLE IF EXISTS recurring_document_template_history');
    raw.execute('DROP TABLE IF EXISTS recurring_document_templates');
    raw.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_rates');
    raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    raw.execute('DROP TABLE IF EXISTS tax_remittances');
    raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=37');
    raw.dispose();
    final w = await AccountingWorkspace.open(f.path);
    addTearDown(w.dispose);
    final upgraded = tables(w);
    for (final name in old.keys.where((n) => !n.startsWith('claim_posting_'))) {
      expect(upgraded[name], old[name], reason: name);
    }
    expect(upgraded['claim_posting_cycles']['rows'], isEmpty);
    expect(upgraded['claim_posting_reversals']['rows'], isEmpty);
    expect(w.activeClaimRecognitionId(f.approved.id), f.source);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 17),
    );
    expect(
      jsonDecode(jsonDecode(archive)['data'])['schemaVersion'],
      LocalAccountingDatabase.schemaVersion,
    );
  });
}
