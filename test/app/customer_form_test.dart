import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/data/customer_codec.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  test(
    'parent defaults seed empty fields and retain entered child details',
    () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final parent = customerFromForm(
        {
          'Name': 'Parent',
          'Email': 'parent@example.test',
          'Telephone': '12345',
          'Address Line 1': 'Parent Street',
          'Address Line 2': 'Parent Floor',
          'City': 'Parent City',
          'Country': 'Singapore',
          'Payment Terms': 'Days After Issue',
          'Number Of Days': '30',
          'Preferred Billing Currency': 'SGD',
        },
        w,
        id: EntityId.random(),
        now: DateTime.utc(2026, 1, 1),
      );
      w.saveCustomer(parent);
      expect(
        () => parent.revise(
          additionalValues: {'billParentCustomer': 'true'},
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        throwsFormatException,
      );
      final empty = customerSelectionUpdates(w, 'Parent Customer', '', {
        'Parent Customer': parent.id.value,
        'Country': 'Malaysia',
        'Country ISO Code': 'MY',
        'Payment Terms': 'Custom',
        'Custom Payment Terms': 'Child Terms',
      });
      expect(empty['Bill Parent Customer'], true);
      expect(empty['Email'], 'parent@example.test');
      expect(empty['Telephone'], '12345');
      expect(empty['Address Line 1'], 'Parent Street');
      expect(empty['Country'], 'Singapore');
      expect(empty.containsKey('Payment Terms'), false);
      expect(empty.containsKey('Preferred Billing Currency'), false);
      final typed = {
        'Parent Customer': parent.id.value,
        'Email': 'child@example.test',
        'Telephone': '98765',
        'Cc': 'copy@example.test',
        'Street Address': 'Inactive cached street',
        'Address Line 2': 'Child Floor',
        'Country': 'Malaysia',
        'Bill Parent Customer': false,
      };
      final changed = customerSelectionUpdates(
        w,
        'Parent Customer',
        'old-parent',
        typed,
      );
      expect(changed, {'Bill Parent Customer': false});
      expect(
        customerSelectionUpdates(w, 'Parent Customer', parent.id.value, typed),
        isEmpty,
      );
      expect(
        customerSelectionUpdates(w, 'Is A Sub-Customer', true, {
          ...typed,
          'Is A Sub-Customer': false,
        }),
        isEmpty,
      );
      expect(
        customerSelectionUpdates(w, 'Parent Customer', '', {
          'Parent Customer': parent.id.value,
          'Country': 'Singapore',
          '_billingCountryChosen': true,
        }).containsKey('Address Line 1'),
        false,
      );
    },
  );

  test(
    'multiline address expansion preserves semantic input and durable lines',
    () async {
      final dir = Directory.systemTemp.createTempSync('customer-address-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      final parent = customerFromForm(
        {
          'Name': 'Address Parent',
          'Payment Terms': 'Days After Issue',
          'Number Of Days': '0',
        },
        w,
        id: EntityId.random(),
        now: DateTime.utc(2026, 1, 1),
      );
      w.saveCustomer(parent);
      final values = <String, Object?>{
        'Name': 'Address Customer',
        'Is A Sub-Customer': true,
        'Parent Customer': parent.id.value,
        'Bill Parent Customer': true,
        'Payment Terms': 'Days After Issue',
        'Number Of Days': '0',
        'Country': 'Malaysia',
        'Address Line 1': 'Street One',
        'Address Line 2': 'Floor Two',
        'Same As Billing Address': false,
        'Shipping Address Line 1': 'Warehouse',
        'Shipping Address Line 2': 'Unit Three',
        'Shipping Country': 'Singapore',
      };
      final expanded = {
        ...values,
        ...customerAddressActionUpdates('Address Line 2', values),
        ...customerAddressActionUpdates('Shipping Address Line 2', values),
      };
      expect(
        customerInputValuesForComparison(expanded),
        customerInputValuesForComparison(values),
      );
      expect(expanded['Street Address'], 'Street One\nFloor Two');
      expect(expanded['Shipping Street Address'], 'Warehouse\nUnit Three');
      final saved = customerFromForm(
        expanded,
        w,
        id: EntityId.random(),
        now: DateTime.utc(2026, 1, 1),
      );
      w.saveCustomer(saved);
      w.dispose();
      w = await AccountingWorkspace.open(path);
      final restored = customerFormValues(
        w.customers().singleWhere((c) => c.displayName == 'Address Customer'),
      );
      expect(restored['Bill Parent Customer'], true);
      expect(restored['Parent Customer'], parent.id.value);
      expect(restored['_multilineBillingAddress'], true);
      expect(restored['Street Address'], 'Street One\nFloor Two');
      expect(restored['_multilineShippingAddress'], true);
      expect(restored['Shipping Street Address'], 'Warehouse\nUnit Three');
      expect(
        customerInputValuesForComparison({
          ...expanded,
          'Street Address': 'Edited Street',
        }),
        isNot(customerInputValuesForComparison(values)),
      );
      w.dispose();
    },
  );

  test(
    'customer profile roundtrips without rewriting legacy contact facts',
    () async {
      final dir = Directory.systemTemp.createTempSync('customer-profile-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final base = customerFromForm(
        {
          'Name': 'Legacy Customer',
          'Payment Terms': 'Days After Issue',
          'Number Of Days': '30',
          'Preferred Billing Currency': 'SGD',
        },
        workspace,
        id: EntityId.random(),
        now: DateTime.utc(2026, 1, 1),
      );
      final legacy = encodeCustomer(base);
      expect(legacy, contains('"version":1'));
      expect(encodeCustomer(decodeCustomer(legacy)), legacy);
      workspace.saveCustomer(base);
      final values = {
        ...customerFormValues(base),
        'Name': 'Profile Customer',
        'Company Name': 'Fictional Company',
        'Title': 'Dr',
        'First Name': 'Alex',
        'Middle Name': 'J',
        'Last Name': 'Sample',
        'Suffix': 'Jr',
        'Mobile Number': '01234',
        'Fax': '5678',
        'Other Contact': 'Office',
        'Website': 'https://example.test',
        'Cc': 'cc@example.test',
        'Bcc': 'bcc@example.test',
        'Primary Payment Method': 'Bank Draft',
        'Invoice Language': 'French',
        'Customer Category': 'Foreign Business',
        'Sales Form Delivery': 'Print Later',
        'Same As Billing Address': false,
        'Shipping Address Line 1': 'Warehouse',
        'Shipping City': 'Test City',
        'Shipping Postcode': '12345',
        'Shipping Country': 'Other Country',
        'Shipping Country Name': 'New Zealand',
        'Shipping Country ISO Code': 'NZ',
      };
      final edited = customerFromForm(
        values,
        workspace,
        original: base,
        id: base.id,
        now: DateTime.utc(2026, 1, 2),
      );
      workspace.saveCustomer(edited);
      expect(encodeCustomer(edited), contains('"version":2'));
      expect(edited.contact.contactName, 'Alex J Sample');
      expect(edited.currency.code, 'SGD');
      expect(edited.paymentTerms.days, 30);
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      final stored = workspace.customers().single;
      for (final entry in values.entries) {
        // These are inactive projections of the line inputs, not a second
        // stored address. The active and multiline paths have exact checks.
        if (const [
          'Street Address',
          'Shipping Street Address',
        ].contains(entry.key)) {
          continue;
        }
        expect(
          customerFormValues(stored)[entry.key],
          entry.value,
          reason: entry.key,
        );
      }
      final same = customerFromForm(
        {
          ...customerFormValues(stored),
          'Same As Billing Address': true,
          'Address Line 1': 'Billing Street',
          'City': 'Billing City',
          'Postcode': '50000',
          'Country': 'Malaysia',
          'Sales Form Delivery': 'Use Company Default',
        },
        workspace,
        original: stored,
        id: stored.id,
        now: DateTime.utc(2026, 1, 3),
      );
      workspace.saveCustomer(same);
      expect(same.shippingAddress?.line1, same.billingAddress?.line1);
      expect(same.preferredDelivery, CustomerDeliveryMethod.companyDefault);
      for (final bad in [
        {'Opening Balance': '100.00'},
        {
          '_files': ['unsaved.pdf'],
        },
        {'Invoice Language': 'Invented'},
        {'Primary Payment Method': 'Invented'},
        {'Same As Billing Address': false, 'Shipping Country ISO Code': 'N'},
      ]) {
        expect(
          () => customerFromForm(
            {...values, ...bad},
            workspace,
            original: stored,
            id: stored.id,
            now: DateTime.utc(2026, 1, 4),
          ),
          throwsFormatException,
        );
      }
      expect(encodeCustomer(decodeCustomer(legacy)), legacy);
      workspace.dispose();
    },
  );

  test(
    'customer parent rejects foreign, inactive and cyclic relationships',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      Customer make(String name) => customerFromForm(
        {
          'Name': name,
          'Payment Terms': 'Days After Issue',
          'Number Of Days': '0',
        },
        workspace,
        id: EntityId.random(),
        now: DateTime.utc(2026, 1, 1),
      );
      final parent = make('Parent');
      workspace.saveCustomer(parent);
      final child = make('Child').revise(
        additionalValues: {'parentCustomerId': parent.id.value},
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      // New records retain revision one; form creation selects the parent's ID.
      final freshChild = customerFromForm(
        {
          'Name': 'Child',
          'Payment Terms': 'Days After Issue',
          'Number Of Days': '0',
          'Is A Sub-Customer': true,
          'Parent Customer': parent.id.value,
        },
        workspace,
        id: child.id,
        now: DateTime.utc(2026, 1, 2),
      );
      workspace.saveCustomer(freshChild);
      expect(
        () => workspace.saveCustomer(
          parent.revise(
            additionalValues: {'parentCustomerId': freshChild.id.value},
            updatedAt: DateTime.utc(2026, 1, 3),
          ),
        ),
        throwsStateError,
      );
      final missing = make('Missing');
      expect(
        () => workspace.saveCustomer(
          customerFromForm(
            {
              ...customerFormValues(missing),
              'Is A Sub-Customer': true,
              'Parent Customer': EntityId.random().value,
            },
            workspace,
            id: missing.id,
            now: DateTime.utc(2026, 1, 3),
          ),
        ),
        throwsStateError,
      );
      workspace.saveCustomer(
        parent.deactivate(updatedAt: DateTime.utc(2026, 1, 4)),
      );
      expect(
        () => workspace.saveCustomer(
          customerFromForm(
            {
              ...customerFormValues(missing),
              'Is A Sub-Customer': true,
              'Parent Customer': parent.id.value,
            },
            workspace,
            id: missing.id,
            now: DateTime.utc(2026, 1, 5),
          ),
        ),
        throwsStateError,
      );
      workspace.saveCustomer(
        freshChild.revise(
          displayName: 'Retained Parent Child',
          updatedAt: DateTime.utc(2026, 1, 6),
        ),
      );
      expect(
        workspace
            .customers()
            .singleWhere((c) => c.id == freshChild.id)
            .additionalValues['parentCustomerId'],
        parent.id.value,
      );
    },
  );
  testWidgets('customer rows show live balances under a shared header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: CustomerPage(workspace: workspace)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final customer = workspace.customers().firstWhere(
      (customer) => customer.displayName == 'Meridian Trading',
    );
    final statement = workspace.database.customerStatement(
      workspace.identity.businessId,
      customer.id,
      DateTime.now(),
    );
    expect(statement, isNotEmpty);
    expect(statement.last.balance.minorUnits, isNot(0));
    final amount = formatAccountingMoney(
      tester.element(find.text('Meridian Trading')),
      statement.last.balance,
    );
    expect(find.text('Customer / Email'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text(amount), findsOneWidget);
    expect(find.textContaining('Due 30 days after invoice'), findsNothing);
    final name = tester.getRect(find.text('Meridian Trading'));
    final email = tester.getRect(find.text('accounts1@example.test'));
    final price = tester.getRect(find.text(amount));
    final edit = tester.getRect(
      find.byKey(ValueKey('edit-customer-${customer.metadata.recordId.value}')),
    );
    final header = tester.getRect(find.text('Balance'));
    expect(email.top - name.bottom, accountingRecordInfoLineGap);
    expect(price.center.dy, closeTo(edit.center.dy, 1));
    expect(edit.left - price.right, accountingContentInset);
    expect(header.right, closeTo(price.right, 1));
    await captureUi(tester, 'Customer Table');
  });
  testWidgets('customer balance and edit action wrap together at 390px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: CustomerPage(workspace: workspace)),
      ),
    );
    await tester.pumpAndSettle();
    final customer = workspace.customers().firstWhere(
      (item) => item.displayName == 'Meridian Trading',
    );
    final amount = formatAccountingMoney(
      tester.element(find.text('Meridian Trading')),
      workspace.database
          .customerStatement(
            workspace.identity.businessId,
            customer.id,
            DateTime.now(),
          )
          .last
          .balance,
    );
    final name = tester.getRect(find.text('Meridian Trading'));
    final price = tester.getRect(find.text(amount));
    final edit = tester.getRect(
      find.byKey(ValueKey('edit-customer-${customer.metadata.recordId.value}')),
    );
    expect(find.text('Customer'), findsOneWidget);
    expect(name.bottom, lessThan(price.top));
    expect(price.center.dy, closeTo(edit.center.dy, 1));
    expect(edit.left - price.right, accountingContentInset);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'customer page creates a durable customer through shared review',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('customer-page-');
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
          home: Scaffold(body: CustomerPage(workspace: workspace)),
        ),
      );
      expect(find.byKey(const ValueKey('customer-search')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-customer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('design-field-Name')),
        'Page Customer',
      );
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(workspace.customers().single.displayName, 'Page Customer');
      expect(find.text('Page Customer'), findsOneWidget);
      expect(find.byKey(const ValueKey('customer-search')), findsNothing);
      final values = customerFormValues(workspace.customers().single);
      for (var index = 0; index < 5; index++) {
        workspace.saveCustomer(
          customerFromForm(
            {...values, 'Name': 'Fictional Extra Customer $index'},
            workspace,
            id: EntityId.random(),
            now: DateTime.now().toUtc(),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(workspace.customers(), hasLength(6));
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('customer-search')),
      );
      expect(search.decoration!.labelText, isNull);
      expect(search.decoration!.hintText, 'Search Customers');
      expect(search.decoration!.hoverColor, Colors.transparent);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'customer form persists fields, edits, and rejects invalid terms',
    () async {
      final dir = Directory.systemTemp.createTempSync('customer-form-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final values = <String, Object?>{
        'Name': 'Test Customer',
        'Email': 'test@example.invalid',
        'Telephone': '123',
        'Party Type': 'Business',
        'Address Line 1': 'Line one',
        'Address Line 2': 'Line two',
        'City': 'City',
        'Postcode': '12345',
        'State / Region': 'Region',
        'Country': 'Other Country',
        'Country Name': 'Test Country',
        'Country ISO Code': 'NZ',
        'Customer Status': 'Active',
        'Preferred Billing Currency': 'SGD',
        'Payment Terms': 'Day Of Month',
        'Monthly Due Day': '15',
        'Rollover Within Days': '3',
        'Tax Details Needed': true,
        'Identification Type': 'Business Registration',
        'Identification Number': 'ID',
        'TIN': 'TIN',
        'SST Registration Number': 'SST',
        'Notes': 'Keep notes',
      };
      final id = EntityId.random();
      final customer = customerFromForm(
        values,
        workspace,
        id: id,
        now: DateTime.utc(2026, 9, 14),
      );
      workspace.saveCustomer(customer);
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      final stored = workspace.customers().single;
      final restored = customerFormValues(stored);
      for (final entry in values.entries) {
        expect(restored[entry.key], entry.value, reason: entry.key);
      }
      final edited = customerFromForm(
        {...restored, 'Name': 'Edited'},
        workspace,
        original: stored,
        id: id,
        now: DateTime.utc(2026, 9, 15),
      );
      workspace.saveCustomer(edited);
      expect(workspace.customers().single.metadata.revision, 2);
      expect(workspace.customers().single.profileDetails.notes, 'Keep notes');
      expect(
        () => customerFromForm(
          {...restored, 'Monthly Due Day': '32'},
          workspace,
          id: EntityId.random(),
          now: DateTime.now(),
        ),
        throwsRangeError,
      );
      expect(workspace.customers(), hasLength(1));
      workspace.dispose();
    },
  );
}
