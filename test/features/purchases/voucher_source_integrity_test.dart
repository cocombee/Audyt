import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/restored_page_routes_test.dart' show tables;

void main() {
  for (final change in [
    {'sourceId': 'not-a-saved-source'},
    {'sourceType': 'billSettlement'},
    {'payee': 'Another supplier'},
    {'amountMinor': 999999},
    {'paymentAccountId': 'demo-savings'},
  ]) {
    test('voucher source rejects $change atomically after restore', () async {
      final root = Directory.systemTemp.createTempSync('voucher-source-');
      addTearDown(() => root.deleteSync(recursive: true));
      final originalPath = '${root.path}/original.sqlite';
      final source = await createDemoWorkspace(databasePath: originalPath);
      final expense = (await source.expenses()).first;
      final valid = PaymentVoucher.create(
        id: 'source-integrity-audit',
        sourceType: PaymentVoucherSourceType.directExpense,
        sourceId: expense.id.value,
        payee: expense.payee,
        amount: expense.amount,
        paymentAccount: 'Demo Bank',
        paymentAccountId: 'demo-bank',
        paymentMethod: 'Bank Transfer',
        paymentDate: expense.occurredOn,
        reference: 'AUDIT SOURCE',
      );
      final archive = source.database.exportDataArchive(
        source.identity.businessId,
        DateTime.now(),
      );
      source.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final restoredPath = '${root.path}/restored.sqlite';
      var restored = await AccountingWorkspace.emptyRestore(
        restoredPath,
        archive,
      );
      final baseline = tables(restored);
      final invalid = PaymentVoucher.fromJson({...valid.toJson(), ...change});
      expect(() => restored.vouchers.saveAndSubmit(invalid), throwsStateError);
      expect(tables(restored), baseline);
      restored.dispose();
      restored = await AccountingWorkspace.open(restoredPath);
      addTearDown(restored.dispose);
      expect(tables(restored), baseline);
      expect(File(originalPath).readAsBytesSync(), originalBytes);
    });
  }
  test(
    'changed saved expense cannot be overwritten by an older voucher',
    () async {
      final w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
      addTearDown(w.dispose);
      final e = (await w.expenses()).firstWhere((e) => !e.isPosted);
      final original = (await w.expense(e.id))!.draft;
      final voucher = PaymentVoucher.create(
        id: 'stale-source-audit',
        sourceType: PaymentVoucherSourceType.directExpense,
        sourceId: e.id.value,
        payee: e.payee,
        amount: e.amount,
        paymentAccount: 'Demo Bank',
        paymentAccountId: 'demo-bank',
        paymentMethod: 'Bank Transfer',
        paymentDate: e.occurredOn,
        reference: 'STALE SOURCE',
      );
      await w.updateExpenseIntake(
        id: e.id,
        expected: original,
        replacement: RecordExpenseDraft.fromJson({
          ...original.toJson(),
          'amount': '95.00',
        }),
      );
      final changed = tables(w);
      expect(() => w.vouchers.save(voucher), throwsStateError);
      expect(tables(w), changed);
    },
  );
  test('foreign-company saved source cannot authorize a voucher', () async {
    final own = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    final foreign = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    addTearDown(own.dispose);
    addTearDown(foreign.dispose);
    final source = foreign.vouchers.sources.first;
    final before = tables(own);
    final foreignBefore = tables(foreign);
    expect(
      () => own.vouchers.save(
        PaymentVoucher.create(
          id: 'foreign-source-audit',
          sourceType: source.type,
          sourceId: source.id,
          payee: source.payee,
          amount: source.amount,
          paymentAccount: 'Demo Bank',
          paymentAccountId: source.paymentAccountId,
          paymentMethod: 'Bank Transfer',
          paymentDate: source.date,
          reference: 'FOREIGN SOURCE',
        ),
      ),
      throwsStateError,
    );
    expect(tables(own), before);
    expect(tables(foreign), foreignBefore);
  });
  test(
    'claim source requires an actual posted settlement and survives restart',
    () async {
      final root = Directory.systemTemp.createTempSync('voucher-claim-source-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/original.sqlite';
      var w = await createDemoWorkspace(
        databasePath: path,
        asOf: DateTime(2026, 9, 30),
      );
      expect(
        w.vouchers.sources.where(
          (s) => s.type == PaymentVoucherSourceType.claimPayment,
        ),
        hasLength(1),
      );
      final claim = w.claims.all.firstWhere(
        (c) => c.status == ClaimStatus.submitted,
      );
      expect(
        w.vouchers.sources.any(
          (s) =>
              s.type == PaymentVoucherSourceType.claimPayment &&
              s.id == claim.id.value,
        ),
        isFalse,
      );
      final accounts = await w.accounts();
      EntityId account(String code) =>
          accounts.singleWhere((a) => a.account.code == code).account.id;
      final date = DateTime.utc(2026, 9, 27);
      w.approveClaim(
        reviewedClaim: claim,
        requestId: EntityId.random(),
        expenseAccountId: account('6000'),
        liabilityAccountId: account('2100'),
        approvedAt: date,
      );
      w.settleClaims(
        reviewedClaims: [w.claims.byId(claim.id)!],
        requestId: EntityId.random(),
        bankAccountId: account('1000'),
        paymentAccountId: 'demo-bank',
        paymentReference: 'SOURCE CLAIM PAYMENT',
        paidAt: date,
      );
      final paidTables = tables(w);
      final archive = w.database.exportDataArchive(w.identity.businessId, date);
      w.dispose();
      final originalBytes = File(path).readAsBytesSync();
      final restoredPath = '${root.path}/restored.sqlite';
      w = await AccountingWorkspace.emptyRestore(restoredPath, archive);
      final source = w.vouchers.sources.singleWhere(
        (s) =>
            s.type == PaymentVoucherSourceType.claimPayment &&
            s.id == claim.id.value,
      );
      expect(source.id, claim.id.value);
      expect(source.payee, claim.claimantName);
      expect(source.amount, claim.amount);
      expect(source.paymentAccountId, 'demo-bank');
      expect(source.date, date);
      expect(
        w.vouchers.sources.any(
          (s) => s.type == PaymentVoucherSourceType.billSettlement,
        ),
        isFalse,
      );
      final voucher = PaymentVoucher.create(
        id: 'settled-claim-control',
        sourceType: source.type,
        sourceId: source.id,
        payee: source.payee,
        amount: source.amount,
        paymentAccount: 'Demo Bank',
        paymentAccountId: source.paymentAccountId,
        paymentMethod: 'Bank Transfer',
        paymentDate: source.date,
        reference: 'CLAIM CONTROL',
      );
      w.vouchers.save(voucher);
      final saved = tables(w);
      for (final key in paidTables.keys.where(
        (key) => key != 'payment_vouchers',
      )) {
        expect(saved[key], paidTables[key], reason: key);
      }
      w.dispose();
      w = await AccountingWorkspace.open(restoredPath);
      addTearDown(w.dispose);
      expect(tables(w), saved);
      expect(w.vouchers.byId(voucher.id)!.toJson(), voucher.toJson());
      expect(
        w.vouchers.sources
            .singleWhere((s) => s.type == source.type && s.id == source.id)
            .id,
        source.id,
      );
      expect(File(path).readAsBytesSync(), originalBytes);
    },
  );
}
