import '../../../app/accounting_theme.dart';

import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_icons.dart';
import '../../../app/responsive.dart';
import '../../../app/frontend_review.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/storage/record_metadata.dart';
import '../application/accounting_workspace.dart';
import '../domain/customer.dart';
import 'widgets/accounting_layout.dart';
import 'widgets/accounting_formatters.dart';
import 'customer_custom_field_setup.dart';

final customerForm = DesignForm(
  'Customers',
  [
    for (final field in partyFields)
      if (field.label == 'Name') ...[
        field,
        const DesignField('Company Name', minimumRowFraction: 0.5),
        const DesignField('Title'),
        const DesignField('First Name'),
        const DesignField('Middle Name'),
        const DesignField('Last Name'),
        const DesignField('Suffix'),
      ] else if (field.label == 'Telephone') ...[
        field,
        const DesignField('Mobile Number'),
        const DesignField('Fax'),
        const DesignField('Other Contact'),
        const DesignField('Website'),
        const DesignField('Cc'),
        const DesignField('Bcc'),
        const DesignField('Is A Sub-Customer', checkbox: true),
      ] else if (field.label == 'Payment Terms') ...[
        const DesignField(
          'Payment Terms',
          required: true,
          options: ['Days After Issue', 'Day Of Month', 'Custom'],
        ),
        const DesignField(
          'Primary Payment Method',
          options: Customer.primaryPaymentMethods,
        ),
        const DesignField(
          'Sales Form Delivery',
          options: ['Print Later', 'Send Later', 'None', 'Use Company Default'],
        ),
        const DesignField(
          'Invoice Language',
          options: Customer.invoiceLanguages,
        ),
        const DesignField(
          'Customer Category',
          options: Customer.customerCategories,
        ),
        const DesignField(
          'Opening Balance',
          customLayout: true,
          currencyCode: 'MYR',
          currencySourceLabel: 'Preferred Billing Currency',
        ),
        const DesignField('Opening Balance Date'),
      ] else if (field.label == 'Country Name') ...[
        field,
        const DesignField('Country ISO Code'),
        const DesignField('Same As Billing Address', checkbox: true),
      ] else
        field,
    const DesignField('Customer Status', options: ['Active', 'Inactive']),
  ],
  evidence: true,
  actionLabel: 'Save Customer',
);

// Same contact-field specification and ordinary-row owner as Suppliers. Only
// Customer-owned conditional fields participate; no global label inference.
DesignForm customerProfileForm(
  AccountingWorkspace workspace,
  Map<String, Object?> values, {
  Customer? original,
}) {
  final parents = {
    for (final customer in workspace.customers())
      if (customer.isActive && customer.id != original?.id)
        customer.id.value: customer.displayName,
  };
  final retainedParent = original?.additionalValues['parentCustomerId'];
  if (retainedParent != null && !parents.containsKey(retainedParent)) {
    parents[retainedParent] =
        workspace
            .customers()
            .where((customer) => customer.id.value == retainedParent)
            .firstOrNull
            ?.displayName ??
        'Unavailable Saved Customer';
  }
  return DesignForm(
    customerForm.title,
    [
      for (final field in customerForm.fields) ...[
        if (field.label == 'Opening Balance')
          DesignField(
            field.label,
            customLayout: true,
            currencyCode:
                original?.currency.code ?? workspace.identity.currency,
            currencySourceLabel: 'Preferred Billing Currency',
          )
        else if (field.label == 'Address Line 1' &&
            values['_multilineBillingAddress'] == true)
          const DesignField('Street Address', multiline: true)
        else if (const [
              'Address Line 1',
              'Address Line 2',
            ].contains(field.label) &&
            values['_multilineBillingAddress'] == true)
          ...<DesignField>[]
        else
          field,
        if (field.label == 'Is A Sub-Customer' &&
            values[field.label] == true) ...[
          DesignField('Parent Customer', required: true, choiceLabels: parents),
          if ('${values['Parent Customer'] ?? ''}'.isNotEmpty)
            const DesignField('Bill Parent Customer', checkbox: true),
        ],
        if (field.label == 'Same As Billing Address' &&
            values[field.label] != true) ...[
          if (values['_multilineShippingAddress'] == true)
            const DesignField('Shipping Street Address', multiline: true)
          else ...[
            const DesignField('Shipping Address Line 1'),
            const DesignField('Shipping Address Line 2'),
          ],
          const DesignField('Shipping City'),
          const DesignField('Shipping Postcode'),
          const DesignField('Shipping State / Region'),
          const DesignField(
            'Shipping Country',
            options: ['Malaysia', 'Singapore', 'Other Country'],
          ),
          if (values['Shipping Country'] == 'Other Country') ...[
            const DesignField('Shipping Country Name'),
            const DesignField('Shipping Country ISO Code'),
          ],
        ],
      ],
    ],
    evidence: customerForm.evidence,
    actionLabel: customerForm.actionLabel,
  );
}

String _streetText(Map<String, Object?> values, {bool shipping = false}) {
  final prefix = shipping ? 'Shipping ' : '';
  if (values[shipping
          ? '_multilineShippingAddress'
          : '_multilineBillingAddress'] ==
      true) {
    return '${values[shipping ? 'Shipping Street Address' : 'Street Address'] ?? ''}';
  }
  return [
    '${values['${prefix}Address Line 1'] ?? ''}',
    '${values['${prefix}Address Line 2'] ?? ''}',
  ].where((line) => line.isNotEmpty).join('\n');
}

Map<String, Object?> customerAddressActionUpdates(
  String label,
  Map<String, Object?> values,
) => switch (label) {
  'Address Line 2' => {
    'Street Address': _streetText(values),
    '_multilineBillingAddress': true,
  },
  'Shipping Address Line 2' => {
    'Shipping Street Address': _streetText(values, shipping: true),
    '_multilineShippingAddress': true,
  },
  _ => const {},
};

/// QBO seeds empty email/phone and seeds billing only when the complete child
/// address is empty. Cc/Bcc, website, name and terms stay owned
/// by the child. Removing the relationship keeps the copied editable fields.
Map<String, Object?> customerSelectionUpdates(
  AccountingWorkspace workspace,
  String label,
  Object? previous,
  Map<String, Object?> values,
) {
  if (label == 'Country') return const {'_billingCountryChosen': true};
  if (label != 'Parent Customer' || previous == values[label]) return const {};
  final parent = workspace
      .customers()
      .where((customer) => customer.id.value == values[label])
      .firstOrNull;
  if (parent == null) return const {};
  final parentValues = customerFormValues(parent);
  final hasTypedBilling =
      _streetText(values).trim().isNotEmpty ||
      values['_billingCountryChosen'] == true ||
      [
        'City',
        'Postcode',
        'State / Region',
        'Country Name',
      ].any((key) => '${values[key] ?? ''}'.trim().isNotEmpty);
  final address = parent.billingAddress;
  return {
    'Bill Parent Customer': previous == null || '$previous'.isEmpty
        ? true
        : values['Bill Parent Customer'] ?? true,
    if ('${values['Email'] ?? ''}'.trim().isEmpty)
      'Email': parent.contact.email ?? '',
    if ('${values['Telephone'] ?? ''}'.trim().isEmpty)
      'Telephone': parent.contact.phone ?? '',
    if (!hasTypedBilling && address != null) ...{
      for (final key in const [
        'Address Line 1',
        'Address Line 2',
        'City',
        'Postcode',
        'State / Region',
        'Country',
        'Country Name',
        'Country ISO Code',
      ])
        key: parentValues[key],
      if (values['_multilineBillingAddress'] == true)
        'Street Address': [
          address.line1,
          address.line2 ?? '',
        ].where((line) => line.isNotEmpty).join('\n'),
    },
  };
}

/// Changing the address editor alone is not an unsaved contact edit.
Map<String, Object?> customerInputValuesForComparison(
  Map<String, Object?> values,
) => {
  for (final key in values.keys.toList()..sort())
    if (!const {
      '_multilineBillingAddress',
      '_multilineShippingAddress',
      '_billingCountryChosen',
      'Address Line 1',
      'Address Line 2',
      'Street Address',
      'Shipping Address Line 1',
      'Shipping Address Line 2',
      'Shipping Street Address',
    }.contains(key))
      key: values[key],
  'Street Address': _streetText(values),
  'Shipping Street Address': _streetText(values, shipping: true),
};

const customerAdditionalFields = {
  'Company Name': 'companyName',
  'Title': 'title',
  'First Name': 'firstName',
  'Middle Name': 'middleName',
  'Last Name': 'lastName',
  'Suffix': 'suffix',
  'Mobile Number': 'mobileNumber',
  'Fax': 'fax',
  'Other Contact': 'otherContact',
  'Website': 'website',
  'Cc': 'cc',
  'Bcc': 'bcc',
  'Primary Payment Method': 'primaryPaymentMethod',
  'Invoice Language': 'invoiceLanguage',
  'Customer Category': 'customerCategory',
};

Map<String, Object?> customerFormValues(Customer c) => {
  for (final entry in customerAdditionalFields.entries)
    entry.key: c.additionalValues[entry.value] ?? '',
  'Name': c.displayName,
  'Is A Sub-Customer': c.additionalValues.containsKey('parentCustomerId'),
  'Parent Customer': c.additionalValues['parentCustomerId'] ?? '',
  'Bill Parent Customer': c.additionalValues['billParentCustomer'] == 'true',
  '_multilineBillingAddress': c.billingAddress?.line1.contains('\n') == true,
  '_billingCountryChosen': c.billingAddress != null,
  'Street Address': [
    c.billingAddress?.line1 ?? '',
    c.billingAddress?.line2 ?? '',
  ].where((line) => line.isNotEmpty).join('\n'),
  '_multilineShippingAddress': c.shippingAddress?.line1.contains('\n') == true,
  'Shipping Street Address': [
    c.shippingAddress?.line1 ?? '',
    c.shippingAddress?.line2 ?? '',
  ].where((line) => line.isNotEmpty).join('\n'),
  'Same As Billing Address': c.additionalValues['shippingSameAsBilling'] == null
      ? c.shippingAddress == null
      : c.additionalValues['shippingSameAsBilling'] == 'true',
  'Shipping Address Line 1': c.shippingAddress?.line1 ?? '',
  'Shipping Address Line 2': c.shippingAddress?.line2 ?? '',
  'Shipping City': c.shippingAddress?.city ?? '',
  'Shipping Postcode': c.shippingAddress?.postalCode ?? '',
  'Shipping State / Region': c.shippingAddress?.stateOrProvince ?? '',
  'Shipping Country': switch (c.shippingAddress?.countryCode) {
    null => '',
    'MY' => 'Malaysia',
    'SG' => 'Singapore',
    _ => 'Other Country',
  },
  'Shipping Country Name': c.additionalValues['shippingCountryName'] ?? '',
  'Shipping Country ISO Code': c.shippingAddress?.countryCode ?? '',
  'Sales Form Delivery': switch (c.preferredDelivery) {
    CustomerDeliveryMethod.email => 'Send Later',
    CustomerDeliveryMethod.print => 'Print Later',
    CustomerDeliveryMethod.none => 'None',
    CustomerDeliveryMethod.companyDefault => 'Use Company Default',
  },
  'Customer Status': c.isActive ? 'Active' : 'Inactive',
  'Country ISO Code': c.billingAddress?.countryCode ?? '',
  'Email': c.contact.email ?? '',
  'Telephone': c.contact.phone ?? '',
  'Party Type': c.profileDetails.partyType,
  'Address Line 1': c.billingAddress?.line1 ?? '',
  'Address Line 2': c.billingAddress?.line2 ?? '',
  'City': c.billingAddress?.city ?? '',
  'Postcode': c.billingAddress?.postalCode ?? '',
  'State / Region': c.billingAddress?.stateOrProvince ?? '',
  'Country': switch (c.billingAddress?.countryCode) {
    null => '',
    'MY' => 'Malaysia',
    'SG' => 'Singapore',
    _ => 'Other Country',
  },
  'Country Name': c.profileDetails.countryName,
  'Preferred Billing Currency': c.currency.code,
  'Payment Terms': c.paymentTerms.formChoice,
  'Custom Payment Terms': c.paymentTerms.customText ?? '',
  'Number Of Days': '${c.paymentTerms.days ?? 0}',
  'Monthly Due Day': '${c.paymentTerms.dayOfMonth ?? 1}',
  'Rollover Within Days': '${c.paymentTerms.rolloverWithinDays}',
  'Tax Details Needed': c.profileDetails.taxDetailsNeeded,
  'Identification Type': c.profileDetails.identificationType,
  'Identification Number': c.profileDetails.identificationNumber,
  'TIN': c.taxProfile.taxIdentifier ?? '',
  'SST Registration Number': c.profileDetails.sstRegistrationNumber,
  'Notes': c.profileDetails.notes,
};

Customer customerFromForm(
  Map<String, Object?> values,
  AccountingWorkspace workspace, {
  Customer? original,
  required EntityId id,
  required DateTime now,
}) {
  String value(String key) => (values[key] as String? ?? '').trim();
  int integer(String key) =>
      int.tryParse(value(key)) ??
      (throw FormatException('$key must be a whole number.'));
  final terms =
      (switch (value('Payment Terms')) {
        'Custom' => PaymentTerms.custom(value('Custom Payment Terms')),
        'Days After Issue' => PaymentTerms.daysAfterIssue(
          integer('Number Of Days'),
        ),
        'Day Of Month' => PaymentTerms.dayOfMonth(
          integer('Monthly Due Day'),
          rolloverWithinDays: integer('Rollover Within Days'),
        ),
        _ => throw const FormatException('Choose explicit payment terms.'),
      }).retainingCustomText(
        values.containsKey('Custom Payment Terms')
            ? value('Custom Payment Terms')
            : original?.paymentTerms.customText,
      );
  final country = value('Country');
  final multilineBilling = values['_multilineBillingAddress'] == true;
  final multilineShipping = values['_multilineShippingAddress'] == true;
  final hasBillingAddress =
      _streetText(values).trim().isNotEmpty ||
      [
        'City',
        'Postcode',
        'State / Region',
        'Country',
        'Country Name',
        'Country ISO Code',
      ].any((key) => value(key).isNotEmpty);
  if (hasBillingAddress &&
      country == 'Other Country' &&
      value('Country Name').isEmpty) {
    throw const FormatException('Enter the country name.');
  }
  final countryCode = switch (country) {
    'Malaysia' => 'MY',
    'Singapore' => 'SG',
    _ => value('Country ISO Code').toUpperCase(),
  };
  if (hasBillingAddress && !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
    throw const FormatException('Enter a two-letter country ISO code.');
  }
  final currency = value('Preferred Billing Currency');
  if (value('Opening Balance').isNotEmpty ||
      value('Opening Balance Date').isNotEmpty) {
    throw const FormatException(
      'Customer opening balances need a dated balanced entry. This command is not connected yet.',
    );
  }
  if ((values['_files'] as List? ?? const []).isNotEmpty ||
      (values['_attachments'] as List? ?? const []).isNotEmpty) {
    throw const FormatException(
      'Customer supporting-document saving is not connected yet. Remove the staged files to save contact details.',
    );
  }
  final billingAddress = hasBillingAddress
      ? CustomerAddress(
          line1: multilineBilling
              ? value('Street Address')
              : value('Address Line 1'),
          line2: multilineBilling ? null : value('Address Line 2'),
          city: value('City'),
          postalCode: value('Postcode'),
          stateOrProvince: value('State / Region'),
          countryCode: countryCode,
        )
      : null;
  final hasShipping =
      _streetText(values, shipping: true).trim().isNotEmpty ||
      const [
        'Shipping City',
        'Shipping Postcode',
        'Shipping State / Region',
        'Shipping Country',
        'Shipping Country Name',
        'Shipping Country ISO Code',
      ].any((key) => value(key).isNotEmpty);
  final shippingCode = switch (value('Shipping Country')) {
    'Malaysia' => 'MY',
    'Singapore' => 'SG',
    _ => value('Shipping Country ISO Code').toUpperCase(),
  };
  final sameBilling = values['Same As Billing Address'] == true;
  if (values.containsKey('Same As Billing Address') &&
      !sameBilling &&
      hasShipping) {
    if (value('Shipping Country') == 'Other Country' &&
        value('Shipping Country Name').isEmpty) {
      throw const FormatException('Enter the shipping country name.');
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(shippingCode)) {
      throw const FormatException(
        'Enter a two-letter shipping country ISO code.',
      );
    }
  }
  final subCustomer = values.containsKey('Is A Sub-Customer')
      ? values['Is A Sub-Customer'] == true
      : original?.additionalValues.containsKey('parentCustomerId') == true;
  final parentId = values.containsKey('Parent Customer')
      ? value('Parent Customer')
      : original?.additionalValues['parentCustomerId'] ?? '';
  if (subCustomer && parentId.isEmpty) {
    throw const FormatException('Choose a parent customer.');
  }
  final additionalValues = {
    for (final entry in customerAdditionalFields.entries)
      entry.value: values.containsKey(entry.key)
          ? value(entry.key)
          : original?.additionalValues[entry.value] ?? '',
    if (subCustomer) 'parentCustomerId': parentId,
    if (subCustomer)
      'billParentCustomer':
          '${values.containsKey('Bill Parent Customer') ? values['Bill Parent Customer'] == true : original?.additionalValues['billParentCustomer'] == 'true'}',
    if (values.containsKey('Same As Billing Address'))
      'shippingSameAsBilling': '$sameBilling'
    else if (original?.additionalValues['shippingSameAsBilling'] != null)
      'shippingSameAsBilling':
          original!.additionalValues['shippingSameAsBilling']!,
    'shippingCountryName': values.containsKey('Shipping Country Name')
        ? value('Shipping Country Name')
        : original?.additionalValues['shippingCountryName'] ?? '',
  };
  final contactParts = [
    for (final key in const ['firstName', 'middleName', 'lastName'])
      if ((additionalValues[key] ?? '').isNotEmpty) additionalValues[key]!,
  ];
  return Customer.create(
    metadata: original == null
        ? RecordMetadata.initial(
            recordId: id,
            businessId: workspace.identity.businessId,
            originDeviceId: workspace.identity.deviceId,
            createdAt: now,
          )
        : original.metadata.nextRevision(updatedAt: now),
    displayName: value('Name'),
    additionalValues: additionalValues,
    contact: CustomerContact(
      contactName: contactParts.isNotEmpty
          ? contactParts.join(' ')
          : const [
              'firstName',
              'middleName',
              'lastName',
            ].any((key) => original?.additionalValues.containsKey(key) == true)
          ? null
          : original?.contact.contactName,
      email: value('Email'),
      phone: value('Telephone'),
    ),
    billingAddress: billingAddress,
    shippingAddress: !values.containsKey('Same As Billing Address')
        ? original?.shippingAddress
        : sameBilling
        ? billingAddress
        : hasShipping
        ? CustomerAddress(
            line1: multilineShipping
                ? value('Shipping Street Address')
                : value('Shipping Address Line 1'),
            line2: multilineShipping ? null : value('Shipping Address Line 2'),
            city: value('Shipping City'),
            postalCode: value('Shipping Postcode'),
            countryCode: shippingCode,
            stateOrProvince: value('Shipping State / Region'),
          )
        : null,
    taxProfile: CustomerTaxProfile(
      taxIdentifier: value('TIN'),
      taxCodeId: original?.taxProfile.taxCodeId,
      isTaxExempt: original?.taxProfile.isTaxExempt ?? false,
    ),
    profileDetails: CustomerProfileDetails(
      partyType: value('Party Type'),
      identificationType: value('Identification Type'),
      identificationNumber: value('Identification Number'),
      sstRegistrationNumber: value('SST Registration Number'),
      notes: value('Notes'),
      countryName: value('Country Name'),
      taxDetailsNeeded: values['Tax Details Needed'] == true,
    ),
    currency: Currency.parse(
      currency.isEmpty || currency == 'Use Company Default'
          ? workspace.identity.currency
          : currency,
    ),
    paymentTerms: terms,
    preferredDelivery: !values.containsKey('Sales Form Delivery')
        ? original?.preferredDelivery ?? CustomerDeliveryMethod.email
        : switch (value('Sales Form Delivery')) {
            'Print Later' => CustomerDeliveryMethod.print,
            'Send Later' => CustomerDeliveryMethod.email,
            'None' => CustomerDeliveryMethod.none,
            'Use Company Default' => CustomerDeliveryMethod.companyDefault,
            _ => throw const FormatException('Choose sales form delivery.'),
          },
    defaultIncomeAccountId: original?.defaultIncomeAccountId,
    defaultTaxAccountId: original?.defaultTaxAccountId,
    statementSettings:
        original?.statementSettings ?? const CustomerStatementSettings(),
    status: switch (value('Customer Status')) {
      'Inactive' => CustomerStatus.inactive,
      'Active' || '' => CustomerStatus.active,
      _ => throw const FormatException('Choose a customer status.'),
    },
    auditEventIds: original?.auditEventIds ?? const [],
  );
}

/// Shared entry to the existing Customer editor and command. Closing without
/// committing returns null; inline callers select only a successfully saved ID.
Future<Customer?> showAccountingCustomerDialog(
  BuildContext context,
  AccountingWorkspace workspace, {
  Customer? customer,
  String initialName = '',
}) async {
  final id = customer?.metadata.recordId ?? EntityId.random();
  Customer? saved;
  await showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => FrontendFormDialog(
      form: customerForm,
      valuesFormBuilder: (values) =>
          customerProfileForm(workspace, values, original: customer),
      selectionValueUpdates: (label, previous, values) =>
          customerSelectionUpdates(workspace, label, previous, values),
      fieldActionLabels: const {
        'Address Line 2': 'Add Lines',
        'Shipping Address Line 2': 'Add Lines',
      },
      fieldActionUpdates: customerAddressActionUpdates,
      inputValuesForComparison: customerInputValuesForComparison,
      additionalContentBuilder: (context, values, reviewing) => reviewing
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: accountingContentInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom Fields',
                    style: AccountingTypography.sectionTitle(context),
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('customer-add-custom-field'),
                    onPressed: () => showCustomerCustomFieldSetup(context),
                    child: const Text('Add Custom Field'),
                  ),
                ],
              ),
            ),
      selectorActions: {
        'Primary Payment Method': [
          AccountingSelectorOption(
            value: '__add_payment_method__',
            label: 'Add Payment Method',
            leading: const AccountingAddIcon(),
            leadingWidth: AccountingDismissIcon.canvasSize,
            onPressed: () => showAccountingPaymentMethodPreview(context),
          ),
        ],
      },
      initial: customer == null
          ? {
              'Name': initialName,
              'Country': 'Malaysia',
              'Country ISO Code': 'MY',
              'Customer Status': 'Active',
              'Preferred Billing Currency': workspace.identity.currency,
              'Payment Terms': 'Days After Issue',
              'Number Of Days': '0',
              'Monthly Due Day': '1',
              'Rollover Within Days': '0',
              'Same As Billing Address': true,
              'Is A Sub-Customer': false,
              'Bill Parent Customer': false,
              'Sales Form Delivery': 'Use Company Default',
              'Invoice Language': 'English',
            }
          : customerFormValues(customer),
      onCommit: (values) async {
        final next = customerFromForm(
          values,
          workspace,
          original: customer,
          id: id,
          now: DateTime.now().toUtc(),
        );
        workspace.saveCustomer(next);
        saved = next;
      },
    ),
  );
  return saved;
}

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  AccountingWorkspace get workspace => widget.workspace;
  String _search = '';
  String? _status;
  Money _balanceFor(Customer customer) {
    final statement = workspace.database.customerStatement(
      workspace.identity.businessId,
      customer.id,
      DateTime.now(),
    );
    return statement.isEmpty
        ? Money.zero(customer.currency.code)
        : statement.last.balance;
  }

  Future<void> _edit(BuildContext context, [Customer? customer]) async {
    await showAccountingCustomerDialog(context, workspace, customer: customer);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final showControls = AccountingRecordControlsPolicy.visible(
        workspace.customers().length,
      );
      final customers = workspace
          .customers()
          .where(
            (c) =>
                (!showControls ||
                    _status == null ||
                    (c.isActive ? 'Active' : 'Inactive') == _status) &&
                [c.displayName, c.contact.email ?? '', c.contact.phone ?? '']
                    .join(' ')
                    .toLowerCase()
                    .contains(showControls ? _search.toLowerCase() : ''),
          )
          .toList();
      final balanceStyle = AccountingTypography.value(context)
          .copyWith(fontWeight: FontWeight.w600);
      final balanceWidth = customers.fold<double>(
        AccountingResponsive.measuredTextWidth(
          context,
          'Balance',
          AccountingTypography.tableHeader(context),
        ),
        (width, customer) {
          final amount = formatAccountingMoney(context, _balanceFor(customer));
          final measured = AccountingResponsive.measuredTextWidth(
            context,
            amount,
            balanceStyle,
          );
          return measured > width ? measured : width;
        },
      );
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Customers',
              title: 'Customers',
              description:
                  'Customer details and billing defaults for this company.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('new-customer'),
                child: const Text('New Customer'),
                onPressed: () => _edit(context),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            if (AccountingRecordControlsPolicy.visible(
              workspace.customers().length,
            ))
              Wrap(
                spacing: accountingContentInset,
                runSpacing: AccountingPageControlScope.runGapOf(context),
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: AccountingLabelledSearch(
                      labelKey: const ValueKey('customer-search-label'),
                      child: TextField(
                        key: const ValueKey('customer-search'),
                        style: AccountingTypography.value(context),
                        decoration:
                            accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Search Customers',
                            ).copyWith(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: accountingFieldContentInset,
                                vertical: 12,
                              ),
                            ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    options: const ['Active', 'Inactive'],
                    value: _status,
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ],
              ),
            if (AccountingRecordControlsPolicy.visible(
              workspace.customers().length,
            ))
              const SizedBox(height: 16),
            if (customers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: accountingContentInset,
                ),
                child: Text('No matching customers.'),
              ),
            AccountingRecordList(
              paginationKey: 'customers',
              totalCount: workspace.customers().length,
              header: _customerHeader(context, balanceWidth),
              children: [
                for (final customer in customers)
                  _customerRow(context, customer, balanceWidth, balanceStyle),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _customerHeader(BuildContext context, double balanceWidth) => Padding(
    padding: accountingContentPadding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth >=
            balanceWidth +
                accountingContentInset * 2 +
                accountingSmallControlHeight +
                160;
        final style = AccountingTypography.tableHeader(context);
        return Row(
          children: [
            Expanded(
              child: Text(
                inline ? 'Customer / Email' : 'Customer',
                style: style,
              ),
            ),
            if (inline) const SizedBox(width: accountingContentInset),
            SizedBox(
              width: inline ? balanceWidth : null,
              child: Text('Balance', textAlign: TextAlign.right, style: style),
            ),
            if (inline) ...[
              const SizedBox(width: accountingContentInset),
              const SizedBox(width: accountingSmallControlHeight),
            ],
          ],
        );
      },
    ),
  );

  Widget _customerRow(
    BuildContext context,
    Customer customer,
    double balanceWidth,
    TextStyle balanceStyle,
  ) {
    final edit = AccountingButton.iconOnly(
      context,
      key: ValueKey('edit-customer-${customer.metadata.recordId.value}'),
      onPressed: () => _edit(context, customer),
      icon: Icons.edit_outlined,
      tooltip: 'Edit ${customer.displayName}',
      compact: true,
    );
    final amount = Text(
      formatAccountingMoney(context, _balanceFor(customer)),
      textAlign: TextAlign.right,
      style: balanceStyle,
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          customer.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AccountingTypography.value(context),
        ),
        if ((customer.contact.email ?? '').isNotEmpty) ...[
          const SizedBox(height: accountingRecordInfoLineGap),
          Text(
            customer.contact.email!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AccountingTypography.helper(context),
          ),
        ],
      ],
    );
    return KeyedSubtree(
      key: ValueKey(customer.metadata.recordId.value),
      child: Padding(
        padding: accountingContentPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inline =
                constraints.maxWidth >=
                balanceWidth +
                    accountingContentInset * 2 +
                    accountingSmallControlHeight +
                    160;
            if (!inline) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: accountingContentInset),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(child: amount),
                      const SizedBox(width: accountingContentInset),
                      edit,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: accountingContentInset),
                SizedBox(width: balanceWidth, child: amount),
                const SizedBox(width: accountingContentInset),
                edit,
              ],
            );
          },
        ),
      ),
    );
  }
}
