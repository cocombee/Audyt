import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'bill_settlement_test.dart' show allocation, settlementFixture;

void main() {
  test(
    'unpaid Bill reversal retains history and removes only current payable',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-bill-reversal-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      final (w, ids, _, _) = await settlementFixture(path);
      addTearDown(w.dispose);
      final source = w.database.readBillDraft(
        w.identity.businessId,
        ids.first,
      )!;
      final posting = w.database.readBillPosting(
        w.identity.businessId,
        source.id,
      )!;
      final before = w.database.payablesAgeing(
        businessId: w.identity.businessId,
        currency: 'MYR',
        asOf: DateTime.utc(2026, 9, 28),
      );
      expect(before.outstandingMinor, BigInt.from(source.total.minorUnits * 2));
      final request = EntityId.random();
      EntityId reverse() => w.reverseBillRecognition(
        requestId: request,
        reviewedBill: source,
        expectedRecognitionJournalId: posting.journalId,
        reversedOn: DateTime.utc(2026, 9, 29),
        reason: 'Supplier bill was duplicated',
        approvedAt: DateTime.utc(2026, 9, 29, 12),
      );
      expect(reverse(), request);
      final saved = tables(w);
      final taxBefore = await w.taxActivity(
        from: DateTime.utc(2026, 9, 1),
        through: DateTime.utc(2026, 9, 28),
      );
      final taxAfter = await w.taxActivity(
        from: DateTime.utc(2026, 9, 29),
        through: DateTime.utc(2026, 9, 29),
      );
      final originalTax = taxBefore.rows
          .where((r) => r.sourceId == source.id)
          .fold(BigInt.zero, (sum, r) => sum + r.taxMinor!);
      expect(
        taxAfter.rows.every((r) => r.isReversal && r.sourceId == source.id),
        isTrue,
      );
      expect(taxAfter.purchaseTaxInCost, -originalTax);
      expect(
        taxAfter.rows.fold(BigInt.zero, (sum, r) => sum + r.grossMinor),
        -BigInt.from(source.total.minorUnits),
      );
      expect(
        tables(w),
        saved,
        reason: 'Reversal activity reads never change the source.',
      );
      expect(reverse(), request);
      expect(tables(w), saved);
      final reversed = w.database.readBillReversal(
        w.identity.businessId,
        source.id,
      )!;
      expect(reversed.sourceJournalId, posting.journalId);
      expect(reversed.journalId, request);
      expect(
        w.database.readBillPosting(w.identity.businessId, source.id),
        isNotNull,
      );
      expect(
        w.database.billOutstanding(w.identity.businessId, source.id).isZero,
        isTrue,
      );
      expect(
        w.database.billOutstanding(
          w.identity.businessId,
          source.id,
          asOf: DateTime.utc(2026, 9, 28),
        ),
        source.total,
      );
      expect(
        w.database.payableBillPage(businessId: w.identity.businessId).total,
        1,
      );
      final after = w.database.payablesAgeing(
        businessId: w.identity.businessId,
        currency: 'MYR',
        asOf: DateTime.utc(2026, 9, 29),
      );
      expect(after.outstandingMinor, BigInt.from(source.total.minorUnits));
      expect(after.controls.single.differenceMinor, BigInt.zero);
      expect(
        w.database
            .payablesAgeing(
              businessId: w.identity.businessId,
              currency: 'MYR',
              asOf: DateTime.utc(2026, 9, 28),
            )
            .outstandingMinor,
        before.outstandingMinor,
      );
      expect(
        () => w.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(source.id, source.total.minorUnits, 100)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'No payment after reversal',
          paidOn: DateTime.utc(2026, 9, 30),
          approvedAt: DateTime.utc(2026, 9, 30, 12),
        ),
        throwsStateError,
      );
      expect(tables(w), saved);
      final archive = w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 9, 30),
      );
      final restored = await AccountingWorkspace.emptyRestore(
        '${root.path}/restored.sqlite',
        archive,
      );
      addTearDown(restored.dispose);
      expect(
        restored.database
            .readBillReversal(restored.identity.businessId, source.id)!
            .journalId,
        request,
      );
      expect(
        restored.database
            .payableBillPage(businessId: restored.identity.businessId)
            .total,
        1,
      );
      expect(tables(restored), saved);
    },
  );

  for (final failure in [
    'foreign company',
    'foreign actor',
    'wrong source',
    'stale review',
    'paid Bill',
    'closed period',
    'injected storage failure',
  ]) {
    test('Bill reversal rejects $failure atomically', () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-bill-reversal-fail-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      final (w, ids, _, _) = await settlementFixture(path);
      addTearDown(w.dispose);
      final source = w.database.readBillDraft(
        w.identity.businessId,
        ids.first,
      )!;
      final posting = w.database.readBillPosting(
        w.identity.businessId,
        source.id,
      )!;
      if (failure == 'paid Bill') {
        w.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(source.id, source.total.minorUnits, 100)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'Existing payment',
          paidOn: DateTime.utc(2026, 9, 28),
          approvedAt: DateTime.utc(2026, 9, 28, 2),
        );
      }
      if (failure == 'closed period') {
        await w.database.closeThrough(
          businessId: w.identity.businessId,
          date: DateTime.utc(2026, 9, 29),
          actorId: w.identity.ownerId,
          changedAt: DateTime.utc(2026, 9, 30),
          reason: 'Period review',
        );
      }
      final raw = sqlite3.open(path);
      addTearDown(raw.dispose);
      if (failure == 'injected storage failure') {
        raw.execute(
          "CREATE TRIGGER reject_bill_reversal BEFORE INSERT ON bill_posting_reversals BEGIN SELECT RAISE(ABORT,'injected failure'); END",
        );
      }
      final before = tables(w);
      expect(
        () => w.database.reverseBillRecognition(
          businessId: failure == 'foreign company'
              ? EntityId.random()
              : w.identity.businessId,
          actorId: failure == 'foreign actor'
              ? EntityId.random()
              : w.identity.ownerId,
          requestId: EntityId.random(),
          reviewedBill: failure == 'stale review'
              ? PurchaseBillDraft.fromJson({
                  ...source.toJson(),
                  'memo': 'Unreviewed change',
                })
              : source,
          expectedRecognitionJournalId: failure == 'wrong source'
              ? EntityId.random()
              : posting.journalId,
          reversedOn: DateTime.utc(2026, 9, 29),
          reason: 'Correct source',
          approvedAt: DateTime.utc(2026, 9, 29, 12),
        ),
        failure == 'injected storage failure'
            ? throwsA(isA<SqliteException>())
            : throwsStateError,
      );
      expect(tables(w), before);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test(
    'schema 42 upgrade adds empty immutable Bill reversal history',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-bill-reversal-upgrade-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      final (initial, ids, _, _) = await settlementFixture(path);
      final bill = ids.first;
      initial.dispose();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      raw.execute('DROP TABLE bill_posting_reversals');
      raw.execute('DROP TABLE bill_settlement_reversals');
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
      raw.execute('PRAGMA user_version=42');
      raw.dispose();
      final upgraded = await AccountingWorkspace.open(path);
      addTearDown(upgraded.dispose);
      expect(
        upgraded.database.readBillPosting(upgraded.identity.businessId, bill),
        isNotNull,
      );
      expect(
        upgraded.database.readBillReversal(upgraded.identity.businessId, bill),
        isNull,
      );
      expect(tables(upgraded)['bill_posting_reversals']['rows'], isEmpty);
      expect(tables(upgraded)['bill_settlement_reversals']['rows'], isEmpty);
    },
  );
}
