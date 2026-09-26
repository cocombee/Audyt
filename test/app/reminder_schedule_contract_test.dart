import 'dart:io';

import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceReminder reminder(DateTime date, {String repeat = 'Never'}) =>
    WorkspaceReminder(
      id: EntityId.random(),
      title: 'Reviewed Date',
      obligation: 'Other',
      agency: 'Other',
      dueDate: date,
      icon: 'Clock',
      repeat: repeat,
    );
void main() {
  test('untouched original SVGs can be selected', () {
    for (final file in reminderOriginalIcons.values) {
      expect(
        File('assets/icons/reminder_originals/$file').readAsBytesSync(),
        File('tool/user_icon_originals/$file').readAsBytesSync(),
        reason: file,
      );
    }
  });
  test('all records retained, Home sorts nearest first and limits to 2–4', () {
    final now = DateTime.now();
    final records = [
      for (var day = 8; day >= 0; day--) reminder(now.add(Duration(days: day))),
    ];
    for (final count in ['2', '3', '4']) {
      final prefs = CompanyPreferences.defaults().change(
        'Reminders & Approvals',
        {'Visible Reminders': count},
      );
      final shown = homeReminders(records, prefs, now);
      expect(shown.length, int.parse(count));
      expect(shown.first.dueDate, reminderFirstDate(now));
      expect(records, hasLength(9));
    }
    expect(
      () => CompanyPreferences.defaults().change('Reminders & Approvals', {
        'Visible Reminders': '1',
      }),
      throwsFormatException,
    );
    expect(
      homeReminders([records.last], CompanyPreferences.defaults(), now),
      hasLength(1),
    );
  });
  test('all frequency units fit within the date horizon', () {
    for (final unit in WorkspaceReminder.frequencyUnits) {
      final every = maxFrequencyFor(unit);
      final record = WorkspaceReminder(
        id: EntityId.random(),
        title: 'Repeat',
        obligation: 'Other',
        agency: 'Other',
        dueDate: DateTime.now(),
        repeat: 'Repeating',
        frequencyEvery: every,
        frequencyUnit: unit,
      );
      expect(record.nextOccurrence(DateTime.now()), isNotNull, reason: unit);
    }
  });
  test('month end and leap anniversaries retain original date anchor', () {
    final jan = reminder(DateTime(2028, 1, 31), repeat: 'Monthly');
    final feb = jan.nextOccurrence(DateTime(2028, 1, 31))!;
    expect(feb.dueDate, DateTime(2028, 2, 29));
    expect(
      feb.nextOccurrence(DateTime(2028, 2, 29))!.dueDate,
      DateTime(2028, 3, 31),
    );
    final leap = reminder(DateTime(2028, 2, 29), repeat: 'Yearly');
    var next = leap;
    for (var i = 0; i < 4; i++) {
      next = next.nextOccurrence(next.dueDate)!;
    }
    expect(next.dueDate, DateTime(2032, 2, 29));
    expect(
      jan.nextOccurrence(DateTime(2029, 4, 5))!.dueDate,
      DateTime(2029, 4, 30),
    );
  });
  test('multi-date save rolls back together; completion adds one next date and survives restart', () async {
    final root = Directory.systemTemp.createTempSync('audyt-reminder-series-');
    addTearDown(() => root.deleteSync(recursive: true));
    var workspace = await AccountingWorkspace.open(
      '${root.path}/ledger.sqlite',
    );
    final now = reminderFirstDate(DateTime.now());
    final repeated = reminder(now, repeat: 'Monthly');
    expect(
      () => workspace.saveReminders([
        repeated,
        reminder(now.subtract(const Duration(days: 1))),
      ]),
      throwsFormatException,
    );
    expect(workspace.reminders, isEmpty);
    workspace.saveReminders([
      repeated,
      reminder(now.add(const Duration(days: 5))),
    ]);
    workspace.saveReminder(workspace.reminders.first.withStatus('Submitted'));
    expect(workspace.reminders, hasLength(3));
    final future = workspace.reminders.last;
    expect(future.icon, 'Clock');
    expect(future.seriesId, repeated.id.value);
    final completed = workspace.reminders.first;
    workspace.saveReminder(completed.withStatus('Submitted'));
    expect(workspace.reminders, hasLength(3));
    expect(
      () => workspace.saveReminder(completed.withStatus('Paid')),
      throwsStateError,
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open('${root.path}/ledger.sqlite');
    addTearDown(workspace.dispose);
    expect(workspace.reminders, hasLength(3));
    expect(workspace.reminders.last.repeat, 'Monthly');
  });
  for (final count in [2, 3, 4]) {
    testWidgets('colour cycle and compact bank omission for $count reminders', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(620, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      workspace.savePreferences(
        workspace.preferences.change('Reminders & Approvals', {
          'Visible Reminders': '$count',
        }),
      );
      workspace.saveReminders([
        for (var n = 0; n < count; n++)
          reminder(DateTime.now().add(Duration(days: n))),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: WorkspaceAccountingHome(workspace: workspace, includeTopSafeArea: true, onRecordExpense: () {})),
        ),
      );
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<AccountingDashboardCard>(
            find.byType(AccountingDashboardCard),
          )
          .toList();
      expect(cards, hasLength(count));
      expect(
        cards.map((card) => card.iconFillColor),
        AccountingColorLibrary.reminderCycle.take(count),
      );
      expect(
        find.byKey(const ValueKey('home-kpi-card-1')),
        count == 3 ? findsOneWidget : findsNothing,
      );
      if (count < 4) {
        expect(
          cards.any(
            (card) => card.iconFillColor == AccountingColorLibrary.primaryGreen,
          ),
          false,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final width in [620.0, 1124.0]) {
    testWidgets('four reminders are 2 + 2 at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final records = [
        for (var n = 0; n < 4; n++)
          reminder(DateTime.now().add(Duration(days: n))),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: DemoReminderPanel(
              reminders: records,
              preferences: CompanyPreferences.defaults(),
            ),
          ),
        ),
      );
      final cards = find.byType(AccountingDashboardCard);
      expect(cards, findsNWidgets(4));
      expect(
        tester.getTopLeft(cards.at(0)).dy,
        tester.getTopLeft(cards.at(1)).dy,
      );
      expect(
        tester.getTopLeft(cards.at(2)).dy,
        tester.getTopLeft(cards.at(3)).dy,
      );
      expect(
        tester.getTopLeft(cards.at(2)).dy,
        greaterThan(tester.getBottomLeft(cards.at(0)).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
