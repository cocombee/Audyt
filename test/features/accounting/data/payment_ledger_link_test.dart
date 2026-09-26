import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/account.dart';

void main() {
  test('ledger links validate ownership and survive restart without rewriting identity', () async {
    final dir = Directory.systemTemp.createTempSync('payment-ledger-link-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final business = workspace.identity.businessId;
    await workspace.createAccount(
      code: '1000',
      name: 'Bank',
      type: AccountType.asset,
    );
    await workspace.createAccount(
      code: '2000',
      name: 'Card',
      type: AccountType.liability,
    );
    await workspace.createAccount(
      code: '4000',
      name: 'Sales',
      type: AccountType.income,
    );
    final chart = await workspace.accounts();
    EntityId account(AccountType type) =>
        chart.singleWhere((r) => r.account.type == type).account.id;
    PaymentAccount payment(
      String id, {
      String currency = 'MYR',
      PaymentAccountType type = PaymentAccountType.bank,
    }) => PaymentAccount.create(
      id: id,
      name: id,
      type: type,
      currencyCode: currency,
    );
    for (final p in [
      payment('bank'),
      payment('other'),
      payment('foreign', currency: 'USD'),
      payment('card', type: PaymentAccountType.card),
    ]) {
      workspace.savePaymentAccount(p);
    }
    void link(String payment, AccountType type) => workspace.database
        .linkPaymentLedgerAccount(business, payment, account(type));
    expect(() => link('bank', AccountType.income), throwsStateError);
    expect(() => link('card', AccountType.asset), throwsStateError);
    expect(() => link('foreign', AccountType.asset), throwsStateError);
    expect(
      () => workspace.database.linkPaymentLedgerAccount(
        EntityId.random(),
        'bank',
        account(AccountType.asset),
      ),
      throwsStateError,
    );
    link('bank', AccountType.asset);
    link('bank', AccountType.asset);
    link('card', AccountType.liability);
    expect(
      () => link('other', AccountType.asset),
      throwsA(isA<SqliteException>()),
    );
    expect(() => link('bank', AccountType.liability), throwsStateError);
    expect(
      () => workspace.savePaymentAccount(payment('bank', currency: 'USD')),
      throwsStateError,
    );
    expect(
      () => workspace.savePaymentAccount(
        payment('bank', type: PaymentAccountType.card),
      ),
      throwsStateError,
    );
    final raw = sqlite3.open(path);
    expect(
      () => raw.execute('DELETE FROM payment_ledger_links'),
      throwsA(isA<SqliteException>()),
    );
    raw.dispose();
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database.paymentLedgerAccount(business, 'bank'),
      account(AccountType.asset),
    );
    expect(workspace.database.paymentLedgerAccount(business, 'other'), isNull);
    expect(await workspace.journals(), isEmpty);
    workspace.dispose();
  });
}
