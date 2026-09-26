import 'currency.dart';

final class Money {
  Money._(this.minorUnits, this.currency);

  factory Money.fromMinor(int minorUnits, String currency) {
    return Money._(minorUnits, Currency.parse(currency).code);
  }

  factory Money.zero(String currency) => Money.fromMinor(0, currency);

  factory Money.fromDecimal(String amount, String currency) {
    final currencyValue = Currency.parse(currency);
    final match = RegExp(r'^([+-]?)(\d+|\d{1,3}(?:,\d{3})+)(?:\.(\d+))?$')
        .firstMatch(amount.trim());
    if (match == null) {
      throw FormatException('Amount must be a decimal number', amount);
    }

    final fractionDigits = currencyValue.fractionDigits;
    final wholeUnits = BigInt.parse(match.group(2)!.replaceAll(',', ''));
    final fraction = match.group(3) ?? '';
    final retainedFraction = fraction
        .padRight(fractionDigits, '0')
        .substring(0, fractionDigits);
    final unroundedMinorUnits =
        wholeUnits * BigInt.from(_powerOfTen(fractionDigits)) +
        (retainedFraction.isEmpty
            ? BigInt.zero
            : BigInt.parse(retainedFraction));
    final roundingDigit = fraction.length > fractionDigits
        ? int.parse(fraction[fractionDigits])
        : 0;
    final sign = match.group(1) == '-' ? -1 : 1;
    final roundedMagnitude =
        unroundedMinorUnits + (roundingDigit >= 5 ? BigInt.one : BigInt.zero);
    return Money.fromMinor(
      _checkedMinor(BigInt.from(sign) * roundedMagnitude),
      currencyValue.code,
    );
  }

  final int minorUnits;
  final String currency;

  static int _powerOfTen(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index++) {
      value *= 10;
    }
    return value;
  }

  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;
  bool get isZero => minorUnits == 0;

  Money operator +(Money other) {
    _ensureSameCurrency(other);
    return Money.fromMinor(
      _checkedMinor(BigInt.from(minorUnits) + BigInt.from(other.minorUnits)),
      currency,
    );
  }

  Money operator -(Money other) {
    _ensureSameCurrency(other);
    return Money.fromMinor(
      _checkedMinor(BigInt.from(minorUnits) - BigInt.from(other.minorUnits)),
      currency,
    );
  }

  static int _checkedMinor(BigInt value) {
    final maximum = BigInt.parse('9223372036854775807');
    final minimum = BigInt.parse('-9223372036854775808');
    if (value < minimum || value > maximum) {
      throw RangeError('Amount exceeds the supported exact monetary range.');
    }
    return value.toInt();
  }

  void _ensureSameCurrency(Money other) {
    if (currency != other.currency) {
      throw StateError('Cannot combine different currencies');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  /// Exact ungrouped decimal input; never converts through floating point.
  String toDecimalString() {
    final digits = Currency.parse(currency).fractionDigits;
    final magnitude = BigInt.from(minorUnits)
        .abs()
        .toString()
        .padLeft(digits + 1, '0');
    final sign = minorUnits < 0 ? '-' : '';
    if (digits == 0) return '$sign$magnitude';
    final split = magnitude.length - digits;
    return '$sign${magnitude.substring(0, split)}.${magnitude.substring(split)}';
  }

  @override
  String toString() => '$currency:$minorUnits';
}
