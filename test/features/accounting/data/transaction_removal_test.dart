import '../../../support/historical_sqlite_fixture.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/transaction_removal.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_document_template.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/credit_posting_fixture.dart';
import '../../../support/historical_expense_schema.dart';
import '../../purchases/voucher_financial_evidence_test.dart';
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;
import 'bill_posting_test.dart' show payableAccount;
import 'claim_recognition_reversal_test.dart' show claimFixture;
import 'credit_posting_boundary_test.dart' show rawTables;
import 'quotation_persistence_test.dart'
    show quotationWorkspace, quotationDraft;

typedef RemovalFixture = ({AccountingWorkspace w, String path, String id});
final removalAt = DateTime.utc(2027, 1, 1);

Future<RemovalFixture> fixture(
  TransactionRecordKind kind, {
  bool pending = false,
}) async {
  if (kind == TransactionRecordKind.invoiceCredit) {
    final f = await creditPostingFixture();
    return (w: f.w, path: f.path, id: f.creditId.value);
  }
  final root = Directory.systemTemp.createTempSync('audyt-removal-');
  addTearDown(() => root.deleteSync(recursive: true));
  final path = '${root.path}/books.sqlite';
  if (kind == TransactionRecordKind.paymentVoucher) {
    final f = await VoucherFinancialFixture.create(path);
    final w = f.workspace;
    addTearDown(w.dispose);
    final s = w.vouchers.sources.singleWhere((s) => s.id == f.expense.value);
    final v = PaymentVoucher.create(
      id: 'removal-voucher',
      sourceType: s.type,
      sourceId: s.id,
      payee: s.payee,
      amount: s.amount,
      paymentAccount: 'Audit Bank',
      paymentAccountId: s.paymentAccountId,
      paymentMethod: 'Bank Transfer',
      paymentDate: s.date,
      reference: 'Removal fixture',
    );
    pending ? w.vouchers.saveAndSubmit(v) : w.vouchers.save(v);
    return (w: w, path: path, id: v.id);
  }
  if (kind == TransactionRecordKind.quotation) {
    final (w, customer, account) = await quotationWorkspace(path);
    addTearDown(w.dispose);
    final q = quotationDraft(customer, account);
    w.saveQuotationDraft(
      q,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 1),
    );
    return (w: w, path: path, id: q.id.value);
  }
  final w = await AccountingWorkspace.open(path);
  addTearDown(w.dispose);
  if (kind == TransactionRecordKind.claim) {
    final c = ClaimStore.demo().all.first;
    pending ? w.claims.saveAndSubmit(c) : w.claims.saveDraft(c);
    return (w: w, path: path, id: c.id.value);
  }
  final (vendor, account) = await setupBill(w);
  final b = billFixture(w, vendor, account.account.id);
  w.saveBillDraft(b, expectedRevision: 0);
  return (w: w, path: path, id: b.id.value);
}

bool visible(
  AccountingWorkspace w,
  TransactionRecordKind kind,
  String id,
) => switch (kind) {
  TransactionRecordKind.claim => w.claims.byId(EntityId.parse(id)) != null,
  TransactionRecordKind.paymentVoucher => w.vouchers.byId(id) != null,
  TransactionRecordKind.bill =>
    w.database.readBillDraft(w.identity.businessId, EntityId.parse(id)) != null,
  TransactionRecordKind.quotation =>
    w.database.readQuotation(w.identity.businessId, EntityId.parse(id)) != null,
  TransactionRecordKind.invoiceCredit =>
    w.database
        .readInvoiceCreditDrafts(w.identity.businessId)
        .any((c) => c.id.value == id),
};

void main() {
  test('removed pending claims leave review counts without changing the ledger, then return on restore', () async {
    final f = await fixture(TransactionRecordKind.claim, pending: true);
    Future<int> pendingCount() async => (await f.w.claimantStatements(
      from: DateTime.utc(2026, 1, 1),
      through: DateTime.utc(2026, 12, 31),
    )).awaitingReview.length;
    expect(await pendingCount(), 1);
    final before = await f.w.journals();
    f.w.setTransactionRemoved(
      reviewed: f.w.reviewTransactionRemoval(TransactionRecordKind.claim, f.id),
      removed: true,
      changedAt: removalAt,
    );
    expect(await pendingCount(), 0);
    expect(await f.w.journals(), before);
    f.w.setTransactionRemoved(
      reviewed: f.w.reviewTransactionRemoval(TransactionRecordKind.claim, f.id),
      removed: false,
      changedAt: removalAt.add(const Duration(seconds: 1)),
    );
    expect(await pendingCount(), 1);
    expect(await f.w.journals(), before);
  });

  for (final kind in [
    TransactionRecordKind.bill,
    TransactionRecordKind.quotation,
  ]) {
    test(
      '${kind.name} recurring source needs cancellation, not just pause, before removal',
      () async {
        final f = await fixture(kind);
        final schedule = f.w.saveDocumentSchedule(
          id: EntityId.random().value,
          name: 'Source removal test',
          kind: kind == TransactionRecordKind.bill
              ? RecurringDocumentKind.bill
              : RecurringDocumentKind.quotation,
          sourceId: EntityId.parse(f.id),
          sourceRevision: 1,
          expectedRevision: 0,
          schedule: RecurrenceRule(
            startsOn: DateTime(2026, 10, 1),
            unit: RecurrenceUnit.months,
            occurrenceCount: 3,
          ),
        );
        for (final paused in [false, true]) {
          if (paused) f.w.changeDocumentScheduleState(schedule, paused: true);
          final review = f.w.reviewTransactionRemoval(kind, f.id);
          expect(review.canRemove, isFalse);
          expect(
            () => f.w.setTransactionRemoved(
              reviewed: review,
              removed: true,
              changedAt: removalAt,
            ),
            throwsStateError,
          );
        }
        f.w.changeDocumentScheduleState(
          f.w.database.documentSchedules(f.w.identity.businessId).single,
          cancel: true,
        );
        final review = f.w.reviewTransactionRemoval(kind, f.id);
        expect(review.canRemove, isTrue);
        f.w.setTransactionRemoved(
          reviewed: review,
          removed: true,
          changedAt: removalAt,
        );
        expect(
          () => f.w.saveDocumentSchedule(
            id: EntityId.random().value,
            name: 'Cannot schedule removed source',
            kind: schedule.kind,
            sourceId: EntityId.parse(f.id),
            sourceRevision: 1,
            expectedRevision: 0,
            schedule: schedule.schedule,
          ),
          throwsStateError,
        );
      },
    );
  }
  for (final kind in TransactionRecordKind.values) {
    for (final pending in [
      false,
      if (kind == TransactionRecordKind.claim ||
          kind == TransactionRecordKind.paymentVoucher)
        true,
    ]) {
      test(
        '${kind.name} ${pending ? 'pending' : 'draft'} removal retains originals, retries once, reopens and restores',
        () async {
          final f = await fixture(kind, pending: pending);
          final w = f.w;
          final raw = sqlite3.open(f.path);
          addTearDown(raw.dispose);
          final original = rawTables(raw);
          final reviewed = w.reviewTransactionRemoval(kind, f.id);
          expect(reviewed.canRemove, isTrue);
          expect(visible(w, kind, f.id), isTrue);
          expect(
            w.setTransactionRemoved(
              reviewed: reviewed,
              removed: true,
              changedAt: removalAt,
            ),
            1,
          );
          expect(visible(w, kind, f.id), isFalse);
          final removed = rawTables(raw);
          for (final table in original.keys.where(
            (t) => !{
              'ledger_audit',
              'sqlite_sequence',
              'transaction_record_removals',
            }.contains(t),
          )) {
            expect(
              removed[table],
              original[table],
              reason: 'Original $table must remain byte-for-byte unchanged',
            );
          }
          expect(
            w.setTransactionRemoved(
              reviewed: reviewed,
              removed: true,
              changedAt: removalAt,
            ),
            1,
          );
          expect(rawTables(raw), removed);
          final archive = w.database.exportDataArchive(
            w.identity.businessId,
            removalAt.add(const Duration(hours: 1)),
          );
          final restored = await AccountingWorkspace.emptyRestore(
            '${f.path}.restored',
            archive,
          );
          addTearDown(restored.dispose);
          expect(visible(restored, kind, f.id), isFalse);
          expect(restored.removedTransactionPage(kind).total, 1);
          w.dispose();
          final reopened = await AccountingWorkspace.open(f.path);
          addTearDown(reopened.dispose);
          expect(visible(reopened, kind, f.id), isFalse);
          final current = reopened.removedTransactionPage(kind).records.single;
          expect(current.canRestore, isTrue);
          expect(current.status, reviewed.status);
          expect(current.sourceFingerprint, reviewed.sourceFingerprint);
          expect(
            reopened.setTransactionRemoved(
              reviewed: current,
              removed: false,
              changedAt: removalAt.add(const Duration(seconds: 1)),
            ),
            2,
          );
          expect(visible(reopened, kind, f.id), isTrue);
          expect(reopened.removedTransactionPage(kind).total, 0);
          expect(
            reopened.reviewTransactionRemoval(kind, f.id).status,
            reviewed.status,
          );
          // An old remove token must not remove a record after a remove/restore cycle.
          final afterRestore = rawTables(raw);
          expect(
            () => reopened.setTransactionRemoved(
              reviewed: reviewed,
              removed: true,
              changedAt: removalAt.add(const Duration(seconds: 2)),
            ),
            throwsStateError,
          );
          expect(rawTables(raw), afterRestore);
          expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        },
      );
    }
  }

  test('removal rejects unauthorized actors, foreign company, stale source, stale time and failed audit atomically', () async {
    final f = await fixture(TransactionRecordKind.bill);
    final w = f.w;
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    final old = w.reviewTransactionRemoval(TransactionRecordKind.bill, f.id);
    final before = rawTables(raw);
    for (final foreignCompany in [false, true]) {
      expect(
        () => w.database.setTransactionRemoved(
          businessId: foreignCompany
              ? EntityId.random()
              : w.identity.businessId,
          actorId: foreignCompany ? w.identity.ownerId : EntityId.random(),
          reviewed: old,
          removed: true,
          changedAt: removalAt,
        ),
        throwsStateError,
      );
      expect(rawTables(raw), before);
    }
    expect(
      () => w.setTransactionRemoved(
        reviewed: old,
        removed: true,
        changedAt: DateTime.utc(2026, 9, 1),
      ),
      throwsStateError,
    );
    expect(rawTables(raw), before);
    final saved = w.database.readBillDraft(
      w.identity.businessId,
      EntityId.parse(f.id),
    )!;
    w.saveBillDraft(
      billFixture(
        w,
        saved.vendorSnapshot,
        saved.lines.single.categoryId!,
        previous: saved,
        memo: 'A concurrent edit',
      ),
      expectedRevision: 1,
    );
    final edited = rawTables(raw);
    expect(
      () => w.setTransactionRemoved(
        reviewed: old,
        removed: true,
        changedAt: removalAt,
      ),
      throwsStateError,
    );
    expect(rawTables(raw), edited);
    final current = w.reviewTransactionRemoval(
      TransactionRecordKind.bill,
      f.id,
    );
    raw.execute(
      "CREATE TRIGGER fail_removal_audit BEFORE INSERT ON ledger_audit WHEN NEW.kind='transaction_record_removed' BEGIN SELECT RAISE(ABORT,'injected audit failure'); END",
    );
    expect(
      () => w.setTransactionRemoved(
        reviewed: current,
        removed: true,
        changedAt: removalAt,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(rawTables(raw), edited);
  });

  test('removed source is immutable at SQLite and command boundaries; removal chain is append-only', () async {
    final f = await fixture(TransactionRecordKind.bill);
    final w = f.w;
    final raw = sqlite3.open(f.path);
    addTearDown(raw.dispose);
    final bill = w.database.readBillDraft(
      w.identity.businessId,
      EntityId.parse(f.id),
    )!;
    w.setTransactionRemoved(
      reviewed: w.reviewTransactionRemoval(TransactionRecordKind.bill, f.id),
      removed: true,
      changedAt: removalAt,
    );
    final before = rawTables(raw);
    for (final sql in [
      'UPDATE bill_drafts SET revision=revision+1',
      'DELETE FROM bill_drafts',
      'UPDATE transaction_record_removals SET removed=0',
      'DELETE FROM transaction_record_removals',
      'INSERT INTO transaction_record_removals SELECT business_id,kind,record_id,revision+2,0,changed_at,actor_id,source_digest,audit_sequence FROM transaction_record_removals',
    ]) {
      expect(() => raw.execute(sql), throwsA(isA<SqliteException>()));
      expect(rawTables(raw), before);
    }
    expect(() => w.saveBillDraft(bill, expectedRevision: 0), throwsStateError);
    expect(rawTables(raw), before);
    expect(
      w.database
          .readBillDraft(w.identity.businessId, bill.id, includeRemoved: true)!
          .toJson(),
      bill.toJson(),
    );
    expect(
      w.database.billDraftPage(businessId: w.identity.businessId).total,
      0,
    );
    expect(
      w.database.searchBillDrafts(
        businessId: w.identity.businessId,
        query: bill.documentNumber,
      ),
      isEmpty,
    );
  });

  test('approval/posting history protects claims even after return, accepted quotes, approved vouchers, posted bills and credits', () async {
    final c = await claimFixture();
    c.w.reverseClaimRecognition(
      reviewedClaim: c.approved,
      requestId: EntityId.random(),
      expectedRecognitionJournalId: c.source,
      decision: ClaimRecognitionDecision.returnForCorrection,
      reversedOn: DateTime.utc(2026, 9, 15),
      reason: 'Return for correction',
      changedAt: DateTime.utc(2026, 9, 15, 12),
    );
    final q = await fixture(TransactionRecordKind.quotation);
    q.w.changeQuotationState(
      EntityId.parse(q.id),
      expectedRevision: 1,
      action: QuotationAction.shared,
      changedAt: DateTime.utc(2026, 9, 2),
    );
    q.w.changeQuotationState(
      EntityId.parse(q.id),
      expectedRevision: 2,
      action: QuotationAction.accepted,
      changedAt: DateTime.utc(2026, 9, 3),
    );
    final v = await fixture(
      TransactionRecordKind.paymentVoucher,
      pending: true,
    );
    v.w.vouchers.approve(v.id);
    final b = await fixture(TransactionRecordKind.bill);
    final payable = await payableAccount(b.w);
    b.w.postBill(
      requestId: EntityId.random(),
      billId: EntityId.parse(b.id),
      expectedRevision: 1,
      payableAccountId: payable.account.id,
      approvedAt: DateTime.utc(2026, 9, 29),
    );
    final credit = await creditPostingFixture();
    credit.w.postInvoiceCredit(
      requestId: EntityId.random(),
      draftId: credit.creditId,
      expectedRevision: 1,
      expectedPaidMinor: 0,
      expectedPriorCreditMinor: 0,
      approvedAt: DateTime.utc(2026, 9, 7),
    );
    for (final (w, path, kind, id) in [
      (c.w, c.path, TransactionRecordKind.claim, c.approved.id.value),
      (q.w, q.path, TransactionRecordKind.quotation, q.id),
      (v.w, v.path, TransactionRecordKind.paymentVoucher, v.id),
      (b.w, b.path, TransactionRecordKind.bill, b.id),
      (
        credit.w,
        credit.path,
        TransactionRecordKind.invoiceCredit,
        credit.creditId.value,
      ),
    ]) {
      final raw = sqlite3.open(path);
      final before = rawTables(raw);
      final review = w.reviewTransactionRemoval(kind, id);
      expect(review.canRemove, isFalse, reason: kind.name);
      expect(review.restriction, isNotNull);
      expect(
        () => w.setTransactionRemoved(
          reviewed: review,
          removed: true,
          changedAt: removalAt,
        ),
        throwsStateError,
      );
      expect(rawTables(raw), before);
      raw.dispose();
    }
  });

  test('schema 50 opens and restores active sources without rewriting historical rows', () async {
    final f = await fixture(TransactionRecordKind.quotation);
    final oldArchive = envelope(
      historical(
        f.w.database.exportDataArchive(f.w.identity.businessId, removalAt),
        50,
      ),
    );
    f.w.dispose();
    final raw = sqlite3.open(f.path);
    dropCurrentQuotationFixtureOwner(raw);
    removeTransactionRemovalSchema(raw);
    raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    raw.execute('DROP TABLE IF EXISTS tax_remittances');
    raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
    raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
    raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
    raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    raw.execute('PRAGMA user_version=50');
    final oldRows = rawTables(raw);
    raw.dispose();
    final reopened = await AccountingWorkspace.open(f.path);
    addTearDown(reopened.dispose);
    final current = sqlite3.open(f.path);
    addTearDown(current.dispose);
    final rows = rawTables(current);
    for (final row in (rows['accounts'] as List).cast<Map<String, Object?>>()) {
      expect(row['profile'], isNull);
      row.remove('profile');
    }
    for (final table in oldRows.keys) {
      expect(rows[table], oldRows[table], reason: table);
    }
    expect(current.userVersion, LocalAccountingDatabase.schemaVersion);
    final restored = await AccountingWorkspace.emptyRestore(
      '${f.path}.old-restored',
      oldArchive,
    );
    addTearDown(restored.dispose);
    for (final w in [reopened, restored]) {
      expect(visible(w, TransactionRecordKind.quotation, f.id), isTrue);
      expect(
        w
            .reviewTransactionRemoval(TransactionRecordKind.quotation, f.id)
            .revision,
        0,
      );
    }
  });

  for (final corruption in [
    'missing source',
    'foreign actor',
    'audit mismatch',
    'revision gap',
  ]) {
    test(
      'archive rejects removal $corruption without populating target',
      () async {
        final f = await fixture(TransactionRecordKind.bill);
        f.w.setTransactionRemoved(
          reviewed: f.w.reviewTransactionRemoval(
            TransactionRecordKind.bill,
            f.id,
          ),
          removed: true,
          changedAt: removalAt,
        );
        final data = body(
          f.w.database.exportDataArchive(
            f.w.identity.businessId,
            removalAt.add(const Duration(hours: 1)),
          ),
        );
        final table =
            (data['tables'] as Map)['transaction_record_removals'] as Map;
        final columns = table['columns'] as List;
        final row = (table['rows'] as List).single as List;
        final (column, value) = switch (corruption) {
          'missing source' => ('record_id', EntityId.random().value),
          'foreign actor' => ('actor_id', EntityId.random().value),
          'audit mismatch' => ('source_digest', 'a' * 64),
          _ => ('revision', 2),
        };
        row[columns.indexOf(column)] = value;
        await expectLater(
          AccountingWorkspace.emptyRestore('${f.path}.bad', envelope(data)),
          throwsFormatException,
        );
        final rejected = sqlite3.open('${f.path}.bad');
        try {
          for (final table in rawTables(rejected).entries) {
            expect(
              table.value,
              isEmpty,
              reason: 'Failed restore populated ${table.key}',
            );
          }
        } finally {
          rejected.dispose();
        }
      },
    );
  }
}
