import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;
import 'claim_receipt_tax_test.dart' show Fixture;
import 'expense_tax_persistence_test.dart' show taxedExpense;

CompanyTaxRate costCode({String name = 'Service Tax', String percent = '8'}) =>
    CompanyTaxRate(
      id: EntityId.random(),
      name: name,
      percent: percent,
      effectiveFrom: DateTime.utc(2026),
      application: TaxApplication.purchases,
    );

Future<Map<String, EntityId>> accounts(AccountingWorkspace w) async {
  final ids = <String, EntityId>{};
  for (final (code, type) in [
    ('1000', AccountType.asset),
    ('1500', AccountType.asset),
    ('2100', AccountType.liability),
    ('5000', AccountType.expense),
    ('5100', AccountType.expense),
  ]) {
    await w.createAccount(code: code, name: code, type: type);
    ids[code] = (await w.accounts())
        .singleWhere((a) => a.account.code == code)
        .account
        .id;
  }
  return ids;
}

void main() {
  test('explicit purchase cost shape retains v1 facts and refuses missing sales mappings', () {
    final code = costCode();
    expect(code.accountId, isNull);
    expect(code.toJson()['version'], 2);
    expect(code.toJson()['purchaseAccounting'], 'cost');
    expect(CompanyTaxRate.fromJson(code.toJson()).toJson(), code.toJson());
    expect(() => code.salesAccountId, throwsStateError);
    for (final purpose in [TaxApplication.sales, TaxApplication.both]) {
      expect(
        () => CompanyTaxRate(
          id: EntityId.random(),
          name: 'SST',
          percent: '8',
          effectiveFrom: DateTime.utc(2026),
          application: purpose,
        ),
        throwsFormatException,
      );
    }
    final legacy = CompanyTaxRate(
      id: EntityId.random(),
      name: 'SST',
      percent: '8',
      effectiveFrom: DateTime.utc(2026),
      application: TaxApplication.both,
      accountId: EntityId.random(),
    ).toJson();
    expect(legacy['version'], 1);
    expect(CompanyTaxRate.fromJson(legacy).toJson(), legacy);
    for (final change in [
      {'version': 1},
      {'purchaseAccounting': 'recoverable'},
      {'application': 'sales'},
      {'account': EntityId.random().value},
    ]) {
      expect(
        () => CompanyTaxRate.fromJson({...code.toJson(), ...change}),
        throwsFormatException,
      );
    }
  });

  test('accountless master saves without ledger accounts and enforces actor, revision and company snapshots', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final code = w.saveTaxRate(costCode());
    expect(await w.accounts(), isEmpty);
    expect(
      () => w.database.saveTaxRate(
        businessId: w.identity.businessId,
        actorId: EntityId.random(),
        rate: costCode(name: 'SST'),
        savedAt: DateTime.utc(2026),
      ),
      throwsStateError,
    );
    final changed = w.saveTaxRate(
      CompanyTaxRate.fromJson({...code.toJson(), 'percent': '6'}),
    );
    expect(changed.revision, 2);
    expect(() => w.saveTaxRate(code), throwsStateError);
    expect(
      w.database.taxRateHistory(w.identity.businessId, code.id).first.toJson(),
      code.toJson(),
    );
    expect(
      () => resolveTaxChoice(
        code.choice,
        codes: w.taxRates,
        date: DateTime.utc(2026, 9),
        purpose: TaxApplication.sales,
      ),
      throwsStateError,
    );
    final other = await AccountingWorkspace.open(':memory:');
    addTearDown(other.dispose);
    final ids = await accounts(other);
    final claim = Fixture(other, ids, code).claim();
    expect(() => other.claims.saveDraft(claim), throwsStateError);
    expect(other.claims.all, isEmpty);
  });

  for (final basis in ['Exclusive', 'Inclusive']) {
    test(
      '$basis Expense tax feeds activity and P&L gross cost without a liability mapping',
      () async {
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final ids = await accounts(w);
        final codes = [
          w.saveTaxRate(costCode()),
          w.saveTaxRate(costCode(name: 'SST', percent: '10')),
        ];
        w.savePaymentAccount(
          PaymentAccount.create(
            id: 'cash',
            name: 'Cash',
            type: PaymentAccountType.cash,
            currencyCode: 'MYR',
          ),
        );
        final id = await w.saveExpenseIntake(taxedExpense(codes, basis));
        await w.saveJournal(
          date: DateTime.utc(2026, 9, 13),
          memo: 'Purchase gross cost',
          lines: [
            JournalLine.debit(
              accountId: ids['5000']!,
              amount: Money.fromDecimal('183', 'MYR'),
            ),
            JournalLine.credit(
              accountId: ids['1000']!,
              amount: Money.fromDecimal('183', 'MYR'),
            ),
          ],
        );
        final journal = (await w.journals()).single;
        await w.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: w.identity.businessId,
            journalId: journal.entry.id,
            expectedRevision: 1,
            actorId: w.identity.ownerId,
            approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
            expenseIntakeId: id,
          ),
        );
        final report = await w.report(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(report.expenses, BigInt.from(18300));
        expect(report.liabilities, BigInt.zero);
        expect(report.periodProfit, BigInt.from(-18300));
        expect(report.isBalanced, isTrue);
        final tax = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(tax.accounts, isEmpty);
        expect(tax.unresolved, isEmpty);
        expect(
          tax.rows.fold(BigInt.zero, (sum, row) => sum + row.taxMinor!),
          BigInt.from(1300),
        );
        expect(
          tax.rows
              .where((r) => r.code != null)
              .every((r) => r.code!.accountId == null),
          isTrue,
        );
      },
    );
  }

  test('Bill allocates accountless tax to gross expense and asset costs, not sales tax payable', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, expense) = await setupBill(w);
    for (final (code, type) in [
      ('1500', AccountType.asset),
      ('2100', AccountType.liability),
    ]) {
      await w.createAccount(code: code, name: code, type: type);
    }
    final all = await w.accounts();
    EntityId id(String code) =>
        all.singleWhere((a) => a.account.code == code).account.id;
    final code = w.saveTaxRate(costCode());
    final initial = billFixture(w, vendor, expense.account.id);
    final json = initial.toJson();
    json['lines'] = [
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: expense.account.id,
        description: 'Service',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromDecimal('100', 'MYR'),
        taxRatePercent: code.percent,
        taxSnapshot: code,
      ).toJson(),
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: id('1500'),
        description: 'Equipment',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromDecimal('20', 'MYR'),
      ).toJson(),
    ];
    json['bill'] = {
      ...json['bill'] as Map<String, Object?>,
      'amountMinor': 12800,
    };
    final bill = PurchaseBillDraft.fromJson(json);
    w.saveBillDraft(bill, expectedRevision: 0);
    w.postBill(
      requestId: EntityId.random(),
      billId: bill.id,
      expectedRevision: 1,
      payableAccountId: id('2100'),
      approvedAt: DateTime.utc(2026, 9, 28, 1),
    );
    final report = await w.report(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(report.expenses, BigInt.from(10800));
    expect(report.assets, BigInt.from(2000));
    expect(report.liabilities, BigInt.from(12800));
    final tax = await w.taxActivity(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(tax.accounts, isEmpty);
    expect(
      tax.rows.fold(BigInt.zero, (sum, row) => sum + row.taxMinor!),
      BigInt.from(800),
    );
  });

  test('mixed Claim receipts preserve purchase cost snapshots through restart and recovery', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-tax-cost-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    final ids = await accounts(w);
    final code = w.saveTaxRate(costCode());
    final claim = Fixture(w, ids, code).claim();
    w.claims.saveAndSubmit(claim);
    w.approveClaim(
      reviewedClaim: w.claims.byId(claim.id)!,
      requestId: EntityId.random(),
      liabilityAccountId: ids['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    w.saveTaxRate(
      CompanyTaxRate.fromJson({
        ...code.toJson(),
        'active': false,
        'percent': '6',
      }),
    );
    final company = w.identity.businessId;
    final archive = w.database.exportDataArchive(
      company,
      DateTime.utc(2026, 10, 2),
    );
    final before = body(archive)['tables'];
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final activity = await w.taxActivity(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(activity.accounts, isEmpty);
    expect(
      activity.rows
          .where((r) => r.code != null)
          .every((r) => r.code!.revision == 1),
      isTrue,
    );
    final report = await w.report(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(report.expenses, BigInt.from(16200));
    expect(report.assets, BigInt.from(2000));
    expect(report.liabilities, BigInt.from(18200));
    final destination = LocalAccountingDatabase.inMemory();
    addTearDown(destination.close);
    destination.restoreDataArchive(archive);
    expect(
      body(
        destination.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
      )['tables'],
      before,
    );
    final forged = body(archive);
    final table = (forged['tables'] as Map)['company_tax_rate_history'] as Map;
    final payloadIndex = (table['columns'] as List).indexOf('payload');
    final row = (table['rows'] as List).first as List;
    final facts = jsonDecode(row[payloadIndex] as String) as Map;
    facts['purchaseAccounting'] = 'recoverable';
    row[payloadIndex] = jsonEncode(facts);
    final rejected = LocalAccountingDatabase.inMemory();
    addTearDown(rejected.close);
    expect(
      () => rejected.restoreDataArchive(envelope(forged)),
      throwsFormatException,
    );
  });

  test('schema 52 upgrade and archive preserve every row and original v1 tax payload', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-tax-cost-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    final ids = await accounts(w);
    final code = w.saveTaxRate(
      CompanyTaxRate(
        id: EntityId.random(),
        name: 'Legacy SST',
        percent: '8',
        effectiveFrom: DateTime.utc(2026),
        application: TaxApplication.both,
        accountId: ids['2100']!,
      ),
    );
    final company = w.identity.businessId;
    final before = body(
      w.database.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
    );
    w.dispose();
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    old.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    old.execute('DROP TABLE IF EXISTS tax_remittances');
    old.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    old.execute('DROP TABLE IF EXISTS company_tax_agencies');
    old.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version=52');
    old.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final after = body(
      w.database.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
    );
    expect(after['tables'], before['tables']);
    expect(after['schemaVersion'], LocalAccountingDatabase.schemaVersion);
    expect(w.taxRates.single.toJson(), code.toJson());
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(envelope(historical(envelope(before), 52)));
    expect(
      body(
        restored.exportDataArchive(company, DateTime.utc(2026, 10, 2)),
      )['tables'],
      before['tables'],
    );
  });
}
