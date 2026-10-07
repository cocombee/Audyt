import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/field_row_trial.dart';

import '../../app/claim_receipts_proposal_test.dart' show prepare;
import '../../support/accounting_test_finders.dart';
import '../../app/journal_workspace_integration_test.dart' show captureUi;
import '../../app/restored_page_routes_test.dart' show tables;

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    testWidgets(
      'operational approval reviews accounts and posts a journal at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        final dir = Directory.systemTemp.createTempSync('claim-ui-');
        final w = await AccountingWorkspace.open('${dir.path}/books.sqlite');
        addTearDown(() {
          w.dispose();
          dir.deleteSync(recursive: true);
        });
        await w.createAccount(
          code: '5000',
          name: 'Office Expense',
          type: AccountType.expense,
        );
        await w.createAccount(
          code: '2100',
          name: 'Claims Payable',
          type: AccountType.liability,
        );
        await w.createAccount(
          code: '1000',
          name: 'Bank',
          type: AccountType.asset,
        );
        w.savePaymentAccount(
          PaymentAccount.create(
            id: 'claim-bank',
            name: 'Bank',
            type: PaymentAccountType.bank,
            currencyCode: 'MYR',
          ),
        );
        w.database.linkPaymentLedgerAccount(
          w.identity.businessId,
          'claim-bank',
          (await w.accounts())
              .singleWhere((a) => a.account.code == '1000')
              .account
              .id,
        );
        final claim = ClaimStore.demo().all.first;
        w.claims.saveDraft(claim);
        w.claims.submit(claim.id);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ClaimsPage(store: w.claims, workspace: w),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('claim-approve-${claim.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
        expect(
          find.text(
            'Review the ledger accounts before posting. Create missing accounts in Chart of Accounts.',
          ),
          findsNothing,
        );
        expect(await w.journals(), isEmpty);
        await captureUi(tester, 'Claim Posting Accounts ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('claim-posting-account-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5000 · Office Expense').last);
        await tester.pumpAndSettle();
        final partialTables = tables(w);
        for (final dismissal in ['Close', 'Escape', 'Backdrop']) {
          if (dismissal == 'Close') {
            await tester.tap(find.byType(AccountingCloseIcon).last);
          } else if (dismissal == 'Escape') {
            await tester.tap(
              find.byKey(const ValueKey('claim-posting-account-0')),
            );
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            // Escape first closes the open selector, preserving its choice.
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tapAt(const Offset(8, 200));
          }
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await captureUi(
            tester,
            'Claim Account Guard $dismissal ${width.toInt()}',
          );
          await tester.tap(find.text('Keep Editing'));
          await tester.pumpAndSettle();
          expect(find.text('5000 · Office Expense'), findsOneWidget);
          expect(tables(w), partialTables);
        }
        await tester.tap(find.byType(AccountingCloseIcon).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(tables(w), partialTables);
        await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('claim-approve-${claim.id}')));
        await tester.pumpAndSettle();
        expect(find.text('5000 · Office Expense'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('claim-posting-account-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5000 · Office Expense').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('claim-posting-account-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2100 · Claims Payable').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(w.claims.byId(claim.id)!.status, ClaimStatus.approved);
        expect(await w.journals(), hasLength(1));
        await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('claim-pay-${claim.id}')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('claim-payment-ordinary-fields')),
          findsOneWidget,
        );
        expectPopupFieldTitleAligned(
          tester,
          'Payment Account',
          find.byKey(const ValueKey('claim-payment-account')),
        );
        await captureUi(tester, 'Claim Payment Account ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('claim-payment-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bank · Bank · RM').last);
        await tester.pumpAndSettle();
        final approvedTables = tables(w);
        await tester.tapAt(const Offset(8, 200));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await captureUi(tester, 'Claim Payment Account Dirty ${width.toInt()}');
        await tester.tap(find.text('Keep Editing'));
        await tester.pumpAndSettle();
        expect(find.text('Bank · Bank · RM'), findsOneWidget);
        expect(tables(w), approvedTables);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('claims-batch-ordinary-fields')),
          findsOneWidget,
        );
        final reference = tester.widget<TextField>(
          find.byKey(const ValueKey('claims-batch-reference')),
        );
        expect(reference.decoration!.labelText, isNull);
        expect(
          find.text(
            'Record reimbursements already made. Each claim retains its category and receipt. Different recipients remain separate; no bank transfer is sent.',
          ),
          findsNothing,
        );
        expect(find.byType(AccountingFieldHelp), findsOneWidget);
        expectPopupFieldTitleAligned(
          tester,
          'Payment Reference',
          find.byKey(const ValueKey('claims-batch-reference')),
        );
        await captureUi(tester, 'Claim Payment Reference ${width.toInt()}');
        await tester.tap(
          find.descendant(
            of: find.byType(AccountingFieldHelp),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('no bank transfer is sent.'),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Claim Payment Reference Help ${width.toInt()}',
        );
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('claims-batch-reference')),
          'UI-PAYMENT-001',
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await captureUi(
          tester,
          'Claim Payment Reference Dirty ${width.toInt()}',
        );
        await tester.tap(find.text('Keep Editing'));
        await tester.pumpAndSettle();
        expect(find.text('UI-PAYMENT-001'), findsOneWidget);
        expect(tables(w), approvedTables);
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(tables(w), approvedTables);
        await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('claim-pay-${claim.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('claim-payment-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bank · Bank · RM').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('claims-batch-reference')),
          'UI-PAYMENT-001',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('claims-batch-confirm')));
        await tester.pumpAndSettle();
        expect(w.claims.byId(claim.id)!.status, ClaimStatus.paid);
        expect(w.claims.byId(claim.id)!.paymentReference, 'UI-PAYMENT-001');
        expect(await w.journals(), hasLength(2));

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
