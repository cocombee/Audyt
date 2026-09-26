import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/presentation/expense_recurrence_dialog.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';

void main() {
  testWidgets('quarterly preview validates interval and returns schedule', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    RecurrenceRule? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showExpenseRecurrenceDialog(
                  context,
                  startsOn: DateTime.utc(2026, 9, 30),
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
    await tester.enterText(find.byKey(const ValueKey('recurrence-every')), '0');
    await tester.tap(find.byKey(const ValueKey('recurrence-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recurrence-error')), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byKey(const ValueKey('recurrence-every')), '3');
    await tester.pumpAndSettle();
    expect(find.textContaining('31-12-2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recurrence-apply')));
    await tester.pumpAndSettle();
    expect(saved!.every, 3);
    expect(saved!.unit, RecurrenceUnit.months);
    expect(tester.takeException(), isNull);
  });

  testWidgets('end date uses the shared label-to-field spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExpenseRecurrenceDialog(
                context,
                startsOn: DateTime.utc(2026, 9, 30),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On Date').last);
    await tester.pumpAndSettle();

    final label = tester.getRect(
      find.byKey(const ValueKey('recurrence-end-label')),
    );
    final field = tester.getRect(find.byKey(const ValueKey('recurrence-end')));
    expect(field.top - label.bottom, closeTo(8, 0.1));
    expect(find.text('End Date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
