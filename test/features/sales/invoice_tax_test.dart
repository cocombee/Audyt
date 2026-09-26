import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice_tax.dart';

void main() {
  test('inclusive line snapshot retains pricing basis and rejects tax tampering', () {
    final line = SalesLineItem.category(id: EntityId.random(), categoryId: EntityId.random(), description: 'Inclusive item', quantity: SalesQuantity.fromInt(2), rate: Money.fromMinor(5400, 'MYR'), taxInclusive: true, taxRatePercent: '8');
    expect(line.subtotal.minorUnits, 10000);
    expect(line.total.minorUnits, 10800);
    expect(line.tax.minorUnits, 800);
    final restored = SalesLineItem.fromJson(Map<String, dynamic>.from(line.toJson()));
    expect(restored.toJson(), line.toJson());
    expect(restored.copyForInvoice(invoiceLineId: EntityId.random()).total, line.total);
    expect(() => SalesLineItem.fromJson({...line.toJson(), 'tax': 0}), throwsArgumentError);
  });
  test('exclusive and inclusive rates reconcile without floating point', () {
    final rate = InvoiceTaxRate.fromPercent('8');
    final exclusive = InvoiceTaxCalculation.calculate(amount: Money.fromDecimal('100', 'MYR'), rate: rate, inclusive: false);
    final inclusive = InvoiceTaxCalculation.calculate(amount: Money.fromDecimal('108', 'MYR'), rate: rate, inclusive: true);
    expect(exclusive.total, inclusive.total);
    expect(exclusive.tax.minorUnits, 800);
    expect(inclusive.net.minorUnits, 10000);
    expect(inclusive.net + inclusive.tax, inclusive.total);
  });
  test('minor-unit rounding, fractional rates and currency precision', () {
    final half = InvoiceTaxCalculation.calculate(amount: Money.fromMinor(1, 'JPY'), rate: InvoiceTaxRate.fromPercent('50'), inclusive: false);
    expect(half.tax.minorUnits, 1);
    final fractional = InvoiceTaxCalculation.calculate(amount: Money.fromMinor(1000000, 'KWD'), rate: InvoiceTaxRate.fromPercent('0.0001'), inclusive: false);
    expect(fractional.tax.minorUnits, 1);
    for (var amount = 0; amount < 300; amount++) {
      final result = InvoiceTaxCalculation.calculate(amount: Money.fromMinor(amount, 'MYR'), rate: InvoiceTaxRate.fromPercent('6.25'), inclusive: true);
      expect(result.net + result.tax, result.total);
      expect(result.total.minorUnits, amount);
    }
  });
  test('invalid rates, negative invoice amounts and overflow reject', () {
    for (final value in ['-1', '1.00001', 'NaN', '8%', '1e3']) {
      expect(() => InvoiceTaxRate.fromPercent(value), throwsFormatException);
    }
    expect(() => InvoiceTaxCalculation.calculate(amount: Money.fromMinor(-1, 'MYR'), rate: InvoiceTaxRate.fromPercent('8'), inclusive: false), throwsArgumentError);
    expect(() => InvoiceTaxCalculation.calculate(amount: Money.fromMinor(0x7fffffffffffffff, 'MYR'), rate: InvoiceTaxRate.fromPercent('100'), inclusive: false), throwsRangeError);
  });
}
