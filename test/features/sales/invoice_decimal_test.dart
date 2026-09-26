import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/invoice_form.dart';

void main() {
  test('invoice display amounts group thousands without changing editable decimals', () {
    final money = Money.fromMinor(361395045, 'MYR');
    expect(invoiceDecimal(money), '3613950.45');
    expect(invoiceMoney(money), 'RM 3,613,950.45');
  });
  test('invoice decimals preserve signs on small credit balances', () {
    for (final entry in <int, String>{
      -1: '-0.01',
      -50: '-0.50',
      -1500: '-15.00',
      0: '0.00',
      1: '0.01',
      1500: '15.00',
    }.entries) {
      expect(invoiceDecimal(Money.fromMinor(entry.key, 'MYR')), entry.value);
    }
  });
}
