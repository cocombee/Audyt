part of 'accounting_database.dart';

extension CatalogueDatabase on LocalAccountingDatabase {
  void _validateSalesCatalogueReferences(
    EntityId businessId,
    Invoice invoice, {
    bool quotation = false,
    List<SalesLineItem>? retainedLines,
  }) {
    final historical = <SalesLineItem>[...?retainedLines];
    final table = quotation ? 'quotation_drafts' : 'invoice_drafts';
    for (final row in _database.select(
      'SELECT payload FROM $table WHERE business_id=? AND id=?',
      [businessId.value, invoice.id.value],
    )) {
      final json = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      historical.addAll(
        quotation
            ? Estimate.fromSnapshot(json).lines
            : Invoice.fromDraftSnapshot(json).lines,
      );
    }
    if (!quotation && invoice.sourceEstimateId != null) {
      for (final row in _database.select(
        'SELECT payload FROM quotation_drafts WHERE business_id=? AND id=?',
        [businessId.value, invoice.sourceEstimateId!.value],
      )) {
        historical.addAll(
          Estimate.fromSnapshot(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ).lines,
        );
      }
    }
    for (final line in invoice.lines) {
      final snapshot = line.catalogue;
      if (snapshot == null) continue;
      final preserved = historical.any(
        (saved) =>
            (saved.id == line.id || saved.id == line.sourceLineId) &&
            saved.categoryId == line.categoryId &&
            saved.catalogue != null &&
            jsonEncode(saved.catalogue!.toJson()) ==
                jsonEncode(snapshot.toJson()),
      );
      if (preserved) continue;
      final items = _database.select(
        'SELECT payload FROM catalogue_items WHERE business_id=? AND id=? AND active=1',
        [businessId.value, snapshot.itemId.value],
      );
      if (items.isEmpty) {
        throw StateError('Choose an active catalogue item in this company.');
      }
      final item = CatalogueItem.fromJson(
        jsonDecode(items.single['payload'] as String) as Map<String, dynamic>,
      );
      final categories = readCatalogueCategories(businessId);
      final category = categories
          .where((c) => c.id == item.categoryId)
          .firstOrNull;
      if (category == null ||
          item.incomeAccountId != line.categoryId ||
          jsonEncode(item.snapshot(category).toJson()) !=
              jsonEncode(snapshot.toJson())) {
        throw StateError(
          'The selected item changed. Reload its name, category and accounting mapping before saving.',
        );
      }
    }
  }

  List<CatalogueCategory> readCatalogueCategories(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT id,name,revision FROM catalogue_categories WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
          [businessId.value],
        )
        .map(
          (row) => CatalogueCategory(
            id: EntityId.parse(row['id'] as String),
            name: row['name'] as String,
            revision: row['revision'] as int,
          ),
        )
        .toList(growable: false);
  }

  CatalogueCategory saveCatalogueCategory({
    required EntityId businessId,
    required EntityId actorId,
    required CatalogueCategory category,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final rows = _database.select(
        'SELECT revision FROM catalogue_categories WHERE business_id=? AND id=?',
        [businessId.value, category.id.value],
      );
      final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
      if (revision != category.revision) {
        throw StateError('Category changed. Reopen before saving.');
      }
      if (_database.select(
        'SELECT id FROM catalogue_categories WHERE business_id=? AND normalized_name=? AND id<>?',
        [businessId.value, category.name.toLowerCase(), category.id.value],
      ).isNotEmpty) {
        throw StateError(
          'This category already exists. Select its saved name.',
        );
      }
      _database.execute(
        'INSERT INTO catalogue_categories(business_id,id,name,normalized_name,revision) VALUES (?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,normalized_name=excluded.normalized_name,revision=excluded.revision',
        [
          businessId.value,
          category.id.value,
          category.name,
          category.name.toLowerCase(),
          revision + 1,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'catalogue_category_saved',
        subjectId: category.id,
        detail: jsonEncode({'revision': revision + 1}),
      );
    });
    return readCatalogueCategories(businessId)
        .singleWhere((c) => c.id == category.id);
  }

  List<CatalogueItem> readCatalogueItems(
    EntityId businessId, {
    bool activeOnly = false,
  }) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM catalogue_items WHERE business_id=? ${activeOnly ? 'AND active=1' : ''} ORDER BY name COLLATE NOCASE,id',
          [businessId.value],
        )
        .map(
          (row) => CatalogueItem.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  CatalogueItem saveCatalogueItem({
    required EntityId businessId,
    required EntityId actorId,
    required CatalogueItem item,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final rows = _database.select(
        'SELECT revision FROM catalogue_items WHERE business_id=? AND id=?',
        [businessId.value, item.id.value],
      );
      final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
      if (revision != item.revision) {
        throw StateError('Item changed. Reopen before saving.');
      }
      if (_database.select(
        'SELECT id FROM catalogue_items WHERE business_id=? AND normalized_name=? AND id<>?',
        [businessId.value, item.name.toLowerCase(), item.id.value],
      ).isNotEmpty) {
        throw StateError('This item already exists. Select its saved name.');
      }
      if (_database.select(
        'SELECT 1 FROM catalogue_categories WHERE business_id=? AND id=?',
        [businessId.value, item.categoryId.value],
      ).isEmpty) {
        throw StateError('Choose a category in this company.');
      }
      final account = _database.select(
        "SELECT 1 FROM accounts WHERE business_id=? AND id=? AND type='income' AND status='active' AND is_parent=0",
        [businessId.value, item.incomeAccountId.value],
      );
      if (account.isEmpty) {
        throw StateError(
          'Set an active Income Account in company Settings before saving an item.',
        );
      }
      final payload = {...item.toJson(), 'revision': revision + 1};
      _database.execute(
        'INSERT INTO catalogue_items(business_id,id,category_id,income_account_id,name,normalized_name,active,revision,payload) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET category_id=excluded.category_id,income_account_id=excluded.income_account_id,name=excluded.name,normalized_name=excluded.normalized_name,active=excluded.active,revision=excluded.revision,payload=excluded.payload',
        [
          businessId.value,
          item.id.value,
          item.categoryId.value,
          item.incomeAccountId.value,
          item.name,
          item.name.toLowerCase(),
          item.active ? 1 : 0,
          revision + 1,
          jsonEncode(payload),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'catalogue_item_saved',
        subjectId: item.id,
        detail: jsonEncode({
          'revision': revision + 1,
          'category': item.categoryId.value,
        }),
      );
    });
    return readCatalogueItems(businessId).singleWhere((i) => i.id == item.id);
  }
}
