import 'payment_terms.dart';
export 'payment_terms.dart' show PaymentTerms, PaymentTermKind;

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';

enum CustomerStatus { active, inactive }

enum CustomerDeliveryMethod { email, print, none, companyDefault }

final class CustomerContact {
  const CustomerContact({this.contactName, this.email, this.phone});

  final String? contactName;
  final String? email;
  final String? phone;
}

final class CustomerAddress {
  const CustomerAddress({
    required this.line1,
    required this.city,
    required this.postalCode,
    required this.countryCode,
    this.line2,
    this.stateOrProvince,
  });

  final String line1;
  final String? line2;
  final String city;
  final String? stateOrProvince;
  final String postalCode;
  final String countryCode;
}

final class CustomerTaxProfile {
  const CustomerTaxProfile({
    this.taxIdentifier,
    this.taxCodeId,
    this.isTaxExempt = false,
  });

  final String? taxIdentifier;
  final EntityId? taxCodeId;
  final bool isTaxExempt;
}

final class CustomerStatementSettings {
  const CustomerStatementSettings({
    this.includeAging = true,
    this.includeUnappliedAmounts = true,
  });

  final bool includeAging;
  final bool includeUnappliedAmounts;
}

final class CustomerProfileDetails {
  const CustomerProfileDetails({
    this.partyType = '',
    this.identificationType = '',
    this.identificationNumber = '',
    this.sstRegistrationNumber = '',
    this.notes = '',
    this.countryName = '',
    this.taxDetailsNeeded = false,
  });
  final String partyType,
      identificationType,
      identificationNumber,
      sstRegistrationNumber,
      notes,
      countryName;
  final bool taxDetailsNeeded;
  Map<String, Object> toJson() => {
    'partyType': partyType,
    'identificationType': identificationType,
    'identificationNumber': identificationNumber,
    'sstRegistrationNumber': sstRegistrationNumber,
    'notes': notes,
    'countryName': countryName,
    'taxDetailsNeeded': taxDetailsNeeded,
  };
  factory CustomerProfileDetails.fromJson(Map<String, dynamic> j) =>
      CustomerProfileDetails(
        partyType: j['partyType'] as String? ?? '',
        identificationType: j['identificationType'] as String? ?? '',
        identificationNumber: j['identificationNumber'] as String? ?? '',
        sstRegistrationNumber: j['sstRegistrationNumber'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        countryName: j['countryName'] as String? ?? '',
        taxDetailsNeeded: j['taxDetailsNeeded'] as bool? ?? false,
      );
}

final class Customer {
  Customer._({
    required this.metadata,
    required this.profileDetails,
    required this.additionalValues,
    required this.displayName,
    required this.contact,
    required this.billingAddress,
    required this.shippingAddress,
    required this.taxProfile,
    required this.currency,
    required this.paymentTerms,
    required this.preferredDelivery,
    required this.defaultIncomeAccountId,
    required this.defaultTaxAccountId,
    required this.statementSettings,
    required this.status,
    required List<EntityId> auditEventIds,
  }) : auditEventIds = List.unmodifiable(auditEventIds);

  factory Customer.create({
    required RecordMetadata metadata,
    CustomerProfileDetails profileDetails = const CustomerProfileDetails(),
    Map<String, String> additionalValues = const {},
    required String displayName,
    required CustomerContact contact,
    CustomerAddress? billingAddress,
    CustomerAddress? shippingAddress,
    required CustomerTaxProfile taxProfile,
    required Currency currency,
    required PaymentTerms paymentTerms,
    CustomerDeliveryMethod preferredDelivery = CustomerDeliveryMethod.email,
    EntityId? defaultIncomeAccountId,
    EntityId? defaultTaxAccountId,
    CustomerStatementSettings statementSettings =
        const CustomerStatementSettings(),
    CustomerStatus status = CustomerStatus.active,
    List<EntityId> auditEventIds = const [],
  }) {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'A customer display name is required.',
      );
    }
    if (additionalValues.keys.any((key) => !additionalKeys.contains(key))) {
      throw const FormatException('Unsupported customer profile field.');
    }
    final extra = Map<String, String>.unmodifiable({
      for (final entry in additionalValues.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    });
    for (final entry in {
      'primaryPaymentMethod': primaryPaymentMethods,
      'invoiceLanguage': invoiceLanguages,
      'customerCategory': customerCategories,
      'shippingSameAsBilling': const ['true', 'false'],
      'billParentCustomer': const ['true', 'false'],
    }.entries) {
      final selected = extra[entry.key];
      if (selected != null && !entry.value.contains(selected)) {
        throw FormatException('Choose a valid ${entry.key}.');
      }
    }
    if (extra['parentCustomerId'] == metadata.recordId.value) {
      throw const FormatException('A customer cannot be its own parent.');
    }
    if (extra.containsKey('billParentCustomer') &&
        !extra.containsKey('parentCustomerId')) {
      throw const FormatException('Parent billing needs a parent customer.');
    }
    return Customer._(
      metadata: metadata,
      profileDetails: profileDetails,
      additionalValues: extra,
      displayName: normalizedName,
      contact: contact,
      billingAddress: billingAddress,
      shippingAddress: shippingAddress,
      taxProfile: taxProfile,
      currency: currency,
      paymentTerms: paymentTerms,
      preferredDelivery: preferredDelivery,
      defaultIncomeAccountId: defaultIncomeAccountId,
      defaultTaxAccountId: defaultTaxAccountId,
      statementSettings: statementSettings,
      status: status,
      auditEventIds: auditEventIds,
    );
  }

  final RecordMetadata metadata;
  final CustomerProfileDetails profileDetails;

  /// Optional master facts, independent of retained transaction snapshots.
  /// Opening balances are accounting entries, never contact metadata.
  final Map<String, String> additionalValues;
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
    'primaryPaymentMethod',
    'invoiceLanguage',
    'customerCategory',
    'parentCustomerId',
    'billParentCustomer',
    'shippingSameAsBilling',
    'shippingCountryName',
  };
  static const primaryPaymentMethods = [
    'Bank Draft',
    'Cash',
    'Cash Deposit',
    'Cheque',
    'Credit Card',
    'Debit Card',
    'Direct Debit',
    'Online Banking',
  ];
  static const invoiceLanguages = [
    'English',
    'French',
    'Spanish',
    'Italian',
    'Chinese (Traditional)',
    'Portuguese (Brazil)',
  ];
  static const customerCategories = [
    'Domestic Business',
    'Domestic Individual',
    'Foreign Business',
    'Foreign Individual',
  ];
  final String displayName;
  final CustomerContact contact;
  final CustomerAddress? billingAddress;
  final CustomerAddress? shippingAddress;
  final CustomerTaxProfile taxProfile;
  final Currency currency;
  final PaymentTerms paymentTerms;
  final CustomerDeliveryMethod preferredDelivery;
  final EntityId? defaultIncomeAccountId;
  final EntityId? defaultTaxAccountId;
  final CustomerStatementSettings statementSettings;
  final CustomerStatus status;
  final List<EntityId> auditEventIds;

  EntityId get id => metadata.recordId;
  bool get isActive => status == CustomerStatus.active;

  Customer revise({
    String? displayName,
    CustomerContact? contact,
    CustomerAddress? billingAddress,
    CustomerAddress? shippingAddress,
    CustomerTaxProfile? taxProfile,
    Currency? currency,
    PaymentTerms? paymentTerms,
    CustomerDeliveryMethod? preferredDelivery,
    EntityId? defaultIncomeAccountId,
    EntityId? defaultTaxAccountId,
    CustomerProfileDetails? profileDetails,
    Map<String, String>? additionalValues,
    CustomerStatementSettings? statementSettings,
    CustomerStatus? status,
    List<EntityId>? auditEventIds,
    required DateTime updatedAt,
  }) {
    final normalizedName = displayName?.trim() ?? this.displayName;
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'A customer display name is required.',
      );
    }
    return Customer.create(
      metadata: metadata.nextRevision(updatedAt: updatedAt),
      profileDetails: profileDetails ?? this.profileDetails,
      additionalValues: additionalValues ?? this.additionalValues,
      displayName: normalizedName,
      contact: contact ?? this.contact,
      billingAddress: billingAddress ?? this.billingAddress,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      taxProfile: taxProfile ?? this.taxProfile,
      currency: currency ?? this.currency,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      preferredDelivery: preferredDelivery ?? this.preferredDelivery,
      defaultIncomeAccountId:
          defaultIncomeAccountId ?? this.defaultIncomeAccountId,
      defaultTaxAccountId: defaultTaxAccountId ?? this.defaultTaxAccountId,
      statementSettings: statementSettings ?? this.statementSettings,
      status: status ?? this.status,
      auditEventIds: auditEventIds ?? this.auditEventIds,
    );
  }

  Customer deactivate({required DateTime updatedAt}) {
    if (!isActive) {
      return this;
    }
    return revise(status: CustomerStatus.inactive, updatedAt: updatedAt);
  }

  Customer activate({required DateTime updatedAt}) {
    if (isActive) {
      return this;
    }
    return revise(status: CustomerStatus.active, updatedAt: updatedAt);
  }
}
