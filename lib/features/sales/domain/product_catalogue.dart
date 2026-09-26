import '../../../core/ids/entity_id.dart';
import 'invoice_tax.dart';

String catalogueName(String value) {
  final name = value.trim();
  if (name.isEmpty) throw const FormatException('Enter a name.');
  return name;
}

final class CatalogueCategory {
  CatalogueCategory({required this.id, required String name, this.revision = 0})
    : name = catalogueName(name);
  final EntityId id;
  final String name;
  final int revision;
  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'revision': revision,
  };
  factory CatalogueCategory.fromJson(Map<String, dynamic> json) =>
      CatalogueCategory(
        id: EntityId.parse(json['id'] as String),
        name: json['name'] as String,
        revision: json['revision'] as int,
      );
}

enum CatalogueItemType { service, product }

/// A category is a reporting group. The income account remains a separate,
/// explicit accounting mapping inherited from the saved company default.
final class CatalogueItem {
  CatalogueItem({
    required this.id,
    required this.categoryId,
    required String name,
    required this.type,
    required this.incomeAccountId,
    this.description = '',
    this.taxRatePercent = '0',
    this.revision = 0,
    this.active = true,
  }) : name = catalogueName(name) {
    InvoiceTaxRate.fromPercent(taxRatePercent);
  }
  final EntityId id, categoryId, incomeAccountId;
  final String name, description, taxRatePercent;
  final CatalogueItemType type;
  final int revision;
  final bool active;
  Map<String, Object?> toJson() => {
    'id': id.value,
    'categoryId': categoryId.value,
    'name': name,
    'type': type.name,
    'incomeAccountId': incomeAccountId.value,
    'description': description,
    'taxRatePercent': taxRatePercent,
    'revision': revision,
    'active': active,
  };
  factory CatalogueItem.fromJson(Map<String, dynamic> json) => CatalogueItem(
    id: EntityId.parse(json['id'] as String),
    categoryId: EntityId.parse(json['categoryId'] as String),
    incomeAccountId: EntityId.parse(json['incomeAccountId'] as String),
    name: json['name'] as String,
    type: CatalogueItemType.values.byName(json['type'] as String),
    description: json['description'] as String,
    taxRatePercent: json['taxRatePercent'] as String,
    revision: json['revision'] as int,
    active: json['active'] as bool,
  );
  CatalogueLineSnapshot snapshot(CatalogueCategory category) {
    if (category.id != categoryId) {
      throw StateError('Choose the item’s saved category.');
    }
    return CatalogueLineSnapshot(
      itemId: id,
      itemName: name,
      categoryId: categoryId,
      categoryName: category.name,
      itemRevision: revision,
    );
  }
}

/// Issued lines retain their names/grouping even after catalogue edits.
final class CatalogueLineSnapshot {
  CatalogueLineSnapshot({
    required this.itemId,
    required String itemName,
    required this.categoryId,
    required String categoryName,
    required this.itemRevision,
  }) : itemName = catalogueName(itemName),
       categoryName = catalogueName(categoryName) {
    if (itemRevision < 1) throw const FormatException('Choose a saved item.');
  }
  final EntityId itemId, categoryId;
  final String itemName, categoryName;
  final int itemRevision;
  Map<String, Object?> toJson() => {
    'itemId': itemId.value,
    'itemName': itemName,
    'categoryId': categoryId.value,
    'categoryName': categoryName,
    'itemRevision': itemRevision,
  };
  factory CatalogueLineSnapshot.fromJson(Map<String, dynamic> json) =>
      CatalogueLineSnapshot(
        itemId: EntityId.parse(json['itemId'] as String),
        itemName: json['itemName'] as String,
        categoryId: EntityId.parse(json['categoryId'] as String),
        categoryName: json['categoryName'] as String,
        itemRevision: json['itemRevision'] as int,
      );
}
