import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:audyt/app/feature_registry.dart';

void main() {
  test('sidebar has one destination per section in usage order', () {
    expect(
      FeatureRegistry.navigationGroups
          .expand((g) => g.features)
          .map((f) => f.id)
          .toList(),
      [
        'home',
        'expenses-vendors',
        'sales-customers',
        'banking',
        'reports',
        'taxes',
        'accounting',
        'documents',
        'users',
      ],
    );
    expect(FeatureRegistry.sidebarId('claims'), 'expenses-vendors');
    expect(FeatureRegistry.sidebarId('accountant-review'), 'accounting');
  });
  test('countdown switches units without changing the deadline', () {
    expect(reminderCountdown(const Duration(hours: 48)), '2 Days');
    expect(reminderCountdown(const Duration(hours: 47)), '47h 00m 00s');
    expect(
      reminderCountdown(const Duration(minutes: 59, seconds: 30)),
      '59m 30s',
    );
    expect(reminderCountdown(const Duration(seconds: 42)), '42s');
    expect(
      reminderCountdown(
        const Duration(hours: 23, minutes: 57, seconds: 26),
        includeSeconds: false,
      ),
      '23h 57m',
    );
    expect(reminderCountdown(Duration.zero), 'Due Now');
  });
  for (final width in [390.0, 800.0, 1224.0]) {
    for (final count in [1, 2, 3, 4]) {
      testWidgets('fluid reminders $count at $width', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DemoReminderPanel(
                  titles: List.generate(count, (i) => 'Reminder ${i + 1}'),
                ),
              ),
            ),
          ),
        );
        expect(find.byTooltip('Show Details'), findsNothing);
        for (var i = 0; i < count; i++) {
          expect(
            find.byKey(ValueKey('reminder-disclosure-Reminder ${i + 1}')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('reminder-disclosure-Reminder 1')),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('demo-reminder-complete-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('compact reminder cards expand and complete independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(body: DemoReminderPanel()),
      ),
    );
    expect(find.text('SST Return'), findsOneWidget);
    expect(find.text('Income Tax'), findsOneWidget);
    expect(find.text('Annual Return'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('reminder-disclosure-SST Return')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('demo-reminder-complete-0')));
    await tester.pump();
    expect(find.text('Completed'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('demo-reminder-complete-1')),
      findsNothing,
    );
    expect(find.textContaining('Snooze'), findsNothing);
    await tester.tap(find.text('Reopen'));
    await tester.pump();
    expect(find.text('Completed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
