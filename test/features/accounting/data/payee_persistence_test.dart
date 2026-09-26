import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/payee.dart';

void main() {
  test(
    'same payee ID stays isolated and unselected mixed businesses are rejected',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      final first = EntityId.random();
      final second = EntityId.random();
      db.savePayee(
        first,
        const Payee(
          id: 'same-id',
          name: 'First Business Contact',
          type: PayeeType.supplier,
        ),
      );
      db.savePayee(
        second,
        const Payee(
          id: 'same-id',
          name: 'Second Business Contact',
          type: PayeeType.vendor,
        ),
      );
      expect(db.readPayees(first).single.name, 'First Business Contact');
      expect(db.readPayees(second).single.name, 'Second Business Contact');
      await expectLater(
        db.openWorkspace(
          newBusinessId: EntityId.random(),
          newDeviceId: EntityId.random(),
          newOwnerId: EntityId.random(),
          defaultCurrency: 'MYR',
        ),
        throwsStateError,
      );
    },
  );

  test('a contact-only database retains its original business on workspace creation', () async {
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    final business = EntityId.random();
    db.savePayee(
      business,
      const Payee(
        id: 'existing',
        name: 'Existing Contact',
        type: PayeeType.other,
      ),
    );
    final identity = await db.openWorkspace(
      newBusinessId: EntityId.random(),
      newDeviceId: EntityId.random(),
      newOwnerId: EntityId.random(),
      defaultCurrency: 'MYR',
    );
    expect(identity.businessId, business);
    expect(db.readPayees(identity.businessId).single.id, 'existing');
  });
  test(
    'payees survive restart and failed writes do not alter memory',
    () async {
      final dir = Directory.systemTemp.createTempSync('payee-persistence-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final payee = workspace.payees.add(
        name: 'New Supplier',
        type: PayeeType.supplier,
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(workspace.payees.byId(payee.id)!.name, 'New Supplier');
      workspace.payees.save(
        Payee(id: payee.id, name: 'Renamed Supplier', type: PayeeType.vendor),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(workspace.payees.all.single.name, 'Renamed Supplier');
      workspace.dispose();
      expect(
        () => workspace.payees.add(
          name: 'Must Not Appear',
          type: PayeeType.other,
        ),
        throwsStateError,
      );
      expect(workspace.payees.all, hasLength(1));
    },
  );

  test(
    'schema six upgrade preserves workspace identity and starts empty payees',
    () async {
      final dir = Directory.systemTemp.createTempSync('payee-migration-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final identity = workspace.identity.businessId;
      workspace.dispose();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      raw.execute('DROP TABLE payees');
      raw.execute('DROP TRIGGER reconciled_match_no_retraction');
      raw.execute('DROP TABLE bank_reconciliation_ledger_snapshots');
      raw.execute('DROP TABLE bank_reconciliation_allocations');
      raw.execute('DROP TABLE bank_reconciliation_reopenings');
      raw.execute('DROP TABLE bank_reconciliations');
      raw.execute('DROP TABLE bank_match_retractions');
      raw.execute('DROP TABLE bank_match_history');
      raw.execute('DROP TABLE bank_statement_matches');
      raw.execute('DROP TABLE bank_statement_imports');
      raw.execute('DROP TABLE payment_ledger_links');
      raw.execute('DROP TABLE payment_accounts');
      raw.execute('DROP TABLE claims');
      raw.execute('DROP TABLE payment_vouchers');
      raw.execute('DROP TABLE recurring_expense_templates');
      raw.execute('DROP TABLE recurring_expense_template_history');
      raw.execute('DROP TABLE recurring_expense_conversions');
      raw.execute('DROP TABLE recurring_expense_occurrences');
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
      raw.execute('PRAGMA user_version = 6');
      raw.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.identity.businessId, identity);
      expect(workspace.payees.all, isEmpty);
      workspace.payees.add(name: 'After Upgrade', type: PayeeType.other);
      expect(workspace.payees.all.single.name, 'After Upgrade');
    },
  );
}
