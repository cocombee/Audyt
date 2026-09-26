import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

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
  test(
    'archive survives restart, preserves evidence and protects posted invoices',
    () async {
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
      final ar = accounts
          .firstWhere((a) => a.account.code == '1100')
          .account
          .id;
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

      final payload = invoice.draftSnapshot();
      w.dispose();
      final legacyDatabase = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(legacyDatabase);
      removeExpenseRemovalSchema(legacyDatabase);
      final storedBefore = legacyDatabase
          .select('SELECT payload FROM invoice_drafts')
          .single['payload'];
      legacyDatabase.execute(
        'ALTER TABLE invoice_drafts DROP COLUMN archived_at',
      );
      legacyDatabase.execute('DROP TABLE invoice_credit_lines');
      legacyDatabase.execute('DROP TABLE invoice_credit_postings');
      legacyDatabase.execute('DROP TABLE invoice_credit_draft_history');
      legacyDatabase.execute('DROP TABLE invoice_credit_drafts');
      legacyDatabase.execute('DROP TABLE customer_receipt_allocations');
      legacyDatabase.execute('DROP TABLE customer_receipts');
      legacyDatabase.execute('DROP TABLE document_numbers');
      legacyDatabase.execute('DROP TABLE IF EXISTS catalogue_items');
      legacyDatabase.execute('DROP TABLE IF EXISTS catalogue_categories');
      legacyDatabase.execute(
        'DROP TABLE IF EXISTS generated_document_deliveries',
      );
      for (final table in [
        'recurring_document_occurrences',
        'recurring_document_template_history',
        'recurring_document_templates',
        'company_tax_rate_history',
        'company_tax_rates',
      ]) {
        legacyDatabase.execute('DROP TABLE IF EXISTS $table');
      }
      legacyDatabase.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      legacyDatabase.execute('DROP TABLE IF EXISTS tax_remittances');
      legacyDatabase.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      legacyDatabase.execute('DROP TABLE IF EXISTS company_tax_agencies');
      legacyDatabase.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      legacyDatabase.execute('DROP VIEW IF EXISTS current_expense_intakes');
      legacyDatabase.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      legacyDatabase.execute('DROP TABLE IF EXISTS expense_revision_postings');
      legacyDatabase.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      legacyDatabase.execute('PRAGMA user_version=25');
      legacyDatabase.dispose();
      w = await AccountingWorkspace.open(path);
      expect(w.invoiceDrafts().single.invoice.draftSnapshot(), payload);
      final upgradedDatabase = sqlite3.open(path);
      expect(
        upgradedDatabase.select('PRAGMA user_version').single['user_version'],
        LocalAccountingDatabase.schemaVersion,
      );
      expect(
        upgradedDatabase
            .select('SELECT payload FROM invoice_drafts')
            .single['payload'],
        storedBefore,
      );
      expect(upgradedDatabase.select('PRAGMA foreign_key_check'), isEmpty);
      upgradedDatabase.dispose();

      final archivedAt = DateTime.utc(2026, 1, 3);
      int archive() => w.setInvoiceDraftArchived(
        invoiceId: invoice.id,
        expectedRevision: 1,
        archived: true,
        changedAt: archivedAt,
      );
      expect(archive(), 2);
      expect(archive(), 2);
      expect(w.invoiceDrafts(), isEmpty);
      expect(
        w.invoiceDrafts(archived: true).single.invoice.draftSnapshot(),
        payload,
      );
      expect(
        () => w.saveInvoiceDraft(
          invoice,
          expectedRevision: 2,
          savedAt: DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
      );
      expect(
        () => w.postInvoice(
          requestId: EntityId.random(),
          invoiceId: invoice.id,
          expectedRevision: 2,
          expectedCustomerRevision: 1,
          documentNumber: 'INV-ARCHIVE',
          receivableAccountId: ar,
          incomeAccountId: sales,
          approvedAt: DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
      );
      expect(
        () => w.database.setInvoiceDraftArchived(
          businessId: w.identity.businessId,
          actorId: EntityId.random(),
          invoiceId: invoice.id,
          expectedRevision: 2,
          archived: false,
          changedAt: DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
      );
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(w.invoiceDrafts(), isEmpty);
      expect(
        w.invoiceDrafts(archived: true).single.invoice.draftSnapshot(),
        payload,
      );
      expect(
        () => w.setInvoiceDraftArchived(
          invoiceId: invoice.id,
          expectedRevision: 1,
          archived: false,
          changedAt: DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
      );
      expect(
        w.setInvoiceDraftArchived(
          invoiceId: invoice.id,
          expectedRevision: 2,
          archived: false,
          changedAt: DateTime.utc(2026, 1, 4),
        ),
        3,
      );
      expect(w.invoiceDrafts(archived: true), isEmpty);
      expect(w.invoiceDrafts().single.invoice.draftSnapshot(), payload);
      w.postInvoice(
        requestId: EntityId.random(),
        invoiceId: invoice.id,
        expectedRevision: 3,
        expectedCustomerRevision: 1,
        documentNumber: 'INV-ARCHIVE',
        receivableAccountId: ar,
        incomeAccountId: sales,
        approvedAt: DateTime.utc(2026, 1, 5),
      );
      expect(
        () => w.setInvoiceDraftArchived(
          invoiceId: invoice.id,
          expectedRevision: 3,
          archived: true,
          changedAt: DateTime.utc(2026, 1, 6),
        ),
        throwsStateError,
      );
      expect(await w.journals(), hasLength(1));
      w.dispose();
    },
  );
}
