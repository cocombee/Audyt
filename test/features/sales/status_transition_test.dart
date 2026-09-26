import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps estimate transitions explicit and reversible where allowed', () {
    final estimate = Estimate.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf501'),
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf502'),
      total: Money.fromMinor(1000, 'USD'),
      issueDate: DateTime.utc(2026, 8, 30),
      validUntil: DateTime.utc(2026, 9, 29),
    );

    final viewed = estimate.send().view();
    final declined = estimate.send().decline();
    final closed = viewed.close();
    final reopened = closed.reopen();
    final expired = estimate.send().expire(asOf: DateTime.utc(2026, 9, 30));

    expect(estimate.status, EstimateStatus.draft);
    expect(viewed.status, EstimateStatus.viewed);
    expect(declined.status, EstimateStatus.declined);
    expect(closed.status, EstimateStatus.closed);
    expect(reopened.status, EstimateStatus.sent);
    expect(expired.status, EstimateStatus.expired);
    expect(
      estimate.send().expire(asOf: DateTime.utc(2026, 9, 29)).status,
      EstimateStatus.sent,
    );
  });

  test(
    'keeps invoice viewed, disputed, voided, and written-off states explicit',
    () {
      final invoice = Invoice.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf503'),
        customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf504'),
        total: Money.fromMinor(1000, 'USD'),
        issueDate: DateTime.utc(2026, 8, 1),
        dueDate: DateTime.utc(2026, 8, 15),
      );

      final viewed = invoice.send().view();
      final disputed = viewed.dispute();
      final resolved = disputed.resolveDispute(asOf: DateTime.utc(2026, 8, 16));
      final voided = invoice.send().voidInvoice();
      final writtenOff = resolved.writeOff();

      expect(viewed.status, InvoiceStatus.viewed);
      expect(disputed.status, InvoiceStatus.disputed);
      expect(
        () => disputed.recordPayment(
          paymentId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf505'),
          amount: Money.fromMinor(100, 'USD'),
          paidAt: DateTime.utc(2026, 8, 10),
        ),
        throwsStateError,
      );
      expect(resolved.status, InvoiceStatus.overdue);
      expect(voided.status, InvoiceStatus.voided);
      expect(writtenOff.status, InvoiceStatus.writtenOff);
    },
  );
}
