import 'dart:convert';

/// Company-scoped preferences with an explicit list of implemented consumers.
/// New controls must be added here only alongside their page/service consumer.
final class CompanyPreferences {
  CompanyPreferences._(this.sections, this.revision);
  factory CompanyPreferences.defaults() => CompanyPreferences._({}, 0);
  factory CompanyPreferences.fromJson(
    Map<String, dynamic> json, {
    int revision = 0,
  }) {
    final sections = <String, Map<String, Object?>>{};
    for (final entry in json.entries) {
      if (!supportedDefaults.containsKey(entry.key) || entry.value is! Map) {
        throw const FormatException('Unsupported company setting.');
      }
      sections[entry.key] = _validate(
        entry.key,
        Map<String, Object?>.from(entry.value as Map),
      );
    }
    return CompanyPreferences._(Map.unmodifiable(sections), revision);
  }
  final Map<String, Map<String, Object?>> sections;
  final int revision;
  static const supportedDefaults = <String, Map<String, Object?>>{
    'Business Profile': {
      'Business Name': '',
      'Legal Name': '',
      'Registration Number': '',
      'Address Line 1': '',
      'Address Line 2': '',
      'City': '',
      'Postcode': '',
      'Country': 'Malaysia',
      'State / Region': '',
      'Country Name': '',
      'Email': '',
      'Telephone': '',
      'Website': '',
      'Business Logo': '',
      '_businessLogoBase64': '',
    },
    'Default Accounts': {
      'Receivables Account': '',
      'Payables Account': '',
      'Income Account': '',
      'Sales Tax Liability Account': '',
    },
    'Sales Preferences': {
      'Default Tax Mode': 'Exclusive',
      'Show Quantity': false,
      'Show Rate': false,
      'Enable Discounts': false,
      'Show Class': false,
      'Customer Message': '',
    },
    'Purchase Preferences': {
      'Show Quantity': false,
      'Show Rate': false,
      'Enable Discounts': false,
      'Show Class': false,
      'Track Items': true,
      'Link To Customer': true,
      'Billable Expenses': true,
    },
    'Reminders & Approvals': {
      'Days Before Due Date': '14',
      'Visible Reminders': '3',
      'Notify When Overdue': true,
    },
    'Backup & Export Preferences': {
      'Backup Frequency': 'Manual',
      'Export Format': 'JSON',
    },
    'Numbering & Document Appearance': {
      'Number Prefix': 'INV',
      'Number Padding': '6 Digits',
      'Show Logo': true,
      'Show Registration': true,
      'Show Tax Breakdown': true,
      'Footer': '',
    },
  };
  Map<String, Object?> values(String section) =>
      Map.unmodifiable({...supportedDefaults[section]!, ...?sections[section]});
  bool enabled(String section, String field) => values(section)[field] == true;
  String text(String section, String field) => values(section)[field] as String;
  CompanyPreferences change(String section, Map<String, Object?> input) =>
      CompanyPreferences._(
        Map.unmodifiable({
          ...sections,
          section: _validate(section, {...?sections[section], ...input}),
        }),
        revision,
      );
  Map<String, Object?> toJson() => sections;
  static Map<String, Object?> _validate(
    String section,
    Map<String, Object?> input,
  ) {
    // Read older archives through one migration; current UI/storage use the two
    // independent switches. Rate always requires Quantity.
    input = {...input};
    if (input.containsKey('Show Quantity & Rate')) {
      final legacy = input.remove('Show Quantity & Rate');
      input.putIfAbsent('Show Quantity', () => legacy);
      input.putIfAbsent('Show Rate', () => legacy);
    }
    final allowed = supportedDefaults[section];
    if (allowed == null) {
      throw const FormatException('Unsupported settings section.');
    }
    final result = <String, Object?>{};
    for (final entry in input.entries) {
      if (!allowed.containsKey(entry.key)) {
        if (entry.key.startsWith('_') && entry.key != '_businessLogoBase64') {
          continue;
        }
        throw FormatException('Unsupported setting: ${entry.key}.');
      }
      if (allowed[entry.key] is bool && entry.value is! bool ||
          allowed[entry.key] is String && entry.value is! String) {
        throw FormatException('Invalid value for ${entry.key}.');
      }
      final value = entry.value;
      if (value is String &&
          value.length >
              (entry.key == '_businessLogoBase64' ? 1000000 : 4000)) {
        throw FormatException('${entry.key} is too long.');
      }
      result[entry.key] = value is String ? value.trim() : value;
    }
    if ((section == 'Sales Preferences' || section == 'Purchase Preferences') &&
        result['Show Rate'] == true) {
      result['Show Quantity'] = true;
    }
    if (section == 'Sales Preferences' &&
        !const [
          'Exclusive',
          'Inclusive',
        ].contains(result['Default Tax Mode'] ?? 'Exclusive')) {
      throw const FormatException(
        'Choose Inclusive or Exclusive for sales amounts.',
      );
    }
    if (section == 'Business Profile' &&
        (result['_businessLogoBase64'] as String? ?? '').isNotEmpty) {
      try {
        base64Decode(result['_businessLogoBase64'] as String);
      } on FormatException {
        throw const FormatException('Choose a valid logo image.');
      }
    }
    if (section == 'Reminders & Approvals') {
      if (!['2', '3', '4'].contains(result['Visible Reminders'] ?? '3')) {
        throw const FormatException(
          'Choose two, three or four visible reminders.',
        );
      }
      final days = int.tryParse(
        result['Days Before Due Date'] as String? ?? '14',
      );
      if (days == null || days < 0 || days > 365) {
        throw const FormatException(
          'Enter a reminder lead time from 0 to 365 days.',
        );
      }
    }
    if (section == 'Purchase Preferences' &&
        (result['Billable Expenses'] ?? true) == true &&
        (result['Link To Customer'] ?? true) == false) {
      throw const FormatException(
        'Billable expenses require customer linkage.',
      );
    }
    if (section == 'Numbering & Document Appearance') {
      final prefix = (result['Number Prefix'] ?? 'INV') as String;
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,19}$').hasMatch(prefix)) {
        throw const FormatException(
          'Use 1–20 letters, digits, hyphens or underscores for the prefix.',
        );
      }
      if (![
        'None',
        '3 Digits',
        '4 Digits',
        '5 Digits',
        '6 Digits',
      ].contains(result['Number Padding'] ?? '6 Digits')) {
        throw const FormatException('Choose valid number padding.');
      }
    }
    if (section == 'Backup & Export Preferences' &&
        (![
              'Manual',
              'Daily',
              'Weekly',
              'Monthly',
            ].contains(result['Backup Frequency'] ?? 'Manual') ||
            !['JSON', 'CSV'].contains(result['Export Format'] ?? 'JSON'))) {
      throw const FormatException(
        'Choose a supported backup frequency and export format.',
      );
    }
    if (section == 'Business Profile' &&
        ![
          'Malaysia',
          'Singapore',
          'Other Country',
        ].contains(result['Country'] ?? 'Malaysia')) {
      throw const FormatException('Choose a valid country.');
    }
    return Map.unmodifiable(result);
  }
}
