import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/audyt_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/menu_visual_geometry.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'date selectors retain shared highlights, spacing and day grid at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 240,
                    child: AccountingSelector<String>(
                      triggerKey: const ValueKey('reference-selector'),
                      value: 'Alpha',
                      hintText: 'Select',
                      options: const [
                        AccountingSelectorOption(
                          value: 'Alpha',
                          label: 'Alpha',
                        ),
                        AccountingSelectorOption(
                          value: 'Beta',
                          label: 'Beta',
                          key: ValueKey('reference-hover'),
                        ),
                      ],
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('reference-selector')));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        final reference = find.byKey(const ValueKey('reference-hover'));
        await mouse.moveTo(tester.getCenter(reference));
        final referencePaint = await paintedSurfaceBounds(
          tester,
          key,
          reference,
          accountingNeutralHighlight,
        );
        await capture(key, 'Selector Grey Highlight ${width.toInt()}', tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await mouse.moveTo(Offset.zero);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: AudytDatePickerDialog(
                  initialDate: DateTime(2026, 9, 26),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2037),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final calendar = tester.getRect(
          find.byKey(const ValueKey('audyt-date-summary-pane')),
        );
        final yearField = find.byKey(const ValueKey('audyt-year-selector'));
        final frame = tester.getRect(yearField);
        expect(frame.left - calendar.left, closeTo(20, .1));
        expect(calendar.right - frame.right, closeTo(20, .1));
        expect(frame.height, closeTo(44, .1));
        final monthField = find.byKey(const ValueKey('audyt-month-selector'));
        final monthFrame = tester.getRect(monthField);
        expect(monthFrame.left, frame.left);
        expect(monthFrame.right, frame.right);
        for (final value in ['2026', 'September']) {
          final text = tester.widget<Text>(find.text(value));
          expect(
            text.style!.color,
            AccountingTheme.of(tester.element(yearField)).foreground,
          );
          expect(text.style!.fontWeight, FontWeight.w400);
        }
        expect(monthFrame.top - frame.bottom, closeTo(10, .1));
        final dateInk = await paintedBounds(
          tester,
          key,
          find.byKey(const ValueKey('audyt-date-month-day')),
        );
        expect(frame.top - dateInk.bottom, closeTo(20, .25));
        expect(find.byKey(const ValueKey('audyt-date-day-26')), findsOneWidget);
        await capture(key, 'Calendar Year Selector ${width.toInt()}', tester);
        await tester.tap(yearField);
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('audyt-year-search'));
        expect(search, findsOneWidget);
        expect(tester.getRect(search), frame);
        await tester.enterText(search, '2026');
        await tester.pumpAndSettle();
        final currentYear = find.byKey(const ValueKey('audyt-date-year-2026'));
        final currentChoice = tester.widget<MenuItemButton>(currentYear);
        expect(
          currentChoice.style!.textStyle!.resolve({})!.fontWeight,
          FontWeight.w400,
        );
        final context = tester.element(currentYear);
        final tokens = AccountingTheme.of(context);
        final selectedColor = Color.alphaBlend(
          tokens.primary.withValues(alpha: .10),
          tokens.card,
        );
        final currentPaint = await paintedSurfaceBounds(
          tester,
          key,
          currentYear,
          selectedColor,
        );
        expect(currentPaint.height, closeTo(referencePaint.height, .5));
        await capture(key, 'Calendar Year Selected ${width.toInt()}', tester);
        await tester.enterText(search, '2027');
        await tester.pumpAndSettle();
        final nextYear = find.byKey(const ValueKey('audyt-date-year-2027'));
        await mouse.moveTo(tester.getCenter(nextYear));
        final yearHover = await paintedSurfaceBounds(
          tester,
          key,
          nextYear,
          accountingNeutralHighlight,
        );
        expect(yearHover.height, closeTo(referencePaint.height, .5));
        await capture(
          key,
          'Calendar Year Search Hover ${width.toInt()}',
          tester,
        );
        await tester.tap(nextYear);
        await tester.pumpAndSettle();
        expect(find.text('2027'), findsOneWidget);
        // Changing navigation does not silently change the selected date.
        expect(find.text('September 26'), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.tap(monthField);
        await tester.pumpAndSettle();
        final monthSearch = find.byKey(const ValueKey('audyt-month-search'));
        expect(tester.getRect(monthSearch), monthFrame);
        await tester.enterText(monthSearch, 'September');
        await tester.pumpAndSettle();
        final selectedMonth = find.byKey(const ValueKey('audyt-date-month-9'));
        final monthPaint = await paintedSurfaceBounds(
          tester,
          key,
          selectedMonth,
          selectedColor,
        );
        expect(monthPaint.height, closeTo(referencePaint.height, .5));
        await tester.enterText(monthSearch, 'October');
        await tester.pumpAndSettle();
        final hoveredMonth = find.byKey(const ValueKey('audyt-date-month-10'));
        await mouse.moveTo(tester.getCenter(hoveredMonth));
        final monthHover = await paintedSurfaceBounds(
          tester,
          key,
          hoveredMonth,
          accountingNeutralHighlight,
        );
        expect(monthHover.height, closeTo(referencePaint.height, .5));
        await capture(
          key,
          'Calendar Month Grey Highlights ${width.toInt()}',
          tester,
        );
        await tester.tap(hoveredMonth);
        await tester.pumpAndSettle();
        expect(find.text('October'), findsOneWidget);
        expect(find.text('2027'), findsOneWidget);
        expect(find.text('September 26'), findsOneWidget);
        expect(find.byKey(const ValueKey('audyt-date-day-31')), findsOneWidget);
        await capture(key, 'Calendar Selected Month ${width.toInt()}', tester);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
