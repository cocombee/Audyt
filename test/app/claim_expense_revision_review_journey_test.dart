import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/presentation/claim_receipt_approval_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/approved_claim_expense_test.dart'
    show approve;
import '../features/accounting/data/claim_receipt_tax_test.dart'
    show fixture, Fixture;
import '../features/accounting/data/claim_expense_revision_posting_test.dart'
    as posting;
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap, capture;
import 'expense_revision_editor_journey_test.dart' show host, keyed;
import 'restored_page_routes_test.dart' show tables;

Future<void> namedAccounts(Fixture f) async {
  const names = {
    '5000': 'Business Service Costs',
    '1500': 'Office Equipment',
    '5100': 'Printing And Stationery',
    '2100': 'Claims Payable',
  };
  for (final stored in await f.w.accounts()) {
    final a = stored.account;
    final name = names[a.code];
    if (name == null) continue;
    await f.w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: a.id,
          code: a.code,
          name: name,
          type: a.type,
          status: a.status,
          isParent: a.isParent,
          isSystem: a.isSystem,
          parentId: a.parentId,
          openingBalance: a.openingBalance,
        ),
        metadata: stored.metadata.nextRevision(
          updatedAt: stored.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
    );
  }
}

Future<EntityId> journal(Fixture f) async {
  final id = EntityId.random();
  await f.w.database.save(
    StoredJournalEntry(
      entry: JournalEntry.draft(
        id: id,
        date: DateTime.utc(2026, 9, 14),
        memo: 'Exact current Claim Expense review',
        lines: [
          JournalLine.debit(
            accountId: f.accounts['5000']!,
            amount: Money.fromDecimal('109.08', 'MYR'),
          ),
          JournalLine.debit(
            accountId: f.accounts['1500']!,
            amount: Money.fromDecimal('20', 'MYR'),
          ),
          JournalLine.debit(
            accountId: f.accounts['5100']!,
            amount: Money.fromDecimal('54', 'MYR'),
          ),
          JournalLine.credit(
            accountId: f.accounts['2100']!,
            amount: Money.fromDecimal('183.08', 'MYR'),
          ),
        ],
      ),
      metadata: RecordMetadata.initial(
        recordId: id,
        businessId: f.w.identity.businessId,
        originDeviceId: f.w.identity.deviceId,
        createdAt: DateTime.now().toUtc(),
      ),
    ),
  );
  return id;
}

Future<void> selectRows(
  WidgetTester tester,
  Fixture f,
  EntityId root, {
  bool wrong = false,
}) async {
  final expense = (await f.w.expense(root))!;
  final accounts = (await f.w.accounts()).map((r) => r.account).toList();
  for (var i = 0; i < expense.draft.lines.length; i++) {
    final code = i == 0 && wrong ? '1500' : ['5000', '1500', '5100'][i];
    final account = accounts.singleWhere((a) => a.id == f.accounts[code]);
    await tap(
      tester,
      keyed('claim-expense-account-${expense.draft.lines[i].id}'),
    );
    await tap(tester, find.text(account.displayName).last);
  }
  final payable = tester.widget<AccountingSelector<EntityId>>(
    find.ancestor(
      of: keyed('claim-receipt-payable'),
      matching: find.byType(AccountingSelector<EntityId>),
    ),
  );
  expect(payable.value, f.accounts['2100']);
  expect(payable.enabled, isFalse);
  expect(keyed('claim-receipt-approval-cancel'), findsNothing);
  expect(find.text('Receipt 1 · Sample Supplier A'), findsNothing);
  // The mixed Inclusive third row stays 54.00, not a second tax uplift.
  expect(find.textContaining('Printing · RM 54.00'), findsWidgets);
  expect(
    tester.widget<FilledButton>(keyed('claim-receipt-approve')).onPressed,
    isNotNull,
  );
}

Future<void> edit(
  WidgetTester tester,
  EntityId root, {
  bool review = false,
  String? editorCapture,
}) async {
  await tap(tester, keyed('open-expense-${root.value}'));
  await tester.enterText(keyed('expense-field-amount'), '101');
  await tester.pumpAndSettle();
  if (editorCapture != null) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture(tester, editorCapture);
  }
  await tap(
    tester,
    keyed(review ? 'expense-save-review' : 'record-expense-save'),
  );
}

void main() {
  for (final scenario in [
    (720.0, false, false),
    (1162.0, false, false),
    (1224.0, true, false),
    (720.0, true, true),
  ]) {
    final (width, saveAndReview, paid) = scenario;
    testWidgets(
      '${paid ? 'paid' : 'current'} mixed Claim Expense ${saveAndReview ? 'Save And Review' : 'Review Saved Posting'} approves exact rows and survives restart at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        installFixedPopoutHost(tester);
        final dir = Directory.systemTemp.createTempSync(
          'claim-expense-review-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        final f = await fixture(path: path);
        await namedAccounts(f);
        var live = f.w;
        addTearDown(() => live.dispose());
        final root = approve(f);
        if (paid) {
          f.w.settleClaims(
            reviewedClaims: f.w.claims.all,
            requestId: EntityId.random(),
            bankAccountId: f.accounts['1000']!,
            paymentReference: 'ORIGINAL-PAID-CLAIM',
            paidAt: DateTime.utc(2026, 9, 17),
          );
        }
        final original = (await f.w.originalExpense(root))!.draft.toJson();
        final claim = f.w.claims.all.single.toJson();
        final draftJournal = await journal(f);
        await host(tester, f.w);
        await edit(
          tester,
          root,
          review: saveAndReview,
          editorCapture:
              '${paid ? 'Paid ' : ''}Claim Expense Current Editor ${width.toInt()}',
        );
        if (!saveAndReview) {
          await tap(tester, keyed('open-expense-${root.value}'));
          await tap(tester, keyed('review-expense-posting-${root.value}'));
        }
        expect(
          keyed('expense-journal-${draftJournal.value}'),
          findsOneWidget,
          reason:
              '${(await f.w.expense(root))!.summary.amount.toDecimalString()} / ${(await f.w.expense(root))!.summary.occurredOn} / ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().join(' | ')}',
        );
        await tap(tester, keyed('expense-journal-${draftJournal.value}'));
        expect(find.byType(ClaimReceiptApprovalDialog), findsOneWidget);
        expect(find.textContaining('183.08'), findsWidgets);
        expect(
          tester.widget<FilledButton>(keyed('claim-receipt-approve')).onPressed,
          isNull,
        );
        final current = (await f.w.expense(root))!.draft;
        final firstAccount = (await f.w.accounts())
            .singleWhere((a) => a.account.id == f.accounts['5000'])
            .account;
        await tap(
          tester,
          keyed('claim-expense-account-${current.lines.first.id}'),
        );
        await tap(tester, find.text(firstAccount.displayName).last);
        final partial = tables(f.w);
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
            '${paid ? 'Paid ' : ''}Current Claim Account Guard $dismissal ${width.toInt()}',
          );
          await tap(tester, find.text('Keep Editing'));
          expect(tables(f.w), partial);
          final payable = tester.widget<AccountingSelector<EntityId>>(
            find.ancestor(
              of: keyed('claim-receipt-payable'),
              matching: find.byType(AccountingSelector<EntityId>),
            ),
          );
          expect(payable.enabled, isFalse);
          expect(payable.value, f.accounts['2100']);
        }
        await selectRows(tester, f, root);
        await capture(
          tester,
          '${paid ? 'Paid ' : ''}Claim Expense Current Row Review ${width.toInt()}',
        );
        await tap(tester, keyed('claim-receipt-approve'));
        expect(find.byType(ClaimReceiptApprovalDialog), findsNothing);
        await capture(
          tester,
          '${paid ? 'Paid ' : ''}Claim Expense Current Journal Review ${width.toInt()}',
        );
        await tap(tester, keyed('approve-journal'));
        expect(tester.takeException(), isNull);
        expect(
          f.w.database
              .expenseRevisionPosting(f.w.identity.businessId, root)!
              .journalId,
          draftJournal,
        );
        expect((await f.w.expense(root))!.summary.pendingRevision, 0);
        expect(f.w.claims.all.single.toJson(), claim);
        expect((await f.w.originalExpense(root))!.draft.toJson(), original);
        expect(
          f.w
              .claimReimbursementPosition(
                claimId: f.w.claims.all.single.id,
                through: DateTime.utc(2027),
              )!
              .outstandingMinor,
          BigInt.from(paid ? 108 : 18308),
        );
        expect(await f.w.journals(), hasLength(paid ? 4 : 3));
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        live = await AccountingWorkspace.open(path);
        expect((await live.expense(root))!.summary.journalId, draftJournal);
        expect((await live.originalExpense(root))!.draft.toJson(), original);
        expect(live.claims.all.single.toJson(), claim);
        await host(tester, live);
        await tap(tester, keyed('open-expense-${root.value}'));
        expect(keyed('expense-add-line'), findsOneWidget);
        expect(keyed('review-expense-posting-${root.value}'), findsNothing);
      },
    );
  }

  for (final stale in [false, true]) {
    testWidgets(
      'current Claim Expense ${stale ? 'stale revision' : 'wrong row accounts'} rejects actual review approval atomically',
      (tester) async {
        await prepare(tester, 720);
        installFixedPopoutHost(tester);
        final f = await fixture();
        await namedAccounts(f);
        addTearDown(f.w.dispose);
        final root = approve(f);
        final original = (await f.w.originalExpense(root))!.draft.toJson();
        final draftJournal = await journal(f);
        await host(tester, f.w);
        await edit(tester, root, review: true);
        await tap(tester, keyed('expense-journal-${draftJournal.value}'));
        await selectRows(tester, f, root, wrong: !stale);
        await tap(tester, keyed('claim-receipt-approve'));
        if (stale) await posting.prepare(f, root, firstAmount: '102');
        await tap(tester, keyed('approve-journal'));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(
            stale ? 'revision changed' : 'exact row accounts',
          ),
          findsOneWidget,
        );
        expect(
          f.w.database.expenseRevisionPosting(f.w.identity.businessId, root),
          isNull,
        );
        expect(
          (await f.w.database.getById(draftJournal))!.entry.state,
          JournalEntryState.draft,
        );
        expect((await f.w.originalExpense(root))!.draft.toJson(), original);
        expect(
          f.w.database.activeClaimRecognitionId(
            f.w.identity.businessId,
            f.w.claims.all.single.id,
          ),
          root,
        );
        expect(
          (await f.w.expense(root))!.summary.pendingRevision,
          stale ? 2 : 1,
        );
      },
    );
  }
}
