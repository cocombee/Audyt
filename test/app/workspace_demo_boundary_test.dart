import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';

void main() {
  testWidgets('payment account created in expense form survives restart', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('account-form-restart-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    await tester.pumpWidget(
      AudytApp(workspace: workspace, initialPath: '/record-expense'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-account-bank')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment-account-bank-option-maybank')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-account-name')),
      'Persistent eBay Bank',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-account-number')),
      '001234',
    );
    await tester.tap(find.byKey(const ValueKey('payment-account-create')));
    await tester.pumpAndSettle();
    expect(workspace.paymentAccounts.single.name, 'Persistent eBay Bank');
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(workspace: workspace, initialPath: '/record-expense'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('expense-field-payment-account')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Persistent eBay Bank'), findsWidgets);
    expect(workspace.paymentAccounts.single.accountNumber, '001234');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('payee created in the expense form survives workspace restart', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('payee-form-restart-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    await tester.pumpWidget(
      AudytApp(workspace: workspace, initialPath: '/record-expense'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payee-name-field')),
      'Persistent Supplier',
    );
    await tester.tap(find.byKey(const ValueKey('payee-create-action')));
    await tester.pumpAndSettle();
    expect(workspace.payees.all.single.name, 'Persistent Supplier');
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(workspace: workspace, initialPath: '/record-expense'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'Persistent',
    );
    await tester.pumpAndSettle();
    expect(find.text('Persistent Supplier'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('real workspace does not seed demonstration claims or vouchers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('workspace-demo-boundary-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    for (final page in [
      ('/claims', 'claims-empty-state'),
      ('/payment-vouchers', 'payment-voucher-empty-state'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: page.$1),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(page.$2)), findsOneWidget);
      expect(find.textContaining('Northwind'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
