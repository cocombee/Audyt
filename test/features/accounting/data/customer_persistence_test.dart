import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/core/money/money.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/customer.dart';

void main() {
  test(
    'customers survive restart, reject stale/foreign writes and migrate v20',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-customers-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final identity = workspace.identity;
      final customer = Customer.create(
        metadata: RecordMetadata.initial(
          recordId: EntityId.random(),
          businessId: identity.businessId,
          originDeviceId: identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 13),
        ),
        displayName: 'Fictional Customer',
        profileDetails: const CustomerProfileDetails(
          partyType: 'Business',
          identificationType: 'Business Registration',
          identificationNumber: 'TEST-ID',
          sstRegistrationNumber: 'TEST-SST',
          notes: 'Preserve these notes.',
          taxDetailsNeeded: true,
        ),
        contact: const CustomerContact(email: 'example@example.invalid'),
        billingAddress: const CustomerAddress(
          line1: 'Example Street',
          city: 'Test City',
          postalCode: '01000',
          countryCode: 'MY',
          stateOrProvince: 'Kedah',
        ),
        taxProfile: const CustomerTaxProfile(),
        currency: Currency.parse('MYR'),
        paymentTerms: PaymentTerms.netDays(30),
      );
      workspace.saveCustomer(customer);
      workspace.saveCustomer(
        customer,
      ); // Exact retry does not duplicate history.
      expect(workspace.customers(), hasLength(1));
      expect(
        workspace.customers().single.profileDetails.toJson(),
        customer.profileDetails.toJson(),
      );
      final changed = customer.revise(
        displayName: 'Revised Customer',
        updatedAt: DateTime.utc(2026, 9, 14),
      );
      workspace.saveCustomer(changed);
      expect(
        workspace.customers().single.profileDetails.toJson(),
        customer.profileDetails.toJson(),
      );
      expect(() => workspace.saveCustomer(customer), throwsStateError);
      expect(
        () => workspace.database.saveCustomer(
          changed,
          actorId: EntityId.random(),
        ),
        throwsStateError,
      );
      expect(workspace.database.readCustomers(EntityId.random()), isEmpty);
      final line = SalesLineItem.item(
        id: EntityId.random(),
        itemId: EntityId.random(),
        description: 'Example service',
        quantity: SalesQuantity.fromDecimal('1.5'),
        rate: Money.fromMinor(1000, 'MYR'),
      );
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: customer.id,
        lines: [line],
        issueDate: DateTime.utc(2026, 9, 1),
        terms: PaymentTerms.netDays(30),
      );
      final savedAt = DateTime.utc(2026, 9, 14);
      expect(
        workspace.saveInvoiceDraft(
          invoice,
          expectedRevision: 0,
          savedAt: savedAt,
        ),
        1,
      );
      expect(
        workspace.saveInvoiceDraft(
          invoice,
          expectedRevision: 0,
          savedAt: savedAt,
        ),
        1,
      );
      expect(
        () => workspace.saveInvoiceDraft(
          invoice.send(),
          expectedRevision: 1,
          savedAt: savedAt,
        ),
        throwsStateError,
      );
      expect(
        () => workspace.saveInvoiceDraft(
          invoice,
          expectedRevision: 5,
          savedAt: savedAt,
        ),
        throwsStateError,
      );
      expect(workspace.database.readInvoiceDrafts(EntityId.random()), isEmpty);
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      final savedInvoice = workspace.invoiceDrafts().single;
      expect(savedInvoice.revision, 1);
      expect(savedInvoice.invoice.total, Money.fromMinor(1500, 'MYR'));
      expect(savedInvoice.invoice.dueDate, DateTime.utc(2026, 10, 1));
      expect(savedInvoice.invoice.lines.single.id, line.id);

      final loaded = workspace.customers().single;
      expect(loaded.displayName, 'Revised Customer');
      expect(loaded.metadata.revision, 2);
      expect(loaded.billingAddress!.postalCode, '01000');
      expect(
        loaded.paymentTerms.dueDateFor(DateTime.utc(2026, 1, 1)),
        DateTime.utc(2026, 1, 31),
      );
      workspace.dispose();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      expect(raw.select('SELECT * FROM customer_history'), hasLength(2));
      expect(
        () => raw.execute('DELETE FROM customer_history'),
        throwsA(isA<SqliteException>()),
      );
      // Reconstruct the pre-change v20 schema and check the incremental migration.
      raw.execute('DROP TABLE claim_settlement_allocations');
      raw.execute('DROP TABLE claim_settlements');
      raw.execute('DROP TABLE claim_postings');
      raw.execute('DROP TABLE invoice_postings');
      raw.execute('DROP TABLE invoice_drafts');
      raw.execute('DROP TABLE invoice_draft_history');
      raw.execute('DROP TABLE customers');
      raw.execute('DROP TABLE customer_history');
      raw.execute('DROP TABLE invoice_credit_lines');
      raw.execute('DROP TABLE invoice_credit_postings');
      raw.execute('DROP TABLE invoice_credit_draft_history');
      raw.execute('DROP TABLE invoice_credit_drafts');
      raw.execute('DROP TABLE customer_receipt_allocations');
      raw.execute('DROP TABLE customer_receipts');
      raw.execute('DROP TABLE document_numbers');
      raw.execute('DROP TABLE IF EXISTS catalogue_items');
      raw.execute('DROP TABLE IF EXISTS catalogue_categories');
      raw.execute('DROP TABLE IF EXISTS generated_document_deliveries');
      raw.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
      raw.execute('DROP TABLE IF EXISTS recurring_document_template_history');
      raw.execute('DROP TABLE IF EXISTS recurring_document_templates');
      raw.execute('DROP TABLE IF EXISTS company_tax_rate_history');
      raw.execute('DROP TABLE IF EXISTS company_tax_rates');
      raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      raw.execute('DROP TABLE IF EXISTS tax_remittances');
      raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
      raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
      raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
      raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      raw.execute('PRAGMA user_version=20');
      raw.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(workspace.identity.businessId, identity.businessId);
      expect(workspace.customers(), isEmpty);
      workspace.saveCustomer(customer);
      expect(workspace.customers(), hasLength(1));
      workspace.dispose();
    },
  );
}
