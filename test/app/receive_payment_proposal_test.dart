import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/receive_payment_proposal.dart';
import 'package:audyt/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inventory = <Map<String, Object?>>[];
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'unified lookup, two entry paths and outstanding-only allocation at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        for (final f in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
        }
        Future<void> open({
          String? invoiceId,
          List<ReceivePaymentInvoice>? invoices,
        }) async {
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('receipt-capture'),
              child: MaterialApp(
                key: UniqueKey(),
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ReceivePaymentProposal(
                          initialInvoiceId: invoiceId,
                          invoices: invoices,
                        ),
                      ),
                      child: const Text('Receive Payment'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Receive Payment'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        Future<void> capture(String title) async {
          final path = Platform.environment['AUDYT_RECEIPT_PROPOSAL_DIR'];
          if (path == null) return;
          Directory(path).createSync(recursive: true);
          var rect = t.getRect(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          );
          final menu = find.byKey(const ValueKey("receive-payment-menu"));
          if (menu.evaluate().isNotEmpty) {
            rect = rect.expandToInclude(t.getRect(menu));
          }
          String filename = "";
          await t.runAsync(() async {
            final image = await (t.renderObject(
              find.byKey(const ValueKey('receipt-capture')),
            ) as RenderRepaintBoundary).toImage();
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawImageRect(
              image,
              rect,
              Rect.fromLTWH(0, 0, rect.width, rect.height),
              Paint(),
            );
            final picture = recorder.endRecording();
            final cropped = await picture.toImage(
              rect.width.ceil(),
              rect.height.ceil(),
            );
            final png = await cropped.toByteData(
              format: ui.ImageByteFormat.png,
            );
            filename =
                'Unified Payment ${title.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '')} ${width.toInt()}.png';
            File('$path/$filename').writeAsBytesSync(png!.buffer.asUint8List());
            cropped.dispose();
            picture.dispose();
            image.dispose();
          });
          inventory.add({
            'category': 'Payment popout',
            'title': title,
            'width': width,
            'file': filename,
            'note': 'Unified Receive Payment proposal only. Actual approved searchable AccountingSelector and FrontendFormDialog owners; no commit callback or workspace writes. Blank standalone entry; invoice action preselects its ID. Details/allocations appear only after selection. Eligible invoices have positive outstanding balance after payments and credits. No aggregate customer option; customer-name search returns matching invoices. Selection uses the invoice identity and its currency. Invoice labels use the filename resolved by Document Settings; fixtures supply sample resolved names. Alphabetical customer then filename order. Live route/naming/posting migration remains pending.',
            'fields': [
              {
                'label': 'Customer or Invoice',
                'kind': 'selector',
                'options': t
                    .widget<AccountingSelector<String>>(
                      find.byType(AccountingSelector<String>).first,
                    )
                    .options
                    .map((o) => o.label)
                    .toList(),
              },
              for (final field
                  in t
                      .widget<FrontendFormDialog>(
                        find.byType(FrontendFormDialog),
                      )
                      .form
                      .fields)
                {
                  'label': field.label,
                  'multiline': field.multiline,
                  'required': field.required,
                  'options':
                      field.choiceLabels?.values.toList() ?? field.options,
                },
            ],
            'renderedTextLabels': find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Text),
                )
                .evaluate()
                .map((e) => (e.widget as Text).data ?? '')
                .where((s) => s.isNotEmpty)
                .toList(),
            'fieldMetadata': 'Rendered unified prototype, with fictional data and existing component owners.',
          });
        }

        Future<void> lookup() async {
          await t.ensureVisible(
            find.byKey(const ValueKey('receive-payment-lookup')),
          );
          await t.tap(find.byKey(const ValueKey('receive-payment-lookup')));
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('receive-payment-search')),
            findsOneWidget,
          );
        }

        await open();
        expect(
          find.byKey(const ValueKey('receive-payment-details')),
          findsNothing,
        );
        expect(find.text('Outstanding Invoices'), findsNothing);
        expect(
          find.byKey(const ValueKey('design-field-Payment Date')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('accounting-form-dialog-footer')),
          findsOneWidget,
        );
        await capture('Receive Payment · Blank');
        await lookup();
        final selector = t.widget<AccountingSelector<String>>(
          find.byType(AccountingSelector<String>).first,
        );
        expect(
          selector.options
              .where((o) => o.value.startsWith('invoice:'))
              .map((o) => o.label),
          [
            'A Company - INV-A',
            'A Company - INV-B',
            'B Company - INV-C',
            'C Company - INV-A',
          ],
        );
        expect(
          selector.options.any(
            (o) => o.label.contains('Cleared') || o.label.contains('Credited'),
          ),
          isFalse,
        );
        await capture('Receive Payment · Search Choices');
        await t.enterText(
          find.byKey(const ValueKey('receive-payment-search')),
          'INV-B',
        );
        await t.pumpAndSettle();
        expect(find.text('A Company - INV-B'), findsOneWidget);
        expect(find.text('C Company - INV-A'), findsNothing);
        await t.tap(find.text('A Company - INV-B'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('receive-payment-details')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('receive-allocation-a1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('receive-allocation-a2')),
          findsOneWidget,
        );
        expect(
          t
              .widget<AccountingLeadingCheckbox>(
                find.byType(AccountingLeadingCheckbox),
              )
              .value,
          isTrue,
        );
        await capture('Receive Payment · Invoice Selected');
        await lookup();
        await t.enterText(
          find.byKey(const ValueKey('receive-payment-search')),
          'INV-PAID',
        );
        await t.pumpAndSettle();
        expect(find.text('No Outstanding Invoices'), findsOneWidget);
        await capture('Receive Payment · Cleared Search');
        await t.enterText(
          find.byKey(const ValueKey('receive-payment-search')),
          'A Company',
        );
        await t.pumpAndSettle();
        expect(find.text('A Company - INV-A'), findsOneWidget);
        expect(find.text('A Company - INV-B'), findsOneWidget);
        expect(find.text('B Company - INV-C'), findsNothing);
        expect(find.textContaining('All Outstanding'), findsNothing);
        await capture('Receive Payment · Customer Search');
        await t.tap(find.text('A Company - INV-A'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('design-field-Amount Received')),
          '500.00',
        );
        await t.enterText(
          find.byKey(const ValueKey('receive-allocation-a1')),
          '500.00',
        );
        await t.pumpAndSettle();
        expect(find.text('500.00'), findsWidgets);
        await lookup();
        await t.enterText(
          find.byKey(const ValueKey('receive-payment-search')),
          'C Company',
        );
        await t.pumpAndSettle();
        await t.tap(find.text('C Company - INV-A'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('receive-allocation-a1')),
          findsNothing,
        );
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('receive-allocation-c1')),
              )
              .controller!
              .text,
          isEmpty,
        );
        await open(invoiceId: 'a1');
        expect(find.text('A Company - INV-A'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('receive-payment-details')),
          findsOneWidget,
        );
        expect(
          t
              .widget<AccountingLeadingCheckbox>(
                find.byType(AccountingLeadingCheckbox),
              )
              .value,
          isTrue,
        );
        await capture('Receive Payment · Invoice Shortcut');
        await open(invoiceId: 'paid');
        expect(
          find.byKey(const ValueKey('receive-payment-details')),
          findsNothing,
        );
        await open(
          invoices: [
            ReceivePaymentInvoice(
              id: 'void',
              customerId: 'v',
              customer: 'Reversed Company',
              filename: 'VOID',
              total: Money.fromMinor(10000, 'MYR'),
              reversed: true,
            ),
            ReceivePaymentInvoice(
              id: 'draft',
              customerId: 'n',
              customer: 'Draft Company',
              filename: 'DRAFT',
              total: Money.fromMinor(10000, 'MYR'),
              posted: false,
            ),
          ],
        );
        await lookup();
        expect(find.text('No Outstanding Invoices'), findsOneWidget);
        expect(t.takeException(), isNull);
        final path = Platform.environment['AUDYT_RECEIPT_PROPOSAL_DIR'];
        if (path != null) {
          File('$path/Unified Payment Inventory.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(inventory),
          );
        }
      },
    );
  }
}
