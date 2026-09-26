import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'accepts an estimate and converts it to a source-linked invoice draft',
    () {
      final estimate = Estimate.draft(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cd101'),
        customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cd102'),
        total: Money.fromMinor(2400, 'USD'),
        issueDate: DateTime.utc(2026, 8, 30),
        validUntil: DateTime.utc(2026, 9, 29),
      );

      final accepted = estimate.send().accept();
      final conversion = accepted.convertToInvoice(
        invoiceId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cd103'),
        issueDate: DateTime.utc(2026, 8, 30),
        dueDate: DateTime.utc(2026, 9, 29),
      );

      expect(accepted.status, EstimateStatus.accepted);
      expect(conversion.estimate.status, EstimateStatus.converted);
      expect(conversion.invoice.status, InvoiceStatus.draft);
      expect(conversion.invoice.customerId, accepted.customerId);
      expect(conversion.invoice.total, accepted.total);
      expect(conversion.sourceEstimateId, accepted.id);
    },
  );
}
