import 'package:audyt/core/money/currency.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a local payment account with explicit type and currency', () {
    final account = PaymentAccount.create(
      id: 'account-1',
      name: 'Maybank Current',
      type: PaymentAccountType.bank,
      currencyCode: 'myr',
    );

    expect(account.name, 'Maybank Current');
    expect(account.type, PaymentAccountType.bank);
    expect(account.currency, Currency.parse('MYR'));
    expect(account.displayLabel, 'Maybank Current · Bank · RM');
  });

  test('requires a name and valid currency for a local account', () {
    expect(
      () => PaymentAccount.create(
        id: 'account-2',
        name: '',
        type: PaymentAccountType.cash,
        currencyCode: 'MYR',
      ),
      throwsArgumentError,
    );
    expect(
      () => PaymentAccount.create(
        id: 'account-2b',
        name: ' ',
        type: PaymentAccountType.cash,
        currencyCode: 'MYR',
      ),
      throwsArgumentError,
    );
    expect(
      () => PaymentAccount.create(
        id: 'account-3',
        name: 'Cash drawer',
        type: PaymentAccountType.cash,
        currencyCode: 'US',
      ),
      throwsFormatException,
    );
  });

  test('normalizes account names without destroying intentional case', () {
    final ordinary = PaymentAccount.create(
      id: 'account-4',
      name: 'operating account',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    );
    final acronym = PaymentAccount.create(
      id: 'account-5',
      name: 'MAYBANK',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    );
    final mixed = PaymentAccount.create(
      id: 'account-6',
      name: 'mYBank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    );
    final leadingWhitespace = PaymentAccount.create(
      id: 'account-7',
      name: '  operating account  ',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    );

    expect(ordinary.name, 'Operating account');
    expect(acronym.name, 'MAYBANK');
    expect(mixed.name, 'MYBank');
    expect(leadingWhitespace.name, 'Operating account');
  });
}
