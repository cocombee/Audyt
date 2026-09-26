import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;
import '../support/fixed_popout_host.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Expense plus exactly one Claimant line at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      tester.view.physicalSize = Size(width, 1800);
      installFixedPopoutHost(tester);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      String? claimant = 'employee-a';
      Widget host({required bool claim}) => RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => StatefulBuilder(
                    builder: (context, update) => RecordExpensePage(
                      includeTopSafeArea: false,
                      preferences: workspace.preferences,
                      settingsWorkspace: workspace,
                      payeeStore: workspace.payees,
                      accounts: workspace.paymentAccounts,
                      onCancel: () => Navigator.pop(dialogContext),
                      claimantField: !claim
                          ? null
                          : Column(
                              key: const ValueKey('claimant-extra-line'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                accountingFieldLabel(
                                  context,
                                  'Claimant *',
                                  alignToField: true,
                                ),
                                const SizedBox(height: accountingFieldLabelGap),
                                AccountingSelector<String>(
                                  controlKey: const ValueKey(
                                    'claimant-one-line-selector',
                                  ),
                                  hintText: 'Select Claimant',
                                  assignedWidth: double.infinity,
                                  value: claimant,
                                  options: const [
                                    AccountingSelectorOption(
                                      value: 'employee-a',
                                      label: 'Aina Rahman',
                                    ),
                                    AccountingSelectorOption(
                                      value: 'employee-b',
                                      label: 'Daniel Lim',
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      update(() => claimant = value),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final fields = [
        'expense-field-payee',
        'expense-document-number',
        'expense-field-date',
        'expense-field-payment-account',
        'expense-tax-treatment',
        'expense-field-category',
        'expense-field-item-or-split',
        'expense-field-tax',
        'expense-field-amount',
        'expense-field-notes',
      ];
      // Guard the initial label layout axis before row edits. Painted native
      // heading alignment still requires separate installed inspection.
      void expectAmountHeadingAxis() {
        final heading = tester.getRect(find.text('Amount (RM)').first);
        final amount = tester.getRect(
          find.byKey(const ValueKey('expense-field-amount')),
        );
        final tax = tester.getRect(find.text('Tax').first);
        expect(heading.right, closeTo(amount.right, .1));
        expect(heading.left, greaterThan(tax.right));
      }

      final before = <String, Rect>{};
      await tester.pumpWidget(host(claim: false));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expectAmountHeadingAxis();
      for (final key in fields) {
        before[key] = tester.getRect(find.byKey(ValueKey(key)));
      }
      await capture(tester, 'Expense Preserved Base ${width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('record-expense-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(claim: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expectAmountHeadingAxis();
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byKey(const ValueKey('claimant-extra-line')), findsOneWidget);
      final extra = tester.getRect(
        find.byKey(const ValueKey('claimant-extra-line')),
      );
      final shift = extra.height + accountingContentInset;
      for (final key in fields) {
        final after = tester.getRect(find.byKey(ValueKey(key)));
        expect(after.width, closeTo(before[key]!.width, .1), reason: key);
        expect(after.left, closeTo(before[key]!.left, .1), reason: key);
        // Modal centering may move its outer frame when its content grows;
        // compare every field to Payee so only the added line is new geometry.
        final baseline = before[key]!.top - before['expense-field-payee']!.top;
        final current =
            after.top -
            tester
                .getRect(find.byKey(const ValueKey('expense-field-payee')))
                .top;
        expect(current, closeTo(baseline, .1), reason: key);
      }
      expect(shift, greaterThan(0));
      final memo = tester.getRect(
        find.byKey(const ValueKey('expense-field-notes')),
      );
      final advanced = tester.getRect(find.text('Advanced Accounting Details'));
      final uploader = tester.getRect(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
      );
      expect(advanced.top, greaterThan(memo.bottom));
      expect(uploader.top, greaterThan(advanced.bottom));
      expect(find.text('Claim category'), findsNothing);
      expect(find.text('Multiple Merchants'), findsNothing);
      expect(find.text('Receipt 1'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'Claim From Expense One Line ${width.toInt()}');
      final add = find.byKey(const ValueKey('expense-add-line'));
      final addButton = tester.widget<IconButton>(add);
      expect(addButton.onPressed, isNotNull);
      expect(
        addButton.style!.backgroundColor!.resolve({}),
        AccountingTheme.of(tester.element(add)).primary,
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('expense-remove-line-1'));
      expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect(add, findsOneWidget);
    });
  }
}
