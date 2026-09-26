import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/bill.dart';

final class BillPaymentBatch {
  BillPaymentBatch._({
    required this.id,
    required List<Bill> bills,
    required this.allocations,
    required this.paidAt,
    required this.total,
  }) : bills = List.unmodifiable(bills);

  factory BillPaymentBatch.create({
    required EntityId id,
    required List<Bill> bills,
    required Map<EntityId, Money> allocations,
    required DateTime paidAt,
  }) {
    if (bills.isEmpty) {
      throw ArgumentError.value(
        bills,
        'bills',
        'At least one bill is required.',
      );
    }
    final billIds = bills.map((bill) => bill.id).toSet();
    if (billIds.length != bills.length) {
      throw ArgumentError.value(
        bills,
        'bills',
        'A bill cannot be included twice.',
      );
    }
    if (!allocations.keys.every(billIds.contains) ||
        allocations.length != billIds.length) {
      throw ArgumentError.value(
        allocations,
        'allocations',
        'Every bill must have exactly one payment allocation.',
      );
    }

    final currencies = bills.map((bill) => bill.total.currency).toSet();
    if (currencies.length != 1) {
      throw ArgumentError.value(
        bills,
        'bills',
        'A payment batch must use one currency.',
      );
    }
    var total = Money.zero(bills.first.total.currency);
    for (final bill in bills) {
      final allocation = allocations[bill.id]!;
      if (!allocation.isPositive) {
        throw ArgumentError.value(
          allocation,
          'allocations',
          'Payment allocations must be positive.',
        );
      }
      if (allocation.currency != bill.total.currency) {
        throw StateError('A payment must use the bill currency.');
      }
      if (allocation.minorUnits > bill.remaining.minorUnits) {
        throw ArgumentError.value(
          allocation,
          'allocations',
          'A bill payment cannot exceed the bill balance.',
        );
      }
      total += allocation;
    }

    final normalizedPaidAt = paidAt.toUtc();
    return BillPaymentBatch._(
      id: id,
      bills: bills
          .map(
            (bill) => bill.recordPayment(
              paymentId: id,
              amount: allocations[bill.id]!,
              paidAt: normalizedPaidAt,
            ),
          )
          .toList(),
      allocations: Map.unmodifiable(allocations),
      paidAt: normalizedPaidAt,
      total: total,
    );
  }

  final EntityId id;
  final List<Bill> bills;
  final Map<EntityId, Money> allocations;
  final DateTime paidAt;
  final Money total;
}
