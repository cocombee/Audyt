import 'package:audyt/app/app.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fixed_popout_host.dart';

void main() {
  testWidgets('renders the live fixed Expense popout from its mounted route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    installFixedPopoutHost(tester);

    await tester.pumpWidget(
      const AudytApp(initialPath: '/record-expense', showInitialSetup: false),
    );
    await tester.pumpAndSettle();

    for (final label in <String>[
      'Amount (RM)',
      'Date',
      'Payee',
      'Document Number',
      'Payment Account',
      'Currency',
      'Amounts Are',
      'Make Recurring',
      'Items',
      'Category',
      'Tax',
      'Advanced Accounting Details',
      'Memo',
      'Receipts',
      'Drop receipts here or choose files',
      'Save Expense',
      'Cancel',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'Missing $label');
    }
    final payee = tester.getRect(
      find.byKey(const ValueKey('expense-field-payee')),
    );
    final number = tester.getRect(
      find.byKey(const ValueKey('expense-document-number')),
    );
    final date = tester.getRect(
      find.byKey(const ValueKey('expense-field-date')),
    );
    expect(payee.top, number.top);
    expect(date.top, greaterThan(payee.bottom));
    final summary = tester.widget<AccountingMemoSummary>(
      find.byType(AccountingMemoSummary),
    );
    expect(summary.rows.singleWhere((row) => row.$1 == 'Subtotal').$2, '0.00');
    expect(summary.rows.singleWhere((row) => row.$1 == 'Tax').$2, '0.00');
    expect(
      summary.rows.singleWhere((row) => row.$1 == 'Total (RM)').$2,
      '0.00',
    );
    expect(find.text('Expense Details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
