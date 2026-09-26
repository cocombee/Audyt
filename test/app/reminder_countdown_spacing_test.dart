import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  testWidgets(
    'every countdown drops seconds before crowding the trailing item',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final now = DateTime.now();
      final records = [
        for (final title in ['Annual Return', 'Income Tax', 'SST Return'])
          WorkspaceReminder(
            id: EntityId.random(),
            title: title,
            obligation: 'Other',
            agency: 'Reviewed Agency',
            dueDate: DateTime(now.year, now.month, now.day + 1),
          ),
      ];
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var totalCompact = 0;
      for (final width in [
        1224.0,
        900.0,
        800.0,
        790.0,
        780.0,
        770.0,
        760.0,
        740.0,
        720.0,
      ]) {
        tester.view.physicalSize = Size(width, 700);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: DemoReminderPanel(
                  reminders: records,
                  preferences: CompanyPreferences.defaults(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        var compactCount = 0;
        for (final record in records) {
          final finder = find.byKey(
            ValueKey('reminder-countdown-${record.id.value}'),
          );
          final text = tester.widget<Text>(finder).data!;
          expect(text, matches(RegExp(r'^\d+h \d{2}m(?: \d{2}s)?$')));
          final full = text.endsWith('s');
          if (!full) {
            compactCount++;
          }
          if (width == 1224) {
            expect(
              full,
              isTrue,
              reason: 'Every card has room, including the middle one.',
            );
          }
          final card = find
              .ancestor(
                of: finder,
                matching: find.byType(AccountingDashboardCard),
              )
              .first;
          final badgeText = find.descendant(
            of: card,
            matching: find.text('Due Soon'),
          );
          final compactBadge = find.descendant(
            of: card,
            matching: find.text('Soon'),
          );
          final shownBadge = badgeText.evaluate().isNotEmpty
              ? badgeText
              : compactBadge;
          final textRight = tester.getRect(finder).right;
          if (full) {
            final rightEdge = shownBadge.evaluate().isEmpty
                ? tester.getRect(card).right
                : tester.getRect(shownBadge).left - 8;
            expect(
              rightEdge - textRight,
              greaterThan(20),
              reason: 'Seconds must leave more than 20px after the countdown.',
            );
          }
        }
        totalCompact += compactCount;
        await captureUi(tester, 'Reminder Countdown Spacing ${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
      expect(
        totalCompact,
        greaterThan(0),
        reason: 'Intermediate three-column layouts omit the final unit before the cards stack.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
