import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'reminder_popout_test.dart' show choose;
import 'restored_page_routes_test.dart' show tables;

WorkspaceReminder annual(WorkspaceReminder record) =>
    WorkspaceReminder.fromJson({
      ...record.toJson(),
      'mode': 'Repeating',
      'repeat': 'Repeating',
      'frequencyUnit': 'Year',
    }, revision: record.revision);

WorkspaceReminder completedOnce() => WorkspaceReminder(
  id: EntityId.random(),
  title: 'Annual Return',
  obligation: 'SSM Annual Return',
  agency: 'Reviewed Agency',
  dueDate: DateTime.now(),
  status: 'Submitted',
  notes: 'Retain completed occurrence.',
  legalSource: 'User-reviewed deadline',
  icon: 'Clock',
);

void main() {
  test('enabling yearly repeat on completed reminder creates one durable successor', () async {
    final dir = Directory.systemTemp.createTempSync('completed-reminder-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var w = await AccountingWorkspace.open(path);
    addTearDown(() => w.dispose());
    w.saveReminder(completedOnce());
    final completed = w.reminders.single;
    w.saveReminder(annual(completed));
    expect(w.reminders, hasLength(2));
    final next = w.reminders.last;
    expect(
      next.dueDate,
      DateTime(
        completed.dueDate.year + 1,
        completed.dueDate.month,
        completed.dueDate.day,
      ),
    );
    expect(next.status, 'Not Started');
    expect(next.seriesId, completed.id.value);
    expect(next.icon, completed.icon);
    expect(next.notes, completed.notes);
    expect(next.legalSource, completed.legalSource);
    expect(w.reminders.first.status, 'Submitted');
    final stale = w.reminders.first;
    w.saveReminder(stale);
    expect(w.reminders, hasLength(2));
    final beforeStale = tables(w);
    expect(() => w.saveReminder(stale.withStatus('Paid')), throwsStateError);
    expect(tables(w), beforeStale);
    w.saveReminder(w.reminders.first.withStatus('Paid'));
    expect(w.reminders, hasLength(2));
    // Editing old history after another anniversary must not add a second
    // outstanding occurrence while its existing successor remains saved.
    w.database.saveReminder(
      businessId: w.identity.businessId,
      actorId: w.identity.ownerId,
      reminder: w.reminders.first,
      savedAt: DateTime.now().toUtc(),
      asOfDate: DateTime(
        next.dueDate.year,
        next.dueDate.month,
        next.dueDate.day + 1,
      ),
    );
    expect(w.reminders, hasLength(2));
    final saved = tables(w);
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(tables(w), saved);
    expect(
      homeReminders(w.reminders, w.preferences, DateTime.now()).single.id,
      next.id,
    );
  });

  test('Not Applicable never creates an automatic successor', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    w.saveReminder(completedOnce().withStatus('Not Applicable'));
    w.saveReminder(annual(w.reminders.single));
    expect(w.reminders, hasLength(1));
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'completed yearly edit shows next countdown through actual pages at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final dir = Directory.systemTemp.createTempSync('reminder-repeat-ui-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final originalPath = '${dir.path}/original.sqlite';
        final original = await AccountingWorkspace.open(originalPath);
        original.saveReminder(completedOnce());
        final completed = original.reminders.single;
        final archive = original.database.exportDataArchive(
          original.identity.businessId,
          DateTime.now().toUtc(),
        );
        final baseline = tables(original);
        original.dispose();
        final originalBytes = File(originalPath).readAsBytesSync();
        final path = '${dir.path}/restored.sqlite';
        var w = await AccountingWorkspace.emptyRestore(path, archive);
        addTearDown(() => w.dispose());
        expect(tables(w), baseline);
        Future<void> tap(Finder target) async {
          if (target.hitTestable().evaluate().isEmpty) {
            await tester.ensureVisible(target);
          }
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Future<void> shell(String route) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(
                  workspace: w,
                  showInitialSetup: false,
                  initialPath: route,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await shell('/taxes');
        await tap(find.byKey(const ValueKey('preview-tab-taxes-3')));
        expect(find.byType(RemindersPage), findsOneWidget);
        await tap(find.byKey(ValueKey('edit-reminder-${completed.id.value}')));
        await choose(tester, 'reminder-mode', 'Repeating');
        await choose(tester, 'reminder-frequency-unit', 'Year');
        expect(find.text('Submitted'), findsOneWidget);
        await captureUi(
          tester,
          'Completed Yearly Reminder Edit ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('reminder-save')));
        expect(w.reminders, hasLength(2));
        final next = w.reminders.last;
        expect(
          next.dueDate,
          DateTime(
            completed.dueDate.year + 1,
            completed.dueDate.month,
            completed.dueDate.day,
          ),
        );
        expect(w.reminders.first.status, 'Submitted');
        expect(
          find.byKey(ValueKey('reminder-row-${next.id.value}')),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Completed Yearly Reminder Saved ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('navigation-item-home')));
        final panel = tester.widget<DemoReminderPanel>(
          find.byType(DemoReminderPanel),
        );
        expect(panel.reminders!.single.id, next.id);
        expect(find.text('Annual Return'), findsOneWidget);
        final endOfNextDay = DateTime(
          next.dueDate.year,
          next.dueDate.month,
          next.dueDate.day,
          23,
          59,
          59,
        );
        expect(
          find.text(reminderCountdown(endOfNextDay.difference(DateTime.now()))),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Next Year Reminder Countdown ${width.toInt()}',
        );
        // The Home completion button reaches the same durable service and
        // immediately replaces this occurrence with the following anniversary.
        await tap(
          find.byKey(const ValueKey('reminder-disclosure-Annual Return')),
        );
        await tap(find.byKey(const ValueKey('demo-reminder-complete-0')));
        expect(w.reminders, hasLength(3));
        final following = w.reminders.last;
        expect(
          following.dueDate,
          DateTime(next.dueDate.year + 1, next.dueDate.month, next.dueDate.day),
        );
        expect(
          tester
              .widget<DemoReminderPanel>(find.byType(DemoReminderPanel))
              .reminders!
              .single
              .id,
          following.id,
        );
        final saved = tables(w);
        for (final entry in baseline.entries) {
          if (!['workspace_reminders', 'ledger_audit'].contains(entry.key)) {
            expect(
              saved[entry.key],
              entry.value,
              reason: 'Reminder changes must leave ${entry.key} intact.',
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(tables(w), saved);
        await shell('/home');
        expect(
          tester
              .widget<DemoReminderPanel>(find.byType(DemoReminderPanel))
              .reminders!
              .single
              .id,
          following.id,
        );
        await captureUi(tester, 'Yearly Reminder Restart ${width.toInt()}');
        expect(File(originalPath).readAsBytesSync(), originalBytes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
