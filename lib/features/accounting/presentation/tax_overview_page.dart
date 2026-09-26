import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/responsive.dart';
import '../../../core/dates/accounting_date.dart';
import '../application/accounting_workspace.dart';
import '../data/accounting_database.dart';
import '../domain/tax_activity_report.dart';
import '../domain/tax_remittance.dart';
import 'widgets/accounting_formatters.dart';
import 'tax_remittance_dialog.dart';
import 'widgets/accounting_layout.dart';

class TaxOverviewPage extends StatefulWidget {
  const TaxOverviewPage({
    super.key,
    required this.workspace,
    this.agencyProposal = true,
    this.taxPaymentsProposal = true,
  });
  final bool agencyProposal, taxPaymentsProposal;
  final AccountingWorkspace workspace;
  @override
  State<TaxOverviewPage> createState() => _TaxOverviewPageState();
}

class _TaxOverviewPageState extends State<TaxOverviewPage> {
  final _from = TextEditingController(
    text: formatAccountingInputDate(DateTime(DateTime.now().year)),
  );
  final _through = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  late DateTime _appliedFrom, _appliedThrough;
  TaxActivityReport? _report;
  String? _error, _rangeError;
  bool _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _appliedFrom = parseAccountingInputDate(_from.text)!;
    _appliedThrough = parseAccountingInputDate(_through.text)!;
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant TaxOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _report = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.workspace.removeListener(_load);
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await widget.workspace.taxActivity(
        from: _appliedFrom,
        through: _appliedThrough,
      );
      if (mounted && generation == _generation) {
        setState(() => _report = report);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _report = null;
          _error = error is StateError
              ? error.message
              : 'Tax activity could not be loaded. Check the dates and retry.';
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _run() {
    final from = parseAccountingInputDate(_from.text);
    final through = parseAccountingInputDate(_through.text);
    if (from == null || through == null || from.isAfter(through)) {
      setState(
        () => _rangeError =
            'Enter valid dates with the start on or before the end.',
      );
      return;
    }
    _rangeError = null;
    _appliedFrom = from;
    _appliedThrough = through;
    _load();
  }

  String _amount(BigInt? amount) => amount == null
      ? 'Unavailable'
      : formatAccountingMinor(
          context,
          amount,
          widget.workspace.identity.currency,
        );
  String _range(TaxActivityReport report) =>
      '${formatAccountingInputDate(report.ledger.from)} – ${formatAccountingInputDate(report.ledger.through)}';

  Future<void> _showSource(TaxActivityRow row) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AccountingDialog.alert(
      dialogContext,
      title: row.sourceLabel,
      description: row.documentNumber.isEmpty ? null : row.documentNumber,
      fixedContentWidth: 600,
      maxContentWidth: 600,
      content: SelectionArea(
        child: AccountingInformationRows(
          rows: [
            ('Posted Date', formatAccountingInputDate(row.date)),
            ('Amounts Are', row.basis),
            ('Tax Code', row.taxLabel),
            if (row.code != null) ...[
              ('Code ID', row.code!.id.value),
              ('Code Revision', '${row.code!.revision}'),
            ],
            if (widget.agencyProposal) ...[
              (
                'Tax Agency',
                row.code?.agencySnapshot?.name ?? 'Unassigned Agency',
              ),
              if (row.code?.agencySnapshot != null) ...[
                (
                  'Registration Number',
                  row.code!.agencySnapshot!.registrationNumber,
                ),
                ('Country Code', row.code!.agencySnapshot!.countryCode),
                ('Agency Revision', '${row.code!.agencySnapshot!.revision}'),
                ('Agency ID', row.code!.agencySnapshot!.id.value),
              ],
            ],
            ('Net Amount', _amount(row.netMinor)),
            ('Tax Amount', _amount(row.taxMinor)),
            ('Gross Amount', _amount(row.grossMinor)),
            (
              'Treatment',
              row.isPurchase
                  ? 'Included in purchase cost; no input-tax credit is claimed.'
                  : 'Sales tax activity',
            ),
            if (row.description.isNotEmpty) ('Description', row.description),
            if (row.unresolvedReason != null)
              ('Needs Review', row.unresolvedReason!),
            ('Source ID', row.sourceId.value),
            if (row.lineId.isNotEmpty) ('Line ID', row.lineId),
            ('Journal ID', row.journalId.value),
            if (row.taxAccountId != null)
              ('Tax Account ID', row.taxAccountId!.value),
          ],
        ),
      ),
      actions: [],
    ),
  );

  Future<void> _showAccount(
    TaxActivityReport report,
    TaxAccountActivity account,
  ) => widget.taxPaymentsProposal
      ? showTaxRemittanceAccountTrace(
          context,
          widget.workspace,
          report,
          account,
        )
      : showDialog<void>(
          context: context,
          builder: (dialogContext) => AccountingDialog.alert(
            dialogContext,
            title: account.balance.account.displayName,
            description: '${_range(report)} · Credit balances',
            fixedContentWidth: 600,
            maxContentWidth: 600,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountingInformationRows(
                  rows: [
                    ('Opening Balance', _amount(account.openingCredit)),
                    ('Source Sales Tax', _amount(account.sourceSalesTax)),
                    (
                      'Other Ledger Movement',
                      _amount(account.otherMovementCredit),
                    ),
                    ('Closing Balance', _amount(account.closingCredit)),
                  ],
                ),
                for (final entry in report.ledger.activityFor(
                  account.balance.account.id,
                ))
                  SelectionArea(
                    child: AccountingInformationRows(
                      rows: [
                        ('Posted Date', formatAccountingInputDate(entry.date)),
                        ('Memo', entry.memo),
                        (
                          'Debits',
                          _amount(
                            entry.lines
                                .where(
                                  (l) =>
                                      l.accountId ==
                                          account.balance.account.id &&
                                      l.isDebit,
                                )
                                .fold<BigInt>(
                                  BigInt.zero,
                                  (v, l) =>
                                      v + BigInt.from(l.amount.minorUnits),
                                ),
                          ),
                        ),
                        (
                          'Credits',
                          _amount(
                            entry.lines
                                .where(
                                  (l) =>
                                      l.accountId ==
                                          account.balance.account.id &&
                                      !l.isDebit,
                                )
                                .fold<BigInt>(
                                  BigInt.zero,
                                  (v, l) =>
                                      v + BigInt.from(l.amount.minorUnits),
                                ),
                          ),
                        ),
                        ('Journal ID', entry.id.value),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [],
          ),
        );

  Future<void> _editTaxPayment({bool link = false}) async {
    try {
      // Resolve owned eligibility before opening so load failures remain visible.
      widget.workspace.taxRemittancePaymentAccounts;
      await showDialog<void>(
        context: context,
        builder: (_) => TaxRemittanceEditor(
          workspace: widget.workspace,
          linkExisting: link,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _paymentRecords() {
    try {
      final w = widget.workspace;
      final payments = w.taxRemittances(includeCorrected: true);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: accountingContentInset,
            ),
            child: accountingSectionTitle(context, 'Tax Payments'),
          ),
          const SizedBox(height: accountingFieldLabelGap),
          AccountingRecordList(
            paginationKey: 'tax-payments',
            emptyState: const Padding(
              padding: accountingContentPadding,
              child: Text('No recorded tax payments.'),
            ),
            children: [
              for (final p in payments)
                Builder(
                  builder: (context) {
                    final correction = w.database.readTaxRemittanceCorrection(
                      w.identity.businessId,
                      p.id,
                    );
                    return AccountingRecordRow(
                      key: ValueKey('tax-payment-${p.id.value}'),
                      topRightInfo: true,
                      title: p.reference,
                      details: Text(
                        '${formatAccountingInputDate(p.paidOn)} · ${p.origin == TaxRemittanceOrigin.recorded ? 'Recorded Payment' : 'Linked Payment'}${correction == null
                            ? ''
                            : correction.kind == TaxRemittanceCorrectionKind.unlink
                            ? ' · Unlinked'
                            : ' · Reversed'}',
                        style: AccountingTypography.value(context),
                      ),
                      trailing: Text(
                        _amount(BigInt.from(p.total.minorUnits)),
                        style: AccountingTypography.value(context),
                      ),
                      actions: [
                        AccountingRecordActions(
                          trailing: [
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey('tax-payment-view-${p.id.value}'),
                              onPressed: () => showTaxRemittance(context, w, p),
                              icon: Icons.visibility_outlined,
                              tooltip: 'View Tax Payment',
                            ),
                            if (correction == null)
                              AccountingButton.iconOnly(
                                context,
                                key: ValueKey(
                                  'tax-payment-correct-${p.id.value}',
                                ),
                                onPressed: () =>
                                    correctTaxRemittance(context, w, p),
                                icon: Icons.edit_outlined,
                                tooltip: 'Correct Tax Payment',
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ],
      );
    } catch (error) {
      return AccountingAlert.build(
        context,
        title: 'Tax Payments Unavailable',
        description: '$error',
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final error = _rangeError ?? _error;
    return AccountingPageShell(
      includeTopSafeArea: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingPageHeader(
            routeLabel: 'Tax',
            title: 'Tax Overview',
            titleKey: 'page-title-tax-overview',
            description: widget.taxPaymentsProposal
                ? 'Posted tax activity, recorded payments and ledger balances. Filing and statutory settlement remain separate.'
                : 'Posted tax activity and ledger balances. SST filing, relief and remittances require separate review.',
            action: widget.taxPaymentsProposal
                ? AccountingButton.primary(
                    context,
                    key: const ValueKey('tax-payment-record'),
                    onPressed: _busy ? null : () => _editTaxPayment(),
                    child: const Text('Record Tax Payment'),
                  )
                : AccountingButton.secondary(
                    context,
                    key: const ValueKey('tax-overview-refresh'),
                    onPressed: _busy ? null : _load,
                    child: const Text('Refresh'),
                  ),
            secondaryActions: [
              if (widget.taxPaymentsProposal) ...[
                AccountingButton.secondary(
                  context,
                  key: const ValueKey('tax-payment-link'),
                  onPressed: _busy ? null : () => _editTaxPayment(link: true),
                  child: const Text('Link Existing Payment'),
                ),
                AccountingButton.secondary(
                  context,
                  key: const ValueKey('tax-overview-refresh'),
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh'),
                ),
              ],
            ],
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (error != null) ...[
            AccountingAlert.build(
              context,
              title: 'Tax Activity Could Not Be Run',
              description: error,
              destructive: true,
            ),
            const SizedBox(height: accountingContentInset),
          ],
          Wrap(
            spacing: accountingContentInset,
            runSpacing: AccountingPageControlScope.runGapOf(context),
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final field in [
                ('From', _from, 'tax-overview-from'),
                ('Through', _through, 'tax-overview-through'),
              ])
                SizedBox(
                  width: accountingCompactDateFieldWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(context, field.$1),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        key: ValueKey(field.$3),
                        controller: field.$2,
                        inputFormatters: [const DateInputFormatter()],
                        decoration:
                            accountingSingleLineInputDecoration(
                              context,
                              hintText: 'DD-MM-YYYY',
                            ).copyWith(
                              suffixIcon: accountingCalendarButton(
                                context,
                                controller: field.$2,
                                label: field.$1,
                                enabled: !_busy,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              AccountingButton.primary(
                context,
                key: const ValueKey('tax-overview-run'),
                onPressed: _busy ? null : _run,
                child: const Text('Run Report'),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          if (_busy) const LinearProgressIndicator(),
          if (widget.taxPaymentsProposal) ...[
            _paymentRecords(),
            const SizedBox(height: accountingContentInset),
          ],
          if (report != null) ...[
            AccountingSummaryTableCard(
              title: 'Book Tax Activity',
              description: _range(report),
              labelHeader: 'Activity',
              valueHeader: 'Amount',
              rows: [
                ('Sales Tax — Net of Credits', _amount(report.salesTax)),
                ('Purchase Tax In Cost', _amount(report.purchaseTaxInCost)),
                if (widget.taxPaymentsProposal)
                  (
                    'Recorded Tax Payments — Net of Reversals',
                    _amount(report.remittedTax),
                  ),
                (
                  'Sources With Tax Facts Unavailable',
                  '${report.unresolved.length}',
                ),
              ],
              note: 'Book activity uses posted dates. Purchase tax does not reduce sales tax payable. These figures are not an SST return or income-tax computation.',
            ),
            const SizedBox(height: accountingContentInset),
            if (widget.agencyProposal)
              for (final group in report.agencyGroups) ...[
                AccountingSummaryTableCard(
                  title:
                      '${group.label}${group.agency == null ? '' : ' · Revision ${group.agency!.revision}'}',
                  description: group.agency == null
                      ? 'No agency was retained on these source facts.'
                      : '${group.agency!.countryCode} · ${group.agency!.registrationNumber.isEmpty ? 'Registration not recorded' : group.agency!.registrationNumber}',
                  labelHeader: 'Book Tax Activity',
                  valueHeader: 'Amount',
                  rows: [
                    ('Sales Tax — Net of Credits', _amount(group.salesTax)),
                    ('Purchase Tax In Cost', _amount(group.purchaseTaxInCost)),
                    if (widget.taxPaymentsProposal)
                      (
                        'Recorded Tax Payments — Net of Reversals',
                        _amount(group.remittedTax),
                      ),
                    (
                      'Sources With Tax Facts Unavailable',
                      '${group.unresolvedCount}',
                    ),
                  ],
                  note:
                      'Saved agency revision · ${_range(report)}. These figures are not a statutory return.',
                ),
                const SizedBox(height: accountingContentInset),
              ],
            AccountingSummaryTableCard(
              title: 'Tax Ledger Balances',
              description: 'Closing credit balances · ${_range(report)}',
              labelHeader: 'Account',
              valueHeader: 'Balance',
              rows: [
                for (final account in report.accounts)
                  (
                    account.balance.account.displayName,
                    _amount(account.closingCredit),
                  ),
              ],
              note: 'Balances include opening amounts and other posted ledger movements. They do not establish statutory tax due.',
            ),
            if (report.accounts.isNotEmpty) ...[
              const SizedBox(height: accountingContentInset),
              AccountingRecordList(
                paginationKey: 'tax-account-activity',
                children: [
                  for (final account in report.accounts)
                    AccountingRecordRow(
                      key: ValueKey(
                        'tax-account-${account.balance.account.id.value}',
                      ),
                      title: account.balance.account.displayName,
                      details: Text(
                        widget.taxPaymentsProposal
                            ? 'Source Sales Tax ${_amount(account.sourceSalesTax)} · Recorded Payments ${_amount(account.remittanceCredit)} · Unattributed ${_amount(account.unattributedMovementCredit)}'
                            : 'Source Sales Tax ${_amount(account.sourceSalesTax)} · Other Movement ${_amount(account.otherMovementCredit)}',
                        style: AccountingTypography.value(context),
                      ),
                      trailing: AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'tax-account-view-${account.balance.account.id.value}',
                            ),
                            onPressed: () => _showAccount(report, account),
                            icon: Icons.visibility_outlined,
                            tooltip:
                                'View ${account.balance.account.displayName}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: accountingContentInset),
            AccountingRecordList(
              paginationKey: 'tax-source-activity',
              emptyState: Padding(
                padding: accountingContentPadding,
                child: Text(
                  'No posted source tax activity in this period.',
                  style: AccountingTypography.value(context),
                ),
              ),
              children: [
                for (final row in report.rows)
                  AccountingRecordRow(
                    topRightInfo: true,
                    key: ValueKey(
                      'tax-source-${row.journalId.value}-${row.lineId}',
                    ),
                    title:
                        '${row.sourceLabel}${row.documentNumber.isEmpty ? '' : ' · ${row.documentNumber}'}',
                    details: Text(
                      '${formatAccountingInputDate(row.date)} · ${row.taxLabel}',
                      style: AccountingTypography.value(context),
                    ),
                    trailing: Text(
                      _amount(row.taxMinor),
                      style: AccountingTypography.value(context),
                    ),
                    actions: [
                      AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'tax-source-view-${row.journalId.value}-${row.lineId}',
                            ),
                            onPressed: () => _showSource(row),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View ${row.sourceLabel}',
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
