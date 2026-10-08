import 'journal_workspace_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_description_field.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/money.dart';
import 'widgets/accounting_formatters.dart';
import '../application/account_repository.dart';
import '../application/accounting_workspace.dart';
import '../domain/account.dart';
import 'widgets/accounting_layout.dart';

/// Both the account list and inline selectors open this same account owner.
/// Return only the ID committed by the existing account command.
Future<EntityId?> showLedgerAccountDialog(
  BuildContext context,
  AccountingWorkspace workspace,
  List<StoredAccount> accounts, {
  Set<ReportingAccountType>? allowedReportingTypes,
  StoredAccount? original,
}) => showDialog<EntityId>(
  context: context,
  builder: (_) => _NewAccountDialog(
    workspace: workspace,
    accounts: accounts,
    allowedReportingTypes: allowedReportingTypes,
    original: original,
  ),
);

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({
    super.key,
    required this.workspace,
    this.compact = false,
  });
  final AccountingWorkspace workspace;
  final bool compact;
  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  List<StoredAccount>? _accounts;
  String? _error;
  String _query = '';
  int _pageSize = AccountingRecordPageSizes.read('chart-of-accounts');
  int _page = 0;
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(ChartOfAccountsPage old) {
    super.didUpdateWidget(old);
    if (old.workspace != widget.workspace) {
      old.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accounts = await widget.workspace.accounts();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Accounts could not be loaded. Your saved records have not been changed.',
        );
      }
    }
  }

  void _create() =>
      showLedgerAccountDialog(context, widget.workspace, _accounts ?? []);
  Future<void> _view(StoredAccount record) async {
    final account = record.account;
    final parent = (_accounts ?? [])
        .where((r) => r.account.id == account.parentId)
        .map((r) => r.account.displayName)
        .firstOrNull;
    final tax = widget.workspace.taxRates
        .where((r) => r.id == account.profile?.defaultTaxCodeId)
        .map((r) => r.label)
        .firstOrNull;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.normal,
        title: account.name,
        description: 'Saved Account Details',
        closeKey: const ValueKey('ledger-account-view-close'),
        content: SelectionArea(
          child: AccountingInformationRows(
            rows: [
              ('Account Code', account.code),
              (
                'Account Type',
                account.profile?.reportingType?.label ??
                    accountingTitleCase(account.type.name),
              ),
              ('Detail Type', account.profile?.detailType ?? 'Not Set'),
              ('Parent Account', parent ?? account.parentId?.value ?? 'None'),
              (
                'Default Tax Code',
                tax ?? account.profile?.defaultTaxCodeId?.value ?? 'Not Set',
              ),
              ('Group Account', account.isParent ? 'Yes' : 'No'),
              ('Status', accountingTitleCase(account.status.name)),
              ('Description', account.profile?.description ?? ''),
              ('Revision', '${record.metadata.revision}'),
            ],
          ),
        ),
        actions: [],
      ),
    );
  }

  Widget _recordActions(BuildContext context, StoredAccount record) =>
      AccountingRecordActions(
        trailing: [
          AccountingButton.iconOnly(
            context,
            key: ValueKey('ledger-account-view-${record.account.id.value}'),
            tooltip: 'View ${record.account.name}',
            icon: Icons.visibility_outlined,
            onPressed: () => _view(record),
          ),
          AccountingButton.iconOnly(
            context,
            key: ValueKey('ledger-account-edit-${record.account.id.value}'),
            tooltip: 'Edit ${record.account.name}',
            icon: Icons.edit_outlined,
            onPressed: () => showLedgerAccountDialog(
              context,
              widget.workspace,
              _accounts ?? [],
              original: record,
            ),
          ),
        ],
      );

  double get _recordActionWidth =>
      accountingSmallControlHeight * 2 + accountingRecordIconGap;

  @override
  Widget build(BuildContext context) {
    final accounts = (_accounts ?? [])
        .where(
          (r) => '${r.account.code} ${r.account.name}'.toLowerCase().contains(
            AccountingRecordControlsPolicy.visible(_accounts?.length ?? 0)
                ? _query.toLowerCase()
                : '',
          ),
        )
        .toList();
    final pages = (accounts.length / _pageSize).ceil().clamp(1, 1000000);
    _page = _page.clamp(0, pages - 1);
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, accounts.length);
    return AccountingPageShell(
      includeTopSafeArea: !widget.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingPageHeader(
            routeLabel: 'Chart Of Accounts',
            title: 'Chart Of Accounts',
            titleKey: 'page-title-accounting',
            description: 'Organize the accounts used to classify and report your transactions.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('new-ledger-account'),
              onPressed: _accounts == null ? null : _create,
              leadingIcon: Icons.add_rounded,
              child: const Text('New Account'),
            ),
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: accountingContentInset,
              ),
              child: Text(_error!, style: AccountingTypography.helper(context)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AccountingButton.outline(
                context,
                key: const ValueKey('retry-accounts'),
                onPressed: _load,
                leadingIcon: Icons.refresh_outlined,
                child: const Text('Retry'),
              ),
            ),
          ] else if (_accounts == null)
            const LinearProgressIndicator()
          else ...[
            if (_accounts!.isNotEmpty) ...[
              _accountToolbar(context),
              const SizedBox(height: 16),
            ],
            AccountingCard.surface(
              context,
              child: accounts.isEmpty
                  ? Padding(
                      padding: accountingContentPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _query.isEmpty
                                ? 'No Accounts Yet'
                                : 'No Matching Accounts',
                            style: AccountingTypography.sectionTitle(context),
                          ),
                          const SizedBox(height: 6),
                          accountingHelperText(
                            context,
                            _query.isEmpty
                                ? 'Create the accounts your business needs. Opening balances are recorded through balanced journals.'
                                : 'Try a different account code or name.',
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = _columnsFor(
                          context,
                          (_accounts ?? []).map((stored) => stored.account),
                          constraints.maxWidth -
                              accountingContentInset * 3 -
                              _recordActionWidth,
                        );
                        return Column(
                          children: [
                            Padding(
                              padding: accountingContentPadding,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _accountHeader(context, columns),
                                  ),
                                  SizedBox(
                                    width:
                                        accountingContentInset +
                                        _recordActionWidth,
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: AccountingTheme.of(context).border,
                            ),
                            for (var index = start; index < end; index++) ...[
                              if (index > start)
                                Divider(
                                  height: 1,
                                  color: AccountingTheme.of(context).border,
                                ),
                              Padding(
                                padding: accountingContentPadding,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _accountRow(
                                        context,
                                        accounts[index].account,
                                        columns,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: accountingContentInset,
                                    ),
                                    SizedBox(
                                      width: _recordActionWidth,
                                      child: _recordActions(
                                        context,
                                        accounts[index],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (AccountingRecordControlsPolicy.visible(
                              _accounts!.length,
                            )) ...[
                              Divider(
                                height: 1,
                                color: AccountingTheme.of(context).border,
                              ),
                              Padding(
                                padding: accountingContentPadding,
                                child: AccountingRecordPagination(
                                  keyPrefix: 'chart-of-accounts',
                                  total: accounts.length,
                                  unfilteredTotal: _accounts!.length,
                                  offset: start,
                                  pageSize: _pageSize,
                                  onPageSizeChanged: (size) => setState(() {
                                    _pageSize = size;
                                    _page = 0;
                                  }),
                                  onPrevious: _page == 0
                                      ? null
                                      : () => setState(() => _page--),
                                  onNext: _page + 1 >= pages
                                      ? null
                                      : () => setState(() => _page++),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountToolbar(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final journal = AccountingButton.outline(
        context,
        key: const ValueKey('new-journal'),
        onPressed:
            (_accounts
                        ?.where(
                          (r) =>
                              r.account.status == AccountStatus.active &&
                              !r.account.isParent,
                        )
                        .length ??
                    0) <
                2
            ? null
            : () => showJournalEditor(context, widget.workspace, _accounts!),
        leadingIcon: Icons.add_rounded,
        child: const Text('New Journal'),
      );
      final journalWidth =
          AccountingResponsive.measuredTextWidth(
            context,
            'New Journal',
            AccountingTypography.button(context),
          ) +
          accountingContentInset * 2 +
          16 +
          8 +
          2;
      final inline =
          constraints.maxWidth >= 240 + accountingContentInset + journalWidth;
      final searchWidth = constraints.maxWidth.clamp(0.0, 240.0);
      final search = SizedBox(
        width: searchWidth,
        child: TextField(
          key: const ValueKey('account-search'),
          onChanged: (value) => setState(() {
            _query = value;
            _page = 0;
          }),
          decoration: accountingSingleLineInputDecoration(
            context,
            hintText: 'Search Accounts',
          ),
        ),
      );
      if (!AccountingRecordControlsPolicy.visible(_accounts?.length ?? 0)) {
        return Align(alignment: Alignment.centerLeft, child: journal);
      }
      return inline
          ? Row(
              children: [
                search,
                const SizedBox(width: accountingContentInset),
                journal,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                search,
                const SizedBox(height: accountingContentInset),
                journal,
              ],
            );
    },
  );

  _AccountColumns _columnsFor(
    BuildContext context,
    Iterable<Account> accounts,
    double availableWidth,
  ) {
    final valueStyle = AccountingTypography.value(context);
    final headerStyle = AccountingTypography.tableHeader(context);
    final badgeStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    double widest(
      String header,
      Iterable<String> values,
      TextStyle? style, {
      double chrome = 0,
    }) {
      var width = AccountingResponsive.measuredTextWidth(
        context,
        header,
        headerStyle,
      );
      for (final value in values) {
        final measured =
            AccountingResponsive.measuredTextWidth(context, value, style) +
            chrome;
        if (measured > width) width = measured;
      }
      return width;
    }

    final items = accounts.toList();
    final code = widest('Code', items.map((a) => a.code), valueStyle);
    final fullName = widest('Account', items.map((a) => a.name), valueStyle);
    final type = widest(
      'Type',
      items.map(
        (a) =>
            '${a.profile?.reportingType?.label ?? accountingTitleCase(a.type.name)}${a.isParent ? ' · Group Account' : ''}',
      ),
      valueStyle,
    );
    final status = widest(
      'Status',
      items.map((a) => accountingTitleCase(a.status.name)),
      badgeStyle,
      chrome: 16,
    );
    // Keep the named columns as long as a useful account-name column fits.
    // Long names can ellipsize instead of forcing every account into two lines.
    final nameRoom =
        availableWidth - code - type - status - accountingContentInset * 3;
    final name = fullName < nameRoom ? fullName : nameRoom;
    final total = code + name + type + status;
    final expanded = nameRoom >= 120;
    final gap = expanded
        ? (availableWidth - total) / 3
        : accountingContentInset;
    return _AccountColumns(
      code: code,
      name: name,
      type: type,
      status: status,
      gap: gap,
      expanded: expanded,
    );
  }

  Widget _accountHeader(BuildContext context, _AccountColumns columns) {
    final style = AccountingTypography.tableHeader(context);
    if (!columns.expanded) {
      return Row(
        children: [
          Expanded(child: Text('Account / Type', style: style)),
          const SizedBox(width: accountingContentInset),
          Text('Status', style: style),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: columns.code,
          child: Text('Code', style: style),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          width: columns.name,
          child: Text('Account', style: style),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          width: columns.type,
          child: Text('Type', style: style),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          width: columns.status,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('Status', style: style),
          ),
        ),
      ],
    );
  }

  Widget _accountRow(
    BuildContext context,
    Account account,
    _AccountColumns columns,
  ) {
    final description =
        '${account.profile?.reportingType?.label ?? accountingTitleCase(account.type.name)}${account.isParent ? ' · Group Account' : ''}';
    final status = AccountingBadge.build(
      context,
      label: accountingTitleCase(account.status.name),
      key: ValueKey('account-status-${account.code}'),
    );
    if (!columns.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: AccountingTypography.value(context),
                ),
              ),
              const SizedBox(width: accountingContentInset),
              status,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            key: ValueKey('account-type-${account.code}'),
            style: AccountingTypography.value(context),
          ),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          key: ValueKey('account-code-cell-${account.code}'),
          width: columns.code,
          child: Text(account.code),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          key: ValueKey('account-name-cell-${account.code}'),
          width: columns.name,
          child: Text(
            account.name,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: AccountingTypography.value(context),
          ),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          key: ValueKey('account-type-cell-${account.code}'),
          width: columns.type,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              description,
              key: ValueKey('account-type-${account.code}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AccountingTypography.value(context),
            ),
          ),
        ),
        SizedBox(width: columns.gap),
        SizedBox(
          key: ValueKey('account-status-cell-${account.code}'),
          width: columns.status,
          child: Align(alignment: Alignment.centerRight, child: status),
        ),
      ],
    );
  }
}

class _AccountColumns {
  const _AccountColumns({
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.gap,
    required this.expanded,
  });
  final double code;
  final double name;
  final double type;
  final double status;
  final double gap;
  final bool expanded;
}

class _NewAccountDialog extends StatefulWidget {
  const _NewAccountDialog({
    required this.workspace,
    required this.accounts,
    this.allowedReportingTypes,
    this.original,
  });
  final StoredAccount? original;
  final Set<ReportingAccountType>? allowedReportingTypes;
  final AccountingWorkspace workspace;
  final List<StoredAccount> accounts;
  @override
  State<_NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends State<_NewAccountDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _openingAmount = TextEditingController();
  final _openingDate = TextEditingController();
  final _editingFocus = FocusScopeNode();
  late final _fieldChanges = Listenable.merge([_code, _name]);
  final _typeFieldKey = GlobalKey();
  final _parentFieldKey = GlobalKey();
  final _saveErrorKey = GlobalKey();
  Iterable<ReportingAccountType> get _allowedTypes =>
      ReportingAccountType.values.where(
        (type) =>
            widget.allowedReportingTypes == null ||
            widget.allowedReportingTypes!.contains(type),
      );
  AccountType? _type;
  ReportingAccountType? _reportingType;
  String? _detailType;
  EntityId? _defaultTaxCode;
  bool _locked = false;
  String _parent = 'none';
  bool _group = false;
  bool _busy = false;
  bool _closePromptOpen = false;
  String? _error;
  late final List<Object?> _openingFacts;
  Future<BigInt>? _balance;
  final _balanceThrough = DateTime.now();

  @override
  void initState() {
    super.initState();
    final account = widget.original?.account;
    if (account != null) {
      _code.text = account.code;
      _name.text = account.name;
      _description.text = account.profile?.description ?? '';
      _type = account.type;
      _reportingType = account.profile?.reportingType;
      _detailType = account.profile?.detailType;
      _defaultTaxCode = account.profile?.defaultTaxCodeId;
      _parent = account.parentId?.value ?? 'none';
      _group = account.isParent;
      _locked = account.status == AccountStatus.locked;
      _balance = widget.workspace
          .report(from: DateTime.utc(1), through: _balanceThrough)
          .then(
            (report) => report.rows
                .singleWhere((row) => row.account.id == account.id)
                .endingNetDebit,
          );
    }
    _openingFacts = _facts;
  }

  List<Object?> get _facts => [
    _code.text,
    _name.text,
    _description.text,
    _type,
    _reportingType,
    _detailType,
    _parent,
    _group,
    _locked,
    _defaultTaxCode,
    _openingAmount.text,
    _openingDate.text,
  ];

  Future<bool> _confirmClassificationChange() async {
    if (widget.original == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AccountingDialog.alert(
            c,
            widthFamily: AccountingPopoutWidthFamily.dialog,
            title: 'Change Account Classification',
            closeKey: const ValueKey('ledger-classification-close'),
            content: accountingHelperText(
              c,
              'Changing the account type or detail changes its reporting classification. Existing postings remain unchanged.',
            ),
            actions: [
              AccountingButton.outline(
                c,
                key: const ValueKey('ledger-classification-keep'),
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Keep Current'),
              ),
              AccountingButton.primary(
                c,
                key: const ValueKey('ledger-classification-change'),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Change Classification'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _changeType(ReportingAccountType? value) async {
    if (value == _reportingType || _busy) return;
    if (!await _confirmClassificationChange() || !mounted) return;
    setState(() {
      _reportingType = value;
      _type = value?.ledgerType;
      _detailType = value?.details.first;
      _parent = 'none';
      _error = null;
    });
  }

  Future<void> _changeDetail(String? value) async {
    if (value == _detailType || _busy) return;
    if (!await _confirmClassificationChange() || !mounted) return;
    setState(() {
      _detailType = value;
      _error = null;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _openingAmount.dispose();
    _openingDate.dispose();
    _editingFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || widget.original != null) return;
    if (_code.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        _type == null) {
      _showSaveError('Enter an account code, name and type.');
      return;
    }
    if (_openingAmount.text.trim().isNotEmpty ||
        _openingDate.text.trim().isNotEmpty) {
      _showSaveError(
        'Opening balances require a dated balanced journal. This step is not connected to account creation yet.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final savedId = await widget.workspace.createAccount(
        code: _code.text,
        name: _name.text,
        type: _type!,
        profile: AccountProfile(
          reportingType: _reportingType,
          detailType: _detailType,
          description: _description.text,
          defaultTaxCodeId: _defaultTaxCode,
        ),
        status: _locked ? AccountStatus.locked : AccountStatus.active,
        isParent: _group,
        parentId: _parent == 'none' ? null : EntityId.parse(_parent),
      );
      if (mounted) Navigator.of(context).pop(savedId);
    } catch (error) {
      if (mounted) {
        _showSaveError(
          error is StateError
              ? error.message
              : 'The account could not be saved. Check the details and retry.',
        );
      }
    }
  }

  void _showSaveError(String message) {
    setState(() {
      _error = message;
      _busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _error != message) return;
      final errorContext = _saveErrorKey.currentContext;
      if (errorContext != null) {
        Scrollable.ensureVisible(errorContext, alignment: 1);
      }
    });
  }

  void _clearFieldError() {
    if (!_busy && _error != null) setState(() => _error = null);
  }

  bool get _hasChanges {
    final facts = _facts;
    return facts.asMap().entries.any((e) => e.value != _openingFacts[e.key]);
  }

  Future<void> _handleClose() async {
    if (_busy || _closePromptOpen) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('ledger-discard-close'),
        keepEditingKey: const ValueKey('ledger-keep-editing'),
        discardKey: const ValueKey('ledger-discard-changes'),
      );
      if (mounted) {
        if (discard == true) {
          Navigator.of(context).pop();
        } else {
          _editingFocus.requestFocus();
        }
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Widget _label(
    String label,
    Widget child, {
    bool ordinary = false,
    String? guidance,
    Key? key,
  }) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(
        context,
        label,
        guidance: guidance,
        alignToField: true,
      ),
      const SizedBox(height: 8),
      child,
      if (!ordinary) const SizedBox(height: 16),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final parents = widget.accounts
        .where(
          (r) =>
              r.account.id != widget.original?.account.id &&
              r.account.isParent &&
              (r.account.status == AccountStatus.active ||
                  r.account.id == widget.original?.account.parentId) &&
              r.account.type == _type,
        )
        .toList();
    return FocusScope(
      node: _editingFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _handleClose();
        },
        child: AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: widget.original == null ? 'New Account' : 'Edit Account',
          closeKey: const ValueKey('ledger-account-close'),
          formFooter: true,
          description: widget.original == null
              ? 'Create an account in the company reporting currency.'
              : 'Account updates are not connected yet.',
          content: SizedBox(
            width: AccountingPopoutTokens.normalContentWidth,
            child: AnimatedBuilder(
              animation: _fieldChanges,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(
                    'Reporting Currency',
                    Text(
                      '${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol} · Company Functional Currency',
                    ),
                    guidance: 'Bank account currencies are configured in Banking. Ledger balances are reported in the company currency.',
                  ),
                  AccountingOrdinaryFields(
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Account Code *',
                        contentSample: _code.text.isEmpty
                            ? 'For Example, 1000'
                            : _code.text,
                        builder: (width) => _label(
                          'Account Code *',
                          TextField(
                            key: const ValueKey('ledger-account-code'),
                            controller: _code,
                            onChanged: (_) => _clearFieldError(),
                            enabled: !_busy,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'For Example, 1000',
                            ),
                          ),
                          ordinary: true,
                          key: GlobalObjectKey(_code),
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Account Name *',
                        contentSample: _name.text.isEmpty
                            ? 'For Example, Cash At Bank'
                            : _name.text,
                        minimumRowFraction: 0.5,
                        builder: (width) => _label(
                          'Account Name *',
                          TextField(
                            key: const ValueKey('ledger-account-name'),
                            controller: _name,
                            onChanged: (_) => _clearFieldError(),
                            enabled: !_busy,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'For Example, Cash At Bank',
                            ),
                          ),
                          ordinary: true,
                          key: GlobalObjectKey(_name),
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Account Type *',
                        choices: [
                          if (_type == null) 'Select Type',
                          for (final type in _allowedTypes) type.label,
                        ],
                        builder: (width) => _label(
                          'Account Type *',
                          AccountingSelector<ReportingAccountType>(
                            triggerKey: const ValueKey('ledger-account-type'),
                            searchKey: const ValueKey('ledger-type-search'),
                            assignedWidth: width,
                            value: _reportingType,
                            onChanged: _changeType,
                            enabled: !_busy,
                            hintText:
                                widget.original != null &&
                                    _reportingType == null
                                ? accountingTitleCase(_type!.name)
                                : 'Select Type',
                            searchable: true,
                            options: [
                              for (final type in _allowedTypes)
                                AccountingSelectorOption(
                                  value: type,
                                  label: type.label,
                                ),
                            ],
                          ),
                          ordinary: true,
                          key: _typeFieldKey,
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Detail Type *',
                        choices:
                            _reportingType?.details ?? ['Select Detail Type'],
                        builder: (width) => _label(
                          'Detail Type *',
                          AccountingSelector<String>(
                            triggerKey: const ValueKey('ledger-detail-type'),
                            searchKey: const ValueKey('ledger-detail-search'),
                            assignedWidth: width,
                            value: _detailType,
                            enabled: !_busy && _reportingType != null,
                            onChanged: _changeDetail,
                            searchable: true,
                            hintText: 'Select Detail Type',
                            options: [
                              for (final detail
                                  in _reportingType?.details ?? <String>[])
                                AccountingSelectorOption(
                                  value: detail,
                                  label: detail,
                                ),
                            ],
                          ),
                          ordinary: true,
                        ),
                      ),
                      if (parents.isNotEmpty)
                        AccountingOrdinaryFieldSlot(
                          label: 'Parent Account',
                          choices: [
                            'None',
                            for (final record in parents)
                              record.account.displayName,
                          ],
                          builder: (width) => _label(
                            'Parent Account',
                            AccountingSelector<String>(
                              triggerKey: const ValueKey(
                                'ledger-parent-account',
                              ),
                              assignedWidth: width,
                              value: _parent,
                              onChanged: (value) =>
                                  setState(() => _parent = value ?? 'none'),
                              hintText: 'None',
                              enabled: !_busy,
                              options: [
                                const AccountingSelectorOption(
                                  value: 'none',
                                  label: 'None',
                                ),
                                for (final record in parents)
                                  AccountingSelectorOption(
                                    value: record.account.id.value,
                                    label: record.account.displayName,
                                    preserveLabelCase: true,
                                  ),
                              ],
                            ),
                            ordinary: true,
                            key: _parentFieldKey,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AccountingResponsive.groupGap),
                  AccountingOrdinaryFields(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Default Tax Code',
                        hasGuidance: true,
                        choices: [
                          'Not Set',
                          for (final rate in widget.workspace.taxRates.where(
                            (r) => r.active || r.id == _defaultTaxCode,
                          ))
                            rate.label,
                        ],
                        builder: (width) => _label(
                          'Default Tax Code',
                          AccountingSelector<EntityId?>(
                            triggerKey: const ValueKey('ledger-default-tax'),
                            assignedWidth: width,
                            value: _defaultTaxCode,
                            enabled: !_busy,
                            onChanged: (value) => setState(() {
                              _defaultTaxCode = value;
                              _error = null;
                            }),
                            hintText: 'Not Set',
                            searchable: true,
                            options: [
                              const AccountingSelectorOption<EntityId?>(
                                value: null,
                                label: 'Not Set',
                              ),
                              for (final rate
                                  in widget.workspace.taxRates.where(
                                    (r) => r.active || r.id == _defaultTaxCode,
                                  ))
                                AccountingSelectorOption<EntityId?>(
                                  value: rate.id,
                                  label: rate.label,
                                ),
                            ],
                          ),
                          ordinary: true,
                          guidance: 'Retains this company tax code as an account default. Existing transaction lines keep their own tax selection.',
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Group Account',
                        minimumControlWidth:
                            18 +
                            accountingContentInset +
                            accountingFieldLabelMinimumWidth(
                              context,
                              'Group Account',
                              alignToField: true,
                              hasGuidance: true,
                            ),
                        builder: (_) => SizedBox(
                          height: accountingControlHeight,
                          child: Row(
                            children: [
                              AccountingLeadingCheckbox(
                                undividedRow: true,
                                checkboxKey: const ValueKey(
                                  'ledger-group-account',
                                ),
                                value: _group,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => _group = value ?? false,
                                      ),
                                semanticLabel: 'Group Account',
                              ),
                              Expanded(
                                child: accountingFieldLabel(
                                  context,
                                  'Group Account',
                                  alignToField: true,
                                  guidance: 'Group accounts contain subaccounts and cannot receive postings.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.original == null &&
                      (_reportingType?.hasOpeningBalance ?? false)) ...[
                    const SizedBox(height: AccountingResponsive.groupGap),
                    AccountingOrdinaryFields(
                      fields: [
                        AccountingOrdinaryFieldSlot(
                          label:
                              'Opening Balance (${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol})',
                          contentSample: formatAccountingInputAmount(
                            Money.zero(widget.workspace.identity.currency),
                          ),
                          builder: (_) => _label(
                            'Opening Balance (${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol})',
                            TextField(
                              key: const ValueKey('ledger-opening-balance'),
                              controller: _openingAmount,
                              enabled: !_busy,
                              onChanged: (_) => _clearFieldError(),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              inputFormatters: [
                                AccountingMoneyInputFormatter(
                                  Currency.parse(
                                    widget.workspace.identity.currency,
                                  ).fractionDigits,
                                ),
                              ],
                              decoration: accountingSingleLineInputDecoration(
                                context,
                                hintText: formatAccountingInputAmount(
                                  Money.zero(
                                    widget.workspace.identity.currency,
                                  ),
                                ),
                              ),
                            ),
                            ordinary: true,
                          ),
                        ),
                        AccountingOrdinaryFieldSlot(
                          label: 'As Of',
                          date: true,
                          contentSample: '00-00-0000',
                          builder: (_) => _label(
                            'As Of',
                            accountingDateFieldFrame(
                              child: TextField(
                                key: const ValueKey('ledger-opening-date'),
                                controller: _openingDate,
                                enabled: !_busy,
                                onChanged: (_) => _clearFieldError(),
                                inputFormatters: [const DateInputFormatter()],
                                decoration:
                                    accountingSingleLineInputDecoration(
                                      context,
                                      hintText: 'DD-MM-YYYY',
                                    ).copyWith(
                                      suffixIcon: accountingCalendarButton(
                                        context,
                                        controller: _openingDate,
                                        label: 'As Of',
                                        enabled: !_busy,
                                      ),
                                    ),
                              ),
                            ),
                            ordinary: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: accountingContentInset),
                  accountingFieldLabel(
                    context,
                    'Description',
                    alignToField: true,
                    guidance: 'Describe the purpose of this account.',
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  AccountingDescriptionField(
                    key: const ValueKey('ledger-account-description'),
                    controller: _description,
                    onEscape: _handleClose,
                    enabled: !_busy,
                    onChanged: (_) => _clearFieldError(),
                    decoration: accountingSingleLineInputDecoration(
                      context,
                      hintText: 'Describe The Account',
                    ),
                  ),
                  if (widget.original != null) ...[
                    const SizedBox(height: accountingContentInset),
                    FutureBuilder<BigInt>(
                      future: _balance,
                      builder: (context, snapshot) => AccountingInformationRows(
                        rows: [
                          (
                            'Status',
                            accountingTitleCase(
                              widget.original!.account.status.name,
                            ),
                          ),
                          (
                            'Posted Balance',
                            snapshot.hasError
                                ? 'Unavailable'
                                : !snapshot.hasData
                                ? 'Loading…'
                                : '${formatAccountingMinor(context, snapshot.data!.abs(), widget.workspace.identity.currency)}${snapshot.data == BigInt.zero
                                      ? ''
                                      : snapshot.data! > BigInt.zero
                                      ? ' Dr'
                                      : ' Cr'}',
                          ),
                          (
                            'Through Date',
                            formatAccountingDate(context, _balanceThrough),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: accountingContentInset),
                  Row(
                    children: [
                      AccountingLeadingCheckbox(
                        undividedRow: true,
                        checkboxKey: const ValueKey('ledger-lock-account'),
                        value: _locked,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _locked = value ?? false),
                        semanticLabel: 'Lock Account',
                      ),
                      Expanded(
                        child: accountingFieldLabel(
                          context,
                          'Lock Account',
                          alignToField: true,
                          guidance: 'Locked accounts are unavailable for new selections and journal approval. Existing records remain available.',
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: _saveErrorKey,
                      style: AccountingTypography.helper(context).copyWith(
                        color: AccountingTheme.of(context).destructive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: null,
              onPressed: _busy ? null : _handleClose,
              child: const Text('Cancel'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('save-ledger-account'),
              onPressed: _busy || widget.original != null ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save Account'),
            ),
          ],
        ),
      ),
    );
  }
}
