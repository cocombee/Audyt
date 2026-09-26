import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/money/money.dart';
import '../application/account_repository.dart';
import '../domain/account.dart';
import 'widgets/accounting_formatters.dart';

/// Physical reconciliation adjustment owner. Saving remains unavailable until
/// a dedicated reference-bearing adjustment command is implemented.
Future<void> showReconciliationAdjustment(
  BuildContext context, {
  required List<StoredAccount> accounts,
  required EntityId bankLedgerId,
  required String bankLabel,
  required String currency,
  required DateTime initialDate,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReconciliationAdjustmentDialog(
    accounts: accounts,
    bankLedgerId: bankLedgerId,
    bankLabel: bankLabel,
    currency: currency,
    initialDate: initialDate,
  ),
);

enum _AdjustmentDirection { deposits, withdrawals }

class _ReconciliationAdjustmentDialog extends StatefulWidget {
  const _ReconciliationAdjustmentDialog({
    required this.accounts,
    required this.bankLedgerId,
    required this.bankLabel,
    required this.currency,
    required this.initialDate,
  });

  final List<StoredAccount> accounts;
  final EntityId bankLedgerId;
  final String bankLabel;
  final String currency;
  final DateTime initialDate;

  @override
  State<_ReconciliationAdjustmentDialog> createState() =>
      _ReconciliationAdjustmentDialogState();
}

class _ReconciliationAdjustmentDialogState
    extends State<_ReconciliationAdjustmentDialog> {
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _editingFocus = FocusScopeNode();
  final _directionFieldKey = GlobalKey();
  final _accountFieldKey = GlobalKey();
  _AdjustmentDirection _direction = _AdjustmentDirection.deposits;
  EntityId? _account;
  bool _closePromptOpen = false;
  late final String _openingInput;

  List<Account> get _accounts => widget.accounts
      .map((record) => record.account)
      .where(
        (account) =>
            account.id != widget.bankLedgerId &&
            !account.isParent &&
            account.status == AccountStatus.active &&
            (_direction == _AdjustmentDirection.deposits
                ? account.type == AccountType.income
                : const [
                    AccountType.asset,
                    AccountType.expense,
                    AccountType.liability,
                  ].contains(account.type)),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _date.text = formatAccountingInputDate(widget.initialDate);
    _openingInput = _inputSnapshot();
  }

  String _inputSnapshot() => jsonEncode([
    _direction.name,
    _date.text,
    _account?.value,
    _amount.text,
    _reference.text,
  ]);

  Future<void> _handleClose() async {
    if (_closePromptOpen) return;
    if (_inputSnapshot() != _openingInput) {
      _closePromptOpen = true;
      try {
        final discard = await AccountingDialog.confirmDiscardChanges(
          context,
          closeKey: const ValueKey('adjustment-discard-close'),
          keepEditingKey: const ValueKey('adjustment-keep-editing'),
          discardKey: const ValueKey('adjustment-discard-changes'),
        );
        if (!mounted) return;
        if (!discard) {
          _editingFocus.requestFocus();
          return;
        }
      } finally {
        _closePromptOpen = false;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reference.dispose();
    _editingFocus.dispose();
    super.dispose();
  }

  Widget _field(String label, Widget child, {Key? key}) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(context, label, alignToField: true),
      const SizedBox(height: accountingFieldLabelGap),
      child,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    final amountZeroHint = formatAccountingInputAmount(
      Money.zero(widget.currency),
    );
    final amountLabel =
        'Amount (${CurrencyPresentation.fromCode(widget.currency).amountSymbol}) *';
    return FocusScope(
      node: _editingFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
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
          title: 'Add Transaction',
          description:
              '${widget.bankLabel} · This adjustment cannot be saved yet.',
          onClose: _handleClose,
          closeKey: const ValueKey('adjustment-editor-close'),
          formFooter: true,
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: AccountingOrdinaryFields(
                fields: [
                  AccountingOrdinaryFieldSlot(
                    label: 'Apply To',
                    choices: const ['Deposits', 'Withdrawals'],
                    builder: (width) => _field(
                      'Apply To',
                      AccountingSelector<_AdjustmentDirection>(
                        triggerKey: const ValueKey('adjustment-direction'),
                        assignedWidth: width,
                        value: _direction,
                        hintText: 'Select Direction',
                        searchable: false,
                        options: const [
                          AccountingSelectorOption(
                            value: _AdjustmentDirection.deposits,
                            label: 'Deposits',
                          ),
                          AccountingSelectorOption(
                            value: _AdjustmentDirection.withdrawals,
                            label: 'Withdrawals',
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _direction = value ?? _direction;
                          if (!_accounts.any((a) => a.id == _account)) {
                            _account = null;
                          }
                        }),
                      ),
                      key: _directionFieldKey,
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: 'Date *',
                    date: true,
                    contentSample: '00-00-0000',
                    builder: (_) => _field(
                      'Date *',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          accountingDateFieldFrame(
                            child: TextField(
                              key: const ValueKey('adjustment-date'),
                              controller: _date,
                              enableInteractiveSelection: true,
                              inputFormatters: [const DateInputFormatter()],
                              decoration:
                                  accountingSingleLineInputDecoration(
                                    context,
                                    hintText: 'DD-MM-YYYY',
                                  ).copyWith(
                                    suffixIcon: accountingCalendarButton(
                                      context,
                                      controller: _date,
                                      label: 'Date',
                                      onPicked: () => setState(() {}),
                                    ),
                                  ),
                            ),
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          AccountingButtonSizeScope(
                            child: AccountingButton.ghost(
                              context,
                              key: const ValueKey('adjustment-today'),
                              onPressed: () => setState(() {
                                _date.text = formatAccountingInputDate(
                                  DateTime.now(),
                                );
                              }),
                              child: const Text("Use Today's Date"),
                            ),
                          ),
                        ],
                      ),
                      key: GlobalObjectKey(_date),
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: 'Account *',
                    choices: [
                      'Select Account',
                      for (final account in accounts) account.displayName,
                    ],
                    minimumRowFraction: 0.5,
                    builder: (width) => _field(
                      'Account *',
                      AccountingSelector<EntityId>(
                        triggerKey: const ValueKey('adjustment-account'),
                        assignedWidth: width,
                        value: _account,
                        hintText: 'Select Account',
                        options: [
                          for (final account in accounts)
                            AccountingSelectorOption(
                              value: account.id,
                              label: account.displayName,
                              group: accountingTitleCase(account.type.name),
                              preserveLabelCase: true,
                            ),
                        ],
                        onChanged: (value) => setState(() => _account = value),
                      ),
                      key: _accountFieldKey,
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: amountLabel,
                    // This independent Amount uses a stable ordinary minimum.
                    // Preserve its fitted row; transactional growth belongs
                    // to the addable line owners, not this control.
                    contentSample: amountZeroHint,
                    builder: (_) => _field(
                      amountLabel,
                      TextField(
                        key: const ValueKey('adjustment-amount'),
                        controller: _amount,
                        enableInteractiveSelection: true,
                        inputFormatters: [
                          AccountingMoneyInputFormatter(
                            Currency.parse(widget.currency).fractionDigits,
                          ),
                        ],
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: amountZeroHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      key: GlobalObjectKey(_amount),
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: 'Reference #',
                    contentSample: _reference.text.isEmpty
                        ? 'Reference'
                        : _reference.text,
                    builder: (_) => _field(
                      'Reference #',
                      TextField(
                        key: const ValueKey('adjustment-reference'),
                        controller: _reference,
                        enableInteractiveSelection: true,
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: 'Reference',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      key: GlobalObjectKey(_reference),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Tooltip(
              message: 'Saving this adjustment is not available yet.',
              child: AccountingButton.primary(
                context,
                key: const ValueKey('save-reconciliation-adjustment'),
                onPressed: null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
