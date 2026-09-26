import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('declared popup content fits its shell at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final footer in [false, true]) {
        for (final maximum in [null, 320.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => AccountingDialog.alert(
                    context,
                    title: 'Review Information',
                    description:
                        'Review the saved information before continuing. '
                        'The explanation should wrap within the existing form '
                        'rather than widen the popup around a narrower field.',
                    maxContentWidth: maximum,
                    content: const SizedBox(
                      width: 420,
                      child: TextField(
                        key: ValueKey('declared-popup-field'),
                        maxLines: 3,
                      ),
                    ),
                    actions: footer
                        ? [
                            AccountingButton.primary(
                              context,
                              key: null,
                              onPressed: () {},
                              child: const Text('Save'),
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material && widget.type == MaterialType.card,
            ),
          );
          final frame = tester.getRect(surface.first);
          final field = tester.getRect(
            find.byKey(const ValueKey('declared-popup-field')),
          );
          final contentWidth = maximum ?? 420.0;
          expect(frame.width, closeTo(contentWidth + 48, .01));
          expect(field.width, closeTo(contentWidth, .01));
          expect(field.left - frame.left, closeTo(24, .01));
          expect(frame.right - field.right, closeTo(24, .01));
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets('close-only popout retains its callback without a footer', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (dialog) => AccountingDialog.alert(
                    dialog,
                    title: 'Saved Information',
                    formFooter: true,
                    content: const Text('Saved facts'),
                    actions: [
                      AccountingButton.ghost(
                        dialog,
                        key: null,
                        onPressed: () => Navigator.pop(dialog, 'closed'),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
    expect(
      find.byKey(const ValueKey('accounting-form-dialog-footer')),
      findsNothing,
    );
    expect(find.byType(AccountingCloseIcon), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byType(AccountingCloseIcon))
          .getSemanticsData()
          .label,
      'Close',
    );
    await tester.tap(find.byType(AccountingCloseIcon));
    await tester.pumpAndSettle();
    expect(result, 'closed');
    semantics.dispose();
  });

  testWidgets(
    'editable popout uses Close for cancellation and Save in its footer',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => AccountingDialog.alert(
                context,
                title: 'Editable Information',
                content: const Text('Editable values'),
                actions: [
                  AccountingButton.ghost(
                    context,
                    key: null,
                    onPressed: () {},
                    child: const Text('Cancel'),
                  ),
                  AccountingButton.primary(
                    context,
                    key: null,
                    onPressed: () {},
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final footer = find.byKey(
        const ValueKey('accounting-form-dialog-footer'),
      );
      expect(footer, findsOneWidget);
      final box = tester.widget<Container>(footer).decoration as BoxDecoration;
      final context = tester.element(footer);
      expect(box.color, AccountingTheme.of(context).muted);
      for (final action in ['Save']) {
        expect(
          find.descendant(of: footer, matching: find.text(action)),
          findsOneWidget,
        );
      }
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(AccountingCloseIcon), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(AccountingCloseIcon))
            .getSemanticsData()
            .label,
        'Close',
      );
      semantics.dispose();
    },
  );
  testWidgets('fixed popup footer keeps body clearance while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => AccountingDialog.alert(
              context,
              title: 'Scrollable Fields',
              contentScrollKey: const ValueKey('test-popup-scroll'),
              content: SizedBox(
                height: 1400,
                child: Column(
                  children: [
                    const TextField(),
                    const Spacer(),
                    AccountingButton.outline(
                      context,
                      key: null,
                      onPressed: () {},
                      child: const Text('Last Field Action'),
                    ),
                  ],
                ),
              ),
              actions: [
                AccountingButton.primary(
                  context,
                  key: null,
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final scroll = find.byKey(const ValueKey('test-popup-scroll'));
    final state = tester.state<ScrollableState>(
      find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
    );
    final footer = find.byKey(const ValueKey('accounting-form-dialog-footer'));
    for (final fraction in [0.0, .5, 1.0]) {
      state.position.jumpTo(state.position.maxScrollExtent * fraction);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(footer).top - tester.getRect(scroll).bottom,
        closeTo(20, .01),
      );
      expect(tester.takeException(), isNull);
    }
    expect(
      tester.getRect(find.text('Last Field Action')).bottom,
      lessThan(tester.getRect(footer).top - 20),
    );
  });
  testWidgets('corner Close keeps cancellation result, key and busy state', (
    tester,
  ) async {
    var busy = true;
    String? result;
    StateSetter? update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialog) => StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return AccountingDialog.alert(
                        context,
                        title: 'Working',
                        content: const Text('Values'),
                        actions: [
                          AccountingButton.ghost(
                            context,
                            key: const ValueKey('dismiss-work'),
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(dialog, 'cancelled'),
                            child: const Text('Cancel'),
                          ),
                          AccountingButton.primary(
                            context,
                            key: null,
                            onPressed: () {},
                            child: const Text('Save'),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final close = find.byKey(const ValueKey('dismiss-work'));
    expect(find.text('Cancel'), findsNothing);
    final icon = close;
    expect(tester.widget<IconButton>(icon).onPressed, isNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(result, isNull);
    final surface = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card,
      ),
    );
    final frame = tester.getRect(surface.first);
    final rect = tester.getRect(close);
    expect(
      rect.top - frame.top,
      closeTo(AccountingPopoutTokens.closeInset, .01),
    );
    expect(
      frame.right - rect.right,
      closeTo(AccountingPopoutTokens.closeInset, .01),
    );
    update!(() => busy = false);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(result, 'cancelled');
  });

  testWidgets('page action retains Cancel outside dialog chrome', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: accountingFormFooter(
              context,
              actions: [
                AccountingButton.ghost(
                  context,
                  key: null,
                  onPressed: () => cancelled = true,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(AccountingCloseIcon), findsNothing);
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });
}
