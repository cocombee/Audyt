import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [480.0, 720.0, 1224.0]) {
    testWidgets(
      'actual Item preview fits ordinary fields and never saves at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final category = w.saveCatalogueCategory(
          CatalogueCategory(id: EntityId.random(), name: 'Video'),
        );
        final account = (await w.accounts())
            .firstWhere((r) => r.account.code == '4000')
            .account;
        final item = w.saveCatalogueItem(
          CatalogueItem(
            id: EntityId.random(),
            categoryId: category.id,
            name: 'Corporate Video',
            type: CatalogueItemType.service,
            incomeAccountId: account.id,
            description: 'A full production package.',
          ),
        );
        final original = item.toJson();
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CatalogueItemDialog(
                      workspace: w,
                      initial: item,
                      preview: const CatalogueItemPreview(),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final ordinaryKeys = ['name', 'code', 'sku'];
        final dialog = tester.getRect(find.byType(AlertDialog));
        for (final key in ordinaryKeys) {
          final input = find.byKey(ValueKey('catalogue-preview-$key'));
          final rect = tester.getRect(input);
          expect(rect.left, greaterThanOrEqualTo(dialog.left));
          expect(rect.right, lessThanOrEqualTo(dialog.right));
          expect(rect.height, accountingControlHeight);
        }
        expect(find.byKey(const ValueKey('catalogue-item-name')), findsNothing);
        expect(find.byKey(const ValueKey('catalogue-tax')), findsNothing);
        expect(find.text('Price / Rate (RM)'), findsOneWidget);
        final rate = find.byKey(const ValueKey('catalogue-preview-rate'));
        expect(tester.getSize(rate).width, lessThan(240));
        expect(tester.widget<TextField>(rate).decoration!.prefixIcon, isNull);
        expect(
          tester
              .widget<AccountingDescriptionField>(
                find.byKey(const ValueKey('catalogue-description')),
              )
              .fixedLines,
          AccountingDescriptionTokens.defaultFixedLines,
        );
        final income = tester.widget<AccountingSelector<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey == const ValueKey('catalogue-preview-income'),
          ),
        );
        expect(
          income.options.map((o) => o.label),
          contains(account.displayName),
        );
        expect(
          income.options.any((o) => o.label.contains('Operating Expenses')),
          isFalse,
        );
        final keep = find.byKey(const ValueKey('catalogue-preview-keep'));
        await tester.ensureVisible(keep);
        await tester.tap(keep);
        await tester.pumpAndSettle();
        expect(find.text('Enter a Code Name.'), findsOneWidget);
        final code = find.byKey(const ValueKey('catalogue-preview-code'));
        await tester.ensureVisible(code);
        await tester.enterText(code, 'bad/name');
        await tester.ensureVisible(keep);
        await tester.tap(keep);
        await tester.pumpAndSettle();
        expect(find.text('Enter a filename-safe Code Name.'), findsOneWidget);
        await tester.ensureVisible(code);
        await tester.enterText(code, 'CV');
        final name = find.byKey(const ValueKey('catalogue-preview-name'));
        await tester.enterText(name, 'Changed video');
        await tester.ensureVisible(keep);
        await tester.tap(keep);
        await tester.pumpAndSettle();
        expect(
          find.text('Preview kept · No catalogue records saved.'),
          findsOneWidget,
        );
        expect(w.catalogueItems.single.toJson(), original);
        expect(w.catalogueCategories.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Item preview uses workspace currency and its precision', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync(
      'audyt-catalogue-currency-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/accounting.db';
    final database = LocalAccountingDatabase.open(path);
    await database.openWorkspace(
      newBusinessId: EntityId.random(),
      newDeviceId: EntityId.random(),
      newOwnerId: EntityId.random(),
      defaultCurrency: 'JPY',
    );
    database.close();
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    await w.createAccount(
      code: '4000',
      name: 'Services',
      type: AccountType.income,
    );
    final account = (await w.accounts()).single.account;
    final category = w.saveCatalogueCategory(
      CatalogueCategory(id: EntityId.random(), name: 'Services'),
    );
    final item = w.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: category.id,
        name: 'Production',
        type: CatalogueItemType.service,
        incomeAccountId: account.id,
      ),
    );
    final original = item.toJson();
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CatalogueItemDialog(
                  workspace: w,
                  initial: item,
                  preview: const CatalogueItemPreview(code: 'PROD'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Price / Rate (¥)'), findsOneWidget);
    expect(find.text('Price / Rate (RM)'), findsNothing);
    final rate = find.byKey(const ValueKey('catalogue-preview-rate'));
    expect(tester.widget<TextField>(rate).controller!.text, '0');
    await tester.enterText(rate, '1234');
    final keep = find.byKey(const ValueKey('catalogue-preview-keep'));
    await tester.ensureVisible(keep);
    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(
      find.text('Preview kept · No catalogue records saved.'),
      findsOneWidget,
    );
    expect(w.catalogueItems.single.toJson(), original);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'nested preview category creation and cancellation never write the workspace',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CatalogueItemDialog(
                    workspace: w,
                    preview: const CatalogueItemPreview(code: 'CV'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final category = find.byKey(const ValueKey('catalogue-preview-category'));
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Category'));
      await tester.pumpAndSettle();
      expect(find.text('Add Category · Proposed'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('catalogue-manual-name')),
        'Video',
      );
      await tester.enterText(
        find.byKey(const ValueKey('catalogue-category-code')),
        'VID',
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      expect(w.catalogueCategories, isEmpty);
      expect(
        tester
            .widget<AccountingSelector<String>>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is AccountingSelector<String> &&
                    widget.triggerKey ==
                        const ValueKey('catalogue-preview-category'),
              ),
            )
            .options
            .any((o) => o.label == 'Video'),
        isTrue,
      );
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalogue-cancel-name')));
      await tester.pumpAndSettle();
      expect(w.catalogueCategories, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalogue-preview-cancel')),
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-preview-cancel')));
      await tester.pumpAndSettle();
      expect(w.catalogueCategories, isEmpty);
      expect(w.catalogueItems, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Item Settings shortcut keeps its real field owner but changes only the new preview default',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      final income = (await w.accounts())
          .firstWhere((r) => r.account.code == '4000')
          .account;
      final before = w.preferences.text('Default Accounts', 'Income Account');
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CatalogueItemDialog(
                    workspace: w,
                    preview: const CatalogueItemPreview(code: 'CV'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final shortcut = find.byKey(
        const ValueKey('catalogue-preview-settings-shortcut'),
      );
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.text('Product / Service Settings'), findsOneWidget);
      final settings = find.byType(FrontendFormDialog);
      expect(tester.widget<FrontendFormDialog>(settings).onCommit, isNull);
      await tester.tap(
        find.byKey(const ValueKey('design-field-Income Account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(income.displayName).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: settings, matching: find.text('Preview')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: settings, matching: find.text('Keep Preview')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FrontendFormDialog), findsNothing);
      final selector = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey == const ValueKey('catalogue-preview-income'),
        ),
      );
      expect(selector.value, income.id.value);
      expect(w.preferences.text('Default Accounts', 'Income Account'), before);
      expect(w.catalogueCategories, isEmpty);
      expect(w.catalogueItems, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
