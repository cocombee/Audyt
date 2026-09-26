import '../../../support/historical_sqlite_fixture.dart';

import 'dart:io';

import 'package:audyt/features/accounting/data/accounting_database.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:sqlite3/sqlite3.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'claim_recognition_reversal_test.dart' show claimFixture;
import 'archive_upgrade_test.dart' show body, envelope;

void main() {
  test(
    'schema 49 upgrade and archive preserve legacy claim payloads and all rows',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'audyt-claimant-upgrade-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/company.sqlite';
      var w = await AccountingWorkspace.open(path);
      addTearDown(() => w.dispose());
      w.claims.saveDraft(ClaimStore.demo().all.first);
      final before = tables(w);
      final archive = body(
        w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.utc(2026, 10),
        ),
      );
      (archive['tables'] as Map).remove('expense_revision_postings');
      (archive['tables'] as Map).remove('expense_revision_drafts');
      archive['schemaVersion'] = 49;
      dropCurrentAccountArchiveFixtureOwner(archive);
      (archive['tables'] as Map).remove('converted_quotation_revisions');
      (archive['tables'] as Map).remove('account_reconciliation_drafts');
      (archive['tables'] as Map).remove(
        'bank_reconciliation_cleared_movements',
      );
      (archive['tables'] as Map).remove('bank_reconciliation_drafts');
      (archive['tables'] as Map).remove('tax_remittance_corrections');
      (archive['tables'] as Map).remove('tax_remittances');
      (archive['tables'] as Map).remove('company_tax_agency_history');
      (archive['tables'] as Map).remove('company_tax_agencies');
      (archive['tables'] as Map).remove('transaction_record_removals');
      w.dispose();
      // v50 only changed the payload marker; v51 adds the removal owner.
      final old = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(old);
      removeTransactionRemovalSchema(old);
      old.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      old.execute('DROP TABLE IF EXISTS tax_remittances');
      old.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      old.execute('DROP TABLE IF EXISTS company_tax_agencies');
      old.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      old.execute('DROP VIEW IF EXISTS current_expense_intakes');
      old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      old.execute('DROP TABLE IF EXISTS expense_revision_postings');
      old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      old.execute('PRAGMA user_version = 49');
      old.dispose();
      w = await AccountingWorkspace.open(path);
      expect(tables(w), before);
      expect(w.claims.all.single.toJson()['version'], 1);
      final raw = sqlite3.open(path);
      expect(
        raw.select('PRAGMA user_version').single['user_version'],
        LocalAccountingDatabase.schemaVersion,
      );
      raw.dispose();
      final recovered = await AccountingWorkspace.emptyRestore(
        '${dir.path}/recovered.sqlite',
        envelope(archive),
      );
      addTearDown(recovered.dispose);
      expect(tables(recovered), before);
      expect(recovered.claims.all.single.claimantIdentity, isNull);
    },
  );
  test(
    'unattributed liability movements reconcile without inventing a claimant',
    () async {
      final f = await claimFixture();
      Future<void> manual(DateTime date, int credit) async {
        await f.w.saveJournal(
          date: date,
          memo: 'Reviewed manual amount due',
          lines: [
            JournalLine.debit(
              accountId: credit < 0 ? f.payable : f.bank,
              amount: Money.fromMinor(credit.abs(), 'MYR'),
            ),
            JournalLine.credit(
              accountId: credit < 0 ? f.bank : f.payable,
              amount: Money.fromMinor(credit.abs(), 'MYR'),
            ),
          ],
        );
        final journal = (await f.w.journals()).singleWhere(
          (j) => j.entry.state == JournalEntryState.draft,
        );
        await f.w.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: f.w.identity.businessId,
            journalId: journal.entry.id,
            expectedRevision: journal.metadata.revision,
            actorId: f.w.identity.ownerId,
            approvedAt: journal.metadata.updatedAt.add(
              const Duration(microseconds: 1),
            ),
          ),
        );
      }

      await manual(DateTime.utc(2026, 8, 31), 500);
      await manual(DateTime.utc(2026, 9, 20), -300);
      await manual(DateTime.utc(2026, 10, 1), 900);
      final before = tables(f.w);
      final report = await f.w.claimantStatements(
        from: DateTime.utc(2026, 9, 10),
        through: DateTime.utc(2026, 9, 30),
      );
      expect(report.statements.single.openingMinor, BigInt.from(1250));
      expect(report.statements.single.closingMinor, BigInt.from(1250));
      expect(report.controls.single.otherOpeningMinor, BigInt.from(500));
      expect(report.controls.single.otherMovementMinor, BigInt.from(-300));
      expect(report.controls.single.otherClosingMinor, BigInt.from(200));
      final other = await f.w.database.readClaimantStatement(
        businessId: EntityId.random(),
        currency: 'MYR',
        from: DateTime.utc(2026, 9),
        through: DateTime.utc(2026, 9, 30),
      );
      expect(other.statements, isEmpty);
      expect(other.awaitingReview, isEmpty);
      expect(other.controls, isEmpty);
      expect(tables(f.w), before);
    },
  );
  test('known claim control retains manual balances before first recognition', () async {
    final f = await claimFixture();
    Future<void> manual(DateTime date, int credit) async {
      await f.w.saveJournal(
        date: date,
        memo: 'Unattributed amount due before first claim',
        lines: [
          JournalLine.debit(
            accountId: credit < 0 ? f.payable : f.bank,
            amount: Money.fromMinor(credit.abs(), 'MYR'),
          ),
          JournalLine.credit(
            accountId: credit < 0 ? f.bank : f.payable,
            amount: Money.fromMinor(credit.abs(), 'MYR'),
          ),
        ],
      );
      final journal = (await f.w.journals()).singleWhere(
        (j) => j.entry.state == JournalEntryState.draft,
      );
      await f.w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: f.w.identity.businessId,
          journalId: journal.entry.id,
          expectedRevision: journal.metadata.revision,
          actorId: f.w.identity.ownerId,
          approvedAt: journal.metadata.updatedAt.add(
            const Duration(microseconds: 1),
          ),
        ),
      );
    }

    // The immutable claim recognition is in September. These August ledger
    // entries still exist when no claimant event falls inside/before the range.
    await manual(DateTime.utc(2026, 8, 1), 900);
    await manual(DateTime.utc(2026, 8, 20), -200);
    final before = tables(f.w);
    Future<void> verify(AccountingWorkspace workspace) async {
      final report = await workspace.claimantStatements(
        from: DateTime.utc(2026, 8, 10),
        through: DateTime.utc(2026, 8, 31),
      );
      expect(report.statements, isEmpty);
      expect(report.controls, hasLength(1));
      final control = report.controls.single;
      expect(control.ledgerBalance.account.id, f.payable);
      expect(control.attributedOpeningMinor, BigInt.zero);
      expect(control.attributedMovementMinor, BigInt.zero);
      expect(control.otherOpeningMinor, BigInt.from(900));
      expect(control.otherMovementMinor, BigInt.from(-200));
      expect(control.otherClosingMinor, BigInt.from(700));
      expect(report.ledger.liabilities, BigInt.from(700));
      expect(report.ledger.periodProfit, BigInt.zero);
      expect(report.ledger.balanceSheetDifference, BigInt.zero);
      expect(tables(workspace), before);
    }

    await verify(f.w);
    final recovered = await AccountingWorkspace.emptyRestore(
      '${File(f.path).parent.path}/earlier-claim-control.sqlite',
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        DateTime.utc(2026, 10),
      ),
    );
    addTearDown(recovered.dispose);
    await verify(recovered);
  });
  test('stable claimant identity, dated recognition/payment, legacy separation and recovery', () async {
    final dir = Directory.systemTemp.createTempSync(
      'audyt-claimant-statement-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/company.sqlite';
    var w = await AccountingWorkspace.open(path);
    addTearDown(() => w.dispose());
    for (final a in [
      ('1000', AccountType.asset),
      ('2100', AccountType.liability),
      ('5000', AccountType.expense),
    ]) {
      await w.createAccount(code: a.$1, name: a.$1, type: a.$2);
    }
    final chart = await w.accounts();
    EntityId account(String c) =>
        chart.singleWhere((a) => a.account.code == c).account.id;
    w.payees.add(id: 'employee-a', name: 'Same Name', type: PayeeType.staff);
    w.payees.add(id: 'director-b', name: 'Same Name', type: PayeeType.director);
    Claim draft(String? person, int day) => Claim.fromJson({
      ...ClaimStore.demo().all.first.toJson(),
      'id': EntityId.random().value,
      'claimantName': 'Same Name',
      'incurredOn': DateTime.utc(2026, 9, day).toIso8601String(),
      if (person != null) ...{
        'version': 2,
        'claimantIdentity': {
          'payeeId': person,
          'type': person == 'employee-a' ? 'staff' : 'director',
        },
      },
    });
    final a = draft('employee-a', 1),
        b = draft('director-b', 2),
        legacy1 = draft(null, 3),
        legacy2 = draft(null, 4);
    for (final c in [a, b, legacy1, legacy2]) {
      w.claims.saveAndSubmit(c);
      w.approveClaim(
        requestId: EntityId.random(),
        reviewedClaim: w.claims.byId(c.id)!,
        expenseAccountId: account('5000'),
        liabilityAccountId: account('2100'),
        approvedAt: DateTime.utc(2026, 9, 10),
      );
    }
    w.payees.save(
      const Payee(
        id: 'employee-a',
        name: 'Renamed Employee',
        type: PayeeType.staff,
      ),
    );
    final pending = draft('employee-a', 20);
    expect(() => w.claims.saveDraft(pending), throwsStateError);
    final linkedPending = Claim.fromJson({
      ...pending.toJson(),
      'claimantName': 'Renamed Employee',
    });
    w.claims.saveAndSubmit(linkedPending);
    final foreign = Claim.fromJson({
      ...pending.toJson(),
      'claimantIdentity': {
        'payeeId': 'foreign-company-person',
        'type': 'staff',
      },
    });
    final beforeRejected = tables(w);
    expect(() => w.claims.saveDraft(foreign), throwsStateError);
    expect(tables(w), beforeRejected);
    w.settleClaims(
      requestId: EntityId.random(),
      reviewedClaims: [w.claims.byId(a.id)!],
      bankAccountId: account('1000'),
      paymentReference: 'REIMBURSE-A',
      paidAt: DateTime.utc(2026, 9, 15),
    );
    final before = tables(w);
    final report = await w.claimantStatements(
      from: DateTime.utc(2026, 9, 10),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(report.statements, hasLength(4));
    final employee = report.statements.singleWhere(
      (s) => s.identity?.payeeId == 'employee-a',
    );
    expect(employee.claimantName, 'Same Name');
    expect(employee.openingMinor, BigInt.from(1250));
    expect(employee.movementMinor, BigInt.from(-1250));
    expect(employee.closingMinor, BigInt.zero);
    expect(employee.events.single.reference, 'REIMBURSE-A');
    expect(
      report.statements
          .singleWhere((s) => s.identity?.payeeId == 'director-b')
          .closingMinor,
      BigInt.from(1250),
    );
    expect(report.statements.where((s) => s.identity == null), hasLength(2));
    expect(report.awaitingReview.single.id, linkedPending.id);
    expect(report.controls.single.attributedClosingMinor, BigInt.from(3750));
    expect(report.controls.single.otherClosingMinor, BigInt.zero);
    expect(tables(w), before);
    final old = await w.claimantStatements(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 14),
    );
    expect(
      old.statements
          .singleWhere((s) => s.identity?.payeeId == 'employee-a')
          .closingMinor,
      BigInt.from(1250),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(w.claims.byId(a.id)!.claimantIdentity!.payeeId, 'employee-a');
    expect(
      (await w.claimantStatements(
        from: DateTime.utc(2026, 9, 10),
        through: DateTime.utc(2026, 9, 30),
      )).controls.single.attributedClosingMinor,
      BigInt.from(3750),
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10),
    );
    w.dispose();
    w = await AccountingWorkspace.emptyRestore(
      '${dir.path}/restored.sqlite',
      archive,
    );
    final recovered = await w.claimantStatements(
      from: DateTime.utc(2026, 9, 10),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(recovered.controls.single.attributedClosingMinor, BigInt.from(3750));
  });

  test(
    'version-one claims remain byte-compatible and malformed identities fail',
    () {
      final old = ClaimStore.demo().all.first;
      expect(Claim.fromJson(old.toJson()).toJson(), old.toJson());
      expect(old.claimantIdentity, isNull);
      for (final identity in [
        {'payeeId': ' ', 'type': 'staff'},
        {'payeeId': 'supplier', 'type': 'supplier'},
        null,
      ]) {
        expect(
          () => Claim.fromJson({
            ...old.toJson(),
            'version': 2,
            'claimantIdentity': identity,
          }),
          throwsFormatException,
        );
      }
    },
  );
}
