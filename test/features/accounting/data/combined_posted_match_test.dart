import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'package:audyt/features/accounting/data/accounting_database.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'matching_window_test.dart' show postMovement;

EntityId importRow(
  AccountingWorkspace workspace,
  int amount, {
  String filename = 'Combine.csv',
}) => workspace.database.importBankStatement(
  id: EntityId.random(),
  businessId: workspace.identity.businessId,
  paymentAccountId: 'demo-bank',
  importedAt: DateTime.now(),
  statement: BankStatementImport.csv(
    filename: filename,
    currency: 'MYR',
    bytes: Uint8List.fromList(
      utf8.encode(
        'Date,Description,Amount,Reference\n2026-09-26,Combine customer payment,${(amount / 100).toStringAsFixed(2)},CMB-1',
      ),
    ),
  ),
);
void main() {
  test(
    'v33 upgrade preserves a single acceptance and enables combined matching',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-v33-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var workspace = await createDemoWorkspace(databasePath: path);
      addTearDown(() => workspace.dispose());
      final business = workspace.identity.businessId;
      final original = workspace.database
          .bankStatements(business, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.csv')
          .id;
      final candidate = workspace.database
          .statementMatchSuggestions(business, original)
          .first
          .candidates
          .first;
      workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: original,
        sourceRow: 2,
        journalId: candidate.journalId,
        lineIndex: candidate.lineIndex,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final acceptance = workspace.database.statementMatchAcceptanceId(
        business,
        original,
        2,
      )!;
      workspace.dispose();
      final legacy = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(legacy);
      removeExpenseRemovalSchema(legacy);
      legacy.execute('DROP TRIGGER bank_match_reserve_ledger');
      legacy.execute('DROP TABLE bank_match_active_ledger_members');
      legacy.execute('DROP TABLE bank_match_ledger_members');
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
      legacy.execute('PRAGMA user_version=33');
      legacy.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.database.acceptedStatementMatches(business, original)[2],
        candidate.movementId,
      );
      expect(
        workspace.database.statementMatchAcceptanceId(business, original, 2),
        acceptance,
      );
      expect(
        workspace.database.statementMatchLedgerMembers(business, acceptance),
        [candidate.movementId],
      );
      final bank = workspace.database.paymentLedgerAccount(
        business,
        'demo-bank',
      )!;
      final first = await postMovement(
        workspace,
        bank,
        DateTime.utc(2026, 9, 26),
        Money.fromMinor(20000, 'MYR'),
        'Upgrade payment 200',
      );
      final second = await postMovement(
        workspace,
        bank,
        DateTime.utc(2026, 9, 26),
        Money.fromMinor(30000, 'MYR'),
        'Upgrade payment 300',
      );
      final id = importRow(workspace, 50000);
      workspace.database.acceptStatementCombinedMatch(
        businessId: business,
        statementId: id,
        sourceRow: 2,
        movementIds: {first, second},
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final combined = workspace.database.statementMatchAcceptanceId(
        business,
        id,
        2,
      )!;
      expect(
        workspace.database
            .statementMatchLedgerMembers(business, combined)
            .toSet(),
        {first, second},
      );
      final upgraded = sqlite3.open(path);
      expect(
        upgraded.select('PRAGMA user_version').single['user_version'],
        LocalAccountingDatabase.schemaVersion,
      );
      expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
      upgraded.dispose();
    },
  );
  test('combined posted records persist, reserve every component, retract atomically', () async {
    final directory = Directory.systemTemp.createTempSync('audyt-combine-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/books.sqlite';
    var workspace = await createDemoWorkspace(databasePath: path);
    addTearDown(() => workspace.dispose());
    final business = workspace.identity.businessId;
    final bank = workspace.database.paymentLedgerAccount(
      business,
      'demo-bank',
    )!;
    final first = await postMovement(
      workspace,
      bank,
      DateTime.utc(2026, 9, 26),
      Money.fromMinor(20000, 'MYR'),
      'Combine payment 200',
    );
    final second = await postMovement(
      workspace,
      bank,
      DateTime.utc(2026, 9, 26),
      Money.fromMinor(30000, 'MYR'),
      'Combine payment 300',
    );
    final foreign = await postMovement(
      workspace,
      workspace.database.paymentLedgerAccount(business, 'demo-savings')!,
      DateTime.utc(2026, 9, 26),
      Money.fromMinor(30000, 'MYR'),
      'Combine other bank',
    );
    final id = importRow(workspace, 50000);
    void accept(Set<String> ids, {EntityId? actor}) =>
        workspace.database.acceptStatementCombinedMatch(
          businessId: business,
          statementId: id,
          sourceRow: 2,
          movementIds: ids,
          actorId: actor ?? workspace.identity.ownerId,
          acceptedAt: DateTime.utc(2026, 9, 26),
        );
    expect(() => accept({first, foreign}), throwsStateError);
    expect(
      () => accept({first, second}, actor: EntityId.random()),
      throwsStateError,
    );
    final wrong = await postMovement(
      workspace,
      bank,
      DateTime.utc(2026, 9, 26),
      Money.fromMinor(29999, 'MYR'),
      'Combine short by cent',
    );
    expect(() => accept({first, wrong}), throwsStateError);
    expect(workspace.database.statementMatchHistory(business, id), isEmpty);
    accept({first, second});
    final acceptance = workspace.database.statementMatchAcceptanceId(
      business,
      id,
      2,
    )!;
    accept({second, first}); // retry is idempotent
    expect(
      workspace.database.statementMatchHistory(business, id),
      hasLength(1),
    );
    expect(
      workspace.database
          .statementMatchLedgerMembers(business, acceptance)
          .toSet(),
      {first, second},
    );
    final single = importRow(
      workspace,
      20000,
      filename: 'Other transaction.csv',
    );
    final split = first.split(':');
    expect(
      () => workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: single,
        sourceRow: 2,
        journalId: EntityId.parse(split.first),
        lineIndex: int.parse(split.last),
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(
      workspace.database
          .statementMatchSearchCandidates(
            businessId: business,
            statementId: single,
            sourceRow: 2,
          )
          .map((item) => item.candidate.movementId),
      isNot(contains(first)),
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(
      workspace.database
          .statementMatchLedgerMembers(business, acceptance)
          .toSet(),
      {first, second},
    );
    final raw = sqlite3.open(path);
    expect(
      () => raw.execute(
        'DELETE FROM bank_match_ledger_members WHERE acceptance_id=?',
        [acceptance],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute(
        'DELETE FROM bank_match_active_ledger_members WHERE acceptance_id=?',
        [acceptance],
      ),
      throwsA(isA<SqliteException>()),
    );
    raw.dispose();
    workspace.database.retractStatementMatch(
      businessId: business,
      acceptanceId: acceptance,
      actorId: workspace.identity.ownerId,
      retractedAt: DateTime.now(),
      reason: 'Review found two separate payments',
    );
    expect(workspace.database.acceptedStatementMatches(business, id), isEmpty);
    expect(
      workspace.database
          .statementMatchLedgerMembers(business, acceptance)
          .toSet(),
      {first, second},
    );
    expect(
      workspace.database.statementMatchHistory(business, id).single.reason,
      'Review found two separate payments',
    );
    workspace.database.acceptStatementMatch(
      businessId: business,
      statementId: single,
      sourceRow: 2,
      journalId: EntityId.parse(split.first),
      lineIndex: int.parse(split.last),
      actorId: workspace.identity.ownerId,
      acceptedAt: DateTime.now(),
    );
    expect(
      workspace.database.acceptedStatementMatches(business, single)[2],
      first,
    );
  });

  test(
    'combined records reconcile and clear both actual ledger movements',
    () async {
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final business = workspace.identity.businessId;
      final bank = workspace.database.paymentLedgerAccount(
        business,
        'demo-bank',
      )!;
      final first = await postMovement(
        workspace,
        bank,
        DateTime.utc(2026, 9, 26),
        Money.fromMinor(20000, 'MYR'),
        'Approval payment 200',
      );
      final second = await postMovement(
        workspace,
        bank,
        DateTime.utc(2026, 9, 26),
        Money.fromMinor(30000, 'MYR'),
        'Approval payment 300',
      );
      final id = importRow(workspace, 50000);
      workspace.database.acceptStatementCombinedMatch(
        businessId: business,
        statementId: id,
        sourceRow: 2,
        movementIds: {first, second},
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final initial = workspace.database.prepareStatementReconciliation(
        businessId: business,
        statementId: id,
        startsOn: DateTime.utc(2026, 9, 26),
        endsOn: DateTime.utc(2026, 9, 26),
        openingBalance: Money.zero('MYR'),
        closingBalance: Money.fromMinor(50000, 'MYR'),
      );
      final opening = initial.recordedOpening;
      final snapshot = workspace.database.prepareStatementReconciliation(
        businessId: business,
        statementId: id,
        startsOn: DateTime.utc(2026, 9, 26),
        endsOn: DateTime.utc(2026, 9, 26),
        openingBalance: opening,
        closingBalance: opening + Money.fromMinor(50000, 'MYR'),
      );
      expect(snapshot.review.rowsAndBalancesAgree, isTrue);
      expect(snapshot.readyForApproval, isTrue);
      final completion = EntityId.random();
      workspace.database.approveStatementReconciliation(
        requestId: completion,
        businessId: business,
        statementId: id,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now(),
        startsOn: snapshot.startsOn,
        endsOn: snapshot.endsOn,
        openingBalance: snapshot.openingBalance,
        closingBalance: snapshot.closingBalance,
        expectedAcceptanceIds: snapshot.acceptanceIds,
        expectedPreviousId: null,
        firstOpeningEvidence:
            'Verified statement opening and both payment records',
      );
      final evidence = workspace.database.reconciliationEvidence(
        business,
        completion.value,
      );
      expect(evidence.matches, hasLength(1));
      expect(
        evidence.matches.single.combinedMovements
            .map((part) => part.candidate.movementId)
            .toSet(),
        {first, second},
      );
      final classification = workspace.database.reconciliationClassification(
        business,
        completion.value,
      )!;
      expect(
        classification.cleared.map((item) => item.id),
        containsAll([first, second]),
      );
      expect(classification.closingDifference.isZero, isTrue);
      expect(
        () => workspace.database.retractStatementMatch(
          businessId: business,
          acceptanceId: snapshot.acceptanceIds[2]!,
          actorId: workspace.identity.ownerId,
          retractedAt: DateTime.now(),
          reason: 'Blocked after approval',
        ),
        throwsStateError,
      );
    },
  );
}
