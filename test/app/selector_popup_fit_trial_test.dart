import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const triggerKey = ValueKey('popup-fit-trigger');
const menuKey = ValueKey('popup-fit-menu');
const longestKey = ValueKey('popup-fit-longest');
const captureKey = ValueKey('popup-fit-capture');
const longest = 'Service Tax · 8%';

Future<void> host(
  WidgetTester tester,
  double width,
  double fieldWidth, {
  String label = longest,
  bool right = false,
  bool searchable = false,
  double scale = 1,
  bool decorated = false,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 700),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: right ? Alignment.topRight : Alignment.topLeft,
                child: AccountingSelector<String>(
                  assignedWidth: fieldWidth,
                  triggerKey: triggerKey,
                  menuKey: menuKey,
                  searchKey: const ValueKey('popup-fit-search'),
                  searchable: searchable,
                  searchHintText: 'Search taxes',
                  hintText: 'Select Tax',
                  value: 'no-tax',
                  onChanged: (_) {},
                  options: [
                    const AccountingSelectorOption(
                      value: 'no-tax',
                      label: 'No Tax',
                    ),
                    AccountingSelectorOption(
                      value: 'service',
                      label: label,
                      key: longestKey,
                      preserveLabelCase: true,
                      group: decorated ? 'Malaysian Tax' : null,
                      leading: decorated
                          ? const SizedBox(width: 36, child: Icon(Icons.flag))
                          : null,
                      leadingWidth: decorated ? 36 : 20,
                    ),
                    if (searchable)
                      for (var i = 0; i < 9; i++)
                        AccountingSelectorOption(
                          value: 'extra$i',
                          label: 'SST $i',
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect panel(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: find.byKey(longestKey), matching: find.byType(Material))
      .first,
);
RenderParagraph optionText(WidgetTester tester) => tester.renderObject(
  find
      .descendant(of: find.byKey(longestKey), matching: find.byType(RichText))
      .first,
);

Future<void> capture(WidgetTester tester, String name) async {
  final path = Platform.environment['AUDYT_SELECTOR_TRIAL_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(captureKey))
        .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'narrow inline selector widens menu without resizing box at $width',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await host(tester, width, 130);
        final before = tester.getRect(find.byKey(triggerKey));
        await tester.tap(find.byKey(triggerKey));
        await tester.pumpAndSettle();
        expect(panel(tester).width, greaterThan(before.width));
        expect(panel(tester).left, closeTo(before.left, .01));
        expect(panel(tester).top, greaterThanOrEqualTo(before.bottom));
        expect(tester.getRect(find.byKey(triggerKey)), before);
        expect(optionText(tester).maxLines, 1);
        expect(optionText(tester).didExceedMaxLines, isFalse);
        await capture(tester, 'Selector Longest Option ${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('wider box sets menu width at $width', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await host(tester, width, 400, right: true);
      final before = tester.getRect(find.byKey(triggerKey));
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(panel(tester).width, closeTo(before.width, .01));
      expect(panel(tester).right, closeTo(before.right, .01));
      expect(optionText(tester).didExceedMaxLines, isFalse);
      await capture(tester, 'Selector Wider Box ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'grouped icon options fit at larger font; searching preserves both widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await host(
        tester,
        720,
        200,
        scale: 1.5,
        decorated: true,
        searchable: true,
      );
      final before = tester.getRect(find.byKey(triggerKey));
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      final popupBefore = panel(tester);
      expect(optionText(tester).didExceedMaxLines, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('popup-fit-search')),
        'service',
      );
      await tester.pumpAndSettle();
      expect(panel(tester).width, popupBefore.width);
      expect(tester.getRect(find.byKey(triggerKey)), before);
      expect(optionText(tester).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'open scroller follows parent shrink, expansion and changed options',
    (tester) async {
      tester.view.physicalSize = const Size(720, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var width = 400.0;
      var label = longest;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topLeft,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SizedBox(
                      width: width,
                      child: AccountingSelector<String>(
                        assignedWidth: 450,
                        triggerKey: triggerKey,
                        hintText: 'Select Tax',
                        value: 'no-tax',
                        onChanged: (_) {},
                        options: [
                          const AccountingSelectorOption(
                            value: 'no-tax',
                            label: 'No Tax',
                          ),
                          AccountingSelectorOption(
                            value: 'service',
                            label: label,
                            preserveLabelCase: true,
                            key: longestKey,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(panel(tester).width, closeTo(400, .01));
      update(() => width = 130);
      await tester.pumpAndSettle();
      final fitted = panel(tester).width;
      expect(fitted, greaterThan(130));
      expect(fitted, lessThan(400));
      expect(tester.getSize(find.byKey(triggerKey)).width, 130);
      expect(optionText(tester).didExceedMaxLines, isFalse);
      update(() => width = 400);
      await tester.pumpAndSettle();
      expect(panel(tester).width, closeTo(400, .01));
      update(() {
        width = 130;
        label = 'Withholding · Non-Resident Contractor';
      });
      await tester.pumpAndSettle();
      expect(panel(tester).width, greaterThan(fitted));
      expect(optionText(tester).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'window resize preserves dismissal and uses current width on reopen',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topRight,
                child: LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    width: constraints.maxWidth - 580,
                    child: AccountingSelector<String>(
                      assignedWidth: 650,
                      triggerKey: triggerKey,
                      hintText: 'Select Tax',
                      value: 'no-tax',
                      onChanged: (_) {},
                      options: const [
                        AccountingSelectorOption(
                          value: 'no-tax',
                          label: 'No Tax',
                        ),
                        AccountingSelectorOption(
                          value: 'service',
                          label: longest,
                          preserveLabelCase: true,
                          key: longestKey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      final wide = panel(tester).width;
      tester.view.physicalSize = const Size(720, 700);
      await tester.pumpAndSettle();
      // Material retains its existing close-on-window-resize behavior.
      expect(find.byKey(longestKey), findsNothing);
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(panel(tester).width, lessThan(wide));
      expect(
        panel(tester).width,
        greaterThan(tester.getSize(find.byKey(triggerKey)).width),
      );
      expect(optionText(tester).didExceedMaxLines, isFalse);
      tester.view.physicalSize = const Size(1224, 700);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(panel(tester).width, closeTo(wide, .01));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'viewport cap keeps extraordinary option on one line with full semantics',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name = List.filled(50, 'Long').join(' ');
      await host(tester, 720, 130, label: name);
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(panel(tester).width, lessThanOrEqualTo(704));
      expect(optionText(tester).maxLines, 1);
      expect(optionText(tester).didExceedMaxLines, isTrue);
      expect(
        tester.getSemantics(find.byKey(longestKey)).getSemanticsData().label,
        contains(name),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit checkbox selector keeps menu and set; ordinary selector closes',
    (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.view.physicalSize = const Size(720, 700);
      t.view.devicePixelRatio = 1;
      final chosen = <String>{};
      String? normal;
      await t.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(accountingContentInset),
              child: StatefulBuilder(
                builder: (context, update) => Column(
                  children: [
                    AccountingSelector<String>(
                      controlKey: const ValueKey('explicit-multi'),
                      assignedWidth: 280,
                      value: null,
                      displayLabel: chosen.isEmpty
                          ? null
                          : chosen.length == 1
                          ? chosen.single
                          : accountingSelectorHintText('Select Multiple ...'),
                      hintText: 'Payment Method',
                      options: [
                        for (final value in ['Cash', 'Card'])
                          AccountingSelectorOption(
                            value: value,
                            label: value,
                            key: ValueKey('explicit-multi-$value'),
                            checked: chosen.contains(value),
                          ),
                      ],
                      onChanged: (value) => update(() {
                        if (value != null && !chosen.remove(value)) {
                          chosen.add(value);
                        }
                      }),
                    ),
                    const SizedBox(height: accountingContentInset),
                    AccountingSelector<String>(
                      controlKey: const ValueKey('ordinary-single'),
                      assignedWidth: 280,
                      value: normal,
                      hintText: 'Select Tax',
                      options: const [
                        AccountingSelectorOption(
                          value: 'none',
                          label: 'No Tax',
                          key: ValueKey('ordinary-no-tax'),
                        ),
                      ],
                      onChanged: (value) => update(() => normal = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Finder k(String value) => find.byKey(ValueKey(value));
      await t.tap(k('explicit-multi'));
      await t.pumpAndSettle();
      await t.tap(k('explicit-multi-Cash'));
      await t.pumpAndSettle();
      expect(chosen, {'Cash'});
      expect(k('explicit-multi-Card'), findsOneWidget);
      await t.tap(k('explicit-multi-Card'));
      await t.pumpAndSettle();
      expect(chosen, {'Cash', 'Card'});
      expect(find.byType(Checkbox), findsNWidgets(2));
      await t.tap(k('explicit-multi-Cash'));
      await t.pumpAndSettle();
      expect(chosen, {'Card'});
      expect(k('explicit-multi-Card'), findsOneWidget);
      // The open menu physically covers the second field. Close it through
      // its visible trigger before exercising the excluded ordinary selector.
      await t.tap(k('explicit-multi'));
      await t.pumpAndSettle();
      expect(k('explicit-multi-Card'), findsNothing);
      await t.tap(k('ordinary-single'));
      await t.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      await t.tap(k('ordinary-no-tax'));
      await t.pumpAndSettle();
      expect(normal, 'none');
      expect(k('ordinary-no-tax'), findsNothing);
      expect(chosen, {'Card'});
      expect(t.getSize(k('ordinary-single')).height, accountingControlHeight);
      expect(t.getSize(k('explicit-multi')).height, accountingControlHeight);
      expect(t.takeException(), isNull);
    },
  );
}
