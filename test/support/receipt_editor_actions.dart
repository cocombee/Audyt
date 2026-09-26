import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> realAction(
  WidgetTester tester,
  Future<void> Function() action, {
  bool closesEditor = false,
}) async {
  await tester.runAsync(() async {
    await action();
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  // File I/O is outside Flutter's fake clock. A callback may finish before
  // the editor has completed its file synchronization and enabled Close.
  // Wait for that visible completion signal before performing the next action.
  final close = find.byKey(const ValueKey('receipt-review-close'));
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  bool finished() => closesEditor
      ? close.evaluate().isEmpty
      : close.evaluate().isEmpty ||
            tester.widget<IconButton>(close).onPressed != null;
  while (!finished() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(
    finished(),
    isTrue,
    reason: closesEditor
        ? 'The saved receipt editor must finish closing.'
        : 'The receipt action must finish before another action starts.',
  );
  await tester.pumpAndSettle();
}
