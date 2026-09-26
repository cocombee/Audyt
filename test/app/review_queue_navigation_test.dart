import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Needs Review opens a queue of real review destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(initialPath: '/home', workspace: workspace),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('home-kpi-Needs Review'));
    final summaryCount = int.parse(
      tester
          .widgetList<Text>(
            find.descendant(of: summary, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .firstWhere((text) => text.endsWith('Items'))
          .split(' ')
          .first,
    );
    await tester.tap(
      find.descendant(
        of: summary,
        matching: find.byType(AccountingMetricIconBox),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Journal Drafts'), findsNothing);
    expect(find.byKey(const ValueKey('review-queue-expenses')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-review-expenses')), findsOneWidget);
    int visibleCount() =>
        [
          'expenses',
          'claims',
          'vouchers',
          'invoices',
          'credits',
          'journals',
        ].fold<int>(0, (total, id) {
          final count = find.byKey(ValueKey('review-queue-count-$id'));
          return total +
              (count.evaluate().isEmpty
                  ? 0
                  : int.parse(tester.widget<Text>(count).data!));
        });
    var queued = visibleCount();
    // Six destinations now span the established five-row list. Include the
    // actual next page rather than treating unpainted rows as missing work.
    final next = find.byKey(const ValueKey('app-1-page-next'));
    while (next.evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(next).onPressed != null) {
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      queued += visibleCount();
    }
    expect(queued, summaryCount);
    final previous = find.byKey(const ValueKey('app-1-page-previous'));
    while (previous.evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(previous).onPressed != null) {
      await tester.ensureVisible(previous);
      await tester.tap(previous);
      await tester.pumpAndSettle();
    }
    final expenseCount = tester.getRect(
      find.byKey(const ValueKey('review-queue-count-expenses')),
    );
    final expenseOpen = tester.getRect(
      find.byKey(const ValueKey('open-review-expenses')),
    );
    expect(expenseCount.center.dy, closeTo(expenseOpen.center.dy, 0.1));

    await tester.tap(find.byKey(const ValueKey('open-review-expenses')));
    await tester.pumpAndSettle();
    expect(find.text('Cerah Internet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review queue keeps paired count and action at narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(initialPath: '/home', workspace: workspace),
    );
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('home-kpi-Needs Review'));
    await tester.tap(
      find.descendant(
        of: summary,
        matching: find.byType(AccountingMetricIconBox),
      ),
    );
    await tester.pumpAndSettle();
    final count = tester.getRect(
      find.byKey(const ValueKey('review-queue-count-expenses')),
    );
    final button = tester.getRect(
      find.byKey(const ValueKey('open-review-expenses')),
    );
    expect(count.center.dy, closeTo(button.center.dy, 0.1));
    expect(tester.takeException(), isNull);
  });
}
