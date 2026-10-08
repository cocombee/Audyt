import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/frontend_review.dart';

// These are independent physical previews, never company or document defaults.
const _salesForms = <String, String>{
  'invoice': 'Invoice',
  'quotation': 'Quotation',
  'credit-note': 'Credit Note',
  'sales-receipt': 'Sales Receipt',
  'statement': 'Statement',
  'refund-receipt': 'Refund Receipt',
};
const _salutations = <String, String>{
  'blank': '<Blank>',
  'to': 'To:',
  'dear': 'Dear',
};
const _nameFormats = <String, String>{
  'first-last': '[First] [Last]',
  'title-last': '[Title] [Last]',
  'first': '[First]',
  'full': '[Full Name]',
  'company': '[Company Name]',
  'display': '[Display Name]',
};

Future<void> showSalesMessagesPreview(
  BuildContext context,
) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => FrontendFormDialog(
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    previewConfirmationEnabled: false,
    initial: const {'Use Greeting': false, 'Email Me A Copy': false},
    leadingContentBuilder: (context, values, reviewing) => Padding(
      padding: const EdgeInsets.only(bottom: accountingContentInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingHelperText(
            context,
            'Saving email settings, standard messages and sending are not connected yet. '
            'PDF customer messages remain in Sales Preferences.',
          ),
          if (!reviewing) ...[
            const SizedBox(height: accountingContentInset),
            AccountingButton.ghost(
              context,
              key: const ValueKey('email-use-standard-message'),
              onPressed: null,
              child: const Text('Use Standard Message'),
            ),
          ],
        ],
      ),
    ),
    form: const DesignForm(
      'Sales Email Messages',
      [
        DesignField('Use Greeting', toggle: true),
        DesignField('Salutation', choiceLabels: _salutations),
        DesignField('Name Format', choiceLabels: _nameFormats),
        DesignField('Sales Form', choiceLabels: _salesForms, required: true),
        DesignField('Email Subject Line'),
        DesignField('Email Message', multiline: true),
        DesignField('Email Me A Copy', toggle: true),
        DesignField('Copy (Cc)'),
        DesignField('Blind Copy (Bcc)'),
      ],
      description:
          'Email message preview. Saving and sending are not connected yet.',
      actionLabel: 'Save Email Messages',
    ),
    reviewInformationRowsBuilder: (values) => [
      ('Use Greeting', values['Use Greeting'] == true ? 'Yes' : 'No'),
      ('Salutation', _salutations[values['Salutation']] ?? 'Not Set'),
      ('Name Format', _nameFormats[values['Name Format']] ?? 'Not Set'),
      ('Sales Form', _salesForms[values['Sales Form']] ?? 'Not Set'),
      ('Email Subject Line', '${values['Email Subject Line'] ?? ''}'),
      ('Email Message', '${values['Email Message'] ?? ''}'),
      ('Email Me A Copy', values['Email Me A Copy'] == true ? 'Yes' : 'No'),
      ('Copy (Cc)', '${values['Copy (Cc)'] ?? ''}'),
      ('Blind Copy (Bcc)', '${values['Blind Copy (Bcc)'] ?? ''}'),
    ],
  ),
);

Future<void> showOnlineDeliveryPreview(
  BuildContext context,
) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => FrontendFormDialog(
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    previewConfirmationEnabled: false,
    initial: const {'PDF Attached': false},
    leadingContentBuilder: (context, values, reviewing) => Padding(
      padding: const EdgeInsets.only(bottom: accountingContentInset),
      child: accountingHelperText(
        context,
        'Saving online delivery settings and sending are not connected yet.',
      ),
    ),
    form: const DesignForm(
      'Online Delivery Settings',
      [
        DesignField(
          'Email Options',
          required: true,
          choiceLabels: {
            'summary': 'Show Short Summary In Email',
            'details': 'Show Full Details In Email',
          },
        ),
        DesignField(
          'Additional Email Options For Invoices',
          required: true,
          choiceLabels: {'online': 'Online Invoice', 'plain': 'Plain Text'},
        ),
        DesignField('PDF Attached', toggle: true),
      ],
      description:
          'Online delivery preview. Saving and sending are not connected yet.',
      actionLabel: 'Save Online Delivery',
    ),
    reviewInformationRowsBuilder: (values) => [
      (
        'Email Options',
        values['Email Options'] == 'details'
            ? 'Show Full Details In Email'
            : 'Show Short Summary In Email',
      ),
      ('PDF Attached', values['PDF Attached'] == true ? 'Yes' : 'No'),
      (
        'Additional Email Options For Invoices',
        values['Additional Email Options For Invoices'] == 'plain'
            ? 'Plain Text'
            : 'Online Invoice',
      ),
    ],
  ),
);
