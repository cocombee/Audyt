import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:audyt/features/sales/sales_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/description_sample.dart';
import '../support/fixed_popout_host.dart';
import '../support/generated_document_host.dart';
import '../support/sales_report_fixture.dart';
import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final rateEnabled in [false, true]) {
    testWidgets(
      'description and bidirectional pricing save/reopen with Rate $rateEnabled',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        await installGeneratedDocumentHost(tester);
        for (final font in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
        final f = await salesReportFixture();
        final w = f.workspace;
        addTearDown(w.dispose);
        w.savePreferences(
          w.preferences.change('Sales Preferences', {
            'Show Quantity': true,
            'Show Rate': rateEnabled,
          }),
        );
        w.savePreferences(
          w.preferences.change('Business Profile', {
            'Business Name': 'Demo Company',
            'Legal Name': 'Demo Company Sdn. Bhd.',
            'Address Line 1': '12 Jalan Demo',
            'Address Line 2': 'Suite 3A',
            'City': 'Kuala Lumpur',
            'Postcode': '50450',
            'Email': 'accounts@demo.example',
            'Telephone': '+60 3 0000 0001',
          }),
        );
        final customer = f.customer.revise(
          displayName: 'Bright Studio',
          contact: const CustomerContact(
            contactName: 'Bright Studio',
            email: 'accounts3@example.test',
            phone: '+60 3 0000 0002',
          ),
          billingAddress: const CustomerAddress(
            line1: '24 Jalan Demo',
            line2: 'Level 2',
            city: 'Petaling Jaya',
            postalCode: '47301',
            countryCode: 'MY',
            stateOrProvince: 'Selangor',
          ),
          updatedAt: DateTime.utc(2026, 9, 30),
        );
        w.saveCustomer(customer);
        final category = w.catalogueCategories.singleWhere(
          (c) => c.name == 'Video',
        );
        final item = w.catalogueItems.singleWhere(
          (i) => i.name == 'Corporate Video',
        );
        final line = SalesLineItem.category(
          id: EntityId.random(),
          categoryId: f.income,
          description: 'Initial description',
          quantity: SalesQuantity.fromInt(4),
          rate: Money.fromDecimal('2', 'MYR'),
          manualAmount: rateEnabled ? null : Money.fromDecimal('8', 'MYR'),
          rateEnabled: rateEnabled,
          taxRatePercent: '0',
          catalogue: item.snapshot(category),
        );
        final second = SalesLineItem.category(
          id: EntityId.random(),
          categoryId: f.income,
          description: 'Short delivery note.',
          quantity: SalesQuantity.fromInt(1),
          rate: Money.fromDecimal('1', 'MYR'),
          manualAmount: rateEnabled ? null : Money.fromDecimal('1', 'MYR'),
          rateEnabled: rateEnabled,
          taxRatePercent: '0',
          catalogue: item.snapshot(category),
        );
        final quote = Estimate.draft(
          id: EntityId.random(),
          customerId: customer.id,
          documentNumber: 'QT-DESCRIPTION-SAMPLE',
          issueDate: DateTime.utc(2026, 9, 30),
          validUntil: DateTime.utc(2026, 10, 30),
          taxMode: 'Exclusive',
          lines: [line, second],
        );
        w.saveQuotationDraft(
          quote,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 30),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: QuotationPage(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await pumpGeneratedDocumentWork(tester);
        }

        Future<void> edit() =>
            tap(find.byKey(ValueKey('edit-quotation-${quote.id}')));
        Finder field(String label) => find
            .byWidgetPredicate(
              (widget) =>
                  (widget is TextFormField ||
                      widget is AccountingDescriptionField) &&
                  widget.key is ValueKey &&
                  (widget.key as ValueKey).value.toString().endsWith('-$label'),
            )
            .first;
        String value(String label) =>
            tester.widget<TextFormField>(field(label)).controller?.text ??
            tester.widget<TextFormField>(field(label)).initialValue ??
            '';
        Future<void> enter(String label, String text) async {
          await tester.ensureVisible(field(label));
          await enterAccountingText(tester, field(label), text);
          await tester.pumpAndSettle();
        }

        await edit();
        expect(find.text('Amount (RM)'), findsOneWidget);
        expect(find.text('Total (RM)'), findsOneWidget);
        expect(
          find.text('Rate (RM)'),
          rateEnabled ? findsOneWidget : findsNothing,
        );
        expect(find.text('Amount (MYR)'), findsNothing);
        final date = find.byKey(const ValueKey('design-field-Date'));
        final reference = find.byKey(const ValueKey('design-field-Reference'));
        expect(
          find.byKey(const ValueKey('design-field-Expiry Date')),
          findsNothing,
        );
        expect(tester.getTopLeft(date).dy, tester.getTopLeft(reference).dy);
        expect(
          tester.getTopLeft(reference).dx,
          greaterThan(tester.getTopLeft(date).dx),
        );
        final descriptionWidth = tester.getSize(field('Description')).width;
        final quantityWidth = tester.getSize(field('Quantity')).width;
        final amountWidth = tester.getSize(field('Amount')).width;
        final fixedContent = find.byKey(
          const ValueKey('accounting-form-dialog-footer'),
        );
        final formWidth = tester.getSize(fixedContent).width;
        expect(quantityWidth, lessThan(60));
        expect(amountWidth, lessThan(100));
        expect(
          tester
              .widget<InputDecorator>(
                find.descendant(
                  of: field('Quantity'),
                  matching: find.byType(InputDecorator),
                ),
              )
              .decoration
              .contentPadding,
          const EdgeInsets.symmetric(
            horizontal: accountingFieldContentInset,
            vertical: 12,
          ),
        );
        if (rateEnabled) {
          final rateWidth = tester.getSize(field('Rate')).width;
          expect(rateWidth, lessThan(100));
          await enter('Rate', '123456.78');
          expect(tester.getSize(field('Rate')).width, greaterThan(rateWidth));
          expect(
            tester.getSize(field('Description')).width,
            lessThan(descriptionWidth),
          );
          expect(tester.getSize(fixedContent).width, formWidth);
          await enter('Rate', '2.00');
        } else {
          await enter('Amount', '123456.78');
          expect(
            tester.getSize(field('Amount')).width,
            greaterThan(amountWidth),
          );
          expect(
            tester.getSize(field('Description')).width,
            lessThan(descriptionWidth),
          );
          expect(tester.getSize(fixedContent).width, formWidth);
          await enter('Amount', '8.00');
        }
        await enter('Quantity', '9999');
        expect(
          tester.getSize(field('Quantity')).width,
          greaterThan(quantityWidth),
        );
        expect(tester.getSize(fixedContent).width, formWidth);
        await enter('Quantity', '4');
        for (final label in ['Quantity', 'Amount', if (rateEnabled) 'Rate']) {
          final peers = find.byWidgetPredicate(
            (w) =>
                w is TextFormField &&
                w.key is ValueKey &&
                (w.key as ValueKey).value.toString().endsWith('-$label'),
          );
          expect(
            tester.getSize(peers.first).width,
            tester.getSize(peers.last).width,
          );
          expect(
            tester.getTopLeft(peers.first).dx,
            tester.getTopLeft(peers.last).dx,
          );
        }
        final restoredWidth = tester.getSize(field('Description')).width;
        final shortDescriptionHeight = tester
            .getSize(field('Description'))
            .height;
        await enter('Description', descriptionSample);
        expect(tester.getSize(field('Description')).width, restoredWidth);
        expect(
          tester.getSize(field('Description')).height,
          greaterThan(shortDescriptionHeight),
        );
        expect(
          tester.getTopLeft(field('Description')).dy,
          tester.getTopLeft(field('Quantity')).dy,
        );
        final descriptions = find
            .byType(AccountingDescriptionField)
            .evaluate()
            .where(
              (e) =>
                  e.widget.key is ValueKey &&
                  (e.widget.key as ValueKey).value.toString().endsWith(
                    '-Description',
                  ),
            )
            .toList();
        final secondField = find.byWidget(descriptions[1].widget);
        expect(
          tester.getTopLeft(secondField).dy -
              tester.getBottomLeft(field('Description')).dy,
          closeTo(10, 0.1),
        );
        expect(double.parse(value('Amount').replaceAll(',', '')), 8);
        await enter('Quantity', '3');
        if (rateEnabled) {
          expect(value('Amount'), '6.00');
          await enter('Amount', '10');
          expect(value('Rate'), '3.34');
          expect(value('Amount'), '10');
          await enter('Rate', '3.3');
          expect(value('Amount'), '9.90');
          await enter('Amount', '10');
        } else {
          expect(value('Amount'), '8.00');
          await enter('Amount', '10');
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextFormField &&
                  widget.key is ValueKey &&
                  (widget.key as ValueKey).value.toString().endsWith('-Rate'),
            ),
            findsNothing,
          );
        }
        const memoSample =
            '1. Keep delivery notes and client feedback with this quotation. Long memo text wraps inside this fixed box and scrolls vertically.\n2. Confirm the final handover after both review rounds.\n- Send the approved master and social versions together.';
        final memoField = find.byKey(const ValueKey('design-field-Memo'));
        await tester.ensureVisible(memoField);
        final memoFrame = tester.getRect(memoField);
        await enterAccountingText(tester, memoField, memoSample);
        await tester.pumpAndSettle();
        expect(tester.getRect(memoField).size, memoFrame.size);
        final memoScroller = tester
            .state<ScrollableState>(
              find
                  .descendant(of: memoField, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        expect(memoScroller.maxScrollExtent, greaterThan(0));
        tester
            .state<AccountingDescriptionFieldState>(memoField)
            .focus
            .unfocus();
        memoScroller.jumpTo(0);
        await tester.ensureVisible(field('Description'));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          rateEnabled
              ? 'Quotation Description Fields'
              : 'Quantity Only Description Fields',
        );
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final saved = w
            .quotations()
            .singleWhere((r) => r.quotation.id == quote.id)
            .quotation;
        expect(saved.lines.first.description, descriptionSample);
        expect(saved.memo, memoSample);
        expect(saved.lines.first.quantity.toString(), '3');
        expect(saved.lines.first.total.minorUnits, 1000);
        expect(saved.lines.first.rateEnabled, rateEnabled);
        expect(
          saved.lines.first.pricingAdjustment.minorUnits,
          rateEnabled ? 2 : 0,
        );
        expect(saved.total.minorUnits, 1100);
        final restored = Estimate.fromSnapshot(
          jsonDecode(jsonEncode(saved.snapshot())),
        );
        expect(restored.lines.first.toJson(), saved.lines.first.toJson());
        final capture = Platform.environment['AUDYT_DESCRIPTION_PDF_CAPTURE'];
        if (capture != null && rateEnabled) {
          Directory(capture).createSync(recursive: true);
          final generated = saved.attachments.singleWhere((a) => a.isGenerated);
          File('$capture/Quotation Description Sample.pdf')
              .writeAsBytesSync(generated.originalBytes);
          final invoice = saved.pricingSnapshot();
          final pdf = await const SalesDocumentRenderer().render(
            SalesDocumentSnapshot.invoice(
              businessId: w.identity.businessId,
              invoice: invoice,
              customer: customer,
              preferences: w.preferences,
            ),
            filename: 'Invoice Description Sample.pdf',
          );
          File('$capture/Invoice Description Sample.pdf')
              .writeAsBytesSync(pdf.originalBytes);
        }
        await edit();
        expect(
          tester
              .state<AccountingDescriptionFieldState>(field('Description'))
              .editor
              .plainDescription,
          descriptionSample,
        );
        expect(value('Amount'), '10.00');
        if (rateEnabled) expect(value('Rate'), '3.34');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
