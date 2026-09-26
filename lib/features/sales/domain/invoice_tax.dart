import '../../../core/money/money.dart';

/// An explicitly supplied percentage, not a jurisdiction's statutory policy.
/// Four decimal places of percentage precision; integer arithmetic throughout.
final class InvoiceTaxRate {
  const InvoiceTaxRate._(this.units);
  static const denominator = 1000000;
  final int units;

  factory InvoiceTaxRate.fromPercent(String percent) {
    final match = RegExp(r'^(\d+)(?:\.(\d{1,4}))?$').firstMatch(percent.trim());
    if (match == null) {
      throw const FormatException(
        'Tax rate must be a nonnegative percentage with up to four decimals.',
      );
    }
    final units =
        BigInt.parse(match.group(1)!) * BigInt.from(10000) +
        BigInt.parse((match.group(2) ?? '').padRight(4, '0'));
    if (units > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Tax rate is too large.');
    }
    return InvoiceTaxRate._(units.toInt());
  }
}

final class InvoiceTaxCalculation {
  const InvoiceTaxCalculation._({
    required this.net,
    required this.tax,
    required this.total,
  });
  final Money net, tax, total;

  /// Amount is the line amount after discounts, already rounded in its currency.
  /// Inclusive amounts stay fixed: rounded tax is subtracted to obtain net.
  factory InvoiceTaxCalculation.calculate({
    required Money amount,
    required InvoiceTaxRate rate,
    required bool inclusive,
  }) {
    if (amount.isNegative) {
      throw ArgumentError('Invoice taxable amount cannot be negative.');
    }
    final base = BigInt.from(amount.minorUnits);
    final numerator = base * BigInt.from(rate.units);
    final denominator =
        BigInt.from(InvoiceTaxRate.denominator) +
        (inclusive ? BigInt.from(rate.units) : BigInt.zero);
    final quotient = numerator ~/ denominator;
    final remainder = numerator % denominator;
    final roundedTax =
        quotient +
        (remainder * BigInt.two >= denominator ? BigInt.one : BigInt.zero);
    final total = inclusive ? base : base + roundedTax;
    final net = inclusive ? base - roundedTax : base;
    Money money(BigInt value) {
      if (value < BigInt.zero || value > BigInt.from(0x7fffffffffffffff)) {
        throw RangeError(
          'Invoice tax calculation exceeds the supported amount range.',
        );
      }
      return Money.fromMinor(value.toInt(), amount.currency);
    }

    return InvoiceTaxCalculation._(
      net: money(net),
      tax: money(roundedTax),
      total: money(total),
    );
  }
}
