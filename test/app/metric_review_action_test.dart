import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only actionable summary icon and text open review', (
    tester,
  ) async {
    var opened = 0;
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: AccountingHomePage(
            data: AccountingHomeData.empty(currencyCode: 'MYR'),
            reviewCount: 3,
            onNeedsReview: () => opened++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final review = find.byKey(const ValueKey('home-kpi-Needs Review'));
    final icon = find.descendant(
      of: review,
      matching: find.byType(AccountingMetricIconBox),
    );
    expect(
      find.descendant(of: icon, matching: find.byType(InkWell)),
      findsOneWidget,
    );
    await tester.tap(icon);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Needs Review'));
    await tester.pumpAndSettle();
    expect(opened, 2);

    final sales = find.byKey(const ValueKey('home-kpi-This Month'));
    final salesIcon = find.descendant(
      of: sales,
      matching: find.byType(AccountingMetricIconBox),
    );
    expect(
      find.descendant(of: salesIcon, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
