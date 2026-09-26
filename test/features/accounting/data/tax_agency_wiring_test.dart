import '../../../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_tax_agency.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/sales_report_fixture.dart';
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'claim_receipt_tax_test.dart' show Fixture;
import 'purchase_tax_cost_mapping_test.dart' show accounts;

CompanyTaxAgency agency({
  EntityId? id,
  int revision = 0,
  String registration = 'Fictional Registration A',
}) => CompanyTaxAgency(
  id: id ?? EntityId.random(),
  name: 'RMCD',
  registrationNumber: registration,
  countryCode: 'MY',
  revision: revision,
);
CompanyTaxRate code(
  CompanyTaxAgency? agency, {
  EntityId? id,
  EntityId? account,
  int revision = 0,
  String name = 'Service Tax',
}) => CompanyTaxRate(
  id: id ?? EntityId.random(),
  name: name,
  percent: '8',
  effectiveFrom: DateTime.utc(2026),
  application: account == null ? TaxApplication.purchases : TaxApplication.both,
  agencySnapshot: agency,
  accountId: account,
  revision: revision,
);
void post(SalesReportFixture f, CompanyTaxRate? rate, String number) {
  final w = f.workspace;
  final invoice = Invoice.draft(
    id: EntityId.random(),
    customerId: f.customer.id,
    documentNumber: number,
    issueDate: DateTime.utc(2026, 9, 1),
    taxMode: 'Exclusive',
    lines: [
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: f.income,
        description: 'Fictional service',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromMinor(10000, 'MYR'),
        taxRatePercent: rate?.percent ?? '0',
        taxSnapshot: rate,
      ),
    ],
  );
  w.saveInvoiceDraft(
    invoice,
    expectedRevision: 0,
    savedAt: DateTime.utc(2026, 9, 2),
  );
  w.postInvoice(
    requestId: EntityId.random(),
    invoiceId: invoice.id,
    expectedRevision: 1,
    expectedCustomerRevision: f.customer.metadata.revision,
    documentNumber: number,
    receivableAccountId: f.receivable,
    incomeAccountId: f.income,
    taxAccountId: rate == null ? null : f.tax,
    approvedAt: DateTime.utc(2026, 9, 3),
  );
}

void main() {
  test('agency-linked code v3 is explicit and old v1/v2 stay exact', () {
    final saved = agency(revision: 1);
    for (final account in [null, EntityId.random()]) {
      final rate = code(saved, account: account);
      expect(rate.toJson()['version'], 3);
      expect(CompanyTaxRate.fromJson(rate.toJson()).toJson(), rate.toJson());
      final legacy = code(null, account: account);
      expect(legacy.toJson()['version'], account == null ? 2 : 1);
      expect(
        CompanyTaxRate.fromJson(legacy.toJson()).toJson(),
        legacy.toJson(),
      );
      expect(
        () => CompanyTaxRate.fromJson({
          ...legacy.toJson(),
          'agency': saved.toJson(),
        }),
        throwsFormatException,
      );
    }
    expect(() => code(agency()), throwsFormatException);
    expect(
      () => CompanyTaxAgency.fromJson({...saved.toJson(), 'version': 2}),
      throwsFormatException,
    );
    expect(
      () => CompanyTaxAgency(
        id: EntityId.random(),
        name: 'RMCD',
        countryCode: 'Malaysia',
      ),
      throwsFormatException,
    );
  });

  test('agency owner, stale revision, duplicate name, company isolation and immutable history', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-agency-owner-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    final initial = w.saveTaxAgency(agency());
    expect(w.taxAgencies.single.toJson(), initial.toJson());
    expect(() => w.saveTaxAgency(initial), returnsNormally);
    expect(() => w.saveTaxAgency(initial), throwsStateError);
    expect(() => w.saveTaxAgency(agency()), throwsStateError);
    expect(
      () => w.database.saveTaxAgency(
        businessId: w.identity.businessId,
        actorId: EntityId.random(),
        agency: agency(id: initial.id, revision: 2),
        savedAt: DateTime.now(),
      ),
      throwsStateError,
    );
    final other = await AccountingWorkspace.open(':memory:');
    addTearDown(other.dispose);
    expect(other.taxAgencies, isEmpty);
    expect(() => other.saveTaxRate(code(initial)), throwsStateError);
    final company = w.identity.businessId;
    expect(w.database.taxAgencyHistory(company, initial.id), hasLength(2));
    final raw = sqlite3.open(path);
    expect(
      () =>
          raw.execute('UPDATE company_tax_agency_history SET payload=payload'),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute('DELETE FROM company_tax_agency_history'),
      throwsA(isA<SqliteException>()),
    );
    raw.dispose();
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(w.taxAgencies.single.revision, 2);
    expect(
      w.database.taxAgencyHistory(company, initial.id).first.toJson(),
      initial.toJson(),
    );
  });

  test('current agency selection, retained mapping, relink revision and rejected forged snapshot', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final first = w.saveTaxAgency(agency());
    final original = w.saveTaxRate(code(first));
    final second = w.saveTaxAgency(
      agency(
        id: first.id,
        revision: first.revision,
        registration: 'Fictional Registration B',
      ),
    );
    // An unchanged saved link is not silently overwritten by a master edit.
    final retained = w.saveTaxRate(
      code(first, id: original.id, revision: original.revision),
    );
    expect(retained.agencySnapshot!.toJson(), first.toJson());
    expect(() => w.saveTaxRate(code(first, name: 'SST')), throwsStateError);
    final relinked = w.saveTaxRate(
      code(second, id: original.id, revision: retained.revision),
    );
    expect(relinked.agencySnapshot!.toJson(), second.toJson());
    final forged = agency(
      id: second.id,
      revision: second.revision,
      registration: 'Forged',
    );
    expect(() => w.saveTaxRate(code(forged, name: 'SST')), throwsStateError);
    expect(
      w.database
          .taxRateHistory(w.identity.businessId, original.id)
          .first
          .toJson(),
      original.toJson(),
    );
  });

  test('actual posted tax groups retain each registration revision and unassigned facts through restart and restore', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-agency-report-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await salesReportFixture(path: path, seedInvoices: false);
    var w = f.workspace;
    final first = w.saveTaxAgency(agency());
    final firstCode = w.saveTaxRate(code(first, account: f.tax));
    post(f, firstCode, 'AGENCY-1');
    post(f, null, 'UNASSIGNED-1');
    final second = w.saveTaxAgency(
      agency(
        id: first.id,
        revision: first.revision,
        registration: 'Fictional Registration B',
      ),
    );
    final secondCode = w.saveTaxRate(
      code(
        second,
        account: f.tax,
        id: firstCode.id,
        revision: firstCode.revision,
      ),
    );
    post(f, secondCode, 'AGENCY-2');
    final range = (DateTime.utc(2026, 9), DateTime.utc(2026, 9, 30));
    Future<void> verify(AccountingWorkspace book) async {
      final activity = await book.taxActivity(
        from: range.$1,
        through: range.$2,
      );
      expect(activity.agencyGroups, hasLength(3));
      expect(
        activity.agencyGroups
            .where((g) => g.agency?.revision == 1)
            .single
            .agency!
            .registrationNumber,
        first.registrationNumber,
      );
      expect(
        activity.agencyGroups
            .where((g) => g.agency?.revision == 2)
            .single
            .agency!
            .registrationNumber,
        second.registrationNumber,
      );
      expect(
        activity.agencyGroups.where((g) => g.agency == null).single.label,
        'Unassigned Agency',
      );
      expect(
        activity.agencyGroups.fold(BigInt.zero, (v, g) => v + g.salesTax),
        activity.salesTax,
      );
      expect(activity.salesTax, BigInt.from(1600));
      expect(activity.purchaseTaxInCost, BigInt.zero);
      expect(activity.accounts.single.closingCredit, BigInt.from(1600));
      final ledger = await book.report(from: range.$1, through: range.$2);
      expect(ledger.revenue, BigInt.from(30000));
      expect(ledger.isBalanced, isTrue);
    }

    await verify(w);
    final before = body(
      w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 10),
      ),
    );
    final company = w.identity.businessId;
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    await verify(w);
    expect(
      body(
        w.database.exportDataArchive(company, DateTime.utc(2026, 10)),
      )['tables'],
      before['tables'],
    );
    final restored = await AccountingWorkspace.emptyRestore(
      '${dir.path}/restored.sqlite',
      envelope(before),
    );
    addTearDown(restored.dispose);
    await verify(restored);
    // Mutate agency history and rehash: identity/history verification rejects it.
    final forged = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    final table =
        (forged['tables'] as Map)['company_tax_agency_history'] as Map;
    final index = (table['columns'] as List).indexOf('payload');
    final row = (table['rows'] as List).first as List;
    final facts = jsonDecode(row[index] as String) as Map;
    facts['registrationNumber'] = 'Forged';
    row[index] = jsonEncode(facts);
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    expect(
      () => empty.restoreDataArchive(envelope(forged)),
      throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
    );
    expect(empty.readTaxAgencies(company), isEmpty);
  });

  test('mixed receipt purchase agency grouping never creates a sales liability or reduces sales tax', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final ids = await accounts(w);
    final authority = w.saveTaxAgency(agency());
    final purchase = w.saveTaxRate(code(authority));
    final claim = Fixture(w, ids, purchase).claim();
    w.claims.saveAndSubmit(claim);
    w.approveClaim(
      requestId: EntityId.random(),
      reviewedClaim: w.claims.byId(claim.id)!,
      liabilityAccountId: ids['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    final report = await w.taxActivity(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    final group = report.agencyGroups.singleWhere((g) => g.agency != null);
    expect(group.agency!.toJson(), authority.toJson());
    expect(group.salesTax, BigInt.zero);
    expect(group.purchaseTaxInCost, BigInt.from(1200));
    expect(report.purchaseTaxInCost, BigInt.from(1200));
    expect(report.accounts, isEmpty);
    expect(
      report.agencyGroups
          .singleWhere((g) => g.agency == null)
          .rows
          .single
          .taxMinor,
      BigInt.zero,
    );
    final ledger = await w.report(
      from: DateTime.utc(2026, 9),
      through: DateTime.utc(2026, 9, 30),
    );
    expect(ledger.expenses, BigInt.from(16200));
    expect(ledger.liabilities, BigInt.from(18200));
    expect(ledger.isBalanced, isTrue);
  });

  test('genuine schema 53 database and archive add only empty agency tables without rewriting tax or financial rows', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-agency-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await salesReportFixture(path: path, seedInvoices: false);
    final w = f.workspace;
    final rate = w.saveTaxRate(code(null, account: f.tax));
    post(f, rate, 'OLD-53');
    final company = w.identity.businessId;
    final before = historical(
      w.database.exportDataArchive(company, DateTime.utc(2026, 10)),
      53,
    );
    w.dispose();
    final raw = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(raw);
    raw.execute('DROP TABLE tax_remittance_corrections');
    raw.execute('DROP TABLE tax_remittances');
    raw.execute('DROP TABLE company_tax_agency_history');
    raw.execute('DROP TABLE company_tax_agencies');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=53');
    raw.dispose();
    final upgraded = await AccountingWorkspace.open(path);
    addTearDown(upgraded.dispose);
    final after = body(
      upgraded.database.exportDataArchive(company, DateTime.utc(2026, 10)),
    );
    dropCurrentAccountArchiveFixtureOwner(after);
    for (final entry in (before['tables'] as Map).entries) {
      expect(
        (after['tables'] as Map)[entry.key],
        entry.value,
        reason: entry.key as String,
      );
    }
    expect(upgraded.taxAgencies, isEmpty);
    expect(upgraded.taxRates.single.toJson(), rate.toJson());
    final restored = await AccountingWorkspace.emptyRestore(
      '${dir.path}/restored.sqlite',
      envelope(before),
    );
    addTearDown(restored.dispose);
    expect(restored.taxAgencies, isEmpty);
    final restoredArchive = body(
      restored.database.exportDataArchive(company, DateTime.utc(2026, 10)),
    );
    dropCurrentAccountArchiveFixtureOwner(restoredArchive);
    for (final entry in (before['tables'] as Map).entries) {
      expect(
        (restoredArchive['tables'] as Map)[entry.key],
        entry.value,
        reason: entry.key as String,
      );
    }
  });
}
