import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final explicit in [false, true]) {
    testWidgets(
      'fixed width stays route-local and respects explicit owner $explicit',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1224, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () => AccountingDialog.showFixed<void>(
                    context: context,
                    contentWidth: 600,
                    builder: (dialogContext) => AccountingDialog.alert(
                      dialogContext,
                      title: 'Saved Information',
                      fixedContentWidth: explicit ? 320 : null,
                      content: const Text('Saved facts'),
                      actions: [
                        AccountingButton.primary(
                          dialogContext,
                          key: null,
                          child: const Text('Nested'),
                          onPressed: () => showDialog<void>(
                            context: dialogContext,
                            builder: (nestedContext) => AccountingDialog.alert(
                              nestedContext,
                              title: 'Nested warning',
                              content: const Text('Short warning.'),
                              actions: [],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final parentSurface = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first;
        final parentWidth = tester.getSize(parentSurface).width;
        expect(
          parentWidth,
          closeTo(
            (explicit ? 320 : 600) + AccountingPopoutTokens.contentInset * 2,
            .1,
          ),
        );
        await tester.tap(find.text('Nested'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(AlertDialog).last,
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .width,
          lessThan(parentWidth),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final initialWidth in [720.0, 1224.0]) {
    testWidgets(
      'fixed popout widens only when needed and keeps vertical scrolling at $initialWidth',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(initialWidth, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const channel = MethodChannel('audyt/window-layout');
        final requests = <double>[];
        String? acquiredOwner;
        String? releasedOwner;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            final arguments = call.arguments as Map;
            if (call.method == 'acquirePopoutWidth') {
              acquiredOwner = arguments['owner'] as String;
              final width = arguments['width'] as double;
              requests.add(width);
              final grownWidth = width > tester.view.physicalSize.width
                  ? width
                  : tester.view.physicalSize.width;
              tester.view.physicalSize = Size(
                grownWidth,
                tester.view.physicalSize.height,
              );
              return grownWidth;
            }
            expect(call.method, 'releasePopoutWidth');
            releasedOwner = arguments['owner'] as String;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () => AccountingDialog.showFixed<void>(
                    context: context,
                    contentWidth: 728,
                    contentInset: accountingContentInset,
                    builder: (dialogContext) => AccountingDialog.alert(
                      dialogContext,
                      title: 'Invoice',
                      contentInset: accountingContentInset,
                      fixedContentWidth: 728,
                      formFooter: true,
                      content: const SizedBox(
                        width: 728,
                        child: Column(
                          children: [
                            SizedBox(height: 1400),
                            Text('Last form field'),
                          ],
                        ),
                      ),
                      actions: [
                        AccountingButton.ghost(
                          dialogContext,
                          key: null,
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(requests, [848.0]);
        expect(acquiredOwner, isNotEmpty);
        expect(releasedOwner, isNull);
        expect(tester.view.physicalSize.height, 600);
        final material = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first;
        final surface = tester.getRect(material);
        expect(surface.width, closeTo(768, .1));
        final close = find
            .ancestor(
              of: find.byType(AccountingCloseIcon),
              matching: find.byType(IconButton),
            )
            .first;
        final closeRect = tester.getRect(close);
        expect(
          closeRect.top - surface.top,
          closeTo(AccountingPopoutTokens.closeInset, .1),
        );
        expect(
          surface.right - closeRect.right,
          closeTo(AccountingPopoutTokens.closeInset, .1),
        );
        expect(find.text('Last form field').hitTestable(), findsNothing);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -1450),
        );
        await tester.pumpAndSettle();
        expect(find.text('Last form field').hitTestable(), findsOneWidget);
        expect(tester.getRect(close), closeRect);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(releasedOwner, acquiredOwner);
        expect(
          tester.view.physicalSize.width,
          initialWidth == 720 ? 848 : 1224,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
