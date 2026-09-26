import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalogue IDs, grouping and historical line snapshots survive reopen and archive restore', () async {
    final root = Directory.systemTemp.createTempSync('audyt-catalogue-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    var workspace = await createDemoWorkspace(databasePath: path);
    final account = (await workspace.accounts())
        .map((r) => r.account)
        .firstWhere(
          (a) =>
              a.type == AccountType.income &&
              !a.isParent &&
              a.status == AccountStatus.active,
        );
    final category = workspace.saveCatalogueCategory(
      CatalogueCategory(id: EntityId.random(), name: ' Video '),
    );
    final item = workspace.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: category.id,
        name: 'Corporate Video',
        type: CatalogueItemType.service,
        incomeAccountId: account.id,
        description: 'Introduction',
      ),
    );
    final snapshot = item.snapshot(category);
    final line = SalesLineItem.category(
      id: EntityId.random(),
      categoryId: account.id,
      description: item.description,
      quantity: SalesQuantity.fromInt(1),
      rate: Money.fromDecimal('1234567.89', 'MYR'),
      catalogue: snapshot,
    );
    expect(
      SalesLineItem.fromJson(Map<String, dynamic>.from(line.toJson()))
          .catalogue!
          .toJson(),
      snapshot.toJson(),
    );
    expect(
      line.copyForInvoice(invoiceLineId: EntityId.random()).catalogue!.toJson(),
      snapshot.toJson(),
    );
    workspace.saveCatalogueItem(
      CatalogueItem(
        id: item.id,
        categoryId: item.categoryId,
        name: 'Renamed Video',
        type: item.type,
        incomeAccountId: account.id,
        revision: item.revision,
      ),
    );
    expect(line.catalogue!.itemName, 'Corporate Video');
    expect(line.catalogue!.categoryName, 'Video');
    final archive = workspace.database.exportDataArchive(
      workspace.identity.businessId,
      DateTime.now().toUtc(),
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(workspace.catalogueItems.single.name, 'Renamed Video');
    expect(workspace.catalogueItems.single.id, item.id);
    expect(workspace.catalogueCategories.single.id, category.id);
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    expect(
      restored.catalogueItems.single.toJson(),
      workspace.catalogueItems.single.toJson(),
    );
    expect(
      restored.catalogueCategories.single.toJson(),
      workspace.catalogueCategories.single.toJson(),
    );
    restored.dispose();
    workspace.dispose();
  });
  test('catalogue rejects duplicates, stale revisions, foreign categories/accounts and unauthorized writers', () async {
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    final account = (await workspace.accounts())
        .map((r) => r.account)
        .firstWhere(
          (a) =>
              a.type == AccountType.income &&
              !a.isParent &&
              a.status == AccountStatus.active,
        );
    final category = workspace.saveCatalogueCategory(
      CatalogueCategory(id: EntityId.random(), name: 'Video'),
    );
    expect(
      () => workspace.saveCatalogueCategory(
        CatalogueCategory(id: EntityId.random(), name: ' video '),
      ),
      throwsStateError,
    );
    expect(
      () => workspace.saveCatalogueCategory(
        CatalogueCategory(id: category.id, name: 'Other'),
      ),
      throwsStateError,
    );
    final item = workspace.saveCatalogueItem(
      CatalogueItem(
        id: EntityId.random(),
        categoryId: category.id,
        name: 'Corporate Video',
        type: CatalogueItemType.service,
        incomeAccountId: account.id,
      ),
    );
    expect(
      () => workspace.saveCatalogueItem(
        CatalogueItem(
          id: EntityId.random(),
          categoryId: category.id,
          name: 'corporate video',
          type: item.type,
          incomeAccountId: account.id,
        ),
      ),
      throwsStateError,
    );
    expect(
      () => workspace.saveCatalogueItem(
        CatalogueItem(
          id: EntityId.random(),
          categoryId: EntityId.random(),
          name: 'Foreign',
          type: item.type,
          incomeAccountId: account.id,
        ),
      ),
      throwsStateError,
    );
    expect(
      () => workspace.saveCatalogueItem(
        CatalogueItem(
          id: EntityId.random(),
          categoryId: category.id,
          name: 'Foreign',
          type: item.type,
          incomeAccountId: EntityId.random(),
        ),
      ),
      throwsStateError,
    );
    expect(
      () => workspace.database.saveCatalogueCategory(
        businessId: workspace.identity.businessId,
        actorId: EntityId.random(),
        category: CatalogueCategory(
          id: EntityId.random(),
          name: 'Unauthorized',
        ),
        savedAt: DateTime.now().toUtc(),
      ),
      throwsStateError,
    );
    expect(workspace.catalogueItems.length, 1);
    expect(workspace.catalogueCategories.length, 1);
    expect(workspace.database.readCatalogueItems(EntityId.random()), isEmpty);
  });
}
