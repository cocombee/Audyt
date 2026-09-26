import '../../../app/frontend_review.dart';
import '../../accounting/domain/payee.dart';
import '../domain/vendor.dart';

final vendorBaseForm = DesignForm('Vendors', [
  for (final field in partyFields)
    if (field.label == 'Name') ...[
      field,
      DesignField(
        'Vendor Type',
        required: true,
        options: [for (final type in vendorPayeeTypes) type.label],
      ),
    ] else if (field.label == 'Payment Terms')
      const DesignField(
        'Payment Terms',
        required: true,
        options: ['Days After Issue', 'Day Of Month', 'Custom'],
      )
    else if (field.label == 'Country Name') ...[
      field,
      const DesignField('Country ISO Code'),
    ] else
      field,
]);

/// One field specification for the existing Vendor owner and review captures.
/// Production preserves structured timing; opening/evidence commands remain gated.
DesignForm vendorProfileProposal({
  required Map<String, String> expenseAccounts,
  String currencyCode = 'MYR',
  bool preserveCurrentTerms = false,
}) => DesignForm(
  'Vendors',
  [
    for (final field in vendorBaseForm.fields)
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
      ] else if (field.label == 'Payment Terms') ...[
        // Exact observed Terms are a proposed alternative to the current
        // structured timing editor; neither set is silently converted.
        if (preserveCurrentTerms)
          field
        else
          const DesignField(
            'Supplier Terms',
            options: ['Due On Receipt', 'Net 15', 'Net 30', 'Net 60', 'Net 90'],
          ),
        const DesignField(
          'Supplier Category',
          options: [
            'Domestic Business',
            'Domestic Individual',
            'Foreign Business',
            'Foreign Individual',
          ],
        ),
        const DesignField('Account Number'),
        DesignField('Default Expense Category', choiceLabels: expenseAccounts),
        DesignField(
          'Billing Rate Per Hour',
          customLayout: true,
          currencyCode: currencyCode,
          currencySourceLabel: preserveCurrentTerms
              ? 'Preferred Billing Currency'
              : null,
        ),
        DesignField(
          'Opening Balance',
          customLayout: true,
          currencyCode: currencyCode,
          currencySourceLabel: preserveCurrentTerms
              ? 'Preferred Billing Currency'
              : null,
        ),
        const DesignField('Opening Balance Date'),
      ] else
        field,
  ],
  evidence: true,
  actionLabel: preserveCurrentTerms ? 'Save Vendor' : 'Preview Vendor',
);
