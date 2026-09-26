import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'saved deadlines drive the nearest two, three and four Home cards at $width',
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
        final root = Directory.systemTemp.createTempSync(
          'audyt-home-reminders-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/company.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: RemindersPage(workspace: workspace)),
          ),
        );
        final today = DateTime.now();
        for (final (title, days, icon) in [
          ('SST Return', 7, 'Calculator'),
          ('Income Tax', 2, 'Taxes'),
          ('Annual Return', 30, 'Letter'),
          ('Payroll', 45, 'Money'),
          ('Permit', 60, 'Document'),
        ]) {
          await tester.tap(find.byKey(const ValueKey('new-reminder')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('reminder-name')),
            title,
          );
          await tester.enterText(
            find.byKey(const ValueKey('reminder-deadline-0')),
            formatAccountingInputDate(
              DateTime(today.year, today.month, today.day + days),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('reminder-icon-selector')),
          );
          await tester.pumpAndSettle();
          final choice = find.byKey(ValueKey('reminder-icon-$icon'));
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('reminder-save')));
          await tester.pumpAndSettle();
          expect(
            workspace.reminders
                .singleWhere((r) => r.title == title)
                .displayIcon,
            'Choice:$icon',
          );
        }
        expect(workspace.reminders, hasLength(5));
        final savedIds = {
          for (final record in workspace.reminders) record.title: record.id,
        };
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect({
          for (final record in workspace.reminders) record.title: record.id,
        }, savedIds);

        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/home',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        List<String> visibleTitles() => tester
            .widget<DemoReminderPanel>(find.byType(DemoReminderPanel))
            .reminders!
            .map((r) => r.title)
            .toList();
        expect(visibleTitles(), ['Income Tax', 'SST Return', 'Annual Return']);
        expect(
          tester
              .widget<DemoReminderPanel>(find.byType(DemoReminderPanel))
              .reminders!
              .map((r) => r.id)
              .toList(),
          [
            savedIds['Income Tax'],
            savedIds['SST Return'],
            savedIds['Annual Return'],
          ],
        );
        expect(
          tester
              .widgetList<AccountingDashboardCard>(
                find.descendant(
                  of: find.byType(DemoReminderPanel),
                  matching: find.byType(AccountingDashboardCard),
                ),
              )
              .map((card) => card.iconFillColor)
              .toList(),
          AccountingColorLibrary.reminderCycle.take(3).toList(),
        );
        if (width == 720) {
          expect(find.byKey(const ValueKey('home-kpi-card-1')), findsOneWidget);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('reminder-disclosure-Income Tax')),
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Three Saved Reminder Cards ${width.toInt()}');

        workspace.savePreferences(
          workspace.preferences.change('Reminders & Approvals', {
            'Visible Reminders': '2',
          }),
        );
        await tester.pumpAndSettle();
        expect(visibleTitles(), ['Income Tax', 'SST Return']);
        if (width == 720) {
          expect(find.byKey(const ValueKey('home-kpi-card-1')), findsNothing);
        }
        workspace.savePreferences(
          workspace.preferences.change('Reminders & Approvals', {
            'Visible Reminders': '4',
          }),
        );
        await tester.pumpAndSettle();
        expect(visibleTitles(), [
          'Income Tax',
          'SST Return',
          'Annual Return',
          'Payroll',
        ]);
        final displayed = tester
            .widget<DemoReminderPanel>(find.byType(DemoReminderPanel))
            .reminders!;
        final frames = [
          for (final record in displayed)
            tester.getRect(find.byKey(ValueKey(record.id.value))),
        ];
        expect(frames[0].top, closeTo(frames[1].top, .1));
        expect(frames[2].top, closeTo(frames[3].top, .1));
        expect(frames[2].top, greaterThan(frames[0].bottom));
        expect(frames[0].width, closeTo(frames[1].width, .1));
        expect(
          tester
              .widgetList<AccountingDashboardCard>(
                find.descendant(
                  of: find.byType(DemoReminderPanel),
                  matching: find.byType(AccountingDashboardCard),
                ),
              )
              .map((card) => card.iconFillColor)
              .toList(),
          AccountingColorLibrary.reminderCycle,
        );
        if (width == 720) {
          expect(find.byKey(const ValueKey('home-kpi-card-1')), findsNothing);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('reminder-disclosure-Income Tax')),
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Four Saved Reminder Cards ${width.toInt()}');
        Future<void> chooseVisibleReminders(String count) async {
          final settings = find.byKey(const ValueKey('accounting-settings'));
          await tester.ensureVisible(settings);
          await tester.tap(settings);
          await tester.pumpAndSettle();
          final section = find.text('Reminders & Approvals').first;
          await tester.ensureVisible(section);
          await tester.tap(section);
          await tester.pumpAndSettle();
          final selector = find.byKey(
            const ValueKey('design-field-Visible Reminders'),
          );
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, count));
          await tester.pumpAndSettle();
          final save = find.byKey(const ValueKey('design-save-settings'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(
            workspace.preferences.text(
              'Reminders & Approvals',
              'Visible Reminders',
            ),
            count,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(save, findsNothing);
        }

        await chooseVisibleReminders('2');
        expect(visibleTitles(), ['Income Tax', 'SST Return']);
        await captureUi(tester, 'Two Saved Reminder Cards From Settings ${width.toInt()}');
        await chooseVisibleReminders('4');
        expect(visibleTitles(), [
          'Income Tax',
          'SST Return',
          'Annual Return',
          'Payroll',
        ]);
        await captureUi(tester, 'Four Saved Reminder Cards From Settings ${width.toInt()}');
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(
          workspace.preferences.text(
            'Reminders & Approvals',
            'Visible Reminders',
          ),
          '4',
        );
        expect(workspace.reminders, hasLength(5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
