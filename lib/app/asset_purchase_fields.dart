import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'field_row_trial.dart';
import 'responsive.dart';
import '../core/money/currency_presentation.dart';
import '../core/money/money.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';

class AssetPurchaseFields extends StatefulWidget {
  const AssetPurchaseFields({
    super.key,
    required this.onChanged,
    this.ordinaryPopup = false,
    this.currencyCode = 'MYR',
  });
  final ValueChanged<Map<String, String>> onChanged;
  final bool ordinaryPopup;
  final String currencyCode;
  @override
  State<AssetPurchaseFields> createState() => _AssetPurchaseFieldsState();
}

class _AssetPurchaseFieldsState extends State<AssetPurchaseFields> {
  final values = <String, String>{
    'Purchase Treatment': 'Expense',
    'Asset Category': 'Equipment',
    'Book Method': 'Straight Line',
    'Tax Policy': 'Accountant Review Required',
  };
  void change(String key, String value) {
    setState(() => values[key] = value);
    widget.onChanged(Map.of(values));
  }

  Widget field(String name, {List<String> options = const []}) {
    final monetary = const {
      'Acquisition Cost',
      'Expense Portion',
      'Residual Value',
    }.contains(name);
    final currency = CurrencyPresentation.fromCode(widget.currencyCode);
    final label = monetary ? '$name (${currency.amountSymbol})' : name;
    final guidance = switch (name) {
      'Purchase Treatment' => 'Link this purchase to Fixed Assets. The original purchase remains linked; do not post it twice.',
      'Tax Policy' => 'Book depreciation and tax capital allowances are separate policies; no tax rate is assumed.',
      'Acquisition Cost' => 'Support the cost with the invoice and any ownership evidence in the purchase receipts.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (guidance != null)
          accountingFieldLabel(
            context,
            label,
            alignToField: true,
            guidance: guidance,
          )
        else
          Text(label, style: AccountingTypography.fieldLabel(context)),
        const SizedBox(height: accountingFieldLabelGap),
        if (options.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) => AccountingSelector<String>(
              assignedWidth: widget.ordinaryPopup ? constraints.maxWidth : null,
              value: values[name],
              hintText: 'Select $name',
              options: [
                for (final o in options)
                  AccountingSelectorOption(value: o, label: o),
              ],
              onChanged: (v) {
                if (v != null) change(name, v);
              },
            ),
          )
        else
          TextFormField(
            key: ValueKey('asset-purchase-field-$name'),
            initialValue: values[name],
            keyboardType: monetary
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : null,
            inputFormatters: monetary
                ? [
                    AccountingMoneyInputFormatter(
                      currency.currency.fractionDigits,
                    ),
                  ]
                : null,
            decoration: accountingSingleLineInputDecoration(
              context,
              hintText: monetary
                  ? formatAccountingInputAmount(Money.zero(currency.code))
                  : null,
            ),
            onChanged: (v) => change(name, v),
          ),
      ],
    );
  }

  Widget purchaseTreatment() {
    const choices = ['Expense', 'Asset Purchase', 'Split Expense / Asset'];
    if (!widget.ordinaryPopup) {
      return field('Purchase Treatment', options: choices);
    }
    return AccountingOrdinaryFields(
      fields: [
        AccountingOrdinaryFieldSlot(
          label: 'Purchase Treatment',
          hasGuidance: true,
          choices: choices,
          builder: (_) => field('Purchase Treatment', options: choices),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 32),
      purchaseTreatment(),
      if (values['Purchase Treatment'] != 'Expense') ...[
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final width =
                AccountingResponsive.fitsWithContentGap(c.maxWidth, const [
                  AccountingResponsive.fieldMinWidth,
                  AccountingResponsive.fieldMinWidth,
                ])
                ? (c.maxWidth - AccountingResponsive.groupGap) / 2
                : c.maxWidth;
            return Wrap(
              spacing: AccountingResponsive.groupGap,
              runSpacing: 16,
              children: [
                SizedBox(width: width, child: field('Asset Name')),
                SizedBox(
                  width: width,
                  child: field(
                    'Asset Category',
                    options: const [
                      'Equipment',
                      'Computer',
                      'Vehicle',
                      'Building',
                      'Land',
                      'Furniture',
                      'Construction In Progress',
                    ],
                  ),
                ),
                SizedBox(width: width, child: field('Acquisition Cost')),
                if (values['Purchase Treatment'] == 'Split Expense / Asset')
                  SizedBox(width: width, child: field('Expense Portion')),
                SizedBox(width: width, child: field('In Service Date')),
                if (values['Asset Category'] != 'Land' &&
                    values['Asset Category'] != 'Construction In Progress') ...[
                  SizedBox(width: width, child: field('Useful Life In Months')),
                  SizedBox(width: width, child: field('Residual Value')),
                  SizedBox(
                    width: width,
                    child: field(
                      'Book Method',
                      options: const [
                        'Straight Line',
                        'Reducing Balance',
                        'Accountant Review Required',
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  width: width,
                  child: field(
                    'Tax Policy',
                    options: const [
                      'Accountant Review Required',
                      'Not Claimed',
                      'Select Saved Policy Later',
                    ],
                  ),
                ),
                if ([
                  'Vehicle',
                  'Building',
                  'Land',
                ].contains(values['Asset Category']))
                  SizedBox(
                    width: width,
                    child: field('Ownership / Registration Reference'),
                  ),
              ],
            );
          },
        ),
      ],
      const SizedBox(height: 16),
    ],
  );
}
