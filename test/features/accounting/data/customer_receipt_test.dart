import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

void main() {
  test('customer receipts are atomic, partial and restart safe', () async {
    final dir = Directory.systemTemp.createTempSync('invoice-posting-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    await w.createAccount(
      code: '1100',
      name: 'Receivables',
      type: AccountType.asset,
    );
    await w.createAccount(
      code: '4000',
      name: 'Sales',
      type: AccountType.income,
    );
    final accounts = await w.accounts();
    final ar = accounts.firstWhere((a) => a.account.code == '1100').account.id;
    final sales = accounts
        .firstWhere((a) => a.account.code == '4000')
        .account
        .id;
    final c = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: EntityId.random(),
        businessId: w.identity.businessId,
        originDeviceId: w.identity.deviceId,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      displayName: 'Test Customer',
      contact: const CustomerContact(),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
    );
    w.saveCustomer(c);
    Invoice draft() => Invoice.draft(
      id: EntityId.random(),
      customerId: c.id,
      total: Money.fromMinor(10000, 'MYR'),
      issueDate: DateTime.utc(2026, 1, 1),
      terms: c.paymentTerms,
      reference: 'PO-001',
      memo: 'Retain the reviewed delivery note.',
      attachments: ClaimStore.demo().all.first.attachments,
    );
    final invoice = draft();
    final legacy = Map<String, dynamic>.from(invoice.draftSnapshot())
      ..remove('reference')
      ..remove('memo')
      ..remove('attachments');
    expect(Invoice.fromDraftSnapshot(legacy).draftSnapshot(), legacy);
    expect(
      () => Invoice.draft(
        id: EntityId.random(),
        customerId: c.id,
        total: invoice.total,
        issueDate: invoice.issueDate,
        attachments: [invoice.attachments.first, invoice.attachments.first],
      ),
      throwsArgumentError,
    );
    w.saveInvoiceDraft(
      invoice,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 1, 2),
    );
    final request = EntityId.random();
    EntityId post(
      Invoice i, {
      EntityId? requestId,
      String number = 'INV-001',
      int revision = 1,
      EntityId? income,
    }) => w.postInvoice(
      requestId: requestId ?? request,
      invoiceId: i.id,
      expectedRevision: revision,
      expectedCustomerRevision: 1,
      documentNumber: number,
      receivableAccountId: ar,
      incomeAccountId: income ?? sales,
      approvedAt: DateTime.utc(2026, 1, 3),
    );

    post(invoice);
    w.dispose();
    final oldSchema = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(oldSchema);
    removeExpenseRemovalSchema(oldSchema);
    final originalInvoice = oldSchema
        .select('SELECT payload FROM invoice_drafts')
        .single['payload'];
    oldSchema.execute('DROP TABLE invoice_credit_lines');
    oldSchema.execute('DROP TABLE invoice_credit_postings');
    oldSchema.execute('DROP TABLE invoice_credit_draft_history');
    oldSchema.execute('DROP TABLE invoice_credit_drafts');
    oldSchema.execute('DROP TABLE customer_receipt_allocations');
    oldSchema.execute('DROP TABLE customer_receipts');
    oldSchema.execute('DROP TABLE IF EXISTS catalogue_items');
    oldSchema.execute('DROP TABLE IF EXISTS catalogue_categories');
    oldSchema.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    oldSchema.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    oldSchema.execute(
      'DROP TABLE IF EXISTS recurring_document_template_history',
    );
    oldSchema.execute('DROP TABLE IF EXISTS recurring_document_templates');
    oldSchema.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    oldSchema.execute('DROP TABLE IF EXISTS company_tax_rates');
    oldSchema.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    oldSchema.execute('DROP TABLE IF EXISTS tax_remittances');
    oldSchema.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    oldSchema.execute('DROP TABLE IF EXISTS company_tax_agencies');
    oldSchema.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    oldSchema.execute('DROP VIEW IF EXISTS current_expense_intakes');
    oldSchema.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    oldSchema.execute('DROP TABLE IF EXISTS expense_revision_postings');
    oldSchema.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    oldSchema.execute('PRAGMA user_version=27');
    oldSchema.dispose();
    w = await AccountingWorkspace.open(path);
    final migrated = sqlite3.open(path);
    expect(
      migrated.select('PRAGMA user_version').single['user_version'],
      LocalAccountingDatabase.schemaVersion,
    );
    expect(
      migrated.select('SELECT payload FROM invoice_drafts').single['payload'],
      originalInvoice,
    );
    expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
    migrated.dispose();
    expect(w.postedInvoices().single.paidMinor, 0);

    await w.createAccount(code: '1000', name: 'Bank', type: AccountType.asset);
    final bank = (await w.accounts())
        .firstWhere((a) => a.account.code == '1000')
        .account
        .id;
    final receiptId = EntityId.random();
    EntityId receive({EntityId? request, int minor = 4000}) =>
        w.database.receiveInvoicePayment(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          requestId: request ?? receiptId,
          customerId: c.id,
          bankAccountId: bank,
          allocations: {invoice.id: Money.fromMinor(minor, 'MYR')},
          reference: 'BANK-1',
          receivedAt: DateTime.utc(2026, 1, 4),
          approvedAt: DateTime.utc(2026, 1, 10),
        );

    for (final scenario in ['owner', 'customer', 'bank', 'date', 'currency']) {
      expect(
        () => w.database.receiveInvoicePayment(
          businessId: w.identity.businessId,
          actorId: scenario == 'owner' ? EntityId.random() : w.identity.ownerId,
          requestId: EntityId.random(),
          customerId: scenario == 'customer' ? EntityId.random() : c.id,
          bankAccountId: scenario == 'bank' ? sales : bank,
          allocations: {
            invoice.id: Money.fromMinor(
              100,
              scenario == 'currency' ? 'USD' : 'MYR',
            ),
          },
          reference: 'BAD',
          receivedAt: scenario == 'date'
              ? DateTime.utc(2025, 12, 31)
              : DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
        reason: scenario,
      );
    }
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER fail_receipt_allocation BEFORE INSERT ON customer_receipt_allocations BEGIN SELECT RAISE(ABORT, 'injected allocation failure'); END",
    );
    expect(receive, throwsA(isA<SqliteException>()));
    expect(await w.journals(), hasLength(1));
    expect(w.postedInvoices().single.paidMinor, 0);
    expect(raw.select('SELECT * FROM customer_receipts'), isEmpty);
    expect(raw.select('SELECT * FROM customer_receipt_allocations'), isEmpty);
    raw.execute('DROP TRIGGER fail_receipt_allocation');
    raw.dispose();
    expect(receive(), receiptId);
    final receivedEntry = (await w.journals()).singleWhere(
      (r) => r.entry.id == receiptId,
    );
    expect(receivedEntry.entry.date, DateTime.utc(2026, 1, 4));
    expect(receivedEntry.metadata.updatedAt, DateTime.utc(2026, 1, 10));
    expect(receive(), receiptId);
    expect(await w.journals(), hasLength(2));
    expect(
      w.database
          .receivablesAsOf(w.identity.businessId, DateTime.utc(2026, 1, 3))
          .single
          .remaining
          .minorUnits,
      10000,
    );
    expect(
      w.database
          .receivablesAsOf(w.identity.businessId, DateTime.utc(2026, 1, 4))
          .single
          .remaining
          .minorUnits,
      6000,
    );
    expect(() => receive(minor: 5000), throwsStateError);
    expect(
      () => receive(request: EntityId.random(), minor: 6001),
      throwsStateError,
    );
    expect(await w.journals(), hasLength(2));
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(receive(), receiptId);
    receive(request: EntityId.random(), minor: 6000);
    expect(await w.journals(), hasLength(3));
    expect(
      () => receive(request: EntityId.random(), minor: 1),
      throwsStateError,
    );

    final second = draft();
    final third = draft();
    for (final item in [second, third]) {
      w.saveInvoiceDraft(
        item,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      post(
        item,
        requestId: EntityId.random(),
        number: item.id == second.id ? 'INV-SECOND' : 'INV-THIRD',
      );
    }
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'receipt-bank',
        name: 'Receipt Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'receipt-bank',
      bank,
    );
    final batchId = EntityId.random();
    final batch = {
      second.id: Money.fromMinor(3000, 'MYR'),
      third.id: Money.fromMinor(7000, 'MYR'),
    };
    final beforeRejected = (await w.journals()).length;
    for (final paymentId in ['missing-bank', 'receipt-bank']) {
      expect(
        () => w.database.receiveInvoicePayment(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          requestId: EntityId.random(),
          customerId: c.id,
          bankAccountId: paymentId == 'receipt-bank' ? ar : bank,
          allocations: batch,
          paymentAccountId: paymentId,
          reference: 'REJECT',
          receivedAt: DateTime.utc(2026, 1, 5),
        ),
        throwsStateError,
      );
    }
    expect((await w.journals()).length, beforeRejected);
    w.database.receiveInvoicePayment(
      businessId: w.identity.businessId,
      actorId: w.identity.ownerId,
      requestId: batchId,
      customerId: c.id,
      bankAccountId: bank,
      allocations: batch,
      paymentAccountId: 'receipt-bank',
      reference: 'BATCH-1',
      receivedAt: DateTime.utc(2026, 1, 5),
    );
    final batchJournal = (await w.journals())
        .singleWhere((r) => r.entry.id == batchId)
        .entry;
    expect(batchJournal.lines, hasLength(3));
    expect(
      w
          .postedInvoices()
          .singleWhere((r) => r.sourceDraft.id == second.id)
          .paidMinor,
      3000,
    );
    expect(
      w
          .postedInvoices()
          .singleWhere((r) => r.sourceDraft.id == third.id)
          .paidMinor,
      7000,
    );
    expect(
      w.database
          .invoiceReceipts(w.identity.businessId, third.id)
          .single
          .reference,
      'BATCH-1',
    );
    final history = w.database.customerReceiptHistory(w.identity.businessId);
    final savedBatch = history.singleWhere((r) => r.reference == 'BATCH-1');
    expect(savedBatch.total.minorUnits, 10000);
    expect(
      savedBatch.allocations.map((a) => a.amount.minorUnits),
      containsAll([3000, 7000]),
    );
    expect(w.database.customerReceiptHistory(EntityId.random()), isEmpty);
    w.dispose();
    // Reconstruct the immediately preceding schema with populated receipts.
    final version28 = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(version28);
    removeExpenseRemovalSchema(version28);
    final retainedReceipts = version28
        .select('SELECT * FROM customer_receipts')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final retainedAllocations = version28
        .select('SELECT * FROM customer_receipt_allocations')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    version28.execute('DROP TABLE invoice_credit_lines');
    version28.execute('DROP TABLE invoice_credit_postings');
    version28.execute('DROP TABLE invoice_credit_draft_history');
    version28.execute('DROP TABLE invoice_credit_drafts');
    version28.execute('DROP TABLE IF EXISTS catalogue_items');
    version28.execute('DROP TABLE IF EXISTS catalogue_categories');
    version28.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    version28.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    version28.execute(
      'DROP TABLE IF EXISTS recurring_document_template_history',
    );
    version28.execute('DROP TABLE IF EXISTS recurring_document_templates');
    version28.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    version28.execute('DROP TABLE IF EXISTS company_tax_rates');
    version28.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    version28.execute('DROP TABLE IF EXISTS tax_remittances');
    version28.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    version28.execute('DROP TABLE IF EXISTS company_tax_agencies');
    version28.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    version28.execute('DROP VIEW IF EXISTS current_expense_intakes');
    version28.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    version28.execute('DROP TABLE IF EXISTS expense_revision_postings');
    version28.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    version28.execute('PRAGMA user_version=28');
    version28.dispose();
    w = await AccountingWorkspace.open(path);
    final upgraded29 = sqlite3.open(path);
    expect(
      upgraded29.select('PRAGMA user_version').single['user_version'],
      LocalAccountingDatabase.schemaVersion,
    );
    expect(
      upgraded29.select('SELECT * FROM customer_receipts'),
      retainedReceipts,
    );
    expect(
      upgraded29.select('SELECT * FROM customer_receipt_allocations'),
      retainedAllocations,
    );
    expect(upgraded29.select('SELECT * FROM invoice_credit_drafts'), isEmpty);
    expect(
      upgraded29.select('SELECT * FROM invoice_credit_draft_history'),
      isEmpty,
    );
    expect(upgraded29.select('PRAGMA foreign_key_check'), isEmpty);
    upgraded29.dispose();
    final beforeRetry = (await w.journals()).length;
    expect(
      w.database.receiveInvoicePayment(
        businessId: w.identity.businessId,
        actorId: w.identity.ownerId,
        requestId: batchId,
        customerId: c.id,
        bankAccountId: bank,
        allocations: batch,
        paymentAccountId: 'receipt-bank',
        reference: 'BATCH-1',
        receivedAt: DateTime.utc(2026, 1, 5),
      ),
      batchId,
    );
    expect((await w.journals()).length, beforeRetry);
    final restored = w.database.customerReceiptHistory(w.identity.businessId);
    final restoredBatch = restored.singleWhere((r) => r.reference == 'BATCH-1');
    expect(restoredBatch.total, savedBatch.total);
    expect(restoredBatch.allocations, savedBatch.allocations);
    expect(restoredBatch.date, savedBatch.date);
    expect(restoredBatch.customer, savedBatch.customer);
    final statement = w.database.customerStatement(
      w.identity.businessId,
      c.id,
      DateTime.utc(2026, 1, 5),
    );
    expect(statement.where((r) => r.reference == 'BATCH-1'), hasLength(1));
    expect(
      statement.singleWhere((r) => r.reference == 'BATCH-1').credit.minorUnits,
      10000,
    );
    expect(statement.last.balance.minorUnits, 10000);
    expect(
      w.database.customerStatement(
        w.identity.businessId,
        EntityId.random(),
        DateTime.utc(2026, 1, 5),
      ),
      isEmpty,
    );
    final earlyStatement = w.database.customerStatement(
      w.identity.businessId,
      c.id,
      DateTime.utc(2026, 1, 3),
    );
    expect(earlyStatement.every((r) => r.credit.isZero), isTrue);
    expect(
      w.database.customerStatement(
        EntityId.random(),
        c.id,
        DateTime.utc(2026, 1, 5),
      ),
      isEmpty,
    );
    final retainedAccounts = w.database.invoicePostingAccounts(
      w.identity.businessId,
      second.id,
    )!;
    expect(retainedAccounts.receivable, ar);
    expect(retainedAccounts.income, sales);
    expect(retainedAccounts.tax, isNull);
    expect(
      w.database.invoicePostingAccounts(EntityId.random(), second.id),
      isNull,
    );
    w.dispose();
  });
}
