import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversion preserves estimate and line-level source linkage', () {
    final estimateId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf401');
    final estimateLineId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf402',
    );
    final invoiceId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf403');
    final invoiceLineId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf404',
    );
    final estimate = Estimate.draft(
      id: estimateId,
      customerId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf405'),
      lines: [
        SalesLineItem.item(
          id: estimateLineId,
          itemId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf406'),
          description: 'Implementation',
          quantity: SalesQuantity.fromInt(1),
          rate: Money.fromMinor(2400, 'USD'),
        ),
      ],
      issueDate: DateTime.utc(2026, 8, 30),
      validUntil: DateTime.utc(2026, 9, 29),
    );

    final conversion = estimate.send().accept().convertToInvoice(
      invoiceId: invoiceId,
      invoiceLineIds: {estimateLineId: invoiceLineId},
      issueDate: DateTime.utc(2026, 8, 30),
      dueDate: DateTime.utc(2026, 9, 29),
    );

    expect(conversion.estimate.status, EstimateStatus.converted);
    expect(conversion.estimate.convertedInvoiceId, invoiceId);
    expect(conversion.invoice.sourceEstimateId, estimateId);
    expect(conversion.invoice.lines.single.id, invoiceLineId);
    expect(conversion.invoice.lines.single.sourceLineId, estimateLineId);
    expect(conversion.sourceEstimateId, estimateId);
  });
}
