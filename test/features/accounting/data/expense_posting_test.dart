import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:flutter/material.dart';
import 'package:audyt/app/app.dart';

import 'dart:io';

import 'package:audyt/features/accounting/domain/expense_draft.dart';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  testWidgets(
    'expense posting atomically links exact reviewed journal and rejects duplicates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('expense-posting-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '5000',
        name: 'Supplies',
        type: AccountType.expense,
      );
      final accounts = await workspace.accounts();
      final cash = accounts
          .firstWhere((a) => a.account.code == '1000')
          .account
          .id;
      final cost = accounts
          .firstWhere((a) => a.account.code == '5000')
          .account
          .id;
      final expense = await workspace.saveExpenseIntake(draft());
      Future<JournalApproval> proposal(String amount) async {
        final existing = (await workspace.journals())
            .map((e) => e.entry.id)
            .toSet();
        await workspace.saveJournal(
          date: DateTime.utc(2026, 9, 13),
          memo: 'Reviewed expense',
          lines: [
            JournalLine.debit(
              accountId: cost,
              amount: Money.fromDecimal(amount, 'MYR'),
            ),
            JournalLine.credit(
              accountId: cash,
              amount: Money.fromDecimal(amount, 'MYR'),
            ),
          ],
        );
        final entry = (await workspace.journals()).singleWhere(
          (e) => !existing.contains(e.entry.id),
        );
        return JournalApproval(
          requestId: EntityId.random(),
          businessId: workspace.identity.businessId,
          journalId: entry.entry.id,
          expectedRevision: 1,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
          expenseIntakeId: expense,
        );
      }

      final wrong = await proposal('30');
      await expectLater(workspace.approveJournal(wrong), throwsStateError);
      expect((await workspace.expense(expense))!.summary.isPosted, isFalse);
      expect(
        (await workspace.database.getJournal(wrong.journalId))!.entry.state,
        JournalEntryState.draft,
      );
      final command = await proposal('25.50');
      final raw = sqlite3.open(path);
      raw.execute(
        "CREATE TRIGGER fail_expense_audit BEFORE INSERT ON ledger_audit BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END",
      );
      await expectLater(
        workspace.approveJournal(command),
        throwsA(isA<SqliteException>()),
      );
      expect((await workspace.expense(expense))!.summary.journalId, isNull);
      expect(
        (await workspace.database.getJournal(command.journalId))!.entry.state,
        JournalEntryState.draft,
      );
      expect(raw.select('SELECT * FROM journal_approvals'), isEmpty);
      raw.execute('DROP TRIGGER fail_expense_audit');
      raw.dispose();
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/expenses-vendors'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('open-expense-${expense.value}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('review-expense-posting-${expense.value}')),
      );
      await tester.tap(
        find.byKey(ValueKey('review-expense-posting-${expense.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('expense-journal-${command.journalId.value}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows,
        contains(('Payment Account', 'Cash')),
      );
      await tester.tap(find.byKey(const ValueKey('approve-journal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('open-expense-${expense.value}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('edit-expense-${expense.value}')),
        findsNothing,
      );
      final savedPosted = (await workspace.expense(expense))!;
      await expectLater(
        workspace.updateExpenseIntake(
          id: expense,
          expected: draft(),
          replacement: RecordExpenseDraft.fromJson({
            ...draft().toJson(),
            'amount': '99.00',
            'paymentAccountId': 'cash',
          }),
        ),
        throwsStateError,
      );
      expect(
        (await workspace.expense(expense))!.draft.toJson(),
        savedPosted.draft.toJson(),
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('view-expense-journal-${expense.value}')),
      );
      await tester.tap(
        find.byKey(ValueKey('view-expense-journal-${expense.value}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Posted Journal'), findsOneWidget);
      expect(find.byKey(const ValueKey('approve-journal')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(
        (await workspace.expense(expense))!.summary.journalId,
        command.journalId,
      );
      final duplicate = await proposal('25.50');
      await expectLater(workspace.approveJournal(duplicate), throwsStateError);
      expect(
        (await workspace.database.getJournal(duplicate.journalId))!.entry.state,
        JournalEntryState.draft,
      );
      expect(
        (await workspace.database.auditEvents(workspace.identity.businessId))
            .where((e) => e['kind'] == 'journal_posted'),
        hasLength(1),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      await tester.pumpWidget(AudytApp(workspace: workspace));
      await tester.pumpAndSettle();
      final home = tester.widget<AccountingHomePage>(
        find.byType(AccountingHomePage),
      );
      expect(home.data.status, AccountingHomeStatus.ready);
      expect(home.data.recentExpenses, hasLength(1));
      expect(home.data.recentExpenses.single.amount.minorUnits, 2550);
      final expectedYear = home.data.referenceDate.year == 2026 ? 2550 : 0;
      expect(home.data.expensesThisYear.minorUnits, expectedYear);
      await tester.pumpWidget(const SizedBox());

      expect(
        (await workspace.expense(expense))!.summary.journalId,
        command.journalId,
      );
      expect(
        (await workspace.database.getJournal(command.journalId))!.entry.state,
        JournalEntryState.posted,
      );
    },
  );
}
