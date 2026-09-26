import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/audyt_date_picker.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reminder commands enforce today through ten years and preserve overdue history', () async {
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    final today = DateTime(2028, 2, 29);
    void save(DateTime due) => workspace.database.saveReminder(
      businessId: workspace.identity.businessId,
      actorId: workspace.identity.ownerId,
      reminder: WorkspaceReminder(
        id: EntityId.random(),
        title: 'Reminder',
        obligation: 'Other',
        agency: 'Other',
        dueDate: due,
      ),
      savedAt: today,
      asOfDate: today,
    );
    expect(() => save(DateTime(2028, 2, 28)), throwsFormatException);
    save(today);
    save(DateTime(2038, 2, 28));
    expect(() => save(DateTime(2038, 3, 1)), throwsFormatException);
    final past = workspace.reminders.first;
    workspace.database.saveReminder(
      businessId: workspace.identity.businessId,
      actorId: workspace.identity.ownerId,
      reminder: past.withStatus('Submitted'),
      savedAt: DateTime(2029),
      asOfDate: DateTime(2029),
    );
    expect(workspace.reminders.first.dueDate, today);
    expect(workspace.reminders.first.status, 'Submitted');
  });
  test('three saved reminder types survive restart, settings, completion and archive restore', () async {
    final root = Directory.systemTemp.createTempSync('audyt-reminder-audit-');
    addTearDown(() => root.deleteSync(recursive: true));
    var workspace = await AccountingWorkspace.open(
      '${root.path}/ledger.sqlite',
    );
    final now = DateTime(2026, 12, 31);
    for (final spec in [
      ('SST Return', 'SST Return', -1),
      ('Income Tax', 'Income Tax Return', 2),
      ('Annual Return', 'SSM Annual Return', 30),
    ]) {
      workspace.saveReminder(
        WorkspaceReminder(
          id: EntityId.random(),
          title: spec.$1,
          obligation: spec.$2,
          agency: 'Other',
          dueDate: now.add(Duration(days: spec.$3)),
          legalSource: 'Reviewed test schedule',
        ),
      );
    }
    final business = workspace.identity.businessId;
    workspace.dispose();
    workspace = await AccountingWorkspace.open('${root.path}/ledger.sqlite');
    addTearDown(workspace.dispose);
    expect(workspace.identity.businessId, business);
    expect(workspace.reminders, hasLength(3));
    expect(
      homeReminders(
        workspace.reminders,
        workspace.preferences,
        now,
      ).map((r) => r.title),
      ['SST Return', 'Income Tax', 'Annual Return'],
    );
    final income = workspace.reminders.firstWhere(
      (r) => r.title == 'Income Tax',
    );
    expect(income.displayStatus(now, workspace.preferences), 'Due Soon');
    workspace.savePreferences(
      workspace.preferences.change('Reminders & Approvals', {
        'Days Before Due Date': '1',
        'Notify When Overdue': false,
      }),
    );
    expect(income.displayStatus(now, workspace.preferences), 'Upcoming');
    expect(
      homeReminders(
        workspace.reminders,
        workspace.preferences,
        now,
      ).map((r) => r.title),
      ['Income Tax', 'Annual Return'],
    );
    workspace.savePreferences(
      workspace.preferences.change('Reminders & Approvals', {
        'Days Before Due Date': '14',
        'Notify When Overdue': true,
      }),
    );
    workspace.saveReminder(income.withStatus('Submitted'));
    expect(
      homeReminders(
        workspace.reminders,
        workspace.preferences,
        now,
      ).map((r) => r.title),
      ['SST Return', 'Annual Return'],
    );
    expect(
      () => workspace.saveReminder(income.withStatus('Paid')),
      throwsStateError,
    );
    final archive = workspace.database.exportDataArchive(business, now);
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    addTearDown(restored.dispose);
    expect(
      restored.reminders.map((r) => r.toJson()),
      workspace.reminders.map((r) => r.toJson()),
    );
  });

  testWidgets(
    'reminders page creates a durable reminder, Home completes same record',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: RemindersPage(workspace: workspace)),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('new-reminder')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reminder-name')),
        'SST Return',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-deadline-0')),
        '01-01-2027',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-save')));
      await tester.pumpAndSettle();
      expect(workspace.reminders.single.title, 'SST Return');
      expect(workspace.reminders.single.dueDate, DateTime(2027, 1, 1));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: workspace,
              builder: (context, _) => DemoReminderPanel(
                reminders: homeReminders(
                  workspace.reminders,
                  workspace.preferences,
                  DateTime(2026),
                ),
                preferences: workspace.preferences,
                onSave: workspace.saveReminder,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reminder-disclosure-SST Return')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();
      expect(workspace.reminders.single.status, 'Submitted');
      expect(find.text('SST Return'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final year in [2026, 2027]) {
    testWidgets('year selector rolls its 100-year window in $year', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AudytDatePickerDialog(
              today: DateTime(year, 1, 1),
              initialDate: DateTime(year, 1, 1),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            ),
          ),
        ),
      );
      final selector = tester.widget<AccountingSelector<int>>(
        find.byType(AccountingSelector<int>).first,
      );
      expect(selector.options.first.value, year - 100);
      expect(selector.value, year);
      await tester.tap(find.byKey(const ValueKey('audyt-year-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('audyt-year-search')),
        '${year - 101}',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('audyt-date-year-${year - 101}')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'calendar crosses December to January and rejects non-leap February 29',
    (tester) async {
      DateTime? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showDialog<DateTime>(
                    context: context,
                    builder: (_) => AudytDatePickerDialog(
                      today: DateTime(2026),
                      initialDate: DateTime(2026, 12, 31),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2030),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('Next month')));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);
      expect(find.text('January'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('Next month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('audyt-date-day-29')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('audyt-date-day-28')));
      await tester.tap(find.byKey(const ValueKey('audyt-date-select')));
      await tester.pumpAndSettle();
      expect(saved, DateTime(2027, 2, 28));
    },
  );

  for (final dialog in [false, true]) {
    testWidgets(
      'wrapped controls use ${dialog ? 20 : 10}px in ${dialog ? 'dialog' : 'page'}',
      (tester) async {
        Widget controls() => SizedBox(
          width: 420,
          child: AccountingControlFlow(
            children: [
              for (final i in [0, 1, 2])
                SizedBox(key: ValueKey('control-$i'), width: 180, height: 44),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: dialog ? Dialog(child: controls()) : controls(),
            ),
          ),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('control-2'))).top -
              tester.getRect(find.byKey(const ValueKey('control-0'))).bottom,
          dialog ? 20 : 10,
        );
      },
    );
  }
}
