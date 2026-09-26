import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import '../../../support/accounting_text_input.dart';

import 'package:audyt/app/accounting_components.dart';

import '../../../support/accounting_test_finders.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'reconciliation_test_support.dart';

import 'package:flutter/material.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';

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
  test('v32 one-to-one match survives the group-match migration', () async {
    final dir = Directory.systemTemp.createTempSync('v32-group-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var workspace = await createDemoWorkspace(databasePath: path);
    addTearDown(() => workspace.dispose());
    final businessId = workspace.identity.businessId;
    final statementId = workspace.database
        .bankStatements(businessId, 'demo-bank')
        .singleWhere((item) => item.filename == 'Demo Bank.csv')
        .id;
    final first = workspace.database
        .statementMatchSuggestions(businessId, statementId)
        .singleWhere((entry) => entry.row.sourceRow == 2)
        .candidates
        .first;
    workspace.database.acceptStatementMatch(
      businessId: businessId,
      statementId: statementId,
      sourceRow: 2,
      journalId: first.journalId,
      lineIndex: first.lineIndex,
      actorId: workspace.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 26),
    );
    final originalAcceptance = workspace.database.statementMatchAcceptanceId(
      businessId,
      statementId,
      2,
    );
    workspace.dispose();

    // v33 only added these two tables. Removing them models the exact v32
    // schema while keeping the previously accepted one-to-one history.
    final previous = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(previous);
    removeExpenseRemovalSchema(previous);
    previous.execute('DROP TABLE bank_match_active_members');
    previous.execute('DROP TABLE bank_match_group_members');
    // These empty v42 tables do not belong to the historical fixture.
    for (final table in ['bill_settlement_allocations', 'bill_settlements']) {
      expect(
        previous.select('SELECT COUNT(*) AS n FROM $table').single['n'],
        0,
      );
      previous.execute('DROP TABLE $table');
    }
    previous.execute('DROP INDEX bill_settlement_audit');
    previous.execute('DROP TABLE IF EXISTS catalogue_items');
    previous.execute('DROP TABLE IF EXISTS catalogue_categories');
    previous.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    previous.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    previous.execute(
      'DROP TABLE IF EXISTS recurring_document_template_history',
    );
    previous.execute('DROP TABLE IF EXISTS recurring_document_templates');
    previous.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    previous.execute('DROP TABLE IF EXISTS company_tax_rates');
    previous.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    previous.execute('DROP TABLE IF EXISTS tax_remittances');
    previous.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    previous.execute('DROP TABLE IF EXISTS company_tax_agencies');
    previous.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    previous.execute('DROP VIEW IF EXISTS current_expense_intakes');
    previous.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    previous.execute('DROP TABLE IF EXISTS expense_revision_postings');
    previous.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    previous.execute('PRAGMA user_version=32');
    previous.dispose();

    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database.acceptedStatementMatches(businessId, statementId)[2],
      first.movementId,
    );
    expect(
      workspace.database.statementMatchAcceptanceId(businessId, statementId, 2),
      originalAcceptance,
    );
    final group = workspace.database.statementGroupMatchSuggestions(
      businessId: businessId,
      statementId: statementId,
      sourceRows: {4, 5},
    );
    expect(group, hasLength(1));
    workspace.database.acceptStatementMatchGroup(
      businessId: businessId,
      statementId: statementId,
      sourceRows: {4, 5},
      journalId: group.single.journalId,
      lineIndex: group.single.lineIndex,
      actorId: workspace.identity.ownerId,
      acceptedAt: DateTime.utc(2026, 9, 26, 1),
    );
    final accepted = workspace.database.acceptedStatementMatches(
      businessId,
      statementId,
    );
    expect(accepted[2], first.movementId);
    expect(accepted[4], group.single.movementId);
    expect(accepted[5], group.single.movementId);
    final headers = workspace.database.journalMatchHeaders(
      businessId,
      statementId,
    );
    expect(headers[first.journalId.value]!.memo, first.memo);
    expect(headers[first.journalId.value]!.date, first.date);
    expect(headers[group.single.journalId.value]!.memo, group.single.memo);
    expect(headers[group.single.journalId.value]!.date, group.single.date);
  });

  test(
    'one posted receipt connects two real demo bank rows atomically',
    () async {
      final dir = Directory.systemTemp.createTempSync('group-match-reopen-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var workspace = await createDemoWorkspace(databasePath: path);
      addTearDown(() => workspace.dispose());
      final businessId = workspace.identity.businessId;
      final csv = workspace.database
          .bankStatements(businessId, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.csv');
      final rows = workspace.database.bankStatement(businessId, csv.id)!.rows;
      final selected = rows
          .where((row) => row.reference.startsWith('DEMO-RCPT-001-'))
          .map((row) => row.sourceRow)
          .toSet();
      expect(selected, hasLength(2));
      expect(
        workspace.database.statementGroupMatchSuggestions(
          businessId: businessId,
          statementId: csv.id,
          sourceRows: {2, 4},
        ),
        isEmpty,
      );
      expect(
        () => workspace.database.statementGroupMatchSuggestions(
          businessId: businessId,
          statementId: csv.id,
          sourceRows: {3, 4},
        ),
        throwsStateError,
      );
      final candidates = workspace.database.statementGroupMatchSuggestions(
        businessId: businessId,
        statementId: csv.id,
        sourceRows: selected,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.memo, contains('DEMO-RCPT-001'));
      final candidate = candidates.single;
      workspace.database.acceptStatementMatchGroup(
        businessId: businessId,
        statementId: csv.id,
        sourceRows: selected,
        journalId: candidate.journalId,
        lineIndex: candidate.lineIndex,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.utc(2026, 9, 26),
      );
      final accepted = workspace.database.acceptedStatementMatches(
        businessId,
        csv.id,
      );
      expect(
        {for (final row in selected) accepted[row]},
        {candidate.movementId},
      );
      final ids = {
        for (final row in selected)
          workspace.database.statementMatchAcceptanceId(
            businessId,
            csv.id,
            row,
          ),
      };
      expect(ids, hasLength(1));
      final groupId = ids.single!;
      expect(
        workspace.database
            .statementMatchHistory(businessId, csv.id)
            .where((entry) => entry.acceptanceId == groupId)
            .map((entry) => entry.sourceRow)
            .toSet(),
        selected,
      );
      final now = DateTime.now();
      final review = workspace.database
          .prepareStatementReconciliation(
            businessId: businessId,
            statementId: csv.id,
            startsOn: DateTime(now.year, now.month, 1),
            endsOn: DateTime(now.year, now.month + 1, 0),
            openingBalance: Money.fromMinor(0, 'MYR'),
            closingBalance: Money.fromMinor(0, 'MYR'),
          )
          .review;
      expect(review.matchedMovement.minorUnits, 50000);
      expect(review.invalidMatchRows, isEmpty);
      expect(
        () => workspace.database.acceptStatementMatchGroup(
          businessId: businessId,
          statementId: csv.id,
          sourceRows: selected,
          journalId: candidate.journalId,
          lineIndex: candidate.lineIndex,
          actorId: workspace.identity.ownerId,
          acceptedAt: DateTime.utc(2026, 9, 26),
        ),
        throwsStateError,
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.database
            .acceptedStatementMatches(businessId, csv.id)
            .keys
            .toSet()
            .containsAll(selected),
        isTrue,
      );
      workspace.database.retractStatementMatch(
        businessId: businessId,
        acceptanceId: groupId,
        actorId: workspace.identity.ownerId,
        retractedAt: DateTime.utc(2026, 9, 27),
        reason: 'Test correction',
      );
      final after = workspace.database.acceptedStatementMatches(
        businessId,
        csv.id,
      );
      for (final row in selected) {
        expect(after.containsKey(row), isFalse);
      }
      expect(
        workspace.database
            .statementMatchHistory(businessId, csv.id)
            .where((entry) => entry.acceptanceId == groupId)
            .every((entry) => entry.reason == 'Test correction'),
        isTrue,
      );
    },
  );

  testWidgets(
    'accepted match prevents double allocation and survives restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('accepted-bank-match-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '5000',
        name: 'Expense',
        type: AccountType.expense,
      );
      final chart = await workspace.accounts();
      final bank = chart
          .singleWhere((r) => r.account.type == AccountType.asset)
          .account
          .id;
      final expense = chart
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
      final business = workspace.identity.businessId;
      workspace.database.linkPaymentLedgerAccount(business, 'bank', bank);
      await workspace.saveJournal(
        date: DateTime.utc(2026, 9, 1),
        memo: 'Supplies',
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
      final journal = (await workspace.journals()).single;
      await workspace.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: business,
          journalId: journal.entry.id,
          expectedRevision: journal.metadata.revision,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now(),
        ),
      );
      final statementId = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: business,
        paymentAccountId: 'bank',
        importedAt: DateTime.now(),
        statement: parse(
          'Date,Description,Amount\n2026-09-01,Shop,-10.00\n2026-09-01,Shop,-10.00',
        ),
      );
      void accept(int row, {EntityId? actor}) =>
          workspace.database.acceptStatementMatch(
            businessId: business,
            statementId: statementId,
            sourceRow: row,
            journalId: journal.entry.id,
            lineIndex: 1,
            actorId: actor ?? workspace.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
      expect(
        workspace.database
            .statementMatchSuggestions(business, statementId)
            .first
            .candidates,
        hasLength(1),
      );
      expect(() => accept(2, actor: EntityId.random()), throwsStateError);
      expect(() => accept(99), throwsStateError);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: statementId.value);
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('review-open-reconciliation')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 transactions remaining'), findsNothing);
      expect(find.text('Statement Date Range'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reconciliation-start')),
            )
            .controller
            ?.text,
        '01-09-2026',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-start')),
        '',
      );
      await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
      await tester.pumpAndSettle();
      expect(find.text('Enter valid statement dates.'), findsOneWidget);
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-start')),
        '01-09-2026',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-end')),
        '30-09-2026',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-opening')),
        '100',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-closing')),
        '80.001',
      );
      await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter balances as exact decimal amounts.'),
        findsOneWidget,
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-closing')),
        '80',
      );
      await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byKey(const ValueKey('reconciliation-balance-check')),
            )
            .rows,
        contains(('Unmatched Rows', '2')),
      );
      expect(find.text('Balance Check Target'), findsOneWidget);
      expect(
        find.text(
          'Resolve the differences and row issues before completing reconciliation.',
        ),
        findsOneWidget,
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-opening')),
        '101',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reconciliation-balance-check')),
        findsNothing,
      );
      final backToMatches = find.byKey(const ValueKey('back-to-matches'));
      await tester.ensureVisible(backToMatches);
      await tester.pumpAndSettle();
      await tester.tap(backToMatches);
      await tester.pumpAndSettle();
      final discard = find.byKey(
        const ValueKey('reconciliation-discard-changes'),
      );
      expect(discard, findsOneWidget);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reconciliation-opening')),
        findsNothing,
      );
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        isEmpty,
      );
      await tester.tap(
        find.byKey(ValueKey('accept-match-2-${journal.entry.id.value}:1')),
      );
      await tester.pumpAndSettle();
      void expectLinkedMovementRows() {
        final details = find.byKey(const ValueKey('accepted-match-details-2'));
        expect(details, findsOneWidget);
        for (final text in [
          'Journal Movement',
          '${journal.entry.id.value}:1',
          'Posting Date',
          '01-09-2026',
          'Memo',
          'Supplies',
        ]) {
          expect(
            find.descendant(of: details, matching: find.text(text)),
            findsOneWidget,
          );
        }
      }

      expectLinkedMovementRows();
      expect(
        find.byKey(const ValueKey('banking-unresolved-bank')),
        findsOneWidget,
      );
      expect(find.text('1 transaction'), findsOneWidget);
      final duplicateMatch = find.byKey(
        ValueKey('accept-match-3-${journal.entry.id.value}:1'),
      );
      // Allocated ledger movements disappear from other bank rows immediately.
      expect(duplicateMatch, findsNothing);
      expect(
        find.byKey(const ValueKey('statement-match-card-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statement-match-card-3')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('retract-match-2')), findsOneWidget);
      expect(find.text('Matched'), findsOneWidget);
      expect(find.text('Unmatched'), findsWidgets);
      expect(find.byKey(const ValueKey('retract-match-2')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      accept(2);
      accept(2);
      expect(() => accept(3), throwsStateError);
      workspace.dispose();
      // Recreate the populated schema-17 boundary before opening the upgrade.
      final legacy = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(legacy);
      removeExpenseRemovalSchema(legacy);
      final originalAcceptance = legacy
          .select('SELECT actor_id,accepted_at FROM bank_statement_matches')
          .single;
      final originalActor = originalAcceptance['actor_id'];
      final originalTime = originalAcceptance['accepted_at'];
      legacy.execute('DROP TRIGGER bank_match_no_update');
      legacy.execute('DROP TRIGGER bank_match_no_delete');
      legacy.execute('DROP TRIGGER reconciled_match_no_retraction');
      legacy.execute('DROP TABLE bank_reconciliation_ledger_snapshots');
      legacy.execute('DROP TABLE bank_reconciliation_allocations');
      legacy.execute('DROP TABLE bank_reconciliation_reopenings');
      legacy.execute('DROP TABLE bank_reconciliations');
      legacy.execute('DROP TABLE bank_match_active_members');
      legacy.execute('DROP TABLE bank_match_group_members');
      legacy.execute('DROP TABLE bank_match_retractions');
      legacy.execute('DROP TABLE bank_match_history');
      legacy.execute('DROP INDEX bank_match_acceptance_id');
      // The legacy fixture drops the modern acceptance column below. Remove
      // schema objects introduced after v17 that still mention that column.
      for (final object in legacy.select(
        "SELECT type,name FROM sqlite_master WHERE sql LIKE '%acceptance_id%' AND type IN ('trigger','view')",
      )) {
        legacy.execute('DROP ${object['type']} ${object['name']}');
      }
      legacy.execute(
        'ALTER TABLE bank_statement_matches DROP COLUMN acceptance_id',
      );
      legacy.execute(
        "CREATE TRIGGER bank_match_no_update BEFORE UPDATE ON bank_statement_matches BEGIN SELECT RAISE(ABORT, 'Accepted matches are immutable'); END",
      );
      legacy.execute(
        "CREATE TRIGGER bank_match_no_delete BEFORE DELETE ON bank_statement_matches BEGIN SELECT RAISE(ABORT, 'Accepted matches are immutable'); END",
      );
      legacy.execute('DROP TABLE claim_settlement_allocations');
      legacy.execute('DROP TABLE claim_settlements');
      legacy.execute('DROP TABLE claim_postings');
      legacy.execute('DROP TABLE invoice_postings');
      legacy.execute('DROP TABLE invoice_drafts');
      legacy.execute('DROP TABLE invoice_draft_history');
      legacy.execute('DROP TABLE customers');
      legacy.execute('DROP TABLE customer_history');
      legacy.execute('DROP TABLE invoice_credit_lines');
      legacy.execute('DROP TABLE invoice_credit_postings');
      legacy.execute('DROP TABLE invoice_credit_draft_history');
      legacy.execute('DROP TABLE invoice_credit_drafts');
      legacy.execute('DROP TABLE customer_receipt_allocations');
      legacy.execute('DROP TABLE customer_receipts');
      legacy.execute('DROP TABLE document_numbers');
      // These empty v42 tables do not belong to the historical fixture.
      for (final table in ['bill_settlement_allocations', 'bill_settlements']) {
        expect(
          legacy.select('SELECT COUNT(*) AS n FROM $table').single['n'],
          0,
        );
        legacy.execute('DROP TABLE $table');
      }
      legacy.execute('DROP INDEX bill_settlement_audit');
      legacy.execute('DROP TABLE IF EXISTS catalogue_items');
      legacy.execute('DROP TABLE IF EXISTS catalogue_categories');
      legacy.execute('DROP TABLE IF EXISTS generated_document_deliveries');
      legacy.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
      legacy.execute(
        'DROP TABLE IF EXISTS recurring_document_template_history',
      );
      legacy.execute('DROP TABLE IF EXISTS recurring_document_templates');
      legacy.execute('DROP TABLE IF EXISTS company_tax_rate_history');
      legacy.execute('DROP TABLE IF EXISTS company_tax_rates');
      legacy.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      legacy.execute('DROP TABLE IF EXISTS tax_remittances');
      legacy.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      legacy.execute('DROP TABLE IF EXISTS company_tax_agencies');
      legacy.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      legacy.execute('DROP VIEW IF EXISTS current_expense_intakes');
      legacy.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      legacy.execute('DROP TABLE IF EXISTS expense_revision_postings');
      legacy.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      legacy.execute('PRAGMA user_version = 17');
      legacy.dispose();
      workspace = await AccountingWorkspace.open(path);
      final migratedHistory = workspace.database.statementMatchHistory(
        business,
        statementId,
      );
      expect(migratedHistory, hasLength(1));
      expect(migratedHistory.single.actorId, originalActor);
      expect(
        migratedHistory.single.acceptedAt,
        DateTime.parse(originalTime as String),
      );
      expect(migratedHistory.single.acceptanceId, '${statementId.value}:2');
      expect(migratedHistory.single.reason, isNull);
      expect(
        workspace.database.statementMatchHistory(
          EntityId.random(),
          statementId,
        ),
        isEmpty,
      );
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        {2: '${journal.entry.id.value}:1'},
      );
      accept(2);
      expect(() => accept(3), throwsStateError);
      final acceptance = workspace.database.statementMatchAcceptanceId(
        business,
        statementId,
        2,
      )!;
      void retract(String reason) => workspace.database.retractStatementMatch(
        businessId: business,
        acceptanceId: acceptance,
        actorId: workspace.identity.ownerId,
        retractedAt: DateTime.now(),
        reason: reason,
      );
      expect(() => retract(''), throwsArgumentError);
      final raw = sqlite3.open(path);
      expect(
        () => raw.execute('DELETE FROM bank_statement_matches'),
        throwsA(isA<SqliteException>()),
      );
      retract('Matched the wrong duplicate row');
      retract('Matched the wrong duplicate row');
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        isEmpty,
      );
      expect(raw.select('SELECT * FROM bank_match_history'), hasLength(1));
      expect(
        raw
            .select('SELECT reason FROM bank_match_retractions')
            .single['reason'],
        'Matched the wrong duplicate row',
      );
      expect(
        () => raw.execute('DELETE FROM bank_match_history'),
        throwsA(isA<SqliteException>()),
      );
      accept(3);
      expect(raw.select('SELECT * FROM bank_match_history'), hasLength(2));
      // An old retry must never retract a newer acceptance.
      retract('Matched the wrong duplicate row');
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        {3: '${journal.entry.id.value}:1'},
      );
      raw.dispose();
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: statementId.value);
      final retractMatch = find.byKey(const ValueKey('retract-match-3'));
      await tester.ensureVisible(retractMatch);
      await tester.tap(retractMatch);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        hasLength(1),
      );
      await tester.ensureVisible(retractMatch);
      await tester.tap(retractMatch);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-match-retraction')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a correction reason.'), findsOneWidget);
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('match-correction-reason')),
        'Wrong statement selected',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-match-retraction')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retract-match-3')), findsNothing);
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('show-match-history')));
      await tester.pumpAndSettle();
      expect(find.text('Match History'), findsWidgets);
      expect(find.text('Wrong statement selected'), findsOneWidget);
      expect(find.text('Matched the wrong duplicate row'), findsOneWidget);
      expect(find.text('Statement Row 2 · Retracted'), findsOneWidget);
      expect(find.text('Statement Row 3 · Retracted'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.database.acceptedStatementMatches(business, statementId),
        isEmpty,
      );
      final singleStatement = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: business,
        paymentAccountId: 'bank',
        importedAt: DateTime.now(),
        statement: parse(
          'Date,Description,Amount\n2026-09-20,Verified shop,-10.00',
        ),
      );
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: singleStatement.value);
      await tester.tap(
        find.byKey(const ValueKey('review-statement-switcher-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('review-statement-option-${singleStatement.value}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Suggested Match'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('matching-window-switch')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('accept-match-2-${journal.entry.id.value}:1')),
      );
      await tester.pumpAndSettle();
      expectLinkedMovementRows();
      await tester.pumpWidget(const SizedBox());
      var matchId = workspace.database.statementMatchAcceptanceId(
        business,
        singleStatement,
        2,
      )!;
      var completion = EntityId.random();
      void approve({
        String evidence =
            'Opening bank statement reviewed; no outstanding items',
        Map<int, String>? matches,
      }) => workspace.database.approveStatementReconciliation(
        requestId: completion,
        businessId: business,
        statementId: singleStatement,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now(),
        startsOn: DateTime.utc(2026, 9, 1),
        endsOn: DateTime.utc(2026, 9, 30),
        openingBalance: Money.fromMinor(10000, 'MYR'),
        closingBalance: Money.fromMinor(9000, 'MYR'),
        expectedAcceptanceIds: matches ?? {2: matchId},
        expectedPreviousId: null,
        firstOpeningEvidence: evidence,
      );
      expect(() => approve(evidence: ''), throwsArgumentError);
      expect(() => approve(matches: {2: 'stale'}), throwsStateError);
      expect(approve, throwsStateError);
      await seedRecordedOpening(workspace, bank);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: singleStatement.value);
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('review-open-reconciliation')),
      );
      await tester.pumpAndSettle();
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-start')),
        '01-09-2026',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-end')),
        '30-09-2026',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-opening')),
        '100',
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-closing')),
        '90',
      );
      await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
      await tester.pumpAndSettle();
      final openingCheckbox = find.byType(Checkbox);
      expect(openingCheckbox, findsOneWidget);
      await tester.ensureVisible(openingCheckbox);
      await tester.ensureVisible(openingCheckbox);
      await tester.tap(openingCheckbox);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('approve-reconciliation')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(openingCheckbox);
      await tester.tap(openingCheckbox);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('approve-reconciliation')),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('approve-reconciliation')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('approve-reconciliation')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Document the first opening balance'),
        findsOneWidget,
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-evidence')),
        'Opening bank statement reviewed; no outstanding items',
      );
      workspace.database.retractStatementMatch(
        businessId: business,
        acceptanceId: matchId,
        actorId: workspace.identity.ownerId,
        retractedAt: DateTime.now(),
        reason: 'Recheck evidence',
      );
      workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: singleStatement,
        sourceRow: 2,
        journalId: journal.entry.id,
        lineIndex: 1,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('approve-reconciliation')),
      );
      await tester.tap(find.byKey(const ValueKey('approve-reconciliation')));
      await tester.pumpAndSettle();
      expect(
        find.text('Accepted matches changed. Review again.'),
        findsOneWidget,
      );
      expect(
        workspace.database.latestReconciliationId(business, 'bank'),
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('approve-reconciliation')),
      );
      await tester.tap(find.byKey(const ValueKey('approve-reconciliation')));
      await tester.pumpAndSettle();
      expect(find.text('Reconciliation Approved'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approve-reconciliation')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('back-to-matches')));
      await tester.pumpAndSettle();
      expect(find.textContaining('transactions remaining'), findsNothing);
      completion = EntityId.parse(
        workspace.database.latestReconciliationId(business, 'bank')!,
      );
      matchId = workspace.database.statementMatchAcceptanceId(
        business,
        singleStatement,
        2,
      )!;
      await tester.pumpWidget(const SizedBox());
      expect(
        workspace.database.latestReconciliationId(business, 'bank'),
        completion.value,
      );
      void retractProtected() => workspace.database.retractStatementMatch(
        businessId: business,
        acceptanceId: matchId,
        actorId: workspace.identity.ownerId,
        retractedAt: DateTime.now(),
        reason: 'Correction',
      );
      expect(retractProtected, throwsStateError);
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.database.latestReconciliationId(business, 'bank'),
        completion.value,
      );
      expect(retractProtected, throwsStateError);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: singleStatement.value);
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('review-imported-statements')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('document-more-${singleStatement.value}')),
      );
      await tester.tap(
        find.byKey(ValueKey('document-more-${singleStatement.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('menu-Reconciliation History')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      final originalPicker = FilePickerPlatform.instance;
      final reportPicker = _ReportPicker(File('${dir.path}/report.html'));
      FilePickerPlatform.instance = reportPicker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final export = find.byKey(
        ValueKey('export-reconciliation-${completion.value}'),
      );
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(reportPicker.file.existsSync(), isFalse);
      reportPicker.cancel = false;
      await tester.runAsync(() async {
        await tester.tap(export);
      });
      final exported = find.text(
        'Reconciliation report saved. Open it in a browser to print.',
      );
      for (
        var attempt = 0;
        attempt < 250 && exported.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        reportPicker.file.readAsStringSync(),
        contains('Reconciliation Report'),
      );
      expect(reportPicker.file.readAsStringSync(), contains('Verified shop'));
      expect(reportPicker.mime, 'text/html');
      const previewPath = String.fromEnvironment('AUDYT_REPORT_PREVIEW');
      if (previewPath.isNotEmpty) {
        File(
          previewPath,
        ).writeAsStringSync(reportPicker.file.readAsStringSync(), flush: true);
      }
      expect(
        find.text(
          'Reconciliation report saved. Open it in a browser to print.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(ValueKey('reconciliation-evidence-${completion.value}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approved Transaction Evidence'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text('Verified shop'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('20-09-2026'), findsWidgets);
      final matchRows = tester.widgetList<AccountingInformationRows>(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.byType(AccountingInformationRows),
        ),
      );
      expect(
        matchRows.any(
          (table) =>
              table.rows.contains(('Journal', journal.entry.id.value)) &&
              table.rows.contains(('Journal Line', '2')),
        ),
        isTrue,
      );
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      expect(
        find.text('Opening bank statement reviewed; no outstanding items'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('reopen-reconciliation-${completion.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(
        workspace.database.latestReconciliationId(business, 'bank'),
        completion.value,
      );
      await tester.tap(
        find.byKey(ValueKey('reopen-reconciliation-${completion.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-reconciliation-reopening')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a reopening reason.'), findsOneWidget);
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('reconciliation-reopening-reason')),
        'Review bank evidence',
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-reconciliation-reopening')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reopened'), findsOneWidget);
      expect(find.text('Review bank evidence'), findsOneWidget);
      expect(
        find.byKey(ValueKey('reopen-reconciliation-${completion.value}')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        workspace.database.reconciliationHistory(
          EntityId.random(),
          singleStatement,
        ),
        isEmpty,
      );
      expect(
        workspace.database.latestReconciliationId(business, 'bank'),
        isNull,
      );
      retractProtected();
      final evidence = workspace.database.reconciliationEvidence(
        business,
        completion.value,
      );
      expect(evidence.matches.single.acceptanceId, matchId);
      expect(evidence.matches.single.statementRow.description, 'Verified shop');
      expect(
        evidence.matches.single.statementRow.amount,
        Money.fromMinor(-1000, 'MYR'),
      );
      expect(evidence.matches.single.journalId, journal.entry.id.value);
      expect(
        () => workspace.database.reconciliationEvidence(
          EntityId.random(),
          completion.value,
        ),
        throwsStateError,
      );
      expect(() => evidence.matches.clear(), throwsUnsupportedError);
      final audit = sqlite3.open(path);
      expect(audit.select('SELECT * FROM bank_reconciliations'), hasLength(1));
      expect(
        audit.select('SELECT * FROM bank_reconciliation_allocations'),
        hasLength(1),
      );
      expect(
        audit.select('SELECT * FROM bank_reconciliation_reopenings'),
        hasLength(1),
      );
      expect(
        () => audit.execute('DELETE FROM bank_reconciliations'),
        throwsA(isA<SqliteException>()),
      );
      audit.dispose();
      expect(await workspace.journals(), hasLength(2));
      workspace.dispose();
    },
  );
}

class _ReportPicker extends FilePickerPlatform {
  _ReportPicker(this.file);
  final File file;
  bool cancel = true;
  String? mime;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    mime = mimeType;
    if (cancel) return null;
    file.writeAsBytesSync(bytes, flush: true);
    return file.uri;
  }
}
