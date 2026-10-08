import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../sales/domain/invoice.dart';
import '../../sales/domain/estimate.dart';
import '../../sales/invoice_form.dart';
import '../../purchases/domain/purchase_bill_draft.dart';
import '../application/accounting_workspace.dart';
import '../data/accounting_database.dart';
import '../domain/recurrence_rule.dart';
import '../domain/recurring_document_template.dart';

Future<void> showRecurringTransactions(
  BuildContext context,
  AccountingWorkspace workspace, {
  RecurringDocumentKind initialKind = RecurringDocumentKind.invoice,
}) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.widerContentWidth,
  contentInset: accountingContentInset,
  builder: (_) => RecurringTransactionsDialog(
    workspace: workspace,
    initialKind: initialKind,
  ),
);

final class ScheduleSource {
  const ScheduleSource(this.id, this.revision, this.label);
  final String id, label;
  final int revision;
}

/// Existing schedules retain their frozen source. Editing a transaction does
/// not replace them or create another schedule implicitly.
Map<String, Object?> documentRecurrenceInitial(
  AccountingWorkspace workspace,
  RecurringDocumentKind kind,
  EntityId sourceId,
) {
  final schedule = workspace.database
      .documentSchedules(workspace.identity.businessId)
      .where(
        (s) => s.kind == kind && s.sourceId == sourceId.value && !s.cancelled,
      )
      .firstOrNull;
  if (schedule == null) return const {};
  return {
    '_recurrenceManaged': true,
    'Make Recurring': switch ((
      schedule.schedule.unit,
      schedule.schedule.every,
    )) {
      (RecurrenceUnit.months, 1) => 'Monthly',
      (RecurrenceUnit.months, 3) => 'Quarterly',
      (RecurrenceUnit.years, 1) => 'Yearly',
      _ => 'Custom',
    },
  };
}

List<ScheduleSource> scheduleSources(
  AccountingWorkspace w,
  RecurringDocumentKind kind,
) {
  if (kind == RecurringDocumentKind.quotation) {
    return [
      for (final record in w.quotations())
        ScheduleSource(
          record.quotation.id.value,
          record.revision,
          '${record.quotation.documentNumber} · ${invoiceMoney(record.quotation.total)}',
        ),
    ];
  }
  if (kind == RecurringDocumentKind.invoice) {
    return [
      for (final r in w.database.recurringInvoiceSources(w.identity.businessId))
        ScheduleSource(
          r.invoice.id.value,
          r.revision,
          '${r.invoice.documentNumber} · ${invoiceMoney(r.invoice.total)}',
        ),
    ];
  }
  final sources = <ScheduleSource>[];
  var offset = 0;
  while (true) {
    final page = w.database.billDraftPage(
      businessId: w.identity.businessId,
      posted: null,
      offset: offset,
      limit: 100,
    );
    sources.addAll([
      for (final b in page.records)
        ScheduleSource(
          b.id.value,
          b.metadata.revision,
          '${b.documentNumber} · ${invoiceMoney(b.total)}',
        ),
    ]);
    offset += page.records.length;
    if (offset >= page.total || page.records.isEmpty) return sources;
  }
}

FrontendFormDialog recurringScheduleEditor(
  AccountingWorkspace w,
  RecurringDocumentKind kind, {
  RecurringDocumentTemplate? original,
}) {
  final sources = scheduleSources(w, kind);
  if (original != null && !sources.any((s) => s.id == original.sourceId)) {
    sources.add(
      ScheduleSource(
        original.sourceId,
        original.sourceRevision,
        switch (original.kind) {
          RecurringDocumentKind.invoice => Invoice.fromDraftSnapshot(
            original.source,
          ).documentNumber,
          RecurringDocumentKind.bill => PurchaseBillDraft.fromJson(
            original.source,
          ).documentNumber,
          RecurringDocumentKind.quotation => Estimate.fromSnapshot(
            original.source,
          ).documentNumber,
        },
      ),
    );
  }
  final rule = original?.schedule;
  DesignForm specification(Map<String, Object?> values) => DesignForm(
    original == null ? 'Recurring Schedule' : 'Edit Recurring Schedule',
    [
      const DesignField('Schedule Name', required: true),
      DesignField(
        'Source Transaction',
        choiceLabels: {for (final s in sources) s.id: s.label},
        required: true,
      ),
      const DesignField(
        'Repeat',
        options: ['Daily', 'Weekly', 'Monthly', 'Yearly'],
        required: true,
      ),
      const DesignField('Every', required: true),
      const DesignField('Start Date', required: true),
      const DesignField(
        'Ends',
        options: ['Never', 'On Date', 'After Occurrences'],
        required: true,
      ),
      if (values['Ends'] == 'On Date')
        const DesignField('End Date', required: true),
      if (values['Ends'] == 'After Occurrences')
        const DesignField('Occurrence Count', required: true),
      const DesignField('Preserve Month End', toggle: true),
    ],
    actionLabel: 'Save',
  );
  return FrontendFormDialog(
    form: specification(const {}),
    valuesFormBuilder: specification,
    initial: {
      'Schedule Name': original?.name ?? '',
      'Source Transaction': original?.sourceId ?? '',
      'Repeat': switch (rule?.unit) {
        RecurrenceUnit.days => 'Daily',
        RecurrenceUnit.weeks => 'Weekly',
        RecurrenceUnit.years => 'Yearly',
        _ => 'Monthly',
      },
      'Every': '${rule?.every ?? 1}',
      'Start Date': formatAccountingInputDate(rule?.startsOn ?? DateTime.now()),
      'Ends': rule?.endsOn != null
          ? 'On Date'
          : rule?.occurrenceCount != null
          ? 'After Occurrences'
          : 'Never',
      'End Date': rule?.endsOn == null
          ? ''
          : formatAccountingInputDate(rule!.endsOn!),
      'Occurrence Count': '${rule?.occurrenceCount ?? ''}',
      'Preserve Month End': rule?.preserveMonthEnd ?? true,
    },
    onCommit: (values) async {
      String text(String k) => (values[k] as String? ?? '').trim();
      final source = sources
          .where((s) => s.id == text('Source Transaction'))
          .firstOrNull;
      if (source == null) {
        throw StateError('Choose a saved source transaction.');
      }
      final every = int.tryParse(text('Every'));
      final start = parseAccountingInputDate(text('Start Date'));
      final end = text('Ends') == 'On Date'
          ? parseAccountingInputDate(text('End Date'))
          : null;
      final count = text('Ends') == 'After Occurrences'
          ? int.tryParse(text('Occurrence Count'))
          : null;
      if (start == null ||
          every == null ||
          every < 1 ||
          every > 1000 ||
          text('Ends') == 'On Date' && end == null ||
          text('Ends') == 'After Occurrences' &&
              (count == null || count < 1 || count > 100000)) {
        throw const FormatException(
          'Enter a valid start, interval and end condition.',
        );
      }
      w.saveDocumentSchedule(
        id: original?.id ?? EntityId.random().value,
        name: text('Schedule Name'),
        kind: kind,
        sourceId: EntityId.parse(source.id),
        sourceRevision: source.revision,
        expectedRevision: original?.revision ?? 0,
        schedule: RecurrenceRule(
          startsOn: start,
          unit: switch (text('Repeat')) {
            'Daily' => RecurrenceUnit.days,
            'Weekly' => RecurrenceUnit.weeks,
            'Monthly' => RecurrenceUnit.months,
            'Yearly' => RecurrenceUnit.years,
            _ => throw const FormatException('Choose a repeat interval.'),
          },
          every: every,
          endsOn: end,
          occurrenceCount: count,
          preserveMonthEnd: values['Preserve Month End'] as bool? ?? true,
        ),
        paused: original?.paused ?? false,
      );
    },
  );
}

int? nextDocumentOccurrence(RecurringDocumentTemplate t, Set<DateTime> used) {
  if (t.paused || t.cancelled) return null;
  for (var i = 0; i < 100000; i++) {
    final date = t.schedule.occurrenceAt(i);
    if (date == null) return null;
    if (!used.contains(date)) return i;
  }
  return null;
}

class RecurringTransactionsDialog extends StatefulWidget {
  const RecurringTransactionsDialog({
    super.key,
    required this.workspace,
    this.initialKind = RecurringDocumentKind.invoice,
  });
  final AccountingWorkspace workspace;
  final RecurringDocumentKind initialKind;
  @override
  State<RecurringTransactionsDialog> createState() =>
      _RecurringTransactionsDialogState();
}

class _RecurringTransactionsDialogState
    extends State<RecurringTransactionsDialog> {
  String? type, status, error;
  Future<void> edit(
    RecurringDocumentKind kind, [
    RecurringDocumentTemplate? original,
  ]) => showDialog<void>(
    context: context,
    builder: (_) =>
        recurringScheduleEditor(widget.workspace, kind, original: original),
  );
  void change(
    RecurringDocumentTemplate t, {
    bool? paused,
    bool cancel = false,
  }) {
    try {
      widget.workspace.changeDocumentScheduleState(
        t,
        paused: paused,
        cancel: cancel,
      );
      setState(() => error = null);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> view(RecurringDocumentTemplate t) async {
    final occurrences = widget.workspace.database.documentOccurrences(
      widget.workspace.identity.businessId,
      t.id,
    );
    final index = nextDocumentOccurrence(
      t,
      occurrences.map((o) => o.date).toSet(),
    );
    final next = index == null ? null : t.schedule.occurrenceAt(index);
    await AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      builder: (context) => AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        title: t.name,
        content: AccountingInformationRows(
          rows: [
            ('Transaction', t.kind.label),
            ('Source Revision', '${t.sourceRevision}'),
            ('Schedule Revision', '${t.revision}'),
            (
              'Status',
              t.cancelled
                  ? 'Cancelled'
                  : t.paused
                  ? 'Paused'
                  : 'Active',
            ),
            ('Next Date', next == null ? '—' : formatAccountingInputDate(next)),
            for (final o in occurrences)
              ('Prepared', formatAccountingInputDate(o.date)),
          ],
        ),
        actions: [
          if (!t.cancelled)
            AccountingButton.outline(
              context,
              key: null,
              onPressed: () {
                change(t, paused: !t.paused);
                Navigator.pop(context);
              },
              child: Text(t.paused ? 'Resume' : 'Pause'),
            ),
          if (!t.cancelled)
            AccountingButton.outline(
              context,
              key: null,
              onPressed: () {
                change(t, cancel: true);
                Navigator.pop(context);
              },
              child: const Text('Cancel Schedule'),
            ),
          if (next != null &&
              !next.isAfter(accountingCalendarDate(DateTime.now())))
            AccountingButton.primary(
              context,
              key: ValueKey('prepare-occurrence-${t.id}'),
              onPressed: () {
                try {
                  widget.workspace.prepareDocumentOccurrence(t, index!);
                  Navigator.pop(context);
                } catch (e) {
                  setState(() => error = '$e');
                  Navigator.pop(context);
                }
              },
              child: const Text('Prepare Draft'),
            ),
          AccountingButton.ghost(
            context,
            key: null,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final all = widget.workspace.database.documentSchedules(
        widget.workspace.identity.businessId,
      );
      final visible = AccountingRecordControlsPolicy.visible(all.length);
      final rows = all
          .where(
            (t) =>
                !visible ||
                (type == null || t.kind.label == type) &&
                    (status == null ||
                        (t.cancelled
                                ? 'Cancelled'
                                : t.paused
                                ? 'Paused'
                                : 'Active') ==
                            status),
          )
          .toList();
      return AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.wider,
        title: 'Recurring Transactions',
        fixedContentWidth: AccountingPopoutTokens.widerContentWidth,
        maxContentWidth: AccountingPopoutTokens.widerContentWidth,
        formFooter: true,
        description: 'Prepare recurring drafts for review.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              AccountingAlert.build(
                context,
                title: 'Recurring Schedule',
                description: error!,
                tone: AccountingAlertTone.critical,
                bottomGap: accountingContentInset,
              ),
            AccountingControlFlow(
              spacing: accountingContentInset,
              crossAxisAlignment: WrapCrossAlignment.end,
              widths: [
                if (visible) ...[
                  accountingSelectorMinimumWidth(context, [
                    'All',
                    'Invoice',
                    'Bill',
                    'Quotation',
                  ]),
                  accountingSelectorMinimumWidth(context, [
                    'All',
                    'Active',
                    'Paused',
                    'Cancelled',
                  ]),
                ],
              ],
              trailingWidth:
                  AccountingResponsive.measuredTextWidth(
                    context,
                    'New Schedule',
                    AccountingTypography.button(context),
                  ) +
                  accountingContentInset * 2,
              trailing: AccountingButton.primary(
                context,
                key: const ValueKey('recurring-new'),
                onPressed: () => edit(
                  type == null
                      ? widget.initialKind
                      : RecurringDocumentKind.values.singleWhere(
                          (kind) => kind.label == type,
                        ),
                ),
                child: const Text('New Schedule'),
              ),
              children: [
                if (visible) ...[
                  AccountingRecordFilter(
                    label: 'Type',
                    options: const ['Invoice', 'Bill', 'Quotation'],
                    value: type,
                    onChanged: (v) => setState(() => type = v),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    options: const ['Active', 'Paused', 'Cancelled'],
                    value: status,
                    onChanged: (v) => setState(() => status = v),
                  ),
                ],
              ],
            ),
            const SizedBox(height: accountingContentInset),
            AccountingRecordList(
              paginationKey: 'recurring-transactions',
              totalCount: all.length,
              children: [
                for (final t in rows)
                  Builder(
                    builder: (context) {
                      final used = widget.workspace.database
                          .documentOccurrences(
                            widget.workspace.identity.businessId,
                            t.id,
                          )
                          .map((o) => o.date)
                          .toSet();
                      final next = nextDocumentOccurrence(t, used);
                      final date = next == null
                          ? null
                          : t.schedule.occurrenceAt(next);
                      final total = switch (t.kind) {
                        RecurringDocumentKind.invoice =>
                          Invoice.fromDraftSnapshot(t.source).total,
                        RecurringDocumentKind.bill =>
                          PurchaseBillDraft.fromJson(t.source).total,
                        RecurringDocumentKind.quotation =>
                          Estimate.fromSnapshot(t.source).total,
                      };
                      return AccountingRecordRow(
                        title: t.name,
                        status: AccountingBadge.build(
                          context,
                          label: t.cancelled
                              ? 'Cancelled'
                              : t.paused
                              ? 'Paused'
                              : 'Active',
                        ),
                        topRightInfo: true,
                        details: Text(
                          '${t.kind.label} · ${switch (t.schedule.unit) {
                            RecurrenceUnit.days => 'Daily',
                            RecurrenceUnit.weeks => 'Weekly',
                            RecurrenceUnit.months => 'Monthly',
                            RecurrenceUnit.years => 'Yearly',
                          }} · ${date == null ? '—' : formatAccountingInputDate(date)}',
                          style: AccountingTypography.value(context),
                        ),
                        trailing: Text(
                          invoiceMoney(total),
                          style: AccountingTypography.fieldLabel(context),
                        ),
                        trailingBelow: AccountingRecordActions(
                          trailing: [
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey('recurring-view-${t.id}'),
                              onPressed: () => view(t),
                              icon: Icons.visibility_outlined,
                              tooltip: 'View ${t.name}',
                            ),
                            if (!t.cancelled)
                              AccountingButton.iconOnly(
                                context,
                                key: ValueKey('recurring-edit-${t.id}'),
                                onPressed: () => edit(t.kind, t),
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit ${t.name}',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          AccountingButton.ghost(
            context,
            key: null,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
