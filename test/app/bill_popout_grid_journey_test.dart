import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/app/accounting_description_field.dart';

import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill;
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;

Future<void> _prepare(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installFixedPopoutHost(tester);
  await tester.runAsync(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    namingSettingsChannel,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      namingSettingsChannel,
      null,
    ),
  );
}

Finder _selector(String label) => find.byWidgetPredicate(
  (w) =>
      w is AccountingSelector<String> &&
      w.triggerKey is ValueKey &&
      (w.triggerKey as ValueKey).value.toString().endsWith('-$label'),
);

Finder _input(String label) => find.byWidgetPredicate(
  (w) =>
      (w is TextFormField || w is AccountingDescriptionField) &&
      w.key is ValueKey &&
      (w.key as ValueKey).value.toString().endsWith('-$label'),
);

Future<void> _choose(
  WidgetTester tester,
  Finder selector,
  String option,
) async {
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byType(AccountingCloseIcon).last);
  await tester.pumpAndSettle();
}

Future<void> _purchaseSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Purchase Preferences').last);
  await tester.tap(find.text('Purchase Preferences').last);
  await tester.pumpAndSettle();
}

Future<void> _saveSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('design-save-settings')).last);
  await tester.pumpAndSettle();
  await _close(tester);
}

Widget _app(AccountingWorkspace workspace, {bool mainSettings = false}) =>
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              if (mainSettings)
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        openAccountingSettings(context, workspace: workspace),
                    child: const Text('Main Settings'),
                  ),
                ),
              Expanded(child: BillsPage(workspace: workspace)),
            ],
          ),
        ),
      ),
    );

void main() {
  for (final startWidth in [720.0, 1224.0]) {
    testWidgets(
      'actual Bill grid saves two exact lines and reopens from $startWidth',
      (tester) async {
        await _prepare(tester, startWidth);
        final root = Directory.systemTemp.createTempSync('audyt-bill-grid-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        final (vendor, account) = await setupBill(w);
        await w.createAccount(
          code: '2299',
          name: 'Fictional Tax Payable',
          type: AccountType.liability,
        );
        final taxAccount = (await w.accounts())
            .singleWhere((a) => a.account.code == '2299')
            .account;
        w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '2.5',
            effectiveFrom: DateTime(2026, 1, 1),
            application: TaxApplication.purchases,
            accountId: taxAccount.id,
          ),
        );

        await tester.pumpWidget(_app(w));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('new-bill')));
        await tester.pumpAndSettle();
        final vendorSelector = _selector('Counterparty');
        expect(
          tester
              .widget<AccountingSelector<String>>(vendorSelector)
              .options
              .first
              .label,
          'Add Vendor',
        );
        await _choose(tester, vendorSelector, 'Add Vendor');
        final nestedVendorForm = tester
            .widget<FrontendFormDialog>(find.byType(FrontendFormDialog).last)
            .form;
        expect(nestedVendorForm.title, 'Vendors');
        expect(
          nestedVendorForm.fields.map((f) => f.label),
          containsAll([
            'Company Name',
            'Mobile Number',
            'Supplier Category',
            'Default Expense Category',
            'Billing Rate Per Hour',
            'Opening Balance',
            'Payment Terms',
          ]),
        );
        expect(
          nestedVendorForm.fields.any((f) => f.label == 'Supplier Terms'),
          isFalse,
        );
        await captureUi(
          tester,
          'Bill Existing Add Vendor ${startWidth.toInt()}',
        );
        await _close(tester);
        expect(
          tester.widget<AccountingSelector<String>>(vendorSelector).value,
          anyOf(isNull, ''),
        );
        await _choose(tester, vendorSelector, 'Add Vendor');
        final vendorName = find.byKey(const ValueKey('design-field-Name')).last;
        await tester.ensureVisible(vendorName);
        await enterAccountingText(tester, vendorName, 'Bill-created Vendor');
        final company = find
            .byKey(const ValueKey('design-field-Company Name'))
            .last;
        await tester.ensureVisible(company);
        await enterAccountingText(
          tester,
          company,
          'Fictional Bill Supplier Company',
        );

        final vendorReview = find.byKey(const ValueKey('design-review')).last;
        await tester.ensureVisible(vendorReview);
        await tester.tap(vendorReview);
        await tester.pumpAndSettle();
        await tester.tap(vendorReview);
        await tester.pumpAndSettle();
        final createdSelector = tester.widget<AccountingSelector<String>>(
          vendorSelector,
        );
        expect(
          createdSelector.options
              .singleWhere((o) => o.value == createdSelector.value)
              .label,
          'Bill-created Vendor',
        );
        expect(
          w.database
              .vendorDirectory(businessId: w.identity.businessId, limit: 100)
              .entries
              .any((e) => e.vendor?.name == 'Bill-created Vendor'),
          isTrue,
        );
        final billCreatedVendor = w.database
            .vendorDirectory(businessId: w.identity.businessId, limit: 100)
            .entries
            .singleWhere((e) => e.vendor?.name == 'Bill-created Vendor')
            .vendor!;
        expect(
          billCreatedVendor.additionalValues['companyName'],
          'Fictional Bill Supplier Company',
        );
        await captureUi(
          tester,
          'Bill Created Vendor Selected ${startWidth.toInt()}',
        );
        for (final rowKey in [
          'design-line-subtotal',
          'design-line-tax',
          'design-line-total',
        ]) {
          final row = find.byKey(ValueKey(rowKey));
          expect(row, findsOneWidget);
          expect(
            find.descendant(of: row, matching: find.text('0.00')),
            findsOneWidget,
          );
        }
        expect(find.text('—'), findsNothing);
        await _choose(
          tester,
          find.byKey(const ValueKey('design-field-Make Recurring')),
          'Monthly',
        );
        expect(tester.view.physicalSize.width, greaterThanOrEqualTo(848));
        expect(tester.view.physicalSize.height, 1400);
        expect(find.text('Qty'), findsNothing);
        expect(find.text('Account'), findsNothing);
        await _choose(
          tester,
          find.byKey(const ValueKey('design-field-Counterparty')),
          vendor.name,
        );
        await _choose(
          tester,
          find.byKey(const ValueKey('design-field-Currency')),
          CurrencyPresentation.fromCode('MYR').amountSymbol,
        );
        await _choose(
          tester,
          find.byKey(const ValueKey('design-field-Tax Mode')),
          'Tax Exclusive',
        );
        await _choose(tester, _selector('Account').first, account.account.name);
        await enterAccountingText(
          tester,
          _input('Description').first,
          'Corporate filing',
        );
        await enterAccountingText(tester, _input('Amount').first, '1234567.89');
        await tester.pumpAndSettle();

        // Company Tax Settings owns the selected name/percentage. Inline selection caps at its placeholder and shrinks for shorter names.
        final noTaxWidth = tester
            .getSize(_selector('Tax Rate (%)').first)
            .width;
        final noTaxDescriptionWidth = tester
            .getSize(_input('Description').first)
            .width;
        final fixedFormWidth = tester
            .getSize(
              find.byKey(const ValueKey('accounting-form-dialog-footer')),
            )
            .width;
        await _choose(
          tester,
          _selector('Tax Rate (%)').first,
          'Service Tax · 2.5%',
        );
        expect(find.text('Service Tax · 2.5%'), findsOneWidget);
        expect(find.text('30,864.20'), findsOneWidget);
        final chosenTaxWidth = tester
            .getSize(_selector('Tax Rate (%)').first)
            .width;
        expect(chosenTaxWidth, greaterThan(noTaxWidth));
        expect(
          tester.getSize(_input('Description').first).width,
          closeTo(noTaxDescriptionWidth - (chosenTaxWidth - noTaxWidth), .1),
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('accounting-form-dialog-footer')),
              )
              .width,
          fixedFormWidth,
        );
        await _choose(tester, _selector('Tax Rate (%)').first, 'No Tax');

        await tester.tap(find.byKey(const ValueKey('design-add-line')));
        await tester.pumpAndSettle();
        await _choose(tester, _selector('Account').last, account.account.name);
        await enterAccountingText(
          tester,
          _input('Description').last,
          'Compliance filing',
        );
        await enterAccountingText(tester, _input('Amount').last, '2450');
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Memo')),
          'Exact Bill UI save',
        );
        await tester.pumpAndSettle();
        final boxes = [
          _selector('Account').first,
          _input('Description').first,
          _selector('Tax Rate (%)').first,
          _input('Amount').first,
        ];
        final rects = boxes.map(tester.getRect).toList();
        expect(
          tester.getSize(_selector('Tax Rate (%)').first).width,
          noTaxWidth,
        );
        expect(
          tester.getSize(_selector('Tax Rate (%)').last).width,
          noTaxWidth,
        );
        for (final selector in [
          _selector('Account').first,
          _selector('Tax Rate (%)').first,
        ]) {
          final label = find
              .descendant(of: selector, matching: find.byType(Text))
              .first;
          final value = tester.widget<Text>(label);
          final painter = TextPainter(
            text: TextSpan(text: value.data, style: value.style),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(tester.element(label)),
          )..layout();
          final arrow = find.descendant(
            of: selector,
            matching: find.byType(AccountingSelectorChevron),
          );
          final paintedArrow = find.descendant(
            of: arrow,
            matching: find.byType(CustomPaint),
          );
          expect(
            tester.getRect(paintedArrow).left -
                tester.getRect(label).left -
                tester.getSize(label).width,
            closeTo(20, .00001),
          );
          painter.dispose();
        }
        expect(rects.map((r) => r.top).toSet().length, 1);
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left - rects[i - 1].right, closeTo(10, .1));
        }
        expect(
          tester.getRect(_input('Amount').last).top - rects.last.bottom,
          closeTo(10, .1),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('design-add-line'))).left -
              rects.last.right,
          closeTo(20, .1),
        );
        final shortcut = find.byKey(
          const ValueKey('transaction-settings-shortcut'),
        );
        final footer = find.byKey(
          const ValueKey('accounting-form-dialog-footer'),
        );
        expect(
          tester.getRect(shortcut).left - tester.getRect(footer).left,
          closeTo(20, .1),
        );
        await captureUi(tester, 'Bill Live Grid ${startWidth.toInt()}');
        final review = find.byKey(const ValueKey('design-review'));
        await tester.tap(review);
        await tester.pumpAndSettle();
        await tester.tap(review);
        await tester.pumpAndSettle();
        final saved = w.database
            .billDraftPage(businessId: w.identity.businessId)
            .records
            .single;
        expect(
          w.database.documentSchedules(w.identity.businessId).single.sourceId,
          saved.id.value,
        );
        expect(saved.total.minorUnits, 123701789);
        expect(saved.lines.length, 2);
        expect(
          saved.lines.every((line) => line.categoryId == account.account.id),
          true,
        );
        expect(saved.memo, 'Exact Bill UI save');
        await tester.tap(find.byKey(ValueKey('edit-bill-${saved.id}')));
        await tester.pumpAndSettle();
        expect(accountingDescriptionText('Corporate filing'), findsOneWidget);
        expect(accountingDescriptionText('Compliance filing'), findsOneWidget);
        expect(find.text('1,234,567.89'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(
          w.database.readBillDraft(w.identity.businessId, saved.id)!.toJson(),
          saved.toJson(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Bill shortcut and main settings persist without hiding entered pricing',
    (tester) async {
      await _prepare(tester, 1224);
      final root = Directory.systemTemp.createTempSync('audyt-bill-settings-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      addTearDown(() => w.dispose());
      final (vendor, account) = await setupBill(w);
      await tester.pumpWidget(_app(w, mainSettings: true));
      await tester.pumpAndSettle();
      final quantity = find.byKey(const ValueKey('design-field-Show Rate'));
      final discount = find.byKey(
        const ValueKey('design-field-Enable Discounts'),
      );
      final classification = find.byKey(
        const ValueKey('design-field-Show Class'),
      );
      await tester.tap(find.text('Main Settings'));
      await tester.pumpAndSettle();
      await _purchaseSettings(tester);
      await tester.tap(quantity);
      await tester.tap(discount);
      await _saveSettings(tester);
      await tester.tap(find.byKey(const ValueKey('new-bill')));
      await tester.pumpAndSettle();
      await _choose(
        tester,
        find.byKey(const ValueKey('design-field-Counterparty')),
        vendor.name,
      );
      await _choose(
        tester,
        find.byKey(const ValueKey('design-field-Tax Mode')),
        'Tax Exclusive',
      );
      await _choose(tester, _selector('Account').first, account.account.name);
      await enterAccountingText(
        tester,
        _input('Description').first,
        'Keep entered pricing',
      );
      await enterAccountingText(tester, _input('Quantity').first, '2');
      await enterAccountingText(tester, _input('Rate').first, '125.05');
      await enterAccountingText(tester, _input('Discount').first, '5');
      // Class is separately enabled through the same scoped settings owner.
      await tester.tap(
        find.byKey(const ValueKey('transaction-settings-shortcut')),
      );
      await tester.pumpAndSettle();
      await _purchaseSettings(tester);
      await tester.tap(classification);
      await _saveSettings(tester);
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('design-field-Class')),
        'Procurement',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-settings-shortcut')),
      );
      await tester.pumpAndSettle();
      await _purchaseSettings(tester);
      expect(
        find.byKey(const ValueKey('design-field-Track Items')),
        findsNothing,
      );
      expect(find.text('Sales Preferences'), findsNothing);
      expect(tester.widget<AccountingSwitchListTile>(quantity).value, true);
      expect(tester.widget<AccountingSwitchListTile>(discount).value, true);
      await tester.tap(quantity);
      await tester.tap(discount);
      await tester.tap(classification);
      await _saveSettings(tester);
      expect(accountingDescriptionText('Keep entered pricing'), findsOneWidget);
      expect(_input('Quantity'), findsOneWidget);
      expect(_input('Rate'), findsNothing);
      expect(_input('Amount'), findsOneWidget);
      expect(_input('Discount'), findsOneWidget);
      expect(find.text('Procurement'), findsOneWidget);
      final review = find.byKey(const ValueKey('design-review'));
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      final saved = w.database
          .billDraftPage(businessId: w.identity.businessId)
          .records
          .single;
      expect(saved.lines.single.quantity.toString(), '2');
      expect(saved.lines.single.rateEnabled, false);
      expect(saved.lines.single.manualAmount!.minorUnits, 25010);
      expect(saved.lines.single.discount.minorUnits, 500);
      expect(saved.total.minorUnits, 24510);
      expect(saved.classification, 'Procurement');
      await tester.tap(find.text('Main Settings'));
      await tester.pumpAndSettle();
      await _purchaseSettings(tester);
      expect(tester.widget<AccountingSwitchListTile>(quantity).value, false);
      expect(tester.widget<AccountingSwitchListTile>(discount).value, false);
      expect(
        tester.widget<AccountingSwitchListTile>(classification).value,
        false,
      );
      await _close(tester);
      final revision = w.preferences.revision;
      await tester.pumpWidget(const SizedBox());
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(w.preferences.revision, revision);
      expect(w.preferences.enabled('Purchase Preferences', 'Show Rate'), false);
      expect(
        w.preferences.enabled('Purchase Preferences', 'Enable Discounts'),
        false,
      );
      expect(
        w.preferences.enabled('Purchase Preferences', 'Show Class'),
        false,
      );
      expect(
        w.preferences.enabled('Purchase Preferences', 'Track Items'),
        true,
      );
      expect(
        w.database.readBillDraft(w.identity.businessId, saved.id)!.toJson(),
        saved.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
