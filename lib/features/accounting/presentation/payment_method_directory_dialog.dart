import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_description_field.dart';
import '../../../app/accounting_icons.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../app/field_row_trial.dart';
import '../../../app/responsive.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/money/currency_presentation.dart';
import '../application/accounting_workspace.dart';
import '../domain/company_payment_method.dart';
import 'widgets/accounting_formatters.dart';

/// Explicit preview facts, not a maintained company directory or stored defaults.
class PaymentMethodDirectoryPreviewEntry {
  const PaymentMethodDirectoryPreviewEntry({
    required this.id,
    required this.name,
    required this.cardPayment,
    this.active = true,
    this.method,
  });
  final String id, name;
  final bool cardPayment, active;
  final CompanyPaymentMethod? method;
}

Future<void> showPaymentMethodDirectoryPreview(
  BuildContext context, {
  bool demo = false,
  String currencyCode = 'MYR',
  AccountingWorkspace? workspace,
}) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => PaymentMethodDirectoryDialog(
    currencyCode: currencyCode,
    workspace: demo ? null : workspace,
    entries: demo
        ? const [
            PaymentMethodDirectoryPreviewEntry(
              id: 'demo-cash',
              name: 'Cash',
              cardPayment: false,
            ),
            PaymentMethodDirectoryPreviewEntry(
              id: 'demo-card',
              name: 'Company Card',
              cardPayment: true,
            ),
            PaymentMethodDirectoryPreviewEntry(
              id: 'demo-debit',
              name: 'Debit Card',
              cardPayment: false,
            ),
            PaymentMethodDirectoryPreviewEntry(
              id: 'demo-inactive',
              name: 'Archived Transfer',
              cardPayment: false,
              active: false,
            ),
          ]
        : const [],
  ),
);

/// Reuses the existing master-list, row actions, and payment-method form.
/// Workspace-backed saves and activation update maintained company records;
/// report actions remain preview-only.
class PaymentMethodDirectoryDialog extends StatefulWidget {
  const PaymentMethodDirectoryDialog({
    super.key,
    this.entries = const [],
    this.currencyCode = 'MYR',
    this.workspace,
  });
  final List<PaymentMethodDirectoryPreviewEntry> entries;
  final String currencyCode;
  final AccountingWorkspace? workspace;
  @override
  State<PaymentMethodDirectoryDialog> createState() =>
      _PaymentMethodDirectoryDialogState();
}

class _PaymentMethodDirectoryDialogState
    extends State<PaymentMethodDirectoryDialog> {
  bool _includeInactive = false;

  List<PaymentMethodDirectoryPreviewEntry> get _entries =>
      widget.workspace == null
      ? widget.entries
      : [
          for (final method in widget.workspace!.paymentMethods)
            PaymentMethodDirectoryPreviewEntry(
              id: method.id.value,
              name: method.name,
              cardPayment: method.cardPayment,
              active: method.active,
              method: method,
            ),
        ];

  Future<void> _report([PaymentMethodDirectoryPreviewEntry? entry]) =>
      showDialog<void>(
        context: context,
        builder: (_) => PaymentMethodReportPreview(
          entries: _entries,
          method: entry,
          currencyCode: widget.currencyCode,
        ),
      );

  Future<void> _view(PaymentMethodDirectoryPreviewEntry entry) =>
      AccountingDialog.showFixed<void>(
        context: context,
        contentWidth: AccountingPopoutTokens.normalContentWidth,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: entry.name,
          fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
          maxContentWidth: AccountingPopoutTokens.normalContentWidth,
          content: AccountingInformationRows(
            rows: [
              ('Name', entry.name),
              ('Card Payment', entry.cardPayment ? 'Yes' : 'No'),
              ('Status', entry.active ? 'Active' : 'Inactive'),
            ],
          ),
          actions: [],
        ),
      );

  Future<void> _activation(PaymentMethodDirectoryPreviewEntry entry) =>
      AccountingDialog.showFixed<void>(
        context: context,
        contentWidth: AccountingPopoutTokens.dialogContentWidth,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: entry.active ? 'Make Method Inactive?' : 'Make Method Active?',
          fixedContentWidth: AccountingPopoutTokens.dialogContentWidth,
          maxContentWidth: AccountingPopoutTokens.dialogContentWidth,
          description: widget.workspace == null
              ? 'Changing payment-method availability is not connected yet.'
              : 'This changes which methods are available for new Expenses.',
          content: Text(entry.name, style: AccountingTypography.value(context)),
          actions: [
            if (entry.active)
              AccountingButton.destructive(
                context,
                key: const ValueKey('payment-method-deactivate-confirm'),
                onPressed: entry.method == null
                    ? null
                    : () => _setActive(entry.method!, false),
                child: const Text('Make Inactive'),
              )
            else
              AccountingButton.primary(
                context,
                key: const ValueKey('payment-method-activate-confirm'),
                onPressed: entry.method == null
                    ? null
                    : () => _setActive(entry.method!, true),
                child: const Text('Make Active'),
              ),
          ],
        ),
      );

  Future<void> _setActive(CompanyPaymentMethod method, bool active) async {
    try {
      widget.workspace!.savePaymentMethod(
        CompanyPaymentMethod(
          id: method.id,
          name: method.name,
          cardPayment: method.cardPayment,
          active: active,
          revision: method.revision,
        ),
      );
      if (mounted) setState(() {});
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update payment method: $error')),
      );
    }
  }

  Future<void> _openMethodForm({
    PaymentMethodDirectoryPreviewEntry? entry,
  }) async {
    final saved = await showAccountingPaymentMethodPreview(
      context,
      directory: true,
      initialName: entry?.name,
      cardPayment: entry?.cardPayment ?? false,
      workspace: widget.workspace,
      existingMethod: entry?.method,
    );
    if (saved != null && mounted) setState(() {});
  }

  Widget _directoryToolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final valueStyle = AccountingTypography.value(context);
      final buttonStyle = AccountingTypography.button(context)
          .copyWith(fontSize: accountingControlFontSize);
      final checkboxWidth =
          18 +
          accountingContentInset +
          AccountingResponsive.measuredTextWidth(
            context,
            'Include Inactive',
            valueStyle,
          );
      final actionsWidth =
          accountingContentInset +
          AccountingResponsive.measuredTextWidth(
            context,
            'Run Report',
            buttonStyle,
          ) +
          AccountingResponsive.measuredTextWidth(
            context,
            'New Payment Method',
            buttonStyle,
          ) +
          4 * accountingContentInset;
      final checkbox = SizedBox(
        width: checkboxWidth,
        child: Row(
          children: [
            AccountingLeadingCheckbox(
              checkboxKey: const ValueKey('payment-method-include-inactive'),
              undividedRow: true,
              value: _includeInactive,
              semanticLabel: 'Include Inactive',
              onChanged: (value) =>
                  setState(() => _includeInactive = value ?? false),
            ),
            Text('Include Inactive', style: valueStyle),
          ],
        ),
      );
      final actions = AccountingButtonGroup(
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: accountingContentInset,
          runSpacing: accountingContentInset,
          children: [
            AccountingButton.outline(
              context,
              key: const ValueKey('payment-method-report'),
              onPressed: _report,
              child: const Text('Run Report'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('payment-method-new'),
              onPressed: _openMethodForm,
              child: const Text('New Payment Method'),
            ),
          ],
        ),
      );
      // Explicit toolbar roles: content-fit checkbox on the left; existing
      // intrinsic buttons on the right. No ordinary-field width rule applies.
      if (checkboxWidth + accountingContentInset + actionsWidth <=
          constraints.maxWidth) {
        return Row(children: [checkbox, const Spacer(), actions]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: checkbox),
          const SizedBox(height: accountingContentInset),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final allEntries = _entries;
    final entries = allEntries
        .where((entry) => _includeInactive || entry.active)
        .toList();
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: 'Payment Methods',
      description: widget.workspace == null
          ? 'Design preview · Methods are not saved. Existing payment selections are unchanged.'
          : 'Manage company payment methods used by Expense.',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _directoryToolbar(),
          const SizedBox(height: accountingContentInset),
          if (entries.isEmpty)
            accountingHelperText(
              context,
              allEntries.isEmpty
                  ? widget.workspace == null
                        ? 'The maintained payment-method list is not connected yet.'
                        : 'No payment methods are saved yet.'
                  : widget.workspace == null
                  ? 'No active methods in this preview.'
                  : 'No active methods. Include inactive methods to see them.',
            )
          else
            AccountingRecordList(
              paginationKey: 'payment-methods',
              totalCount: entries.length,
              children: [
                for (final entry in entries)
                  AccountingRecordRow(
                    key: ValueKey('payment-method-row-${entry.id}'),
                    title: entry.name,
                    details: Text(
                      'Card Payment: ${entry.cardPayment ? 'Yes' : 'No'}',
                      style: AccountingTypography.value(context),
                    ),
                    status: AccountingBadge.build(
                      context,
                      label: entry.active ? 'Active' : 'Inactive',
                    ),
                    trailing: AccountingRecordActions(
                      trailing: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('payment-method-activity-${entry.id}'),
                          onPressed: () => _report(entry),
                          icon: Icons.insert_chart_outlined,
                          iconAsset: '014-presentation.svg',
                          tooltip: 'Run Report for ${entry.name}',
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('payment-method-view-${entry.id}'),
                          onPressed: () => _view(entry),
                          icon: Icons.visibility_outlined,
                          tooltip: 'View ${entry.name}',
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('payment-method-edit-${entry.id}'),
                          onPressed: () => _openMethodForm(entry: entry),
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit ${entry.name}',
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey(
                            'payment-method-activation-${entry.id}',
                          ),
                          onPressed: () => _activation(entry),
                          icon: entry.active ? Icons.block : Icons.restore,
                          tooltip:
                              '${entry.active ? 'Make Inactive' : 'Make Active'} ${entry.name}',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      actions: [],
    );
  }
}

/// Physical report routes only. Preview names never supply transaction methods,
/// creation/modification metadata, deletion facts, or a production query result.
class PaymentMethodReportPreview extends StatefulWidget {
  const PaymentMethodReportPreview({
    super.key,
    required this.entries,
    this.method,
    required this.currencyCode,
  });
  final List<PaymentMethodDirectoryPreviewEntry> entries;
  final PaymentMethodDirectoryPreviewEntry? method;
  final String currencyCode;

  @override
  State<PaymentMethodReportPreview> createState() =>
      _PaymentMethodReportPreviewState();
}

class _PaymentMethodReportPreviewState
    extends State<PaymentMethodReportPreview> {
  static const _metadataColumns = [
    'Create Date',
    'Created By',
    'Last Modified',
    'Last Modified By',
  ];
  final _columns = <String>{};
  final _filters = _PaymentMethodReportFilterPreview();
  final _presentation = _PaymentMethodReportPresentationPreview();
  final _activity = _PaymentMethodActivityReportPreview();
  final _unavailableActivityDate = TextEditingController();
  final _activityFilters = _ActivityReportFilterPreview();
  final _exportController = MenuController();
  final _exportFocusNode = FocusNode();
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  final _notesAnchor = GlobalKey();
  bool _notesVisible = false;
  String _printOrientation = 'Portrait';
  bool _repeatPageHeader = false;
  bool _exportEscapeHandled = false;
  bool _closing = false;
  late final String _initialDraft;
  final _from = TextEditingController(
    text: formatAccountingInputDate(DateTime(DateTime.now().year)),
  );
  final _through = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );

  @override
  void initState() {
    super.initState();
    if (widget.method != null) {
      _presentation.title.text = 'Payment Method Activity';
      _activityFilters.enabled.add('Payment Method');
      _activityFilters.modes['Payment Method'] = '';
      _activityFilters.selections['Payment Method'] = {widget.method!.id};
    }
    _initialDraft = _draftSnapshot();
  }

  @override
  void dispose() {
    _activityFilters.dispose();
    _from.dispose();
    _through.dispose();
    _filters.dispose();
    _presentation.dispose();
    _exportFocusNode.dispose();
    _notes.dispose();
    _notesFocus.dispose();
    _unavailableActivityDate.dispose();
    super.dispose();
  }

  // Capture local working report facts, not caret/focus/disclosure state or
  // company preferences. Sort sets so undoing a choice is an unchanged draft.
  String _draftSnapshot() => jsonEncode([
    _columns.toList()..sort(),
    _filters.enabled.toList()..sort(),
    _filters.methods.toList()..sort(),
    _filters.presets,
    _filters.deleted,
    _filters.dates.map((key, value) => MapEntry(key, value.text)),
    _presentation.showLogo,
    _presentation.showCompanyName,
    _presentation.showTitle,
    _presentation.showDate,
    _presentation.showTime,
    _presentation.showPeriod,
    _presentation.companyName.text,
    _presentation.title.text,
    _presentation.header,
    _presentation.footer,
    _presentation.sortBy,
    _presentation.sortOrder,
    if (widget.method != null) ...[
      _activity.period,
      _activity.grouping,
      _activity.negative,
      _activity.divideBy1000,
      _activity.withoutCents,
      _activity.showInRed,
      _activity.columns,
      _from.text,
      _through.text,
      _unavailableActivityDate.text,
      _activityFilters.enabled.toList()..sort(),
      _activityFilters.modes,
      _activitySelectionSnapshot(),
      _activityFilters.presets,
      _activityFilters.dates.map((key, value) => MapEntry(key, value.text)),
      _activityFilters.text.map((key, value) => MapEntry(key, value.text)),
    ],
    _notes.text,
    _printOrientation,
    _repeatPageHeader,
  ]);

  Map<String, List<String>> _activitySelectionSnapshot() {
    // Filter controls lazily create empty selection sets while rendering.
    // Missing and empty both mean no choice; viewing them is not an edit.
    final keys =
        _activityFilters.selections.keys
            .where((key) => _activityFilters.selections[key]!.isNotEmpty)
            .toList()
          ..sort();
    return {
      for (final key in keys)
        key: _activityFilters.selections[key]!.toList()..sort(),
    };
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final discard =
          _draftSnapshot() == _initialDraft ||
          await AccountingDialog.confirmDiscardChanges(context);
      if (mounted && discard) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  Future<void> _customise() async {
    if (widget.method != null) {
      await _customiseActivity();
      return;
    }
    await AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      builder: (_) => _PaymentMethodReportColumns(
        columns: _columns,
        filters: _filters,
        presentation: _presentation,
        entries: widget.entries,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _saveCustomisationPreview() => AccountingDialog.showFixed<void>(
    context: context,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    builder: (_) =>
        _PaymentMethodSavedReportPreview(reportTitle: _presentation.title.text),
  );

  Future<void> _managementReportPreview() => AccountingDialog.showFixed<void>(
    context: context,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    builder: (_) => const _PaymentMethodManagementReportPreview(),
  );

  void _openNotes() {
    setState(() => _notesVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_notesVisible) return;
      _notesFocus.requestFocus();
      final noteContext = _notesAnchor.currentContext;
      if (noteContext != null) Scrollable.ensureVisible(noteContext);
    });
  }

  String get _activityPeriodHeading {
    if (_activity.period == 'Custom' &&
        parseAccountingInputDate(_from.text) != null &&
        parseAccountingInputDate(_through.text) != null) {
      return '${_from.text} – ${_through.text}';
    }
    return _activity.period;
  }

  Future<void> _printPreview() async {
    final next = await AccountingDialog.showFixed<String>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.normal,
          key: const ValueKey('payment-method-report-print-dialog'),
          title: 'Print, Email, Or Save As PDF',
          fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
          maxContentWidth: AccountingPopoutTokens.normalContentWidth,
          description: 'Report delivery preview. Generated report pages and delivery commands are not connected.',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountingSectionTitle(context, 'Report Print Settings'),
              const SizedBox(height: accountingContentInset),
              AccountingOrdinaryFields(
                fields: [
                  AccountingOrdinaryFieldSlot(
                    label: 'Orientation',
                    choices: const ['Portrait', 'Landscape'],
                    builder: (width) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Orientation',
                          alignToField: true,
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        AccountingSelector<String>(
                          controlKey: const ValueKey(
                            'payment-method-report-print-orientation',
                          ),
                          assignedWidth: width,
                          value: _printOrientation,
                          hintText: 'Orientation',
                          options: const [
                            AccountingSelectorOption(
                              value: 'Portrait',
                              label: 'Portrait',
                            ),
                            AccountingSelectorOption(
                              value: 'Landscape',
                              label: 'Landscape',
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) refresh(() => _printOrientation = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: accountingContentInset),
              Row(
                children: [
                  AccountingLeadingCheckbox(
                    checkboxKey: const ValueKey(
                      'payment-method-report-repeat-header',
                    ),
                    semanticLabel: 'Repeat Page Header',
                    value: _repeatPageHeader,
                    onChanged: (v) =>
                        refresh(() => _repeatPageHeader = v == true),
                  ),
                  Expanded(
                    child: Text(
                      'Repeat Page Header',
                      style: AccountingTypography.value(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: accountingContentInset),
              accountingHelperText(
                context,
                'Report pages are unavailable until the company report query and PDF renderer are connected.',
              ),
            ],
          ),
          actions: [
            AccountingButton.outline(
              context,
              key: const ValueKey('payment-method-report-print-email'),
              onPressed: () => Navigator.of(context).pop('email'),
              child: const Text('Email'),
            ),
            AccountingButton.outline(
              context,
              key: const ValueKey('payment-method-report-save-pdf'),
              onPressed: null,
              child: const Text('Save As PDF'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('payment-method-report-print-submit'),
              onPressed: null,
              child: const Text('Print'),
            ),
          ],
        ),
      ),
    );
    if (next == 'email' && mounted) {
      await AccountingDialog.showFixed<void>(
        context: context,
        contentWidth: AccountingPopoutTokens.normalContentWidth,
        builder: (_) => _PaymentMethodReportEmailPreview(
          reportTitle: _presentation.title.text.trim().isEmpty
              ? (widget.method == null
                    ? 'Payment Method List'
                    : 'Payment Method Activity')
              : _presentation.title.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.method != null;
    final currency = CurrencyPresentation.fromCode(widget.currencyCode)
        .amountSymbol;
    final activityColumns = [
      for (final id in _activity.columns)
        _paymentMethodActivityColumns.singleWhere((column) => column.id == id),
    ];
    final fluidColumn = activity
        ? activityColumns.indexWhere(
            (column) => column.role == _ActivityReportColumnRole.text,
          )
        : 0;
    final headers = activity
        ? [
            for (final column in activityColumns)
              column.role == _ActivityReportColumnRole.money
                  ? '${column.header} ($currency)'
                  : column.header,
          ]
        : ['Payment Method', ..._metadataColumns.where(_columns.contains)];
    final rows = activity
        ? <List<String>>[]
        : [
            for (final entry in widget.entries)
              [entry.name, for (final _ in headers.skip(1)) 'Unavailable'],
          ];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          key: ValueKey(
            activity
                ? 'payment-method-activity-report'
                : 'payment-method-list-report',
          ),
          title: activity
              ? '${widget.method!.name} · Activity'
              : 'Payment Method List',
          description: activity
              ? 'Design preview · Transaction queries, calculated date ranges and original-record links are not connected.'
              : 'Design preview · Maintained methods and metadata queries are not connected. Shown names are temporary preview facts.',
          maxContentWidth: AccountingPopoutTokens.customContentWidth,
          onClose: _close,
          closeKey: const ValueKey('payment-method-report-close'),
          content: SizedBox(
            width: AccountingPopoutTokens.customContentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activity) ...[
                  _activityFields(context, () {}),
                  const SizedBox(height: accountingContentInset),
                ],
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: accountingContentInset,
                  runSpacing: accountingContentInset,
                  children: [
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('payment-method-report-customise'),
                      onPressed: _customise,
                      child: const Text('Customise'),
                    ),
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('payment-method-report-notes'),
                      onPressed: _openNotes,
                      child: Text(_notesVisible ? 'Edit Notes' : 'Add Notes'),
                    ),
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('payment-method-report-email'),
                      onPressed: _printPreview,
                      child: const Text('Email'),
                    ),
                    Tooltip(
                      message: 'Saved report customisations are not connected.',
                      child: AccountingButton.outline(
                        context,
                        key: const ValueKey(
                          'payment-method-report-save-customisation',
                        ),
                        onPressed: _saveCustomisationPreview,
                        child: const Text('Save Customisation'),
                      ),
                    ),
                    _exportMenu(context),
                    Tooltip(
                      message:
                          'Printing requires a connected company report query.',
                      child: AccountingButton.outline(
                        context,
                        key: const ValueKey('payment-method-report-print'),
                        onPressed: _printPreview,
                        child: const Text('Print'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: accountingContentInset),
                ...[
                  if (_presentation.showCompanyName &&
                      _presentation.companyName.text.trim().isNotEmpty)
                    _reportHeading(context, _presentation.companyName.text),
                  if (_presentation.showTitle)
                    _reportHeading(context, _presentation.title.text),
                  if (activity && _presentation.showPeriod)
                    _reportHeading(context, _activityPeriodHeading),
                  if (_presentation.showLogo)
                    accountingHelperText(
                      context,
                      'The saved company logo is not connected to this report preview.',
                    ),
                  const SizedBox(height: accountingContentInset),
                ],
                if (headers.isNotEmpty)
                  AccountingCard.surface(
                    context,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: accountingContentInset,
                        right: accountingContentInset,
                        bottom: rows.isEmpty
                            ? 0
                            : accountingContentInset -
                                  accountingUndividedRowVerticalInset,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final headerStyle = AccountingTypography.tableHeader(
                            context,
                          );
                          final valueStyle = AccountingTypography.value(
                            context,
                          );
                          final widths = [
                            for (
                              var column = 0;
                              column < headers.length;
                              column++
                            )
                              [
                                    AccountingResponsive.measuredTextWidth(
                                      context,
                                      headers[column],
                                      headerStyle,
                                    ),
                                    for (final row in rows)
                                      AccountingResponsive.measuredTextWidth(
                                        context,
                                        row[column],
                                        valueStyle,
                                      ),
                                  ].reduce((a, b) => a > b ? a : b) +
                                  (column == headers.length - 1
                                      ? 0
                                      : accountingContentInset),
                          ];
                          final minimum = widths.fold<double>(
                            0,
                            (a, b) => a + b,
                          );
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            key: const ValueKey(
                              'payment-method-report-table-scroll',
                            ),
                            child: SizedBox(
                              width: minimum > constraints.maxWidth
                                  ? minimum
                                  : constraints.maxWidth,
                              child: Table(
                                key: const ValueKey(
                                  'payment-method-report-table',
                                ),
                                columnWidths: {
                                  for (
                                    var column = 0;
                                    column < headers.length;
                                    column++
                                  )
                                    column: column == fluidColumn
                                        ? const FlexColumnWidth()
                                        : FixedColumnWidth(widths[column]),
                                },
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AccountingTheme.of(context)
                                              .border,
                                        ),
                                      ),
                                    ),
                                    children: [
                                      for (
                                        var column = 0;
                                        column < headers.length;
                                        column++
                                      )
                                        accountingCompactTableCell(
                                          headers[column],
                                          style: headerStyle,
                                          textAlign:
                                              activity &&
                                                  activityColumns[column]
                                                          .role !=
                                                      _ActivityReportColumnRole
                                                          .text
                                              ? TextAlign.right
                                              : TextAlign.left,
                                          rightInset:
                                              column == headers.length - 1
                                              ? 0
                                              : accountingContentInset,
                                          verticalInset: accountingContentInset,
                                        ),
                                    ],
                                  ),
                                  for (
                                    var index = 0;
                                    index < rows.length;
                                    index++
                                  )
                                    TableRow(
                                      children: [
                                        for (
                                          var column = 0;
                                          column < headers.length;
                                          column++
                                        )
                                          accountingCompactTableCell(
                                            rows[index][column],
                                            style: valueStyle,
                                            textAlign:
                                                activity &&
                                                    activityColumns[column]
                                                            .role !=
                                                        _ActivityReportColumnRole
                                                            .text
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            rightInset:
                                                column == headers.length - 1
                                                ? 0
                                                : accountingContentInset,
                                            firstDataRow: index == 0,
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (activity && headers.isEmpty) ...[
                  const SizedBox(height: accountingContentInset),
                  accountingHelperText(
                    context,
                    'Select at least one report column.',
                  ),
                ],
                if (rows.isEmpty) ...[
                  const SizedBox(height: accountingContentInset),
                  accountingHelperText(
                    context,
                    activity
                        ? 'Transaction activity is unavailable until payment-method facts and the report query are connected.'
                        : 'The maintained payment-method list is not connected yet.',
                  ),
                ],
                if (_notesVisible) ...[
                  const SizedBox(height: accountingContentInset),
                  Column(
                    key: _notesAnchor,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: accountingFieldLabel(
                              context,
                              'Notes',
                              alignToField: true,
                            ),
                          ),
                          AccountingButton.ghost(
                            context,
                            key: const ValueKey(
                              'payment-method-report-close-notes',
                            ),
                            onPressed: () =>
                                setState(() => _notesVisible = false),
                            child: const Text('Close Notes'),
                          ),
                        ],
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      AccountingDescriptionField(
                        key: const ValueKey(
                          'payment-method-report-note-editor',
                        ),
                        controller: _notes,
                        focusNode: _notesFocus,
                        onEscape: _close,
                        role: AccountingDescriptionRole.memo,
                        maxLength: 4000,
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: 'Add notes or include additional info with your report',
                        ),
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      accountingHelperText(context, '4000 characters max'),
                    ],
                  ),
                ],
                if (_presentation.showDate || _presentation.showTime) ...[
                  const SizedBox(height: accountingContentInset),
                  Align(
                    alignment: _presentation.footerAlignment,
                    child: accountingHelperText(
                      context,
                      'Prepared date/time is unavailable until a company report query completes.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            AccountingButton.primary(
              context,
              key: const ValueKey('payment-method-report-run'),
              onPressed: null,
              child: const Text('Run Report'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityFields(BuildContext context, VoidCallback changed) =>
      AccountingOrdinaryFields(
        fields: [
          AccountingOrdinaryFieldSlot(
            label: 'Report Period',
            choices: paymentMethodActivityReportPeriodChoices,
            builder: (width) => _activitySelector(
              context,
              'Report Period',
              paymentMethodActivityReportPeriodChoices,
              _activity.period,
              width,
              (v) {
                setState(() => _activity.period = v);
                changed();
              },
            ),
          ),
          if (_activity.period != 'All Dates')
            for (final field in [
              ('From', _from),
              if (!_activity.period.startsWith('Since ')) ('Through', _through),
            ])
              AccountingOrdinaryFieldSlot(
                label: field.$1,
                date: true,
                contentSample: 'DD-MM-YYYY',
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accountingFieldLabel(context, field.$1, alignToField: true),
                    const SizedBox(height: accountingFieldLabelGap),
                    TextField(
                      key: ValueKey('payment-method-report-${field.$1}'),
                      controller: _activity.period == 'Custom'
                          ? field.$2
                          : _unavailableActivityDate,
                      enabled: _activity.period == 'Custom',
                      onChanged: (_) {
                        setState(() {});
                        changed();
                      },
                      inputFormatters: [const DateInputFormatter()],
                      decoration:
                          accountingSingleLineInputDecoration(
                            context,
                            hintText: _activity.period == 'Custom'
                                ? 'DD-MM-YYYY'
                                : 'Unavailable',
                          ).copyWith(
                            suffixIcon: accountingCalendarButton(
                              context,
                              controller: field.$2,
                              label: field.$1,
                              enabled: _activity.period == 'Custom',
                            ),
                          ),
                    ),
                  ],
                ),
              ),
          AccountingOrdinaryFieldSlot(
            label: 'Group By',
            choices: paymentMethodActivityReportGroupingChoices,
            builder: (width) => _activitySelector(
              context,
              'Group By',
              paymentMethodActivityReportGroupingChoices,
              _activity.grouping,
              width,
              (v) {
                setState(() => _activity.grouping = v);
                changed();
              },
            ),
          ),
        ],
      );

  Widget _activitySelector(
    BuildContext context,
    String label,
    List<String> choices,
    String value,
    double width,
    ValueChanged<String> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(context, label, alignToField: true),
      const SizedBox(height: accountingFieldLabelGap),
      AccountingSelector<String>(
        controlKey: ValueKey('payment-method-activity-$label'),
        assignedWidth: width,
        options: [
          for (final choice in choices)
            AccountingSelectorOption(value: choice, label: choice),
        ],
        value: value,
        hintText: label,
        onChanged: (v) {
          if (v != null) changed(v);
        },
      ),
    ],
  );

  Future<void> _customiseActivity() => AccountingDialog.showFixed<void>(
    context: context,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) {
        void change(VoidCallback update) {
          setState(update);
          refresh(() {});
        }

        Widget check(
          String label,
          bool value,
          ValueChanged<bool> update, {
          double verticalInset = accountingUndividedRowVerticalInset,
        }) => Padding(
          padding: EdgeInsets.symmetric(vertical: verticalInset),
          child: Row(
            children: [
              AccountingLeadingCheckbox(
                checkboxKey: ValueKey('payment-method-activity-$label'),
                undividedRow: true,
                semanticLabel: label,
                value: value,
                onChanged: (v) => change(() => update(v == true)),
              ),
              Expanded(
                child: Text(label, style: AccountingTypography.value(context)),
              ),
            ],
          ),
        );
        return AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: 'Customise Activity Report',
          description: 'Preview options only. Report queries, calculated date ranges and saved customisations are not connected. Personal preferences are unchanged.',
          fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
          maxContentWidth: AccountingPopoutTokens.normalContentWidth,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountingSectionTitle(context, 'General'),
              const SizedBox(height: accountingContentInset),
              _activityFields(context, () => refresh(() {})),
              if (_activity.period != 'Custom' &&
                  _activity.period != 'All Dates') ...[
                const SizedBox(height: accountingContentInset),
                accountingHelperText(
                  context,
                  'Calculated period dates are unavailable until the date-range command is connected; custom dates are retained.',
                ),
              ],
              const SizedBox(height: accountingContentInset),
              accountingSectionTitle(context, 'Number Format'),
              const SizedBox(height: accountingContentInset),
              check(
                'Divide By 1000',
                _activity.divideBy1000,
                (v) => _activity.divideBy1000 = v,
              ),
              check(
                'Without Cents',
                _activity.withoutCents,
                (v) => _activity.withoutCents = v,
              ),
              const SizedBox(height: accountingContentInset),
              AccountingOrdinaryFields(
                fields: [
                  AccountingOrdinaryFieldSlot(
                    label: 'Negative Numbers',
                    choices: const ['-100', '(100)', '100-'],
                    builder: (width) => _activitySelector(
                      context,
                      'Negative Numbers',
                      const ['-100', '(100)', '100-'],
                      _activity.negative,
                      width,
                      (v) => change(() => _activity.negative = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: accountingContentInset),
              check(
                'Show In Red',
                _activity.showInRed,
                (v) => _activity.showInRed = v,
              ),
              const SizedBox(height: accountingContentInset),
              accountingSectionTitle(context, 'Columns'),
              const SizedBox(height: accountingContentInset),
              accountingHelperText(
                context,
                'Select columns; drag a selected label to reorder.',
              ),
              const SizedBox(height: accountingContentInset),
              _paymentMethodReportCheckboxRows(
                context,
                [
                  for (final id in _activity.columns)
                    _paymentMethodActivityColumns
                        .singleWhere((column) => column.id == id)
                        .label,
                  for (final column in _paymentMethodActivityColumns)
                    if (!_activity.columns.contains(column.id)) column.label,
                ],
                (label) {
                  final column = _paymentMethodActivityColumns.singleWhere(
                    (column) => column.label == label,
                  );
                  if (_activity.columns.contains(column.id)) {
                    return _activityColumnRow(
                      context,
                      column.id,
                      change,
                      (name, value, update) =>
                          check(name, value, update, verticalInset: 0),
                    );
                  }
                  return check(label, false, (value) {
                    if (value) _activity.columns.add(column.id);
                  }, verticalInset: 0);
                },
                maximumFieldsPerRow: 3,
              ),
              const SizedBox(height: accountingContentInset),
              _activityFilterFields(context, change),
              _PaymentMethodReportPresentationControls(
                presentation: _presentation,
                onChanged: () => setState(() {}),
                includeReportPeriod: true,
                sortByChoices: paymentMethodActivityReportSortChoices,
              ),
            ],
          ),
          actions: [
            AccountingButton.primary(
              context,
              key: const ValueKey('payment-method-activity-options-back'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back To Report'),
            ),
          ],
        );
      },
    ),
  );

  List<(String, String)> _activityFilterChoices(String name) => switch (name) {
    'Payment Method' => [
      for (final e in widget.entries) (e.id, e.name),
      if (widget.method != null &&
          !widget.entries.any((e) => e.id == widget.method!.id))
        (widget.method!.id, widget.method!.name),
    ],
    'Transaction Type' => [
      for (final name in _activityTransactionTypeChoices) (name, name),
    ],
    _ => const [], // Maintained directories must supply real company-owned IDs.
  };

  Widget _activityFilterFields(
    BuildContext context,
    void Function(VoidCallback) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingSectionTitle(context, 'Filters'),
      const SizedBox(height: accountingContentInset),
      accountingHelperText(
        context,
        'Maintained account, party, term and product choices are unavailable in this preview.',
      ),
      const SizedBox(height: accountingContentInset),
      AccountingOrdinaryFields(
        fields: [
          for (final name in paymentMethodActivityFilterNames)
            AccountingOrdinaryFieldSlot(
              label: name,
              choices: _activityFilters.presets.containsKey(name)
                  ? (name == 'Due Date'
                        ? paymentMethodActivityReportPeriodChoices
                        : paymentMethodReportMetadataDateChoices)
                  : _activityFilters.text.containsKey(name)
                  ? const []
                  : [
                      ..._activityFilterAggregates[name]!,
                      'Select All',
                      for (final c in _activityFilterChoices(name)) c.$2,
                    ],
              contentSample: name == 'Amount' ? '100.00' : name,
              builder: (width) => Column(
                key: ValueKey('payment-method-activity-filter-field-$name'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: accountingUndividedRowVerticalInset,
                    ),
                    child: Row(
                      children: [
                        AccountingLeadingCheckbox(
                          checkboxKey: ValueKey(
                            'payment-method-activity-filter-enable-$name',
                          ),
                          undividedRow: true,
                          semanticLabel: '$name filter',
                          value: _activityFilters.enabled.contains(name),
                          onChanged: (v) => change(
                            () => v == true
                                ? _activityFilters.enabled.add(name)
                                : _activityFilters.enabled.remove(name),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            name,
                            style: AccountingTypography.fieldLabel(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  if (_activityFilters.text.containsKey(name))
                    TextField(
                      key: ValueKey(
                        'payment-method-activity-filter-text-$name',
                      ),
                      controller: _activityFilters.text[name],
                      decoration: accountingSingleLineInputDecoration(
                        context,
                        hintText: name,
                      ),
                      // Amount here is a report predicate, not a transactional
                      // money editor. Preserve text criteria; never apply digit growth.
                      onChanged: (_) =>
                          change(() => _activityFilters.enabled.add(name)),
                    )
                  else if (_activityFilters.presets.containsKey(name))
                    AccountingSelector<String>(
                      controlKey: ValueKey(
                        'payment-method-activity-filter-value-$name',
                      ),
                      assignedWidth: width,
                      options: [
                        for (final value
                            in name == 'Due Date'
                                ? paymentMethodActivityReportPeriodChoices
                                : paymentMethodReportMetadataDateChoices)
                          AccountingSelectorOption(value: value, label: value),
                      ],
                      value: _activityFilters.presets[name],
                      hintText: name,
                      onChanged: (v) {
                        if (v != null) {
                          change(() {
                            _activityFilters.presets[name] = v;
                            _activityFilters.enabled.add(name);
                          });
                        }
                      },
                    )
                  else
                    _activityMultipleFilter(context, name, width, change),
                ],
              ),
            ),
        ],
      ),
      for (final name in _activityFilters.presets.keys)
        if (_activityFilters.presets[name] == 'Custom')
          _activityFilterCustomDates(context, name),
    ],
  );

  Widget _activityMultipleFilter(
    BuildContext context,
    String name,
    double width,
    void Function(VoidCallback) change,
  ) {
    final choices = _activityFilterChoices(name);
    final values = _activityFilters.selections.putIfAbsent(
      name,
      () => <String>{},
    );
    final multiple = !['Cleared', 'A/R Paid', 'A/P Paid'].contains(name);
    final mode = _activityFilters.modes[name]!;
    final selectedLabel = mode.isNotEmpty
        ? null
        : values.length == 1
        ? choices.singleWhere((c) => c.$1 == values.single).$2
        : accountingSelectorHintText('Select Multiple ...');
    return AccountingSelector<String>(
      controlKey: ValueKey('payment-method-activity-filter-value-$name'),
      searchKey: ValueKey('payment-method-activity-filter-search-$name'),
      assignedWidth: width,
      value: mode.isEmpty ? null : 'mode:$mode',
      displayLabel: selectedLabel,
      hintText: name,
      options: [
        for (final value in _activityFilterAggregates[name]!)
          AccountingSelectorOption(
            value: 'mode:$value',
            label: value,
            key: ValueKey(
              'payment-method-activity-filter-option-$name-mode:$value',
            ),
          ),
        if (multiple)
          AccountingSelectorOption(
            value: 'all',
            label: 'Select All',
            key: ValueKey('payment-method-activity-filter-option-$name-all'),
            enabled: choices.isNotEmpty,
            checked: choices.isNotEmpty && values.length == choices.length,
          ),
        for (final c in choices)
          AccountingSelectorOption(
            value: 'item:${c.$1}',
            label: c.$2,
            key: ValueKey(
              'payment-method-activity-filter-option-$name-item:${c.$1}',
            ),
            checked: values.contains(c.$1),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        change(() {
          _activityFilters.enabled.add(name);
          if (v.startsWith('mode:')) {
            _activityFilters.modes[name] = v.substring(5);
            values.clear();
          } else {
            _activityFilters.modes[name] = '';
            if (v == 'all') {
              final allSelected = values.length == choices.length;
              values.clear();
              if (!allSelected) values.addAll(choices.map((c) => c.$1));
            } else {
              final id = v.substring(5);
              if (!values.remove(id)) values.add(id);
            }
          }
        });
      },
    );
  }

  Widget _activityFilterCustomDates(BuildContext context, String name) =>
      Column(
        key: ValueKey('payment-method-activity-filter-dates-$name'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: accountingContentInset),
          accountingSectionTitle(context, '$name · Custom'),
          const SizedBox(height: accountingContentInset),
          AccountingOrdinaryFields(
            fields: [
              for (final direction in ['From', 'Through'])
                AccountingOrdinaryFieldSlot(
                  label: direction,
                  date: true,
                  contentSample: 'DD-MM-YYYY',
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        direction,
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        key: ValueKey(
                          'payment-method-activity-filter-$name-$direction',
                        ),
                        controller: _activityFilters.dates['$name-$direction'],
                        inputFormatters: [const DateInputFormatter()],
                        decoration:
                            accountingSingleLineInputDecoration(
                              context,
                              hintText: 'DD-MM-YYYY',
                            ).copyWith(
                              suffixIcon: accountingCalendarButton(
                                context,
                                controller:
                                    _activityFilters.dates['$name-$direction']!,
                                label: '$name $direction',
                                enabled: true,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );

  Widget _activityColumnRow(
    BuildContext context,
    String id,
    void Function(VoidCallback) change,
    Widget Function(String, bool, ValueChanged<bool>) check,
  ) {
    final column = _paymentMethodActivityColumns.singleWhere((c) => c.id == id);
    Widget row() => check(column.label, true, (v) {
      if (!v) {
        _activity.columns.remove(id);
      }
    });
    void move(int delta) => change(() {
      final current = _activity.columns.indexOf(id);
      final other = current + delta;
      if (current < 0 || other < 0 || other >= _activity.columns.length) return;
      _activity.columns.removeAt(current);
      _activity.columns.insert(other, id);
    });
    return Semantics(
      customSemanticsActions: {
        if (_activity.columns.indexOf(id) > 0)
          CustomSemanticsAction(label: 'Move ${column.label} Up'): () =>
              move(-1),
        if (_activity.columns.indexOf(id) < _activity.columns.length - 1)
          CustomSemanticsAction(label: 'Move ${column.label} Down'): () =>
              move(1),
      },
      child: LayoutBuilder(
        builder: (context, constraints) => DragTarget<String>(
          key: ValueKey('payment-method-activity-column-row-$id'),
          onWillAcceptWithDetails: (d) =>
              d.data != id && _activity.columns.contains(d.data),
          onAcceptWithDetails: (d) => change(() {
            if (!_activity.columns.contains(id) ||
                !_activity.columns.contains(d.data)) {
              return;
            }
            _activity.columns.remove(d.data);
            _activity.columns.insert(_activity.columns.indexOf(id), d.data);
          }),
          builder: (context, candidates, rejected) => Draggable<String>(
            data: id,
            feedback: Material(
              color: AccountingTheme.of(context).card,
              child: SizedBox(width: constraints.maxWidth, child: row()),
            ),
            childWhenDragging: Opacity(opacity: 0, child: row()),
            child: MouseRegion(cursor: SystemMouseCursors.grab, child: row()),
          ),
        ),
      ),
    );
  }

  Widget _reportHeading(BuildContext context, String text) => Align(
    alignment: _presentation.headerAlignment,
    child: Text(text, style: AccountingTypography.sectionTitle(context)),
  );

  Widget _exportMenu(BuildContext context) {
    // CSV remains Audyt's existing export option. The working classic
    // reference exposes Excel/PDF and the management-report entry.
    const formats = ['Excel', 'PDF', 'CSV', 'Add To Management Reports'];
    final width = accountingMenuContentWidth(context, [
      for (final format in formats) (label: format, adornmentWidth: 0.0),
    ]);
    return Focus(
      focusNode: _exportFocusNode,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            (_exportController.isOpen || _exportEscapeHandled)) {
          if (event is KeyDownEvent) {
            _exportEscapeHandled = true;
            _exportController.close();
          } else if (event is KeyUpEvent) {
            _exportEscapeHandled = false;
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AccountingMenuAnchor(
        controller: _exportController,
        onOpen: _exportFocusNode.requestFocus,
        menuWidth: width,
        style: accountingSelectorMenuStyle(context, width, 360),
        menuChildren: [
          for (final format in formats)
            MenuItemButton(
              key: ValueKey('payment-method-report-export-$format'),
              style: accountingActionMenuItemStyle(context),
              onPressed:
                  format == 'Add To Management Reports' && widget.method == null
                  ? () {
                      _exportController.close();
                      _managementReportPreview();
                    }
                  : format == 'PDF'
                  ? () {
                      _exportController.close();
                      _printPreview();
                    }
                  : null,
              child: Text(format),
            ),
        ],
        builder: (context, controller, child) => AccountingButton.outline(
          context,
          key: const ValueKey('payment-method-report-export'),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: const Text('Export'),
        ),
      ),
    );
  }
}

/// The directly inspected master-list management picker. The reference's
/// exclusive choices use Audyt's established selector, not new radio styling.
/// No reference-account report names or production Add command are inferred.
class _PaymentMethodManagementReportPreview extends StatefulWidget {
  const _PaymentMethodManagementReportPreview();

  @override
  State<_PaymentMethodManagementReportPreview> createState() =>
      _PaymentMethodManagementReportPreviewState();
}

class _PaymentMethodManagementReportPreviewState
    extends State<_PaymentMethodManagementReportPreview> {
  static const _create = 'Create A New Management Report';
  static const _existing = 'Add To An Existing Management Report';
  final _name = TextEditingController();
  String _action = _create;
  bool _closing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final dirty = _name.text.isNotEmpty || _action != _create;
      final discard =
          !dirty || await AccountingDialog.confirmDiscardChanges(context);
      if (mounted && discard) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        key: const ValueKey('payment-method-management-dialog'),
        title: 'Add To Management Reports',
        description: 'Management report preview. Report selection and adding are not available yet.',
        fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
        maxContentWidth: AccountingPopoutTokens.normalContentWidth,
        onClose: _close,
        closeKey: const ValueKey('payment-method-management-close'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingOrdinaryFields(
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: 'Action',
                  choices: const [_create, _existing],
                  builder: (width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Action',
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      AccountingSelector<String>(
                        controlKey: const ValueKey(
                          'payment-method-management-action',
                        ),
                        assignedWidth: width,
                        value: _action,
                        hintText: 'Action',
                        options: const [
                          AccountingSelectorOption(
                            value: _create,
                            label: _create,
                          ),
                          AccountingSelectorOption(
                            value: _existing,
                            label: _existing,
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _action = value);
                        },
                      ),
                    ],
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: _action == _create
                      ? 'Management Report Name'
                      : 'Management Report',
                  contentSample: _action == _create
                      ? (_name.text.isEmpty ? '0000000000' : _name.text)
                      : 'Management Report',
                  builder: (width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        _action == _create
                            ? 'Management Report Name'
                            : 'Management Report',
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      if (_action == _create)
                        TextField(
                          key: const ValueKey('payment-method-management-name'),
                          controller: _name,
                          decoration: accountingSingleLineInputDecoration(
                            context,
                          ),
                          onChanged: (_) => setState(() {}),
                        )
                      else
                        AccountingSelector<String>(
                          controlKey: const ValueKey(
                            'payment-method-management-existing',
                          ),
                          assignedWidth: width,
                          value: null,
                          hintText: 'Select Management Report',
                          options: const [],
                          emptyText: 'No management reports available',
                          helperText:
                              'Management reports are not available yet.',
                          onChanged: (_) {},
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Adding to management reports is not available yet.',
            child: AccountingButton.primary(
              context,
              key: const ValueKey('payment-method-management-add'),
              onPressed: null,
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared master/activity saved-report fields observed through both callers.
/// local draft does not create groups, share a report or change preferences.
class _PaymentMethodSavedReportPreview extends StatefulWidget {
  const _PaymentMethodSavedReportPreview({required this.reportTitle});
  final String reportTitle;

  @override
  State<_PaymentMethodSavedReportPreview> createState() =>
      _PaymentMethodSavedReportPreviewState();
}

class _PaymentMethodSavedReportPreviewState
    extends State<_PaymentMethodSavedReportPreview> {
  late final TextEditingController _name;
  final _groupName = TextEditingController();
  String _shareWith = 'None';
  bool _showNewGroup = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.reportTitle);
  }

  @override
  void dispose() {
    _name.dispose();
    _groupName.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final dirty =
          _name.text != widget.reportTitle ||
          _groupName.text.isNotEmpty ||
          _shareWith != 'None';
      final discard =
          !dirty || await AccountingDialog.confirmDiscardChanges(context);
      if (mounted && discard) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  AccountingOrdinaryFieldSlot _textSlot(
    String label,
    TextEditingController controller,
    String id,
  ) => AccountingOrdinaryFieldSlot(
    label: label,
    contentSample: controller.text.isEmpty ? '0000000000' : controller.text,
    builder: (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingFieldLabel(context, label, alignToField: true),
        const SizedBox(height: accountingFieldLabelGap),
        TextField(
          key: ValueKey('payment-method-saved-report-$id'),
          controller: controller,
          decoration: accountingSingleLineInputDecoration(context),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
  );

  Widget _nameField(
    String label,
    TextEditingController controller,
    String id,
  ) => AccountingOrdinaryFields(fields: [_textSlot(label, controller, id)]);

  Widget _newGroupFields() => LayoutBuilder(
    builder: (context, constraints) {
      final field = _textSlot('New Group Name', _groupName, 'group-name');
      final width = trialRows(
        constraints.maxWidth,
        [field.minimumWidth(context)],
        gap: AccountingResponsive.groupGap,
        preferEqual: true,
      ).single.widths.single;
      return Wrap(
        spacing: AccountingResponsive.groupGap,
        runSpacing: AccountingResponsive.groupGap,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(width: width, child: field.builder(width)),
          Tooltip(
            message: 'Maintained report groups are not connected.',
            child: AccountingButton.outline(
              context,
              key: const ValueKey('payment-method-saved-report-add-group'),
              onPressed: null,
              child: const Text('Add'),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        key: const ValueKey('payment-method-saved-report-dialog'),
        title: 'Save Customisation',
        description: 'Report customisation preview. Maintained groups, sharing and saving are not connected.',
        fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
        maxContentWidth: AccountingPopoutTokens.normalContentWidth,
        onClose: _close,
        closeKey: const ValueKey('payment-method-saved-report-close'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _nameField('Custom Report Name', _name, 'name'),
            const SizedBox(height: accountingContentInset),
            AccountingOrdinaryFields(
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: 'Add This Report To A Group',
                  choices: const ['None'],
                  builder: (width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Add This Report To A Group',
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      AccountingSelector<String>(
                        controlKey: const ValueKey(
                          'payment-method-saved-report-group',
                        ),
                        assignedWidth: width,
                        value: 'None',
                        hintText: 'Report Group',
                        semanticsLabel: 'Report Group',
                        options: [
                          AccountingSelectorOption(
                            value: '__add_group__',
                            label: 'Add New Group',
                            key: const ValueKey(
                              'payment-method-saved-report-new-group',
                            ),
                            leading: const AccountingAddIcon(),
                            leadingWidth: AccountingDismissIcon.canvasSize,
                            onPressed: () =>
                                setState(() => _showNewGroup = true),
                          ),
                          const AccountingSelectorOption(
                            value: 'None',
                            label: 'None',
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Share With',
                  choices: const ['All', 'None'],
                  builder: (width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Share With',
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      AccountingSelector<String>(
                        controlKey: const ValueKey(
                          'payment-method-saved-report-share',
                        ),
                        assignedWidth: width,
                        value: _shareWith,
                        hintText: 'Share With',
                        options: const [
                          AccountingSelectorOption(value: 'All', label: 'All'),
                          AccountingSelectorOption(
                            value: 'None',
                            label: 'None',
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _shareWith = value);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showNewGroup) ...[
              const SizedBox(height: accountingContentInset),
              _newGroupFields(),
            ],
          ],
        ),
        actions: [
          AccountingButton.primary(
            context,
            key: const ValueKey('payment-method-saved-report-save'),
            onPressed: null,
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// New report-delivery surface, reusing the existing popup/input/memo/action
/// and unsaved-work owners. No mail command, recipients or personal template is
/// inferred from the reference account; the final Send remains unavailable.
class _PaymentMethodReportEmailPreview extends StatefulWidget {
  const _PaymentMethodReportEmailPreview({required this.reportTitle});
  final String reportTitle;
  @override
  State<_PaymentMethodReportEmailPreview> createState() =>
      _PaymentMethodReportEmailPreviewState();
}

class _PaymentMethodReportEmailPreviewState
    extends State<_PaymentMethodReportEmailPreview> {
  late final Map<String, TextEditingController> _fields;
  late final Map<String, String> _opening;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _fields = {
      'To': TextEditingController(),
      'CC': TextEditingController(),
      'Subject': TextEditingController(
        text: 'Your ${widget.reportTitle} Report',
      ),
      'Body': TextEditingController(),
      'Report': TextEditingController(text: '${widget.reportTitle} Report'),
    };
    _opening = {for (final e in _fields.entries) e.key: e.value.text};
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final dirty = _fields.entries.any((e) => e.value.text != _opening[e.key]);
      final discard =
          !dirty || await AccountingDialog.confirmDiscardChanges(context);
      if (mounted && discard) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  Widget _textFields(List<String> names) => AccountingOrdinaryFields(
    fields: [
      for (final name in names)
        AccountingOrdinaryFieldSlot(
          label: name,
          contentSample: _fields[name]!.text.isEmpty
              ? '0000000000'
              : '${_fields[name]!.text}${name == 'Report' ? '.pdf' : ''}',
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountingFieldLabel(context, name, alignToField: true),
              const SizedBox(height: accountingFieldLabelGap),
              TextField(
                key: ValueKey('payment-method-report-email-$name'),
                controller: _fields[name],
                decoration: accountingSingleLineInputDecoration(context)
                    .copyWith(suffixText: name == 'Report' ? '.pdf' : null),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        key: const ValueKey('payment-method-report-email-dialog'),
        title: 'Email Report',
        description: 'Email preview. The generated attachment and sending are not available yet.',
        fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
        maxContentWidth: AccountingPopoutTokens.normalContentWidth,
        onClose: _close,
        closeKey: const ValueKey('payment-method-report-email-close'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _textFields(const ['To', 'CC']),
            const SizedBox(height: accountingContentInset),
            _textFields(const ['Subject']),
            const SizedBox(height: accountingContentInset),
            accountingFieldLabel(context, 'Body', alignToField: true),
            const SizedBox(height: accountingFieldLabelGap),
            AccountingDescriptionField(
              key: const ValueKey('payment-method-report-email-Body'),
              controller: _fields['Body'],
              onEscape: _close,
              decoration: accountingSingleLineInputDecoration(context),
            ),
            const SizedBox(height: accountingContentInset),
            _textFields(const ['Report']),
          ],
        ),
        actions: [
          AccountingButton.primary(
            context,
            key: const ValueKey('payment-method-report-email-send'),
            onPressed: null,
            child: const Text('Send'),
          ),
        ],
      ),
    ),
  );
}

Widget _paymentMethodReportCheckboxRows(
  BuildContext context,
  List<String> labels,
  Widget Function(String label) builder, {
  int maximumFieldsPerRow = 4,
}) => LayoutBuilder(
  builder: (context, constraints) => AccountingOrdinaryFieldRows(
    width: constraints.maxWidth,
    minima: [
      for (final label in labels)
        18 +
            accountingContentInset +
            AccountingResponsive.measuredTextWidth(
              context,
              label,
              AccountingTypography.value(context),
            ),
    ],
    preferEqual: true,
    maximumFieldsPerRow: maximumFieldsPerRow,
    fieldBuilder: (index, width) => builder(labels[index]),
  ),
);

class _PaymentMethodReportColumns extends StatefulWidget {
  const _PaymentMethodReportColumns({
    required this.columns,
    required this.onChanged,
    required this.filters,
    required this.presentation,
    required this.entries,
  });
  final Set<String> columns;
  final VoidCallback onChanged;
  final _PaymentMethodReportFilterPreview filters;
  final _PaymentMethodReportPresentationPreview presentation;
  final List<PaymentMethodDirectoryPreviewEntry> entries;

  @override
  State<_PaymentMethodReportColumns> createState() =>
      _PaymentMethodReportColumnsState();
}

class _PaymentMethodReportColumnsState
    extends State<_PaymentMethodReportColumns> {
  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  Widget _check(
    String name,
    bool value,
    ValueChanged<bool?> onChanged, {
    bool heading = false,
    bool enabled = true,
    String? controlId,
  }) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: accountingUndividedRowVerticalInset,
    ),
    child: Row(
      children: [
        AccountingLeadingCheckbox(
          checkboxKey: ValueKey(
            'payment-method-report-filter-${controlId ?? name}',
          ),
          undividedRow: true,
          semanticLabel: name,
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
        Expanded(
          child: Text(
            name,
            style: heading
                ? AccountingTypography.fieldLabel(context)
                : AccountingTypography.value(context),
          ),
        ),
      ],
    ),
  );

  Widget _filterSelector(
    String name,
    List<String> choices,
    String value,
    ValueChanged<String> update,
    double assignedWidth,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _check(
        name,
        widget.filters.enabled.contains(name),
        (v) => _changed(
          () => v == true
              ? widget.filters.enabled.add(name)
              : widget.filters.enabled.remove(name),
        ),
        heading: true,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      AccountingSelector<String>(
        assignedWidth: assignedWidth,
        controlKey: ValueKey('payment-method-report-filter-value-$name'),
        options: [
          for (final choice in choices)
            AccountingSelectorOption(value: choice, label: choice),
        ],
        value: value,
        onChanged: (v) {
          if (v == null) return;
          _changed(() {
            update(v);
            widget.filters.enabled.add(name);
          });
        },
        hintText: name,
        semanticsLabel: '$name report filter',
      ),
    ],
  );

  Widget _customDates(String name) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: accountingContentInset),
      accountingSectionTitle(context, '$name · Custom'),
      const SizedBox(height: accountingContentInset),
      AccountingOrdinaryFields(
        fields: [
          for (final direction in ['From', 'Through'])
            AccountingOrdinaryFieldSlot(
              label: direction,
              date: true,
              contentSample: 'DD-MM-YYYY',
              builder: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  accountingFieldLabel(context, direction, alignToField: true),
                  const SizedBox(height: accountingFieldLabelGap),
                  TextField(
                    key: ValueKey(
                      'payment-method-report-filter-$name-$direction',
                    ),
                    controller: widget.filters.dates['$name-$direction'],
                    inputFormatters: [const DateInputFormatter()],
                    decoration:
                        accountingSingleLineInputDecoration(
                          context,
                          hintText: 'DD-MM-YYYY',
                        ).copyWith(
                          suffixIcon: accountingCalendarButton(
                            context,
                            controller:
                                widget.filters.dates['$name-$direction']!,
                            label: '$name $direction',
                            enabled: true,
                          ),
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.normal,
    title: 'Customise Report',
    description: 'Preview options only. Filters and sorting are not applied to a company query; personal report preferences are unchanged.',
    fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
    maxContentWidth: AccountingPopoutTokens.normalContentWidth,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingSectionTitle(context, 'Columns'),
        const SizedBox(height: accountingContentInset),
        _paymentMethodReportCheckboxRows(
          context,
          _PaymentMethodReportPreviewState._metadataColumns,
          (name) => Row(
            children: [
              AccountingLeadingCheckbox(
                checkboxKey: ValueKey('payment-method-report-column-$name'),
                undividedRow: true,
                semanticLabel: name,
                value: widget.columns.contains(name),
                onChanged: (value) => _changed(
                  () => value == true
                      ? widget.columns.add(name)
                      : widget.columns.remove(name),
                ),
              ),
              Expanded(
                child: Text(name, style: AccountingTypography.value(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: accountingContentInset),
        accountingSectionTitle(context, 'Filters'),
        const SizedBox(height: accountingContentInset),
        _check(
          'Payment Method',
          widget.filters.enabled.contains('Payment Method'),
          (v) => _changed(
            () => v == true
                ? widget.filters.enabled.add('Payment Method')
                : widget.filters.enabled.remove('Payment Method'),
          ),
          heading: true,
        ),
        if (widget.filters.enabled.contains('Payment Method')) ...[
          if (widget.entries.isEmpty)
            accountingHelperText(
              context,
              'The maintained payment-method choices are not connected yet.',
            )
          else ...[
            _check(
              'Select All',
              widget.filters.methods.length == widget.entries.length,
              (v) => _changed(() {
                widget.filters.methods.clear();
                if (v == true) {
                  widget.filters.methods.addAll(
                    widget.entries.map((e) => e.id),
                  );
                }
              }),
            ),
            for (final entry in widget.entries)
              _check(
                entry.name,
                widget.filters.methods.contains(entry.id),
                (v) => _changed(
                  () => v == true
                      ? widget.filters.methods.add(entry.id)
                      : widget.filters.methods.remove(entry.id),
                ),
                controlId: 'method-${entry.id}',
              ),
          ],
        ],
        const SizedBox(height: accountingContentInset),
        AccountingOrdinaryFields(
          fields: [
            for (final name in ['Created Date', 'Last Modified Date'])
              AccountingOrdinaryFieldSlot(
                label: name,
                choices: paymentMethodReportMetadataDateChoices,
                builder: (width) => _filterSelector(
                  name,
                  paymentMethodReportMetadataDateChoices,
                  widget.filters.presets[name]!,
                  (v) => widget.filters.presets[name] = v,
                  width,
                ),
              ),
            AccountingOrdinaryFieldSlot(
              label: 'Deleted',
              choices: const ['All', 'Deleted', 'Not Deleted'],
              builder: (width) => _filterSelector(
                'Deleted',
                const ['All', 'Deleted', 'Not Deleted'],
                widget.filters.deleted,
                (v) => widget.filters.deleted = v,
                width,
              ),
            ),
          ],
        ),
        for (final name in ['Created Date', 'Last Modified Date'])
          if (widget.filters.presets[name] == 'Custom') _customDates(name),
        _PaymentMethodReportPresentationControls(
          presentation: widget.presentation,
          onChanged: widget.onChanged,
          sortByChoices: [
            'Default',
            ..._PaymentMethodReportPreviewState._metadataColumns,
          ],
        ),
      ],
    ),
    actions: [
      AccountingButton.primary(
        context,
        key: const ValueKey('payment-method-report-columns-back'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back To Report'),
      ),
    ],
  );
}

/// One existing presentation owner shared by master and activity report routes.
/// Report Period and the sort catalogue are explicit caller roles; report-header
/// responsive rows include the explicitly approved header and Date/Time groups.
class _PaymentMethodReportPresentationControls extends StatefulWidget {
  const _PaymentMethodReportPresentationControls({
    required this.presentation,
    required this.onChanged,
    required this.sortByChoices,
    this.includeReportPeriod = false,
  });
  final _PaymentMethodReportPresentationPreview presentation;
  final VoidCallback onChanged;
  final List<String> sortByChoices;
  final bool includeReportPeriod;
  @override
  State<_PaymentMethodReportPresentationControls> createState() =>
      _PaymentMethodReportPresentationControlsState();
}

class _PaymentMethodReportPresentationControlsState
    extends State<_PaymentMethodReportPresentationControls> {
  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  Widget _check(
    String name,
    bool value,
    ValueChanged<bool?> onChanged, {
    bool heading = false,
    bool enabled = true,
    String? controlId,
    double verticalInset = accountingUndividedRowVerticalInset,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: verticalInset),
    child: Row(
      children: [
        AccountingLeadingCheckbox(
          checkboxKey: ValueKey(
            'payment-method-report-filter-${controlId ?? name}',
          ),
          undividedRow: true,
          semanticLabel: name,
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
        Expanded(
          child: Text(
            name,
            style: heading
                ? AccountingTypography.fieldLabel(context)
                : AccountingTypography.value(context),
          ),
        ),
      ],
    ),
  );

  Widget _headerFooter() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: accountingContentInset),
      accountingSectionTitle(context, 'Header/Footer'),
      const SizedBox(height: accountingContentInset),
      _headerCheckboxes(),
      if (widget.includeReportPeriod)
        _check(
          'Report Period',
          widget.presentation.showPeriod,
          (v) => _changed(() => widget.presentation.showPeriod = v == true),
        ),
      if (widget.presentation.showCompanyName ||
          widget.presentation.showTitle) ...[
        const SizedBox(height: accountingContentInset),
        AccountingOrdinaryFields(
          fields: [
            for (final name in [
              if (widget.presentation.showCompanyName) 'Company Name',
              if (widget.presentation.showTitle) 'Report Title',
            ])
              AccountingOrdinaryFieldSlot(
                label: name,
                contentSample: name,
                builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accountingFieldLabel(context, name, alignToField: true),
                    const SizedBox(height: accountingFieldLabelGap),
                    TextField(
                      key: ValueKey('payment-method-report-heading-$name'),
                      controller: name == 'Company Name'
                          ? widget.presentation.companyName
                          : widget.presentation.title,
                      decoration: accountingSingleLineInputDecoration(
                        context,
                        hintText: name,
                      ),
                      onChanged: (_) => widget.onChanged(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: accountingContentInset),
      _paymentMethodReportCheckboxRows(
        context,
        const ['Date Prepared', 'Time Prepared'],
        (name) => _check(
          name,
          name == 'Date Prepared'
              ? widget.presentation.showDate
              : widget.presentation.showTime,
          (v) => _changed(() {
            if (name == 'Date Prepared') {
              widget.presentation.showDate = v == true;
            } else {
              widget.presentation.showTime = v == true;
            }
          }),
          verticalInset: 0,
        ),
      ),
      // These original value/label line boxes add 6px beyond the painted square
      // and heading. Preserve the user's 20px visible gap at this owner only.
      const SizedBox(height: accountingContentInset - 6),
      AccountingOrdinaryFields(
        fields: [
          for (final name in ['Header Alignment', 'Footer Alignment'])
            AccountingOrdinaryFieldSlot(
              label: name,
              choices: _PaymentMethodReportPresentationPreview.alignments,
              builder: (width) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountingFieldLabel(context, name, alignToField: true),
                  const SizedBox(height: accountingFieldLabelGap),
                  AccountingSelector<String>(
                    controlKey: ValueKey('payment-method-report-$name'),
                    assignedWidth: width,
                    options: [
                      for (final value
                          in _PaymentMethodReportPresentationPreview.alignments)
                        AccountingSelectorOption(value: value, label: value),
                    ],
                    value: name == 'Header Alignment'
                        ? widget.presentation.header
                        : widget.presentation.footer,
                    hintText: name,
                    onChanged: (v) {
                      if (v == null) return;
                      _changed(() {
                        if (name == 'Header Alignment') {
                          widget.presentation.header = v;
                        } else {
                          widget.presentation.footer = v;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  // Explicit scope: header options, the master metadata-column group and the
  // Date/Time Prepared pair. Filter enablers and method lists keep their owners.
  Widget _headerCheckboxes() {
    final options = <(String, bool, ValueChanged<bool?>)>[
      (
        'Show Logo',
        widget.presentation.showLogo,
        (v) => _changed(() => widget.presentation.showLogo = v == true),
      ),
      (
        'Company Name',
        widget.presentation.showCompanyName,
        (v) => _changed(() => widget.presentation.showCompanyName = v == true),
      ),
      (
        'Report Title',
        widget.presentation.showTitle,
        (v) => _changed(() => widget.presentation.showTitle = v == true),
      ),
    ];
    return _paymentMethodReportCheckboxRows(
      context,
      [for (final option in options) option.$1],
      (name) {
        final option = options.firstWhere((option) => option.$1 == name);
        return _check(option.$1, option.$2, option.$3);
      },
    );
  }

  Widget _sorting() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: accountingContentInset),
      accountingSectionTitle(context, 'Sorting'),
      const SizedBox(height: accountingContentInset),
      AccountingOrdinaryFields(
        fields: [
          for (final name in ['Sort By', 'Sort Order'])
            AccountingOrdinaryFieldSlot(
              label: name,
              choices: _sortChoices(name),
              builder: (width) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountingFieldLabel(context, name, alignToField: true),
                  const SizedBox(height: accountingFieldLabelGap),
                  AccountingSelector<String>(
                    controlKey: ValueKey('payment-method-report-$name'),
                    assignedWidth: width,
                    options: [
                      for (final value in _sortChoices(name))
                        AccountingSelectorOption(value: value, label: value),
                    ],
                    value: name == 'Sort By'
                        ? widget.presentation.sortBy
                        : widget.presentation.sortOrder,
                    hintText: name,
                    onChanged: (v) {
                      if (v == null) return;
                      _changed(() {
                        if (name == 'Sort By') {
                          widget.presentation.sortBy = v;
                        } else {
                          widget.presentation.sortOrder = v;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  List<String> _sortChoices(String name) => name == 'Sort By'
      ? widget.sortByChoices
      : const ['Ascending Order', 'Descending Order'];

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('payment-method-report-presentation'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_headerFooter(), _sorting()],
  );
}

/// Working-reference choices belong to master metadata filters only. They do
/// not alter ordinary transaction calendars, report periods or saved defaults.
const paymentMethodReportMetadataDateChoices = [
  'All Dates',
  'Custom',
  'Today',
  'This Week',
  'This Week-to-date',
  'This Month',
  'This Month-to-date',
  'This Quarter',
  'This Quarter-to-date',
  'This Year',
  'This Year-to-date',
  'This Year-to-last-month',
  'Yesterday',
  'Recent',
  'Last Week',
  'Last Week-to-date',
  'Last Month',
  'Last Month-to-date',
  'Last Quarter',
  'Last Quarter-to-date',
  'Last Year',
  'Last Year-to-date',
  'Since 30 Days Ago',
  'Since 60 Days Ago',
  'Since 90 Days Ago',
  'Since 365 Days Ago',
];

/// Verified activity catalogue. Future periods belong to this report only;
/// metadata selectors retain their separate 26-choice catalogue.
const paymentMethodActivityReportPeriodChoices = [
  ...paymentMethodReportMetadataDateChoices,
  'Next Week',
  'Next 4 Weeks',
  'Next Month',
  'Next Quarter',
  'Next Year',
];

// Working classic sorting catalogue; tax labels reuse Audyt's existing
// Tax Amount/Tax Code terms, not a claim of GST calculation parity.
const paymentMethodActivityReportSortChoices = [
  'Default',
  'A/P Paid',
  'A/R Paid',
  'Account',
  'Adj',
  'Clr',
  'Create Date',
  'Created By',
  'Customer',
  'Date',
  'Employee',
  'Tax Amount',
  'Tax Code',
  'Invoice Date',
  'Last Modified',
  'Last Modified By',
  'Memo/Description',
  'Name',
  'No.',
  'Online Banking',
  'Product/Service',
  'Qty',
  'Split',
  'Supplier',
  'Taxable Amount',
  'Transaction Type',
  'Unit Price/Rate',
];

const paymentMethodActivityReportGroupingChoices = [
  'None',
  'Account',
  'Transaction Type',
  'Customer',
  'Supplier',
  'Employee',
  'Product/Service',
  'Payment Method',
  'Day',
  'Week',
  'Month',
  'Quarter',
  'Year',
];

enum _ActivityReportColumnRole { text, number, money }

class _ActivityReportColumn {
  const _ActivityReportColumn(
    this.id,
    this.label,
    this.header, [
    this.role = _ActivityReportColumnRole.text,
  ]);
  final String id, label, header;
  final _ActivityReportColumnRole role;
}

// Classic option labels map to Audyt's existing table headings. Tax fields
// retain Audyt's Tax Code/Tax Amount terms; no GST calculation is implied.
const _paymentMethodActivityColumns = [
  _ActivityReportColumn('date', 'Date', 'Transaction Date'),
  _ActivityReportColumn('type', 'Transaction Type', 'Transaction Type'),
  _ActivityReportColumn('number', 'No.', 'Number'),
  _ActivityReportColumn('name', 'Name', 'Name'),
  _ActivityReportColumn('description', 'Memo/Description', 'Description'),
  _ActivityReportColumn('account', 'Account', 'Account Name'),
  _ActivityReportColumn('split', 'Split', 'Split Account'),
  _ActivityReportColumn(
    'amount',
    'Amount',
    'Amount',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn(
    'balance',
    'Balance',
    'Balance',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn('adjustment', 'Adj', 'Adj'),
  _ActivityReportColumn('created-date', 'Create Date', 'Create Date'),
  _ActivityReportColumn('created-by', 'Created By', 'Created By'),
  _ActivityReportColumn('modified-date', 'Last Modified', 'Last Modified'),
  _ActivityReportColumn('modified-by', 'Last Modified By', 'Last Modified By'),
  _ActivityReportColumn('customer', 'Customer', 'Customer'),
  _ActivityReportColumn('supplier', 'Supplier', 'Supplier'),
  _ActivityReportColumn('employee', 'Employee', 'Employee'),
  _ActivityReportColumn('item', 'Product/Service', 'Product/Service'),
  _ActivityReportColumn(
    'quantity',
    'Qty',
    'Qty',
    _ActivityReportColumnRole.number,
  ),
  _ActivityReportColumn(
    'rate',
    'Unit Price/Rate',
    'Unit Price/Rate',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn('invoice-date', 'Invoice Date', 'Invoice Date'),
  _ActivityReportColumn('ar-paid', 'A/R Paid', 'A/R Paid'),
  _ActivityReportColumn('ap-paid', 'A/P Paid', 'A/P Paid'),
  _ActivityReportColumn('cleared', 'Clr', 'Clr'),
  _ActivityReportColumn(
    'debit',
    'Debit',
    'Debit',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn(
    'credit',
    'Credit',
    'Credit',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn('online-banking', 'Online Banking', 'Online Banking'),
  _ActivityReportColumn('tax-code', 'Tax Code', 'Tax Code'),
  _ActivityReportColumn(
    'tax-amount',
    'Tax Amount',
    'Tax Amount',
    _ActivityReportColumnRole.money,
  ),
  _ActivityReportColumn(
    'taxable-amount',
    'Taxable Amount',
    'Taxable Amount',
    _ActivityReportColumnRole.money,
  ),
];

// Observed classic report choices, not enabled accounting capabilities or saved
// company preferences. Query/type mappings and maintained choice IDs are pending.
const paymentMethodActivityFilterNames = [
  "Payment Method",
  "Transaction Type",
  "Distribution Account",
  "Account",
  "Name",
  "Customer",
  "Supplier",
  "Employee",
  "Terms",
  "Product/Service",
  "Due Date",
  "Created Date",
  "Last Modified Date",
  "Cleared",
  "A/R Paid",
  "A/P Paid",
  "Amount",
  "Memo",
  "No.",
];

const _activityFilterAggregates = <String, List<String>>{
  "Payment Method": ["All"],
  "Transaction Type": ["All", "Posting", "Non-Posting"],
  "Distribution Account": [
    "All",
    "Specified",
    "All Balance Sheet Accounts",
    "All Asset Accounts",
    "All Current Asset Accounts",
    "All Cash and cash equivalents Accounts",
    "All Trade and other receivables Accounts",
    "All Current assets Accounts",
    "All Property, plant and equipment Accounts",
    "All Non-current assets Accounts",
    "All Liability Accounts",
    "All Current Liability Accounts",
    "All Trade and other payables Accounts",
    "All Credit card Accounts",
    "All Current liabilities Accounts",
    "All Non-current liabilities Accounts",
    "All Owner's equity Accounts",
    "All Income/Expense Accounts",
    "All Income Accounts",
    "All Cost of sales Accounts",
    "All Expenses Accounts",
    "All Other income Accounts",
    "All Other expense Accounts",
  ],
  "Account": [
    "All",
    "All Balance Sheet Accounts",
    "All Asset Accounts",
    "All Current Asset Accounts",
    "All Cash and cash equivalents Accounts",
    "All Trade and other receivables Accounts",
    "All Current assets Accounts",
    "All Property, plant and equipment Accounts",
    "All Non-current assets Accounts",
    "All Liability Accounts",
    "All Current Liability Accounts",
    "All Trade and other payables Accounts",
    "All Credit card Accounts",
    "All Current liabilities Accounts",
    "All Non-current liabilities Accounts",
    "All Owner's equity Accounts",
  ],
  "Name": ["All", "Not Specified", "Specified"],
  "Customer": ["All", "Not Specified", "Specified"],
  "Supplier": ["All", "Not Specified", "Specified"],
  "Employee": ["All"],
  "Terms": ["All", "Not Specified", "Specified"],
  "Product/Service": ["All", "Not Specified", "Specified"],
  "Cleared": ["All", "Cleared", "Uncleared", "Reconciled"],
  "A/R Paid": ["All", "Paid", "Unpaid"],
  "A/P Paid": ["All", "Paid", "Unpaid"],
};

const _activityTransactionTypeChoices = [
  "Credit Card Expense",
  "Cheque Expense",
  "Invoice",
  "Payment",
  "Journal Entry",
  "Bill",
  "Credit Card Credit",
  "Supplier Credit",
  "Credit",
  "Bill Payment (Cheque)",
  "Bill Payment (Credit Card)",
  "Payroll payment",
  "Charge",
  "Transfer",
  "Deposit",
  "Statement",
  "Time Charge",
  "Cash/Other Expense",
  "Sales Receipt",
  "Credit Note",
  "Refund",
  "Estimate",
  "Obsolete Payroll Adjustment",
  "Liability Payment (Cheque)",
  "Liability Payment (Credit Card)",
  "Payroll YTD",
  "Liability Refund",
  "Prior Liability Payments",
  "Direct Deposit Withdrawal",
  "Liability Payment (E-pay)",
  "Liability Payment (Marked Paid)",
  "Inventory Qty Adjust",
  "GST Payment",
  "GST Adjustment",
  "Job",
  "Expense",
  "Service Tax Partial Utilisation",
  "Service Tax Defer",
  "Service Tax Reversal",
  "Service Tax Refund",
  "Service Tax Gross Adjustment",
  "Reverse Charge",
  "Inventory Starting Value from Desktop",
  "Inventory Starting Value",
  "Credit Card Payment",
  "Revenue Recognition",
  "Employee Non-Reimbursable Expense",
  "Employee Reimbursement",
  "Employee Reimbursable Expense",
  "Change Order",
  "Item Receipt",
];

class _ActivityReportFilterPreview {
  final enabled = <String>{};
  final modes = {
    for (final name in _activityFilterAggregates.keys) name: 'All',
  };
  final selections = <String, Set<String>>{};
  final presets = {
    for (final name in ['Due Date', 'Created Date', 'Last Modified Date'])
      name: 'All Dates',
  };
  final dates = {
    for (final name in ['Due Date', 'Created Date', 'Last Modified Date'])
      for (final direction in ['From', 'Through'])
        '$name-$direction': TextEditingController(),
  };
  final text = {
    for (final name in ['Amount', 'Memo', 'No.']) name: TextEditingController(),
  };
  void dispose() {
    for (final c in [...dates.values, ...text.values]) {
      c.dispose();
    }
  }
}

class _PaymentMethodActivityReportPreview {
  // Retain Audyt's existing explicit date pair and ungrouped table rather
  // than importing the reference account's saved reporting preferences.
  String period = 'Custom', grouping = 'None', negative = '-100';
  bool divideBy1000 = false, withoutCents = false, showInRed = false;
  final columns = [
    for (final column in _paymentMethodActivityColumns.take(9)) column.id,
  ];
}

/// Report-only working presentation. No company, document or personal
/// preference writes; prepared facts await the real report result.
class _PaymentMethodReportPresentationPreview {
  static const alignments = ['Left', 'Centre', 'Right'];
  bool showLogo = false, showCompanyName = false, showTitle = true;
  bool showDate = false, showTime = false;
  String header = 'Left', footer = 'Left';
  String sortBy = 'Default', sortOrder = 'Ascending Order';
  bool showPeriod = false;
  final companyName = TextEditingController();
  final title = TextEditingController(text: 'Payment Method List');
  Alignment get headerAlignment => _alignment(header);
  Alignment get footerAlignment => _alignment(footer);
  Alignment _alignment(String value) => switch (value) {
    'Centre' => Alignment.center,
    'Right' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
  void dispose() {
    companyName.dispose();
    title.dispose();
  }
}

class _PaymentMethodReportFilterPreview {
  final enabled = <String>{};
  final methods = <String>{};
  final presets = {
    'Created Date': 'All Dates',
    'Last Modified Date': 'All Dates',
  };
  String deleted = 'All';
  final dates = {
    for (final name in ['Created Date', 'Last Modified Date'])
      for (final direction in ['From', 'Through'])
        '$name-$direction': TextEditingController(),
  };
  void dispose() {
    for (final controller in dates.values) {
      controller.dispose();
    }
  }
}
