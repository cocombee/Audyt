import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/core/dates/accounting_date.dart';

import 'widgets/accounting_formatters.dart';

import '../domain/recurrence_rule.dart';

Future<RecurrenceRule?> showExpenseRecurrenceDialog(
  BuildContext context, {
  required DateTime startsOn,
  RecurrenceRule? initial,
}) => showDialog<RecurrenceRule>(
  context: context,
  builder: (_) => _RecurrenceDialog(startsOn: startsOn, initial: initial),
);

class _RecurrenceDialog extends StatefulWidget {
  const _RecurrenceDialog({required this.startsOn, this.initial});
  final DateTime startsOn;
  final RecurrenceRule? initial;
  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  late RecurrenceUnit unit = widget.initial?.unit ?? RecurrenceUnit.months;
  late final every = TextEditingController(
    text: '${widget.initial?.every ?? 1}',
  );
  late final end = TextEditingController(
    text: widget.initial?.endsOn == null
        ? ''
        : formatAccountingInputDate(widget.initial!.endsOn!),
  );
  late final count = TextEditingController(
    text: '${widget.initial?.occurrenceCount ?? 12}',
  );
  late String ending = widget.initial?.endsOn != null
      ? 'On Date'
      : widget.initial?.occurrenceCount != null
      ? 'After Occurrences'
      : 'Never';
  late bool monthEnd = widget.initial?.preserveMonthEnd ?? true;
  String? error;
  late final (RecurrenceUnit, String, String, String, String, bool) _opening;
  bool _closing = false;

  (RecurrenceUnit, String, String, String, String, bool) _snapshot() =>
      (unit, every.text, end.text, count.text, ending, monthEnd);

  @override
  void initState() {
    super.initState();
    _opening = _snapshot();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final discard =
          _snapshot() == _opening ||
          await AccountingDialog.confirmDiscardChanges(context);
      if (mounted && discard) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    every.dispose();
    end.dispose();
    count.dispose();
    super.dispose();
  }

  RecurrenceRule rule() {
    final interval = int.tryParse(every.text);
    if (interval == null || interval < 1) {
      throw const FormatException('Enter a positive whole-number interval.');
    }
    final date = ending == 'On Date'
        ? parseAccountingInputDate(end.text)
        : null;
    if (ending == 'On Date' && date == null) {
      throw const FormatException('Enter a valid end date.');
    }
    final occurrences = ending == 'After Occurrences'
        ? int.tryParse(count.text)
        : null;
    if (ending == 'After Occurrences' &&
        (occurrences == null || occurrences < 1)) {
      throw const FormatException('Enter a positive occurrence count.');
    }
    return RecurrenceRule(
      startsOn: widget.initial?.startsOn ?? widget.startsOn,
      unit: unit,
      every: interval,
      endsOn: date,
      occurrenceCount: occurrences,
      preserveMonthEnd: monthEnd,
    );
  }

  Widget input(String label, TextEditingController controller, String key) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingFieldLabel(
            context,
            label,
            alignToField: true,
            key: key == 'recurrence-end'
                ? const ValueKey('recurrence-end-label')
                : null,
          ),
          const SizedBox(height: accountingFieldLabelGap),
          Builder(
            builder: (context) {
              final field = TextField(
                key: ValueKey(key),
                controller: controller,
                enableInteractiveSelection: true,
                inputFormatters: key == 'recurrence-end'
                    ? const [DateInputFormatter()]
                    : null,
                onChanged: (_) => setState(() => error = null),
                decoration:
                    (key == 'recurrence-end'
                            ? accountingSingleLineInputDecoration(
                                context,
                                hintText: 'DD-MM-YYYY',
                              )
                            : accountingInputDecoration(context))
                        .copyWith(
                          suffixIcon: key == 'recurrence-end'
                              ? accountingCalendarButton(
                                  context,
                                  controller: controller,
                                  label: 'End Date',
                                  onPicked: () => setState(() => error = null),
                                )
                              : null,
                        ),
              );
              return key == 'recurrence-end'
                  ? accountingDateFieldFrame(child: field)
                  : field;
            },
          ),
        ],
      );
  @override
  Widget build(BuildContext context) {
    List<DateTime> preview = [];
    try {
      preview = rule().preview(count: 4);
    } catch (_) {
      /* Validation is shown when applying. */
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: PopScope<RecurrenceRule>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.wider,
          title: 'Recurring Expense',
          formFooter: true,
          description:
              'Choose when this expense repeats and review the next dates.',
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Starts ${formatAccountingInputDate(widget.initial?.startsOn ?? widget.startsOn)}',
                  ),
                  const SizedBox(height: 12),
                  AccountingOrdinaryFields(
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Repeat Unit',
                        hasGuidance: true,
                        choices: ['Days', 'Weeks', 'Months', 'Years'],
                        builder: (width) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accountingFieldLabel(
                              context,
                              'Repeat Unit',
                              alignToField: true,
                              guidance: accountingFieldGuidance('Repeat'),
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            AccountingSelector<RecurrenceUnit>(
                              assignedWidth: width,
                              hintText: 'Repeat Unit',
                              options: [
                                for (final value in RecurrenceUnit.values)
                                  AccountingSelectorOption(
                                    value: value,
                                    label: switch (value) {
                                      RecurrenceUnit.days => 'Days',
                                      RecurrenceUnit.weeks => 'Weeks',
                                      RecurrenceUnit.months => 'Months',
                                      RecurrenceUnit.years => 'Years',
                                    },
                                  ),
                              ],
                              value: unit,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => unit = value);
                                }
                              },
                              semanticsLabel: 'Repeat Unit',
                            ),
                          ],
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Every',
                        builder: (_) =>
                            input('Every', every, 'recurrence-every'),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Ends',
                        choices: ['Never', 'On Date', 'After Occurrences'],
                        builder: (width) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accountingFieldLabel(
                              context,
                              'Ends',
                              alignToField: true,
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            AccountingSelector<String>(
                              assignedWidth: width,
                              hintText: 'Ends',
                              options: [
                                for (final value in [
                                  'Never',
                                  'On Date',
                                  'After Occurrences',
                                ])
                                  AccountingSelectorOption(
                                    value: value,
                                    label: value,
                                  ),
                              ],
                              value: ending,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => ending = value);
                                }
                              },
                              semanticsLabel: 'Ends',
                            ),
                          ],
                        ),
                      ),
                      if (ending == 'On Date')
                        AccountingOrdinaryFieldSlot(
                          label: 'End Date',
                          date: true,
                          contentSample: '00-00-0000',
                          builder: (_) =>
                              input('End Date', end, 'recurrence-end'),
                        ),
                      if (ending == 'After Occurrences')
                        AccountingOrdinaryFieldSlot(
                          label: 'Occurrences',
                          builder: (_) =>
                              input('Occurrences', count, 'recurrence-count'),
                        ),
                    ],
                  ),
                  if (unit == RecurrenceUnit.months ||
                      unit == RecurrenceUnit.years)
                    Theme(
                      data: Theme.of(context)
                          .copyWith(hoverColor: Colors.transparent),
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Keep Month End'),
                        value: monthEnd,
                        onChanged: (value) =>
                            setState(() => monthEnd = value ?? true),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('Schedule Preview'),
                  Text(preview.map(formatAccountingInputDate).join(' · ')),
                  const SizedBox(height: 12),
                  const Text(
                    'Saves the schedule with this expense. Open Recurring Expenses to review due suggestions.',
                  ),
                  if (error != null)
                    Text(error!, key: const ValueKey('recurrence-error')),
                ],
              ),
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: null,
              onPressed: _close,
              child: const Text('Cancel'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('recurrence-apply'),
              onPressed: () {
                try {
                  Navigator.pop(context, rule());
                } on FormatException catch (e) {
                  setState(() => error = e.message);
                } on ArgumentError catch (e) {
                  setState(() => error = e.message.toString());
                }
              },
              child: const Text('Apply Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
