// Gallery evidence opens production routes against an isolated Demo Company.
// Layout copies cannot establish that a design is installed in the live app.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';

const _capture = ValueKey('design-capture');

Finder _selector(String label) => find.byWidgetPredicate(
  (w) =>
      w is AccountingSelector<String> &&
      w.triggerKey is ValueKey &&
      (w.triggerKey as ValueKey).value.toString().endsWith('-$label'),
);
Finder _input(String label) => find.byWidgetPredicate(
  (w) =>
      (w is TextFormField || w is AccountingDescriptionField) &&
      w.key is ValueKey &&
      (w.key as ValueKey).value.toString().endsWith('-$label'),
);

Future<void> _choose(WidgetTester tester, Finder finder, String value) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(value).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _captureDialog(
  WidgetTester tester,
  String? output,
  String name,
) async {
  if (output == null) return;
  final material = find
      .descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byType(Material),
      )
      .first;
  final rect = tester.getRect(material);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final shape = tester.widget<Material>(material).shape;
  await tester.runAsync(() async {
    final full = await boundary.toImage(pixelRatio: 1.5);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(1.5);
    if (shape != null) {
      canvas.clipPath(
        shape.getOuterPath(Rect.fromLTWH(0, 0, rect.width, rect.height)),
      );
    }
    canvas.scale(1 / 1.5);
    canvas.drawImageRect(
      full,
      Rect.fromLTRB(
        rect.left * 1.5,
        rect.top * 1.5,
        rect.right * 1.5,
        rect.bottom * 1.5,
      ),
      Rect.fromLTWH(0, 0, rect.width * 1.5, rect.height * 1.5),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(
      (rect.width * 1.5).round(),
      (rect.height * 1.5).round(),
    );
    final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
    cropped.dispose();
    full.dispose();
  });
}

void main() {
  final bounds = <String, Object?>{
    'authority': 'Production page routes and dialogs, isolated Demo Company; widget evidence only.',
    'owners': <String, Object?>{},
  };
  Map<String, double> coordinates(Rect rect) => {
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
  };
  for (final width in [1224.0, 720.0]) {
    testWidgets(
      'production Invoice, Quotation, Bill and Catalogue forms at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 2400);
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
        final w = await createDemoWorkspace(includeRowReview: true);
        addTearDown(w.dispose);
        final output = Platform.environment['AUDYT_DESIGN_CAPTURE'];
        final suffix = width == 720 ? ' Minimum Desktop' : '';
        for (final kind in [
          'Invoice',
          'Quotation',
          'Bill',
          'Product Service',
        ]) {
          tester.view.physicalSize = Size(width, 2400);
          final page = switch (kind) {
            'Invoice' => InvoicePage(workspace: w),
            'Quotation' => QuotationPage(workspace: w),
            'Bill' => BillsPage(workspace: w),
            _ => ProductCataloguePage(workspace: w),
          };
          await tester.pumpWidget(
            RepaintBoundary(
              key: _capture,
              child: MaterialApp(
                key: ValueKey('$kind-$width'),
                theme: AccountingTheme.light(),
                home: Scaffold(body: page),
                debugShowCheckedModeBanner: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final create = find.byKey(
            ValueKey(
              kind == 'Product Service'
                  ? 'catalogue-add-item'
                  : 'new-${kind.toLowerCase()}',
            ),
          );
          await tester.ensureVisible(create);
          await tester.tap(create);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$kind opens at $width',
          );
          if (kind != 'Product Service') {
            // Same ten-character content: a populated reference demonstrates
            // automatic rows with no blank-field sizing shortcut.
            for (final label in ['Date', 'Reference']) {
              await enterAccountingText(
                tester,
                find.byKey(ValueKey('design-field-$label')),
                '02-10-2026',
              );
            }
            await tester.pumpAndSettle();
            final dates = [
              for (final label in ['Date', 'Reference'])
                tester.getRect(find.byKey(ValueKey('design-field-$label'))),
            ];
            expect(dates[0].top, dates[1].top);
            expect(
              find.byKey(const ValueKey('design-field-Due Date')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('design-field-Expiry Date')),
              findsNothing,
            );
            expect(dates[0].width, greaterThan(100));
            expect(dates[1].width, greaterThan(100));
            if (kind == 'Quotation') {
              expect(
                find.byKey(const ValueKey('design-field-Payment Terms')),
                findsNothing,
              );
              for (final choice in [
                ('90 Days', '31-12-2026'),
                ('60 Days', '01-12-2026'),
                ('30 Days', '01-11-2026'),
              ]) {
                await _choose(
                  tester,
                  find.byKey(const ValueKey('design-field-Validity')),
                  choice.$1,
                );
                expect(find.text('Valid until: ${choice.$2}'), findsNothing);
                expect(
                  find.byWidgetPredicate(
                    (w) =>
                        w is Tooltip &&
                        (w.message ?? '').contains('Valid until: ${choice.$2}'),
                  ),
                  findsOneWidget,
                );
              }
            }
            for (final label in ['Date', 'Reference']) {
              final input = tester.widget<TextFormField>(
                find.byKey(ValueKey('design-field-$label')),
              );
              expect(input.controller!.text, '02-10-2026');
            }
            final customer = tester.getRect(
              find.byKey(const ValueKey('design-field-Counterparty')),
            );
            expect(customer.top, lessThanOrEqualTo(dates[0].top));
          }
          if (kind == 'Product Service') {
            final fields = [
              for (final key in [
                'catalogue-type',
                'catalogue-tax',
                'catalogue-category',
                'catalogue-item-name',
              ])
                tester.getRect(find.byKey(ValueKey(key))),
            ];
            expect(fields[0].top, fields[1].top);
            expect(fields[2].top, fields[3].top);
            expect(fields.map((r) => r.width).toSet(), hasLength(1));
            await _choose(
              tester,
              find.byKey(const ValueKey('catalogue-category')),
              'Video',
            );
            await _choose(
              tester,
              find.byKey(const ValueKey('catalogue-item-name')),
              'Corporate Video',
            );
            final description = tester.widget<AccountingDescriptionField>(
              find.byKey(const ValueKey('catalogue-description')),
            );
            expect(description.fixedLines, isNotNull);
            (bounds['owners'] as Map<String, Object?>)['$kind-$width'] = {
              'controls': fields.map(coordinates).toList(),
              'description': coordinates(
                tester.getRect(
                  find.byKey(const ValueKey('catalogue-description')),
                ),
              ),
              'fixedLines': description.fixedLines,
            };
            await _captureDialog(tester, output, '$kind Popout$suffix');
            // These menus and creation dialogs belong to the live catalogue owner.
            if (width == 1224) {
              for (final entry in [
                ('catalogue-category', 'Category', 'Add Category'),
                ('catalogue-item-name', 'Item Name', 'Add Item'),
              ]) {
                await tester.tap(find.byKey(ValueKey(entry.$1)));
                await tester.pumpAndSettle();
                if (output != null) {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    find.byKey(_capture),
                  );
                  await tester.runAsync(() async {
                    final image = await boundary.toImage(pixelRatio: 1.5);
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    await File('$output/${entry.$2} Selector Review.png')
                        .writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
                await tester.tap(find.text(entry.$3).last);
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const ValueKey('catalogue-manual-name')),
                  findsOneWidget,
                );
                await _captureDialog(
                  tester,
                  output,
                  'Add ${entry.$2} Registration',
                );
                await tester.tap(
                  find.byKey(const ValueKey('catalogue-cancel-name')),
                );
                await tester.pumpAndSettle();
              }
            }
          } else {
            for (final rowKey in [
              'design-line-subtotal',
              'design-line-tax',
              'design-line-total',
            ]) {
              final row = find.byKey(ValueKey(rowKey));
              expect(row, findsOneWidget);
              expect(
                find.descendant(of: row, matching: find.text('0.00')),
                findsOneWidget,
              );
            }
            final recurring = find.byKey(
              const ValueKey('design-field-Make Recurring'),
            );
            expect(recurring, findsOneWidget);
            await _choose(tester, recurring, 'Monthly');
            expect(
              find.byKey(const ValueKey('design-field-Start Date')),
              findsOneWidget,
            );
            await _choose(tester, recurring, 'No');
            if (kind == 'Bill') {
              await _choose(
                tester,
                find.byKey(const ValueKey('design-field-Tax Mode')),
                'Tax Exclusive',
              );
            } else {
              expect(
                find.byKey(const ValueKey('design-field-Tax Mode')),
                findsNothing,
              );
              expect(
                find.byKey(const ValueKey('design-document-tax')),
                findsOneWidget,
              );
            }
            final field = kind == 'Bill' ? 'Account' : 'Product / Service';
            final choice = kind == 'Bill'
                ? (await w.accounts())
                      .singleWhere((a) => a.account.code == '5000')
                      .account
                      .name
                : 'Corporate Video';
            await _choose(tester, _selector(field).first, choice);
            await enterAccountingText(
              tester,
              _input('Description').first,
              'Company introduction video with a long description that wraps within this row, keeping the adjacent fields aligned to the top.',
            );
            await enterAccountingText(
              tester,
              _input('Amount').first,
              '1234567.89',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('design-add-line')));
            await tester.pumpAndSettle();
            await _choose(
              tester,
              _selector(field).last,
              kind == 'Bill' ? choice : 'Product Photography',
            );
            await enterAccountingText(tester, _input('Amount').last, '2450');
            await tester.pumpAndSettle();
            final boxes = [
              _selector(field).first,
              _input('Description').first,
              if (kind == 'Bill') _selector('Tax Rate (%)').first,
              _input('Amount').first,
            ];
            final rects = boxes.map(tester.getRect).toList();
            (bounds['owners'] as Map<String, Object?>)['$kind-$width'] = {
              'lineFields': rects.map(coordinates).toList(),
              'peerGap': AccountingTransactionGridTokens.peerGap,
              'amountHeight': tester.getSize(_input('Amount').first).height,
              'columnWidths': {
                field: tester.getSize(_selector(field).first).width,
                'Amount': tester.getSize(_input('Amount').first).width,
              },
            };
            expect(rects.map((r) => r.top).toSet(), hasLength(1));
            expect(rects[1].height, greaterThan(accountingControlHeight));
            for (var i = 1; i < rects.length; i++) {
              expect(
                rects[i].left - rects[i - 1].right,
                closeTo(AccountingTransactionGridTokens.peerGap, .01),
              );
            }
            for (final row in [0, 1]) {
              expect(
                tester.getSize(_input('Amount').at(row)).height,
                accountingControlHeight,
              );
            }
            expect(
              tester.getSize(_selector(field).first).width,
              tester.getSize(_selector(field).last).width,
            );
            expect(
              tester.getSize(_input('Amount').first).width,
              tester.getSize(_input('Amount').last).width,
            );
            await _captureDialog(tester, output, '$kind Popout$suffix');
            if (kind == 'Invoice' && width == 1224) {
              await tester.tap(_selector('Product / Service').first);
              await tester.pumpAndSettle();
              if (output != null) {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(_capture),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1.5);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File('$output/Item Selector Review.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.tap(find.text('Add Item').last);
              await tester.pumpAndSettle();
              expect(find.byType(CatalogueItemDialog), findsOneWidget);
              await _captureDialog(tester, output, 'Add Item Registration');
              await tester.tap(
                find.byKey(const ValueKey('catalogue-cancel-item')),
              );
              await tester.pumpAndSettle();
            }
          }
          if (kind != 'Product Service') {
            await _choose(
              tester,
              find.byKey(
                ValueKey(
                  kind == 'Quotation'
                      ? 'design-field-Validity'
                      : 'design-field-Payment Terms',
                ),
              ),
              'Custom',
            );
            final memo = find.byKey(
              ValueKey(
                kind == 'Quotation'
                    ? 'design-field-Memo'
                    : 'design-field-Custom Payment Terms',
              ),
            );
            expect(
              tester.widget<AccountingDescriptionField>(memo).role,
              kind == 'Quotation'
                  ? AccountingDescriptionRole.memo
                  : AccountingDescriptionRole.paymentTerms,
            );
            expect(
              find.byKey(const ValueKey('design-field-Due Date')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('design-field-Expiry Date')),
              findsNothing,
            );
            if (kind == 'Quotation') {
              expect(find.text('Quotation Info'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('quotation-valid-until')),
                findsNothing,
              );
            }
            await enterAccountingText(
              tester,
              memo,
              kind == 'Quotation'
                  ? '1. Offer validity subject to availability.\n2. Please confirm the final scope before acceptance.'
                  : '1. First instalment after delivery.\n2. Balance after acceptance.',
            );
            await tester.pumpAndSettle();
            if (kind == 'Quotation') {
              final text = tester
                  .widget<AccountingDescriptionField>(memo)
                  .controller!
                  .text;
              await _choose(
                tester,
                find.byKey(const ValueKey('design-field-Validity')),
                '30 Days',
              );
              expect(find.text('Memo'), findsOneWidget);
              expect(
                tester
                    .widget<AccountingDescriptionField>(memo)
                    .controller!
                    .text,
                text,
              );
              await _choose(
                tester,
                find.byKey(const ValueKey('design-field-Validity')),
                'Custom',
              );
              expect(find.text('Quotation Info'), findsOneWidget);
              expect(
                tester
                    .widget<AccountingDescriptionField>(memo)
                    .controller!
                    .text,
                text,
              );
              expect(
                find.byKey(const ValueKey('design-field-Expiry Date')),
                findsNothing,
              );
            }
            await _captureDialog(
              tester,
              output,
              '$kind Custom Terms Popout$suffix',
            );
          }
          expect(tester.takeException(), isNull, reason: '$kind at $width');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
        if (output != null) {
          File('$output/Form Rendered Bounds.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(bounds),
          );
        }
      },
    );
  }
}
