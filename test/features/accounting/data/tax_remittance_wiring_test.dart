import '../../../support/historical_sqlite_fixture.dart';

import 'package:audyt/features/accounting/application/account_repository.dart';

import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/domain/tax_activity_report.dart';

import 'bank_statement_import_test.dart' show parse;

import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_agency.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/tax_remittance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/sales_report_fixture.dart';
import '../../../app/restored_page_routes_test.dart' show tables;
import 'tax_agency_wiring_test.dart' show agency, code, post;
import 'archive_upgrade_test.dart' show body, envelope, historical;

final start = DateTime.utc(2030);

class Fixture {
  Fixture(this.sales, this.bank, this.agency);
  final SalesReportFixture sales;
  final EntityId bank;
  final CompanyTaxAgency agency;
  AccountingWorkspace get w => sales.workspace;
  TaxRemittanceAllocation allocation(
    int minor, {
    CompanyTaxAgency? to,
    EntityId? account,
    String currency = 'MYR',
  }) => TaxRemittanceAllocation(
    agency: to ?? agency,
    liabilityAccountId: account ?? sales.tax,
    periodFrom: DateTime.utc(2026, 9),
    periodThrough: DateTime.utc(2026, 10, 31),
    amount: Money.fromMinor(minor, currency),
  );
  TaxRemittance record(
    int minor, {
    EntityId? request,
    DateTime? at,
    List<TaxRemittanceAllocation>? allocations,
  }) => w.recordTaxRemittance(
    requestId: request ?? EntityId.random(),
    paymentAccountId: 'fictional-remittance-bank',
    allocations: allocations ?? [allocation(minor)],
    paidOn: DateTime.utc(2026, 9, 20),
    reference: 'FICTIONAL-SST-REMITTANCE',
    recordedAt: at ?? start,
  );
}

Future<Fixture> setup({String path = ':memory:'}) async {
  final f = await salesReportFixture(path: path, seedInvoices: false),
      w = f.workspace;
  await w.createAccount(
    code: '1000',
    name: 'Fictional Remittance Bank',
    type: AccountType.asset,
  );
  final bank = (await w.accounts())
      .singleWhere((a) => a.account.code == '1000')
      .account
      .id;
  w.database.savePaymentAccount(
    w.identity.businessId,
    PaymentAccount.create(
      id: 'fictional-remittance-bank',
      name: 'Fictional Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    ),
  );
  w.database.linkPaymentLedgerAccount(
    w.identity.businessId,
    'fictional-remittance-bank',
    bank,
  );
  final a = w.saveTaxAgency(agency());
  final rate = w.saveTaxRate(code(a, account: f.tax));
  post(f, rate, 'FICTIONAL-SST-SOURCE');
  return Fixture(f, bank, a);
}

Future<StoredJournalEntry> manual(
  Fixture f,
  int minor, {
  bool expense = false,
  DateTime? date,
}) async {
  await f.w.saveJournal(
    date: date ?? DateTime.utc(2026, 9, 21),
    memo: 'Fictional reviewed external payment',
    lines: [
      JournalLine.debit(
        accountId: expense ? f.sales.income : f.sales.tax,
        amount: Money.fromMinor(minor, 'MYR'),
      ),
      JournalLine.credit(
        accountId: f.bank,
        amount: Money.fromMinor(minor, 'MYR'),
      ),
    ],
  );
  final draft = (await f.w.journals()).singleWhere(
    (j) => j.entry.state == JournalEntryState.draft,
  );
  return f.w.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: f.w.identity.businessId,
      journalId: draft.entry.id,
      expectedRevision: 1,
      actorId: f.w.identity.ownerId,
      approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    ),
  );
}

Future<TaxActivityReport> report(AccountingWorkspace w) => w.taxActivity(
  from: DateTime.utc(2026, 9),
  through: DateTime.utc(2026, 9, 30),
);
Map<String, dynamic> editTable(
  String archive,
  String table,
  void Function(List columns, List rows) edit,
) {
  final data = body(archive), t = (data['tables'] as Map)[table] as Map;
  edit(t['columns'] as List, t['rows'] as List);
  return data;
}

void main() {
  test('record once, separate agency periods, exact tax ledger/P&L, correction/retry, restart and restore', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-remittance-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite', f = await setup(path: path);
    var w = f.w;
    final other = w.saveTaxAgency(
      CompanyTaxAgency(
        id: EntityId.random(),
        name: 'Fictional Agency',
        countryCode: 'MY',
      ),
    );
    final request = EntityId.random();
    final allocations = [f.allocation(200), f.allocation(100, to: other)];
    final payment = f.record(300, request: request, allocations: allocations);
    final before = tables(w);
    expect(
      f.record(300, request: request, allocations: allocations).toJson(),
      payment.toJson(),
    );
    expect(tables(w), before);
    final activity = await report(w), account = activity.accounts.single;
    expect(activity.salesTax, BigInt.from(800));
    expect(activity.remittedTax, BigInt.from(300));
    expect(activity.ledger.periodProfit, BigInt.from(10000));
    expect(account.closingCredit, BigInt.from(500));
    expect(account.remittanceCredit, BigInt.from(-300));
    expect(account.unattributedMovementCredit, BigInt.zero);
    expect(
      activity.agencyGroups
          .singleWhere((g) => g.agency?.id == other.id)
          .remittedTax,
      BigInt.from(100),
    );
    expect(activity.remittances, hasLength(2));
    expect(
      (await w.journals()).where((j) => j.entry.id == request),
      hasLength(1),
    );
    expect(
      () => f.record(
        301,
        request: request,
        at: start.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    final correction = w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: payment,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 2)),
      reason: 'Fictional payment correction',
    );
    expect(correction.kind, TaxRemittanceCorrectionKind.reversal);
    expect(w.taxRemittances(), isEmpty);
    expect(w.taxRemittances(includeCorrected: true), hasLength(1));
    final after = tables(w);
    expect(
      w
          .correctTaxRemittance(
            requestId: correction.id,
            reviewedRemittance: payment,
            on: correction.on,
            recordedAt: correction.recordedAt,
            reason: correction.reason,
          )
          .toJson(),
      correction.toJson(),
    );
    expect(tables(w), after);
    final corrected = await report(w);
    expect(corrected.remittedTax, BigInt.zero);
    expect(corrected.accounts.single.closingCredit, BigInt.from(800));
    expect(corrected.accounts.single.unattributedMovementCredit, BigInt.zero);
    expect(corrected.ledger.periodProfit, BigInt.from(10000));
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      start.add(const Duration(seconds: 3)),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(tables(w), after);
    expect((await report(w)).remittances, hasLength(4));
    final restored = await AccountingWorkspace.emptyRestore(
      ':memory:',
      archive,
    );
    addTearDown(restored.dispose);
    expect(tables(restored), after);
    expect(
      (await report(restored)).accounts.single.closingCredit,
      BigInt.from(800),
    );
  });

  test('link partially and conservatively, unlink attribution without reposting, relink preserves old facts', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final source = await manual(f, 500);
    final first = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: source,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(200)],
      reference: 'Fictional attribution A',
      recordedAt: start,
    );
    final count = (await f.w.journals()).length;
    final second = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: source,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(300)],
      reference: 'Fictional attribution B',
      recordedAt: start.add(const Duration(seconds: 1)),
    );
    expect((await f.w.journals()).length, count);
    expect((await report(f.w)).remittedTax, BigInt.from(500));
    final before = tables(f.w);
    expect(
      () => f.w.linkTaxRemittance(
        requestId: EntityId.random(),
        reviewedJournal: source,
        paymentAccountId: 'fictional-remittance-bank',
        allocations: [f.allocation(1)],
        reference: 'Fictional over allocation',
        recordedAt: start.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
    expect(tables(f.w), before);
    final correction = f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: first,
      on: source.entry.date,
      recordedAt: start.add(const Duration(seconds: 3)),
      reason: 'Fictional agency attribution correction',
    );
    expect(correction.kind, TaxRemittanceCorrectionKind.unlink);
    expect(correction.journalId, isNull);
    expect((await f.w.journals()).length, count);
    expect((await report(f.w)).remittedTax, BigInt.from(300));
    expect(
      (await report(f.w)).accounts.single.unattributedMovementCredit,
      BigInt.from(-200),
    );
    final linked = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: source,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(200)],
      reference: 'Fictional corrected attribution',
      recordedAt: start.add(const Duration(seconds: 4)),
    );
    expect(linked.journalId, source.entry.id);
    expect((await f.w.journals()).length, count);
    expect(f.w.taxRemittances(), hasLength(2));
    expect(f.w.taxRemittances(includeCorrected: true), hasLength(3));
    expect(
      f.w.taxRemittances().map((p) => p.id),
      containsAll([second.id, linked.id]),
    );
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      start.add(const Duration(seconds: 5)),
    );
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      archive,
    );
    addTearDown(recovered.dispose);
    expect((await report(recovered)).remittedTax, BigInt.from(500));
  });

  for (final defect in [
    'foreign actor',
    'unknown account',
    'wrong currency',
    'stale agency',
    'non-tax journal',
    'stale journal',
  ]) {
    test('rejects $defect atomically', () async {
      final f = await setup();
      addTearDown(f.w.dispose);
      StoredJournalEntry? source;
      if (defect == 'non-tax journal' || defect == 'stale journal') {
        source = await manual(f, 100, expense: defect == 'non-tax journal');
      }
      if (defect == 'stale agency') f.w.saveTaxAgency(f.agency);
      final before = tables(f.w);
      expect(
        () => defect == 'foreign actor'
            ? f.w.database.recordTaxRemittance(
                businessId: f.w.identity.businessId,
                actorId: EntityId.random(),
                requestId: EntityId.random(),
                paymentAccountId: 'fictional-remittance-bank',
                allocations: [f.allocation(100)],
                paidOn: DateTime.utc(2026, 9, 20),
                reference: 'Fictional invalid actor',
                recordedAt: start,
              )
            : source == null
            ? f.record(
                100,
                allocations: [
                  f.allocation(
                    100,
                    account: defect == 'unknown account' ? f.bank : null,
                    currency: defect == 'wrong currency' ? 'USD' : 'MYR',
                  ),
                ],
              )
            : f.w.linkTaxRemittance(
                requestId: EntityId.random(),
                reviewedJournal: defect == 'stale journal'
                    ? StoredJournalEntry(
                        entry: JournalEntry.restore(
                          id: source.entry.id,
                          date: source.entry.date,
                          memo: 'Changed memo',
                          lines: source.entry.lines,
                          state: source.entry.state,
                        ),
                        metadata: source.metadata,
                      )
                    : source,
                paymentAccountId: 'fictional-remittance-bank',
                allocations: [f.allocation(100)],
                reference: 'Fictional invalid source',
                recordedAt: start,
              ),
        throwsStateError,
      );
      expect(tables(f.w), before);
    });
  }

  test('active attribution protects generic financial reversal; unlink then exact reversal is allowed', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final original = await manual(f, 100);
    final linked = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: original,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(100)],
      reference: 'Fictional protected link',
      recordedAt: start,
    );
    final reversal = original.entry.reversal(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 22),
      memo: 'Fictional generic reversal',
    );
    await f.w.saveJournal(
      date: reversal.date,
      memo: reversal.memo,
      lines: reversal.lines,
    );
    final draft = (await f.w.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    // Save the real reversal marker through the guarded draft repository.
    final marked = StoredJournalEntry(
      entry: JournalEntry.restore(
        id: draft.entry.id,
        date: reversal.date,
        memo: reversal.memo,
        lines: reversal.lines,
        state: JournalEntryState.draft,
        reversesId: original.entry.id,
      ),
      metadata: draft.metadata.nextRevision(
        updatedAt: start.add(const Duration(seconds: 1)),
      ),
    );
    await f.w.database.save(marked);
    final command = JournalApproval(
      requestId: EntityId.random(),
      businessId: f.w.identity.businessId,
      journalId: marked.entry.id,
      expectedRevision: 2,
      actorId: f.w.identity.ownerId,
      approvedAt: start.add(const Duration(seconds: 3)),
    );
    final before = tables(f.w);
    await expectLater(f.w.approveJournal(command), throwsStateError);
    expect(tables(f.w), before);
    f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: linked,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 2)),
      reason: 'Fictional unlink before correction',
    );
    await f.w.approveJournal(command);
    expect((await report(f.w)).remittedTax, BigInt.zero);
    final recovered = await AccountingWorkspace.emptyRestore(
      ':memory:',
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        start.add(const Duration(seconds: 4)),
      ),
    );
    addTearDown(recovered.dispose);
    expect(
      (await report(recovered)).accounts.single.closingCredit,
      BigInt.from(800),
    );
  });

  test('recovery rejects forged agency, allocation, signature and lost audit without replacing destination', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final payment = f.record(300);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      start.add(const Duration(seconds: 1)),
    );
    for (final defect in ['agency', 'amount', 'signature', 'audit']) {
      final target = LocalAccountingDatabase.inMemory();
      final data = defect == 'audit'
          ? editTable(
              archive,
              'ledger_audit',
              (columns, rows) => rows.removeWhere(
                (row) =>
                    row[columns.indexOf('kind')] == 'tax.remittance_recorded',
              ),
            )
          : editTable(archive, 'tax_remittances', (columns, rows) {
              final row = rows.single as List;
              if (defect == 'signature') {
                row[columns.indexOf('signature')] = 'forged';
                return;
              }
              final payload =
                  jsonDecode(row[columns.indexOf('payload')] as String) as Map;
              final a = (payload['allocations'] as List).first as Map;
              if (defect == 'agency') {
                (a['agency'] as Map)['registrationNumber'] =
                    'Forged registration';
              } else {
                a['amountMinor'] = 301;
              }
              row[columns.indexOf('payload')] = jsonEncode(payload);
            });
      expect(
        () => target.restoreDataArchive(envelope(data)),
        throwsA(anything),
      );
      expect(target.readTaxRemittances(f.w.identity.businessId), isEmpty);
      // Failed import leaves the complete destination empty, verified by a subsequent valid restore.
      target.restoreDataArchive(archive);
      expect(
        target.readTaxRemittances(f.w.identity.businessId).single.id,
        payment.id,
      );
      target.close();
    }
    expect(
      () => f.w.database.recordTaxRemittance(
        businessId: f.w.identity.businessId,
        actorId: f.w.identity.ownerId,
        requestId: payment.id,
        paymentAccountId: 'fictional-remittance-bank',
        allocations: [f.allocation(301)],
        paidOn: payment.paidOn,
        reference: payment.reference,
        recordedAt: payment.recordedAt,
      ),
      throwsStateError,
    );
  });

  test('genuine schema 54 database/archive adds empty remittance tables and preserves all saved rows', () async {
    final dir = Directory.systemTemp.createTempSync(
      'audyt-remittance-upgrade-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite', f = await setup(path: path);
    final before = tables(f.w);
    final oldArchive = envelope(
      historical(
        f.w.database.exportDataArchive(f.w.identity.businessId, start),
        54,
      ),
    );
    f.w.dispose();
    final raw = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(raw);
    raw.execute('DROP TABLE tax_remittance_corrections');
    raw.execute('DROP TABLE tax_remittances');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=54');
    raw.dispose();
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final after = tables(w);
    for (final e in before.entries) {
      if (!e.key.startsWith('tax_remittance')) {
        expect(after[e.key], e.value, reason: e.key);
      }
    }
    expect(w.taxRemittances(), isEmpty);
    final target = await AccountingWorkspace.emptyRestore(
      ':memory:',
      oldArchive,
    );
    addTearDown(target.dispose);
    for (final e in before.entries) {
      if (!e.key.startsWith('tax_remittance')) {
        expect(tables(target)[e.key], e.value, reason: e.key);
      }
    }
    expect(target.taxRemittances(), isEmpty);
    expect(LocalAccountingDatabase.schemaVersion, 66);
  });
  test('closed periods reject record/reversal atomically; linking existing closed-period books adds no posting', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final recorded = f.record(100);
    final existing = await manual(f, 200);
    await f.w.database.closeThrough(
      businessId: f.w.identity.businessId,
      actorId: f.w.identity.ownerId,
      date: DateTime.utc(2026, 9, 30),
      changedAt: start.add(const Duration(seconds: 1)),
      reason: 'Fictional reviewed closed period',
    );
    final before = tables(f.w);
    expect(
      () => f.record(50, at: start.add(const Duration(seconds: 2))),
      throwsStateError,
    );
    expect(
      () => f.w.correctTaxRemittance(
        requestId: EntityId.random(),
        reviewedRemittance: recorded,
        on: DateTime.utc(2026, 9, 22),
        recordedAt: start.add(const Duration(seconds: 2)),
        reason: 'Fictional locked-period correction',
      ),
      throwsStateError,
    );
    expect(tables(f.w), before);
    final count = (await f.w.journals()).length;
    f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: existing,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(200)],
      reference: 'Fictional attribution of already-posted books',
      recordedAt: start.add(const Duration(seconds: 3)),
    );
    expect((await f.w.journals()).length, count);
    expect((await report(f.w)).remittedTax, BigInt.from(300));
    f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: recorded,
      on: DateTime.utc(2026, 10, 1),
      recordedAt: start.add(const Duration(seconds: 4)),
      reason: 'Fictional next-open-period correction',
    );
    final september = await report(f.w);
    expect(september.remittedTax, BigInt.from(300));
    final october = await f.w.taxActivity(
      from: DateTime.utc(2026, 10),
      through: DateTime.utc(2026, 10, 31),
    );
    expect(october.remittedTax, BigInt.from(-100));
    expect(october.accounts.single.openingCredit, BigInt.from(500));
    expect(october.accounts.single.closingCredit, BigInt.from(600));
    expect(october.ledger.periodProfit, BigInt.zero);
  });

  test('bank matching prevents payment reversal until the match is explicitly retracted', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final payment = f.record(300);
    final statement = f.w.database.importBankStatement(
      id: EntityId.random(),
      businessId: f.w.identity.businessId,
      paymentAccountId: 'fictional-remittance-bank',
      importedAt: start.add(const Duration(seconds: 1)),
      statement: parse(
        'Date,Description,Amount\n2026-09-20,Fictional RMCD payment,-3.00',
      ),
    );
    final bankLine = (await f.w.journals())
        .singleWhere((j) => j.entry.id == payment.journalId)
        .entry
        .lines
        .indexWhere((l) => l.accountId == f.bank);
    f.w.database.acceptStatementMatch(
      businessId: f.w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      journalId: payment.journalId,
      lineIndex: bankLine,
      actorId: f.w.identity.ownerId,
      acceptedAt: start.add(const Duration(seconds: 2)),
    );
    final before = tables(f.w);
    final request = EntityId.random();
    TaxRemittanceCorrection reverse() => f.w.correctTaxRemittance(
      requestId: request,
      reviewedRemittance: payment,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 4)),
      reason: 'Fictional payment correction',
    );
    expect(reverse, throwsStateError);
    expect(tables(f.w), before);
    f.w.database.retractStatementMatch(
      businessId: f.w.identity.businessId,
      acceptanceId: f.w.database.statementMatchAcceptanceId(
        f.w.identity.businessId,
        statement,
        2,
      )!,
      actorId: f.w.identity.ownerId,
      retractedAt: start.add(const Duration(seconds: 3)),
      reason: 'Fictional incorrect payment match',
    );
    reverse();
    expect((await report(f.w)).remittedTax, BigInt.zero);
  });

  test('foreign company journal/agency/account and unsupported payment profile cannot cross the owner boundary', () async {
    final f = await setup(), other = await setup();
    addTearDown(f.w.dispose);
    addTearDown(other.w.dispose);
    final foreign = await manual(other, 100), local = await manual(f, 100);
    final before = tables(f.w);
    for (final defect in ['journal', 'agency', 'account', 'profile']) {
      expect(
        () => f.w.linkTaxRemittance(
          requestId: EntityId.random(),
          reviewedJournal: defect == 'journal' ? foreign : local,
          paymentAccountId: defect == 'profile'
              ? 'missing-company-profile'
              : 'fictional-remittance-bank',
          allocations: [
            f.allocation(
              100,
              to: defect == 'agency' ? other.agency : null,
              account: defect == 'account' ? other.sales.tax : null,
            ),
          ],
          reference: 'Fictional invalid $defect',
          recordedAt: start,
        ),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
      expect(tables(f.w), before);
    }
  });

  test('agency edits preserve frozen records and idempotent retry while new old-agency selections are rejected', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final request = EntityId.random(), saved = f.record(200, request: request);
    f.w.saveTaxAgency(
      agency(
        id: f.agency.id,
        revision: f.agency.revision,
        registration: 'Fictional updated registration',
      ),
    );
    final before = tables(f.w);
    expect(f.record(200, request: request).toJson(), saved.toJson());
    expect(
      f.w.taxRemittances().single.allocations.single.agency.registrationNumber,
      f.agency.registrationNumber,
    );
    expect(
      () => f.record(50, at: start.add(const Duration(seconds: 1))),
      throwsStateError,
    );
    expect(tables(f.w), before);
    final restored = await AccountingWorkspace.emptyRestore(
      ':memory:',
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        start.add(const Duration(seconds: 2)),
      ),
    );
    addTearDown(restored.dispose);
    expect(restored.taxRemittances().single.toJson(), saved.toJson());
  });

  test('original evidence survives restart; data-only recovery preserves identity/checksum and reports unavailable bytes', () async {
    final dir = Directory.systemTemp.createTempSync(
      'audyt-remittance-evidence-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite', f = await setup(path: path);
    final evidence = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'fictional-tax-payment-original',
        batchId: 'fictional-tax-payment-batch',
        filename: 'Fictional Tax Payment.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(
          '%PDF-fictional remittance evidence'.codeUnits,
        ),
      ),
    );
    final saved = f.w.recordTaxRemittance(
      requestId: EntityId.random(),
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(200)],
      paidOn: DateTime.utc(2026, 9, 20),
      reference: 'Fictional attached evidence',
      recordedAt: start,
      attachments: [evidence],
    );
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      start.add(const Duration(seconds: 1)),
    );
    f.w.dispose();
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(
      w.taxRemittances().single.attachments.single.originalBytes,
      evidence.originalBytes,
    );
    final restored = await AccountingWorkspace.emptyRestore(
      ':memory:',
      archive,
    );
    addTearDown(restored.dispose);
    final recovered = restored.taxRemittances().single.attachments.single;
    expect(recovered.originalId, evidence.originalId);
    expect(recovered.originalSha256, evidence.originalSha256);
    expect(recovered.originalBytes, isEmpty);
    expect((await report(restored)).remittedTax, BigInt.from(200));
    final data = editTable(archive, 'tax_remittances', (columns, rows) {
      final row = rows.single as List,
          payload =
              jsonDecode(row[columns.indexOf('payload')] as String) as Map;
      ((payload['attachments'] as List).single as Map)['originalSha256'] =
          'forged';
      row[columns.indexOf('payload')] = jsonEncode(payload);
    });
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    expect(() => empty.restoreDataArchive(envelope(data)), throwsA(anything));
    empty.restoreDataArchive(archive);
    expect(empty.readTaxRemittances(saved.businessId).single.id, saved.id);
  });

  test('report rejects payment over-allocation and account mismatch independently of database persistence', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final saved = f.record(100), base = await report(f.w);
    TaxActivityReport forged(TaxRemittanceAllocation allocation) =>
        TaxActivityReport.build(
          ledger: base.ledger,
          activity: base.rows,
          taxAccountIds: base.accounts.map((a) => a.balance.account.id).toSet(),
          remittanceActivity: [
            TaxRemittanceActivity(
              source: TaxRemittance(
                id: saved.id,
                businessId: saved.businessId,
                actorId: saved.actorId,
                journalId: saved.journalId,
                journalRevision: saved.journalRevision,
                journalFingerprint: saved.journalFingerprint,
                origin: saved.origin,
                bankAccountId: saved.bankAccountId,
                paymentAccountId: saved.paymentAccountId,
                paidOn: saved.paidOn,
                recordedAt: saved.recordedAt,
                reference: saved.reference,
                memo: saved.memo,
                allocations: [allocation],
              ),
              allocation: allocation,
            ),
          ],
        );
    expect(() => forged(f.allocation(101)), throwsStateError);
    expect(
      () => forged(f.allocation(100, account: f.sales.income)),
      throwsStateError,
    );
  });

  test('locked bank rejects new posting and reversal, preserving already-recorded history', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final saved = f.record(200),
        bank = (await f.w.accounts()).singleWhere(
          (a) => a.account.id == f.bank,
        );
    await f.w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: bank.account.id,
          code: bank.account.code,
          name: bank.account.name,
          type: bank.account.type,
          status: AccountStatus.locked,
        ),
        metadata: bank.metadata.nextRevision(
          updatedAt: bank.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
    final before = tables(f.w);
    expect(
      () => f.record(100, at: start.add(const Duration(seconds: 1))),
      throwsStateError,
    );
    expect(
      () => f.w.correctTaxRemittance(
        requestId: EntityId.random(),
        reviewedRemittance: saved,
        on: DateTime.utc(2026, 9, 22),
        recordedAt: start.add(const Duration(seconds: 2)),
        reason: 'Fictional locked-bank reversal',
      ),
      throwsStateError,
    );
    expect(tables(f.w), before);
    expect((await report(f.w)).remittedTax, BigInt.from(200));
    final restored = await AccountingWorkspace.emptyRestore(
      ':memory:',
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        start.add(const Duration(seconds: 3)),
      ),
    );
    addTearDown(restored.dispose);
    expect(restored.taxRemittances().single.toJson(), saved.toJson());
  });

  test('recovery rejects coordinated over-allocation even when individual signature and audit are internally consistent', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final journal = await manual(f, 500);
    f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: journal,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(300)],
      reference: 'Fictional first allocation',
      recordedAt: start,
    );
    final second = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: journal,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(100)],
      reference: 'Fictional second allocation',
      recordedAt: start.add(const Duration(seconds: 1)),
    );
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      start.add(const Duration(seconds: 2)),
    );
    final data = body(archive),
        table = (data['tables'] as Map)['tax_remittances'] as Map,
        columns = table['columns'] as List;
    final row = (table['rows'] as List).singleWhere(
      (r) => r[columns.indexOf('id')] == second.id.value,
    ) as List;
    final payload =
        jsonDecode(row[columns.indexOf('payload')] as String) as Map;
    ((payload['allocations'] as List).single as Map)['amountMinor'] = 400;
    final signature =
        jsonDecode(row[columns.indexOf('signature')] as String) as List;
    signature[7] = payload['allocations'];
    row[columns.indexOf('payload')] = jsonEncode(payload);
    row[columns.indexOf('signature')] = jsonEncode(signature);
    final audit = (data['tables'] as Map)['ledger_audit'] as Map,
        auditColumns = audit['columns'] as List;
    final event = (audit['rows'] as List).singleWhere(
      (r) =>
          r[auditColumns.indexOf('kind')] == 'tax.remittance_recorded' &&
          r[auditColumns.indexOf('subject_id')] == second.id.value,
    ) as List;
    event[auditColumns.indexOf('detail')] = jsonEncode(payload);
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    expect(
      () => empty.restoreDataArchive(envelope(data)),
      throwsFormatException,
    );
    empty.restoreDataArchive(archive);
    expect(empty.readTaxRemittances(f.w.identity.businessId), hasLength(2));
  });

  test('secondary combined bank-match member blocks dedicated and generic remittance reversal', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final first = f.record(
      100,
      request: EntityId.parse('00000000-0000-4000-8000-000000000001'),
    );
    final second = f.record(
      200,
      request: EntityId.parse('00000000-0000-4000-8000-000000000002'),
      at: start.add(const Duration(seconds: 1)),
    );
    final statement = f.w.database.importBankStatement(
      id: EntityId.random(),
      businessId: f.w.identity.businessId,
      paymentAccountId: 'fictional-remittance-bank',
      importedAt: start.add(const Duration(seconds: 2)),
      statement: parse(
        'Date,Description,Amount\n2026-09-20,Fictional combined remittance,-3.00',
      ),
    );
    final entries = await f.w.journals(),
        original = entries.singleWhere((j) => j.entry.id == second.journalId);
    String movement(TaxRemittance p) {
      final journal = entries.singleWhere((j) => j.entry.id == p.journalId);
      return '${p.journalId.value}:${journal.entry.lines.indexWhere((l) => l.accountId == f.bank)}';
    }

    f.w.database.acceptStatementCombinedMatch(
      businessId: f.w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      movementIds: {movement(first), movement(second)},
      actorId: f.w.identity.ownerId,
      acceptedAt: start.add(const Duration(seconds: 3)),
    );
    expect(
      f.w.database.acceptedStatementMatches(
        f.w.identity.businessId,
        statement,
      )[2],
      movement(first),
    );
    final before = tables(f.w);
    expect(
      () => f.w.correctTaxRemittance(
        requestId: EntityId.random(),
        reviewedRemittance: second,
        on: DateTime.utc(2026, 9, 22),
        recordedAt: start.add(const Duration(seconds: 4)),
        reason: 'Fictional combined payment correction',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reason',
          contains('bank statement match'),
        ),
      ),
    );
    expect(tables(f.w), before);
    final reversed = original.entry.reversal(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 22),
      memo: 'Fictional generic combined reversal',
    );
    await f.w.saveJournal(
      date: reversed.date,
      memo: reversed.memo,
      lines: reversed.lines,
    );
    final draft = (await f.w.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    final marked = StoredJournalEntry(
      entry: JournalEntry.restore(
        id: draft.entry.id,
        date: reversed.date,
        memo: reversed.memo,
        lines: reversed.lines,
        state: JournalEntryState.draft,
        reversesId: second.journalId,
      ),
      metadata: draft.metadata.nextRevision(
        updatedAt: start.add(const Duration(seconds: 4)),
      ),
    );
    await f.w.database.save(marked);
    final guard = tables(f.w);
    await expectLater(
      f.w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: f.w.identity.businessId,
          journalId: marked.entry.id,
          expectedRevision: 2,
          actorId: f.w.identity.ownerId,
          approvedAt: start.add(const Duration(seconds: 5)),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reason',
          contains('bank statement match'),
        ),
      ),
    );
    expect(tables(f.w), guard);
    f.w.database.retractStatementMatch(
      businessId: f.w.identity.businessId,
      acceptanceId: f.w.database.statementMatchAcceptanceId(
        f.w.identity.businessId,
        statement,
        2,
      )!,
      actorId: f.w.identity.ownerId,
      retractedAt: start.add(const Duration(seconds: 6)),
      reason: 'Fictional combined match correction',
    );
    f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: second,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 7)),
      reason: 'Fictional payment correction after unmatching',
    );
    expect((await report(f.w)).remittedTax, BigInt.from(100));
  });

  test('SQL history protection rejects changing or deleting both payment and correction facts', () async {
    final dir = Directory.systemTemp.createTempSync(
      'audyt-remittance-immutable-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite',
        f = await setup(path: path),
        payment = f.record(100);
    final correction = f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: payment,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 1)),
      reason: 'Fictional immutable correction',
    );
    final before = tables(f.w);
    f.w.dispose();
    final raw = sqlite3.open(path);
    for (final table in ['tax_remittances', 'tax_remittance_corrections']) {
      expect(
        () => raw.execute('UPDATE $table SET payload=?', ['{}']),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute('DELETE FROM $table'),
        throwsA(isA<SqliteException>()),
      );
    }
    raw.dispose();
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(tables(w), before);
    expect(
      w.taxRemittances(includeCorrected: true).single.toJson(),
      payment.toJson(),
    );
    expect(
      w.database
          .readTaxRemittanceCorrection(w.identity.businessId, payment.id)!
          .toJson(),
      correction.toJson(),
    );
  });

  test('eligible choices are immutable read-only budgets; allocation/unlink/reversal refresh them without a new posting', () async {
    final f = await setup();
    addTearDown(f.w.dispose);
    final source = await manual(f, 500);
    await manual(f, 100, expense: true);
    final before = tables(f.w),
        choices = f.w.taxRemittanceCandidates('fictional-remittance-bank');
    expect(choices, hasLength(1));
    expect(choices.single.journal.entry.id, source.entry.id);
    expect(choices.single.available.minorUnits, 500);
    expect(
      f.w.taxRemittancePaymentAccounts.single.id,
      'fictional-remittance-bank',
    );
    expect(f.w.taxRemittanceLiabilityAccounts.single.account.id, f.sales.tax);
    expect(tables(f.w), before);
    expect(() => choices.single.remaining.clear(), throwsUnsupportedError);
    final first = f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: choices.single.journal,
      paymentAccountId: choices.single.paymentAccountId,
      allocations: [f.allocation(300)],
      reference: 'Fictional partial candidate',
      recordedAt: start,
    );
    expect(
      f.w
          .taxRemittanceCandidates('fictional-remittance-bank')
          .single
          .available
          .minorUnits,
      200,
    );
    f.w.linkTaxRemittance(
      requestId: EntityId.random(),
      reviewedJournal: source,
      paymentAccountId: 'fictional-remittance-bank',
      allocations: [f.allocation(200)],
      reference: 'Fictional complete candidate',
      recordedAt: start.add(const Duration(seconds: 1)),
    );
    expect(f.w.taxRemittanceCandidates('fictional-remittance-bank'), isEmpty);
    f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: first,
      on: source.entry.date,
      recordedAt: start.add(const Duration(seconds: 2)),
      reason: 'Fictional refreshed attribution',
    );
    expect(
      f.w
          .taxRemittanceCandidates('fictional-remittance-bank')
          .single
          .available
          .minorUnits,
      300,
    );
    final recorded = f.record(100, at: start.add(const Duration(seconds: 3)));
    f.w.correctTaxRemittance(
      requestId: EntityId.random(),
      reviewedRemittance: recorded,
      on: DateTime.utc(2026, 9, 22),
      recordedAt: start.add(const Duration(seconds: 4)),
      reason: 'Fictional reversed payment',
    );
    expect(
      f.w
          .taxRemittanceCandidates('fictional-remittance-bank')
          .map((c) => c.journal.entry.id),
      [source.entry.id],
    );
  });

  test('eligible read excludes unsupported/unlinked/wrong-currency/locked profiles and foreign company budgets', () async {
    final f = await setup(), other = await setup();
    addTearDown(f.w.dispose);
    addTearDown(other.w.dispose);
    await manual(f, 100);
    for (final entry in [
      ('card', PaymentAccountType.card, 'MYR'),
      ('foreign-currency', PaymentAccountType.bank, 'USD'),
      ('unlinked', PaymentAccountType.bank, 'MYR'),
    ]) {
      f.w.database.savePaymentAccount(
        f.w.identity.businessId,
        PaymentAccount.create(
          id: entry.$1,
          name: 'Fictional ${entry.$1}',
          type: entry.$2,
          currencyCode: entry.$3,
        ),
      );
    }
    final before = tables(f.w);
    expect(f.w.taxRemittancePaymentAccounts.map((p) => p.id), [
      'fictional-remittance-bank',
    ]);
    expect(
      other.w.taxRemittanceCandidates('fictional-remittance-bank'),
      isEmpty,
    );
    for (final name in ['card', 'foreign-currency', 'unlinked']) {
      expect(() => f.w.taxRemittanceCandidates(name), throwsStateError);
    }
    expect(tables(f.w), before);
    final bank = (await f.w.accounts()).singleWhere(
      (a) => a.account.id == f.bank,
    );
    await f.w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: bank.account.id,
          code: bank.account.code,
          name: bank.account.name,
          type: bank.account.type,
          status: AccountStatus.locked,
        ),
        metadata: bank.metadata.nextRevision(
          updatedAt: bank.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
    expect(f.w.taxRemittancePaymentAccounts, isEmpty);
    expect(
      () => f.w.taxRemittanceCandidates('fictional-remittance-bank'),
      throwsStateError,
    );
  });
}
