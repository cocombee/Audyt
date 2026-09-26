import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';

/// Isolated fictional books, exercising the real invoice posting boundary.
Future<SalesReportFixture> salesReportFixture({
  String path = ':memory:',
  bool seedInvoices = true,
}) async {
  final workspace = await AccountingWorkspace.open(path);
  for (final entry in [
    ('1100', 'Fictional Receivables', AccountType.asset),
    ('4000', 'Fictional Sales', AccountType.income),
    ('2200', 'Fictional Tax Payable', AccountType.liability),
  ]) {
    await workspace.createAccount(
      code: entry.$1,
      name: entry.$2,
      type: entry.$3,
    );
  }
  final accounts = await workspace.accounts();
  EntityId account(String code) =>
      accounts.singleWhere((a) => a.account.code == code).account.id;
  final customer = Customer.create(
    metadata: RecordMetadata.initial(
      recordId: EntityId.random(),
      businessId: workspace.identity.businessId,
      originDeviceId: workspace.identity.deviceId,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    displayName: 'Fictional Sales Review Customer',
    contact: const CustomerContact(),
    taxProfile: const CustomerTaxProfile(),
    currency: Currency.parse('MYR'),
    paymentTerms: PaymentTerms.netDays(30),
  );
  workspace.saveCustomer(customer);
  final fixture = SalesReportFixture(
    workspace,
    customer,
    account('1100'),
    account('4000'),
    account('2200'),
  );
  for (final entry in [
    ('Video', 'Corporate Video', 1200000),
    ('Video', 'Event Video', 450000),
    ('Photography', 'Event Photography', 600000),
  ]) {
    final category =
        workspace.catalogueCategories
            .where((category) => category.name == entry.$1)
            .firstOrNull ??
        workspace.saveCatalogueCategory(
          CatalogueCategory(id: EntityId.random(), name: entry.$1),
        );
    final item = workspace.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: category.id,
        name: entry.$2,
        type: CatalogueItemType.service,
        incomeAccountId: fixture.income,
      ),
    );
    if (!seedInvoices) continue;
    fixture.invoices.add(
      fixture.addInvoice(
        item: item,
        category: category,
        minor: entry.$3,
        date: DateTime.utc(2026, 9, 1),
      ),
    );
  }
  return fixture;
}

class SalesReportFixture {
  SalesReportFixture(
    this.workspace,
    this.customer,
    this.receivable,
    this.income,
    this.tax,
  );
  final AccountingWorkspace workspace;
  final Customer customer;
  final EntityId receivable, income, tax;
  final List<Invoice> invoices = [];

  Invoice addInvoice({
    required CatalogueItem item,
    required CatalogueCategory category,
    required int minor,
    required DateTime date,
    int discount = 0,
    String taxRate = '0',
    bool inclusive = false,
    bool post = true,
  }) {
    final invoice = Invoice.draft(
      id: EntityId.random(),
      customerId: customer.id,
      documentNumber: 'FICTIONAL-${EntityId.random().value}',
      issueDate: date,
      taxMode: inclusive ? 'Inclusive' : 'Exclusive',
      lines: [
        SalesLineItem.category(
          id: EntityId.random(),
          categoryId: income,
          description: item.name,
          quantity: SalesQuantity.fromInt(1),
          rate: Money.fromMinor(minor, 'MYR'),
          discount: Money.fromMinor(discount, 'MYR'),
          taxRatePercent: taxRate,
          taxInclusive: inclusive,
          catalogue: item.snapshot(category),
        ),
      ],
    );
    workspace.saveInvoiceDraft(
      invoice,
      expectedRevision: 0,
      savedAt: date.add(const Duration(days: 1)),
    );
    if (post) {
      workspace.postInvoice(
        requestId: EntityId.random(),
        invoiceId: invoice.id,
        expectedRevision: 1,
        expectedCustomerRevision: customer.metadata.revision,
        documentNumber: invoice.documentNumber,
        receivableAccountId: receivable,
        incomeAccountId: income,
        taxAccountId: invoice.lines.single.tax.minorUnits == 0 ? null : tax,
        approvedAt: date.add(const Duration(days: 2)),
      );
    }
    return invoice;
  }
}
