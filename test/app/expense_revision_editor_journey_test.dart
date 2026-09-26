import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import '../features/accounting/data/expense_revision_test.dart' show source;
import '../features/accounting/data/journal_editability_test.dart'
    show importPayment, completeImported, reopen;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap, capture;

Future<void> host(WidgetTester tester, AccountingWorkspace workspace) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ExpenseIntakePage(workspace: workspace, onRecordExpense: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder keyed(String key) => find.byKey(ValueKey(key));

void main() {
  for (final scenario in [(720.0, false), (1224.0, false), (720.0, true)]) {
    final (width, forced) = scenario;
    testWidgets(
      'posted Expense edits/adds/removes, saves, reviews and restarts at $width forced=$forced',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        final root = await source(f);
        if (forced) {
          f.w.savePreferences(
            f.w.preferences.change('Purchase Preferences', {'Show Rate': true}),
          );
        }
        await host(tester, f.w);
        await tap(tester, keyed('open-expense-${root.summary.id.value}'));
        expect(
          tester
              .widget<RecordExpensePage>(find.byType(RecordExpensePage))
              .readOnly,
          isFalse,
        );
        expect(keyed('expense-add-line'), findsOneWidget);
        final description = keyed('expense-field-item-or-split');
        await enterAccountingText(
          tester,
          description,
          '1. Corrected description with retained details\n2. Second retained paragraph',
        );
        await tester.enterText(keyed('expense-field-amount'), '12');
        await tester.pumpAndSettle();
        await tap(tester, keyed('expense-add-line'));
        expect(keyed('expense-line-1-amount'), findsOneWidget);
        await tap(tester, keyed('expense-remove-line-1'));
        expect(keyed('expense-line-1-amount'), findsNothing);
        await tester.ensureVisible(keyed('expense-field-amount'));
        await tester.pumpAndSettle();
        final amount = tester.getRect(keyed('expense-field-amount'));
        final add = tester.getRect(keyed('expense-add-line'));
        expect(add.left, greaterThan(amount.right));
        expect(
          add.right,
          lessThanOrEqualTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
          ),
        );
        expect(
          add.right,
          lessThanOrEqualTo(
            tester.getRect(keyed('expense-transaction-lines')).right + .1,
          ),
        );
        if (forced) {
          expect(keyed('expense-line-0-quantity'), findsOneWidget);
          expect(keyed('expense-line-0-rate'), findsOneWidget);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Expense Editable Lines ${width.toInt()}${forced ? ' Forced' : ''}',
        );
        await tap(tester, keyed('record-expense-save'));
        expect(find.byType(RecordExpensePage), findsNothing);
        final pending = (await f.w.expense(root.summary.id))!;
        expect(pending.summary.pendingRevision, 1);
        expect(pending.draft.lines.single.amount, '12');
        expect(
          pending.draft.lines.single.description,
          contains('Second retained paragraph'),
        );
        expect(
          (await f.w.originalExpense(root.summary.id))!.draft.toJson(),
          root.draft.toJson(),
        );
        expect(await f.w.journals(), hasLength(1));
        expect(
          f.w.database
              .readRecentPostedExpenseIntakes(
                businessId: f.business,
                through: DateTime.utc(2027),
              )
              .single
              .amount
              .minorUnits,
          1000,
        );
        expect(
          f.w.database
              .readExpenseIntakePage(businessId: f.business, posted: false)
              .records
              .single
              .id,
          root.summary.id,
        );
        final journal = await f.post(9, 2, -1200, approve: false);
        await tap(tester, keyed('open-expense-${root.summary.id.value}'));
        expect(
          tester
              .widget<TextFormField>(keyed('expense-field-amount'))
              .controller!
              .text,
          '12',
        );
        await tap(
          tester,
          keyed('review-expense-posting-${root.summary.id.value}'),
        );
        await tap(tester, keyed('expense-journal-${journal.value}'));
        await tap(tester, keyed('approve-journal'));
        expect(tester.takeException(), isNull);
        expect(
          f.w.database
              .expenseRevisionPosting(f.business, root.summary.id)!
              .journalId,
          journal,
        );
        expect(
          (await f.w.expense(root.summary.id))!.summary.pendingRevision,
          0,
        );
        expect(await f.w.journals(), hasLength(3));
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        expect(
          (await f.w.expense(root.summary.id))!.draft.toJson(),
          pending.draft.toJson(),
        );
        expect(
          (await f.w.originalExpense(root.summary.id))!.draft.toJson(),
          root.draft.toJson(),
        );
      },
    );
  }

  testWidgets(
    'late reconciliation rejects an open editor save, locks reopen, and releases on reopening',
    (tester) async {
      await prepare(tester, 720);
      installFixedPopoutHost(tester);
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final root = await source(f);
      await host(tester, f.w);
      await tap(tester, keyed('open-expense-${root.summary.id.value}'));
      await tester.enterText(keyed('expense-field-amount'), '12');
      final statement = importPayment(f);
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: root.summary.journalId!,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final completion = completeImported(f, statement);
      await tap(tester, keyed('record-expense-save'));
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(f.w.expenseRevision(root.summary.id), isNull);
      expect(find.textContaining('reconciliation'), findsWidgets);
      Navigator.of(tester.element(find.byType(RecordExpensePage))).pop();
      await tester.pumpAndSettle();
      await tap(tester, keyed('open-expense-${root.summary.id.value}'));
      expect(
        tester
            .widget<RecordExpensePage>(find.byType(RecordExpensePage))
            .readOnly,
        isTrue,
      );
      expect(keyed('expense-add-line'), findsNothing);
      Navigator.of(tester.element(find.byType(RecordExpensePage))).pop();
      await tester.pumpAndSettle();
      reopen(f, completion);
      await tap(tester, keyed('open-expense-${root.summary.id.value}'));
      expect(
        tester
            .widget<RecordExpensePage>(find.byType(RecordExpensePage))
            .readOnly,
        isFalse,
      );
      expect(keyed('expense-add-line'), findsOneWidget);
      await tester.enterText(keyed('expense-field-amount'), '12');
      await tap(tester, keyed('record-expense-save'));
      expect((await f.w.expense(root.summary.id))!.draft.amount, '12.00');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
