import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

void main() {
  test('schema seven upgrade preserves identity and payment details survive restart', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-payment-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final business = workspace.identity.businessId;
    workspace.dispose();
    final raw = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(raw);
    removeExpenseRemovalSchema(raw);
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
    raw.execute('PRAGMA user_version = 7');
    raw.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(workspace.identity.businessId, business);
    final account = PaymentAccount.create(
      id: 'bank-1',
      name: 'Bank eBay',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
      accountNumber: '001234',
      bankId: 'bank-code',
      bankName: 'Test Bank',
    );
    workspace.savePaymentAccount(account);
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    final restored = workspace.paymentAccounts.single;
    expect(restored.id, account.id);
    expect(restored.name, 'Bank eBay');
    expect(restored.accountNumber, '001234');
    expect(restored.bankId, 'bank-code');
    expect(restored.bankName, 'Test Bank');
    expect(restored.currency.code, 'MYR');
    expect(restored.type, PaymentAccountType.bank);
    workspace.dispose();
    expect(() => workspace.savePaymentAccount(account), throwsStateError);
  });
}
