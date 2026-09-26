import 'dart:io';

import 'package:audyt/app/demo_company.dart' show demoReceipt;
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

Future<
  ({
    AccountingWorkspace w,
    String path,
    Invoice invoice,
    EntityId creditId,
    EntityId receivable,
    EntityId income,
    EntityId tax,
    EntityId liability,
    EntityId bank,
    Customer customer,
  })
>
creditPostingFixture({int paidMinor = 0, bool evidence = true}) async {
  final root = Directory.systemTemp.createTempSync('credit-posting-');
  addTearDown(() => root.deleteSync(recursive: true));
  final path = '${root.path}/books.sqlite';
  final w = await AccountingWorkspace.open(path);
  addTearDown(w.dispose);
  for (final entry in [
    ('1100', 'Receivables', AccountType.asset),
    ('4000', 'Fictional Sales', AccountType.income),
    ('2200', 'Fictional Tax Payable', AccountType.liability),
    ('2300', 'Customer Credits', AccountType.liability),
    ('1000', 'Fictional Bank', AccountType.asset),
  ]) {
    await w.createAccount(code: entry.$1, name: entry.$2, type: entry.$3);
  }
  final accounts = await w.accounts();
  EntityId account(String code) =>
      accounts.singleWhere((a) => a.account.code == code).account.id;
  final customer = Customer.create(
    metadata: RecordMetadata.initial(
      recordId: EntityId.random(),
      businessId: w.identity.businessId,
      originDeviceId: w.identity.deviceId,
      createdAt: DateTime.utc(2026, 9, 1),
    ),
    displayName: 'Fictional Credit Customer',
    contact: const CustomerContact(),
    taxProfile: const CustomerTaxProfile(),
    currency: Currency.parse('MYR'),
    paymentTerms: PaymentTerms.netDays(30),
  );
  w.saveCustomer(customer);
  final lineId = EntityId.random();
  final invoice = Invoice.draft(
    id: EntityId.random(),
    customerId: customer.id,
    documentNumber: 'CREDIT-SOURCE-1',
    issueDate: DateTime.utc(2026, 9, 1),
    classification: 'Saved Class',
    location: 'Saved Location',
    taxMode: 'Exclusive',
    lines: [
      SalesLineItem.category(
        id: lineId,
        categoryId: account('4000'),
        description: 'Fictional goods',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromMinor(10000, 'MYR'),
        taxRatePercent: '8',
      ),
    ],
  );
  w.saveInvoiceDraft(
    invoice,
    expectedRevision: 0,
    savedAt: DateTime.utc(2026, 9, 2),
  );
  w.postInvoice(
    requestId: EntityId.random(),
    invoiceId: invoice.id,
    expectedRevision: 1,
    expectedCustomerRevision: customer.metadata.revision,
    documentNumber: invoice.documentNumber,
    receivableAccountId: account('1100'),
    incomeAccountId: account('4000'),
    taxAccountId: account('2200'),
    approvedAt: DateTime.utc(2026, 9, 3),
  );
  if (paidMinor > 0) {
    w.receiveInvoicePayment(
      requestId: EntityId.random(),
      customerId: customer.id,
      bankAccountId: account('1000'),
      allocations: {invoice.id: Money.fromMinor(paidMinor, 'MYR')},
      reference: 'Fictional receipt',
      receivedAt: DateTime.utc(2026, 9, 4),
    );
  }
  final creditId = EntityId.random();
  w.saveInvoiceCreditDraft(
    draftId: creditId,
    invoiceId: invoice.id,
    lineCredits: {lineId: Money.fromMinor(5400, 'MYR')},
    reason: 'Fictional returned goods',
    creditDate: DateTime.utc(2026, 9, 6),
    expectedRevision: 0,
    savedAt: DateTime.utc(2026, 9, 6),
    attachments: evidence
        ? [demoReceipt('CREDIT-SUPPORT', DateTime.utc(2026, 9, 6), 5400)]
        : [],
  );
  return (
    w: w,
    path: path,
    invoice: invoice,
    creditId: creditId,
    receivable: account('1100'),
    income: account('4000'),
    tax: account('2200'),
    liability: account('2300'),
    bank: account('1000'),
    customer: customer,
  );
}

Future<int> creditLedgerBalance(
  AccountingWorkspace w,
  EntityId account,
) async => (await w.journals())
    .where((j) => j.entry.state == JournalEntryState.posted)
    .expand((j) => j.entry.lines)
    .where((l) => l.accountId == account)
    .fold<int>(
      0,
      (sum, l) =>
          sum + (l.isDebit ? l.amount.minorUnits : -l.amount.minorUnits),
    );
