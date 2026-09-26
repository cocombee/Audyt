import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import '../support/generated_document_host.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final quotation in [false, true]) {
      for (final forcedPricing in [false, true]) {
        testWidgets(
          '${quotation ? 'Quotation' : 'Invoice'} header grouping remains stable on Add/Remove ${forcedPricing ? 'forced pricing' : 'default'} $width',
          (tester) async {
            installFixedPopoutHost(tester);
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await loadJournalLayoutFonts();
            final w = await createDemoWorkspace();
            addTearDown(w.dispose);
            await w.createAccount(
              code: '2299',
              name: 'Fictional Sales Tax Payable',
              type: AccountType.liability,
            );
            final taxAccount = (await w.accounts())
                .singleWhere((record) => record.account.code == '2299')
                .account
                .id;
            w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'Fictional Domestic Sales Tax',
                percent: '8',
                effectiveFrom: DateTime.utc(2026, 1, 1),
                application: TaxApplication.sales,
                accountId: taxAccount,
              ),
            );
            w.savePreferences(
              w.preferences.change('Sales Preferences', {
                'Show Quantity': forcedPricing,
                'Show Rate': forcedPricing,
              }),
            );
            final preferencesBefore = w.preferences.toJson();
            final preferenceRevisionBefore = w.preferences.revision;
            final invoiceCount = w.invoiceDrafts().length;
            final quotationCount = w.quotations().length;
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AccountingTheme.light(),
                  home: Scaffold(
                    body: quotation
                        ? QuotationPage(workspace: w)
                        : InvoicePage(workspace: w),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(quotation ? 'Create Quotation' : 'Create Invoice'),
            );
            await tester.pumpAndSettle();
            final tax = find.byKey(const ValueKey('design-document-tax'));
            final terms = find.byKey(
              ValueKey(
                quotation
                    ? 'design-field-Validity'
                    : 'design-field-Payment Terms',
              ),
            );
            final add = find.byKey(const ValueKey('design-add-line'));
            Future<void> showHeader() async {
              Scrollable.of(tester.element(tax)).position.jumpTo(0);
              await tester.pumpAndSettle();
            }

            await showHeader();
            Rect headerRect(Finder field) => tester
                .getRect(field)
                .shift(
                  Offset(
                    0,
                    -tester
                        .getTopLeft(
                          find.text(quotation ? 'Quotation' : 'Invoice'),
                        )
                        .dy,
                  ),
                );
            final taxBefore = headerRect(tax);
            final termsBefore = headerRect(terms);
            void expectDistinctPricingHeadings() {
              if (!forcedPricing) return;
              final rate = tester.renderObject<RenderParagraph>(
                find.text('Rate (RM)', findRichText: true),
              );
              final amount = tester.renderObject<RenderParagraph>(
                find.text('Amount (RM)', findRichText: true),
              );
              final rateRight = rate
                  .localToGlobal(Offset(rate.size.width, 0))
                  .dx;
              final amountLeft = amount.localToGlobal(Offset.zero).dx;
              expect(amountLeft - rateRight, greaterThanOrEqualTo(10));
            }

            expectDistinctPricingHeadings();
            final windowBefore = tester.view.physicalSize;
            await tester.ensureVisible(add);
            await tester.tap(add);
            await tester.pumpAndSettle();
            final remove = find.byKey(const ValueKey('design-remove-line-1'));
            expect(remove, findsOneWidget);
            await showHeader();
            expect(headerRect(tax), taxBefore);
            expect(headerRect(terms), termsBefore);
            expectDistinctPricingHeadings();
            expect(tester.view.physicalSize, windowBefore);
            await captureUi(
              tester,
              '${quotation ? 'Quotation' : 'Invoice'} Stable Header ${forcedPricing ? 'Forced Pricing' : 'Default'} ${width.toInt()}',
            );
            await tester.ensureVisible(remove);
            await tester.tap(remove);
            await tester.pumpAndSettle();
            expect(remove, findsNothing);
            await showHeader();
            expect(headerRect(tax), taxBefore);
            expect(headerRect(terms), termsBefore);
            await tester.tap(find.byKey(const ValueKey('design-close')));
            await tester.pumpAndSettle();
            final discard = find.byKey(
              const ValueKey('design-discard-changes'),
            );
            if (discard.evaluate().isNotEmpty) {
              await tester.tap(discard);
              await tester.pumpAndSettle();
            }
            expect(find.byKey(const ValueKey('design-close')), findsNothing);
            expect(w.preferences.toJson(), preferencesBefore);
            expect(w.preferences.revision, preferenceRevisionBefore);
            expect(w.invoiceDrafts().length, invoiceCount);
            expect(w.quotations().length, quotationCount);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final width in [720.0, 1224.0]) {
    for (final quotation in [false, true]) {
      for (final catalogue in [false, true]) {
        final title =
            '${quotation ? 'Quotation' : 'Invoice'} ${catalogue ? 'Catalogue' : 'Legacy'}';
        testWidgets(
          '$title mixed saved tax permits Add/Remove but validates new tax at save $width',
          (tester) async {
            WidgetController.hitTestWarningShouldBeFatal = true;
            addTearDown(
              () => WidgetController.hitTestWarningShouldBeFatal = false,
            );
            installFixedPopoutHost(tester);
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await installGeneratedDocumentHost(tester);
            await loadJournalLayoutFonts();
            final root = Directory.systemTemp.createTempSync(
              'audyt-mixed-tax-actions-',
            );
            addTearDown(() => root.deleteSync(recursive: true));
            var w = await createDemoWorkspace(
              databasePath: '${root.path}/books.sqlite',
            );
            addTearDown(() => w.dispose());
            if (catalogue) {
              w.savePreferences(
                w.preferences.change('Sales Preferences', {
                  'Show Quantity': true,
                  'Show Rate': true,
                }),
              );
            }
            final income = (await w.accounts())
                .singleWhere((r) => r.account.code == '4000')
                .account
                .id;
            final customer = w.customers().firstWhere((c) => c.isActive);
            final category = w.saveCatalogueCategory(
              CatalogueCategory(
                id: EntityId.random(),
                name: 'Fictional Services',
              ),
            );
            final item = w.saveCatalogueItem(
              CatalogueItem(
                id: EntityId.random(),
                categoryId: category.id,
                name: 'Fictional Additional Service',
                type: CatalogueItemType.service,
                incomeAccountId: income,
                description: 'Additional prepared service',
              ),
            );
            final id = EntityId.random();
            final invoice = invoiceFromForm(
              {
                'Counterparty': customer.id.value,
                'Date': '14-09-2026',
                'Document Number': 'FICTIONAL-MIXED-TAX',
                'Currency': 'MYR',
                'Payment Terms': 'Use Customer Default',
                'Tax Mode': 'Exclusive',
                '_lines': [
                  for (final rate in ['8', '0'])
                    {
                      '_lineId': EntityId.random().value,
                      'Description': 'Saved service $rate',
                      'Quantity': '1',
                      'Rate': '100',
                      'Discount': '0',
                      'Tax Rate (%)': rate,
                      'Account': income.value,
                      if (catalogue) 'Product / Service': item.id.value,
                    },
                ],
              },
              id: id,
              customer: customer,
              incomeAccountIds: {income.value},
              catalogueItems: [item],
              catalogueCategories: [category],
            );
            if (quotation) {
              w.saveQuotationDraft(
                Estimate.draft(
                  id: id,
                  customerId: customer.id,
                  lines: invoice.lines,
                  issueDate: invoice.issueDate,
                  validUntil: invoice.dueDate,
                  taxMode: invoice.taxMode,
                  documentNumber: invoice.documentNumber,
                ),
                expectedRevision: 0,
                savedAt: DateTime.utc(2026, 9, 15),
              );
            } else {
              w.saveInvoiceDraft(
                invoice,
                expectedRevision: 0,
                savedAt: DateTime.utc(2026, 9, 15),
              );
            }
            String original() => quotation
                ? w
                      .quotations()
                      .singleWhere((r) => r.quotation.id == id)
                      .quotation
                      .snapshot()
                      .toString()
                : w
                      .invoiceDrafts()
                      .singleWhere((r) => r.invoice.id == id)
                      .invoice
                      .draftSnapshot()
                      .toString();
            final before = original();
            Widget page() => RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: quotation
                      ? QuotationPage(workspace: w)
                      : InvoicePage(workspace: w),
                ),
              ),
            );
            await tester.pumpWidget(page());
            await tester.pumpAndSettle();
            Future<void> tap(Finder finder) async {
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              await tester.tap(finder);
              await pumpGeneratedDocumentWork(tester);
            }

            await tap(
              find.byKey(
                ValueKey(
                  '${quotation ? 'edit-quotation' : 'edit-invoice'}-${id.value}',
                ),
              ),
            );
            final add = find.byKey(const ValueKey('design-add-line'));
            expect(
              tester.widget<IconButton>(add).onPressed,
              isNotNull,
              reason: 'Unresolved saved tax is not approved reconciliation.',
            );
            await tap(add);
            expect(
              find.byKey(const ValueKey('design-remove-line-2')),
              findsOneWidget,
            );
            Finder items() => find.byWidgetPredicate(
              (v) =>
                  v is AccountingSelector<String> &&
                  v.triggerKey is ValueKey &&
                  '${(v.triggerKey as ValueKey).value}'.endsWith(
                    '-Product / Service',
                  ),
            );
            Future<void> prepareLine() async {
              if (catalogue) {
                await tap(items().last);
                await tap(find.widgetWithText(MenuItemButton, item.name).last);
              } else {
                final account = find
                    .byWidgetPredicate(
                      (v) =>
                          v is AccountingSelector<String> &&
                          v.triggerKey is ValueKey &&
                          '${(v.triggerKey as ValueKey).value}'.endsWith(
                            '-Account',
                          ),
                    )
                    .last;
                final label = tester
                    .widget<AccountingSelector<String>>(account)
                    .options
                    .singleWhere((o) => o.value == income.value)
                    .label;
                await tap(account);
                await tap(find.widgetWithText(MenuItemButton, label).last);
                final description = find
                    .byWidgetPredicate(
                      (v) =>
                          v.key is ValueKey &&
                          '${(v.key as ValueKey).value}'.endsWith(
                            '-Description',
                          ),
                    )
                    .last;
                await tester.ensureVisible(description);
                await enterAccountingText(
                  tester,
                  description,
                  'Additional prepared service',
                );
                await tester.pumpAndSettle();
              }
            }

            await prepareLine();
            final amount = find
                .byWidgetPredicate(
                  (v) =>
                      v is TextFormField &&
                      v.key is ValueKey &&
                      '${(v.key as ValueKey).value}'.endsWith('-Amount'),
                )
                .last;
            await tester.ensureVisible(amount);
            await enterAccountingText(tester, amount, '10');
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              '$title Mixed Tax Prepared Line ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('design-review')));
            expect(
              find.textContaining('Choose one document tax'),
              findsOneWidget,
            );
            expect(find.textContaining('FormatException:'), findsNothing);
            expect(original(), before);
            await captureUi(
              tester,
              '$title Mixed Tax Save Warning ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('design-remove-line-2')));
            expect(
              find.byKey(const ValueKey('design-remove-line-2')),
              findsNothing,
            );
            expect(original(), before);
            await tap(add);
            await prepareLine();
            final newAmount = find
                .byWidgetPredicate(
                  (v) =>
                      v is TextFormField &&
                      v.key is ValueKey &&
                      '${(v.key as ValueKey).value}'.endsWith('-Amount'),
                )
                .last;
            await tester.ensureVisible(newAmount);
            await enterAccountingText(tester, newAmount, '10');
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('design-document-tax')));
            await tap(find.widgetWithText(MenuItemButton, 'No Tax').last);
            await tap(find.byKey(const ValueKey('design-review')));
            expect(find.byKey(const ValueKey('design-back')), findsOneWidget);
            await tap(find.byKey(const ValueKey('design-review')));
            expect(find.byKey(const ValueKey('design-add-line')), findsNothing);
            final saved = quotation
                ? w
                      .quotations()
                      .singleWhere((r) => r.quotation.id == id)
                      .quotation
                      .lines
                : w
                      .invoiceDrafts()
                      .singleWhere((r) => r.invoice.id == id)
                      .invoice
                      .lines;
            expect(saved.length, 3);
            expect(saved.map((l) => l.taxRatePercent).toSet(), {'0'});
            expect(
              saved.map((l) => l.id).take(2),
              invoice.lines.map((l) => l.id),
            );
            expect(
              saved.take(2).map((l) => l.categoryId),
              invoice.lines.map((l) => l.categoryId),
            );
            expect(
              saved.take(2).map((l) => l.catalogue?.itemId),
              invoice.lines.map((l) => l.catalogue?.itemId),
            );
            expect(
              saved.take(2).map((l) => l.description),
              invoice.lines.map((l) => l.description),
            );
            expect(saved.last.catalogue?.itemId, catalogue ? item.id : null);
            expect(saved.last.categoryId, income);

            w.dispose();
            w = await AccountingWorkspace.open('${root.path}/books.sqlite');
            final restarted = quotation
                ? w
                      .quotations()
                      .singleWhere((r) => r.quotation.id == id)
                      .quotation
                      .lines
                : w
                      .invoiceDrafts()
                      .singleWhere((r) => r.invoice.id == id)
                      .invoice
                      .lines;
            expect(restarted.length, 3);
            expect(restarted.map((l) => l.taxRatePercent).toSet(), {'0'});
            expect(
              restarted.take(2).map((l) => l.categoryId),
              invoice.lines.map((l) => l.categoryId),
            );
            expect(
              restarted.take(2).map((l) => l.catalogue?.itemId),
              invoice.lines.map((l) => l.catalogue?.itemId),
            );
            expect(
              restarted.last.catalogue?.itemId,
              catalogue ? item.id : null,
            );
            expect(restarted.last.categoryId, income);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
