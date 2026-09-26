import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_side_tooltip.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  });

  testWidgets('expanded company selector keeps labels before the chevron', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Current Company'));
    final subtitle = tester.getRect(find.text('Legal Type Not Set'));
    final chevron = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('company-switcher')),
        matching: find.byType(AccountingSelectorChevron),
      ),
    );
    expect(
      tester.widget<Text>(find.text('Current Company')).overflow,
      TextOverflow.ellipsis,
    );
    expect(tester.widget<Text>(find.text('Current Company')).maxLines, 1);
    expect(tester.widget<Text>(find.text('Legal Type Not Set')).maxLines, 1);
    if (tester
        .renderObject<RenderParagraph>(find.text('Current Company'))
        .didExceedMaxLines) {
      expect(chevron.left - title.right, closeTo(20, 0.1));
    }
    expect(title.height, lessThan(30));
    expect(subtitle.height, lessThan(30));
  });

  testWidgets('sidebar frames, content, and notifications follow 24/20 axes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const DemoCompany(child: AudytApp(initialPath: '/expenses-vendors')),
    );
    await tester.pumpAndSettle();

    final company = find.byKey(const ValueKey('company-switcher'));
    final companyFrame = tester.getRect(company);
    final logo = tester.getRect(
      find.byKey(const ValueKey('company-selector-logo')),
    );
    final brandLogo = tester.getRect(
      find.byKey(const ValueKey('accounting-brand-icon-box')),
    );
    final chevron = tester.getRect(
      find.descendant(
        of: company,
        matching: find.byType(AccountingSelectorChevron),
      ),
    );
    final expenses = find.byKey(
      const ValueKey('navigation-item-expenses-vendors'),
    );
    final expenseFrame = tester.getRect(expenses);
    final expenseIcon = tester.getRect(
      find.descendant(of: expenses, matching: find.byType(AccountingIcon)),
    );
    final expenseBadge = tester.getRect(
      find.byKey(const ValueKey('navigation-badge-expenses-vendors')),
    );

    expect(companyFrame.left, closeTo(24, 0.1));
    expect(companyFrame.right, closeTo(270 - 24, 0.1));
    expect(expenseFrame.left, closeTo(companyFrame.left, 0.1));
    expect(expenseFrame.right, closeTo(companyFrame.right, 0.1));
    expect(logo.left - companyFrame.left, closeTo(20, 0.1));
    expect(brandLogo.left, closeTo(companyFrame.left, 0.1));
    expect(find.byKey(const ValueKey('accounting-brand-mark')), findsNothing);
    expect(expenseIcon.left, closeTo(logo.left, 0.1));
    expect(companyFrame.right - chevron.right, closeTo(20, 0.1));
    expect(expenseFrame.right - expenseBadge.right, closeTo(20, 0.1));
    final textAxis = tester
        .getRect(find.descendant(of: expenses, matching: find.text('Expenses')))
        .left;
    for (final text in ['Audyt', 'Home']) {
      expect(
        tester.getRect(find.text(text)).left,
        closeTo(textAxis, 0.1),
        reason: text,
      );
    }
    final companyPlaceholder = find.byKey(
      const ValueKey('company-selector-logo'),
    );
    expect(
      (tester.widget<Container>(companyPlaceholder).decoration as BoxDecoration)
          .color,
      accountingLightTabBand,
    );
    expect(
      find.descendant(
        of: companyPlaceholder,
        matching: find.byType(AccountingIcon),
      ),
      findsNothing,
    );

    for (final (index, group) in FeatureRegistry.navigationGroups.indexed.skip(
      1,
    )) {
      final divider = tester.getRect(
        find.byKey(ValueKey('navigation-divider-${group.id}')),
      );
      expect(divider.left, 24, reason: group.label);
      expect(divider.right, 270 - 24, reason: group.label);
      expect(divider.height, 1, reason: group.label);
      final previous =
          FeatureRegistry.navigationGroups[index - 1].features.last;
      final previousLabel = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('navigation-item-${previous.id}')),
          matching: find.text(previous.label),
        ),
      );
      final nextHeading = tester.getRect(
        find.byKey(ValueKey('navigation-group-${group.id}')),
      );
      expect(
        divider.center.dy,
        closeTo((previousLabel.bottom + nextHeading.top) / 2, 0.1),
        reason: group.label,
      );
    }

    for (final group in FeatureRegistry.navigationGroups) {
      final heading = tester.getRect(
        find.byKey(ValueKey('navigation-group-${group.id}')),
      );
      expect(heading.left, closeTo(24, 0.1), reason: group.label);
      expect(
        heading.right,
        closeTo(companyFrame.right, 0.1),
        reason: group.label,
      );
    }

    final title = tester.getRect(find.text('Demo Company'));
    final subtitle = tester.getRect(find.text('Sdn. Bhd.'));
    expect(title.left - logo.right, closeTo(14, 0.1));
    expect(subtitle.left, closeTo(title.left, 0.1));
    expect(chevron.left - title.right, greaterThanOrEqualTo(20));
    expect(title.height, lessThan(30));
    expect(subtitle.height, lessThan(30));
    expect(subtitle.top - title.bottom, closeTo(4, 0.1));
    expect((title.top + subtitle.bottom) / 2, closeTo(logo.center.dy, 0.1));
  });

  testWidgets(
    'Settings keeps the navigation axes and highlights only its icon',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const AudytApp());
      await tester.pumpAndSettle();

      final home = find.byKey(const ValueKey('navigation-item-home'));
      final settings = find.byKey(const ValueKey('accounting-settings'));
      final iconBox = find.byKey(
        const ValueKey('accounting-settings-icon-box'),
      );
      final settingsIcon = find.descendant(
        of: iconBox,
        matching: find.byType(AccountingIcon),
      );
      final homeIcon = find.descendant(
        of: home,
        matching: find.byType(AccountingIcon),
      );
      final settingsGlyph = find
          .descendant(of: settingsIcon, matching: find.byType(SizedBox))
          .first;
      final homeGlyph = find
          .descendant(of: homeIcon, matching: find.byType(SizedBox))
          .first;
      expect(
        tester.getRect(settingsGlyph).center.dx,
        tester.getRect(homeGlyph).center.dx,
      );
      expect(
        tester
            .getRect(
              find.descendant(of: settings, matching: find.text('Settings')),
            )
            .left,
        tester
            .getRect(find.descendant(of: home, matching: find.text('Home')))
            .left,
      );
      expect(tester.getSize(iconBox), const Size(32, 32));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getRect(settings).center);
      await tester.pump();
      final iconDecoration =
          tester.widget<DecoratedBox>(iconBox).decoration as BoxDecoration;
      final footerDecoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('accounting-settings-footer')),
                  )
                  .decoration
              as BoxDecoration;
      expect(iconDecoration.color, accountingNeutralHighlight);
      expect(
        iconDecoration.borderRadius,
        BorderRadius.circular(accountingControlRadius),
      );
      expect(
        footerDecoration.color,
        AccountingTheme.of(tester.element(settings)).sidebar,
      );
      await mouse.removePointer();
    },
  );

  testWidgets('collapsed navigation keeps full-size icons in 44px boxes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const DemoCompany(child: AudytApp(initialPath: '/expenses-vendors')),
    );
    await tester.pumpAndSettle();
    final expandedBrand = tester.getRect(
      find.byKey(const ValueKey('accounting-brand-icon-box')),
    );
    final expandedExpenses = tester.getRect(
      find.byKey(const ValueKey('navigation-item-expenses-vendors')),
    );
    final expandedSales = tester.getRect(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
    );
    final expandedItemGap = expandedSales.top - expandedExpenses.bottom;
    final collapse = find.byKey(
      const ValueKey('collapse-accounting-navigation'),
    );
    expect(tester.getSize(collapse), const Size(44, 44));
    expect(tester.widget<InkWell>(collapse).hoverColor, Colors.transparent);
    expect(
      tester.widget<InkWell>(collapse).borderRadius,
      BorderRadius.circular(accountingControlRadius),
    );
    await tester.tap(collapse);
    await tester.pumpAndSettle();

    final rail = tester.getRect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
    );
    final brand = tester.getRect(
      find.byKey(const ValueKey('accounting-compact-brand-icon-box')),
    );
    final nav = find.byKey(const ValueKey('navigation-item-expenses-vendors'));
    final navRect = tester.getRect(nav);
    final compactSales = tester.getRect(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
    );
    expect(compactSales.top - navRect.bottom, expandedItemGap);
    final icon = tester.getRect(
      find
          .descendant(
            of: find.descendant(of: nav, matching: find.byType(AccountingIcon)),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(rail.width, AccountingResponsive.compactRailWidth);
    expect(expandedBrand.size, brand.size);
    expect(brand.size, const Size(44, 44));
    expect(navRect.size, brand.size);
    expect(brand.left - rail.left, 24);
    expect(navRect.left - rail.left, 24);
    expect(rail.right - navRect.right, 24);
    expect(icon.size, const Size(20, 20));
    expect(brand.top, expandedBrand.top);
    expect(tester.widget<InkWell>(nav).hoverColor, accountingNeutralHighlight);
    final expand = find.byKey(const ValueKey('expand-accounting-navigation'));
    expect(tester.getSize(expand), const Size(44, 44));
    expect(tester.widget<InkWell>(expand).hoverColor, Colors.transparent);
    expect(
      tester.widget<InkWell>(expand).borderRadius,
      BorderRadius.circular(accountingControlRadius),
    );
    final compactSettings = find.byKey(
      const ValueKey('accounting-settings-icon-box'),
    );
    final compactSettingsDecoration =
        tester.widget<DecoratedBox>(compactSettings).decoration
            as BoxDecoration;
    expect(
      compactSettingsDecoration.borderRadius,
      BorderRadius.circular(accountingControlRadius),
    );
    expect(tester.getSize(compactSettings), const Size(32, 32));
    expect(find.byType(AccountingSideTooltip), findsWidgets);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(navRect.center);
    await tester.pump(accountingTooltipWaitDuration);
    await tester.pump();
    final tooltip = tester.getRect(
      find.byKey(const ValueKey('side-tooltip-Expenses')),
    );
    expect(tooltip.left - navRect.right, closeTo(12, 0.1));
    expect(tooltip.center.dy, closeTo(navRect.center.dy, 0.1));
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('side-tooltip-Expenses')),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, Colors.black.withValues(alpha: 0.8));
    await mouse.removePointer();
    for (final id in [
      'leading',
      ...FeatureRegistry.navigationGroups.skip(1).map((group) => group.id),
    ]) {
      final divider = tester.getRect(
        find.byKey(ValueKey('navigation-divider-$id')),
      );
      expect(divider.left - rail.left, 24);
      expect(rail.right - divider.right, 24);
      expect(divider.height, 1);
    }
    final leading = tester.getRect(
      find.byKey(const ValueKey('navigation-divider-leading')),
    );
    final home = tester.getRect(
      find.byKey(const ValueKey('navigation-item-home')),
    );
    expect(
      leading.center.dy,
      closeTo((tester.getRect(expand).bottom + home.top) / 2, 0.1),
    );
    for (final (index, group) in FeatureRegistry.navigationGroups.indexed.skip(
      1,
    )) {
      final previous =
          FeatureRegistry.navigationGroups[index - 1].features.last;
      final line = tester.getRect(
        find.byKey(ValueKey('navigation-divider-${group.id}')),
      );
      final previousIcon = tester.getRect(
        find.byKey(ValueKey('navigation-item-${previous.id}')),
      );
      final nextIcon = tester.getRect(
        find.byKey(ValueKey('navigation-item-${group.features.first.id}')),
      );
      expect(
        line.center.dy,
        closeTo((previousIcon.bottom + nextIcon.top) / 2, 0.1),
        reason: group.label,
      );
    }
  });
}
