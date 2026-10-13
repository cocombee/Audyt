import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> host(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const DemoCompany(child: AudytApp()));
    await t.pumpAndSettle();
  }

  double width(WidgetTester t) =>
      t.getSize(find.byKey(const ValueKey('accounting-navigation-rail'))).width;
  testWidgets(
    'sidebar width interpolates, reverses and preserves the selected page',
    (t) async {
      await host(t);
      await t.tap(
        find.byKey(const ValueKey('navigation-item-expenses-vendors')),
      );
      await t.pumpAndSettle();
      final start = width(t);
      await t.tap(find.byKey(const ValueKey('collapse-accounting-navigation')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final middle = width(t);
      expect(middle, greaterThan(92));
      expect(middle, lessThan(start));
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('expand-accounting-navigation')));
      await t.pump();
      expect(width(t), closeTo(middle, .1));
      await t.pumpAndSettle();
      expect(width(t), closeTo(start, .1));
      expect(
        find.byKey(const ValueKey('page-title-expenses-vendors')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'automatic compact/expanded transitions animate existing breakpoints',
    (t) async {
      await host(t);
      await t.binding.setSurfaceSize(const Size(720, 900));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(width(t), greaterThan(92));
      expect(width(t), lessThan(270));
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
      expect(width(t), 92);
      await t.binding.setSurfaceSize(const Size(1440, 900));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(width(t), greaterThan(92));
      expect(width(t), lessThan(270));
      await t.pumpAndSettle();
      expect(width(t), 270);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('reduced motion switches without interpolation', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await host(t);
    await t.tap(find.byKey(const ValueKey('collapse-accounting-navigation')));
    await t.pump();
    expect(width(t), 92);
    expect(t.takeException(), isNull);
  });
}
