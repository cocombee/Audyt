import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/frontend_review.dart';

/// Physical setup only. Draft choices never replace company or customer facts.
Future<void> showStatementSettingsPreview(
  BuildContext context,
) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: 600,
  builder: (_) => FrontendFormDialog(
    contentWidth: 600,
    previewConfirmationEnabled: false,
    initial: const {'Transaction Detail': '', 'Show Ageing Table': false},
    leadingContentBuilder: (context, values, reviewing) => Padding(
      padding: const EdgeInsets.only(bottom: accountingContentInset),
      child: accountingHelperText(
        context,
        'Saving statement settings is not connected yet.',
      ),
    ),
    form: const DesignForm(
      'Statement Settings',
      [
        DesignField(
          'Transaction Detail',
          required: true,
          choiceLabels: {
            'single': 'Single Transaction Line',
            'detail': 'All Detail Lines',
          },
        ),
        DesignField('Show Ageing Table', toggle: true),
      ],
      description: 'Statement settings preview. Saving is not connected yet.',
      actionLabel: 'Save Statement Settings',
    ),
    reviewInformationRowsBuilder: (values) {
      final detail = switch (values['Transaction Detail']) {
        'single' => 'Single Transaction Line',
        'detail' => 'All Detail Lines',
        _ => throw const FormatException('Choose a transaction detail level.'),
      };
      return [
        ('Transaction Detail', detail),
        (
          'Show Ageing Table',
          values['Show Ageing Table'] == true ? 'Yes' : 'No',
        ),
      ];
    },
  ),
);
