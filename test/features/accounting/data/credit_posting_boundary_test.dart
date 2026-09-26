import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/sales/domain/customer_statement_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/credit_posting_fixture.dart';

// Raw rows, including original evidence payloads, rather than metadata-only export.
Map<String, Object?> rawTables(Database raw) => {
  for (final row in raw.select(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  ))
    row['name'] as String: [
      for (final record in raw.select(
        'SELECT * FROM "${row['name']}" ORDER BY rowid',
      ))
        Map<String, Object?>.from(record),
    ],
};

void main() {
  for (final failure in [
    'unauthorized',
    'foreign company',
    'missing draft',
    'stale revision',
    'stale payment',
    'stale prior credit',
    'missing evidence',
    'early approval',
    'missing liability',
    'asset liability',
    'tax liability',
    'foreign liability',
    'archived liability',
    'parent liability',
    'archived original income',
    'archived original tax',
    'archived original receivable',
    'closed period',
    'line write failure',
    'audit write failure',
  ]) {
    test('credit rejects $failure and preserves every raw table', () async {
      final f = await creditPostingFixture(
        paidMinor: 8000,
        evidence: failure != 'missing evidence',
      );
      final w = f.w;
      final raw = sqlite3.open(f.path);
      addTearDown(raw.dispose);
      if (failure == 'closed period') {
        await w.database.closeThrough(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          date: DateTime.utc(2026, 9, 6),
          changedAt: DateTime.utc(2026, 9, 7),
          reason: 'Fictional period review',
        );
      }
      final archived = switch (failure) {
        'archived liability' => f.liability,
        'archived original income' => f.income,
        'archived original tax' => f.tax,
        'archived original receivable' => f.receivable,
        _ => null,
      };
      if (archived != null) {
        raw.execute("UPDATE accounts SET status='archived' WHERE id=?", [
          archived.value,
        ]);
      }
      if (failure == 'parent liability') {
        raw.execute('UPDATE accounts SET is_parent=1 WHERE id=?', [
          f.liability.value,
        ]);
      }
      if (failure == 'line write failure') {
        raw.execute(
          "CREATE TRIGGER fail_credit BEFORE INSERT ON invoice_credit_lines BEGIN SELECT RAISE(ABORT,'injected line failure'); END",
        );
      }
      if (failure == 'audit write failure') {
        raw.execute(
          "CREATE TRIGGER fail_credit BEFORE INSERT ON ledger_audit WHEN NEW.kind='invoice_credit_posted' BEGIN SELECT RAISE(ABORT,'injected audit failure'); END",
        );
      }
      final liability = switch (failure) {
        'missing liability' => null,
        'asset liability' => f.bank,
        'tax liability' => f.tax,
        'foreign liability' => EntityId.random(),
        _ => f.liability,
      };
      final before = rawTables(raw);
      expect(
        () => w.database.postInvoiceCredit(
          businessId: failure == 'foreign company'
              ? EntityId.random()
              : w.identity.businessId,
          actorId: failure == 'unauthorized'
              ? EntityId.random()
              : w.identity.ownerId,
          requestId: EntityId.random(),
          draftId: failure == 'missing draft' ? EntityId.random() : f.creditId,
          expectedRevision: failure == 'stale revision' ? 0 : 1,
          expectedPaidMinor: failure == 'stale payment' ? 0 : 8000,
          expectedPriorCreditMinor: failure == 'stale prior credit' ? 1 : 0,
          approvedAt: DateTime.utc(
            2026,
            9,
            failure == 'early approval' ? 5 : 7,
          ),
          customerCreditAccount: liability,
        ),
        throwsA(
          failure.endsWith('write failure')
              ? isA<SqliteException>()
              : isA<StateError>(),
        ),
      );
      expect(rawTables(raw), before);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('reviewed credit posts once, notifies linked pages, balances ledger and preserves typed statement on restart', () async {
    final f = await creditPostingFixture(paidMinor: 8000);
    var w = f.w;
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    var notifications = 0;
    w.addListener(() => notifications++);
    final review = w.reviewCreditDraft(f.creditId);
    final request = EntityId.random();
    EntityId post({EntityId? requestId, int? paid}) => w.postInvoiceCredit(
      requestId: requestId ?? request,
      draftId: f.creditId,
      expectedRevision: review.draft.revision,
      expectedPaidMinor: paid ?? review.paidMinor,
      expectedPriorCreditMinor: review.priorCreditMinor,
      approvedAt: DateTime.utc(2026, 9, 7),
      customerCreditAccount: f.liability,
    );
    expect(() => post(paid: 0), throwsStateError);
    expect(notifications, 0);
    expect(post(), request);
    expect(notifications, 1);
    final once = rawTables(raw);
    expect(post(), request);
    expect(rawTables(raw), once);
    expect(() => post(paid: 0), throwsStateError);
    expect(() => post(requestId: EntityId.random()), throwsStateError);
    expect(rawTables(raw), once);
    final journal = (await w.journals())
        .singleWhere((j) => j.entry.id == request)
        .entry;
    expect(
      journal.lines.fold<int>(
        0,
        (sum, line) =>
            sum +
            (line.isDebit ? line.amount.minorUnits : -line.amount.minorUnits),
      ),
      0,
    );
    expect(await creditLedgerBalance(w, f.bank), 8000);
    expect(await creditLedgerBalance(w, f.receivable), 0);
    expect(await creditLedgerBalance(w, f.liability), -2600);
    final statement = w.database.customerStatement(
      w.identity.businessId,
      f.customer.id,
      DateTime.utc(2026, 9, 7),
    );
    expect(statement.map((r) => r.activity), [
      CustomerStatementActivity.invoice,
      CustomerStatementActivity.payment,
      CustomerStatementActivity.credit,
    ]);
    expect(statement.map((r) => r.balance.minorUnits), [10800, 2800, -2600]);
    expect(
      w.database
          .customerStatement(
            w.identity.businessId,
            f.customer.id,
            DateTime.utc(2026, 9, 5),
          )
          .last
          .balance
          .minorUnits,
      2800,
    );
    expect(
      w.database.receivablesAsOf(
        w.identity.businessId,
        DateTime.utc(2026, 9, 7),
      ),
      isEmpty,
    );
    w.dispose();
    w = await AccountingWorkspace.open(f.path);
    addTearDown(w.dispose);
    expect(rawTables(raw), once);
    expect(
      w.database.customerStatement(
        w.identity.businessId,
        f.customer.id,
        DateTime.utc(2026, 9, 7),
      ),
      statement,
    );
  });

  test('a second actual credit invalidates a captured review without another posting', () async {
    final f = await creditPostingFixture();
    final w = f.w;
    final review = w.reviewCreditDraft(f.creditId);
    final second = EntityId.random();
    w.saveInvoiceCreditDraft(
      draftId: second,
      invoiceId: f.invoice.id,
      lineCredits: {f.invoice.lines.single.id: Money.fromMinor(1080, 'MYR')},
      reason: 'Fictional second credit',
      creditDate: DateTime.utc(2026, 9, 6),
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 6),
      attachments: review.draft.attachments,
    );
    w.postInvoiceCredit(
      requestId: EntityId.random(),
      draftId: second,
      expectedRevision: 1,
      expectedPaidMinor: 0,
      expectedPriorCreditMinor: 0,
      approvedAt: DateTime.utc(2026, 9, 7),
    );
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    final before = rawTables(raw);
    expect(
      () => w.postInvoiceCredit(
        requestId: EntityId.random(),
        draftId: f.creditId,
        expectedRevision: review.draft.revision,
        expectedPaidMinor: review.paidMinor,
        expectedPriorCreditMinor: review.priorCreditMinor,
        approvedAt: DateTime.utc(2026, 9, 7),
      ),
      throwsStateError,
    );
    expect(rawTables(raw), before);
    expect(w.reviewCreditDraft(f.creditId).priorCreditMinor, 1080);
  });

  test('data-only recovery cannot post a draft whose evidence bytes are unavailable', () async {
    final f = await creditPostingFixture();
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 9, 7),
    );
    final copyPath = '${File(f.path).parent.path}/copy.sqlite';
    final w = await AccountingWorkspace.emptyRestore(copyPath, archive);
    addTearDown(w.dispose);
    final raw = sqlite3.open(copyPath);
    addTearDown(raw.dispose);
    final before = rawTables(raw);
    expect(
      () => w.postInvoiceCredit(
        requestId: EntityId.random(),
        draftId: f.creditId,
        expectedRevision: 1,
        expectedPaidMinor: 0,
        expectedPriorCreditMinor: 0,
        approvedAt: DateTime.utc(2026, 9, 7),
      ),
      throwsStateError,
    );
    expect(rawTables(raw), before);
  });
  for (final paidMinor in [0, 8000]) {
    test(
      'invoice, receipt and credit reconcile yearly financial reports paid $paidMinor',
      () async {
        final f = await creditPostingFixture(paidMinor: paidMinor);
        final w = f.w;
        final before = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 9, 5),
        );
        expect(before.revenue, BigInt.from(10000));
        expect(before.periodProfit, BigInt.from(10000));
        expect(before.assets, BigInt.from(10800));
        expect(before.isBalanced, isTrue);
        w.postInvoiceCredit(
          requestId: EntityId.random(),
          draftId: f.creditId,
          expectedRevision: 1,
          expectedPaidMinor: paidMinor,
          expectedPriorCreditMinor: 0,
          approvedAt: DateTime.utc(2026, 9, 7),
          customerCreditAccount: paidMinor == 0 ? null : f.liability,
        );
        final yearly = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(yearly.revenue, BigInt.from(5000));
        expect(yearly.expenses, BigInt.zero);
        expect(yearly.periodProfit, BigInt.from(5000));
        expect(yearly.assets, BigInt.from(paidMinor == 0 ? 5400 : 8000));
        expect(yearly.liabilities, BigInt.from(paidMinor == 0 ? 400 : 3000));
        expect(yearly.totalEquity, BigInt.from(5000));
        expect(yearly.trialBalanceDebits, yearly.trialBalanceCredits);
        expect(yearly.balanceSheetDifference, BigInt.zero);
        final nextYear = await w.report(
          from: DateTime.utc(2027),
          through: DateTime.utc(2027, 12, 31),
        );
        expect(nextYear.periodProfit, BigInt.zero);
        expect(nextYear.assets, yearly.assets);
        expect(nextYear.liabilities, yearly.liabilities);
        expect(nextYear.totalEquity, yearly.totalEquity);
        expect(nextYear.isBalanced, isTrue);
        w.dispose();
        final reopened = await AccountingWorkspace.open(f.path);
        addTearDown(reopened.dispose);
        final restarted = await reopened.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(restarted.periodProfit, yearly.periodProfit);
        expect(restarted.trialBalanceDebits, yearly.trialBalanceDebits);
        expect(restarted.isBalanced, isTrue);
      },
    );
  }
}
