import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/reconciliation_history_dialog.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/reconciliation_test_support.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture;

Finder keyed(String key) => find.byKey(ValueKey(key));

Future<
  ({
    AccountingWorkspace w,
    EntityId statement,
    Money opening,
    Uint8List original,
  })
>
fixture(int openingCount, {String path = ':memory:'}) async {
  final w = await AccountingWorkspace.open(path);
  await w.createAccount(
    code: '1000',
    name: 'Fictional Bank',
    type: AccountType.asset,
  );
  await w.createAccount(
    code: '5000',
    name: 'Fictional Supplies',
    type: AccountType.expense,
  );
  final accounts = await w.accounts();
  final bank = accounts.singleWhere((a) => a.account.code == '1000').account.id;
  final expense = accounts
      .singleWhere((a) => a.account.code == '5000')
      .account
      .id;
  await seedRecordedOpening(w, bank);
  final equity = (await w.accounts())
      .singleWhere((a) => a.account.code == '3000')
      .account
      .id;
  Future<EntityId> post(
    DateTime date,
    String memo,
    List<JournalLine> lines,
  ) async {
    await w.saveJournal(date: date, memo: memo, lines: lines);
    final draft = (await w.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: draft.entry.id,
        expectedRevision: draft.metadata.revision,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.now(),
      ),
    );
    return draft.entry.id;
  }

  for (var i = 1; i < openingCount; i++) {
    await post(DateTime.utc(2026, 8, 31), 'Fictional opening $i', [
      JournalLine.debit(accountId: bank, amount: Money.fromMinor(100, 'MYR')),
      JournalLine.credit(
        accountId: equity,
        amount: Money.fromMinor(100, 'MYR'),
      ),
    ]);
  }
  final journal = await post(
    DateTime.utc(2026, 9, 2),
    'Fictional statement payment',
    [
      JournalLine.debit(
        accountId: expense,
        amount: Money.fromMinor(1000, 'MYR'),
      ),
      JournalLine.credit(accountId: bank, amount: Money.fromMinor(1000, 'MYR')),
    ],
  );
  w.savePaymentAccount(
    PaymentAccount.create(
      id: 'bank',
      name: 'Fictional Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    ),
  );
  final business = w.identity.businessId;
  w.database.linkPaymentLedgerAccount(business, 'bank', bank);
  final original = Uint8List.fromList(
    utf8.encode(
      'Date,Description,Amount\n2026-09-02,Fictional statement payment,-10.00',
    ),
  );
  final statement = w.database.importBankStatement(
    id: EntityId.random(),
    businessId: business,
    paymentAccountId: 'bank',
    importedAt: DateTime.now(),
    statement: BankStatementImport.csv(
      filename: 'Fictional statement.csv',
      currency: 'MYR',
      bytes: original,
    ),
  );
  w.database.acceptStatementMatch(
    businessId: business,
    statementId: statement,
    sourceRow: 2,
    journalId: journal,
    lineIndex: 1,
    actorId: w.identity.ownerId,
    acceptedAt: DateTime.now(),
  );
  return (
    w: w,
    statement: statement,
    opening: Money.fromMinor(10000 + (openingCount - 1) * 100, 'MYR'),
    original: original,
  );
}

Future<void> host(
  WidgetTester tester,
  AccountingWorkspace w,
  EntityId statement,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: const ValueKey('open-form'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => StatementReconciliationDialog(
                      workspace: w,
                      statementId: statement,
                      currency: 'MYR',
                    ),
                  ),
                  child: const Text('Review statement'),
                ),
                TextButton(
                  key: const ValueKey('open-history'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ReconciliationHistoryDialog(
                      workspace: w,
                      statementId: statement,
                    ),
                  ),
                  child: const Text('Reconciliation history'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'opening checklist uses shared five-row controls and preserves selection at $width',
      (tester) async {
        await prepare(tester, width);
        AccountingRecordPageSizes.reset();
        addTearDown(AccountingRecordPageSizes.reset);
        final f = await fixture(6);
        addTearDown(f.w.dispose);
        final business = f.w.identity.businessId;
        final snapshot = f.w.database.prepareStatementReconciliation(
          businessId: business,
          statementId: f.statement,
          startsOn: DateTime.utc(2026, 9, 1),
          endsOn: DateTime.utc(2026, 9, 30),
          openingBalance: f.opening,
          closingBalance: Money.fromMinor(f.opening.minorUnits - 1000, 'MYR'),
        );
        expect(snapshot.openingMovements, hasLength(6));
        await host(tester, f.w, f.statement);
        Future<void> review() async {
          await tap(tester, keyed('open-form'));
          await tester.enterText(keyed('reconciliation-start'), '01-09-2026');
          await tester.enterText(keyed('reconciliation-end'), '30-09-2026');
          await tester.enterText(keyed('reconciliation-opening'), '105.00');
          await tester.enterText(keyed('reconciliation-closing'), '95.00');
          await tap(tester, keyed('review-reconciliation'));
        }

        await review();
        expect(find.text('1–5 of 6'), findsOneWidget);
        expect(keyed('reconciliation-opening-items-page-size'), findsOneWidget);
        for (final item in snapshot.openingMovements.take(5)) {
          expect(keyed('opening-outstanding-${item.id}'), findsOneWidget);
        }
        final last = snapshot.openingMovements.last;
        expect(keyed('opening-outstanding-${last.id}'), findsNothing);
        await tap(tester, keyed('reconciliation-opening-items-page-next'));
        expect(find.text('6–6 of 6'), findsOneWidget);
        await tap(tester, keyed('opening-outstanding-${last.id}'));
        expect(
          tester
              .widget<Checkbox>(keyed('opening-outstanding-${last.id}'))
              .value,
          isTrue,
        );
        await capture(
          tester,
          'Reconciliation Opening Last Item ${width.toInt()}',
        );
        await tap(tester, keyed('reconciliation-opening-items-page-previous'));
        await tap(tester, keyed('reconciliation-opening-items-page-next'));
        expect(
          tester
              .widget<Checkbox>(keyed('opening-outstanding-${last.id}'))
              .value,
          isTrue,
        );
        await tap(tester, keyed('save-reconciliation-draft'));
        expect(
          f.w.database
              .readReconciliationDraft(business, f.statement)!
              .openingOutstandingIds,
          {last.id},
        );
        await tap(tester, keyed('reconciliation-opening-items-page-size'));
        await tap(tester, find.text('10').last);
        expect(find.text('1–6 of 6'), findsOneWidget);
        await tap(tester, find.bySemanticsLabel('Close').last);
        await tap(tester, keyed('open-form'));
        await tap(tester, keyed('review-reconciliation'));
        expect(find.text('1–6 of 6'), findsOneWidget);
        expect(
          tester
              .widget<Checkbox>(keyed('opening-outstanding-${last.id}'))
              .value,
          isTrue,
        );
        expect(
          f.w.database.bankStatement(business, f.statement)!.sourceBytes,
          f.original,
        );
        expect(await f.w.journals(), hasLength(7));
        await capture(
          tester,
          'Reconciliation Opening Retained Selection ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'approved evidence keeps all preserved facts reachable without parallel pagination at $width',
      (tester) async {
        await prepare(tester, width);
        final f = await fixture(22);
        addTearDown(f.w.dispose);
        final business = f.w.identity.businessId;
        final snapshot = f.w.database.prepareStatementReconciliation(
          businessId: business,
          statementId: f.statement,
          startsOn: DateTime.utc(2026, 9, 1),
          endsOn: DateTime.utc(2026, 9, 30),
          openingBalance: f.opening,
          closingBalance: Money.fromMinor(f.opening.minorUnits - 1000, 'MYR'),
        );
        final request = EntityId.random();
        f.w.database.approveStatementReconciliation(
          requestId: request,
          businessId: business,
          statementId: f.statement,
          actorId: f.w.identity.ownerId,
          approvedAt: DateTime.now(),
          startsOn: snapshot.startsOn,
          endsOn: snapshot.endsOn,
          openingBalance: snapshot.openingBalance,
          closingBalance: snapshot.closingBalance,
          expectedAcceptanceIds: snapshot.acceptanceIds,
          expectedPreviousId: snapshot.previousId,
          firstOpeningEvidence: 'Fictional bank opening statement reviewed.',
        );
        final preserved = f.w.database.reconciliationReportSnapshot(
          business,
          request.value,
        );
        expect(preserved.ledger!.movements, hasLength(23));
        await host(tester, f.w, f.statement);
        await tap(tester, keyed('open-history'));
        await tap(tester, keyed('reconciliation-evidence-${request.value}'));
        expect(find.text('Approved Transaction Evidence'), findsOneWidget);
        expect(find.byType(AccountingRecordPagination), findsNothing);
        expect(find.text('Next'), findsNothing);
        expect(find.text('Previous'), findsNothing);
        for (final item in preserved.ledger!.movements) {
          expect(
            find.text('31-08-2026 · ${item.memo}').evaluate().isNotEmpty ||
                find.text('02-09-2026 · ${item.memo}').evaluate().isNotEmpty,
            isTrue,
            reason:
                'Preserved ledger movement ${item.id} must remain in the scrollable evidence.',
          );
        }
        await capture(
          tester,
          'Reconciliation All Evidence Top ${width.toInt()}',
        );
        final acceptance = find.text(
          preserved.evidence.matches.single.acceptanceId,
        );
        await tester.ensureVisible(acceptance);
        await tester.pumpAndSettle();
        expect(acceptance, findsOneWidget);
        await capture(
          tester,
          'Reconciliation All Evidence Bottom ${width.toInt()}',
        );
        final after = f.w.database.reconciliationReportSnapshot(
          business,
          request.value,
        );
        expect(after.evidence.sourceDigest, preserved.evidence.sourceDigest);
        expect(
          after.ledger!.movements.map((m) => m.id),
          preserved.ledger!.movements.map((m) => m.id),
        );
        expect(
          f.w.database.bankStatement(business, f.statement)!.sourceBytes,
          f.original,
        );
        expect(await f.w.journals(), hasLength(23));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
