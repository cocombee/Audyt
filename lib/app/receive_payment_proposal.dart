import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/money/money.dart';
import '../core/money/currency_presentation.dart';
import '../features/sales/invoice_form.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';
import 'accounting_components.dart';
import 'accounting_description_field.dart';
import 'accounting_theme.dart';
import 'frontend_review.dart';
import 'transaction_form_layout.dart';

/// An isolated review projection, never a payment posting command.
@immutable
class ReceivePaymentInvoice {
  const ReceivePaymentInvoice({
    required this.id,
    required this.customerId,
    required this.customer,
    required this.filename,
    required this.total,
    this.paidMinor = 0,
    this.creditedMinor = 0,
    this.posted = true,
    this.reversed = false,
  });
  final String id, customerId, customer, filename;
  final Money total;
  final int paidMinor, creditedMinor;
  final bool posted, reversed;
  int get outstandingMinor => total.minorUnits - paidMinor - creditedMinor;
  bool get eligible => posted && !reversed && outstandingMinor > 0;
}

final receivePaymentExamples = <ReceivePaymentInvoice>[
  ReceivePaymentInvoice(
    id: 'a1',
    customerId: 'a',
    customer: 'A Company',
    filename: 'INV-A',
    total: Money.fromMinor(60000, 'MYR'),
  ),
  ReceivePaymentInvoice(
    id: 'a2',
    customerId: 'a',
    customer: 'A Company',
    filename: 'INV-B',
    total: Money.fromMinor(50000, 'MYR'),
    paidMinor: 10000,
  ),
  ReceivePaymentInvoice(
    id: 'b1',
    customerId: 'b',
    customer: 'B Company',
    filename: 'INV-C',
    total: Money.fromMinor(30000, 'MYR'),
  ),
  ReceivePaymentInvoice(
    id: 'c1',
    customerId: 'c',
    customer: 'C Company',
    filename: 'INV-A',
    total: Money.fromMinor(20000, 'MYR'),
  ),
  ReceivePaymentInvoice(
    id: 'paid',
    customerId: 'd',
    customer: 'D Cleared Company',
    filename: 'INV-PAID',
    total: Money.fromMinor(20000, 'MYR'),
    paidMinor: 20000,
  ),
  ReceivePaymentInvoice(
    id: 'credited',
    customerId: 'e',
    customer: 'E Credited Company',
    filename: 'INV-CREDITED',
    total: Money.fromMinor(10000, 'MYR'),
    creditedMinor: 10000,
  ),
];

/// Both entry paths use this owner. No workspace, database or commit callback.
class ReceivePaymentProposal extends StatefulWidget {
  const ReceivePaymentProposal({
    super.key,
    this.invoices,
    this.initialInvoiceId,
  });
  final List<ReceivePaymentInvoice>? invoices;
  final String? initialInvoiceId;
  @override
  State<ReceivePaymentProposal> createState() => _ReceivePaymentProposalState();
}

class _ReceivePaymentProposalState extends State<ReceivePaymentProposal> {
  String? _choice;
  final _selected = <String>{};
  final _allocations = <String, TextEditingController>{};
  Map<String, Object?> _draft = {'Payment Date': '02-10-2026'};

  List<ReceivePaymentInvoice> get _eligible =>
      (widget.invoices ?? receivePaymentExamples)
          .where((i) => i.eligible)
          .toList()
        ..sort((a, b) {
          final company = a.customer.toLowerCase().compareTo(
            b.customer.toLowerCase(),
          );
          if (company != 0) return company;
          final name = a.filename.toLowerCase().compareTo(
            b.filename.toLowerCase(),
          );
          return name != 0 ? name : a.id.compareTo(b.id);
        });
  Map<String, List<ReceivePaymentInvoice>> get _choices => {
    for (final i in _eligible) 'invoice:${i.id}': [i],
  };
  List<ReceivePaymentInvoice> get _visible => _choices[_choice] ?? [];
  String get _currency => _visible.firstOrNull?.total.currency ?? 'MYR';
  String get _symbol => CurrencyPresentation.fromCode(_currency).amountSymbol;
  String _number(int minor) =>
      invoiceDecimal(Money.fromMinor(minor, _currency));
  int? _minor(Object? value) {
    try {
      return Money.fromDecimal(
        '${value ?? '0'}'.replaceAll(',', ''),
        _currency,
      ).minorUnits;
    } on FormatException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = _eligible
        .where((i) => i.id == widget.initialInvoiceId)
        .firstOrNull;
    if (initial != null) {
      _choice = 'invoice:${initial.id}';
      _selected.add(initial.id);
    }
  }

  @override
  void dispose() {
    for (final c in _allocations.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(String? choice) => setState(() {
    _choice = choice;
    _selected.clear();
    for (final c in _allocations.values) {
      c.clear();
    }
    _draft.remove('Amount Received');
    if (choice?.startsWith('invoice:') == true) {
      _selected.add(_visible.single.id);
    }
  });
  DesignForm get _form => DesignForm(
    'Receive Payment',
    [
      if (_visible.isNotEmpty) ...[
        const DesignField('Payment Date', required: true),
        const DesignField('Reference'),
        const DesignField('Payment Method', options: paymentMethods),
        const DesignField(
          'Deposit To',
          required: true,
          choiceLabels: {'bank': 'Fictional Bank', 'cash': 'Fictional Cash'},
        ),
        DesignField('Amount Received', required: true, currencyCode: _currency),
        const DesignField(
          'Memo',
          multiline: true,
          fullWidth: true,
          descriptionRole: AccountingDescriptionRole.memo,
        ),
      ],
    ],
    defaultCurrencyCode: _currency,
    actionLabel: 'Record Payment',
  );

  Widget _lookup(
    BuildContext context,
    Map<String, Object?> values,
    bool reviewing,
  ) {
    _draft = Map.of(values);
    final choices = _choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingFieldLabel(
          context,
          'Customer or Invoice',
          alignToField: true,
        ),
        const SizedBox(height: accountingFieldLabelGap),
        LayoutBuilder(
          builder: (context, constraints) => AccountingSelector<String>(
            assignedWidth: constraints.maxWidth,
            triggerKey: const ValueKey('receive-payment-lookup'),
            menuKey: const ValueKey('receive-payment-menu'),
            searchKey: const ValueKey('receive-payment-search'),
            hintText: 'Search Customer or Filename',
            searchHintText: 'Search Customer or Filename',
            alwaysSearchable: true,
            emptyText: 'No Outstanding Invoices',
            value: _choice,
            enabled: !reviewing,
            options: [
              for (final entry in choices.entries)
                AccountingSelectorOption(
                  key: ValueKey('receive-choice-${entry.key}'),
                  value: entry.key,
                  label:
                      '${entry.value.first.customer} - ${entry.value.first.filename}',
                  preserveLabelCase: true,
                ),
            ],
            onChanged: _choose,
          ),
        ),
        if (_visible.isNotEmpty) ...[
          const SizedBox(height: accountingContentInset),
          AccountingInformationRows(
            key: const ValueKey('receive-payment-details'),
            rows: [
              ('Customer', _visible.first.customer),
              if (_choice!.startsWith('invoice:'))
                ('Invoice', _visible.single.filename),
              (
                'Outstanding',
                invoiceMoney(
                  Money.fromMinor(
                    _visible.fold(0, (n, i) => n + i.outstandingMinor),
                    _currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
        ],
      ],
    );
  }

  Widget _rows(
    BuildContext context,
    Map<String, Object?> values,
    bool reviewing,
  ) {
    if (_visible.isEmpty || reviewing) return const SizedBox.shrink();
    final received = _minor(values['Amount Received']) ?? 0;
    final applied = _selected.fold(
      0,
      (n, id) => n + (_minor(_allocations[id]?.text) ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: accountingContentInset),
        Text(
          'Outstanding Invoices',
          style: AccountingTypography.sectionTitle(context),
        ),
        for (final i in _visible) ...[
          const SizedBox(height: accountingContentInset),
          AccountingRecordRow(
            leadingOverlaysTitle: true,
            topRightInfo: true,
            leading: AccountingLeadingCheckbox(
              value: _selected.contains(i.id),
              hitKey: ValueKey('receive-select-${i.id}'),
              semanticLabel: 'Select ${i.customer} - ${i.filename}',
              onChanged: (checked) => setState(() {
                checked == true ? _selected.add(i.id) : _selected.remove(i.id);
                if (checked != true) {
                  _allocations[i.id]?.clear();
                }
              }),
            ),
            title: i.filename,
            details: Text(i.customer),
            trailing: Text(
              invoiceMoney(Money.fromMinor(i.outstandingMinor, _currency)),
              style: AccountingTypography.value(context),
            ),
          ),
          const SizedBox(height: accountingFieldLabelGap),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: AccountingTransactionGridTokens.numericWidth(
                context,
                'Payment',
                [_number(i.outstandingMinor)],
                title: 'Payment ($_symbol)',
                minimumText: 'Payment ($_symbol)',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountingFieldLabel(
                    context,
                    'Payment ($_symbol)',
                    alignToField: true,
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  TextField(
                    key: ValueKey('receive-allocation-${i.id}'),
                    enabled: _selected.contains(i.id),
                    controller: _allocations.putIfAbsent(
                      i.id,
                      () => TextEditingController(),
                    ),
                    inputFormatters: [AccountingMoneyInputFormatter(2)],
                    textAlign: TextAlign.right,
                    style: AccountingTypography.controlValue(context),
                    decoration: accountingSingleLineInputDecoration(context),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: accountingContentInset),
        AccountingInformationRows(
          rows: [
            ('Amount Applied ($_symbol)', _number(applied)),
            (
              'Payment Not Applied ($_symbol)',
              _number(math.max(0, received - applied)),
            ),
          ],
        ),
        if (applied > received)
          accountingHelperText(
            context,
            'Amount applied exceeds the amount received.',
          ),
      ],
    );
  }

  List<(String, String)> _review(Map<String, Object?> values) {
    if (_visible.isEmpty || _selected.isEmpty) {
      throw const FormatException('Choose an outstanding customer or invoice.');
    }
    final received = _minor(values['Amount Received']);
    var applied = 0;
    for (final i in _visible.where((i) => _selected.contains(i.id))) {
      final amount = _minor(_allocations[i.id]?.text);
      if (amount == null || amount < 0 || amount > i.outstandingMinor) {
        throw const FormatException(
          'Payment must fit the invoice outstanding balance.',
        );
      }
      applied += amount;
    }
    if (received == null ||
        received <= 0 ||
        applied <= 0 ||
        applied > received) {
      throw const FormatException(
        'Enter an amount received and valid invoice allocations.',
      );
    }
    return [
      ('Customer', _visible.first.customer),
      for (final i in _visible.where((i) => _selected.contains(i.id)))
        (
          i.filename,
          invoiceMoney(
            Money.fromMinor(_minor(_allocations[i.id]?.text)!, _currency),
          ),
        ),
      ('Amount Received ($_symbol)', _number(received)),
      ('Payment Not Applied ($_symbol)', _number(received - applied)),
    ];
  }

  @override
  Widget build(BuildContext context) => FrontendFormDialog(
    key: ValueKey(_choice),
    form: _form,
    initial: _draft,
    leadingContentBuilder: _lookup,
    additionalContentBuilder: _rows,
    reviewInformationRowsBuilder: _review,
  );
}
