import '../accounting/domain/payment_account.dart';
import '../accounting/domain/bank_statement_import.dart';
import '../accounting/presentation/attachment_preview_dialog.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';

import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/frontend_review.dart';
import '../../core/ids/entity_id.dart';
import '../../core/money/money.dart';
import '../../core/money/currency_presentation.dart';
import '../../core/dates/accounting_date.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/domain/account.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import 'invoice_form.dart';

class CustomerReceiptsPage extends StatefulWidget {
  const CustomerReceiptsPage({
    super.key,
    required this.workspace,
    this.statementRow,
    this.statementAccount,
    this.initialDate,
    this.popout = false,
  });
  final AccountingWorkspace workspace;
  final BankStatementRow? statementRow;
  final PaymentAccount? statementAccount;
  final DateTime? initialDate;
  final bool popout;
  @override
  State<CustomerReceiptsPage> createState() => _CustomerReceiptsPageState();
}

class _CustomerReceiptsPageState extends State<CustomerReceiptsPage> {
  final selected = <EntityId>{};
  String search = '';
  String _invoiceAmountLabel(int index) =>
      'Amount Received for Invoice ${index + 1}';

  Future<void> receive() async {
    final invoices = widget.workspace
        .postedInvoices()
        .where(
          (r) =>
              selected.contains(r.sourceDraft.id) &&
              r.paidMinor + r.creditedMinor < r.sourceDraft.total.minorUnits,
        )
        .toList();
    if (invoices.isEmpty) return;
    final customer = invoices.first.sourceDraft.customerId;
    final currency = invoices.first.sourceDraft.total.currency;
    if (invoices.any(
      (r) =>
          r.sourceDraft.customerId != customer ||
          r.sourceDraft.total.currency != currency,
    )) {
      return;
    }
    final accounts = (await widget.workspace.accounts())
        .map((r) => r.account)
        .where(
          (a) =>
              a.type == AccountType.asset &&
              a.status == AccountStatus.active &&
              !a.isParent,
        )
        .toList();
    final payments = widget.workspace.paymentAccounts
        .where(
          (p) =>
              p.type != PaymentAccountType.card &&
              p.currency.code == currency &&
              accounts.any(
                (a) =>
                    a.id ==
                    widget.workspace.database.paymentLedgerAccount(
                      widget.workspace.identity.businessId,
                      p.id,
                    ),
              ),
        )
        .toList();
    if (!mounted) return;
    if (payments.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AccountingDialog.alert(
          dialogContext,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: 'Set Up A Payment Account',
          content: const Text(
            'In Banking, link a bank or cash payment account to an active ledger account in the invoice currency, then return to receive payment.',
          ),
          actions: [],
        ),
      );
      return;
    }

    final request = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: DesignForm(
          'Receive Customer Payment',
          [
            const DesignField('Date', required: true),
            const DesignField('Reference', required: true),
            DesignField(
              'Bank Account',
              required: true,
              choiceLabels: {for (final p in payments) p.id: p.displayLabel},
            ),
            for (var i = 0; i < invoices.length; i++)
              DesignField(
                _invoiceAmountLabel(i),
                required: true,
                currencyCode: currency,
              ),
          ],
          actionLabel: 'Record Payment',
          description: 'Enter the amount received for each invoice. The total received is their sum.',
        ),
        informationRows: [
          ('Customer', invoices.first.customerSnapshot.displayName),
          ('Currency', CurrencyPresentation.fromCode(currency).amountSymbol),
          for (var i = 0; i < invoices.length; i++)
            ('Invoice ${i + 1}', invoices[i].documentNumber),
        ],
        initial: {
          'Date': formatAccountingInputDate(
            widget.statementRow?.date ?? widget.initialDate ?? DateTime.now(),
          ),
          if (widget.statementRow?.reference.isNotEmpty == true)
            'Reference': widget.statementRow!.reference,
          if (widget.statementAccount != null &&
              payments.any(
                (account) => account.id == widget.statementAccount!.id,
              ))
            'Bank Account': widget.statementAccount!.id,
          for (var i = 0; i < invoices.length; i++)
            _invoiceAmountLabel(i): invoiceDecimal(
              invoices.length == 1 &&
                      widget.statementRow?.amount.currency == currency &&
                      widget.statementRow!.amount.minorUnits > 0 &&
                      widget.statementRow!.amount.minorUnits <=
                          invoices[i].sourceDraft.total.minorUnits -
                              invoices[i].paidMinor -
                              invoices[i].creditedMinor
                  ? widget.statementRow!.amount
                  : Money.fromMinor(
                      invoices[i].sourceDraft.total.minorUnits -
                          invoices[i].paidMinor -
                          invoices[i].creditedMinor,
                      currency,
                    ),
            ),
        },
        reviewInformationRowsBuilder: (values) {
          var total = Money.zero(currency);
          final rows = <(String, String)>[];
          for (var i = 0; i < invoices.length; i++) {
            final amount = Money.fromDecimal(
              values[_invoiceAmountLabel(i)] as String,
              currency,
            );
            final remaining =
                invoices[i].sourceDraft.total.minorUnits -
                invoices[i].paidMinor -
                invoices[i].creditedMinor;
            if (!amount.isPositive || amount.minorUnits > remaining) {
              throw FormatException(
                'Invoice ${i + 1} needs a positive amount no more than its remaining balance.',
              );
            }
            total += amount;
            rows.add((invoices[i].documentNumber, invoiceMoney(amount)));
          }
          return [...rows, ('Total Received', invoiceMoney(total))];
        },
        onCommit: (values) async => widget.workspace.receiveInvoicePayment(
          requestId: request,
          customerId: customer,
          paymentAccountId: values['Bank Account'] as String,
          bankAccountId:
              widget.workspace.database.paymentLedgerAccount(
                widget.workspace.identity.businessId,
                values['Bank Account'] as String,
              ) ??
              (throw StateError(
                'Link this payment account to a ledger account in Banking.',
              )),
          allocations: {
            for (var i = 0; i < invoices.length; i++)
              invoices[i].sourceDraft.id: Money.fromDecimal(
                values[_invoiceAmountLabel(i)] as String,
                currency,
              ),
          },
          reference: values['Reference'] as String,
          receivedAt:
              parseAccountingInputDate(values['Date'] as String) ??
              (throw const FormatException('Enter a valid payment date.')),
          approvedAt: approvedAt,
        ),
      ),
    );
    if (mounted && result != null) setState(selected.clear);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final outstanding = widget.workspace
          .postedInvoices()
          .where(
            (r) =>
                r.paidMinor + r.creditedMinor < r.sourceDraft.total.minorUnits,
          )
          .toList();
      final chosen = outstanding
          .where((r) => selected.contains(r.sourceDraft.id))
          .toList();
      final allHistory = widget.workspace.database.customerReceiptHistory(
        widget.workspace.identity.businessId,
      );
      final controlCount = outstanding.length + allHistory.length;
      final effectiveSearch =
          AccountingRecordControlsPolicy.visible(controlCount) ? search : '';
      final visible = outstanding
          .where(
            (r) => '${r.documentNumber} ${r.customerSnapshot.displayName}'
                .toLowerCase()
                .contains(effectiveSearch.toLowerCase()),
          )
          .toList();
      final history = allHistory
          .where(
            (r) =>
                '${r.customer} ${r.reference} ${r.allocations.map((a) => a.number).join(' ')}'
                    .toLowerCase()
                    .contains(effectiveSearch.toLowerCase()),
          )
          .toList();
      final receiveButton = AccountingButton.primary(
        context,
        key: const ValueKey('receive-selected-invoices'),
        onPressed: chosen.isEmpty ? null : receive,
        child: Text('Receive Payment (${chosen.length})'),
      );
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.popout)
            AccountingPageHeader(
              routeLabel: 'Receive Payment',
              title: 'Receive Payment',
              description: 'Select outstanding invoices for one customer and currency, then review the amounts received.',
              action: receiveButton,
            ),
          if (!widget.popout)
            const SizedBox(height: accountingPageTitleOuterGap),
          if (AccountingRecordControlsPolicy.visible(controlCount))
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: SizedBox(
                  width: double.infinity,
                  height: accountingControlHeight,
                  child: TextField(
                    key: const ValueKey('receipt-search'),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: accountingSingleLineInputDecoration(
                      context,
                      hintText: 'Search payments',
                    ),
                    onChanged: (value) => setState(() => search = value),
                  ),
                ),
              ),
            ),
          if (AccountingRecordControlsPolicy.visible(controlCount))
            const SizedBox(height: 16),
          if (visible.isEmpty)
            const AccountingPageText('No outstanding invoices.'),
          AccountingRecordList(
            paginationKey: 'customer-outstanding',
            totalCount: outstanding.length,
            children: [
              for (final record in visible)
                AccountingRecordRow(
                  topRightInfo: true,
                  leadingOverlaysTitle: true,
                  title: record.documentNumber,
                  status: AccountingBadge.build(
                    context,
                    label: record.paidMinor + record.creditedMinor == 0
                        ? 'Unpaid'
                        : record.sourceDraft
                              .settlementStatus(
                                paidMinor: record.paidMinor,
                                creditedMinor: record.creditedMinor,
                              )
                              .label,
                  ),
                  statusWidth: AccountingBadge.measuredWidth(
                    context,
                    record.paidMinor + record.creditedMinor == 0
                        ? 'Unpaid'
                        : record.sourceDraft
                              .settlementStatus(
                                paidMinor: record.paidMinor,
                                creditedMinor: record.creditedMinor,
                              )
                              .label,
                  ),
                  compactStatus: record.paidMinor + record.creditedMinor > 0
                      ? Tooltip(
                          message: record.sourceDraft
                              .settlementStatus(
                                paidMinor: record.paidMinor,
                                creditedMinor: record.creditedMinor,
                              )
                              .label,
                          child: AccountingBadge.build(
                            context,
                            label: record.sourceDraft
                                .settlementStatus(
                                  paidMinor: record.paidMinor,
                                  creditedMinor: record.creditedMinor,
                                )
                                .compactLabel,
                          ),
                        )
                      : null,
                  leading: AccountingLeadingCheckbox(
                    checkboxKey: ValueKey(
                      'select-receipt-${record.sourceDraft.id.value}',
                    ),
                    semanticLabel: 'Select ${record.documentNumber}',
                    value: selected.contains(record.sourceDraft.id),
                    onChanged:
                        chosen.isEmpty ||
                            (record.sourceDraft.customerId ==
                                    chosen.first.sourceDraft.customerId &&
                                record.sourceDraft.total.currency ==
                                    chosen.first.sourceDraft.total.currency)
                        ? (value) => setState(() {
                            if (value == true) {
                              selected.add(record.sourceDraft.id);
                            } else {
                              selected.remove(record.sourceDraft.id);
                            }
                          })
                        : null,
                  ),
                  details: Text(record.customerSnapshot.displayName),
                  trailing: Text(
                    formatAccountingMoney(
                      context,
                      Money.fromMinor(
                        record.sourceDraft.total.minorUnits -
                            record.paidMinor -
                            record.creditedMinor,
                        record.sourceDraft.total.currency,
                      ),
                    ),
                    style: AccountingTypography.value(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  actions: [
                    AccountingRecordActions(
                      trailing: [
                        for (final attachment in record.sourceDraft.attachments)
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'receipt-evidence-${record.sourceDraft.id.value}-${attachment.originalId}',
                            ),
                            icon:
                                attachment.originalMimeType.startsWith('image/')
                                ? Icons.image_outlined
                                : Icons.description_outlined,
                            tooltip: 'View ${attachment.filename}',
                            onPressed: () =>
                                showAttachmentPreview(context, attachment),
                          ),
                        AccountingButton.outline(
                          context,
                          key: ValueKey(
                            'receipt-view-${record.sourceDraft.id.value}',
                          ),
                          child: const Text('View'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AccountingDialog.alert(
                              dialogContext,
                              widthFamily: AccountingPopoutWidthFamily.normal,
                              title: record.documentNumber,
                              content: AccountingInformationRows(
                                rows: [
                                  (
                                    'Customer',
                                    record.customerSnapshot.displayName,
                                  ),
                                  (
                                    'Total',
                                    invoiceMoney(record.sourceDraft.total),
                                  ),
                                  (
                                    'Paid',
                                    invoiceMoney(
                                      Money.fromMinor(
                                        record.paidMinor,
                                        record.sourceDraft.total.currency,
                                      ),
                                    ),
                                  ),
                                  (
                                    'Credited',
                                    invoiceMoney(
                                      Money.fromMinor(
                                        record.creditedMinor,
                                        record.sourceDraft.total.currency,
                                      ),
                                    ),
                                  ),
                                  if (record.sourceDraft.memo.isNotEmpty)
                                    ('Memo', record.sourceDraft.memo),
                                ],
                              ),
                              actions: [],
                            ),
                          ),
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey(
                            'receipt-locked-${record.sourceDraft.id.value}',
                          ),
                          icon: Icons.delete_outline,
                          tooltip:
                              'Posted invoices require a linked correction.',
                          onPressed: null,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: accountingContentInset),
            child: accountingSectionTitle(context, 'Received Payments'),
          ),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AccountingPageText(
                search.trim().isEmpty
                    ? 'No payments received yet.'
                    : 'No matching received payments.',
              ),
            ),
          const SizedBox(height: 12),
          AccountingRecordList(
            paginationKey: 'customer-payment-history',
            totalCount: allHistory.length,
            children: [
              for (final receipt in history)
                AccountingRecordRow(
                  topRightInfo: true,
                  title: receipt.reference,
                  details: Text(
                    '${receipt.customer} · ${formatAccountingInputDate(receipt.date)}',
                  ),
                  trailing: Text(
                    invoiceMoney(receipt.total),
                    style: AccountingTypography.value(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  actions: [
                    AccountingRecordActions(
                      trailing: [
                        AccountingButton.outline(
                          context,
                          key: ValueKey('view-payment-${receipt.requestId}'),
                          child: const Text('View'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AccountingDialog.alert(
                              dialogContext,
                              widthFamily: AccountingPopoutWidthFamily.normal,
                              title: receipt.reference,
                              content: AccountingInformationRows(
                                rows: [
                                  ('Customer', receipt.customer),
                                  (
                                    'Date',
                                    formatAccountingInputDate(receipt.date),
                                  ),
                                  ('Total', invoiceMoney(receipt.total)),
                                  for (final allocation in receipt.allocations)
                                    (
                                      allocation.number,
                                      invoiceMoney(allocation.amount),
                                    ),
                                ],
                              ),
                              actions: [],
                            ),
                          ),
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('locked-payment-${receipt.requestId}'),
                          icon: Icons.delete_outline,
                          tooltip:
                              'Posted payments require a linked correction.',
                          onPressed: null,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      if (widget.popout) {
        return AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: 'Receive Payment',
          description: 'Select outstanding invoices for one customer and currency, then review the amounts received.',
          maxContentWidth: AccountingPopoutTokens.customContentWidth,
          content: SizedBox(
            width: AccountingPopoutTokens.customContentWidth,
            child: body,
          ),
          actions: [receiveButton],
        );
      }
      return AccountingPageShell(child: body);
    },
  );
}
