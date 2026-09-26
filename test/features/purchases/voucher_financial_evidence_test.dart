import 'dart:io';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_evidence.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/restored_page_routes_test.dart' show tables;
import '../accounting/data/bank_statement_import_test.dart' show parse;
import '../accounting/data/expense_intake_test.dart' show draft;
import '../accounting/data/reconciliation_test_support.dart'
    show seedRecordedOpening;

final class VoucherFinancialFixture {
  VoucherFinancialFixture(this.workspace, this.expense, this.bank, this.cost);
  final AccountingWorkspace workspace;
  final EntityId expense, bank, cost;
  EntityId? journal;
  static final paymentDate = DateTime.utc(2026, 9, 13);

  static Future<VoucherFinancialFixture> create(String path) async {
    final w = await AccountingWorkspace.open(path);
    await w.createAccount(
      code: '1000',
      name: 'Audit Bank',
      type: AccountType.asset,
    );
    await w.createAccount(
      code: '5000',
      name: 'Supplies',
      type: AccountType.expense,
    );
    final accounts = await w.accounts();
    EntityId account(String code) =>
        accounts.singleWhere((a) => a.account.code == code).account.id;
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Audit Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'bank',
      account('1000'),
    );
    await seedRecordedOpening(w, account('1000'));
    final expense = await w.saveExpenseIntake(
      RecordExpenseDraft.fromJson({
        ...draft(amount: '10.00', paymentAccountId: 'bank').toJson(),
        'paymentAccount': 'Audit Bank',
      }),
    );
    return VoucherFinancialFixture(
      w,
      expense,
      account('1000'),
      account('5000'),
    );
  }

  PaymentVoucher approveVoucher({String id = 'financial-voucher'}) {
    final s = workspace.vouchers.sources.singleWhere(
      (s) => s.id == expense.value,
    );
    final v = PaymentVoucher.create(
      id: id,
      sourceType: s.type,
      sourceId: s.id,
      payee: s.payee,
      amount: s.amount,
      paymentAccount: 'Audit Bank',
      paymentAccountId: s.paymentAccountId,
      paymentMethod: 'Bank Transfer',
      paymentDate: s.date,
      reference: 'AUDIT PAYMENT',
    );
    workspace.vouchers.saveAndSubmit(v);
    return workspace.vouchers.approve(
      v.id,
      approver: workspace.identity.ownerId.value,
    );
  }

  Future<void> postExpense() async {
    await workspace.saveJournal(
      date: paymentDate,
      memo: 'Reviewed source payment',
      lines: [
        JournalLine.debit(
          accountId: cost,
          amount: Money.fromMinor(1000, 'MYR'),
        ),
        JournalLine.credit(
          accountId: bank,
          amount: Money.fromMinor(1000, 'MYR'),
        ),
      ],
    );
    final j = (await workspace.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    journal = j.entry.id;
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: workspace.identity.businessId,
        journalId: journal!,
        expectedRevision: j.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: j.metadata.updatedAt.add(const Duration(seconds: 1)),
        expenseIntakeId: expense,
      ),
    );
  }

  EntityId acceptBankMatch() {
    final w = workspace;
    final statement = w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'bank',
      importedAt: DateTime.utc(2026, 9, 14),
      statement: parse(
        'Date,Description,Amount\n2026-09-13,Stationery Shop,-10.00',
      ),
    );
    w.database.acceptStatementMatch(
      businessId: w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      journalId: journal!,
      lineIndex: 1,
      actorId: w.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 14),
    );
    return statement;
  }

  EntityId completeBankReview(EntityId statement) {
    final w = workspace, id = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: id,
      businessId: w.identity.businessId,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.utc(2026, 9, 15),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(9000, 'MYR'),
      expectedAcceptanceIds: {
        2: w.database.statementMatchAcceptanceId(
          w.identity.businessId,
          statement,
          2,
        )!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence:
          'Fictional opening statement verified with owner contribution.',
    );
    return id;
  }

  Future<void> reversePayment() async {
    final w = workspace;
    final original = (await w.journals()).singleWhere(
      (j) => j.entry.id == journal,
    );
    final reversal = original.entry.reversal(
      id: EntityId.random(),
      date: DateTime.utc(2026, 9, 16),
      memo: 'Correct fictional source payment',
    );
    await w.database.save(
      StoredJournalEntry(
        entry: reversal,
        metadata: RecordMetadata.initial(
          recordId: reversal.id,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 16),
        ),
      ),
    );
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: reversal.id,
        expectedRevision: 1,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.utc(2026, 9, 17),
      ),
    );
  }
}

void main() {
  test(
    'unposted source cannot mark a voucher paid or change any table',
    () async {
      final dir = Directory.systemTemp.createTempSync('voucher-financial-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = await VoucherFinancialFixture.create(
        '${dir.path}/books.sqlite',
      );
      addTearDown(f.workspace.dispose);
      final v = f.approveVoucher();
      final before = tables(f.workspace);
      expect(
        () => f.workspace.vouchers.recordPayment(
          v.id,
          paidAt: VoucherFinancialFixture.paymentDate,
        ),
        throwsStateError,
      );
      expect(tables(f.workspace), before);
      expect(
        f.workspace.vouchers.byId(v.id)!.status,
        PaymentVoucherStatus.approved,
      );
    },
  );

  test(
    'accepted bank match without completion cannot mark voucher reconciled',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'voucher-reconciliation-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = await VoucherFinancialFixture.create(
        '${dir.path}/books.sqlite',
      );
      addTearDown(f.workspace.dispose);
      await f.postExpense();
      final v = f.approveVoucher();
      f.workspace.vouchers.recordPayment(
        v.id,
        paidAt: VoucherFinancialFixture.paymentDate,
      );
      f.acceptBankMatch();
      final before = tables(f.workspace);
      expect(
        () => f.workspace.vouchers.reconcile(
          v.id,
          reconciledAt: DateTime.utc(2026, 9, 15),
        ),
        throwsStateError,
      );
      expect(tables(f.workspace), before);
      expect(
        f.workspace.vouchers.byId(v.id)!.status,
        PaymentVoucherStatus.paid,
      );
    },
  );
  test('posted payment and completed bank proof survive archive, restart and reopening', () async {
    final dir = Directory.systemTemp.createTempSync('voucher-proof-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/original.sqlite';
    final f = await VoucherFinancialFixture.create(path);
    await f.postExpense();
    final approved = f.approveVoucher();
    final before = tables(f.workspace);
    final paid = f.workspace.vouchers.recordPayment(approved.id);
    expect(f.workspace.vouchers.verification(paid).paymentVerified, isTrue);
    expect(
      f.workspace.vouchers.verification(paid).reconciliationVerified,
      isFalse,
    );
    expect(paid.paymentEvidence!.journalId, f.journal);
    expect(paid.paymentEvidence!.lineIndex, 1);
    expect(paid.paymentEvidence!.movementAmount, Money.fromMinor(1000, 'MYR'));
    expect(paid.paidAt, VoucherFinancialFixture.paymentDate);
    expect(paid.paymentDate, VoucherFinancialFixture.paymentDate);
    final paidTables = tables(f.workspace);
    for (final key in before.keys.where(
      (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
    )) {
      expect(paidTables[key], before[key], reason: key);
    }
    expect(
      (paidTables['ledger_audit']['rows'] as List).length,
      (before['ledger_audit']['rows'] as List).length + 1,
    );
    f.workspace.vouchers.recordPayment(paid.id);
    expect(tables(f.workspace), paidTables);
    final statement = f.acceptBankMatch();
    final completion = f.completeBankReview(statement);
    final bankTables = tables(f.workspace);
    final reconciled = f.workspace.vouchers.reconcile(paid.id);
    final proof = reconciled.reconciliationEvidence!;
    expect(proof.completionId, completion);
    expect(
      proof.acceptanceId,
      EntityId.parse(
        f.workspace.database.statementMatchAcceptanceId(
          f.workspace.identity.businessId,
          statement,
          2,
        )!,
      ),
    );
    expect(proof.approvedAt, DateTime.utc(2026, 9, 15));
    final retainedOnly = PaymentVoucherStore(vouchers: [reconciled]);
    addTearDown(retainedOnly.dispose);
    final unavailable = retainedOnly.verification(reconciled);
    expect(unavailable.status, PaymentVoucherStatus.reconciled);
    expect(unavailable.paymentVerified, isFalse);
    expect(unavailable.reconciliationVerified, isFalse);
    expect(
      f.workspace.vouchers.verification(reconciled).paymentVerified,
      isTrue,
    );
    expect(
      f.workspace.vouchers.verification(reconciled).reconciliationVerified,
      isTrue,
    );
    expect(
      f.workspace.vouchers.verification(reconciled).status,
      PaymentVoucherStatus.reconciled,
    );
    final completeTables = tables(f.workspace);
    for (final key in bankTables.keys.where(
      (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
    )) {
      expect(completeTables[key], bankTables[key], reason: key);
    }
    f.workspace.vouchers.reconcile(paid.id);
    expect(tables(f.workspace), completeTables);
    final archive = f.workspace.database.exportDataArchive(
      f.workspace.identity.businessId,
      DateTime.utc(2026, 9, 27),
    );
    f.workspace.dispose();
    final originalBytes = File(path).readAsBytesSync();
    final restoredPath = '${dir.path}/restored.sqlite';
    var w = await AccountingWorkspace.emptyRestore(restoredPath, archive);
    expect(tables(w), completeTables);
    w.dispose();
    w = await AccountingWorkspace.open(restoredPath);
    addTearDown(() => w.dispose());
    expect(tables(w), completeTables);
    final restored = w.vouchers.byId(paid.id)!;
    expect(restored.toJson(), reconciled.toJson());
    expect(
      w.vouchers.verification(restored).status,
      PaymentVoucherStatus.reconciled,
    );
    w.database.reopenStatementReconciliation(
      businessId: w.identity.businessId,
      completionId: completion.value,
      actorId: w.identity.ownerId,
      reopenedAt: DateTime.utc(2026, 9, 16),
      reason: 'Correct fictional statement review',
    );
    final reopened = tables(w);
    expect(w.vouchers.verification(restored).paymentVerified, isTrue);
    expect(w.vouchers.verification(restored).reconciliationVerified, isFalse);
    expect(w.vouchers.verification(restored).status, PaymentVoucherStatus.paid);
    expect(w.vouchers.byId(paid.id)!.reconciliationEvidence, proof);
    expect(() => w.vouchers.reconcile(paid.id), throwsStateError);
    expect(tables(w), reopened);
    w.database.retractStatementMatch(
      businessId: w.identity.businessId,
      acceptanceId: proof.acceptanceId.value,
      actorId: w.identity.ownerId,
      retractedAt: DateTime.utc(2026, 9, 16),
      reason: 'Recheck fictional source',
    );
    // Data-only recovery retains review history; new matching needs the actual original bytes.
    expect(
      w.database
          .bankStatement(w.identity.businessId, statement)!
          .sourceAvailable,
      isFalse,
    );
    w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'bank',
      importedAt: DateTime.utc(2026, 9, 17),
      statement: parse(
        'Date,Description,Amount\n2026-09-13,Stationery Shop,-10.00',
      ),
    );
    w.database.acceptStatementMatch(
      businessId: w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      journalId: f.journal!,
      lineIndex: 1,
      actorId: w.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 17),
    );
    final renewed = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: renewed,
      businessId: w.identity.businessId,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.utc(2026, 9, 18),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(9000, 'MYR'),
      expectedAcceptanceIds: {
        2: w.database.statementMatchAcceptanceId(
          w.identity.businessId,
          statement,
          2,
        )!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence: 'Fictional opening rechecked.',
    );
    expect(w.vouchers.verification(restored).status, PaymentVoucherStatus.paid);
    final reconfirmed = w.vouchers.reconcile(
      paid.id,
      expectedCurrent: restored,
    );
    expect(reconfirmed.reconciliationEvidence!.completionId, renewed);
    expect(
      reconfirmed.reconciliationEvidence!.acceptanceId,
      isNot(proof.acceptanceId),
    );
    expect(
      w.vouchers.verification(reconfirmed).status,
      PaymentVoucherStatus.reconciled,
    );
    final audit = tables(w)['ledger_audit'] as Map;
    final detailIndex = (audit['columns'] as List).indexOf('detail');
    final last = (audit['rows'] as List)
        .map((r) => jsonDecode(r[detailIndex] as String) as Map)
        .singleWhere(
          (r) =>
              (r['reconciliationEvidence'] as Map?)?['completionId'] ==
              renewed.value,
        );
    expect(last['previousReconciliationEvidence'], proof.toJson());
    expect(File(path).readAsBytesSync(), originalBytes);
  });

  test('reversed posted source invalidates current payment without erasing history', () async {
    final dir = Directory.systemTemp.createTempSync('voucher-reversal-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = await VoucherFinancialFixture.create('${dir.path}/books.sqlite');
    addTearDown(f.workspace.dispose);
    await f.postExpense();
    final approved = f.approveVoucher();
    final paid = f.workspace.vouchers.recordPayment(approved.id);
    await f.reversePayment();
    final before = tables(f.workspace);
    expect(f.workspace.vouchers.verification(paid).paymentVerified, isFalse);
    expect(
      f.workspace.vouchers.verification(paid).reconciliationVerified,
      isFalse,
    );
    expect(
      f.workspace.vouchers.verification(paid).status,
      PaymentVoucherStatus.onHold,
    );
    expect(f.workspace.vouchers.byId(paid.id)!.toJson(), paid.toJson());
    expect(() => f.workspace.vouchers.recordPayment(paid.id), throwsStateError);
    expect(() => f.workspace.vouchers.reconcile(paid.id), throwsStateError);
    expect(tables(f.workspace), before);
  });

  test(
    'external ledger change invalidates cached reconciliation status',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'voucher-external-ledger-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      final f = await VoucherFinancialFixture.create(path);
      addTearDown(f.workspace.dispose);
      await f.postExpense();
      final approved = f.approveVoucher();
      final paid = f.workspace.vouchers.recordPayment(approved.id);
      final statement = f.acceptBankMatch();
      f.completeBankReview(statement);
      final reconciled = f.workspace.vouchers.reconcile(paid.id);
      expect(
        f.workspace.vouchers.verification(reconciled).status,
        PaymentVoucherStatus.reconciled,
      );
      // A second read must use the same proof, then a separate SQLite writer
      // must invalidate it without requiring the workspace to be reopened.
      expect(
        f.workspace.vouchers.verification(reconciled).status,
        PaymentVoucherStatus.reconciled,
      );
      final external = sqlite3.open(path);
      external.execute('UPDATE journal_entries SET memo=? WHERE id=?', [
        'Externally changed reviewed payment',
        f.journal!.value,
      ]);
      external.dispose();
      expect(
        f.workspace.vouchers.verification(reconciled).status,
        PaymentVoucherStatus.paid,
      );
      expect(
        f.workspace.vouchers.byId(paid.id)!.reconciliationEvidence,
        reconciled.reconciliationEvidence,
      );
    },
  );

  test(
    'reviewed proof, owner and audit failure cannot commit a false payment',
    () async {
      final dir = Directory.systemTemp.createTempSync('voucher-commit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      final f = await VoucherFinancialFixture.create(path);
      addTearDown(f.workspace.dispose);
      await f.postExpense();
      final approved = f.approveVoucher();
      final before = tables(f.workspace);
      final reviewed = f.workspace.vouchers.loadPaymentEvidence!(approved);
      final wrong = PaymentVoucherPaymentEvidence(
        journalId: EntityId.random(),
        lineIndex: reviewed.lineIndex,
        movementAmount: reviewed.movementAmount,
        paymentDate: reviewed.paymentDate,
      );
      expect(
        () => f.workspace.vouchers.recordPayment(
          approved.id,
          expectedPaymentEvidence: wrong,
        ),
        throwsStateError,
      );
      final foreign = f.workspace.database.openVoucherStore(
        f.workspace.identity.businessId,
        actorId: EntityId.random(),
      );
      addTearDown(foreign.dispose);
      expect(() => foreign.recordPayment(approved.id), throwsStateError);
      final forged = PaymentVoucher.fromJson({
        ...approved.toJson(),
        'payee': 'Changed after approval',
      });
      expect(() => f.workspace.vouchers.persist!(forged), throwsStateError);
      expect(
        () => f.workspace.vouchers.persist!(
          approved.recordPayment(paidAt: reviewed.paymentDate),
        ),
        throwsStateError,
      );
      expect(tables(f.workspace), before);
      final raw = sqlite3.open(path);
      raw.execute(
        "CREATE TRIGGER fail_voucher_audit BEFORE INSERT ON ledger_audit WHEN NEW.kind='voucher_control_confirmed' BEGIN SELECT RAISE(ABORT,'injected audit failure'); END",
      );
      expect(
        () => f.workspace.vouchers.recordPayment(
          approved.id,
          expectedCurrent: approved,
          expectedPaymentEvidence: reviewed,
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(tables(f.workspace), before);
      expect(
        f.workspace.vouchers.byId(approved.id)!.toJson(),
        approved.toJson(),
      );
      raw.execute('DROP TRIGGER fail_voucher_audit');
      raw.dispose();
      f.workspace.vouchers.orderPayment(approved.id);
      final changed = tables(f.workspace);
      expect(
        () => f.workspace.vouchers.recordPayment(
          approved.id,
          expectedCurrent: approved,
          expectedPaymentEvidence: reviewed,
        ),
        throwsStateError,
      );
      expect(tables(f.workspace), changed);
      f.workspace.vouchers.recordPayment(
        approved.id,
        expectedCurrent: f.workspace.vouchers.byId(approved.id),
        expectedPaymentEvidence: reviewed,
      );
      expect(
        f.workspace.vouchers.byId(approved.id)!.status,
        PaymentVoucherStatus.paid,
      );
    },
  );

  test('one claim voucher retains its allocation within a real multi-claim bank payment', () async {
    final dir = Directory.systemTemp.createTempSync('voucher-claim-batch-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final w = await AccountingWorkspace.open('${dir.path}/books.sqlite');
    addTearDown(w.dispose);
    for (final pair in [
      ('1000', AccountType.asset),
      ('2100', AccountType.liability),
      ('5000', AccountType.expense),
    ]) {
      await w.createAccount(code: pair.$1, name: pair.$1, type: pair.$2);
    }
    final accounts = await w.accounts();
    EntityId account(String code) =>
        accounts.singleWhere((a) => a.account.code == code).account.id;
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Claims Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'bank',
      account('1000'),
    );
    await seedRecordedOpening(w, account('1000'));
    final first = ClaimStore.demo().all.first;
    final second = Claim.fromJson({
      ...first.toJson(),
      'id': EntityId.random().value,
    });
    for (final claim in [first, second]) {
      w.claims.saveDraft(claim);
      w.claims.submit(claim.id);
      w.approveClaim(
        requestId: EntityId.random(),
        reviewedClaim: w.claims.byId(claim.id)!,
        expenseAccountId: account('5000'),
        liabilityAccountId: account('2100'),
        approvedAt: DateTime.utc(2026, 9, 14),
      );
    }
    final batchId = EntityId.random();
    final batch = w.settleClaims(
      requestId: batchId,
      reviewedClaims: w.claims.all,
      bankAccountId: account('1000'),
      paymentAccountId: 'bank',
      paymentReference: 'FICTIONAL BATCH',
      paidAt: DateTime.utc(2026, 9, 15),
    );
    final source = w.vouchers.sources.first;
    final draftVoucher = PaymentVoucher.create(
      id: 'batch-control',
      sourceType: source.type,
      sourceId: source.id,
      payee: source.payee,
      amount: source.amount,
      paymentAccount: 'Claims Bank',
      paymentAccountId: 'bank',
      paymentMethod: 'Bank Transfer',
      paymentDate: source.date,
      reference: 'ONE CLAIM',
    );
    w.vouchers.saveAndSubmit(draftVoucher);
    w.vouchers.approve(draftVoucher.id);
    final before = tables(w);
    final paid = w.vouchers.recordPayment(draftVoucher.id);
    expect(paid.amount, source.amount);
    expect(paid.paymentEvidence!.movementAmount, batch.total);
    expect(
      paid.paymentEvidence!.movementAmount.minorUnits,
      source.amount.minorUnits * 2,
    );
    expect(paid.paymentEvidence!.journalId, batchId);
    for (final key in before.keys.where(
      (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
    )) {
      expect(tables(w)[key], before[key], reason: key);
    }
    final statement = w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'bank',
      importedAt: DateTime.utc(2026, 9, 16),
      statement: parse(
        'Date,Description,Amount\n2026-09-15,Claims batch,-${(batch.total.minorUnits / 100).toStringAsFixed(2)}',
      ),
    );
    w.database.acceptStatementMatch(
      businessId: w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      journalId: batchId,
      lineIndex: paid.paymentEvidence!.lineIndex,
      actorId: w.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 16),
    );
    final completion = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: completion,
      businessId: w.identity.businessId,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.utc(2026, 9, 17),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(10000 - batch.total.minorUnits, 'MYR'),
      expectedAcceptanceIds: {
        2: w.database.statementMatchAcceptanceId(
          w.identity.businessId,
          statement,
          2,
        )!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence: 'Fictional claim bank opening verified.',
    );
    final bankComplete = tables(w);
    final reviewed = w.vouchers.reconcile(paid.id);
    expect(reviewed.amount, source.amount);
    expect(reviewed.reconciliationEvidence!.completionId, completion);
    for (final key in bankComplete.keys.where(
      (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
    )) {
      expect(tables(w)[key], bankComplete[key], reason: key);
    }
  });
  test('combined bank review proves a voucher even when its payment is the second member', () async {
    final dir = Directory.systemTemp.createTempSync('voucher-combined-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = await VoucherFinancialFixture.create('${dir.path}/books.sqlite');
    addTearDown(f.workspace.dispose);
    await f.postExpense();
    final w = f.workspace;
    final approved = f.approveVoucher();
    final paid = w.vouchers.recordPayment(approved.id);
    final otherId = EntityId.parse('00000000-0000-4000-8000-000000000005');
    final other = JournalEntry.draft(
      id: otherId,
      date: VoucherFinancialFixture.paymentDate,
      memo: 'Fictional second supplier payment',
      lines: [
        JournalLine.debit(
          accountId: f.cost,
          amount: Money.fromMinor(500, 'MYR'),
        ),
        JournalLine.credit(
          accountId: f.bank,
          amount: Money.fromMinor(500, 'MYR'),
        ),
      ],
    );
    await w.database.save(
      StoredJournalEntry(
        entry: other,
        metadata: RecordMetadata.initial(
          recordId: otherId,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 13),
        ),
      ),
    );
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: otherId,
        expectedRevision: 1,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.utc(2026, 9, 14),
      ),
    );
    final statement = w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'bank',
      importedAt: DateTime.utc(2026, 9, 14),
      statement: parse(
        'Date,Description,Amount\n2026-09-13,Suppliers batch,-15.00',
      ),
    );
    w.database.acceptStatementCombinedMatch(
      businessId: w.identity.businessId,
      statementId: statement,
      sourceRow: 2,
      movementIds: {'${f.journal!.value}:1', '${otherId.value}:1'},
      actorId: w.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 14),
    );
    final completion = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: completion,
      businessId: w.identity.businessId,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.utc(2026, 9, 15),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(8500, 'MYR'),
      expectedAcceptanceIds: {
        2: w.database.statementMatchAcceptanceId(
          w.identity.businessId,
          statement,
          2,
        )!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence: 'Fictional opening verified.',
    );
    final before = tables(w);
    final reconciled = w.vouchers.reconcile(paid.id);
    expect(reconciled.paymentEvidence!.journalId, f.journal);
    expect(reconciled.reconciliationEvidence!.completionId, completion);
    expect(
      w.vouchers.verification(reconciled).status,
      PaymentVoucherStatus.reconciled,
    );
    for (final key in before.keys.where(
      (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
    )) {
      expect(tables(w)[key], before[key], reason: key);
    }
    await w.saveJournal(
      date: DateTime.utc(2026, 9, 12),
      memo: 'New fictional backdated bank movement',
      lines: [
        JournalLine.debit(
          accountId: f.cost,
          amount: Money.fromMinor(100, 'MYR'),
        ),
        JournalLine.credit(
          accountId: f.bank,
          amount: Money.fromMinor(100, 'MYR'),
        ),
      ],
    );
    final newDraft = (await w.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: newDraft.entry.id,
        expectedRevision: newDraft.metadata.revision,
        actorId: w.identity.ownerId,
        approvedAt: newDraft.metadata.updatedAt.add(const Duration(seconds: 1)),
      ),
    );
    final changed = tables(w);
    expect(
      w.vouchers.verification(reconciled).status,
      PaymentVoucherStatus.paid,
    );
    expect(() => w.vouchers.reconcile(paid.id), throwsStateError);
    expect(tables(w), changed);
  });
}
