import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/approved_claim_expense_test.dart'
    show approve;
import '../features/accounting/data/claim_receipt_tax_test.dart' show fixture;
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('approved Claim edits the current Expense body at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      installFixedPopoutHost(tester);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final journal = approve(f);
      final saved = (await f.w.expense(journal))!;
      final frozen = saved.draft.toJson();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: ExpenseIntakePage(workspace: f.w, onRecordExpense: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey('open-expense-${journal.value}')));
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(ClaimEditorDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('expense-approved-claimant')),
        findsOneWidget,
      );
      expect(find.text(saved.draft.claimSource!.claimantName), findsWidgets);
      expect(
        find.byKey(const ValueKey('expense-tax-treatment')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-claim-liability-account')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('record-expense-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('expense-add-line')), findsOneWidget);
      for (var row = 1; row < saved.draft.lines.length; row++) {
        expect(
          find.byKey(ValueKey('expense-remove-line-$row')),
          findsOneWidget,
        );
      }
      final gridRight = tester
          .getRect(find.byKey(const ValueKey('expense-transaction-lines')))
          .right;
      for (var row = 0; row < saved.draft.lines.length; row++) {
        final amount = find.byKey(
          ValueKey(
            row == 0 ? 'expense-field-amount' : 'expense-line-$row-amount',
          ),
        );
        expect(
          tester.getRect(amount).right,
          lessThan(gridRight - 20),
          reason:
              'Current Amount reserves the original right-side action lane.',
        );
        final frame = find.descendant(
          of: amount,
          matching: find.byType(InputDecorator),
        );
        expect(frame, findsOneWidget);
        expect(
          tester.getRect(frame).right,
          lessThan(gridRight - 20),
          reason:
              'The painted field preserves its gap before the original action.',
        );
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'Approved Claim Editable Header ${width.toInt()}');
      final original = find.byKey(
        ValueKey(
          'expense-attachment-view-${saved.draft.attachments.single.originalId}',
        ),
      );
      await tester.ensureVisible(original);
      await tester.pumpAndSettle();
      expect(original, findsOneWidget);
      expect(find.text('Receipt 1'), findsNothing);
      await capture(
        tester,
        'Approved Claim Editable Receipts ${width.toInt()}',
      );
      expect((await f.w.expense(journal))!.draft.toJson(), frozen);
      final viewJournal = find.byKey(
        ValueKey('view-expense-journal-${journal.value}'),
      );
      final saveButton = find.byKey(const ValueKey('record-expense-save'));
      final button = tester.widget<FilledButton>(saveButton);
      final buttonContext = tester.element(saveButton);
      expect(
        button.style!.backgroundColor!.resolve({}),
        AccountingTheme.of(buttonContext).primary,
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        AccountingTheme.of(buttonContext).primaryForeground,
      );
      await tap(tester, viewJournal);
      expect(tester.takeException(), isNull);
      expect(await f.w.journals(), hasLength(1));
      Navigator.of(tester.element(find.byType(RecordExpensePage))).pop();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expense-field-amount')),
        '101',
      );
      await tap(tester, find.byKey(const ValueKey('record-expense-save')));
      expect(
        find.byType(RecordExpensePage),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .join(' | '),
      );
      final pending = (await f.w.expense(journal))!;
      expect(pending.summary.pendingRevision, 1);
      expect(pending.draft.taxTotals!.total.minorUnits, 18308);
      expect(pending.draft.amount, '183.08');
      expect(
        pending.draft.claimSource!.claimantName,
        saved.draft.claimSource!.claimantName,
      );
      expect(
        pending.draft.claimSource!.claimantId,
        saved.draft.claimSource!.claimantId,
      );
      expect(
        pending.draft.claimSource!.lineBases,
        saved.draft.claimSource!.lineBases,
      );
      await tap(tester, find.byKey(ValueKey('open-expense-${journal.value}')));
      await tap(tester, find.byKey(const ValueKey('expense-add-line')));
      await tap(tester, find.byKey(const ValueKey('expense-line-3-category')));
      await tap(tester, find.text('Office Operations').last);
      await tester.enterText(
        find.byKey(const ValueKey('expense-line-3-amount')),
        '5',
      );
      await tap(tester, find.byKey(const ValueKey('expense-tax-treatment')));
      await tap(tester, find.text('Tax Exclusive').last);
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-line-3-amount')),
      );
      await tester.pumpAndSettle();
      await capture(
        tester,
        'Approved Claim Editable Added Row ${width.toInt()}',
      );
      await tap(tester, find.byKey(const ValueKey('record-expense-save')));
      expect(find.byType(RecordExpensePage), findsNothing);
      final added = (await f.w.expense(journal))!;
      expect(added.draft.lines, hasLength(4));
      expect(added.draft.taxMode, 'Exclusive');
      expect(added.draft.taxTotals!.total.minorUnits, 19240);
      expect(added.draft.claimSource!.lineBases.values.toSet(), {'Exclusive'});
      await tap(tester, find.byKey(ValueKey('open-expense-${journal.value}')));
      await tap(tester, find.byKey(const ValueKey('expense-remove-line-3')));
      await tap(tester, find.byKey(const ValueKey('record-expense-save')));
      final removed = (await f.w.expense(journal))!;
      expect(removed.summary.pendingRevision, 3);
      expect(removed.draft.lines, hasLength(3));
      expect(removed.draft.taxTotals!.total.minorUnits, 18740);
      expect(
        removed.draft.claimSource!.claimantName,
        saved.draft.claimSource!.claimantName,
      );

      expect((await f.w.originalExpense(journal))!.draft.toJson(), frozen);
      expect(await f.w.journals(), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
