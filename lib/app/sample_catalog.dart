import 'package:flutter/material.dart';

import 'frontend_review.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';

/// Session-only examples. Never pass these maps to accounting repositories.
Map<String, Object?> sampleValues(DesignForm form, int variation) => {
  for (final field in form.fields)
    field.label: field.toggle
        ? variation.isEven
        : field.options.isNotEmpty
        ? field.options[variation % field.options.length]
        : _example(field.label, variation),
  if (form.lines)
    '_lines': [
      {
        'Description': 'Example Office Supplies',
        'Quantity': '2',
        'Rate': '50.00',
        'Tax Code': 'Example Tax — Review Required',
        'Account': 'Example Expense Account',
      },
      {
        'Description': 'Example Service',
        'Quantity': '1',
        'Rate': '250.00',
        'Tax Code': 'Example Exempt',
        'Account': 'Example Expense Account',
      },
    ],
};
String _example(String label, int n) {
  final key = label.toLowerCase();
  if (key.contains('date') || key.contains('from') || key.contains('through')) {
    return '13-09-2026';
  }
  if (key.contains('email')) return 'example@example.com';
  if (key.contains('postcode')) return '50450';
  if (key.contains('city')) return 'Kuala Lumpur';
  if (key.contains('address')) return '${n + 1} Example Street';
  if (key.contains('amount') ||
      key.contains('cost') ||
      key.contains('balance')) {
    return '350.00';
  }
  if (key.contains('rate') || key.contains('percentage')) return '0';
  if (key.contains('tin') ||
      key.contains('registration') ||
      key.contains('identification')) {
    return 'EXAMPLE ONLY';
  }
  if (key.contains('number') || key.contains('reference')) {
    return 'EXAMPLE-${n + 1}';
  }
  if (key.contains('telephone')) return '+60 00 000 0000';
  return 'Example $label';
}

class SampleCatalog extends StatelessWidget {
  const SampleCatalog({super.key, this.onlyForm});
  final DesignForm? onlyForm;
  @override
  Widget build(BuildContext context) {
    final groups = onlyForm != null
        ? {
            'Current Section': [onlyForm!],
          }
        : {
            'Settings': settingsForms,
            'Operational Inputs': operationalExamples,
            ...frontendAreas,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Design Examples',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Fictional, session-only inputs. Tax values are illustrative, not configured rates. Each variation cycles the available selections and switches; these are not saved accounting records.',
        ),
        for (final group in groups.entries)
          ExpansionTile(
            title: Text(
              group.key == 'Current Section'
                  ? onlyForm!.title
                  : group.key
                        .replaceAll('-', ' ')
                        .split(' ')
                        .map(
                          (s) => s.isEmpty
                              ? s
                              : s[0].toUpperCase() + s.substring(1),
                        )
                        .join(' '),
            ),
            children: [
              for (final form in group.value)
                ExpansionTile(
                  title: Text(form.title),
                  children: [
                    SampleStateRows(form: form),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _count(form); i++)
                            AccountingButton.outline(
                              context,
                              key: ValueKey("sample-${form.title}-$i"),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FrontendFormDialog(
                                  form: form,
                                  initial: sampleValues(form, i),
                                  accountOptions: const [
                                    'Example Bank',
                                    'Example Expense Account',
                                    'Example Asset Account',
                                  ],
                                ),
                              ),
                              child: Text('Input Variation ${i + 1}'),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Open a variation to inspect populated inputs, tax selections and conditional details. Changes remain in this preview.',
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  int _count(DesignForm form) => form.fields.fold<int>(
    2,
    (n, f) => f.options.length > n ? f.options.length : n,
  );
}

List<String> sampleStates(String title) {
  if (settingsForms.any((f) => f.title == title)) {
    return ['Configured', 'Incomplete', 'Validation Error'];
  }
  if ([
    'Customers',
    'Vendors',
    'Contacts',
    'Products & Services',
    'Tax Codes',
  ].contains(title)) {
    return ['Active', 'Inactive', 'Missing Details'];
  }
  if (title == 'Deadlines') {
    return ['Upcoming', 'Due Today', 'Overdue', 'Completed'];
  }
  if (title == 'Fixed Assets') {
    return ['Draft', 'In Service', 'Fully Depreciated', 'Disposed'];
  }
  if (title.contains('Report') ||
      [
        'Cash Flow',
        'Changes In Equity',
        'Receivables Ageing',
        'Payables Ageing',
        'Tax Reconciliation',
      ].contains(title)) {
    return ['Ready', 'No Activity', 'Review Needed'];
  }
  if (title.contains('Document') ||
      title == 'For Review' ||
      title == 'Filing History') {
    return ['Uploaded', 'Needs Review', 'Linked', 'Filing Failed'];
  }
  if (['Invoices', 'Bills'].contains(title)) {
    return [
      'Draft',
      'Pending Approval',
      'Approved',
      'Partially Paid',
      'Paid',
      'Overdue',
      'Voided',
    ];
  }
  if (title == 'Quotations' || title == 'Purchase Orders') {
    return ['Draft', 'Pending Approval', 'Approved', 'Declined', 'Expired'];
  }
  return ['Draft', 'Pending Review', 'Approved', 'Completed', 'Rejected'];
}

class SampleStateRows extends StatelessWidget {
  const SampleStateRows({super.key, required this.form});
  final DesignForm form;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final status in sampleStates(form.title))
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: Icon(
            status.contains('Error') ||
                    status.contains('Failed') ||
                    status == 'Rejected'
                ? Icons.error_outline
                : Icons.description_outlined,
            size: 20,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  'Example ${form.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: accountingRecordTitleLabelGap),
              AccountingBadge.build(context, label: status),
            ],
          ),
          subtitle: Text(
            'EXAMPLE-${sampleStates(form.title).indexOf(status) + 1}',
          ),
          trailing: AccountingButton.outline(
            context,
            key: ValueKey('view-state-${form.title}-$status'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AccountingDialog.alert(
                dialogContext,
                widthFamily: AccountingPopoutWidthFamily.normal,
                title: 'Example ${form.title}',
                description: '$status · Fictional record for design review',
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(label: Text(status)),
                      const SizedBox(height: 12),
                      Text(_stateHelp(status)),
                      const Divider(height: 24),
                      for (final entry in sampleValues(
                        form,
                        0,
                      ).entries.where((e) => !e.key.startsWith('_')))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text('${entry.value}'),
                            ],
                          ),
                        ),
                      if (form.evidence)
                        const Text(
                          'Supporting Documents: Example Receipt.pdf · Metadata only; no file was uploaded.',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'These statuses are visual examples. No approval, payment, depreciation or submission has occurred.',
                      ),
                    ],
                  ),
                ),
                actions: [],
              ),
            ),
            child: const Text('View'),
          ),
        ),
    ],
  );
  String _stateHelp(String status) => switch (status) {
    'Rejected' || 'Declined' =>
      'Example reviewer feedback: correct the supporting details and resubmit.',
    'Overdue' => 'Example follow-up: the due date has passed. Review the outstanding item.',
    'Partially Paid' =>
      'Example original: RM 350.00 · Paid: RM 150.00 · Remaining: RM 200.00.',
    'Paid' =>
      'Example original: RM 350.00 · Paid: RM 350.00 · Remaining: RM 0.00.',
    'Validation Error' || 'Missing Details' || 'Incomplete' =>
      'Example issue: required identity or reference details are missing.',
    'Filing Failed' => 'Example issue: destination unavailable. Original document remains available for retry.',
    _ => 'Review this sample record and its current status.',
  };
}

const operationalExamples = <DesignForm>[
  DesignForm(
    'Expenses',
    [
      DesignField('Payee'),
      DesignField('Date'),
      DesignField('Amount'),
      DesignField('Payment Account'),
      DesignField(
        'Category',
        options: ['Fuel', 'Office Supplies', 'Asset Purchase'],
      ),
      DesignField('Tax Mode', options: taxModes),
      DesignField('Memo', multiline: true),
    ],
    lines: true,
    recurring: true,
    evidence: true,
  ),
  DesignForm(
    'Claims',
    [
      DesignField('Claimant'),
      DesignField('Date'),
      DesignField('Amount'),
      DesignField('Category', options: ['Travel', 'Fuel', 'Office Supplies']),
      DesignField('Reason', multiline: true),
    ],
    lines: true,
    evidence: true,
  ),
  DesignForm('Payment Vouchers', [
    DesignField('Payee'),
    DesignField('Date'),
    DesignField('Amount'),
    DesignField('Payment Account'),
    DesignField('Payment Method', options: paymentMethods),
    DesignField('Reference'),
  ], evidence: true),
  DesignForm('Chart Of Accounts', [
    DesignField('Account Name'),
    DesignField('Account Number'),
    DesignField(
      'Account Type',
      options: ['Asset', 'Liability', 'Equity', 'Income', 'Expense'],
    ),
    DesignField('Currency', options: currencies),
  ]),
  DesignForm(
    'Journal Review',
    [
      DesignField('Date'),
      DesignField('Reference'),
      DesignField('Reason', multiline: true),
    ],
    lines: true,
    evidence: true,
  ),
];
