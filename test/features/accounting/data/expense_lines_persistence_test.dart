import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:flutter_test/flutter_test.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  final priced = RecordExpenseDraft.fromJson({
    ...draft(amount: '10.00').toJson(),
    'paymentAccountId': 'cash',
    'documentNumber': 'SUPPLIER-001',
    'lines': [
      const ExpenseDraftLine(
        id: 'line-one',
        category: 'Office Operations',
        description: '1. Long retained detail\n2. Another paragraph',
        tax: 'No tax',
        amount: '10.00',
        quantity: '3',
        rate: '3.34',
        pricingAdjustment: '-0.02',
      ).toJson(),
    ],
  });

  test(
    'inverse pricing and line identity survive save, retry, edit and restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('expense-lines-');
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
      final id = await workspace.saveExpenseIntake(priced);
      expect(await workspace.saveExpenseIntake(priced), id);
      expect(await workspace.expenses(), hasLength(1));
      final changed = RecordExpenseDraft.fromJson({
        ...priced.toJson(),
        'amount': '9.90',
        'lines': [
          {
            ...priced.lines.single.toJson(),
            'rate': '3.30',
            'amount': '9.90',
            'pricingAdjustment': null,
          },
        ],
      });
      await workspace.updateExpenseIntake(
        id: id,
        expected: priced,
        replacement: changed,
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final saved = (await workspace.expense(id))!;
      expect(saved.draft.toJson(), changed.toJson());
      expect(saved.summary.amount.minorUnits, 990);
      expect(saved.draft.lines.single.id, 'line-one');
      expect(saved.draft.documentNumber, 'SUPPLIER-001');
      expect(await workspace.journals(), isEmpty);
    },
  );

  test(
    'invalid totals, duplicate rows and mismatched pricing cannot be stored',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      for (final lines in [
        [
          ExpenseDraftLine.fromJson({
            ...priced.lines.single.toJson(),
            'amount': '11.00',
          }),
        ],
        [priced.lines.single, priced.lines.single],
        [
          ExpenseDraftLine.fromJson({
            ...priced.lines.single.toJson(),
            'rate': '3.33',
          }),
        ],
      ]) {
        final invalid = RecordExpenseDraft(
          submissionId: 'invalid-line-submission',
          amount: '10.00',
          date: priced.date,
          payee: priced.payee,
          paymentAccount: priced.paymentAccount,
          category: priced.category,
          tax: priced.tax,
          customer: '',
          billable: false,
          dimensions: '',
          itemOrSplitDetails: '',
          notes: '',
          lines: lines,
        );
        await expectLater(
          workspace.saveExpenseIntake(invalid),
          throwsFormatException,
        );
      }
      expect(await workspace.expenses(), isEmpty);
      expect(await workspace.journals(), isEmpty);
    },
  );

  test(
    'quantity alone retains manual amount and recurrence resets every tax flag',
    () {
      final informational = RecordExpenseDraft.fromJson({
        ...priced.toJson(),
        'lines': [
          {
            ...priced.lines.single.toJson(),
            'rate': null,
            'pricingAdjustment': null,
            'quantity': '400',
          },
        ],
      });
      expect(informational.amount, '10.00');
      final occurrence = RecurringExpenseTemplate(
        id: 'template',
        revision: 1,
        sourceExpenseId: 'expense',
        schedule: RecurrenceRule(
          startsOn: DateTime.utc(2026, 10, 1),
          unit: RecurrenceUnit.months,
        ),
        defaults: informational,
      ).occurrenceAt(1)!;
      expect(occurrence.suggestion.lines.single.tax, 'Unknown / Review Needed');
      expect(occurrence.suggestion.lines.single.amount, '10.00');
      expect(informational.lines.single.tax, 'No tax');
      final legacy = draft();
      expect(
        RecordExpenseDraft.fromJson(legacy.toJson()).toJson(),
        legacy.toJson(),
      );
    },
  );
}
