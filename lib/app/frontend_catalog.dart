import 'accounting_description_field.dart' show AccountingDescriptionRole;

/// Frontend review specifications. These do not configure tax or post records.
class DesignField {
  const DesignField(
    this.label, {
    this.options = const [],
    this.choiceLabels,
    this.disabledOptions = const {},
    this.toggle = false,
    this.checkbox = false,
    this.multiline = false,
    this.fullWidth = false,
    this.customLayout = false,
    this.minimumRowFraction = 0,
    this.required = false,
    this.monetary = false,
    this.currencyCode,
    this.currencySourceLabel,
    this.descriptionRole = AccountingDescriptionRole.narrative,
  });
  final String label;
  final List<String> options;

  /// Stable persisted value to display label; null keeps ordinary text choices.
  final Map<String, String>? choiceLabels;
  final Set<String> disabledOptions;
  final bool toggle;

  /// Compact checkbox using the existing directory/Chart control owner.
  final bool checkbox;
  final bool multiline;

  /// Explicit full-row field; never inferred from a label or inherited.
  final bool fullWidth;

  /// Explicit custom-owner exemption from shared ordinary popup rows.
  final bool customLayout;

  /// Ordinary popup minimum share; embedded and custom owners ignore it.
  final double minimumRowFraction;
  final bool required;

  /// Uses the existing amount editor and the editing session's currency.
  final bool monetary;

  /// Explicit currency for an amount whose field label is not simply Amount.
  final String? currencyCode;

  /// Currency selector owned by this editing session; code is its fallback.
  final String? currencySourceLabel;
  final AccountingDescriptionRole descriptionRole;
}

class DesignForm {
  const DesignForm(
    this.title,
    this.fields, {
    this.description,
    this.actionLabel,
    this.lines = false,
    this.lineChoiceLabels = const {},
    this.lineDisabledOptions = const {},
    this.lineFields,
    this.counterpartyCurrencies = const {},
    this.counterpartyCustomTerms = const {},
    this.defaultCurrencyCode = 'MYR',
    this.recurring = false,
    this.evidence = false,
  });
  final String title;
  final String? description, actionLabel;
  final List<DesignField> fields;
  final bool lines, recurring, evidence;
  final Map<String, Map<String, String>> lineChoiceLabels;
  final Map<String, Set<String>> lineDisabledOptions;
  final List<String>? lineFields;
  final Map<String, String> counterpartyCurrencies;
  final Map<String, String> counterpartyCustomTerms;
  final String defaultCurrencyCode;

  DesignForm withLineFields(List<String> fields) => DesignForm(
    title,
    this.fields,
    description: description,
    actionLabel: actionLabel,
    lines: lines,
    lineChoiceLabels: lineChoiceLabels,
    lineDisabledOptions: lineDisabledOptions,
    lineFields: fields,
    counterpartyCurrencies: counterpartyCurrencies,
    counterpartyCustomTerms: counterpartyCustomTerms,
    defaultCurrencyCode: defaultCurrencyCode,
    recurring: recurring,
    evidence: evidence,
  );

  String get primaryAction =>
      actionLabel ??
      switch (title) {
        'Customers' => 'Add Customer',
        'Vendors' => 'Add Vendor',
        'Contacts' => 'Add Contact',
        'Products & Services' => 'Add Product Or Service',
        'Invoices' => 'Create Invoice',
        'Quotations' => 'Create Quotation',
        'Credit Notes' => 'Create Credit Note',
        'Sales Receipts' => 'Record Sales Receipt',
        'Refunds' => 'Record Refund',
        'Bills' => 'Record Bill',
        'Supplier Credits' => 'Record Supplier Credit',
        'Purchase Orders' => 'Create Purchase Order',
        'Tax Codes' => 'Add Tax Code',
        'Deadlines' => 'Add Reminder',
        'Pay Bills' => 'Record Bill Payment',
        'Receive Payment' => 'Record Customer Payment',
        'Accounting Review Queue' => 'Review Proposals',
        'For Review' => 'Review Documents',
        'Linked Documents' => 'View Linked Documents',
        'Filing History' => 'View Filing History',
        'Tax Overview' => 'Review Tax Summary',
        'Returns & Payments' => 'Preview Fields',
        _ => 'View $title',
      };
  bool get startsRecord =>
      ['Add ', 'Create ', 'Record '].any(primaryAction.startsWith);
}

const currencies = ['MYR', 'USD', 'SGD', 'EUR', 'GBP', 'AUD', 'JPY'];
const taxFamilies = [
  'Sales Tax',
  'Service Tax',
  'Withholding Tax',
  'Income Tax',
  'Stamp Duty',
  'Other Applicable Tax',
];
const termsChoices = [
  'Due On Receipt',
  'Net 7',
  'Net 14',
  'Net 15',
  'Net 30',
  'Net 60',
  'Net 90',
  'Days After Issue',
  'Day Of Month',
  'Custom',
];
const taxModes = [
  'Exclusive',
  'Inclusive',
  'Out Of Scope',
  'Exempt',
  'Review Needed',
];
const paymentMethods = [
  'Cash',
  'Card',
  'QR Pay',
  'Online Transfer',
  'Bank Transfer',
  'Cheque',
  'Other',
];
const settingsForms = <DesignForm>[
  DesignForm('Business Profile', [
    DesignField('Business Name', required: true),
    DesignField('Legal Name'),
    DesignField(
      'Business Type',
      options: [
        'Sole Proprietor',
        'Partnership',
        'Company',
        'Limited Liability Partnership',
        'Other',
      ],
    ),
    DesignField('Registration Number'),
    DesignField('TIN'),
    DesignField('MSIC Code'),
    ...addressFields,
    DesignField('Email'),
    DesignField('Telephone'),
    DesignField('Website'),
    DesignField('Business Logo'),
  ]),
  DesignForm('Accounting Preferences', [
    DesignField(
      'Financial Year Starts',
      options: [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ],
    ),
    DesignField('Reporting Basis', options: ['Accrual', 'Cash']),
    DesignField(
      'Reporting Framework',
      options: ['MPERS', 'MFRS', 'IFRS', 'Other / Accountant Review'],
    ),
    DesignField('Home Currency', options: currencies),
    DesignField(
      'Date Format',
      options: ['DD-MM-YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD'],
    ),
    DesignField('Close Through Date'),
    DesignField(
      'Closing Policy',
      options: ['Require Owner Approval', 'Prevent Changes'],
    ),
    DesignField('Duplicate Warnings', toggle: true),
  ]),
  DesignForm('Default Accounts', [
    DesignField('Receivables Account'),
    DesignField('Payables Account'),
    DesignField('Income Account'),
    DesignField('Expense Account'),
    DesignField('Sales Tax Liability Account'),
    DesignField('Service Tax Liability Account'),
    DesignField('Discount Account'),
    DesignField('Rounding Account'),
    DesignField('Retained Earnings Account'),
  ]),
  DesignForm('Tax Settings', [
    DesignField('Jurisdiction', options: ['Malaysia', 'Other']),
    DesignField(
      'Registration Status',
      options: [
        'Not Registered',
        'Registered',
        'Registration Pending',
        'Review Needed',
      ],
    ),
    DesignField('Tax Family', options: taxFamilies),
    DesignField('Registration Number'),
    DesignField('Effective From'),
    DesignField(
      'Tax Agency',
      options: ['Kastam / RMCD', 'LHDN / HASiL', 'Other'],
    ),
    DesignField(
      'Filing Frequency',
      options: [
        'Monthly',
        'Every Two Months',
        'Quarterly',
        'Annually',
        'Custom',
      ],
    ),
    DesignField('Taxable Period Starts'),
    DesignField('Tax Basis', options: ['Cash', 'Accrual', 'Policy-Specific']),
    DesignField('Default Tax Mode', options: taxModes),
    DesignField('Require Tax Review', toggle: true),
  ]),
  DesignForm('E-Invoice Profile', [
    DesignField('Environment', options: ['Sandbox', 'Production']),
    DesignField('Business Activity Description', multiline: true),
    DesignField(
      'Submission Mode',
      options: ['Individual', 'Consolidated', 'Self-Billed'],
    ),
    DesignField('Review Before Submit', toggle: true),
  ]),
  DesignForm('Sales Preferences', [
    DesignField('Default Payment Terms', options: termsChoices),
    DesignField('Custom Term Value'),
    DesignField('Show Product / Service', toggle: true),
    DesignField('Show Quantity', toggle: true),
    DesignField('Show Rate', toggle: true),
    DesignField('Enable Discounts', toggle: true),
    DesignField('Show Class', toggle: true),
    DesignField('Default Tax Mode', options: ['Exclusive', 'Inclusive']),
    DesignField(
      'Customer Message',
      multiline: true,
      fullWidth: true,
      customLayout: true,
      descriptionRole: AccountingDescriptionRole.narrative,
    ),
    DesignField('Statement Message', multiline: true),
    DesignField(
      'Apply Customer Credits',
      options: ['Propose For Approval', 'Manual Only'],
    ),
  ]),
  DesignForm('Purchase Preferences', [
    DesignField('Default Bill Terms', options: termsChoices),
    DesignField('Custom Term Value'),
    DesignField('Show Quantity', toggle: true),
    DesignField('Show Rate', toggle: true),
    DesignField('Enable Discounts', toggle: true),
    DesignField('Show Class', toggle: true),
    DesignField('Track Items', toggle: true),
    DesignField('Link To Customer', toggle: true),
    DesignField('Billable Expenses', toggle: true),
    DesignField('Purchase Orders', toggle: true),
    DesignField('Require Bill Reference', toggle: true),
    DesignField(
      'Duplicate Bill Check',
      options: ['Supplier And Reference', 'Supplier, Date And Amount', 'Both'],
    ),
    DesignField(
      'Match Bill Payments',
      options: ['Propose For Approval', 'Manual Only'],
    ),
  ]),
  DesignForm('Numbering & Document Appearance', [
    DesignField(
      'Document Type',
      options: [
        'Invoice',
        'Quotation',
        'Credit Note',
        'Receipt',
        'Bill',
        'Payment Voucher',
        'Claim',
        'Journal',
      ],
    ),
    DesignField('Number Prefix'),
    DesignField('Next Number'),
    DesignField(
      'Number Padding',
      options: ['None', '3 Digits', '4 Digits', '5 Digits', '6 Digits'],
    ),
    DesignField(
      'Reset Sequence',
      options: ['Never', 'Financial Year', 'Calendar Year', 'Monthly'],
    ),
    DesignField('Paper Size', options: ['A4', 'Letter']),
    DesignField('Show Logo', toggle: true),
    DesignField('Show Registration', toggle: true),
    DesignField('Show Tax Breakdown', toggle: true),
    DesignField(
      'Footer',
      multiline: true,
      fullWidth: true,
      customLayout: true,
      descriptionRole: AccountingDescriptionRole.narrative,
    ),
  ]),
  DesignForm('Reminders & Approvals', [
    DesignField(
      'Reminder Type',
      options: [
        'Tax Filing',
        'Tax Payment',
        'Annual Report',
        'Invoice Due',
        'Bill Due',
        'Missing Evidence',
      ],
    ),
    DesignField('Days Before Due Date'),
    DesignField('Visible Reminders', options: ['2', '3', '4']),
    DesignField('Repeat Interval In Days'),
    DesignField('Notify When Overdue', toggle: true),
    DesignField('Delivery', options: ['In App', 'Prepare Email Draft']),
    DesignField(
      'Transaction Approval',
      options: ['Every Transaction', 'Above Threshold', 'Manual Review'],
    ),
    DesignField('Approval Threshold'),
    DesignField('Approver', options: ['Workspace Owner', 'Accountant Review']),
    DesignField('Review Suggestions', toggle: true),
  ]),
  DesignForm('Document & Upload Preferences', [
    DesignField('Scan Documents', toggle: true),
    DesignField('Confirm Extracted Date', toggle: true),
    DesignField('Confirm Category', toggle: true),
    DesignField(
      'Duplicate Detection',
      options: ['Content Hash', 'Reference And Supplier', 'Both'],
    ),
    DesignField(
      'Filename Conflict',
      options: ['Ask Before Filing', 'Add Sequence Suffix'],
    ),
    DesignField(
      'Multiple Attachments',
      options: ['Individual Files', 'Combined PDF Derivative'],
    ),
    DesignField(
      'Print Output',
      options: ['Preserve Original', 'A4 Derivative'],
    ),
    DesignField('Preserve Original Files', toggle: true),
  ]),
  DesignForm('Backup & Export Preferences', [
    DesignField(
      'Backup Frequency',
      options: ['Manual', 'Daily', 'Weekly', 'Monthly'],
    ),
    DesignField('Backup Destination'),
    DesignField('Export Format', options: ['CSV', 'PDF', 'JSON']),
    DesignField(
      'Date Range',
      options: ['All Dates', 'Financial Year', 'Custom'],
    ),
    DesignField('From Date'),
    DesignField('Through Date'),
  ]),
];

const addressFields = [
  DesignField('Address Line 1', minimumRowFraction: 0.5),
  DesignField('Address Line 2', minimumRowFraction: 0.5),
  DesignField('City'),
  DesignField('Postcode'),
  DesignField('Country', options: ['Malaysia', 'Singapore', 'Other Country']),
  DesignField('State / Region'),
  DesignField('Country Name'),
];
const partyFields = [
  DesignField('Name', required: true, minimumRowFraction: 0.5),
  DesignField(
    'Party Type',
    options: ['Business', 'Individual', 'Government', 'Other'],
  ),
  DesignField('Email'),
  DesignField('Telephone'),
  ...addressFields,
  DesignField(
    'Preferred Billing Currency',
    options: ['Use Company Default', ...currencies],
  ),
  DesignField(
    'Payment Terms',
    options: ['Use Company Default', ...termsChoices],
  ),
  DesignField('Tax Details Needed', toggle: true),
  DesignField(
    'Identification Type',
    options: [
      'Business Registration',
      'MyKad',
      'MyTentera',
      'Passport',
      'Other',
    ],
  ),
  DesignField('Identification Number'),
  DesignField('TIN'),
  DesignField('SST Registration Number'),
  DesignField('Notes', multiline: true),
];
const transactionFields = [
  DesignField('Counterparty', required: true),
  DesignField('Document Number'),
  DesignField('Date', required: true),
  DesignField('Due Date'),
  DesignField('Reference'),
  DesignField('Currency', options: ['Use Counterparty Default', ...currencies]),
  DesignField('Payment Terms', options: termsChoices),
  DesignField('Tax Mode', options: taxModes),
  DesignField('Class'),
  DesignField('Location'),
  DesignField(
    'Memo',
    multiline: true,
    descriptionRole: AccountingDescriptionRole.memo,
  ),
];
const settlementFields = [
  DesignField('Counterparty', required: true),
  DesignField('Payment Date', required: true),
  DesignField('Payment Method', options: paymentMethods),
  DesignField('Payment Account'),
  DesignField('Reference'),
  DesignField('Amount', required: true),
  DesignField(
    'How to Match Payment',
    options: [
      'Choose Invoices or Bills',
      'Suggest Oldest First',
      'Leave Payment Unmatched',
    ],
  ),
  DesignField('Invoice or Bill Number'),
  DesignField('Amount Applied to Document'),
  DesignField('Credit To Apply'),
  DesignField('Payment Not Applied'),
  DesignField('Source Document'),
  DesignField(
    'Memo',
    multiline: true,
    descriptionRole: AccountingDescriptionRole.memo,
  ),
];
const reportFields = [
  DesignField(
    'Period',
    options: [
      'This Month',
      'This Quarter',
      'This Financial Year',
      'Last Financial Year',
      'Custom',
    ],
  ),
  DesignField('From Date'),
  DesignField('Through Date'),
  DesignField('Basis', options: ['Use Company Default', 'Accrual', 'Cash']),
  DesignField(
    'Comparison',
    options: ['None', 'Previous Period', 'Previous Year'],
  ),
  DesignField('Columns', options: ['Total', 'Month', 'Quarter', 'Year']),
  DesignField('Show Zero Balances', toggle: true),
  DesignField('Include Subaccounts', toggle: true),
  DesignField('Export', options: ['PDF', 'CSV']),
];
const frontendAreas = <String, List<DesignForm>>{
  'sales-customers': [
    DesignForm(
      'Invoices',
      transactionFields,
      lines: true,
      recurring: true,
      evidence: true,
    ),
    DesignForm('Customers', partyFields),
    DesignForm('Quotations', transactionFields, lines: true, evidence: true),
    DesignForm('Credit Notes', transactionFields, lines: true, evidence: true),
    DesignForm('Receive Payment', settlementFields, evidence: true),
    DesignForm(
      'Sales Receipts',
      [
        DesignField('Counterparty', required: true),
        DesignField('Document Number'),
        DesignField('Date', required: true),
        DesignField('Reference'),
        DesignField(
          'Payment Method',
          options: ['Bank Transfer', 'Cash', 'Cheque', 'Card', 'Other'],
        ),
        DesignField('Payment Account'),
        DesignField(
          'Currency',
          options: ['Use Counterparty Default', ...currencies],
        ),
        DesignField('Tax Mode', options: taxModes),
        DesignField('Class'),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      lines: true,
      evidence: true,
    ),
    DesignForm('Refunds', settlementFields, evidence: true),
    DesignForm('Customer Statements', reportFields),
  ],
  'expenses-vendors': [
    DesignForm(
      'Bills',
      transactionFields,
      lines: true,
      recurring: true,
      evidence: true,
    ),
    DesignForm('Vendors', partyFields),
    DesignForm('Pay Bills', settlementFields, evidence: true),
    DesignForm(
      'Supplier Credits',
      transactionFields,
      lines: true,
      evidence: true,
    ),
    DesignForm(
      'Purchase Orders',
      transactionFields,
      lines: true,
      evidence: true,
    ),
  ],
  'contacts-items': [
    DesignForm('Contacts', [
      DesignField('Role', options: ['Customer', 'Vendor', 'Claimant', 'Other']),
      ...partyFields,
    ]),
    DesignForm('Products & Services', [
      DesignField('Name', required: true),
      DesignField(
        'Type',
        options: ['Service', 'Non-Inventory Item', 'Inventory Item'],
      ),
      DesignField('SKU'),
      DesignField('Description', multiline: true),
      DesignField('Sales Rate'),
      DesignField('Purchase Cost'),
      DesignField('Income Account'),
      DesignField('Expense Account'),
      DesignField('Tax Code'),
      DesignField('E-Invoice Classification'),
      DesignField('Active', toggle: true),
    ]),
  ],
  'taxes': [
    DesignForm('Tax Overview', [
      DesignField('Tax Family', options: taxFamilies),
      DesignField(
        'Period',
        options: ['Current Period', 'Previous Period', 'Custom'],
      ),
      DesignField('Registration Number'),
    ]),
    DesignForm('Tax Codes', [
      DesignField('Code', required: true),
      DesignField('Name', required: true),
      DesignField('Tax Family', options: taxFamilies),
      DesignField(
        'Rate Type',
        options: ['Percentage', 'Fixed Amount', 'Exempt', 'Out Of Scope'],
      ),
      DesignField('Rate / Amount'),
      DesignField('Effective From'),
      DesignField('Effective Through'),
      DesignField('Liability Account'),
      DesignField(
        'Purchase Treatment',
        options: ['Liability', 'Expense', 'Non-Tracking'],
      ),
      DesignField('Return Line'),
      DesignField('Legal Source'),
      DesignField('Notes', multiline: true),
    ]),
    DesignForm(
      'Returns & Payments',
      [
        DesignField('Tax Family', options: taxFamilies),
        DesignField('Period From'),
        DesignField('Period Through'),
        DesignField(
          'Return Status',
          options: ['Draft', 'For Review', 'Submitted', 'Amended'],
        ),
        DesignField('Submission Date'),
        DesignField('Submission Reference'),
        DesignField('Payment Date'),
        DesignField('Payment Reference'),
        DesignField('Amount'),
      ],
      evidence: true,
      description: 'Design preview only. No tax return or payment is recorded, posted, filed or submitted.',
    ),
    DesignForm('Deadlines', [
      DesignField(
        'Obligation',
        options: [
          'SST Return',
          'SST Payment',
          'Income Tax Return',
          'Tax Estimate Instalment',
          'Withholding Tax',
          'SSM Annual Return',
          'Financial Statements',
          'Other',
        ],
      ),
      DesignField(
        'Agency',
        options: ['Kastam / RMCD', 'LHDN / HASiL', 'SSM', 'Other'],
      ),
      DesignField('Trigger Date'),
      DesignField('Due Date'),
      DesignField('Days Before Reminder'),
      DesignField(
        'Status',
        options: [
          'Not Started',
          'Preparing',
          'Submitted',
          'Paid',
          'Not Applicable',
        ],
      ),
      DesignField('Override Reason', multiline: true),
      DesignField('Legal Source'),
    ], evidence: true),
  ],
  'documents': [
    DesignForm('For Review', [
      DesignField(
        'Document Type',
        options: [
          'Expense',
          'Bill',
          'Invoice',
          'Claim',
          'Payment Voucher',
          'Other',
        ],
      ),
      DesignField('Extracted Date'),
      DesignField('Merchant / Supplier'),
      DesignField('Amount'),
      DesignField('Document Reference'),
      DesignField('Category'),
      DesignField('Category Code'),
      DesignField(
        'Match',
        options: [
          'Create New Draft',
          'Link Existing Transaction',
          'Possible Duplicate',
          'Needs Review',
        ],
      ),
      DesignField('Existing Transaction'),
      DesignField('Confirmed Filename'),
      DesignField('Destination Folder'),
    ], evidence: true),
    DesignForm('Linked Documents', [
      DesignField(
        'Transaction Type',
        options: [
          'Expense',
          'Bill',
          'Invoice',
          'Claim',
          'Payment Voucher',
          'Journal',
        ],
      ),
      DesignField('Transaction Reference'),
      DesignField('Document Name'),
      DesignField(
        'Version',
        options: ['Original', 'Edited Derivative', 'Print PDF'],
      ),
      DesignField('Notes', multiline: true),
    ]),
    DesignForm('Filing History', [
      DesignField('Status', options: ['Pending', 'Filed', 'Needs Attention']),
      DesignField('Original Filename'),
      DesignField('Final Filename'),
      DesignField('Destination'),
      DesignField(
        'Conflict Action',
        options: [
          'Keep Existing',
          'Choose Another Name',
          'Add Sequence Suffix',
        ],
      ),
      DesignField('Failure Details', multiline: true),
    ]),
  ],
  'accountant-review': [
    DesignForm(
      'Period Close',
      [
        DesignField('Period From', required: true),
        DesignField('Period Through', required: true),
        DesignField(
          'Bank Reconciliation',
          options: ['Not Reviewed', 'Needs Attention', 'Reviewed'],
        ),
        DesignField(
          'Receivables And Payables',
          options: ['Not Reviewed', 'Needs Attention', 'Reviewed'],
        ),
        DesignField(
          'Missing Documents',
          options: ['Not Reviewed', 'Needs Attention', 'Reviewed'],
        ),
        DesignField(
          'Draft And Unposted Entries',
          options: ['Not Reviewed', 'Needs Attention', 'Reviewed'],
        ),
        DesignField(
          'Tax Reconciliation',
          options: ['Not Reviewed', 'Needs Attention', 'Reviewed'],
        ),
        DesignField(
          'Accruals And Prepayments',
          options: [
            'Not Reviewed',
            'Not Applicable',
            'Needs Attention',
            'Reviewed',
          ],
        ),
        DesignField(
          'Asset Depreciation',
          options: [
            'Not Reviewed',
            'Not Applicable',
            'Needs Attention',
            'Reviewed',
          ],
        ),
        DesignField(
          'Review Conclusion',
          options: ['Keep Open', 'Request Corrections', 'Ready For Approval'],
        ),
        DesignField('Reviewer Note', multiline: true),
      ],
      evidence: true,
      actionLabel: 'Review Period Close',
      description: 'Review completeness and supporting evidence before requesting a period lock. A balanced ledger can still contain omissions.',
    ),
    DesignForm(
      'Fixed Assets',
      [
        DesignField('Asset Name', required: true),
        DesignField('Asset Reference'),
        DesignField('Acquisition Date', required: true),
        DesignField('In Service Date'),
        DesignField('Cost', required: true, monetary: true),
        DesignField('Residual Value', monetary: true),
        DesignField('Useful Life In Months'),
        DesignField(
          'Depreciation Method',
          options: [
            'Straight Line',
            'Reducing Balance',
            'No Depreciation',
            'Accountant Review',
          ],
        ),
        DesignField('Asset Account'),
        DesignField('Accumulated Depreciation Account'),
        DesignField('Depreciation Expense Account'),
        DesignField('Source Document'),
        DesignField('Notes', multiline: true),
      ],
      evidence: true,
      actionLabel: 'Add Asset',
      description: 'Link capital purchases to an asset record and review depreciation policy. Adding the record must not duplicate the original purchase.',
    ),

    DesignForm('Accounting Review Queue', [
      DesignField(
        'Review Type',
        options: [
          'Suggested Transaction',
          'Missing Evidence',
          'Classification Correction',
          'Reconciliation Difference',
        ],
      ),
      DesignField('Source Transaction'),
      DesignField('Transaction Date'),
      DesignField('Reason', multiline: true),
      DesignField('Debit Account'),
      DesignField('Credit Account'),
      DesignField('Amount'),
      DesignField(
        'Decision',
        options: [
          'Pending',
          'Request Information',
          'Approve Proposal',
          'Reject Proposal',
        ],
      ),
      DesignField('Reviewer Note', multiline: true),
    ], evidence: true),
  ],
  'banking': [
    DesignForm(
      'Transfers',
      [
        DesignField('From Account', required: true),
        DesignField('To Account', required: true),
        DesignField('Transfer Date', required: true),
        DesignField('Amount', required: true),
        DesignField('Bank Reference'),
        DesignField('Linked Transaction'),
        DesignField(
          'Make Recurring',
          options: ['No', 'Scheduled', 'Reminder', 'Unscheduled'],
        ),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      evidence: true,
      actionLabel: 'Record Transfer',
      description: 'Record money moved between your own accounts through your bank. Match both statement entries to one transfer.',
    ),
    DesignForm(
      'Deposits',
      [
        DesignField('Deposit Account', required: true),
        DesignField('Deposit Date', required: true),
        DesignField(
          'Deposit Source',
          options: [
            'Existing Customer Payment',
            'Cash On Hand',
            'Cheque Received',
            'Other Receipt',
          ],
        ),
        DesignField('Linked Receipt Or Payment'),
        DesignField('Bank Reference'),
        DesignField(
          'Tax Mode',
          options: ['Exclusive', 'Inclusive', 'Out Of Scope'],
        ),
        DesignField(
          'Make Recurring',
          options: ['No', 'Scheduled', 'Reminder', 'Unscheduled'],
        ),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      lines: true,
      lineFields: [
        'Received From',
        'Account',
        'Description',
        'Payment Method',
        'Reference',
        'Amount',
        'Tax Rate (%)',
      ],
      evidence: true,
      actionLabel: 'Record Deposit',
      description: 'Record a deposit made outside Audyt and link its existing receipts. Attach the deposit slip or bank confirmation.',
    ),
    DesignForm(
      'Credit Card Payments',
      [
        DesignField('Credit Card Account', required: true),
        DesignField('Payee', choiceLabels: {}),
        DesignField('Payment Date', required: true),
        DesignField('Funding Bank Account', required: true),
        // Retain amount typography/alignment; ordinary tracks own its width.
        DesignField('Amount', required: true, customLayout: true),
        DesignField('Paid By Cheque', checkbox: true, fullWidth: true),
        DesignField('Cheque Number'),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      evidence: true,
      actionLabel: 'Record Card Payment',
      description: 'Review a payment from a bank account to a credit card. Recording this payment is not connected yet.',
    ),
    DesignForm(
      'Credit Card Credits',
      [
        DesignField('Credit Card Account', required: true),
        DesignField('Payee', choiceLabels: {}),
        DesignField('Payment Date', required: true),
        DesignField('Reference'),
        DesignField('Permit Number'),
        DesignField(
          'Tax Mode',
          options: ['Exclusive', 'Inclusive', 'Out Of Scope'],
        ),
        DesignField(
          'Make Recurring',
          options: ['No', 'Scheduled', 'Reminder', 'Unscheduled'],
        ),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      lines: true,
      lineFields: ['Account', 'Description', 'Amount', 'Tax Rate (%)'],
      evidence: true,
      actionLabel: 'Record Card Credit',
      description: 'Review a credit returned to a credit card. Recording this credit is not connected yet.',
    ),
    DesignForm(
      'Cheques',
      [
        DesignField(
          'Direction',
          options: ['Issued', 'Received'],
          required: true,
        ),
        DesignField('Bank Account', required: true),
        DesignField('Cheque Number', required: true),
        DesignField('Cheque Date', required: true),
        DesignField('Payee Or Payer', required: true),
        DesignField('Amount', required: true),
        DesignField('Linked Payment Or Receipt'),
        DesignField(
          'Cheque Status',
          options: [
            'Draft',
            'Issued',
            'Received',
            'Deposited',
            'Cleared',
            'Returned',
            'Voided',
            'Stop Requested',
            'Stop Confirmed',
          ],
        ),
        DesignField('Cleared Date'),
        DesignField('Bank Reference'),
        DesignField(
          'Memo',
          multiline: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
      evidence: true,
      actionLabel: 'Record Cheque',
      description: 'Track physical cheques and link their payments. A cheque copy records the instrument; bank evidence confirms clearance. Issue, deposit or stop a cheque through your bank.',
    ),
  ],
  'reports': [
    DesignForm('Cash Flow', reportFields),
    DesignForm('Changes In Equity', reportFields),
    DesignForm('Receivables Ageing', reportFields),
    DesignForm('Payables Ageing', reportFields),
    DesignForm('Tax Reconciliation', reportFields),
    DesignForm('Management Report Pack', reportFields),
  ],
};
