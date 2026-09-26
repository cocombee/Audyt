import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/accounting/data/accounting_database.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test(
    'schema 23 upgrades without rewriting existing claim evidence',
    () async {
      final dir = Directory.systemTemp.createTempSync('claim-upgrade-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      final claim = ClaimStore.demo().all.first;
      w.claims.saveDraft(claim);
      w.dispose();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      final before = raw.select('SELECT payload FROM claims').single['payload'];
      raw.execute('DROP VIEW all_claim_postings');
      raw.execute('DROP TABLE claim_posting_reversals');
      raw.execute('DROP TABLE claim_posting_cycles');
      for (final table in [
        'claim_settlement_allocations',
        'claim_settlements',
        'claim_postings',
      ]) {
        raw.execute('DROP TABLE $table');
      }
      raw.execute('ALTER TABLE invoice_drafts DROP COLUMN archived_at');
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
      raw.execute('PRAGMA user_version=23');
      raw.dispose();
      w = await AccountingWorkspace.open(path);
      expect(w.claims.all.single.toJson(), claim.toJson());
      w.dispose();
      final upgraded = sqlite3.open(path);
      expect(
        upgraded.select('PRAGMA user_version').single['user_version'],
        LocalAccountingDatabase.schemaVersion,
      );
      expect(
        upgraded.select('SELECT payload FROM claims').single['payload'],
        before,
      );
      expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
      expect(upgraded.select('SELECT * FROM claim_postings'), isEmpty);
      expect(upgraded.select('SELECT * FROM claim_settlements'), isEmpty);
      upgraded.dispose();
    },
  );
}
