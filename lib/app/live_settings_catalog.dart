import '../features/accounting/domain/company_preferences.dart';
import 'frontend_catalog.dart';

/// Shortcuts expose only durable settings with consumers on that form.
/// The ordinary Settings editor and company revision remain the sole owners.
Map<String, Set<String>> transactionSettingsFields(String title) {
  final sections = switch (title) {
    'Invoices' ||
    'Quotations' => ['Sales Preferences', 'Numbering & Document Appearance'],
    'Sales Receipts' => ['Sales Preferences'],
    'Record Expense' => ['Purchase Preferences'],
    'Bills' => ['Purchase Preferences'],
    'Products & Services' => ['Default Accounts'],
    _ => const <String>[],
  };
  return {
    for (final section in sections)
      section: switch ((title, section)) {
        (_, 'Default Accounts') => {'Income Account'},
        ('Sales Receipts', 'Sales Preferences') => {
          'Default Tax Mode',
          'Show Quantity',
          'Show Rate',
          'Show Class',
        },
        ('Bills', 'Purchase Preferences') => {
          'Show Quantity',
          'Show Rate',
          'Enable Discounts',
          'Show Class',
        },
        ('Record Expense', 'Purchase Preferences') => {
          'Show Quantity',
          'Show Rate',
          'Track Items',
          'Link To Customer',
          'Billable Expenses',
        },
        _ => CompanyPreferences.supportedDefaults[section]!.keys.toSet(),
      },
  };
}

/// Live controls are deliberately narrower than the design catalogue.
/// Every field listed here has a durable consumer, not a preview promise.
List<DesignForm> liveSettingsForms(
  Map<String, Map<String, String>> accountChoices,
) => [
  for (final section in CompanyPreferences.supportedDefaults.entries)
    DesignForm(section.key, [
      for (final field
          in settingsForms
              .firstWhere((form) => form.title == section.key)
              .fields)
        if (section.value.containsKey(field.label))
          field.label == 'Export Format'
              ? const DesignField('Export Format', options: ['JSON', 'CSV'])
              : field.label.endsWith('Account')
              ? DesignField(
                  field.label,
                  choiceLabels: {
                    '': 'No Default',
                    ...?accountChoices[field.label],
                  },
                )
              : field,
    ], actionLabel: 'Save'),
];
