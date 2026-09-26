import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import 'reminder_form_dialog.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/dates/accounting_date.dart';
import '../application/accounting_workspace.dart';
import '../domain/workspace_reminder.dart';
import 'widgets/accounting_layout.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;

  Future<void> _edit(BuildContext context, [WorkspaceReminder? record]) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            ReminderFormDialog(workspace: workspace, reminder: record),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace,
    builder: (context, _) => AccountingPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingPageHeader(
            routeLabel: 'Deadlines',
            title: 'Deadlines',
            description: 'Home shows the nearest active deadlines, using the two-to-four card limit in Settings. Review dates against their legal source.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('new-reminder'),
              leadingIcon: Icons.add_rounded,
              onPressed: () => _edit(context),
              child: const Text('Add Reminder'),
            ),
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          AccountingCard.surface(
            context,
            child: Column(
              children: [
                if (workspace.reminders.isEmpty)
                  Padding(
                    padding: accountingContentPadding,
                    child: Text(
                      'No reminders yet.',
                      style: AccountingTypography.helper(context),
                    ),
                  ),
                for (final record in workspace.reminders) ...[
                  AccountingRecordRow(
                    key: ValueKey('reminder-row-${record.id.value}'),
                    title: record.title,
                    status: AccountingBadge.build(
                      context,
                      label: record.displayStatus(
                        DateTime.now(),
                        workspace.preferences,
                      ),
                    ),
                    details: Text(
                      '${record.obligation} · ${formatAccountingInputDate(record.dueDate)}',
                    ),
                    trailing: AccountingRecordActions(
                      trailing: const [],
                      actions: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('edit-reminder-${record.id.value}'),
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit Reminder',
                          onPressed: () => _edit(context, record),
                        ),
                      ],
                    ),
                  ),
                  if (record.id != workspace.reminders.last.id)
                    Divider(
                      height: 1,
                      color: AccountingTheme.of(context).border,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
