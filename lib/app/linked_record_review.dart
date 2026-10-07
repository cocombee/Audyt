import 'package:flutter/material.dart';

import '../core/money/currency_presentation.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';

/// Frontend-only demonstration of source-linked accounting transitions.
/// No example is treated as a live invoice, payment, or journal.
class LinkedRecordReview extends StatefulWidget {
  const LinkedRecordReview({super.key, required this.workflow});
  final String workflow;
  @override
  State<LinkedRecordReview> createState() => _LinkedRecordReviewState();
}

class _LinkedRecordReviewState extends State<LinkedRecordReview> {
  bool _examples = false;
  String? _source;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _reviewed = false;
  String? _error;
  bool get _refund => widget.workflow == 'Refunds';
  bool get _credit =>
      ['Credit Notes', 'Supplier Credits'].contains(widget.workflow);
  bool get _outgoing =>
      ['Pay Bills', 'Supplier Credits'].contains(widget.workflow);
  int get _original => 100000;
  int get _remaining => _source == 'EXAMPLE-002' ? 40000 : 100000;
  String get _sourceLabel => _outgoing ? 'Bill' : 'Sale';
  String get _verb => _refund
      ? 'Refund'
      : _credit
      ? 'Credit'
      : 'Payment';
  String money(int value) =>
      currencyAmountLabel('MYR', (value / 100).toStringAsFixed(2));
  int? get _entered {
    final text = _amount.text.trim();
    if (!RegExp(r'^\d+(?:,\d{3})*(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.replaceAll(',', '').split('.');
    return int.tryParse(parts[0])! * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 96).clamp(220.0, 680.0);
    return AccountingDialog.alert(
      context,
      title: widget.workflow,
      formFooter: true,
      maxContentWidth: width,
      description: 'Design preview · No live records are loaded or posted.',
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select Existing $_sourceLabel',
                style: AccountingTypography.sectionTitle(context),
              ),
              const SizedBox(height: 6),
              if (!_examples) ...[
                Text(
                  'Choose a saved $_sourceLabel to reuse its customer or supplier, currency, amounts and documents.',
                ),
                const SizedBox(height: 12),
                AccountingButton.outline(
                  context,
                  key: const ValueKey('load-linked-examples'),
                  onPressed: () => setState(() => _examples = true),
                  child: const Text('Try Example Records'),
                ),
              ] else
                AccountingSelector<String>(
                  assignedWidth: width,
                  menuWidth: width,
                  triggerKey: const ValueKey('linked-source'),
                  options: const [
                    AccountingSelectorOption(
                      value: 'EXAMPLE-001',
                      label: 'Example 001 · Full Balance',
                    ),
                    AccountingSelectorOption(
                      value: 'EXAMPLE-002',
                      label: 'Example 002 · Partial Balance',
                    ),
                  ],
                  value: _source,
                  hintText: 'Select Example Record',
                  onChanged: (value) => setState(() {
                    _source = value;
                    _amount.text = (_remaining / 100).toStringAsFixed(2);
                    _reviewed = false;
                    _error = null;
                  }),
                ),
              if (_source != null) ...[
                const SizedBox(height: 20),
                AccountingInformationRows(
                  rows: [
                    (
                      'Source',
                      '$_source · Example ${_outgoing ? 'Supplier' : 'Customer'}',
                    ),
                    ('Original $_sourceLabel Amount', money(_original)),
                    (
                      _refund
                          ? 'Previously Refunded'
                          : _credit
                          ? 'Previously Credited'
                          : 'Previously Allocated',
                      money(_original - _remaining),
                    ),
                    (
                      '${_refund
                          ? 'Refundable'
                          : _credit
                          ? 'Creditable'
                          : 'Outstanding'} Balance',
                      money(_remaining),
                    ),
                  ],
                ),
                if (_refund)
                  const Text(
                    'Example sale is fully paid. An unpaid invoice needs a credit adjustment, not a cash refund.',
                  ),
                const SizedBox(height: 16),
                if (_credit)
                  accountingFieldLabel(
                    context,
                    '$_verb Amount (${CurrencyPresentation.fromCode('MYR').amountSymbol})',
                    alignToField: true,
                    guidance: 'Credit reduces the source balance. It does not itself return money. Source line and tax allocations must be reviewed before posting.',
                  )
                else
                  Text(
                    '$_verb Amount (${CurrencyPresentation.fromCode('MYR').amountSymbol})',
                    style: AccountingTypography.fieldLabel(context),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('linked-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [AccountingMoneyInputFormatter(2)],
                  decoration: accountingSingleLineInputDecoration(context),
                  onChanged: (_) => setState(() {
                    _reviewed = false;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  'Remaining After $_verb: ${_entered == null || _entered! > _remaining ? 'Check Amount' : money(_remaining - _entered!)}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _reason,
                  decoration: accountingSingleLineInputDecoration(context)
                      .copyWith(hintText: 'Reason / Reference'),
                  onChanged: (_) => setState(() => _reviewed = false),
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Existing Evidence',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 4),
                    AccountingFieldHelp(
                      label: 'Existing Evidence',
                      message: 'Production uses the original record’s document links.',
                    ),
                  ],
                ),
                Text(
                  'Source document: $_source · Example only; no file is attached.',
                ),
                if (_credit)
                  const Text(
                    'Credit adjusts the source balance; no cash is refunded.',
                  ),
                if (!_credit)
                  const Text(
                    'Record money moved outside Audyt. This screen does not send a bank payment.',
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AccountingTheme.of(context).destructive,
                    ),
                  ),
                if (_reviewed) ...[
                  const Divider(height: 24),
                  Text(
                    'Preview Ready · ${money(_entered!)} linked to $_source',
                  ),
                  const Text(
                    'Source details and evidence are reused. No new upload is required. Nothing has been posted.',
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        AccountingButton.preview(
          context,
          key: const ValueKey('review-linked-record'),
          onPressed: _source == null
              ? null
              : () => setState(() {
                  final value = _entered;
                  if (value == null || value <= 0 || value > _remaining) {
                    _error =
                        'Enter an amount above zero and no more than ${money(_remaining)}.';
                    _reviewed = false;
                  } else if ((_refund || _credit) &&
                      _reason.text.trim().isEmpty) {
                    _error = 'Enter a reason for this adjustment.';
                    _reviewed = false;
                  } else {
                    _error = null;
                    _reviewed = true;
                  }
                }),
        ),
      ],
    );
  }
}
