import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../sales/domain/invoice_tax.dart';

import 'company_tax_agency.dart';

enum TaxApplication { sales, purchases, both }

/// Explicit company data, never a statutory or inferred tax rate.
final class CompanyTaxRate {
  CompanyTaxRate({
    required this.id,
    required String name,
    required String percent,
    required DateTime effectiveFrom,
    DateTime? effectiveThrough,
    required this.application,
    this.accountId,
    this.agencySnapshot,
    this.description = '',
    this.active = true,
    this.revision = 0,
  }) : name = name.trim(),
       percent = percent.trim(),
       effectiveFrom = accountingCalendarDate(effectiveFrom),
       effectiveThrough = effectiveThrough == null
           ? null
           : accountingCalendarDate(effectiveThrough) {
    if (this.name.isEmpty ||
        this.name.length > 200 ||
        description.length > 4000 ||
        revision < 0) {
      throw const FormatException('Enter a tax name and valid description.');
    }
    if (accountId == null && application != TaxApplication.purchases) {
      throw const FormatException('Sales tax requires a liability account.');
    }
    if (agencySnapshot != null && agencySnapshot!.revision < 1) {
      throw const FormatException('Choose a saved tax agency revision.');
    }
    InvoiceTaxRate.fromPercent(this.percent);
    if (this.effectiveThrough?.isBefore(this.effectiveFrom) ?? false) {
      throw const FormatException(
        'Effective Through must follow Effective From.',
      );
    }
  }
  final EntityId id;
  // A purchase-only cost code has no separate tax posting account. Existing
  // v1 mappings stay retained even though purchase posting uses gross cost.
  final EntityId? accountId;
  final CompanyTaxAgency? agencySnapshot;
  EntityId get salesAccountId {
    if (application == TaxApplication.purchases || accountId == null) {
      throw StateError(
        'This purchase tax code has no sales liability mapping.',
      );
    }
    return accountId!;
  }

  final String name, percent, description;
  final DateTime effectiveFrom;
  final DateTime? effectiveThrough;
  final TaxApplication application;
  final bool active;
  final int revision;
  String get choice => '${id.value}:$revision:$percent';
  String get label => '$name · $percent%';
  bool applies(
    DateTime date,
    TaxApplication purpose, {
    bool requireActive = true,
  }) {
    final day = accountingCalendarDate(date);
    return (!requireActive || active) &&
        !day.isBefore(effectiveFrom) &&
        !(effectiveThrough != null && day.isAfter(effectiveThrough!)) &&
        (application == TaxApplication.both || application == purpose);
  }

  Map<String, Object?> toJson() => {
    'version': agencySnapshot != null ? 3 : (accountId == null ? 2 : 1),
    if (agencySnapshot != null) 'agency': agencySnapshot!.toJson(),
    'id': id.value,
    'account': accountId?.value,
    if (accountId == null) 'purchaseAccounting': 'cost',
    'name': name,
    'percent': percent,
    'from': effectiveFrom.toIso8601String(),
    'through': effectiveThrough?.toIso8601String(),
    'application': application.name,
    'description': description,
    'active': active,
    'revision': revision,
  };
  factory CompanyTaxRate.fromJson(Map<String, dynamic> j) {
    if (!const {1, 2, 3}.contains(j['version']) ||
        j['version'] != 3 && j['agency'] != null ||
        j['version'] == 3 &&
            (j['agency'] is! Map ||
                j['account'] != null && j['purchaseAccounting'] != null ||
                j['account'] == null &&
                    (j['application'] != 'purchases' ||
                        j['purchaseAccounting'] != 'cost')) ||
        j['version'] == 1 && j['account'] == null ||
        j['version'] == 2 &&
            (j['account'] != null ||
                j['application'] != 'purchases' ||
                j['purchaseAccounting'] != 'cost')) {
      throw const FormatException('Unsupported tax code accounting contract.');
    }
    return CompanyTaxRate(
      id: EntityId.parse(j['id'] as String),
      accountId: j['account'] == null
          ? null
          : EntityId.parse(j['account'] as String),
      agencySnapshot: j['agency'] == null
          ? null
          : CompanyTaxAgency.fromJson(
              Map<String, dynamic>.from(j['agency'] as Map),
            ),
      name: j['name'] as String,
      percent: j['percent'] as String,
      effectiveFrom: DateTime.parse(j['from'] as String),
      effectiveThrough: j['through'] == null
          ? null
          : DateTime.parse(j['through'] as String),
      application: TaxApplication.values.byName(j['application'] as String),
      description: j['description'] as String,
      active: j['active'] as bool,
      revision: j['revision'] as int,
    );
  }
}

String taxPercent(String value) =>
    value.contains(':') ? value.split(':').last : value;
CompanyTaxRate? resolveTaxChoice(
  String choice, {
  required List<CompanyTaxRate> codes,
  required DateTime date,
  required TaxApplication purpose,
  CompanyTaxRate? saved,
}) {
  if (!choice.contains(':')) return null;
  if (saved?.choice == choice &&
      saved!.applies(date, purpose, requireActive: false)) {
    return saved;
  }
  final selected = codes
      .where((r) => r.choice == choice && r.applies(date, purpose))
      .firstOrNull;
  if (selected == null) {
    throw StateError(
      'Tax code changed or is unavailable for this date. Review the line.',
    );
  }
  return selected;
}
