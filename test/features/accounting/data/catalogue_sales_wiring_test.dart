import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter_test/flutter_test.dart';

import 'quotation_persistence_test.dart' show quotationWorkspace;

void main() {
  test('sales commit maps items and preserves historical names through edits, conversion and reopen', () async {
    final root = Directory.systemTemp.createTempSync('audyt-catalogue-sales-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    final (originalWorkspace, customer, account) = await quotationWorkspace(
      path,
    );
    var workspace = originalWorkspace;
    addTearDown(() => workspace.dispose());
    final category = workspace.saveCatalogueCategory(
      CatalogueCategory(id: EntityId.random(), name: 'Video'),
    );
    final item = workspace.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: category.id,
        name: 'Corporate Video',
        type: CatalogueItemType.service,
        incomeAccountId: account.account.id,
        description: 'Introduction',
        taxRatePercent: '8',
      ),
    );
    final id = EntityId.random();
    final lineId = EntityId.random();
    final values = <String, Object?>{
      'Counterparty': customer.id.value,
      'Date': '01-09-2026',
      'Currency': 'MYR',
      'Payment Terms': 'Use Customer Default',
      'Tax Mode': 'Exclusive',
      'Document Number': 'CATALOGUE-INVOICE',
      '_lines': [
        {
          '_lineId': lineId.value,
          'Product / Service': item.id.value,
          'Account': 'untrusted-account',
          'Description': 'Edited description',
          'Amount': '1234567.89',
          'Discount': '0',
          'Tax Rate (%)': '8',
        },
      ],
    };
    Invoice parse(Map<String, Object?> input, {Invoice? existing}) =>
        invoiceFromForm(
          input,
          id: existing?.id ?? id,
          existing: existing,
          customer: customer,
          incomeAccountIds: {account.account.id.value},
          catalogueItems: workspace.catalogueItems,
          catalogueCategories: workspace.catalogueCategories,
          requireCatalogueItem: true,
        );
    final invoice = parse(values);
    expect(invoice.lines.single.categoryId, account.account.id);
    expect(invoice.lines.single.catalogue!.itemName, 'Corporate Video');
    expect(invoice.lines.single.catalogue!.categoryName, 'Video');
    expect(invoice.lines.single.description, 'Edited description');
    expect(invoice.total.minorUnits, 133333332);
    workspace.saveInvoiceDraft(
      invoice,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 1),
    );
    final quoteId = EntityId.random();
    final quote = Estimate.draft(
      id: quoteId,
      customerId: customer.id,
      lines: invoice.lines,
      issueDate: DateTime.utc(2026, 9, 1),
      validUntil: DateTime.utc(2026, 10, 1),
      terms: customer.paymentTerms,
      documentNumber: 'CATALOGUE-QUOTE',
      taxMode: 'Exclusive',
    );
    workspace.saveQuotationDraft(
      quote,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 1),
    );
    workspace.saveCatalogueCategory(
      CatalogueCategory(
        id: category.id,
        name: 'Renamed Category',
        revision: category.revision,
      ),
    );
    workspace.saveCatalogueItem(
      CatalogueItem(
        id: item.id,
        categoryId: category.id,
        name: 'Renamed Item',
        type: item.type,
        incomeAccountId: account.account.id,
        revision: item.revision,
        taxRatePercent: '8',
      ),
    );
    final edited = parse({
      ...invoiceFormValues(invoice),
      'Memo': 'New memo',
    }, existing: invoice);
    expect(
      edited.lines.single.catalogue!.toJson(),
      invoice.lines.single.catalogue!.toJson(),
    );
    workspace.saveInvoiceDraft(
      edited,
      expectedRevision: 1,
      savedAt: DateTime.utc(2026, 9, 2),
    );
    final editedQuote = parse({
      ...invoiceFormValues(quote.pricingSnapshot()),
      'Memo': 'New quotation memo',
    }, existing: quote.pricingSnapshot());
    expect(editedQuote.lines.single.catalogue!.itemName, 'Corporate Video');
    for (final (action, revision, day) in [
      (QuotationAction.shared, 1, 2),
      (QuotationAction.accepted, 2, 3),
    ]) {
      workspace.changeQuotationState(
        quoteId,
        expectedRevision: revision,
        action: action,
        changedAt: DateTime.utc(2026, 9, day),
      );
    }
    final convertedId = EntityId.random();
    workspace.convertQuotationToInvoice(
      quoteId,
      expectedRevision: 3,
      invoiceId: convertedId,
      documentNumber: 'CATALOGUE-CONVERTED',
      issueDate: DateTime.utc(2026, 9, 4),
      dueDate: DateTime.utc(2026, 10, 19),
      convertedAt: DateTime.utc(2026, 9, 4),
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    final saved = workspace
        .invoiceDrafts()
        .singleWhere((r) => r.invoice.id == id)
        .invoice;
    final converted = workspace
        .invoiceDrafts()
        .singleWhere((r) => r.invoice.id == convertedId)
        .invoice;
    expect(saved.memo, 'New memo');
    expect(saved.lines.single.catalogue!.itemName, 'Corporate Video');
    expect(
      converted.lines.single.catalogue!.toJson(),
      saved.lines.single.catalogue!.toJson(),
    );
    expect(converted.lines.single.sourceLineId, lineId);
    expect(workspace.catalogueCategories.single.name, 'Renamed Category');
    expect(workspace.catalogueItems.single.name, 'Renamed Item');
    // A copied snapshot cannot establish a new sales link after the master changed.
    final stale = Invoice.draft(
      id: EntityId.random(),
      customerId: customer.id,
      lines: invoice.lines,
      issueDate: invoice.issueDate,
      terms: invoice.terms,
      documentNumber: 'STALE-SNAPSHOT',
      taxMode: invoice.taxMode,
    );
    expect(
      () => workspace.saveInvoiceDraft(
        stale,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 9, 5),
      ),
      throwsStateError,
    );
    final before = workspace.invoiceDrafts().length;
    final foreign = await quotationWorkspace('${root.path}/other.sqlite');
    addTearDown(foreign.$1.dispose);
    final foreignCategory = foreign.$1.saveCatalogueCategory(
      CatalogueCategory(id: EntityId.random(), name: 'Foreign'),
    );
    final foreignItem = foreign.$1.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: foreignCategory.id,
        name: 'Foreign item',
        type: CatalogueItemType.service,
        incomeAccountId: foreign.$3.account.id,
      ),
    );
    final raw = Map<String, String>.from(
      (values['_lines'] as List).single as Map,
    );
    raw['Product / Service'] = foreignItem.id.value;
    expect(
      () => parse({
        ...values,
        '_lines': [raw],
      }),
      throwsStateError,
    );
    expect(workspace.invoiceDrafts().length, before);
  });
}
