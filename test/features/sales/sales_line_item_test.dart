import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inverse rate rounds upward while exact amount survives snapshot and conversion', () {
    final quantity = SalesQuantity.fromInt(3);
    final amount = Money.fromDecimal('10', 'MYR');
    final rate = quantity.rateFor(amount);
    expect(rate.minorUnits, 334);
    final line = SalesLineItem.category(
      id: EntityId.random(),
      categoryId: EntityId.random(),
      description: 'Corporate Video',
      quantity: quantity,
      rate: rate,
      manualAmount: amount,
      taxRatePercent: '6',
    );
    expect(line.gross.minorUnits, 1000);
    expect(line.pricingAdjustment.minorUnits, 2);
    expect(line.total.minorUnits, 1060);
    final reopened = SalesLineItem.fromJson(line.toJson());
    expect(reopened.toJson(), line.toJson());
    final converted = reopened.copyForInvoice(invoiceLineId: EntityId.random());
    expect(converted.total, line.total);
    expect(converted.pricingAdjustment, line.pricingAdjustment);
    final typedRate = SalesLineItem.category(
      id: line.id,
      categoryId: line.categoryId!,
      description: line.description,
      quantity: quantity,
      rate: Money.fromDecimal('3.30', 'MYR'),
      taxRatePercent: '0',
    );
    expect(typedRate.total.minorUnits, 990);
    expect(typedRate.pricingAdjustment.minorUnits, 0);
    final quantityOnly = SalesLineItem.category(
      id: EntityId.random(),
      categoryId: line.categoryId!,
      description: line.description,
      quantity: SalesQuantity.fromInt(9),
      rate: amount,
      manualAmount: amount,
      rateEnabled: false,
      taxRatePercent: '0',
    );
    expect(quantityOnly.total.minorUnits, 1000);
    expect(SalesLineItem.fromJson(quantityOnly.toJson()).rateEnabled, false);
    expect(
      SalesQuantity.fromInt(4)
          .rateFor(Money.fromDecimal('8', 'MYR'))
          .minorUnits,
      200,
    );
  });

  test(
    'quantity pricing keeps large intermediates exact and rejects overflow',
    () {
      final maximum = Money.fromMinor(9223372036854775807, 'MYR');
      final minimum = Money.fromMinor(-9223372036854775808, 'MYR');
      expect(SalesQuantity.fromInt(1).multiply(maximum), maximum);
      expect(SalesQuantity.fromDecimal('1').multiply(minimum), minimum);
      expect(
        SalesQuantity.fromDecimal('0.5').multiply(maximum).minorUnits,
        4611686018427387904,
      );
      expect(
        SalesQuantity.fromDecimal('0.001')
            .multiply(Money.fromMinor(1500, 'MYR'))
            .minorUnits,
        2,
      );
      expect(
        SalesQuantity.fromDecimal('0.001')
            .multiply(Money.fromMinor(-1500, 'MYR'))
            .minorUnits,
        -2,
      );
      expect(
        SalesQuantity.fromDecimal('0.001')
            .multiply(Money.fromMinor(-1750, 'MYR'))
            .minorUnits,
        -2,
      );
      expect(
        () => SalesQuantity.fromInt(2).multiply(maximum),
        throwsRangeError,
      );
      expect(
        () => SalesQuantity.fromInt(2).multiply(minimum),
        throwsRangeError,
      );
      expect(
        () => SalesQuantity.fromInt(9223372036854775807),
        throwsRangeError,
      );
      expect(
        SalesQuantity.fromDecimal('9223372036854775.807').scaledUnits,
        9223372036854775807,
      );
      expect(
        () => SalesQuantity.fromDecimal('9223372036854775.808'),
        throwsRangeError,
      );
      expect(
        () => SalesQuantity.fromDecimal('18446744073709551617'),
        throwsRangeError,
      );
    },
  );
  test(
    'calculates a typed item line from quantity, rate, discount, and tax',
    () {
      final line = SalesLineItem.item(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf201'),
        itemId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf202'),
        description: 'Consulting',
        quantity: SalesQuantity.fromDecimal('2.5'),
        rate: Money.fromMinor(1000, 'USD'),
        discount: Money.fromMinor(100, 'USD'),
        tax: Money.fromMinor(190, 'USD'),
        taxCodeId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf203'),
      );

      expect(line.quantity, SalesQuantity.fromDecimal('2.5'));
      expect(line.gross, Money.fromMinor(2500, 'USD'));
      expect(line.subtotal, Money.fromMinor(2400, 'USD'));
      expect(line.total, Money.fromMinor(2590, 'USD'));
      expect(line.taxCodeId, isNotNull);
      expect(line.quantity.toString(), '2.5');
    },
  );
}
