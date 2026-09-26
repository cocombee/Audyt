import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claim_receipt_approval_dialog.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_expense_snapshot_test.dart'
    show expenseBody;
import '../features/accounting/data/claim_receipt_tax_test.dart' show fixture;
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Claim page reviews every Expense row before atomic approval at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = await fixture();
        addTearDown(f.w.dispose);
        final draft = expenseBody(f);
        final claim = Claim.expense(
          id: EntityId.random(),
          draft: draft,
          claimantName: 'Fictional Registered Employee',
        );
        f.w.claims.saveAndSubmit(claim);
        final submitted = f.w.claims.byId(claim.id)!;
        final frozen = submitted.toJson();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ClaimsPage(store: f.w.claims, workspace: f.w),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> open() async {
          await tap(tester, find.byKey(ValueKey('claim-more-${claim.id}')));
          await tap(tester, find.byKey(ValueKey('claim-approve-${claim.id}')));
        }

        await open();
        final approve = find.byKey(const ValueKey('claim-receipt-approve'));
        expect(tester.widget<FilledButton>(approve).onPressed, isNull);
        // Leaving a partially reviewed dialog never saves a guessed account.
        await tap(
          tester,
          find
              .byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Close',
              )
              .last,
        );
        expect(f.w.claims.byId(claim.id)!.toJson(), frozen);
        expect(await f.w.journals(), isEmpty);
        await open();
        final ledger = (await f.w.accounts()).map((r) => r.account).toList();
        final codes = ['5000', '1500', '5100'];
        for (var i = 0; i < draft.lines.length; i++) {
          final account = ledger.singleWhere(
            (a) => a.id == f.accounts[codes[i]],
          );
          expect([
            AccountType.expense,
            AccountType.asset,
          ], contains(account.type));
          await tap(
            tester,
            find.byKey(ValueKey('claim-expense-account-${draft.lines[i].id}')),
          );
          expect(find.text('2100 · Claims Payable'), findsNothing);
          await tap(tester, find.text(account.displayName).last);
          expect(tester.widget<FilledButton>(approve).onPressed, isNull);
        }
        await tap(tester, find.byKey(const ValueKey('claim-receipt-payable')));
        final payable = ledger.singleWhere((a) => a.id == f.accounts['2100']);
        await tap(tester, find.text(payable.displayName).last);
        expect(tester.widget<FilledButton>(approve).onPressed, isNotNull);
        expect(find.byType(ClaimReceiptApprovalDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'Claim Expense Line Account Approval ${width.toInt()}',
        );
        await tap(tester, approve);
        expect(find.byType(ClaimReceiptApprovalDialog), findsNothing);
        final approved = f.w.claims.byId(claim.id)!;
        expect(approved.status, ClaimStatus.approved);
        expect(approved.expenseDraft!.toJson(), draft.toJson());
        expect(approved.receiptCostAllocations.keys.toSet(), {
          for (final c in codes) f.accounts[c]!,
        });
        final journals = await f.w.journals();
        expect(journals, hasLength(1));
        final expenses = await f.w.expenses();
        expect(expenses, hasLength(1));
        final linked = (await f.w.expense(expenses.single.id))!.draft;
        expect(
          linked.lines.map((l) => l.toJson()).toList(),
          draft.lines.map((l) => l.toJson()).toList(),
        );
        expect(linked.taxTotals!.total.minorUnits, 18632);
        expect(linked.claimSource!.claimantName, claim.claimantName);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
