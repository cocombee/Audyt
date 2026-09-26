import '../support/accounting_text_input.dart';

import 'package:audyt/app/accounting_description_field.dart';

import '../support/generated_document_host.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/fixed_popout_host.dart';

Future<void> _prepare(WidgetTester tester) async {
  installFixedPopoutHost(tester);
  tester.view.physicalSize = const Size(1224, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byType(AccountingCloseIcon).last);
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String section) async {
  final row = find.byKey(ValueKey('settings-editor-$section'));
  await tester.ensureVisible(row);
  await tester.tap(find.text(section).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('design-save-settings')).last;
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'actual invoice saves selected items with the approved one-line grid',
    (tester) async {
      await _prepare(tester);
      await installGeneratedDocumentHost(tester);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final account = (await workspace.accounts())
          .singleWhere((a) => a.account.code == '4000')
          .account;
      final category = workspace.saveCatalogueCategory(
        CatalogueCategory(id: EntityId.random(), name: 'Video'),
      );
      final item = workspace.saveCatalogueItem(
        CatalogueItem(
          id: EntityId.random(),
          categoryId: category.id,
          name: 'Corporate Video',
          type: CatalogueItemType.service,
          incomeAccountId: account.id,
          description: 'Company introduction video',
        ),
      );
      final customer = workspace.customers().firstWhere((c) => c.isActive);
      final originalIds = workspace
          .invoiceDrafts()
          .map((r) => r.invoice.id)
          .toSet();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(body: InvoicePage(workspace: workspace)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-invoice')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AccountingMemoSummary),
          matching: find.text('0.00'),
        ),
        findsNWidgets(3),
      );
      expect(find.text('—'), findsNothing);
      Future<void> choose(String label, String option) async {
        final selector = find.byKey(ValueKey('design-field-$label'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      await choose('Counterparty', customer.displayName);
      expect(find.byKey(const ValueKey('design-field-Tax Mode')), findsNothing);
      expect(find.byKey(const ValueKey('design-document-tax')), findsOneWidget);
      await choose('Make Recurring', 'Monthly');
      expect(
        find.byKey(const ValueKey('design-field-Start Date')),
        findsOneWidget,
      );
      Finder selector(String label) => find.byWidgetPredicate(
        (w) =>
            w is AccountingSelector<String> &&
            w.triggerKey is ValueKey &&
            (w.triggerKey as ValueKey).value.toString().endsWith('-$label'),
      );
      Finder input(String label) => find.byWidgetPredicate(
        (w) =>
            (w is TextFormField || w is AccountingDescriptionField) &&
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().endsWith('-$label'),
      );
      await tester.ensureVisible(selector('Product / Service').first);
      await tester.tap(selector('Product / Service').first);
      await tester.pumpAndSettle();
      expect(find.text('Video'), findsNothing);
      await tester.tap(find.text('Corporate Video').last);
      await tester.pumpAndSettle();
      expect(
        accountingDescriptionText('Company introduction video'),
        findsOneWidget,
      );
      await enterAccountingText(tester, input('Amount').first, '1234567.89');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('design-add-line')));
      await tester.pumpAndSettle();
      await tester.tap(selector('Product / Service').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corporate Video').last);
      await tester.pumpAndSettle();
      await enterAccountingText(tester, input('Amount').last, '2450');
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('design-field-Memo')),
        'Catalogue UI save',
      );
      await tester.pumpAndSettle();
      final boxes = [
        selector('Product / Service').first,
        input('Description').first,
        input('Amount').first,
      ];
      final rects = boxes.map(tester.getRect).toList();
      expect(rects.map((r) => r.top).toSet().length, 1);
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left - rects[i - 1].right, closeTo(10, .1));
      }
      expect(
        tester.getRect(input('Amount').last).top -
            rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b),
        closeTo(10, .1),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('design-add-line'))).left -
            rects.last.right,
        closeTo(20, .1),
      );
      expect(find.text('Amount (RM)'), findsOneWidget);
      expect(find.text('Account'), findsNothing);
      expect(find.text('Qty'), findsNothing);
      await captureUi(tester, 'Invoice Live Catalogue');
      final review = find.byKey(const ValueKey('design-review'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await pumpGeneratedDocumentWork(tester);
      await tester.tap(review);
      await pumpGeneratedDocumentWork(tester);
      final saved = workspace
          .invoiceDrafts()
          .singleWhere((r) => !originalIds.contains(r.invoice.id))
          .invoice;
      expect(saved.memo, 'Catalogue UI save');
      expect(saved.lines.length, 2);
      expect(saved.total.minorUnits, 123701789);
      expect(
        saved.lines.every((line) => line.catalogue!.itemId == item.id),
        true,
      );
      expect(
        saved.lines.every((line) => line.catalogue!.categoryId == category.id),
        true,
      );
      expect(saved.lines.every((line) => line.categoryId == account.id), true);
      final schedule = workspace.database
          .documentSchedules(workspace.identity.businessId)
          .single;
      expect(schedule.sourceId, saved.id.value);
      expect(schedule.sourceRevision, 1);
      expect(schedule.schedule.every, 1);
      final edit = find.byKey(ValueKey('edit-invoice-${saved.id.value}'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final recurrence = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey == const ValueKey('design-field-Make Recurring'),
        ),
      );
      expect(recurrence.value, 'Monthly');
      expect(recurrence.enabled, false);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main and invoice shortcut share preferences, keep draft values and survive reopen',
    (tester) async {
      await _prepare(tester);
      final root = Directory.systemTemp.createTempSync('audyt-shortcut-');
      addTearDown(() => root.deleteSync(recursive: true));
      var workspace = await createDemoWorkspace(
        databasePath: '${root.path}/books.sqlite',
      );
      addTearDown(() => workspace.dispose());
      workspace.savePreferences(
        workspace.preferences.change('Sales Preferences', {
          'Show Rate': false,
          'Enable Discounts': false,
          'Customer Message': 'Keep this message',
        }),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () =>
                          openAccountingSettings(context, workspace: workspace),
                      child: const Text('Main Settings'),
                    ),
                  ),
                  Expanded(child: InvoicePage(workspace: workspace)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Settings'));
      await tester.pumpAndSettle();
      await _expand(tester, 'Sales Preferences');
      final quantity = find.byKey(const ValueKey('design-field-Show Rate'));
      expect(tester.widget<AccountingSwitchListTile>(quantity).value, false);
      await tester.tap(quantity);
      await _save(tester);
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Show Rate'),
        true,
      );
      await _close(tester);
      await tester.tap(find.byKey(const ValueKey('new-invoice')));
      await tester.pumpAndSettle();
      final description = find.byWidgetPredicate(
        (w) =>
            w is AccountingDescriptionField &&
            w.decoration?.hintText == 'Description',
      );
      await tester.ensureVisible(description);
      await enterAccountingText(tester, description, 'Draft service');
      final shortcut = find.byKey(
        const ValueKey('transaction-settings-shortcut'),
      );
      final footer = find.byKey(
        const ValueKey('accounting-form-dialog-footer'),
      );
      expect(
        tester.getRect(shortcut).left - tester.getRect(footer).left,
        closeTo(accountingContentInset, .1),
      );
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.text('Business Profile'), findsNothing);
      expect(find.text('Purchase Preferences'), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-section-expense')),
        findsNothing,
      );
      await _expand(tester, 'Sales Preferences');
      expect(tester.widget<AccountingSwitchListTile>(quantity).value, true);
      final discount = find.byKey(
        const ValueKey('design-field-Enable Discounts'),
      );
      expect(tester.widget<AccountingSwitchListTile>(discount).value, false);
      await tester.tap(discount);
      await _save(tester);
      await captureUi(tester, 'Invoice Settings Shortcut');
      await _close(tester);
      expect(accountingDescriptionText('Draft service'), findsOneWidget);
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Keep this message',
      );
      await tester.tap(find.byKey(const ValueKey('design-close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('design-discard-changes')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Settings'));
      await tester.pumpAndSettle();
      await _expand(tester, 'Sales Preferences');
      expect(tester.widget<AccountingSwitchListTile>(discount).value, true);
      await _close(tester);
      final revision = workspace.preferences.revision;
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open('${root.path}/books.sqlite');
      expect(workspace.preferences.revision, revision);
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Enable Discounts'),
        true,
      );
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Keep this message',
      );
      final other = await createDemoWorkspace();
      expect(
        other.preferences.text('Sales Preferences', 'Customer Message'),
        isEmpty,
      );
      other.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'item registration uses four equal selectors and the actual scoped income setting',
    (tester) async {
      await _prepare(tester);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final income = (await workspace.accounts())
          .singleWhere((a) => a.account.code == '4000')
          .account;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCatalogueItemDialog(context, workspace),
                  child: const Text('Add Item'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();
      final widths = [
        for (final name in ['type', 'tax', 'category', 'item-name'])
          tester.getSize(find.byKey(ValueKey('catalogue-$name'))).width,
      ];
      expect(widths.every((w) => (w - widths.first).abs() < .1), true);
      expect(find.text('Price'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('catalogue-settings-shortcut')),
      );
      await tester.pumpAndSettle();
      await _expand(tester, 'Default Accounts');
      expect(
        find.byKey(const ValueKey('design-field-Receivables Account')),
        findsNothing,
      );
      final account = find.byKey(const ValueKey('design-field-Income Account'));
      await tester.tap(account);
      await tester.pumpAndSettle();
      await tester.tap(find.text('${income.code} · ${income.name}').last);
      await tester.pumpAndSettle();
      await _save(tester);
      expect(
        workspace.preferences.text('Default Accounts', 'Income Account'),
        income.id.value,
      );
      await _close(tester);
      await tester.tap(find.byKey(const ValueKey('catalogue-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Category').last);
      await tester.pumpAndSettle();
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('catalogue-manual-name')),
        'Video',
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalogue-item-name')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Item').last);
      await tester.pumpAndSettle();
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('catalogue-manual-name')),
        'Corporate Video',
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('catalogue-description')),
        'Company introduction',
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Product Service Live Registration');
      await tester.tap(find.byKey(const ValueKey('catalogue-save-item')));
      await tester.pumpAndSettle();
      expect(workspace.catalogueItems.single.name, 'Corporate Video');
      expect(
        workspace.catalogueItems.single.categoryId,
        workspace.catalogueCategories.single.id,
      );
      expect(workspace.catalogueCategories.single.name, 'Video');
      expect(workspace.catalogueItems.single.incomeAccountId, income.id);
      expect(
        workspace.catalogueItems.single.description,
        'Company introduction',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
