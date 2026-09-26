import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../core/dates/accounting_date.dart';
import '../../core/money/money.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';

class ReceivableAgeingPage extends StatefulWidget {
  const ReceivableAgeingPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<ReceivableAgeingPage> createState() => _ReceivableAgeingPageState();
}

class _ReceivableAgeingPageState extends State<ReceivableAgeingPage> {
  late final date = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  DateTime asOf = accountingCalendarDate(DateTime.now());
  String? error;
  @override
  void dispose() {
    date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final records = widget.workspace.database.receivablesAsOf(
        widget.workspace.identity.businessId,
        asOf,
      );
      final totals = <String, Money>{};
      for (final record in records) {
        totals.update(
          record.remaining.currency,
          (amount) => amount + record.remaining,
          ifAbsent: () => record.remaining,
        );
      }
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Receivables Ageing',
              title: 'Receivables Ageing',
              description: 'Outstanding posted invoices by contractual due date. Receipts after the report date are excluded.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('run-ageing'),
                child: const Text('Run Report'),
                onPressed: () {
                  final parsed = parseAccountingInputDate(date.text);
                  setState(() {
                    error = parsed == null ? 'Enter a valid date.' : null;
                    if (parsed != null) asOf = parsed;
                  });
                },
              ),
            ),
            const SizedBox(height: accountingPageTitleOuterGap),
            if (error != null) ...[
              AccountingAlert.build(
                context,
                key: const ValueKey('ageing-error-notice'),
                title: 'Ageing Report Could Not Be Run',
                description: error!,
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
                        key: const ValueKey('ageing-date'),
                        controller: date,
                        enableInteractiveSelection: true,
                        inputFormatters: const [DateInputFormatter()],
                        decoration:
                            accountingSingleLineInputDecoration(
                              context,
                              hintText: 'DD-MM-YYYY',
                            ).copyWith(
                              suffixIcon: accountingCalendarButton(
                                context,
                                controller: date,
                                label: 'As Of',
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            for (final currency
                in totals.isEmpty
                    ? [widget.workspace.identity.currency]
                    : totals.keys) ...[
              AccountingSummaryTableCard(
                key: const ValueKey('receivables-ageing-summary'),
                title: 'Ageing Summary',
                description: 'As of ${formatAccountingInputDate(asOf)}',
                labelHeader: 'Ageing bucket',
                valueHeader: 'Outstanding',
                rows: [
                  for (final bucket in [
                    'Current',
                    '1–30 Days',
                    '31–60 Days',
                    '61–90 Days',
                    'Over 90 Days',
                  ])
                    (
                      bucket,
                      formatAccountingMoney(
                        context,
                        records
                            .where(
                              (record) =>
                                  record.remaining.currency == currency &&
                                  record.bucket == bucket,
                            )
                            .fold<Money>(
                              Money.zero(currency),
                              (sum, record) => sum + record.remaining,
                            ),
                      ),
                    ),
                  (
                    'Total Outstanding',
                    formatAccountingMoney(
                      context,
                      totals[currency] ?? Money.zero(currency),
                    ),
                  ),
                ],
                note: records.isEmpty
                    ? 'No outstanding posted invoices for this date.'
                    : null,
              ),
              const SizedBox(height: accountingContentInset),
            ],
            if (records.isNotEmpty)
              AccountingRecordList(
                paginationKey: 'receivable-ageing-1',
                children: [
                  for (final record in records)
                    AccountingRecordRow(
                      topRightInfo: true,
                      title: record.number,
                      details: Text(
                        '${record.customer}\nDue ${formatAccountingInputDate(record.dueDate)} · ${record.bucket}',
                      ),
                      trailing: Text(
                        formatAccountingMoney(context, record.remaining),
                        style: AccountingTypography.value(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}
