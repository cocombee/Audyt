import 'dart:convert';

import '../../../core/ids/entity_id.dart';
import '../../../core/money/currency.dart';
import '../../../core/storage/record_metadata.dart';
import '../domain/customer.dart';

/// Versioned durable snapshot; transaction snapshots remain independent.
String encodeCustomer(Customer c) => jsonEncode({
  'version':
      c.additionalValues.isEmpty &&
          c.preferredDelivery != CustomerDeliveryMethod.companyDefault
      ? 1
      : 2,
  if (c.additionalValues.isNotEmpty) 'additionalValues': c.additionalValues,
  'id': c.id.value,
  'business': c.metadata.businessId.value,
  'device': c.metadata.originDeviceId.value,
  'created': c.metadata.createdAt.toIso8601String(),
  'updated': c.metadata.updatedAt.toIso8601String(),
  'revision': c.metadata.revision,
  'name': c.displayName,
  if (c.profileDetails.toJson().values.any(
    (value) => value != '' && value != false,
  ))
    'profileDetails': c.profileDetails.toJson(),
  'contact': {
    'name': c.contact.contactName,
    'email': c.contact.email,
    'phone': c.contact.phone,
  },
  'billing': _address(c.billingAddress),
  'shipping': _address(c.shippingAddress),
  'tax': {
    'identifier': c.taxProfile.taxIdentifier,
    'code': c.taxProfile.taxCodeId?.value,
    'exempt': c.taxProfile.isTaxExempt,
  },
  'currency': c.currency.code,
  'terms': c.paymentTerms.toJson(),
  'delivery': c.preferredDelivery.name,
  'income': c.defaultIncomeAccountId?.value,
  'taxAccount': c.defaultTaxAccountId?.value,
  'ageing': c.statementSettings.includeAging,
  'unapplied': c.statementSettings.includeUnappliedAmounts,
  'status': c.status.name,
  'audit': c.auditEventIds.map((id) => id.value).toList(),
});

Map<String, Object?>? _address(CustomerAddress? a) => a == null
    ? null
    : {
        'line1': a.line1,
        'line2': a.line2,
        'city': a.city,
        'postalCode': a.postalCode,
        'country': a.countryCode,
        'state': a.stateOrProvince,
      };

Customer decodeCustomer(String payload) {
  final j = jsonDecode(payload) as Map<String, dynamic>;
  if (j['version'] != 1 && j['version'] != 2) {
    throw const FormatException('Unsupported customer version.');
  }
  EntityId? optionalId(dynamic value) =>
      value == null ? null : EntityId.parse(value as String);
  CustomerAddress? address(dynamic value) {
    if (value == null) return null;
    final a = value as Map<String, dynamic>;
    return CustomerAddress(
      line1: a['line1'] as String,
      line2: a['line2'] as String?,
      city: a['city'] as String,
      postalCode: a['postalCode'] as String,
      countryCode: a['country'] as String,
      stateOrProvince: a['state'] as String?,
    );
  }

  final contact = j['contact'] as Map<String, dynamic>;
  final tax = j['tax'] as Map<String, dynamic>;
  return Customer.create(
    metadata: RecordMetadata.restore(
      recordId: EntityId.parse(j['id'] as String),
      businessId: EntityId.parse(j['business'] as String),
      originDeviceId: EntityId.parse(j['device'] as String),
      createdAt: DateTime.parse(j['created'] as String),
      updatedAt: DateTime.parse(j['updated'] as String),
      revision: j['revision'] as int,
      deletedAt: null,
    ),
    displayName: j['name'] as String,
    additionalValues: j['version'] == 2
        ? Map<String, String>.from(j['additionalValues'] as Map? ?? const {})
        : const {},
    profileDetails: CustomerProfileDetails.fromJson(
      Map<String, dynamic>.from(j['profileDetails'] as Map? ?? const {}),
    ),
    contact: CustomerContact(
      contactName: contact['name'] as String?,
      email: contact['email'] as String?,
      phone: contact['phone'] as String?,
    ),
    billingAddress: address(j['billing']),
    shippingAddress: address(j['shipping']),
    taxProfile: CustomerTaxProfile(
      taxIdentifier: tax['identifier'] as String?,
      taxCodeId: optionalId(tax['code']),
      isTaxExempt: tax['exempt'] as bool,
    ),
    currency: Currency.parse(j['currency'] as String),
    paymentTerms: PaymentTerms.fromJson(j['terms'] as Map<String, dynamic>),
    preferredDelivery: CustomerDeliveryMethod.values.byName(
      j['delivery'] as String,
    ),
    defaultIncomeAccountId: optionalId(j['income']),
    defaultTaxAccountId: optionalId(j['taxAccount']),
    statementSettings: CustomerStatementSettings(
      includeAging: j['ageing'] as bool,
      includeUnappliedAmounts: j['unapplied'] as bool,
    ),
    status: CustomerStatus.values.byName(j['status'] as String),
    auditEventIds: (j['audit'] as List)
        .map((v) => EntityId.parse(v as String))
        .toList(),
  );
}
