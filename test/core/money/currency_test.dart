import 'package:audyt/core/money/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes currency codes and exposes decimal precision', () {
    expect(Currency.parse('usd').code, 'USD');
    expect(Currency.parse('USD').fractionDigits, 2);
    expect(Currency.parse('JPY').fractionDigits, 0);
    expect(Currency.parse('KWD').fractionDigits, 3);
    expect(() => Currency.parse('US'), throwsFormatException);
  });
}
