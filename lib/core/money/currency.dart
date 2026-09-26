final class Currency {
  Currency._(this.code, this.fractionDigits);

  factory Currency.parse(String code) {
    final normalizedCode = code.toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCode)) {
      throw FormatException('Currency must be a three-letter ISO code', code);
    }
    return Currency._(
      normalizedCode,
      _fractionDigitsByCode[normalizedCode] ?? 2,
    );
  }

  final String code;
  final int fractionDigits;

  static const Map<String, int> _fractionDigitsByCode = {
    'BHD': 3,
    'IQD': 3,
    'JOD': 3,
    'KWD': 3,
    'LYD': 3,
    'OMR': 3,
    'TND': 3,
    'CLP': 0,
    'ISK': 0,
    'JPY': 0,
    'KRW': 0,
    'VND': 0,
  };

  @override
  bool operator ==(Object other) =>
      other is Currency &&
      other.code == code &&
      other.fractionDigits == fractionDigits;

  @override
  int get hashCode => Object.hash(code, fractionDigits);

  @override
  String toString() => code;
}
