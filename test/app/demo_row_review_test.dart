import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audited Demo row fixtures have six records without posting extra movements', () async {
    final date = DateTime(2026, 9, 30);
    final base = await createDemoWorkspace(asOf: date);
    final review = await createDemoWorkspace(
      asOf: date,
      includeRowReview: true,
    );
    addTearDown(base.dispose);
    addTearDown(review.dispose);
    expect(review.customers(), hasLength(6));
    expect(review.invoiceDrafts().length + review.postedInvoices().length, 6);
    expect(review.creditDrafts(), hasLength(6));
    expect(
      review.creditDrafts().every(
        (d) =>
            review.database.invoiceCreditPosting(
              review.identity.businessId,
              d.id,
            ) ==
            null,
      ),
      isTrue,
    );
    expect(review.quotations(), hasLength(6));
    expect(review.catalogueItems, hasLength(6));
    expect(review.taxRates, hasLength(6));
    expect(
      review.database.recurringExpenseTemplates(review.identity.businessId),
      hasLength(6),
    );
    expect(
      review.database.documentSchedules(review.identity.businessId),
      hasLength(6),
    );
    expect(
      review.database
          .billDraftPage(businessId: review.identity.businessId)
          .total,
      6,
    );
    expect(
      review.database
          .vendorDirectory(businessId: review.identity.businessId)
          .total,
      greaterThanOrEqualTo(6),
    );
    expect(
      review.database
          .billDraftPage(businessId: review.identity.businessId)
          .records
          .first
          .attachments
          .length,
      greaterThanOrEqualTo(1),
    );
    final billPages = review.database.billDraftPage(
      businessId: review.identity.businessId,
      limit: 50,
    );
    expect(billPages.records.any((b) => b.attachments.length == 6), isTrue);
    for (final account in review.paymentAccounts.where(
      (a) => a.type == PaymentAccountType.bank,
    )) {
      final statements = review.database.bankStatements(
        review.identity.businessId,
        account.id,
      );
      expect(statements, hasLength(6));
      expect(
        statements.any(
          (s) =>
              review.database
                  .bankStatement(review.identity.businessId, s.id)!
                  .rows
                  .length ==
              6,
        ),
        isTrue,
      );
    }
    final before = await base.report(from: DateTime.utc(2026), through: date);
    final after = await review.report(from: DateTime.utc(2026), through: date);
    expect(after.assets, before.assets);
    expect(after.liabilities, before.liabilities);
    expect(after.periodProfit, before.periodProfit);
    expect(after.isBalanced, isTrue);
    expect((await review.journals()).length, (await base.journals()).length);
  });
}
