import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../app/reminder_appearance_picker.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/ids/entity_id.dart';
import '../application/accounting_workspace.dart';
import '../domain/workspace_reminder.dart';
import 'widgets/accounting_formatters.dart';

class ReminderFormDialog extends StatefulWidget {
  const ReminderFormDialog({super.key, required this.workspace, this.reminder});
  final AccountingWorkspace workspace;
  final WorkspaceReminder? reminder;
  @override
  State<ReminderFormDialog> createState() => _ReminderFormDialogState();
}

class _ReminderFormDialogState extends State<ReminderFormDialog> {
  final _form = GlobalKey<FormState>();
  late final id = widget.reminder?.id ?? EntityId.random();
  late final name = TextEditingController(text: widget.reminder?.title ?? '');
  late final dates = <TextEditingController>[
    TextEditingController(
      text: formatAccountingInputDate(
        widget.reminder?.dueDate ?? DateTime.now(),
      ),
    ),
  ];
  late String mode =
      widget.reminder?.repeat != null && widget.reminder!.repeat != 'Never'
      ? 'Repeating'
      : widget.reminder?.mode ?? 'Once';
  late int every = widget.reminder?.frequencyEvery ?? 1;
  late String unit = widget.reminder?.effectiveFrequencyUnit ?? 'Month';
  late String icon = widget.reminder?.displayIcon ?? 'Choice:Calendar';
  late String status = widget.reminder?.status ?? 'Not Started';
  String? error;
  @override
  void dispose() {
    name.dispose();
    for (final date in dates) {
      date.dispose();
    }
    super.dispose();
  }

  Widget field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AccountingTypography.fieldLabel(context)),
      const SizedBox(height: accountingFieldLabelGap),
      child,
    ],
  );
  Widget selector(
    String key,
    String value,
    List<String> choices,
    ValueChanged<String> onChanged,
  ) => AccountingSelector<String>(
    triggerKey: ValueKey(key),
    assignedWidth: double.infinity,
    options: [
      for (final choice in choices)
        AccountingSelectorOption(value: choice, label: choice),
    ],
    value: value,
    hintText: 'Choose',
    onChanged: (value) {
      if (value != null) {
        setState(() {
          onChanged(value);
          error = null;
        });
      }
    },
  );
  Widget deadline(TextEditingController controller, int index) => Row(
    key: ObjectKey(controller),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: accountingDateFieldFrame(
          child: TextFormField(
            key: ValueKey('reminder-deadline-$index'),
            controller: controller,
            inputFormatters: const [DateInputFormatter()],
            decoration: accountingSingleLineInputDecoration(context).copyWith(
              suffixIcon: accountingCalendarButton(
                context,
                controller: controller,
                label: 'Deadline ${index + 1}',
                firstDate: reminderFirstDate(DateTime.now()),
                lastDate: reminderLastDate(DateTime.now()),
                onPicked: () => setState(() => error = null),
              ),
            ),
            validator: (text) {
              final date = parseAccountingInputDate(text ?? '');
              if (date == null) return 'Enter DD-MM-YYYY.';
              if (date != widget.reminder?.dueDate &&
                  !validNewReminderDate(date, DateTime.now())) {
                return 'Today through ten years ahead.';
              }
              return null;
            },
          ),
        ),
      ),
      if (mode == 'Custom Dates') ...[
        const SizedBox(width: 10),
        if (index == 0)
          accountingCompactAdd(
            context,
            key: const ValueKey('reminder-add-date'),
            tooltip: 'Add Date',
            onPressed: () => setState(() {
              dates.add(
                TextEditingController(
                  text: formatAccountingInputDate(DateTime.now()),
                ),
              );
              error = null;
            }),
          )
        else
          accountingCompactRemove(
            context,
            tooltip: 'Remove Date',
            key: ValueKey('remove-reminder-date-$index'),
            onPressed: () {
              setState(() {
                dates.remove(controller);
                error = null;
              });
              controller.dispose();
            },
          ),
      ],
    ],
  );
  void save() {
    if (!_form.currentState!.validate()) return;
    try {
      final selected = [
        for (final controller in mode == 'Custom Dates' ? dates : dates.take(1))
          parseAccountingInputDate(controller.text)!,
      ];
      if (selected.toSet().length != selected.length) {
        throw const FormatException('Choose different deadlines.');
      }
      final original = widget.reminder;
      widget.workspace.saveReminders([
        for (var i = 0; i < selected.length; i++)
          WorkspaceReminder(
            id: i == 0 ? id : EntityId.random(),
            title: name.text,
            obligation: original?.obligation ?? 'Other',
            agency: original?.agency ?? 'Other',
            dueDate: selected[i],
            triggerDate: original?.triggerDate,
            leadDays: original?.leadDays,
            status: i == 0 ? status : 'Not Started',
            notes: original?.notes ?? '',
            legalSource: original?.legalSource ?? '',
            revision: i == 0 ? original?.revision ?? 0 : 0,
            icon: icon,
            mode: mode,
            repeat: mode == 'Repeating' ? 'Repeating' : 'Never',
            frequencyEvery: every,
            frequencyUnit: unit,
            seriesId: mode == 'Repeating'
                ? original?.seriesId ?? id.value
                : null,
            repeatAnchor:
                original?.dueDate == selected[i] &&
                    original?.effectiveFrequencyUnit == unit &&
                    original?.frequencyEvery == every
                ? original?.repeatAnchor
                : selected[i],
          ),
      ]);
      Navigator.of(context).pop();
    } catch (failure) {
      setState(
        () => error = failure is FormatException ? failure.message : '$failure',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogInsets =
        DialogTheme.of(context).insetPadding ??
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
    // Both outer dialog insets and the form's inner insets reduce the usable
    // width. Calculate columns from that space so they stay paired at 720px.
    final width = math.min(
      AccountingPopoutTokens.widerContentWidth,
      media.size.width -
          dialogInsets.horizontal -
          media.viewInsets.horizontal -
          accountingContentInset * 2,
    );
    final column = (width - 20) / 2;
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.wider,
      title: widget.reminder == null ? 'Add Reminder' : 'Edit Reminder',
      maxContentWidth: width,
      contentInset: accountingContentInset,
      formFooter: true,
      content: Form(
        key: _form,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Text(error!, style: AccountingTypography.helper(context)),
                const SizedBox(height: 20),
              ],
              AccountingOrdinaryFields(
                fields: [
                  AccountingOrdinaryFieldSlot(
                    label: 'Reminder Name',
                    contentSample: 'Annual Return',
                    builder: (_) => field(
                      'Reminder Name',
                      TextFormField(
                        key: const ValueKey('reminder-name'),
                        controller: name,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            WorkspaceReminder.nameLimit,
                          ),
                        ],
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: 'Reminder Name',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter a reminder name.'
                            : null,
                      ),
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: 'Mode',
                    choices: ['Once', 'Repeating', 'Custom Dates'],
                    builder: (_) => field(
                      'Mode',
                      selector(
                        'reminder-mode',
                        mode,
                        const ['Once', 'Repeating', 'Custom Dates'],
                        (value) {
                          mode = value;
                          if (value == 'Custom Dates' && dates.length == 1) {
                            dates.add(
                              TextEditingController(
                                text: formatAccountingInputDate(DateTime.now()),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  if (mode != 'Custom Dates')
                    AccountingOrdinaryFieldSlot(
                      label: 'Deadline',
                      date: true,
                      contentSample: '00-00-0000',
                      builder: (_) =>
                          field('Deadline', deadline(dates.first, 0)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  if (mode == 'Custom Dates')
                    SizedBox(
                      width: column,
                      child: field(
                        'Deadline',
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var i = 0;
                              i < (mode == 'Custom Dates' ? dates.length : 1);
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(height: 10),
                              deadline(dates[i], i),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (mode == 'Repeating')
                    SizedBox(
                      width: column,
                      child: field(
                        'Frequency',
                        Row(
                          children: [
                            Expanded(
                              child: selector(
                                'reminder-frequency-number',
                                '$every',
                                [
                                  for (
                                    var n = 1;
                                    n <= maxFrequencyFor(unit);
                                    n++
                                  )
                                    '$n',
                                ],
                                (value) => every = int.parse(value),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 2,
                              child: selector(
                                'reminder-frequency-unit',
                                unit,
                                WorkspaceReminder.frequencyUnits,
                                (value) {
                                  unit = value;
                                  every = math.min(
                                    every,
                                    maxFrequencyFor(unit),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(
                    width: column,
                    child: ReminderAppearancePicker(
                      icon: icon,
                      onChanged: (value) => setState(() => icon = value),
                    ),
                  ),
                ],
              ),
              if (widget.reminder != null) ...[
                const SizedBox(height: 20),
                AccountingOrdinaryFields(
                  fields: [
                    AccountingOrdinaryFieldSlot(
                      label: 'Status',
                      minimumRowFraction: 1,
                      choices: WorkspaceReminder.statuses,
                      builder: (_) => field(
                        'Status',
                        selector(
                          'reminder-status',
                          status,
                          WorkspaceReminder.statuses,
                          (value) => status = value,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AccountingButton.primary(
          context,
          key: const ValueKey('reminder-save'),
          onPressed: save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
