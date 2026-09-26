import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/customer_payment.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allocates one customer payment across multiple invoices', () {
    final customerId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf601');
    final invoiceOne = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf602'),
      customerId: customerId,
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 1),
      dueDate: DateTime.utc(2026, 8, 31),
    ).send();
    final invoiceTwo = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf603'),
      customerId: customerId,
      total: Money.fromMinor(500, 'USD'),
      issueDate: DateTime.utc(2026, 8, 2),
      dueDate: DateTime.utc(2026, 9, 1),
    ).send();
    final allocationOneId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf604',
    );
    final allocationTwoId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf605',
    );
    final payment = CustomerPayment.received(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf606'),
      customerId: customerId,
      amount: Money.fromMinor(1250, 'USD'),
      receivedAt: DateTime.utc(2026, 8, 10, 10),
    );

    final batch = payment.allocateAcross(
      invoices: [invoiceOne, invoiceTwo],
      allocationIds: {
        invoiceOne.id: allocationOneId,
        invoiceTwo.id: allocationTwoId,
      },
    );

    expect(batch.invoices[0].status, InvoiceStatus.paid);
    expect(batch.invoices[0].amountPaid, Money.fromMinor(1000, 'USD'));
    expect(batch.invoices[1].status, InvoiceStatus.partiallyPaid);
    expect(batch.invoices[1].amountPaid, Money.fromMinor(250, 'USD'));
    expect(batch.payment.unappliedAmount, Money.zero('USD'));
    expect(batch.totalApplied, Money.fromMinor(1250, 'USD'));
    expect(batch.allocations, hasLength(2));
    expect(batch.allocations[0].id, allocationOneId);
    expect(batch.allocations[0].invoiceId, invoiceOne.id);
    expect(batch.allocations[1].id, allocationTwoId);
    expect(batch.payment.auditAllocationIds, [
      allocationOneId,
      allocationTwoId,
    ]);
  });

  test(
    'honors explicit amounts and leaves the remaining payment unapplied',
    () {
      final customerId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf701');
      final invoiceOne = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf702'),
        customerId: customerId,
        total: Money.fromMinor(1000, 'USD'),
        issueDate: DateTime.utc(2026, 8, 1),
        dueDate: DateTime.utc(2026, 8, 31),
      ).send();
      final invoiceTwo = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf703'),
        customerId: customerId,
        total: Money.fromMinor(800, 'USD'),
        issueDate: DateTime.utc(2026, 8, 2),
        dueDate: DateTime.utc(2026, 9, 1),
      ).send();
      final payment = CustomerPayment.received(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf704'),
        customerId: customerId,
        amount: Money.fromMinor(1000, 'USD'),
        receivedAt: DateTime.utc(2026, 8, 10, 10),
      );

      final batch = payment.allocateAcross(
        invoices: [invoiceOne, invoiceTwo],
        allocationIds: {
          invoiceOne.id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf705'),
          invoiceTwo.id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf706'),
        },
        requestedAmounts: {
          invoiceOne.id: Money.fromMinor(200, 'USD'),
          invoiceTwo.id: Money.fromMinor(300, 'USD'),
        },
      );

      expect(batch.invoices[0].amountPaid, Money.fromMinor(200, 'USD'));
      expect(batch.invoices[1].amountPaid, Money.fromMinor(300, 'USD'));
      expect(batch.totalApplied, Money.fromMinor(500, 'USD'));
      expect(batch.payment.unappliedAmount, Money.fromMinor(500, 'USD'));
    },
  );

  test(
    'keeps overpayments unapplied and rejects invalid or repeated allocations',
    () {
      final customerId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf711');
      final invoice = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf712'),
        customerId: customerId,
        total: Money.fromMinor(1000, 'USD'),
        issueDate: DateTime.utc(2026, 8, 1),
        dueDate: DateTime.utc(2026, 8, 31),
      ).send();
      final secondInvoice = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf713'),
        customerId: customerId,
        total: Money.fromMinor(500, 'USD'),
        issueDate: DateTime.utc(2026, 8, 2),
        dueDate: DateTime.utc(2026, 9, 1),
      ).send();
      final payment = CustomerPayment.received(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf714'),
        customerId: customerId,
        amount: Money.fromMinor(1800, 'USD'),
        receivedAt: DateTime.utc(2026, 8, 10, 10),
      );
      final allocationId = EntityId.parse(
        '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf715',
      );
      final allocated = payment.allocateTo(invoice, allocationId: allocationId);

      final overpaid = allocated.payment.allocateAcross(
        invoices: [secondInvoice],
        allocationIds: {
          secondInvoice.id: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf716',
          ),
        },
      );
      expect(overpaid.invoices.single.status, InvoiceStatus.paid);
      expect(overpaid.payment.unappliedAmount, Money.fromMinor(300, 'USD'));
      expect(
        () => allocated.payment.allocateTo(
          invoice,
          allocationId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf717'),
        ),
        throwsStateError,
      );

      final differentCustomerInvoice = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf718'),
        customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf719'),
        total: Money.fromMinor(100, 'USD'),
        issueDate: DateTime.utc(2026, 8, 1),
        dueDate: DateTime.utc(2026, 8, 31),
      ).send();
      final differentCurrencyInvoice = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf720'),
        customerId: customerId,
        total: Money.fromMinor(100, 'EUR'),
        issueDate: DateTime.utc(2026, 8, 1),
        dueDate: DateTime.utc(2026, 8, 31),
      ).send();
      expect(
        () => payment.allocateAcross(invoices: [differentCustomerInvoice]),
        throwsStateError,
      );
      expect(
        () => payment.allocateAcross(invoices: [differentCurrencyInvoice]),
        throwsStateError,
      );
    },
  );
}
