import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/reconciliation_history_dialog.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/reconciliation_test_support.dart';
import '../support/accounting_text_input.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture;

Finder keyed(String key) => find.byKey(ValueKey(key));

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual reconciliation owners preserve custom scope and approval at $width',
      (tester) async {
        await prepare(tester, width);
        AccountingRecordPageSizes.reset();
        addTearDown(AccountingRecordPageSizes.reset);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
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
        final bank = accounts
            .singleWhere((a) => a.account.code == '1000')
            .account
            .id;
        final expense = accounts
            .singleWhere((a) => a.account.code == '5000')
            .account
            .id;
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
        await seedRecordedOpening(w, bank);
        await w.saveJournal(
          date: DateTime.utc(2026, 9, 2),
          memo: 'Fictional supplies payment',
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
        final journal = (await w.journals()).singleWhere(
          (j) => j.entry.state == JournalEntryState.draft,
        );
        await w.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: business,
            journalId: journal.entry.id,
            expectedRevision: journal.metadata.revision,
            actorId: w.identity.ownerId,
            approvedAt: journal.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        );
        final original = Uint8List.fromList(
          utf8.encode(
            'Date,Description,Amount\n2026-09-02,Fictional supplies payment,-10.00',
          ),
        );
        final statement = w.database.importBankStatement(
          id: EntityId.random(),
          businessId: business,
          paymentAccountId: 'bank',
          importedAt: DateTime.utc(2026, 9, 30),
          statement: BankStatementImport.csv(
            filename: 'Fictional September.csv',
            currency: 'MYR',
            bytes: original,
          ),
        );
        w.database.acceptStatementMatch(
          businessId: business,
          statementId: statement,
          sourceRow: 2,
          journalId: journal.entry.id,
          lineIndex: 1,
          actorId: w.identity.ownerId,
          acceptedAt: DateTime.utc(2026, 9, 30),
        );
        Widget form({bool embedded = false}) => StatementReconciliationDialog(
          workspace: w,
          statementId: statement,
          currency: 'MYR',
          embedded: embedded,
        );
        Future<void> host({bool embedded = false}) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                key: ValueKey(embedded),
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: embedded
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: form(embedded: true),
                          ),
                        )
                      : Builder(
                          builder: (context) => Column(
                            children: [
                              TextButton(
                                key: const ValueKey('open-statement'),
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => form(),
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

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> snap(String stem) async {
          expect(tester.takeException(), isNull);
          await capture(tester, '$stem ${width.toInt()}');
        }

        Future<void> close() => tap(find.bySemanticsLabel('Close').last);
        await host(embedded: true);
        expect(keyed('reconciliation-date-fields'), findsNothing);
        expect(keyed('reconciliation-balance-fields'), findsOneWidget);
        await snap('Reconciliation Embedded');
        await host();
        await tap(keyed('open-statement'));
        expect(keyed('reconciliation-date-fields'), findsOneWidget);
        Rect rect(String name) => tester.getRect(keyed(name));
        final start = rect('reconciliation-start');
        final end = rect('reconciliation-end');
        expect(end.top, start.top);
        expect(end.width, closeTo(start.width, .1));
        expect(end.left - start.right, closeTo(20, .1));
        final opening = rect('reconciliation-opening');
        final closing = rect('reconciliation-closing');
        expect(closing.top, closeTo(opening.top, .1));
        expect(closing.left - opening.right, closeTo(20, .1));
        expect(closing.width, closeTo(opening.width, .1));
        expect(find.text('Opening Balance (RM)'), findsOneWidget);
        expect(find.text('Closing Balance (RM)'), findsOneWidget);
        for (final key in [
          'reconciliation-opening',
          'reconciliation-closing',
        ]) {
          final decoration = tester.widget<TextField>(keyed(key)).decoration!;
          expect(decoration.prefixIcon, isNull);
          expect(decoration.prefixText, isNull);
        }
        final surface = tester.getRect(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byWidgetPredicate(
                  (w) => w is Material && w.type == MaterialType.card,
                ),
              )
              .first,
        );
        expect(surface.width, closeTo(528, .1));
        expect(opening.left - surface.left, closeTo(24, .1));
        expect(find.text('Cancel'), findsNothing);
        expect(
          tester.getRect(keyed('approve-reconciliation')).left,
          greaterThan(tester.getRect(keyed('save-reconciliation-draft')).right),
        );
        await snap('Reconciliation Dates');
        await tap(find.bySemanticsLabel('Help for Statement Start'));
        await snap('Reconciliation Date Help');
        await tap(keyed('reconciliation-opening'));
        await tester.enterText(keyed('reconciliation-start'), '01-09-2026');
        await tester.enterText(keyed('reconciliation-end'), '30-09-2026');
        await tester.enterText(keyed('reconciliation-opening'), '100.00');
        await tester.enterText(keyed('reconciliation-closing'), '91.00');
        await tap(keyed('review-reconciliation'));
        expect(
          tester.getRect(find.text('Opening Outstanding Items')).left,
          closeTo(
            tester
                    .getRect(keyed('reconciliation-opening-outstanding-card'))
                    .left +
                accountingContentInset,
            .1,
          ),
        );
        final balanceCheck = tester.widget<AccountingInformationRows>(
          keyed('reconciliation-balance-check'),
        );
        expect(balanceCheck.rows, [
          ('Balance Check Target', 'RM 0.00'),
          ('Statement Difference', 'RM 1.00'),
          ('Match Difference', 'RM 1.00'),
          ('Unmatched Rows', '0'),
        ]);
        expect(
          find.descendant(
            of: keyed('reconciliation-balance-check'),
            matching: find.text(':'),
          ),
          findsNWidgets(4),
        );
        expect(
          tester
              .widget<FilledButton>(keyed('approve-reconciliation'))
              .onPressed,
          isNull,
        );
        expect(w.database.isStatementReconciled(business, statement), isFalse);
        await snap('Reconciliation Difference Blocked');
        await tester.enterText(keyed('reconciliation-closing'), '90.00');
        await tap(keyed('review-reconciliation'));
        await snap('Reconciliation Ready');
        await tester.enterText(
          keyed('reconciliation-evidence'),
          'Fictional draft opening evidence.',
        );
        await tap(keyed('save-reconciliation-draft'));
        expect(keyed('reconciliation-draft-saved'), findsOneWidget);
        await snap('Reconciliation Draft Saved');
        await close();
        await tap(keyed('open-statement'));
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-opening'))
              .controller!
              .text,
          '100.00',
        );
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-closing'))
              .controller!
              .text,
          '90.00',
        );
        expect(
          tester
              .widget<FilledButton>(keyed('approve-reconciliation'))
              .onPressed,
          isNull,
        );
        await snap('Reconciliation Draft Resumed');
        await tap(keyed('review-reconciliation'));
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-evidence'))
              .controller!
              .text,
          'Fictional draft opening evidence.',
        );
        await tester.enterText(keyed('reconciliation-evidence'), '');
        await tap(keyed('approve-reconciliation'));
        expect(
          find.text(
            'Document the first opening balance and any outstanding items.',
          ),
          findsOneWidget,
        );
        await snap('Reconciliation Required Evidence');
        await tester.enterText(
          keyed('reconciliation-evidence'),
          'Fictional opening statement and recorded capital verified.',
        );
        await tap(keyed('approve-reconciliation'));
        expect(w.database.isStatementReconciled(business, statement), isTrue);
        expect(w.database.readReconciliationDraft(business, statement), isNull);
        expect(
          tester.widget<TextField>(keyed('reconciliation-opening')).readOnly,
          isTrue,
        );
        await snap('Reconciliation Approved');
        await close();
        await tap(keyed('open-history'));
        final approval = w.database
            .reconciliationHistory(business, statement)
            .single;
        await snap('Reconciliation History');
        await tap(keyed('reconciliation-evidence-${approval.id}'));
        expect(find.byType(TextField), findsNothing);
        expect(keyed('reconciliation-approved-balances'), findsOneWidget);
        await snap('Reconciliation Transaction Evidence');
        await close();
        await tap(keyed('reopen-reconciliation-${approval.id}'));
        expect(keyed('reconciliation-reopening-reason'), findsOneWidget);
        expect(find.byType(AccountingOrdinaryFields), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        final reasonFrame = tester.getRect(
          keyed('reconciliation-reopening-reason'),
        );
        final reasonSurface = tester.getRect(
          find
              .descendant(
                of: find.byType(AlertDialog).last,
                matching: find.byWidgetPredicate(
                  (w) => w is Material && w.type == MaterialType.card,
                ),
              )
              .first,
        );
        expect(reasonFrame.width, closeTo(420, .1));
        expect(reasonSurface.width, closeTo(468, .1));
        expect(reasonFrame.left - reasonSurface.left, closeTo(24, .1));
        expect(reasonSurface.right - reasonFrame.right, closeTo(24, .1));
        final reopen = tester.widget<FilledButton>(
          keyed('confirm-reconciliation-reopening'),
        );
        expect(
          reopen.style!.backgroundColor!.resolve({}),
          AccountingTheme.of(
            tester.element(keyed('confirm-reconciliation-reopening')),
          ).primary,
          reason: 'The sole positive popout action uses the existing green primary token.',
        );
        await snap('Reconciliation Reopen Reason');
        await close();
        expect(
          w.database
              .reconciliationHistory(business, statement)
              .single
              .reopenedAt,
          isNull,
        );
        expect(
          w.database.bankStatement(business, statement)!.sourceBytes,
          original,
        );
        // Exercise the actual reopen commit after verifying cancellation.
        final originalApproval = w.database.reconciliationReportSnapshot(
          business,
          approval.id,
        );
        await tap(keyed('reopen-reconciliation-${approval.id}'));
        await tap(keyed('confirm-reconciliation-reopening'));
        expect(find.text('Enter a reopening reason.'), findsOneWidget);
        expect(w.database.isStatementReconciled(business, statement), isTrue);
        await enterAccountingText(
          tester,
          keyed('reconciliation-reopening-reason'),
          'Review the original statement connection.',
        );
        await tap(keyed('confirm-reconciliation-reopening'));
        expect(w.database.isStatementReconciled(business, statement), isFalse);
        final reopened = w.database
            .reconciliationHistory(business, statement)
            .single;
        expect(
          reopened.reopeningReason,
          'Review the original statement connection.',
        );
        expect(reopened.reopenedAt, isNotNull);
        expect(originalApproval.approval.reopenedAt, isNull);
        expect(
          w.database.bankStatement(business, statement)!.sourceBytes,
          original,
        );
        expect(await w.journals(), hasLength(2));
        await snap('Reconciliation Reopened History');
        await close();

        // Reapprove the same retained statement after each explicit reopening.
        // Six real historical approvals must trigger the shared five-row footer.
        for (var revision = 1; revision < 6; revision++) {
          final snapshot = w.database.prepareStatementReconciliation(
            businessId: business,
            statementId: statement,
            startsOn: DateTime.utc(2026, 9, 1),
            endsOn: DateTime.utc(2026, 9, 30),
            openingBalance: Money.fromMinor(10000, 'MYR'),
            closingBalance: Money.fromMinor(9000, 'MYR'),
          );
          final request = EntityId.random();
          w.database.approveStatementReconciliation(
            requestId: request,
            businessId: business,
            statementId: statement,
            actorId: w.identity.ownerId,
            approvedAt: DateTime.now(),
            startsOn: snapshot.startsOn,
            endsOn: snapshot.endsOn,
            openingBalance: snapshot.openingBalance,
            closingBalance: snapshot.closingBalance,
            expectedAcceptanceIds: snapshot.acceptanceIds,
            expectedPreviousId: snapshot.previousId,
            firstOpeningEvidence: 'Original opening statement verified.',
          );
          if (revision < 5) {
            w.database.reopenStatementReconciliation(
              businessId: business,
              completionId: request.value,
              actorId: w.identity.ownerId,
              reopenedAt: DateTime.now(),
              reason: 'Fictional history pagination fixture.',
            );
          }
        }
        await tap(keyed('open-history'));
        final records = w.database.reconciliationHistory(business, statement);
        expect(records, hasLength(6));
        expect(find.byType(AccountingRecordList), findsOneWidget);
        expect(keyed('reconciliation-history-page-size'), findsOneWidget);
        expect(find.text('1–5 of 6'), findsOneWidget);
        for (final record in records.take(5)) {
          expect(keyed('reconciliation-evidence-${record.id}'), findsOneWidget);
        }
        expect(
          keyed('reconciliation-evidence-${records.last.id}'),
          findsNothing,
        );
        await snap('Reconciliation History Five Rows');
        await tap(keyed('reconciliation-history-page-next'));
        expect(find.text('6–6 of 6'), findsOneWidget);
        expect(
          keyed('reconciliation-evidence-${records.last.id}'),
          findsOneWidget,
        );
        await snap('Reconciliation History Last Page');
        await tap(keyed('reconciliation-history-page-size'));
        await tap(find.text('10').last);
        expect(find.text('1–6 of 6'), findsOneWidget);
        await close();
        await tap(keyed('open-history'));
        expect(find.text('1–6 of 6'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
