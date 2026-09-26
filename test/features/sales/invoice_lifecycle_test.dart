import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'age bands follow due date and a late partial payment remains overdue',
    () {
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: EntityId.random(),
        total: Money.fromMinor(10000, 'MYR'),
        issueDate: DateTime.utc(2026, 1, 1),
        dueDate: DateTime.utc(2026, 1, 31),
      ).send();
      final due = invoice.dueDate;
      for (final entry in <int, ReceivableAgeBand>{
        0: ReceivableAgeBand.current,
        1: ReceivableAgeBand.days1To30,
        30: ReceivableAgeBand.days1To30,
        31: ReceivableAgeBand.days31To60,
        60: ReceivableAgeBand.days31To60,
        61: ReceivableAgeBand.days61To90,
        90: ReceivableAgeBand.days61To90,
        91: ReceivableAgeBand.over90,
      }.entries) {
        expect(
          invoice.ageBand(asOf: due.add(Duration(days: entry.key))),
          entry.value,
        );
      }
      final partial = invoice.recordPayment(
        paymentId: EntityId.random(),
        amount: Money.fromMinor(4000, 'MYR'),
        paidAt: due.add(const Duration(days: 31)),
      );
      expect(partial.status, InvoiceStatus.overdue);
      expect(partial.remaining, Money.fromMinor(6000, 'MYR'));
      final paid = partial.recordPayment(
        paymentId: EntityId.random(),
        amount: Money.fromMinor(6000, 'MYR'),
        paidAt: due.add(const Duration(days: 91)),
      );
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.daysOverdue(asOf: due.add(const Duration(days: 100))), 0);
      expect(
        invoice.dispute().daysOverdue(asOf: due.add(const Duration(days: 91))),
        91,
      );
      expect(
        invoice.writeOff().daysOverdue(asOf: due.add(const Duration(days: 91))),
        0,
      );
    },
  );

  test('invoice uses shared monthly terms and cutoff across year end', () {
    final invoice = Invoice.draft(
      id: EntityId.random(),
      customerId: EntityId.random(),
      total: Money.fromMinor(100, 'MYR'),
      issueDate: DateTime(2026, 12, 28),
      terms: PaymentTerms.dayOfMonth(31, rolloverWithinDays: 5),
    );
    expect(invoice.dueDate, DateTime.utc(2027, 1, 31));
    expect(invoice.terms.kind, PaymentTermKind.dayOfMonth);
    expect(invoice.terms.dueInDays, isNull);
  });
  test('sends an invoice and records a partial customer payment', () {
    final invoice = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb101'),
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb102'),
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 30),
      dueDate: DateTime.utc(2026, 9, 29),
    );

    final sent = invoice.send();
    final paymentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb103');
    final partial = sent.recordPayment(
      paymentId: paymentId,
      amount: Money.fromMinor(400, 'USD'),
      paidAt: DateTime.utc(2026, 8, 31, 10),
    );

    expect(sent.status, InvoiceStatus.sent);
    expect(partial.status, InvoiceStatus.partiallyPaid);
    expect(partial.amountPaid, Money.fromMinor(400, 'USD'));
    expect(partial.remaining, Money.fromMinor(600, 'USD'));
    expect(partial.paymentIds, contains(paymentId));
  });

  test('keeps an overpayment as unapplied credit', () {
    final invoice = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb111'),
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb112'),
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 30),
      dueDate: DateTime.utc(2026, 9, 29),
    ).send();

    final paid = invoice.recordPayment(
      paymentId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb113'),
      amount: Money.fromMinor(1250, 'USD'),
      paidAt: DateTime.utc(2026, 8, 31, 10),
    );

    expect(paid.status, InvoiceStatus.paid);
    expect(paid.remaining, Money.zero('USD'));
    expect(paid.amountPaid, Money.fromMinor(1000, 'USD'));
    expect(paid.unappliedCredit, Money.fromMinor(250, 'USD'));
  });

  test('marks an open invoice overdue only after its due date', () {
    final sent = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb121'),
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cb122'),
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 1),
      dueDate: DateTime.utc(2026, 8, 15),
    ).send();

    expect(
      sent.markOverdue(asOf: DateTime.utc(2026, 8, 14)).status,
      InvoiceStatus.sent,
    );
    expect(
      sent.markOverdue(asOf: DateTime.utc(2026, 8, 15, 23, 59)).status,
      InvoiceStatus.sent,
    );
    expect(
      sent.markOverdue(asOf: DateTime.utc(2026, 8, 16)).status,
      InvoiceStatus.overdue,
    );
  });
}
