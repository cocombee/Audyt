import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';

void main() {
  testWidgets('reminder cards share geometry and expand from arrow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(body: DemoReminderPanel(availableWidth: 1000)),
      ),
    );
    await tester.pump();
    final cards = find.byType(AccountingDashboardCard);
    expect(cards, findsNWidgets(3));
    expect(tester.getSize(cards.at(0)), tester.getSize(cards.at(1)));
    final iconBox = find.descendant(
      of: cards.at(0),
      matching: find.byType(AccountingMetricIconBox),
    );
    final chevron = find.descendant(
      of: cards.at(0),
      matching: find.byType(AccountingSelectorChevron),
    );
    final paintedChevron = find.descendant(
      of: chevron,
      matching: find.byType(CustomPaint),
    );
    expect(tester.getRect(paintedChevron).top, tester.getRect(iconBox).top);
    expect(
      tester.getRect(cards.at(0)).right - tester.getRect(paintedChevron).right,
      20,
    );
    expect(tester.getSize(chevron), const Size(22, 22));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(tester.getCenter(chevron));
    await tester.pumpAndSettle();
    final hovered = tester.widget<AnimatedContainer>(
      find.descendant(of: chevron, matching: find.byType(AnimatedContainer)),
    );
    expect(
      (hovered.decoration! as BoxDecoration).color,
      AccountingTheme.of(tester.element(chevron)).primary
          .withValues(alpha: 0.12),
    );
    expect((hovered.decoration! as BoxDecoration).shape, BoxShape.circle);
    await pointer.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: chevron,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      Colors.transparent,
    );
    expect(find.text('Mark Complete'), findsNothing);
    expect(find.byTooltip('Show Details'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('reminder-disclosure-SST Return')),
    );
    await tester.pump();
    expect(find.text('Mark Complete'), findsOneWidget);
    expect(find.text('Snooze One Day'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
