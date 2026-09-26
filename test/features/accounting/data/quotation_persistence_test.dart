import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope;

Future<(AccountingWorkspace, Customer, StoredAccount)> quotationWorkspace(
  String path,
) async {
  final w = await AccountingWorkspace.open(path);
  await w.createAccount(
    code: '4000',
    name: 'Fictional sales',
    type: AccountType.income,
  );
  final account = (await w.accounts()).single;
  final c = Customer.create(
    metadata: RecordMetadata.initial(
      recordId: EntityId.random(),
      businessId: w.identity.businessId,
      originDeviceId: w.identity.deviceId,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    displayName: 'Fictional quotation customer',
    contact: const CustomerContact(),
    taxProfile: const CustomerTaxProfile(),
    currency: Currency.parse('MYR'),
    paymentTerms: PaymentTerms.netDays(45),
  );
  w.saveCustomer(c);
  return (w, c, account);
}

Estimate quotationDraft(
  Customer c,
  StoredAccount account, {
  EntityId? id,
  String memo = 'Quoted memo',
  String number = 'QT-000001',
  String reference = 'PO-QUOTE',
  String currency = 'MYR',
}) => Estimate.draft(
  id: id ?? EntityId.random(),
  customerId: c.id,
  documentNumber: number,
  issueDate: DateTime.utc(2026, 9, 1),
  validUntil: DateTime.utc(2026, 9, 30),
  terms: c.paymentTerms,
  classification: 'Quoted Class',
  location: 'Saved Branch',
  reference: reference,
  memo: memo,
  taxMode: 'Exclusive',
  attachments: [
    ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'quotation-evidence',
        batchId: 'quotation-batch',
        filename: 'quotation.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=',
          ),
        ),
      ),
    ),
  ],
  lines: [
    SalesLineItem.category(
      id: EntityId.random(),
      categoryId: account.account.id,
      description: 'Quoted fictional service',
      quantity: SalesQuantity.fromInt(3),
      rate: Money.fromMinor(5000, currency),
      discount: Money.fromMinor(500, currency),
      taxRatePercent: '6',
    ),
  ],
);

void main() {
  test('quotation history and atomic conversion survive archive restore and reopen without posting', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-quotation-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (source, customer, account) = await quotationWorkspace(
      '${dir.path}/source.sqlite',
    );
    final identity = source.identity;
    final quote = quotationDraft(customer, account);
    final db = source.database;
    int save(Estimate quote, int revision, DateTime at) =>
        db.saveQuotationDraft(
          businessId: identity.businessId,
          actorId: identity.ownerId,
          quotation: quote,
          expectedRevision: revision,
          savedAt: at,
        );
    expect(save(quote, 0, DateTime.utc(2026, 9, 1)), 1);
    expect(save(quote, 0, DateTime.utc(2026, 9, 1)), 1);
    final nextNumber = db.allocateDocumentNumber(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      recordId: EntityId.random(),
      documentType: 'quotation',
      allocatedAt: DateTime.utc(2026, 9, 1, 1),
    );
    expect(nextNumber, 'QT-000002');
    for (final (action, revision, day) in [
      (QuotationAction.shared, 1, 2),
      (QuotationAction.accepted, 2, 3),
    ]) {
      expect(
        db.changeQuotationState(
          businessId: identity.businessId,
          actorId: identity.ownerId,
          quotationId: quote.id,
          expectedRevision: revision,
          action: action,
          changedAt: DateTime.utc(2026, 9, day),
        ),
        revision + 1,
      );
    }
    final beforeConversion = tables(source);
    final invoiceId = EntityId.random();
    EntityId convert({String number = 'INV-QUOTATION', EntityId? id}) =>
        db.convertQuotationToInvoice(
          businessId: identity.businessId,
          actorId: identity.ownerId,
          quotationId: quote.id,
          expectedRevision: 3,
          invoiceId: id ?? invoiceId,
          documentNumber: number,
          issueDate: DateTime.utc(2026, 9, 4),
          dueDate: DateTime.utc(2026, 10, 19),
          convertedAt: DateTime.utc(2026, 9, 4, 1),
        );
    expect(convert(), invoiceId);
    final invoice = db.readInvoiceDrafts(identity.businessId).single.invoice;
    final linkedTables = tables(source);
    final disconnected = Invoice.fromDraftSnapshot({
      ...invoice.draftSnapshot(),
      'estimate': null,
    });
    expect(
      () => source.saveInvoiceDraft(
        disconnected,
        expectedRevision: 1,
        savedAt: DateTime.utc(2026, 9, 4, 2),
      ),
      throwsStateError,
    );
    final alteredLine = invoice.draftSnapshot();
    final rows = alteredLine['lines'] as List;
    rows.single['sourceLine'] = EntityId.random().value;
    expect(
      () => source.saveInvoiceDraft(
        Invoice.fromDraftSnapshot(alteredLine),
        expectedRevision: 1,
        savedAt: DateTime.utc(2026, 9, 4, 2),
      ),
      throwsStateError,
    );
    expect(tables(source), linkedTables);
    expect(invoice.total.minorUnits, 15370);
    expect(invoice.terms.toJson(), customer.paymentTerms.toJson());
    expect(invoice.issueDate, DateTime.utc(2026, 9, 4));
    expect(invoice.dueDate, DateTime.utc(2026, 10, 19));
    expect(invoice.sourceEstimateId, quote.id);
    expect(invoice.documentNumber, 'INV-QUOTATION');
    expect(invoice.reference, quote.reference);
    expect(invoice.memo, quote.memo);
    expect(invoice.classification, quote.classification);
    expect(invoice.location, quote.location);
    expect(invoice.taxMode, quote.taxMode);
    expect(
      invoice.attachments.map((a) => a.toJson()),
      quote.attachments.map((a) => a.toJson()),
    );
    expect(invoice.lines.single.id, isNot(quote.lines.single.id));
    expect(invoice.lines.single.sourceLineId, quote.lines.single.id);
    expect(invoice.lines.single.quantity, quote.lines.single.quantity);
    expect(invoice.lines.single.rate, quote.lines.single.rate);
    final converted = db.readQuotation(identity.businessId, quote.id)!;
    expect(converted.quotation.status, EstimateStatus.converted);
    expect(converted.quotation.validUntil, DateTime.utc(2026, 9, 30));
    expect(converted.revision, 4);
    expect(
      converted.customerSnapshot.metadata.revision,
      customer.metadata.revision,
    );
    final afterConversion = tables(source);
    expect(convert(), invoiceId);
    expect(tables(source), afterConversion);
    expect(() => convert(number: 'INV-OTHER'), throwsStateError);
    expect(() => convert(id: EntityId.random()), throwsStateError);
    expect(tables(source), afterConversion);
    for (final table in beforeConversion.keys.where(
      (key) => !{
        'quotation_drafts',
        'quotation_history',
        'invoice_drafts',
        'invoice_draft_history',
        'ledger_audit',
      }.contains(key),
    )) {
      expect(afterConversion[table], beforeConversion[table], reason: table);
    }
    expect((await source.journals()), isEmpty);
    final report = await source.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(report.revenue, BigInt.zero);
    expect(report.assets, BigInt.zero);
    final archive = db.exportDataArchive(
      identity.businessId,
      DateTime.utc(2026, 9, 5),
    );
    for (final defect in [
      'identity',
      'history',
      'signature',
      'originalInvoice',
    ]) {
      final data = body(archive);
      final quotes = data['tables']['quotation_drafts'];
      final row = (quotes['rows'] as List).single as List;
      int column(Map table, String key) =>
          (table['columns'] as List).indexOf(key);
      if (defect == 'identity') {
        final payload =
            jsonDecode(row[column(quotes, 'payload')] as String) as Map;
        payload['pricing']['id'] = EntityId.random().value;
        row[column(quotes, 'payload')] = jsonEncode(payload);
      } else if (defect == 'history') {
        (data['tables']['quotation_history']['rows'] as List).removeAt(0);
      } else if (defect == 'signature') {
        row[column(quotes, 'conversion_signature')] = 'damaged';
      } else {
        final table = data['tables']['invoice_draft_history'] as Map;
        final invoiceRow = (table['rows'] as List).single as List;
        final payload =
            jsonDecode(invoiceRow[column(table, 'payload')] as String) as Map;
        payload['memo'] = 'Does not match the original quotation';
        invoiceRow[column(table, 'payload')] = jsonEncode(payload);
      }
      final target = LocalAccountingDatabase.inMemory();
      expect(
        () => target.restoreDataArchive(envelope(data)),
        throwsFormatException,
        reason: defect,
      );
      // The rejected transaction leaves the same destination usable and empty.
      target.restoreDataArchive(archive);
      expect(target.readQuotation(identity.businessId, quote.id)!.revision, 4);
      target.close();
    }
    final metadataExpected = tables(source);
    source.dispose();
    final sourceHash = sha256.convert(
      File('${dir.path}/source.sqlite').readAsBytesSync(),
    );
    var restored = await AccountingWorkspace.emptyRestore(
      '${dir.path}/restored.sqlite',
      archive,
    );
    expect(tables(restored), metadataExpected);
    final recovered = restored.database.readQuotation(
      identity.businessId,
      quote.id,
    )!;
    expect(
      recovered.quotation.attachments.single.originalSha256,
      quote.attachments.single.originalSha256,
    );
    expect(recovered.quotation.attachments.single.originalBytes, isEmpty);
    expect(recovered.quotation.terms.toJson(), customer.paymentTerms.toJson());
    expect(recovered.quotation.validUntil, quote.validUntil);
    expect(recovered.quotation.documentNumber, quote.documentNumber);
    expect(recovered.quotation.reference, quote.reference);
    expect(recovered.quotation.memo, quote.memo);
    expect(recovered.quotation.classification, quote.classification);
    expect(recovered.quotation.location, quote.location);
    expect(recovered.quotation.taxMode, quote.taxMode);
    expect(recovered.quotation.lines.single.id, quote.lines.single.id);
    expect(
      recovered.quotation.lines.single.quantity,
      quote.lines.single.quantity,
    );
    expect(recovered.quotation.lines.single.rate, quote.lines.single.rate);
    expect(recovered.quotation.convertedInvoiceId, invoiceId);
    restored.dispose();
    restored = await AccountingWorkspace.open('${dir.path}/restored.sqlite');
    expect(tables(restored), metadataExpected);
    expect(
      restored.database
          .readQuotation(identity.businessId, quote.id)!
          .quotation
          .convertedInvoiceId,
      invoiceId,
    );
    expect(
      sha256.convert(File('${dir.path}/source.sqlite').readAsBytesSync()),
      sourceHash,
    );
    restored.dispose();
  });

  test('stale/foreign commands and changed income accounts reject without partial conversion', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-quotation-reject-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (w, c, account) = await quotationWorkspace(
      '${dir.path}/source.sqlite',
    );
    addTearDown(w.dispose);
    final identity = w.identity;
    final quote = quotationDraft(c, account);
    final db = w.database;
    db.saveQuotationDraft(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotation: quote,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 1),
    );
    var before = tables(w);
    for (final (business, owner, revision) in [
      (identity.businessId, EntityId.random(), 1),
      (EntityId.random(), identity.ownerId, 1),
      (identity.businessId, identity.ownerId, 0),
    ]) {
      expect(
        () => db.changeQuotationState(
          businessId: business,
          actorId: owner,
          quotationId: quote.id,
          expectedRevision: revision,
          action: QuotationAction.shared,
          changedAt: DateTime.utc(2026, 9, 2),
        ),
        throwsStateError,
      );
      expect(tables(w), before);
    }
    expect(db.readQuotations(EntityId.random()), isEmpty);
    db.changeQuotationState(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotationId: quote.id,
      expectedRevision: 1,
      action: QuotationAction.shared,
      changedAt: DateTime.utc(2026, 9, 2),
    );
    db.changeQuotationState(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotationId: quote.id,
      expectedRevision: 2,
      action: QuotationAction.accepted,
      changedAt: DateTime.utc(2026, 9, 3),
    );
    await db.saveAccount(
      StoredAccount(
        account: Account.create(
          id: account.account.id,
          code: account.account.code,
          name: account.account.name,
          type: AccountType.income,
          status: AccountStatus.locked,
        ),
        metadata: account.metadata.nextRevision(
          updatedAt: account.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
    before = tables(w);
    expect(
      () => db.convertQuotationToInvoice(
        businessId: identity.businessId,
        actorId: identity.ownerId,
        quotationId: quote.id,
        expectedRevision: 3,
        invoiceId: EntityId.random(),
        documentNumber: 'INV-REJECTED',
        issueDate: DateTime.utc(2026, 9, 4),
        dueDate: DateTime.utc(2026, 10, 19),
        convertedAt: DateTime.utc(2026, 9, 4, 1),
      ),
      throwsStateError,
    );
    expect(tables(w), before);
    expect(db.readInvoiceDrafts(identity.businessId), isEmpty);
    expect(
      db.readQuotation(identity.businessId, quote.id)!.quotation.status,
      EstimateStatus.accepted,
    );
  });
  test('quotation pages use saved values, bounded records, literal search and civil expiry', () async {
    final root = Directory.systemTemp.createTempSync('audyt-quotation-pages-');
    addTearDown(() => root.deleteSync(recursive: true));
    final (w, customer, account) = await quotationWorkspace(
      '${root.path}/books.sqlite',
    );
    addTearDown(w.dispose);
    final quotes = <Estimate>[];
    for (var i = 0; i < 12; i++) {
      final quote = quotationDraft(
        customer,
        account,
        number: 'QT-PAGE-$i',
        reference: i == 0 ? 'PO-%_SPECIAL' : 'PO-OTHER',
        currency: i == 11 ? 'USD' : 'MYR',
      );
      quotes.add(quote);
      w.saveQuotationDraft(
        quote,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 9, 1, 0, 0, i),
      );
    }
    w.changeQuotationState(
      quotes.first.id,
      expectedRevision: 1,
      action: QuotationAction.shared,
      changedAt: DateTime.utc(2026, 9, 2),
    );
    final before = tables(w);
    final db = w.database, business = w.identity.businessId;
    final first = db.quotationPage(
      business,
      offset: 0,
      pageSize: 5,
      asOf: DateTime.utc(2026, 9, 30, 23, 59),
    );
    expect(first.total, 12);
    expect(first.records.map((r) => r.quotation.id), [
      quotes.first.id,
      ...quotes.reversed.take(4).map((q) => q.id),
    ]);
    expect(first.currencies, ['MYR', 'USD']);
    expect(() => first.records.clear(), throwsUnsupportedError);
    final next = db.quotationPage(
      business,
      offset: 5,
      pageSize: 5,
      asOf: DateTime.utc(2026, 9, 30),
    );
    expect(next.records.length, 5);
    expect(
      next.records
          .map((r) => r.quotation.id)
          .toSet()
          .intersection(first.records.map((r) => r.quotation.id).toSet()),
      isEmpty,
    );
    for (final query in ['%_', 'fictional QUOTATION customer', 'qt-page-0']) {
      final result = db.quotationPage(
        business,
        offset: 0,
        pageSize: 5,
        search: query,
        asOf: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, query.contains('customer') ? 12 : 1);
      expect(result.records.first.quotation.id, quotes.first.id);
    }
    final usd = db.quotationPage(
      business,
      offset: 0,
      pageSize: 5,
      currency: 'USD',
      asOf: DateTime.utc(2026, 9, 30),
    );
    expect(usd.records.single.quotation.id, quotes.last.id);
    final shared = db.quotationPage(
      business,
      offset: 0,
      pageSize: 5,
      status: EstimateStatus.sent,
      asOf: DateTime.utc(2026, 9, 30, 23, 59),
    );
    expect(shared.records.single.quotation.id, quotes.first.id);
    final expired = db.quotationPage(
      business,
      offset: 0,
      pageSize: 5,
      status: EstimateStatus.expired,
      asOf: DateTime.utc(2026, 10, 1),
    );
    expect(expired.records.single.quotation.id, quotes.first.id);
    expect(
      quotes.first
          .send()
          .expire(asOf: DateTime.utc(2026, 9, 30, 23, 59))
          .status,
      EstimateStatus.sent,
    );
    expect(quotes.first.pricingSnapshot().dueDate, DateTime.utc(2026, 10, 16));
    expect(
      db
          .quotationPage(
            EntityId.random(),
            offset: 0,
            pageSize: 5,
            asOf: DateTime.utc(2026),
          )
          .total,
      0,
    );
    expect(
      () => db.quotationPage(
        business,
        offset: -1,
        pageSize: 5,
        asOf: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
    expect(
      () => db.quotationPage(
        business,
        offset: 0,
        pageSize: 101,
        asOf: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
    expect(tables(w), before);
  });

  test('conversion rejects reused invoice identities/numbers and invalid dates atomically', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-quotation-collisions-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final (w, customer, account) = await quotationWorkspace(
      '${root.path}/books.sqlite',
    );
    addTearDown(w.dispose);
    final quote = quotationDraft(customer, account);
    w.saveQuotationDraft(
      quote,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 1),
    );
    w.changeQuotationState(
      quote.id,
      expectedRevision: 1,
      action: QuotationAction.shared,
      changedAt: DateTime.utc(2026, 9, 2),
    );
    w.changeQuotationState(
      quote.id,
      expectedRevision: 2,
      action: QuotationAction.accepted,
      changedAt: DateTime.utc(2026, 9, 3),
    );
    final priorId = EntityId.random();
    w.saveInvoiceDraft(
      Invoice.fromDraftSnapshot({
        ...quote.pricingSnapshot().draftSnapshot(),
        'id': priorId.value,
        'documentNumber': 'INV-EXISTING',
      }),
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 3, 1),
    );
    final before = tables(w);
    void convert({
      EntityId? id,
      String number = 'INV-NEW',
      int revision = 3,
      DateTime? issue,
      DateTime? due,
    }) => w.convertQuotationToInvoice(
      quote.id,
      expectedRevision: revision,
      invoiceId: id ?? EntityId.random(),
      documentNumber: number,
      issueDate: issue ?? DateTime.utc(2026, 9, 4),
      dueDate: due ?? DateTime.utc(2026, 10, 19),
      convertedAt: DateTime.utc(2026, 9, 4),
    );
    for (final command in <void Function()>[
      () => convert(number: 'INV-EXISTING'),
      () => convert(id: priorId),
      () => convert(id: quote.id),
      () => convert(revision: 2),
      () => convert(issue: DateTime.utc(2026, 8, 31)),
    ]) {
      expect(command, throwsStateError);
      expect(tables(w), before);
    }
    expect(() => convert(due: DateTime.utc(2026, 10, 20)), throwsArgumentError);
    expect(tables(w), before);
    expect(w.invoiceDrafts().single.invoice.id, priorId);
    expect(w.quotations().single.quotation.status, EstimateStatus.accepted);
    expect(await w.journals(), isEmpty);
  });
}
