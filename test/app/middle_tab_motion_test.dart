import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  testWidgets('middle and top tabs share a moving selected surface', (tester) async {
    for (final embedded in [false, true]) {
      var selected = 0;
      await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) => AccountingTabs(
          key: ValueKey(embedded), labels: const ['Balance Sheet', 'Profit And Loss', 'Trial Balance'],
          selectedIndex: selected, embedded: embedded, keyPrefix: 'report',
          onChanged: (v) => setState(() => selected = v))),
      )));
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicator, isA<BoxDecoration>());
      expect((tabBar.indicator as BoxDecoration).color, AccountingTheme.light().extension<AccountingTokens>()!.card);
      await tester.tap(find.byKey(const ValueKey('report-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tabBar.controller!.animation!.value, greaterThan(0));
      expect(tabBar.controller!.animation!.value, lessThan(2));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    }
  });
}
