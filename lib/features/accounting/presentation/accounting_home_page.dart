import '../domain/workspace_reminder.dart';
import '../domain/company_preferences.dart';

import 'dart:math' as math;

import '../../../../core/money/currency.dart';
import '../domain/ledger_report.dart';
import 'widgets/expense_pie_chart.dart';
import 'widgets/sales_profit_chart.dart';
import '../domain/account.dart';
import '../domain/journal_entry.dart';
import '../domain/payment_account.dart';
import '../../../../app/design_samples.dart';
import '../application/accounting_workspace.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/money.dart';
import 'widgets/accounting_formatters.dart';
import 'widgets/accounting_layout.dart';

Map<String, Money> _categoryBreakdown(
  LedgerReport report,
  Map<String, String> sourceCategories, {
  bool byAccount = false,
  String unknown = 'Uncategorized',
}) {
  final expenseIds = report.rows
      .where(
        (r) =>
            r.account.type == AccountType.expense &&
            !_isDirectCostName(r.account.name),
      )
      .map((r) => r.account.id)
      .toSet();
  final totals = <String, BigInt>{};
  for (final entry in report.postedEntries) {
    if (entry.isClosing || entry.date.isBefore(report.from)) continue;
    final category =
        sourceCategories[entry.id.value] ??
        sourceCategories[entry.reversesId?.value];
    final label = category == null || category.trim().isEmpty
        ? unknown
        : category;
    for (final line in entry.lines.where(
      (l) => expenseIds.contains(l.accountId),
    )) {
      final accountName = report.rows
          .firstWhere((row) => row.account.id == line.accountId)
          .account
          .name;
      final groupLabel = byAccount ? accountName : label;
      final amount =
          BigInt.from(line.amount.minorUnits) *
          BigInt.from(line.isDebit ? 1 : -1);
      totals.update(groupLabel, (v) => v + amount, ifAbsent: () => amount);
    }
  }
  return {
    for (final entry in totals.entries)
      entry.key: Money.fromDecimal(
        // Use the shared exact-money parser rather than narrowing an arbitrary BigInt.
        _categoryAmountDecimal(entry.value, report.currency),
        report.currency,
      ),
  };
}

bool _isDirectCostName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('cost of goods') ||
      normalized.contains('cost of sales') ||
      normalized.contains('cogs');
}

String _categoryAmountDecimal(BigInt value, String currency) {
  final digits = Currency.parse(currency).fractionDigits;
  final scale = BigInt.from(10).pow(digits);
  final magnitude = value.abs();
  return '${value.isNegative ? '-' : ''}${magnitude ~/ scale}${digits == 0 ? '' : '.${(magnitude % scale).toString().padLeft(digits, '0')}'}';
}

enum AccountingHomeStatus { loading, ready, error }

class AccountingExpense {
  const AccountingExpense({
    required this.occurredOn,
    required this.category,
    required this.amount,
    this.payee,
  });

  final DateTime occurredOn;
  final String? payee;
  final String category;
  final Money amount;
}

class AccountingHomeData {
  const AccountingHomeData({
    required this.currencyCode,
    required this.recentExpenses,
    this.asOf,
    this.status = AccountingHomeStatus.ready,
    this.errorMessage,
    this.postedMonthTotal,
    this.postedYearTotal,
    this.postedMonthSales,
    this.postedYearSales,
    this.postedBankBalance,
    this.bankAccounts = const [],
    this.bankAccountBalances = const {},
    this.trendActivities = const [],
    this.postedExpenseAccounts,
    this.postedMonthExpenseAccounts,
    this.monthPayees,
    this.yearPayees,
    this.monthAccounts,
    this.yearAccounts,
    this.needsReviewCount = 0,
  });

  factory AccountingHomeData.empty({
    required String currencyCode,
    DateTime? asOf,
  }) {
    return AccountingHomeData(
      currencyCode: currencyCode,
      recentExpenses: const <AccountingExpense>[],
      asOf: asOf,
    );
  }

  factory AccountingHomeData.fromExpenses({
    required String currencyCode,
    required Iterable<AccountingExpense> expenses,
    DateTime? asOf,
  }) {
    final sortedExpenses = expenses.toList()
      ..sort((left, right) => right.occurredOn.compareTo(left.occurredOn));
    return AccountingHomeData(
      currencyCode: currencyCode,
      recentExpenses: List<AccountingExpense>.unmodifiable(sortedExpenses),
      asOf: asOf,
    );
  }

  final String currencyCode;
  final int needsReviewCount;
  final List<AccountingExpense> recentExpenses;
  final DateTime? asOf;
  final AccountingHomeStatus status;
  final String? errorMessage;
  final Money? postedMonthTotal;
  final Money? postedYearTotal;
  final Money? postedMonthSales;
  final Money? postedYearSales;
  final Money? postedBankBalance;
  final List<PaymentAccount> bankAccounts;
  final Map<String, Money> bankAccountBalances;
  final List<SalesTrendActivity> trendActivities;
  final Map<String, Money>? monthPayees,
      yearPayees,
      monthAccounts,
      yearAccounts;
  final Map<String, Money>? postedExpenseAccounts;
  final Map<String, Money>? postedMonthExpenseAccounts;
  Map<String, Money> expenseAccounts({
    required bool month,
    String grouping = 'Category',
  }) {
    if (grouping == 'Payee') return (month ? monthPayees : yearPayees) ?? {};
    if (grouping == 'Account') {
      return (month ? monthAccounts : yearAccounts) ?? {};
    }
    final posted = month ? postedMonthExpenseAccounts : postedExpenseAccounts;
    if (posted != null) return posted;
    final amounts = <String, Money>{};
    for (final expense in recentExpenses) {
      if (expense.occurredOn.year != referenceDate.year ||
          (month && expense.occurredOn.month != referenceDate.month) ||
          expense.occurredOn.isAfter(referenceDate) ||
          expense.amount.currency != currencyCode) {
        continue;
      }
      amounts.update(
        expense.category,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    return amounts;
  }

  DateTime get referenceDate => asOf ?? DateTime.now();

  bool get isEmpty => recentExpenses.isEmpty;

  Money get expensesThisMonth =>
      postedMonthTotal ??
      _sumWhere(
        (expense) =>
            expense.occurredOn.year == referenceDate.year &&
            expense.occurredOn.month == referenceDate.month,
      );

  Money get expensesThisYear =>
      postedYearTotal ??
      _sumWhere((expense) => expense.occurredOn.year == referenceDate.year);

  Money get salesThisMonth => postedMonthSales ?? Money.zero(currencyCode);
  Money get salesThisYear => postedYearSales ?? Money.zero(currencyCode);
  Money get bankBalance => postedBankBalance ?? Money.zero(currencyCode);
  Money bankBalanceFor(String? accountId) => accountId == null
      ? bankBalance
      : bankAccountBalances[accountId] ?? Money.zero(currencyCode);

  String bankBalanceLabel(String? accountId) {
    if (accountId == null) return 'All Balance';
    for (final account in bankAccounts) {
      if (account.id == accountId) {
        return account.shortName;
      }
    }
    return 'All Balance';
  }

  AccountingExpense? get lastRecorded {
    if (recentExpenses.isEmpty) {
      return null;
    }
    return recentExpenses.reduce(
      (left, right) => left.occurredOn.isAfter(right.occurredOn) ? left : right,
    );
  }

  Money _sumWhere(bool Function(AccountingExpense) predicate) {
    var total = Money.zero(currencyCode);
    for (final expense in recentExpenses) {
      if (predicate(expense) && expense.amount.currency == currencyCode) {
        total += expense.amount;
      }
    }
    return total;
  }
}

class WorkspaceAccountingHome extends StatefulWidget {
  const WorkspaceAccountingHome({
    super.key,
    required this.workspace,
    this.asOf,
    required this.includeTopSafeArea,
    required this.onRecordExpense,
    this.onNeedsReview,
    this.onDataChanged,
    this.topInset = AccountingResponsive.pageTitleOuterGap,
    this.reviewCount = 0,
  });
  final AccountingWorkspace workspace;
  final DateTime? asOf;
  final bool includeTopSafeArea;
  final double topInset;
  final VoidCallback onRecordExpense;
  final VoidCallback? onNeedsReview;
  final ValueChanged<AccountingHomeData>? onDataChanged;
  final int reviewCount;
  @override
  State<WorkspaceAccountingHome> createState() =>
      _WorkspaceAccountingHomeState();
}

class _WorkspaceAccountingHomeState extends State<WorkspaceAccountingHome> {
  AccountingHomeData? _data;
  List<WorkspaceReminder> _reminders = [];
  CompanyPreferences _preferences = CompanyPreferences.defaults();
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkspaceAccountingHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace ||
        oldWidget.asOf != widget.asOf) {
      oldWidget.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _data = null;
      _reminders = [];
      _preferences = CompanyPreferences.defaults();
      _load();
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_load);
    super.dispose();
  }

  Money _money(BigInt amount) {
    final minor = amount.toInt();
    if (BigInt.from(minor) != amount) {
      throw StateError('Total exceeds supported amount range.');
    }
    return Money.fromMinor(minor, widget.workspace.identity.currency);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final workspace = widget.workspace;
    final now = widget.asOf ?? DateTime.now();
    final through = DateTime.utc(now.year, now.month, now.day);
    try {
      final preferences = workspace.preferences;
      final reminders = workspace.reminders;
      final year = await workspace.report(
        from: DateTime.utc(now.year),
        through: through,
      );
      final month = await workspace.report(
        from: DateTime.utc(now.year, now.month),
        through: through,
      );
      final allTime = await workspace.report(
        from: DateTime.utc(1),
        through: through,
      );
      final bankAccounts = workspace.paymentAccounts
          .where((payment) => payment.type == PaymentAccountType.bank)
          .toList(growable: false);
      final bankAccountIds = bankAccounts
          .map(
            (payment) => workspace.database.paymentLedgerAccount(
              workspace.identity.businessId,
              payment.id,
            ),
          )
          .whereType<EntityId>()
          .toSet();
      final bankBalance = allTime.rows
          .where((row) => bankAccountIds.contains(row.account.id))
          .fold<BigInt>(BigInt.zero, (sum, row) => sum + row.endingNetDebit);
      final balancesByLedgerId = {
        for (final row in allTime.rows)
          if (bankAccountIds.contains(row.account.id))
            row.account.id: row.endingNetDebit,
      };
      final bankAccountBalances = {
        for (final account in bankAccounts)
          account.id: _money(
            balancesByLedgerId[workspace.database.paymentLedgerAccount(
                  workspace.identity.businessId,
                  account.id,
                )] ??
                BigInt.zero,
          ),
      };
      final accountById = {
        for (final row in year.rows) row.account.id: row.account,
      };
      final invoiceJournalIds = workspace
          .postedInvoices()
          .map((invoice) => invoice.journalId)
          .toSet();
      final activities = <SalesTrendActivity>[];
      for (final entry in year.postedEntries) {
        if (entry.isClosing) continue;
        var invoiced = 0, costs = 0, directCosts = 0, bankDebit = 0;
        for (final line in entry.lines) {
          final account = accountById[line.accountId];
          if (account == null) continue;
          final amount = line.amount.minorUnits;
          if (account.type == AccountType.income) {
            invoiced += line.isCredit ? amount : -amount;
          } else if (account.type == AccountType.expense) {
            final signed = line.isDebit ? amount : -amount;
            costs += signed;
            if (_isDirectCostName(account.name)) {
              directCosts += signed;
            }
          }
          if (bankAccountIds.contains(line.accountId)) {
            bankDebit += line.isDebit ? amount : -amount;
          }
        }
        activities.add(
          SalesTrendActivity(
            date: entry.date,
            invoicedMinor: invoiced,
            receivedMinor: invoiced > 0 && bankDebit > 0
                ? math.min(invoiced, bankDebit)
                : 0,
            costMinor: costs,
            directCostMinor: directCosts,
            invoiceCount: invoiceJournalIds.contains(entry.id) ? 1 : 0,
            receiptCount: invoiced > 0 && bankDebit > 0 ? 1 : 0,
          ),
        );
      }
      for (final receipt in workspace.database.customerReceiptHistory(
        workspace.identity.businessId,
      )) {
        if (!DateTime.utc(
          receipt.date.year,
          receipt.date.month,
          receipt.date.day,
        ).isAfter(through)) {
          activities.add(
            SalesTrendActivity(
              date: receipt.date,
              receivedMinor: receipt.total.minorUnits,
              receiptCount: 1,
            ),
          );
        }
      }
      final recentRecords = workspace.database.readRecentPostedExpenseIntakes(
        businessId: workspace.identity.businessId,
        through: through,
      );
      final pendingExpenseCount = workspace.database
          .readPendingExpenseIntakes(
            businessId: workspace.identity.businessId,
            limit: 1,
          )
          .count;
      final draftJournalCount = workspace.database
          .readJournalPage(
            businessId: workspace.identity.businessId,
            state: JournalEntryState.draft,
            limit: 1,
          )
          .total;
      final needsReviewCount =
          pendingExpenseCount +
          draftJournalCount +
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
      final expenses = recentRecords
          .map(
            (e) => AccountingExpense(
              occurredOn: e.occurredOn,
              category: e.category,
              amount: e.amount,
              payee: e.payee,
            ),
          )
          .toList();
      final journalIds = <EntityId>{};
      for (final entry in year.postedEntries) {
        if (entry.date.isBefore(year.from)) continue;
        journalIds.add(entry.id);
        if (entry.reversesId != null) journalIds.add(entry.reversesId!);
      }
      final sourceLabels = workspace.database.expenseSourceLabelsForJournals(
        businessId: workspace.identity.businessId,
        journalIds: journalIds,
      );
      final claimRecognitions = workspace.claimRecognitionSnapshots;
      final sourcePayees = {
        for (final source in sourceLabels.entries)
          source.key: source.value.payee,
        for (final recognition in claimRecognitions.entries)
          recognition.key.value: recognition.value.vendorName,
      };
      final sourceCategories = {
        for (final source in sourceLabels.entries)
          source.key: source.value.category,
        for (final recognition in claimRecognitions.entries)
          recognition.key.value: recognition.value.category,
      };
      final data = AccountingHomeData(
        currencyCode: workspace.identity.currency,
        needsReviewCount: needsReviewCount,
        recentExpenses: List.unmodifiable(expenses),
        asOf: now,
        postedMonthTotal: _money(month.expenses),
        postedMonthSales: _money(month.revenue),
        postedBankBalance: _money(bankBalance),
        bankAccounts: List.unmodifiable(bankAccounts),
        bankAccountBalances: Map.unmodifiable(bankAccountBalances),
        trendActivities: List.unmodifiable(activities),
        monthPayees: _categoryBreakdown(
          month,
          sourcePayees,
          unknown: 'Unspecified Payee',
        ),
        yearPayees: _categoryBreakdown(
          year,
          sourcePayees,
          unknown: 'Unspecified Payee',
        ),
        monthAccounts: _categoryBreakdown(month, {}, byAccount: true),
        yearAccounts: _categoryBreakdown(year, {}, byAccount: true),
        postedYearTotal: _money(year.expenses),
        postedYearSales: _money(year.revenue),
        postedMonthExpenseAccounts: _categoryBreakdown(month, sourceCategories),
        postedExpenseAccounts: _categoryBreakdown(year, sourceCategories),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _preferences = preferences;
          _reminders = reminders;
        });
        widget.onDataChanged?.call(data);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        final data = AccountingHomeData(
          currencyCode: workspace.identity.currency,
          recentExpenses: const [],
          status: AccountingHomeStatus.error,
        );
        setState(() => _data = data);
        widget.onDataChanged?.call(data);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AccountingHomePage(
    data:
        _data ??
        AccountingHomeData(
          currencyCode: widget.workspace.identity.currency,
          recentExpenses: const [],
          status: AccountingHomeStatus.loading,
        ),
    includeTopSafeArea: widget.includeTopSafeArea,
    topInset: widget.topInset,
    onRecordExpense: widget.onRecordExpense,
    onNeedsReview: widget.onNeedsReview,
    reviewCount: widget.reviewCount,
    onRetry: _load,
    titleKey: 'page-title-home',
    preferenceKey: widget.workspace.identity.businessId.value,
    reminders: _reminders,
    preferences: _preferences,
    onReminderSave: widget.workspace.saveReminder,
  );
}

class AccountingHomePage extends StatefulWidget {
  const AccountingHomePage({
    required this.data,
    super.key,
    this.onRecordExpense,
    this.onNeedsReview,
    this.onRetry,
    this.includeTopSafeArea = true,
    this.topInset = AccountingResponsive.pageTitleOuterGap,
    this.titleKey,
    this.reviewCount = 0,
    this.preferenceKey,
    this.reminders,
    this.preferences,
    this.onReminderSave,
  });

  final List<WorkspaceReminder>? reminders;
  final CompanyPreferences? preferences;
  final ValueChanged<WorkspaceReminder>? onReminderSave;
  final AccountingHomeData data;
  final VoidCallback? onRecordExpense;
  final VoidCallback? onNeedsReview;
  final VoidCallback? onRetry;
  final bool includeTopSafeArea;
  final double topInset;
  final String? titleKey;
  final int reviewCount;
  final String? preferenceKey;

  @override
  State<AccountingHomePage> createState() => _AccountingHomePageState();
}

class _AccountingHomePageState extends State<AccountingHomePage> {
  static final Map<String, _HomeChartSelection> _remembered = {};
  static final Map<String, String> _rememberedBankAccounts = {};
  late _HomeChartSelection selection;
  String? _selectedBankAccountId;

  @override
  void initState() {
    super.initState();
    selection =
        _remembered[widget.preferenceKey] ?? const _HomeChartSelection();
    _selectedBankAccountId = _rememberedBankAccounts[widget.preferenceKey];
  }

  @override
  void didUpdateWidget(covariant AccountingHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferenceKey != widget.preferenceKey) {
      selection =
          _remembered[widget.preferenceKey] ?? const _HomeChartSelection();
      _selectedBankAccountId = _rememberedBankAccounts[widget.preferenceKey];
    }
  }

  String? get _bankAccountId =>
      widget.data.bankAccounts.any(
        (account) => account.id == _selectedBankAccountId,
      )
      ? _selectedBankAccountId
      : null;

  void _selectBankAccount(String? id) {
    setState(() => _selectedBankAccountId = id);
    if (widget.preferenceKey case final key?) {
      if (id == null) {
        _rememberedBankAccounts.remove(key);
      } else {
        _rememberedBankAccounts[key] = id;
      }
    }
  }

  void _select(_HomeChartSelection next) {
    setState(() => selection = next);
    if (widget.preferenceKey case final key?) _remembered[key] = next;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final onRecordExpense = widget.onRecordExpense;
    final onRetry = widget.onRetry;
    final titleKey = widget.titleKey;
    final reviewCount = widget.reviewCount;
    final includeTopSafeArea = widget.includeTopSafeArea;
    final topInset = widget.topInset;
    final visibleReminders = widget.reminders == null
        ? null
        : homeReminders(widget.reminders!, widget.preferences!, DateTime.now());
    final reminderCount = visibleReminders?.length ?? demoReminderTitles.length;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AccountingPageHeader(
          routeLabel: 'Home',
          title: 'Home',
          description: 'Track expenses and keep your records current.',
          titleKey: titleKey,
          action: AccountingButton.primary(
            context,
            key: const ValueKey('home-record-expense-action'),
            onPressed: onRecordExpense,
            leadingIcon: Icons.add_rounded,
            child: const Text('Record Expense'),
          ),
        ),
        const SizedBox(height: accountingPageTitleOuterGap),
        _HomeKpiStrip(
          data: data,
          reviewCount: reviewCount + data.needsReviewCount,
          month: selection.month,
          bankAccountId: _bankAccountId,
          onBankAccountSelected: _selectBankAccount,
          onNeedsReview: widget.onNeedsReview,
        ),
        const SizedBox(height: AccountingResponsive.sectionGap),
        if (data.status == AccountingHomeStatus.ready)
          _ExpenseOverview(data: data, selection: selection, onSelect: _select)
        else if (data.status == AccountingHomeStatus.loading)
          SizedBox(
            key: const ValueKey('expense-overview-loading'),
            height: 220,
            child: Center(
              child: AccountingSkeleton.build(context, height: 180, width: 180),
            ),
          ),
        const SizedBox(height: AccountingResponsive.sectionGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final compactSummary =
                constraints.maxWidth <
                homeKpiCombinedMinWidth(
                  context,
                  data,
                  reviewCount + data.needsReviewCount,
                  month: selection.month,
                  bankAccountId: _bankAccountId,
                );
            return DemoReminderPanel(
              reminders: visibleReminders,
              preferences: widget.preferences,
              onSave: widget.onReminderSave,
              availableWidth: constraints.maxWidth,
              leadingCard:
                  compactSummary && reminderCount != 2 && reminderCount != 4
                  ? AccountingCard.surface(
                      context,
                      key: const ValueKey('home-kpi-card-1'),
                      child: Padding(
                        padding: accountingContentPadding,
                        child: _HomeKpiStrip.metric(
                          context,
                          Icons.account_balance_outlined,
                          data.bankBalanceLabel(_bankAccountId),
                          formatAccountingMoney(
                            context,
                            data.bankBalanceFor(_bankAccountId),
                          ),
                          valueFontSize: homeKpiValueFontSize(
                            data,
                            bankAccountId: _bankAccountId,
                          ),
                          trailing: data.bankAccounts.isEmpty
                              ? null
                              : _BankBalanceMenu(
                                  data: data,
                                  selectedId: _bankAccountId,
                                  onSelected: _selectBankAccount,
                                ),
                        ),
                      ),
                    )
                  : null,
            );
          },
        ),
        const SizedBox(height: AccountingResponsive.sectionGap),
        _RecentExpensesCard(
          data: data,
          onRecordExpense: onRecordExpense,
          onRetry: onRetry,
        ),
      ],
    );

    return AccountingPageShell(
      includeTopSafeArea: includeTopSafeArea,
      topInset: topInset,
      child: data.status == AccountingHomeStatus.loading
          ? Semantics(
              key: const ValueKey('accounting-home-loading'),
              container: true,
              explicitChildNodes: true,
              liveRegion: true,
              label: 'Loading accounting home',
              child: content,
            )
          : content,
    );
  }
}

double homeKpiValueFontSize(
  AccountingHomeData data, {
  bool month = true,
  String? bankAccountId,
}) {
  int wholeDigits(Money amount) {
    final scale = BigInt.from(10)
        .pow(Currency.parse(amount.currency).fractionDigits);
    return (BigInt.from(amount.minorUnits).abs() ~/ scale).toString().length;
  }

  final digits = math.max(
    wholeDigits(month ? data.salesThisMonth : data.salesThisYear),
    wholeDigits(data.bankBalanceFor(bankAccountId)),
  );
  if (digits <= 5) return accountingMetricValueFontSize;
  if (digits == 6) return 20;
  if (digits == 7) return 18;
  return 16;
}

List<double> homeKpiMetricWidths(
  BuildContext context,
  AccountingHomeData data,
  int reviewCount, {
  bool month = true,
  String? bankAccountId,
}) {
  final total = formatAccountingMoney(
    context,
    month ? data.salesThisMonth : data.salesThisYear,
  );
  final bankBalance = formatAccountingMoney(
    context,
    data.bankBalanceFor(bankAccountId),
  );
  final theme = Theme.of(context).textTheme;
  final labelStyle = theme.bodyMedium?.copyWith(
    color: AccountingTheme.of(context).mutedForeground,
    height: 1,
  );
  final valueStyle = theme.headlineSmall?.copyWith(
    fontSize: homeKpiValueFontSize(
      data,
      month: month,
      bankAccountId: bankAccountId,
    ),
    height: 1,
  );
  return [
    for (final (label, value) in [
      (month ? 'This Month' : 'This Year', total),
      (data.bankBalanceLabel(bankAccountId), bankBalance),
      ('Needs Review', '$reviewCount Item${reviewCount == 1 ? '' : 's'}'),
    ])
      accountingMetricIconExtent +
          12 +
          [
            AccountingResponsive.measuredTextWidth(context, label, labelStyle),
            AccountingResponsive.measuredTextWidth(context, value, valueStyle),
          ].reduce((a, b) => a > b ? a : b) +
          (label == data.bankBalanceLabel(bankAccountId) &&
                  data.bankAccounts.isNotEmpty
              ? 40
              : 0),
  ];
}

double homeKpiCombinedMinWidth(
  BuildContext context,
  AccountingHomeData data,
  int reviewCount, {
  bool month = true,
  String? bankAccountId,
}) {
  final widths = homeKpiMetricWidths(
    context,
    data,
    reviewCount,
    month: month,
    bankAccountId: bankAccountId,
  );
  final metricMinWidth =
      widths.reduce((a, b) => a + b) +
      (AccountingResponsive.groupGap * 2 + 1) * 2 +
      accountingContentInset * 2 +
      (data.bankAccounts.isEmpty ? 0 : accountingContentInset - 8);
  // Split the top summary before the reminder grid would leave three columns.
  // Both measurements follow real text widths, including larger totals.
  return math.max(metricMinWidth, reminderThreeColumnMinWidth(context));
}

class _HomeKpiStrip extends StatelessWidget {
  const _HomeKpiStrip({
    required this.data,
    required this.reviewCount,
    required this.month,
    required this.bankAccountId,
    required this.onBankAccountSelected,
    this.onNeedsReview,
  });
  final AccountingHomeData data;
  final int reviewCount;
  final bool month;
  final String? bankAccountId;
  final ValueChanged<String?> onBankAccountSelected;
  final VoidCallback? onNeedsReview;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final total = formatAccountingMoney(
      context,
      month ? data.salesThisMonth : data.salesThisYear,
    );
    final bankBalance = formatAccountingMoney(
      context,
      data.bankBalanceFor(bankAccountId),
    );
    final valueFontSize = homeKpiValueFontSize(
      data,
      month: month,
      bankAccountId: bankAccountId,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = [
          metric(
            context,
            Icons.payments_outlined,
            month ? 'This Month' : 'This Year',
            total,
            valueFontSize: valueFontSize,
          ),
          metric(
            context,
            Icons.account_balance_outlined,
            data.bankBalanceLabel(bankAccountId),
            bankBalance,
            valueFontSize: valueFontSize,
            trailing: data.bankAccounts.isEmpty
                ? null
                : _BankBalanceMenu(
                    data: data,
                    selectedId: bankAccountId,
                    onSelected: onBankAccountSelected,
                  ),
          ),
          metric(
            context,
            Icons.fact_check_outlined,
            'Needs Review',
            '$reviewCount Item${reviewCount == 1 ? '' : 's'}',
            valueFontSize: valueFontSize,
            onPressed: onNeedsReview,
          ),
        ];
        final widths = homeKpiMetricWidths(
          context,
          data,
          reviewCount,
          month: month,
          bankAccountId: bankAccountId,
        );
        final minimumWidth = homeKpiCombinedMinWidth(
          context,
          data,
          reviewCount,
          month: month,
          bankAccountId: bankAccountId,
        );
        if (constraints.maxWidth < minimumWidth) {
          // Bank Balance leads the reminder grid in compact layouts, leaving
          // the sales total and review count as the two top summary cards.
          final compactMetricIndexes = [0, 2];
          final columns = AccountingResponsive.balancedColumnCount(
            constraints.maxWidth,
            compactMetricIndexes.length,
            minItemWidth:
                compactMetricIndexes
                    .map((index) => widths[index])
                    .reduce((a, b) => a > b ? a : b) +
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
              for (final index in compactMetricIndexes)
                SizedBox(
                  width: cardWidth,
                  child: AccountingCard.surface(
                    context,
                    key: ValueKey<String>('home-kpi-card-$index'),
                    child: Padding(
                      padding: accountingContentPadding,
                      child: metrics[index],
                    ),
                  ),
                ),
            ],
          );
        }
        // Distribute spare space equally, not in proportion to text width.
        // The divider/card's existing end inset is part of the visible gap.
        // The bank trigger has only an 8px inner gap, so compensate for that
        // instead of adding another full content inset before it.
        final bankGapAdjustment = data.bankAccounts.isEmpty
            ? 0.0
            : accountingContentInset - 8;
        final sparePerMetric =
            (constraints.maxWidth -
                accountingContentInset * 2 -
                (AccountingResponsive.groupGap * 2 + 1) * 2 -
                widths.reduce((a, b) => a + b) -
                bankGapAdjustment) /
            3;
        return AccountingCard.surface(
          context,
          key: const ValueKey('home-kpi-strip'),
          child: Padding(
            padding: accountingContentPadding,
            child: Row(
              children: [
                SizedBox(width: widths[0] + sparePerMetric, child: metrics[0]),
                _divider(tokens),
                SizedBox(
                  width: widths[1] + sparePerMetric + bankGapAdjustment,
                  child: metrics[1],
                ),
                _divider(tokens),
                SizedBox(width: widths[2] + sparePerMetric, child: metrics[2]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _divider(AccountingTokens tokens) => Container(
    width: 1,
    height: accountingMetricIconExtent,
    margin: const EdgeInsets.symmetric(
      horizontal: AccountingResponsive.groupGap,
    ),
    color: tokens.border,
  );

  static Widget metric(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    required double valueFontSize,
    Widget? trailing,
    VoidCallback? onPressed,
  }) {
    final tokens = AccountingTheme.of(context);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    return Row(
      key: ValueKey<String>('home-kpi-$label'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountingMetricIconBox(
          icon,
          iconSize: switch (icon) {
            Icons.payments_outlined => 23,
            Icons.account_balance_outlined || Icons.link_off_outlined => 19,
            _ => 21,
          },
          onPressed: onPressed,
          tooltip: 'Open $label',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: AccountingMetricTextGroup(
              label: Text(
                label,
                maxLines: enlargedText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.mutedForeground, height: 1),
              ),
              value: Text(
                value,
                maxLines: enlargedText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontSize: valueFontSize, height: 1),
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }
}

class _BankBalanceMenu extends StatelessWidget {
  const _BankBalanceMenu({
    required this.data,
    required this.selectedId,
    required this.onSelected,
  });

  final AccountingHomeData data;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => AccountingCompactChoiceMenu<String>(
    triggerKey: const ValueKey('home-bank-switcher'),
    tooltip: 'Select bank account',
    value: selectedId ?? 'all',
    options: [
      AccountingSelectorOption(
        value: 'all',
        label: data.bankBalanceLabel(null),
        key: const ValueKey('home-bank-option-all'),
      ),
      for (final account in data.bankAccounts)
        AccountingSelectorOption(
          value: account.id,
          label: data.bankBalanceLabel(account.id),
          key: ValueKey('home-bank-option-${account.id}'),
          preserveLabelCase: true,
        ),
    ],
    onChanged: (id) => onSelected(id == 'all' ? null : id),
  );
}

class _HomeChartSelection {
  const _HomeChartSelection({
    this.month = true,
    this.barChart = false,
    this.grouping = 'Category',
    this.receivedSales = false,
    this.allCosts = true,
    this.trendPeriod = SalesTrendPeriod.monthly,
  });
  final bool month;
  final bool barChart;
  final String grouping;
  final bool receivedSales;
  final bool allCosts;
  final SalesTrendPeriod trendPeriod;

  _HomeChartSelection copyWith({
    bool? month,
    bool? barChart,
    String? grouping,
    bool? receivedSales,
    bool? allCosts,
    SalesTrendPeriod? trendPeriod,
  }) => _HomeChartSelection(
    month: month ?? this.month,
    barChart: barChart ?? this.barChart,
    grouping: grouping ?? this.grouping,
    receivedSales: receivedSales ?? this.receivedSales,
    allCosts: allCosts ?? this.allCosts,
    trendPeriod: trendPeriod ?? this.trendPeriod,
  );
}

class _ChartCycleButton extends StatelessWidget {
  const _ChartCycleButton({
    required this.buttonKey,
    required this.icon,
    required this.next,
    required this.onPressed,
    this.asset,
  });
  final Key buttonKey;
  final IconData icon;
  final String next;
  final VoidCallback onPressed;
  final String? asset;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Switch to $next',
    child: SizedBox.square(
      dimension: accountingSmallControlHeight,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AccountingTheme.of(context).foreground,
          backgroundColor: AccountingTheme.of(context).card,
          side: BorderSide(color: AccountingTheme.of(context).input),
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(accountingSmallControlHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(accountingSmallIconRadius),
          ),
        ),
        child: Builder(
          builder: (iconContext) => asset == null
              ? AccountingIcon.smallAction(
                  icon,
                  color: IconTheme.of(iconContext).color,
                )
              : SizedBox.square(
                  dimension: AccountingIcon.smallCanvasSizeForAsset(asset!),
                  child: SvgPicture.asset(
                    'assets/icons/small/$asset',
                    colorFilter: ColorFilter.mode(
                      IconTheme.of(iconContext).color ??
                          AccountingTheme.of(iconContext).foreground,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}

class _ExpenseOverview extends StatelessWidget {
  const _ExpenseOverview({
    required this.data,
    required this.selection,
    required this.onSelect,
  });
  final AccountingHomeData data;
  final _HomeChartSelection selection;
  final ValueChanged<_HomeChartSelection> onSelect;

  double _fourBarCardHeight(BuildContext context) {
    double lineHeight(TextStyle? style, {TextHeightBehavior? behavior}) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: behavior,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return accountingContentInset * 3 +
        lineHeight(AccountingTypography.sectionTitle(context)) +
        AccountingResponsive.titleSubtitleGap +
        lineHeight(
          AccountingTypography.helper(context)
              .copyWith(height: 17 / accountingSmallControlFontSize),
          behavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ) +
        4 *
            (lineHeight(Theme.of(context).textTheme.bodyMedium) +
                AccountingProgressBar.labelGap +
                8) +
        3 * AccountingProgressBar.rowGap;
  }

  @override
  Widget build(BuildContext context) {
    final amounts = data.expenseAccounts(
      month: selection.month,
      grouping: selection.grouping,
    );
    final expenseTotal = amounts.values.fold(
      Money.zero(data.currencyCode),
      (total, amount) => total + amount,
    );
    final expense = ExpensePieChart(
      barChart: selection.barChart,
      grouping: selection.grouping,
      amounts: amounts,
      total: expenseTotal,
      periodControl: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartCycleButton(
            buttonKey: const ValueKey('expense-cycle-chart'),
            icon: selection.barChart
                ? Icons.stacked_bar_chart_outlined
                : Icons.pie_chart_outline,
            next: selection.barChart ? 'Pie Chart' : 'Bar Chart',
            onPressed: () =>
                onSelect(selection.copyWith(barChart: !selection.barChart)),
          ),
          const SizedBox(width: accountingRecordIconGap),
          _ChartCycleButton(
            buttonKey: const ValueKey('expense-cycle-grouping'),
            icon: switch (selection.grouping) {
              'Category' => Icons.category_outlined,
              'Payee' => Icons.person_outline,
              _ => Icons.list_alt_outlined,
            },
            asset: selection.grouping == 'Account'
                ? '075-account-grouping.svg'
                : null,
            next: switch (selection.grouping) {
              'Category' => 'Payee',
              'Payee' => 'Account',
              _ => 'Category',
            },
            onPressed: () => onSelect(
              selection.copyWith(
                grouping: switch (selection.grouping) {
                  'Category' => 'Payee',
                  'Payee' => 'Account',
                  _ => 'Category',
                },
              ),
            ),
          ),
          const SizedBox(width: accountingRecordIconGap),
          _ChartCycleButton(
            buttonKey: const ValueKey('expense-cycle-period'),
            icon: Icons.calendar_today_outlined,
            asset: selection.month
                ? '067-month-clock.svg'
                : '074-year-calendar.svg',
            next: selection.month ? 'This Year' : 'This Month',
            onPressed: () =>
                onSelect(selection.copyWith(month: !selection.month)),
          ),
        ],
      ),
    );
    // Pie height follows the circle/legend clearance. The historical four-bar
    // floor belongs to bars and non-pie states, not empty space below a circle.
    final expenseMinHeight =
        selection.barChart ||
            !expenseTotal.isPositive ||
            amounts.values.any((amount) => amount.isNegative)
        ? _fourBarCardHeight(context)
        : 0.0;
    SalesProfitChart sales({bool fillHeight = false}) => SalesProfitChart(
      fillHeight: fillHeight,
      activities: data.trendActivities,
      currencyCode: data.currencyCode,
      asOf: data.referenceDate,
      receivedSales: selection.receivedSales,
      allCosts: selection.allCosts,
      period: selection.trendPeriod,
      onSalesToggle: () =>
          onSelect(selection.copyWith(receivedSales: !selection.receivedSales)),
      onCostToggle: () =>
          onSelect(selection.copyWith(allCosts: !selection.allCosts)),
      onPeriodCycle: () => onSelect(
        selection.copyWith(
          trendPeriod:
              SalesTrendPeriod.values[(selection.trendPeriod.index + 1) %
                  SalesTrendPeriod.values.length],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: expenseMinHeight),
                child: expense,
              ),
              const SizedBox(height: accountingContentInset),
              sales(),
            ],
          );
        }
        return Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(accountingContentInset),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.top,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: expenseMinHeight),
                    child: expense,
                  ),
                ),
                const SizedBox.shrink(),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.fill,
                  child: sales(fillHeight: true),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

List<double> _recentExpenseTableWidths(
  BuildContext context,
  List<AccountingExpense> expenses,
) {
  final headerStyle = AccountingTypography.tableHeader(context);
  final cellStyle = Theme.of(context).textTheme.bodyMedium;
  double widest(String heading, Iterable<String> values) {
    var width = AccountingResponsive.measuredTextWidth(
      context,
      heading,
      headerStyle,
    );
    for (final value in values) {
      final measured = AccountingResponsive.measuredTextWidth(
        context,
        value,
        cellStyle,
      );
      if (measured > width) width = measured;
    }
    return width;
  }

  return [
    widest(
      'Date',
      expenses.map((e) => formatAccountingDate(context, e.occurredOn)),
    ),
    widest('Payee', expenses.map((e) => e.payee ?? 'No payee')),
    widest('Category/Account', expenses.map((e) => e.category)),
    widest(
      'Amount',
      expenses.map((e) => formatAccountingMoney(context, e.amount)),
    ),
  ];
}

List<double> _recentExpenseThreeColumnWidths(
  BuildContext context,
  List<AccountingExpense> expenses,
) {
  final theme = Theme.of(context).textTheme;
  double widest(Iterable<String> values, TextStyle? style) => values
      .map(
        (value) =>
            AccountingResponsive.measuredTextWidth(context, value, style),
      )
      .reduce((a, b) => a > b ? a : b);
  final date = widest(
    expenses.map((e) => formatAccountingDate(context, e.occurredOn)),
    theme.bodySmall,
  );
  final details = [
    widest(
      expenses.map((e) => e.payee ?? 'No payee'),
      theme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    ),
    widest(expenses.map((e) => e.category), theme.bodyMedium),
  ].reduce((a, b) => a > b ? a : b);
  final amount = widest(
    expenses.map((e) => formatAccountingMoney(context, e.amount)),
    theme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  return [date, details, amount];
}

double _recentExpenseThreeColumnMinWidth(
  BuildContext context,
  List<AccountingExpense> expenses,
) {
  final widths = _recentExpenseThreeColumnWidths(context, expenses);
  return widths.reduce((a, b) => a + b) + AccountingResponsive.groupGap * 2;
}

class _RecentExpensesCard extends StatelessWidget {
  const _RecentExpensesCard({
    required this.data,
    this.onRecordExpense,
    this.onRetry,
  });

  final AccountingHomeData data;
  final VoidCallback? onRecordExpense;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return AccountingCard.surface(
      context,
      key: const ValueKey('recent-expenses-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            key: const ValueKey('recent-expenses-card-header'),
            width: double.infinity,
            padding: accountingContentPadding,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                accountingSectionTitle(context, 'Recent expenses'),
                const SizedBox(height: 6),
                accountingHelperText(
                  context,
                  'Recent recorded expenses. Ledger totals include approved expense entries and adjustments.',
                ),
              ],
            ),
          ),
          Padding(
            key: const ValueKey('recent-expenses-card-content'),
            padding: const EdgeInsets.symmetric(
              horizontal: accountingContentInset,
            ),
            child: _buildState(context),
          ),
        ],
      ),
    );
  }

  Widget _buildState(BuildContext context) {
    switch (data.status) {
      case AccountingHomeStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: accountingContentInset),
          child: _LoadingRecentExpenses(),
        );
      case AccountingHomeStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: accountingContentInset),
          child: _HomeLoadError(onRetry: onRetry),
        );
      case AccountingHomeStatus.ready:
        if (data.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: accountingContentInset,
            ),
            child: _EmptyRecentExpenses(onRecordExpense: onRecordExpense),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final tableWidths = _recentExpenseTableWidths(
              context,
              data.recentExpenses,
            );
            final tableMinWidth =
                tableWidths.reduce((a, b) => a + b) +
                AccountingResponsive.groupGap * 3;
            if (constraints.maxWidth >= tableMinWidth) {
              return _RecentExpensesTable(
                expenses: data.recentExpenses,
                minimumWidths: tableWidths,
              );
            }
            if (constraints.maxWidth >=
                _recentExpenseThreeColumnMinWidth(
                  context,
                  data.recentExpenses,
                )) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: accountingContentInset,
                ),
                child: _RecentExpensesThreeColumn(
                  expenses: data.recentExpenses,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: accountingContentInset,
              ),
              child: _RecentExpensesStack(expenses: data.recentExpenses),
            );
          },
        );
    }
  }
}

class _EmptyRecentExpenses extends StatelessWidget {
  const _EmptyRecentExpenses({this.onRecordExpense});

  final VoidCallback? onRecordExpense;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            Semantics(
              image: true,
              container: true,
              label: 'Receipt',
              child: Icon(
                Icons.receipt_outlined,
                key: const ValueKey('home-empty-expenses-icon'),
                size: 20,
                color: tokens.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No expenses recorded yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.cardForeground,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Record an expense to start building your local accounting history.',
              textAlign: TextAlign.center,
              style: AccountingTypography.helper(context),
            ),
            const SizedBox(height: 12),
            AccountingButton.outline(
              context,
              key: null,
              onPressed: onRecordExpense,
              leadingIcon: Icons.add_rounded,
              child: const Text('Record Expense'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingRecentExpenses extends StatelessWidget {
  const _LoadingRecentExpenses();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('recent-expenses-loading'),
      liveRegion: true,
      label: 'Loading recent expenses',
      child: Column(
        key: const ValueKey('recent-expenses-loading-skeletons'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading expenses…',
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < 3; index++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AccountingSkeleton.build(
                          context,
                          height: 14,
                          width: 96,
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (_, constraints) {
                            final desiredWidth = index == 0 ? 180.0 : 140.0;
                            return AccountingSkeleton.build(
                              context,
                              height: 18,
                              width: desiredWidth > constraints.maxWidth
                                  ? constraints.maxWidth
                                  : desiredWidth,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AccountingSkeleton.build(context, height: 18, width: 96),
                ],
              ),
            ),
            if (index < 2) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AccountingAlert.build(
      context,
      key: const ValueKey('accounting-home-load-error'),
      title: "We couldn't load your expenses.",
      description: 'Try again when the local accounting source is available.',
      destructive: true,
      action: AccountingButton.outline(
        context,
        key: null,
        onPressed: onRetry,
        child: const Text('Retry'),
      ),
    );
  }
}

class _RecentExpensesTable extends StatelessWidget {
  const _RecentExpensesTable({
    required this.expenses,
    required this.minimumWidths,
  });

  final List<AccountingExpense> expenses;
  final List<double> minimumWidths;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final headerStyle = AccountingTypography.tableHeader(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap =
            (constraints.maxWidth - minimumWidths.reduce((a, b) => a + b)) / 3;
        return Semantics(
          container: true,
          label: 'Recent expenses table',
          child: Padding(
            padding: const EdgeInsets.only(
              bottom:
                  accountingContentInset - accountingUndividedRowVerticalInset,
            ),
            child: Table(
              key: const ValueKey('recent-expenses-table'),
              columnWidths: <int, TableColumnWidth>{
                0: FixedColumnWidth(minimumWidths[0] + gap),
                1: FixedColumnWidth(minimumWidths[1] + gap),
                2: FixedColumnWidth(minimumWidths[2] + gap),
                3: FixedColumnWidth(minimumWidths[3]),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: tokens.border)),
                  ),
                  children: <Widget>[
                    _tableCell(
                      'Date',
                      style: headerStyle,
                      rightInset: gap,
                      verticalInset: accountingContentInset,
                    ),
                    _tableCell(
                      'Payee',
                      style: headerStyle,
                      rightInset: gap,
                      verticalInset: accountingContentInset,
                    ),
                    _tableCell(
                      'Category/Account',
                      style: headerStyle,
                      rightInset: gap,
                      verticalInset: accountingContentInset,
                    ),
                    _tableCell(
                      'Amount',
                      style: headerStyle,
                      textAlign: TextAlign.right,
                      rightInset: 0,
                      verticalInset: accountingContentInset,
                    ),
                  ],
                ),
                for (var index = 0; index < expenses.length; index++)
                  TableRow(
                    children: <Widget>[
                      _tableCell(
                        formatAccountingDate(
                          context,
                          expenses[index].occurredOn,
                        ),
                        rightInset: gap,
                        firstDataRow: index == 0,
                      ),
                      _tableCell(
                        expenses[index].payee ?? 'No payee',
                        rightInset: gap,
                        firstDataRow: index == 0,
                      ),
                      _tableCell(
                        expenses[index].category,
                        rightInset: gap,
                        firstDataRow: index == 0,
                      ),
                      _tableCell(
                        formatAccountingMoney(context, expenses[index].amount),
                        textAlign: TextAlign.right,
                        rightInset: 0,
                        firstDataRow: index == 0,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tableCell(
    String text, {
    TextStyle? style,
    TextAlign textAlign = TextAlign.left,
    double rightInset = AccountingResponsive.groupGap,
    double verticalInset = accountingUndividedRowVerticalInset,
    bool firstDataRow = false,
  }) => accountingCompactTableCell(
    text,
    style: style,
    textAlign: textAlign,
    rightInset: rightInset,
    verticalInset: verticalInset,
    firstDataRow: firstDataRow,
  );
}

class _RecentExpensesThreeColumn extends StatelessWidget {
  const _RecentExpensesThreeColumn({required this.expenses});

  final List<AccountingExpense> expenses;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final widths = _recentExpenseThreeColumnWidths(context, expenses);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxWidth - widths.reduce((a, b) => a + b)) / 2;
        return Column(
          key: const ValueKey('recent-expenses-three-column'),
          children: [
            for (var index = 0; index < expenses.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: widths[0],
                      child: Text(
                        formatAccountingDate(
                          context,
                          expenses[index].occurredOn,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: widths[1],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expenses[index].payee ?? 'No payee',
                            style: textTheme.titleMedium?.copyWith(
                              color: tokens.cardForeground,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            expenses[index].category,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: widths[2],
                      child: Text(
                        formatAccountingMoney(context, expenses[index].amount),
                        textAlign: TextAlign.right,
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.cardForeground,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RecentExpensesStack extends StatelessWidget {
  const _RecentExpensesStack({required this.expenses});

  final List<AccountingExpense> expenses;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('recent-expenses-stack'),
      children: <Widget>[
        for (var index = 0; index < expenses.length; index++) ...<Widget>[
          Semantics(
            container: true,
            label: _semanticRowLabel(context, expenses[index]),
            child: _RecentExpenseStackRow(expense: expenses[index]),
          ),
          if (index < expenses.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }

  String _semanticRowLabel(BuildContext context, AccountingExpense expense) {
    return '${formatAccountingDate(context, expense.occurredOn)}, '
        '${expense.payee ?? 'No payee'}, ${expense.category}, '
        '${formatAccountingMoney(context, expense.amount)}';
  }
}

class _RecentExpenseStackRow extends StatelessWidget {
  const _RecentExpenseStackRow({required this.expense});

  final AccountingExpense expense;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatAccountingDate(context, expense.occurredOn),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.mutedForeground),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.payee ?? 'No payee',
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.cardForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  expense.category,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: AccountingResponsive.groupGap),
          Expanded(
            child: Align(
              alignment: Alignment.topRight,
              child: Text(
                formatAccountingMoney(context, expense.amount),
                textAlign: TextAlign.right,
                softWrap: true,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.cardForeground,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
