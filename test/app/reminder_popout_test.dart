import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/presentation/reminder_form_dialog.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:flutter_test/flutter_test.dart';

Future<void> choose(WidgetTester tester, String key, String label) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(MenuItemButton, label));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label));
  await tester.pumpAndSettle();
}

Future<void> reminderView(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
}

void checkReminderColumns(
  WidgetTester tester, {
  bool repeating = false,
  bool editing = false,
}) {
  Rect frame(String key) => tester.getRect(find.byKey(ValueKey(key)));
  final name = frame('reminder-name');
  final mode = frame('reminder-mode');
  final icon = frame('reminder-icon-selector');
  final deadline = frame('reminder-deadline-0');
  final modeValue = tester
      .widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey == const ValueKey('reminder-mode'),
        ),
      )
      .value;
  final custom = modeValue == 'Custom Dates';
  expect(mode.top, closeTo(name.top, .1));
  expect(mode.left - name.right, closeTo(20, .1));
  expect(mode.width, closeTo(name.width, .1));
  if (custom) {
    expect(deadline.left, name.left);
    expect(deadline.top, greaterThan(name.top));
    // The custom date/appearance pair retains its original half-width owner.
    expect(icon.left, mode.left);
    expect(icon.right, closeTo(mode.right, .1));
  } else {
    expect(deadline.top, closeTo(name.top, .1));
    expect(deadline.left - mode.right, closeTo(20, .1));
    expect(deadline.width, closeTo(name.width, .1));
    if (repeating) {
      final number = frame('reminder-frequency-number');
      final unit = frame('reminder-frequency-unit');
      expect(number.left, name.left);
      expect(unit.left - number.right, closeTo(20, .1));
      expect(unit.top, closeTo(number.top, .1));
      expect(icon.top, closeTo(number.top, .1));
      expect(icon.left - unit.right, closeTo(20, .1));
      expect(icon.width, closeTo(unit.right - number.left, .1));
    } else {
      expect(icon.left, name.left);
    }
  }
  if (editing) {
    final status = frame('reminder-status');
    expect(status.left, name.left);
    expect(
      status.width,
      closeTo(mode.right - name.left + (custom ? 0 : deadline.width + 20), .1),
    );
    expect(status.top, greaterThan(icon.top));
  }
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'custom dates share Close column, recover full width and save at $width',
      (tester) async {
        await reminderView(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: RemindersPage(workspace: workspace)),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('new-reminder')));
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('reminder-deadline-0'));
        checkReminderColumns(tester);
        await captureUi(tester, 'Reminder Full Columns Once ${width.toInt()}');
        await tester.enterText(
          find.byKey(const ValueKey('reminder-name')),
          'Annual Return Plus Too Long',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('reminder-name')),
              )
              .controller!
              .text
              .length,
          16,
        );
        await choose(tester, 'reminder-mode', 'Custom Dates');
        final second = find.byKey(const ValueKey('reminder-deadline-1'));
        expect(second, findsOneWidget);
        final a = tester.getRect(first), b = tester.getRect(second);
        final closeA = tester.getRect(
          find.byKey(const ValueKey('remove-reminder-date-0')),
        );
        final closeB = tester.getRect(
          find.byKey(const ValueKey('remove-reminder-date-1')),
        );
        checkReminderColumns(tester);
        await captureUi(
          tester,
          'Reminder Full Columns Custom ${width.toInt()}',
        );
        final customWidth = closeA.right - a.left;
        expect(a.width, lessThan(customWidth));
        expect(a.right, b.right);
        expect(closeA.left - a.right, closeTo(10, .1));
        expect(closeB.left - b.right, closeTo(10, .1));
        await tester.tap(find.byKey(const ValueKey('remove-reminder-date-0')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('remove-reminder-date-0')),
          findsNothing,
        );
        expect(tester.getRect(first).width, closeTo(customWidth, .1));
        await tester.tap(find.byKey(const ValueKey('reminder-add-date')));
        await tester.pumpAndSettle();
        await tester.enterText(
          second,
          formatAccountingInputDate(
            DateTime.now().add(const Duration(days: 3)),
          ),
        );
        final footer = find.byKey(
          const ValueKey('accounting-form-dialog-footer'),
        );
        expect(footer, findsOneWidget);
        final save = find.byKey(const ValueKey('reminder-save'));
        expect(
          tester.getRect(save).right,
          closeTo(tester.getRect(footer).right - 20, .1),
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(workspace.reminders, hasLength(2));
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets('edited repeating reminder fills both columns at $width', (
      tester,
    ) async {
      await reminderView(tester, width);
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final reminder = WorkspaceReminder.fromJson({
        'id': 'd3c585e1-f2e8-4a47-9872-e23ad3a6865a',
        'title': 'Annual Return',
        'obligation': 'Other',
        'agency': 'Other',
        'dueDate': DateTime.now().toIso8601String(),
        'status': 'Not Started',
        'notes': '',
        'legalSource': '',
        'mode': 'Repeating',
        'repeat': 'Repeating',
        'frequencyEvery': 1,
        'frequencyUnit': 'Year',
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ReminderFormDialog(
                      workspace: workspace,
                      reminder: reminder,
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      checkReminderColumns(tester, repeating: true, editing: true);
      await captureUi(
        tester,
        'Reminder Full Columns Repeating ${width.toInt()}',
      );
      await choose(tester, 'reminder-mode', 'Once');
      checkReminderColumns(tester, editing: true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'repeating shows number and unit; Save persists selected frequency and appearance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
        'Annual Return',
      );
      expect(find.text('Frequency'), findsNothing);
      await choose(tester, 'reminder-mode', 'Repeating');
      expect(find.text('Frequency'), findsOneWidget);
      await choose(tester, 'reminder-frequency-unit', '5 Years');
      await choose(tester, 'reminder-frequency-number', '2');
      await tester.tap(find.byKey(const ValueKey('reminder-icon-selector')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('reminder-icon-Clock')),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-icon-Clock')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-save')));
      await tester.pumpAndSettle();
      final saved = workspace.reminders.single;
      expect(saved.repeat, 'Repeating');
      expect(saved.frequencyEvery, 2);
      expect(saved.frequencyUnit, '5 Years');
      expect(
        find.byKey(const ValueKey('reminder-colour-selector')),
        findsNothing,
      );
      expect(saved.icon, 'Choice:Clock');
      workspace.saveReminder(saved.withStatus('Submitted'));
      expect(workspace.reminders, hasLength(2));
      expect(workspace.reminders.last.dueDate.year, saved.dueDate.year + 10);
      expect(tester.takeException(), isNull);
    },
  );
}
