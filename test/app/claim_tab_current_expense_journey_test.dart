import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/approved_claim_expense_test.dart'
    show approve;
import '../features/accounting/data/claim_expense_snapshot_test.dart'
    as snapshot;
import '../features/accounting/data/claim_receipt_tax_test.dart'
    show fixture, Fixture;
import '../support/fixed_popout_host.dart';
import 'claim_expense_editor_journey_test.dart'
    show identifiedClaim, maintainedBody;
import 'claim_expense_revision_review_journey_test.dart' show namedAccounts;
import 'claim_receipts_proposal_test.dart' show prepare, tap, capture;
import 'expense_revision_editor_journey_test.dart' show keyed;

Future<void> host(WidgetTester tester, AccountingWorkspace w) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ClaimsPage(
            store: w.claims,
            workspace: w,
            payeeStore: w.payees,
            receiptTaxProposal: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Object paymentFacts(AccountingWorkspace w) {
  final envelope = jsonDecode(
    w.database.exportDataArchive(w.identity.businessId, DateTime.utc(2027)),
  ) as Map;
  final tables =
      (jsonDecode(envelope['data'] as String) as Map)['tables'] as Map;
  return [tables['claim_settlements'], tables['claim_settlement_allocations']];
}

Future<(EntityId, Money)> reviewedJournal(Fixture f, EntityId root) async {
  final current = (await f.w.expense(root))!.draft;
  final json = current.toJson();
  (json['lines'] as List).first['amount'] = '101';
  final lines = (json['lines'] as List)
      .map(
        (l) => ExpenseDraftLine.fromJson(Map<String, dynamic>.from(l as Map)),
      )
      .toList();
  final codes = ['5000', '1500', '5100'];
  var total = Money.zero(current.currencyCode);
  final entries = <JournalLine>[];
  for (var i = 0; i < lines.length; i++) {
    final gross = current.lineCalculation(lines[i]).total;
    total += gross;
    entries.add(
      JournalLine.debit(accountId: f.accounts[codes[i]]!, amount: gross),
    );
  }
  entries.add(
    JournalLine.credit(accountId: f.accounts['2100']!, amount: total),
  );
  final id = EntityId.random();
  await f.w.database.save(
    StoredJournalEntry(
      entry: JournalEntry.draft(
        id: id,
        date: DateTime.utc(2026, 9, 14),
        memo: 'Fictional exact Claim-tab current correction',
        lines: entries,
      ),
      metadata: RecordMetadata.initial(
        recordId: id,
        businessId: f.w.identity.businessId,
        originDeviceId: f.w.identity.deviceId,
        createdAt: DateTime.now().toUtc(),
      ),
    ),
  );
  return (id, total);
}

void main() {
  for (final scenario in [
    (720.0, false, false),
    (1224.0, true, false),
    (720.0, true, true),
  ]) {
    final (width, modern, paid) = scenario;
    testWidgets(
      'Claim tab ${modern ? 'Expense-backed' : 'legacy receipt'} ${paid ? 'paid' : 'approved'} uses current Expense revisions and preserves original at $width',
      (tester) async {
        await prepare(tester, width);
        final previousHitWarning = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(
          () =>
              WidgetController.hitTestWarningShouldBeFatal = previousHitWarning,
        );
        installFixedPopoutHost(tester);
        final dir = Directory.systemTemp.createTempSync('claim-tab-current-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        final f = await fixture(path: path);
        await namedAccounts(f);
        var live = f.w;
        addTearDown(() => live.dispose());
        late EntityId root;
        if (modern) {
          final draft = maintainedBody(f);
          final submitted = f.w.claims.saveAndSubmit(identifiedClaim(f, draft));
          root = f.w.approveClaim(
            reviewedClaim: submitted,
            requestId: EntityId.random(),
            expenseLineAccounts: snapshot.accounts(f, draft),
            liabilityAccountId: f.accounts['2100']!,
            approvedAt: DateTime.utc(2026, 9, 15),
          );
        } else {
          root = approve(f);
        }
        if (paid) {
          f.w.settleClaims(
            reviewedClaims: f.w.claims.all,
            requestId: EntityId.random(),
            bankAccountId: f.accounts['1000']!,
            paymentReference: 'FICTIONAL-ORIGINAL',
            paidAt: DateTime.utc(2026, 9, 17),
          );
        }
        final claim = f.w.claims.all.single;
        final frozen = claim.toJson();
        final original = (await f.w.originalExpense(root))!.draft.toJson();
        final payments = paymentFacts(f.w);
        expect(
          f.w.database.currentClaimExpenseSummary(EntityId.random(), claim.id),
          isNull,
        );
        expect(
          f.w.database.currentClaimExpenseSummary(
            f.w.identity.businessId,
            EntityId.random(),
          ),
          isNull,
        );
        final (journal, total) = await reviewedJournal(f, root);
        await host(tester, f.w);
        await tap(tester, keyed('claim-edit-${claim.id}'));
        expect(
          tester
              .widget<RecordExpensePage>(find.byType(RecordExpensePage))
              .readOnly,
          isFalse,
        );
        expect(keyed('expense-approved-claimant'), findsOneWidget);
        expect(find.text(claim.claimantName), findsOneWidget);
        await tap(tester, keyed('expense-add-line'));
        expect(keyed('expense-line-3-amount'), findsOneWidget);
        await tap(tester, keyed('expense-remove-line-3'));
        expect(keyed('expense-line-3-amount'), findsNothing);
        await tester.enterText(keyed('expense-field-amount'), '101');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final label =
            '${paid
                ? 'Paid'
                : modern
                ? 'Expense-backed'
                : 'Legacy'} Claim Tab';
        await capture(tester, '$label Current Editor ${width.toInt()}');
        await tap(tester, keyed('record-expense-save'));
        expect(find.byType(RecordExpensePage), findsNothing);
        final current = f.w.database.currentClaimExpenseSummary(
          f.w.identity.businessId,
          claim.id,
        )!;
        expect(current.id, root);
        expect(current.amount, total);
        expect(current.hasPendingRevision, isTrue);
        final row = keyed('claim-row-${claim.id}');
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining(total.toDecimalString()),
          ),
          findsWidgets,
        );
        expect(f.w.claims.byId(claim.id)!.toJson(), frozen);
        expect((await f.w.originalExpense(root))!.draft.toJson(), original);
        expect(paymentFacts(f.w), payments);

        await tap(tester, keyed('claim-more-${claim.id}'));
        if (!paid) {
          await tap(tester, find.text('Original Submission').last);
        }
        expect(
          tester
              .widget<RecordExpensePage>(find.byType(RecordExpensePage))
              .readOnly,
          isTrue,
        );
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(keyed('expense-add-line'), findsNothing);
        await tap(tester, keyed('record-expense-cancel'));
        expect(f.w.claims.byId(claim.id)!.toJson(), frozen);
        await tap(tester, keyed('claim-edit-${claim.id}'));
        expect(
          tester
              .widget<TextFormField>(keyed('expense-field-amount'))
              .controller!
              .text,
          '101',
        );
        await tap(tester, keyed('review-expense-posting-${root.value}'));
        await tap(tester, keyed('expense-journal-${journal.value}'));
        final expense = (await f.w.expense(root))!;
        final accounts = (await f.w.accounts()).map((a) => a.account).toList();
        for (var i = 0; i < expense.draft.lines.length; i++) {
          await tap(
            tester,
            keyed('claim-expense-account-${expense.draft.lines[i].id}'),
          );
          final account = accounts.singleWhere(
            (a) => a.id == f.accounts[['5000', '1500', '5100'][i]],
          );
          await tap(tester, find.text(account.displayName).last);
        }
        expect(
          tester.widget<FilledButton>(keyed('claim-receipt-approve')).onPressed,
          isNotNull,
        );
        await capture(tester, '$label Current Review ${width.toInt()}');
        await tap(tester, keyed('claim-receipt-approve'));
        await tap(tester, keyed('approve-journal'));
        expect(
          f.w.database
              .currentClaimExpenseSummary(f.w.identity.businessId, claim.id)!
              .journalId,
          journal,
        );
        expect(
          f.w.database
              .currentClaimExpenseSummary(f.w.identity.businessId, claim.id)!
              .hasPendingRevision,
          isFalse,
        );
        expect(paymentFacts(f.w), payments);
        expect(f.w.claims.byId(claim.id)!.toJson(), frozen);
        expect((await f.w.originalExpense(root))!.draft.toJson(), original);
        expect(
          f.w
              .claimReimbursementPosition(
                claimId: claim.id,
                through: DateTime.utc(2027),
              )!
              .outstandingMinor,
          BigInt.from(paid ? 108 : total.minorUnits),
        );
        await tester.pumpWidget(const SizedBox());
        live.dispose();
        live = await AccountingWorkspace.open(path);
        await host(tester, live);
        await tap(tester, keyed('claim-edit-${claim.id}'));
        expect(
          tester
              .widget<RecordExpensePage>(find.byType(RecordExpensePage))
              .readOnly,
          isFalse,
        );
        expect(keyed('expense-add-line'), findsOneWidget);
        expect(
          live.database
              .currentClaimExpenseSummary(live.identity.businessId, claim.id)!
              .id,
          root,
        );
        expect(live.claims.byId(claim.id)!.toJson(), frozen);
        expect(paymentFacts(live), payments);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
