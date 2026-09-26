import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/demo_company.dart';
import '../../core/dates/accounting_date.dart';
import '../../core/ids/entity_id.dart';
import '../../core/money/money.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';
import 'domain/customer_statement_activity.dart';

class CustomerStatementPage extends StatefulWidget {
  const CustomerStatementPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<CustomerStatementPage> createState() => _CustomerStatementPageState();
}

class _CustomerStatementPageState extends State<CustomerStatementPage> {
  EntityId? customer;
  DateTime asOf = accountingCalendarDate(DateTime.now());
  late final date = TextEditingController(
    text: formatAccountingInputDate(asOf),
  );
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
      final customers = widget.workspace.customers();
      final selectedCustomer =
          customer ??
          (DemoCompany.active(context) && customers.isNotEmpty
              ? customers.first.id
              : null);
      final records = selectedCustomer == null
          ? null
          : widget.workspace.database.customerStatement(
              widget.workspace.identity.businessId,
              selectedCustomer,
              asOf,
            );
      final balances = <String, Money>{};
      for (final row in records ?? []) {
        balances[row.balance.currency] = row.balance;
      }
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Customer Statements',
              title: 'Customer Statements',
              description: 'Posted invoices, allocated customer payments and credit notes through the selected date.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('run-statement'),
                child: const Text('Run Report'),
                onPressed: selectedCustomer == null
                    ? null
                    : () {
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
                key: const ValueKey('statement-error-notice'),
                title: 'Statement Could Not Be Run',
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: AccountingSelector<EntityId>(
                    key: const ValueKey('statement-customer'),
                    assignedWidth: 280,
                    options: [
                      for (final c in customers)
                        AccountingSelectorOption(
                          value: c.id,
                          label: c.displayName,
                        ),
                    ],
                    value: selectedCustomer,
                    onChanged: (value) => setState(() => customer = value),
                    hintText: 'Choose Customer',
                    searchable: true,
                  ),
                ),
                SizedBox(
                  width: accountingCompactDateFieldWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(context, 'As Of'),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        key: const ValueKey('statement-date'),
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
            if (records == null)
              const AccountingPageText(
                'Choose a customer to view their statement.',
              )
            else ...[
              for (final currency
                  in balances.isEmpty
                      ? [widget.workspace.identity.currency]
                      : balances.keys) ...[
                AccountingSummaryTableCard(
                  key: const ValueKey('customer-statement-summary'),
                  title: 'Statement Summary',
                  description: 'As of ${formatAccountingInputDate(asOf)}',
                  labelHeader: 'Activity',
                  valueHeader: 'Amount',
                  rows: [
                    (
                      'Invoices',
                      formatAccountingMoney(
                        context,
                        records
                            .where((row) => row.debit.currency == currency)
                            .fold<Money>(
                              Money.zero(currency),
                              (sum, row) => sum + row.debit,
                            ),
                      ),
                    ),
                    (
                      'Payments',
                      formatAccountingMoney(
                        context,
                        records
                            .where(
                              (row) =>
                                  row.credit.currency == currency &&
                                  row.activity ==
                                      CustomerStatementActivity.payment,
                            )
                            .fold<Money>(
                              Money.zero(currency),
                              (sum, row) => sum + row.credit,
                            ),
                      ),
                    ),
                    (
                      'Credits',
                      formatAccountingMoney(
                        context,
                        records
                            .where(
                              (row) =>
                                  row.credit.currency == currency &&
                                  row.activity ==
                                      CustomerStatementActivity.credit,
                            )
                            .fold<Money>(
                              Money.zero(currency),
                              (sum, row) => sum + row.credit,
                            ),
                      ),
                    ),
                    (
                      'Closing Balance',
                      formatAccountingMoney(
                        context,
                        balances[currency] ?? Money.zero(currency),
                      ),
                    ),
                  ],
                  note: records.isEmpty
                      ? 'No posted activity for this customer through this date.'
                      : null,
                ),
                const SizedBox(height: accountingContentInset),
              ],
              if (records.isNotEmpty)
                AccountingRecordList(
                  paginationKey: 'customer-statement-1',
                  children: [
                    for (final row in records)
                      AccountingRecordRow(
                        topRightInfo: true,
                        title: row.reference,
                        details: Text(
                          '${formatAccountingInputDate(row.date)} · ${row.activity.label}\nBalance · ${formatAccountingMoney(context, row.balance)}',
                        ),
                        trailing: Text(
                          formatAccountingMoney(
                            context,
                            row.debit.isPositive ? row.debit : row.credit,
                          ),
                          style: AccountingTypography.value(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      );
    },
  );
}
