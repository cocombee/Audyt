import '../../accounting/domain/company_tax_rate.dart';
import 'invoice_tax.dart';
import 'product_catalogue.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

enum SalesLineKind { item, category }

final class SalesQuantity {
  static const int scale = 1000;

  const SalesQuantity._(this.scaledUnits);

  factory SalesQuantity.fromInt(int units) {
    if (units <= 0) {
      throw ArgumentError.value(
        units,
        'units',
        'A sales quantity must be positive.',
      );
    }
    return SalesQuantity._(
      _checkedQuantity(BigInt.from(units) * BigInt.from(scale)),
    );
  }

  factory SalesQuantity.fromDecimal(String value) {
    final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(value.trim());
    if (match == null) {
      throw FormatException(
        'Quantity must be a positive number with up to three decimals.',
        value,
      );
    }
    final whole = BigInt.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    final scaledUnits = whole * BigInt.from(scale) + BigInt.parse(fraction);
    if (scaledUnits <= BigInt.zero) {
      throw ArgumentError.value(
        value,
        'value',
        'A sales quantity must be positive.',
      );
    }
    return SalesQuantity._(_checkedQuantity(scaledUnits));
  }

  final int scaledUnits;

  /// Inverse pricing rounds a positive rate upward to the currency cent.
  /// The exact entered amount remains separate from this rounded display rate.
  Money rateFor(Money amount) {
    final numerator = BigInt.from(amount.minorUnits) * BigInt.from(scale);
    final denominator = BigInt.from(scaledUnits);
    final magnitude = numerator.abs();
    final rounded =
        magnitude ~/ denominator +
        (magnitude % denominator != BigInt.zero ? BigInt.one : BigInt.zero);
    final result = numerator.isNegative ? -rounded : rounded;
    if (result.abs() > BigInt.parse('9223372036854775807')) {
      throw RangeError('Rate exceeds the supported exact amount range.');
    }
    return Money.fromMinor(result.toInt(), amount.currency);
  }

  Money multiply(Money amount) {
    // Intermediate products can exceed int even when the rounded amount fits.
    // Round the magnitude, then apply its sign: half away from zero.
    final product = BigInt.from(amount.minorUnits) * BigInt.from(scaledUnits);
    final divisor = BigInt.from(scale);
    final magnitude = product.abs();
    final roundedMagnitude =
        magnitude ~/ divisor +
        (magnitude % divisor * BigInt.two >= divisor
            ? BigInt.one
            : BigInt.zero);
    final rounded = product.isNegative ? -roundedMagnitude : roundedMagnitude;
    if (rounded < BigInt.parse('-9223372036854775808') ||
        rounded > BigInt.parse('9223372036854775807')) {
      throw RangeError(
        'Quantity pricing exceeds the supported exact amount range.',
      );
    }
    return Money.fromMinor(rounded.toInt(), amount.currency);
  }

  static int _checkedQuantity(BigInt value) {
    if (value > BigInt.parse('9223372036854775807')) {
      throw RangeError('Quantity exceeds the supported exact quantity range.');
    }
    return value.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is SalesQuantity && other.scaledUnits == scaledUnits;

  @override
  int get hashCode => scaledUnits.hashCode;

  @override
  String toString() {
    final whole = scaledUnits ~/ scale;
    final fraction = (scaledUnits % scale).toString().padLeft(3, '0');
    final trimmedFraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmedFraction.isEmpty ? '$whole' : '$whole.$trimmedFraction';
  }
}

final class SalesLineItem {
  SalesLineItem._({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.categoryId,
    required this.description,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.tax,
    required this.taxInclusive,
    required this.taxRatePercent,
    required this.taxCodeId,
    required this.sourceLineId,
    this.catalogue,
    this.taxSnapshot,
    this.manualAmount,
    this.rateEnabled = true,
  });

  factory SalesLineItem.item({
    required EntityId id,
    required EntityId itemId,
    required String description,
    required SalesQuantity quantity,
    required Money rate,
    Money? manualAmount,
    bool rateEnabled = true,
    Money? discount,
    Money? tax,
    EntityId? taxCodeId,
    CompanyTaxRate? taxSnapshot,
    bool taxInclusive = false,
    String? taxRatePercent,
  }) {
    return SalesLineItem._create(
      id: id,
      kind: SalesLineKind.item,
      itemId: itemId,
      categoryId: null,
      description: description,
      quantity: quantity,
      rate: rate,
      manualAmount: manualAmount,
      rateEnabled: rateEnabled,
      discount: discount,
      tax: tax,
      taxCodeId: taxSnapshot?.id ?? taxCodeId,
      taxSnapshot: taxSnapshot,
      taxInclusive: taxInclusive,
      taxRatePercent: taxRatePercent,
    );
  }

  factory SalesLineItem.category({
    required EntityId id,
    required EntityId categoryId,
    required String description,
    required SalesQuantity quantity,
    required Money rate,
    Money? manualAmount,
    bool rateEnabled = true,
    Money? discount,
    Money? tax,
    EntityId? taxCodeId,
    CompanyTaxRate? taxSnapshot,
    bool taxInclusive = false,
    String? taxRatePercent,
    EntityId? sourceLineId,
    CatalogueLineSnapshot? catalogue,
  }) {
    return SalesLineItem._create(
      id: id,
      kind: SalesLineKind.category,
      itemId: null,
      categoryId: categoryId,
      description: description,
      quantity: quantity,
      rate: rate,
      manualAmount: manualAmount,
      rateEnabled: rateEnabled,
      discount: discount,
      tax: tax,
      taxCodeId: taxSnapshot?.id ?? taxCodeId,
      taxSnapshot: taxSnapshot,
      taxInclusive: taxInclusive,
      taxRatePercent: taxRatePercent,
      sourceLineId: sourceLineId,
      catalogue: catalogue,
    );
  }

  factory SalesLineItem._create({
    required EntityId id,
    required SalesLineKind kind,
    required EntityId? itemId,
    required EntityId? categoryId,
    required String description,
    required SalesQuantity quantity,
    required Money rate,
    Money? manualAmount,
    bool rateEnabled = true,
    required Money? discount,
    required Money? tax,
    required EntityId? taxCodeId,
    CompanyTaxRate? taxSnapshot,
    bool taxInclusive = false,
    String? taxRatePercent,
    EntityId? sourceLineId,
    CatalogueLineSnapshot? catalogue,
  }) {
    if (taxSnapshot != null &&
        (taxCodeId != null && taxCodeId != taxSnapshot.id ||
            taxRatePercent != taxSnapshot.percent)) {
      throw ArgumentError('Tax snapshot must match the retained line rate.');
    }
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'A sales line description is required.',
      );
    }
    if (rate.isNegative || (!rate.isPositive && rateEnabled)) {
      throw ArgumentError.value(
        rate,
        'rate',
        'A sales line rate must be positive.',
      );
    }
    if (!rateEnabled && manualAmount == null) {
      throw ArgumentError('Quantity-only pricing requires a manual amount.');
    }
    if (manualAmount != null &&
        (!manualAmount.isPositive || manualAmount.currency != rate.currency)) {
      throw ArgumentError(
        'A manual amount must be positive and use the line currency.',
      );
    }
    final gross = manualAmount ?? quantity.multiply(rate);
    final normalizedDiscount = discount ?? Money.zero(rate.currency);
    final calculated = taxRatePercent == null
        ? null
        : InvoiceTaxCalculation.calculate(
            amount: gross - normalizedDiscount,
            rate: InvoiceTaxRate.fromPercent(taxRatePercent),
            inclusive: taxInclusive,
          ).tax;
    if (calculated != null && tax != null && calculated != tax) {
      throw ArgumentError(
        'Tax amount does not match the retained rate and pricing basis.',
      );
    }
    final normalizedTax = calculated ?? tax ?? Money.zero(rate.currency);
    if (normalizedDiscount.currency != rate.currency ||
        normalizedTax.currency != rate.currency) {
      throw StateError('A sales line must use one currency.');
    }
    if (normalizedDiscount.isNegative || normalizedTax.isNegative) {
      throw ArgumentError.value(
        normalizedDiscount.isNegative ? normalizedDiscount : normalizedTax,
        'lineAmounts',
        'Discount and tax amounts cannot be negative.',
      );
    }
    if (normalizedDiscount.minorUnits > gross.minorUnits) {
      throw ArgumentError.value(
        normalizedDiscount,
        'discount',
        'A line discount cannot exceed its gross amount.',
      );
    }
    if (taxInclusive &&
        normalizedTax.minorUnits > (gross - normalizedDiscount).minorUnits) {
      throw ArgumentError(
        'Included tax cannot exceed the discounted line amount.',
      );
    }
    return SalesLineItem._(
      id: id,
      kind: kind,
      itemId: itemId,
      categoryId: categoryId,
      description: normalizedDescription,
      quantity: quantity,
      rate: rate,
      manualAmount: manualAmount,
      rateEnabled: rateEnabled,
      discount: normalizedDiscount,
      tax: normalizedTax,
      taxCodeId: taxSnapshot?.id ?? taxCodeId,
      taxSnapshot: taxSnapshot,
      taxInclusive: taxInclusive,
      taxRatePercent: taxRatePercent,
      sourceLineId: sourceLineId,
      catalogue: catalogue,
    );
  }

  static Money totalFor(Iterable<SalesLineItem> lines) {
    final lineList = lines.toList(growable: false);
    if (lineList.isEmpty) {
      throw ArgumentError.value(
        lines,
        'lines',
        'At least one sales line is required to calculate a total.',
      );
    }
    if (lineList.map((line) => line.id).toSet().length != lineList.length) {
      throw ArgumentError(
        'A sales document cannot contain duplicate line identities.',
      );
    }
    var total = lineList.first.total;
    for (final line in lineList.skip(1)) {
      total += line.total;
    }
    return total;
  }

  SalesLineItem copyForInvoice({required EntityId invoiceLineId}) {
    return SalesLineItem._(
      id: invoiceLineId,
      kind: kind,
      itemId: itemId,
      categoryId: categoryId,
      description: description,
      quantity: quantity,
      rate: rate,
      manualAmount: manualAmount,
      rateEnabled: rateEnabled,
      discount: discount,
      tax: tax,
      taxCodeId: taxSnapshot?.id ?? taxCodeId,
      taxSnapshot: taxSnapshot,
      taxInclusive: taxInclusive,
      taxRatePercent: taxRatePercent,
      sourceLineId: id,
      catalogue: catalogue,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id.value,
    'kind': kind.name,
    'item': itemId?.value,
    'category': categoryId?.value,
    'description': description,
    'quantity': quantity.toString(),
    'rate': rate.minorUnits,
    if (manualAmount != null) 'manualAmountMinor': manualAmount!.minorUnits,
    if (!rateEnabled) 'rateEnabled': false,
    'discount': discount.minorUnits,
    'tax': tax.minorUnits,
    if (taxInclusive) 'taxInclusive': true,
    if (taxRatePercent != null) 'taxRatePercent': taxRatePercent,
    'currency': rate.currency,
    'taxCode': taxCodeId?.value,
    if (taxSnapshot != null) 'taxSnapshot': taxSnapshot!.toJson(),
    'sourceLine': sourceLineId?.value,
    if (catalogue != null) 'catalogue': catalogue!.toJson(),
    if (catalogue != null) 'subtotalMinor': subtotal.minorUnits,
  };

  factory SalesLineItem.fromJson(Map<String, dynamic> j) {
    EntityId? id(dynamic v) => v == null ? null : EntityId.parse(v as String);
    final kind = SalesLineKind.values.byName(j['kind'] as String);
    final item = id(j['item']);
    final category = id(j['category']);
    if ((kind == SalesLineKind.item && (item == null || category != null)) ||
        (kind == SalesLineKind.category &&
            (category == null || item != null))) {
      throw const FormatException('Invalid sales line ownership.');
    }
    final currency = j['currency'] as String;
    return SalesLineItem._create(
      id: EntityId.parse(j['id'] as String),
      kind: kind,
      itemId: item,
      categoryId: category,
      description: j['description'] as String,
      quantity: SalesQuantity.fromDecimal(j['quantity'] as String),
      rate: Money.fromMinor(j['rate'] as int, currency),
      manualAmount: j['manualAmountMinor'] == null
          ? null
          : Money.fromMinor(j['manualAmountMinor'] as int, currency),
      rateEnabled: j['rateEnabled'] as bool? ?? true,
      discount: Money.fromMinor(j['discount'] as int, currency),
      tax: Money.fromMinor(j['tax'] as int, currency),
      taxCodeId: id(j['taxCode']),
      taxSnapshot: j['taxSnapshot'] == null
          ? null
          : CompanyTaxRate.fromJson(
              Map<String, dynamic>.from(j['taxSnapshot'] as Map),
            ),
      taxInclusive: j['taxInclusive'] as bool? ?? false,
      taxRatePercent: j['taxRatePercent'] as String?,
      sourceLineId: id(j['sourceLine']),
      catalogue: j['catalogue'] == null
          ? null
          : CatalogueLineSnapshot.fromJson(
              Map<String, dynamic>.from(j['catalogue'] as Map),
            ),
    );
  }

  final CompanyTaxRate? taxSnapshot;
  final EntityId id;
  final SalesLineKind kind;
  final EntityId? itemId;
  final EntityId? categoryId;
  final String description;
  final SalesQuantity quantity;
  final Money rate;

  /// A manual amount keeps quantity informational, or preserves an exact amount
  /// whose inverse rate cannot be represented in currency minor units.
  final Money? manualAmount;
  final bool rateEnabled;
  final Money discount;
  final Money tax;
  final bool taxInclusive;
  final String? taxRatePercent;
  final EntityId? taxCodeId;
  final EntityId? sourceLineId;
  final CatalogueLineSnapshot? catalogue;

  Money get gross => manualAmount ?? quantity.multiply(rate);
  Money get pricingAdjustment => rateEnabled && manualAmount != null
      ? quantity.multiply(rate) - manualAmount!
      : Money.zero(rate.currency);
  Money get subtotal =>
      gross - discount - (taxInclusive ? tax : Money.zero(rate.currency));
  Money get total => subtotal + tax;
}
