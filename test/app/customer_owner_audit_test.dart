import 'dart:io';
import 'dart:convert';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Customer custom field setup keeps parent, guards draft and reviews exact facts at $width',
      (tester) async {
        await prepare(tester, width);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final before = w
            .customers()
            .map((c) => jsonEncode(customerFormValues(c)))
            .toList();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: CustomerPage(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder field(String name) =>
            find.byKey(ValueKey('design-field-$name')).last;
        Finder key(String value) => find.byKey(ValueKey(value)).last;
        await tap(tester, key('new-customer'));
        await tester.enterText(field('Name'), 'Fictional retained parent');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tap(tester, key('customer-add-custom-field'));
        expect(field('Data Type'), findsOneWidget);
        await capture(tester, 'Customer Custom Field Empty ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        expect(
          tester.widget<TextFormField>(field('Name')).controller!.text,
          'Fictional retained parent',
        );
        await tap(tester, key('customer-add-custom-field'));
        await tester.enterText(field('Name'), 'Fictional Reference');
        await tap(tester, field('Data Type'));
        await tap(tester, find.text('Text And Number').last);
        expect(
          find.byKey(const ValueKey('customer-custom-item-text-0')),
          findsNothing,
        );
        await tap(tester, key('design-review'));
        expect(find.text('Text And Number'), findsOneWidget);
        await capture(tester, 'Customer Custom Text Review ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, key('design-discard-changes'));
        await tap(tester, key('customer-add-custom-field'));
        expect(field('Data Type'), findsOneWidget);
        await tester.enterText(field('Name'), 'Fictional Department');
        await tap(tester, field('Data Type'));
        await tap(tester, find.text('Dropdown List').last);
        await tester.enterText(
          key('customer-custom-item-text-0'),
          'Production',
        );
        await tester.enterText(key('customer-custom-item-text-1'), 'Office');
        await tap(tester, key('customer-custom-item-add'));
        await Scrollable.ensureVisible(
          tester.element(key('customer-custom-item-text-0')),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Customer Custom Blank Extra Item ${width.toInt()}',
        );
        await tester.enterText(key('customer-custom-item-text-2'), 'Temporary');
        await tester.pumpAndSettle();
        final removedController = tester
            .widget<TextField>(key('customer-custom-item-text-2'))
            .controller!;
        expect(
          find.byKey(const ValueKey('customer-custom-item-remove-2')),
          findsNothing,
        );
        expect(key('customer-custom-item-active-2'), findsOneWidget);
        await tester.enterText(key('customer-custom-item-text-2'), '');
        await tester.pumpAndSettle();
        await tap(tester, key('customer-custom-item-remove-2'));
        expect(
          find.byKey(const ValueKey('customer-custom-item-text-2')),
          findsNothing,
        );
        await tap(tester, key('customer-custom-item-active-1'));
        expect(
          tester.widget<TextField>(key('customer-custom-item-text-1')).enabled,
          isFalse,
        );
        expect(
          tester
              .widget<TextField>(key('customer-custom-item-text-1'))
              .controller!
              .text,
          'Office',
        );
        await tap(tester, key('customer-custom-item-active-0'));
        expect(
          tester.widget<TextField>(key('customer-custom-item-text-0')).enabled,
          isTrue,
        );
        await tap(tester, key('customer-custom-item-active-1'));
        expect(
          tester.widget<TextField>(key('customer-custom-item-text-1')).enabled,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(key('customer-custom-item-text-1'))
              .controller!
              .text,
          'Office',
        );
        await tap(tester, key('customer-custom-item-active-1'));
        FocusManager.instance.primaryFocus?.unfocus();
        await Scrollable.ensureVisible(
          tester.element(find.text('Colour').last),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(field('Colour'));
        await tester.pumpAndSettle();
        final colour = tester.widget<AccountingSelector<String>>(
          find
              .ancestor(
                of: field('Colour'),
                matching: find.byType(AccountingSelector<String>),
              )
              .last,
        );
        expect(colour.options, hasLength(17));
        expect(
          colour.options.every((option) => option.leading != null),
          isTrue,
        );
        await capture(tester, 'Customer Custom Colour Menu ${width.toInt()}');
        await tap(tester, find.text('Lavender').last);
        await Scrollable.ensureVisible(
          tester.element(key('customer-custom-item-text-0')),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await capture(tester, 'Customer Custom Dropdown ${width.toInt()}');
        await Scrollable.ensureVisible(
          tester.element(find.text('Category').last),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(key('customer-custom-category'));
        await tester.pumpAndSettle();
        final category = tester.widget<AccountingSelector<String>>(
          find
              .ancestor(
                of: key('customer-custom-category'),
                matching: find.byType(AccountingSelector<String>),
              )
              .last,
        );
        expect(
          category.options.singleWhere((o) => o.value == 'Transaction').enabled,
          isFalse,
        );
        await capture(tester, 'Customer Custom Category Menu ${width.toInt()}');
        await tap(tester, find.text('Customer').last);
        await tap(tester, key('customer-custom-form-Invoice'));
        await tap(tester, key('customer-custom-form-Quotation'));
        await capture(tester, 'Customer Custom Form Choices ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        await capture(tester, 'Customer Custom Discard ${width.toInt()}');
        await tap(tester, key('design-keep-editing'));
        expect(
          tester
              .widget<TextField>(key('customer-custom-item-text-0'))
              .controller!
              .text,
          'Production',
        );
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await tap(tester, key('customer-custom-form-Credit Card Credit'));
        expect(
          tester.getRect(key('design-review')).bottom,
          lessThanOrEqualTo(613),
        );
        await capture(tester, 'Customer Custom Short Window ${width.toInt()}');
        await tap(tester, key('customer-custom-form-Credit Card Credit'));
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        await tap(tester, key('customer-custom-item-text-0'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(tester, key('design-keep-editing'));
        await tap(tester, key('design-review'));
        expect(find.text('Production · Active'), findsOneWidget);
        expect(find.text('Office · Inactive'), findsOneWidget);
        expect(find.text('Invoice, Quotation'), findsOneWidget);
        expect(find.text('Not Connected Yet'), findsOneWidget);
        expect(find.text('Save Custom Field'), findsOneWidget);
        expect(
          tester.widget<ButtonStyleButton>(key('design-review')).onPressed,
          isNull,
        );
        await capture(tester, 'Customer Custom Review ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, key('design-discard-changes'));
        expect(
          () => removedController.text = 'Disposed probe',
          throwsFlutterError,
        );
        expect(
          tester.widget<TextFormField>(field('Name')).controller!.text,
          'Fictional retained parent',
        );
        expect(
          w.customers().map((c) => jsonEncode(customerFormValues(c))).toList(),
          before,
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, key('design-discard-changes'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Customer profile conditional branches and guard at $width',
      (tester) async {
        await prepare(tester, width);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: CustomerPage(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const ValueKey('new-customer')));
        await capture(tester, 'Customer Profile New ${width.toInt()}');
        Finder field(String label) =>
            find.byKey(ValueKey('design-field-$label'));
        await tester.enterText(field('Name'), 'Fictional Customer Profile');
        await tester.enterText(field('First Name'), 'Alex');
        await tester.enterText(field('Email'), 'profile@example.test');
        await tap(tester, field('Is A Sub-Customer'));
        expect(field('Parent Customer'), findsOneWidget);
        await tap(tester, field('Parent Customer'));
        await tap(tester, find.text('Meridian Trading').last);
        expect(field('Bill Parent Customer'), findsOneWidget);
        expect(
          tester.widget<TextFormField>(field('Email')).controller!.text,
          'profile@example.test',
        );
        await capture(tester, 'Customer Profile Parent ${width.toInt()}');
        await tap(tester, field('Bill Parent Customer'));
        await tap(tester, field('Parent Customer'));
        await tap(tester, find.text('Northwind Services').last);
        await capture(
          tester,
          'Customer Parent Separate Billing ${width.toInt()}',
        );
        await tester.ensureVisible(field('Bill Parent Customer'));
        await tap(tester, field('Bill Parent Customer'));
        await tester.ensureVisible(field('Address Line 1'));
        await tester.enterText(
          field('Address Line 1'),
          'Fictional Billing Street',
        );
        await tester.enterText(field('Address Line 2'), 'Second Floor');
        await tap(
          tester,
          find.byKey(const ValueKey('design-field-action-Address Line 2')),
        );
        expect(field('Address Line 1'), findsNothing);
        expect(
          tester
              .widget<AccountingDescriptionField>(field('Street Address'))
              .controller!
              .text,
          'Fictional Billing Street\nSecond Floor',
        );
        await Scrollable.ensureVisible(
          tester.element(field('Street Address')),
          alignment: .2,
        );
        await tester.pumpAndSettle();
        await capture(tester, 'Customer Billing Add Lines ${width.toInt()}');
        await tap(tester, field('Same As Billing Address'));
        await tester.ensureVisible(field('Shipping Address Line 1'));
        await tester.enterText(
          field('Shipping Address Line 1'),
          'Fictional Warehouse',
        );
        await tap(tester, field('Shipping Country'));
        await tap(tester, find.text('Singapore').last);
        await tap(
          tester,
          find.byKey(
            const ValueKey('design-field-action-Shipping Address Line 2'),
          ),
        );
        expect(
          tester
              .widget<AccountingDescriptionField>(
                field('Shipping Street Address'),
              )
              .controller!
              .text,
          'Fictional Warehouse',
        );
        await Scrollable.ensureVisible(
          tester.element(field('Shipping Street Address')),
          alignment: .2,
        );
        await tester.pumpAndSettle();
        await capture(tester, 'Customer Shipping Add Lines ${width.toInt()}');
        await capture(tester, 'Customer Profile Shipping ${width.toInt()}');
        await tap(tester, field('Same As Billing Address'));
        expect(field('Shipping Street Address'), findsNothing);
        await tap(tester, field('Same As Billing Address'));
        expect(
          tester
              .widget<AccountingDescriptionField>(
                field('Shipping Street Address'),
              )
              .controller!
              .text,
          'Fictional Warehouse',
        );
        await tap(tester, field('Sales Form Delivery'));
        await tap(tester, find.text('Print Later').last);
        await tap(tester, field('Invoice Language'));
        await tap(tester, find.text('French').last);
        final parentNameBeforeMethod = tester
            .widget<TextFormField>(field('Name'))
            .controller!
            .text;
        await tap(tester, field('Primary Payment Method'));
        await capture(tester, 'Customer Profile Payment Menu ${width.toInt()}');
        await tap(tester, find.text('Add Payment Method').last);
        await capture(tester, 'Customer Payment Method Setup ${width.toInt()}');
        expect(
          find.textContaining('Saving payment methods is not connected yet.'),
          findsOneWidget,
        );
        final methodSurface = find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.type == MaterialType.card,
          ),
        );
        expect(
          tester.getSize(methodSurface).width,
          closeTo(600 + AccountingPopoutTokens.contentInset * 2, .1),
        );
        await tester.enterText(field('Name').last, 'Fictional audit card');
        await tap(tester, find.byKey(const ValueKey('design-review')).last);
        expect(find.text('Fictional audit card'), findsOneWidget);
        expect(find.text('No'), findsOneWidget);
        await capture(
          tester,
          'Customer Payment Method Unchecked Review ${width.toInt()}',
        );
        await tap(tester, find.byKey(const ValueKey('design-back')).last);
        await tap(tester, field('This Is A Credit Card'));
        await tap(tester, find.byKey(const ValueKey('design-review')).last);
        expect(find.text('Fictional audit card'), findsOneWidget);
        expect(find.text('Yes'), findsOneWidget);
        expect(find.text('Keep Preview'), findsNothing);
        final unavailableSave = find
            .byKey(const ValueKey('design-review'))
            .last;
        expect(
          tester.widget<ButtonStyleButton>(unavailableSave).onPressed,
          isNull,
        );
        await capture(
          tester,
          'Customer Payment Method Review ${width.toInt()}',
        );
        await tap(tester, find.byKey(const ValueKey('design-back')).last);
        expect(
          tester.widget<TextFormField>(field('Name').last).controller!.text,
          'Fictional audit card',
        );
        await tap(tester, field('Name').last);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(tester, 'Customer Payment Method Guard ${width.toInt()}');
        await tap(tester, find.byKey(const ValueKey('design-keep-editing')));
        expect(
          tester.widget<TextFormField>(field('Name').last).controller!.text,
          'Fictional audit card',
        );
        await tap(tester, find.byKey(const ValueKey('design-close')).last);
        await tap(tester, find.byKey(const ValueKey('design-discard-changes')));
        expect(
          tester.widget<TextFormField>(field('Name').last).controller!.text,
          parentNameBeforeMethod,
        );
        await tap(tester, field('Primary Payment Method'));
        await tap(tester, find.text('Bank Draft').last);
        await tester.ensureVisible(field('Opening Balance'));
        final openingBalanceTitle = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.startsWith('Opening Balance (') ?? false),
        );
        await tester.ensureVisible(openingBalanceTitle.last);
        await tester.pumpAndSettle();
        final emptyAmountWidth = tester.getSize(field('Opening Balance')).width;
        await capture(tester, 'Customer Amount Empty ${width.toInt()}');
        await tester.enterText(field('Opening Balance'), '123456789012.34');
        await tester.pumpAndSettle();
        await tester.ensureVisible(openingBalanceTitle.last);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(field('Opening Balance')).width,
          closeTo(emptyAmountWidth, .1),
          reason: 'Independent money fields keep their ordinary row width',
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: field('Opening Balance'),
                  matching: find.byType(EditableText),
                ),
              )
              .textAlign,
          TextAlign.right,
        );
        await capture(tester, 'Customer Amount Entered ${width.toInt()}');
        await tester.enterText(field('Opening Balance'), '');
        await tester.pumpAndSettle();
        expect(
          tester.getSize(field('Opening Balance')).width,
          closeTo(emptyAmountWidth, .1),
        );
        await tester.ensureVisible(field('Notes'));
        await capture(tester, 'Customer Profile Lower ${width.toInt()}');
        await tap(tester, find.byKey(const ValueKey('design-close')));
        await capture(
          tester,
          'Customer Profile Discard Warning ${width.toInt()}',
        );
        await tap(tester, find.byKey(const ValueKey('design-keep-editing')));
        expect(
          tester.widget<TextFormField>(field('Email')).controller!.text,
          'profile@example.test',
        );
        await tap(tester, find.byKey(const ValueKey('design-review')));
        await capture(tester, 'Customer Profile Review ${width.toInt()}');
        await tap(tester, find.byKey(const ValueKey('design-review')));
        final saved = w.customers().singleWhere(
          (c) => c.displayName == 'Fictional Customer Profile',
        );
        expect(saved.additionalValues['invoiceLanguage'], 'French');
        expect(saved.additionalValues['primaryPaymentMethod'], 'Bank Draft');
        expect(saved.shippingAddress?.line1, 'Fictional Warehouse');
        expect(
          saved.billingAddress?.line1,
          'Fictional Billing Street\nSecond Floor',
        );
        expect(saved.additionalValues['parentCustomerId'], isNotEmpty);
        expect(saved.additionalValues['billParentCustomer'], 'true');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    for (final long in [false, true]) {
      testWidgets('actual Customer columns at $width / long $long', (
        tester,
      ) async {
        await prepare(tester, width);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        var customer = w.customers().firstWhere(
          (c) => c.displayName == 'Meridian Trading',
        );
        if (long) {
          customer = customer.revise(
            displayName: 'Fictional International Engineering And Business Services Company',
            updatedAt: DateTime.now().toUtc(),
          );
          w.saveCustomer(customer);
        }
        final before = customerFormValues(customer);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    // The supported compact-sidebar page-content minimum is 620.
                    width: width == 720 ? 620 : width,
                    child: CustomerPage(workspace: w),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final name = find.text(customer.displayName);
        final row = find.byKey(ValueKey(customer.metadata.recordId.value));
        final amountText = formatAccountingMoney(
          tester.element(name),
          w.database
              .customerStatement(
                w.identity.businessId,
                customer.id,
                DateTime.now(),
              )
              .last
              .balance,
        );
        final amount = find.descendant(
          of: row,
          matching: find.text(amountText),
        );
        final edit = find.byKey(
          ValueKey('edit-customer-${customer.metadata.recordId.value}'),
        );
        final header = find.text('Balance');
        expect(
          tester.widget<Text>(header).style,
          AccountingTypography.tableHeader(tester.element(header)),
        );
        expect(
          tester.getRect(header).right,
          closeTo(tester.getRect(amount).right, .01),
        );
        expect(
          tester.getRect(edit).left - tester.getRect(amount).right,
          closeTo(accountingContentInset, .01),
        );
        expect(
          tester.getRect(edit).center.dy,
          closeTo(tester.getRect(amount).center.dy, .01),
        );
        expect(
          tester.getRect(name).left,
          closeTo(tester.getRect(find.text('Customer / Email')).left, .01),
        );
        expect(
          tester.getRect(edit).right,
          closeTo(tester.getRect(row).right - accountingContentInset, .01),
        );
        expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
        expect(find.byKey(const ValueKey('customer-search')), findsNothing);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'Customer ${long ? 'Long Name' : 'Columns'} ${width.toInt()}',
        );
        await tap(tester, edit);
        expect(find.byKey(const ValueKey('design-field-Name')), findsOneWidget);
        await capture(
          tester,
          'Customer Edit ${long ? 'Long Name' : 'Ordinary'} ${width.toInt()}',
        );
        if (width == 1224 && !long) {
          final directory = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
          if (directory != null) {
            final owner = tester.widget<FrontendFormDialog>(
              find.byType(FrontendFormDialog),
            );
            File('$directory/Actual Customer Form Definition.json')
                .writeAsStringSync(
                  jsonEncode({
                    'owner': 'CustomerPage._edit using FrontendFormDialog',
                    'scope': 'Actual populated edit entry. Definition is not proof of conditional visibility or QuickBooks parity.',
                    'fields': [
                      for (final field in owner.form.fields)
                        {
                          'label': field.label,
                          'options': field.options,
                          'required': field.required,
                          'multiline': field.multiline,
                          'toggle': field.toggle,
                        },
                    ],
                  }),
                );
          }
        }
        await tap(tester, accountingCloseIcon().first);
        expect(
          customerFormValues(
            w.customers().singleWhere((c) => c.id == customer.id),
          ),
          before,
        );
      });
    }
  }

  testWidgets('actual edit saves a customer without inventing an address', (
    tester,
  ) async {
    await prepare(tester, 1224);
    final dir = Directory.systemTemp.createTempSync('audyt-customer-owner-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await createDemoWorkspace(databasePath: path);
    addTearDown(() => w.dispose());
    final customer = w.customers().firstWhere(
      (c) => c.displayName == 'Meridian Trading',
    );
    expect(customer.billingAddress, isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: CustomerPage(workspace: w)),
      ),
    );
    await tester.pumpAndSettle();
    await tap(
      tester,
      find.byKey(ValueKey('edit-customer-${customer.metadata.recordId.value}')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('design-field-Name')),
      'Fictional Updated Customer',
    );
    await tap(tester, find.byKey(const ValueKey('design-review')));
    await tap(tester, find.byKey(const ValueKey('design-review')));
    final saved = w.customers().singleWhere((c) => c.id == customer.id);
    expect(saved.displayName, 'Fictional Updated Customer');
    expect(saved.billingAddress, isNull);
    expect(saved.currency.code, customer.currency.code);
    expect(saved.paymentTerms.formChoice, customer.paymentTerms.formChoice);
    expect(saved.metadata.revision, customer.metadata.revision + 1);
    final invalidCountry = customerFormValues(saved)
      ..['Country'] = 'Other Country'
      ..['Country ISO Code'] = 'NZ';
    expect(
      () => customerFromForm(
        invalidCountry,
        w,
        original: saved,
        id: saved.id,
        now: DateTime.now().toUtc(),
      ),
      throwsFormatException,
      reason: 'Choosing Other Country still requires its entered name.',
    );
    final invalidCode = customerFormValues(saved)
      ..['Address Line 1'] = 'Fictional entered address'
      ..['Country'] = 'Other Country'
      ..['Country Name'] = 'Fictional Country'
      ..['Country ISO Code'] = 'N';
    expect(
      () => customerFromForm(
        invalidCode,
        w,
        original: saved,
        id: saved.id,
        now: DateTime.now().toUtc(),
      ),
      throwsFormatException,
      reason:
          'An entered address still requires a two-letter country identity.',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    w.dispose();
    w = await AccountingWorkspace.open(path);
    final reopened = w.customers().singleWhere((c) => c.id == customer.id);
    expect(customerFormValues(reopened), customerFormValues(saved));
    expect(reopened.billingAddress, isNull);
    expect(reopened.metadata.revision, saved.metadata.revision);
  });
}
