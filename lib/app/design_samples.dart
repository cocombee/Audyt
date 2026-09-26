import '../features/accounting/domain/workspace_reminder.dart';
import '../features/accounting/domain/company_preferences.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_color_library.dart';
import 'accounting_theme.dart';
import 'reminder_appearance_picker.dart';
import 'responsive.dart';

const demoFolderRoot = '/Users/mrkokom/Downloads/Audyt Demo';
String demoFolder(String type) =>
    '$demoFolderRoot/$type/2026/09. September 2026';
const demoReminderTitles = ['SST Return', 'Income Tax', 'Annual Return'];

double reminderThreeColumnMinWidth(BuildContext context) =>
    _minimumReminderCardWidth(context, demoReminderTitles) * 3 +
    AccountingResponsive.groupGap * 2;

double _minimumReminderCardWidth(BuildContext context, List<String> titles) {
  final titleStyle = Theme.of(context).textTheme.bodyMedium;
  final titleWidth = titles
      .map(
        (title) =>
            AccountingResponsive.measuredTextWidth(context, title, titleStyle),
      )
      .reduce((a, b) => a > b ? a : b);
  return accountingContentInset * 2 +
      accountingMetricIconExtent +
      12 +
      AccountingResponsive.groupGap +
      titleWidth +
      24;
}

String reminderCountdown(Duration remaining, {bool includeSeconds = true}) {
  if (remaining.inSeconds <= 0) return 'Due Now';
  if (remaining.inHours >= 48) return '${(remaining.inHours / 24).ceil()} Days';
  final seconds = remaining.inSeconds % 60;
  final minutes = remaining.inMinutes % 60;
  if (remaining.inHours > 0) {
    final hoursAndMinutes =
        '${remaining.inHours}h ${minutes.toString().padLeft(2, '0')}m';
    return includeSeconds
        ? '$hoursAndMinutes ${seconds.toString().padLeft(2, '0')}s'
        : hoursAndMinutes;
  }
  if (remaining.inMinutes > 0) {
    final minutesOnly = '${remaining.inMinutes}m';
    return includeSeconds
        ? '$minutesOnly ${seconds.toString().padLeft(2, '0')}s'
        : minutesOnly;
  }
  return includeSeconds ? '${remaining.inSeconds}s' : 'Under 1m';
}

class DemoReminderPanel extends StatelessWidget {
  const DemoReminderPanel({
    super.key,
    this.availableWidth,
    this.leadingCard,
    this.titles = demoReminderTitles,
    this.reminders,
    this.preferences,
    this.onSave,
  });
  final double? availableWidth;
  final Widget? leadingCard;
  final List<String> titles;
  final List<WorkspaceReminder>? reminders;
  final CompanyPreferences? preferences;
  final ValueChanged<WorkspaceReminder>? onSave;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titles =
          reminders?.map((record) => record.title).toList() ?? this.titles;
      if (titles.isEmpty && leadingCard == null) return const SizedBox.shrink();
      final available = (availableWidth ?? constraints.maxWidth).clamp(
        0.0,
        constraints.maxWidth,
      );
      // At narrow card widths the badge moves below the icon/title row.
      // Reserve the full title and disclosure width there; counting badge
      // beside them would make a two-card row split prematurely.
      final minimumCardWidth = _minimumReminderCardWidth(
        context,
        titles.isEmpty ? demoReminderTitles : titles,
      );
      final balancedColumns = (titles.length == 2 || titles.length == 4)
          ? 2
          : AccountingResponsive.balancedColumnCount(
              available,
              titles.length + (leadingCard == null ? 0 : 1),
              minItemWidth: minimumCardWidth,
            );
      final width =
          (available - (balancedColumns - 1) * AccountingResponsive.groupGap) /
          balancedColumns;
      return Wrap(
        spacing: AccountingResponsive.groupGap,
        runSpacing: AccountingResponsive.groupGap,
        children: [
          if (leadingCard != null)
            SizedBox(
              width: (titles.length == 2 || titles.length == 4)
                  ? available
                  : width,
              child: leadingCard!,
            ),
          for (var i = 0; i < titles.length; i++)
            SizedBox(
              width: width,
              child: _ReminderCard(
                key: ValueKey(reminders?[i].id.value ?? titles[i]),
                index: i,
                cardCount: titles.length,
                title: titles[i],
                record: reminders?[i],
                preferences: preferences,
                onSave: onSave,
                inline: titles.length <= 2 && width >= 560,
              ),
            ),
        ],
      );
    },
  );
}

class _ReminderCard extends StatefulWidget {
  const _ReminderCard({
    super.key,
    required this.index,
    required this.cardCount,
    required this.title,
    required this.inline,
    this.record,
    this.preferences,
    this.onSave,
  });
  final WorkspaceReminder? record;
  final CompanyPreferences? preferences;
  final ValueChanged<WorkspaceReminder>? onSave;
  final String title;
  final bool inline;
  final int index, cardCount;
  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  Color get _iconFill =>
      AccountingColorLibrary.reminderColor(widget.index, widget.cardCount);

  DateTime get _due => widget.record == null
      ? _demoDue
      : DateTime(
          widget.record!.dueDate.year,
          widget.record!.dueDate.month,
          widget.record!.dueDate.day,
          23,
          59,
          59,
        );
  late final DateTime _demoDue = DateTime.now().add(
    [
      const Duration(days: 5),
      const Duration(hours: 23, minutes: 59),
      const Duration(minutes: 35),
    ][widget.index % 3],
  );
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });
  bool _done = false, _expanded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.record != null
        ? widget.record!.displayStatus(DateTime.now(), widget.preferences!)
        : _done
        ? 'Completed'
        : _due.isBefore(DateTime.now())
        ? 'Overdue'
        : widget.index == 0
        ? 'Upcoming'
        : 'Due Soon';
    final compactStatus = switch (status) {
      'Upcoming' => 'Next',
      'Due Soon' => 'Soon',
      _ => null,
    };
    final badgeStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    double badgeWidth(String label) =>
        AccountingResponsive.measuredTextWidth(context, label, badgeStyle) + 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingDashboardCard(
          title: widget.title,
          icon: [
            Icons.badge_outlined,
            Icons.notifications_none,
            Icons.insert_chart_outlined,
          ][widget.index % 3],
          iconFillColor: _iconFill,
          iconArtwork: widget.record == null
              ? null
              : OriginalReminderIcon(
                  widget.record!.displayIcon,
                  color: AccountingTheme.of(context).primaryForeground,
                ),
          expanded: _expanded,
          hideStackedValue: true,
          preferredValueWidth: badgeWidth(status),
          preferredCompactValueWidth: compactStatus == null
              ? null
              : badgeWidth(compactStatus),
          compactValue: compactStatus == null
              ? null
              : AccountingBadge.build(context, label: compactStatus),
          onTap: () => setState(() => _expanded = !_expanded),
          value: AccountingBadge.build(context, label: status),
          detail: LayoutBuilder(
            builder: (context, constraints) {
              final style = AccountingTypography.sectionTitle(context)
                  .copyWith(height: 1);
              final remaining = _due.difference(DateTime.now());
              final full = reminderCountdown(remaining);
              // The shared card already reserves 20px before its trailing
              // item. Keep seconds only with additional room in this text
              // column; never squeeze or ellipsize the final time unit.
              final showSeconds =
                  constraints.maxWidth >
                  AccountingResponsive.measuredTextWidth(context, full, style);
              return Text(
                _done
                    ? 'Completed'
                    : reminderCountdown(remaining, includeSeconds: showSeconds),
                key: ValueKey(
                  'reminder-countdown-${widget.record?.id.value ?? widget.index}',
                ),
                style: style,
              );
            },
          ),
          expandedContent: !_expanded
              ? null
              : Padding(
                  // The header already contributes its 20px bottom inset.
                  padding: const EdgeInsets.fromLTRB(
                    accountingContentInset,
                    0,
                    accountingContentInset,
                    accountingContentInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.record == null
                            ? 'Illustrative demo deadline. Review the submission and supporting records.'
                            : [
                                widget.record!.obligation,
                                widget.record!.agency,
                                if (widget.record!.legalSource.isNotEmpty)
                                  'Source: ${widget.record!.legalSource}',
                                if (widget.record!.notes.isNotEmpty)
                                  widget.record!.notes,
                              ].join(' · '),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: AccountingTypography.helper(context),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: AccountingButton.outline(
                          context,
                          key: ValueKey(
                            'demo-reminder-complete-${widget.index}',
                          ),
                          onPressed: () {
                            if (widget.record != null) {
                              try {
                                widget.onSave?.call(
                                  widget.record!.withStatus(
                                    widget.record!.completed
                                        ? 'Not Started'
                                        : 'Submitted',
                                  ),
                                );
                              } catch (error) {
                                setState(() => _error = '$error');
                              }
                            } else {
                              setState(() => _done = !_done);
                            }
                          },
                          child: Text(_done ? 'Reopen' : 'Mark Complete'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
