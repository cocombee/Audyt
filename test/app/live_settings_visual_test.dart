import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [1224.0, 720.0]) {
    testWidgets(
      'real workspace settings, reminders and row rendering at $width',
      (tester) async {
        if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] == null) return;
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: workspace, showInitialSetup: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Live Home ${width.toInt()}');
        workspace.savePreferences(
          workspace.preferences.change('Reminders & Approvals', {
            'Visible Reminders': '4',
          }),
        );
        workspace.saveReminder(
          WorkspaceReminder(
            id: EntityId.random(),
            title: 'Custom Reminder',
            obligation: 'Other',
            agency: 'Other',
            dueDate: DateTime.now().add(const Duration(days: 7)),
            icon: 'Clock',
          ),
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(
            find.byKey(ValueKey(workspace.reminders.last.id.value)),
          ),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Four Reminder Cards ${width.toInt()}');
        await tester.tap(
          find.byKey(const ValueKey('navigation-item-sales-customers')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(Tab, 'Invoices'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Live Invoice Rows ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('navigation-item-taxes')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(Tab, 'Deadlines'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('new-reminder')), findsOneWidget);
        expect(workspace.reminders, hasLength(4));
        await captureUi(tester, 'Live Reminders ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('new-reminder')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('reminder-name')),
          'Annual Return',
        );
        await captureUi(tester, 'Reminder Once Popout ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('reminder-mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Repeating'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Reminder Repeating Popout ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('reminder-mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Custom Dates'));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Reminder Custom Dates Popout ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('reminder-icon-selector')));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Reminder Original Icons ${width.toInt()}');
        expect(
          find.byKey(const ValueKey('reminder-icon-grid')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('reminder-icon-grid')), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(IconButton),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('accounting-settings')));
        await tester.pumpAndSettle();
        for (final title in [
          'Sales Preferences',
          'Purchase Preferences',
          'Reminders & Approvals',
        ]) {
          await tester.ensureVisible(find.text(title).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(title).first);
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const ValueKey('design-save-settings'))),
            alignment: 1,
          );
          await tester.pumpAndSettle();
          await captureUi(tester, 'Live $title ${width.toInt()}');
          expect(find.byKey(const ValueKey('design-preview')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('design-save-settings')),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text(title).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(title).first);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
