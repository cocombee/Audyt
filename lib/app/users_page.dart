import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/accounting/presentation/widgets/accounting_layout.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'field_row_trial.dart';
import 'user_directory.dart';
import 'responsive.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.directory, this.compact = false});
  final UserDirectory directory;
  final bool compact;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _search = '';
  Timer? _searchDebounce;
  final _searchController = TextEditingController();
  int _operationGeneration = 0;
  PagedUserDirectory? get _paged => widget.directory is PagedUserDirectory
      ? widget.directory as PagedUserDirectory
      : null;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadPage(int offset, int limit, String search) {
    _searchDebounce?.cancel();
    setState(() => _selected.clear());
    unawaited(_paged!.loadPage(offset: offset, limit: limit, search: search));
  }

  bool _busy = false;
  bool _selecting = false;
  final Set<String> _selected = {};
  String? _noticeMessage;
  String _noticeTitle = 'Demo Company';
  int _noticeGeneration = 0;

  void _setPreviewNotice() {
    _noticeTitle = 'Demo Company';
    _noticeMessage =
        widget.directory.isPreview && widget.directory.canManageUsers
        ? 'Director preview. Changes affect sample employees only.'
        : null;
    ++_noticeGeneration;
  }

  @override
  void initState() {
    super.initState();
    _search = _paged?.search ?? '';
    _searchController.text = _search;
    _setPreviewNotice();
  }

  @override
  void didUpdateWidget(covariant UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      _searchDebounce?.cancel();
      ++_operationGeneration;
      _search = _paged?.search ?? '';
      _searchController.text = _search;
      _selected.clear();
      _busy = false;
      _selecting = false;
      _setPreviewNotice();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final generation = ++_operationGeneration;
    setState(() => _busy = true);
    try {
      await action();
    } on StateError catch (error) {
      if (mounted && generation == _operationGeneration) {
        setState(() {
          _noticeTitle = 'Could Not Update Employees';
          _noticeMessage = error.message;
          ++_noticeGeneration;
        });
      }
    } finally {
      if (mounted && generation == _operationGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _bulk(List<RegisteredUser> users, UserBatchAction action) async {
    final directory = widget.directory;
    BusinessRole? role;
    final verb = switch (action) {
      UserBatchAction.approve => 'Approve',
      UserBatchAction.reject => 'Reject',
      UserBatchAction.remove => 'Delete',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          title: '$verb ${users.length} Employees',
          maxContentWidth: 400,
          formFooter: true,
          contentInset: 20,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(users.map((u) => u.name).join(', ')),
                const SizedBox(height: 20),
                if (action == UserBatchAction.approve)
                  AccountingOrdinaryFields(
                    key: const ValueKey('employee-batch-role-fields'),
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Role',
                        minimumRowFraction: 1,
                        hasGuidance: true,
                        choices: [
                          if (role == null) 'Select Role',
                          for (final option in BusinessRole.values)
                            option.label,
                        ],
                        builder: (width) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accountingFieldLabel(
                              context,
                              'Role',
                              alignToField: true,
                              guidance: 'Only Directors can approve employees and manage access.',
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            AccountingSelector<BusinessRole>(
                              assignedWidth: width,
                              triggerKey: const ValueKey('batch-user-role'),
                              value: role,
                              hintText: 'Select Role',
                              options: [
                                for (final item in BusinessRole.values)
                                  AccountingSelectorOption(
                                    value: item,
                                    label: item.label,
                                  ),
                              ],
                              onChanged: (value) => update(() => role = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    action == UserBatchAction.remove
                        ? 'Remove these employees from this business? Accounting records and linked documents are retained.'
                        : 'Reject these pending registrations?',
                  ),
              ],
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: const ValueKey('cancel-user-batch'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            (switch (action) {
              UserBatchAction.remove => AccountingButton.destructive,
              UserBatchAction.reject => AccountingButton.outline,
              UserBatchAction.approve => AccountingButton.primary,
            })(
              context,
              key: const ValueKey('confirm-user-batch'),
              onPressed: action == UserBatchAction.approve && role == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(verb),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || directory != widget.directory) return;
    if (action == UserBatchAction.approve &&
        role == BusinessRole.director &&
        !await _confirmDirectorAppointment(users)) {
      return;
    }
    if (!mounted || directory != widget.directory) return;
    await _run(() async {
      await directory.applyBatch(users, action, role: role);
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
      }
    });
  }

  Future<void> _role(RegisteredUser user, {required bool approving}) async {
    final directory = widget.directory;
    final choices = directory.roleOptions(user);
    if (choices.isEmpty ||
        (!approving && choices.every((role) => role == user.role))) {
      return;
    }
    BusinessRole? selected = approving ? null : user.role;
    final result = await showDialog<BusinessRole>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          title: approving ? 'Approve Employee' : 'Change Role',
          description: '${user.name} · ${user.email}',
          maxContentWidth: 400,
          formFooter: true,
          contentInset: 20,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountingOrdinaryFields(
                  key: const ValueKey('employee-role-fields'),
                  fields: [
                    AccountingOrdinaryFieldSlot(
                      label: 'Role',
                      minimumRowFraction: 1,
                      hasGuidance: true,
                      choices: [
                        if (selected == null) 'Select Role',
                        for (final option in choices) option.label,
                      ],
                      builder: (width) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accountingFieldLabel(
                            context,
                            'Role',
                            alignToField: true,
                            guidance: 'Only Directors can approve employees and manage access.',
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          AccountingSelector<BusinessRole>(
                            assignedWidth: width,
                            triggerKey: const ValueKey('user-role-selector'),
                            value: selected,
                            hintText: 'Select Role',
                            options: [
                              for (final role in choices)
                                AccountingSelectorOption(
                                  value: role,
                                  label: role.label,
                                ),
                            ],
                            onChanged: (role) => update(() => selected = role),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: const ValueKey('cancel-user-dialog'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('confirm-user-role'),
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text(approving ? 'Approve' : 'Change Role'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted || directory != widget.directory) return;
    if (result == BusinessRole.director &&
        (approving || user.role != BusinessRole.director) &&
        !await _confirmDirectorAppointment([user])) {
      return;
    }
    if (!mounted || directory != widget.directory) return;
    await _run(
      () => approving
          ? directory.approve(user, result)
          : directory.changeRole(user, result),
    );
  }

  Future<bool> _confirmDirectorAppointment(List<RegisteredUser> users) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AccountingDialog.alert(
            context,
            title: users.length == 1
                ? 'Appoint Director?'
                : 'Appoint Directors?',
            maxContentWidth: 400,
            formFooter: true,
            contentInset: 20,
            content: Text(
              '${users.map((user) => user.name).join(', ')} will receive Director access '
              'to this business. Directors can approve or reject registrations, '
              'change employee roles, appoint other Directors and remove employee access. '
              'Only appoint people you trust. Continue?',
            ),
            actions: [
              AccountingButton.ghost(
                context,
                key: const ValueKey('cancel-director-appointment'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              AccountingButton.primary(
                context,
                key: const ValueKey('confirm-director-appointment'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, Appoint'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _confirm(RegisteredUser user, {required bool removing}) async {
    final directory = widget.directory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        title: removing ? 'Delete Employee' : 'Reject Registration',
        maxContentWidth: 400,
        formFooter: true,
        contentInset: 20,
        content: Text(
          removing
              ? 'Remove ${user.name} from this business? Accounting records and linked documents are retained.'
              : 'Reject the registration from ${user.name}?',
        ),
        actions: [
          AccountingButton.ghost(
            context,
            key: const ValueKey('cancel-user-action'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          (removing ? AccountingButton.destructive : AccountingButton.outline)(
            context,
            key: const ValueKey('confirm-user-action'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(removing ? 'Delete Employee' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || directory != widget.directory) return;
    await _run(
      () => removing ? directory.remove(user) : directory.reject(user),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.directory,
    builder: (context, _) {
      final paged = _paged;
      if (!widget.directory.canManageUsers) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                paged?.loading == true
                    ? 'Checking access…'
                    : paged?.error ?? 'Only Directors can manage employees.',
              ),
              if (paged != null && !paged.loading)
                AccountingButton.outline(
                  context,
                  key: const ValueKey('users-check-access'),
                  onPressed: () => unawaited(paged.refresh()),
                  child: const Text('Check Access'),
                ),
            ],
          ),
        );
      }
      final all = widget.directory.users;
      final selected = all.where((u) => _selected.contains(u.id)).toList();
      final deleteRestrictions = [
        for (final user in selected)
          if (widget.directory.removalRestriction(user)
              case final String reason)
            reason,
      ];
      final canDeleteSelected = deleteRestrictions.isEmpty;
      final allPending = selected.every(
        (u) => u.status == RegistrationStatus.pending,
      );
      final showSearch = AccountingRecordControlsPolicy.visible(
        paged?.total ?? all.length,
      );
      final query = showSearch ? _search.trim().toLowerCase() : '';
      final users = paged != null
          ? all
          : all
                .where(
                  (user) => '${user.name} ${user.email}'.toLowerCase().contains(
                    query,
                  ),
                )
                .toList();
      return AccountingPageShell(
        includeTopSafeArea: !widget.compact,
        topInset: widget.compact
            ? AccountingResponsive.pageTitleOuterGap
            : AccountingResponsive.pageTitleOuterGap -
                  AccountingResponsive.tabStripTopInset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Employees',
              title: 'Employees',
              description:
                  'Review employee registrations and manage business roles.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('users-select'),
                onPressed: _busy || paged?.loading == true
                    ? null
                    : () => setState(() {
                        _selecting = !_selecting;
                        _selected.clear();
                      }),
                child: Text(
                  _selecting ? 'Cancel Selection' : 'Select Employees',
                ),
              ),
            ),
            const SizedBox(height: accountingPageTitleOuterGap),
            if (_noticeMessage != null)
              AccountingAlert.build(
                context,
                key: ValueKey('users-notice-$_noticeGeneration'),
                title: _noticeTitle,
                description: _noticeMessage!,
                tone: AccountingAlertTone.warning,
                bottomGap: accountingContentInset,
              ),
            if (showSearch) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: AccountingLabelledSearch(
                    child: TextField(
                      key: const ValueKey('users-search'),
                      controller: _searchController,
                      decoration: accountingSingleLineInputDecoration(
                        context,
                        hintText: 'Search Name Or Email',
                      ),
                      onChanged: (value) {
                        setState(() => _search = value);
                        if (paged != null) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (mounted) {
                                _loadPage(0, paged.pageSize, value.trim());
                              }
                            },
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: accountingContentInset),
            ],
            if (paged != null) ...[
              if (paged.loading) const LinearProgressIndicator(),
              if (paged.error != null) Text(paged.error!),
              if (paged.hasUnconfirmedChange)
                Align(
                  alignment: Alignment.centerRight,
                  child: AccountingButton.outline(
                    context,
                    key: const ValueKey('users-retry-change'),
                    onPressed: _busy || paged.loading
                        ? null
                        : () => _run(paged.retryUnconfirmedChange),
                    child: const Text('Retry Last Change'),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: AccountingButton.outline(
                  context,
                  key: const ValueKey('users-refresh'),
                  onPressed: _busy || paged.loading
                      ? null
                      : () => unawaited(paged.refresh()),
                  child: const Text('Refresh Employees'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = _UsersColumns.measure(
                  context,
                  all,
                  constraints.maxWidth - accountingContentInset * 2,
                  selecting: _selecting,
                );
                return AccountingRecordList(
                  paginationKey: 'users',
                  totalCount: paged?.total ?? all.length,
                  externalPagination: paged == null
                      ? null
                      : Padding(
                          padding: accountingContentPadding,
                          child: AccountingRecordPagination(
                            keyPrefix: 'users',
                            total: paged.matched,
                            unfilteredTotal: paged.total,
                            offset: paged.offset,
                            pageSize: paged.pageSize,
                            pageSizes: AccountingRecordControlsPolicy.pageSizes,
                            onPageSizeChanged: (size) {
                              if (!_busy && !paged.loading) {
                                _loadPage(0, size, _search.trim());
                              }
                            },
                            onPrevious:
                                _busy || paged.loading || paged.offset == 0
                                ? null
                                : () => _loadPage(
                                    paged.offset - paged.pageSize,
                                    paged.pageSize,
                                    _search.trim(),
                                  ),
                            onNext:
                                _busy ||
                                    paged.loading ||
                                    paged.offset + paged.pageSize >=
                                        paged.matched
                                ? null
                                : () => _loadPage(
                                    paged.offset + paged.pageSize,
                                    paged.pageSize,
                                    _search.trim(),
                                  ),
                          ),
                        ),
                  header: Padding(
                    padding: accountingContentPadding,
                    child: columns.header(context),
                  ),
                  emptyState: Padding(
                    padding: accountingContentPadding,
                    child: Text(
                      query.isEmpty
                          ? 'No registrations yet.'
                          : 'No matching employees.',
                    ),
                  ),
                  children: [
                    for (final user in users)
                      AccountingRecordRow(
                        key: ValueKey('user-row-${user.id}'),
                        columnGap: columns.gap,
                        minimumDetailsWidth: columns.expanded
                            ? columns.user
                            : null,
                        leadingOverlaysTitle: _selecting,
                        leading: !_selecting
                            ? null
                            : AccountingLeadingCheckbox(
                                hitKey: ValueKey(
                                  'user-selection-hit-${user.id}',
                                ),
                                checkboxKey: ValueKey('user-select-${user.id}'),
                                value: _selected.contains(user.id),
                                semanticLabel: 'Select ${user.name}',
                                onChanged: _busy || paged?.loading == true
                                    ? null
                                    : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(user.id);
                                        } else {
                                          _selected.remove(user.id);
                                        }
                                      }),
                              ),
                        title: user.name,
                        details: Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AccountingTypography.helper(context),
                        ),
                        trailing: columns.cells(
                          context,
                          user: user,
                          actions: AccountingRecordActions(
                            trailing: const [],
                            actions: [
                              if (user.status ==
                                  RegistrationStatus.pending) ...[
                                AccountingButton.iconOnly(
                                  context,
                                  key: ValueKey('approve-user-${user.id}'),
                                  icon: Icons.check,
                                  iconAsset: '088-approval-check.svg',
                                  iconPaintedSizeAdjustment: 2,
                                  tooltip: 'Approve ${user.name}',
                                  compact: true,
                                  onPressed: _busy || _paged?.loading == true
                                      ? null
                                      : () => _role(user, approving: true),
                                ),
                                AccountingButton.iconOnly(
                                  context,
                                  key: ValueKey('reject-user-${user.id}'),
                                  icon: Icons.close,
                                  iconAsset: '028-close.svg',
                                  iconPaintedSizeAdjustment: -1,
                                  tooltip: 'Reject ${user.name}',
                                  compact: true,
                                  onPressed: _busy || _paged?.loading == true
                                      ? null
                                      : () => _confirm(user, removing: false),
                                ),
                              ] else ...[
                                if (user.status == RegistrationStatus.approved)
                                  AccountingButton.iconOnly(
                                    context,
                                    key: ValueKey('change-role-${user.id}'),
                                    icon: Icons.edit_outlined,
                                    tooltip:
                                        widget.directory
                                            .roleOptions(user)
                                            .any((role) => role != user.role)
                                        ? 'Change Role For ${user.name}'
                                        : 'This Director’s access is protected.',
                                    compact: true,
                                    onPressed:
                                        _busy ||
                                            _paged?.loading == true ||
                                            !widget.directory
                                                .roleOptions(user)
                                                .any(
                                                  (role) => role != user.role,
                                                )
                                        ? null
                                        : () => _role(user, approving: false),
                                  ),
                                AccountingButton.iconOnly(
                                  context,
                                  key: ValueKey('delete-user-${user.id}'),
                                  icon: Icons.delete_outline,
                                  tooltip:
                                      widget.directory.removalRestriction(
                                        user,
                                      ) ??
                                      'Delete ${user.name}',
                                  compact: true,
                                  onPressed:
                                      _busy ||
                                          _paged?.loading == true ||
                                          widget.directory.removalRestriction(
                                                user,
                                              ) !=
                                              null
                                      ? null
                                      : () => _confirm(user, removing: true),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_selecting && selected.length > 1) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (allPending)
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('users-bulk-reject'),
                      onPressed: _busy || _paged?.loading == true
                          ? null
                          : () => _bulk(selected, UserBatchAction.reject),
                      child: const Text('Reject'),
                    ),
                  Tooltip(
                    message: canDeleteSelected
                        ? 'Delete selected users'
                        : deleteRestrictions.first,
                    child: AccountingButton.destructive(
                      context,
                      key: const ValueKey('users-bulk-delete'),
                      onPressed:
                          _busy || _paged?.loading == true || !canDeleteSelected
                          ? null
                          : () => _bulk(selected, UserBatchAction.remove),
                      child: const Text('Delete'),
                    ),
                  ),
                  if (allPending)
                    AccountingButton.primary(
                      context,
                      key: const ValueKey('users-bulk-approve'),
                      onPressed: _busy || _paged?.loading == true
                          ? null
                          : () => _bulk(selected, UserBatchAction.approve),
                      child: const Text('Approve'),
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

/// Matches the content-measured columns in Recent Expenses and Accounts.
/// Spare width becomes the same gap between each pair, rather than a single
/// large spacer before Status. Header and record cells share the measurement.
class _UsersColumns {
  const _UsersColumns({
    required this.user,
    required this.status,
    required this.role,
    required this.actions,
    required this.gap,
    required this.expanded,
  });
  final double user, status, role, actions, gap;
  final bool expanded;

  static _UsersColumns measure(
    BuildContext context,
    List<RegisteredUser> users,
    double available, {
    required bool selecting,
  }) {
    final header = AccountingTypography.tableHeader(context);
    final value = AccountingTypography.controlValue(context);
    final helper = AccountingTypography.helper(context);
    final badge = Theme.of(context).textTheme.labelSmall!
        .copyWith(fontWeight: FontWeight.w600);
    double width(String text, TextStyle style) =>
        AccountingResponsive.measuredTextWidth(context, text, style);
    double widest(
      String title,
      Iterable<String> values,
      TextStyle style, {
      double chrome = 0,
    }) => values.fold(
      width(title, header),
      (largest, text) => math.max(largest, width(text, style) + chrome),
    );
    final status = widest(
      'Status',
      ['Pending', 'Approved', 'Rejected'],
      badge,
      chrome: 16,
    );
    final role = widest('Role', BusinessRole.values.map((r) => r.label), value);
    final actions = math.max(
      width('Actions', header),
      accountingSmallControlHeight * 2 + accountingRecordIconGap,
    );
    final selection = selecting ? 18 + accountingContentInset : 0.0;
    final fullUser =
        math.max(
          widest(
            'Employee / Email',
            users.map((u) => u.name),
            value.copyWith(fontWeight: FontWeight.w500),
          ),
          widest('Employee / Email', users.map((u) => u.email), helper),
        ) +
        selection;
    final room =
        available - status - role - actions - accountingContentInset * 3;
    final user = math.min(math.max(160 + selection, fullUser), room);
    final expanded = room >= 160 + selection;
    return _UsersColumns(
      user: user,
      status: status,
      role: role,
      actions: actions,
      gap: expanded
          ? (available - user - status - role - actions) / 3
          : accountingContentInset,
      expanded: expanded,
    );
  }

  Widget header(BuildContext context) {
    final style = AccountingTypography.tableHeader(context);
    if (!expanded) return Text('Employee / Email', style: style);
    return Row(
      children: [
        SizedBox(
          key: const ValueKey('users-user-header'),
          width: user,
          child: Text('Employee / Email', style: style),
        ),
        SizedBox(width: gap),
        SizedBox(
          key: const ValueKey('users-status-header'),
          width: status,
          child: Text('Status', style: style),
        ),
        SizedBox(width: gap),
        SizedBox(
          key: const ValueKey('users-role-header'),
          width: role,
          child: Text('Role', style: style),
        ),
        SizedBox(width: gap),
        SizedBox(
          key: const ValueKey('users-actions-header'),
          width: actions,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('Actions', style: style),
          ),
        ),
      ],
    );
  }

  Widget cells(
    BuildContext context, {
    required RegisteredUser user,
    required Widget actions,
  }) {
    Widget cell(String label, double width, Widget child) => SizedBox(
      key: ValueKey('user-${label.toLowerCase()}-cell-${user.id}'),
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!expanded) ...[
            Text(label, style: AccountingTypography.tableHeader(context)),
            const SizedBox(height: accountingRecordInfoLineGap),
          ],
          child,
        ],
      ),
    );
    final children = [
      cell(
        'Status',
        status,
        Align(
          alignment: Alignment.centerLeft,
          child: AccountingBadge.build(
            context,
            label: switch (user.status) {
              RegistrationStatus.pending => 'Pending',
              RegistrationStatus.approved => 'Approved',
              RegistrationStatus.rejected => 'Rejected',
            },
          ),
        ),
      ),
      cell(
        'Role',
        role,
        Text(
          user.role?.label ?? '—',
          style: AccountingTypography.controlValue(context),
        ),
      ),
      cell(
        'Actions',
        this.actions,
        Align(alignment: Alignment.centerRight, child: actions),
      ),
    ];
    if (expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          children[0],
          SizedBox(width: gap),
          children[1],
          SizedBox(width: gap),
          children[2],
        ],
      );
    }
    return Wrap(
      spacing: accountingContentInset,
      runSpacing: accountingContentInset,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
