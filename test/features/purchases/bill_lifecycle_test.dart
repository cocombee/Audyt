import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draft snapshot retains identity and refuses paid-state injection', () {
    final bill = Bill.draft(
      id: EntityId.random(),
      vendorId: EntityId.random(),
      total: Money.fromMinor(123456, 'MYR'),
      issueDate: DateTime(2026, 9, 1),
      terms: PaymentTerms.dayOfMonth(20),
    );
    final snapshot = bill.draftSnapshot();
    final restored = Bill.restoreDraft(snapshot);
    expect(restored.draftSnapshot(), snapshot);
    expect(restored.status, BillStatus.draft);
    expect(restored.paymentIds, isEmpty);
    expect(() => bill.review().draftSnapshot(), throwsStateError);
    expect(
      () => Bill.restoreDraft({...snapshot, 'amountPaid': 123456}),
      throwsFormatException,
    );
  });
  test('bill monthly terms survive review and reject conflicting dates', () {
    Bill create({DateTime? dueDate}) => Bill.draft(
      id: EntityId.random(),
      vendorId: EntityId.random(),
      total: Money.fromMinor(100, 'MYR'),
      issueDate: DateTime(2024, 2, 1),
      dueDate: dueDate,
      terms: PaymentTerms.dayOfMonth(31),
    );
    final bill = create().review();
    expect(bill.dueDate, DateTime.utc(2024, 2, 29));
    expect(bill.terms.kind, PaymentTermKind.dayOfMonth);
    expect(() => create(dueDate: DateTime(2024, 3, 1)), throwsArgumentError);
  });
  test('bill dates retain calendar days and become overdue the next day', () {
    final bill = Bill.draft(
      id: EntityId.random(),
      vendorId: EntityId.random(),
      total: Money.fromMinor(100, 'MYR'),
      issueDate: DateTime(2026, 9, 1, 23),
      dueDate: DateTime(2026, 9, 13, 1),
    ).review();
    expect(bill.issueDate, DateTime.utc(2026, 9, 1));
    expect(bill.dueDate, DateTime.utc(2026, 9, 13));
    expect(
      bill.markOverdue(asOf: DateTime(2026, 9, 13, 23, 59)).status,
      BillStatus.open,
    );
    expect(
      bill.markOverdue(asOf: DateTime(2026, 9, 14)).status,
      BillStatus.overdue,
    );
  });
  test('reviews a vendor bill and applies a partial Pay Bills payment', () {
    final bill = Bill.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc101'),
      vendorId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc102'),
      total: Money.fromMinor(1500, 'USD'),
      issueDate: DateTime.utc(2026, 8, 30),
      dueDate: DateTime.utc(2026, 9, 29),
    );
    final paymentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc103');

    final open = bill.review();
    final partial = open.recordPayment(
      paymentId: paymentId,
      amount: Money.fromMinor(500, 'USD'),
      paidAt: DateTime.utc(2026, 8, 31, 10),
    );

    expect(bill.status, BillStatus.draft);
    expect(open.status, BillStatus.open);
    expect(partial.status, BillStatus.partiallyPaid);
    expect(partial.amountPaid, Money.fromMinor(500, 'USD'));
    expect(partial.remaining, Money.fromMinor(1000, 'USD'));
    expect(partial.paymentIds, contains(paymentId));
  });
}
