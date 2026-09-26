import 'package:audyt/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rounds decimal input half-up into integer minor units', () {
    expect(Money.fromDecimal('12.345', 'usd').minorUnits, 1235);
    expect(Money.fromDecimal('12.344', 'USD').minorUnits, 1234);
    expect(Money.fromDecimal('-0.005', 'USD').minorUnits, -1);
  });
  test('accepts valid grouped money and rejects malformed commas', () {
    expect(Money.fromDecimal('1,234.56', 'MYR').minorUnits, 123456);
    expect(() => Money.fromDecimal('12,34.56', 'MYR'), throwsFormatException);
  });
  test(
    'decimal conversion and arithmetic reject overflow instead of wrapping',
    () {
      final maximum = Money.fromDecimal('92233720368547758.07', 'MYR');
      expect(maximum.minorUnits, 9223372036854775807);
      expect(
        () => Money.fromDecimal('92233720368547758.08', 'MYR'),
        throwsRangeError,
      );
      expect(
        () => Money.fromDecimal('184467440737095516.17', 'MYR'),
        throwsRangeError,
      );
      expect(() => maximum + Money.fromMinor(1, 'MYR'), throwsRangeError);
      final minimum = Money.fromMinor(-9223372036854775808, 'MYR');
      expect(() => minimum - Money.fromMinor(1, 'MYR'), throwsRangeError);
    },
  );
}
