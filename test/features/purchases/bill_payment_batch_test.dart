import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/bill.dart';
import 'package:audyt/features/purchases/domain/bill_payment_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allocates one Pay Bills batch across multiple open bills', () {
    final billOne = Bill.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc111'),
      vendorId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc112'),
      total: Money.fromMinor(500, 'USD'),
      issueDate: DateTime.utc(2026, 8, 1),
      dueDate: DateTime.utc(2026, 8, 31),
    ).review();
    final billTwo = Bill.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc113'),
      vendorId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc114'),
      total: Money.fromMinor(700, 'USD'),
      issueDate: DateTime.utc(2026, 8, 2),
      dueDate: DateTime.utc(2026, 9, 1),
    ).review();
    final batchId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cc115');

    final batch = BillPaymentBatch.create(
      id: batchId,
      bills: [billOne, billTwo],
      allocations: {
        billOne.id: Money.fromMinor(500, 'USD'),
        billTwo.id: Money.fromMinor(700, 'USD'),
      },
      paidAt: DateTime.utc(2026, 8, 30, 12),
    );

    expect(batch.total, Money.fromMinor(1200, 'USD'));
    expect(batch.bills.every((bill) => bill.status == BillStatus.paid), isTrue);
    expect(batch.bills.expand((bill) => bill.paymentIds), contains(batchId));
  });
}
