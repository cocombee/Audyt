import '../features/accounting/presentation/tax_rates_page.dart';
import '../features/accounting/presentation/tax_overview_page.dart';
import '../features/accounting/presentation/reminders_page.dart';
import '../features/accounting/application/workspace_backup.dart';

import 'package:audyt/app/accounting_icons.dart';

import '../features/sales/invoice_credit_page.dart';
import '../features/sales/customer_statement_page.dart';
import '../features/sales/receivable_ageing_page.dart';
import '../features/accounting/presentation/payables_ageing_page.dart';
import '../features/sales/customer_receipts_page.dart';
import '../features/sales/invoice_page.dart';
import '../features/sales/quotation_page.dart';
import '../features/sales/product_catalogue_page.dart';
import '../features/accounting/presentation/customer_page.dart';
import 'sidebar_settings_icon.dart';
import 'company_switcher.dart';
import 'restored_company.dart';
import 'demo_company.dart';
import 'frontend_review.dart';
import '../features/accounting/presentation/audit_log_dialog.dart';
import '../features/accounting/presentation/banking_page.dart';
import '../features/accounting/domain/bank_statement_import.dart';
import '../features/accounting/domain/expense_intake.dart';
import '../features/accounting/domain/payment_account.dart';
import '../features/accounting/domain/journal_entry.dart';
import '../features/accounting/presentation/widgets/accounting_formatters.dart';
import '../features/accounting/presentation/ledger_reports_page.dart';
import '../features/accounting/presentation/expense_intake_page.dart';
import '../features/accounting/presentation/journal_workspace_page.dart';
import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/presentation/chart_of_accounts_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/dates/accounting_date.dart';

import '../features/accounting/presentation/accounting_home_page.dart';
import '../features/accounting/presentation/record_expense_page.dart';
import '../features/accounting/domain/payee.dart';
import '../features/accounting/presentation/widgets/accounting_layout.dart';
import '../features/purchases/domain/claim_store.dart';
import '../features/purchases/domain/claim.dart';
import '../features/purchases/presentation/claims_page.dart';
import '../features/purchases/presentation/vendors_page.dart';
import '../features/purchases/presentation/bills_page.dart';
import '../features/purchases/presentation/pay_bills_page.dart';
import '../features/purchases/domain/payment_voucher_store.dart';
import '../features/purchases/domain/payment_voucher.dart';
import '../features/purchases/presentation/payment_vouchers_page.dart';
import '../core/money/money.dart';
import 'accounting_components.dart';
import 'accounting_color_library.dart';
import 'accounting_global_search.dart';
import 'accounting_theme.dart';
import 'accounting_side_tooltip.dart';
import 'feature_registry.dart';
import 'responsive.dart';
import 'routing.dart';
import 'naming_setup.dart';
import 'local_profile.dart';
import 'user_directory.dart';
import 'users_page.dart';
import 'google_membership_connection.dart';

class AudytApp extends StatelessWidget {
  const AudytApp({
    super.key,
    this.initialPath = '/home',
    this.showInitialSetup = false,
    this.accountCurrencyCode = 'MYR',
    this.paymentAccounts,
    this.homeData,
    this.workspace,
    this.startInDemoCompany = false,
    this.taxWorkflowProposal = true,
    this.userDirectory,
    this.membershipConnection,
  });

  final String initialPath;
  final bool showInitialSetup;
  final String accountCurrencyCode;
  final List<String>? paymentAccounts;
  final AccountingHomeData? homeData;
  final AccountingWorkspace? workspace;
  final bool startInDemoCompany;

  /// Isolated review activation; ordinary app entry points retain current UI.
  final bool taxWorkflowProposal;
  final UserDirectory? userDirectory;

  /// Caller owns this business-bound connection and disposes it with workspace.
  final GoogleMembershipConnection? membershipConnection;

  @override
  Widget build(BuildContext context) {
    final route = AccountingRouting.resolve(initialPath);

    Widget shell(UserDirectory? directory) => AccountingShell(
      key: ObjectKey(workspace),
      initialRoute: route!,
      taxWorkflowProposal: taxWorkflowProposal,
      showInitialSetup: showInitialSetup,
      accountCurrencyCode: accountCurrencyCode,
      paymentAccounts: paymentAccounts,
      homeData: homeData,
      workspace: workspace,
      userDirectory: directory,
      submitRegistration:
          membershipConnection == null ||
              (membershipConnection!.approvalStatus != null &&
                  !membershipConnection!.hasUnconfirmedRegistration)
          ? null
          : (profile) => membershipConnection!.submitProfile(
              googleSubject: profile.googleSubject,
              name: profile.name,
              email: profile.email,
              requestedRole: profile.role.toLowerCase(),
            ),
      approvalStatus: membershipConnection?.approvalStatus,
    );
    return MaterialApp(
      key: ObjectKey(workspace),
      debugShowCheckedModeBanner: false,
      title: 'Audyt',
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.light,
      home: route == null
          ? const _UnknownRoutePage()
          : _StartupCompanyRoute(
              startInDemoCompany: startInDemoCompany,
              child: membershipConnection == null
                  ? shell(userDirectory)
                  : ListenableBuilder(
                      listenable: membershipConnection!,
                      builder: (context, _) =>
                          shell(membershipConnection!.directory),
                    ),
            ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    return brightness == Brightness.light
        ? AccountingTheme.light()
        : AccountingTheme.dark();
  }
}

/// The live workspace stays underneath the temporary demo route so the
/// company selector can return to saved records without replacing their DB.
class _StartupCompanyRoute extends StatefulWidget {
  const _StartupCompanyRoute({
    required this.startInDemoCompany,
    required this.child,
  });
  final bool startInDemoCompany;
  final Widget child;

  @override
  State<_StartupCompanyRoute> createState() => _StartupCompanyRouteState();
}

class _StartupCompanyRouteState extends State<_StartupCompanyRoute> {
  @override
  void initState() {
    super.initState();
    if (widget.startInDemoCompany) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DemoCompanyPage()),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AccountingShell extends StatefulWidget {
  const AccountingShell({
    required this.initialRoute,
    this.showInitialSetup = false,
    this.taxWorkflowProposal = true,
    super.key,
    this.accountCurrencyCode = 'MYR',
    this.paymentAccounts,
    this.homeData,
    this.workspace,
    this.userDirectory,
    this.submitRegistration,
    this.approvalStatus,
  });

  final AccountingRoute initialRoute;
  final bool showInitialSetup;
  final bool taxWorkflowProposal;
  final String accountCurrencyCode;
  final List<String>? paymentAccounts;
  final AccountingHomeData? homeData;
  final AccountingWorkspace? workspace;
  final UserDirectory? userDirectory;
  final Future<void> Function(LocalProfile)? submitRegistration;
  final String? approvalStatus;

  @override
  State<AccountingShell> createState() => _AccountingShellState();
}

class _AccountingShellState extends State<AccountingShell> {
  final _previewUsers = PreviewUserDirectory(extraApplicants: 9);
  UserDirectory? get _users =>
      widget.userDirectory ??
      (DemoCompany.active(context) ? _previewUsers : null);
  bool get _canManageUsers => _users?.canManageUsers ?? false;
  void _usersChanged() {
    if (mounted) setState(() {});
  }

  static const _windowLayout = MethodChannel('audyt/window-layout');
  bool _sidebarCollapsed = false;
  bool _sidebarExpansionPending = false;
  bool _compactResizeExpansionStarted = false;
  double _compactResizeDragDistance = 0;
  double? _preferredSidebarWidth;
  bool _settingsHovered = false;
  bool _settingsOpen = false;
  late final ClaimStore _claimStore = widget.workspace == null
      ? ClaimStore.demo()
      : widget.workspace!.claims;
  late final PaymentVoucherStore _paymentVoucherStore = widget.workspace == null
      ? PaymentVoucherStore.demo()
      : widget.workspace!.vouchers;
  late final PayeeStore _payeeStore =
      widget.workspace?.payees ?? PayeeStore(payees: PayeeCatalog.demo);
  late AccountingFeature _currentFeature = widget.initialRoute.feature;
  late AccountingHomeData _homeData =
      widget.homeData ??
      AccountingHomeData.empty(currencyCode: widget.accountCurrencyCode);
  List<AccountingSearchResult> _globalSearchItems = const [];
  Future<List<AccountingSearchResult>>? _globalSearchLoad;
  List<ExpenseIntakeSummary> _pendingExpenses = const [];
  int _pendingExpenseCount = 0;
  int _draftJournalCount = 0;
  String? _globalSearchTab;
  String? _billSearchSelection;
  bool _journalInitialPosted = false;
  DateTime? _journalSummaryThrough;
  int _searchLoadGeneration = 0;
  int _notificationLoadGeneration = 0;
  int _journalCountGeneration = 0;
  final ValueNotifier<String?> _selectedBankStatementId = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _previewUsers.addListener(_usersChanged);
    widget.userDirectory?.addListener(_usersChanged);
    _restoreSidebarWidth();
    _claimStore.addListener(_refreshNotificationCounts);
    _paymentVoucherStore.addListener(_refreshNotificationCounts);
    widget.workspace?.addListener(_workspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startBackupScheduler(),
    );
    _reloadPendingExpenses();
    _reloadJournalCount();
  }

  @override
  void didUpdateWidget(covariant AccountingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userDirectory != widget.userDirectory) {
      oldWidget.userDirectory?.removeListener(_usersChanged);
      widget.userDirectory?.addListener(_usersChanged);
    }
  }

  Future<void> _restoreSidebarWidth() async {
    try {
      final width = await _windowLayout.invokeMethod<double>(
        'loadSidebarWidth',
      );
      if (mounted && width != null) {
        setState(() {
          _preferredSidebarWidth = width.clamp(
            AccountingResponsive.extendedRailMinWidth,
            AccountingResponsive.extendedRailResizableMaxWidth,
          );
        });
      }
    } on MissingPluginException {
      // The desktop window channel is absent in widget tests and other hosts.
    }
  }

  Future<void> _saveSidebarWidth() async {
    final width = _preferredSidebarWidth;
    if (width == null) return;
    try {
      await _windowLayout.invokeMethod<void>('saveSidebarWidth', {
        'width': width,
      });
    } on MissingPluginException {
      // Other hosts do not persist the native desktop window layout.
    }
  }

  Future<void> _expandSidebar(double windowWidth) async {
    if (_sidebarExpansionPending) return;
    _sidebarExpansionPending = true;
    try {
      final desiredSidebarWidth =
          (_preferredSidebarWidth ?? AccountingResponsive.extendedRailMaxWidth)
              .clamp(
                AccountingResponsive.extendedRailMinWidth,
                AccountingResponsive.extendedRailResizableMaxWidth,
              );
      final minimumWindowWidth =
          desiredSidebarWidth +
          AccountingResponsive.navigationDividerWidth +
          AccountingResponsive.desktopMainContentMinWidth;
      if (windowWidth < minimumWindowWidth) {
        try {
          await _windowLayout.invokeMethod<double>('growToWidth', {
            'width': minimumWindowWidth,
          });
        } on MissingPluginException {
          // Widget tests and other hosts do not own a native window.
        }
      }
      if (!mounted) return;
      setState(() {
        _sidebarCollapsed = false;
      });
    } finally {
      _sidebarExpansionPending = false;
    }
  }

  @override
  void dispose() {
    widget.userDirectory?.removeListener(_usersChanged);
    _previewUsers.dispose();
    _claimStore.removeListener(_refreshNotificationCounts);
    _paymentVoucherStore.removeListener(_refreshNotificationCounts);
    _backupScheduler?.dispose();
    widget.workspace?.removeListener(_workspaceChanged);
    _selectedBankStatementId.dispose();
    _searchLoadGeneration++;
    _notificationLoadGeneration++;
    _journalCountGeneration++;
    if (widget.workspace == null) {
      _claimStore.dispose();
      _paymentVoucherStore.dispose();
    }
    super.dispose();
  }

  void _refreshNotificationCounts() {
    if (mounted) setState(() {});
    _invalidateSearchResults();
  }

  WorkspaceBackup? _backupScheduler;
  void _startBackupScheduler() {
    if (!mounted || widget.workspace == null || DemoCompany.active(context)) {
      return;
    }
    _backupScheduler = WorkspaceBackup(widget.workspace!)..start();
  }

  void _workspaceChanged() {
    if (mounted) setState(() {});
    _invalidateSearchResults();
    _reloadPendingExpenses();
    _reloadJournalCount();
  }

  Future<void> _reloadJournalCount() async {
    final workspace = widget.workspace;
    if (workspace == null) return;
    final generation = ++_journalCountGeneration;
    try {
      final page = workspace.database.readJournalPage(
        businessId: workspace.identity.businessId,
        state: JournalEntryState.draft,
        limit: 1,
      );
      if (mounted && generation == _journalCountGeneration) {
        setState(() => _draftJournalCount = page.total);
      }
    } catch (_) {
      // Keep the previous count until the workspace can be read again.
    }
  }

  Future<void> _reloadPendingExpenses() async {
    final workspace = widget.workspace;
    if (workspace == null) return;
    final generation = ++_notificationLoadGeneration;
    try {
      final pending = workspace.database.readPendingExpenseIntakes(
        businessId: workspace.identity.businessId,
      );
      if (mounted && generation == _notificationLoadGeneration) {
        setState(() {
          _pendingExpenses = pending.recent;
          _pendingExpenseCount = pending.count;
        });
      }
    } catch (_) {
      // Preserve the last usable notification list during a transient read error.
    }
  }

  void _invalidateSearchResults() {
    _searchLoadGeneration++;
    _globalSearchItems = const [];
    _globalSearchLoad = null;
  }

  Future<Iterable<AccountingSearchResult>> _searchResults(String query) async {
    if (query.trim().isEmpty) return const <AccountingSearchResult>[];
    final generation = _searchLoadGeneration;
    try {
      final items = _globalSearchItems.isNotEmpty
          ? _globalSearchItems
          : await (_globalSearchLoad ??= loadNonJournalSearchResults(
              claims: _claimStore,
              vouchers: _paymentVoucherStore,
              workspace: widget.workspace,
              includeExpenses: false,
            ));
      if (!mounted || generation != _searchLoadGeneration) {
        return const <AccountingSearchResult>[];
      }
      _globalSearchItems = items;
      const afterJournals = {
        'Account',
        'Payment Account',
        'Bank Statement',
        'Customer Receipt',
      };
      final leading = <AccountingSearchResult>[];
      final afterExpenses = <AccountingSearchResult>[];
      final trailing = <AccountingSearchResult>[];
      var trailingStarted = false;
      for (final item in items) {
        if (afterJournals.contains(item.type)) trailingStarted = true;
        if (!item.matches(query)) continue;
        if (trailingStarted) {
          trailing.add(item);
        } else if (const {
          'Page',
          'Claim',
          'Payment Voucher',
        }.contains(item.type)) {
          leading.add(item);
        } else {
          afterExpenses.add(item);
        }
      }
      final results = leading.take(12).toList();
      if (results.length < 12 && widget.workspace != null) {
        results.addAll(
          searchExpenseResults(
            workspace: widget.workspace!,
            query: query,
            limit: 12 - results.length,
          ),
        );
      }
      if (results.length < 12) {
        results.addAll(afterExpenses.take(12 - results.length));
      }
      if (results.length < 12 && widget.workspace != null) {
        results.addAll(
          searchBillResults(
            workspace: widget.workspace!,
            query: query,
            limit: 12 - results.length,
          ).where((item) => item.matches(query)),
        );
      }
      if (results.length < 12 && widget.workspace != null) {
        results.addAll(
          searchJournalResults(
            workspace: widget.workspace!,
            query: query,
            limit: 12 - results.length,
          ).where((item) => item.matches(query)),
        );
      }
      if (results.length < 12) {
        results.addAll(trailing.take(12 - results.length));
      }
      return results;
    } catch (_) {
      if (generation == _searchLoadGeneration) _globalSearchLoad = null;
      return const <AccountingSearchResult>[];
    }
  }

  Map<String, int> _tabNotificationCountsForArea(String area) {
    if (area == 'users' && _canManageUsers) {
      return {
        'Employees': _users is PagedUserDirectory
            ? (_users as PagedUserDirectory).pendingCount
            : _users!.pendingRegistrations.length,
      };
    }
    if (area == 'banking') {
      return {
        'Bank Activity': widget.workspace?.bankReviewNotificationCount ?? 0,
      };
    }
    if (area != 'expenses-vendors') return const {};
    return {
      'Expenses': _pendingExpenseCount,
      'Claims': _claimStore.all
          .where((claim) => claim.status == ClaimStatus.submitted)
          .length,
      'Payment Vouchers': _paymentVoucherStore.all
          .where(
            (voucher) => {
              PaymentVoucherStatus.pendingApproval,
              PaymentVoucherStatus.onHold,
            }.contains(_paymentVoucherStore.verification(voucher).status),
          )
          .length,
    };
  }

  int _notificationCountForSidebarPage(String id) =>
      _tabNotificationCountsForArea(id).values
          .fold(0, (sum, count) => sum + count);

  List<_TopNotification> _notifications() {
    final items = <_TopNotification>[
      if (_canManageUsers &&
          _users is PagedUserDirectory &&
          (_users as PagedUserDirectory).pendingCount > 0)
        _TopNotification(
          id: 'registrations-pending-${(_users as PagedUserDirectory).pendingCount}',
          title: 'Employee Registrations',
          detail:
              '${(_users as PagedUserDirectory).pendingCount} awaiting Director approval',
          date: DateTime.now(),
          icon: Icons.person_outline,
          featureId: 'users',
          count: (_users as PagedUserDirectory).pendingCount,
          showDate: false,
        ),
      if (_canManageUsers && _users is! PagedUserDirectory)
        for (final user in _users!.pendingRegistrations)
          _TopNotification(
            id: 'registration-${user.id}',
            title: user.name,
            detail: _users!.isPreview
                ? 'Demo registration awaiting approval'
                : 'New registration awaiting approval',
            date: user.submittedAt,
            icon: Icons.person_outline,
            featureId: 'users',
          ),
      for (final expense in _pendingExpenses)
        _TopNotification(
          id: 'expense-${expense.id.value}',
          title: expense.payee.isEmpty ? 'Expense' : expense.payee,
          detail: 'Expense needs review',
          date: expense.createdAt,
          icon: Icons.receipt_long_outlined,
          featureId: 'expenses-vendors',
        ),
      if (_pendingExpenseCount > _pendingExpenses.length)
        _TopNotification(
          id: 'expense-remaining-${_pendingExpenseCount - _pendingExpenses.length}',
          title: 'More Expenses',
          detail:
              '${_pendingExpenseCount - _pendingExpenses.length} more need review in Expenses',
          date: DateTime.fromMillisecondsSinceEpoch(0),
          icon: Icons.receipt_long_outlined,
          featureId: 'expenses-vendors',
          count: _pendingExpenseCount - _pendingExpenses.length,
          showDate: false,
        ),
      for (final claim in _claimStore.all.where(
        (claim) => claim.status == ClaimStatus.submitted,
      ))
        _TopNotification(
          id: 'claim-${claim.id.value}',
          title: claim.vendorName,
          detail: 'Claim needs review',
          date: claim.incurredOn ?? DateTime.fromMillisecondsSinceEpoch(0),
          icon: Icons.shopping_bag_outlined,
          featureId: 'claims',
        ),
      for (final voucher in _paymentVoucherStore.all.where(
        (voucher) => {
          PaymentVoucherStatus.pendingApproval,
          PaymentVoucherStatus.onHold,
        }.contains(_paymentVoucherStore.verification(voucher).status),
      ))
        _TopNotification(
          id: 'voucher-${voucher.id}',
          title: voucher.payee,
          detail:
              _paymentVoucherStore.verification(voucher).status ==
                  PaymentVoucherStatus.pendingApproval
              ? 'Voucher pending approval'
              : 'Voucher payment needs review',
          date: voucher.paymentDate,
          icon: Icons.assignment_turned_in_outlined,
          featureId: 'payment-vouchers',
        ),
    ];
    final workspace = widget.workspace;
    if (workspace != null) {
      final bank = workspace.bankReviewSnapshot;
      for (final notice in bank.recent) {
        items.add(
          _TopNotification(
            id: notice.id,
            title: notice.title,
            detail: notice.isStatement
                ? 'Statement awaiting approval'
                : 'Bank movement needs review',
            date: notice.date,
            icon: Icons.account_balance_outlined,
            featureId: 'banking',
          ),
        );
      }
      if (bank.total > bank.recent.length) {
        final remaining = bank.total - bank.recent.length;
        items.add(
          _TopNotification(
            id: 'bank-remaining-$remaining',
            title: 'More Bank Activity',
            detail: '$remaining more need review in Banking',
            date: DateTime.fromMillisecondsSinceEpoch(0),
            icon: Icons.account_balance_outlined,
            featureId: 'banking',
            count: remaining,
            showDate: false,
          ),
        );
      }
    }
    items.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return items;
  }

  int get _localReviewCount =>
      _claimStore.all
          .where(
            (claim) => switch (claim.status) {
              ClaimStatus.draft ||
              ClaimStatus.submitted ||
              ClaimStatus.returned => true,
              _ => false,
            },
          )
          .length +
      _paymentVoucherStore.all
          .where(
            (voucher) =>
                switch (_paymentVoucherStore.verification(voucher).status) {
                  PaymentVoucherStatus.draft ||
                  PaymentVoucherStatus.pendingApproval ||
                  PaymentVoucherStatus.onHold => true,
                  _ => false,
                },
          )
          .length;

  bool _openingSetup = false;
  Future<bool> _ensureSetup(SetupKind kind) async {
    // Demo Company is an isolated in-memory preview. Its entry forms should
    // never depend on the real company's saved folder permissions.
    if (!widget.showInitialSetup || DemoCompany.active(context)) return true;
    if (_openingSetup) return false;
    _openingSetup = true;
    try {
      return await openNamingSetup(context, kind: kind, onlyIfMissing: true);
    } finally {
      _openingSetup = false;
    }
  }

  void _selectFeature(AccountingFeature feature) async {
    if (feature.id == 'users' && !_canManageUsers) return;
    if (feature.id == _currentFeature.id && _globalSearchTab == null) return;
    if (feature.id == 'record-expense') {
      await _openRecordExpense();
      return;
    }
    if (mounted) {
      setState(() {
        _currentFeature = feature;
        _globalSearchTab = null;
        _billSearchSelection = null;
        _journalInitialPosted = false;
        _journalSummaryThrough = null;
      });
    }
  }

  void _openReviewQueue() {
    final feature = FeatureRegistry.byId('accounting');
    if (feature == null) return;
    setState(() {
      _currentFeature = feature;
      _globalSearchTab = 'Accounting Review Queue';
      _billSearchSelection = null;
      _journalInitialPosted = false;
      _journalSummaryThrough = null;
    });
  }

  void _openReviewDestination(
    String id, {
    String? tab,
    bool journalPosted = false,
    DateTime? journalThrough,
  }) {
    final feature = FeatureRegistry.byId(id);
    if (feature == null) return;
    setState(() {
      _currentFeature = feature;
      _globalSearchTab = tab;
      _billSearchSelection = null;
      _journalInitialPosted = journalPosted;
      _journalSummaryThrough = journalThrough;
    });
  }

  void _handleGlobalSearchSelection(AccountingSearchResult result) {
    final feature = FeatureRegistry.byId(result.featureId);
    if (feature == null) return;
    if (feature.id == 'record-expense') {
      _selectFeature(feature);
      return;
    }
    setState(() {
      _currentFeature = feature;
      _globalSearchTab = result.tab;
      _billSearchSelection = result.tab == 'Bills' ? result.title : null;
      _journalInitialPosted = false;
      _journalSummaryThrough = null;
    });
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    setState(() => _settingsOpen = true);
    try {
      await openAccountingSettings(
        context,
        workspace: widget.workspace,
        onOpenRestored: (path) async {
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => RestoredCompanyPage(path: path)),
          );
        },
        onManageUsers: _canManageUsers
            ? () => _selectFeature(FeatureRegistry.byId('users')!)
            : null,
        loadAccountNames: widget.workspace == null
            ? null
            : () async => (await widget.workspace!.accounts())
                  .map(
                    (entry) => '${entry.account.code} · ${entry.account.name}',
                  )
                  .toList(),
        onAuditLog: widget.workspace == null
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => AuditLogDialog(workspace: widget.workspace!),
              ),
      );
    } finally {
      if (mounted) setState(() => _settingsOpen = false);
    }
  }

  Widget _settingsFooter({required bool compact}) {
    final tokens = AccountingTheme.of(context);
    final highlighted = _settingsHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _settingsHovered = true),
      onExit: (_) => setState(() => _settingsHovered = false),
      child: DecoratedBox(
        key: const ValueKey('accounting-settings-footer'),
        decoration: BoxDecoration(
          color: tokens.sidebar,
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: accountingControlHeight + 16,
            child: compact
                ? Center(
                    child: SizedBox.square(
                      dimension: accountingControlHeight,
                      child: IconButton(
                        key: const ValueKey('accounting-settings'),
                        onPressed: _openSettings,
                        tooltip: 'Settings',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: accountingControlHeight,
                          height: accountingControlHeight,
                        ),
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        icon: _settingsIconBox(
                          tokens,
                          highlighted,
                          compact: true,
                        ),
                      ),
                    ),
                  )
                : TextButton(
                    key: const ValueKey('accounting-settings'),
                    onPressed: _openSettings,
                    style: TextButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Colors.transparent,
                      foregroundColor: highlighted
                          ? tokens.foreground
                          : tokens.mutedForeground,
                      overlayColor: Colors.transparent,
                      side: BorderSide.none,
                      shape: const RoundedRectangleBorder(),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.fromLTRB(32, 0, 24, 0),
                    ),
                    child: Row(
                      children: [
                        _settingsIconBox(tokens, highlighted, compact: false),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            'Settings',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: highlighted
                                      ? tokens.foreground
                                      : tokens.mutedForeground,
                                  fontSize: accountingControlFontSize,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _settingsIconBox(
    AccountingTokens tokens,
    bool highlighted, {
    required bool compact,
  }) => AccountingSettingsIconBox(
    surfaceKey: const ValueKey('accounting-settings-icon-box'),
    highlighted: highlighted,
  );

  Widget _pageWithSettings({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _currentPage(compact: compact)),
        _settingsFooter(compact: false),
      ],
    );
  }

  Future<void> _openRecordExpense({
    BankStatementRow? statementRow,
    PaymentAccount? statementAccount,
    DateTime? reconciliationDate,
    bool stayOnCurrentPage = false,
  }) async {
    if (!await _ensureSetup(SetupKind.expense) || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RecordExpensePage(
        employeePayeeSearch: _users?.findEmployeePayees,
        preferences: widget.workspace?.preferences,
        settingsWorkspace: widget.workspace,
        initialStatementDraft: statementAccount == null
            ? null
            : statementRow == null
            ? RecordExpenseDraft(
                amount: '',
                date: formatAccountingInputDate(
                  reconciliationDate ?? DateTime.now(),
                ),
                payee: '',
                paymentAccount: statementAccount.name,
                paymentAccountId: statementAccount.id,
                category: '',
                tax: '0',
                customer: '',
                billable: false,
                dimensions: '',
                itemOrSplitDetails: '',
                notes: '',
                currencyCode: statementAccount.currency.code,
                taxMode: 'Exclusive',
              )
            : RecordExpenseDraft(
                amount: formatAccountingInputAmount(
                  Money.fromMinor(
                    statementRow.amount.minorUnits.abs(),
                    statementRow.amount.currency,
                  ),
                ),
                date: formatAccountingInputDate(statementRow.date),
                payee: '',
                paymentAccount: statementAccount.name,
                paymentAccountId: statementAccount.id,
                category: '',
                tax: '',
                customer: '',
                billable: false,
                dimensions: '',
                itemOrSplitDetails: '',
                notes:
                    'Bank statement: ${statementRow.description}${statementRow.reference.isEmpty ? '' : ' · ${statementRow.reference}'}',
                currencyCode: statementRow.amount.currency,
              ),
        currencyCode:
            statementAccount?.currency.code ?? widget.accountCurrencyCode,
        paymentAccounts: widget.paymentAccounts,
        accounts: widget.workspace?.paymentAccounts,
        onPaymentAccountSave: widget.workspace?.savePaymentAccount,
        payeeStore: _payeeStore,
        includeTopSafeArea: false,
        onSave: _saveExpense,
        onSaved: () {
          Navigator.pop(dialogContext);
          if (!stayOnCurrentPage) _expenseSaved();
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }

  Future<void> _openReceiptFromStatement(
    BankStatementRow? row,
    PaymentAccount account, {
    DateTime? reconciliationDate,
  }) async {
    final workspace = widget.workspace;
    if (workspace == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CustomerReceiptsPage(
        workspace: workspace,
        statementRow: row,
        statementAccount: account,
        initialDate: reconciliationDate,
        popout: true,
      ),
    );
  }

  Future<void> _openVoucherFromStatement(
    BankStatementRow row,
    PaymentAccount account,
  ) async {
    if (!await _ensureSetup(SetupKind.voucher) || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PaymentVoucherEditorDialog(
        id: 'voucher-${DateTime.now().microsecondsSinceEpoch}',
        sources: _paymentVoucherStore.hasSourceProvider
            ? _paymentVoucherStore.sources
                  .where(
                    (s) =>
                        s.paymentAccountId == account.id &&
                        s.amount ==
                            Money.fromMinor(
                              row.amount.minorUnits.abs(),
                              row.amount.currency,
                            ),
                  )
                  .toList()
            : null,
        accounts: widget.workspace?.paymentAccounts ?? const [],
        payeeStore: _payeeStore,
        defaultCurrencyCode: account.currency.code,
        initialStatementAmount: Money.fromMinor(
          row.amount.minorUnits.abs(),
          row.amount.currency,
        ),
        initialStatementDate: row.date,
        initialStatementReference: row.reference,
        initialStatementAccount: account,
        onPaymentAccountSave: widget.workspace?.savePaymentAccount,
        onSaveDraft: _paymentVoucherStore.save,
        onSubmit: _paymentVoucherStore.saveAndSubmit,
      ),
    );
  }

  Future<void> _openInvoiceFromStatement(
    BankStatementRow row,
    PaymentAccount account,
  ) async {
    final workspace = widget.workspace;
    if (workspace == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 960,
          height: MediaQuery.sizeOf(dialogContext).height - 48,
          child: InvoicePage(workspace: workspace, createDraftOnOpen: true),
        ),
      ),
    );
  }

  void _openHome() {
    final home = FeatureRegistry.byId('home');
    if (home != null) {
      _selectFeature(home);
    }
  }

  Future<void> _saveExpense(RecordExpenseDraft draft) async {
    if (widget.workspace != null) {
      await widget.workspace!.saveExpenseIntake(draft);
      return;
    }
    final amount = Money.fromDecimal(draft.amount, draft.currencyCode);
    final date = parseAccountingInputDate(draft.date);
    if (date == null) {
      throw FormatException('Invalid expense date', draft.date);
    }
    final expense = AccountingExpense(
      occurredOn: date,
      payee: draft.payee.isEmpty ? null : draft.payee,
      category: draft.category,
      amount: amount,
    );
    _homeData = AccountingHomeData.fromExpenses(
      currencyCode: draft.currencyCode,
      expenses: <AccountingExpense>[..._homeData.recentExpenses, expense],
      asOf: _homeData.asOf,
    );
  }

  void _expenseSaved() {
    if (widget.workspace != null) {
      setState(
        () => _currentFeature = FeatureRegistry.byId('expenses-vendors')!,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense saved for accounting review')),
      );
      return;
    }
    setState(() => _currentFeature = FeatureRegistry.byId('home')!);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Expense saved')));
  }

  Widget _reviewQueuePage({required bool compact}) {
    final workspace = widget.workspace!;
    final claimCount = _claimStore.all
        .where(
          (claim) => switch (claim.status) {
            ClaimStatus.draft ||
            ClaimStatus.submitted ||
            ClaimStatus.returned => true,
            _ => false,
          },
        )
        .length;
    final voucherCount = _paymentVoucherStore.all
        .where(
          (voucher) =>
              switch (_paymentVoucherStore.verification(voucher).status) {
                PaymentVoucherStatus.draft ||
                PaymentVoucherStatus.pendingApproval ||
                PaymentVoucherStatus.onHold => true,
                _ => false,
              },
        )
        .length;
    final creditCount = workspace
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
    final entries =
        <
              ({
                String id,
                String title,
                String detail,
                int count,
                String destination,
                String? tab,
              })
            >[
              (
                id: 'expenses',
                title: 'Expenses',
                detail: 'Unposted expense records',
                count: _pendingExpenseCount,
                destination: 'expenses-vendors',
                tab: 'Expenses',
              ),
              (
                id: 'claims',
                title: 'Claims',
                detail: 'Draft, submitted, or returned claims',
                count: claimCount,
                destination: 'claims',
                tab: 'Claims',
              ),
              (
                id: 'vouchers',
                title: 'Payment Vouchers',
                detail: 'Draft, pending, or on-hold vouchers',
                count: voucherCount,
                destination: 'payment-vouchers',
                tab: 'Payment Vouchers',
              ),
              (
                id: 'invoices',
                title: 'Invoice Drafts',
                detail: 'Invoices awaiting completion or posting',
                count: workspace.invoiceDrafts().length,
                destination: 'sales-customers',
                tab: 'Invoices',
              ),
              (
                id: 'credits',
                title: 'Credit Note Drafts',
                detail: 'Credit notes awaiting posting',
                count: creditCount,
                destination: 'sales-customers',
                tab: 'Credit Notes',
              ),
              (
                id: 'journals',
                title: 'Journal Drafts',
                detail: 'Journal entries awaiting approval',
                count: _draftJournalCount,
                destination: 'accountant-review',
                tab: 'Journal Review',
              ),
            ]
            .where((entry) => entry.count > 0)
            .toList();
    return AccountingPageShell(
      includeTopSafeArea: !compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountingPageHeader(
            routeLabel: 'Accounting Review Queue',
            title: 'Needs Review',
            description:
                'Open the records that still need review or completion.',
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          AccountingRecordList(
            paginationKey: 'app-1',
            emptyState: const Padding(
              padding: accountingContentPadding,
              child: Text('No items need review.'),
            ),
            children: [
              for (final entry in entries)
                AccountingRecordRow(
                  key: ValueKey('review-queue-${entry.id}'),
                  title: entry.title,
                  details: Text(
                    entry.detail,
                    style: AccountingTypography.helper(context),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.count}',
                        key: ValueKey('review-queue-count-${entry.id}'),
                        style: AccountingTypography.value(context),
                      ),
                      const SizedBox(width: accountingContentInset),
                      AccountingButton.outline(
                        context,
                        key: ValueKey('open-review-${entry.id}'),
                        onPressed: () => _openReviewDestination(
                          entry.destination,
                          tab: entry.tab,
                        ),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currentPage({required bool compact}) {
    if (_currentFeature.id == 'record-expense') {
      return _currentFunctionalPage(compact: compact);
    }
    final area = FeatureRegistry.sidebarId(_currentFeature.id);
    if (frontendAreas.containsKey(area) || area == 'accounting') {
      const existingLabels = {
        'expenses-vendors': 'Expenses',
        'banking': 'Bank Activity',
        'reports': 'Ledger Reports',
        'accounting': 'Chart Of Accounts',
      };
      final hasExisting =
          widget.workspace != null && existingLabels.containsKey(area);
      final extras = <String, Widget>{
        if ((area == 'contacts-items' || area == 'sales-customers') &&
            widget.workspace != null)
          'Products & Services': ProductCataloguePage(
            workspace: widget.workspace!,
          ),
        if (area == 'expenses-vendors' && widget.workspace != null)
          'Vendors': VendorsPage(workspace: widget.workspace!),
        if (area == 'expenses-vendors' && widget.workspace != null)
          'Bills': BillsPage(
            key: ValueKey('bills-search-${_billSearchSelection ?? ''}'),
            workspace: widget.workspace!,
            initialSearch: _billSearchSelection ?? '',
          ),
        if (area == 'expenses-vendors' && widget.workspace != null)
          'Pay Bills': PayBillsPage(workspace: widget.workspace!),
        if (area == 'taxes' && widget.workspace != null)
          'Tax Codes': TaxRatesPage(
            workspace: widget.workspace!,
            purchaseCostProposal: widget.taxWorkflowProposal,
            taxAgencyProposal: widget.taxWorkflowProposal,
          ),
        if (area == 'taxes' && widget.workspace != null)
          'Tax Overview': TaxOverviewPage(
            workspace: widget.workspace!,
            agencyProposal: widget.taxWorkflowProposal,
            taxPaymentsProposal: widget.taxWorkflowProposal,
          ),
        if (area == 'taxes' && widget.workspace != null)
          'Deadlines': RemindersPage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Credit Notes': InvoiceCreditPage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Customer Statements': CustomerStatementPage(
            workspace: widget.workspace!,
          ),
        if (area == 'reports' && widget.workspace != null)
          'Receivables Ageing': ReceivableAgeingPage(
            workspace: widget.workspace!,
          ),
        if (area == 'reports' && widget.workspace != null)
          'Payables Ageing': PayablesAgeingPage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Invoices': InvoicePage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Quotations': QuotationPage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Receive Payment': CustomerReceiptsPage(workspace: widget.workspace!),
        if (area == 'sales-customers' && widget.workspace != null)
          'Customers': CustomerPage(workspace: widget.workspace!),
        if (area == 'expenses-vendors') ...{
          'Claims': _currentFunctionalPage(
            compact: compact,
            featureId: 'claims',
          ),
          'Payment Vouchers': _currentFunctionalPage(
            compact: compact,
            featureId: 'payment-vouchers',
          ),
        },
        if (area == 'accounting' && widget.workspace != null)
          'Journal Review': _currentFunctionalPage(
            compact: compact,
            featureId: 'accountant-review',
          ),
        if (area == 'accounting' && widget.workspace != null)
          'Accounting Review Queue': _reviewQueuePage(compact: compact),
      };
      return FrontendAreaPage(
        key: ValueKey(
          'frontend-area-$area-${_currentFeature.id}-$_globalSearchTab',
        ),
        notificationCounts: _tabNotificationCountsForArea(area),
        workspace: widget.workspace,
        employeePayeeSearch: _users?.findEmployeePayees,
        loadAccountNames: widget.workspace == null
            ? null
            : () async => (await widget.workspace!.accounts())
                  .map(
                    (entry) => '${entry.account.code} · ${entry.account.name}',
                  )
                  .toList(),
        area: area,
        title: FeatureRegistry.byId(area)!.label,
        formsOverride: area == 'accounting'
            ? frontendAreas['accountant-review']
            : area == 'sales-customers'
            ? [
                ...frontendAreas[area]!.where(
                  (form) =>
                      widget.workspace == null ||
                      !['Customers', 'Invoices'].contains(form.title),
                ),
                frontendAreas['contacts-items']!.last,
              ]
            : null,
        existing: hasExisting
            ? _currentFunctionalPage(compact: compact, featureId: area)
            : null,
        existingLabel: hasExisting ? existingLabels[area] : null,
        extraPages: extras,
        initialPage:
            _globalSearchTab ??
            switch (_currentFeature.id) {
              'claims' => 'Claims',
              'payment-vouchers' => 'Payment Vouchers',
              'accountant-review' => 'Journal Review',
              'contacts-items' => 'Products & Services',
              _ => null,
            },
      );
    }
    return _currentFunctionalPage(compact: compact);
  }

  Widget _currentFunctionalPage({required bool compact, String? featureId}) {
    final selectedId = featureId ?? _currentFeature.id;
    if (selectedId == 'users') {
      if (_users == null) {
        return const Center(
          child: Text('Only Directors can manage employees.'),
        );
      }
      return UsersPage(directory: _users!, compact: compact);
    }
    if (selectedId == 'banking' && widget.workspace != null) {
      return BankingPage(
        workspace: widget.workspace!,
        compact: compact,
        selectedStatementId: _selectedBankStatementId,
        onRecordExpense: (row, account) =>
            _openRecordExpense(statementRow: row, statementAccount: account),
        onReceivePayment: _openReceiptFromStatement,
        onPaymentVoucher: _openVoucherFromStatement,
        onCreateInvoice: _openInvoiceFromStatement,
        onReconciliationExpense: (account, date) => _openRecordExpense(
          statementAccount: account,
          reconciliationDate: date,
          stayOnCurrentPage: true,
        ),
        onReconciliationPayment: (account, date) =>
            _openReceiptFromStatement(null, account, reconciliationDate: date),
      );
    }
    if (selectedId == 'reports' && widget.workspace != null) {
      return LedgerReportsPage(
        workspace: widget.workspace!,
        compact: compact,
        selectedStatementId: _selectedBankStatementId,
        reviewCount: _localReviewCount,
        onNeedsReview: _openReviewQueue,
        onPostedJournals: (report) => _openReviewDestination(
          'accountant-review',
          tab: 'Journal Review',
          journalPosted: true,
          journalThrough: report.through,
        ),
        onPendingDrafts: (report) => _openReviewDestination(
          'accountant-review',
          tab: 'Journal Review',
          journalThrough: report.through,
        ),
        onAccounts: () =>
            _openReviewDestination('accounting', tab: 'Chart Of Accounts'),
      );
    }
    if (selectedId == 'expenses-vendors' && widget.workspace != null) {
      return ExpenseIntakePage(
        employeePayeeSearch: _users?.findEmployeePayees,
        workspace: widget.workspace!,
        compact: compact,
        onRecordExpense: _openRecordExpense,
        beforeReviewExpense: () => _ensureSetup(SetupKind.expense),
      );
    }
    if (selectedId == 'accountant-review' && widget.workspace != null) {
      return JournalReviewPage(
        key: ValueKey(
          'journal-summary-$_journalInitialPosted-$_journalSummaryThrough',
        ),
        workspace: widget.workspace!,
        compact: compact,
        initialPosted: _journalInitialPosted,
        through: _journalSummaryThrough,
      );
    }
    if (selectedId == 'accounting' && widget.workspace != null) {
      return ChartOfAccountsPage(
        workspace: widget.workspace!,
        compact: compact,
      );
    }
    if (selectedId == 'home' && widget.workspace != null) {
      return WorkspaceAccountingHome(
        asOf: DemoCompany.referenceDate(context),
        workspace: widget.workspace!,
        includeTopSafeArea: !compact,
        topInset: compact
            ? AccountingResponsive.pageTitleOuterGap
            : AccountingResponsive.pageTitleOuterGap -
                  AccountingResponsive.tabStripTopInset,
        onRecordExpense: _openRecordExpense,
        onNeedsReview: _openReviewQueue,
        reviewCount: _localReviewCount,
      );
    }
    if (selectedId == 'home') {
      return AccountingHomePage(
        data: _homeData,
        includeTopSafeArea: !compact,
        topInset: compact
            ? AccountingResponsive.pageTitleOuterGap
            : AccountingResponsive.pageTitleOuterGap -
                  AccountingResponsive.tabStripTopInset,
        onRecordExpense: _openRecordExpense,
        onNeedsReview: _openReviewQueue,
        reviewCount: _localReviewCount,
        titleKey: 'page-title-home',
      );
    }
    if (selectedId == 'record-expense') {
      return RecordExpensePage(
        employeePayeeSearch: _users?.findEmployeePayees,
        preferences: widget.workspace?.preferences,
        settingsWorkspace: widget.workspace,
        currencyCode: widget.accountCurrencyCode,
        paymentAccounts: widget.paymentAccounts,
        accounts: widget.workspace?.paymentAccounts,
        onPaymentAccountSave: widget.workspace?.savePaymentAccount,
        payeeStore: _payeeStore,
        includeTopSafeArea: !compact,
        onSave: _saveExpense,
        onSaved: _expenseSaved,
        onCancel: _openHome,
      );
    }
    if (selectedId == 'claims') {
      return ClaimsPage(
        receiptTaxProposal: widget.taxWorkflowProposal,
        store: _claimStore,
        workspace: widget.workspace,
        beforeCreate: () => _ensureSetup(SetupKind.claims),
        compact: compact,
        payeeStore: _payeeStore,
        defaultCurrencyCode: widget.accountCurrencyCode,
      );
    }
    if (selectedId == 'payment-vouchers') {
      return PaymentVouchersPage(
        store: _paymentVoucherStore,
        workspace: widget.workspace,
        beforeCreate: () => _ensureSetup(SetupKind.voucher),
        compact: compact,
        defaultCurrencyCode: widget.accountCurrencyCode,
        paymentAccounts: widget.paymentAccounts,
        accounts: widget.workspace?.paymentAccounts,
        loadAccounts: widget.workspace == null
            ? null
            : () => widget.workspace!.paymentAccounts,
        onPaymentAccountSave: widget.workspace?.savePaymentAccount,
        payeeStore: _payeeStore,
      );
    }
    return _FeaturePage(
      feature: FeatureRegistry.byId(selectedId)!,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final sidebarNotificationCounts = {
      for (final group in FeatureRegistry.navigationGroups)
        for (final feature in group.features)
          feature.id: _notificationCountForSidebarPage(feature.id),
    };
    final notifications = _notifications();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every destination shares the same window breakpoint. Selecting a
        // page never changes the sidebar state; its content reflows instead.
        final navigationMode = AccountingResponsive.navigationModeFor(
          constraints.maxWidth,
        );
        final effectiveNavigationMode =
            _sidebarCollapsed ||
                navigationMode == AccountingNavigationMode.compactRail
            ? AccountingNavigationMode.compactRail
            : AccountingNavigationMode.extendedRail;
        const effectiveMainContentMinWidth =
            AccountingResponsive.desktopMainContentMinWidth;
        final navigationWidth = AccountingResponsive.navigationWidthFor(
          constraints.maxWidth,
          effectiveNavigationMode,
          mainContentMinWidth: effectiveMainContentMinWidth,
          preferredWidth: _preferredSidebarWidth,
        );
        final navigation = _NavigationPanel(
          currentFeature: _currentFeature,
          companyName: widget.workspace?.preferences.text(
            'Business Profile',
            'Business Name',
          ),
          canManageUsers: _canManageUsers,
          notificationCounts: sidebarNotificationCounts,
          onSelected: _selectFeature,
          mode: effectiveNavigationMode,
          onToggleSidebar: () async {
            if (effectiveNavigationMode ==
                AccountingNavigationMode.compactRail) {
              await _expandSidebar(constraints.maxWidth);
            } else {
              setState(() {
                _sidebarCollapsed = true;
              });
            }
          },
        );

        if (navigationMode == AccountingNavigationMode.drawer) {
          return Scaffold(
            backgroundColor: tokens.background,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: tokens.background,
              foregroundColor: tokens.foreground,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Open Accounting Navigation',
                ),
              ),
              title: const Text('Audyt'),
            ),
            drawer: Drawer(
              key: const ValueKey('accounting-navigation-drawer'),
              width: AccountingResponsive.drawerWidthFor(constraints.maxWidth),
              backgroundColor: tokens.sidebar,
              child: navigation,
            ),
            body: _pageWithSettings(compact: true),
          );
        }

        return Scaffold(
          backgroundColor: tokens.background,
          body: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    key: ValueKey<String>(
                      effectiveNavigationMode ==
                              AccountingNavigationMode.compactRail
                          ? 'accounting-navigation-compact-rail'
                          : 'accounting-navigation-extended-rail',
                    ),
                    width: navigationWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: navigation),
                        _settingsFooter(
                          compact:
                              effectiveNavigationMode ==
                              AccountingNavigationMode.compactRail,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    key: const ValueKey('accounting-navigation-divider-line'),
                    width: AccountingResponsive.navigationDividerWidth,
                    child: ColoredBox(color: tokens.sidebarBorder),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _GlobalTopBar(
                          isHome: const {
                            'home',
                            'users',
                          }.contains(_currentFeature.id),
                          searchResults: _searchResults,
                          onSearchSelected: _handleGlobalSearchSelection,
                          notifications: notifications,
                          onNotificationSelected: (id) {
                            final feature = FeatureRegistry.byId(id);
                            if (feature != null) _selectFeature(feature);
                          },
                          onOpenSettings: _openSettings,
                          submitRegistration: widget.submitRegistration,
                          approvalStatus: widget.approvalStatus,
                        ),
                        Expanded(child: _currentPage(compact: false)),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left:
                    navigationWidth -
                    (AccountingResponsive.navigationDividerDragWidth -
                            AccountingResponsive.navigationDividerWidth) /
                        2,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    key: const ValueKey('accounting-navigation-resize-border'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) {
                      _compactResizeDragDistance = 0;
                      _compactResizeExpansionStarted = false;
                    },
                    onHorizontalDragUpdate: (details) {
                      if (effectiveNavigationMode ==
                          AccountingNavigationMode.compactRail) {
                        _compactResizeDragDistance += details.delta.dx;
                        if (_compactResizeDragDistance > 0 &&
                            !_compactResizeExpansionStarted) {
                          _compactResizeExpansionStarted = true;
                          _expandSidebar(constraints.maxWidth);
                        }
                        return;
                      }
                      final currentWidth =
                          AccountingResponsive.extendedRailWidthFor(
                            constraints.maxWidth,
                            mainContentMinWidth: effectiveMainContentMinWidth,
                            preferredWidth: _preferredSidebarWidth,
                          );
                      final requestedWidth = currentWidth + details.delta.dx;
                      setState(() {
                        if (requestedWidth <
                            AccountingResponsive.extendedRailMinWidth) {
                          _sidebarCollapsed = true;
                        } else {
                          _preferredSidebarWidth = requestedWidth.clamp(
                            AccountingResponsive.extendedRailMinWidth,
                            AccountingResponsive.extendedRailResizableMaxWidth,
                          );
                        }
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      if (effectiveNavigationMode ==
                          AccountingNavigationMode.extendedRail) {
                        _saveSidebarWidth();
                      }
                      _compactResizeDragDistance = 0;
                      _compactResizeExpansionStarted = false;
                    },
                    child: const SizedBox(
                      width: AccountingResponsive.navigationDividerDragWidth,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopNotification {
  const _TopNotification({
    required this.id,
    required this.title,
    required this.detail,
    required this.date,
    required this.icon,
    required this.featureId,
    this.count = 1,
    this.showDate = true,
  });
  final String id;
  final String title;
  final String detail;
  final DateTime date;
  final IconData icon;
  final String featureId;
  final int count;
  final bool showDate;
}

class _NotificationsMenu extends StatefulWidget {
  const _NotificationsMenu({
    required this.notifications,
    required this.onSelected,
  });
  final List<_TopNotification> notifications;
  final ValueChanged<String> onSelected;

  @override
  State<_NotificationsMenu> createState() => _NotificationsMenuState();
}

class _NotificationsMenuState extends State<_NotificationsMenu> {
  bool _expanded = false;
  final Set<String> _selectedNotificationIds = {};

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final entries = _expanded
        ? widget.notifications
        : widget.notifications.take(3).toList();
    final titleMetrics = TextPainter(
      text: TextSpan(
        text: 'Notifications',
        style: AccountingTypography.sectionTitle(context),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final panelHeight =
        titleMetrics.height +
        22 +
        (entries.isEmpty ? 60 : entries.length * 64) +
        (widget.notifications.length > 3 ? 46 : 0);
    titleMetrics.dispose();
    return AccountingMenuAnchor(
      menuWidth: 360,
      maxHeight: 720,
      gap: 8,
      style: accountingSelectorMenuStyle(context, 360, 720).copyWith(
        alignment: AlignmentDirectional.bottomEnd,
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        side: const WidgetStatePropertyAll(BorderSide.none),
        elevation: const WidgetStatePropertyAll(5),
        shadowColor: const WidgetStatePropertyAll(accountingMenuShadowColor),
      ),
      menuChildren: const [],
      menuChildrenBuilder: (width, height) => [
        SizedBox(
          key: const ValueKey('notification-panel'),
          width: width - 16,
          height: (height - 16).clamp(0.0, panelHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                key: const ValueKey('notifications-fixed-heading'),
                child: Text(
                  'Notifications',
                  style: AccountingTypography.sectionTitle(context),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No notifications',
                    style: AccountingTypography.helper(context),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    key: const ValueKey('notifications-scroll-list'),
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      final date = MaterialLocalizations.of(context)
                          .formatShortDate(item.date);
                      final unread = !_selectedNotificationIds.contains(
                        item.id,
                      );
                      return SizedBox(
                        height: 64,
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                key: ValueKey('notification-${item.id}'),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: unread
                                      ? tokens.primary.withValues(alpha: 0.10)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.zero,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.zero,
                                  onTap: () {
                                    setState(
                                      () =>
                                          _selectedNotificationIds.add(item.id),
                                    );
                                    MenuController.maybeOf(context)?.close();
                                    widget.onSelected(item.featureId);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        AccountingNotificationIcon(
                                          item.icon,
                                          color: tokens.foreground,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    AccountingTypography.control(
                                                      context,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                item.showDate
                                                    ? '${item.detail} · $date'
                                                    : item.detail,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    AccountingTypography.helper(
                                                      context,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (index < entries.length - 1 &&
                                !unread &&
                                _selectedNotificationIds.contains(
                                  entries[index + 1].id,
                                ))
                              Container(
                                key: ValueKey(
                                  'notification-divider-${item.id}',
                                ),
                                height: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                color: tokens.border,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              if (widget.notifications.length > 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                  child: TextButton(
                    key: const ValueKey('notifications-read-more'),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: accountingActionMenuItemStyle(context),
                    child: Text(_expanded ? 'Show less' : 'Read more'),
                  ),
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, child) => Semantics(
        label: 'Notifications',
        button: true,
        child: IconButton(
          key: const ValueKey('global-notifications'),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              setState(() => _expanded = false);
              controller.open();
            }
          },
          style: ButtonStyle(
            shape: const WidgetStatePropertyAll(CircleBorder()),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? tokens.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          icon: SizedBox.square(
            dimension: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: SvgPicture.asset(
                    'assets/icons/013-bell.svg',
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      tokens.foreground,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                if (widget.notifications.isNotEmpty)
                  Positioned(
                    top: -5,
                    left: 22,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: Container(
                        key: const ValueKey('global-notification-badge'),
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AccountingColorLibrary.grapefruitDeep,
                          borderRadius: BorderRadius.circular(
                            accountingControlRadius,
                          ),
                        ),
                        child: Text(
                          accountingNotificationCountLabel(
                            widget.notifications.fold<int>(
                              0,
                              (sum, item) => sum + item.count,
                            ),
                          ),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalTopBar extends StatelessWidget {
  const _GlobalTopBar({
    required this.isHome,
    required this.searchResults,
    required this.onSearchSelected,
    required this.notifications,
    required this.onNotificationSelected,
    required this.onOpenSettings,
    this.submitRegistration,
    this.approvalStatus,
  });
  final bool isHome;
  final Future<Iterable<AccountingSearchResult>> Function(String) searchResults;
  final ValueChanged<AccountingSearchResult> onSearchSelected;
  final List<_TopNotification> notifications;
  final ValueChanged<String> onNotificationSelected;
  final VoidCallback onOpenSettings;
  final Future<void> Function(LocalProfile)? submitRegistration;
  final String? approvalStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final dateLabel = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime.now());
    final dateTextStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: tokens.foreground, fontWeight: FontWeight.w500);
    final date = Container(
      key: const ValueKey('global-date-box'),
      height: accountingControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(accountingControlRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AccountingIcon(
            Icons.calendar_today_outlined,
            size: 17,
            color: tokens.mutedForeground,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dateTextStyle,
            ),
          ),
        ],
      ),
    );
    final search = SizedBox(
      key: const ValueKey('global-search-box'),
      height: accountingControlHeight,
      child: Autocomplete<AccountingSearchResult>(
        displayStringForOption: (result) => result.title,
        onSelected: onSearchSelected,
        optionsBuilder: (value) => searchResults(value.text),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            TextField(
              key: const ValueKey('global-search-field'),
              controller: controller,
              focusNode: focusNode,
              maxLines: 1,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                hintText: 'Search transactions and records',
                hintMaxLines: 1,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(
                    left: accountingContentInset,
                    right: 16,
                  ),
                  child: AccountingIcon(Icons.search_rounded, size: 19),
                ),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 55,
                  height: accountingControlHeight,
                ),
                filled: true,
                fillColor: tokens.card,
                hoverColor: Colors.transparent,
                contentPadding: const EdgeInsets.only(
                  left: accountingContentInset,
                  right: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    accountingControlHeight / 2,
                  ),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    accountingControlHeight / 2,
                  ),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    accountingControlHeight / 2,
                  ),
                  borderSide: BorderSide(
                    color: tokens.primary,
                    width: accountingFocusedBorderWidth,
                  ),
                ),
              ),
            ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: tokens.card,
            surfaceTintColor: tokens.card,
            elevation: 6,
            shadowColor: accountingMenuShadowColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
              side: BorderSide(color: tokens.border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final result = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: result.detail.isEmpty
                        ? null
                        : Text(
                            result.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: Text(
                      result.type,
                      style: AccountingTypography.helper(context),
                    ),
                    onTap: () => onSelected(result),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final notificationButton = _NotificationsMenu(
      notifications: notifications,
      onSelected: onNotificationSelected,
    );
    final profile = LocalProfileMenu(
      submitRegistration: submitRegistration,
      approvalStatus: approvalStatus,
    );
    return AccountingPageAlignment(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the search in the top row until its hint would shorten to
          // "Search transactions..". Let it use the space freed by the icon
          // rail before moving it beneath the date and actions.
          final dateWidth =
              24 +
              17 +
              8 +
              AccountingResponsive.measuredTextWidth(
                context,
                dateLabel,
                dateTextStyle,
              );
          final minimumSearchWidth =
              55 +
              20 +
              AccountingResponsive.measuredTextWidth(
                context,
                'Search transactions..',
                Theme.of(context).inputDecorationTheme.hintStyle ??
                    Theme.of(context).textTheme.bodyMedium,
              );
          final preferredSearchWidth = minimumSearchWidth > 283
              ? minimumSearchWidth
              : 283.0;
          final availableSearchWidth =
              constraints.maxWidth -
              dateWidth -
              AccountingResponsive.groupGap * 2 -
              24 -
              48 -
              36;
          final stacked = availableSearchWidth < minimumSearchWidth;
          final searchWidth = stacked
              ? constraints.maxWidth.clamp(0.0, preferredSearchWidth).toDouble()
              : availableSearchWidth
                    .clamp(minimumSearchWidth, preferredSearchWidth)
                    .toDouble();
          final dateAndActions = Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: date),
              ),
              notificationButton,
              const SizedBox(width: 24),
              profile,
            ],
          );
          return Padding(
            key: const ValueKey('global-top-bar'),
            padding: EdgeInsets.fromLTRB(
              0,
              AccountingResponsive.topBarTopInset,
              0,
              AccountingResponsive.topBarBottomInset +
                  (isHome ? AccountingResponsive.tabStripTopInset : 0),
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dateAndActions,
                      const SizedBox(height: AccountingResponsive.groupGap),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(width: searchWidth, child: search),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: date,
                        ),
                      ),
                      const SizedBox(width: AccountingResponsive.groupGap),
                      SizedBox(width: searchWidth, child: search),
                      const SizedBox(width: AccountingResponsive.groupGap),
                      notificationButton,
                      const SizedBox(width: 24),
                      profile,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.currentFeature,
    required this.companyName,
    required this.canManageUsers,
    required this.notificationCounts,
    required this.onSelected,
    required this.mode,
    required this.onToggleSidebar,
  });

  final AccountingFeature currentFeature;
  final String? companyName;
  final bool canManageUsers;
  final Map<String, int> notificationCounts;
  final ValueChanged<AccountingFeature> onSelected;
  final AccountingNavigationMode mode;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    if (mode == AccountingNavigationMode.compactRail) {
      return _buildCompactRail(context);
    }
    return _buildExtendedNavigation(context);
  }

  void _selectFromNavigation(BuildContext context, AccountingFeature feature) {
    onSelected(feature);
    if (mode == AccountingNavigationMode.drawer) {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildExtendedNavigation(BuildContext context) {
    final tokens = AccountingTheme.of(context);

    return Semantics(
      container: true,
      label: 'Accounting navigation',
      child: Material(
        color: tokens.sidebar,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: <Widget>[
              _buildBrandBlock(context),
              const SizedBox(height: 8),
              CompanySelector(
                key: const ValueKey('company-switcher'),
                companyName: companyName,
              ),
              const SizedBox(height: 22),
              for (final (index, group)
                  in FeatureRegistry.navigationGroups.indexed) ...<Widget>[
                if (index > 0) ...[
                  const SizedBox(height: 12),
                  Transform.translate(
                    offset: const Offset(0, -7.25),
                    child: Divider(
                      key: ValueKey('navigation-divider-${group.id}'),
                      height: 1,
                      thickness: 1,
                      color: tokens.sidebarBorder,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Semantics(
                  container: true,
                  label: group.label,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(0, index == 0 ? 12 : 0, 0, 8),
                    child: Text(
                      group.label,
                      key: ValueKey<String>('navigation-group-${group.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AccountingTypography.helper(context)
                          .copyWith(letterSpacing: 0),
                    ),
                  ),
                ),
                for (final feature in group.features.where(
                  (feature) => feature.id != 'users' || canManageUsers,
                ))
                  _extendedNavigationItem(context, feature),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandBlock(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: 'Audyt',
      child: SizedBox(
        height: 56,
        child: Row(
          key: const ValueKey('accounting-brand'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              key: const ValueKey('accounting-brand-icon-box'),
              width: accountingControlHeight,
              height: accountingControlHeight,
              decoration: BoxDecoration(
                color: tokens.sidebarPrimary,
                borderRadius: BorderRadius.circular(accountingControlRadius),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Audyt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.sidebarForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _navigationToggleButton(
              context,
              key: const ValueKey('collapse-accounting-navigation'),
              label: 'Collapse navigation',
              compact: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigationToggleButton(
    BuildContext context, {
    required Key key,
    required String label,
    required bool compact,
  }) {
    final tokens = AccountingTheme.of(context);
    return AccountingMinorHoverRegion(
      builder: (context, highlighted) => Semantics(
        button: true,
        label: label,
        enabled: true,
        child: InkWell(
          key: key,
          onTap: onToggleSidebar,
          borderRadius: BorderRadius.circular(accountingControlRadius),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: SizedBox.square(
            dimension: accountingControlHeight,
            child: Center(
              child: DecoratedBox(
                key: ValueKey(
                  '${compact ? 'expand' : 'collapse'}-accounting-navigation-highlight',
                ),
                decoration: BoxDecoration(
                  color: highlighted
                      ? accountingNeutralHighlight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(accountingControlRadius),
                ),
                child: SizedBox.square(
                  dimension: accountingSmallControlHeight,
                  child: AccountingIcon(
                    Icons.view_sidebar_outlined,
                    size: 17,
                    color: highlighted
                        ? tokens.foreground
                        : tokens.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _extendedNavigationItem(
    BuildContext context,
    AccountingFeature feature,
  ) {
    final tokens = AccountingTheme.of(context);
    final selected = feature.id == FeatureRegistry.sidebarId(currentFeature.id);
    final notificationCount = notificationCounts[feature.id] ?? 0;
    final item = Material(
      color: tokens.sidebar.withValues(alpha: 0),
      child: InkWell(
        key: ValueKey<String>('navigation-item-${feature.id}'),
        borderRadius: BorderRadius.circular(accountingControlRadius),
        onTap: () => _selectFromNavigation(context, feature),
        child: SizedBox(
          height: accountingControlHeight,
          child: Center(
            child: Container(
              height: accountingControlHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: accountingContentInset,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? tokens.sidebarAccent
                    : tokens.sidebar.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(accountingControlRadius),
              ),
              child: Row(
                children: <Widget>[
                  AccountingIcon(
                    _iconFor(feature.id),
                    size: 20,
                    color: selected
                        ? tokens.sidebarPrimaryForeground
                        : tokens.mutedForeground,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      feature.label,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AccountingTypography.navigation(
                            context,
                            selected: selected,
                          ).copyWith(
                            color: selected
                                ? tokens.sidebarPrimaryForeground
                                : tokens.mutedForeground,
                          ),
                    ),
                  ),
                  if (notificationCount > 0)
                    Container(
                      key: ValueKey<String>('navigation-badge-${feature.id}'),
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? tokens.card : tokens.sidebarPrimary,
                        borderRadius: BorderRadius.circular(
                          accountingControlRadius,
                        ),
                      ),
                      child: Text(
                        accountingNotificationCountLabel(notificationCount),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? tokens.foreground
                              : tokens.primaryForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      label: feature.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: item,
      ),
    );
  }

  Widget _buildCompactRail(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return Semantics(
      container: true,
      label: 'Accounting navigation',
      child: Material(
        color: tokens.sidebar,
        child: SafeArea(
          child: ListView(
            key: const ValueKey('accounting-navigation-compact-list'),
            padding: const EdgeInsets.fromLTRB(0, 32, 0, 16),
            children: <Widget>[
              Semantics(
                header: true,
                label: 'Audyt',
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: CompanySelector(
                      key: const ValueKey('company-switcher'),
                      compact: true,
                      companyName: companyName,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Expand Accounting Navigation',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _navigationToggleButton(
                    context,
                    key: const ValueKey('expand-accounting-navigation'),
                    label: 'Expand Accounting Navigation',
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Transform.translate(
                offset: const Offset(0, 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(
                    key: const ValueKey('navigation-divider-leading'),
                    height: 1,
                    thickness: 1,
                    color: tokens.sidebarBorder,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final (index, group)
                  in FeatureRegistry.navigationGroups.indexed)
                Semantics(
                  container: true,
                  label: group.label,
                  child: Column(
                    children: <Widget>[
                      if (index > 0) ...[
                        Transform.translate(
                          offset: const Offset(0, 2),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Divider(
                              key: ValueKey('navigation-divider-${group.id}'),
                              height: 1,
                              thickness: 1,
                              color: tokens.sidebarBorder,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final feature in group.features.where(
                        (feature) => feature.id != 'users' || canManageUsers,
                      ))
                        _compactNavigationItem(context, feature),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactNavigationItem(
    BuildContext context,
    AccountingFeature feature,
  ) {
    final tokens = AccountingTheme.of(context);
    final selected = feature.id == FeatureRegistry.sidebarId(currentFeature.id);
    return Semantics(
      button: true,
      selected: selected,
      label: feature.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
        child: AccountingSideTooltip(
          message: feature.label,
          child: Material(
            color: tokens.sidebar.withValues(alpha: 0),
            child: InkWell(
              key: ValueKey<String>('navigation-item-${feature.id}'),
              borderRadius: BorderRadius.circular(accountingControlRadius),
              hoverColor: accountingNeutralHighlight,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              onTap: () => onSelected(feature),
              child: SizedBox(
                height: accountingControlHeight,
                child: Center(
                  child: Container(
                    width: accountingControlHeight,
                    height: accountingControlHeight,
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.sidebarPrimary
                          : tokens.sidebar.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(
                        accountingControlRadius,
                      ),
                    ),
                    child: AccountingIcon(
                      _iconFor(feature.id),
                      size: 20,
                      color: selected
                          ? tokens.sidebarPrimaryForeground
                          : tokens.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String featureId) {
    switch (featureId) {
      case 'home':
        return Icons.dashboard_outlined;
      case 'banking':
        return Icons.account_balance_outlined;
      case 'sales-customers':
        return Icons.shopping_bag_outlined;
      case 'expenses-vendors':
        return Icons.receipt_long_outlined;
      case 'claims':
        return Icons.assignment_outlined;
      case 'payment-vouchers':
        return Icons.payments_outlined;
      case 'record-expense':
        return Icons.note_add_outlined;
      case 'accounting':
        return Icons.account_tree_outlined;
      case 'taxes':
        return Icons.percent_outlined;
      case 'reports':
        return Icons.bar_chart_outlined;
      case 'users':
        return Icons.people_outline;
      case 'documents':
        return Icons.description_outlined;
      case 'contacts-items':
        return Icons.contacts_outlined;
      case 'accountant-review':
        return Icons.fact_check_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _FeaturePage extends StatefulWidget {
  const _FeaturePage({required this.feature, this.compact = false});

  final AccountingFeature feature;
  final bool compact;

  @override
  State<_FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<_FeaturePage> {
  int _selected = 0;

  AccountingFeature get feature => widget.feature;
  bool get compact => widget.compact;

  static const _sections = <String, List<String>>{
    'sales-customers': ['Invoices', 'Customers', 'Credit Notes', 'Receipts'],
    'contacts-items': ['Contacts', 'Products & Services'],
    'taxes': ['Tax Overview', 'Tax Codes', 'Returns & Payments', 'Deadlines'],
    'documents': ['For Review', 'Linked Documents', 'Filing History'],
  };

  @override
  void didUpdateWidget(covariant _FeaturePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feature.id != feature.id) _selected = 0;
  }

  @override
  Widget build(BuildContext context) {
    final description =
        _descriptions[feature.id] ?? 'This workflow is not available yet.';

    return AccountingPageShell(
      includeTopSafeArea: !compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AccountingPageHeader(
            routeLabel: _groupLabel(feature.groupId),
            title: feature.label,
            titleKey: 'page-title-${feature.id}',
            eyebrow: _groupLabel(feature.groupId),
            description: description,
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_sections[feature.id] case final sections?) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < sections.length; index++)
                  AccountingButton.ghost(
                    context,
                    key: ValueKey('preview-tab-${feature.id}-$index'),
                    onPressed: () => setState(() => _selected = index),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selected == index) ...[
                          const Icon(Icons.check, size: 16),
                          const SizedBox(width: 6),
                        ],
                        Text(sections[index]),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(
              height: 1,
              indent: accountingContentInset,
              endIndent: accountingContentInset,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: accountingContentInset,
              ),
              child: Text(
                sections[_selected],
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: accountingContentInset,
              ),
              child: Text(
                'Layout preview. Records and actions for this section are not connected yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(accountingControlRadius),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          feature.id == 'documents' ? 'Document' : 'Reference',
                        ),
                      ),
                      const Expanded(child: Text('Date')),
                      const Expanded(child: Text('Status')),
                    ],
                  ),
                  const Divider(height: 32),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('No preview records'),
                  ),
                ],
              ),
            ),
          ] else
            AccountingEmptyState.card(
              context,
              title: 'Not Available Yet',
              description: 'This workflow is not available yet.',
              icon: Icons.construction_outlined,
            ),
        ],
      ),
    );
  }

  String _groupLabel(String groupId) {
    for (final group in FeatureRegistry.navigationGroups) {
      if (group.id == groupId) {
        return group.label;
      }
    }
    return 'Accounting';
  }

  static const _descriptions = <String, String>{
    'home': 'Keep your business finances clear, current, and ready for the next decision.',
    'banking':
        'Review imported bank and card activity before it reaches the ledger.',
    'sales-customers': 'Keep the customer balance and money-in lifecycle in one accounting workspace.',
    'expenses-vendors': 'Track paid expenses and unpaid vendor obligations without mixing their ledger paths.',
    'record-expense': 'Capture a new expense with its accounting category and supporting document.',
    'claims': 'Record personally paid expenses as claims, review them, and reimburse the claimant without duplicating a direct expense.',
    'payment-vouchers': 'Prepare and reconcile payments against one existing expense, claim payment, or bill settlement.',
    'accounting': 'Maintain the chart, periods, journals, and controls behind every accounting workflow.',
    'taxes': 'Keep tax codes, liabilities, payments, and reporting tied to posted accounting data.',
    'reports': 'Turn the same accounting records into financial, management, tax, and reconciliation views.',
    'documents': 'Keep receipts, bills, attachments, exports, and backups linked to accounting records.',
    'contacts-items': 'Maintain accounting-facing customers, vendors, products, services, and tax defaults.',
    'accountant-review': 'Resolve exceptions, inspect audit history, and prepare controlled accounting exports.',
  };
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Route Not Found'),
            SizedBox(height: 8),
            Text('This path is not part of the Accounting Core release.'),
          ],
        ),
      ),
    );
  }
}
