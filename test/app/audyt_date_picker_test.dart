import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';

import '../support/menu_visual_geometry.dart';

import 'package:audyt/app/audyt_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  for (final width in [900.0, 390.0, 320.0]) {
    for (final day in [26, 30]) {
      testWidgets('responsive date summary at $width on day $day', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 740));
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: Size(width, 740)),
                child: child!,
              ),
              home: Scaffold(
                body: AudytDatePickerDialog(
                  initialDate: DateTime(2026, 9, day),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.byKey(const ValueKey('audyt-date-weekday'));
        final summary = tester.widget<Text>(finder);
        expect(summary.data, day == 26 ? 'Saturday' : 'Wednesday');
        expect(summary.style!.fontWeight, FontWeight.w400);
        if (width == 900) {
          expect(find.text('September $day'), findsOneWidget);
          final weekdayBox = tester.getRect(finder);
          final monthDayBox = tester.getRect(
            find.byKey(const ValueKey('audyt-date-month-day')),
          );
          expect(monthDayBox.top, closeTo(weekdayBox.bottom, .01));
        } else {
          expect(
            find.byKey(const ValueKey('audyt-date-month-day')),
            findsNothing,
          );
        }
        final surface = tester.getRect(
          find.byKey(const ValueKey('audyt-date-surface')),
        );
        for (final line in [
          'audyt-date-weekday',
          if (width == 900) 'audyt-date-month-day',
        ]) {
          final label = find.byKey(ValueKey(line));
          final paragraph = tester.renderObject<RenderParagraph>(label);
          final text = tester.widget<Text>(label);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.data!.length),
          );
          expect(boxes, hasLength(1));
          final ink = await paintedBounds(tester, key, label);
          expect(ink.left - surface.left, closeTo(20, 0.25));
          expect(
            ink.right,
            lessThanOrEqualTo(tester.getRect(label).right + .125),
          );
        }
        expect(find.byKey(const ValueKey('audyt-month-year')), findsNothing);
        expect(
          find.byKey(const ValueKey('audyt-month-year-icon')),
          findsNothing,
        );
        final calendar = tester.getRect(
          find.byKey(const ValueKey('audyt-calendar')),
        );
        final nextInk = await paintedBounds(
          tester,
          key,
          find.byKey(const ValueKey('Next month')),
        );
        expect(calendar.right - nextInk.right, closeTo(20, .25));
        // Use an unselected final-row digit so its painted ink is measured,
        // independently of the selected date's green circle.
        final finalRowDay = day == 30 ? 29 : 30;
        final finalRowInk = await paintedBounds(
          tester,
          key,
          find.descendant(
            of: find.byKey(ValueKey('audyt-date-day-$finalRowDay')),
            matching: find.text('$finalRowDay'),
          ),
        );
        for (final arrow in ['Previous month', 'Next month']) {
          final ink = await paintedBounds(
            tester,
            key,
            find.byKey(ValueKey(arrow)),
          );
          if (width == 900) {
            expect(ink.top - finalRowInk.bottom, closeTo(20, .25));
            expect(calendar.bottom - ink.bottom, closeTo(36, .25));
            expect(
              ink.center.dy,
              closeTo(
                tester
                    .getRect(find.byKey(const ValueKey('audyt-date-select')))
                    .center
                    .dy,
                .25,
              ),
            );
          }
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(
            location: tester.getRect(find.byKey(ValueKey(arrow))).center,
          );
          await tester.pumpAndSettle();
          final hoveredInk = await paintedBounds(
            tester,
            key,
            find.byKey(ValueKey(arrow)),
          );
          expect(hoveredInk, ink);
          await mouse.removePointer();
          await tester.pumpAndSettle();
        }
        if (width < 900) {
          final pane = tester.getRect(
            find.byKey(const ValueKey('audyt-date-summary-pane')),
          );
          final select = find.byKey(const ValueKey('audyt-date-select'));
          final border = await paintedBounds(tester, key, select, cutoff: 252);
          final weekdayInk = await paintedBounds(tester, key, finder);
          expect(border.left - pane.left, closeTo(20, .25));
          expect(pane.bottom - border.bottom, closeTo(8, .25));
          final yearFrame = tester.getRect(
            find.byKey(const ValueKey('audyt-year-selector')),
          );
          final monthFrame = tester.getRect(
            find.byKey(const ValueKey('audyt-month-selector')),
          );
          expect(yearFrame.top - weekdayInk.bottom, closeTo(20, .25));
          expect(monthFrame.top - yearFrame.bottom, closeTo(10, .25));
          expect(border.top - monthFrame.bottom, closeTo(8, .25));
          expect(calendar.bottom - finalRowInk.bottom, closeTo(20, .25));
          for (final arrow in ['Previous month', 'Next month']) {
            final ink = await paintedBounds(
              tester,
              key,
              find.byKey(ValueKey(arrow)),
            );
            expect(ink.center.dy, closeTo(border.center.dy, .25));
          }
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('audyt-calendar')),
              matching: find.byKey(const ValueKey('Next month')),
            ),
            findsNothing,
          );
          final close = tester.getRect(
            find.byKey(const ValueKey('audyt-date-close')),
          );
          expect(tester.getRect(select).overlaps(close), isFalse);
        }
        await capture(key, 'Calendar Responsive $width Day $day', tester);
        await tester.tap(find.byKey(const ValueKey('Next month')));
        await tester.pumpAndSettle();
        expect(find.text('October'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('Previous month')));
        await tester.pumpAndSettle();
        expect(find.text('September'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final month in [9, 10, 5, 2]) {
    testWidgets(
      'calendar last-row controls, hover and compact height in month $month',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
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
                body: AudytDatePickerDialog(
                  initialDate: DateTime(2026, month, month == 2 ? 2 : 1),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final box = tester.getRect(
          find.byKey(const ValueKey('audyt-date-surface')),
        );
        final select = tester.getRect(
          find.byKey(const ValueKey('audyt-date-select')),
        );
        final arrowInk = await paintedBounds(
          tester,
          key,
          find.byKey(const ValueKey('Next month')),
        );
        final previousInk = await paintedBounds(
          tester,
          key,
          find.byKey(const ValueKey('Previous month')),
        );
        final selectBorder = await paintedBounds(
          tester,
          key,
          find.byKey(const ValueKey('audyt-date-select')),
          cutoff: 252,
        );
        expect(arrowInk.bottom, closeTo(previousInk.bottom, 0.25));
        expect(arrowInk.center.dy, closeTo(selectBorder.center.dy, 0.25));
        expect(box.bottom - selectBorder.bottom, closeTo(20, 0.25));
        expect(box.bottom - select.bottom, 20);
        expect(box.height, lessThan(390));
        final lastDay = DateUtils.getDaysInMonth(2026, month);
        final dateButton = find.byKey(ValueKey('audyt-date-day-$lastDay'));
        final lastDateInk = await paintedBounds(
          tester,
          key,
          find.descendant(of: dateButton, matching: find.text('$lastDay')),
        );
        expect(arrowInk.top - lastDateInk.bottom, closeTo(20, .25));
        expect(box.right - arrowInk.right, closeTo(20, .25));
        await capture(key, 'Calendar Visible Month $month', tester);
        final calendar = tester.getRect(
          find.byKey(const ValueKey('audyt-calendar')),
        );
        final offset = DateUtils.firstDayOffset(
          2026,
          month,
          MaterialLocalizations.of(
            tester.element(find.byKey(const ValueKey('audyt-calendar'))),
          ),
        );
        var left = double.infinity;
        var right = 0.0;
        for (var day = 1; day <= lastDay; day++) {
          final column = (offset + day - 1) % 7;
          if (column != 0 && column != 6) continue;
          final label = find.descendant(
            of: find.byKey(ValueKey('audyt-date-day-$day')),
            matching: find.text('$day'),
          );
          final ink = await paintedBounds(tester, key, label);
          if (column == 0) expect(ink.left - calendar.left, closeTo(20, .25));
          if (column == 6) expect(calendar.right - ink.right, closeTo(20, .25));
          if (column == 0 && ink.left < left) left = ink.left;
          if (column == 6 && ink.right > right) right = ink.right;
        }
        expect(left - calendar.left, closeTo(20, .25));
        expect(calendar.right - right, closeTo(20, .25));
        expect(select.height, 44);
        expect(find.text('Choose expense date'), findsNothing);
        final summary = tester.widget<Text>(
          find.byKey(const ValueKey('audyt-date-weekday')),
        );
        expect(summary.style!.fontWeight, FontWeight.w400);
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('audyt-date-select')),
        );
        expect(
          button.style!.backgroundColor!.resolve({}),
          AccountingTheme.of(
            tester.element(find.byKey(const ValueKey('audyt-date-select'))),
          ).primary,
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: select.center);
        await tester.pumpAndSettle();
        final context = tester.element(
          find.byKey(const ValueKey('audyt-date-select')),
        );
        expect(
          button.style!.backgroundColor!.resolve({WidgetState.hovered}),
          AccountingTheme.of(context).primary,
        );
        await capture(key, 'Calendar Month $month Hover', tester);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('picker uses 20px edges, bottom navigation and a Select action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showAudytDatePicker(
                context: context,
                initialDate: DateTime(2026, 9, 25),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              ),
              child: const Text('Open calendar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open calendar'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    final shape =
        tester.widget<Dialog>(dialog).shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(accountingSectionRadius));
    expect(find.byTooltip('Switch to input'), findsNothing);
    final box = tester.getRect(
      find.byKey(const ValueKey('audyt-date-surface')),
    );
    final date = tester.getRect(
      find.byKey(const ValueKey('audyt-date-summary')),
    );
    final select = tester.getRect(
      find.byKey(const ValueKey('audyt-date-select')),
    );
    final previous = tester.getRect(
      find.byKey(const ValueKey('Previous month')),
    );
    final next = tester.getRect(find.byKey(const ValueKey('Next month')));
    expect(select.left, date.left);
    expect(box.bottom - select.bottom, accountingContentInset);
    expect(previous.center.dy, closeTo(select.center.dy, 0.1));
    expect(next.center.dy, closeTo(select.center.dy, 0.1));
    // The hit box extends beyond the painted edge; raster checks above assert 20px.
    expect(box.right - next.right, closeTo(7.75, .1));
    expect(next.left - previous.right, accountingRecordIconGap);
    final close = tester.getRect(
      find.byKey(const ValueKey('audyt-date-close')),
    );
    expect(box.right - close.right, AccountingPopoutTokens.closeInset);
    expect(close.top - box.top, AccountingPopoutTokens.closeInset);
    final lastDate = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('audyt-date-day-30')),
        matching: find.text('30'),
      ),
    );
    expect(next.bottom, greaterThan(lastDate.bottom));

    await tester.tap(find.byKey(const ValueKey('audyt-year-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('audyt-year-search')),
      '2026',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('audyt-date-year-2026')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audyt-date-year-2026')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audyt-month-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('audyt-month-search')),
      'September',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audyt-date-month-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audyt-date-day-26')));
    await tester.tap(find.byKey(const ValueKey('audyt-date-select')));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 9, 26));
    expect(find.byType(AudytDatePickerDialog), findsNothing);
  });

  testWidgets(
    'year and month navigation preserve selection and enforce date bounds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showAudytDatePicker(
                  context: context,
                  initialDate: DateTime(2026, 9, 27),
                  firstDate: DateTime(2025, 10, 15),
                  lastDate: DateTime(2027, 2, 10),
                ),
                child: const Text('Open bounded calendar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open bounded calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audyt-year-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audyt-date-year-2025')));
      await tester.pumpAndSettle();
      expect(find.text('October'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('September 27'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audyt-month-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('audyt-date-month-9')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('audyt-date-month-10')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('audyt-date-day-14')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('audyt-date-day-15')));
      await tester.pumpAndSettle();
      expect(find.text('October 15'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audyt-year-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audyt-date-year-2027')));
      await tester.pumpAndSettle();
      expect(find.text('February'), findsOneWidget);
      expect(find.text('2027'), findsOneWidget);
      expect(find.text('October 15'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('audyt-date-day-11')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('Next month')));
      await tester.pumpAndSettle();
      expect(find.text('February'), findsOneWidget);
      expect(find.text('2027'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audyt-date-day-10')));
      await tester.tap(find.byKey(const ValueKey('audyt-date-select')));
      await tester.pumpAndSettle();
      expect(result, DateTime(2027, 2, 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar stays usable on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: const Size(390, 740)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAudytDatePicker(
                context: context,
                initialDate: DateTime(2026, 9, 25),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              ),
              child: const Text('Open calendar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open calendar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('audyt-date-day-25')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final box = tester.getRect(
      find.byKey(const ValueKey('audyt-date-surface')),
    );
    final select = tester.getRect(
      find.byKey(const ValueKey('audyt-date-select')),
    );
    final next = tester.getRect(find.byKey(const ValueKey('Next month')));
    final pane = tester.getRect(
      find.byKey(const ValueKey('audyt-date-summary-pane')),
    );
    expect(select.left - box.left, accountingContentInset);
    expect(pane.bottom - select.bottom, closeTo(accountingFieldLabelGap, .1));
    expect(next.center.dy, closeTo(select.center.dy, .1));
    final close = tester.getRect(
      find.byKey(const ValueKey('audyt-date-close')),
    );
    expect(box.right - close.right, AccountingPopoutTokens.closeInset);
    expect(close.top - box.top, AccountingPopoutTokens.closeInset);
    await tester.tap(find.byKey(const ValueKey('audyt-date-select')));
    await tester.pumpAndSettle();
  });
}
