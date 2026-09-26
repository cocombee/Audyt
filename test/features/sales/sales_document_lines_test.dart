import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives estimate and invoice totals from item and category lines', () {
    final customerId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf301');
    final itemLine = SalesLineItem.item(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf302'),
      itemId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf303'),
      description: 'Implementation',
      quantity: SalesQuantity.fromInt(2),
      rate: Money.fromMinor(1000, 'USD'),
      discount: Money.fromMinor(100, 'USD'),
      tax: Money.fromMinor(190, 'USD'),
    );
    final categoryLine = SalesLineItem.category(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf304'),
      categoryId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf305'),
      description: 'Support',
      quantity: SalesQuantity.fromInt(1),
      rate: Money.fromMinor(500, 'USD'),
    );
    expect(
      () => Invoice.draft(
        id: EntityId.random(),
        customerId: customerId,
        lines: [itemLine, itemLine],
        issueDate: DateTime.utc(2026, 8, 30),
      ),
      throwsArgumentError,
    );
    expect(
      () => Estimate.draft(
        id: EntityId.random(),
        customerId: customerId,
        lines: [categoryLine, categoryLine],
        issueDate: DateTime.utc(2026, 8, 30),
        validUntil: DateTime.utc(2026, 9, 30),
      ),
      throwsArgumentError,
    );
    final lines = [itemLine, categoryLine];
    final issueDate = DateTime.utc(2026, 8, 30);

    final estimate = Estimate.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf306'),
      customerId: customerId,
      lines: lines,
      issueDate: issueDate,
      validUntil: DateTime.utc(2026, 9, 29),
      terms: PaymentTerms.netDays(30),
    );
    final invoice = Invoice.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf307'),
      customerId: customerId,
      lines: lines,
      issueDate: issueDate,
      terms: PaymentTerms.netDays(30),
    );

    expect(estimate.total, Money.fromMinor(2590, 'USD'));
    expect(invoice.total, Money.fromMinor(2590, 'USD'));
    expect(invoice.dueDate, DateTime.utc(2026, 9, 29));
    expect(invoice.terms.dueInDays, 30);
    expect(invoice.lines, hasLength(2));
  });
}
