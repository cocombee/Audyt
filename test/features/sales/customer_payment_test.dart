import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/customer_payment.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies a customer payment and preserves an unapplied remainder', () {
    final paymentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ce101');
    final invoice = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ce102'),
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ce103'),
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 30),
      dueDate: DateTime.utc(2026, 9, 29),
    ).send();
    final payment = CustomerPayment.received(
      id: paymentId,
      customerId: invoice.customerId,
      amount: Money.fromMinor(1250, 'USD'),
      receivedAt: DateTime.utc(2026, 8, 31, 10),
    );

    expect(
      () => payment.allocateTo(
        invoice,
        allocatedAt: payment.receivedAt.subtract(
          const Duration(microseconds: 1),
        ),
      ),
      throwsStateError,
    );
    expect(payment.allocations, isEmpty);
    expect(payment.unappliedAmount, payment.amount);
    final allocation = payment.allocateTo(
      invoice,
      allocatedAt: payment.receivedAt.add(const Duration(days: 1)),
    );
    expect(
      allocation.allocation.allocatedAt,
      payment.receivedAt.add(const Duration(days: 1)),
    );

    expect(allocation.invoice.status, InvoiceStatus.paid);
    expect(allocation.applied, Money.fromMinor(1000, 'USD'));
    expect(allocation.payment.unappliedAmount, Money.fromMinor(250, 'USD'));
    expect(allocation.payment.allocationIds, contains(invoice.id));
  });
}
