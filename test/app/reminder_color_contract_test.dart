import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tax reminder icons use the existing red, blue and yellow swatches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 900));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(body: DemoReminderPanel()),
        ),
      );
      final cards = tester
          .widgetList<AccountingDashboardCard>(
            find.byType(AccountingDashboardCard),
          )
          .toList();
      expect(cards.map((card) => card.title), [
        'SST Return',
        'Income Tax',
        'Annual Return',
      ]);
      expect(cards.map((card) => card.iconFillColor), [
        AccountingColorLibrary.grapefruit,
        AccountingColorLibrary.blueJeansDeep,
        AccountingColorLibrary.sunflowerDeep,
      ]);
      expect(cards.last.iconForegroundColor, isNull);
      final yellowIcon = tester.widget<AccountingIcon>(
        find
            .descendant(
              of: find.byType(AccountingDashboardCard).last,
              matching: find.byType(AccountingIcon),
            )
            .first,
      );
      expect(yellowIcon.color, AccountingTokens.light.primaryForeground);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
