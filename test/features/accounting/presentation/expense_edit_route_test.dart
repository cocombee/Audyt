import 'package:audyt/app/accounting_components.dart';

import '../../../support/accounting_test_finders.dart';

import 'dart:io';

import 'package:audyt/features/accounting/presentation/audit_log_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';

import '../data/expense_intake_test.dart' show draft;

void main() {
  testWidgets(
    'intake edit saves durably and cancellation preserves saved amount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('expense-route-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      final original = RecordExpenseDraft.fromJson({
        ...draft(paymentAccountId: 'cash').toJson(),
        'tax': 'No tax',
      });
      final id = await workspace.saveExpenseIntake(original);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpenseIntakePage(
              workspace: workspace,
              onRecordExpense: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        await tester.pumpAndSettle();
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap('open-expense-${id.value}');
      await tester.enterText(
        find.byKey(const ValueKey('expense-field-amount')),
        '31.00',
      );
      await tap('record-expense-save');
      expect((await workspace.expense(id))!.summary.amount.minorUnits, 3100);
      await tap('open-expense-${id.value}');
      await tester.enterText(
        find.byKey(const ValueKey('expense-field-amount')),
        '99.00',
      );
      await tap('record-expense-cancel');
      showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (_) => AuditLogDialog(workspace: workspace),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('audit-filters')), findsNothing);
      await tap('audit-event-1');
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows,
        contains(('Amount', '25.50 → 31.00')),
      );
      expect(find.textContaining('99.00'), findsNothing);
      expect(find.byKey(const ValueKey('audit-open-journal-1')), findsNothing);
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect((await workspace.expense(id))!.summary.amount.minorUnits, 3100);
      expect(await workspace.expenses(), hasLength(1));
      expect(await workspace.journals(), isEmpty);
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        hasLength(1),
      );
    },
  );
}
