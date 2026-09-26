import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/tax_activity_report.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_receipt.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'archive_upgrade_test.dart' show body, envelope, historical;

class Fixture {
  Fixture(this.w, this.accounts, this.code);
  final AccountingWorkspace w;
  final Map<String, EntityId> accounts;
  final CompanyTaxRate code;
  Claim claim({CompanyTaxRate? rate, bool plain = false}) {
    final original = ClaimStore.demo().all.first;
    final document = original.attachments.single.originalId;
    final tax = rate ?? code;
    final receipts = [
      ClaimReceipt(
        id: 'receipt-a',
        merchant: 'Sample Supplier A',
        date: DateTime.utc(2026, 9, 10),
        currency: 'MYR',
        taxMode: 'Exclusive',
        originalDocumentIds: [document],
        lines: [
          ClaimReceiptLine(
            expenseAccountId: accounts['5000']!,
            item: ExpenseDraftLine(
              id: 'receipt-a-taxed',
              category: 'Travel',
              description: 'Business service',
              tax: tax.choice,
              taxSnapshot: tax,
              amount: '100',
            ),
          ),
          ClaimReceiptLine(
            expenseAccountId: accounts['1500']!,
            item: const ExpenseDraftLine(
              id: 'receipt-a-asset',
              category: 'Equipment',
              description: 'Equipment purchase',
              tax: '0',
              amount: '20',
            ),
          ),
        ],
      ),
      ClaimReceipt(
        id: 'receipt-b',
        merchant: 'Sample Supplier B',
        date: DateTime.utc(2026, 9, 12),
        currency: 'MYR',
        taxMode: 'Inclusive',
        originalDocumentIds: [document],
        lines: [
          ClaimReceiptLine(
            expenseAccountId: accounts['5100']!,
            item: ExpenseDraftLine(
              id: 'receipt-b-taxed',
              category: 'Printing',
              description: 'Printed material',
              tax: tax.choice,
              taxSnapshot: tax,
              amount: '54',
            ),
          ),
        ],
      ),
    ];
    final total = receipts.fold(
      Money.zero('MYR'),
      (sum, r) => sum + r.totals.total,
    );
    return Claim.fromJson({
      ...original.toJson(),
      'id': EntityId.random().value,
      'incurredOn': '2026-09-14T00:00:00.000Z',
      if (!plain) 'version': 3,
      'amountMinor': plain ? original.amount.minorUnits : total.minorUnits,
      if (!plain) 'receipts': receipts.map((r) => r.toJson()).toList(),
    });
  }
}

Future<Fixture> fixture({String path = ':memory:'}) async {
  final w = await AccountingWorkspace.open(path);
  final ids = <String, EntityId>{};
  for (final (code, type) in [
    ('1000', AccountType.asset),
    ('1500', AccountType.asset),
    ('2100', AccountType.liability),
    ('2200', AccountType.liability),
    ('5000', AccountType.expense),
    ('5100', AccountType.expense),
  ]) {
    await w.createAccount(code: code, name: code, type: type);
    ids[code] = (await w.accounts())
        .singleWhere((a) => a.account.code == code)
        .account
        .id;
  }
  final rate = w.saveTaxRate(
    CompanyTaxRate(
      id: EntityId.random(),
      name: 'Service Tax',
      percent: '8',
      application: TaxApplication.purchases,
      effectiveFrom: DateTime.utc(2026),
      accountId: ids['2200']!,
    ),
  );
  return Fixture(w, ids, rate);
}

Future<TaxActivityReport> report(AccountingWorkspace w) => w.taxActivity(
  from: DateTime.utc(2026, 9),
  through: DateTime.utc(2026, 9, 30),
);
void main() {
  test('mixed receipts reconcile exact gross cost, liability, P&L and tax without input credit', () async {
    final f = await fixture();
    final w = f.w;
    addTearDown(w.dispose);
    final claim = f.claim();
    expect(claim.amount.minorUnits, 18200);
    expect(claim.toJson()['version'], 3);
    w.claims.saveAndSubmit(claim);
    expect((await report(w)).rows, isEmpty);
    final submitted = w.claims.byId(claim.id)!;
    final request = EntityId.random();
    final at = DateTime.utc(2026, 9, 15);
    EntityId post({EntityId? override}) => w.approveClaim(
      reviewedClaim: submitted,
      requestId: request,
      expenseAccountId: override,
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: at,
    );
    expect(() => post(override: f.accounts['5000']), throwsStateError);
    expect(await w.journals(), isEmpty);
    expect(post(), request);
    expect(post(), request);
    final ledger = await w.report(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(ledger.expenses, BigInt.from(16200));
    expect(ledger.assets, BigInt.from(2000));
    expect(ledger.liabilities, BigInt.from(18200));
    expect(ledger.balanceSheetDifference, BigInt.zero);
    final activity = await report(w);
    expect(activity.rows, hasLength(3));
    expect(activity.unresolved, isEmpty);
    expect(
      activity.rows.fold<BigInt>(BigInt.zero, (a, r) => a + r.grossMinor),
      BigInt.from(18200),
    );
    expect(
      activity.rows.fold<BigInt>(BigInt.zero, (a, r) => a + r.taxMinor!),
      BigInt.from(1200),
    );
    final taxBalance = ledger.rows.singleWhere(
      (r) => r.account.id == f.accounts['2200'],
    );
    expect(taxBalance.endingNetDebit, BigInt.zero);
    expect(
      w.claims.byId(claim.id)!.receipts.map((r) => r.toJson()).toList(),
      claim.receipts.map((r) => r.toJson()).toList(),
    );
  });
  test('new selection rejects stale, foreign, expired and fabricated code snapshots; retained edits survive deactivation', () async {
    final f = await fixture();
    final w = f.w;
    addTearDown(w.dispose);
    final retained = f.claim();
    w.claims.saveDraft(retained);
    w.saveTaxRate(
      CompanyTaxRate.fromJson({
        ...f.code.toJson(),
        'active': false,
        'percent': '6',
      }),
    );
    expect(() => w.claims.saveDraft(f.claim()), throwsStateError);
    final edited = Claim.fromJson({
      ...retained.toJson(),
      'businessPurpose': 'Reviewed purpose',
    });
    w.claims.saveDraft(edited);
    w.claims.submit(edited.id);
    w.approveClaim(
      reviewedClaim: w.claims.byId(edited.id)!,
      requestId: EntityId.random(),
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    expect(
      (await report(w)).rows
          .where((r) => r.code != null)
          .every((r) => r.code?.revision == 1),
      true,
    );
    final invented = CompanyTaxRate.fromJson({
      ...f.code.toJson(),
      'percent': '5',
    });
    expect(() => w.claims.saveDraft(f.claim(rate: invented)), throwsStateError);
    final foreign = await fixture();
    addTearDown(foreign.w.dispose);
    expect(
      () => w.claims.saveDraft(f.claim(rate: foreign.code)),
      throwsStateError,
    );
    final expired = w.saveTaxRate(
      CompanyTaxRate(
        id: EntityId.random(),
        name: 'SST',
        percent: '5',
        application: TaxApplication.purchases,
        effectiveFrom: DateTime.utc(2026),
        effectiveThrough: DateTime.utc(2026, 9, 11),
        accountId: f.accounts['2200']!,
      ),
    );
    expect(() => w.claims.saveDraft(f.claim(rate: expired)), throwsStateError);
  });
  test('receipt tax and cost facts survive settlement, restart and data-only recovery without duplicate expense', () async {
    final dir = Directory.systemTemp.createTempSync('claim-receipt-tax-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(path: path);
    var w = f.w;
    w.payees.add(
      id: 'director-a',
      name: 'Director A',
      type: PayeeType.director,
    );
    final claim = Claim.fromJson({
      ...f.claim().toJson(),
      'claimantName': 'Director A',
      'claimantIdentity': {'payeeId': 'director-a', 'type': 'director'},
    });
    w.claims.saveAndSubmit(claim);
    w.approveClaim(
      reviewedClaim: w.claims.byId(claim.id)!,
      requestId: EntityId.random(),
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'claim-bank',
        name: 'Claim Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'claim-bank',
      f.accounts['1000']!,
    );
    final payment = EntityId.random();
    w.settleClaims(
      requestId: payment,
      reviewedClaims: [w.claims.byId(claim.id)!],
      bankAccountId: f.accounts['1000']!,
      paymentAccountId: 'claim-bank',
      paymentReference: 'PAY-001',
      paidAt: DateTime.utc(2026, 9, 16),
    );
    final statement = await w.claimantStatements(
      from: DateTime.utc(2026, 9, 15),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(statement.statements.single.identity!.payeeId, 'director-a');
    expect(statement.statements.single.openingMinor, BigInt.from(18200));
    expect(statement.statements.single.closingMinor, BigInt.zero);
    expect(statement.controls.single.otherClosingMinor, BigInt.zero);
    final paid = w.claims.byId(claim.id)!;
    expect(paid.status, ClaimStatus.paid);
    final facts = paid.receipts.map((r) => r.toJson()).toList();
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 2),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(
      w.claims.byId(claim.id)!.receipts.map((r) => r.toJson()).toList(),
      facts,
    );
    final ledger = await w.report(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(ledger.expenses, BigInt.from(16200));
    expect(ledger.liabilities, BigInt.zero);
    expect((await report(w)).rows, hasLength(3));
    final restored = await AccountingWorkspace.emptyRestore(
      '${dir.path}/restore.sqlite',
      archive,
    );
    addTearDown(restored.dispose);
    final recovered = restored.claims.byId(claim.id)!;
    expect(recovered.receipts.map((r) => r.toJson()).toList(), facts);
    expect(recovered.hasReviewableAttachment, false);
    expect((await report(restored)).rows, hasLength(3));
    final recoveredStatement = await restored.claimantStatements(
      from: DateTime.utc(2026, 9, 15),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(
      recoveredStatement.statements.single.openingMinor,
      BigInt.from(18200),
    );
    expect(recoveredStatement.statements.single.closingMinor, BigInt.zero);
    final data = body(archive);
    final table =
        (data['tables'] as Map)['claim_settlement_allocations'] as Map;
    final payloadColumn = (table['columns'] as List).indexOf('paid_payload');
    final row = (table['rows'] as List).first as List;
    final forged = jsonDecode(row[payloadColumn] as String) as Map;
    final line =
        (((forged['receipts'] as List).first as Map)['lines'] as List).first
            as Map;
    line['expenseAccountId'] = f.accounts['5100']!.value;
    row[payloadColumn] = jsonEncode(forged);
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    expect(
      () => empty.restoreDataArchive(envelope(data)),
      throwsFormatException,
    );
    expect(empty.openClaimStore(w.identity.businessId).all, isEmpty);
  });
  test(
    'reversal cancels retained receipt tax even after current source changes',
    () async {
      final f = await fixture();
      final w = f.w;
      addTearDown(w.dispose);
      final claim = f.claim();
      w.claims.saveAndSubmit(claim);
      final source = w.approveClaim(
        reviewedClaim: w.claims.byId(claim.id)!,
        requestId: EntityId.random(),
        liabilityAccountId: f.accounts['2100']!,
        approvedAt: DateTime.utc(2026, 9, 15),
      );
      w.reverseClaimRecognition(
        reviewedClaim: w.claims.byId(claim.id)!,
        requestId: EntityId.random(),
        expectedRecognitionJournalId: source,
        decision: ClaimRecognitionDecision.returnForCorrection,
        reversedOn: DateTime.utc(2026, 9, 16),
        reason: 'Correct receipt allocation',
        changedAt: DateTime.utc(2026, 9, 16),
      );
      final activity = await report(w);
      expect(activity.rows, hasLength(6));
      expect(
        activity.rows.fold<BigInt>(BigInt.zero, (a, r) => a + r.taxMinor!),
        BigInt.zero,
      );
      final changed = Claim.fromJson({
        ...w.claims.byId(claim.id)!.toJson(),
        'businessPurpose': 'Correction after original recognition',
      });
      // Returned claims are retained by saveDraft, without replacing frozen cycle facts.
      w.claims.saveDraft(changed);
      expect((await report(w)).rows.map((r) => r.description).toSet(), {
        'Business service',
        'Equipment purchase',
        'Printed material',
      });
      final archive = w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 10, 2),
      );
      final recovered = LocalAccountingDatabase.inMemory();
      addTearDown(recovered.close);
      recovered.restoreDataArchive(archive);
      expect(
        recovered
            .openClaimStore(w.identity.businessId)
            .byId(claim.id)!
            .businessPurpose,
        changed.businessPurpose,
      );
      for (final column in ['reviewed_payload', 'result_payload']) {
        final data = body(archive);
        final table = (data['tables'] as Map)['claim_posting_reversals'] as Map;
        final index = (table['columns'] as List).indexOf(column);
        final row = (table['rows'] as List).first as List;
        final forged = jsonDecode(row[index] as String) as Map;
        final line =
            (((forged['receipts'] as List).first as Map)['lines'] as List).first
                as Map;
        line['expenseAccountId'] = f.accounts['5100']!.value;
        row[index] = jsonEncode(forged);
        final empty = LocalAccountingDatabase.inMemory();
        addTearDown(empty.close);
        expect(
          () => empty.restoreDataArchive(envelope(data)),
          throwsFormatException,
        );
        expect(empty.openClaimStore(w.identity.businessId).all, isEmpty);
      }
    },
  );
  test('archive tampering of tax snapshots or recognition allocations rolls back recovery', () async {
    final f = await fixture();
    final w = f.w;
    addTearDown(w.dispose);
    final claim = f.claim();
    w.claims.saveAndSubmit(claim);
    w.approveClaim(
      reviewedClaim: w.claims.byId(claim.id)!,
      requestId: EntityId.random(),
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 2),
    );
    for (final target in ['claims', 'claim_postings']) {
      for (final corruption in ['frozen-tax', 'cost-allocation']) {
        final data = body(archive);
        final table = (data['tables'] as Map)[target] as Map;
        final columns = (table['columns'] as List).cast<String>();
        final rows = table['rows'] as List;
        final index = columns.indexOf(
          target == 'claims' ? 'payload' : 'claim_payload',
        );
        final payload =
            jsonDecode(rows.first[index] as String) as Map<String, dynamic>;
        final first =
            ((payload['receipts'] as List).first as Map)['lines'] as List;
        if (corruption == 'frozen-tax') {
          // Preserve amount/rate totals: only the retained master revision is forged.
          final item = (first.first as Map)['item'] as Map;
          (item['taxSnapshot'] as Map)['revision'] = 99;
        } else {
          // Still a valid company expense account and balanced gross amount.
          (first.first as Map)['expenseAccountId'] = f.accounts['5100']!.value;
        }
        rows.first[index] = jsonEncode(payload);
        final empty = LocalAccountingDatabase.inMemory();
        addTearDown(empty.close);
        expect(
          () => empty.restoreDataArchive(envelope(data)),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
        expect(empty.openClaimStore(w.identity.businessId).all, isEmpty);
        expect(empty.readTaxRates(w.identity.businessId), isEmpty);
      }
    }
    final data = body(archive);
    final journalTable = (data['tables'] as Map)['journal_lines'] as Map;
    final accountColumn = (journalTable['columns'] as List).indexOf(
      'account_id',
    );
    final debit = (journalTable['rows'] as List).cast<List>().firstWhere(
      (r) => r[accountColumn] == f.accounts['5000']!.value,
    );
    debit[accountColumn] = f.accounts['5100']!.value;
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    expect(
      () => empty.restoreDataArchive(envelope(data)),
      throwsFormatException,
    );
    expect(empty.openClaimStore(w.identity.businessId).all, isEmpty);
  });
  test('schema 51 database and archive preserve every saved row through upgrade', () async {
    final dir = Directory.systemTemp.createTempSync('claim-tax-migration-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await createDemoWorkspace(databasePath: path);
    final company = w.identity.businessId;
    final before = body(
      w.database.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
    );
    final tables = before['tables'] as Map;
    expect(((tables['claim_postings'] as Map)['rows'] as List), isNotEmpty);
    expect(
      ((tables['claim_settlement_allocations'] as Map)['rows'] as List),
      isNotEmpty,
    );
    final claimPayloads = (tables['claims'] as Map)['rows'] as List;
    expect(claimPayloads, hasLength(16));
    w.dispose();
    final raw = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(raw);
    raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    raw.execute('DROP TABLE IF EXISTS tax_remittances');
    raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=51');
    raw.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final after = body(
      w.database.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
    );
    expect(after['tables'], tables);
    expect(after['schemaVersion'], LocalAccountingDatabase.schemaVersion);
    final destination = LocalAccountingDatabase.inMemory();
    addTearDown(destination.close);
    destination.restoreDataArchive(envelope(historical(envelope(before), 51)));
    final restored = body(
      destination.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
    );
    // Linked Expenses did not exist in schema 51. Their new presentation
    // and unavailable-evidence state are validated by the migration; compare
    // every pre-existing archive row exactly, without normalizing its payload.
    for (final snapshot in [tables, restored['tables'] as Map]) {
      final expenses = snapshot['expense_intakes'] as Map;
      final payload = (expenses['columns'] as List).indexOf('payload');
      final rows = expenses['rows'] as List;
      final derived = rows
          .where(
            (row) =>
                (jsonDecode((row as List)[payload] as String)
                    as Map)['claimSource'] !=
                null,
          )
          .toList();
      expect(derived, hasLength(2));
      rows.removeWhere(derived.contains);
    }
    expect(restored['tables'], tables);
    expect(restored['schemaVersion'], LocalAccountingDatabase.schemaVersion);
    final verify = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(verify.dispose);
    expect(
      verify.select('PRAGMA user_version').single['user_version'],
      LocalAccountingDatabase.schemaVersion,
    );
    expect(verify.select('PRAGMA foreign_key_check'), isEmpty);
    expect(verify.select('PRAGMA integrity_check').single.values.first, 'ok');
  });
}
