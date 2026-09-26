import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';

void main() {
  testWidgets('invoice search keeps matching page insets on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(310, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: InvoicePage(workspace: workspace)),
      ),
    );
    await tester.pumpAndSettle();
    final search = tester.getRect(find.byKey(const ValueKey('invoice-search')));
    expect(search.left, closeTo(310 - search.right, 0.1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty catalog gives setup guidance without creating a draft', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('invoice-empty-');
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/books.sqlite',
    );
    addTearDown(() {
      workspace.dispose();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: InvoicePage(workspace: workspace)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('new-invoice')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Before creating or editing an invoice'),
      findsOneWidget,
    );
    expect(workspace.invoiceDrafts(), isEmpty);
  });
  testWidgets('blank invoice form creates a durable calculated draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('invoice-posting-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    await w.createAccount(
      code: '1100',
      name: 'Receivables',
      type: AccountType.asset,
    );
    await w.createAccount(
      code: '4000',
      name: 'Sales',
      type: AccountType.income,
    );
    await w.createAccount(
      code: '2200',
      name: 'Tax Payable',
      type: AccountType.liability,
    );
    final accounts = await w.accounts();
    final sales = accounts
        .firstWhere((a) => a.account.code == '4000')
        .account
        .id;
    final c = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: EntityId.random(),
        businessId: w.identity.businessId,
        originDeviceId: w.identity.deviceId,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      displayName: 'Test Customer',
      contact: const CustomerContact(),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
    );
    w.saveCustomer(c);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: InvoicePage(workspace: w)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('new-invoice')));
    await tester.pumpAndSettle();
    Future<void> choose(String key, String label) async {
      final trigger = find.byKey(ValueKey(key));
      await tester.ensureVisible(trigger);
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('design-field-Counterparty', 'Test Customer');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('design-field-Document Number')),
          )
          .controller!
          .text,
      'INV-000001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('design-field-Document Number')),
      'INV-NEW-1',
    );
    await tester.pumpAndSettle();
    await choose('design-field-Tax Mode', 'Inclusive');
    for (final entry in {
      'Description': 'New Service',
      'Quantity': '2',
      'Rate': '54',
      'Discount': '0',
      'Tax Rate (%)': '8',
    }.entries) {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == entry.key,
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    final account = find.text('Select Account');
    await tester.ensureVisible(account);
    await tester.tap(account);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4000 · Sales').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsNothing);
    expect(w.invoiceDrafts(), hasLength(1));
    final invoice = w.invoiceDrafts().single.invoice;
    expect(invoice.customerId, c.id);
    expect(invoice.dueDate, invoice.terms.dueDateFor(invoice.issueDate));
    expect(invoice.total.minorUnits, 10800);
    expect(invoice.lines.single.tax.minorUnits, 800);
    expect(invoice.lines.single.categoryId, sales);
    expect(await w.journals(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(w.invoiceDrafts().single.invoice.documentNumber, 'INV-NEW-1');
    w.dispose();
  });
}
