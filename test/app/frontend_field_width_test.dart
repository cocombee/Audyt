import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final spec in ['Invoice', 'Purchase Order', 'Scaled Invoice']) {
      testWidgets('$spec selectors fit actual choices at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final initial = <String, Object?>{
          'Currency': 'MYR',
          'Tax Mode': 'Exclusive',
          'Payment Terms': 'Days After Issue',
          'Counterparty': 'customer-0',
        };
        final form = spec == 'Purchase Order'
            ? frontendAreas['expenses-vendors']!.singleWhere(
                (f) => f.title == 'Purchase Orders',
              )
            : invoiceForm(
                {
                  for (var i = 0; i < 10; i++)
                    'customer-$i': 'Customer $i · Commercial Services',
                },
                {'sales': '4100 · Sales'},
              );
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    spec == 'Scaled Invoice' ? 1.4 : 1,
                  ),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        openFrontendForm(context, form, initial: initial),
                    child: const Text('Open Form'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Form'));
        await tester.pumpAndSettle();

        Future<void> capture(String state) async {
          final directory = Platform.environment['AUDYT_FIELD_CAPTURE_DIR'];
          if (directory == null) return;
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final frame = await boundary.toImage(pixelRatio: 1);
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$directory/Fields $spec $state ${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }

        for (final element
            in find.byType(AccountingSelector<String>).evaluate()) {
          final selector = element.widget as AccountingSelector<String>;
          if (selector.triggerKey == null) continue;
          final trigger = find.byKey(selector.triggerKey!);
          final label = find
              .descendant(of: trigger, matching: find.byType(Text))
              .first;
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '${selector.hintText} selected label must remain readable',
          );
          final style = tester.widget<Text>(label).style;
          for (final option in selector.options) {
            final painter = TextPainter(
              text: TextSpan(text: option.label, style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(element),
            )..layout();
            expect(
              painter.width,
              lessThanOrEqualTo(paragraph.size.width + 0.1),
              reason:
                  '${selector.hintText} must reserve its longest actual choice',
            );
            painter.dispose();
          }
        }
        await capture('Closed');
        final currency = find.byKey(const ValueKey('design-field-Currency'));
        await tester.ensureVisible(currency);
        await tester.pumpAndSettle();
        final closedRect = tester.getRect(currency);
        await tester.tap(currency);
        await tester.pumpAndSettle();
        await capture('Currency Choices');
        await tester.tap(find.text('£'));
        await tester.pumpAndSettle();
        expect(tester.getRect(currency), closedRect);
        final currencySelector = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey == const ValueKey('design-field-Currency'),
        );
        expect(
          tester.widget<AccountingSelector<String>>(currencySelector).value,
          'GBP',
        );
        final currencyOptions = tester
            .widget<AccountingSelector<String>>(currencySelector)
            .options;
        if (currencyOptions.any(
          (option) => option.value == 'Use Counterparty Default',
        )) {
          expect(
            currencyOptions
                .singleWhere(
                  (option) => option.value == 'Use Counterparty Default',
                )
                .label,
            'Default (RM)',
            reason:
                'An explicit override must not relabel the default currency',
          );
        }
        expect(
          tester
              .renderObject<RenderParagraph>(
                find.descendant(of: currency, matching: find.text('£')),
              )
              .didExceedMaxLines,
          isFalse,
        );
        await capture('Selected');
        if (spec != 'Purchase Order') {
          final customer = find.byKey(
            const ValueKey('design-field-Counterparty'),
          );
          Scrollable.of(tester.element(customer)).position.jumpTo(0);
          await tester.pumpAndSettle();
          final customerRect = tester.getRect(customer);
          await tester.tap(customer);
          await tester.pumpAndSettle();
          final search = find.byWidgetPredicate(
            (widget) => widget is TextField && widget.autofocus,
          );
          expect(search, findsOneWidget);
          await tester.enterText(search, 'Customer 9');
          await tester.pumpAndSettle();
          await capture('Customer Search');
          await tester.tap(find.text('Customer 9 · Commercial Services'));
          await tester.pumpAndSettle();
          expect(tester.getRect(customer), customerRect);
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.text('Customer 9 · Commercial Services'),
                )
                .didExceedMaxLines,
            isFalse,
          );
        }
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('design-keep-editing')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<AccountingSelector<String>>(currencySelector).value,
          'GBP',
        );
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-discard-changes')));
        await tester.pumpAndSettle();
        expect(initial['Currency'], 'MYR');
        expect(initial['Counterparty'], 'customer-0');
        expect(find.text('Open Form'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
