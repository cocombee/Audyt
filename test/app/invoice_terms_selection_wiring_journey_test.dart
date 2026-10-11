import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_payment_term.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/quotation_persistence_test.dart'
    show quotationWorkspace;
import '../support/accounting_text_input.dart' show enterAccountingText;
import '../support/generated_document_host.dart'
    show installGeneratedDocumentHost, pumpGeneratedDocumentWork;
import 'claim_receipts_proposal_test.dart' show capture, prepare;

void main() {
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'Invoice selects exact named rules and reopens generic at $width',
      (tester) async {
        await prepare(tester, width);
        await installGeneratedDocumentHost(tester);
        final root = Directory.systemTemp.createTempSync(
          'invoice-term-choice-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        final (initialWorkspace, customer, income) = await quotationWorkspace(
          path,
        );
        var workspace = initialWorkspace;
        addTearDown(() => workspace.dispose());
        final category = workspace.saveCatalogueCategory(
          CatalogueCategory(id: EntityId.random(), name: 'Services'),
        );
        final item = workspace.saveCatalogueItem(
          CatalogueItem(
            id: EntityId.random(),
            categoryId: category.id,
            name: 'Fictional service',
            type: CatalogueItemType.service,
            incomeAccountId: income.account.id,
            taxRatePercent: '0',
          ),
        );
        final fixed = workspace.createPaymentTerm(
          CompanyPaymentTerm(
            id: EntityId.random(),
            name: 'Net 30', // Collision with a built-in, but this rule is 12 days.
            rule: PaymentTerms.daysAfterIssue(12),
          ),
        );
        final monthly = workspace.createPaymentTerm(
          CompanyPaymentTerm(
            id: EntityId.random(),
            name: 'Monthly 20',
            rule: PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5),
          ),
        );

        Finder key(String name) => find.byKey(ValueKey(name)).last;
        Future<void> host() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(body: InvoicePage(workspace: workspace)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await pumpGeneratedDocumentWork(tester);
        }

        Future<void> fill(String name, String value) async {
          final field = key('design-field-$name');
          await tester.ensureVisible(field);
          await enterAccountingText(tester, field, value);
          await tester.pumpAndSettle();
        }

        Future<void> choose(String name, String label) async {
          await tap(key('design-field-$name'));
          await tap(find.widgetWithText(MenuItemButton, label).last);
        }

        Future<void> fillLine(String suffix, String value) async {
          final field = find.byWidgetPredicate(
            (widget) =>
                (widget is TextFormField ||
                    widget is AccountingDescriptionField) &&
                widget.key is ValueKey &&
                (widget.key as ValueKey).value.toString().endsWith('-$suffix'),
          );
          await tester.ensureVisible(field);
          await enterAccountingText(tester, field, value);
          await tester.pumpAndSettle();
        }

        AccountingSelector<String> selectorFor(String label) =>
            tester.widget<AccountingSelector<String>>(
              find
                  .ancestor(
                    of: key('design-field-$label'),
                    matching: find.byType(AccountingSelector<String>),
                  )
                  .last,
            );

        await host();
        await tap(key('new-invoice'));
        expect(selectorFor('Payment Terms').value, 'Use Customer Default');
        await choose('Counterparty', customer.displayName);
        await fill('Date', '01-09-2026');
        await fill('Reference', 'Named Invoice reference');
        final itemSelector = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey is ValueKey &&
              (widget.triggerKey as ValueKey).value.toString().endsWith(
                '-Product / Service',
              ),
        );
        await tap(itemSelector);
        await tap(find.widgetWithText(MenuItemButton, item.name).last);
        await fillLine('Description', 'Fictional named invoice service');
        await fillLine('Amount', '100');
        await tap(key('design-document-tax'));
        await tap(find.widgetWithText(MenuItemButton, 'No Tax').last);

        await tap(key('design-field-Payment Terms'));
        expect(find.text('Net 30'), findsOneWidget);
        expect(find.text('Net 30 · Saved Term'), findsOneWidget);
        expect(find.text('Add Term'), findsNothing);
        await tester.ensureVisible(find.text('Net 30 · Saved Term'));
        await capture(tester, 'Invoice Named Menu ${width.toInt()}');
        await tap(
          find.widgetWithText(MenuItemButton, 'Net 30 · Saved Term').last,
        );
        expect(selectorFor('Payment Terms').value, isNot('Net 30'));
        await capture(tester, 'Invoice Named Fixed Selected ${width.toInt()}');
        await tap(key('design-review'));
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        expect(find.textContaining('Could not review:'), findsNothing);
        await capture(tester, 'Invoice Named Fixed Review ${width.toInt()}');
        await tap(key('design-review'));

        var record = workspace.invoiceDrafts().single;
        var invoice = record.invoice;
        expect(invoice.terms.toJson(), fixed.rule.toJson());
        expect(invoice.dueDate, DateTime.utc(2026, 9, 13));
        expect(invoice.customerId, customer.id);
        expect(invoice.reference, 'Named Invoice reference');
        expect(invoice.lines.single.catalogue!.itemId, item.id);
        expect(
          invoice.lines.single.description,
          'Fictional named invoice service',
        );
        expect(await workspace.journals(), isEmpty);

        await tap(key('edit-invoice-${invoice.id.value}'));
        expect(selectorFor('Payment Terms').value, 'Days After Issue');
        expect(
          tester
              .widget<TextFormField>(key('design-field-Number Of Days'))
              .controller!
              .text,
          '12',
        );
        await capture(tester, 'Invoice Named Generic Reopen ${width.toInt()}');
        await fill('Date', '18-09-2026');
        await choose('Payment Terms', 'Monthly 20');
        await capture(
          tester,
          'Invoice Named Monthly Selected ${width.toInt()}',
        );
        await tap(key('design-review'));
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        expect(find.textContaining('Could not review:'), findsNothing);
        await capture(tester, 'Invoice Named Monthly Review ${width.toInt()}');
        await tap(key('design-review'));
        record = workspace.invoiceDrafts().single;
        invoice = record.invoice;
        expect(record.revision, 2);
        expect(invoice.terms.toJson(), monthly.rule.toJson());
        expect(invoice.dueDate, DateTime.utc(2026, 10, 20));
        expect(invoice.reference, 'Named Invoice reference');
        expect(invoice.lines.single.catalogue!.itemId, item.id);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        record = workspace.invoiceDrafts().single;
        invoice = record.invoice;
        expect(invoice.terms.toJson(), monthly.rule.toJson());
        expect(invoice.dueDate, DateTime.utc(2026, 10, 20));
        await host();
        await tap(key('edit-invoice-${invoice.id.value}'));
        expect(selectorFor('Payment Terms').value, 'Day Of Month');
        expect(selectorFor('Monthly Due Day').value, '20');
        expect(
          tester
              .widget<TextFormField>(key('design-field-Rollover Within Days'))
              .controller!
              .text,
          '5',
        );
        await capture(tester, 'Invoice Named Generic Restart ${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
