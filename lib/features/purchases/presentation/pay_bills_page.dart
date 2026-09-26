import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../../core/money/currency_presentation.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/data/accounting_database.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/payment_account.dart';
import '../../accounting/presentation/attachment_preview_dialog.dart';
import '../../accounting/presentation/widgets/accounting_layout.dart';
import '../../sales/invoice_form.dart' show invoiceDecimal, invoiceMoney;
import 'bill_form.dart';

class PayBillsPage extends StatefulWidget {
  const PayBillsPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<PayBillsPage> createState() => _PayBillsPageState();
}

class _PayBillsPageState extends State<PayBillsPage> {
  String _billAmountLabel(int index) => 'Amount Paid for Bill ${index + 1}';
  AccountingWorkspace get workspace => widget.workspace;
  final _search = TextEditingController();
  final _selected = <EntityId>{};
  String? _error;
  String? _status = 'Outstanding';
  int _offset = 0;
  int _pageSize = AccountingRecordPageSizes.read('pay-bill');
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    try {
      final bills = [
        for (final id in _selected)
          workspace.database.readBillPosting(
                workspace.identity.businessId,
                id,
              ) ??
              (throw StateError(
                'A selected bill is unavailable. Reopen the selection.',
              )),
      ];
      if (bills.isEmpty) return;
      final currency = bills.first.source.total.currency;
      if (bills.any((b) => b.source.total.currency != currency)) {
        throw StateError('Select bills in one currency per payment.');
      }
      final remaining = {
        for (final b in bills)
          b.source.id: workspace.database.billOutstanding(
            workspace.identity.businessId,
            b.source.id,
          ),
      };
      if (remaining.values.any((m) => !m.isPositive)) {
        throw StateError(
          'A selected bill was paid. Clear the selection and review the current balances.',
        );
      }
      final accounts = (await workspace.accounts())
          .map((a) => a.account)
          .toList();
      final payments = workspace.paymentAccounts
          .where(
            (p) =>
                p.type != PaymentAccountType.card &&
                p.currency.code == currency &&
                accounts.any(
                  (a) =>
                      a.id ==
                          workspace.database.paymentLedgerAccount(
                            workspace.identity.businessId,
                            p.id,
                          ) &&
                      a.type == AccountType.asset &&
                      a.status == AccountStatus.active &&
                      !a.isParent,
                ),
          )
          .toList();
      if (!mounted) return;
      if (payments.isEmpty) {
        throw StateError(
          'In Banking, link a bank or cash payment account to an active ledger account in ${CurrencyPresentation.fromCode(currency).amountSymbol}.',
        );
      }
      final request = EntityId.random();
      final approvedAt = DateTime.now().toUtc();
      List<BillSettlementAllocation> allocations(Map<String, Object?> values) =>
          [
            for (var i = 0; i < bills.length; i++)
              BillSettlementAllocation(
                billId: bills[i].source.id,
                revision: bills[i].source.metadata.revision,
                expectedRemaining: remaining[bills[i].source.id]!,
                amount: Money.fromDecimal(
                  values[_billAmountLabel(i)] as String,
                  currency,
                ),
              ),
          ];
      List<(String, String)> review(Map<String, Object?> values) {
        final selected = allocations(values);
        var total = Money.zero(currency);
        for (final a in selected) {
          if (!a.amount.isPositive ||
              a.amount.minorUnits > a.expectedRemaining.minorUnits) {
            throw const FormatException(
              'Each payment must be positive and no more than the remaining bill balance.',
            );
          }
          total += a.amount;
        }
        final date = parseAccountingInputDate(values['Date'] as String);
        if (date == null ||
            bills.any((b) => date.isBefore(b.source.bill.issueDate))) {
          throw const FormatException(
            'Choose a payment date on or after every selected bill date.',
          );
        }
        final reference = (values['Reference'] as String).trim();
        if (reference.isEmpty || reference.length > 120) {
          throw const FormatException(
            'Use a payment reference of 1–120 characters.',
          );
        }
        return [
          ('Date', formatAccountingInputDate(date)),
          ('Reference', reference),
          (
            'Bank Account',
            payments
                .firstWhere((p) => p.id == values['Bank Account'])
                .displayLabel,
          ),
          for (var i = 0; i < bills.length; i++) ...[
            (
              'Bill ${i + 1}',
              '${bills[i].source.documentNumber} · ${bills[i].source.vendorSnapshot.name}',
            ),
            ('Payment ${i + 1}', invoiceMoney(selected[i].amount)),
            (
              'Remaining ${i + 1}',
              invoiceMoney(selected[i].expectedRemaining - selected[i].amount),
            ),
          ],
          ('Total Payment', invoiceMoney(total)),
        ];
      }

      final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => FrontendFormDialog(
          form: DesignForm(
            'Pay Bills',
            [
              const DesignField('Date', required: true),
              const DesignField('Reference', required: true),
              DesignField(
                'Bank Account',
                required: true,
                choiceLabels: {for (final p in payments) p.id: p.displayLabel},
              ),
              for (var i = 0; i < bills.length; i++)
                DesignField(
                  _billAmountLabel(i),
                  required: true,
                  currencyCode: currency,
                ),
            ],
            actionLabel: 'Record Payment',
            description: 'Enter the amount paid for each bill. The total payment is their sum; it reduces the payable and bank balance without another expense.',
          ),
          informationRows: [
            for (var i = 0; i < bills.length; i++)
              (
                'Bill ${i + 1}',
                '${bills[i].source.documentNumber} · ${bills[i].source.vendorSnapshot.name} · ${invoiceMoney(remaining[bills[i].source.id]!)} remaining',
              ),
          ],
          initial: {
            'Date': formatAccountingInputDate(DateTime.now()),
            if (payments.length == 1) 'Bank Account': payments.single.id,
            for (var i = 0; i < bills.length; i++)
              _billAmountLabel(i): invoiceDecimal(
                remaining[bills[i].source.id]!,
              ),
          },
          reviewInformationRowsBuilder: review,
          onCommit: (values) async {
            review(values);
            workspace.settleRecognizedBills(
              requestId: request,
              allocations: allocations(values),
              paymentAccountId: values['Bank Account'] as String,
              paymentReference: values['Reference'] as String,
              paidOn: parseAccountingInputDate(values['Date'] as String)!,
              approvedAt: approvedAt,
            );
          },
        ),
      );
      if (mounted) {
        setState(() {
          _error = null;
          if (result != null) {
            _selected.clear();
            _offset = 0;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _view(PayableBillRecord record) async {
    final accounts = {
      for (final a in await workspace.accounts())
        a.account.id: '${a.account.code} · ${a.account.name}',
    };
    if (!mounted) return;
    final posting = workspace.database.readBillPosting(
      workspace.identity.businessId,
      record.source.id,
    )!;
    final remaining = workspace.database.billOutstanding(
      workspace.identity.businessId,
      record.source.id,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        title: 'View Bill',
        maxContentWidth: 680,
        actions: const [],
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountingInformationRows(
                rows: [
                  ...billInformationRows(
                    posting.source,
                    accountNames: accounts,
                  ),
                  ('Remaining', invoiceMoney(remaining)),
                  (
                    'Payable Account',
                    accounts[posting.payableAccountId] ??
                        posting.payableAccountId.value,
                  ),
                  ('Posting Journal', posting.journalId.value),
                ],
              ),
              if (posting.source.attachments.isNotEmpty) ...[
                const SizedBox(height: accountingContentInset),
                AccountingAttachmentList(
                  paginationKey: 'pay-bill-view-attachments',
                  children: [
                    for (final a in posting.source.attachments)
                      AccountingAttachmentRecordRow(
                        attachment: a,
                        actions: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'pay-bill-attachment-${posting.source.id}-${a.originalId}',
                            ),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View Attachment',
                            onPressed: () => showAttachmentPreview(context, a),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewPayment(StoredBillSettlement payment) async {
    final reversal = workspace.database.readBillPaymentReversal(
      workspace.identity.businessId,
      payment.id,
    );
    final account = workspace.paymentAccounts
        .where((a) => a.id == payment.paymentAccountId)
        .firstOrNull;
    final accounts = {
      for (final a in await workspace.accounts())
        a.account.id: '${a.account.code} · ${a.account.name}',
    };
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        title: 'View Bill Payment',
        maxContentWidth: 680,
        actions: const [],
        content: SizedBox(
          width: 680,
          child: AccountingInformationRows(
            rows: [
              ('Reference', payment.reference),
              ('Date', formatAccountingInputDate(payment.paidOn)),
              (
                'Bank Account',
                account?.displayLabel ?? payment.paymentAccountId,
              ),
              (
                'Ledger Account',
                accounts[payment.bankAccountId] ?? payment.bankAccountId.value,
              ),
              ('Total Payment', invoiceMoney(payment.total)),
              for (var i = 0; i < payment.allocations.length; i++) ...[
                (
                  'Bill ${i + 1}',
                  workspace.database
                      .readBillDraft(
                        workspace.identity.businessId,
                        payment.allocations[i].billId,
                      )!
                      .documentNumber,
                ),
                (
                  'Payment ${i + 1}',
                  invoiceMoney(payment.allocations[i].amount),
                ),
              ],
              ('Journal', payment.journalId.value),
              ('Payment ID', payment.id.value),
              if (reversal != null) ...[
                ('Status', 'Reversed'),
                ('Reversed On', formatAccountingInputDate(reversal.reversedOn)),
                ('Reversal Reason', reversal.reason),
                ('Reversal Journal', reversal.journalId.value),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _reversePayment(StoredBillSettlement payment) async {
    final request = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    final today = accountingCalendarDate(DateTime.now());
    final initialDate = today.isBefore(payment.paidOn) ? payment.paidOn : today;
    List<(String, String)> review(Map<String, Object?> values) {
      final date = parseAccountingInputDate(values['Date'] as String);
      if (date == null ||
          accountingCalendarDate(date).isBefore(payment.paidOn)) {
        throw const FormatException(
          'Choose a date on or after the original payment date.',
        );
      }
      final reason = (values['Reason'] as String).trim();
      if (reason.isEmpty || reason.length > 500) {
        throw const FormatException('Enter a reason of 1–500 characters.');
      }
      return [
        ('Original Journal', payment.journalId.value),
        ('Reversal Date', formatAccountingInputDate(date)),
        ('Reversal Reason', reason),
        ('Payment Reversed', invoiceMoney(payment.total)),
        for (final allocation in payment.allocations)
          (
            'Amount Paid for Bill',
            '${workspace.database.readBillDraft(workspace.identity.businessId, allocation.billId)!.documentNumber} · ${invoiceMoney(allocation.amount)}',
          ),
      ];
    }

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: const DesignForm(
          'Reverse Bill Payment',
          [
            DesignField('Date', required: true),
            DesignField('Reason', required: true, multiline: true),
          ],
          actionLabel: 'Reverse Payment',
          description: 'Reverse the complete payment batch and restore its Bill balances. The original payment stays in history.',
        ),
        initial: {'Date': formatAccountingInputDate(initialDate)},
        informationRows: [
          ('Reference', payment.reference),
          ('Original Payment', invoiceMoney(payment.total)),
        ],
        reviewInformationRowsBuilder: review,
        onCommit: (values) async {
          review(values);
          workspace.reverseBillPayment(
            requestId: request,
            sourcePaymentId: payment.id,
            reversedOn: parseAccountingInputDate(values['Date'] as String)!,
            reason: (values['Reason'] as String).trim(),
            approvedAt: approvedAt,
          );
        },
      ),
    );
    return result != null;
  }

  Future<void> _history(PayableBillRecord bill) async {
    var offset = 0;
    var pageSize = AccountingRecordPageSizes.read('bill-payment-history');
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final total = workspace.database.billSettlementCount(
            workspace.identity.businessId,
            bill.source.id,
          );
          final records = workspace.database.billSettlementsForBill(
            workspace.identity.businessId,
            bill.source.id,
            offset: offset,
            limit: pageSize,
          );
          return AccountingDialog.alert(
            context,
            title: 'Bill Payments',
            maxContentWidth: 680,
            actions: const [],
            content: SizedBox(
              width: 680,
              child: total == 0
                  ? const Text('No payments recorded for this bill.')
                  : AccountingRecordList(
                      paginationKey: 'pay-bills-1',
                      totalCount: total,
                      externalPagination: Padding(
                        padding: accountingContentPadding,
                        child: AccountingRecordPagination(
                          total: total,
                          offset: offset,
                          pageSize: pageSize,
                          keyPrefix: 'bill-payment-history',
                          onPageSizeChanged: (size) => update(() {
                            pageSize = size;
                            offset = 0;
                          }),
                          onPrevious: offset == 0
                              ? null
                              : () => update(
                                  () => offset = (offset - pageSize).clamp(
                                    0,
                                    total,
                                  ),
                                ),
                          onNext: offset + pageSize >= total
                              ? null
                              : () => update(() => offset += pageSize),
                        ),
                      ),
                      children: [
                        for (final p in records)
                          AccountingRecordRow(
                            title: p.reference,
                            topRightInfo: true,
                            status:
                                workspace.database.readBillPaymentReversal(
                                      workspace.identity.businessId,
                                      p.id,
                                    ) !=
                                    null
                                ? AccountingBadge.build(
                                    context,
                                    label: 'Reversed',
                                  )
                                : null,
                            details: Text(formatAccountingInputDate(p.paidOn)),
                            trailing: Text(
                              invoiceMoney(
                                p.allocations
                                    .firstWhere(
                                      (a) => a.billId == bill.source.id,
                                    )
                                    .amount,
                              ),
                            ),
                            actions: [
                              AccountingRecordActions(
                                trailing: [
                                  AccountingButton.iconOnly(
                                    context,
                                    key: ValueKey('view-bill-payment-${p.id}'),
                                    icon: Icons.visibility_outlined,
                                    tooltip: 'View Bill Payment',
                                    onPressed: () => _viewPayment(p),
                                  ),
                                  if (workspace.database
                                          .readBillPaymentReversal(
                                            workspace.identity.businessId,
                                            p.id,
                                          ) ==
                                      null)
                                    AccountingButton.iconOnly(
                                      context,
                                      key: ValueKey(
                                        'reverse-bill-payment-${p.id}',
                                      ),
                                      icon: Icons.undo,
                                      tooltip: 'Reverse Bill Payment',
                                      onPressed: () async {
                                        if (await _reversePayment(p)) {
                                          update(() {});
                                          if (mounted) {
                                            setState(() {
                                              _selected.clear();
                                              _offset = 0;
                                            });
                                          }
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final controlCount = workspace.database
          .payableBillPage(businessId: workspace.identity.businessId, limit: 1)
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = workspace.database.payableBillPage(
        businessId: workspace.identity.businessId,
        search: showControls ? _search.text : '',
        offset: showControls ? _offset : 0,
        limit: _pageSize,
        status: switch (showControls ? _status : null) {
          'Outstanding' => PayableBillStatus.outstanding,
          'Unpaid' => PayableBillStatus.unpaid,
          'Partially Paid' => PayableBillStatus.partiallyPaid,
          'Paid' => PayableBillStatus.paid,
          _ => null,
        },
      );
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Pay Bills',
              title: 'Pay Bills',
              description: 'Select outstanding bills in one currency, then review the amount paid for each bill.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('pay-selected-bills'),
                onPressed: _selected.isEmpty ? null : _pay,
                child: Text('Record Payment (${_selected.length})'),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            if (_error != null) ...[
              AccountingAlert.build(
                context,
                title: 'Bill Payment',
                description: _error!,
                tone: AccountingAlertTone.critical,
              ),
              const SizedBox(height: accountingContentInset),
            ],
            AccountingRecordControls(
              recordCount: controlCount,
              child: AccountingControlFlow(
                spacing: accountingContentInset,
                runSpacing: AccountingPageControlScope.runGapOf(context),
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        accountingFieldLabel(context, 'Search'),
                        const SizedBox(height: accountingFieldLabelGap),
                        SizedBox(
                          height: 44,
                          child: TextField(
                            key: const ValueKey('pay-bill-search'),
                            controller: _search,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Vendor, number or reference',
                            ),
                            onChanged: (_) => setState(() => _offset = 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    controlKey: const ValueKey('pay-bill-status-filter'),
                    options: const [
                      'Outstanding',
                      'Unpaid',
                      'Partially Paid',
                      'Paid',
                    ],
                    value: _status,
                    onChanged: (value) => setState(() {
                      _status = value;
                      _offset = 0;
                    }),
                  ),
                  if (_search.text.isNotEmpty || _status != null)
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('clear-pay-bill-filter'),
                      onPressed: () => setState(() {
                        _search.clear();
                        _status = null;
                        _offset = 0;
                      }),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            if (_selected.isNotEmpty)
              AccountingButton.outline(
                context,
                key: const ValueKey('clear-pay-bill-selection'),
                onPressed: () => setState(_selected.clear),
                child: const Text('Clear Selection'),
              ),
            if (showControls) const SizedBox(height: accountingContentInset),
            if (page.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: accountingContentInset,
                ),
                child: Text('No matching posted bills.'),
              ),
            AccountingRecordList(
              totalCount: controlCount,
              paginationKey: 'pay-bills-2',
              externalPagination: page.total == 0
                  ? null
                  : Padding(
                      padding: accountingContentPadding,
                      child: AccountingRecordPagination(
                        total: page.total,
                        unfilteredTotal: controlCount,
                        offset: page.offset,
                        pageSize: _pageSize,
                        keyPrefix: 'pay-bill',
                        onPageSizeChanged: (size) => setState(() {
                          _pageSize = size;
                          _offset = 0;
                        }),
                        onPrevious: page.offset == 0
                            ? null
                            : () => setState(
                                () => _offset = (page.offset - _pageSize).clamp(
                                  0,
                                  page.total,
                                ),
                              ),
                        onNext: page.offset + _pageSize >= page.total
                            ? null
                            : () => setState(
                                () => _offset = page.offset + _pageSize,
                              ),
                      ),
                    ),
              children: [
                for (final r in page.records)
                  AccountingRecordRow(
                    key: ValueKey('pay-bill-row-${r.source.id}'),
                    topRightInfo: true,
                    leadingOverlaysTitle: true,
                    leading: AccountingLeadingCheckbox(
                      value: _selected.contains(r.source.id),
                      hitKey: ValueKey('select-pay-bill-${r.source.id}'),
                      semanticLabel: 'Select ${r.source.documentNumber}',
                      onChanged: !r.remaining.isPositive
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _selected.add(r.source.id);
                              } else {
                                _selected.remove(r.source.id);
                              }
                            }),
                    ),
                    title: r.source.vendorSnapshot.name,
                    status: AccountingBadge.build(context, label: r.status),
                    details: Text(
                      '${r.source.documentNumber} · Due ${formatAccountingInputDate(r.source.bill.dueDate)}',
                    ),
                    trailing: Text(
                      invoiceMoney(r.remaining),
                      style: AccountingTypography.value(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('view-pay-bill-${r.source.id}'),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View Bill',
                            onPressed: () => _view(r),
                          ),
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('pay-bill-history-${r.source.id}'),
                            icon: Icons.history_outlined,
                            tooltip: 'Bill Payments',
                            onPressed: () => _history(r),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
