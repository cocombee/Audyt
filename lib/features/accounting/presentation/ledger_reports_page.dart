import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_color_library.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../application/accounting_workspace.dart';
import '../domain/ledger_report.dart';
import '../domain/account.dart';
import '../../sales/domain/sales_report.dart';
import 'widgets/accounting_layout.dart';
import 'widgets/accounting_formatters.dart';

class LedgerReportsPage extends StatefulWidget {
  const LedgerReportsPage({
    super.key,
    required this.workspace,
    required this.compact,
    this.selectedStatementId,
    this.reviewCount = 0,
    this.onNeedsReview,
    this.onPostedJournals,
    this.onPendingDrafts,
    this.onAccounts,
    this.onSummaryChanged,
  });
  final AccountingWorkspace workspace;
  final bool compact;
  final ValueNotifier<String?>? selectedStatementId;
  final int reviewCount;
  final VoidCallback? onNeedsReview;
  final ValueChanged<LedgerReport>? onPostedJournals;
  final ValueChanged<LedgerReport>? onPendingDrafts;
  final VoidCallback? onAccounts;
  final void Function(LedgerReport? report, int needsReview)? onSummaryChanged;
  @override
  State<LedgerReportsPage> createState() => _LedgerReportsPageState();
}

class _LedgerReportsPageState extends State<LedgerReportsPage> {
  final _from = TextEditingController(
    text: formatAccountingInputDate(DateTime(DateTime.now().year)),
  );
  final _through = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  late DateTime _appliedFrom;
  late DateTime _appliedThrough;
  LedgerReport? _report;
  SalesReport? _sales;
  List<AccountingReportQualityMeasure> _qualityMeasures =
      AccountingReportQualityMeasure.empty;
  int _workspaceNeedsReview = 0;
  String? _error;
  String? _rangeError;
  String _view = 'Balance Sheet';
  bool _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _appliedFrom = parseAccountingInputDate(_from.text)!;
    _appliedThrough = parseAccountingInputDate(_through.text)!;
    widget.selectedStatementId?.addListener(_load);
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant LedgerReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _generation++;
      _report = null;
      _sales = null;
      _qualityMeasures = AccountingReportQualityMeasure.empty;
      _workspaceNeedsReview = 0;
      _error = null;
      _load();
    }
    if (oldWidget.selectedStatementId != widget.selectedStatementId) {
      oldWidget.selectedStatementId?.removeListener(_load);
      widget.selectedStatementId?.addListener(_load);
      if (oldWidget.workspace == widget.workspace) _load();
    }
  }

  @override
  void dispose() {
    widget.selectedStatementId?.removeListener(_load);
    _generation++;
    widget.workspace.removeListener(_load);
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  Future<void> _runReport() async {
    final from = parseAccountingInputDate(_from.text);
    final through = parseAccountingInputDate(_through.text);
    if (from == null || through == null || from.isAfter(through)) {
      setState(() {
        _rangeError = 'Enter valid dates with the start on or before the end.';
      });
      return;
    }
    _rangeError = null;
    _appliedFrom = from;
    _appliedThrough = through;
    await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Notifications refresh the last requested report, never unfinished fields.
      final snapshot = await widget.workspace.reportWithSales(
        from: _appliedFrom,
        through: _appliedThrough,
      );
      final report = snapshot.ledger;
      final quality = _loadQualityMeasures(report);
      if (mounted && generation == _generation) {
        setState(() {
          _report = report;
          _sales = snapshot.sales;
          _qualityMeasures = quality.measures;
          _workspaceNeedsReview = quality.needsReview;
        });
        widget.onSummaryChanged?.call(report, quality.needsReview);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _report = null;
          _sales = null;
          _qualityMeasures = AccountingReportQualityMeasure.empty;
          _workspaceNeedsReview = 0;
          _error = error is StateError
              ? error.message
              : 'Reports could not be loaded. Check your dates and retry.';
        });
        widget.onSummaryChanged?.call(null, 0);
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  ({List<AccountingReportQualityMeasure> measures, int needsReview})
  _loadQualityMeasures(LedgerReport report) {
    final workspace = widget.workspace;
    bool inRange(DateTime date) {
      final day = DateTime.utc(date.year, date.month, date.day);
      return !day.isBefore(report.from) && !day.isAfter(report.through);
    }

    final counts = workspace.database.readReportQualityCounts(
      businessId: workspace.identity.businessId,
      from: report.from,
      through: report.through,
    );

    var statementRowCount = 0;
    var autoLinkedRowCount = 0;
    var manuallyLinkedRowCount = 0;
    final statements = [
      for (final account in workspace.paymentAccounts)
        ...workspace.database.bankStatements(
          workspace.identity.businessId,
          account.id,
        ),
    ];
    final selectedId = widget.selectedStatementId?.value;
    final selected =
        statements.where((item) => item.id.value == selectedId).firstOrNull ??
        statements.firstOrNull;
    if (selected != null) {
      final statement = workspace.database.bankStatement(
        workspace.identity.businessId,
        selected.id,
      );
      final matchOrigins = workspace.database.statementMatchAutomaticFlags(
        workspace.identity.businessId,
        selected.id,
      );
      for (final row in (statement?.rows ?? const []).where(
        (row) => inRange(row.date),
      )) {
        statementRowCount++;
        final automatic = matchOrigins[row.sourceRow];
        if (automatic == true) {
          autoLinkedRowCount++;
        } else if (automatic == false) {
          manuallyLinkedRowCount++;
        }
      }
    }
    final connectedRowCount = autoLinkedRowCount + manuallyLinkedRowCount;

    final needsReview =
        counts.pendingExpenses +
        counts.pendingJournals +
        workspace.invoiceDrafts().length +
        workspace
            .creditDrafts()
            .where(
              (draft) =>
                  workspace.database.invoiceCreditPosting(
                    workspace.identity.businessId,
                    draft.id,
                  ) ==
                  null,
            )
            .length;
    return (
      measures: [
        AccountingReportQualityMeasure(
          'Expense receipts',
          counts.expensesWithReceipts,
          counts.expensesInRange,
          'expense records dated in the report range include a receipt',
        ),
        AccountingReportQualityMeasure(
          'Reconciliation progress',
          connectedRowCount,
          statementRowCount,
          '${selected?.filename ?? 'No selected statement'}: imported bank rows in the report range are connected to ledger entries',
          breakdown: selected == null
              ? null
              : '${selected.filename} · Auto-linked $autoLinkedRowCount · Manually linked $manuallyLinkedRowCount · Unlinked ${statementRowCount - connectedRowCount}',
        ),
        AccountingReportQualityMeasure(
          'Posted entries',
          counts.postedJournalsInRange,
          counts.journalsInRange,
          'journal entries dated in the report range have been posted',
        ),
      ],
      needsReview: needsReview,
    );
  }

  // Exact minor-unit formatting also supports totals beyond a single journal line.
  String _amount(BigInt value) {
    final currency = widget.workspace.identity.currency;
    final exponent = Currency.parse(currency).fractionDigits;
    final base = BigInt.from(10).pow(exponent);
    final magnitude = value.abs();
    final whole = (magnitude ~/ base).toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return currencyAmountLabel(
      currency,
      '${value.isNegative ? '-' : ''}$whole${exponent == 0 ? '' : '.${(magnitude % base).toString().padLeft(exponent, '0')}'}',
    );
  }

  Widget _row(String label, BigInt value) => AccountingReportValueRow(
    label: label,
    value: _amount(value),
    emphasized: const [
      'Total Equity',
      'Total Credits',
      'Period Profit',
      'Closing Net Debit',
    ].contains(label),
  );

  Future<void> _showSalesCategory(
    SalesReport sales,
    SalesReportCategory category,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        title: category.name,
        description:
            '${formatAccountingInputDate(sales.ledger.from)} – ${formatAccountingInputDate(sales.ledger.through)} · Net Sales · ${CurrencyPresentation.fromCode(sales.ledger.currency).amountSymbol}',
        fixedContentWidth: 600,
        maxContentWidth: 600,
        content: AccountingCard.surface(
          dialogContext,
          child: Padding(
            padding: accountingContentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in category.items)
                  AccountingReportValueRow(
                    key: ValueKey(
                      'sales-item-${item.id?.value ?? 'unclassified'}',
                    ),
                    label: item.name,
                    value: _amount(item.netMinor),
                    onTap: () => _showSalesSources(sales, item),
                  ),
                const Divider(),
                AccountingReportValueRow(
                  label: 'Total',
                  value: _amount(category.netMinor),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
        actions: [],
      ),
    );
  }

  Future<void> _showSalesSources(
    SalesReport sales,
    SalesReportItem item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        title: item.name,
        description:
            '${formatAccountingInputDate(sales.ledger.from)} – ${formatAccountingInputDate(sales.ledger.through)} · Posted Sales',
        fixedContentWidth: 600,
        maxContentWidth: 600,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final source in item.sources)
              SelectionArea(
                child: AccountingInformationRows(
                  rows: [
                    ('Date', formatAccountingInputDate(source.journal.date)),
                    (
                      'Source',
                      switch (source.allocation.kind) {
                        SalesSourceKind.invoice => 'Invoice',
                        SalesSourceKind.credit => 'Invoice Credit',
                        SalesSourceKind.journal => 'Journal',
                      },
                    ),
                    if (source.allocation.documentNumber.isNotEmpty)
                      ('Invoice Number', source.allocation.documentNumber),
                    ('Net Sales', _amount(source.allocation.netMinor)),
                    ('Memo', source.journal.memo),
                    ('Journal', source.journal.id.value),
                    ('Source ID', source.allocation.sourceId.value),
                  ],
                ),
              ),
            AccountingReportValueRow(
              label: 'Total',
              value: _amount(item.netMinor),
              emphasized: true,
            ),
          ],
        ),
        actions: [],
      ),
    );
  }

  Future<void> _showAccountActivity(
    LedgerReport report,
    LedgerAccountBalance row, {
    bool operatingOnly = false,
  }) async {
    final entries = report.activityFor(
      row.account.id,
      operatingOnly: operatingOnly,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        title: 'Account Activity',
        description:
            '${row.account.displayName} · ${formatAccountingInputDate(report.from)} – ${formatAccountingInputDate(report.through)}',
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!operatingOnly)
                  _row('Opening Net Debit', row.openingNetDebit),
                if (operatingOnly)
                  const Text(
                    'Operating activity only; closing entries are excluded.',
                  ),
                for (final entry in entries) ...[
                  const Divider(),
                  SelectionArea(
                    child: AccountingInformationRows(
                      rows: [
                        ('Date', formatAccountingInputDate(entry.date)),
                        ('Memo', entry.memo),
                        ('Journal', entry.id.value),
                        if (entry.isClosing) ('Entry Type', 'Closing Entry'),
                        if (entry.reversesId != null)
                          ('Reverses', entry.reversesId!.value),
                        for (final line in entry.lines.where(
                          (line) => line.accountId == row.account.id,
                        ))
                          (
                            line.isDebit ? 'Debit' : 'Credit',
                            _amount(BigInt.from(line.amount.minorUnits)),
                          ),
                      ],
                    ),
                  ),
                ],
                if (entries.isEmpty)
                  const Text('No posted activity in this period.'),
                const Divider(),
                _row(
                  operatingOnly ? 'Operating Net Debit' : 'Ending Net Debit',
                  operatingOnly ? row.operatingNetDebit : row.endingNetDebit,
                ),
                const Text(
                  'Negative net debit amounts represent credit balances.',
                ),
              ],
            ),
          ),
        ),
        actions: [],
      ),
    );
  }

  Widget _accountRow(
    LedgerReport report,
    LedgerAccountBalance row,
    String label,
    BigInt value, {
    bool operatingOnly = false,
  }) => InkWell(
    key: ValueKey('report-account-${row.account.id.value}'),
    borderRadius: BorderRadius.circular(8),
    onTap: () =>
        _showAccountActivity(report, row, operatingOnly: operatingOnly),
    child: Padding(padding: EdgeInsets.zero, child: _row(label, value)),
  );

  List<Widget> _accountDetails(
    LedgerReport report,
    AccountType type, {
    bool movement = false,
  }) => [
    for (final row in report.rows.where((row) => row.account.type == type))
      if ((movement ? row.operatingNetDebit : row.endingNetDebit) !=
          BigInt.zero)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _accountRow(
            report,
            row,
            row.account.displayName,
            (movement ? row.operatingNetDebit : row.endingNetDebit) *
                BigInt.from(
                  type == AccountType.income ||
                          type == AccountType.liability ||
                          type == AccountType.equity
                      ? -1
                      : 1,
                ),
            operatingOnly: movement,
          ),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final sales = _sales;
    final salesMeasures = [
      for (final category in sales?.categories ?? <SalesReportCategory>[])
        AccountingReportQualityMeasure.salesShare(
          category.name,
          category.netMinor,
          sales!.netMinor,
        ),
    ];
    final error = _error ?? _rangeError;
    return AccountingPageShell(
      includeTopSafeArea: !widget.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingPageHeader(
            routeLabel: 'Reports',
            title: 'Reports',
            titleKey: 'page-title-reports',
            description: 'Accrual reports from posted journals. Balanced totals do not prove that all transactions have been recorded.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('run-report'),
              onPressed: _busy ? null : _runReport,
              child: const Text('Run Report'),
            ),
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (error != null) ...[
            AccountingAlert.build(
              context,
              key: const ValueKey('report-error-notice'),
              title: 'Report Could Not Be Run',
              description: error,
              destructive: true,
            ),
            const SizedBox(height: accountingContentInset),
          ],
          AccountingReportsSummaryStrip(
            report: report,
            reviewCount: widget.reviewCount + _workspaceNeedsReview,
            onNeedsReview: widget.onNeedsReview,
            onPostedJournals: report == null || widget.onPostedJournals == null
                ? null
                : () => widget.onPostedJournals!(report),
            onPendingDrafts: report == null || widget.onPendingDrafts == null
                ? null
                : () => widget.onPendingDrafts!(report),
            onAccounts: widget.onAccounts,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: accountingContentInset,
            runSpacing: AccountingPageControlScope.runGapOf(context),
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final field in [
                ('From', _from, 'report-from'),
                ('Through', _through, 'report-through'),
              ])
                SizedBox(
                  width: accountingCompactDateFieldWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(
                        context,
                        field.$1,
                        key: ValueKey('${field.$3}-label'),
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        key: ValueKey(field.$3),
                        controller: field.$2,
                        enableInteractiveSelection: true,
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
            ],
          ),
          const SizedBox(height: accountingContentInset),
          AccountingReportViewSection(
            selected: _view,
            onChanged: (view) => setState(() => _view = view),
            content: _view == 'Sales'
                ? AccountingReportQualityCard(
                    title: 'Sales By Category',
                    measures: salesMeasures,
                    onSelected: sales == null
                        ? null
                        : (measure) => _showSalesCategory(
                            sales,
                            sales.categories[salesMeasures.indexOf(measure)],
                          ),
                    emptyMessage: _busy
                        ? 'Loading sales…'
                        : 'No posted sales in this period.',
                  )
                : AccountingReportQualityCard(measures: _qualityMeasures),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const LinearProgressIndicator()
          else if (report != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: accountingContentInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.postedJournalIds.length} posted journals · ${report.pendingDrafts} pending drafts through ${formatAccountingInputDate(report.through)}',
                  ),
                  Text(
                    'Report period: ${formatAccountingInputDate(report.from)} – ${formatAccountingInputDate(report.through)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: accountingContentInset),
            AccountingCard.surface(
              context,
              child: Padding(
                padding: accountingContentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_view == 'Balance Sheet') ...[
                      _row('Assets', report.assets),
                      ..._accountDetails(report, AccountType.asset),
                      _row('Liabilities', report.liabilities),
                      ..._accountDetails(report, AccountType.liability),
                      _row(
                        'Contributed And Retained Equity',
                        report.contributedAndRetainedEquity,
                      ),
                      ..._accountDetails(report, AccountType.equity),
                      _row('Unclosed Earnings', report.unclosedEarnings),
                      const Divider(),
                      _row('Total Equity', report.totalEquity),
                      const Divider(height: 20),
                      _row(
                        'Balance Sheet Difference',
                        report.balanceSheetDifference,
                      ),
                    ] else if (_view == 'Profit And Loss') ...[
                      _row('Revenue', report.revenue),
                      ..._accountDetails(
                        report,
                        AccountType.income,
                        movement: true,
                      ),
                      _row('Expenses', report.expenses),
                      ..._accountDetails(
                        report,
                        AccountType.expense,
                        movement: true,
                      ),
                      const Divider(),
                      _row('Period Profit', report.periodProfit),
                    ] else if (_view == 'Sales' && sales != null) ...[
                      for (final category in sales.categories)
                        AccountingReportValueRow(
                          key: ValueKey(
                            'sales-category-${category.id?.value ?? 'unclassified'}',
                          ),
                          label: category.name,
                          value: _amount(category.netMinor),
                          onTap: () => _showSalesCategory(sales, category),
                        ),
                      const Divider(),
                      AccountingReportValueRow(
                        label: 'Total',
                        value: _amount(sales.netMinor),
                        emphasized: true,
                      ),
                    ] else ...[
                      for (final row in report.rows)
                        if (row.endingNetDebit != BigInt.zero)
                          _accountRow(
                            report,
                            row,
                            '${row.account.displayName} · ${row.endingNetDebit.isNegative ? 'Credit' : 'Debit'}',
                            row.endingNetDebit.abs(),
                          ),
                      const Divider(),
                      _row('Total Debits', report.trialBalanceDebits),
                      _row('Total Credits', report.trialBalanceCredits),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<(String, String, IconData, Color)> _reportSummaryMetrics(
  LedgerReport? report,
  int reviewCount,
) => [
  (
    'Posted Journals',
    report == null
        ? '—'
        : '${report.postedJournalIds.length} Journal${report.postedJournalIds.length == 1 ? '' : 's'}',
    Icons.receipt_outlined,
    AccountingColorLibrary.blueJeansDeep,
  ),
  (
    'Pending Drafts',
    report == null
        ? '—'
        : '${report.pendingDrafts} Draft${report.pendingDrafts == 1 ? '' : 's'}',
    Icons.pending_actions_outlined,
    AccountingColorLibrary.sunflowerDeep,
  ),
  (
    'Accounts Tracked',
    report == null
        ? '—'
        : '${report.rows.length} Account${report.rows.length == 1 ? '' : 's'}',
    Icons.verified_outlined,
    AccountingColorLibrary.primaryGreen,
  ),
  (
    'Needs Review',
    report == null ? '—' : '$reviewCount Item${reviewCount == 1 ? '' : 's'}',
    Icons.fact_check_outlined,
    AccountingColorLibrary.grapefruit,
  ),
];

String _compactReportSummaryLabel(String label) => switch (label) {
  'Posted Journals' => 'Journals',
  'Pending Drafts' => 'Drafts',
  'Accounts Tracked' => 'Accounts',
  'Needs Review' => 'Review',
  _ => label,
};

List<double> reportSummaryMetricWidths(
  BuildContext context, {
  LedgerReport? report,
  int reviewCount = 0,
}) {
  final labelStyle = Theme.of(context).textTheme.bodyMedium
      ?.copyWith(color: AccountingTheme.of(context).mutedForeground, height: 1);
  final valueStyle = AccountingTypography.sectionTitle(context)
      .copyWith(height: 1);
  return [
    for (final item in _reportSummaryMetrics(report, reviewCount))
      accountingMetricIconExtent +
          12 +
          [
            AccountingResponsive.measuredTextWidth(
              context,
              _compactReportSummaryLabel(item.$1),
              labelStyle,
            ),
            AccountingResponsive.measuredTextWidth(
              context,
              item.$2,
              valueStyle,
            ),
          ].reduce((a, b) => a > b ? a : b),
  ];
}

double reportSummaryCombinedMinWidth(
  BuildContext context, {
  LedgerReport? report,
  int reviewCount = 0,
}) {
  final widths = reportSummaryMetricWidths(
    context,
    report: report,
    reviewCount: reviewCount,
  );
  // The accepted bar uses equal Expanded slots. Reserve the widest metric
  // in every slot; summing unequal minima can silently ellipsize a value.
  return widths.reduce((a, b) => a > b ? a : b) * widths.length +
      (accountingContentInset * 2 + 1) * (widths.length - 1) +
      accountingContentInset * 2;
}

class AccountingReportsSummaryStrip extends StatelessWidget {
  const AccountingReportsSummaryStrip({
    super.key,
    required this.report,
    required this.reviewCount,
    this.onNeedsReview,
    this.onPostedJournals,
    this.onPendingDrafts,
    this.onAccounts,
  });
  final LedgerReport? report;
  final int reviewCount;
  final VoidCallback? onNeedsReview;
  final VoidCallback? onPostedJournals;
  final VoidCallback? onPendingDrafts;
  final VoidCallback? onAccounts;
  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final metrics = _reportSummaryMetrics(report, reviewCount);
    VoidCallback? action(String label) => switch (label) {
      'Posted Journals' => onPostedJournals,
      'Pending Drafts' => onPendingDrafts,
      'Accounts Tracked' => onAccounts,
      'Needs Review' => onNeedsReview,
      _ => null,
    };
    Widget metric((String, String, IconData, Color) item) => Row(
      key: ValueKey<String>('report-summary-${item.$1}'),
      children: [
        AccountingMetricIconBox(
          item.$3,
          fillColor: item.$4,
          onPressed: action(item.$1),
          tooltip: 'Open ${item.$1}',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: action(item.$1),
            behavior: HitTestBehavior.opaque,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labelStyle = Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.mutedForeground, height: 1);
                final fullLabelFits =
                    AccountingResponsive.measuredTextWidth(
                      context,
                      item.$1,
                      labelStyle,
                    ) <=
                    constraints.maxWidth;
                return AccountingMetricTextGroup(
                  label: Text(
                    fullLabelFits
                        ? item.$1
                        : _compactReportSummaryLabel(item.$1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    semanticsLabel: item.$1,
                    style: labelStyle,
                  ),
                  value: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AccountingTypography.sectionTitle(context)
                        .copyWith(height: 1),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumMetricWidths = reportSummaryMetricWidths(
          context,
          report: report,
          reviewCount: reviewCount,
        );
        if (constraints.maxWidth <
            reportSummaryCombinedMinWidth(
              context,
              report: report,
              reviewCount: reviewCount,
            )) {
          final columns = AccountingResponsive.balancedColumnCount(
            constraints.maxWidth,
            metrics.length,
            minItemWidth:
                minimumMetricWidths.reduce((a, b) => a > b ? a : b) +
                accountingContentInset * 2,
          );
          final cardWidth =
              (constraints.maxWidth -
                  (columns - 1) * AccountingResponsive.groupGap) /
              columns;
          return Wrap(
            spacing: AccountingResponsive.groupGap,
            runSpacing: AccountingResponsive.groupGap,
            children: [
              for (final item in metrics)
                SizedBox(
                  width: cardWidth,
                  child: AccountingCard.surface(
                    context,
                    key: ValueKey<String>('report-summary-card-${item.$1}'),
                    child: Padding(
                      padding: accountingContentPadding,
                      child: metric(item),
                    ),
                  ),
                ),
            ],
          );
        }
        return AccountingCard.surface(
          context,
          key: const ValueKey('report-summary-strip'),
          child: Padding(
            padding: accountingContentPadding,
            child: Row(
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 42,
                      color: tokens.border,
                      margin: const EdgeInsets.symmetric(
                        horizontal: accountingContentInset,
                      ),
                    ),
                  Expanded(child: metric(metrics[i])),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The current Ledger Reports selector/card composition. Design previews and
/// related reports use this owner instead of copying a previous report layout.
class AccountingReportViewSection extends StatelessWidget {
  const AccountingReportViewSection({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.content,
    this.labels = _reportViewLabels,
    this.icons = const [
      Icons.account_tree_outlined,
      Icons.insert_chart_outlined,
      Icons.fact_check_outlined,
      Icons.insert_chart_outlined,
    ],
  }) : assert(labels.length == icons.length);
  final String selected;
  final ValueChanged<String> onChanged;
  final Widget content;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final quality = AccountingCard.surface(
        context,
        key: const ValueKey('report-quality-card'),
        child: content,
      );
      final selectorWidth = AccountingReportViewSelector.visibleWidth(
        context,
        labels: labels,
      );
      if (constraints.maxWidth - selectorWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingTabs(
              embedded: true,
              labels: labels,
              selectedIndex: labels.indexOf(selected),
              onChanged: (index) => onChanged(labels[index]),
              keyPrefix: 'report-tab',
            ),
            const SizedBox(height: accountingContentInset),
            quality,
          ],
        );
      }
      return Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: AccountingReportViewSelector(
              selected: selected,
              onChanged: onChanged,
              labels: labels,
              icons: icons,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  // The adjoining report choices own the minimum card height.
                  // Short category lists must not clip the selected final view.
                  constraints: BoxConstraints(
                    minHeight:
                        accountingControlHeight * labels.length +
                        AccountingReportViewSelector._bandInset * 2,
                  ),
                  child: quality,
                ),
              ),
              SizedBox(width: selectorWidth),
            ],
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
            top:
                AccountingReportViewSelector._bandInset +
                labels.indexOf(selected) * accountingControlHeight,
            right: selectorWidth - 2,
            width: AccountingReportViewSelector._overlap + 4,
            height: accountingControlHeight,
            child: ColoredBox(color: AccountingTheme.of(context).card),
          ),
        ],
      );
    },
  );
}

/// Existing undivided ledger value row; totals retain AccountingTotalRow.
class AccountingReportValueRow extends StatelessWidget {
  const AccountingReportValueRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
    this.onTap,
  });
  final String label, value;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = emphasized
        ? AccountingTotalRow(label: label, value: value)
        : Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: accountingUndividedRowVerticalInset,
            ),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: 12),
                Text(value),
              ],
            ),
          );
    return onTap == null
        ? row
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: row,
          );
  }
}

class AccountingReportQualityMeasure {
  const AccountingReportQualityMeasure(
    this.label,
    this.count,
    this.total,
    this.source, {
    this.breakdown,
  }) : _salesFraction = null,
       _salesDisplay = null,
       _salesExplanation = null;

  factory AccountingReportQualityMeasure.salesShare(
    String label,
    BigInt value,
    BigInt total,
  ) {
    if (total <= BigInt.zero) {
      return AccountingReportQualityMeasure._sales(
        label,
        0,
        '—',
        'Sales share is unavailable when total net sales is zero or negative.',
      );
    }
    final scaled = value.abs() * BigInt.from(100);
    final rounded =
        scaled ~/ total +
        (scaled % total * BigInt.two >= total ? BigInt.one : BigInt.zero);
    final fraction = value <= BigInt.zero
        ? 0.0
        : value >= total
        ? 1.0
        : ((value * BigInt.from(1000000)) ~/ total).toInt() / 1000000;
    return AccountingReportQualityMeasure._sales(
      label,
      fraction,
      '${value.isNegative ? '-' : ''}$rounded%',
      'Share of posted net sales in the applied report period.',
    );
  }

  const AccountingReportQualityMeasure._sales(
    this.label,
    this._salesFraction,
    this._salesDisplay,
    this._salesExplanation,
  ) : count = 0,
      total = 0,
      source = '',
      breakdown = null;

  final double? _salesFraction;
  final String? _salesDisplay, _salesExplanation;
  final String label;
  final int count;
  final int total;
  final String source;
  final String? breakdown;
  double get fraction => _salesFraction ?? (total == 0 ? 0 : count / total);
  String get display =>
      _salesDisplay ??
      (total == 0
          ? '—'
          : label == 'Reconciliation progress'
          ? '$count of $total · ${(fraction * 100).round()}%'
          : '${(fraction * 100).round()}%');
  String get explanation =>
      _salesExplanation ??
      (total == 0
          ? 'No data to calculate $label.'
          : '$count of $total $source.');

  static const empty = <AccountingReportQualityMeasure>[
    AccountingReportQualityMeasure(
      'Expense receipts',
      0,
      0,
      'expense records dated in the report range include a receipt',
    ),
    AccountingReportQualityMeasure(
      'Reconciliation progress',
      0,
      0,
      'imported bank rows in the report range are connected to ledger entries',
    ),
    AccountingReportQualityMeasure(
      'Posted entries',
      0,
      0,
      'journal entries dated in the report range have been posted',
    ),
  ];
}

class AccountingReportQualityCard extends StatelessWidget {
  const AccountingReportQualityCard({
    super.key,
    required this.measures,
    this.title = 'Quality measures',
    this.onSelected,
    this.emptyMessage,
  });
  final String? emptyMessage;
  final List<AccountingReportQualityMeasure> measures;
  final String title;
  final ValueChanged<AccountingReportQualityMeasure>? onSelected;

  @override
  Widget build(BuildContext context) {
    final ranked = [...measures]
      ..sort((a, b) => b.fraction.compareTo(a.fraction));
    return Padding(
      // Match the title's painted top inset to the final bar's bottom inset.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AccountingTypography.sectionTitle(context)),
          const SizedBox(height: accountingContentInset),
          if (measures.isEmpty && emptyMessage != null) Text(emptyMessage!),
          for (final (index, row) in measures.indexed) ...[
            if (index > 0) const SizedBox(height: AccountingProgressBar.rowGap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: row.explanation,
                  child: InkWell(
                    onTap: onSelected == null ? null : () => onSelected!(row),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(row.label)),
                        const SizedBox(width: 8),
                        Text(
                          row.display,
                          key: ValueKey('quality-value-$index'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AccountingProgressBar.labelGap),
                AccountingProgressBar(
                  key: ValueKey('quality-progress-$index'),
                  value: row.fraction,
                  color:
                      AccountingColorLibrary.chartSeries[ranked.indexOf(row) %
                          AccountingColorLibrary.chartSeries.length],
                ),
                if (row.breakdown != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    row.breakdown!,
                    key: ValueKey('quality-breakdown-$index'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AccountingTheme.of(context).mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _reportViewLabels = <String>[
  'Balance Sheet',
  'Profit And Loss',
  'Trial Balance',
  'Sales',
];

class AccountingReportViewSelector extends StatelessWidget {
  const AccountingReportViewSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.labels = _reportViewLabels,
    this.icons = const [
      Icons.account_tree_outlined,
      Icons.insert_chart_outlined,
      Icons.fact_check_outlined,
      Icons.insert_chart_outlined,
    ],
  }) : assert(labels.length == icons.length);

  final String selected;
  final ValueChanged<String> onChanged;
  final List<String> labels;
  final List<IconData> icons;
  static const double _overlap = accountingSectionRadius;
  static const double _bandInset = 3;
  static const double _labelInset = accountingContentInset;
  static const double _iconSize = 18;
  static double visibleWidth(
    BuildContext context, {
    List<String> labels = _reportViewLabels,
  }) {
    var longest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: AccountingTypography.navigation(context, selected: true),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > longest) longest = painter.width;
    }
    return longest + _labelInset * 3 + _iconSize;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final selectedIndex = labels.indexOf(selected);
    return SizedBox(
      key: const ValueKey('report-view-selector'),
      width: visibleWidth(context, labels: labels) + _overlap,
      height: accountingControlHeight * labels.length + _bandInset * 2,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(accountingControlRadius),
          bottomRight: Radius.circular(accountingControlRadius),
        ),
        child: ColoredBox(
          color: accountingTabBandColor(context),
          child: Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('report-selector-indicator'),
                duration: const Duration(milliseconds: 300),
                curve: Curves.ease,
                left: _bandInset,
                right: _bandInset,
                top: _bandInset + selectedIndex * accountingControlHeight,
                height: accountingControlHeight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: BorderRadius.circular(
                      accountingControlRadius,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(_bandInset),
                child: Column(
                  children: [
                    for (final (index, label) in labels.indexed)
                      Semantics(
                        selected: label == selected,
                        button: true,
                        label: label,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: ValueKey('report-tab-$index'),
                            onTap: () => onChanged(label),
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            splashFactory: NoSplash.splashFactory,
                            child: SizedBox(
                              height: accountingControlHeight,
                              child: Padding(
                                // Match the sidebar item's painted 20px
                                // label inset after the chart masks overlap.
                                padding: const EdgeInsets.only(
                                  left: _overlap + _labelInset - _bandInset,
                                  right: _labelInset - _bandInset,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: AnimatedDefaultTextStyle(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.ease,
                                            style:
                                                AccountingTypography.navigation(
                                                  context,
                                                  selected: label == selected,
                                                ).copyWith(
                                                  color: label == selected
                                                      ? tokens.foreground
                                                      : tokens.mutedForeground,
                                                ),
                                            child: Text(label, maxLines: 1),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: _labelInset),
                                      AccountingIcon(
                                        icons[index],
                                        size: _iconSize,
                                        color: label == selected
                                            ? tokens.foreground
                                            : tokens.mutedForeground,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
