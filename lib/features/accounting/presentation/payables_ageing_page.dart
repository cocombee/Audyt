import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/responsive.dart';
import '../../../core/dates/accounting_date.dart';
import '../../purchases/presentation/bill_form.dart' show billInformationRows;
import '../application/accounting_workspace.dart';
import '../data/accounting_database.dart';
import 'attachment_preview_dialog.dart';
import 'widgets/accounting_formatters.dart';
import 'widgets/accounting_layout.dart';

/// A historical read of posted Bills and their actual payable control accounts.
/// Editing the date alone never changes the applied report.
class PayablesAgeingPage extends StatefulWidget {
  const PayablesAgeingPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<PayablesAgeingPage> createState() => _PayablesAgeingPageState();
}

class _PayablesAgeingPageState extends State<PayablesAgeingPage> {
  final _date = TextEditingController();
  late DateTime _asOf;
  PayablesAgeingSnapshot? _report;
  String? _error;
  int _limit = AccountingRecordPageSizes.read('payables-ageing');
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _reset();
    widget.workspace.addListener(_refresh);
  }

  void _reset() {
    _asOf = accountingCalendarDate(DateTime.now());
    _date.text = formatAccountingInputDate(_asOf);
    _offset = 0;
    _load();
  }

  @override
  void didUpdateWidget(covariant PayablesAgeingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_refresh);
      widget.workspace.addListener(_refresh);
      _reset();
    }
  }

  void _load() {
    try {
      _report = widget.workspace.database.payablesAgeing(
        businessId: widget.workspace.identity.businessId,
        currency: widget.workspace.identity.currency,
        asOf: _asOf,
        offset: _offset,
        limit: _limit,
      );
      _offset = _report!.offset;
      _error = null;
    } catch (error) {
      // A failed saved-data read must not keep a previous matching balance on
      // screen as though it were current. Invalid typed dates retain the report.
      _report = null;
      _error = error.toString();
    }
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  void _run() {
    final parsed = parseAccountingInputDate(_date.text);
    setState(() {
      if (parsed == null) {
        _error = 'Enter a valid date.';
        return;
      }
      _asOf = accountingCalendarDate(parsed);
      _offset = 0;
      _load();
    });
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_refresh);
    _date.dispose();
    super.dispose();
  }

  Future<void> _view(
    PayableAgeingRecord record,
    PayablesAgeingSnapshot report,
  ) async {
    final workspace = widget.workspace;
    try {
      final accounts = {
        for (final a in await workspace.accounts())
          a.account.id: '${a.account.code} · ${a.account.name}',
      };
      if (!mounted || workspace != widget.workspace || report != _report) {
        return;
      }
      final posting = record.posting;
      await showDialog<void>(
        context: context,
        builder: (context) => AccountingDialog.alert(
          context,
          title: 'View Payable Balance',
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
                    ('As Of', formatAccountingInputDate(report.asOf)),
                    (
                      'Outstanding',
                      formatAccountingMoney(context, record.remaining),
                    ),
                    ('Ageing Bucket', record.bucket),
                    ...billInformationRows(
                      posting.source,
                      accountNames: accounts,
                    ),
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
                    paginationKey: 'payable-view-attachments',
                    children: [
                      for (final attachment in posting.source.attachments)
                        AccountingAttachmentRecordRow(
                          attachment: attachment,
                          actions: [
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'ageing-attachment-${posting.source.id}-${attachment.originalId}',
                              ),
                              icon: Icons.visibility_outlined,
                              tooltip: 'View Attachment',
                              onPressed: () =>
                                  showAttachmentPreview(context, attachment),
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
    } catch (error) {
      if (mounted && workspace == widget.workspace) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AccountingPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingPageHeader(
            routeLabel: 'Payables Ageing',
            title: 'Payables Ageing',
            description: 'Outstanding posted Bills by contractual due date. Payments after the report date are excluded.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('run-payables-ageing'),
              onPressed: _run,
              child: const Text('Run Report'),
            ),
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_error != null) ...[
            AccountingAlert.build(
              context,
              key: const ValueKey('payables-ageing-error'),
              title: 'Failed — Payables Ageing',
              description: _error!,
              destructive: true,
            ),
            const SizedBox(height: accountingContentInset),
          ],
          Wrap(
            spacing: accountingContentInset,
            runSpacing: AccountingPageControlScope.runGapOf(context),
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: accountingCompactDateFieldWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountingFieldLabel(context, 'As Of'),
                    const SizedBox(height: accountingFieldLabelGap),
                    TextField(
                      key: const ValueKey('payables-ageing-date'),
                      controller: _date,
                      inputFormatters: const [DateInputFormatter()],
                      decoration:
                          accountingSingleLineInputDecoration(
                            context,
                            hintText: 'DD-MM-YYYY',
                          ).copyWith(
                            suffixIcon: accountingCalendarButton(
                              context,
                              controller: _date,
                              label: 'As Of',
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (report != null) ...[
            const SizedBox(height: accountingContentInset),
            AccountingSummaryTableCard(
              key: const ValueKey('payables-ageing-summary'),
              title: 'Ageing Summary',
              description: 'As of ${formatAccountingInputDate(report.asOf)}',
              labelHeader: 'Ageing bucket',
              valueHeader: 'Outstanding',
              rows: [
                for (final entry in report.buckets.entries)
                  (
                    entry.key,
                    formatAccountingMinor(
                      context,
                      entry.value,
                      report.currency,
                    ),
                  ),
                (
                  'Total Outstanding',
                  formatAccountingMinor(
                    context,
                    report.outstandingMinor,
                    report.currency,
                  ),
                ),
              ],
              note: report.total == 0
                  ? 'No outstanding posted Bills for this date.'
                  : null,
            ),
            for (final control in report.controls) ...[
              const SizedBox(height: accountingContentInset),
              AccountingSummaryTableCard(
                key: ValueKey('payables-control-${control.accountId}'),
                title: '${control.code} · ${control.name}',
                description: 'Payable Control Comparison',
                labelHeader: 'Balance',
                valueHeader: 'Amount',
                rows: [
                  (
                    'Bill Outstanding',
                    formatAccountingMinor(
                      context,
                      control.billMinor,
                      report.currency,
                    ),
                  ),
                  (
                    'Posted Ledger',
                    formatAccountingMinor(
                      context,
                      control.ledgerMinor,
                      report.currency,
                    ),
                  ),
                  (
                    'Difference',
                    formatAccountingMinor(
                      context,
                      control.differenceMinor,
                      report.currency,
                    ),
                  ),
                ],
                note: control.differenceMinor == BigInt.zero
                    ? 'Totals match for this date. Matching totals do not establish that every source or liability is complete.'
                    : 'Review other liabilities, manual entries and missing allocations in this account. No adjustment has been created.',
              ),
            ],
            if (report.records.isNotEmpty) ...[
              const SizedBox(height: accountingContentInset),
              AccountingRecordList(
                paginationKey: 'payables-ageing-1',
                totalCount: report.total,
                externalPagination: Padding(
                  padding: accountingContentPadding,
                  child: AccountingRecordPagination(
                    total: report.total,
                    offset: report.offset,
                    pageSize: _limit,
                    keyPrefix: 'payables-ageing',
                    onPageSizeChanged: (size) => setState(() {
                      _limit = size;
                      _offset = 0;
                      _load();
                    }),
                    onPrevious: report.offset == 0
                        ? null
                        : () => setState(() {
                            _offset = (report.offset - _limit).clamp(
                              0,
                              report.total,
                            );
                            _load();
                          }),
                    onNext: report.offset + _limit >= report.total
                        ? null
                        : () => setState(() {
                            _offset = report.offset + _limit;
                            _load();
                          }),
                  ),
                ),
                children: [
                  for (final record in report.records)
                    AccountingRecordRow(
                      key: ValueKey(
                        'payables-ageing-row-${record.posting.source.id}',
                      ),
                      topRightInfo: true,
                      title: record.posting.source.documentNumber,
                      details: Text(
                        '${record.posting.source.vendorSnapshot.name}\nDue ${formatAccountingInputDate(record.posting.source.bill.dueDate)} · ${record.bucket}',
                      ),
                      trailing: Text(
                        formatAccountingMoney(context, record.remaining),
                        style: AccountingTypography.value(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      actions: [
                        AccountingRecordActions(
                          trailing: [
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'view-payables-ageing-${record.posting.source.id}',
                              ),
                              icon: Icons.visibility_outlined,
                              tooltip: 'View Payable Balance',
                              onPressed: () => _view(record, report),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
