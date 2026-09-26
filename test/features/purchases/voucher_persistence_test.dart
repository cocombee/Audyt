import 'dart:io';

import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';

import '../accounting/data/expense_intake_test.dart' as expense_fixture;

void main() {
  test(
    'voucher account identity requires matching business and currency',
    () async {
      final dir = Directory.systemTemp.createTempSync('voucher-account-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      final draft = PaymentVoucher.fromJson({
        ...PaymentVoucherStore.demo().all.last.toJson(),
        'status': 'draft',
        'paymentAccountId': 'local-account',
      });
      expect(() => workspace.vouchers.save(draft), throwsStateError);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'local-account',
          name: 'USD Account',
          type: PaymentAccountType.bank,
          currencyCode: 'USD',
        ),
      );
      expect(() => workspace.vouchers.save(draft), throwsStateError);
      expect(workspace.vouchers.all, isEmpty);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'local-account',
          name: 'Renamed Account',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      final sourceId = await workspace.saveExpenseIntake(
        expense_fixture.draft(paymentAccountId: 'local-account'),
      );
      final sourcedDraft = PaymentVoucher.fromJson({
        ...draft.toJson(),
        'sourceType': 'directExpense',
        'sourceId': sourceId.value,
        'payee': 'Stationery Shop',
        'amountMinor': 2550,
      });
      workspace.vouchers.saveAndSubmit(sourcedDraft);
      final restored = workspace.database
          .openVoucherStore(workspace.identity.businessId)
          .all
          .single;
      expect(restored.paymentAccountId, 'local-account');
      expect(restored.paymentAccount, draft.paymentAccount);
      expect(restored.approve().paymentAccountId, 'local-account');
      expect(
        () => workspace.savePaymentAccount(
          PaymentAccount.create(
            id: 'local-account',
            name: 'Wrong Currency',
            type: PaymentAccountType.bank,
            currencyCode: 'USD',
          ),
        ),
        throwsStateError,
      );
      expect(workspace.paymentAccounts.single.currency.code, 'MYR');
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'local-account',
          name: 'Updated Name',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      expect(workspace.paymentAccounts.single.name, 'Updated Name');
    },
  );
  test('voucher restart preserves source and stale approval cannot overwrite state', () async {
    final dir = Directory.systemTemp.createTempSync('voucher-storage-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'voucher-account',
        name: 'Voucher Account',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    final sourceId = await workspace.saveExpenseIntake(
      expense_fixture.draft(paymentAccountId: 'voucher-account'),
    );
    final voucher = PaymentVoucher.fromJson({
      ...PaymentVoucherStore.demo().all.last.toJson(),
      'sourceType': 'directExpense',
      'sourceId': sourceId.value,
      'payee': 'Stationery Shop',
      'amountMinor': 2550,
      'paymentAccountId': 'voucher-account',
    });
    workspace.vouchers.saveAndSubmit(
      PaymentVoucher.fromJson({...voucher.toJson(), 'status': 'draft'}),
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(workspace.vouchers.all.single.toJson(), voucher.toJson());
    final stale = workspace.database.openVoucherStore(
      workspace.identity.businessId,
    );
    workspace.vouchers.approve(voucher.id, approver: 'Local reviewer');
    expect(() => stale.cancel(voucher.id), throwsStateError);
    expect(
      stale.byId(voucher.id)!.status,
      PaymentVoucherStatus.pendingApproval,
    );
    final restored = workspace.database.openVoucherStore(
      workspace.identity.businessId,
    );
    expect(restored.byId(voucher.id)!.status, PaymentVoucherStatus.approved);
    expect(restored.byId(voucher.id)!.sourceId, voucher.sourceId);
  });
}
