import '../../../core/ids/entity_id.dart';
import 'sales_line_item.dart';
import '../../../core/money/money.dart';

/// Allocation of an approved invoice credit. The caller supplies cumulative
/// credits and receipts from immutable records in the posting transaction.
/// Excess credit becomes customer credit; it does not imply a cash refund.
final class InvoiceCreditAllocation {
  const InvoiceCreditAllocation._({
    required this.receivableReduction,
    required this.customerCredit,
    required this.remainingReceivable,
  });
  final Money receivableReduction;
  final Money customerCredit;
  final Money remainingReceivable;

  factory InvoiceCreditAllocation.calculate({
    required Money invoiceTotal,
    required Money priorCredits,
    required Money receiptsApplied,
    required Money credit,
  }) {
    if ([
      priorCredits,
      receiptsApplied,
      credit,
    ].any((m) => m.currency != invoiceTotal.currency)) {
      throw ArgumentError('Invoice credit amounts must use one currency.');
    }
    if (!invoiceTotal.isPositive ||
        !credit.isPositive ||
        priorCredits.isNegative ||
        receiptsApplied.isNegative) {
      throw ArgumentError(
        'Use positive invoice/credit amounts and nonnegative prior amounts.',
      );
    }
    if (priorCredits.minorUnits > invoiceTotal.minorUnits ||
        receiptsApplied.minorUnits > invoiceTotal.minorUnits) {
      throw StateError('Prior amounts exceed the original invoice.');
    }
    final availableCredit = invoiceTotal - priorCredits;
    if (credit.minorUnits > availableCredit.minorUnits) {
      throw StateError(
        'Cumulative credits cannot exceed the original invoice.',
      );
    }
    final netReceivable = availableCredit - receiptsApplied;
    final outstanding = netReceivable.isPositive
        ? netReceivable
        : Money.zero(invoiceTotal.currency);
    final reduction = credit.minorUnits < outstanding.minorUnits
        ? credit
        : outstanding;
    return InvoiceCreditAllocation._(
      receivableReduction: reduction,
      customerCredit: credit - reduction,
      remainingReceivable: outstanding - reduction,
    );
  }
}

/// Splits successive gross credits against the original posted net/tax amounts.
/// Cumulative rounding prevents repeated small credits from creating tax drift.
final class InvoiceCreditLineAmounts {
  const InvoiceCreditLineAmounts._(this.net, this.tax);
  final Money net;
  final Money tax;
  Money get total => net + tax;

  factory InvoiceCreditLineAmounts.calculate({
    required Money originalNet,
    required Money originalTax,
    required Money priorGrossCredit,
    required Money grossCredit,
  }) {
    final currency = originalNet.currency;
    if ([
      originalTax,
      priorGrossCredit,
      grossCredit,
    ].any((m) => m.currency != currency)) {
      throw ArgumentError('Credit line amounts must use one currency.');
    }
    if (originalNet.isNegative ||
        originalTax.isNegative ||
        priorGrossCredit.isNegative ||
        !grossCredit.isPositive) {
      throw ArgumentError('Invalid original or credit line amount.');
    }
    final original = originalNet + originalTax;
    if (!original.isPositive ||
        priorGrossCredit.minorUnits > original.minorUnits ||
        grossCredit.minorUnits > (original - priorGrossCredit).minorUnits) {
      throw StateError('Cumulative line credit exceeds the posted line.');
    }
    int cumulativeTax(int gross) {
      final numerator =
          BigInt.from(gross) * BigInt.from(originalTax.minorUnits);
      final denominator = BigInt.from(original.minorUnits);
      return ((numerator * BigInt.two + denominator) ~/
              (denominator * BigInt.two))
          .toInt();
    }

    final tax = Money.fromMinor(
      cumulativeTax(priorGrossCredit.minorUnits + grossCredit.minorUnits) -
          cumulativeTax(priorGrossCredit.minorUnits),
      currency,
    );
    return InvoiceCreditLineAmounts._(grossCredit - tax, tax);
  }
}

/// Validates source identity before calculating a reviewed credit's line amounts.
Map<EntityId, InvoiceCreditLineAmounts> allocateInvoiceCreditLines({
  required List<SalesLineItem> originalLines,
  required Map<EntityId, Money> priorGrossCredits,
  required Map<EntityId, Money> requestedGrossCredits,
}) {
  final sources = {for (final line in originalLines) line.id: line};
  if (sources.length != originalLines.length || sources.isEmpty) {
    throw StateError('Credit review requires unique original invoice lines.');
  }
  if (requestedGrossCredits.isEmpty ||
      [
        ...priorGrossCredits.keys,
        ...requestedGrossCredits.keys,
      ].any((id) => !sources.containsKey(id))) {
    throw ArgumentError(
      'Credit allocations must identify original invoice lines.',
    );
  }
  for (final prior in priorGrossCredits.entries) {
    final total = sources[prior.key]!.total;
    if (prior.value.currency != total.currency ||
        prior.value.isNegative ||
        prior.value.minorUnits > total.minorUnits) {
      throw StateError('Invalid prior credit allocation.');
    }
  }
  return Map.unmodifiable({
    for (final requested in requestedGrossCredits.entries)
      requested.key: InvoiceCreditLineAmounts.calculate(
        originalNet: sources[requested.key]!.subtotal,
        originalTax: sources[requested.key]!.tax,
        priorGrossCredit:
            priorGrossCredits[requested.key] ??
            Money.zero(requested.value.currency),
        grossCredit: requested.value,
      ),
  });
}
