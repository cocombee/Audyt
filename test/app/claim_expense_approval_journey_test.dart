import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claim_receipt_approval_dialog.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_expense_snapshot_test.dart'
    show expenseBody;
import '../features/accounting/data/claim_receipt_tax_test.dart' show fixture;
import '../support/fixed_popout_host.dart';
import '../support/accounting_test_finders.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    testWidgets(
      'actual Claim page reviews every Expense row before atomic approval at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
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
        for (var i = 0; i < draft.lines.length; i++) {
          final frame = find.byKey(
            ValueKey('claim-expense-account-${draft.lines[i].id}'),
          );
          await tester.ensureVisible(frame);
          await tester.pumpAndSettle();
          final titles = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data?.startsWith('Line ${i + 1} · ') == true &&
                widget.style?.fontWeight == FontWeight.w600,
          );
          expect(titles, findsOneWidget);
          expect(
            tester.getTopLeft(titles).dx,
            closeTo(tester.getTopLeft(frame).dx, .1),
          );
        }
        final payableFrame = find.byKey(
          const ValueKey('claim-receipt-payable'),
        );
        await tester.ensureVisible(payableFrame);
        await tester.pumpAndSettle();
        expectPopupFieldTitleAligned(
          tester,
          'Claims Payable Account',
          payableFrame,
        );
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
        final first = ledger.singleWhere((a) => a.id == f.accounts['5000']);
        await tap(
          tester,
          find.byKey(ValueKey('claim-expense-account-${draft.lines.first.id}')),
        );
        await tap(tester, find.text(first.displayName).last);
        final partialTables = tables(f.w);
        for (final dismissal in ['Close', 'Escape', 'Backdrop']) {
          if (dismissal == 'Close') {
            await tap(tester, find.byType(AccountingCloseIcon).last);
          } else if (dismissal == 'Escape') {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(8, 200));
            await tester.pumpAndSettle();
          }
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await capture(
            tester,
            'Claim Expense Account Guard $dismissal ${width.toInt()}',
          );
          await tap(tester, find.text('Keep Editing'));
          final selector = tester.widget<AccountingSelector<EntityId>>(
            find.ancestor(
              of: find.byKey(
                ValueKey('claim-expense-account-${draft.lines.first.id}'),
              ),
              matching: find.byType(AccountingSelector<EntityId>),
            ),
          );
          expect(selector.value, first.id);
          expect(tables(f.w), partialTables);
        }
        await tap(tester, find.byType(AccountingCloseIcon).last);
        await tap(tester, find.text('Discard'));
        expect(tables(f.w), partialTables);
        await open();
        expect(find.text(first.displayName), findsNothing);
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

    testWidgets(
      'actual receipt-only Claim review guards payable choice at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        installFixedPopoutHost(tester);
        final f = await fixture();
        addTearDown(f.w.dispose);
        final claim = f.claim();
        f.w.claims.saveAndSubmit(claim);
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
        await tap(tester, find.byType(AccountingCloseIcon).last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        await open();
        final payable = (await f.w.accounts())
            .singleWhere((a) => a.account.id == f.accounts['2100'])
            .account;
        await tap(tester, find.byKey(const ValueKey('claim-receipt-payable')));
        await tap(tester, find.text(payable.displayName).last);
        final before = tables(f.w);
        for (final dismissal in ['Close', 'Escape', 'Backdrop']) {
          if (dismissal == 'Close') {
            await tap(tester, find.byType(AccountingCloseIcon).last);
          } else if (dismissal == 'Escape') {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(8, 200));
            await tester.pumpAndSettle();
          }
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await capture(
            tester,
            'Claim Receipt Payable Guard $dismissal ${width.toInt()}',
          );
          await tap(tester, find.text('Keep Editing'));
          expect(tables(f.w), before);
        }
        await tap(tester, find.byType(AccountingCloseIcon).last);
        await tap(tester, find.text('Discard'));
        expect(tables(f.w), before);
        await open();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('claim-receipt-approve')),
              )
              .onPressed,
          isNull,
        );
        await tap(tester, find.byKey(const ValueKey('claim-receipt-payable')));
        await tap(tester, find.text(payable.displayName).last);
        await tap(tester, find.byKey(const ValueKey('claim-receipt-approve')));
        expect(f.w.claims.byId(claim.id)!.status, ClaimStatus.approved);
        expect(await f.w.journals(), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
