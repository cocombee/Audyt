import 'field_row_trial.dart';
import 'field_guidance.dart';
import '../features/purchases/domain/bill_tax_selection.dart';
import '../features/accounting/domain/company_tax_rate.dart';
import 'accounting_description_field.dart';

import 'naming_setup.dart' show SetupKind, openAccountingSettings;
import 'live_settings_catalog.dart';
import 'sidebar_settings_icon.dart';
import 'accounting_icons.dart';
import 'transaction_form_layout.dart';

import 'dart:async';

import '../features/accounting/presentation/receipt_review_dialog.dart';
import '../features/accounting/presentation/receipt_review_queue.dart';

import 'dart:math' as math;
import 'dart:convert';

import 'profile_photo_editor.dart';

import '../core/ids/entity_id.dart';
import '../core/dates/accounting_date.dart';
import '../core/documents/receipt_document.dart';
import '../features/accounting/presentation/attachment_preview_dialog.dart';
import 'asset_purchase_fields.dart';
import 'linked_record_review.dart';
import 'demo_company.dart';
import '../core/money/currency_presentation.dart';
import '../core/money/currency.dart';
import '../core/money/money.dart';
import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/domain/account.dart';
import '../features/accounting/presentation/chart_of_accounts_page.dart'
    show showLedgerAccountDialog;
import '../features/accounting/domain/payment_account.dart';
import '../features/accounting/domain/payee.dart';
import '../features/accounting/presentation/record_expense_page.dart'
    show showAccountingPayeeDialog;
import '../features/accounting/presentation/customer_page.dart'
    show showAccountingCustomerDialog;
import '../features/accounting/domain/ledger_report.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/accounting/domain/recurrence_rule.dart';
import '../features/accounting/domain/recurring_document_template.dart';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'frontend_catalog.dart';
import 'responsive.dart';
import '../features/accounting/presentation/widgets/accounting_layout.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';
import '../features/sales/domain/invoice_tax.dart';
import '../features/sales/domain/sales_line_item.dart';
import '../features/sales/product_catalogue_page.dart';

export 'frontend_catalog.dart';

/// Existing payment-method setup surface, shared by its selector callers.
/// The durable directory command remains explicitly pending.
Future<void> showAccountingPaymentMethodPreview(
  BuildContext context, {
  bool directory = false,
  String? initialName,
  bool cardPayment = false,
}) async {
  final cardLabel = directory
      ? 'This Is A Credit Or Debit Card'
      : 'This Is A Credit Card';
  await AccountingDialog.showFixed<Map<String, Object?>>(
    context: context,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    builder: (_) => FrontendFormDialog(
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      previewConfirmationEnabled: false,
      initial: {'Name': initialName ?? '', cardLabel: cardPayment},
      leadingContentBuilder: (context, values, reviewing) => Padding(
        padding: const EdgeInsets.only(bottom: accountingContentInset),
        child: accountingHelperText(
          context,
          'Saving payment methods is not connected yet.',
        ),
      ),
      form: DesignForm(
        initialName == null ? 'New Payment Method' : 'Edit Payment Method',
        [
          const DesignField('Name', required: true),
          DesignField(cardLabel, checkbox: true),
        ],
        description: 'Payment method setup preview. Saving payment methods is not connected yet.',
        actionLabel: 'Save Payment Method',
      ),
    ),
  );
}

bool _salesDocumentTaxFamily(DesignForm form) =>
    form.lines && const {'Invoices', 'Quotations'}.contains(form.title);

List<String> _transactionGridFields(DesignForm form) =>
    const {'Deposits', 'Credit Card Credits'}.contains(form.title)
    ? form.lineFields!
    : [
        form.lineChoiceLabels.containsKey('Product / Service')
            ? 'Product / Service'
            : 'Account',
        'Description',
        if (form.lineFields!.contains('Quantity')) 'Quantity',
        if (form.lineFields!.contains('Rate')) 'Rate',
        if (form.lineFields!.contains('Discount')) 'Discount',
        if (!_salesDocumentTaxFamily(form)) 'Tax Rate (%)',
        'Amount',
      ];

String _transactionColumnTitle(String field, String currency) =>
    switch (field) {
      'Account' => 'Category',
      'Tax Rate (%)' => 'Tax',
      'Quantity' => 'Qty',
      'Amount' || 'Rate' || 'Discount' =>
        '$field (${CurrencyPresentation.fromCode(currency).amountSymbol})',
      _ => field,
    };

// These frontend transaction inputs reserve the default editable caret and
// its gap within the content floor. Quantity and other numeric owners retain
// their existing sizing; a title/helper floor is still independent of padding.
double _frontendTransactionNumericWidth(
  BuildContext context,
  String field,
  Iterable<String> values, {
  String? minimumText,
  required String title,
}) => math.max(
  AccountingTransactionGridTokens.numericWidth(
        context,
        field,
        values,
        minimumText: minimumText,
      ) +
      (field == 'Quantity' ? 0 : const TextField().cursorWidth + 1),
  AccountingTransactionGridTokens.fieldTitleWidth(context, title),
);

Map<String, double> _transactionColumnWidths(
  BuildContext context,
  DesignForm form,
  List<Map<String, String>> lines,
  String currency, {
  bool reservePopout = false,
  bool compactSelections = true,
}) {
  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final digits = Currency.parse(currency).fractionDigits;
  String displayed(Map<String, String> line, String field) {
    if (field == 'Amount' && form.lineFields!.contains('Rate')) {
      if (line['_manualAmount'] != null) return line['_manualAmount']!;
      try {
        return formatAccountingMoneyInputText(
          formatAccountingInputAmount(
            SalesQuantity.fromDecimal(line['Quantity'] ?? '1')
                .multiply(Money.fromDecimal(line['Rate'] ?? '', currency)),
          ),
          digits,
        );
      } on Object {
        return '';
      }
    }
    return field == 'Quantity'
        ? line[field] ?? ''
        : formatAccountingMoneyInputText(line[field] ?? '', digits);
  }

  double numericWidth(String field) {
    // A fixed popout still reserves its established optional-column width.
    // The actual controls give unused space to Description, then grow with ink.
    final seed = reservePopout || field == 'Discount'
        ? switch (field) {
            'Quantity' => '9999',
            'Rate' => '999,999.99',
            _ => '9,999,999.99',
          }
        : AccountingTransactionGridTokens.initialNumericText[field]!;
    return _frontendTransactionNumericWidth(
      context,
      field,
      [
        if (field != 'Quantity')
          formatAccountingMoneyInputText(
            formatAccountingInputAmount(Money.zero(currency)),
            digits,
          ),
        ...lines.map((line) => displayed(line, field)),
      ],
      minimumText: seed,
      title: _transactionColumnTitle(field, currency),
    );
  }

  double selectorWidth(String field) =>
      AccountingTransactionGridTokens.selectionWidth(
        context,
        field == 'Tax Rate (%)'
            ? 'Select Tax'
            : field == 'Account'
            ? 'Select Category'
            : 'Select Item',
        title: _transactionColumnTitle(field, currency),
        selectedLabels: reservePopout || !compactSelections
            ? null
            : lines.map(
                (line) =>
                    form.lineChoiceLabels[field]?[line[field]] ?? line[field],
              ),
      );

  if (const {'Deposits', 'Credit Card Credits'}.contains(form.title)) {
    return {
      for (final field in _transactionGridFields(form))
        field: field == 'Description'
            ? AccountingTransactionGridTokens.descriptionMinimumWidth
            : field == 'Amount'
            ? numericWidth(field)
            : form.lineChoiceLabels.containsKey(field)
            ? AccountingTransactionGridTokens.selectionWidth(
                context,
                field == 'Tax Rate (%)' ? 'Select Tax' : 'Select $field',
                title: field == 'Account'
                    ? 'Account'
                    : _transactionColumnTitle(field, currency),
                selectedLabels: reservePopout
                    ? null
                    : lines.map(
                        (line) =>
                            form.lineChoiceLabels[field]?[line[field]] ??
                            line[field],
                      ),
              )
            : math.max(
                AccountingTransactionGridTokens.fieldTitleWidth(context, field),
                measure(field, AccountingTypography.controlValue(context)) +
                    accountingContentInset * 2,
              ),
    };
  }
  return {
    for (final field in _transactionGridFields(form))
      field: field == 'Description'
          ? AccountingTransactionGridTokens.descriptionMinimumWidth
          : math.max(
              (!reservePopout ||
                          const {
                            'Product / Service',
                            'Account',
                            'Tax Rate (%)',
                          }.contains(field)) &&
                      const {
                        'Quantity',
                        'Rate',
                        'Amount',
                        'Product / Service',
                        'Account',
                        'Tax Rate (%)',
                      }.contains(field)
                  ? 0
                  : measure(
                      _transactionColumnTitle(field, currency),
                      AccountingTypography.fieldLabel(context),
                    ),
              field == 'Product / Service' ||
                      field == 'Account' ||
                      field == 'Tax Rate (%)'
                  ? selectorWidth(field)
                  : numericWidth(field),
            ),
  };
}

/// The content contract is measured before acquiring the desktop width owner.
/// Ordinary transaction rows retain 728px; optional/long controls grow the popout.
double frontendTransactionContentWidth(
  BuildContext context,
  DesignForm form, {
  List<Map<String, String>> lines = const [],
}) {
  if (!form.lineChoiceLabels.containsKey('Product / Service') &&
      !form.lineChoiceLabels.containsKey('Account')) {
    return 728;
  }
  final columns = _transactionColumnWidths(
    context,
    form,
    lines,
    form.defaultCurrencyCode,
    reservePopout: true,
  );
  final optional = columns.entries
      .where((e) => const {'Quantity', 'Rate', 'Discount'}.contains(e.key))
      .toList();
  final baseline = optional.isEmpty
      ? 728.0
      : frontendTransactionContentWidth(
              context,
              form.withLineFields(
                form.lineFields!
                    .where(
                      (f) =>
                          !const {'Quantity', 'Rate', 'Discount'}.contains(f),
                    )
                    .toList(),
              ),
              lines: lines,
            ) +
            optional.fold<double>(
              0,
              (sum, e) =>
                  sum + e.value + AccountingTransactionGridTokens.peerGap,
            );
  final numberWidth = (TextPainter(
    text: TextSpan(
      text: '${math.max(1, lines.length)}',
      style: AccountingTypography.controlValue(context),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout()).width;
  return math
      .max(
        baseline,
        columns.values.reduce((a, b) => a + b) +
            (columns.length - 1) * AccountingTransactionGridTokens.peerGap +
            numberWidth +
            accountingContentInset * 2 +
            20,
      )
      .ceilToDouble();
}

Future<Map<String, Object?>?> openFrontendForm(
  BuildContext context,
  DesignForm form, {
  Map<String, Object?>? initial,
  List<String> accountOptions = const [],
  AccountingWorkspace? settingsWorkspace,
  Future<List<Payee>> Function(String)? employeePayeeSearch,
}) {
  if (const [
    'Refunds',
    'Credit Notes',
    'Receive Payment',
    'Pay Bills',
  ].contains(form.title)) {
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => LinkedRecordReview(workflow: form.title),
    );
  }
  return _openFrontendPreviewForm(
    context,
    form,
    initial: initial,
    accountOptions: accountOptions,
    settingsWorkspace: settingsWorkspace,
    employeePayeeSearch: employeePayeeSearch,
  );
}

Future<Map<String, Object?>?> _openFrontendPreviewForm(
  BuildContext context,
  DesignForm form, {
  Map<String, Object?>? initial,
  List<String> accountOptions = const [],
  AccountingWorkspace? settingsWorkspace,
  Future<List<Payee>> Function(String)? employeePayeeSearch,
}) async {
  final salesReceipt =
      form.title == 'Sales Receipts' && settingsWorkspace != null;
  final transfer = form.title == 'Transfers' && settingsWorkspace != null;
  final deposit = form.title == 'Deposits' && settingsWorkspace != null;
  final cheque = form.title == 'Cheques' && settingsWorkspace != null;
  final cardPayment =
      form.title == 'Credit Card Payments' && settingsWorkspace != null;
  final cardCredit =
      form.title == 'Credit Card Credits' && settingsWorkspace != null;
  final banking = transfer || deposit || cheque || cardPayment || cardCredit;
  final registeredPayees = <String, Payee>{};
  var payeeSearchRevision = 0;
  var transferAccounts = banking
      ? (await settingsWorkspace.accounts())
            .map((record) => record.account)
            .toList()
      : const <Account>[];
  final transferBalances = <String, Money>{};
  if (banking) {
    try {
      final report = await settingsWorkspace.report(
        from: DateTime.utc(1),
        through: DateTime.now(),
      );
      for (final row in report.rows) {
        final creditNormal = const {
          AccountType.liability,
          AccountType.equity,
        }.contains(row.account.type);
        final units = creditNormal ? -row.endingNetDebit : row.endingNetDebit;
        // Keep aggregate overflow unavailable instead of inventing a balance.
        if (BigInt.from(units.toInt()) == units) {
          transferBalances[row.account.id.value] = Money.fromMinor(
            units.toInt(),
            report.currency,
          );
        }
      }
    } on Object {
      // An unavailable report is not a zero balance.
    }
  }
  final depositLedgerAccounts = salesReceipt
      ? (await settingsWorkspace.accounts())
            .map((record) => record.account)
            .toList()
      : const <Account>[];
  if (!context.mounted) return null;
  DesignForm currentForm() => salesReceipt
      ? _catalogueSalesReceiptForm(
          form,
          settingsWorkspace,
          initial: initial,
          accountOptions: accountOptions,
          depositLedgerAccounts: depositLedgerAccounts,
        )
      : transfer
      ? _catalogueBalanceAccountForm(
          form,
          transferAccounts,
          settingsWorkspace.identity.currency,
          initial,
        )
      : cardPayment
      ? _catalogueCardPaymentForm(
          form,
          transferAccounts,
          settingsWorkspace,
          initial,
        )
      : cardCredit
      ? _catalogueCardCreditForm(
          form,
          transferAccounts,
          settingsWorkspace,
          initial,
          registeredPayees: registeredPayees.values,
        )
      : cheque
      ? _catalogueBalanceAccountForm(
          form,
          transferAccounts,
          settingsWorkspace.identity.currency,
          initial,
          selectorFields: const {'Bank Account'},
          eligible: (account) => _depositAccountEligible(
            account,
            settingsWorkspace,
            'Deposit Account',
          ),
        )
      : deposit
      ? _catalogueDepositForm(
          form,
          transferAccounts,
          settingsWorkspace,
          initial,
        )
      : form;
  final initialValues = {
    if (banking) 'Currency': settingsWorkspace.identity.currency,
    if (cardPayment) ...{
      'Payment Date': formatAccountingInputDate(DateTime.now()),
      'Paid By Cheque': false,
    },
    if (cardCredit) 'Payment Date': formatAccountingInputDate(DateTime.now()),
    if (transfer || deposit || cardCredit) ...{
      if (!cardCredit)
        transfer ? 'Transfer Date' : 'Deposit Date': formatAccountingInputDate(
          DateTime.now(),
        ),
      'Make Recurring': 'No',
      'Interval': 'Monthly',
      'Every': '1',
      'Week Of Month': 'Day',
      'Day Of Month': '1',
      'Day Of Week': 'Monday',
      'Month Of Year': 'January',
      'End': 'None',
      if (deposit || cardCredit) 'Tax Mode': 'Exclusive',
    },
    if (form.title == 'Fixed Assets' && settingsWorkspace != null)
      'Currency': settingsWorkspace.identity.currency,
    if (salesReceipt && initial?['_lines'] == null) ...{
      'Tax Mode': settingsWorkspace.preferences.text(
        'Sales Preferences',
        'Default Tax Mode',
      ),
      'Currency': 'Use Counterparty Default',
      'Receipt Message': settingsWorkspace.preferences.text(
        'Sales Preferences',
        'Customer Message',
      ),
    },
    ...?initial,
    if ((deposit || cardCredit) &&
        initial != null &&
        !initial.containsKey('Tax Mode'))
      'Tax Mode': '',
    if (deposit &&
        initial?['_lines'] == null &&
        '${initial?['Amount'] ?? ''}'.isNotEmpty)
      '_lines': [
        {'Amount': '${initial!['Amount']}', 'Tax Rate (%)': ''},
      ],
    if (salesReceipt &&
        initial != null &&
        !initial.containsKey('Receipt Message') &&
        initial.containsKey('Memo'))
      'Receipt Message': initial['Memo'],
  };
  final openingWidth = form.lines
      ? frontendTransactionContentWidth(
          context,
          currentForm(),
          lines: [
            for (final line in initial?['_lines'] as List? ?? const [])
              Map<String, String>.from(line as Map),
          ],
        )
      : null;
  Widget builder(BuildContext _) => FrontendFormDialog(
    widthFamily: form.title == 'Fixed Assets'
        ? AccountingPopoutWidthFamily.wider
        : AccountingPopoutWidthFamily.normal,
    form: currentForm(),
    formBuilder: salesReceipt || banking ? currentForm : null,
    accountBalances: transferBalances,
    onSearchPayees: cardCredit && employeePayeeSearch != null
        ? (query) async {
            final revision = ++payeeSearchRevision;
            final matches = await employeePayeeSearch(query);
            if (revision != payeeSearchRevision) return;
            for (final employee in matches) {
              if (employee.type == PayeeType.staff) {
                registeredPayees[employee.id] = employee;
              }
            }
          }
        : null,
    valuesFormBuilder: cardPayment
        ? (values) {
            final base = currentForm();
            return DesignForm(
              base.title,
              [
                for (final field in base.fields)
                  if ((field.label != 'Paid By Cheque' ||
                          '${values['Funding Bank Account'] ?? ''}'
                              .isNotEmpty) &&
                      (field.label != 'Cheque Number' ||
                          ('${values['Funding Bank Account'] ?? ''}'
                                  .isNotEmpty &&
                              values['Paid By Cheque'] == true)))
                    field,
              ],
              description: base.description,
              actionLabel: base.actionLabel,
              evidence: base.evidence,
              defaultCurrencyCode: base.defaultCurrencyCode,
            );
          }
        : null,
    onAddPayee: cardPayment || cardCredit
        ? () async {
            final result = await showAccountingPayeeDialog(
              context,
              newId: () => 'payee-${DateTime.now().microsecondsSinceEpoch}',
              onAddCustomer: cardCredit
                  ? (initialName) async {
                      final customer = await showAccountingCustomerDialog(
                        context,
                        settingsWorkspace,
                        initialName: initialName,
                      );
                      return customer?.id.value;
                    }
                  : null,
            );
            if (result == null || !context.mounted) return null;
            if (result.customerId != null) {
              return 'customer:${result.customerId}';
            }
            final payee = result.payee!;
            try {
              settingsWorkspace.payees.save(payee);
            } on Object {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Payee could not be saved. Check storage and try again.',
                    ),
                  ),
                );
              }
              return null;
            }
            return payee.id;
          }
        : null,
    onAddAccount: banking
        ? (field) async {
            final records = await settingsWorkspace.accounts();
            if (!context.mounted) return null;
            final id = await showLedgerAccountDialog(
              context,
              settingsWorkspace,
              records,
              allowedReportingTypes:
                  cardCredit && field == 'Credit Card Account'
                  ? const {ReportingAccountType.creditCard}
                  : cardPayment
                  ? {
                      field == 'Credit Card Account'
                          ? ReportingAccountType.creditCard
                          : ReportingAccountType.cashAndCashEquivalents,
                    }
                  : transfer
                  ? _transferReportingTypes
                  : cheque || field == 'Deposit Account'
                  ? const {ReportingAccountType.cashAndCashEquivalents}
                  : field == 'Cash Back Account'
                  ? _cashBackReportingTypes
                  : null,
            );
            if (id == null || !context.mounted) return null;
            transferAccounts = (await settingsWorkspace.accounts())
                .map((record) => record.account)
                .toList();
            return transferAccounts.any(
                  (account) =>
                      account.id == id &&
                      (cardCredit
                          ? (field == 'Credit Card Account'
                                ? _cardPaymentAccountEligible(
                                    account,
                                    settingsWorkspace,
                                  )
                                : account.status == AccountStatus.active &&
                                      !account.isParent)
                          : cardPayment
                          ? (field == 'Credit Card Account'
                                ? _cardPaymentAccountEligible(
                                    account,
                                    settingsWorkspace,
                                  )
                                : _depositAccountEligible(
                                    account,
                                    settingsWorkspace,
                                    'Deposit Account',
                                  ))
                          : transfer
                          ? _transferAccountEligible(account)
                          : _depositAccountEligible(
                              account,
                              settingsWorkspace,
                              cheque ? 'Deposit Account' : field,
                            )),
                )
                ? id.value
                : null;
          }
        : null,
    initial: initialValues,
    contentWidth: openingWidth,
    lineDefaults: salesReceipt
        ? const {'Quantity': '1'}
        : deposit || cardCredit
        ? const {'Tax Rate (%)': '0'}
        : const {},
    accountOptions: accountOptions,
    settingsWorkspace: settingsWorkspace,
  );
  if (!form.lines) {
    return showDialog<Map<String, Object?>>(context: context, builder: builder);
  }
  return AccountingDialog.showFixed<Map<String, Object?>>(
    context: context,
    contentWidth: openingWidth!,
    builder: builder,
  );
}

/// Configure the existing catalogue owner from maintained company data. This
/// remains a preview; selector identity is not a receipt-posting command.
DesignForm _catalogueSalesReceiptForm(
  DesignForm original,
  AccountingWorkspace workspace, {
  Map<String, Object?>? initial,
  List<String> accountOptions = const [],
  List<Account> depositLedgerAccounts = const [],
}) {
  final savedLines = [
    for (final line in initial?['_lines'] as List? ?? const [])
      Map<String, String>.from(line as Map),
  ];
  final preferences = workspace.preferences;
  final savedCustomer = '${initial?['Counterparty'] ?? ''}';
  final customerChoices = {
    for (final customer in workspace.customers())
      if (customer.isActive || customer.id.value == savedCustomer)
        customer.id.value:
            '${customer.displayName}${customer.isActive ? '' : ' · Inactive'}',
  };
  final unavailableCustomers = {
    for (final customer in workspace.customers())
      if (!customer.isActive) customer.id.value,
    if (savedCustomer.isNotEmpty && !customerChoices.containsKey(savedCustomer))
      savedCustomer,
  };
  if (savedCustomer.isNotEmpty && !customerChoices.containsKey(savedCustomer)) {
    customerChoices[savedCustomer] = '$savedCustomer · Retained';
  }
  final deposits = {
    for (final account in workspace.paymentAccounts)
      if (account.type != PaymentAccountType.card)
        account.id: account.displayLabel,
  };
  final savedDeposit = '${initial?['Payment Account'] ?? ''}';
  final eligibleLedgerIds = {
    for (final account in depositLedgerAccounts)
      if (account.type == AccountType.asset &&
          account.status == AccountStatus.active &&
          !account.isParent)
        account.id,
  };
  final unavailableDeposits = {
    for (final payment in workspace.paymentAccounts)
      if (!eligibleLedgerIds.contains(
        workspace.database.paymentLedgerAccount(
          workspace.identity.businessId,
          payment.id,
        ),
      ))
        payment.id,
  };
  if (savedDeposit.isNotEmpty && !deposits.containsKey(savedDeposit)) {
    deposits[savedDeposit] = '$savedDeposit · Retained';
    unavailableDeposits.add(savedDeposit);
  }
  // Do not convert an older account-based draft into an item-based receipt.
  final catalogue =
      savedLines.isEmpty ||
      savedLines.any((line) => (line['Product / Service'] ?? '').isNotEmpty) ||
      savedLines.every((line) => (line['Account'] ?? '').isEmpty);
  final quantity =
      preferences.enabled('Sales Preferences', 'Show Quantity') ||
      savedLines.any(
        (line) =>
            (line['Quantity'] ?? '').isNotEmpty && line['Quantity'] != '1',
      );
  final rate =
      preferences.enabled('Sales Preferences', 'Show Rate') ||
      savedLines.any((line) => (line['Rate'] ?? '').isNotEmpty);
  return DesignForm(
    original.title,
    [
      for (final field in original.fields)
        if (field.label == 'Counterparty')
          DesignField(
            field.label,
            required: field.required,
            choiceLabels: customerChoices,
            disabledOptions: unavailableCustomers,
          )
        else if (field.label == 'Document Number') ...[
          const DesignField('Email'),
          const DesignField('Send Later', toggle: true),
          const DesignField(
            'Billing Address',
            multiline: true,
            fullWidth: true,
          ),
          field,
        ] else if (field.label == 'Memo') ...[
          const DesignField(
            'Receipt Message',
            multiline: true,
            fullWidth: true,
            descriptionRole: AccountingDescriptionRole.memo,
          ),
          const DesignField(
            'Statement Message',
            multiline: true,
            fullWidth: true,
          ),
        ] else if (field.label == 'Payment Account')
          DesignField(
            field.label,
            required: field.required,
            choiceLabels: deposits,
            disabledOptions: unavailableDeposits,
          )
        else
          field,
    ],
    description: original.description,
    actionLabel: original.actionLabel,
    lines: original.lines,
    lineFields: [
      catalogue ? 'Product / Service' : 'Account',
      'Description',
      if (quantity || rate) 'Quantity',
      rate ? 'Rate' : 'Amount',
      if (savedLines.any((line) => (line['Discount'] ?? '').isNotEmpty))
        'Discount',
      'Tax Rate (%)',
    ],
    lineChoiceLabels: {
      if (catalogue)
        'Product / Service': {
          for (final item in workspace.catalogueItems)
            if (item.active ||
                savedLines.any(
                  (line) => line['Product / Service'] == item.id.value,
                ))
              item.id.value: '${item.name}${item.active ? '' : ' · Inactive'}',
          for (final line in savedLines)
            if ((line['Product / Service'] ?? '').isNotEmpty &&
                !workspace.catalogueItems.any(
                  (item) => item.id.value == line['Product / Service'],
                ))
              line['Product / Service']!:
                  '${line['_salesReceiptItemName'] ?? line['Product / Service']} · Retained',
        }
      else
        'Account': {
          for (final account in accountOptions) account: account,
          for (final line in savedLines)
            if ((line['Account'] ?? '').isNotEmpty)
              line['Account']!: line['Account']!,
        },
      'Tax Rate (%)': {
        '0': 'No Tax',
        for (final code in workspace.taxRates) code.choice: code.label,
        for (final line in savedLines)
          if ((line['Tax Rate (%)'] ?? '').isNotEmpty &&
              line['_salesReceiptTaxChoice'] == line['Tax Rate (%)'] &&
              line['_salesReceiptTaxLabel'] != null)
            line['Tax Rate (%)']!: line['_salesReceiptTaxLabel']!,
      },
    },
    counterpartyCurrencies: {
      for (final customer in workspace.customers())
        customer.id.value: customer.currency.code,
    },
    defaultCurrencyCode: workspace.identity.currency,
    recurring: original.recurring,
    evidence: original.evidence,
  );
}

// The working Transfer selector offers balance-sheet classifications. Keep
// identity and retained choices; receipt posting and recurring templates remain
// separate commands from this existing session-preview owner.
const _transferReportingTypes = {
  ReportingAccountType.cashAndCashEquivalents,
  ReportingAccountType.currentAssets,
  ReportingAccountType.propertyPlantAndEquipment,
  ReportingAccountType.nonCurrentAssets,
  ReportingAccountType.creditCard,
  ReportingAccountType.currentLiabilities,
  ReportingAccountType.nonCurrentLiabilities,
  ReportingAccountType.ownersEquity,
};

bool _transferAccountEligible(Account account) =>
    !account.isParent &&
    account.status == AccountStatus.active &&
    const {
      AccountType.asset,
      AccountType.liability,
      AccountType.equity,
    }.contains(account.type) &&
    !const {
      ReportingAccountType.tradeAndOtherReceivables,
      ReportingAccountType.tradeAndOtherPayables,
    }.contains(account.profile?.reportingType);

DesignForm _catalogueBalanceAccountForm(
  DesignForm original,
  List<Account> accounts,
  String currency,
  Map<String, Object?>? initial, {
  Set<String> selectorFields = const {'From Account', 'To Account'},
  bool Function(Account)? eligible,
}) {
  final choices = {
    for (final account in accounts)
      if ((eligible ?? _transferAccountEligible)(account))
        account.id.value: account.name,
  };
  final unavailable = <String>{};
  for (final key in selectorFields) {
    final retained = '${initial?[key] ?? ''}';
    if (retained.isNotEmpty && !choices.containsKey(retained)) {
      choices[retained] =
          '${accounts.where((a) => a.id.value == retained).firstOrNull?.name ?? retained} · Retained';
      unavailable.add(retained);
    }
  }
  return DesignForm(
    original.title,
    [
      for (final field in original.fields)
        if (selectorFields.contains(field.label))
          DesignField(
            field.label,
            required: field.required,
            choiceLabels: choices,
            disabledOptions: unavailable,
          )
        else
          field,
    ],
    description: original.description,
    actionLabel: original.actionLabel,
    evidence: original.evidence,
    lines: original.lines,
    lineFields: original.lineFields,
    lineChoiceLabels: original.lineChoiceLabels,
    lineDisabledOptions: original.lineDisabledOptions,
    recurring: original.recurring,
    counterpartyCurrencies: original.counterpartyCurrencies,
    counterpartyCustomTerms: original.counterpartyCustomTerms,
    defaultCurrencyCode: currency,
  );
}

bool _cardPaymentAccountEligible(
  Account account,
  AccountingWorkspace workspace,
) {
  if (account.isParent || account.status != AccountStatus.active) return false;
  if (account.profile?.reportingType == ReportingAccountType.creditCard) {
    return true;
  }
  return workspace.paymentAccounts.any(
    (payment) =>
        payment.type == PaymentAccountType.card &&
        account.type == AccountType.liability &&
        payment.currency.code == workspace.identity.currency &&
        workspace.database.paymentLedgerAccount(
              workspace.identity.businessId,
              payment.id,
            ) ==
            account.id,
  );
}

DesignForm _catalogueCardPaymentForm(
  DesignForm original,
  List<Account> accounts,
  AccountingWorkspace workspace,
  Map<String, Object?>? initial, {
  Iterable<Payee> registeredPayees = const [],
  bool includeCustomerEmployees = false,
}) {
  final cards = _catalogueBalanceAccountForm(
    original,
    accounts,
    workspace.identity.currency,
    initial,
    selectorFields: const {'Credit Card Account'},
    eligible: (account) => _cardPaymentAccountEligible(account, workspace),
  );
  final banks = _catalogueBalanceAccountForm(
    cards,
    accounts,
    workspace.identity.currency,
    initial,
    selectorFields: const {'Funding Bank Account'},
    eligible: (account) =>
        _depositAccountEligible(account, workspace, 'Deposit Account'),
  );
  final parties = {
    for (final customer in workspace.customers())
      if (includeCustomerEmployees && customer.isActive)
        'customer:${customer.id.value}': '${customer.displayName} · Customer',
    for (final payee in workspace.payees.all)
      if (!includeCustomerEmployees || payee.type != PayeeType.staff)
        payee.id: '${payee.name} · ${payee.typeLabel}',
    for (final employee in registeredPayees)
      employee.id: '${employee.name} · ${employee.typeLabel}',
  };
  final retained = '${initial?['Payee'] ?? ''}';
  final unavailable = retained.isNotEmpty && !parties.containsKey(retained);
  if (unavailable) parties[retained] = '$retained · Retained';
  return DesignForm(
    original.title,
    [
      for (final field in banks.fields)
        if (field.label == 'Payee')
          DesignField(
            'Payee',
            choiceLabels: parties,
            disabledOptions: {if (unavailable) retained},
          )
        else
          field,
    ],
    description: original.description,
    actionLabel: original.actionLabel,
    evidence: original.evidence,
    lines: original.lines,
    lineFields: original.lineFields,
    lineChoiceLabels: original.lineChoiceLabels,
    lineDisabledOptions: original.lineDisabledOptions,
    recurring: original.recurring,
    counterpartyCurrencies: original.counterpartyCurrencies,
    counterpartyCustomTerms: original.counterpartyCustomTerms,
    defaultCurrencyCode: workspace.identity.currency,
  );
}

DesignForm _catalogueCardCreditForm(
  DesignForm original,
  List<Account> accounts,
  AccountingWorkspace workspace,
  Map<String, Object?>? initial, {
  Iterable<Payee> registeredPayees = const [],
}) {
  final configured = _catalogueCardPaymentForm(
    original,
    accounts,
    workspace,
    initial,
    registeredPayees: registeredPayees,
    includeCustomerEmployees: true,
  );
  final accountChoices = {
    for (final account in accounts)
      if (account.status == AccountStatus.active && !account.isParent)
        account.id.value: account.name,
  };
  final unavailable = <String>{};
  for (final line in initial?['_lines'] as List? ?? const []) {
    final id = '${(line as Map)['Account'] ?? ''}';
    if (id.isNotEmpty && !accountChoices.containsKey(id)) {
      accountChoices[id] =
          '${accounts.where((a) => a.id.value == id).firstOrNull?.name ?? id} · Retained';
      unavailable.add(id);
    }
  }
  return DesignForm(
    original.title,
    configured.fields,
    description: original.description,
    actionLabel: original.actionLabel,
    lines: true,
    lineFields: original.lineFields,
    lineChoiceLabels: {
      'Account': accountChoices,
      'Tax Rate (%)': {
        '0': 'No Tax',
        for (final rate in workspace.taxRates) rate.choice: rate.label,
      },
    },
    lineDisabledOptions: {'Account': unavailable},
    evidence: original.evidence,
    defaultCurrencyCode: workspace.identity.currency,
  );
}

const _cashBackReportingTypes = {
  ReportingAccountType.cashAndCashEquivalents,
  ReportingAccountType.currentAssets,
  ReportingAccountType.creditCard,
  ReportingAccountType.currentLiabilities,
  ReportingAccountType.ownersEquity,
};

bool _depositAccountEligible(
  Account account,
  AccountingWorkspace workspace,
  String field,
) {
  if (account.isParent || account.status != AccountStatus.active) return false;
  if (field == 'Account') return true;
  if (field == 'Cash Back Account' && account.profile?.reportingType != null) {
    return _cashBackReportingTypes.contains(account.profile!.reportingType);
  }
  if (account.profile?.reportingType ==
      ReportingAccountType.cashAndCashEquivalents) {
    return true;
  }
  return workspace.paymentAccounts.any(
    (payment) =>
        const {
          PaymentAccountType.bank,
          PaymentAccountType.cash,
        }.contains(payment.type) &&
        payment.currency.code == workspace.identity.currency &&
        workspace.database.paymentLedgerAccount(
              workspace.identity.businessId,
              payment.id,
            ) ==
            account.id,
  );
}

DesignForm _catalogueDepositForm(
  DesignForm original,
  List<Account> accounts,
  AccountingWorkspace workspace,
  Map<String, Object?>? initial,
) {
  final savedLines = [
    for (final line in initial?['_lines'] as List? ?? const [])
      Map<String, String>.from(line as Map),
  ];
  final disabled = <String, Set<String>>{};
  Map<String, String> choices(String field, Iterable<String> retained) {
    final result = {
      for (final account in accounts)
        if (_depositAccountEligible(account, workspace, field))
          account.id.value: account.name,
    };
    for (final id in retained.where((id) => id.isNotEmpty)) {
      if (!result.containsKey(id)) {
        result[id] =
            '${accounts.where((a) => a.id.value == id).firstOrNull?.name ?? id} · Retained';
        (disabled[field] ??= {}).add(id);
      }
    }
    return result;
  }

  final deposits = choices('Deposit Account', [
    '${initial?['Deposit Account'] ?? ''}',
  ]);
  final cashBack = choices('Cash Back Account', [
    '${initial?['Cash Back Account'] ?? ''}',
  ]);
  final lineAccounts = choices(
    'Account',
    savedLines.map((line) => line['Account'] ?? ''),
  );
  final parties = {
    for (final customer in workspace.customers())
      if (customer.isActive)
        'customer:${customer.id.value}': '${customer.displayName} · Customer',
    for (final payee in workspace.payees.all)
      if (payee.type.name != 'staff')
        'payee:${payee.id}': '${payee.name} · ${payee.typeLabel}',
  };
  for (final line in savedLines) {
    final id = line['Received From'] ?? '';
    if (id.isNotEmpty && !parties.containsKey(id)) {
      parties[id] = '$id · Retained';
      (disabled['Received From'] ??= {}).add(id);
    }
  }
  final methods = {
    for (final method in const [
      'Bank Draft',
      'Cash',
      'Cash Deposit',
      'Cheque',
      'Credit Card',
      'Debit Card',
      'Direct Debit',
      'Online Banking',
    ])
      method: method,
    for (final line in savedLines)
      if ((line['Payment Method'] ?? '').isNotEmpty)
        line['Payment Method']!: line['Payment Method']!,
  };
  return DesignForm(
    original.title,
    [
      for (final field in original.fields)
        if (field.label == 'Deposit Account')
          DesignField(
            field.label,
            required: true,
            choiceLabels: deposits,
            disabledOptions: disabled[field.label] ?? const {},
          )
        else
          field,
      DesignField(
        'Cash Back Account',
        choiceLabels: cashBack,
        disabledOptions: disabled['Cash Back Account'] ?? const {},
      ),
      const DesignField('Cash Back Memo'),
      const DesignField('Cash Back Amount', monetary: true),
    ],
    description: original.description,
    actionLabel: original.actionLabel,
    lines: true,
    lineFields: original.lineFields,
    lineChoiceLabels: {
      'Received From': parties,
      'Account': lineAccounts,
      'Payment Method': methods,
      'Tax Rate (%)': {
        '0': 'No Tax',
        for (final code in workspace.taxRates) code.choice: code.label,
      },
    },
    lineDisabledOptions: disabled,
    defaultCurrencyCode: workspace.identity.currency,
    evidence: original.evidence,
  );
}

class FrontendFormDialog extends StatefulWidget {
  const FrontendFormDialog({
    super.key,
    required this.form,
    this.initial,
    this.accountOptions = const [],
    this.embedded = false,
    this.fieldLayoutOwner,
    this.contentWidth,
    this.widthFamily = AccountingPopoutWidthFamily.normal,
    this.onCommit,
    this.lineDefaults = const {},
    this.footerContent,
    this.embeddedContentBuilder,
    this.additionalContentBuilder,
    this.leadingContentBuilder,
    this.informationRows = const [],
    this.reviewInformationRowsBuilder,
    this.reviewDocumentsBuilder,
    this.onPreview,
    this.attachmentSetupKind,
    this.attachmentCategoryCode,
    this.firstDate,
    this.lastDate,
    this.settingsWorkspace,
    this.formBuilder,
    this.valuesFormBuilder,
    this.selectionValueUpdates,
    this.selectorActions = const {},
    this.fieldActionLabels = const {},
    this.fieldActionUpdates,
    this.inputValuesForComparison,
    this.previewConfirmationEnabled = true,
    this.onAddCounterparty,
    this.onAddPayee,
    this.onSearchPayees,
    this.onAddAccount,
    this.accountBalances = const {},
  });
  final Future<void> Function(Map<String, Object?> values)? onCommit;

  /// An unwired setup may show reviewed facts without offering an apparent
  /// successful Keep Preview that its caller cannot retain.
  final bool previewConfirmationEnabled;
  final Map<String, String> lineDefaults;
  final Widget? footerContent;

  /// An embedded owner may compose its ordinary fields with a labelled external
  /// control. Null slots mean read-only review; original content stays available.
  /// No opt-in is inferred for other fields, buttons, popouts or page owners.
  final Widget Function(
    Widget content,
    List<AccountingOrdinaryFieldSlot>? fields,
    double fieldWidth,
  )?
  embeddedContentBuilder;

  /// Explicit staged content belonging to this form. Review is read-only;
  /// exact facts must be included by reviewInformationRowsBuilder.
  final Widget Function(
    BuildContext context,
    Map<String, Object?> values,
    bool reviewing,
  )?
  additionalContentBuilder;

  /// Explicit owner content before ordinary fields, using the same shell.
  final Widget Function(
    BuildContext context,
    Map<String, Object?> values,
    bool reviewing,
  )?
  leadingContentBuilder;
  final List<(String, String)> informationRows;

  /// Resolves transaction defaults and exact amounts for review, without saving.
  /// Commit still revalidates current records and permissions independently.
  final List<(String, String)> Function(Map<String, Object?> values)?
  reviewInformationRowsBuilder;

  /// Resolves the current generated document or selected manual originals.
  /// Reuses the attachment viewer; neither review nor paging commits a record.
  final Future<List<ReceiptAttachment>> Function(Map<String, Object?> values)?
  reviewDocumentsBuilder;
  final DateTime? firstDate, lastDate;
  final SetupKind? attachmentSetupKind;
  final String Function(List<Map<String, String>>)? attachmentCategoryCode;
  final Future<void> Function(Map<String, Object?>)? onPreview;
  final bool embedded;

  /// Settings sections embedded inside a popup inherit ordinary row planning.
  /// Main/page/tab owners retain their layout unless explicitly opted in.
  final AccountingFieldLayoutOwner? fieldLayoutOwner;
  final double? contentWidth;
  final AccountingPopoutWidthFamily widthFamily;
  final DesignForm form;
  final AccountingWorkspace? settingsWorkspace;
  final DesignForm Function()? formBuilder;

  /// Existing directory owner; returns the saved ID after refreshing form choices.
  final Future<String?> Function()? onAddCounterparty;
  final Future<String?> Function()? onAddPayee;
  final Future<void> Function(String query)? onSearchPayees;
  final Future<String?> Function(String field)? onAddAccount;
  final Map<String, Money> accountBalances;

  /// Explicit owner-provided conditional fields. No inference or inherited opt-in.
  final DesignForm Function(Map<String, Object?> values)? valuesFormBuilder;

  /// Dependency patches belong to the calling owner, never inferred by label.
  /// Called after a selector/checkbox change with its previous value.
  final Map<String, Object?> Function(
    String label,
    Object? previous,
    Map<String, Object?> values,
  )?
  selectionValueUpdates;
  final Map<String, List<AccountingSelectorOption<String>>> selectorActions;
  final Map<String, String> fieldActionLabels;
  final Map<String, Object?> Function(
    String label,
    Map<String, Object?> values,
  )?
  fieldActionUpdates;
  final Map<String, Object?> Function(Map<String, Object?> values)?
  inputValuesForComparison;
  final List<String> accountOptions;
  final Map<String, Object?>? initial;
  @override
  State<FrontendFormDialog> createState() => _FrontendFormDialogState();
}

class _FrontendFormDialogState extends State<FrontendFormDialog> {
  String? _payeeLookupError;
  int _payeeLookupRevision = 0;

  Future<void> _searchRegisteredPayees(String query) async {
    final search = widget.onSearchPayees;
    if (search == null) return;
    final revision = ++_payeeLookupRevision;
    try {
      await search(query);
      if (!mounted || revision != _payeeLookupRevision) return;
      setState(() => _payeeLookupError = null);
    } on Object {
      if (!mounted || revision != _payeeLookupRevision) return;
      setState(
        () => _payeeLookupError =
            'Employee choices could not be loaded. Search again to retry.',
      );
    }
  }

  final _ordinaryFieldKeys = <String, GlobalKey>{};
  final _editingFocus = FocusScopeNode();
  late final String _openingInput;
  bool _closePromptOpen = false;
  String? _requiredReviewWarning;

  // Presence warnings follow the edited fields. Other command/validation errors
  // retain their own lifecycle and must never be cleared by an unrelated edit.
  void _refreshRequiredReviewWarning() {
    if (_requiredReviewWarning == null) return;
    if (_error != _requiredReviewWarning) {
      _requiredReviewWarning = null;
      return;
    }
    final missing = _transferFields(_form.fields)
        .where(
          (field) =>
              field.required && '${_values[field.label] ?? ''}'.trim().isEmpty,
        )
        .map((field) => field.label)
        .toList();
    _requiredReviewWarning = missing.isEmpty
        ? null
        : 'Complete ${missing.join(', ')} before reviewing.';
    _error = _requiredReviewWarning;
  }

  bool get _ordinaryPopupLayout =>
      (widget.fieldLayoutOwner ??
          (widget.embedded
              ? AccountingFieldLayoutOwner.pageTab
              : AccountingFieldLayoutOwner.sharedPopup)) ==
      AccountingFieldLayoutOwner.sharedPopup;
  bool _retainQuantityRate = false;
  bool _retainQuantity = false;
  bool _retainDiscount = false;
  DesignForm get _baseForm => widget.formBuilder?.call() ?? widget.form;
  DesignForm get _form {
    final base =
        widget.valuesFormBuilder?.call(Map.unmodifiable(_values)) ?? _baseForm;
    if (base.lineFields == null) return base;
    final fields = [
      for (final field in base.lineFields!)
        if (const {'Deposits', 'Credit Card Credits'}.contains(base.title) &&
            _values['Tax Mode'] == 'Out Of Scope' &&
            field == 'Tax Rate (%)')
          ...<String>[]
        else if (_retainQuantityRate && field == 'Amount') ...[
          'Quantity',
          'Rate',
        ] else
          field,
      if (_retainDiscount && !base.lineFields!.contains('Discount')) 'Discount',
      if (_retainQuantity && !base.lineFields!.contains('Quantity')) 'Quantity',
    ];
    return base.withLineFields(fields.toSet().toList());
  }

  bool get _salesGrid =>
      widget.settingsWorkspace != null &&
      _form.lineChoiceLabels.containsKey('Product / Service');
  bool get _documentTaxFamily => _salesDocumentTaxFamily(_form);
  String get _salesBasisDefault =>
      widget.settingsWorkspace?.preferences.text(
        'Sales Preferences',
        'Default Tax Mode',
      ) ??
      'Exclusive';
  String? get _documentTaxChoice {
    final choices = _lines.map((line) => line['Tax Rate (%)'] ?? '').toSet();
    return choices.length == 1 && choices.single.isNotEmpty
        ? choices.single
        : null;
  }

  Widget _documentTaxBasisWarning() {
    if (const {
      'Exclusive',
      'Inclusive',
      'Exempt',
      'Out Of Scope',
    }.contains(_values['Tax Mode'])) {
      return const SizedBox.shrink();
    }
    // A retained No Tax choice does not establish the saved amount basis.
    // Keep the saved facts intact until the user confirms the document tax.
    return Padding(
      padding: const EdgeInsets.only(top: accountingContentInset),
      child: AccountingAlert.build(
        context,
        key: const ValueKey('sales-document-tax-basis-warning'),
        title: 'Amount Basis Required',
        description: 'Select a Tax option to confirm the saved amount basis using Sales Preferences.',
        tone: AccountingAlertTone.warning,
      ),
    );
  }

  bool get _billTaxFamily => _form.title == 'Bills' && _transactionGrid;

  Map? _originalBillLine(Map<String, String> line) =>
      (widget.initial?['_lines'] as List? ?? const [])
          .whereType<Map>()
          .where((saved) => saved['_lineId'] == line['_lineId'])
          .firstOrNull;

  CompanyTaxRate? _savedBillTax(Map<String, String> line) =>
      (widget.initial?['_billTaxSnapshots'] as Map?)?[line['_lineId']]
          as CompanyTaxRate?;

  bool _billLineTaxResolved(Map<String, String> line) {
    final date = parseAccountingInputDate(_values['Date'] as String? ?? '');
    if (date == null) return false;
    try {
      resolveBillTaxSelection(
        line['Tax Rate (%)'] ?? '',
        codes: widget.settingsWorkspace!.taxRates,
        date: date,
        originalChoice: _originalBillLine(line)?['Tax Rate (%)'] as String?,
        saved: _savedBillTax(line),
      );
      return true;
    } on Object {
      return false;
    }
  }

  Widget _billTaxWarnings() {
    final missingRows = [
      for (var i = 0; i < _lines.length; i++)
        if (!_billLineTaxResolved(_lines[i])) '${i + 1}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!const {
          'Exclusive',
          'Inclusive',
          'Exempt',
          'Out Of Scope',
        }.contains(_values['Tax Mode'])) ...[
          const SizedBox(height: accountingContentInset),
          AccountingAlert.build(
            context,
            key: const ValueKey('bill-tax-basis-warning'),
            title: 'Amount Basis Required',
            description: 'Select Tax Exclusive or Tax Inclusive. The saved Bill has no document-wide amount basis.',
            tone: AccountingAlertTone.warning,
          ),
        ],
        if (missingRows.isNotEmpty) ...[
          const SizedBox(height: accountingContentInset),
          AccountingAlert.build(
            context,
            key: const ValueKey('bill-tax-selection-warning'),
            title: 'Tax Selection Required',
            description:
                'Select No Tax or a configured tax valid for the Bill date for ${missingRows.length == 1 ? 'row' : 'rows'} ${missingRows.join(', ')}.',
            tone: AccountingAlertTone.warning,
          ),
        ],
      ],
    );
  }

  bool get _transactionGrid =>
      _salesGrid ||
      (widget.settingsWorkspace != null &&
          _form.lineChoiceLabels.containsKey('Account') &&
          _form.lineFields?.contains('Description') == true &&
          (_form.lineFields?.contains('Amount') == true ||
              _form.lineFields?.contains('Rate') == true));
  bool get _ordinaryTransactionHeader =>
      _transactionGrid ||
      (!widget.embedded &&
          _form.lines &&
          trialOrdinaryGroups.containsKey(_form.title));
  late double _contentWidth =
      widget.contentWidth ?? AccountingPopoutTokens.widerContentWidth;
  late final String _widthOwner = 'transaction-${identityHashCode(this)}';
  bool _ownsWidth = false;
  Future<void> _ensureTransactionWidth({bool allowShrink = false}) async {
    if (!mounted || !_form.lines) return;
    // Header controls already wrap through the existing group planner. Adding
    // a line must only reserve the width required by its transaction columns.
    final requiredWidth = _transactionGrid
        ? frontendTransactionContentWidth(context, _form, lines: _lines)
        : math.max(
            AccountingPopoutTokens.widerContentWidth,
            _previewFixedWidth(_previewColumnWidths(_moneyCurrencyCode())) +
                180,
          );
    final width = allowShrink
        ? requiredWidth
        : math.max(_contentWidth, requiredWidth);
    if (width == _contentWidth) return;
    _ownsWidth = await AccountingDialog.acquireFixedWidth(_widthOwner, width);
    if (!mounted) {
      if (_ownsWidth) await AccountingDialog.releaseFixedWidth(_widthOwner);
      return;
    }
    _contentWidth = width;
  }

  Future<void> _openTransactionSettings() async {
    final workspace = widget.settingsWorkspace;
    final fields = transactionSettingsFields(_form.title);
    if (workspace == null || fields.isEmpty) return;
    final previousFields = _form.lineFields ?? const <String>[];
    await openAccountingSettings(
      context,
      workspace: workspace,
      fields: fields,
      setupKinds: {
        if (widget.attachmentSetupKind != null) widget.attachmentSetupKind!,
      },
      title: '${_form.title} Settings',
    );
    if (!mounted) return;
    final nextFields = _baseForm.lineFields ?? const <String>[];
    // Hiding a preference must not conceal a nonzero or incomplete draft value.
    _retainDiscount =
        !nextFields.contains('Discount') &&
        _lines.any((line) {
          final text = (line['Discount'] ?? '').trim();
          if (text.isEmpty) return false;
          try {
            return Money.fromDecimal(text, _moneyCurrencyCode()).minorUnits !=
                0;
          } on Object {
            return true;
          }
        });
    if (nextFields.contains('Rate')) _retainQuantityRate = false;
    if (nextFields.contains('Quantity')) _retainQuantity = false;
    if (previousFields.contains('Amount') && nextFields.contains('Rate')) {
      for (final line in _lines) {
        line.putIfAbsent('Quantity', () => '1');
        final amountText = line['Amount'] ?? '';
        try {
          final quantity = SalesQuantity.fromDecimal(line['Quantity']!);
          final amount = Money.fromDecimal(amountText, _moneyCurrencyCode());
          line['Rate'] = formatAccountingInputAmount(quantity.rateFor(amount));
          line['_manualAmount'] = amountText;
        } on Object {
          line['Rate'] = '';
          line.remove('_manualAmount');
        }
        line.remove('_amountEdited');
      }
    } else if (previousFields.contains('Rate') &&
        nextFields.contains('Amount')) {
      for (final line in _lines) {
        try {
          final quantity = SalesQuantity.fromDecimal(line['Quantity'] ?? '1');
          if (!nextFields.contains('Quantity') &&
              quantity != SalesQuantity.fromInt(1)) {
            _retainQuantity = true;
          }
          if ((line['Rate'] ?? '').isEmpty && line['_manualAmount'] == null) {
            line['Amount'] = '';
            continue;
          }
          line['Amount'] =
              line['_manualAmount'] ??
              formatAccountingInputAmount(
                quantity.multiply(
                  Money.fromDecimal(line['Rate'] ?? '', _moneyCurrencyCode()),
                ),
              );
          line.remove('_manualAmount');
        } on Object {
          _retainQuantityRate = true;
          _error = 'Complete the entered quantity and rate before saving. These fields remain visible for this draft.';
        }
      }
    }
    await _ensureTransactionWidth(allowShrink: true);
    if (mounted) {
      setState(() {
        if (widget.reviewDocumentsBuilder != null) _review = false;
      });
    }
  }

  late final String _today = formatAccountingInputDate(DateTime.now());
  late final Map<String, Object?> _values = {
    if (_baseForm.fields.any((field) => field.label == 'Date')) 'Date': _today,
    if (_baseForm.fields.any((field) => field.label == 'Due Date'))
      'Due Date': _today,
    ...?widget.initial,
  };
  late final List<Map<String, String>> _lines =
      widget.initial?['_lines'] is List
      ? [
          for (final line in widget.initial!['_lines'] as List)
            {
              ...Map<String, String>.from(line as Map),
              '_lineId':
                  (line['_lineId'] as String?) ?? EntityId.random().value,
            },
        ]
      : [
          {...widget.lineDefaults, '_lineId': EntityId.random().value},
        ];
  late final List<String> _files = List<String>.from(
    widget.initial?['_files'] as List? ?? [],
  );
  late final List<ReceiptAttachment?> _attachments;

  @override
  void initState() {
    super.initState();
    if (_documentTaxFamily &&
        widget.initial?['_savedSalesTaxFacts'] != true &&
        widget.initial?['_lines'] == null) {
      if (!const {
        'Exclusive',
        'Inclusive',
        'Exempt',
        'Out Of Scope',
      }.contains(_values['Tax Mode'])) {
        _values['Tax Mode'] = _salesBasisDefault;
      }
      for (final line in _lines) {
        line['Tax Rate (%)'] = '0';
      }
    }
    if (_form.lines && !_transactionGrid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _ensureTransactionWidth();
        if (mounted) setState(() {});
      });
    }
    // Initialize the paired collection before an import mutates filenames.
    // A lazy initializer based on _files.length otherwise creates a placeholder
    // for the first new filename and shifts every actual document one position.
    _attachments = List<ReceiptAttachment?>.generate(_files.length, (i) {
      final saved = widget.initial?['_attachments'];
      return saved is List && i < saved.length
          ? saved[i] as ReceiptAttachment?
          : null;
    });
    // The displayed quotation validity and its derived expiry are opening
    // defaults, not user edits. Capture them before the first build reads them.
    _syncQuotationExpiry();
    _openingInput = _inputSnapshot();
    if (widget.onSearchPayees != null) {
      unawaited(_searchRegisteredPayees(''));
    }
  }

  final Map<String, TextEditingController> _controllers = {};
  bool _logoDragOver = false;

  bool _editingLogo = false;
  late Uint8List? _logoPreview =
      widget.initial?['_businessLogoBase64'] is String &&
          (widget.initial!['_businessLogoBase64'] as String).isNotEmpty
      ? base64Decode(widget.initial!['_businessLogoBase64'] as String)
      : null;
  bool _savedSettings = false;

  Future<void> _editLogo(String name, Future<Uint8List> Function() read) async {
    if (_editingLogo) return;
    _editingLogo = true;
    try {
      final bytes = await read();
      if (!mounted) return;
      final cropped = await showProfilePhotoEditor(context, bytes);
      if (cropped != null && mounted) {
        setState(() {
          _savedSettings = false;
          _values['Business Logo'] = name;
          _values['_businessLogoBase64'] = cropped;
          _logoPreview = base64Decode(cropped);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The logo could not be opened. Choose a JPEG or PNG image.',
        );
      }
    } finally {
      _editingLogo = false;
    }
  }

  Future<void> _chooseLogo() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isNotEmpty && mounted) {
      await _editLogo(files.first.name, files.first.readAsBytes);
    }
  }

  bool _isMoneyField(DesignField field) {
    final label = field.label;
    return field.monetary ||
        field.currencyCode != null ||
        field.currencySourceLabel != null ||
        const {
          'Amount',
          'Fixed Amount',
          'Amount Applied to Document',
          'Payment Not Applied',
          'Credit To Apply',
        }.contains(label);
  }

  String _fieldMoneyCurrencyCode(DesignField field) {
    final selected = _values[field.currencySourceLabel]?.toString();
    if (selected != null && RegExp(r'^[A-Za-z]{3}$').hasMatch(selected)) {
      return selected.toUpperCase();
    }
    return _moneyCurrencyCode(field.currencyCode);
  }

  String _moneyCurrencyCode([String? explicit]) {
    if (explicit != null) return explicit;
    final selected = (_values['Currency'] ?? widget.initial?['Currency'])
        ?.toString();
    if (selected != null && RegExp(r'^[A-Za-z]{3}$').hasMatch(selected)) {
      return selected.toUpperCase();
    }
    return _counterpartyCurrencyCode();
  }

  String _counterpartyCurrencyCode() =>
      _form.counterpartyCurrencies[_values['Counterparty']?.toString()] ??
      _form.defaultCurrencyCode;

  String? _amountPrefix(DesignField field) {
    if (_ordinaryPopupLayout) return null;
    if (!_isMoneyField(field)) return null;
    final code = _fieldMoneyCurrencyCode(field);
    try {
      return CurrencyPresentation.fromCode(code).amountSymbol;
    } on FormatException {
      return code;
    }
  }

  @override
  void dispose() {
    _editingFocus.dispose();
    if (_ownsWidth) unawaited(AccountingDialog.releaseFixedWidth(_widthOwner));
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Iterable<DesignField> get _reviewFields sync* {
    final emitted = <String>{};
    for (final declared in _receivePaymentFields(
      _transferFields(_quotationValidityFields(_form.fields)),
    )) {
      if (_ordinaryTransactionHeader && declared.label == 'Due Date') continue;
      final field =
          declared.descriptionRole == AccountingDescriptionRole.memo &&
              _customInformationActive
          ? DesignField(
              _memoKey,
              multiline: true,
              descriptionRole: _customInformationRole,
            )
          : declared;
      if (emitted.add(field.label)) yield field;
      final value = _values[field.label];
      final dependent = value == 'Days After Issue'
          ? const ['Number Of Days']
          : value == 'Day Of Month'
          ? const ['Monthly Due Day', 'Rollover Within Days']
          : value == 'Custom' &&
                !_form.fields.any(
                  (f) => f.descriptionRole == AccountingDescriptionRole.memo,
                )
          ? const ['Custom Payment Terms']
          : const <String>[];
      for (final label in dependent) {
        if (emitted.add(label)) yield DesignField(label);
      }
    }
  }

  bool _review = false;
  late bool _recurring =
      widget.initial?['_recurring'] == true ||
      (widget.initial?['Make Recurring'] != null &&
          widget.initial?['Make Recurring'] != 'No');
  late final _scheduleId = EntityId.random().value;
  bool get _recurrenceLocked => widget.initial?['_recurrenceManaged'] == true;
  String get _recurrenceFrequency =>
      '${_values['Make Recurring'] ?? (_recurring ? 'Monthly' : 'No')}';

  DocumentRecurrenceRequest _recurrenceRequest() {
    String text(String key) => '${_values[key] ?? ''}'.trim();
    final start = parseAccountingInputDate(text('Start Date'));
    final endChoice = text('End Condition');
    final end = endChoice == 'On Date'
        ? parseAccountingInputDate(text('End Date'))
        : null;
    final count = endChoice == 'After Occurrences'
        ? int.tryParse(text('Occurrence Count'))
        : null;
    final custom = _recurrenceFrequency == 'Custom';
    final every = custom
        ? int.tryParse(text('Every'))
        : _recurrenceFrequency == 'Quarterly'
        ? 3
        : 1;
    if (start == null ||
        every == null ||
        every < 1 ||
        every > 1000 ||
        !['No End Date', 'On Date', 'After Occurrences'].contains(endChoice) ||
        endChoice == 'On Date' && end == null ||
        endChoice == 'After Occurrences' &&
            (count == null || count < 1 || count > 100000)) {
      throw const FormatException(
        'Enter a valid recurring start, interval and end condition.',
      );
    }
    final unit = custom
        ? switch (text('Interval Unit')) {
            'Days' => RecurrenceUnit.days,
            'Weeks' => RecurrenceUnit.weeks,
            'Months' => RecurrenceUnit.months,
            'Years' => RecurrenceUnit.years,
            _ => throw const FormatException(
              'Choose a recurring interval unit.',
            ),
          }
        : _recurrenceFrequency == 'Yearly'
        ? RecurrenceUnit.years
        : RecurrenceUnit.months;
    return DocumentRecurrenceRequest(
      id: _scheduleId,
      name: text('Document Number'),
      schedule: RecurrenceRule(
        startsOn: start,
        unit: unit,
        every: every,
        endsOn: end,
        occurrenceCount: count,
        preserveMonthEnd: _values['Preserve Month End'] as bool? ?? true,
      ),
    );
  }

  String? _error;
  List<(String, String)>? _resolvedReviewRows;
  List<ReceiptAttachment>? _resolvedReviewDocuments;
  int _reviewDocument = 0;
  bool _preparingReview = false;

  Map<String, Object?> _formValues() => {
    ..._values,
    if (_form.title == 'Deposits' && _depositLineTotals() != null)
      'Amount': _depositTotal(
        _depositLineTotals()!.$3,
        formatAccountingInputAmount,
      ),
    // Standard payment terms own the derived date. A hidden legacy/default
    // value must not override them. Custom and embedded owners keep their facts.
    if (!widget.embedded &&
        const {'Invoices', 'Bills'}.contains(_form.title) &&
        !_customTermsActive)
      'Due Date': '',
    if (_documentTaxFamily) '_documentTaxChoice': _documentTaxChoice,
    '_preview': widget.onCommit == null,
    '_lines': [
      for (final line in _lines)
        {
          for (final entry in line.entries)
            if (!const {'Amount', 'Rate', 'Quantity'}.contains(entry.key) ||
                _form.lineFields?.contains(entry.key) != false)
              entry.key: entry.value,
        },
    ],
    '_files': List<String>.from(_files),
    '_attachments': List<ReceiptAttachment?>.from(_attachments),
    if (_resolvedReviewDocuments != null)
      '_reviewedDocuments': List<ReceiptAttachment>.from(
        _resolvedReviewDocuments!,
      ),
    '_recurring': _recurring,
    if (_transactionGrid && _form.recurring && _recurring && !_recurrenceLocked)
      '_documentRecurrence': _recurrenceRequest(),
  };

  (Money, Money, Money)? _lineTotals() {
    final mode = '${_values['Tax Mode'] ?? ''}';
    if (!const {
      'Exclusive',
      'Inclusive',
      'Out Of Scope',
      'Exempt',
    }.contains(mode)) {
      return null;
    }
    try {
      final currency = _moneyCurrencyCode();
      var subtotal = Money.zero(currency);
      var tax = Money.zero(currency);
      var total = Money.zero(currency);
      var hasLine = false;
      for (final line in _lines) {
        final usesAmount =
            _form.lineFields?.contains('Amount') ?? line.containsKey('Amount');
        final amountText =
            (usesAmount ? line['Amount'] ?? '' : line['Rate'] ?? '').trim();
        if (amountText.isEmpty) {
          if (line.values.any(
            (value) =>
                value.trim().isNotEmpty &&
                value != line['_lineId'] &&
                value != '1' &&
                value != '0',
          )) {
            return null;
          }
          continue;
        }
        hasLine = true;
        final quantity = SalesQuantity.fromDecimal(
          usesAmount ? '1' : line['Quantity'] ?? '',
        );
        final rate = Money.fromDecimal(amountText, currency);
        final discount = Money.fromDecimal(
          (line['Discount'] ?? '').trim().isEmpty ? '0' : line['Discount']!,
          currency,
        );
        final discounted =
            (usesAmount || line['_manualAmount'] == null
                ? quantity.multiply(rate)
                : Money.fromDecimal(line['_manualAmount']!, currency)) -
            discount;
        if (_billTaxFamily && !_billLineTaxResolved(line)) return null;
        if (_salesReceiptCatalogue && !_salesReceiptLineTaxResolved(line)) {
          return null;
        }
        if (_bankingLineTaxFamily && !_bankingLineTaxResolved(line)) {
          return null;
        }
        final rateText = taxPercent((line['Tax Rate (%)'] ?? '').trim());
        if ((mode == 'Inclusive' || mode == 'Exclusive') && rateText.isEmpty) {
          return null;
        }
        if ((mode == 'Exempt' || mode == 'Out Of Scope') &&
            rateText.isNotEmpty &&
            InvoiceTaxRate.fromPercent(rateText).units != 0) {
          return null;
        }
        final calculated = InvoiceTaxCalculation.calculate(
          amount: discounted,
          rate: InvoiceTaxRate.fromPercent(rateText.isEmpty ? '0' : rateText),
          inclusive: mode == 'Inclusive',
        );
        subtotal += calculated.net;
        tax += calculated.tax;
        total += calculated.total;
      }
      return hasLine ? (subtotal, tax, total) : null;
    } on Object {
      return null;
    }
  }

  bool _lineAmountsEmpty(String currency) => _lines.every((line) {
    try {
      return ['Amount', 'Rate', '_manualAmount', 'Discount'].every((key) {
        final text = (line[key] ?? '').trim();
        return text.isEmpty ||
            Money.fromDecimal(text, currency).minorUnits == 0;
      });
    } on Object {
      return false;
    }
  });

  bool _committing = false;
  bool _isDragOver = false;

  String _displayLabel(String label) {
    if (_receivePaymentProposal && label == 'Amount') {
      return 'Amount Received (${CurrencyPresentation.fromCode(_moneyCurrencyCode()).amountSymbol})';
    }
    if ((_receivePaymentProposal || _salesReceiptProposal) &&
        label == 'Payment Account') {
      return 'Deposit To';
    }
    if (_quotationValidityProposal &&
        label == 'Memo' &&
        _customInformationActive) {
      return 'Quotation Info';
    }
    if (label == 'Custom Payment Terms') return 'Payment Terms';
    if (_ordinaryTransactionHeader) {
      if (label == 'Payment Terms') return 'Terms';
      if (label == 'Tax Mode') return 'Amounts are';
    }
    if (label != 'Counterparty') return label;
    return const [
          'Invoices',
          'Quotations',
          'Credit Notes',
          'Receive Payment',
          'Sales Receipts',
          'Refunds',
        ].contains(_form.title)
        ? 'Customer'
        : 'Vendor';
  }

  String _choiceLabel(DesignField field, String value) {
    if (const {'Tax Mode', 'Default Tax Mode'}.contains(field.label) &&
        const {'Exclusive', 'Inclusive'}.contains(value)) {
      return 'Tax $value';
    }
    if (_ordinaryTransactionHeader) {
      if (field.label == 'Currency') {
        if (value == 'Use Counterparty Default') {
          return 'Default (${CurrencyPresentation.fromCode(_counterpartyCurrencyCode()).amountSymbol})';
        }
        if (CurrencyPresentation.byCurrency.containsKey(value)) {
          return CurrencyPresentation.fromCode(value).amountSymbol;
        }
      }
      if (value == 'Use Customer Default') return 'Customer Default';
      if (value == 'Use Vendor Default') return 'Vendor Default';
    }
    if (field.choiceLabels != null) {
      return field.choiceLabels![value] ??
          (value.isEmpty ? 'Not Set' : 'Unavailable Selection');
    }
    if (field.label.contains('Currency') &&
        CurrencyPresentation.byCurrency.containsKey(value)) {
      return CurrencyPresentation.fromCode(value).label;
    }
    return value;
  }

  String _reviewValue(DesignField field) {
    final value = _values[field.label];
    if (value == null) return 'Not Set';
    if (value is bool) return value ? 'Yes' : 'No';
    return _choiceLabel(field, '$value');
  }

  String? get _defaultCustomTerms =>
      _form.counterpartyCustomTerms[_values['Counterparty']];
  // Explicit quotation popout proposal. Offer validity is independent of the
  // payment terms retained by the legacy conversion/storage contract.
  bool get _quotationValidityProposal =>
      !widget.embedded && _baseForm.title == 'Quotations' && _baseForm.lines;
  bool get _salesReceiptProposal =>
      !widget.embedded &&
      widget.onCommit == null &&
      _baseForm.title == 'Sales Receipts';
  bool get _receivePaymentProposal =>
      !widget.embedded &&
      widget.onCommit == null &&
      _baseForm.title == 'Receive Payment' &&
      _baseForm.fields.any((field) => field.label == 'Counterparty');
  String get _quotationValidityChoice => _values.putIfAbsent('Validity', () {
    final date = parseAccountingInputDate('${_values['Date'] ?? ''}');
    final expiry = parseAccountingInputDate('${_values['Expiry Date'] ?? ''}');
    if (date == null || expiry == null) return '30 Days';
    final days = DateTime.utc(
      expiry.year,
      expiry.month,
      expiry.day,
    ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
    return const [30, 60, 90].contains(days) ? '$days Days' : 'Custom';
  }) as String;

  void _syncQuotationExpiry() {
    if (!_quotationValidityProposal || _quotationValidityChoice == 'Custom') {
      return;
    }
    final date = parseAccountingInputDate('${_values['Date'] ?? ''}');
    if (date == null) return;
    final days = int.parse(_quotationValidityChoice.split(' ').first);
    final expiry = formatAccountingInputDate(
      DateTime(date.year, date.month, date.day + days),
    );
    _values['Expiry Date'] = expiry;
    final controller = _controllers['Expiry Date'];
    if (controller != null && controller.text != expiry) {
      controller.text = expiry;
    }
  }

  List<DesignField> _quotationValidityFields(List<DesignField> fields) {
    if (!_quotationValidityProposal) return fields;
    _syncQuotationExpiry();
    return [
      for (final field in fields)
        if (field.label == 'Payment Terms')
          const DesignField(
            'Validity',
            options: ['30 Days', '60 Days', '90 Days', 'Custom'],
          )
        else if (field.label != 'Expiry Date')
          field,
    ];
  }

  bool get _customTermsActive =>
      !_quotationValidityProposal &&
      (_values['Payment Terms'] == 'Custom' ||
          (const [
                'Use Customer Default',
                'Use Vendor Default',
              ].contains(_values['Payment Terms']) &&
              _defaultCustomTerms != null));
  bool get _customInformationActive => _quotationValidityProposal
      ? _quotationValidityChoice == 'Custom'
      : _customTermsActive;
  AccountingDescriptionRole get _customInformationRole =>
      _quotationValidityProposal
      ? AccountingDescriptionRole.memo
      : AccountingDescriptionRole.paymentTerms;
  String get _memoKey => _salesReceiptCatalogue
      ? 'Receipt Message'
      : _quotationValidityProposal
      ? 'Memo'
      : _customInformationActive
      ? 'Custom Payment Terms'
      : 'Memo';
  String get _customTermsInitial => _quotationValidityProposal
      ? '${_values['Memo'] ?? ''}'
      : '${_values['Custom Payment Terms'] ?? _defaultCustomTerms ?? _values['Memo'] ?? ''}';

  void _selectField(String label, String? value) {
    final previous = _values[label];
    if (_bankingLineTaxFamily &&
        label == 'Tax Mode' &&
        value == 'Out Of Scope' &&
        value != _values[label]) {
      for (final line in _lines) {
        line['Tax Rate (%)'] = '';
      }
    }
    if (_bankingLineTaxFamily &&
        label == 'Tax Mode' &&
        const {'Exclusive', 'Inclusive'}.contains(_values[label]) &&
        const {'Exclusive', 'Inclusive'}.contains(value) &&
        value != _values[label]) {
      for (final line in _lines) {
        if (!_bankingLineTaxResolved(line) ||
            (line['Amount'] ?? '').trim().isEmpty) {
          continue;
        }
        try {
          final calculation = InvoiceTaxCalculation.calculate(
            amount: Money.fromDecimal(line['Amount']!, _moneyCurrencyCode()),
            rate: InvoiceTaxRate.fromPercent(taxPercent(line['Tax Rate (%)']!)),
            inclusive: _values[label] == 'Inclusive',
          );
          line['Amount'] = formatAccountingInputAmount(
            value == 'Inclusive' ? calculation.total : calculation.net,
          );
          line['_selectionRevision'] =
              '${(int.tryParse(line['_selectionRevision'] ?? '') ?? 0) + 1}';
        } on Object {
          // Incomplete or out-of-range drafts retain their entered amount.
        }
      }
    }
    _values[label] = value;
    if (const {
          'Transfers',
          'Deposits',
          'Credit Card Credits',
        }.contains(_form.title) &&
        label == 'Make Recurring') {
      _recurring = value != null && value != 'No';
    }
    if (_salesReceiptCatalogue &&
        const {'Currency', 'Counterparty', 'Payment Account'}.contains(label) &&
        _error ==
            'Choose an available Deposit To account in the receipt currency.') {
      _error = null;
    }
    if (_salesReceiptCatalogue && label == 'Counterparty') {
      final customer = widget.settingsWorkspace!
          .customers()
          .where((customer) => customer.id.value == value)
          .firstOrNull;
      if (customer != null) {
        final address = customer.billingAddress;
        final addressText = address == null
            ? ''
            : [
                address.line1,
                address.line2 ?? '',
                address.city,
                address.postalCode,
                address.stateOrProvince ?? '',
                customer.profileDetails.countryName.isNotEmpty
                    ? customer.profileDetails.countryName
                    : address.countryCode,
              ].where((line) => line.trim().isNotEmpty).join('\n');
        for (final entry in {
          'Email': customer.contact.email ?? '',
          'Billing Address': addressText,
        }.entries) {
          _values[entry.key] = entry.value;
          _controllers[entry.key]?.text = entry.value;
        }
      }
    }
    if (_quotationValidityProposal && label == 'Validity') {
      _syncQuotationExpiry();
    }
    if (label == 'Counterparty' &&
        const [
          'Use Customer Default',
          'Use Vendor Default',
        ].contains(_values['Payment Terms'])) {
      _values['Custom Payment Terms'] = _defaultCustomTerms ?? '';
      _controllers['Custom Payment Terms']?.text = _defaultCustomTerms ?? '';
    }
    if (label == 'Payment Terms' && _customTermsActive) {
      if ('${_values['Custom Payment Terms'] ?? ''}'.isEmpty) {
        _values['Custom Payment Terms'] =
            _defaultCustomTerms ?? _values['Memo'] ?? '';
        _controllers['Custom Payment Terms']?.text = _customTermsInitial;
      }
    }
    _applyOwnerUpdates(
      widget.selectionValueUpdates?.call(
        label,
        previous,
        Map.unmodifiable(_values),
      ),
    );
  }

  void _applyOwnerUpdates(Map<String, Object?>? updates) {
    if (updates == null) return;
    for (final entry in updates.entries) {
      _values[entry.key] = entry.value;
      if (entry.value is String) {
        _controllers[entry.key]?.text = entry.value as String;
      }
    }
  }

  bool get _isSettingsForm =>
      settingsForms.any((form) => form.title == _form.title);

  List<String> _optionsFor(DesignField field) {
    final label = field.label;
    final accountField = label.endsWith('Account');
    if (_salesReceiptCatalogue && label == 'Payment Account') {
      return [
        for (final value in field.choiceLabels!.keys)
          if (value == _values[label] ||
              (!field.disabledOptions.contains(value) &&
                  _salesReceiptDepositCurrencyMatches(value)))
            value,
      ];
    }
    return field.choiceLabels != null
        ? field.choiceLabels!.keys.toList()
        : label == 'State / Region' && _values['Country'] == 'Malaysia'
        ? const [
            'Johor',
            'Kedah',
            'Kelantan',
            'Melaka',
            'Negeri Sembilan',
            'Pahang',
            'Pulau Pinang',
            'Perak',
            'Perlis',
            'Selangor',
            'Terengganu',
            'Sabah',
            'Sarawak',
            'Kuala Lumpur',
            'Labuan',
            'Putrajaya',
          ]
        : accountField
        ? widget.accountOptions
        : field.options;
  }

  bool _salesReceiptDepositCurrencyMatches(String id) =>
      widget.settingsWorkspace!.paymentAccounts.any(
        (payment) =>
            payment.id == id && payment.currency.code == _moneyCurrencyCode(),
      );

  List<AccountingSelectorOption<String>> _selectorOptions(
    DesignField field,
  ) => [
    ...?widget.selectorActions[field.label],
    if (const {
          'Transfers',
          'Deposits',
          'Cheques',
          'Credit Card Payments',
          'Credit Card Credits',
        }.contains(_form.title) &&
        field.label.endsWith('Account') &&
        widget.onAddAccount != null)
      AccountingSelectorOption(
        value: '__add_account__',
        label: 'Add Account',
        leading: const AccountingAddIcon(),
        leadingWidth: AccountingDismissIcon.canvasSize,
        onPressed: () async {
          final id = await widget.onAddAccount!(field.label);
          if (id == null || !mounted) return;
          setState(() => _selectField(field.label, id));
        },
      ),
    if (field.label == 'Payee' && widget.onAddPayee != null)
      AccountingSelectorOption(
        value: '__add_payee__',
        label: 'Add Payee',
        leading: const AccountingAddIcon(),
        leadingWidth: AccountingDismissIcon.canvasSize,
        onPressed: () async {
          final id = await widget.onAddPayee!();
          if (id != null && mounted) {
            setState(() => _selectField(field.label, id));
          }
        },
      ),
    if (field.label == 'Counterparty' && widget.onAddCounterparty != null)
      AccountingSelectorOption(
        value: '__add_counterparty__',
        label: 'Add ${_displayLabel(field.label)}',
        leading: const AccountingAddIcon(),
        leadingWidth: AccountingDismissIcon.canvasSize,
        onPressed: () async {
          final id = await widget.onAddCounterparty!();
          if (id == null || !mounted) return;
          _selectField('Counterparty', id);
          await _ensureTransactionWidth();
          if (mounted) setState(() {});
        },
      )
    else if (_salesReceiptCatalogue && field.label == 'Counterparty')
      AccountingSelectorOption(
        value: '__add_customer__',
        label: 'Add Customer',
        leading: const AccountingAddIcon(),
        leadingWidth: AccountingDismissIcon.canvasSize,
        onPressed: () async {
          final customer = await showAccountingCustomerDialog(
            context,
            widget.settingsWorkspace!,
          );
          if (customer == null || !mounted) return;
          _selectField('Counterparty', customer.id.value);
          await _ensureTransactionWidth();
          if (mounted) setState(() {});
        },
      ),
    for (final value in _optionsFor(field))
      AccountingSelectorOption(
        value: value,
        label:
            _salesReceiptCatalogue &&
                field.label == 'Payment Account' &&
                (field.disabledOptions.contains(value) ||
                    !_salesReceiptDepositCurrencyMatches(value)) &&
                !_choiceLabel(field, value).endsWith(' · Retained')
            ? '${_choiceLabel(field, value)} · Retained'
            : _choiceLabel(field, value),
        enabled:
            !field.disabledOptions.contains(value) &&
            (!(_salesReceiptCatalogue && field.label == 'Payment Account') ||
                _salesReceiptDepositCurrencyMatches(value)),
        preserveLabelCase:
            field.label.endsWith('Account') ||
            field.choiceLabels != null ||
            field.label.contains('Currency'),
      ),
  ];

  bool _isDateField(String label) =>
      (label.endsWith('Date') && label != 'Days Before Due Date') ||
      label.startsWith('Effective ') ||
      label == 'Period From' ||
      label == 'Period Through';

  Widget _field(DesignField field, {double? assignedWidth}) {
    final label = field.label;
    final isDateField = _isDateField(label);
    final accountField = label.endsWith('Account');
    final options = _optionsFor(field);
    if (field.checkbox) {
      return Row(
        children: [
          AccountingLeadingCheckbox(
            undividedRow: true,
            checkboxKey: ValueKey('design-field-$label'),
            value: _values[label] == true,
            onChanged: (value) => setState(() {
              final previous = _values[label];
              _values[label] = value ?? false;
              _applyOwnerUpdates(
                widget.selectionValueUpdates?.call(
                  label,
                  previous,
                  Map.unmodifiable(_values),
                ),
              );
            }),
            semanticLabel: label,
          ),
          Expanded(
            child: accountingFieldLabel(context, label, alignToField: true),
          ),
        ],
      );
    }
    if (field.toggle) {
      return AccountingSwitchListTile(
        key: ValueKey('design-field-$label'),
        compact: _isSettingsForm,
        title: accountingFieldLabel(context, label, alignToField: true),
        value: label == 'Preserve Original Files' || _values[label] == true,
        onChanged: label == 'Preserve Original Files'
            ? null
            : (value) => setState(() {
                _values[label] = value;
                _savedSettings = false;
                if (_form.title == 'Sales Preferences' ||
                    _form.title == 'Purchase Preferences') {
                  if (label == 'Show Rate' && value) {
                    _values['Show Quantity'] = true;
                  }
                  if (label == 'Show Quantity' && !value) {
                    _values['Show Rate'] = false;
                  }
                }
                if (_form.title == 'Purchase Preferences') {
                  if (label == 'Link To Customer' && !value) {
                    _values['Billable Expenses'] = false;
                  }
                  if (label == 'Billable Expenses' && value) {
                    _values['Link To Customer'] = true;
                  }
                }
              }),
      );
    }
    return Column(
      key:
          _ordinaryPopupLayout &&
              !field.multiline &&
              !field.fullWidth &&
              !field.customLayout &&
              (!_isMoneyField(field) || field.monetary)
          ? _ordinaryFieldKeys.putIfAbsent(
              label,
              () => GlobalKey(debugLabel: 'ordinary-${_form.title}:$label'),
            )
          : null,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_receivePaymentProposal && label == 'Memo') ...[
          _receivePaymentAllocations(),
          const SizedBox(height: AccountingResponsive.groupGap),
        ],
        accountingFieldLabel(
          context,
          '${_displayLabel(label)}${_ordinaryPopupLayout && _isMoneyField(field) && !_receivePaymentProposal ? ' (${CurrencyPresentation.fromCode(_fieldMoneyCurrencyCode(field)).amountSymbol})' : ''}${field.required ? ' *' : ''}',
          alignToField: true,
          key:
              _quotationValidityProposal &&
                  label == 'Validity' &&
                  _quotationValidityChoice != 'Custom'
              ? const ValueKey('quotation-valid-until')
              : null,
          guidance:
              _quotationValidityProposal &&
                  label == 'Validity' &&
                  _quotationValidityChoice != 'Custom'
              ? 'Choose the quotation validity. Valid until: ${_values['Expiry Date'] ?? ''}'
              : null,
        ),
        const SizedBox(height: accountingFieldLabelGap),
        if (label == 'Business Logo')
          DropTarget(
            onDragEntered: (_) => setState(() => _logoDragOver = true),
            onDragExited: (_) => setState(() => _logoDragOver = false),
            onDragDone: (details) {
              if (details.files.isNotEmpty) {
                setState(() => _logoDragOver = false);
                _editLogo(
                  details.files.first.name,
                  details.files.first.readAsBytes,
                );
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_logoPreview != null) ...[
                  Image.memory(
                    _logoPreview!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    semanticLabel: 'Business logo preview',
                  ),
                  const SizedBox(height: 12),
                ],
                AccountingAttachmentDropzone(
                  surfaceKey: const ValueKey('design-business-logo-dropzone'),
                  actionKey: const ValueKey('design-business-logo'),
                  dragOver: _logoDragOver,
                  onChoose: _chooseLogo,
                  prompt: 'Drop logo here or choose files',
                  formats: _values[label] as String? ?? 'JPEG, PNG, or HEIC.',
                ),
              ],
            ),
          )
        else if (options.isNotEmpty ||
            accountField ||
            field.choiceLabels != null)
          AccountingSelector<String>(
            triggerKey: ValueKey('design-field-$label'),
            options: _selectorOptions(field),
            value: _values[label] as String?,
            onChanged: (value) => setState(() {
              _selectField(label, value);
              _savedSettings = false;
              if (label == 'Country') {
                // A country change intentionally clears the old region even
                // when preference updates preserve other section fields.
                _values['State / Region'] = '';
                _controllers.remove('State / Region')?.dispose();
              }
              _refreshRequiredReviewWarning();
            }),
            hintText: 'Select ${_displayLabel(label)}',
            alwaysSearchable: label == 'Payee' && widget.onSearchPayees != null,
            onQueryChanged: label == 'Payee' && widget.onSearchPayees != null
                ? (query) => unawaited(_searchRegisteredPayees(query))
                : null,
            errorText: label == 'Payee' ? _payeeLookupError : null,
            menuWidth: 300,
            assignedWidth: assignedWidth,
          )
        else
          Builder(
            builder: (context) {
              if (field.multiline) {
                return AccountingDescriptionField(
                  onEscape: widget.embedded ? null : _handleClose,
                  role: field.descriptionRole,
                  key: ValueKey('design-field-$label'),
                  controller: _controllers.putIfAbsent(
                    label,
                    () => TextEditingController(
                      text: _values[label] as String? ?? '',
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _values[label] = value;
                    _savedSettings = false;
                    _refreshRequiredReviewWarning();
                  }),
                );
              }
              final input = TextFormField(
                key: ValueKey('design-field-$label'),
                readOnly: label == 'Payment Not Applied',
                controller: _controllers.putIfAbsent(
                  label,
                  () => TextEditingController(
                    text: _isMoneyField(field)
                        ? formatAccountingMoneyInputText(
                            _values[label] as String? ?? '',
                            Currency.parse(_fieldMoneyCurrencyCode(field))
                                .fractionDigits,
                          )
                        : _values[label] as String? ?? '',
                  ),
                ),
                maxLines: 1,
                style: field.customLayout && _isMoneyField(field)
                    ? AccountingTypography.controlValue(context)
                    : null,
                textAlign: field.customLayout && _isMoneyField(field)
                    ? TextAlign.right
                    : TextAlign.start,
                keyboardType: _isMoneyField(field)
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : null,
                enableInteractiveSelection: true,
                inputFormatters: isDateField
                    ? const [DateInputFormatter()]
                    : _isMoneyField(field)
                    ? [
                        AccountingMoneyInputFormatter(
                          Currency.parse(_fieldMoneyCurrencyCode(field))
                              .fractionDigits,
                        ),
                      ]
                    : null,
                onChanged: (value) => setState(() {
                  _values[label] = value;
                  if (_quotationValidityProposal) {
                    if (label == 'Expiry Date') _values['Validity'] = 'Custom';
                    if (label == 'Date') _syncQuotationExpiry();
                  }
                  _savedSettings = false;
                  _refreshRequiredReviewWarning();
                }),
                decoration:
                    accountingSingleLineInputDecoration(
                      context,
                      prefixText: _amountPrefix(field),
                      hintText: _isMoneyField(field)
                          ? formatAccountingInputAmount(
                              Money.zero(_fieldMoneyCurrencyCode(field)),
                            )
                          : null,
                    ).copyWith(
                      suffixIcon: isDateField
                          ? accountingCalendarButton(
                              context,
                              controller: _controllers[label]!,
                              label: label,
                              firstDate: widget.firstDate,
                              lastDate: widget.lastDate,
                              onPicked: () => setState(() {
                                _values[label] = _controllers[label]!.text;
                                if (_quotationValidityProposal) {
                                  if (label == 'Expiry Date') {
                                    _values['Validity'] = 'Custom';
                                  }
                                  if (label == 'Date') _syncQuotationExpiry();
                                }
                                _savedSettings = false;
                                _refreshRequiredReviewWarning();
                              }),
                            )
                          : null,
                    ),
              );
              return isDateField
                  ? accountingDateFieldFrame(child: input)
                  : input;
            },
          ),
        if (widget.fieldActionLabels.containsKey(label) &&
            widget.fieldActionUpdates != null) ...[
          const SizedBox(height: accountingFieldLabelGap),
          AccountingButton.ghost(
            context,
            key: ValueKey('design-field-action-$label'),
            onPressed: () => setState(() {
              _applyOwnerUpdates(
                widget.fieldActionUpdates!(label, Map.unmodifiable(_values)),
              );
            }),
            child: Text(widget.fieldActionLabels[label]!),
          ),
        ],
        if (const {
              'Transfers',
              'Deposits',
              'Cheques',
              'Credit Card Payments',
              'Credit Card Credits',
            }.contains(_form.title) &&
            const [
              'From Account',
              'To Account',
              'Deposit Account',
              'Bank Account',
              'Credit Card Account',
              'Funding Bank Account',
            ].contains(label) &&
            '${_values[label] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: accountingFieldLabelGap),
          accountingHelperText(
            context,
            widget.accountBalances[_values[label]] == null
                ? 'Balance unavailable'
                : 'Balance: ${formatAccountingMoney(context, widget.accountBalances[_values[label]]!)}',
          ),
        ],
        if (const {
              'Transfers',
              'Deposits',
              'Credit Card Credits',
            }.contains(_form.title) &&
            label == 'Make Recurring' &&
            _values[label] == 'Unscheduled') ...[
          const SizedBox(height: accountingFieldLabelGap),
          accountingHelperText(
            context,
            'Unscheduled templates have no timetable.',
          ),
        ],
        if (widget.embedded &&
            !(widget.embedded && _ordinaryPopupLayout) &&
            (_values[label] == 'Days After Issue' ||
                _values[label] == 'Day Of Month')) ...[
          const SizedBox(height: 12),
          _field(
            DesignField(
              _values[label] == 'Days After Issue'
                  ? 'Number Of Days'
                  : 'Monthly Due Day',
            ),
          ),
          if (_values[label] == 'Day Of Month') ...[
            const SizedBox(height: 12),
            _field(const DesignField('Rollover Within Days')),
          ],
        ],
      ],
    );
  }

  // Card Credit templates replace transaction date/reference with timing. Keep
  // the underlying draft values so cancelling template mode restores them.
  List<DesignField> _cardCreditTemplateFields(List<DesignField> fields) {
    if (_form.title != 'Credit Card Credits' ||
        !const {
          'Scheduled',
          'Reminder',
          'Unscheduled',
        }.contains(_values['Make Recurring'])) {
      return fields;
    }
    return fields
        .where(
          (field) => !const {'Payment Date', 'Reference'}.contains(field.label),
        )
        .toList();
  }

  List<DesignField> _transferFields(List<DesignField> fields) {
    fields = _cardCreditTemplateFields(fields);
    if (!const {
          'Transfers',
          'Deposits',
          'Credit Card Credits',
        }.contains(_form.title) ||
        fields.any((field) => field.label == 'Template Name')) {
      return fields;
    }
    final type = _values['Make Recurring'];
    final timed = const ['Scheduled', 'Reminder'].contains(type);
    final interval = _values['Interval'];
    return [
      for (final field in fields) ...[
        field,
        if (field.label == 'Make Recurring' &&
            type != null &&
            type != 'No') ...[
          const DesignField('Template Name', required: true),
          if (timed) ...[
            DesignField(
              type == 'Scheduled' ? 'Days In Advance' : 'Days Before',
              required: true,
            ),
            const DesignField(
              'Interval',
              options: ['Daily', 'Weekly', 'Monthly', 'Yearly'],
            ),
            if (interval != 'Yearly')
              const DesignField('Every', required: true),
            if (interval == 'Monthly')
              const DesignField(
                'Week Of Month',
                options: ['Day', 'First', 'Second', 'Third', 'Fourth', 'Last'],
              ),
            if (interval == 'Weekly' ||
                interval == 'Monthly' && _values['Week Of Month'] != 'Day')
              const DesignField(
                'Day Of Week',
                options: [
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                  'Sunday',
                ],
              ),
            if (interval == 'Yearly')
              const DesignField(
                'Month Of Year',
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
            if (interval == 'Yearly' ||
                interval == 'Monthly' && _values['Week Of Month'] == 'Day')
              DesignField(
                'Day Of Month',
                options: [for (var i = 1; i <= 28; i++) '$i', 'Last'],
              ),
            const DesignField('Start Date', required: true),
            const DesignField('End', options: ['None', 'By', 'After']),
            if (_values['End'] == 'By')
              const DesignField('End Date', required: true),
            if (_values['End'] == 'After')
              const DesignField('Occurrences', required: true),
          ],
        ],
      ],
    ];
  }

  List<DesignField> _receivePaymentFields(List<DesignField> fields) {
    if (!_receivePaymentProposal) return fields;
    return [
      for (final label in const [
        'Counterparty',
        'Payment Date',
        'Payment Method',
        'Reference',
        'Payment Account',
        'Amount',
        'Memo',
      ])
        ...fields.where((field) => field.label == label),
    ];
  }

  Widget _receivePaymentAllocations({bool readOnly = false}) {
    final currency = _moneyCurrencyCode();
    final symbol = CurrencyPresentation.fromCode(currency).amountSymbol;
    int? minor(Object? value) {
      final text = '${value ?? ''}'.trim();
      if (text.isEmpty) return 0;
      try {
        return Money.fromDecimal(text, currency).minorUnits;
      } on FormatException {
        return null;
      }
    }

    String number(int amount) =>
        formatAccountingInputAmount(Money.fromMinor(amount, currency));
    final received = minor(_values['Amount']);
    final examples = _values['_receiptExamples'] == true;
    final selected =
        (_values['_receiptSelected'] as List?)?.cast<int>().toSet() ?? <int>{};
    const balances = [60000, 40000];
    final payments = [
      for (var i = 0; i < 2; i++)
        selected.contains(i) ? minor(_values['_receiptAllocation$i']) : 0,
    ];
    final applied = payments.fold<int>(0, (sum, value) => sum + (value ?? 0));
    final valid =
        received != null &&
        received >= 0 &&
        payments.every((amount) => amount != null && amount >= 0) &&
        applied <= received &&
        [for (var i = 0; i < 2; i++) (payments[i] ?? 0) <= balances[i]]
            .every((value) => value);
    final capacity =
        selected.fold<int>(0, (sum, i) => sum + balances[i]) - applied;
    final credit = examples && _values['_receiptCredit'] == true && valid
        ? math.min(10000, math.max(0, capacity))
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Outstanding Invoices',
          style: AccountingTypography.sectionTitle(context),
        ),
        const SizedBox(height: accountingFieldLabelGap),
        if (!examples)
          AccountingButton.outline(
            context,
            key: const ValueKey('receipt-example-records'),
            onPressed: () => setState(() => _values['_receiptExamples'] = true),
            child: const Text('Try Example Records'),
          )
        else ...[
          accountingHelperText(
            context,
            'Example records only; no live payment is recorded.',
          ),
          const SizedBox(height: AccountingResponsive.groupGap),
          for (var i = 0; i < 2; i++) ...[
            AccountingSwitchListTile(
              key: ValueKey('receipt-select-invoice-$i'),
              title: Text('Invoice DEMO-00${i + 1}'),
              value: selected.contains(i),
              onChanged: readOnly
                  ? null
                  : (checked) => setState(() {
                      if (checked) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                      _values['_receiptSelected'] = selected.toList();
                      final remaining = math.max(0, (received ?? 0) - applied);
                      final amount = checked
                          ? math.min(balances[i], remaining)
                          : 0;
                      _values['_receiptAllocation$i'] = number(amount);
                      _controllers['receipt-allocation-$i']?.text = number(
                        amount,
                      );
                    }),
            ),
            AccountingInformationRows(
              rows: [('Open Balance ($symbol)', number(balances[i]))],
            ),
            const SizedBox(height: accountingFieldLabelGap),
            accountingFieldLabel(
              context,
              'Payment ($symbol)',
              alignToField: true,
            ),
            const SizedBox(height: accountingFieldLabelGap),
            TextFormField(
              key: ValueKey('receipt-allocation-$i'),
              enabled: !readOnly && selected.contains(i),
              controller: _controllers.putIfAbsent(
                'receipt-allocation-$i',
                () => TextEditingController(
                  text: '${_values['_receiptAllocation$i'] ?? '0.00'}',
                ),
              ),
              inputFormatters: const [AccountingMoneyInputFormatter(2)],
              decoration: accountingSingleLineInputDecoration(context),
              onChanged: (value) =>
                  setState(() => _values['_receiptAllocation$i'] = value),
            ),
            const SizedBox(height: AccountingResponsive.groupGap),
          ],
          Text(
            'Available Credits',
            style: AccountingTypography.sectionTitle(context),
          ),
          AccountingSwitchListTile(
            key: const ValueKey('receipt-select-credit'),
            title: Text('Credit Note DEMO-001 ($symbol 100.00)'),
            value: _values['_receiptCredit'] == true,
            onChanged: readOnly
                ? null
                : (value) => setState(() => _values['_receiptCredit'] = value),
          ),
        ],
        const SizedBox(height: AccountingResponsive.groupGap),
        Text(
          'Payment Summary ($symbol)',
          style: AccountingTypography.sectionTitle(context),
        ),
        AccountingInformationRows(
          rows: [
            ('Payment Applied', valid ? number(applied) : 'Check Amounts'),
            ('Credits Applied', valid ? number(credit) : 'Check Amounts'),
            (
              'Unapplied Payment',
              valid ? number(received - applied) : 'Check Amounts',
            ),
          ],
        ),
        if (!valid)
          accountingHelperText(
            context,
            'Allocate no more than the payment received or each invoice balance.',
          ),
      ],
    );
  }

  double _minimumFieldWidth(DesignField field) {
    if (_isMoneyField(field)) {
      final currency = _fieldMoneyCurrencyCode(field);
      final title =
          '${_displayLabel(field.label)} (${CurrencyPresentation.fromCode(currency).amountSymbol})${field.required ? ' *' : ''}';
      final measured = AccountingTransactionGridTokens.numericWidth(
        context,
        'Amount',
        // These are independent form fields. Entered-value growth belongs to
        // addable transaction columns, not ordinary one/two-field tracks.
        const [],
        title: field.customLayout ? null : title,
      );
      if (!field.customLayout) return measured;
      // The outlined input has two painted borders outside its digit insets.
      // Keep the heading floor independent, so a title-held width stays exact.
      final border = accountingSingleLineInputDecoration(context)
          .enabledBorder!
          .borderSide
          .width;
      return math.max(
        measured + border * 2,
        AccountingTransactionGridTokens.fieldTitleWidth(context, title),
      );
    }
    final labelWidth = accountingFieldLabelMinimumWidth(
      context,
      '${_displayLabel(field.label)}${field.required ? ' *' : ''}',
    );
    final options = _selectorOptions(field);
    final selected = options.any(
      (option) => option.value == _values[field.label],
    );
    final plainWidth = _isDateField(field.label)
        ? math.max(
            accountingCompactDateFieldWidth,
            AccountingResponsive.measuredTextWidth(
                  context,
                  '${_values[field.label] ?? '00-00-0000'}',
                  AccountingTypography.controlValue(context),
                ) +
                accountingContentInset * 2 +
                accountingControlHeight +
                2,
          )
        : math.max(
                AccountingResponsive.measuredTextWidth(
                  context,
                  '0000000000',
                  AccountingTypography.controlValue(context),
                ),
                _ordinaryPopupLayout &&
                        !field.multiline &&
                        !field.fullWidth &&
                        !field.customLayout &&
                        !_isMoneyField(field)
                    ? AccountingResponsive.measuredTextWidth(
                        context,
                        '${_values[field.label] ?? ''}',
                        AccountingTypography.controlValue(context),
                      )
                    : 0,
              ) +
              // Match the painted outlined-input inset used by the shared
              // ordinary adapter, including its four extra pixels per side.
              accountingContentInset * 2 +
              2;
    final valueWidth =
        options.isEmpty &&
            !field.label.endsWith('Account') &&
            field.choiceLabels == null
        ? plainWidth
        : accountingSelectorMinimumWidth(context, [
            if (!selected)
              accountingSelectorHintText(
                'Select ${_displayLabel(field.label)}',
              ),
            ...options.map((option) => option.label),
          ]);
    return labelWidth > valueWidth ? labelWidth : valueWidth;
  }

  Widget _fields(
    List<DesignField> fields,
    double width, {
    bool allowTrial = true,
  }) {
    fields = _receivePaymentFields(_transferFields(fields));
    fields = [
      for (final field in _quotationValidityFields(fields)) ...[
        if (field.descriptionRole == AccountingDescriptionRole.memo &&
            _customInformationActive)
          DesignField(
            _memoKey,
            multiline: true,
            descriptionRole: _customInformationRole,
          )
        else
          field,
        if (_ordinaryPopupLayout && field.label == 'Payment Terms') ...[
          if (_values[field.label] == 'Days After Issue' &&
              !fields.any((f) => f.label == 'Number Of Days'))
            const DesignField('Number Of Days'),
          if (_values[field.label] == 'Day Of Month') ...[
            if (!fields.any((f) => f.label == 'Monthly Due Day'))
              DesignField(
                'Monthly Due Day',
                options: List.generate(31, (index) => '${index + 1}'),
              ),
            if (!fields.any((f) => f.label == 'Rollover Within Days'))
              const DesignField('Rollover Within Days'),
          ],
        ],
        if (field.label == 'Payment Terms' &&
            _values['Payment Terms'] == 'Custom' &&
            !fields.any((f) => f.label == 'Custom Payment Terms') &&
            !_form.fields.any(
              (f) => f.descriptionRole == AccountingDescriptionRole.memo,
            ))
          const DesignField(
            'Custom Payment Terms',
            multiline: true,
            required: true,
            descriptionRole: AccountingDescriptionRole.paymentTerms,
          ),
      ],
    ];
    // Reviewed popout proposal only: Terms own payment timing; no second
    // Due Date picker. Existing saved facts and all embedded owners stay intact.
    if (!widget.embedded &&
        _form.lines &&
        trialOrdinaryGroups.containsKey(_form.title)) {
      fields = fields.where((field) => field.label != 'Due Date').toList();
    }
    final two = AccountingResponsive.fitsWithContentGap(width, const [
      AccountingResponsive.fieldMinWidth,
      AccountingResponsive.fieldMinWidth,
    ]);
    final fieldWidth = two
        ? (width - AccountingResponsive.groupGap) / 2
        : width;
    fields = fields
        .where(
          (field) =>
              // Location is an optional branch tag, not a normal invoice input.
              // Existing tags remain editable and are never cleared by hiding
              // the unused field on a new transaction.
              (field.label != 'Custom Term Value' ||
                  const ['Days After Issue', 'Day Of Month'].contains(
                    _values[_form.title == 'Purchase Preferences'
                        ? 'Default Bill Terms'
                        : 'Default Payment Terms'],
                  )) &&
              (field.label != 'Approval Threshold' ||
                  _values['Transaction Approval'] == 'Above Threshold') &&
              (!const ['From Date', 'Through Date'].contains(field.label) ||
                  _form.title != 'Backup & Export Preferences' ||
                  _values['Date Range'] == 'Custom') &&
              (field.label != 'Location' ||
                  '${widget.initial?['Location'] ?? ''}'.trim().isNotEmpty) &&
              (!const [
                    'Country Name',
                    'Country ISO Code',
                  ].contains(field.label) ||
                  _values['Country'] == 'Other Country') &&
              (!const [
                    'Identification Type',
                    'Identification Number',
                    'TIN',
                    'SST Registration Number',
                  ].contains(field.label) ||
                  !_form.fields.any((f) => f.label == 'Tax Details Needed') ||
                  _values['Tax Details Needed'] == true),
        )
        .toList();
    List<String>? trialLabels;
    if (allowTrial && _ordinaryPopupLayout) {
      final run = <DesignField>[];
      for (final field in fields) {
        final ordinary =
            !field.multiline &&
            !field.toggle &&
            !field.checkbox &&
            !field.fullWidth &&
            !field.customLayout &&
            (!_isMoneyField(field) || field.monetary);
        if (ordinary) {
          run.add(field);
        } else if (run.isNotEmpty) {
          break;
        }
      }
      if (run.isNotEmpty) trialLabels = run.map((f) => f.label).toList();
    }
    final groupLabels = trialLabels;
    if (groupLabels != null &&
        fields.any((field) => field.label == groupLabels.first) &&
        fields.any((field) => field.label == groupLabels.last)) {
      final trialFields = [
        for (final label in groupLabels)
          if (fields.any((field) => field.label == label))
            fields.firstWhere((f) => f.label == label),
      ];
      final groupStart = fields.indexOf(trialFields.first);
      final prefix = fields.take(groupStart).toList();
      final suffix = fields.skip(groupStart + trialFields.length).toList();
      final trialMinima = [
        for (final field in trialFields)
          math.max(
            _minimumFieldWidth(field),
            (width - AccountingResponsive.groupGap) * field.minimumRowFraction,
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prefix.isNotEmpty) ...[
            _fields(prefix, width),
            const SizedBox(height: AccountingResponsive.groupGap),
          ],
          AccountingOrdinaryFieldRows(
            width: width,
            minima: trialMinima,
            maximumFieldsPerRow:
                !widget.embedded &&
                    !_form.lines &&
                    widget.widthFamily == AccountingPopoutWidthFamily.normal
                ? 2
                : 4,
            threeOrMoreFieldMinima: [
              for (final field in trialFields)
                if (field.monetary)
                  AccountingResponsive.measuredTextWidth(
                        context,
                        _controllers[field.label]?.text ??
                            formatAccountingMoneyInputText(
                              _values[field.label] as String? ?? '',
                              Currency.parse(_fieldMoneyCurrencyCode(field))
                                  .fractionDigits,
                            ),
                        Theme.of(context).textTheme.bodyLarge,
                      ) +
                      accountingContentInset * 2 +
                      // Ordinary inputs inherit bodyLarge, and RenderEditable
                      // reserves its default caret plus a one-pixel gap.
                      const TextField().cursorWidth +
                      1
                else
                  null,
            ],
            preferEqual: true,
            fieldBuilder: (index, assigned) =>
                _field(trialFields[index], assignedWidth: assigned),
          ),
          if (suffix.isNotEmpty)
            const SizedBox(height: AccountingResponsive.groupGap),
          if (suffix.isNotEmpty) _fields(suffix, width),
        ],
      );
    }
    final switches = _isSettingsForm
        ? fields.where((field) => field.toggle).toList()
        : <DesignField>[];
    if (_isSettingsForm) {
      fields = fields.where((field) => !field.toggle).toList();
    }
    final consumed = <String>{};
    const pairs = <String, List<String>>{
      'Currency': ['Tax Mode'],
      'Payment Terms': ['Class'],
      'Due Date': ['Tax Mode'],
      'Effective From': ['Effective Through'],
      'Period From': ['Period Through'],
    };
    final children = <Widget>[];
    for (final field in fields) {
      if (consumed.contains(field.label)) continue;
      final partner = fields
          .where(
            (f) =>
                !consumed.contains(f.label) &&
                (pairs[field.label]?.contains(f.label) ?? false),
          )
          .firstOrNull;
      final first = _minimumFieldWidth(field);
      final second = partner == null ? 0.0 : _minimumFieldWidth(partner);
      final fits =
          partner != null &&
          first + second + AccountingResponsive.groupGap <= fieldWidth;
      if (fits) {
        consumed.add(partner.label);
        final extra =
            (fieldWidth - first - second - AccountingResponsive.groupGap) / 2;
        children.add(
          SizedBox(
            width: fieldWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: first + extra,
                  child: _field(field, assignedWidth: first + extra),
                ),
                const SizedBox(width: AccountingResponsive.groupGap),
                SizedBox(
                  width: second + extra,
                  child: _field(partner, assignedWidth: second + extra),
                ),
              ],
            ),
          ),
        );
      } else {
        // A long choice occupies a whole row before its label is clipped.
        final assigned =
            field.multiline || field.fullWidth || first > fieldWidth
            ? width
            : fieldWidth;
        children.add(
          SizedBox(
            width: assigned,
            child: _field(field, assignedWidth: assigned),
          ),
        );
      }
    }
    final inputs = Wrap(
      spacing: AccountingResponsive.groupGap,
      runSpacing: AccountingResponsive.groupGap,
      children: children,
    );
    if (switches.isEmpty) return inputs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (children.isNotEmpty) ...[
          inputs,
          const SizedBox(height: AccountingResponsive.groupGap),
        ],
        // Compact rows already contain the 20px visual gap. Adding another
        // spacer here would count their unpainted native target margins twice.
        Wrap(
          key: ValueKey('settings-switches-${_form.title}'),
          spacing: AccountingResponsive.groupGap,
          children: [
            for (final field in switches)
              SizedBox(
                width: fieldWidth,
                child: _field(field, assignedWidth: fieldWidth),
              ),
          ],
        ),
      ],
    );
  }

  Widget _transactionHeader(double width) => LayoutBuilder(
    builder: (context, constraints) =>
        _transactionHeaderFields(math.min(width, constraints.maxWidth)),
  );

  Widget _transactionHeaderFields(double width) {
    final fields =
        _cardCreditTemplateFields(_quotationValidityFields(_form.fields))
            .where(
              (f) =>
                  !const {'Class', 'Memo'}.contains(f.label) &&
                  !(_form.title == 'Deposits' &&
                      f.label.startsWith('Cash Back')) &&
                  (!_salesReceiptCatalogue ||
                      !const {
                        'Receipt Message',
                        'Statement Message',
                      }.contains(f.label)) &&
                  (!_documentTaxFamily || f.label != 'Tax Mode'),
            )
            .toList();
    final compactLabels = [
      _quotationValidityProposal ? 'Validity' : 'Payment Terms',
      'Currency',
      'Tax Mode',
    ];
    final compact = [
      for (final label in compactLabels) ...[
        ...fields.where((f) => f.label == label),
        if (_ordinaryPopupLayout && label == 'Payment Terms') ...[
          if (_values[label] == 'Days After Issue')
            const DesignField('Number Of Days'),
          if (_values[label] == 'Day Of Month') ...[
            DesignField(
              'Monthly Due Day',
              options: List.generate(31, (index) => '${index + 1}'),
            ),
            const DesignField('Rollover Within Days'),
          ],
        ],
      ],
      if (_bankingLineTaxFamily)
        ...fields.where((field) => field.label == 'Make Recurring'),
      if (_form.recurring)
        const DesignField(
          'Make Recurring',
          options: ['No', 'Monthly', 'Quarterly', 'Yearly', 'Custom'],
        ),
    ];
    final other = fields
        .where(
          (f) =>
              !compactLabels.contains(f.label) &&
              !(_bankingLineTaxFamily && f.label == 'Make Recurring'),
        )
        .toList();
    if (_documentTaxFamily) compact.add(const DesignField('Tax'));
    final minimums = [
      for (final field in compact)
        if (_documentTaxFamily && field.label == 'Tax')
          _documentTaxMinimumWidth
        else if (compact.length >= 3 && field.options.isNotEmpty)
          _fittingSelectorWidth(field)
        else
          _minimumFieldWidth(field),
    ];
    final required =
        minimums.fold(0.0, (a, b) => a + b) +
        AccountingResponsive.groupGap * math.max(0, compact.length - 1);
    final extra = compact.isEmpty
        ? 0.0
        : math.max(0.0, width - required) / compact.length;
    final trialWidths = !widget.embedded
        ? [
            for (final row in trialRows(width, minimums, preferEqual: true))
              ...row.widths,
          ]
        : [for (final value in minimums) value + extra];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fields(other, width),
        if (compact.isNotEmpty) ...[
          const SizedBox(height: AccountingResponsive.groupGap),
          Wrap(
            spacing: AccountingResponsive.groupGap,
            runSpacing: AccountingResponsive.groupGap,
            children: [
              for (var i = 0; i < compact.length; i++)
                SizedBox(
                  width: trialWidths[i],
                  child: _documentTaxFamily && compact[i].label == 'Tax'
                      ? _documentTaxEditor(trialWidths[i], compact: true)
                      : compact[i].label == 'Make Recurring' &&
                            !_bankingLineTaxFamily
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            accountingFieldLabel(
                              context,
                              'Make Recurring',
                              alignToField: true,
                              guidance: _recurrenceLocked
                                  ? 'Manage the saved schedule in Recurring.'
                                  : null,
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            AccountingSelector<String>(
                              triggerKey: const ValueKey(
                                'design-field-Make Recurring',
                              ),
                              hintText: 'Make Recurring',
                              value: _recurrenceFrequency,
                              assignedWidth: trialWidths[i],
                              enabled: !_committing && !_recurrenceLocked,
                              options: [
                                for (final value in compact[i].options)
                                  AccountingSelectorOption(
                                    value: value,
                                    label: value,
                                  ),
                              ],
                              onChanged: (value) => setState(() {
                                _values['Make Recurring'] = value ?? 'No';
                                _recurring = value != null && value != 'No';
                                _values.putIfAbsent(
                                  'Start Date',
                                  () => _values['Date'] ?? _today,
                                );
                                _values.putIfAbsent(
                                  'End Condition',
                                  () => 'No End Date',
                                );
                                _values.putIfAbsent('Every', () => '1');
                                _values.putIfAbsent(
                                  'Interval Unit',
                                  () => 'Months',
                                );
                                _values.putIfAbsent(
                                  'Preserve Month End',
                                  () => true,
                                );
                              }),
                            ),
                          ],
                        )
                      : _field(compact[i], assignedWidth: trialWidths[i]),
                ),
            ],
          ),
        ],

        if (_bankingLineTaxFamily && _values['Make Recurring'] != 'No') ...[
          const SizedBox(height: AccountingResponsive.groupGap),
          _fields(
            _transferFields(const [DesignField('Make Recurring')])
                .where((field) => field.label != 'Make Recurring')
                .toList(),
            width,
          ),
        ],
        if (_form.recurring && _recurring && !_recurrenceLocked) ...[
          const SizedBox(height: AccountingResponsive.groupGap),
          _fields([
            if (_recurrenceFrequency == 'Custom') ...[
              const DesignField('Every', required: true),
              const DesignField(
                'Interval Unit',
                options: ['Days', 'Weeks', 'Months', 'Years'],
                required: true,
              ),
            ],
            const DesignField('Start Date', required: true),
            const DesignField(
              'End Condition',
              options: ['No End Date', 'On Date', 'After Occurrences'],
            ),
            if (_values['End Condition'] == 'On Date')
              const DesignField('End Date', required: true),
            if (_values['End Condition'] == 'After Occurrences')
              const DesignField('Occurrence Count', required: true),
            const DesignField('Preserve Month End', toggle: true),
          ], width),
        ],
      ],
    );
  }

  Map<String, String> get _documentTaxLabels {
    final current = _documentTaxChoice;
    final date =
        parseAccountingInputDate('${_values['Date'] ?? ''}') ?? DateTime.now();
    final available = {
      '0': 'No Tax',
      for (final code
          in widget.settingsWorkspace?.taxRates ?? <CompanyTaxRate>[])
        if (code.applies(date, TaxApplication.sales)) code.choice: code.label,
    };
    final savedLabels = _values['_savedTaxCodeLabels'] as Map? ?? const {};
    final labels = {...available};
    if (current != null && !labels.containsKey(current)) {
      labels[current] =
          savedLabels[current] as String? ??
          _form.lineChoiceLabels['Tax Rate (%)']?[current] ??
          'Saved rate · ${taxPercent(current)}%';
    }
    return labels;
  }

  double get _documentTaxMinimumWidth =>
      accountingSelectorMinimumWidth(context, [
        'No Tax',
        if (_documentTaxChoice == null) 'Saved taxes · Review',
        ..._documentTaxLabels.values,
      ]);

  double _fittingSelectorWidth(DesignField field) {
    final options = _selectorOptions(field);
    final selected =
        field.label == 'Make Recurring' ||
        options.any((option) => option.value == _values[field.label]);
    return accountingSelectorMinimumWidth(context, [
      if (!selected)
        accountingSelectorHintText('Select ${_displayLabel(field.label)}'),
      ...options.map((option) => option.label),
    ]);
  }

  String get _documentTaxExplanation {
    final basis = '${_values['Tax Mode'] ?? ''}';
    return _documentTaxChoice == null
        ? 'Saved line taxes are retained. Choose one tax before saving new items or replacing their tax.'
        : 'Amounts are ${basis.isEmpty ? 'unresolved' : basis.toLowerCase()}. Tax applies to every item.';
  }

  Widget _documentTaxEditor(double width, {bool compact = false}) {
    final current = _documentTaxChoice;
    final labels = _documentTaxLabels;
    final mixed = current == null;
    final basis = '${_values['Tax Mode'] ?? ''}';
    final fieldWidth = compact
        ? width
        : width >=
              2 * AccountingResponsive.fieldMinWidth +
                  AccountingResponsive.groupGap
        ? (width - AccountingResponsive.groupGap) / 2
        : width;
    return Padding(
      padding: EdgeInsets.only(
        top: compact ? 0 : AccountingResponsive.groupGap,
      ),
      child: SizedBox(
        width: fieldWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            accountingFieldLabel(
              context,
              'Tax',
              alignToField: true,
              guidance: _documentTaxExplanation,
            ),
            const SizedBox(height: accountingFieldLabelGap),
            AccountingSelector<String>(
              assignedWidth: fieldWidth,
              triggerKey: const ValueKey('design-document-tax'),
              hintText: 'No Tax',
              value: mixed ? '__saved_tax__' : current,
              options: [
                if (mixed)
                  const AccountingSelectorOption(
                    value: '__saved_tax__',
                    label: 'Saved taxes · Review',
                  ),
                for (final entry in labels.entries)
                  AccountingSelectorOption(
                    value: entry.key,
                    label: entry.value,
                    preserveLabelCase: true,
                  ),
              ],
              onChanged: (choice) {
                if (choice == null || choice == '__saved_tax__') return;
                setState(() {
                  for (final line in _lines) {
                    line['Tax Rate (%)'] = choice;
                  }
                  if (!const {'Exclusive', 'Inclusive'}.contains(basis) &&
                      (choice != '0' ||
                          !const {'Exempt', 'Out Of Scope'}.contains(basis))) {
                    _values['Tax Mode'] = _salesBasisDefault;
                  }
                  _resolvedReviewRows = null;
                  _resolvedReviewDocuments = null;
                  _error = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _attachmentBusy = false;

  Future<void> _convertAttachment(int index) async {
    final original = _attachments[index];
    if (original == null || _attachmentBusy) return;
    setState(() => _attachmentBusy = true);
    try {
      const pipeline = ReceiptDocumentPipeline();
      final decoded = original.status == AttachmentProcessingStatus.queued
          ? await pipeline.process(
              ReceiptAttachmentInput(
                originalId: original.originalId,
                batchId: original.batchId,
                filename: original.filename,
                mimeType: original.originalMimeType,
                bytes: original.originalBytes,
              ),
            )
          : original;
      final converted = decoded.canConvertToPdf
          ? await pipeline.convertToPdf(decoded)
          : decoded;
      if (mounted) setState(() => _attachments[index] = converted);
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachments[index] = original.withFailure(
            'PDF conversion failed. Review the image and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Widget _attachmentRow(int index) {
    final attachment = _attachments[index];
    final busy = _attachmentBusy || _committing;
    final actions = <Widget>[
      AccountingButton.iconOnly(
        context,
        key: ValueKey('preview-supporting-file-$index'),
        onPressed: attachment == null || busy
            ? null
            : () => showAttachmentPreview(context, attachment),
        icon: Icons.visibility_outlined,
        tooltip: 'View Supporting Document',
      ),
      if (attachment != null &&
          attachment.isImage &&
          attachment.originalBytes.isNotEmpty) ...[
        AccountingButton.iconOnly(
          context,
          key: ValueKey('edit-supporting-file-$index'),
          onPressed: busy ? null : () => _openAttachment(index),
          icon: Icons.edit_outlined,
          tooltip: 'Edit Supporting Document',
        ),
        if (attachment.pdfBytes == null)
          AccountingButton.outline(
            context,
            key: ValueKey('convert-supporting-file-$index'),
            onPressed: busy ? null : () => _convertAttachment(index),
            child: const Text('Convert to PDF'),
          ),
      ],
      AccountingButton.iconOnly(
        context,
        key: ValueKey('remove-supporting-file-$index'),
        tooltip: 'Remove Supporting Document',
        icon: Icons.delete_outline,
        onPressed: busy
            ? null
            : () => setState(() {
                _files.removeAt(index);
                _attachments.removeAt(index);
              }),
      ),
    ];
    if (attachment != null) {
      return AccountingAttachmentRecordRow(
        attachment: attachment,
        showProcessingStatus: false,
        actions: actions,
      );
    }
    // Preserve legacy filename-only entries without inventing image evidence.
    return Builder(
      builder: (context) {
        final row = AccountingRecordRow(
          title: _files[index],
          details: const Text('Preview unavailable · filename only'),
          trailing: Wrap(spacing: 8, runSpacing: 8, children: actions),
        );
        return AccountingAttachmentList.isGrouped(context)
            ? row
            : AccountingCard.surface(context, child: row);
      },
    );
  }

  Future<void> _openAttachment(int index) async {
    if (_attachmentBusy) return;
    setState(() => _attachmentBusy = true);
    try {
      await _editAttachment(index);
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _editAttachment(int index) async {
    final original = _attachments[index];
    if (original == null) return;
    if (original.originalBytes.isEmpty) {
      await showAttachmentPreview(context, original);
      return;
    }
    final attachment = original.status == AttachmentProcessingStatus.queued
        ? await const ReceiptDocumentPipeline().process(
            ReceiptAttachmentInput(
              originalId: original.originalId,
              batchId: original.batchId,
              filename: original.filename,
              mimeType: original.originalMimeType,
              bytes: original.originalBytes,
            ),
          )
        : original;
    if (!mounted) return;
    final queue = ReceiptReviewQueue([attachment]);
    await showDialog<void>(
      context: context,
      builder: (_) => ReceiptReviewDialog(
        queue: queue,
        setupKind: widget.attachmentSetupKind,
        destinationDate: parseAccountingInputDate(
          _values['Date'] as String? ?? '',
        ),
        categoryCode: widget.attachmentCategoryCode?.call(_lines) ?? '',
        onSave: (saved) async {
          if (mounted) {
            setState(() {
              _attachments[index] = saved;
              _files[index] = saved.filename;
            });
          }
        },
      ),
    );
    queue.dispose();
  }

  Future<void> _chooseFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        // ignore: deprecated_member_use
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic'],
      );
      final picked = <ReceiptAttachmentInput>[];
      for (final file in result) {
        final extension = file.name.split('.').last.toLowerCase();
        picked.add(
          ReceiptAttachmentInput(
            originalId:
                'preview-${DateTime.now().microsecondsSinceEpoch}-${picked.length}',
            batchId: 'frontend-preview',
            filename: file.name,
            mimeType: extension == 'pdf'
                ? 'application/pdf'
                : extension == 'jpg' || extension == 'jpeg'
                ? 'image/jpeg'
                : 'image/$extension',
            bytes: await file.readAsBytes(),
          ),
        );
      }
      _appendFiles(picked);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The file picker could not be opened.');
      }
    }
  }

  void _appendFiles(List<ReceiptAttachmentInput> files) {
    if (!mounted || files.isEmpty) return;
    final attachments = files.map(ReceiptAttachment.queued).toList();
    setState(() {
      _files.addAll(attachments.map((file) => file.filename));
      _attachments.addAll(attachments);
    });
  }

  Future<void> _onFilesDropped(DropDoneDetails details) async {
    if (mounted) setState(() => _isDragOver = false);
    final picked = <ReceiptAttachmentInput>[];
    for (final file in details.files) {
      if (file is DropItemDirectory) continue;
      final extension = file.name.split('.').last.toLowerCase();
      if (!const {'pdf', 'png', 'jpg', 'jpeg', 'heic'}.contains(extension)) {
        if (mounted) setState(() => _error = 'Choose a PDF or image file.');
        continue;
      }
      final bookmark = file.extraAppleBookmark;
      var accessed = false;
      try {
        if (bookmark != null && bookmark.isNotEmpty) {
          accessed = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        }
        picked.add(
          ReceiptAttachmentInput(
            originalId:
                'preview-${DateTime.now().microsecondsSinceEpoch}-${picked.length}',
            batchId: 'frontend-preview',
            filename: file.name,
            mimeType: extension == 'pdf'
                ? 'application/pdf'
                : extension == 'jpg' || extension == 'jpeg'
                ? 'image/jpeg'
                : 'image/$extension',
            bytes: await file.readAsBytes(),
          ),
        );
      } on Object {
        if (mounted) setState(() => _error = 'Could not read ${file.name}.');
      } finally {
        if (accessed) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark!,
          );
        }
      }
    }
    _appendFiles(picked);
  }

  Future<void> _selectSalesItem(Map<String, String> line, String? value) async {
    if (value == null) return;
    final item = widget.settingsWorkspace?.catalogueItems
        .where((item) => item.id.value == value)
        .firstOrNull;
    if (item == null || !mounted || !_lines.contains(line)) return;
    if (_salesReceiptCatalogue) {
      line.remove('_salesReceiptTaxChoice');
      line.remove('_salesReceiptTaxLabel');
    }
    line.addAll({
      'Product / Service': item.id.value,
      'Description': item.description,
      'Account': item.incomeAccountId.value,
      if (_salesReceiptCatalogue) '_salesReceiptItemName': item.name,
      if (!_documentTaxFamily)
        'Tax Rate (%)': _salesReceiptCatalogue && item.taxRatePercent != '0'
            ? ''
            : item.taxRatePercent,
      '_selectionRevision':
          '${(int.tryParse(line['_selectionRevision'] ?? '') ?? 0) + 1}',
    });
    await _ensureTransactionWidth();
    if (mounted) setState(() {});
  }

  bool get _salesReceiptCatalogue =>
      _form.title == 'Sales Receipts' && _transactionGrid;

  bool get _bankingLineTaxFamily =>
      const {'Deposits', 'Credit Card Credits'}.contains(_form.title);

  bool _bankingLineTaxResolved(Map<String, String> line) {
    if (_values['Tax Mode'] == 'Out Of Scope') return true;
    final value = line['Tax Rate (%)'] ?? '';
    if (value == '0') return true;
    if (!value.contains(':')) return false;
    final date = parseAccountingInputDate(
      '${_values[_form.title == 'Deposits' ? 'Deposit Date' : 'Payment Date'] ?? ''}',
    );
    return date != null &&
        widget.settingsWorkspace!.taxRates.any(
          (code) =>
              code.choice == value &&
              code.applies(
                date,
                _form.title == 'Credit Card Credits'
                    ? TaxApplication.purchases
                    : TaxApplication.sales,
              ),
        );
  }

  bool _salesReceiptLineTaxResolved(Map<String, String> line) {
    final value = line['Tax Rate (%)'] ?? '';
    if (value == '0') return true;
    final workspace = widget.settingsWorkspace!;
    // A stored catalogue percentage does not identify a maintained tax code.
    // Keep historical numeric choices visible, but require explicit selection.
    if (!value.contains(':')) return false;
    final date = parseAccountingInputDate('${_values['Date'] ?? ''}');
    return date != null &&
        workspace.taxRates.any(
          (code) =>
              code.choice == value && code.applies(date, TaxApplication.sales),
        );
  }

  Widget _cardPaymentMemoSummary() {
    final currency = _moneyCurrencyCode();
    String total;
    try {
      final value = '${_values['Amount'] ?? ''}';
      total = formatAccountingMoneyInputText(
        formatAccountingInputAmount(
          Money.fromDecimal(value.isEmpty ? '0' : value, currency),
        ),
        Currency.parse(currency).fractionDigits,
      );
    } on Object {
      total = 'Check Amount';
    }
    return AccountingMemoSummary(
      summaryLabelInset: accountingContentInset,
      rows: [
        (
          'Total Paid (${CurrencyPresentation.fromCode(currency).amountSymbol})',
          total,
        ),
      ],
      memo: (height) => AccountingDescriptionField(
        key: const ValueKey('design-field-Memo'),
        role: AccountingDescriptionRole.memo,
        onEscape: widget.embedded ? null : _handleClose,
        controller: _controllers.putIfAbsent(
          'Memo',
          () => TextEditingController(text: '${_values['Memo'] ?? ''}'),
        ),
        minimumHeight: height,
        fixedHeight: height,
        decoration: accountingInputDecoration(context),
        onChanged: (value) => _values['Memo'] = value,
      ),
    );
  }

  Widget _lineMemoSummary(List<(String, String)> rows) => AccountingMemoSummary(
    summaryLabelInset: widget.embedded ? 0 : accountingContentInset,
    memoLabel: _salesReceiptCatalogue
        ? 'Receipt Message'
        : _customInformationActive
        ? _quotationValidityProposal
              ? 'Quotation Info'
              : 'Payment Terms'
        : 'Memo',
    rows: rows,
    rowKeys: const [
      ValueKey('design-line-subtotal'),
      ValueKey('design-line-tax'),
      ValueKey('design-line-total'),
    ],
    totalLabelKey: const ValueKey('design-total-label'),
    memo: (height) => AccountingDescriptionField(
      onEscape: widget.embedded ? null : _handleClose,
      role: _customInformationActive
          ? _customInformationRole
          : AccountingDescriptionRole.memo,
      key: ValueKey('design-field-$_memoKey'),
      controller: _controllers.putIfAbsent(
        _memoKey,
        () => TextEditingController(
          text: _customInformationActive
              ? _customTermsInitial
              : '${_values[_memoKey] ?? ''}',
        ),
      ),
      minimumHeight: height,
      fixedHeight: height,
      decoration: accountingInputDecoration(context),
      onChanged: (value) {
        _values[_memoKey] = value;
        if (_customTermsActive && _values['Payment Terms'] != 'Custom') {
          setState(() => _values['Payment Terms'] = 'Custom');
        }
      },
    ),
  );

  Widget _transactionLineEditor(double width) {
    final currency = _moneyCurrencyCode();
    final columns = _transactionColumnWidths(
      context,
      _form,
      _lines,
      currency,
      compactSelections: !widget.embedded,
    );
    final numberWidth = (TextPainter(
      text: TextSpan(
        text: '${_lines.length}',
        style: AccountingTypography.controlValue(context),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout()).width;
    columns['Description'] =
        width -
        numberWidth -
        AccountingTransactionGridTokens.numberGap(context, _lines.length) -
        accountingContentInset -
        20 -
        (columns.length - 1) * AccountingTransactionGridTokens.peerGap -
        columns.entries
            .where((e) => e.key != 'Description')
            .fold(0.0, (a, e) => a + e.value);
    Widget cell(int row, String field, double cellWidth) {
      final line = _lines[row];
      if (_bankingLineTaxFamily &&
          const {
            'Received From',
            'Account',
            'Payment Method',
          }.contains(field)) {
        return AccountingSelector<String>(
          assignedWidth: cellWidth,
          triggerKey: ValueKey('${line['_lineId']}-$field'),
          value: line[field],
          hintText: 'Select $field',
          options: [
            if (field == 'Account' && widget.onAddAccount != null)
              AccountingSelectorOption(
                value: '__add_account__',
                label: 'Add Account',
                leading: const AccountingAddIcon(),
                onPressed: () async {
                  final id = await widget.onAddAccount!('Account');
                  if (id != null && mounted && _lines.contains(line)) {
                    setState(() => line[field] = id);
                  }
                },
              ),
            if (field == 'Received From')
              AccountingSelectorOption(
                value: '__add_customer__',
                label: 'Add Customer',
                leading: const AccountingAddIcon(),
                onPressed: () async {
                  final customer = await showAccountingCustomerDialog(
                    context,
                    widget.settingsWorkspace!,
                  );
                  if (customer != null && mounted && _lines.contains(line)) {
                    setState(
                      () => line[field] = 'customer:${customer.id.value}',
                    );
                  }
                },
              ),
            if (field == 'Payment Method')
              AccountingSelectorOption(
                value: '__add_method__',
                label: 'Add Payment Method',
                leading: const AccountingAddIcon(),
                onPressed: () async {
                  await showAccountingPaymentMethodPreview(context);
                },
              ),
            for (final option in _form.lineChoiceLabels[field]!.entries)
              AccountingSelectorOption(
                value: option.key,
                label: option.value,
                preserveLabelCase: true,
                enabled:
                    !(_form.lineDisabledOptions[field]?.contains(option.key) ??
                        false),
              ),
          ],
          onChanged: (value) => setState(() => line[field] = value ?? ''),
        );
      }
      if (field == 'Account') {
        return AccountingSelector<String>(
          assignedWidth: cellWidth,
          triggerKey: ValueKey('${line['_lineId']}-$field'),
          value: line[field],
          hintText: 'Select Category',
          options: [
            for (final option in _form.lineChoiceLabels[field]!.entries)
              AccountingSelectorOption(
                value: option.key,
                label: option.value,
                preserveLabelCase: true,
              ),
          ],
          onChanged: (value) => setState(() => line[field] = value ?? ''),
        );
      }
      if (field == 'Product / Service') {
        return AccountingSelector<String>(
          assignedWidth: cellWidth,
          triggerKey: ValueKey('${line['_lineId']}-$field'),
          value: line[field],
          hintText: 'Select Item',
          options: [
            AccountingSelectorOption(
              value: '__add_item__',
              label: 'Add Item',
              leading: const AccountingAddIcon(),
              leadingWidth: AccountingDismissIcon.canvasSize,
              onPressed: () async {
                final item = await showCatalogueItemDialog(
                  context,
                  widget.settingsWorkspace!,
                );
                if (item != null && mounted) {
                  await _selectSalesItem(line, item.id.value);
                }
              },
            ),
            for (final option in _form.lineChoiceLabels[field]!.entries)
              AccountingSelectorOption(
                value: option.key,
                label: option.value,
                preserveLabelCase: true,
                enabled:
                    _form.title != 'Sales Receipts' ||
                    widget.settingsWorkspace!.catalogueItems.any(
                      (item) => item.id.value == option.key && item.active,
                    ),
              ),
          ],
          onChanged: (value) => _selectSalesItem(line, value),
        );
      }
      if (field == 'Tax Rate (%)') {
        final rates = {
          '0',
          if (!_billTaxFamily &&
              !_salesReceiptCatalogue &&
              !_bankingLineTaxFamily)
            ...?_form.lineChoiceLabels[field]?.keys.where(
              (value) => !value.contains(':'),
            ),
          for (final code in widget.settingsWorkspace!.taxRates)
            if (code.applies(
              parseAccountingInputDate(
                    (_values[_form.title == 'Deposits'
                                ? 'Deposit Date'
                                : _form.title == 'Credit Card Credits'
                                ? 'Payment Date'
                                : 'Date'])
                            as String? ??
                        '',
                  ) ??
                  DateTime.now(),
              const {'Bills', 'Credit Card Credits'}.contains(_form.title)
                  ? TaxApplication.purchases
                  : TaxApplication.sales,
            ))
              code.choice,
          if (!_billTaxFamily &&
              !_salesReceiptCatalogue &&
              !_bankingLineTaxFamily)
            ...widget.settingsWorkspace!.catalogueItems.map(
              (i) => i.taxRatePercent,
            ),
          if (_billTaxFamily &&
              (_originalBillLine(line)?[field] as String? ?? '').isNotEmpty)
            _originalBillLine(line)![field] as String,
          if (!_billTaxFamily)
            for (final other in _lines)
              if ((other[field] ?? '').isNotEmpty) other[field]!,
        };
        return AccountingSelector<String>(
          assignedWidth: cellWidth,
          triggerKey: ValueKey('${line['_lineId']}-$field'),
          value: _billTaxFamily && !_billLineTaxResolved(line)
              ? null
              : line[field],
          hintText:
              _billTaxFamily ||
                  const {
                    'Sales Receipts',
                    'Deposits',
                    'Credit Card Credits',
                  }.contains(_form.title)
              ? 'Select Tax'
              : 'No Tax',
          options: [
            for (final rate in rates)
              AccountingSelectorOption(
                value: rate,
                enabled: _billTaxFamily
                    ? _billLineTaxResolved({...line, field: rate})
                    : _bankingLineTaxFamily
                    ? _bankingLineTaxResolved({...line, field: rate})
                    : !_salesReceiptCatalogue ||
                          _salesReceiptLineTaxResolved({...line, field: rate}),
                preserveLabelCase:
                    _billTaxFamily ||
                    const {
                      'Sales Receipts',
                      'Deposits',
                      'Credit Card Credits',
                    }.contains(_form.title),
                label: rate == '0'
                    ? 'No Tax'
                    : _salesReceiptCatalogue &&
                          line['_salesReceiptTaxChoice'] == rate &&
                          line['_salesReceiptTaxLabel'] != null
                    ? line['_salesReceiptTaxLabel']!
                    : (_billTaxFamily && _savedBillTax(line)?.choice == rate
                              ? _savedBillTax(line)!.label
                              : _form.lineChoiceLabels[field]?[rate]) ??
                          '${taxPercent(rate)}%',
              ),
          ],
          onChanged: (value) => setState(() {
            line[field] = value ?? '';
            if (_salesReceiptCatalogue) {
              line['_salesReceiptTaxChoice'] = value ?? '';
              line['_salesReceiptTaxLabel'] = value == '0'
                  ? 'No Tax'
                  : _form.lineChoiceLabels[field]?[value] ??
                        '${taxPercent(value ?? '')}%';
            }
          }),
        );
      }
      if (field == 'Description') {
        return AccountingDescriptionField(
          onEscape: widget.embedded ? null : _handleClose,
          role: AccountingDescriptionRole.transactionItem,
          fixedLines: null,
          key: ValueKey(
            '${line['_lineId']}-${line['_selectionRevision'] ?? '0'}-$field',
          ),
          initialValue: line[field],
          decoration: accountingInputDecoration(context, hintText: field),
          onChanged: (value) => line[field] = value,
        );
      }
      if (field == 'Amount' && _form.lineFields!.contains('Rate')) {
        final digits = Currency.parse(currency).fractionDigits;
        String calculated() {
          // Keep the actively keyed text/caret intact, including a trailing dot.
          if (line['_manualAmount'] != null) return line['_manualAmount']!;
          try {
            final gross = line['_manualAmount'] == null
                ? SalesQuantity.fromDecimal(line['Quantity'] ?? '1')
                      .multiply(Money.fromDecimal(line['Rate'] ?? '', currency))
                : Money.fromDecimal(line['_manualAmount']!, currency);
            return formatAccountingMoneyInputText(
              formatAccountingInputAmount(gross),
              digits,
            );
          } on Object {
            return '';
          }
        }

        final amountController = _controllers.putIfAbsent(
          '${line['_lineId']}-Amount',
          () => TextEditingController(),
        );
        final next = calculated();
        if (amountController.text != next) {
          amountController.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
        }
        return TextFormField(
          key: ValueKey('${line['_lineId']}-Amount'),
          controller: amountController,
          style: AccountingTypography.controlValue(context),
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AccountingMoneyInputFormatter(digits)],
          decoration: accountingSingleLineInputDecoration(
            context,
            hintText: formatAccountingMoneyInputText(
              formatAccountingInputAmount(Money.zero(currency)),
              digits,
            ),
          ),
          onChanged: (value) async {
            line['_manualAmount'] = value;
            try {
              final quantity = SalesQuantity.fromDecimal(
                line['Quantity'] ?? '1',
              );
              line['Rate'] = formatAccountingInputAmount(
                quantity.rateFor(Money.fromDecimal(value, currency)),
              );
              // Only the inverse Rate field is rebuilt, preserving Amount's caret.
              line['_rateRevision'] =
                  '${(int.tryParse(line['_rateRevision'] ?? '') ?? 0) + 1}';
            } on Object {
              /* Incomplete amounts retain their editable value. */
            }
            await _ensureTransactionWidth();
            if (mounted) setState(() {});
          },
        );
      }
      final money = const {'Amount', 'Rate', 'Discount'}.contains(field);
      final digits = Currency.parse(currency).fractionDigits;
      return TextFormField(
        key: ValueKey(
          '${line['_lineId']}-${line['_selectionRevision'] ?? '0'}-${field == 'Rate' ? line['_rateRevision'] ?? '0' : '0'}-$field',
        ),
        initialValue: money
            ? formatAccountingMoneyInputText(line[field] ?? '', digits)
            : line[field],
        style: AccountingTypography.controlValue(context),
        textAlign: field == 'Quantity'
            ? TextAlign.center
            : money
            ? TextAlign.right
            : TextAlign.left,
        keyboardType: money || field == 'Quantity'
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        inputFormatters: money ? [AccountingMoneyInputFormatter(digits)] : null,
        decoration: accountingSingleLineInputDecoration(
          context,
          hintText: money
              ? formatAccountingMoneyInputText(
                  formatAccountingInputAmount(Money.zero(currency)),
                  digits,
                )
              : field == 'Quantity'
              ? null
              : field,
        ),
        onChanged: (value) async {
          line[field] = value;
          if (field == 'Amount') line['_amountEdited'] = 'true';
          if (field == 'Rate' || field == 'Quantity') {
            line.remove('_manualAmount');
          }
          if (field == 'Discount' && _retainDiscount) {
            try {
              _retainDiscount = _lines.any((line) {
                final value = (line['Discount'] ?? '').trim();
                return value.isNotEmpty &&
                    Money.fromDecimal(value, currency).minorUnits != 0;
              });
            } on Object {
              // Incomplete input remains visible until corrected or cleared.
            }
          }
          await _ensureTransactionWidth();
          if (mounted) setState(() {});
        },
      );
    }

    String amount(Money value) => formatAccountingMoneyInputText(
      formatAccountingInputAmount(value),
      Currency.parse(currency).fractionDigits,
    );
    final totals = _depositLineTotals();
    final emptyAmounts = _lineAmountsEmpty(currency);
    final zero = amount(Money.zero(currency));
    final unavailable = emptyAmounts ? zero : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: accountingContentInset),
        Text(
          _form.title == 'Deposits' ? 'Funds' : 'Items',
          style: AccountingTypography.fieldLabel(context),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: accountingContentInset),
        AccountingTransactionGrid(
          columns: [
            for (final entry in columns.entries)
              AccountingTransactionColumn(
                title: _form.title == 'Deposits' && entry.key == 'Account'
                    ? 'Account'
                    : _transactionColumnTitle(entry.key, currency),
                width: entry.value,
                headerAlignment: entry.key == 'Amount'
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                naturalHeaderWidth: const {
                  'Quantity',
                  'Rate',
                  'Amount',
                  'Product / Service',
                  'Account',
                  'Tax Rate (%)',
                }.contains(entry.key),
                cell: (row, w) => cell(row, entry.key, w),
              ),
          ],
          rowCount: _lines.length,
          rowKey: (row) => ValueKey(
            '${_salesGrid ? 'sales' : 'purchase'}-item-row-${_lines[row]['_lineId']}',
          ),
          action: (row) => row == 0
              ? accountingCompactAdd(
                  context,
                  key: const ValueKey('design-add-line'),
                  onPressed: () async {
                    _lines.add({
                      ...widget.lineDefaults,
                      if (_documentTaxFamily)
                        'Tax Rate (%)': _documentTaxChoice ?? '',
                      '_lineId': EntityId.random().value,
                    });
                    await _ensureTransactionWidth();
                    if (mounted) setState(() {});
                  },
                )
              : accountingCompactRemove(
                  context,
                  key: ValueKey('design-remove-line-$row'),
                  tooltip: 'Remove Item ${row + 1}',
                  onPressed: () => setState(() => _lines.removeAt(row)),
                ),
        ),
        const SizedBox(height: accountingContentInset),
        const Divider(height: 1),
        const SizedBox(height: accountingContentInset),
        if (_form.title == 'Deposits') ...[
          _fields(
            _form.fields
                .where((field) => field.label.startsWith('Cash Back'))
                .toList(),
            width,
          ),
          const SizedBox(height: accountingContentInset),
        ],
        _lineMemoSummary([
          (
            _form.title == 'Deposits' ? 'Other Funds' : 'Subtotal',
            totals == null
                ? unavailable
                : amount(
                    _form.title == 'Deposits' &&
                            _values['Tax Mode'] == 'Inclusive'
                        ? totals.$3
                        : totals.$1,
                  ),
          ),
          if (!(_form.title == 'Credit Card Credits' &&
              _values['Tax Mode'] == 'Out Of Scope'))
            ('Tax', totals == null ? unavailable : amount(totals.$2)),
          (
            'Total (${CurrencyPresentation.fromCode(currency).amountSymbol})',
            totals == null
                ? unavailable
                : _form.title == 'Deposits'
                ? _depositTotal(totals.$3, amount)
                : amount(totals.$3),
          ),
        ]),
        if (totals == null && !emptyAmounts) ...[
          const SizedBox(height: accountingFieldLabelGap),
          accountingHelperText(
            context,
            'Complete item amounts and tax treatment to see the total.',
          ),
        ],
      ],
    );
  }

  (Money, Money, Money)? _depositLineTotals() {
    final totals = _lineTotals();
    if (_form.title != 'Deposits' || totals != null) return totals;
    if (_lineAmountsEmpty(_moneyCurrencyCode())) {
      final zero = Money.zero(_moneyCurrencyCode());
      return (zero, zero, zero);
    }
    return null;
  }

  String _depositTotal(Money funds, String Function(Money) format) {
    try {
      final text = '${_values['Cash Back Amount'] ?? ''}'.trim();
      final cash = text.isEmpty
          ? Money.zero(funds.currency)
          : Money.fromDecimal(text, funds.currency);
      return format(funds - cash);
    } on Object {
      return '—';
    }
  }

  List<String> get _previewLineFields => [
    for (final field
        in _form.lineFields ??
            const ['Description', 'Quantity', 'Rate', 'Tax Code', 'Account'])
      if (!_documentTaxFamily ||
          !const {'Tax Code', 'Tax Rate (%)'}.contains(field))
        field,
  ];

  bool _previewMoneyField(String field) =>
      const {'Amount', 'Rate', 'Discount'}.contains(field);

  Map<String, double> _previewColumnWidths(String currencyCode) {
    final fractionDigits = Currency.parse(currencyCode).fractionDigits;
    return <String, double>{
      for (final field in _previewLineFields)
        field: field == 'Description'
            ? 180
            : _previewMoneyField(field) || field == 'Quantity'
            ? _frontendTransactionNumericWidth(
                context,
                field,
                [
                  if (_previewMoneyField(field))
                    formatAccountingMoneyInputText(
                      formatAccountingInputAmount(Money.zero(currencyCode)),
                      fractionDigits,
                    ),
                  ..._lines.map(
                    (line) => _previewMoneyField(field)
                        ? formatAccountingMoneyInputText(
                            line[field] ?? '',
                            fractionDigits,
                          )
                        : line[field] ?? '',
                  ),
                ],
                minimumText: field == 'Discount' ? '000' : null,
                title: _transactionColumnTitle(field, currencyCode),
              )
            : AccountingTransactionGridTokens.selectionWidth(
                context,
                field == 'Account'
                    ? 'Select Category'
                    : field == 'Product / Service'
                    ? 'Select Item'
                    : 'Select Tax',
                title: _transactionColumnTitle(field, currencyCode),
                selectedLabels: _lines.map(
                  (line) =>
                      _form.lineChoiceLabels[field]?[line[field]] ??
                      line[field],
                ),
              ),
    };
  }

  double _previewFixedWidth(Map<String, double> widths) {
    final numberPainter = TextPainter(
      text: TextSpan(
        text: '${_lines.length}',
        style: AccountingTypography.controlValue(context),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final numberWidth = numberPainter.width;
    numberPainter.dispose();
    return numberWidth +
        AccountingTransactionGridTokens.numberGap(context, _lines.length) +
        accountingContentInset +
        AccountingDismissIcon.controlExtent +
        (widths.length - 1) * AccountingTransactionGridTokens.peerGap +
        widths.entries
            .where((entry) => entry.key != 'Description')
            .fold(0.0, (sum, entry) => sum + entry.value);
  }

  Widget _lineEditor(double width) {
    if (_transactionGrid) {
      return LayoutBuilder(
        builder: (context, constraints) =>
            _transactionLineEditor(math.min(width, constraints.maxWidth)),
      );
    }
    final fields = _previewLineFields;
    final currencyCode = _moneyCurrencyCode();
    final fractionDigits = Currency.parse(currencyCode).fractionDigits;
    bool moneyField(String field) => _previewMoneyField(field);
    final widths = _previewColumnWidths(currencyCode);
    final fixedWidth = _previewFixedWidth(widths);
    if (widths.containsKey('Description')) {
      widths['Description'] = math.max(180, width - fixedWidth);
    }
    final gridWidth = fixedWidth + (widths['Description'] ?? 0);
    void selectItem(int index, String? value) {
      if (value == null) return;
      final item = widget.settingsWorkspace?.catalogueItems
          .where((item) => item.id.value == value)
          .firstOrNull;
      if (item == null) return;
      _lines[index].addAll({
        'Product / Service': item.id.value,
        'Description': item.description,
        'Account': item.incomeAccountId.value,
        if (!_documentTaxFamily) 'Tax Rate (%)': item.taxRatePercent,
        '_selectionRevision':
            '${(int.tryParse(_lines[index]['_selectionRevision'] ?? '') ?? 0) + 1}',
      });
    }

    Widget cell(int index, String field, double cellWidth) {
      final line = _lines[index];
      if (_form.lineChoiceLabels[field] case final choices?) {
        return AccountingSelector<String>(
          assignedWidth: cellWidth,
          triggerKey: ValueKey('${line['_lineId']}-$field'),
          value: line[field],
          hintText: 'Select $field',
          options: [
            if (field == 'Product / Service' &&
                widget.settingsWorkspace != null)
              AccountingSelectorOption(
                value: '__add_item__',
                label: 'Add Item',
                leading: const AccountingAddIcon(),
                leadingWidth: AccountingDismissIcon.canvasSize,
                onPressed: () async {
                  final item = await showCatalogueItemDialog(
                    context,
                    widget.settingsWorkspace!,
                  );
                  if (item != null && mounted && _lines.contains(line)) {
                    setState(
                      () => selectItem(_lines.indexOf(line), item.id.value),
                    );
                  }
                },
              ),
            for (final option in choices.entries)
              AccountingSelectorOption(
                value: option.key,
                label: option.value,
                preserveLabelCase: true,
              ),
          ],
          onChanged: (value) => setState(() {
            if (field == 'Product / Service') {
              selectItem(index, value);
            } else if (value == null) {
              line.remove(field);
            } else {
              line[field] = value;
            }
          }),
        );
      }
      final key = ValueKey(
        '${identityHashCode(line)}-${line['_selectionRevision'] ?? '0'}-$field',
      );
      if (field == 'Description') {
        return AccountingDescriptionField(
          onEscape: widget.embedded ? null : _handleClose,
          role: AccountingDescriptionRole.transactionItem,
          fixedLines: null,
          key: key,
          initialValue: line[field],
          onChanged: (value) => line[field] = value,
        );
      }
      return TextFormField(
        key: key,
        initialValue: moneyField(field)
            ? formatAccountingMoneyInputText(line[field] ?? '', fractionDigits)
            : line[field],
        style: AccountingTypography.controlValue(context),
        textAlign: field == 'Quantity'
            ? TextAlign.center
            : moneyField(field)
            ? TextAlign.right
            : TextAlign.left,
        keyboardType: moneyField(field) || field == 'Quantity'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        inputFormatters: moneyField(field)
            ? [AccountingMoneyInputFormatter(fractionDigits)]
            : null,
        decoration: accountingSingleLineInputDecoration(
          context,
          hintText: moneyField(field)
              ? formatAccountingMoneyInputText(
                  formatAccountingInputAmount(Money.zero(currencyCode)),
                  fractionDigits,
                )
              : field == 'Quantity'
              ? null
              : field,
        ),
        onChanged: (value) async {
          line[field] = value;
          await _ensureTransactionWidth();
          if (mounted) setState(() {});
        },
      );
    }

    final previewTotals = _lineTotals();
    final emptyAmounts = _lineAmountsEmpty(currencyCode);
    final unavailable = emptyAmounts
        ? formatAccountingMoneyInputText(
            formatAccountingInputAmount(Money.zero(currencyCode)),
            fractionDigits,
          )
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: accountingContentInset),
        Text('Items', style: AccountingTypography.fieldLabel(context)),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: accountingContentInset),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: AccountingTransactionGrid(
              columns: [
                for (final field in fields)
                  AccountingTransactionColumn(
                    title: _transactionColumnTitle(field, currencyCode),
                    width: widths[field]!,
                    headerAlignment: field != 'Rate' && moneyField(field)
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    naturalHeaderWidth: field != 'Description',
                    cell: (row, w) => cell(row, field, w),
                  ),
              ],
              rowCount: _lines.length,
              rowKey: (row) => ObjectKey(_lines[row]),
              action: (row) => row == 0
                  ? accountingCompactAdd(
                      context,
                      key: const ValueKey('design-add-line'),
                      onPressed: () async {
                        _lines.add({
                          ...widget.lineDefaults,
                          if (_documentTaxFamily)
                            'Tax Rate (%)': _documentTaxChoice ?? '',
                          '_lineId': EntityId.random().value,
                        });
                        await _ensureTransactionWidth();
                        if (mounted) setState(() {});
                      },
                    )
                  : accountingCompactRemove(
                      context,
                      key: ValueKey('design-remove-line-$row'),
                      tooltip: 'Remove Item ${row + 1}',
                      onPressed: () => setState(() => _lines.removeAt(row)),
                    ),
            ),
          ),
        ),
        const SizedBox(height: accountingContentInset),
        const Divider(height: 1),
        const SizedBox(height: accountingContentInset),
        _lineMemoSummary([
          (
            'Subtotal',
            previewTotals != null
                ? formatAccountingMoneyInputText(
                    formatAccountingInputAmount(previewTotals.$1),
                    fractionDigits,
                  )
                : unavailable,
          ),
          (
            'Tax',
            previewTotals != null
                ? formatAccountingMoneyInputText(
                    formatAccountingInputAmount(previewTotals.$2),
                    fractionDigits,
                  )
                : unavailable,
          ),
          (
            'Total (${CurrencyPresentation.fromCode(currencyCode).amountSymbol})',
            previewTotals != null
                ? formatAccountingMoneyInputText(
                    formatAccountingInputAmount(previewTotals.$3),
                    fractionDigits,
                  )
                : unavailable,
          ),
        ]),
        if (previewTotals == null && !emptyAmounts) ...[
          const SizedBox(height: accountingFieldLabelGap),
          accountingHelperText(
            context,
            'Complete item prices and tax treatment to see the total.',
          ),
        ],
        const SizedBox(height: 12),
        Text(
          widget.onCommit == null
              ? 'Preview amounts only. Nothing is posted, filed or submitted.'
              : 'Amounts are validated when saved. Posting requires a separate review.',
        ),
      ],
    );
  }

  String _inputSnapshot() => jsonEncode(
    [
      {
        for (final entry
            in (widget.inputValuesForComparison?.call(
                      Map.unmodifiable(_values),
                    ) ??
                    _values)
                .entries)
          if (!const {'_lines', '_files', '_attachments'}.contains(entry.key) &&
              entry.value != null &&
              entry.value != '')
            entry.key: entry.value,
      },
      [
        for (final line in _lines)
          {
            for (final entry in line.entries)
              if (entry.value.isNotEmpty) entry.key: entry.value,
          },
      ],
      _files,
      [
        for (final file in _attachments)
          file == null
              ? null
              : [
                  file.originalId,
                  file.originalSha256,
                  file.derivativeId,
                  file.derivativeSha256,
                  file.pdfSha256,
                ],
      ],
      _recurring,
    ],
    toEncodable: (dynamic value) {
      if (value is DateTime) return value.toIso8601String();
      return value.toJson();
    },
  );

  Future<void> _handleClose() async {
    if (_committing || _preparingReview || _closePromptOpen) return;
    if (_inputSnapshot() == _openingInput) {
      Navigator.of(context).pop();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('design-discard-close'),
        keepEditingKey: const ValueKey('design-keep-editing'),
        discardKey: const ValueKey('design-discard-changes'),
      );
      if (mounted) {
        if (discard) {
          Navigator.of(context).pop();
        } else {
          _editingFocus.requestFocus();
        }
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded && _ordinaryPopupLayout) {
      return LayoutBuilder(
        builder: (context, constraints) =>
            _build(context, availableWidth: constraints.maxWidth),
      );
    }
    return _build(context);
  }

  Widget _build(BuildContext context, {double? availableWidth}) {
    final preferredWidth = _form.lines
        ? _contentWidth
        : widget.embedded
        ? widget.contentWidth ??
              (MediaQuery.sizeOf(context).width - 128).clamp(200.0, 720.0)
        : AccountingPopoutTokens.contentWidthFor(widget.widthFamily) ??
              widget.contentWidth ??
              (MediaQuery.sizeOf(context).width - 128).clamp(200.0, 720.0);
    final width = availableWidth != null && availableWidth.isFinite
        ? math.min(preferredWidth, availableWidth)
        : widget.embedded || _form.lines
        ? preferredWidth
        : math.min(
            preferredWidth,
            math.max(
              0.0,
              MediaQuery.sizeOf(context).width -
                  AccountingPopoutTokens.windowInsets.horizontal -
                  AccountingPopoutTokens.contentInset * 2,
            ),
          );
    final classSection = _form.title == 'Bills'
        ? 'Purchase Preferences'
        : 'Sales Preferences';
    final tagFields = _form.fields.where((field) {
      if (field.label == 'Memo') return !_form.lines;
      if (field.label != 'Class') return false;
      return !_transactionGrid ||
          '${_values['Class'] ?? ''}'.isNotEmpty ||
          widget.settingsWorkspace!.preferences.enabled(
            classSection,
            'Show Class',
          );
    }).toList();
    final additional =
        widget.additionalContentBuilder?.call(
          context,
          Map.unmodifiable(_formValues()),
          _review,
        ) ??
        (_form.title == 'Credit Card Payments' && !_review
            ? _cardPaymentMemoSummary()
            : null);
    final leading = widget.leadingContentBuilder?.call(
      context,
      Map.unmodifiable(_formValues()),
      _review,
    );
    final content = SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ?leading,
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: AccountingTheme.of(context).destructive),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.informationRows.isNotEmpty) ...[
            AccountingInformationRows(rows: widget.informationRows),
            const SizedBox(height: accountingContentInset),
          ],
          if (_review && _resolvedReviewDocuments != null) ...[
            if (_resolvedReviewDocuments!.length > 1) ...[
              accountingFieldLabel(context, 'Attachment', alignToField: true),
              const SizedBox(height: accountingFieldLabelGap),
              AccountingSelector<int>(
                triggerKey: const ValueKey('document-review-selector'),
                hintText: 'Choose attachment',
                options: [
                  for (final (index, document)
                      in _resolvedReviewDocuments!.indexed)
                    AccountingSelectorOption(
                      value: index,
                      label: document.filename,
                    ),
                ],
                value: _reviewDocument,
                onChanged: (value) {
                  if (value != null) setState(() => _reviewDocument = value);
                },
              ),
              const SizedBox(height: accountingContentInset),
            ],
            AttachmentPreviewDialog(
              key: ValueKey(
                'document-review-${_resolvedReviewDocuments![_reviewDocument].originalId}-${_resolvedReviewDocuments![_reviewDocument].originalSha256}',
              ),
              attachment: _resolvedReviewDocuments![_reviewDocument],
              embedded: true,
              originalOnly:
                  !_resolvedReviewDocuments![_reviewDocument].isGenerated,
            ),
          ] else if (_review) ...[
            Text(
              'Review Selections',
              style: AccountingTypography.sectionTitle(context),
            ),
            const SizedBox(height: 12),
            if (_resolvedReviewRows != null)
              AccountingInformationRows(rows: _resolvedReviewRows!)
            else
              AccountingInformationRows(
                rows: [
                  for (final field in _reviewFields)
                    (_displayLabel(field.label), _reviewValue(field)),
                  if (_quotationValidityProposal &&
                      _quotationValidityChoice != 'Custom')
                    ('Valid Until', '${_values['Expiry Date'] ?? 'Not Set'}'),
                  if (_form.lines) ('Line Items', '${_lines.length}'),
                  if (_files.isNotEmpty) ('Selected Files', _files.join(', ')),
                ],
              ),
            if (_receivePaymentProposal) ...[
              const SizedBox(height: AccountingResponsive.groupGap),
              _receivePaymentAllocations(readOnly: true),
            ],
          ] else ...[
            if (_ordinaryTransactionHeader)
              _transactionHeader(width)
            else
              _fields(
                _form.lines
                    ? _form.fields
                          .where(
                            (field) => !const {
                              'Tax Mode',
                              'Class',
                              'Memo',
                            }.contains(field.label),
                          )
                          .toList()
                    : _form.title == 'Credit Card Payments'
                    ? _form.fields
                          .where((field) => field.label != 'Memo')
                          .toList()
                    : _form.fields,
                width,
              ),
            // Asset-register policy fields belong to the catalogue preview.
            // Operational bills allocate actual expense/asset accounts per line;
            // they must not accept unsupported registration/depreciation values.
            if (_form.title == 'Bills' && widget.onCommit == null)
              AssetPurchaseFields(
                ordinaryPopup: true,
                currencyCode: _moneyCurrencyCode(),
                onChanged: (v) => _values['_assetPurchase'] = v,
              ),
            if (_form.lines) ...[
              if (!_transactionGrid &&
                  !_ordinaryTransactionHeader &&
                  !_documentTaxFamily &&
                  _form.fields.any((field) => field.label == 'Tax Mode')) ...[
                const SizedBox(height: AccountingResponsive.groupGap),
                _fields(
                  _form.fields
                      .where((field) => field.label == 'Tax Mode')
                      .toList(),
                  width,
                ),
              ],
              if (_documentTaxFamily && !_ordinaryTransactionHeader)
                _documentTaxEditor(width),
              if (_documentTaxFamily) _documentTaxBasisWarning(),
              if (_billTaxFamily) _billTaxWarnings(),
              _lineEditor(width),
              if (_salesReceiptCatalogue) ...[
                const SizedBox(height: AccountingResponsive.groupGap),
                _fields(
                  _form.fields
                      .where((field) => field.label == 'Statement Message')
                      .toList(),
                  width,
                ),
              ],
              if (tagFields.isNotEmpty) ...[
                const SizedBox(height: AccountingResponsive.groupGap),
                _fields(tagFields, width),
              ],
            ],
            if (_form.recurring && !_ordinaryTransactionHeader) ...[
              const Divider(height: 36),
              AccountingSwitchListTile(
                title: accountingFieldLabel(
                  context,
                  'Recurring',
                  alignToField: true,
                ),
                value: _recurring,
                onChanged: (value) => setState(() => _recurring = value),
              ),
              if (_recurring)
                _fields(const [
                  DesignField(
                    'Frequency',
                    options: ['Monthly', 'Quarterly', 'Yearly', 'Custom'],
                  ),
                  DesignField('Every'),
                  DesignField(
                    'Interval Unit',
                    options: ['Days', 'Weeks', 'Months', 'Years'],
                  ),
                  DesignField('Start Date'),
                  DesignField(
                    'End Condition',
                    options: ['No End Date', 'On Date', 'After Occurrences'],
                  ),
                  DesignField('End Date / Occurrence Count'),
                  DesignField(
                    'Month-End Rule',
                    options: ['Keep Month End', 'Use Starting Day'],
                  ),
                ], width),
            ],
            if (additional != null && _form.title == 'Credit Card Payments')
              const SizedBox(height: accountingContentInset),
            ?additional,
            if (_form.evidence) ...[
              if (_transactionGrid)
                const SizedBox(height: accountingContentInset)
              else
                const Divider(height: 36),
              Text(
                'Supporting Documents',
                style: _transactionGrid
                    ? AccountingTypography.fieldLabel(context)
                    : AccountingTypography.sectionTitle(context),
              ),
              const SizedBox(height: accountingFieldLabelGap),
              DropTarget(
                enable:
                    defaultTargetPlatform == TargetPlatform.macOS ||
                    defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.linux,
                onDragEntered: (_) {
                  if (mounted) setState(() => _isDragOver = true);
                },
                onDragExited: (_) {
                  if (mounted) setState(() => _isDragOver = false);
                },
                onDragDone: _onFilesDropped,
                child: InkWell(
                  onTap: _chooseFiles,
                  borderRadius: BorderRadius.circular(accountingControlRadius),
                  child: AccountingAttachmentDropzone(
                    dragOver: _isDragOver,
                    onChoose: _chooseFiles,
                    prompt: 'Drop documents here or choose files',
                    formats:
                        'JPEG, PNG, HEIC, or PDF. Multiple files supported.',
                    actionKey: const ValueKey('design-choose-files'),
                  ),
                ),
              ),
              if (_files.isNotEmpty) const SizedBox(height: 12),
              AccountingAttachmentList(
                paginationKey: '${_form.title}-attachments',
                children: [
                  for (var i = 0; i < _files.length; i++) _attachmentRow(i),
                ],
              ),
            ],
          ],
        ],
      ),
    );
    final onReview =
        _committing ||
            _attachmentBusy ||
            _preparingReview ||
            (_review &&
                widget.onCommit == null &&
                !widget.previewConfirmationEnabled)
        ? null
        : () async {
            if (_salesReceiptCatalogue &&
                '${_values['Payment Account'] ?? ''}'.isNotEmpty) {
              final depositField = _form.fields.singleWhere(
                (field) => field.label == 'Payment Account',
              );
              if (!_selectorOptions(depositField).any(
                (option) =>
                    option.value == _values['Payment Account'] &&
                    option.enabled,
              )) {
                setState(
                  () => _error = 'Choose an available Deposit To account in the receipt currency.',
                );
                return;
              }
            }
            try {
              if (_transactionGrid &&
                  _form.recurring &&
                  _recurring &&
                  !_recurrenceLocked) {
                _recurrenceRequest();
              }
            } on Object catch (error) {
              setState(
                () => _error =
                    'Could not review: ${error is FormatException ? error.message : error}',
              );
              return;
            }
            if (_review) {
              if (widget.embedded && widget.onCommit == null) {
                setState(() {
                  _review = false;
                  _error = null;
                });
                return;
              }
              final values = _formValues();
              final commit = widget.onCommit;
              if (commit != null) {
                setState(() {
                  _committing = true;
                  _error = null;
                });
                try {
                  await commit(values);
                } catch (error) {
                  if (mounted) {
                    setState(() {
                      _committing = false;
                      _error = 'Could not save: $error';
                    });
                  }
                  return;
                }
                if (!context.mounted) return;
              }
              if (widget.embedded) {
                setState(() {
                  _committing = false;
                  _review = false;
                  _savedSettings = true;
                });
              } else {
                Navigator.pop(context, values);
              }
              return;
            }
            if (_billTaxFamily &&
                !const {
                  'Exclusive',
                  'Inclusive',
                  'Exempt',
                  'Out Of Scope',
                }.contains(_values['Tax Mode'])) {
              setState(
                () => _error =
                    'Select Tax Exclusive or Tax Inclusive for bill amounts.',
              );
              return;
            }
            final unavailable = _form.fields
                .where(
                  (field) =>
                      field.choiceLabels != null &&
                      '${_values[field.label] ?? ''}'.trim().isNotEmpty &&
                      !field.choiceLabels!.containsKey(_values[field.label]),
                )
                .toList();
            if (unavailable.isNotEmpty) {
              setState(
                () =>
                    _error = 'Choose an available ${unavailable.first.label}.',
              );
              return;
            }
            final missing = _transferFields(_form.fields)
                .where(
                  (field) =>
                      field.required &&
                      '${_values[field.label] ?? ''}'.trim().isEmpty,
                )
                .map((field) => field.label);
            List<(String, String)>? resolvedRows;
            List<ReceiptAttachment>? resolvedDocuments;
            if (missing.isEmpty &&
                widget.reviewInformationRowsBuilder != null) {
              try {
                resolvedRows = widget.reviewInformationRowsBuilder!(
                  _formValues(),
                );
              } catch (error) {
                setState(
                  () => _error =
                      'Could not review: ${error is FormatException ? error.message : error}',
                );
                return;
              }
            }
            if (missing.isEmpty && widget.reviewDocumentsBuilder != null) {
              FocusScope.of(context).unfocus();
              setState(() {
                _preparingReview = true;
                _error = null;
              });
              try {
                resolvedDocuments = await widget.reviewDocumentsBuilder!(
                  _formValues(),
                );
                if (resolvedDocuments.isEmpty) {
                  throw StateError('No document available for review.');
                }
              } catch (error) {
                if (mounted) {
                  setState(() {
                    _preparingReview = false;
                    _error =
                        'Could not review: ${error is FormatException ? error.message : error}';
                  });
                }
                return;
              }
              if (!mounted) return;
            }
            setState(() {
              _preparingReview = false;
              _requiredReviewWarning = missing.isEmpty
                  ? null
                  : 'Complete ${missing.join(', ')} before reviewing.';
              _error = _requiredReviewWarning;
              _review = missing.isEmpty;
              _resolvedReviewRows = resolvedRows;
              _resolvedReviewDocuments = resolvedDocuments;
              _reviewDocument = 0;
            });
          };
    final actions = widget.embedded && widget.onCommit != null
        ? <Widget>[
            AccountingButton.outline(
              context,
              key: const ValueKey('design-preview'),
              onPressed: _committing
                  ? null
                  : () async {
                      if (widget.onPreview != null) {
                        await widget.onPreview!({..._values});
                      } else {
                        setState(() => _review = !_review);
                      }
                    },
              leadingIcon: _review ? null : Icons.visibility_outlined,
              child: Text(_review ? 'Back' : 'Preview'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('design-save-settings'),
              onPressed: _committing
                  ? null
                  : () async {
                      final missing = _form.fields
                          .where(
                            (field) =>
                                field.required &&
                                '${_values[field.label] ?? ''}'.trim().isEmpty,
                          )
                          .map((field) => field.label)
                          .toList();
                      if (missing.isNotEmpty) {
                        setState(
                          () => _error =
                              'Complete ${missing.join(', ')} before saving.',
                        );
                        return;
                      }
                      setState(() {
                        _committing = true;
                        _error = null;
                        _savedSettings = false;
                      });
                      try {
                        await widget.onCommit!({..._values});
                        if (mounted) {
                          setState(() {
                            _committing = false;
                            _review = false;
                            _savedSettings = true;
                          });
                        }
                      } catch (error) {
                        if (mounted) {
                          setState(() {
                            _committing = false;
                            _error = 'Could not save: $error';
                          });
                        }
                      }
                    },
              child: Text(_committing ? 'Saving…' : 'Save'),
            ),
          ]
        : <Widget>[
            if (!widget.embedded)
              AccountingButton.ghost(
                context,
                key: const ValueKey('design-cancel'),
                onPressed: _committing || _preparingReview
                    ? null
                    : _handleClose,
                child: const Text('Cancel'),
              ),
            if (_review)
              AccountingButton.outline(
                context,
                key: const ValueKey('design-back'),
                onPressed: _committing || _preparingReview
                    ? null
                    : () => setState(() => _review = false),
                child: const Text('Back'),
              ),
            if (_review || widget.onCommit != null)
              AccountingButton.primary(
                context,
                key: const ValueKey('design-review'),
                onPressed: onReview,
                child: Text(
                  _review
                      ? (_committing
                            ? 'Saving…'
                            : widget.onCommit != null ||
                                  !widget.previewConfirmationEnabled
                            ? (_form.actionLabel ?? 'Save')
                            : widget.embedded
                            ? 'Continue Editing'
                            : 'Keep Preview')
                      : _preparingReview
                      ? 'Preparing…'
                      : widget.onCommit != null
                      ? 'Review'
                      : 'Preview',
                ),
              )
            else
              AccountingButton.preview(
                context,
                key: const ValueKey('design-review'),
                onPressed: onReview,
              ),
          ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingHelperText(
            context,
            widget.onCommit == null
                ? 'Preview only. These choices do not change live records and reset when Settings closes.'
                : _savedSettings
                ? 'Saved. These settings now apply to this company.'
                : 'Save changes to apply them to this company.',
          ),
          const SizedBox(height: 16),
          widget.embeddedContentBuilder == null
              ? content
              : widget.embeddedContentBuilder!(
                  content,
                  _review
                      ? null
                      : [
                          for (final field in _form.fields)
                            AccountingOrdinaryFieldSlot(
                              label: field.label,
                              choices: _selectorOptions(field)
                                  .map((option) => option.label)
                                  .toList(),
                              hasGuidance:
                                  accountingFieldGuidance(field.label) != null,
                              minimumControlWidth: _minimumFieldWidth(field),
                              builder: (assigned) =>
                                  _field(field, assignedWidth: assigned),
                            ),
                        ],
                  width,
                ),
          if (widget.footerContent != null) widget.footerContent!,
          const SizedBox(height: accountingContentInset),
          if ((widget.embedded && _ordinaryPopupLayout))
            accountingFormFooter(
              context,
              key: ValueKey('settings-form-footer-${_form.title}'),
              actions: actions,
            )
          else ...[
            Divider(
              height: 1,
              thickness: 1,
              color: AccountingTheme.of(context).border,
            ),
            const SizedBox(height: accountingContentInset),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: accountingContentInset,
                runSpacing: accountingContentInset,
                children: actions,
              ),
            ),
          ],
        ],
      );
    }
    return FocusScope(
      node: _editingFocus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _handleClose();
        },
        child: AccountingDialog.alert(
          context,
          onClose: _handleClose,
          closeKey: const ValueKey('design-close'),
          canClose: !_committing && !_preparingReview,
          title: _transactionGrid
              ? switch (_form.title) {
                  'Invoices' => 'Invoice',
                  'Quotations' => 'Quotation',
                  'Bills' => 'Bill',
                  _ => _form.title,
                }
              : _form.title,
          formFooter: true,
          contentInset:
              const {'Invoices', 'Quotations', 'Bills'}.contains(_form.title)
              ? accountingContentInset
              : AccountingPopoutTokens.contentInset,
          footerLeading:
              widget.settingsWorkspace != null &&
                  transactionSettingsFields(_form.title).isNotEmpty
              ? AccountingSettingsShortcut(
                  key: const ValueKey('transaction-settings-shortcut'),
                  onPressed: _committing || _preparingReview
                      ? null
                      : _openTransactionSettings,
                )
              : null,
          contentScrollKey: ValueKey(_review),
          maxContentWidth: width,
          fixedContentWidth: _form.lines ? _contentWidth : widget.contentWidth,
          widthFamily: _form.lines
              ? AccountingPopoutWidthFamily.custom
              : widget.widthFamily,
          description: _transactionGrid && _form.title != 'Deposits'
              ? null
              : widget.onCommit == null
              ? 'Design preview · Changes are kept only in this review session. Nothing is posted, filed or submitted.'
              : (_form.description ??
                    'Review the details, then save to this company.'),
          content: widget.footerContent == null
              ? AbsorbPointer(absorbing: _preparingReview, child: content)
              : SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [content, widget.footerContent!],
                  ),
                ),
          actions: actions,
        ),
      ),
    );
  }
}

class FrontendAreaPage extends StatefulWidget {
  const FrontendAreaPage({
    super.key,
    required this.area,
    required this.title,
    this.existing,
    this.existingLabel,
    this.loadAccountNames,
    this.extraPages = const {},
    this.notificationCounts = const {},
    this.formsOverride,
    this.initialPage,
    this.workspace,
    this.employeePayeeSearch,
  });
  final Map<String, Widget> extraPages;
  final Map<String, int> notificationCounts;
  final List<DesignForm>? formsOverride;
  final String? initialPage;
  final String area, title;
  final AccountingWorkspace? workspace;
  final Future<List<Payee>> Function(String)? employeePayeeSearch;
  final Widget? existing;
  final String? existingLabel;
  final Future<List<String>> Function()? loadAccountNames;
  @override
  State<FrontendAreaPage> createState() => _FrontendAreaPageState();
}

class _FrontendAreaPageState extends State<FrontendAreaPage> {
  int _selected = 0;
  bool _initialised = false;
  final Map<String, Map<String, Object?>> _drafts = {};
  final Map<String, Set<String>> _removedPreviews = {};
  String? _period = 'All Dates', _status = 'All Statuses';
  String _search = '';
  bool _calendar = false;
  DateTime _calendarDate = DateTime.now();
  final _customFrom = TextEditingController();
  final _customThrough = TextEditingController();
  Future<LedgerReport>? _ledgerFuture;
  String? _ledgerRangeKey;
  final _appliedReportRanges = <String, (DateTime, DateTime)>{};
  final _reportInputs = <String, Map<String, Object?>>{};

  bool _hasLivePeriod(String title) =>
      widget.workspace != null &&
      const {
        'Cash Flow',
        'Changes In Equity',
        'Management Report Pack',
      }.contains(title);

  (DateTime, DateTime) _reportPeriodRange(Map<String, Object?> values) {
    final now = DateTime.now();
    final through = DateTime.utc(now.year, now.month, now.day);
    return switch (values['Period']) {
      'All Dates' => (DateTime.utc(1900), through),
      'This Month' => (DateTime.utc(now.year, now.month), through),
      'This Quarter' => (
        DateTime.utc(now.year, ((now.month - 1) ~/ 3) * 3 + 1),
        through,
      ),
      'Custom' => switch ((
        parseAccountingInputDate('${values['From Date'] ?? ''}'),
        parseAccountingInputDate('${values['Through Date'] ?? ''}'),
      )) {
        (final DateTime from, final DateTime end) when !from.isAfter(end) => (
          from,
          end,
        ),
        _ => throw const FormatException(
          'Enter valid dates with the start on or before the end.',
        ),
      },
      _ => throw const FormatException('Choose a report period.'),
    };
  }

  Future<void> _openReportPeriod(DesignForm form) async {
    final workspace = widget.workspace!;
    DesignForm periodForm(Map<String, Object?> values) => DesignForm(
      form.title,
      [
        const DesignField(
          'Period',
          required: true,
          options: ['All Dates', 'This Month', 'This Quarter', 'Custom'],
        ),
        if (values['Period'] == 'Custom') ...[
          const DesignField('From Date', required: true),
          const DesignField('Through Date', required: true),
        ],
      ],
      description: 'Choose the period for this report.',
      actionLabel: 'Run Report',
    );
    final initial = _reportInputs[form.title] ?? {'Period': 'All Dates'};
    await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: periodForm(initial),
        initial: initial,
        valuesFormBuilder: periodForm,
        reviewInformationRowsBuilder: (values) {
          final range = _reportPeriodRange(values);
          return [
            ('From Date', formatAccountingInputDate(range.$1)),
            ('Through Date', formatAccountingInputDate(range.$2)),
          ];
        },
        onCommit: (values) async {
          final range = _reportPeriodRange(values);
          final report = await workspace.report(
            from: range.$1,
            through: range.$2,
          );
          if (!mounted || widget.workspace != workspace) {
            throw StateError('The company changed. Reopen this report.');
          }
          setState(() {
            _reportInputs[form.title] = Map.of(values);
            _appliedReportRanges[form.title] = range;
            _ledgerRangeKey =
                '${range.$1.toIso8601String()}|${range.$2.toIso8601String()}';
            _ledgerFuture = Future.value(report);
          });
        },
      ),
    );
  }

  void _invalidateLedger() {
    if (mounted) {
      setState(() {
        _ledgerFuture = null;
        _ledgerRangeKey = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.workspace?.addListener(_invalidateLedger);
  }

  @override
  void dispose() {
    widget.workspace?.removeListener(_invalidateLedger);
    _customFrom.dispose();
    _customThrough.dispose();
    super.dispose();
  }

  bool _canRemovePreview(Map<String, Object?> record) =>
      DemoCompany.active(context) &&
      const {
        'Draft',
        'Pending Review',
        'Pending Approval',
        'Rejected',
        'Declined',
      }.contains(record['_status']);

  Future<void> _removePreviewRecord(
    DesignForm form,
    Map<String, Object?> record,
  ) async {
    if (!_canRemovePreview(record)) return;
    final confirmed = await AccountingDialog.showFixed<bool>(
      context: context,
      contentWidth: AccountingPopoutTokens.dialogContentWidth,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        title: 'Remove Preview',
        content: const Text(
          'Remove this preview from the list? You can restore it while this screen is open.',
        ),
        actions: [
          AccountingButton.ghost(
            dialogContext,
            key: const ValueKey('cancel-remove-preview'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          AccountingButton.destructive(
            dialogContext,
            key: const ValueKey('confirm-remove-preview'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canRemovePreview(record)) return;
    setState(() {
      (_removedPreviews[form.title] ??= {}).add('${record['_reference']}');
    });
  }

  String _previewValueLabel(
    DesignForm form,
    Map<String, Object?> record,
    String field,
    Object? value,
  ) {
    final workspace = widget.workspace;
    final configured = form.title == 'Sales Receipts' && workspace != null
        ? _catalogueSalesReceiptForm(form, workspace, initial: record)
        : form;
    return configured.fields
            .where((f) => f.label == field)
            .firstOrNull
            ?.choiceLabels?['$value'] ??
        '$value';
  }

  Widget _previewRecord(DesignForm form, Map<String, Object?> record) {
    final amount = record['Amount'];
    final priced = amount is String && amount.trim().isNotEmpty;
    final actions = <Widget>[
      if (record['_attachments'] is List)
        for (final attachment
            in (record['_attachments'] as List).whereType<ReceiptAttachment>())
          AccountingButton.outline(
            context,
            key: ValueKey('record-attachment-${attachment.originalId}'),
            onPressed: () => showAttachmentPreview(context, attachment),
            child: Text(attachment.filename),
          ),
      AccountingButton.outline(
        context,
        key: ValueKey('view-record-${record['_reference']}'),
        onPressed: () => _openFrontendPreviewForm(
          context,
          form,
          initial: record,
          settingsWorkspace: widget.workspace,
          employeePayeeSearch: widget.employeePayeeSearch,
          accountOptions: const ['Demo Bank', 'Operating Expenses'],
        ),
        child: const Text('View'),
      ),
      AccountingButton.iconOnly(
        context,
        key: ValueKey('delete-record-${record['_reference']}'),
        onPressed: _canRemovePreview(record)
            ? () => _removePreviewRecord(form, record)
            : null,
        icon: Icons.delete_outline,
        tooltip: _canRemovePreview(record)
            ? 'Remove Preview'
            : 'Only unapproved preview records can be removed',
      ),
    ];
    final row = AccountingRecordRow(
      topRightInfo: priced,
      padding: accountingContentPadding,
      title:
          '${record['Counterparty'] ?? record['Name'] ?? record['_reference']}',
      status: AccountingBadge.build(context, label: '${record['_status']}'),
      details: Text(
        '${record['_reference']} · ${record['Date']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AccountingTypography.helper(context),
      ),
      trailing: priced
          ? Text(
              key: ValueKey('record-amount-${record['_reference']}'),
              formatAccountingMoney(
                context,
                Money.fromDecimal(
                  amount,
                  record['Currency'] is String
                      ? record['Currency'] as String
                      : 'MYR',
                ),
              ),
              style: AccountingTypography.fieldLabel(context),
            )
          : AccountingButtonSizeScope(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
      trailingBelow: priced ? AccountingRecordActions(trailing: actions) : null,
    );
    return KeyedSubtree(key: ValueKey(record['_reference']), child: row);
  }

  (DateTime, DateTime)? _reportDateRange() {
    final now = DateTime.now();
    final through = DateTime.utc(now.year, now.month, now.day);
    return switch (_period) {
      'This Month' => (DateTime.utc(now.year, now.month), through),
      'This Quarter' => (
        DateTime.utc(now.year, ((now.month - 1) ~/ 3) * 3 + 1),
        through,
      ),
      'This Year' => (DateTime.utc(now.year), through),
      'Last Year' => (
        DateTime.utc(now.year - 1),
        DateTime.utc(now.year - 1, 12, 31),
      ),
      'Custom' => switch ((
        parseAccountingInputDate(_customFrom.text),
        parseAccountingInputDate(_customThrough.text),
      )) {
        (final DateTime from, final DateTime end) when !from.isAfter(end) => (
          from,
          end,
        ),
        _ => null,
      },
      _ => (DateTime.utc(1900), through),
    };
  }

  Widget _reportLayout(String title) {
    final rows = switch (title) {
      'Cash Flow' => [
        'Operating Activities',
        'Investing Activities',
        'Financing Activities',
        'Net Change In Cash',
        'Opening Cash',
        'Closing Cash',
      ],
      'Changes In Equity' => [
        'Opening Equity',
        'Profit / Loss',
        'Owner Contributions',
        'Distributions',
        'Closing Equity',
      ],
      'Receivables Ageing' || 'Payables Ageing' => [
        'Current',
        '1–30 Days',
        '31–60 Days',
        '61–90 Days',
        'Over 90 Days',
        'Total Outstanding',
      ],
      'Tax Reconciliation' => [
        'Taxable Amount',
        'Tax Charged',
        'Adjustments',
        'Return Amount',
        'Payments',
        'Difference',
      ],
      _ => [
        'Cover Page',
        'Profit And Loss',
        'Balance Sheet',
        'Cash Flow',
        'Notes',
      ],
    };
    final headers = switch (title) {
      'Cash Flow' => ('Cash movement', 'Amount'),
      'Changes In Equity' => ('Equity movement', 'Amount'),
      'Receivables Ageing' ||
      'Payables Ageing' => ('Ageing bucket', 'Outstanding'),
      'Tax Reconciliation' => ('Tax measure', 'Amount'),
      _ => ('Section', 'Value'),
    };
    Widget table(
      Map<String, String> values,
      String description,
      String? note,
    ) => AccountingSummaryTableCard(
      key: ValueKey('report-preview-table-$title'),
      title: title,
      description: description,
      labelHeader: headers.$1,
      valueHeader: headers.$2,
      rows: [for (final row in rows) (row, values[row] ?? '—')],
      note: note,
    );
    final workspace = widget.workspace;
    if (workspace == null) {
      return table(
        const {},
        'Report layout preview · Figures will come from the ledger after integration.',
        null,
      );
    }
    final range = _appliedReportRanges[title] ?? _reportDateRange();
    if (range == null) {
      return table(const {}, 'Choose a valid date range.', null);
    }
    final key = '${range.$1.toIso8601String()}|${range.$2.toIso8601String()}';
    if (_ledgerFuture == null || _ledgerRangeKey != key) {
      _ledgerRangeKey = key;
      _ledgerFuture = workspace.report(from: range.$1, through: range.$2);
    }
    return FutureBuilder<LedgerReport>(
      future: _ledgerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return table(const {}, 'Ledger report could not be loaded.', null);
        }
        final report = snapshot.data;
        if (report == null) {
          return table(const {}, 'Loading posted ledger activity…', null);
        }
        final values = _reportValues(title, report, workspace);
        return table(
          values.$1,
          title == 'Tax Reconciliation' && DemoCompany.active(context)
              ? 'Sample tax figures · design preview, not ledger-derived'
              : title == 'Tax Reconciliation'
              ? 'Tax-return comparison unavailable.'
              : 'Posted ledger activity · ${formatAccountingInputDate(range.$1)}–${formatAccountingInputDate(range.$2)}',
          values.$2,
        );
      },
    );
  }

  (Map<String, String>, String?) _reportValues(
    String title,
    LedgerReport report,
    AccountingWorkspace workspace,
  ) {
    String money(BigInt amount) => formatAccountingMoney(
      context,
      Money.fromMinor(amount.toInt(), report.currency),
    );
    BigInt total(Iterable<BigInt> amounts) =>
        amounts.fold(BigInt.zero, (sum, amount) => sum + amount);
    if (title == 'Tax Reconciliation' && DemoCompany.active(context)) {
      return (
        {
          'Taxable Amount': money(BigInt.from(128475000)),
          'Tax Charged': money(BigInt.from(7708500)),
          'Adjustments': money(BigInt.from(-124500)),
          'Return Amount': money(BigInt.from(7584000)),
          'Payments': money(BigInt.from(6000000)),
          'Difference': money(BigInt.from(1584000)),
        },
        'Illustrative values only. Tax classifications and payments are not connected to the ledger.',
      );
    }
    final cashIds = {
      for (final payment in workspace.paymentAccounts)
        ?workspace.database.paymentLedgerAccount(
          workspace.identity.businessId,
          payment.id,
        ),
    };
    final cashRows = report.rows.where(
      (row) => cashIds.contains(row.account.id),
    );
    final openingCash = total(cashRows.map((row) => row.openingNetDebit));
    final closingCash = total(cashRows.map((row) => row.endingNetDebit));
    final cashChange = closingCash - openingCash;
    if (title == 'Cash Flow') {
      final accounts = {
        for (final row in report.rows) row.account.id: row.account,
      };
      final classified = <String, BigInt>{
        'Operating Activities': BigInt.zero,
        'Investing Activities': BigInt.zero,
        'Financing Activities': BigInt.zero,
      };
      var incomplete = false;
      for (final entry in report.postedEntries) {
        final entryDay = DateTime.utc(
          entry.date.year,
          entry.date.month,
          entry.date.day,
        );
        if (entryDay.isBefore(report.from) ||
            entryDay.isAfter(report.through)) {
          continue;
        }
        final cashDelta = total(
          entry.lines
              .where((line) => cashIds.contains(line.accountId))
              .map(
                (line) => line.isDebit
                    ? BigInt.from(line.amount.minorUnits)
                    : -BigInt.from(line.amount.minorUnits),
              ),
        );
        if (cashDelta == BigInt.zero) continue;
        final others = entry.lines
            .where((line) => !cashIds.contains(line.accountId))
            .map((line) => accounts[line.accountId])
            .whereType<Account>()
            .toList();
        String? category;
        if (others.isNotEmpty &&
            others.every(
              (account) =>
                  account.type == AccountType.equity ||
                  account.type == AccountType.liability &&
                      RegExp(
                        r'loan|borrow',
                        caseSensitive: false,
                      ).hasMatch(account.name),
            )) {
          category = 'Financing Activities';
        } else if (others.isNotEmpty &&
            others.every(
              (account) =>
                  account.type == AccountType.asset &&
                  RegExp(
                    r'fixed|equipment|investment|property',
                    caseSensitive: false,
                  ).hasMatch(account.name),
            )) {
          category = 'Investing Activities';
        } else if (others.isNotEmpty &&
            others.every(
              (account) =>
                  account.type == AccountType.income ||
                  account.type == AccountType.expense ||
                  RegExp(
                    r'receivable|payable|inventory|tax',
                    caseSensitive: false,
                  ).hasMatch(account.name),
            )) {
          category = 'Operating Activities';
        }
        if (category == null) {
          incomplete = true;
        } else {
          classified[category] = classified[category]! + cashDelta;
        }
      }
      return (
        {
          for (final item in classified.entries)
            item.key: cashIds.isEmpty || incomplete ? '—' : money(item.value),
          'Net Change In Cash': cashIds.isEmpty ? '—' : money(cashChange),
          'Opening Cash': cashIds.isEmpty ? '—' : money(openingCash),
          'Closing Cash': cashIds.isEmpty ? '—' : money(closingCash),
        },
        cashIds.isEmpty
            ? 'Link a payment account to a cash or bank ledger account to calculate cash flow.'
            : incomplete
            ? 'Some cash entries need an activity classification; the cash totals remain ledger-derived.'
            : null,
      );
    }
    if (title == 'Changes In Equity') {
      final openingEquity = -total(
        report.rows
            .where(
              (row) =>
                  row.account.type == AccountType.equity ||
                  row.account.type == AccountType.income ||
                  row.account.type == AccountType.expense,
            )
            .map((row) => row.openingNetDebit),
      );
      final contributions = -total(
        report.rows
            .where(
              (row) =>
                  row.account.type == AccountType.equity &&
                  RegExp(
                    r'capital|contribution',
                    caseSensitive: false,
                  ).hasMatch(row.account.name),
            )
            .map((row) => row.operatingNetDebit),
      );
      final distributions = total(
        report.rows
            .where(
              (row) =>
                  row.account.type == AccountType.equity &&
                  RegExp(
                    r'draw|distribution',
                    caseSensitive: false,
                  ).hasMatch(row.account.name),
            )
            .map((row) => row.operatingNetDebit),
      );
      return (
        {
          'Opening Equity': money(openingEquity),
          'Profit / Loss': money(report.periodProfit),
          'Owner Contributions': money(contributions),
          'Distributions': money(distributions),
          'Closing Equity': money(report.totalEquity),
        },
        'Owner movements use equity accounts named capital, contribution, draw, or distribution.',
      );
    }
    if (title == 'Receivables Ageing') {
      final receivables = workspace.database.receivablesAsOf(
        workspace.identity.businessId,
        report.through,
      );
      final values = <String, String>{};
      for (final bucket in [
        'Current',
        '1–30 Days',
        '31–60 Days',
        '61–90 Days',
        'Over 90 Days',
      ]) {
        values[bucket] = money(
          total(
            receivables
                .where(
                  (row) =>
                      row.bucket == bucket &&
                      row.remaining.currency == report.currency,
                )
                .map((row) => BigInt.from(row.remaining.minorUnits)),
          ),
        );
      }
      values['Total Outstanding'] = money(
        total(
          receivables
              .where((row) => row.remaining.currency == report.currency)
              .map((row) => BigInt.from(row.remaining.minorUnits)),
        ),
      );
      return (values, null);
    }
    if (title == 'Management Report Pack') {
      return (
        {
          'Profit And Loss': money(report.periodProfit),
          'Balance Sheet': money(report.assets),
          'Cash Flow': cashIds.isEmpty ? '—' : money(cashChange),
        },
        'Values show period profit, closing assets, and net cash movement. Cover page and notes have no monetary total.',
      );
    }
    return (
      const {},
      title == 'Payables Ageing'
          ? 'Open a company to run Payables Ageing from posted Bills and dated payments.'
          : title == 'Tax Reconciliation'
          ? 'Tax-return allocations and statutory filing basis are not implemented. Book tax activity and remittance evidence do not establish a filed return or its balance.'
          : null,
    );
  }

  @override
  void didUpdateWidget(covariant FrontendAreaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _drafts.clear();
      _removedPreviews.clear();
      _reportInputs.clear();
      _appliedReportRanges.clear();
      oldWidget.workspace?.removeListener(_invalidateLedger);
      widget.workspace?.addListener(_invalidateLedger);
      _ledgerFuture = null;
      _ledgerRangeKey = null;
    }
    if (oldWidget.area != widget.area) {
      _selected = 0;
      _search = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final forms = widget.formsOverride ?? frontendAreas[widget.area]!;
    final available = <String>{
      if (widget.existing != null) widget.existingLabel!,
      ...forms.map((form) => form.title),
      ...widget.extraPages.keys,
    }.toList();
    final order = switch (widget.area) {
      'sales-customers' => const [
        'Invoices',
        'Customers',
        'Credit Notes',
        'Receipts',
        'Products & Services',
      ],
      'expenses-vendors' => const [
        'Expenses',
        'Bills',
        'Claims',
        'Payment Vouchers',
        'Vendors',
        'Pay Bills',
        'Supplier Credits',
        'Purchase Orders',
      ],
      'accounting' => const [
        'Chart Of Accounts',
        'Journal Review',
        'Accounting Review Queue',
      ],
      _ => const <String>[],
    };
    final labels = [
      ...order.where(available.contains),
      ...available.where((label) => !order.contains(label)),
    ];
    if (!_initialised) {
      final initial = labels.indexOf(widget.initialPage ?? '');
      if (initial >= 0) _selected = initial;
      _initialised = true;
    }
    final selectedLabel = labels[_selected];
    final form = widget.extraPages.containsKey(selectedLabel)
        ? null
        : forms.where((form) => form.title == selectedLabel).firstOrNull;
    final selectedPage = widget.extraPages[selectedLabel] ?? widget.existing;
    final previewRows = form == null
        ? const <Map<String, Object?>>[]
        : demoRecords(form);
    final hasPreviewRows =
        form != null &&
        (DemoCompany.active(context)
            ? previewRows.isNotEmpty
            : _drafts.containsKey(form.title));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingPageAlignment(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AccountingResponsive.tabStripTopInset,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AccountingTheme.of(context).muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AccountingTabs(
                  key: ValueKey('area-tabs-${widget.area}'),
                  labels: labels,
                  notificationCounts: widget.notificationCounts,
                  selectedIndex: _selected,
                  keyPrefix: 'preview-tab-${widget.area}',
                  revealSelectedOnResize: true,
                  onChanged: (index) => setState(() => _selected = index),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: form == null
              ? selectedPage!
              : AccountingPageShell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AccountingPageHeader(
                        routeLabel: widget.title,
                        title: form.title,
                        titleKey: 'page-title-${widget.area}',
                        description: _hasLivePeriod(form.title)
                            ? 'Posted ledger activity for the selected period.'
                            : form.description ?? 'Explore this accounting workflow before backend approval.',
                        action: AccountingButton.primary(
                          context,
                          key: const ValueKey('design-open-form'),
                          leadingIcon:
                              !_drafts.containsKey(form.title) &&
                                  form.startsRecord
                              ? Icons.add_rounded
                              : null,
                          onPressed: () async {
                            if (_hasLivePeriod(form.title)) {
                              await _openReportPeriod(form);
                              return;
                            }
                            final accounts =
                                await widget.loadAccountNames?.call() ??
                                <String>[];
                            if (!context.mounted) return;
                            final result = await openFrontendForm(
                              context,
                              form,
                              initial: _drafts[form.title],
                              accountOptions: accounts,
                              settingsWorkspace: widget.workspace,
                              employeePayeeSearch: widget.employeePayeeSearch,
                            );
                            if (result != null && mounted) {
                              setState(() => _drafts[form.title] = result);
                            }
                          },
                          child: Text(
                            _hasLivePeriod(form.title)
                                ? 'Run Report'
                                : _drafts.containsKey(form.title)
                                ? 'Edit Preview'
                                : form.primaryAction,
                          ),
                        ),
                      ),
                      const SizedBox(height: accountingPageTitleOuterGap),
                      if (hasPreviewRows &&
                          AccountingRecordControlsPolicy.visible(
                            previewRows.length,
                          ))
                        Wrap(
                          spacing: accountingContentInset,
                          runSpacing: AccountingPageControlScope.runGapOf(
                            context,
                          ),
                          children: [
                            SizedBox(
                              width: math.max(
                                240,
                                AccountingResponsive.measuredTextWidth(
                                      context,
                                      'Search ${form.title}',
                                      AccountingTypography.controlValue(
                                        context,
                                      ),
                                    ) +
                                    accountingContentInset * 2,
                              ),
                              child: TextField(
                                key: const ValueKey('preview-record-search'),
                                decoration:
                                    accountingSingleLineInputDecoration(
                                      context,
                                      hintText: 'Search ${form.title}',
                                    ).copyWith(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal:
                                                accountingFieldContentInset,
                                            vertical: 12,
                                          ),
                                    ),
                                onChanged: (value) =>
                                    setState(() => _search = value),
                              ),
                            ),
                            for (final label in ['Date Range', 'Status'])
                              AccountingSelector<String>(
                                triggerKey: ValueKey('preview-filter-$label'),
                                options: [
                                  for (final value
                                      in label == 'Date Range'
                                          ? [
                                              'All Dates',
                                              'This Month',
                                              'This Quarter',
                                              'This Year',
                                              'Last Year',
                                              'Custom',
                                            ]
                                          : [
                                              'All Statuses',
                                              'Draft',
                                              'Needs Review',
                                              'Approved',
                                              'Completed',
                                              'Paid',
                                              'Partially Paid',
                                              'Overdue',
                                              'Rejected',
                                              'Active',
                                              'Inactive',
                                            ])
                                    AccountingSelectorOption(
                                      value: value,
                                      label: value,
                                    ),
                                ],
                                value: label == 'Date Range'
                                    ? _period
                                    : _status,
                                onChanged: (value) => setState(() {
                                  if (label == 'Date Range') {
                                    _period = value;
                                  } else {
                                    _status = value;
                                  }
                                }),
                                hintText: label,
                                menuWidth: 220,
                              ),
                          ],
                        ),
                      if (hasPreviewRows &&
                          AccountingRecordControlsPolicy.visible(
                            previewRows.length,
                          ) &&
                          _period == 'Custom')
                        Padding(
                          padding: const EdgeInsets.only(
                            top: accountingContentInset,
                          ),
                          child: Wrap(
                            spacing: accountingContentInset,
                            runSpacing: AccountingPageControlScope.runGapOf(
                              context,
                            ),
                            children: [
                              for (final label in ['From', 'Through'])
                                SizedBox(
                                  width:
                                      accountingCompactDateFieldWidth +
                                      accountingContentInset,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      accountingFieldLabel(
                                        context,
                                        label,
                                        key: ValueKey(
                                          'preview-custom-${label.toLowerCase()}-label',
                                        ),
                                      ),
                                      const SizedBox(
                                        height: accountingFieldLabelGap,
                                      ),
                                      TextField(
                                        key: ValueKey(
                                          'preview-custom-${label.toLowerCase()}',
                                        ),
                                        controller: label == 'From'
                                            ? _customFrom
                                            : _customThrough,
                                        enableInteractiveSelection: true,
                                        inputFormatters: const [
                                          DateInputFormatter(),
                                        ],
                                        onChanged: (_) => setState(() {}),
                                        decoration:
                                            accountingSingleLineInputDecoration(
                                              context,
                                              hintText: 'DD-MM-YYYY',
                                            ).copyWith(
                                              suffixIcon:
                                                  accountingCalendarButton(
                                                    context,
                                                    controller: label == 'From'
                                                        ? _customFrom
                                                        : _customThrough,
                                                    label: label,
                                                  ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (hasPreviewRows &&
                          AccountingRecordControlsPolicy.visible(
                            previewRows.length,
                          ))
                        const SizedBox(height: accountingContentInset),
                      if (form.title == 'Deadlines') ...[
                        Row(
                          children: [
                            AccountingButton.ghost(
                              context,
                              key: const ValueKey('deadlines-list-view'),
                              onPressed: () =>
                                  setState(() => _calendar = false),
                              child: const Text('List'),
                            ),
                            AccountingButton.ghost(
                              context,
                              key: const ValueKey('deadlines-calendar-view'),
                              onPressed: () => setState(() => _calendar = true),
                              child: const Text('Calendar'),
                            ),
                          ],
                        ),
                        if (_calendar)
                          SizedBox(
                            width: 360,
                            child: CalendarDatePicker(
                              initialDate: _calendarDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2200),
                              onDateChanged: (value) =>
                                  setState(() => _calendarDate = value),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.area == 'reports') _reportLayout(form.title),
                      if (widget.area == 'reports')
                        const SizedBox(height: accountingContentInset),
                      AccountingRecordList(
                        paginationKey: '${widget.area}-${form.title}',
                        totalCount: DemoCompany.active(context)
                            ? previewRows.length
                            : (_drafts.containsKey(form.title) ? 1 : 0),
                        children: [
                          if (DemoCompany.active(context))
                            for (final record in previewRows.where(
                              (r) =>
                                  !(_removedPreviews[form.title]?.contains(
                                        '${r['_reference']}',
                                      ) ??
                                      false) &&
                                  (!AccountingRecordControlsPolicy.visible(
                                        previewRows.length,
                                      ) ||
                                      (!AccountingRecordControlsPolicy.visible(
                                                previewRows.length,
                                              ) ||
                                              _status == 'All Statuses' ||
                                              r['_status'] == _status) &&
                                          (() {
                                            final range = _reportDateRange();
                                            final date =
                                                parseAccountingInputDate(
                                                  '${r['Date'] ?? ''}',
                                                );
                                            return range == null ||
                                                (date != null &&
                                                    !date.isBefore(range.$1) &&
                                                    !date.isAfter(range.$2));
                                          })() &&
                                          r.toString().toLowerCase().contains(
                                            _search.toLowerCase(),
                                          )),
                            ))
                              _previewRecord(form, record)
                          else if (_drafts[form.title] case final draft?)
                            if (draft.toString().toLowerCase().contains(
                              _search.toLowerCase(),
                            ))
                              Padding(
                                padding: accountingContentPadding,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (form.title == 'Sales Receipts'
                                              ? [
                                                  for (final field
                                                      in form.fields)
                                                    if (draft.containsKey(
                                                      field.label,
                                                    ))
                                                      MapEntry(
                                                        field.label,
                                                        draft[field.label],
                                                      ),
                                                ]
                                              : draft.entries)
                                          .where(
                                            (entry) =>
                                                !entry.key.startsWith('_'),
                                          )
                                          .take(3)
                                          .map(
                                            (entry) =>
                                                '${entry.key}: ${_previewValueLabel(form, draft, entry.key, entry.value)}',
                                          )
                                          .join(' · '),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Design only · Not saved to accounting',
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Padding(
                                padding: accountingContentPadding,
                                child: Text('No matching preview records.'),
                              )
                          else
                            const Padding(
                              padding: accountingContentPadding,
                              child: Text(
                                'No preview records. Open the form to explore its fields and selections.',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: accountingContentInset),
                      if (DemoCompany.active(context) &&
                          (_removedPreviews[form.title]?.isNotEmpty ?? false))
                        AccountingButton.ghost(
                          context,
                          key: ValueKey('restore-previews-${form.title}'),
                          onPressed: () => setState(
                            () => _removedPreviews.remove(form.title),
                          ),
                          child: Text(
                            'Restore Removed Previews (${_removedPreviews[form.title]!.length})',
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(left: accountingContentInset),
                        child: Text(
                          'Preview records last only while this screen is open. Existing accounting records are unaffected.',
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
