import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

final class CustomerPaymentAllocationRecord {
  const CustomerPaymentAllocationRecord({
    required this.id,
    required this.paymentId,
    required this.customerId,
    required this.invoiceId,
    required this.amount,
    required this.allocatedAt,
  });

  final EntityId id;
  final EntityId paymentId;
  final EntityId customerId;
  final EntityId invoiceId;
  final Money amount;
  final DateTime allocatedAt;
}

final class CustomerPayment {
  CustomerPayment._({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.receivedAt,
    required this.unappliedAmount,
    required List<EntityId> allocationIds,
    required List<CustomerPaymentAllocationRecord> allocations,
  }) : allocationIds = List.unmodifiable(allocationIds),
       allocations = List.unmodifiable(allocations);

  factory CustomerPayment.received({
    required EntityId id,
    required EntityId customerId,
    required Money amount,
    required DateTime receivedAt,
  }) {
    if (!amount.isPositive) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A payment must be positive.',
      );
    }
    return CustomerPayment._(
      id: id,
      customerId: customerId,
      amount: amount,
      receivedAt: receivedAt.toUtc(),
      unappliedAmount: amount,
      allocationIds: const [],
      allocations: const [],
    );
  }

  final EntityId id;
  final EntityId customerId;
  final Money amount;
  final DateTime receivedAt;
  final Money unappliedAmount;

  /// Invoice IDs retained for compatibility with the original single-allocation API.
  final List<EntityId> allocationIds;

  /// Immutable, auditable allocation records with distinct allocation IDs.
  final List<CustomerPaymentAllocationRecord> allocations;

  List<EntityId> get auditAllocationIds =>
      List.unmodifiable(allocations.map((allocation) => allocation.id));

  CustomerPaymentAllocation allocateTo(
    Invoice invoice, {
    EntityId? allocationId,
    DateTime? allocatedAt,
    Money? amount,
  }) {
    final allocationTime = (allocatedAt ?? receivedAt).toUtc();
    if (allocationTime.isBefore(receivedAt)) {
      throw StateError('An allocation cannot precede receipt of its payment.');
    }
    if (invoice.customerId != customerId) {
      throw StateError('A payment can only be allocated to its customer.');
    }
    if (allocationIds.contains(invoice.id)) {
      throw StateError('A payment cannot be allocated to an invoice twice.');
    }
    if (unappliedAmount.isZero) {
      throw StateError('This payment has no unapplied amount.');
    }
    final amountToOffer = amount ?? unappliedAmount;
    if (!amountToOffer.isPositive) {
      throw ArgumentError.value(
        amountToOffer,
        'amount',
        'An allocation amount must be positive.',
      );
    }
    if (amountToOffer.currency != this.amount.currency ||
        amountToOffer.currency != invoice.total.currency) {
      throw StateError('An allocation must use the payment currency.');
    }
    final resolvedAllocationId = allocationId ?? invoice.id;
    if (allocations.any(
      (allocation) => allocation.id == resolvedAllocationId,
    )) {
      throw StateError('An allocation ID can only be used once.');
    }

    final amountLimitedByPayment =
        amountToOffer.minorUnits > unappliedAmount.minorUnits
        ? unappliedAmount.minorUnits
        : amountToOffer.minorUnits;
    final appliedMinorUnits =
        amountLimitedByPayment > invoice.remaining.minorUnits
        ? invoice.remaining.minorUnits
        : amountLimitedByPayment;
    if (appliedMinorUnits <= 0) {
      throw StateError('The invoice has no remaining balance.');
    }
    final applied = Money.fromMinor(appliedMinorUnits, amountToOffer.currency);
    final updatedInvoice = invoice.recordPayment(
      paymentId: id,
      amount: applied,
      paidAt: receivedAt,
    );
    final allocation = CustomerPaymentAllocationRecord(
      id: resolvedAllocationId,
      paymentId: id,
      customerId: customerId,
      invoiceId: invoice.id,
      amount: applied,
      allocatedAt: allocationTime,
    );
    final updatedPayment = CustomerPayment._(
      id: id,
      customerId: customerId,
      amount: this.amount,
      receivedAt: receivedAt,
      unappliedAmount: unappliedAmount - applied,
      allocationIds: [...allocationIds, invoice.id],
      allocations: [...allocations, allocation],
    );
    return CustomerPaymentAllocation(
      payment: updatedPayment,
      invoice: updatedInvoice,
      applied: applied,
      allocation: allocation,
    );
  }

  CustomerPaymentAllocationBatch allocateAcross({
    required List<Invoice> invoices,
    Map<EntityId, EntityId> allocationIds = const {},
    Map<EntityId, Money> requestedAmounts = const {},
  }) {
    if (invoices.isEmpty) {
      throw ArgumentError.value(
        invoices,
        'invoices',
        'At least one invoice is required.',
      );
    }
    final invoiceIds = invoices.map((invoice) => invoice.id).toSet();
    if (invoiceIds.length != invoices.length) {
      throw ArgumentError.value(
        invoices,
        'invoices',
        'An invoice cannot be included twice.',
      );
    }
    if (allocationIds.isNotEmpty &&
        (allocationIds.length != invoices.length ||
            !invoiceIds.every(allocationIds.containsKey) ||
            allocationIds.values.toSet().length != invoices.length)) {
      throw ArgumentError.value(
        allocationIds,
        'allocationIds',
        'Every invoice requires one distinct allocation ID.',
      );
    }
    if (requestedAmounts.isNotEmpty &&
        (requestedAmounts.length != invoices.length ||
            !invoiceIds.every(requestedAmounts.containsKey))) {
      throw ArgumentError.value(
        requestedAmounts,
        'requestedAmounts',
        'Every invoice requires exactly one requested amount.',
      );
    }
    for (final invoice in invoices) {
      if (invoice.customerId != customerId) {
        throw StateError('A payment can only be allocated to its customer.');
      }
      if (invoice.total.currency != amount.currency) {
        throw StateError('A payment must use the invoice currency.');
      }
      if (invoice.paymentIds.contains(id)) {
        throw StateError('A payment cannot be allocated to an invoice twice.');
      }
      final requestedAmount = requestedAmounts[invoice.id];
      if (requestedAmount != null) {
        if (!requestedAmount.isPositive) {
          throw ArgumentError.value(
            requestedAmount,
            'requestedAmounts',
            'Allocation amounts must be positive.',
          );
        }
        if (requestedAmount.currency != amount.currency) {
          throw StateError('An allocation must use the payment currency.');
        }
      }
    }

    var currentPayment = this;
    final updatedInvoices = <Invoice>[];
    final updatedAllocations = <CustomerPaymentAllocationRecord>[];
    for (final invoice in invoices) {
      if (currentPayment.unappliedAmount.isZero) {
        updatedInvoices.add(invoice);
        continue;
      }
      final result = currentPayment.allocateTo(
        invoice,
        allocationId: allocationIds[invoice.id],
        amount: requestedAmounts[invoice.id],
      );
      currentPayment = result.payment;
      updatedInvoices.add(result.invoice);
      updatedAllocations.add(result.allocation);
    }

    var totalApplied = Money.zero(amount.currency);
    for (final allocation in updatedAllocations) {
      totalApplied += allocation.amount;
    }
    return CustomerPaymentAllocationBatch(
      payment: currentPayment,
      invoices: updatedInvoices,
      allocations: updatedAllocations,
      totalApplied: totalApplied,
    );
  }
}

final class CustomerPaymentAllocation {
  const CustomerPaymentAllocation({
    required this.payment,
    required this.invoice,
    required this.applied,
    required this.allocation,
  });

  final CustomerPayment payment;
  final Invoice invoice;
  final Money applied;
  final CustomerPaymentAllocationRecord allocation;
}

final class CustomerPaymentAllocationBatch {
  CustomerPaymentAllocationBatch({
    required this.payment,
    required List<Invoice> invoices,
    required List<CustomerPaymentAllocationRecord> allocations,
    required this.totalApplied,
  }) : invoices = List.unmodifiable(invoices),
       allocations = List.unmodifiable(allocations);

  final CustomerPayment payment;
  final List<Invoice> invoices;
  final List<CustomerPaymentAllocationRecord> allocations;
  final Money totalApplied;
}
