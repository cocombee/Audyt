import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const branches = [
  CatalogueCategoryBranch(id: 'video', name: 'Video'),
  CatalogueCategoryBranch(
    id: 'commercial',
    name: 'Commercial',
    parentId: 'video',
  ),
  CatalogueCategoryBranch(
    id: 'campaign',
    name: 'Regional Campaigns',
    parentId: 'commercial',
  ),
  CatalogueCategoryBranch(id: 'photo', name: 'Photography'),
  CatalogueCategoryBranch(
    id: 'orphan',
    name: 'Unknown Parent',
    parentId: 'missing',
  ),
  CatalogueCategoryBranch(id: 'cycle-a', name: 'Loop A', parentId: 'cycle-b'),
  CatalogueCategoryBranch(id: 'cycle-b', name: 'Loop B', parentId: 'cycle-a'),
];

void main() {
  test('category preview ancestry rejects self, descendants, missing and cyclic parents', () {
    expect(
      catalogueCategoryPath('campaign', branches),
      'Video / Commercial / Regional Campaigns',
    );
    expect(
      catalogueCategoryPath('commercial', branches, excluding: 'commercial'),
      isNull,
    );
    expect(
      catalogueCategoryPath('campaign', branches, excluding: 'commercial'),
      isNull,
    );
    expect(catalogueCategoryPath('orphan', branches), isNull);
    expect(catalogueCategoryPath('cycle-a', branches), isNull);
    expect(
      catalogueCategoryPath('video', [...branches, branches.first]),
      isNull,
    );
  });

  for (final width in [480.0, 720.0, 1224.0]) {
    testWidgets('actual managed category Edit/Keep/Cancel proposal at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final before = workspace.catalogueCategories
          .map((c) => c.toJson())
          .toList();
      CatalogueNamePreview? kept;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  kept = await showDialog<CatalogueNamePreview>(
                    context: context,
                    builder: (_) => const CatalogueNameDialog(
                      title: 'Edit Category',
                      preview: true,
                      hierarchyPreview: true,
                      categoryId: 'commercial',
                      initialName: 'Commercial',
                      initialCode: 'COM',
                      initialParentId: 'video',
                      parentChoices: branches,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      await open();
      final parent = find.byKey(const ValueKey('catalogue-category-parent'));
      final selector = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey == const ValueKey('catalogue-category-parent'),
        ),
      );
      expect(selector.options.map((o) => o.label).toList(), [
        'Video',
        'Photography',
      ]);
      final dialog = tester.getRect(find.byType(AlertDialog));
      for (final key in [
        'catalogue-manual-name',
        'catalogue-category-code',
        'catalogue-category-parent',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(dialog.left));
        expect(rect.right, lessThanOrEqualTo(dialog.right));
        expect(rect.height, accountingControlHeight);
      }
      await tester.tap(parent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photography').last);
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('catalogue-category-subcategory'),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(parent, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingSelector<String>>(
              find.byWidgetPredicate(
                (w) =>
                    w is AccountingSelector<String> &&
                    w.triggerKey == const ValueKey('catalogue-category-parent'),
              ),
            )
            .value,
        'photo',
      );
      await tester.enterText(
        find.byKey(const ValueKey('catalogue-manual-name')),
        'Corporate',
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      expect(kept!.name, 'Corporate');
      expect(kept!.categoryId, 'commercial');
      expect(kept!.parentId, 'photo');
      expect(
        workspace.catalogueCategories.map((c) => c.toJson()).toList(),
        before,
      );
      await open();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      expect(kept!.parentId, isNull);
      expect(kept!.categoryId, 'commercial');
      await open();
      await tester.tap(find.byKey(const ValueKey('catalogue-cancel-name')));
      await tester.pumpAndSettle();
      expect(kept, isNull);
      expect(
        workspace.catalogueCategories.map((c) => c.toJson()).toList(),
        before,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'inline creation omits management branch; invalid parent cannot be kept',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(
            body: CatalogueNameDialog(title: 'Add Category', preview: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('catalogue-category-subcategory')),
        findsNothing,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(
            body: CatalogueNameDialog(
              key: ValueKey('managed-category-invalid-parent'),
              title: 'Edit Category',
              preview: true,
              hierarchyPreview: true,
              categoryId: 'commercial',
              initialName: 'Commercial',
              initialCode: 'COM',
              initialParentId: 'campaign',
              parentChoices: branches,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a valid Parent Category.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'managed creation requires parent and fits full-path menu at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        CatalogueNamePreview? kept;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    kept = await showDialog<CatalogueNamePreview>(
                      context: context,
                      builder: (_) => const CatalogueNameDialog(
                        title: 'Add Category',
                        preview: true,
                        hierarchyPreview: true,
                        initialName: 'Social Campaigns',
                        initialCode: 'soc',
                        parentChoices: branches,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final dialogBefore = tester.getRect(find.byType(AlertDialog));
        await tester.tap(
          find.byKey(const ValueKey('catalogue-category-subcategory')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(AlertDialog)).width,
          dialogBefore.width,
        );
        await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
        await tester.pumpAndSettle();
        expect(find.text('Choose a valid Parent Category.'), findsOneWidget);
        final parent = find.byKey(const ValueKey('catalogue-category-parent'));
        final before = tester.getRect(parent);
        await tester.tap(parent);
        await tester.pumpAndSettle();
        const label = 'Video / Commercial / Regional Campaigns';
        final choice = find.text(label);
        expect(choice, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: choice, matching: find.byType(RichText)),
        );
        expect(paragraph.maxLines, 1);
        expect(paragraph.didExceedMaxLines, isFalse);
        final panel = tester.getRect(
          find.ancestor(of: choice, matching: find.byType(Material)).first,
        );
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(width));
        expect(panel.top, greaterThanOrEqualTo(before.bottom));
        expect(tester.getRect(parent), before);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('catalogue-save-name')));
        await tester.pumpAndSettle();
        expect(kept!.name, 'Social Campaigns');
        expect(kept!.code, 'SOC');
        expect(kept!.categoryId, isNull);
        expect(kept!.parentId, 'campaign');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
