import 'journal_workspace_page.dart';
import '../../../../core/ids/entity_id.dart';

import 'dart:convert';

import '../../../../core/dates/accounting_date.dart';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../application/accounting_workspace.dart';
import 'widgets/accounting_formatters.dart';

class AuditLogDialog extends StatefulWidget {
  const AuditLogDialog({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends State<AuditLogDialog> {
  List<Map<String, Object?>> _rows = [];
  final List<int?> _pages = [null];
  int? _anchor;
  String? _kind;
  EntityId? _actor;
  String? _error;
  bool _loading = true;
  bool _more = false;
  int _total = 0;
  int _unfilteredTotal = 0;
  int _pageSize = AccountingRecordPageSizes.read('audit');
  List<String> _kinds = [];
  final Set<int> _expanded = {};
  final _fromText = TextEditingController();
  final _throughText = TextEditingController();
  DateTime? _from;
  DateTime? _before;
  String? _dateError;

  @override
  void dispose() {
    _fromText.dispose();
    _throughText.dispose();
    super.dispose();
  }

  void _applyDates() {
    DateTime? parse(String text) {
      final day = parseAccountingInputDate(text);
      return day == null ? null : DateTime.utc(day.year, day.month, day.day);
    }

    final from = parse(_fromText.text);
    final through = parse(_throughText.text);
    if ((_fromText.text.trim().isNotEmpty && from == null) ||
        (_throughText.text.trim().isNotEmpty && through == null) ||
        (from != null && through != null && from.isAfter(through))) {
      setState(
        () => _dateError =
            'Enter valid DD-MM-YYYY dates with From on or before Through.',
      );
      return;
    }
    _dateError = null;
    _from = from;
    _before = through?.add(const Duration(days: 1));
    _anchor = null;
    _pages
      ..clear()
      ..add(null);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Freeze the whole default list, not the newest matching filter result.
      // A narrow filter must never hide the controls for a six-record list.
      final latest = _anchor == null
          ? await widget.workspace.database.auditEventPage(
              widget.workspace.identity.businessId,
              limit: 1,
            )
          : const <Map<String, Object?>>[];
      final anchor = _anchor ?? latest.firstOrNull?['sequence'] as int?;
      final rows = await widget.workspace.database.auditEventPage(
        widget.workspace.identity.businessId,
        limit: _pageSize + 1,
        beforeSequence: _pages.last,
        throughSequence: anchor,
        kind: _kind,
        actorId: _actor,
        occurredFrom: _from,
        occurredBefore: _before,
      );
      final rawCount = await widget.workspace.database.auditEventCount(
        widget.workspace.identity.businessId,
        throughSequence: anchor,
      );
      final filteredCount = await widget.workspace.database.auditEventCount(
        widget.workspace.identity.businessId,
        throughSequence: anchor,
        kind: _kind,
        actorId: _actor,
        occurredFrom: _from,
        occurredBefore: _before,
      );
      if (!mounted) return;
      setState(() {
        _anchor = anchor;
        _unfilteredTotal = rawCount;
        _total = filteredCount;
        _kinds = {
          'journal_posted',
          'period_closed',
          'expense_intake_edited',
          ...widget.workspace.database.auditEventKinds(
            widget.workspace.identity.businessId,
          ),
        }.toList()..sort();
        _more = rows.length > _pageSize;
        _rows = rows.take(_pageSize).toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  String _label(Object? kind) => switch (kind) {
    'journal_posted' => 'Journal Posted',
    'period_closed' => 'Period Closed',
    'expense_intake_edited' => 'Expense Edited',
    _ => accountingTitleCase('$kind'.replaceAll('_', ' ')),
  };

  Future<void> _openJournal(Map<String, Object?> row) async {
    try {
      await showPostedJournal(
        context,
        widget.workspace,
        EntityId.parse(row['subject_id'] as String),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open journal: $error')));
    }
  }

  void _filterActor(EntityId? actor) {
    _actor = actor;
    _anchor = null;
    _pages
      ..clear()
      ..add(null);
    _load();
  }

  String _timestamp(Object? value) {
    final date = DateTime.tryParse('$value')?.toUtc();
    if (date == null) return '$value';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${formatAccountingInputDate(date)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)} UTC';
  }

  List<(String, String)> _details(Map<String, Object?> row) {
    final lines = <(String, String)>[
      ('Actor', '${row['actor_id']}'),
      ('Record', '${row['subject_id']}'),
    ];
    const labels = {
      'requestId': 'Approval Request',
      'reviewedRevision': 'Reviewed Revision',
      'postedRevision': 'Posted Revision',
      'reversesId': 'Reverses Journal',
      'closingEquityAccountId': 'Closing Equity Account',
      'expenseIntakeId': 'Expense Record',
      'previous': 'Previous Closing Date',
      'through': 'Closed Through',
      'reason': 'Reason',
    };
    try {
      final detail = jsonDecode(row['detail'] as String);
      if (detail is! Map<String, dynamic>) throw const FormatException();
      if (row['kind'] == 'expense_intake_edited') {
        final before = detail['before'];
        final after = detail['after'];
        if (before is! Map || after is! Map) throw const FormatException();
        const fields = {
          'date': 'Date',
          'amount': 'Amount',
          'payee': 'Payee',
          'paymentAccount': 'Payment Account',
          'paymentAccountId': 'Payment Account ID',
          'category': 'Category',
          'tax': 'Tax',
          'customer': 'Customer',
          'billable': 'Billable',
          'dimensions': 'Dimensions',
          'itemOrSplitDetails': 'Items Or Split Details',
          'notes': 'Notes',
        };
        for (final field in fields.entries) {
          if (before[field.key] != after[field.key]) {
            lines.add((
              field.value,
              '${before[field.key] ?? "—"} → ${after[field.key] ?? "—"}',
            ));
          }
        }
        for (final key in ['attachments', 'reviewSnapshots']) {
          if (jsonEncode(before[key]) != jsonEncode(after[key])) {
            lines.add(
              key == 'attachments'
                  ? ('Attachments', 'Updated; original files are preserved.')
                  : ('Receipt Edit History', 'Updated.'),
            );
          }
        }
        return lines;
      }
      for (final entry in detail.entries) {
        if (entry.value != null) {
          lines.add((labels[entry.key] ?? entry.key, '${entry.value}'));
        }
      }
    } on Object {
      lines.add(('Stored Details', '${row['detail']}'));
    }
    return lines;
  }

  void _resetPage() {
    _anchor = null;
    _pages
      ..clear()
      ..add(null);
  }

  double get _dateFieldWidth =>
      (AccountingResponsive.measuredTextWidth(
                context,
                'DD-MM-YYYY',
                AccountingTypography.controlValue(context),
              ) +
              accountingFieldContentInset * 2 +
              accountingControlHeight +
              4)
          .clamp(accountingCompactDateFieldWidth, double.infinity);

  Widget _dateField(
    String label,
    TextEditingController controller,
    String key,
  ) => SizedBox(
    width: _dateFieldWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountingFieldLabel(context, label, alignToField: true),
        const SizedBox(height: accountingFieldLabelGap),
        TextField(
          key: ValueKey(key),
          controller: controller,
          enabled: !_loading,
          maxLines: 1,
          keyboardType: TextInputType.datetime,
          inputFormatters: const [DateInputFormatter()],
          style: AccountingTypography.controlValue(context),
          textAlignVertical: TextAlignVertical.center,
          decoration:
              accountingSingleLineInputDecoration(
                context,
                hintText: 'DD-MM-YYYY',
              ).copyWith(
                suffixIcon: accountingCalendarButton(
                  context,
                  controller: controller,
                  label: label,
                  enabled: !_loading,
                ),
              ),
        ),
      ],
    ),
  );

  Widget _event(Map<String, Object?> row) {
    final sequence = row['sequence'] as int;
    final expanded = _expanded.contains(sequence);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: InkWell(
            key: ValueKey('audit-event-$sequence'),
            onTap: () => setState(() {
              if (!_expanded.add(sequence)) _expanded.remove(sequence);
            }),
            child: AccountingRecordRow(
              title: _label(row['kind']),
              details: Text(
                _timestamp(row['occurred_at']),
                style: AccountingTypography.helper(context),
              ),
              trailing: RotatedBox(
                quarterTurns: expanded ? 2 : 0,
                child: const AccountingSelectorChevron(),
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            key: ValueKey('audit-details-$sequence'),
            padding: const EdgeInsets.fromLTRB(
              accountingContentInset,
              0,
              accountingContentInset,
              accountingContentInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectionArea(
                  child: AccountingInformationRows(rows: _details(row)),
                ),
                const SizedBox(height: accountingContentInset),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: accountingRecordIconGap,
                  runSpacing: accountingRecordIconGap,
                  children: [
                    AccountingButton.outline(
                      context,
                      key: ValueKey('audit-filter-actor-$sequence'),
                      onPressed: _loading
                          ? null
                          : () => _filterActor(
                              EntityId.parse(row['actor_id'] as String),
                            ),
                      child: const Text('Filter By This Actor'),
                    ),
                    if (row['kind'] == 'journal_posted')
                      AccountingButton.outline(
                        context,
                        key: ValueKey('audit-open-journal-$sequence'),
                        onPressed: () => _openJournal(row),
                        child: const Text('View Journal'),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showControls = AccountingRecordControlsPolicy.visible(
      _unfilteredTotal,
    );
    final eventLabels = ['All Events', ..._kinds.map(_label)];
    final eventWidth = accountingSelectorMinimumWidth(context, eventLabels);
    return AccountingDialog.alert(
      context,
      title: 'Audit Log',
      description: 'Review recorded accounting changes.',
      maxContentWidth: 900,
      contentScrollKey: const ValueKey('audit-content-scroll'),
      content: SizedBox(
        width: 900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              AccountingAlert.build(
                context,
                title: 'Could Not Load Audit Events',
                description: _error!,
                tone: AccountingAlertTone.critical,
                bottomGap: accountingContentInset,
              ),
            AccountingControlFlow(
              crossAxisAlignment: WrapCrossAlignment.end,
              widths: [
                if (showControls) ...[
                  eventWidth,
                  _dateFieldWidth,
                  _dateFieldWidth,
                  AccountingResponsive.measuredTextWidth(
                        context,
                        'Apply',
                        AccountingTypography.button(context),
                      ) +
                      accountingContentInset * 2,
                  AccountingResponsive.measuredTextWidth(
                        context,
                        'Clear',
                        AccountingTypography.button(context),
                      ) +
                      accountingContentInset * 2,
                ],
              ],
              trailingWidth:
                  AccountingResponsive.measuredTextWidth(
                    context,
                    'Refresh',
                    AccountingTypography.button(context),
                  ) +
                  accountingContentInset * 2,
              trailing: AccountingButton.outline(
                context,
                key: const ValueKey('audit-refresh'),
                onPressed: _loading
                    ? null
                    : () {
                        _resetPage();
                        _load();
                      },
                child: const Text('Refresh'),
              ),
              children: [
                if (showControls) ...[
                  SizedBox(
                    width: eventWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Event',
                          alignToField: true,
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        AccountingSelector<String>(
                          controlKey: const ValueKey('audit-kind'),
                          value: _kind ?? '',
                          hintText: 'All Events',
                          options: [
                            const AccountingSelectorOption(
                              value: '',
                              label: 'All Events',
                            ),
                            for (final kind in _kinds)
                              AccountingSelectorOption(
                                value: kind,
                                label: _label(kind),
                              ),
                          ],
                          enabled: !_loading,
                          onChanged: (value) {
                            _kind = value == '' ? null : value;
                            _resetPage();
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                  _dateField('From (UTC)', _fromText, 'audit-from'),
                  _dateField('Through (UTC)', _throughText, 'audit-through'),
                  AccountingButton.primary(
                    context,
                    key: const ValueKey('audit-apply-dates'),
                    onPressed: _loading ? null : _applyDates,
                    child: const Text('Apply'),
                  ),
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('audit-clear-dates'),
                    onPressed: _loading
                        ? null
                        : () {
                            _fromText.clear();
                            _throughText.clear();
                            _applyDates();
                          },
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            if (_actor != null) ...[
              const SizedBox(height: accountingContentInset),
              Wrap(
                spacing: accountingRecordIconGap,
                runSpacing: accountingRecordIconGap,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _actor == widget.workspace.identity.ownerId
                        ? 'Actor: Workspace Owner'
                        : 'Actor: ${_actor!.value}',
                  ),
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('audit-all-actors'),
                    onPressed: _loading ? null : () => _filterActor(null),
                    child: const Text('All Actors'),
                  ),
                ],
              ),
            ],
            if (_dateError != null)
              AccountingAlert.build(
                context,
                title: 'Check Dates',
                description: _dateError!,
                tone: AccountingAlertTone.warning,
                topGap: accountingContentInset,
              ),
            const SizedBox(height: accountingContentInset),
            if (_loading)
              const SizedBox(
                height: accountingControlHeight,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              AccountingRecordList(
                paginationKey: 'audit',
                totalCount: _unfilteredTotal,
                emptyState: const Padding(
                  padding: accountingContentPadding,
                  child: Text('No accounting events recorded.'),
                ),
                externalPagination: Padding(
                  padding: accountingContentPadding,
                  child: AccountingRecordPagination(
                    keyPrefix: 'audit',
                    total: _total,
                    unfilteredTotal: _unfilteredTotal,
                    offset: (_pages.length - 1) * _pageSize,
                    pageSize: _pageSize,
                    onPageSizeChanged: (size) {
                      _pageSize = size;
                      _pages
                        ..clear()
                        ..add(null);
                      _load();
                    },
                    onPrevious: _pages.length == 1
                        ? null
                        : () {
                            _pages.removeLast();
                            _load();
                          },
                    onNext: !_more || _error != null
                        ? null
                        : () {
                            _pages.add(_rows.last['sequence'] as int);
                            _load();
                          },
                  ),
                ),
                children: [
                  for (final row in _rows)
                    KeyedSubtree(
                      key: ValueKey(row['sequence']),
                      child: _event(row),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: const [],
    );
  }
}
