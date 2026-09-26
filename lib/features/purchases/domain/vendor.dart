import '../../../core/ids/entity_id.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/storage/record_metadata.dart';
import '../../accounting/domain/payee.dart';
import '../../accounting/domain/payment_terms.dart';

const vendorPayeeTypes = {
  PayeeType.supplier,
  PayeeType.vendor,
  PayeeType.smallProvider,
};

/// Contact facts stay separate from the shared payee identity and transactions.
final class VendorDetails {
  VendorDetails({
    Map<String, String> values = const {},
    this.taxDetailsNeeded = false,
  }) : values = Map.unmodifiable({
         for (final key in keys) key: (values[key] ?? '').trim(),
       }) {
    if (values.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unsupported vendor contact field.');
    }
    final country = this.values['countryCode']!;
    if (country.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      throw const FormatException('Enter a two-letter country ISO code.');
    }
    if (this.values['countryName']!.isNotEmpty && country.isEmpty) {
      throw const FormatException('A named country needs its ISO code.');
    }
    if (!const {
      '',
      'Business',
      'Individual',
      'Government',
      'Other',
    }.contains(this.values['partyType'])) {
      throw const FormatException('Invalid vendor party type.');
    }
    if (!const {
      '',
      'Business Registration',
      'MyKad',
      'MyTentera',
      'Passport',
      'Other',
    }.contains(this.values['identificationType'])) {
      throw const FormatException('Invalid vendor identification type.');
    }
  }

  static const keys = {
    'partyType',
    'email',
    'telephone',
    'addressLine1',
    'addressLine2',
    'city',
    'postcode',
    'state',
    'countryCode',
    'countryName',
    'identificationType',
    'identificationNumber',
    'tin',
    'sstRegistrationNumber',
    'notes',
  };
  final Map<String, String> values;
  final bool taxDetailsNeeded;
  String operator [](String key) => values[key] ?? '';

  Map<String, Object> toJson() => {
    ...values,
    'taxDetailsNeeded': taxDetailsNeeded,
  };

  factory VendorDetails.fromJson(Map<String, dynamic> json) {
    if (json.length != keys.length + 1 ||
        json['taxDetailsNeeded'] is! bool ||
        keys.any((key) => json[key] is! String)) {
      throw const FormatException('Invalid vendor contact snapshot.');
    }
    return VendorDetails(
      values: {for (final key in keys) key: json[key] as String},
      taxDetailsNeeded: json['taxDetailsNeeded'] as bool,
    );
  }
}

final class Vendor {
  Vendor({
    required this.metadata,
    required this.payeeId,
    required String name,
    required this.type,
    required this.details,
    required this.currency,
    required this.terms,
    Map<String, String> additionalValues = const {},
  }) : name = name.trim(),
       additionalValues = Map.unmodifiable({
         for (final key in additionalKeys)
           if ((additionalValues[key] ?? '').trim().isNotEmpty)
             key: additionalValues[key]!.trim(),
       }) {
    if (additionalValues.keys.any((key) => !additionalKeys.contains(key))) {
      throw const FormatException('Unsupported supplier profile field.');
    }
    final category = this.additionalValues['supplierCategory'];
    if (category != null && !supplierCategories.contains(category)) {
      throw const FormatException('Choose a valid supplier category.');
    }
    final rate = this.additionalValues['billingRate'];
    if (rate != null && Money.fromDecimal(rate, currency.code).minorUnits < 0) {
      throw const FormatException('Billing rate cannot be negative.');
    }
    if (payeeId.trim().isEmpty ||
        this.name.isEmpty ||
        !vendorPayeeTypes.contains(type) ||
        metadata.isTombstone) {
      throw const FormatException(
        'A vendor requires a valid commercial payee.',
      );
    }
  }

  final RecordMetadata metadata;
  EntityId get id => metadata.recordId;
  final String payeeId, name;
  final PayeeType type;
  final VendorDetails details;
  final Currency currency;
  final PaymentTerms terms;

  // Separate optional supplier facts preserve legacy version-one snapshots.
  // An opening balance is a dated accounting command, never contact metadata.
  static const additionalKeys = {
    'companyName',
    'title',
    'firstName',
    'middleName',
    'lastName',
    'suffix',
    'mobileNumber',
    'fax',
    'otherContact',
    'website',
    'cc',
    'bcc',
    'supplierCategory',
    'accountNumber',
    'defaultExpenseAccountId',
    'billingRate',
  };
  static const supplierCategories = {
    'Domestic Business',
    'Domestic Individual',
    'Foreign Business',
    'Foreign Individual',
  };
  final Map<String, String> additionalValues;
  Payee get payee => Payee(id: payeeId, name: name, type: type);

  Map<String, Object?> toJson() => {
    'version': additionalValues.isEmpty ? 1 : 2,
    if (additionalValues.isNotEmpty) 'additionalValues': additionalValues,
    'id': id.value,
    'businessId': metadata.businessId.value,
    'deviceId': metadata.originDeviceId.value,
    'createdAt': metadata.createdAt.toIso8601String(),
    'updatedAt': metadata.updatedAt.toIso8601String(),
    'revision': metadata.revision,
    'payeeId': payeeId,
    'name': name,
    'type': type.name,
    'details': details.toJson(),
    'currency': currency.code,
    'terms': terms.toJson(),
  };

  factory Vendor.fromJson(Map<String, dynamic> json) {
    const keys = {
      'version',
      'id',
      'businessId',
      'deviceId',
      'createdAt',
      'updatedAt',
      'revision',
      'payeeId',
      'name',
      'type',
      'details',
      'currency',
      'terms',
    };
    final version = json['version'];
    final snapshotKeys = {...keys, if (version == 2) 'additionalValues'};
    if ((version != 1 && version != 2) ||
        json.length != snapshotKeys.length ||
        json.keys.any((key) => !snapshotKeys.contains(key))) {
      throw const FormatException('Unsupported vendor snapshot.');
    }
    try {
      final extra = version == 2
          ? Map<String, String>.from(json['additionalValues'] as Map)
          : <String, String>{};
      if (version == 2 && extra.isEmpty) {
        throw const FormatException('Empty supplier profile extension.');
      }
      return Vendor(
        additionalValues: extra,
        metadata: RecordMetadata.restore(
          recordId: EntityId.parse(json['id'] as String),
          businessId: EntityId.parse(json['businessId'] as String),
          originDeviceId: EntityId.parse(json['deviceId'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          updatedAt: DateTime.parse(json['updatedAt'] as String),
          revision: json['revision'] as int,
          deletedAt: null,
        ),
        payeeId: json['payeeId'] as String,
        name: json['name'] as String,
        type: PayeeType.values.byName(json['type'] as String),
        details: VendorDetails.fromJson(
          json['details'] as Map<String, dynamic>,
        ),
        currency: Currency.parse(json['currency'] as String),
        terms: PaymentTerms.fromJson(json['terms'] as Map<String, dynamic>),
      );
    } catch (_) {
      throw const FormatException('Invalid vendor snapshot.');
    }
  }
}
