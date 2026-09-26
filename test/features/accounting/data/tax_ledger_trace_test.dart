import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/tax_activity_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/sales_report_fixture.dart';
import '../../../app/restored_page_routes_test.dart' show tables;
import 'tax_agency_wiring_test.dart' show agency, code, post;

Future<void> manual(SalesReportFixture f, DateTime date, int amount) async {
  final w = f.workspace;
  await w.saveJournal(
    date: date,
    memo: 'Fictional reviewed ledger movement',
    lines: [
      JournalLine.debit(
        accountId: amount < 0 ? f.tax : f.receivable,
        amount: Money.fromMinor(amount.abs(), 'MYR'),
      ),
      JournalLine.credit(
        accountId: amount < 0 ? f.receivable : f.tax,
        amount: Money.fromMinor(amount.abs(), 'MYR'),
      ),
    ],
  );
  final journal = (await w.journals()).singleWhere(
    (j) => j.entry.state == JournalEntryState.draft,
  );
  await w.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: w.identity.businessId,
      journalId: journal.entry.id,
      expectedRevision: 1,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    ),
  );
}

Future<TaxActivityReport> report(AccountingWorkspace w) => w.taxActivity(
  from: DateTime.utc(2026, 9),
  through: DateTime.utc(2026, 9, 30),
);

TaxActivityRow changed(
  TaxActivityRow row, {
  int delta = 0,
  DateTime? date,
  bool? reversal,
  bool partial = false,
  EntityId? account,
}) => TaxActivityRow(
  sourceId: row.sourceId,
  journalId: row.journalId,
  lineId: row.lineId,
  date: date ?? row.date,
  kind: row.kind,
  documentNumber: row.documentNumber,
  description: row.description,
  basis: row.basis,
  netMinor: partial ? null : row.netMinor,
  taxMinor: row.taxMinor! + BigInt.from(delta),
  grossMinor: row.grossMinor + BigInt.from(delta),
  code: row.code,
  ratePercent: row.ratePercent,
  taxAccountId: account ?? row.taxAccountId,
  isReversal: reversal ?? row.isReversal,
);

void main() {
  test('actual source and offsetting manual movements retain exact per-journal trace across restart', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-tax-trace-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await salesReportFixture(path: path, seedInvoices: false);
    var w = f.workspace;
    final savedAgency = w.saveTaxAgency(agency());
    final rate = w.saveTaxRate(code(savedAgency, account: f.tax));
    await manual(f, DateTime.utc(2026, 8, 31), 1000);
    post(f, rate, 'FICTIONAL-TAX-TRACE');
    await manual(f, DateTime.utc(2026, 9, 4), -300);
    await manual(f, DateTime.utc(2026, 9, 5), 300);
    await manual(f, DateTime.utc(2026, 10), -100);
    final before = tables(w);
    final activity = await report(w);
    final account = activity.accounts.single;
    expect(account.openingCredit, BigInt.from(1000));
    expect(account.closingCredit, BigInt.from(1800));
    expect(account.sourceSalesTax, BigInt.from(800));
    expect(account.otherMovementCredit, BigInt.zero);
    expect(
      account.movements,
      hasLength(3),
      reason: 'Net zero must not hide the two manual movements.',
    );
    expect(account.movements.map((m) => m.movementCredit), [
      BigInt.from(800),
      BigInt.from(-300),
      BigInt.from(300),
    ]);
    expect(
      account.movements.first.sourceRows.single.code!.agencySnapshot!.toJson(),
      savedAgency.toJson(),
    );
    expect(
      account.movements
          .skip(1)
          .every((m) => !m.hasSourceTax && m.sourceRows.isEmpty),
      isTrue,
      reason: 'An unmatched tax debit is not inferred to be an agency payment.',
    );
    expect(() => account.movements.clear(), throwsUnsupportedError);
    expect(
      () => account.movements.first.sourceRows.clear(),
      throwsUnsupportedError,
    );
    expect(
      tables(w),
      before,
      reason: 'The read-only trace must not post or label payments.',
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final reopened = (await report(w)).accounts.single;
    expect(
      reopened.movements.map((m) => m.journal.id),
      account.movements.map((m) => m.journal.id),
    );
    expect(reopened.closingCredit, account.closingCredit);
    expect(tables(w), before);
  });

  for (final defect in ['amount', 'date', 'partial', 'reversal', 'account']) {
    test(
      'rejects source $defect inconsistent with the actual posted tax journal',
      () async {
        final f = await salesReportFixture(seedInvoices: false);
        addTearDown(f.workspace.dispose);
        final rate = f.workspace.saveTaxRate(code(null, account: f.tax));
        post(f, rate, 'FICTIONAL-TRACE-BOUNDARY');
        final original = await report(f.workspace);
        final row = changed(
          original.rows.single,
          delta: defect == 'amount' ? 1 : 0,
          date: defect == 'date' ? DateTime.utc(2026, 9, 2) : null,
          reversal: defect == 'reversal' ? true : null,
          partial: defect == 'partial',
          account: defect == 'account' ? f.receivable : null,
        );
        expect(
          () => TaxActivityReport.build(
            ledger: original.ledger,
            activity: [row],
            taxAccountIds: {f.tax},
          ),
          throwsStateError,
        );
        expect((await report(f.workspace)).salesTax, BigInt.from(800));
      },
    );
  }
}
