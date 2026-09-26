import '../../../core/ids/entity_id.dart';
import 'company_preferences.dart';

/// A reviewed, user-entered deadline. No statutory due date is inferred.
final class WorkspaceReminder {
  WorkspaceReminder({
    required this.id,
    required String title,
    required this.obligation,
    required this.agency,
    required DateTime dueDate,
    this.triggerDate,
    this.leadDays,
    this.status = 'Not Started',
    this.notes = '',
    this.legalSource = '',
    this.revision = 0,
    this.icon = 'Calendar',
    this.mode = 'Once',
    this.repeat = 'Never',
    this.seriesId,
    this.repeatAnchor,
    this.frequencyEvery = 1,
    this.frequencyUnit = 'Month',
  }) : title = title.trim(),
       dueDate = DateTime(dueDate.year, dueDate.month, dueDate.day) {
    if (this.title.isEmpty ||
        this.title.length > 120 ||
        !obligations.contains(obligation) ||
        !statuses.contains(status) ||
        (leadDays != null && (leadDays! < 0 || leadDays! > 365)) ||
        notes.length > 4000 ||
        legalSource.length > 4000 ||
        !reminderOriginalIcons.containsKey(icon) ||
        !['Once', 'Repeating', 'Custom Dates'].contains(mode) ||
        !repeatOptions.contains(repeat) ||
        frequencyEvery < 1 ||
        frequencyEvery > maxFrequencyFor(frequencyUnit) ||
        !frequencyUnits.contains(frequencyUnit)) {
      throw const FormatException('Complete a valid reminder and due date.');
    }
  }
  final EntityId id;
  final String title, obligation, agency, status, notes, legalSource;
  final DateTime dueDate;
  final DateTime? triggerDate;
  final int? leadDays;
  final int revision;
  final String icon, repeat, frequencyUnit, mode;
  final int frequencyEvery;
  String get displayIcon => icon == 'Calendar'
      ? switch (obligation) {
          'SSM Annual Return' => 'Choice:Letter',
          'Income Tax Return' => 'Choice:Taxes',
          'SST Return' || 'SST Payment' => 'Choice:Calculator',
          _ => 'Choice:Calendar',
        }
      : icon;
  static const nameLimit = 16;
  static const frequencyUnits = [
    'Day',
    'Week',
    'Month',
    'Quarter',
    '6 Months',
    'Year',
    '2 Years',
    '3 Years',
    '4 Years',
    '5 Years',
  ];
  String get effectiveFrequencyUnit => switch (repeat) {
    'Weekly' => 'Week',
    'Monthly' => 'Month',
    'Quarterly' => 'Quarter',
    'Yearly' => 'Year',
    _ => frequencyUnit,
  };
  final String? seriesId;
  final DateTime? repeatAnchor;
  static const repeatOptions = [
    'Never',
    'Repeating',
    'Weekly',
    'Monthly',
    'Quarterly',
    'Yearly',
  ];

  static const obligations = [
    'SST Return',
    'SST Payment',
    'Income Tax Return',
    'Tax Estimate Instalment',
    'Withholding Tax',
    'SSM Annual Return',
    'Financial Statements',
    'Other',
  ];
  static const statuses = [
    'Not Started',
    'Preparing',
    'Submitted',
    'Paid',
    'Not Applicable',
  ];
  bool get completed =>
      ['Submitted', 'Paid', 'Not Applicable'].contains(status);
  int effectiveLeadDays(CompanyPreferences preferences) =>
      leadDays ??
      int.parse(
        preferences.text('Reminders & Approvals', 'Days Before Due Date'),
      );
  bool overdue(DateTime now) =>
      dueDate.isBefore(DateTime(now.year, now.month, now.day));
  String displayStatus(DateTime now, CompanyPreferences preferences) =>
      completed
      ? 'Completed'
      : overdue(now)
      ? 'Overdue'
      : dueDate.difference(DateTime(now.year, now.month, now.day)).inDays <=
            effectiveLeadDays(preferences)
      ? 'Due Soon'
      : 'Upcoming';
  WorkspaceReminder withStatus(String value) => WorkspaceReminder(
    id: id,
    title: title,
    obligation: obligation,
    agency: agency,
    dueDate: dueDate,
    triggerDate: triggerDate,
    leadDays: leadDays,
    status: value,
    notes: notes,
    legalSource: legalSource,
    revision: revision,
    icon: icon,
    mode: mode,
    repeat: repeat,
    seriesId: seriesId,
    repeatAnchor: repeatAnchor,
    frequencyEvery: frequencyEvery,
    frequencyUnit: frequencyUnit,
  );
  Map<String, Object?> toJson() => {
    'icon': icon,
    'mode': mode,
    'repeat': repeat,
    'seriesId': seriesId,
    'repeatAnchor': repeatAnchor?.toIso8601String(),
    'frequencyEvery': frequencyEvery,
    'frequencyUnit': frequencyUnit,
    'id': id.value,
    'title': title,
    'obligation': obligation,
    'agency': agency,
    'dueDate': dueDate.toIso8601String(),
    'triggerDate': triggerDate?.toIso8601String(),
    'leadDays': leadDays,
    'status': status,
    'notes': notes,
    'legalSource': legalSource,
  };
  factory WorkspaceReminder.fromJson(
    Map<String, dynamic> json, {
    int revision = 0,
  }) => WorkspaceReminder(
    id: EntityId.parse(json['id'] as String),
    title: json['title'] as String,
    obligation: json['obligation'] as String,
    agency: json['agency'] as String,
    dueDate: DateTime.parse(json['dueDate'] as String),
    triggerDate: json['triggerDate'] == null
        ? null
        : DateTime.parse(json['triggerDate'] as String),
    leadDays: json['leadDays'] as int?,
    status: json['status'] as String,
    notes: json['notes'] as String,
    legalSource: json['legalSource'] as String,
    revision: revision,
    icon: json['icon'] as String? ?? 'Calendar',
    mode:
        json['mode'] as String? ??
        (json['repeat'] != null && json['repeat'] != 'Never'
            ? 'Repeating'
            : 'Once'),
    repeat: json['repeat'] as String? ?? 'Never',
    frequencyEvery: json['frequencyEvery'] as int? ?? 1,
    frequencyUnit: json['frequencyUnit'] as String? ?? 'Month',
    seriesId: json['seriesId'] as String?,
    repeatAnchor: json['repeatAnchor'] == null
        ? null
        : DateTime.parse(json['repeatAnchor'] as String),
  );

  WorkspaceReminder? nextOccurrence(DateTime now) {
    if (repeat == 'Never') return null;
    final anchor = repeatAnchor ?? dueDate;
    var next = dueDate;
    do {
      if (effectiveFrequencyUnit == 'Day' || effectiveFrequencyUnit == 'Week') {
        next = DateTime(
          next.year,
          next.month,
          next.day +
              frequencyEvery * (effectiveFrequencyUnit == 'Week' ? 7 : 1),
        );
      } else {
        final step =
            frequencyEvery *
            switch (effectiveFrequencyUnit) {
              'Month' => 1,
              'Quarter' => 3,
              '6 Months' => 6,
              'Year' => 12,
              '2 Years' => 24,
              '3 Years' => 36,
              '4 Years' => 48,
              '5 Years' => 60,
              _ => 1,
            };
        final month = DateTime(next.year, next.month + step);
        final lastDay = DateTime(month.year, month.month + 1, 0).day;
        next = DateTime(
          month.year,
          month.month,
          anchor.day > lastDay ? lastDay : anchor.day,
        );
      }
    } while (next.isBefore(reminderFirstDate(now)));
    if (next.isAfter(reminderLastDate(now))) return null;
    return WorkspaceReminder(
      id: EntityId.random(),
      title: title,
      obligation: obligation,
      agency: agency,
      dueDate: next,
      leadDays: leadDays,
      notes: notes,
      legalSource: legalSource,
      icon: icon,
      mode: 'Repeating',
      repeat: repeat,
      seriesId: seriesId ?? id.value,
      repeatAnchor: anchor,
      frequencyEvery: frequencyEvery,
      frequencyUnit: frequencyUnit,
    );
  }
}

List<WorkspaceReminder> homeReminders(
  Iterable<WorkspaceReminder> records,
  CompanyPreferences preferences,
  DateTime now,
) {
  final visible =
      records
          .where(
            (record) =>
                !record.completed &&
                (!record.overdue(now) ||
                    preferences.enabled(
                      'Reminders & Approvals',
                      'Notify When Overdue',
                    )),
          )
          .toList()
        ..sort((a, b) {
          final date = a.dueDate.compareTo(b.dueDate);
          return date != 0 ? date : a.id.value.compareTo(b.id.value);
        });
  return visible
      .take(
        int.parse(
          preferences.text('Reminders & Approvals', 'Visible Reminders'),
        ),
      )
      .toList();
}

DateTime reminderFirstDate(DateTime now) =>
    DateTime(now.year, now.month, now.day);
DateTime reminderLastDate(DateTime now) {
  final year = now.year + 10;
  final lastDay = DateTime(year, now.month + 1, 0).day;
  return DateTime(year, now.month, now.day > lastDay ? lastDay : now.day);
}

bool validNewReminderDate(DateTime value, DateTime now) =>
    !value.isBefore(reminderFirstDate(now)) &&
    !value.isAfter(reminderLastDate(now));

/// The current picker offers exactly the supplied collection, unchanged.
const reminderSelectableIcons = <String, String>{
  'Invoice': '001-invoice.svg',
  'History': '002-history.svg',
  'Receive Mail': '003-receive-mail.svg',
  'Stats': '004-stats.svg',
  'Bar Chart': '005-bar-chart.svg',
  'List': '006-list.svg',
  'Money': '007-money.svg',
  'Calendar': '008-calendar.svg',
  'Clock': '009-clock.svg',
  'Dollar': '010-dollar.svg',
  'Document': '011-document.svg',
  'Tax': '012-tax.svg',
  'Discount': '013-discount.svg',
  'Dollar 1': '014-dollar-1.svg',
  'Letter': '015-letter.svg',
  'Calendar 1': '016-calendar-1.svg',
  'Meeting Room': '017-meeting-room.svg',
  'File': '018-file.svg',
  'Calendar 2': '019-calendar-2.svg',
  'Video Call': '020-videocall.svg',
  'Quote Request': '021-quote-request.svg',
  'Printer': '022-printer.svg',
  '30 Days': '023-30-days.svg',
  'Calculator': '024-calculator.svg',
  'Car': '025-car.svg',
  'House': '026-house.svg',
  'Taxes': '027-taxes.svg',
  'Preview': '028-preview.svg',
  'Download PDF': '029-download-pdf.svg',
  'File 1': '030-file-1.svg',
  'Files': '031-files.svg',
  'Money Bag': '032-money-bag.svg',
  'Currency': '033-currency.svg',
  'Pension': '034-pension.svg',
  'Cashier': '035-cashier.svg',
  'Building': '036-building.svg',
  'Money Box': '037-money-box.svg',
  'Schedule': '038-schedule.svg',
  'Box': '039-box.svg',
  'Delivery': '040-delivery.svg',
  'Security Guard': '041-security-guard.svg',
  'Telephone': '042-telephone.svg',
  'Notification': '043-notification.svg',
  'Folder': '044-folder.svg',
};

/// Historical names remain readable; their artwork follows the new collection.
/// New choices have explicit IDs so a saved Calendar choice is never replaced
/// by the obligation-specific presentation of an old default Calendar.
final reminderOriginalIcons = <String, String>{
  for (final entry in reminderSelectableIcons.entries)
    'Choice:${entry.key}': entry.value,
  ...reminderSelectableIcons,
  'Delete': reminderSelectableIcons['File']!,
  'Image': reminderSelectableIcons['File']!,
  'Equalizer': reminderSelectableIcons['Stats']!,
  'Show': reminderSelectableIcons['Preview']!,
  'Edit': reminderSelectableIcons['File']!,
  'Broken Link': reminderSelectableIcons['Files']!,
  'Link': reminderSelectableIcons['Files']!,
  'Download': reminderSelectableIcons['Download PDF']!,
  'Checklist': reminderSelectableIcons['List']!,
  'Account': reminderSelectableIcons['Invoice']!,
  'Coupon': reminderSelectableIcons['Discount']!,
  'History 1': reminderSelectableIcons['History']!,
  'User': reminderSelectableIcons['Meeting Room']!,
  '6 Month': reminderSelectableIcons['Schedule']!,
  'Quarter': reminderSelectableIcons['Calendar 2']!,
  'Cash Register': reminderSelectableIcons['Cashier']!,
  'Loan': reminderSelectableIcons['Money Box']!,
  'Menu': reminderSelectableIcons['List']!,
  'Menu 1': reminderSelectableIcons['List']!,
  'Import Export': reminderSelectableIcons['Files']!,
  'Location': reminderSelectableIcons['Building']!,
  'Refund': reminderSelectableIcons['Currency']!,
  'Stock Market': reminderSelectableIcons['Stats']!,
  'Sync': reminderSelectableIcons['Schedule']!,
};

/// Keep each recurrence interval within the reminder's ten-year date horizon.
int maxFrequencyFor(String unit) => switch (unit) {
  'Quarter' => 40,
  '6 Months' => 20,
  'Year' => 10,
  '2 Years' => 5,
  '3 Years' => 3,
  '4 Years' => 2,
  '5 Years' => 2,
  _ => 100,
};
