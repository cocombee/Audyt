import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/frontend_catalog.dart';
import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';

void main() => stdout.writeln(
  const JsonEncoder.withIndent('  ').convert([
    for (final form in liveSettingsForms({}))
      {
        'section': form.title,
        'live': true,
        'action': 'Save',
        'fields': [
          for (final f in form.fields)
            {
              'label': f.label,
              'switch': f.toggle,
              'options': f.options,
              'required': f.required,
              'guidance': accountingFieldGuidance(f.label),
              'default':
                  CompanyPreferences.supportedDefaults[form.title]![f.label],
            },
        ],
      },
    for (final form in settingsForms)
      if (form.fields.any(
        (field) =>
            !(CompanyPreferences.supportedDefaults[form.title]?.containsKey(
                  field.label,
                ) ??
                false),
      ))
        {
          'section': form.title,
          'live': false,
          'offeredInSettings': false,
          'reason': 'No completed durable consumer. Design catalogue only.',
          'fields': [
            for (final field in form.fields)
              if (!(CompanyPreferences.supportedDefaults[form.title]
                      ?.containsKey(field.label) ??
                  false))
                {'label': field.label, 'options': field.options},
          ],
        },
  ]),
);
