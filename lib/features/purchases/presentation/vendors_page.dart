import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/currency_presentation.dart';
import '../../../core/storage/record_metadata.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/data/accounting_database.dart';
import '../../accounting/domain/payee.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/payment_terms.dart';
import '../../accounting/presentation/widgets/accounting_layout.dart';
import '../domain/vendor.dart';
import 'vendor_profile_proposal.dart';
export 'vendor_profile_proposal.dart' show vendorBaseForm;

final vendorForm = vendorBaseForm;

const vendorAdditionalFields = {
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
  'Supplier Category': 'supplierCategory',
  'Account Number': 'accountNumber',
  'Default Expense Category': 'defaultExpenseAccountId',
  'Billing Rate Per Hour': 'billingRate',
};

const _detailFields = {
  'Party Type': 'partyType',
  'Email': 'email',
  'Telephone': 'telephone',
  'Address Line 1': 'addressLine1',
  'Address Line 2': 'addressLine2',
  'City': 'city',
  'Postcode': 'postcode',
  'State / Region': 'state',
  'Country ISO Code': 'countryCode',
  'Country Name': 'countryName',
  'Identification Type': 'identificationType',
  'Identification Number': 'identificationNumber',
  'TIN': 'tin',
  'SST Registration Number': 'sstRegistrationNumber',
  'Notes': 'notes',
};

Map<String, Object?> vendorFormValues(Vendor vendor) => {
  for (final field in vendorAdditionalFields.entries)
    field.key: vendor.additionalValues[field.value] ?? '',
  'Name': vendor.name,
  'Vendor Type': vendor.type.label,
  for (final field in _detailFields.entries)
    field.key: vendor.details[field.value],
  'Country': switch (vendor.details['countryCode']) {
    'MY' => 'Malaysia',
    'SG' => 'Singapore',
    '' => '',
    _ => 'Other Country',
  },
  'Preferred Billing Currency': vendor.currency.code,
  'Payment Terms': vendor.terms.formChoice,
  'Custom Payment Terms': vendor.terms.customText ?? '',
  'Number Of Days': '${vendor.terms.days ?? 0}',
  'Monthly Due Day': '${vendor.terms.dayOfMonth ?? 1}',
  'Rollover Within Days': '${vendor.terms.rolloverWithinDays}',
  'Tax Details Needed': vendor.details.taxDetailsNeeded,
};

Vendor vendorFromForm(
  Map<String, Object?> values,
  AccountingWorkspace workspace, {
  required EntityId id,
  required String payeeId,
  Vendor? original,
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
            : original?.terms.customText,
      );
  final country = value('Country');
  if (country == 'Other Country' &&
      (value('Country Name').isEmpty ||
          !RegExp(r'^[A-Z]{2}$')
              .hasMatch(value('Country ISO Code').toUpperCase()))) {
    throw const FormatException(
      'Enter the country name and two-letter ISO code.',
    );
  }
  // Until their real commands are connected, reject rather than drop these
  // visible proposed facts. Existing contact saves remain available.
  if (value('Opening Balance').isNotEmpty ||
      value('Opening Balance Date').isNotEmpty) {
    throw const FormatException(
      'Supplier opening balances need a dated balanced entry. This command is not connected yet.',
    );
  }
  if ((values['_files'] as List? ?? const []).isNotEmpty ||
      (values['_attachments'] as List? ?? const []).isNotEmpty) {
    throw const FormatException(
      'Supplier supporting-document saving is not connected yet. Remove the staged files to save contact details.',
    );
  }
  final currency = value('Preferred Billing Currency');
  return Vendor(
    metadata: original == null
        ? RecordMetadata.initial(
            recordId: id,
            businessId: workspace.identity.businessId,
            originDeviceId: workspace.identity.deviceId,
            createdAt: now,
          )
        : original.metadata.nextRevision(updatedAt: now),
    additionalValues: {
      for (final field in vendorAdditionalFields.entries)
        field.value: values.containsKey(field.key)
            ? value(field.key)
            : original?.additionalValues[field.value] ?? '',
    },
    payeeId: payeeId,
    name: value('Name'),
    type: vendorPayeeTypes.firstWhere(
      (type) => type.label == value('Vendor Type'),
      orElse: () => throw const FormatException('Choose a vendor type.'),
    ),
    details: VendorDetails(
      values: {
        for (final field in _detailFields.entries)
          field.value: value(field.key),
        'countryCode': switch (country) {
          'Malaysia' => 'MY',
          'Singapore' => 'SG',
          '' => '',
          _ => value('Country ISO Code').toUpperCase(),
        },
      },
      taxDetailsNeeded: values['Tax Details Needed'] == true,
    ),
    currency: Currency.parse(
      currency.isEmpty || currency == 'Use Company Default'
          ? workspace.identity.currency
          : currency,
    ),
    terms: terms,
  );
}

Future<Vendor?> showAccountingVendorDialog(
  BuildContext context,
  AccountingWorkspace workspace, {
  VendorDirectoryEntry? entry,
}) async {
  final original = entry?.vendor;
  final id = original?.id ?? EntityId.random();
  final accounts = await workspace.accounts();
  if (!context.mounted) return null;
  final expenseAccounts = {
    for (final stored in accounts)
      if (stored.account.type == AccountType.expense &&
          !stored.account.isParent &&
          stored.account.status == AccountStatus.active)
        stored.account.id.value: stored.account.displayName,
  };
  final savedDefault = original?.additionalValues['defaultExpenseAccountId'];
  if (savedDefault != null && !expenseAccounts.containsKey(savedDefault)) {
    final savedAccounts = accounts.where(
      (a) => a.account.id.value == savedDefault,
    );
    expenseAccounts[savedDefault] = savedAccounts.isEmpty
        ? 'Unavailable Saved Expense Account'
        : savedAccounts.single.account.displayName;
  }
  Vendor? saved;
  await showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => FrontendFormDialog(
      form: vendorProfileProposal(
        expenseAccounts: expenseAccounts,
        currencyCode: original?.currency.code ?? workspace.identity.currency,
        preserveCurrentTerms: true,
      ),
      initial: original == null
          ? {
              'Name': entry?.payee.name ?? '',
              'Vendor Type': (entry?.payee.type ?? PayeeType.supplier).label,
              'Country': 'Malaysia',
              'Country ISO Code': 'MY',
              'Preferred Billing Currency': workspace.identity.currency,
              'Payment Terms': 'Days After Issue',
              'Number Of Days': '0',
              'Monthly Due Day': '1',
              'Rollover Within Days': '0',
            }
          : vendorFormValues(original),
      onCommit: (values) async {
        final next = vendorFromForm(
          values,
          workspace,
          id: id,
          payeeId: entry?.payee.id ?? id.value,
          original: original,
          now: DateTime.now().toUtc(),
        );
        workspace.saveVendor(
          next,
          expectedRevision: original?.metadata.revision ?? 0,
          expectedPayee: entry?.payee,
        );
        saved = next;
      },
    ),
  );
  return saved;
}

class VendorsPage extends StatefulWidget {
  const VendorsPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<VendorsPage> createState() => _VendorsPageState();
}

class _VendorsPageState extends State<VendorsPage> {
  AccountingWorkspace get workspace => widget.workspace;
  final _search = TextEditingController();
  PayeeType? _type;
  int _offset = 0;
  int _pageSize = AccountingRecordPageSizes.read('vendor');
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit([VendorDirectoryEntry? entry]) async {
    await showAccountingVendorDialog(context, workspace, entry: entry);
  }

  Future<void> _view(
    VendorDirectoryEntry entry, {
    bool historical = false,
  }) async {
    final accounts = await workspace.accounts();
    if (!mounted) return;
    final accountLabels = {
      for (final stored in accounts)
        stored.account.id.value: stored.account.displayName,
    };
    String additionalValue(String key, String value) =>
        key == 'defaultExpenseAccountId'
        ? (value.isEmpty
              ? 'Not Set'
              : accountLabels[value] ??
                    'Unavailable Saved Expense Account ($value)')
        : value;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final vendor = entry.vendor;
        return AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: historical
              ? 'Vendor Revision ${vendor!.metadata.revision}'
              : 'View Vendor',
          maxContentWidth: AccountingPopoutTokens.widerContentWidth,
          actions: const [],
          content: SizedBox(
            width: AccountingPopoutTokens.widerContentWidth,
            key: const ValueKey('vendor-details'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountingInformationRows(
                  rows: [
                    ('Name', entry.payee.name),
                    ('Vendor Type', entry.payee.type.label),
                    ('Supplier ID', entry.payee.id),
                    if (vendor != null) ...[
                      ('Profile ID', vendor.id.value),
                      ('Revision', '${vendor.metadata.revision}'),
                      ('Updated', vendor.metadata.updatedAt.toIso8601String()),
                      for (final field in _detailFields.entries)
                        (field.key, vendor.details[field.value]),
                      (
                        'Currency',
                        CurrencyPresentation.fromCode(vendor.currency.code)
                            .amountSymbol,
                      ),
                      for (final field in vendorAdditionalFields.entries)
                        if (vendor.additionalValues.containsKey(field.value))
                          (
                            field.key,
                            additionalValue(
                              field.value,
                              vendor.additionalValues[field.value]!,
                            ),
                          ),
                      ('Payment Terms', vendor.terms.label),
                      (
                        'Tax Details Needed',
                        vendor.details.taxDetailsNeeded ? 'Yes' : 'No',
                      ),
                    ],
                  ],
                ),
                if (vendor == null) ...[
                  const SizedBox(height: accountingContentInset),
                  const Text('Contact details have not been recorded.'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _history(Vendor vendor) => showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.custom,
      title: 'Vendor History',
      maxContentWidth: AccountingPopoutTokens.widerContentWidth,
      actions: const [],
      content: SizedBox(
        width: AccountingPopoutTokens.widerContentWidth,
        child: AccountingRecordList(
          paginationKey: 'vendors-1',
          children: [
            for (final version
                in workspace.database
                    .vendorHistory(workspace.identity.businessId, vendor.id)
                    .reversed)
              AccountingRecordRow(
                title: 'Revision ${version.metadata.revision}',
                details: Text(
                  '${version.name} · ${version.metadata.updatedAt.toIso8601String()}',
                ),
                trailing: AccountingRecordActions(
                  trailing: [
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey(
                        'vendor-history-view-${version.metadata.revision}',
                      ),
                      icon: Icons.visibility_outlined,
                      tooltip: 'View Revision',
                      onPressed: () => _view(
                        VendorDirectoryEntry(version.payee, version),
                        historical: true,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final controlCount = workspace.database
          .vendorDirectory(businessId: workspace.identity.businessId, limit: 1)
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = workspace.database.vendorDirectory(
        businessId: workspace.identity.businessId,
        search: showControls ? _search.text : '',
        type: showControls ? _type : null,
        offset: showControls ? _offset : 0,
        limit: _pageSize,
      );
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Vendors',
              title: 'Vendors',
              description:
                  'Supplier contacts and payment terms for this company.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('new-vendor'),
                onPressed: _edit,
                child: const Text('New Vendor'),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            AccountingRecordControls(
              recordCount: controlCount,
              child: Wrap(
                spacing: accountingContentInset,
                runSpacing: AccountingPageControlScope.runGapOf(context),
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(context, 'Search'),
                        const SizedBox(height: accountingFieldLabelGap),
                        SizedBox(
                          height: 44,
                          child: TextField(
                            key: const ValueKey('vendor-search'),
                            controller: _search,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Name, email or telephone',
                            ),
                            onChanged: (_) => setState(() => _offset = 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Vendor Type',
                    controlKey: const ValueKey('vendor-type-filter'),
                    options: [for (final type in vendorPayeeTypes) type.label],
                    value: _type?.label,
                    onChanged: (value) => setState(() {
                      _type = value == null
                          ? null
                          : vendorPayeeTypes.firstWhere(
                              (type) => type.label == value,
                            );
                      _offset = 0;
                    }),
                  ),
                  if (_search.text.isNotEmpty || _type != null)
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('clear-vendor-filter'),
                      child: const Text('Clear'),
                      onPressed: () => setState(() {
                        _search.clear();
                        _type = null;
                        _offset = 0;
                      }),
                    ),
                ],
              ),
            ),
            if (showControls) const SizedBox(height: accountingContentInset),
            if (page.entries.isEmpty)
              const AccountingPageText('No matching vendors.'),
            AccountingRecordList(
              totalCount: controlCount,
              paginationKey: 'vendors-2',
              externalPagination: page.total == 0
                  ? null
                  : Padding(
                      padding: accountingContentPadding,
                      child: AccountingRecordPagination(
                        total: page.total,
                        unfilteredTotal: controlCount,
                        offset: page.offset,
                        pageSize: _pageSize,
                        keyPrefix: 'vendor',
                        onPageSizeChanged: (size) => setState(() {
                          _pageSize = size;
                          _offset = 0;
                        }),
                        onPrevious: page.offset == 0
                            ? null
                            : () => setState(
                                () => _offset = (page.offset - _pageSize).clamp(
                                  0,
                                  page.total,
                                ),
                              ),
                        onNext: page.offset + _pageSize >= page.total
                            ? null
                            : () => setState(
                                () => _offset = page.offset + _pageSize,
                              ),
                      ),
                    ),
              children: [
                for (final entry in page.entries)
                  AccountingRecordRow(
                    key: ValueKey('vendor-row-${entry.payee.id}'),
                    title: entry.payee.name,
                    details: Text(
                      [
                        entry.payee.type.label,
                        if (entry.vendor?.details['email'].isNotEmpty == true)
                          entry.vendor!.details['email'],
                      ].join(' · '),
                    ),
                    trailing: AccountingRecordActions(
                      trailing: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('view-vendor-${entry.payee.id}'),
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Vendor',
                          onPressed: () => _view(entry),
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('edit-vendor-${entry.payee.id}'),
                          icon: Icons.edit_outlined,
                          tooltip: entry.vendor == null
                              ? 'Add Vendor Details'
                              : 'Edit Vendor',
                          onPressed: () => _edit(entry),
                        ),
                        if (entry.vendor != null)
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('history-vendor-${entry.payee.id}'),
                            icon: Icons.history_outlined,
                            tooltip: 'History',
                            onPressed: () => _history(entry.vendor!),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
