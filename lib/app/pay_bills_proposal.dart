import '../core/dates/accounting_date.dart';
import 'transaction_form_layout.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';
import '../core/money/money.dart';

import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'frontend_review.dart';

/// Isolated, fictional design review. No workspace, channel or posting command.
class PayBillsProposal extends StatefulWidget {
  const PayBillsProposal({super.key});
  @override
  State<PayBillsProposal> createState() => _PayBillsProposalState();
}

class _PayBillsProposalState extends State<PayBillsProposal> {
  static const _balances = [60000, 40000];
  static const _credits = [10000, 5000];
  final _selected = <int>{0, 1};
  final _payments = [
    TextEditingController(text: '600.00'),
    TextEditingController(text: '400.00'),
  ];
  final _creditInputs = [
    TextEditingController(text: '0.00'),
    TextEditingController(text: '0.00'),
  ];
  static const _accounts = {
    'bank': 'Fictional Bank',
    'cash': 'Fictional Cash',
    'card': 'Fictional Credit Card',
  };

  @override
  void dispose() {
    for (final controller in [..._payments, ..._creditInputs]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _minor(String text) {
    try {
      final amount = Money.fromDecimal(text.replaceAll(',', ''), 'MYR');
      return amount.minorUnits < 0 ? null : amount.minorUnits;
    } on FormatException {
      return null;
    }
  }

  String _decimal(int amount) => (amount / 100).toStringAsFixed(2);
  int? get _total {
    var total = 0;
    for (final i in _selected) {
      final payment = _minor(_payments[i].text),
          credit = _minor(_creditInputs[i].text);
      if (payment == null ||
          credit == null ||
          credit > _credits[i] ||
          payment + credit > _balances[i]) {
        return null;
      }
      total += payment;
    }
    return total;
  }

  DesignForm _form(Map<String, Object?> values) => DesignForm('Pay Bills', [
    const DesignField(
      'Payment Account',
      required: true,
      choiceLabels: _accounts,
    ),
    const DesignField('Payment Date', required: true),
    if (values['Payment Account'] != 'card') const DesignField('Reference'),
  ], actionLabel: 'Record Bill Payment');

  List<(String, String)> _review(Map<String, Object?> values) {
    final date = parseAccountingInputDate('${values['Payment Date'] ?? ''}');
    if (date == null || date.isBefore(DateTime(2026, 10, 1))) {
      throw const FormatException(
        'Choose a payment date on or after the selected bill dates.',
      );
    }
    if (_selected.isEmpty ||
        _total == null ||
        !_selected.any(
          (i) =>
              (_minor(_payments[i].text) ?? 0) +
                  (_minor(_creditInputs[i].text) ?? 0) >
              0,
        )) {
      throw const FormatException(
        'Select a bill and keep Payment plus Credit Applied within its open balance and available credit.',
      );
    }
    return [
      for (final i in _selected) ...[
        ('Bill ${i + 1}', 'DEMO-B00${i + 1}'),
        ('Payment ${i + 1} (RM)', _payments[i].text),
        ('Credit Applied ${i + 1} (RM)', _creditInputs[i].text),
      ],
      ('Total Payment (RM)', _decimal(_total!)),
    ];
  }

  Widget _amount(
    BuildContext context,
    String label,
    String key,
    TextEditingController controller,
    bool enabled,
  ) => SizedBox(
    width: AccountingTransactionGridTokens.numericWidth(
      context,
      label,
      [controller.text],
      minimumText: '$label (RM)',
      title: '$label (RM)',
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingFieldLabel(context, '$label (RM)', alignToField: true),
        const SizedBox(height: accountingFieldLabelGap),
        TextField(
          key: ValueKey(key),
          controller: controller,
          enabled: enabled,
          style: AccountingTypography.controlValue(context),
          textAlign: TextAlign.right,
          inputFormatters: [AccountingMoneyInputFormatter(2)],
          decoration: accountingSingleLineInputDecoration(context),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
  );

  Widget _billRows(BuildContext context, bool reviewing) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: accountingContentInset),
      Text(
        'Outstanding Bills',
        style: AccountingTypography.sectionTitle(context),
      ),
      const SizedBox(height: accountingFieldLabelGap),
      accountingHelperText(
        context,
        'Select bills and apply available supplier credits.',
      ),
      for (var i = 0; i < _balances.length; i++) ...[
        const SizedBox(height: accountingContentInset),
        AccountingRecordRow(
          key: ValueKey('pay-bills-row-$i'),
          topRightInfo: true,
          leadingOverlaysTitle: true,
          leading: AccountingLeadingCheckbox(
            value: _selected.contains(i),
            hitKey: ValueKey('pay-bills-select-$i'),
            semanticLabel: 'Select DEMO-B00${i + 1}',
            onChanged: reviewing
                ? null
                : (checked) => setState(() {
                    checked == true ? _selected.add(i) : _selected.remove(i);
                  }),
          ),
          title: 'Fictional Supplier ${i + 1}',
          details: Text(
            'DEMO-B00${i + 1} · Due 31-10-2026\nAvailable Supplier Credit (RM): ${_decimal(_credits[i])}',
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Open Balance (RM)',
                style: AccountingTypography.fieldLabel(context),
              ),
              Text(
                _decimal(_balances[i]),
                style: AccountingTypography.value(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: accountingFieldLabelGap),
        Wrap(
          spacing: accountingContentInset,
          runSpacing: accountingContentInset,
          children: [
            _amount(
              context,
              'Payment',
              'pay-bills-payment-$i',
              _payments[i],
              !reviewing && _selected.contains(i),
            ),
            _amount(
              context,
              'Credit Applied',
              'pay-bills-credit-$i',
              _creditInputs[i],
              !reviewing && _selected.contains(i),
            ),
          ],
        ),
        const SizedBox(height: accountingContentInset),
        const Divider(),
      ],
      AccountingInformationRows(
        rows: [
          (
            'Total Payment (RM)',
            _total == null ? 'Check Allocations' : _decimal(_total!),
          ),
        ],
      ),
      if (_total == null)
        accountingHelperText(
          context,
          'Payment plus Credit Applied cannot exceed a bill balance; credit cannot exceed the available supplier credit.',
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => FrontendFormDialog(
    form: _form({'Payment Account': 'bank'}),
    initial: const {'Payment Account': 'bank', 'Payment Date': '02-10-2026'},
    valuesFormBuilder: _form,
    additionalContentBuilder: (context, _, reviewing) =>
        reviewing ? const SizedBox.shrink() : _billRows(context, false),
    reviewInformationRowsBuilder: _review,
  );
}
