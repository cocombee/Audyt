import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presents RM with RM while retaining the canonical code', () {
    final presentation = CurrencyPresentation.fromCode('myr');

    expect(presentation.currency, Currency.parse('MYR'));
    expect(presentation.code, 'MYR');
    expect(presentation.name, 'Malaysian Ringgit');
    expect(presentation.symbol, 'RM');
    expect(presentation.label, 'RM · Malaysian Ringgit');
  });

  test('keeps valid unknown three-letter codes identifiable', () {
    final presentation = CurrencyPresentation.fromCode('xyz');

    expect(presentation.code, 'XYZ');
    expect(presentation.name, 'Unknown currency');
    expect(presentation.symbol, 'XYZ');
    expect(presentation.label, 'XYZ · Unknown currency');
    expect(presentation.currency.fractionDigits, 2);
  });

  test(
    'uses short symbols for amounts and falls back to unknown ISO codes',
    () {
      expect(currencyAmountLabel('MYR', '1,515.00'), 'RM 1,515.00');
      expect(currencyAmountLabel('USD', '1,515.00'), '\$1,515.00');
      expect(currencyAmountLabel('USD', '-1.50'), '-\$1.50');
      expect(currencyAmountLabel('XYZ', '1.50'), 'XYZ 1.50');
    },
  );

  test('rejects invalid currency input without falling back', () {
    expect(() => CurrencyPresentation.fromCode('US'), throwsFormatException);
    expect(() => CurrencyPresentation.fromCode('US1'), throwsFormatException);
  });
}
