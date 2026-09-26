import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:audyt/app/accounting_description_field.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  salesReceiptConfiguredJourneys();
  salesReceiptCustomerCreationJourneys();
  for (final width in [720.0, 1224.0]) {
    for (final (title, savedPreview) in [
      ('Sales Receipts', false),
      ('Purchase Orders', false),
      ('Supplier Credits', false),
      for (final form in frontendAreas.values.expand((forms) => forms))
        if (form.lines) (form.title, true),
    ]) {
      testWidgets(
        '$title ${savedPreview ? 'View' : 'New'} preview route shares editable grid at $width',
        (tester) async {
          installFixedPopoutHost(tester);
          tester.view.physicalSize = Size(width, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadJournalLayoutFonts();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: DemoCompany(
                  child: Scaffold(
                    body: FrontendAreaPage(
                      area: frontendAreas.entries
                          .firstWhere(
                            (entry) =>
                                entry.value.any((form) => form.title == title),
                          )
                          .key,
                      title: title,
                      initialPage: title,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final trigger = savedPreview
              ? find
                    .byWidgetPredicate(
                      (widget) =>
                          widget.key is ValueKey &&
                          '${(widget.key as ValueKey).value}'.startsWith(
                            'view-record-',
                          ),
                    )
                    .first
              : find.byKey(const ValueKey('design-open-form'));
          await tester.ensureVisible(trigger);
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          expect(find.byType(AccountingTransactionGrid), findsOneWidget);
          expect(find.textContaining('Design preview ·'), findsOneWidget);

          Finder input(String field) => find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField &&
                widget.key is ValueKey &&
                '${(widget.key as ValueKey).value}'.endsWith('-$field'),
          );
          final monetaryField = title == 'Deposits' ? 'Amount' : 'Rate';
          final initialRows = input(monetaryField).evaluate().length;
          final rate = input(monetaryField).first;
          final quantity = input('Quantity').first;
          await tester.ensureVisible(rate);
          await enterAccountingText(tester, rate, '123456.78');
          if (title != 'Deposits') {
            await enterAccountingText(tester, quantity, '12');
          }
          await tester.pumpAndSettle();
          for (final field in [rate, if (title != 'Deposits') quantity]) {
            expect(
              tester
                  .widget<InputDecorator>(
                    find.descendant(
                      of: field,
                      matching: find.byType(InputDecorator),
                    ),
                  )
                  .decoration
                  .prefix,
              isNull,
            );
            expect(
              tester
                  .widget<InputDecorator>(
                    find.descendant(
                      of: field,
                      matching: find.byType(InputDecorator),
                    ),
                  )
                  .decoration
                  .prefixText,
              isNull,
            );
          }
          final grid = tester.widget<AccountingTransactionGrid>(
            find.byType(AccountingTransactionGrid),
          );
          expect(
            grid.columns.map((column) => column.title),
            contains('$monetaryField (RM)'),
          );
          final rowBefore = tester.getRect(rate);
          final add = find.byKey(const ValueKey('design-add-line'));
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(input(monetaryField), findsNWidgets(initialRows + 1));
          expect(tester.getRect(rate.first).size, rowBefore.size);
          final editable = tester.widget<EditableText>(
            find.descendant(
              of: rate.first,
              matching: find.byType(EditableText),
            ),
          );
          expect(editable.controller.text.replaceAll(',', ''), '123456.78');
          await captureUi(
            tester,
            '$title Shared Preview ${savedPreview ? 'View' : 'New'} Added Row ${width.toInt()}',
          );

          final remove = find.byKey(
            ValueKey('design-remove-line-$initialRows'),
          );
          await tester.ensureVisible(remove);
          await tester.tap(remove);
          await tester.pumpAndSettle();
          expect(input(monetaryField), findsNWidgets(initialRows));
          expect(find.byType(AccountingDescriptionField), findsWidgets);
          if (!savedPreview && title == 'Supplier Credits') {
            final memo = find.byKey(const ValueKey('design-field-Memo'));
            await tester.ensureVisible(memo);
            await enterAccountingText(
              tester,
              memo,
              'Retain credit working Memo.',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
            await captureUi(
              tester,
              '$title Shared Preview New Memo Discard ${width.toInt()}',
            );
            await tester.tap(find.byKey(const ValueKey('design-keep-editing')));
            await tester.pumpAndSettle();
            expect(
              accountingDescriptionText('Retain credit working Memo.'),
              findsOneWidget,
            );
            expect(editable.controller.text.replaceAll(',', ''), '123456.78');
            await tester.tap(find.byKey(const ValueKey('design-close')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('design-discard-changes')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(FrontendFormDialog), findsNothing);
            await tester.tap(find.byKey(const ValueKey('design-open-form')));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: input('Rate').first,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              isEmpty,
            );
            expect(
              accountingDescriptionText('Retain credit working Memo.'),
              findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

void salesReceiptConfiguredJourneys() {
  for (final width in [720.0, 1224.0]) {
    for (final showRate in [false, true]) {
      for (final basis in ['Exclusive', 'Inclusive']) {
        testWidgets(
          'Sales Receipt maintained selectors and independent row tax $basis rate=$showRate at $width',
          (tester) async {
            installFixedPopoutHost(tester);
            tester.view.physicalSize = Size(width, 1600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await loadJournalLayoutFonts();
            final root = Directory.systemTemp.createTempSync(
              'receipt-controls-',
            );
            addTearDown(() => root.deleteSync(recursive: true));
            final w = await createDemoWorkspace(
              databasePath: '${root.path}/books.sqlite',
            );
            addTearDown(w.dispose);
            await w.createAccount(
              code: '2299',
              name: 'Configured Sales Tax',
              type: AccountType.liability,
            );
            final accounts = await w.accounts();
            final taxAccount = accounts
                .singleWhere((a) => a.account.code == '2299')
                .account
                .id;
            final incomeAccount = accounts
                .singleWhere((a) => a.account.code == '4000')
                .account
                .id;
            final tax = w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'Configured Service Tax',
                percent: '8',
                effectiveFrom: DateTime(2020),
                application: TaxApplication.sales,
                accountId: taxAccount,
              ),
            );
            final purchaseTax = w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'Purchase Only',
                percent: '10',
                effectiveFrom: DateTime(2020),
                application: TaxApplication.purchases,
              ),
            );
            final samePercentTax = w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'Alternate Configured Tax',
                percent: '8',
                effectiveFrom: DateTime(2020),
                application: TaxApplication.sales,
                accountId: taxAccount,
              ),
            );
            final group = w.saveCatalogueCategory(
              CatalogueCategory(
                id: EntityId.random(),
                name: 'Configured Services',
              ),
            );
            final item = w.saveCatalogueItem(
              CatalogueItem(
                id: EntityId.random(),
                categoryId: group.id,
                name: 'Registered Service',
                type: CatalogueItemType.service,
                incomeAccountId: incomeAccount,
                description: 'Maintained item description',
                taxRatePercent: '8',
              ),
            );
            w.savePreferences(
              w.preferences.change('Sales Preferences', {
                'Default Tax Mode': basis,
                'Show Rate': showRate,
                'Show Quantity': showRate,
                'Customer Message': 'Configured receipt message',
              }),
            );
            final customer = w.customers().firstWhere((c) => c.isActive);
            for (final (id, type, currency) in [
              ('unlinked-bank', PaymentAccountType.bank, 'MYR'),
              ('foreign-bank', PaymentAccountType.bank, 'USD'),
              ('receipt-card', PaymentAccountType.card, 'MYR'),
            ]) {
              w.savePaymentAccount(
                PaymentAccount.create(
                  id: id,
                  name: id,
                  type: type,
                  currencyCode: currency,
                ),
              );
            }
            w.saveCustomer(
              customerFromForm(
                {
                  ...customerFormValues(customer),
                  'Email': 'maintained@example.test',
                  'Address Line 1': 'Registered billing address',
                  'Country': 'Malaysia',
                  'Country ISO Code': 'MY',
                  'City': 'Kuala Lumpur',
                  'Postcode': '50000',
                },
                w,
                original: customer,
                id: customer.id,
                now: DateTime.now().toUtc(),
              ),
            );
            final preferencesBefore = jsonEncode(w.preferences.sections);
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AccountingTheme.light(),
                  home: Scaffold(
                    body: FrontendAreaPage(
                      area: 'sales-customers',
                      title: 'Sales Receipts',
                      initialPage: 'Sales Receipts',
                      workspace: w,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('design-open-form')));
            await tester.pumpAndSettle();
            final captureSuffix =
                '${showRate ? 'Forced Qty Rate' : 'Default'} $basis ${width.toInt()}';
            await captureUi(
              tester,
              'Sales Receipt Configured Empty $captureSuffix',
            );
            expect(
              find.byKey(const ValueKey('design-document-tax')),
              findsNothing,
            );
            expect(find.byType(AccountingTransactionGrid), findsOneWidget);
            void expectFluidDescriptionMinimum() {
              final grid = tester.widget<AccountingTransactionGrid>(
                find.byType(AccountingTransactionGrid),
              );
              expect(
                grid.columns
                    .singleWhere((column) => column.title == 'Description')
                    .width,
                greaterThanOrEqualTo(180),
              );
            }

            expectFluidDescriptionMinimum();

            Finder selectors(String suffix) => find.byWidgetPredicate(
              (widget) =>
                  widget is AccountingSelector<String> &&
                  widget.triggerKey is ValueKey &&
                  '${(widget.triggerKey as ValueKey).value}'.endsWith(suffix),
            );
            Future<void> choose(Finder finder, String value) async {
              final selector = tester.widget<AccountingSelector<String>>(
                finder,
              );
              final option = selector.options.singleWhere(
                (o) => o.value == value,
              );
              expect(option.enabled, isTrue);
              final trigger = find.byKey(selector.triggerKey!);
              await tester.ensureVisible(trigger);
              await tester.tap(trigger);
              await tester.pumpAndSettle();
              await tester.tap(find.text(option.label).last);
              await tester.pumpAndSettle();
            }

            Finder input(String field) => find.byWidgetPredicate(
              (widget) =>
                  widget is TextFormField &&
                  widget.key is ValueKey &&
                  '${(widget.key as ValueKey).value}'.endsWith('-$field'),
            );
            final customerSelector = tester.widget<AccountingSelector<String>>(
              selectors('design-field-Counterparty'),
            );
            expect(customerSelector.options.first.label, 'Add Customer');
            await choose(
              selectors('design-field-Counterparty'),
              w.customers().firstWhere((c) => c.isActive).id.value,
            );
            expect(
              tester.widget<TextFormField>(input('Email')).controller!.text,
              'maintained@example.test',
            );
            final billing = find.byKey(
              const ValueKey('design-field-Billing Address'),
            );
            expect(
              tester
                  .widget<AccountingDescriptionField>(billing)
                  .controller!
                  .text,
              contains('Registered billing address'),
            );
            final receiptMessage = find.byKey(
              const ValueKey('design-field-Receipt Message'),
            );
            final statementMessage = find.byKey(
              const ValueKey('design-field-Statement Message'),
            );
            expect(
              tester
                  .widget<AccountingDescriptionField>(receiptMessage)
                  .controller!
                  .text,
              'Configured receipt message',
            );
            Future<void> enterDescription(Finder field, String text) async {
              await tester.ensureVisible(field);
              await enterAccountingText(tester, field, text);
              await tester.pumpAndSettle();
            }

            await enterAccountingText(
              tester,
              input('Email'),
              'receipt-local@example.test',
            );
            await enterDescription(billing, 'Receipt-local billing address');
            await enterDescription(
              receiptMessage,
              'Receipt-local customer message',
            );
            await enterDescription(
              statementMessage,
              'Independent statement message',
            );
            final deposit = w.paymentAccounts.first;
            final depositChoices = tester.widget<AccountingSelector<String>>(
              selectors('design-field-Payment Account'),
            );
            expect(
              depositChoices.options.map((option) => option.value),
              isNot(contains('unlinked-bank')),
            );
            expect(
              depositChoices.options.map((option) => option.value),
              isNot(contains('foreign-bank')),
            );
            expect(
              depositChoices.options.map((option) => option.value),
              isNot(contains('receipt-card')),
            );
            await choose(selectors('design-field-Payment Account'), deposit.id);
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('design-field-Payment Account'),
                  )
                  .value,
              deposit.id,
            );
            await choose(selectors('design-field-Currency'), 'USD');
            final retainedDeposit = tester.widget<AccountingSelector<String>>(
              selectors('design-field-Payment Account'),
            );
            expect(retainedDeposit.value, deposit.id);
            expect(retainedDeposit.options.single.value, deposit.id);
            expect(retainedDeposit.options.single.enabled, isFalse);
            expect(
              retainedDeposit.options.single.label,
              endsWith(' · Retained'),
            );
            if (!showRate && basis == 'Exclusive') {
              final trigger = find.byKey(retainedDeposit.triggerKey!);
              await tester.ensureVisible(trigger);
              await tester.tap(trigger);
              await tester.pumpAndSettle();
              await captureUi(
                tester,
                'Sales Receipt Retained Deposit Currency ${width.toInt()}',
              );
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
            }
            await tester.ensureVisible(find.text('Preview'));
            await tester.tap(find.text('Preview'));
            await tester.pumpAndSettle();
            expect(
              find.text(
                'Choose an available Deposit To account in the receipt currency.',
              ),
              findsOneWidget,
            );
            if (!showRate && basis == 'Exclusive') {
              await captureUi(
                tester,
                'Sales Receipt Deposit Currency Warning ${width.toInt()}',
              );
            }
            await choose(
              selectors('design-field-Currency'),
              'Use Counterparty Default',
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('design-field-Payment Account'),
                  )
                  .value,
              deposit.id,
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('design-field-Payment Account'),
                  )
                  .options
                  .singleWhere((option) => option.value == deposit.id)
                  .enabled,
              isTrue,
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('design-field-Tax Mode'),
                  )
                  .value,
              basis,
            );
            expect(input('Rate'), showRate ? findsOneWidget : findsNothing);
            expect(input('Quantity'), showRate ? findsOneWidget : findsNothing);
            final product = tester.widget<AccountingSelector<String>>(
              selectors('-Product / Service').first,
            );
            expect(product.options.first.label, 'Add Item');
            await choose(selectors('-Product / Service').first, item.id.value);
            final rowTax = tester.widget<AccountingSelector<String>>(
              selectors('-Tax Rate (%)').first,
            );
            expect(rowTax.value, '');
            expect(rowTax.options.map((o) => o.value), isNot(contains('8')));
            expect(
              rowTax.options.map((o) => o.value),
              contains(samePercentTax.choice),
            );
            expect(rowTax.options.map((o) => o.value), contains(tax.choice));
            expect(
              rowTax.options.map((o) => o.value),
              isNot(contains(purchaseTax.choice)),
            );
            await choose(selectors('-Tax Rate (%)').first, tax.choice);
            await enterAccountingText(
              tester,
              input(showRate ? 'Rate' : 'Amount').first,
              '100',
            );
            final add = find.byKey(const ValueKey('design-add-line'));
            await tester.ensureVisible(add);
            await tester.tap(add);
            await tester.pumpAndSettle();
            await choose(selectors('-Product / Service').at(1), item.id.value);
            await choose(selectors('-Tax Rate (%)').at(1), '0');
            await enterAccountingText(
              tester,
              input(showRate ? 'Rate' : 'Amount').at(1),
              '20',
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Tax Rate (%)').first,
                  )
                  .value,
              tax.choice,
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Tax Rate (%)').at(1),
                  )
                  .value,
              '0',
            );
            expect(
              find.text(basis == 'Exclusive' ? '128.00' : '120.00'),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('design-remove-line-1')),
              findsOneWidget,
            );
            await captureUi(
              tester,
              'Sales Receipt Configured Mixed Tax $captureSuffix',
            );

            final taxTrigger = find.byKey(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Tax Rate (%)').first,
                  )
                  .triggerKey!,
            );
            await tester.ensureVisible(taxTrigger);
            await tester.tap(taxTrigger);
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Sales Receipt Configured Tax Menu $captureSuffix',
            );
            await tester.tap(find.text(tax.label).last);
            await tester.pumpAndSettle();
            final remove = find.byKey(const ValueKey('design-remove-line-1'));
            await tester.ensureVisible(remove);
            await tester.tap(remove);
            await tester.pumpAndSettle();
            expect(selectors('-Product / Service'), findsOneWidget);
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Tax Rate (%)'),
                  )
                  .value,
              tax.choice,
            );
            expect(find.text('Preview'), findsOneWidget);
            expect(
              find.textContaining('Preview records last only'),
              findsOneWidget,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('design-review')),
            );
            await tester.tap(find.byKey(const ValueKey('design-review')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Keep Preview'));
            await tester.pumpAndSettle();
            expect(
              find.textContaining('Counterparty: ${customer.displayName}'),
              findsOneWidget,
            );
            await tester.tap(find.byKey(const ValueKey('design-open-form')));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('design-field-Counterparty'),
                  )
                  .value,
              customer.id.value,
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Product / Service'),
                  )
                  .value,
              item.id.value,
            );
            expect(
              tester
                  .widget<AccountingSelector<String>>(
                    selectors('-Tax Rate (%)'),
                  )
                  .value,
              tax.choice,
            );
            expect(
              tester.widget<TextFormField>(input('Email')).controller!.text,
              'receipt-local@example.test',
            );
            for (final (field, text) in [
              (billing, 'Receipt-local billing address'),
              (receiptMessage, 'Receipt-local customer message'),
              (statementMessage, 'Independent statement message'),
            ]) {
              expect(
                tester
                    .widget<AccountingDescriptionField>(field)
                    .controller!
                    .text,
                text,
              );
            }
            expect(
              w
                  .customers()
                  .singleWhere((c) => c.id == customer.id)
                  .contact
                  .email,
              'maintained@example.test',
            );
            final editedCode = w.saveTaxRate(
              CompanyTaxRate(
                id: tax.id,
                name: 'Renamed Configured Tax',
                percent: '8',
                effectiveFrom: DateTime(2020),
                application: TaxApplication.sales,
                accountId: taxAccount,
                revision: tax.revision,
              ),
            );
            expect(editedCode.choice, isNot(tax.choice));
            await tester.tap(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label == 'Close',
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('design-open-form')));
            await tester.pumpAndSettle();
            final retainedTax = tester.widget<AccountingSelector<String>>(
              selectors('-Tax Rate (%)'),
            );
            expectFluidDescriptionMinimum();
            expect(retainedTax.value, tax.choice);
            final retainedChoice = retainedTax.options.singleWhere(
              (o) => o.value == tax.choice,
            );
            expect(retainedChoice.label, tax.label);
            expect(retainedChoice.enabled, isFalse);
            await captureUi(
              tester,
              'Sales Receipt Configured Retained Tax $captureSuffix',
            );
            expect(jsonEncode(w.preferences.sections), preferencesBefore);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

void salesReceiptCustomerCreationJourneys() {
  for (final width in [720.0, 1224.0]) {
    for (final title in ['Sales Receipts', 'Invoices', 'Quotations']) {
      testWidgets(
        '$title Add Customer uses the durable existing owner at $width',
        (tester) async {
          installFixedPopoutHost(tester);
          tester.view.physicalSize = Size(width, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadJournalLayoutFonts();
          final root = Directory.systemTemp.createTempSync('receipt-customer-');
          addTearDown(() => root.deleteSync(recursive: true));
          final w = await createDemoWorkspace(
            databasePath: '${root.path}/books.sqlite',
          );
          addTearDown(w.dispose);
          final preferences = jsonEncode(w.preferences.sections);
          final count = w.customers().length;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: switch (title) {
                    'Invoices' => InvoicePage(workspace: w),
                    'Quotations' => QuotationPage(workspace: w),
                    _ => FrontendAreaPage(
                      area: 'sales-customers',
                      title: title,
                      initialPage: title,
                      workspace: w,
                    ),
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              ValueKey(switch (title) {
                'Invoices' => 'new-invoice',
                'Quotations' => 'new-quotation',
                _ => 'design-open-form',
              }),
            ),
          );
          await tester.pumpAndSettle();
          Finder counterparty() => find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey ==
                    const ValueKey('design-field-Counterparty'),
          );
          Future<void> addCustomer() async {
            final selector = tester.widget<AccountingSelector<String>>(
              counterparty(),
            );
            expect(selector.options.first.label, 'Add Customer');
            await tester.ensureVisible(find.byKey(selector.triggerKey!));
            await tester.tap(find.byKey(selector.triggerKey!));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Add Customer').last);
            await tester.pumpAndSettle();
            expect(find.byType(FrontendFormDialog), findsNWidgets(2));
            expect(
              tester
                  .widget<FrontendFormDialog>(
                    find.byType(FrontendFormDialog).last,
                  )
                  .form,
              same(customerForm),
            );
          }

          await addCustomer();
          await captureUi(
            tester,
            '$title Existing Add Customer ${width.toInt()}',
          );
          final close = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Close',
          );
          await tester.tap(close.last);
          await tester.pumpAndSettle();
          expect(w.customers().length, count);
          expect(
            tester.widget<AccountingSelector<String>>(counterparty()).value,
            anyOf(isNull, equals('')),
          );
          await addCustomer();
          for (final (label, value) in [
            ('Name', 'Receipt-created Customer'),
            ('Email', 'created@example.test'),
            ('Address Line 1', 'Created billing address'),
            ('City', 'Kuala Lumpur'),
            ('Postcode', '50000'),
          ]) {
            final field = find.byKey(ValueKey('design-field-$label')).last;
            await tester.ensureVisible(field);
            await enterAccountingText(tester, field, value);
            await tester.pumpAndSettle();
          }
          final review = find.byKey(const ValueKey('design-review'));
          await tester.ensureVisible(review.last);
          await tester.tap(review.last);
          await tester.pumpAndSettle();
          await captureUi(
            tester,
            '$title Existing Customer Review ${width.toInt()}',
          );
          await tester.tap(review.last);
          await tester.pumpAndSettle();
          final saved = w.customers().singleWhere(
            (c) => c.displayName == 'Receipt-created Customer',
          );
          expect(w.customers().length, count + 1);
          final selector = tester.widget<AccountingSelector<String>>(
            counterparty(),
          );
          expect(selector.value, saved.id.value);
          expect(
            selector.options
                .singleWhere((o) => o.value == saved.id.value)
                .label,
            saved.displayName,
          );
          if (title == 'Sales Receipts') {
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('design-field-Email')),
                  )
                  .controller!
                  .text,
              'created@example.test',
            );
            expect(
              tester
                  .widget<AccountingDescriptionField>(
                    find.byKey(const ValueKey('design-field-Billing Address')),
                  )
                  .controller!
                  .text,
              contains('Created billing address'),
            );
          }
          await captureUi(
            tester,
            '$title Created Customer Selected ${width.toInt()}',
          );
          expect(jsonEncode(w.preferences.sections), preferences);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
