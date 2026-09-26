// Receipt-aware approval review proposal, using the existing dialog/row owners.
import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/field_row_trial.dart';
import '../../../app/responsive.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/expense_draft.dart';
import '../../accounting/presentation/widgets/accounting_formatters.dart';
import '../domain/claim.dart';

/// Exact reviewed row identities travel with the payable account to the
/// existing atomic approval command; labels never determine posting accounts.
final class ClaimExpenseApprovalSelection {
  ClaimExpenseApprovalSelection({
    required this.payableAccountId,
    required Map<String, EntityId> lineAccounts,
  }) : lineAccounts = Map.unmodifiable(lineAccounts);
  final EntityId payableAccountId;
  final Map<String, EntityId> lineAccounts;
}

class ClaimReceiptApprovalDialog extends StatefulWidget {
  const ClaimReceiptApprovalDialog({
    super.key,
    required this.claim,
    required this.accounts,
    this.currentExpense,
  });
  final Claim claim;
  final List<Account> accounts;

  /// Current approved-Claim Expense review retains its original liability and
  /// claimant. It does not manufacture a replacement Claim submission.
  final RecordExpenseDraft? currentExpense;
  @override
  State<ClaimReceiptApprovalDialog> createState() =>
      _ClaimReceiptApprovalDialogState();
}

class _ClaimReceiptApprovalDialogState
    extends State<ClaimReceiptApprovalDialog> {
  EntityId? _payable;
  final Map<String, EntityId> _lineAccounts = {};
  @override
  void initState() {
    super.initState();
    _payable = widget.currentExpense?.claimSource?.liabilityAccountId;
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final expense = widget.currentExpense ?? claim.expenseDraft;
    final expenseAccounts = widget.accounts
        .where(
          (a) =>
              !a.isParent &&
              a.status == AccountStatus.active &&
              [AccountType.expense, AccountType.asset].contains(a.type),
        )
        .toList();
    final reviewedAllLines =
        expense == null ||
        expense.lines.every(
          (line) => expenseAccounts.any(
            (account) => account.id == _lineAccounts[line.id],
          ),
        );
    final costs = <EntityId, Money>{};
    if (expense == null) {
      costs.addAll(claim.receiptCostAllocations);
    } else if (reviewedAllLines) {
      for (final line in expense.lines) {
        final gross = expense.lineCalculation(line).total;
        costs.update(
          _lineAccounts[line.id]!,
          (old) => old + gross,
          ifAbsent: () => gross,
        );
      }
    }
    final validCosts =
        reviewedAllLines &&
        costs.keys.every(
          (id) => widget.accounts.any(
            (a) =>
                a.id == id &&
                !a.isParent &&
                a.status == AccountStatus.active &&
                [AccountType.expense, AccountType.asset].contains(a.type),
          ),
        );
    String accountName(EntityId id) =>
        widget.accounts.where((a) => a.id == id).firstOrNull?.displayName ??
        'Unavailable account';
    final payableAccounts = widget.accounts
        .where(
          (a) =>
              a.type == AccountType.liability &&
              !a.isParent &&
              (widget.currentExpense == null
                  ? a.status == AccountStatus.active
                  : a.id == _payable),
        )
        .toList();
    final validPayable = payableAccounts.any(
      (a) => a.id == _payable && a.status == AccountStatus.active,
    );
    return AccountingDialog.alert(
      context,
      key: const ValueKey('claim-receipt-approval'),
      title: widget.currentExpense == null
          ? 'Approve Claim'
          : 'Review Claim Expense',
      description: expense == null
          ? 'Review each receipt and its ledger allocation before approving.'
          : 'Review each expense line and its ledger allocation before approving.',
      formFooter: true,
      fixedContentWidth: 600,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountingInformationRows(
            key: const ValueKey('claim-receipt-summary'),
            rows: [
              ('Claimant', claim.claimantName),
              (
                'Claim Total',
                formatAccountingMoney(
                  context,
                  expense == null
                      ? claim.amount
                      : Money.fromDecimal(expense.amount, expense.currencyCode),
                ),
              ),
            ],
          ),
          if (expense != null) ...[
            const SizedBox(height: AccountingResponsive.sectionGap),
            AccountingOrdinaryFields(
              fields: [
                for (var i = 0; i < expense.lines.length; i++)
                  AccountingOrdinaryFieldSlot(
                    label:
                        'Line ${i + 1} · ${expense.lines[i].category} · ${formatAccountingMoney(context, expense.lineCalculation(expense.lines[i]).total)}',
                    choices: [
                      'Select Account',
                      for (final a in expenseAccounts) a.displayName,
                    ],
                    builder: (width) {
                      final line = expense.lines[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accountingFieldLabel(
                            context,
                            'Line ${i + 1} · ${line.category} · ${formatAccountingMoney(context, expense.lineCalculation(line).total)}',
                            guidance: line.description.isEmpty
                                ? null
                                : line.description,
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          AccountingSelector<EntityId>(
                            assignedWidth: width,
                            triggerKey: ValueKey(
                              'claim-expense-account-${line.id}',
                            ),
                            hintText: 'Select Account',
                            value: _lineAccounts[line.id],
                            options: [
                              for (final a in expenseAccounts)
                                AccountingSelectorOption(
                                  value: a.id,
                                  label: a.displayName,
                                  preserveLabelCase: true,
                                ),
                            ],
                            onChanged: (id) => setState(() {
                              if (id == null) {
                                _lineAccounts.remove(line.id);
                              } else {
                                _lineAccounts[line.id] = id;
                              }
                            }),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ],
          for (
            var i = 0;
            widget.currentExpense == null && i < claim.receipts.length;
            i++
          ) ...[
            const SizedBox(height: AccountingResponsive.sectionGap),
            accountingSectionTitle(
              context,
              'Receipt ${i + 1} · ${claim.receipts[i].merchant}',
            ),
            AccountingInformationRows(
              rows: [
                (
                  'Amounts Are',
                  const {
                        'Exclusive',
                        'Inclusive',
                      }.contains(claim.receipts[i].taxMode)
                      ? 'Tax ${claim.receipts[i].taxMode}'
                      : claim.receipts[i].taxMode,
                ),
                (
                  'Subtotal',
                  formatAccountingMoney(context, claim.receipts[i].totals.net),
                ),
                (
                  'Tax',
                  formatAccountingMoney(context, claim.receipts[i].totals.tax),
                ),
                (
                  'Receipt Total',
                  formatAccountingMoney(
                    context,
                    claim.receipts[i].totals.total,
                  ),
                ),
                for (final l in claim.receipts[i].lines)
                  (
                    l.item.taxSnapshot?.label ?? 'No Tax',
                    '${accountName(l.expenseAccountId)} · ${formatAccountingMoney(context, l.item.calculation(claim.receipts[i].currency, claim.receipts[i].taxMode).total)}',
                  ),
              ],
            ),
          ],
          if (costs.isNotEmpty) ...[
            const SizedBox(height: AccountingResponsive.sectionGap),
            accountingSectionTitle(context, 'Ledger Allocation'),
            AccountingInformationRows(
              key: const ValueKey('claim-receipt-costs'),
              rows: [
                for (final entry in costs.entries)
                  (
                    accountName(entry.key),
                    formatAccountingMoney(context, entry.value),
                  ),
              ],
            ),
          ],
          if (!validCosts && expense == null)
            AccountingAlert.build(
              context,
              title: 'Category Selection Required',
              description: 'A receipt account is unavailable. Return the claim for correction.',
            ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Claims Payable Account',
                choices: [
                  'Select Claims Payable',
                  for (final a in payableAccounts) a.displayName,
                ],
                builder: (width) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accountingFieldLabel(
                      context,
                      'Claims Payable Account',
                      guidance: 'Purchase tax remains in expense or asset cost. Reimbursement settles Claims Payable.',
                    ),
                    const SizedBox(height: accountingFieldLabelGap),
                    AccountingSelector<EntityId>(
                      assignedWidth: width,
                      triggerKey: const ValueKey('claim-receipt-payable'),
                      menuKey: const ValueKey('claim-receipt-payable-menu'),
                      hintText: 'Select Claims Payable',
                      value: _payable,
                      enabled: widget.currentExpense == null,
                      options: [
                        for (final a in payableAccounts)
                          AccountingSelectorOption(
                            value: a.id,
                            label: a.displayName,
                            preserveLabelCase: true,
                          ),
                      ],
                      onChanged: (v) => setState(() => _payable = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AccountingButton.primary(
          context,
          key: const ValueKey('claim-receipt-approve'),
          onPressed: validCosts && validPayable
              ? () => Navigator.pop(
                  context,
                  expense == null
                      ? _payable
                      : ClaimExpenseApprovalSelection(
                          payableAccountId: _payable!,
                          lineAccounts: _lineAccounts,
                        ),
                )
              : null,
          child: Text(
            widget.currentExpense == null ? 'Approve Claim' : 'Review Journal',
          ),
        ),
      ],
    );
  }
}
