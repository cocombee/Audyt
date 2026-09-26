import 'package:audyt/app/frontend_catalog.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 900.0, 1224.0]) {
    testWidgets(
      'All pages preserve top alignment and Settings footer at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final group in FeatureRegistry.navigationGroups) {
          for (final feature in group.features) {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(AudytApp(initialPath: feature.path));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: feature.label);
            if (feature.id == 'users' &&
                find
                    .byKey(const ValueKey('accounting-page-header'))
                    .evaluate()
                    .isEmpty) {
              expect(
                find.text('Only Directors can manage employees.'),
                findsOneWidget,
              );
              continue;
            }
            final header = tester.getRect(
              find.byKey(const ValueKey('accounting-page-header')),
            );
            expect(
              header.width,
              greaterThan(width < 600 ? width - 150 : width - 370),
              reason: feature.label,
            );
            final topLimit =
                (frontendAreas.containsKey(feature.id) ||
                        const [
                          'accounting',
                          'claims',
                          'payment-vouchers',
                        ].contains(feature.id)
                    ? 170
                    : 110) +
                (width < 1000 ? 64 : 0) +
                (width < 600 ? 20 : 0);
            expect(
              header.top,
              lessThan(topLimit),
              reason: '${feature.label} must start at top',
            );
            final footer = tester.getRect(
              find.byKey(const ValueKey('accounting-settings-footer')),
            );
            final gear = tester.getRect(
              find.byKey(const ValueKey('accounting-settings')),
            );
            expect(footer.bottom, 1000);
            expect(gear.right, lessThanOrEqualTo(width));
            final compactRail = find.byKey(
              const ValueKey('accounting-navigation-compact-rail'),
            );
            if (compactRail.evaluate().isNotEmpty) {
              expect(gear.width, 44);
              expect(gear.center.dx, closeTo(footer.center.dx, 0.1));
              expect(find.text('Settings'), findsNothing);
            } else {
              expect(gear.left, 0);
              expect(gear.width, footer.width);
              expect(find.text('Settings'), findsOneWidget);
            }
          }
        }
      },
    );
  }
}
