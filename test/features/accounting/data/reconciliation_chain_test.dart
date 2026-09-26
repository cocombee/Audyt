import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/accounting/application/reconciliation_report.dart';
import 'package:audyt/features/accounting/domain/statement_reconciliation.dart';

import 'dart:convert';

import 'reconciliation_test_support.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'bank_statement_import_test.dart' show parse;

void main() {
  test('statement chain enforces continuity, current parent and latest-first reopening', () async {
    final dir = Directory.systemTemp.createTempSync('reconciliation-chain-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final business = workspace.identity.businessId;
    await workspace.createAccount(
      code: '1000',
      name: 'Bank',
      type: AccountType.asset,
    );
    await workspace.createAccount(
      code: '5000',
      name: 'Supplies',
      type: AccountType.expense,
    );
    final accounts = await workspace.accounts();
    final bank = accounts
        .singleWhere((r) => r.account.type == AccountType.asset)
        .account
        .id;
    final expense = accounts
        .singleWhere((r) => r.account.type == AccountType.expense)
        .account
        .id;
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    workspace.database.linkPaymentLedgerAccount(business, 'bank', bank);
    final statements = <EntityId>[];
    final acceptanceIds = <String>[];
    for (final month in [9, 10]) {
      await workspace.saveJournal(
        date: DateTime.utc(2026, month, 2),
        memo: 'Supplies $month',
        lines: [
          JournalLine.debit(
            accountId: expense,
            amount: Money.fromMinor(1000, 'MYR'),
          ),
          JournalLine.credit(
            accountId: bank,
            amount: Money.fromMinor(1000, 'MYR'),
          ),
        ],
      );
      final draft = (await workspace.journals()).singleWhere(
        (r) => r.entry.state == JournalEntryState.draft,
      );
      await workspace.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: business,
          journalId: draft.entry.id,
          expectedRevision: draft.metadata.revision,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now(),
        ),
      );
      final id = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: business,
        paymentAccountId: 'bank',
        importedAt: DateTime.now(),
        statement: parse(
          'Date,Description,Amount\n2026-${month.toString().padLeft(2, '0')}-02,Supplies,-10.00',
        ),
      );
      workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: id,
        sourceRow: 2,
        journalId: draft.entry.id,
        lineIndex: 1,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      statements.add(id);
      acceptanceIds.add(
        workspace.database.statementMatchAcceptanceId(business, id, 2)!,
      );
    }
    // A populated schema-18 database must retain source and allocations on upgrade.
    workspace.dispose();
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    removeExpenseRemovalSchema(old);
    old.execute('DROP TRIGGER reconciled_match_no_retraction');
    old.execute('DROP TABLE bank_reconciliation_ledger_snapshots');
    old.execute('DROP TABLE bank_reconciliation_allocations');
    old.execute('DROP TABLE bank_reconciliation_reopenings');
    old.execute('DROP TABLE bank_reconciliations');
    old.execute('DROP TABLE claim_settlement_allocations');
    old.execute('DROP TABLE claim_settlements');
    old.execute('DROP TABLE claim_postings');
    old.execute('DROP TABLE invoice_postings');
    old.execute('DROP TABLE invoice_drafts');
    old.execute('DROP TABLE invoice_draft_history');
    old.execute('DROP TABLE customers');
    old.execute('DROP TABLE customer_history');
    old.execute('DROP TABLE invoice_credit_lines');
    old.execute('DROP TABLE invoice_credit_postings');
    old.execute('DROP TABLE invoice_credit_draft_history');
    old.execute('DROP TABLE invoice_credit_drafts');
    old.execute('DROP TABLE customer_receipt_allocations');
    old.execute('DROP TABLE customer_receipts');
    old.execute('DROP TABLE document_numbers');
    // These empty v42 tables do not belong to the historical fixture.
    for (final table in ['bill_settlement_allocations', 'bill_settlements']) {
      expect(old.select('SELECT COUNT(*) AS n FROM $table').single['n'], 0);
      old.execute('DROP TABLE $table');
    }
    old.execute('DROP INDEX bill_settlement_audit');
    old.execute('DROP TABLE IF EXISTS catalogue_items');
    old.execute('DROP TABLE IF EXISTS catalogue_categories');
    old.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    old.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    old.execute('DROP TABLE IF EXISTS recurring_document_template_history');
    old.execute('DROP TABLE IF EXISTS recurring_document_templates');
    old.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    old.execute('DROP TABLE IF EXISTS company_tax_rates');
    old.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    old.execute('DROP TABLE IF EXISTS tax_remittances');
    old.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    old.execute('DROP TABLE IF EXISTS company_tax_agencies');
    old.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version=18');
    old.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database.statementMatchAcceptanceId(business, statements[0], 2),
      acceptanceIds[0],
    );
    expect(workspace.database.bankStatements(business, 'bank'), hasLength(2));
    await seedRecordedOpening(workspace, bank);
    final first = EntityId.random();
    final second = EntityId.random();
    void approve(
      int index,
      EntityId request, {
      String? parent,
      int startDay = 1,
      int? opening,
      EntityId? actor,
      Set<String> outstanding = const {},
    }) {
      workspace.database.approveStatementReconciliation(
        requestId: request,
        businessId: business,
        statementId: statements[index],
        actorId: actor ?? workspace.identity.ownerId,
        approvedAt: DateTime.now(),
        startsOn: DateTime.utc(2026, 9 + index, startDay),
        endsOn: DateTime.utc(2026, 10 + index, 0),
        openingBalance: Money.fromMinor(opening ?? 10000 - index * 1000, 'MYR'),
        closingBalance: Money.fromMinor(9000 - index * 1000, 'MYR'),
        expectedAcceptanceIds: {2: acceptanceIds[index]},
        expectedPreviousId: parent,
        openingOutstandingIds: outstanding,
        firstOpeningEvidence:
            'Opening bank statement verified with outstanding list.',
      );
    }

    expect(() => approve(0, first, actor: EntityId.random()), throwsStateError);
    approve(0, first);
    final originalSnapshot = workspace.database.reconciliationLedgerSnapshot(
      business,
      first.value,
    )!;
    expect(originalSnapshot.balance, Money.fromMinor(9000, 'MYR'));
    expect(originalSnapshot.movements, hasLength(2));
    final originalReport = workspace.database.reconciliationReportSnapshot(
      business,
      first.value,
    );
    expect(originalReport.approval.reopenedAt, isNull);
    expect(originalReport.changes.unchanged, isTrue);
    expect(
      workspace.database
          .reconciliationLedgerChanges(business, first.value)
          .unchanged,
      isTrue,
    );
    final incorrectReview = workspace.database.prepareStatementReconciliation(
      businessId: business,
      statementId: statements[1],
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 31),
      openingBalance: Money.fromMinor(9001, 'MYR'),
      closingBalance: Money.fromMinor(8001, 'MYR'),
    );
    expect(incorrectReview.review.rowsAndBalancesAgree, isTrue);
    expect(incorrectReview.recordedOpening, Money.fromMinor(9000, 'MYR'));
    expect(incorrectReview.openingDifference.minorUnits, 1);
    expect(incorrectReview.requiredStart, DateTime.utc(2026, 10, 1));
    expect(incorrectReview.readyForApproval, isFalse);
    expect(() => approve(1, second), throwsStateError);
    expect(
      () => approve(1, second, parent: first.value, startDay: 2),
      throwsStateError,
    );
    expect(
      () => approve(1, second, parent: first.value, startDay: 0),
      throwsStateError,
    );
    expect(
      () => approve(1, second, parent: first.value, opening: 9001),
      throwsStateError,
    );
    approve(1, second, parent: first.value);
    final secondClassification = workspace.database
        .reconciliationClassification(business, second.value)!;
    expect(secondClassification.agrees, isTrue);
    expect(secondClassification.clearedBalance, Money.fromMinor(8000, 'MYR'));
    expect(secondClassification.outstanding, isEmpty);
    void reopen(EntityId id) =>
        workspace.database.reopenStatementReconciliation(
          businessId: business,
          completionId: id.value,
          actorId: workspace.identity.ownerId,
          reopenedAt: DateTime.now(),
          reason: 'Correct statement evidence',
        );
    expect(() => reopen(first), throwsStateError);
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database.latestReconciliationId(business, 'bank'),
      second.value,
    );
    reopen(second);
    expect(
      workspace.database.latestReconciliationId(business, 'bank'),
      first.value,
    );
    reopen(first);
    expect(workspace.database.latestReconciliationId(business, 'bank'), isNull);
    // Retrying old approvals must not resurrect reopened completions.
    approve(0, first);
    approve(1, second, parent: first.value);
    expect(workspace.database.latestReconciliationId(business, 'bank'), isNull);
    await workspace.saveJournal(
      date: DateTime.utc(2026, 8, 31),
      memo: 'Uncleared cheque',
      lines: [
        JournalLine.debit(
          accountId: expense,
          amount: Money.fromMinor(500, 'MYR'),
        ),
        JournalLine.credit(
          accountId: bank,
          amount: Money.fromMinor(500, 'MYR'),
        ),
      ],
    );
    final cheque = (await workspace.journals()).singleWhere(
      (r) => r.entry.state == JournalEntryState.draft,
    );
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: business,
        journalId: cheque.entry.id,
        expectedRevision: cheque.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now(),
      ),
    );
    final preservedSnapshot = workspace.database.reconciliationLedgerSnapshot(
      business,
      first.value,
    )!;
    expect(preservedSnapshot.balance, Money.fromMinor(9000, 'MYR'));
    expect(
      preservedSnapshot.movements.map((m) => m.memo),
      isNot(contains('Uncleared cheque')),
    );
    final delta = workspace.database.reconciliationLedgerChanges(
      business,
      first.value,
    );
    expect(delta.added.single.memo, 'Uncleared cheque');
    final updatedReport = workspace.database.reconciliationReportSnapshot(
      business,
      first.value,
    );
    expect(updatedReport.approval.reopenedAt, isNotNull);
    expect(updatedReport.changes.added.single.memo, 'Uncleared cheque');
    expect(updatedReport.ledger!.balance, originalReport.ledger!.balance);
    expect(originalReport.approval.reopenedAt, isNull);
    expect(originalReport.changes.added, isEmpty);
    expect(
      () => workspace.database.reconciliationReportSnapshot(
        EntityId.random(),
        first.value,
      ),
      throwsStateError,
    );
    expect(delta.unchanged, isFalse);
    final replacement = EntityId.random();
    expect(() => approve(0, replacement), throwsStateError);
    expect(
      () => approve(0, replacement, outstanding: {'missing'}),
      throwsStateError,
    );
    final outstandingId = '${cheque.entry.id.value}:1';
    final review = workspace.database.prepareStatementReconciliation(
      businessId: business,
      statementId: statements[0],
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(9000, 'MYR'),
      openingOutstandingIds: {outstandingId},
    );
    expect(review.recordedOpening, Money.fromMinor(10000, 'MYR'));
    expect(
      review.openingMovements.singleWhere((m) => m.id == outstandingId).amount,
      Money.fromMinor(-500, 'MYR'),
    );
    expect(review.readyForApproval, isTrue);
    approve(0, replacement, outstanding: {outstandingId});
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    final persisted = sqlite3.open(path);
    final payload = jsonDecode(
      persisted.select('SELECT payload FROM bank_reconciliations WHERE id=?', [
            replacement.value,
          ]).single['payload']
          as String,
    ) as Map<String, dynamic>;
    expect(payload['openingOutstanding'], [outstandingId]);
    final historical = workspace.database.reconciliationEvidence(
      business,
      replacement.value,
    );
    expect(historical.openingOutstanding.single.id, outstandingId);
    expect(historical.openingOutstanding.single.memo, 'Uncleared cheque');
    final report = reconciliationReportHtml(
      businessId: '<script>unsafe</script>',
      generatedAt: DateTime.utc(2026, 11, 1),
      approval: workspace.database
          .reconciliationHistory(business, statements[0])
          .firstWhere((a) => a.id == replacement.value),
      evidence: ReconciliationEvidence(
        filename: '<img src=x onerror=alert(1)>.csv',
        sourceDigest: historical.sourceDigest,
        matches: historical.matches,
        openingOutstanding: historical.openingOutstanding,
      ),
      ledger: workspace.database.reconciliationLedgerSnapshot(
        business,
        replacement.value,
      ),
      classification: workspace.database.reconciliationClassification(
        business,
        replacement.value,
      ),
      changes: workspace.database.reconciliationLedgerChanges(
        business,
        replacement.value,
      ),
    );
    expect(report, contains('&lt;script&gt;unsafe&lt;/script&gt;'));
    expect(report, isNot(contains('<script>')));
    expect(report, contains('&lt;img src=x onerror=alert(1)&gt;.csv'));
    expect(report, contains('-RM 5.00'));
    expect(report, contains('RM 90.00'));
    expect(report, contains(outstandingId));
    expect(report, contains('Uncleared cheque'));
    expect(report, contains('Outstanding'));
    expect(report, isNot(contains('https://')));
    final classified = workspace.database.reconciliationClassification(
      business,
      replacement.value,
    )!;
    expect(classified.agrees, isTrue);
    expect(classified.clearedBalance, Money.fromMinor(9000, 'MYR'));
    expect(classified.outstandingBalance, Money.fromMinor(-500, 'MYR'));
    expect(classified.outstanding.single.id, outstandingId);
    expect(
      historical.openingOutstanding.single.amount,
      Money.fromMinor(-500, 'MYR'),
    );
    expect(() => historical.openingOutstanding.clear(), throwsUnsupportedError);
    expect(
      workspace.database
          .reconciliationLedgerSnapshot(business, replacement.value)!
          .balance,
      Money.fromMinor(8500, 'MYR'),
    );
    expect(
      () =>
          persisted.execute('DELETE FROM bank_reconciliation_ledger_snapshots'),
      throwsA(isA<SqliteException>()),
    );
    persisted.dispose();
    expect(
      workspace.database.latestReconciliationId(business, 'bank'),
      replacement.value,
    );
    workspace.database.retractStatementMatch(
      businessId: business,
      acceptanceId: acceptanceIds[1],
      actorId: workspace.identity.ownerId,
      retractedAt: DateTime.now(),
      reason: 'Use complete October statement',
    );
    final october = workspace.database.importBankStatement(
      id: EntityId.random(),
      businessId: business,
      paymentAccountId: 'bank',
      importedAt: DateTime.now(),
      statement: parse(
        'Date,Description,Amount\n2026-10-02,Supplies,-10.00\n2026-10-20,Cheque cleared,-5.00',
      ),
    );
    final octoberJournal = (await workspace.journals()).singleWhere(
      (r) => r.entry.date.month == 10,
    );
    for (final pair in [(2, octoberJournal.entry.id), (3, cheque.entry.id)]) {
      workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: october,
        sourceRow: pair.$1,
        journalId: pair.$2,
        lineIndex: 1,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
    }
    final octoberApproval = EntityId.random();
    workspace.database.approveStatementReconciliation(
      requestId: octoberApproval,
      businessId: business,
      statementId: october,
      actorId: workspace.identity.ownerId,
      approvedAt: DateTime.now(),
      startsOn: DateTime.utc(2026, 10, 1),
      endsOn: DateTime.utc(2026, 10, 31),
      openingBalance: Money.fromMinor(9000, 'MYR'),
      closingBalance: Money.fromMinor(7500, 'MYR'),
      expectedAcceptanceIds: {
        for (final row in [2, 3])
          row: workspace.database.statementMatchAcceptanceId(
            business,
            october,
            row,
          )!,
      },
      expectedPreviousId: replacement.value,
    );
    final clearedOctober = workspace.database.reconciliationClassification(
      business,
      octoberApproval.value,
    )!;
    expect(clearedOctober.agrees, isTrue);
    expect(clearedOctober.outstanding, isEmpty);
    expect(clearedOctober.clearedBalance, Money.fromMinor(7500, 'MYR'));
    expect(
      clearedOctober.cleared.where((m) => m.id == outstandingId),
      hasLength(1),
    );
    expect(
      workspace.database
          .reconciliationClassification(business, replacement.value)!
          .outstanding
          .single
          .id,
      outstandingId,
    );
    expect(await workspace.journals(), hasLength(4));
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database
          .reconciliationClassification(business, octoberApproval.value)!
          .outstanding,
      isEmpty,
    );
    reopen(octoberApproval);
    await workspace.saveJournal(
      date: DateTime.utc(2026, 9, 20),
      memo: 'Late recorded refund',
      lines: [
        JournalLine.debit(accountId: bank, amount: Money.fromMinor(50, 'MYR')),
        JournalLine.credit(
          accountId: expense,
          amount: Money.fromMinor(50, 'MYR'),
        ),
      ],
    );
    final late = (await workspace.journals()).singleWhere(
      (r) => r.entry.state == JournalEntryState.draft,
    );
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: business,
        journalId: late.entry.id,
        expectedRevision: late.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now(),
      ),
    );
    expect(
      workspace.database
          .reconciliationLedgerChanges(business, replacement.value)
          .added
          .single
          .memo,
      'Late recorded refund',
    );
    expect(
      () => approve(1, EntityId.random(), parent: replacement.value),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reason',
          contains('previous reconciliation ledger changed'),
        ),
      ),
    );
    expect(await workspace.journals(), hasLength(5));
    workspace.dispose();
    final legacy19 = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(legacy19);
    removeExpenseRemovalSchema(legacy19);
    legacy19.execute('DROP TABLE bank_reconciliation_ledger_snapshots');
    legacy19.execute('DROP TABLE claim_settlement_allocations');
    legacy19.execute('DROP TABLE claim_settlements');
    legacy19.execute('DROP TABLE claim_postings');
    legacy19.execute('DROP TABLE invoice_postings');
    legacy19.execute('DROP TABLE invoice_drafts');
    legacy19.execute('DROP TABLE invoice_draft_history');
    legacy19.execute('DROP TABLE customers');
    legacy19.execute('DROP TABLE customer_history');
    legacy19.execute('DROP TABLE invoice_credit_lines');
    legacy19.execute('DROP TABLE invoice_credit_postings');
    legacy19.execute('DROP TABLE invoice_credit_draft_history');
    legacy19.execute('DROP TABLE invoice_credit_drafts');
    legacy19.execute('DROP TABLE customer_receipt_allocations');
    legacy19.execute('DROP TABLE customer_receipts');
    legacy19.execute('DROP TABLE document_numbers');
    // These empty v42 tables do not belong to the historical fixture.
    for (final table in ['bill_settlement_allocations', 'bill_settlements']) {
      expect(
        legacy19.select('SELECT COUNT(*) AS n FROM $table').single['n'],
        0,
      );
      legacy19.execute('DROP TABLE $table');
    }
    legacy19.execute('DROP INDEX bill_settlement_audit');
    legacy19.execute('DROP TABLE IF EXISTS catalogue_items');
    legacy19.execute('DROP TABLE IF EXISTS catalogue_categories');
    legacy19.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    legacy19.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    legacy19.execute(
      'DROP TABLE IF EXISTS recurring_document_template_history',
    );
    legacy19.execute('DROP TABLE IF EXISTS recurring_document_templates');
    legacy19.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    legacy19.execute('DROP TABLE IF EXISTS company_tax_rates');
    legacy19.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    legacy19.execute('DROP TABLE IF EXISTS tax_remittances');
    legacy19.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    legacy19.execute('DROP TABLE IF EXISTS company_tax_agencies');
    legacy19.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    legacy19.execute('DROP VIEW IF EXISTS current_expense_intakes');
    legacy19.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    legacy19.execute('DROP TABLE IF EXISTS expense_revision_postings');
    legacy19.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    legacy19.execute('PRAGMA user_version=19');
    legacy19.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database.reconciliationLedgerSnapshot(
        business,
        replacement.value,
      ),
      isNull,
    );
    expect(
      workspace.database.latestReconciliationId(business, 'bank'),
      replacement.value,
    );
    workspace.dispose();
  });
}
