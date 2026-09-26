import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/closing_proposal.dart';

import 'ledger_report_test.dart' show id, metadata;

void main() {
  test(
    'schema five ordinary journal survives closing-column migration',
    () async {
      final dir = Directory.systemTemp.createTempSync('closing-migration-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var db = LocalAccountingDatabase.open(path);
      final at = DateTime.utc(2026, 9, 30);
      final entry = JournalEntry.draft(
        id: id(20),
        date: at,
        memo: 'Preserve historical draft',
        lines: [],
      );
      await db.save(
        StoredJournalEntry(entry: entry, metadata: metadata(20, at)),
      );
      db.close();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      raw.execute('ALTER TABLE journal_entries DROP COLUMN closing_equity_id');
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
      raw.execute('PRAGMA user_version = 5');
      raw.dispose();
      db = LocalAccountingDatabase.open(path);
      addTearDown(db.close);
      final restored = (await db.getById(id(20)))!;
      expect(restored.entry.isClosing, isFalse);
      expect(restored.entry.memo, 'Preserve historical draft');
      expect(restored.metadata.revision, 1);
      expect(restored.entry.date, at);
    },
  );

  test(
    'closing and its reversal survive restart without erasing period profit',
    () async {
      final dir = Directory.systemTemp.createTempSync('closing-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var db = LocalAccountingDatabase.open(path);
      final at = DateTime.utc(2026, 9, 30);
      await db.configureLedger(businessId: id(90), currencyCode: 'MYR');
      final types = [
        AccountType.asset,
        AccountType.equity,
        AccountType.income,
        AccountType.expense,
      ];
      for (var i = 0; i < types.length; i++) {
        await db.saveAccount(
          StoredAccount(
            account: Account.create(
              id: id(i + 1),
              code: '${i + 1}',
              name: 'Account',
              type: types[i],
            ),
            metadata: metadata(i + 1, at),
          ),
        );
      }
      Future<void> approve(JournalEntry entry, int n) async {
        await db.save(
          StoredJournalEntry(entry: entry, metadata: metadata(n, at)),
        );
        await db.approve(
          JournalApproval(
            requestId: id(n + 100),
            businessId: id(90),
            journalId: id(n),
            expectedRevision: 1,
            actorId: id(91),
            approvedAt: at.add(const Duration(hours: 1)),
          ),
        );
      }

      JournalLine debit(int a, int v) => JournalLine.debit(
        accountId: id(a),
        amount: Money.fromMinor(v, 'MYR'),
      );
      JournalLine credit(int a, int v) => JournalLine.credit(
        accountId: id(a),
        amount: Money.fromMinor(v, 'MYR'),
      );
      await approve(
        JournalEntry.draft(
          id: id(10),
          date: at,
          memo: 'Sale',
          lines: [debit(1, 10000), credit(3, 10000)],
        ),
        10,
      );
      await approve(
        JournalEntry.draft(
          id: id(11),
          date: at,
          memo: 'Expense',
          lines: [debit(4, 3000), credit(1, 3000)],
        ),
        11,
      );
      final before = await db.report(
        businessId: id(90),
        from: DateTime.utc(2026, 9),
        through: at,
      );
      final proposal = ClosingProposal.fromReport(
        before,
        equityAccountId: id(2),
      );
      await approve(
        JournalEntry.draft(
          id: id(12),
          date: at,
          memo: 'Reviewed close',
          lines: proposal.lines,
          closingEquityAccountId: id(2),
        ),
        12,
      );
      db.close();
      db = LocalAccountingDatabase.open(path);
      addTearDown(db.close);
      final after = await db.report(
        businessId: id(90),
        from: DateTime.utc(2026, 9),
        through: at,
      );
      expect(after.periodProfit, BigInt.from(7000));
      expect(after.unclosedEarnings, BigInt.zero);
      expect(after.contributedAndRetainedEquity, BigInt.from(7000));
      expect(after.isBalanced, isTrue);
      final closing = (await db.getById(id(12)))!.entry;
      expect(closing.isClosing, isTrue);
      final reversal = closing.reversal(
        id: id(14),
        date: at,
        memo: 'Forged ordinary reversal',
      );
      await expectLater(
        approve(
          JournalEntry.restore(
            id: reversal.id,
            date: reversal.date,
            memo: reversal.memo,
            lines: reversal.lines,
            state: JournalEntryState.draft,
            reversesId: closing.id,
          ),
          14,
        ),
        throwsStateError,
      );
      expect((await db.getById(id(14)))!.entry.state, JournalEntryState.draft);
      expect(
        (await db.auditEvents(id(90)))
            .where((e) => e['subject_id'] == id(14).value),
        isEmpty,
      );

      await approve(
        closing.reversal(id: id(13), date: at, memo: 'Reopen closing'),
        13,
      );
      final reversed = await db.report(
        businessId: id(90),
        from: DateTime.utc(2026, 9),
        through: at,
      );
      expect(reversed.periodProfit, BigInt.from(7000));
      expect(reversed.unclosedEarnings, BigInt.from(7000));
      expect(reversed.isBalanced, isTrue);
    },
  );
}
