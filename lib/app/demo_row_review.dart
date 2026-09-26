import '../features/accounting/domain/company_tax_rate.dart';
import '../features/accounting/domain/account.dart';
import '../features/accounting/domain/recurrence_rule.dart';
import '../features/accounting/domain/recurring_expense_template.dart';
import '../features/accounting/domain/expense_draft.dart';
import '../features/accounting/domain/recurring_document_template.dart';
import '../features/accounting/data/accounting_database.dart';

import 'dart:convert';
import 'dart:typed_data';

import '../core/ids/entity_id.dart';
import '../core/money/currency.dart';
import '../core/money/money.dart';
import '../core/storage/record_metadata.dart';
import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/domain/payment_account.dart';
import '../features/accounting/domain/bank_statement_import.dart';
import '../features/accounting/domain/customer.dart';
import '../features/accounting/domain/payee.dart';
import '../features/purchases/domain/purchase_bill_draft.dart';
import '../features/purchases/domain/vendor.dart';
import '../features/sales/domain/estimate.dart';
import '../features/sales/domain/invoice.dart';
import '../features/sales/domain/product_catalogue.dart';
import '../features/sales/domain/sales_line_item.dart';
import '../core/documents/receipt_document.dart';

/// Called only while creating the isolated Demo Company. These review drafts
/// and unmatched imports never post journals or touch a live company/file.
Future<void> seedDemoRowReview(
  AccountingWorkspace w,
  DateTime date, {
  required ReceiptAttachment Function(String, DateTime, int) receiptFactory,
}) async {
  final accounts = {
    for (final r in await w.accounts()) r.account.code: r.account.id,
  };
  RecordMetadata metadata() => RecordMetadata.initial(
    recordId: EntityId.random(),
    businessId: w.identity.businessId,
    originDeviceId: w.identity.deviceId,
    createdAt: DateTime.now().toUtc(),
  );
  final customers = [...w.customers()];
  for (final name in [
    'Cedar Events',
    'Harbour Studio',
    'Orchard Media',
  ].take(6 - customers.length)) {
    final customer = Customer.create(
      metadata: metadata(),
      displayName: name,
      contact: CustomerContact(
        email: '${name.toLowerCase().replaceAll(' ', '.')}@example.test',
      ),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
    );
    w.saveCustomer(customer);
    customers.add(customer);
  }
  final categories = [
    for (final name in ['Video', 'Photography'])
      w.saveCatalogueCategory(
        CatalogueCategory(id: EntityId.random(), name: name),
      ),
  ];
  final items = <CatalogueItem>[];
  for (final (i, name) in [
    'Corporate Video',
    'Event Video',
    'Product Photography',
    'Portrait Photography',
    'Editing Service',
    'Location Coverage',
  ].indexed) {
    items.add(
      w.saveCatalogueItem(
        CatalogueItem(
          id: EntityId.random(),
          categoryId: categories[i % 2].id,
          name: name,
          type: CatalogueItemType.service,
          incomeAccountId: accounts['4000']!,
          description: 'Fictional $name for row design review',
        ),
      ),
    );
  }
  SalesLineItem line(int i, {bool purchase = false}) => SalesLineItem.category(
    id: EntityId.random(),
    categoryId: accounts[purchase ? '6000' : '4000']!,
    description: items[i % items.length].description,
    quantity: SalesQuantity.fromInt(1),
    rate: Money.fromMinor(10000 + i * 1250, 'MYR'),
    taxRatePercent: '0',
    catalogue: purchase
        ? null
        : items[i % items.length].snapshot(categories[i % 2]),
  );
  for (var i = 3; i < 6; i++) {
    w.saveInvoiceDraft(
      Invoice.draft(
        id: EntityId.random(),
        customerId: customers[i].id,
        documentNumber: 'DEMO-INV-00${i + 1}',
        issueDate: date,
        terms: customers[i].paymentTerms,
        lines: [line(i)],
        memo: 'Fictional draft for row review',
      ),
      expectedRevision: 0,
      savedAt: DateTime.now().toUtc(),
    );
  }
  final creditSource = w.postedInvoices().first.sourceDraft;
  for (var i = w.creditDrafts().length; i < 6; i++) {
    w.saveInvoiceCreditDraft(
      draftId: EntityId.random(),
      invoiceId: creditSource.id,
      lineCredits: {creditSource.lines.first.id: Money.fromMinor(10000, 'MYR')},
      reason: 'Fictional credit ${i + 1} for row review',
      creditDate: date,
      expectedRevision: 0,
      savedAt: DateTime.now().toUtc(),
      attachments: [receiptFactory('DEMO-CREDIT-${i + 1}', date, 10000)],
    );
  }
  for (var i = 0; i < 6; i++) {
    w.saveQuotationDraft(
      Estimate.draft(
        id: EntityId.random(),
        customerId: customers[i].id,
        documentNumber: 'DEMO-QT-00${i + 1}',
        issueDate: date,
        validUntil: date.add(const Duration(days: 30)),
        terms: customers[i].paymentTerms,
        lines: [line(i)],
        taxMode: 'Out Of Scope',
        memo: 'Fictional quotation for row review',
      ),
      expectedRevision: 0,
      savedAt: DateTime.now().toUtc(),
    );
    final vendorMetadata = metadata();
    final vendor = Vendor(
      metadata: vendorMetadata,
      payeeId: vendorMetadata.recordId.value,
      name: [
        'Cedar Supplies',
        'Harbour Printing',
        'Orchard Rentals',
        'River Sound',
        'Meadow Lighting',
        'Summit Equipment',
      ][i],
      type: PayeeType.supplier,
      details: VendorDetails(
        values: {
          'email': 'supplier${i + 1}@example.test',
          'countryCode': 'MY',
          'countryName': 'Malaysia',
        },
      ),
      currency: Currency.parse('MYR'),
      terms: PaymentTerms.netDays(30),
    );
    w.saveVendor(vendor, expectedRevision: 0);
    final billId = EntityId.random();
    final number = w.database.allocateDocumentNumber(
      businessId: w.identity.businessId,
      actorId: w.identity.ownerId,
      recordId: billId,
      documentType: 'bill',
      allocatedAt: DateTime.now().toUtc(),
    );
    w.saveBillDraft(
      PurchaseBillDraft(
        metadata: RecordMetadata.initial(
          recordId: billId,
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.now().toUtc(),
        ),
        vendorSnapshot: vendor,
        documentNumber: number,
        issueDate: date,
        dueDate: date.add(const Duration(days: 30)),
        terms: vendor.terms,
        lines: [line(i, purchase: true)],
        taxMode: 'Out Of Scope',
        memo: 'Fictional unposted purchase for row review',
        attachments: [
          for (var j = 0; j < (i == 0 ? 6 : 1); j++)
            receiptFactory(
              'DEMO-BILL-${i + 1}-Receipt-${j + 1}',
              date,
              10000 + i * 1250,
            ),
        ],
      ),
      expectedRevision: 0,
    );
  }
  for (final (i, summary) in (await w.expenses()).take(6).indexed) {
    final record = (await w.expense(summary.id))!;
    final defaults = RecordExpenseDraft.fromJson({
      ...record.draft.toJson(),
      'attachments': <Object>[],
      'attachmentName': null,
      'reviewSnapshots': <Object>[],
    });
    w.database.saveRecurringExpenseTemplate(
      w.identity.businessId,
      RecurringExpenseTemplate(
        id: EntityId.random().value,
        revision: 1,
        sourceExpenseId: summary.id.value,
        defaults: defaults,
        schedule: RecurrenceRule(
          startsOn: date.add(const Duration(days: 1)),
          unit: RecurrenceUnit.months,
          occurrenceCount: 12,
        ),
        paused: i == 5,
      ),
    );
  }
  final invoiceSources = w.invoiceDrafts().take(3).toList();
  final billSources = w.database
      .billDraftPage(businessId: w.identity.businessId, limit: 6)
      .records
      .take(3)
      .toList();
  for (var i = 0; i < 6; i++) {
    final invoice = i < 3;
    w.saveDocumentSchedule(
      id: EntityId.random().value,
      name: '${invoice ? 'Monthly Service' : 'Monthly Purchase'} ${i % 3 + 1}',
      kind: invoice
          ? RecurringDocumentKind.invoice
          : RecurringDocumentKind.bill,
      sourceId: invoice ? invoiceSources[i].invoice.id : billSources[i - 3].id,
      sourceRevision: invoice
          ? invoiceSources[i].revision
          : billSources[i - 3].metadata.revision,
      expectedRevision: 0,
      schedule: RecurrenceRule(
        startsOn: date.add(const Duration(days: 1)),
        unit: RecurrenceUnit.months,
        occurrenceCount: 12,
      ),
      paused: i == 5,
    );
  }
  await w.createAccount(
    code: '2200',
    name: 'Demo Tax Payable',
    type: AccountType.liability,
  );
  final taxAccount = (await w.accounts())
      .singleWhere((r) => r.account.code == '2200')
      .account;
  // Isolated Malaysian examples entered through the same saved tax-code owner.
  // Withholding needs a deduction owner; it must not become an added charge.
  for (final (name, percent) in [
    ('Sales Tax', '5'),
    ('SST', '10'),
    ('Service Tax (F&B)', '6'),
    ('Service Tax', '8'),
    ('Exempt', '0'),
    ('Out Of Scope', '0'),
  ]) {
    w.saveTaxRate(
      CompanyTaxRate(
        id: EntityId.random(),
        name: name,
        percent: percent,
        effectiveFrom: DateTime(date.year),
        application: TaxApplication.both,
        accountId: taxAccount.id,
      ),
    );
  }
  // Existing Expenses, Claims, Vouchers and Accounts already exceed six.
  // Give each bank an independent six-import example, each with six source rows.
  for (final account in w.paymentAccounts.where(
    (a) => a.type == PaymentAccountType.bank,
  )) {
    final count = w.database
        .bankStatements(w.identity.businessId, account.id)
        .length;
    for (var i = count; i < 6; i++) {
      final csv =
          'Date,Description,Amount,Reference\n${[for (var j = 0; j < 6; j++) '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')},Fictional review ${i + 1} row ${j + 1},${j + 1}.00,DEMO-${i + 1}-${j + 1}'].join('\n')}\n';
      w.database.importBankStatement(
        id: EntityId.random(),
        businessId: w.identity.businessId,
        paymentAccountId: account.id,
        importedAt: DateTime.now(),
        statement: BankStatementImport.csv(
          filename: '${account.name} Review ${i + 1}.csv',
          currency: account.currency.code,
          bytes: Uint8List.fromList(utf8.encode(csv)),
        ),
      );
    }
  }
}
