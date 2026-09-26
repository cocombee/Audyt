import 'currency.dart';

final class CurrencyPresentation {
  const CurrencyPresentation({
    required this.currency,
    required this.name,
    required this.symbol,
  });

  factory CurrencyPresentation.fromCode(String code) {
    final currency = Currency.parse(code.trim());
    return byCurrency[currency.code] ??
        CurrencyPresentation(
          currency: currency,
          name: 'Unknown currency',
          symbol: currency.code,
        );
  }

  final Currency currency;
  final String name;
  final String symbol;

  String get code => currency.code;
  String get label => '$amountSymbol · $name';

  /// Amounts use a one- or two-character symbol when known; ISO code remains
  /// available for storage, selectors, and unrecognized currencies.
  String get amountSymbol => symbol.runes.length <= 2 ? symbol : code;
  String get amountPrefix => RegExp(r'^[A-Za-z]+$').hasMatch(amountSymbol)
      ? '$amountSymbol '
      : amountSymbol;

  static final List<CurrencyPresentation> known = <CurrencyPresentation>[
    CurrencyPresentation(
      currency: Currency.parse('MYR'),
      name: 'Malaysian Ringgit',
      symbol: 'RM',
    ),
    CurrencyPresentation(
      currency: Currency.parse('USD'),
      name: 'US Dollar',
      symbol: '\$',
    ),
    CurrencyPresentation(
      currency: Currency.parse('SGD'),
      name: 'Singapore Dollar',
      symbol: 'S\$',
    ),
    CurrencyPresentation(
      currency: Currency.parse('EUR'),
      name: 'Euro',
      symbol: '€',
    ),
    CurrencyPresentation(
      currency: Currency.parse('GBP'),
      name: 'Pound Sterling',
      symbol: '£',
    ),
    CurrencyPresentation(
      currency: Currency.parse('AUD'),
      name: 'Australian Dollar',
      symbol: 'A\$',
    ),
    CurrencyPresentation(
      currency: Currency.parse('CNY'),
      name: 'Chinese Yuan',
      symbol: '¥',
    ),
    CurrencyPresentation(
      currency: Currency.parse('HKD'),
      name: 'Hong Kong Dollar',
      symbol: '\$',
    ),
    CurrencyPresentation(
      currency: Currency.parse('THB'),
      name: 'Thai Baht',
      symbol: '฿',
    ),
    CurrencyPresentation(
      currency: Currency.parse('IDR'),
      name: 'Indonesian Rupiah',
      symbol: 'Rp',
    ),
    CurrencyPresentation(
      currency: Currency.parse('INR'),
      name: 'Indian Rupee',
      symbol: '₹',
    ),
    CurrencyPresentation(
      currency: Currency.parse('JPY'),
      name: 'Japanese Yen',
      symbol: '¥',
    ),
  ];

  static final Map<String, CurrencyPresentation> byCurrency =
      <String, CurrencyPresentation>{
        for (final option in known) option.code: option,
      };
}

String currencyAmountLabel(String code, String amount) {
  final prefix = CurrencyPresentation.fromCode(code).amountPrefix;
  return amount.startsWith('-')
      ? '-$prefix${amount.substring(1)}'
      : '$prefix$amount';
}
