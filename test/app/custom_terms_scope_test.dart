import 'package:audyt/features/sales/domain/product_catalogue.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_document_template.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/features/sales/sales_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import '../support/generated_document_host.dart';
import '../support/sales_report_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom terms, separate memo and due date survive SQLite and recurrence',
    () async {
      final f = await salesReportFixture();
      addTearDown(f.workspace.dispose);
      final date = DateTime.utc(2026, 10, 1);
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: f.customer.id,
        lines: [
          SalesLineItem.category(
            id: EntityId.random(),
            categoryId: f.income,
            description: 'Fictional service',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(100, 'MYR'),
            taxRatePercent: '0',
          ),
        ],
        issueDate: date,
        dueDate: date.add(const Duration(days: 12)),
        terms: PaymentTerms.custom(
          'First instalment after delivery.\nBalance after review.',
        ),
        memo: 'Retained original memo',
        taxMode: 'Exclusive',
      );
      f.workspace.saveInvoiceDraft(invoice, expectedRevision: 0, savedAt: date);
      final saved = f.workspace.invoiceDrafts().singleWhere(
        (r) => r.invoice.id == invoice.id,
      );
      final values = invoiceFormValues(saved.invoice);
      expect(values['Payment Terms'], 'Custom');
      expect(values['Custom Payment Terms'], invoice.terms.label);
      expect(values['Memo'], invoice.memo);
      final edited = invoiceFromForm(
        values,
        id: invoice.id,
        existing: invoice,
        customer: f.customer,
        incomeAccountIds: {f.income.value},
      );
      expect(edited.terms.label, invoice.terms.label);
      expect(edited.memo, invoice.memo);
      final standard = invoiceFromForm(
        {...values, 'Payment Terms': 'Net 30', 'Due Date': '31-10-2026'},
        id: invoice.id,
        existing: invoice,
        customer: f.customer,
        incomeAccountIds: {f.income.value},
      );
      f.workspace.saveInvoiceDraft(
        standard,
        expectedRevision: saved.revision,
        savedAt: date.add(const Duration(seconds: 1)),
      );
      final reopened = f.workspace.invoiceDrafts().singleWhere(
        (r) => r.invoice.id == invoice.id,
      );
      expect(reopened.invoice.terms.label, 'Net 30');
      expect(reopened.invoice.terms.customText, invoice.terms.customText);
      expect(reopened.invoice.memo, invoice.memo);
      final restoredCustom = invoiceFromForm(
        {
          ...invoiceFormValues(reopened.invoice),
          'Payment Terms': 'Custom',
          'Due Date': '13-10-2026',
        },
        id: invoice.id,
        existing: reopened.invoice,
        customer: f.customer,
        incomeAccountIds: {f.income.value},
      );
      f.workspace.saveInvoiceDraft(
        restoredCustom,
        expectedRevision: reopened.revision,
        savedAt: date.add(const Duration(seconds: 2)),
      );
      final customRevision = f.workspace
          .invoiceDrafts()
          .singleWhere((r) => r.invoice.id == invoice.id)
          .revision;
      expect(restoredCustom.terms.label, invoice.terms.label);
      expect(
        PaymentTerms.fromJson(jsonDecode(jsonEncode(invoice.terms.toJson())))
            .label,
        invoice.terms.label,
      );
      final schedule = f.workspace.saveDocumentSchedule(
        id: EntityId.random().value,
        name: 'Custom terms recurrence',
        kind: RecurringDocumentKind.invoice,
        sourceId: invoice.id,
        sourceRevision: customRevision,
        expectedRevision: 0,
        schedule: RecurrenceRule(
          startsOn: DateTime.utc(2026, 11, 1),
          unit: RecurrenceUnit.months,
          occurrenceCount: 1,
        ),
      );
      final next = f.workspace.database.prepareDocumentOccurrence(
        businessId: f.workspace.identity.businessId,
        actorId: f.workspace.identity.ownerId,
        templateId: schedule.id,
        expectedRevision: schedule.revision,
        index: 0,
        preparedAt: DateTime.utc(2026, 11, 1),
      );
      final recurring = f.workspace
          .invoiceDrafts()
          .singleWhere((r) => r.invoice.id.value == next)
          .invoice;
      expect(recurring.terms.label, invoice.terms.label);
      expect(
        recurring.dueDate.difference(recurring.issueDate),
        const Duration(days: 12),
      );
      final quote = Estimate.draft(
        id: EntityId.random(),
        customerId: f.customer.id,
        total: invoice.total,
        issueDate: date,
        validUntil: invoice.dueDate,
        terms: invoice.terms,
      );
      expect(
        Estimate.fromSnapshot(jsonDecode(jsonEncode(quote.snapshot())))
            .terms
            .label,
        invoice.terms.label,
      );
      expect(() => invoice.terms.dueOn(date), throwsFormatException);
    },
  );

  testWidgets(
    'only item paragraphs scale relative to their editor font, Memo has no extra',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                for (final role in [
                  AccountingDescriptionRole.narrative,
                  AccountingDescriptionRole.transactionItem,
                  AccountingDescriptionRole.memo,
                ])
                  SizedBox(
                    width: 300,
                    child: AccountingDescriptionField(
                      key: ValueKey(role),
                      role: role,
                      fixedHeight: 120,
                      initialValue: 'Alpha\nBeta',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double interval(AccountingDescriptionRole role) {
        final field = find.byKey(ValueKey(role));
        Finder paragraph(String value) => find.descendant(
          of: field,
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().trim() == value,
          ),
        );
        return tester.getTopLeft(paragraph('Beta').first).dy -
            tester.getTopLeft(paragraph('Alpha').first).dy;
      }

      expect(
        interval(AccountingDescriptionRole.transactionItem),
        closeTo(13 * (17.8 / 9), .5),
      );
      expect(
        interval(AccountingDescriptionRole.memo),
        lessThan(interval(AccountingDescriptionRole.narrative)),
      );
      double? fontSize(AccountingDescriptionRole role) => tester
          .widget<RichText>(
            find
                .descendant(
                  of: find.byKey(ValueKey(role)),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is RichText && w.text.toPlainText().trim() == 'Alpha',
                  ),
                )
                .first,
          )
          .text
          .style
          ?.fontSize;
      expect(fontSize(AccountingDescriptionRole.transactionItem), 13);
      expect(
        fontSize(AccountingDescriptionRole.transactionItem),
        fontSize(AccountingDescriptionRole.narrative),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('current renderer produces short, custom, many-item and long-paragraph samples', () async {
    final f = await salesReportFixture();
    addTearDown(f.workspace.dispose);
    final preferences = f.workspace.preferences
        .change('Sales Preferences', {'Show Quantity': true, 'Show Rate': true})
        .change('Business Profile', {
          'Business Name': 'Fictional Demo Company',
          'Address Line 1': '24 Jalan Demo',
          'Address Line 2': 'Unit 12',
          'City': 'Petaling Jaya',
          'Postcode': '46000',
          'State / Region': 'Selangor',
          'Country': 'Malaysia',
          'Telephone': '+60 12 345 6789',
          'Email': 'demo@example.test',
          '_businessLogoBase64': 'iVBORw0KGgoAAAANSUhEUgAAALQAAAC0CAIAAACyr5FlAAAFh0lEQVR4nO3dzW8UdRzH8d/sbrVCKWpBaKCpLVjxocY0UhE8QYpcNI3GRIkaDiaCD3+A4VAx0RgTPWAIXkxMSUx8OJCIhtD0IpWHbTAoltDSUrCSUroI7lJouw9jyujaA59hd2e3zo7vVzhsZ37dHn7vfufXvWDZtm2Amwnd9CpAHHDD5IBEHJCIAxJxQCIOSMQBiTggRUzpte7fMQc/5X8ouqmjpO9vlejjc4IIQCjFj4MsApNIMeMgi4AlUpw4yCKQiRThrxXK8Cfv++I1DsrwM4+7U/hjhSwC/4gpcHJQRnkpbL8KiYMyylEBu8bH5yheHIyN8pXv3uUXB2WUu7x2MI84KCMYct9HzhzwHAdjI0hy3E0mB7zFwdgInlz2lMkBD3EwNoLqljvL5IBEHJCIA4XGwYEj2Nz3l8kBiTggEQck4oBEHJCIAxJxQCIOSMQBiTggEQck4oBEHJCIAxJxQCIOSMQBiTggEQck4oBEHJCIAxJxQCIOSMQBiTggEQck4oBEHJCIAxJxQCIOSMQBiTggEQck4oBEHJCIAxJxQCIOSMQBiTggEQck4oAUMXPuYNv2vj/P28auCIX3jvy07/zx7EVnwQ8X+784e7hn4/aDFwfePv61c/HdR55dv/SBJw+8Z4x5etmjz9e3pjLpSCj85bmj353/Ofvm7XUtz9Wtvpaaupae/qBv39hk3H09/BVH0k5vjX5ujLkjXPFRy4vX09PdF05mL2ZNZ9L182tClpWxbcuY5fPums6kjTFrFq14ZnnLG72dieTkgorKj1s2j08mopfOGGMer2l8qrb51aOfTaVTaxev7Ghuf72302U9/PtYuZ5O7uzveqF+jVpwKj764MJlxpim6qWnE2POxZcb1u3sP5BIThpjEsnJT/q7Xmlc59x6qWHtroHuqXTKGHNofPD3a5cjVshlPXx95hhMjNXNv1vdPRIbemLRihvTYuWR2JBz8d6qRf3xC9k1p+KjDVWLndeNVfcMxEezt97v+zZlZ1zWw9dxhEOh1I2HRYUV/rR1i/Ov+c7lzt0jsaHVNY3GmMdqGtSDwLKMsf9+HZr54hZmr4fvzhyzPbRw2WDi4uyDyGzx5HXbtpdUVhtjJlJTzsXhq+Orqmt/uTLifLmquvbM1Zl3MMb8NnGpqXrpr1dmDraWMR3N7e+c2OuyHv6dHAsqKt9satsz/KPLmsOxwW1NG6Kxf8fGnuFDb93fVhW5PfsOnf+8wzcjvVvvW39bKGyM2Vj7cEUo4r4evpsczhPENnbECncO9xz742z2orPgxJWRXQPdzuue8dPbmjZs7tmd/fajsaElldW7W7ckM6lIKPzVuWjvpWHnVtdoX928ms61r12enrg8PfHhye/d18OdZdtuT2D+A8DAi27qULf4hBQScUAiDkjEAYk4IBEHJOKARByQiAMScUAiDkjEAYk4IBEHJOKARByQiAMScUAiDkjEAYk4IBEHJOKARByQiAMScUAiDkjEAYk4IBEHJOKARByQiAMScYA4kD8mByTigEQckIgDEnFAIg5IxAGJOCARByTigEQckIgDEnFAIg5IxAGJOCARByTigEQckIgDEnFAIg5IxAGJOCARByTiQKFxRDd1uC9AWXPfXyYHJOKARBzwEAfHjqC65c4yOeAtDoZH8OSyp0wOeI6D4REkOe4mkwPFiIPhEQy572N+k4M+yl1eO5j3Y4U+yle+e8eZA0WNg+FRjgrYtQInB32Ul8L2y7Jt28tPbd2/w8u3o9S8/Bp7PXMwQvzM4+4U4UBKH/7kfV+8PlZm4xHjE8X6dS1mHA4S+Q8Vd4oXPw4HicyxUjzcSxXHbIRSIqU+7c1FHChTfHwOiTggEQck4oBEHJCIAxJxQCIOGOUvvxLZ2IS5vCYAAAAASUVORK5CYII=',
        });
    final customer = Customer.create(
      metadata: f.customer.metadata,
      displayName: 'Fictional Customer',
      contact: const CustomerContact(
        phone: '+60 11 1234 5678',
        email: 'customer@example.test',
      ),
      billingAddress: const CustomerAddress(
        line1: '12 Jalan Contoh',
        line2: 'Unit 8',
        city: 'Shah Alam',
        postalCode: '40000',
        stateOrProvince: 'Selangor',
        countryCode: 'MY',
      ),
      taxProfile: f.customer.taxProfile,
      currency: f.customer.currency,
      paymentTerms: f.customer.paymentTerms,
    );
    for (final scenario in [
      'Memo',
      'Custom Terms',
      'Many Items',
      'Long Description',
    ]) {
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: customer.id,
        documentNumber: 'INV-FICTIONAL',
        issueDate: DateTime.utc(2026, 10, 1),
        dueDate: DateTime.utc(2026, 10, 31),
        terms: scenario == 'Custom Terms'
            ? PaymentTerms.custom(
                '1. First instalment after delivery and a complete review of every supplied item.\n2. Balance after acceptance of the final delivered work.',
              )
            : PaymentTerms.netDays(30),
        memo: scenario == 'Custom Terms' ? 'Retained original memo' : '1. This fictional note wraps at forty percent of the page width and keeps its hanging continuation aligned.\n2. The second paragraph has the same baseline interval.\n\nFinal fictional memo text.',
        lines: [
          for (
            var n = 1;
            n <=
                (scenario == 'Many Items'
                    ? 48
                    : scenario == 'Long Description'
                    ? 1
                    : 3);
            n++
          )
            SalesLineItem.category(
              id: EntityId.random(),
              categoryId: f.income,
              description: scenario == 'Long Description'
                  ? [
                      for (var p = 1; p <= 18; p++)
                        '$p. ${List.filled(8, 'Fictional filming preparation includes lighting sound interviews and delivery.').join(' ')}',
                    ].join('\n')
                  : 'Item $n: Fictional filming, editing and delivery.\nAdditional paragraph for this item.',
              quantity: SalesQuantity.fromInt(1),
              rate: Money.fromMinor(10000, 'MYR'),
              catalogue: CatalogueLineSnapshot(
                itemId: EntityId.random(),
                itemName: n.isEven ? 'Event Photography' : 'Corporate Video',
                categoryId: f.income,
                categoryName: 'Filming',
                itemRevision: 1,
              ),
            ),
        ],
      );
      final snapshot = scenario == 'Custom Terms'
          ? SalesDocumentSnapshot.quotation(
              businessId: f.workspace.identity.businessId,
              quotation: Estimate.draft(
                id: invoice.id,
                customerId: customer.id,
                issueDate: invoice.issueDate,
                validUntil: invoice.dueDate,
                terms: invoice.terms,
                lines: invoice.lines,
                memo: invoice.memo,
                documentNumber: 'QT-FICTIONAL',
              ),
              customer: customer,
              preferences: preferences,
            )
          : SalesDocumentSnapshot.invoice(
              businessId: f.workspace.identity.businessId,
              invoice: invoice,
              customer: customer,
              preferences: preferences,
            );
      expect(snapshot.content['companyDetails'], [
        '24 Jalan Demo, Unit 12',
        '46000 Petaling Jaya, Selangor, Malaysia',
      ]);
      expect(snapshot.content['customerDetails'], [
        '12 Jalan Contoh, Unit 8',
        '40000 Shah Alam, Selangor, Malaysia',
      ]);
      final pdf = await const SalesDocumentRenderer().render(
        snapshot,
        filename: '$scenario.pdf',
      );
      expect(pdf.originalBytes.take(5).toList(), ascii.encode('%PDF-'));
      final capture = Platform.environment['AUDYT_PAYMENT_LAYOUT_CAPTURE'];
      if (capture != null) {
        File('$capture/Updated $scenario.pdf')
            .writeAsBytesSync(pdf.originalBytes);
      }
    }
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'live Custom terms switches the Memo box and retains both buffers at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final font in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
        installFixedPopoutHost(tester);
        await installGeneratedDocumentHost(tester);
        final f = await salesReportFixture();
        addTearDown(f.workspace.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: InvoicePage(workspace: f.workspace)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Invoice').last);
        await pumpGeneratedDocumentWork(tester);
        final memo = find.byKey(const ValueKey('design-field-Memo'));
        await tester.ensureVisible(memo);
        await enterAccountingText(tester, memo, 'Original memo');
        await tester.pumpAndSettle();
        final terms = find.byKey(const ValueKey('design-field-Payment Terms'));
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Custom').last);
        await tester.tap(find.text('Custom').last);
        await tester.pumpAndSettle();
        final customTerms = find.byKey(
          const ValueKey('design-field-Custom Payment Terms'),
        );
        await tester.ensureVisible(customTerms);
        expect(
          tester.widget<AccountingDescriptionField>(customTerms).role,
          AccountingDescriptionRole.paymentTerms,
        );
        expect(
          tester
              .state<AccountingDescriptionFieldState>(customTerms)
              .editor
              .plainDescription,
          'Original memo',
        );
        await enterAccountingText(
          tester,
          customTerms,
          'Custom delivery terms\nSecond instalment.',
        );
        await tester.pumpAndSettle();
        final capture = Platform.environment['AUDYT_PAYMENT_LAYOUT_CAPTURE'];
        if (capture != null) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$capture/Custom Payment Terms Field ${width.toInt()}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Net 30').last);
        await tester.tap(find.text('Net 30').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .state<AccountingDescriptionFieldState>(memo)
              .editor
              .plainDescription,
          'Original memo',
        );
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Custom').last);
        await tester.tap(find.text('Custom').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .state<AccountingDescriptionFieldState>(customTerms)
              .editor
              .plainDescription,
          'Custom delivery terms\nSecond instalment.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
