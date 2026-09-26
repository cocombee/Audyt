import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import '../support/fitting_field_row.dart';
import '../support/generated_document_host.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import 'restored_page_routes_test.dart' show tables;

void main() {
  legacyAmountBasisCases();
  for (final width in [720.0, 1224.0]) {
    for (final quotation in [false, true]) {
      for (final basis in ['Exclusive', 'Inclusive']) {
        final title = quotation ? 'Quotation' : 'Invoice';
        testWidgets(
          '$title one configured document tax, $basis, history and restart at $width',
          (tester) async {
            installFixedPopoutHost(tester);
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await installGeneratedDocumentHost(tester);
            final root = Directory.systemTemp.createTempSync('sales-doc-tax-');
            addTearDown(() => root.deleteSync(recursive: true));
            final path = '${root.path}/books.sqlite';
            var w = await createDemoWorkspace(databasePath: path);
            addTearDown(() => w.dispose());
            await w.createAccount(
              code: '2299',
              name: 'Fictional Tax Account',
              type: AccountType.liability,
            );
            final taxAccount = (await w.accounts())
                .singleWhere((a) => a.account.code == '2299')
                .account
                .id;
            final salesAccount = (await w.accounts())
                .singleWhere((a) => a.account.code == '4000')
                .account
                .id;
            final code = w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'Service Tax',
                percent: '8',
                effectiveFrom: DateTime.utc(2026, 1, 1),
                application: TaxApplication.sales,
                accountId: taxAccount,
              ),
            );
            final purchaseCode = w.saveTaxRate(
              CompanyTaxRate(
                id: EntityId.random(),
                name: 'SST',
                percent: '10',
                effectiveFrom: DateTime.utc(2026, 1, 1),
                application: TaxApplication.purchases,
                accountId: taxAccount,
              ),
            );
            w.savePreferences(
              w.preferences.change('Sales Preferences', {
                'Default Tax Mode': basis,
              }),
            );
            final category = w.saveCatalogueCategory(
              CatalogueCategory(id: EntityId.random(), name: 'Service'),
            );
            final item = w.saveCatalogueItem(
              CatalogueItem(
                id: EntityId.random(),
                categoryId: category.id,
                name: 'Registered Service',
                type: CatalogueItemType.service,
                incomeAccountId: salesAccount,
                description: 'Configured item description',
                taxRatePercent: '20',
              ),
            );
            final customer = w.customers().firstWhere((c) => c.isActive);
            final originalIds = quotation
                ? w.quotations().map((r) => r.quotation.id).toSet()
                : w.invoiceDrafts().map((r) => r.invoice.id).toSet();
            await (FontLoader('Inter')..addFont(
                  rootBundle.load('assets/fonts/Inter-Variable.woff2'),
                ))
                .load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
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

            Future<void> choose(Finder finder, String label) async {
              await tap(finder);
              await tap(find.widgetWithText(MenuItemButton, label).last);
            }

            Finder itemSelector() => find.byWidgetPredicate(
              (v) =>
                  v is AccountingSelector<String> &&
                  v.triggerKey is ValueKey &&
                  '${(v.triggerKey as ValueKey).value}'.endsWith(
                    '-Product / Service',
                  ),
            );
            Finder documentSelector() => find.byWidgetPredicate(
              (v) =>
                  v is AccountingSelector<String> &&
                  v.triggerKey == const ValueKey('design-document-tax'),
            );
            Finder amountInput() => find.byWidgetPredicate(
              (v) =>
                  v is TextFormField &&
                  v.key is ValueKey &&
                  '${(v.key as ValueKey).value}'.endsWith('-Amount'),
            );
            await tap(
              find.byKey(ValueKey(quotation ? 'new-quotation' : 'new-invoice')),
            );
            await choose(
              find.byKey(const ValueKey('design-field-Counterparty')),
              customer.displayName,
            );
            expect(
              find.byKey(const ValueKey('design-field-Tax Mode')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('design-document-tax')),
              findsOneWidget,
            );
            final selector = tester.widget<AccountingSelector<String>>(
              documentSelector(),
            );
            expect(selector.value, '0');
            expect(selector.options.map((o) => o.value), contains(code.choice));
            expect(
              selector.options.map((o) => o.value),
              isNot(contains(purchaseCode.choice)),
            );
            expect(selector.options.map((o) => o.value), isNot(contains('20')));
            await choose(
              find.byKey(const ValueKey('design-document-tax')),
              code.label,
            );
            await choose(itemSelector().first, item.name);
            await enterAccountingText(
              tester,
              amountInput().first,
              basis == 'Inclusive' ? '108' : '100',
            );
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('design-add-line')));
            await choose(itemSelector().last, item.name);
            await enterAccountingText(
              tester,
              amountInput().last,
              basis == 'Inclusive' ? '54' : '50',
            );
            await tester.pumpAndSettle();
            expect(
              find.byWidgetPredicate(
                (v) =>
                    v is AccountingSelector<String> &&
                    v.triggerKey is ValueKey &&
                    '${(v.triggerKey as ValueKey).value}'.endsWith(
                      '-Tax Rate (%)',
                    ),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('design-line-tax')),
                matching: find.text('12.00'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('design-line-total')),
                matching: find.text('162.00'),
              ),
              findsOneWidget,
            );
            expectFittingFieldRow(tester, [
              quotation
                  ? 'design-field-Validity'
                  : 'design-field-Payment Terms',
              'design-field-Currency',
              'design-field-Make Recurring',
              'design-document-tax',
            ]);
            final beforeReview = tables(w);
            await captureUi(
              tester,
              '$title Document Tax $basis ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('design-review')));
            expect(find.textContaining('Could not review'), findsNothing);
            expect(tables(w), beforeReview);
            await tap(find.byKey(const ValueKey('design-back')));
            expect(tables(w), beforeReview);
            await tap(find.byKey(const ValueKey('design-review')));
            await tap(find.byKey(const ValueKey('design-review')));
            Invoice saved() => quotation
                ? w
                      .quotations()
                      .singleWhere((r) => !originalIds.contains(r.quotation.id))
                      .quotation
                      .pricingSnapshot()
                : w
                      .invoiceDrafts()
                      .singleWhere((r) => !originalIds.contains(r.invoice.id))
                      .invoice;
            final document = saved();
            expect(document.total.minorUnits, 16200);
            expect(document.taxMode, basis);
            expect(document.lines, hasLength(2));
            expect(document.lines.map((l) => l.taxSnapshot?.choice).toSet(), {
              code.choice,
            });
            expect(
              document.lines.fold(0, (int a, l) => a + l.tax.minorUnits),
              1200,
            );
            expect(document.attachments.any((a) => a.isGenerated), isTrue);
            w.saveTaxRate(
              CompanyTaxRate(
                id: code.id,
                name: code.name,
                percent: '9',
                effectiveFrom: code.effectiveFrom,
                application: code.application,
                accountId: code.accountId,
                active: false,
                revision: code.revision,
              ),
            );
            w.savePreferences(
              w.preferences.change('Sales Preferences', {
                'Default Tax Mode': basis == 'Exclusive'
                    ? 'Inclusive'
                    : 'Exclusive',
              }),
            );
            await tester.pumpAndSettle();
            final edit = find.byKey(
              ValueKey(
                '${quotation ? 'edit-quotation' : 'edit-invoice'}-${document.id.value}',
              ),
            );
            await revealAccountingRecord(tester, edit);
            await tap(edit);
            final historical = tester.widget<AccountingSelector<String>>(
              documentSelector(),
            );
            expect(historical.value, code.choice);
            expect(
              historical.options
                  .singleWhere((o) => o.value == code.choice)
                  .label,
              code.label,
            );
            await enterAccountingText(
              tester,
              find.byKey(const ValueKey('design-field-Memo')),
              'Memo only, preserved tax',
            );
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('design-review')));
            await tap(find.byKey(const ValueKey('design-review')));
            expect(saved().taxMode, basis);
            expect(saved().lines.map((l) => l.taxSnapshot?.choice).toSet(), {
              code.choice,
            });
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            w.dispose();
            w = await AccountingWorkspace.open(path);
            expect(saved().total.minorUnits, 16200);
            expect(saved().taxMode, basis);
            expect(saved().memo, 'Memo only, preserved tax');
            expect(saved().lines.map((l) => l.taxSnapshot?.choice).toSet(), {
              code.choice,
            });
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

void legacyAmountBasisCases() {
  for (final width in [720.0, 1224.0]) {
    for (final quotation in [false, true]) {
      for (final forcedPricing in [false, true]) {
        final title = quotation ? 'Quotation' : 'Invoice';
        final layout = forcedPricing ? 'Forced Quantity Rate' : 'Default';
        testWidgets(
          '$title saved amount basis review preserves facts and preferences $layout $width',
          (tester) async {
            installFixedPopoutHost(tester);
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await loadJournalLayoutFonts();
            final root = Directory.systemTemp.createTempSync(
              'sales-basis-review-',
            );
            addTearDown(() => root.deleteSync(recursive: true));
            final path = '${root.path}/books.sqlite';
            var w = await createDemoWorkspace(databasePath: path);
            addTearDown(() => w.dispose());
            w.savePreferences(
              w.preferences.change('Sales Preferences', {
                'Show Quantity': forcedPricing,
                'Show Rate': forcedPricing,
                'Enable Discounts': false,
                'Default Tax Mode': forcedPricing ? 'Inclusive' : 'Exclusive',
              }),
            );
            final prefs = w.preferences.toJson();
            final prefsRevision = w.preferences.revision;
            final income = (await w.accounts())
                .singleWhere((r) => r.account.code == '4000')
                .account
                .id;
            final customer = w.customers().firstWhere((c) => c.isActive);
            final id = EntityId.random();
            final lines = [
              SalesLineItem.category(
                id: EntityId.random(),
                categoryId: income,
                description: 'Retained service with confirmed No Tax',
                quantity: SalesQuantity.fromInt(1),
                rate: Money.fromDecimal('100', 'MYR'),
                taxRatePercent: '0',
              ),
            ];
            const number = 'FICTIONAL-BASIS-REVIEW';
            if (quotation) {
              w.saveQuotationDraft(
                Estimate.draft(
                  id: id,
                  customerId: customer.id,
                  lines: lines,
                  issueDate: DateTime.utc(2026, 9, 15),
                  validUntil: DateTime.utc(2026, 10, 15),
                  taxMode: 'Exclusive',
                  documentNumber: number,
                ),
                expectedRevision: 0,
                savedAt: DateTime.utc(2026, 9, 15),
              );
              // Model a retained payload from before the current save guard.
              // The live creation validator must continue rejecting it.
              w.dispose();
              final legacy = sqlite3.open(path);
              final payload = jsonDecode(
                legacy.select(
                      'SELECT payload FROM quotation_drafts WHERE id=?',
                      [id.value],
                    ).single['payload']
                    as String,
              ) as Map<String, dynamic>;
              (payload['pricing'] as Map).remove('taxMode');
              legacy.execute(
                'UPDATE quotation_drafts SET payload=? WHERE id=?',
                [jsonEncode(payload), id.value],
              );
              legacy.dispose();
              w = await AccountingWorkspace.open(path);
            } else {
              w.saveInvoiceDraft(
                Invoice.draft(
                  id: id,
                  customerId: customer.id,
                  lines: lines,
                  issueDate: DateTime.utc(2026, 9, 15),
                  terms: customer.paymentTerms,
                  documentNumber: number,
                ),
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
            Future<void> tap(Finder finder) async {
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              await tester.tap(finder);
              await pumpGeneratedDocumentWork(tester);
            }

            final warning = find.byKey(
              const ValueKey('sales-document-tax-basis-warning'),
            );
            final tax = find.byKey(const ValueKey('design-document-tax'));
            final close = find.byKey(const ValueKey('design-close'));
            final total = find.byKey(const ValueKey('design-line-total'));
            await tap(
              find.byKey(ValueKey(quotation ? 'new-quotation' : 'new-invoice')),
            );
            expect(
              warning,
              findsNothing,
              reason: 'New documents already use the personal Sales default.',
            );
            await tap(close);
            expect(
              find.byKey(const ValueKey('design-discard-changes')),
              findsNothing,
            );
            final edit = find.byKey(
              ValueKey(
                quotation ? 'edit-quotation-$id' : 'edit-invoice-${id.value}',
              ),
            );
            await revealAccountingRecord(tester, edit);
            await tap(edit);
            expect(warning, findsOneWidget);
            expect(find.text('Amount Basis Required'), findsOneWidget);
            expect(
              original(),
              before,
              reason: 'Opening must not infer a basis into saved facts.',
            );
            await tester.ensureVisible(warning);
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Saved $title Amount Basis Review $layout ${width.toInt()}',
            );
            expect(
              find.descendant(of: total, matching: find.text('—')),
              findsOneWidget,
            );
            await tap(tax);
            await tap(find.widgetWithText(MenuItemButton, 'No Tax').last);
            expect(warning, findsNothing);
            expect(
              find.descendant(of: total, matching: find.text('100.00')),
              findsOneWidget,
            );
            await tap(find.byKey(const ValueKey('design-add-line')));
            await tap(find.byKey(const ValueKey('design-remove-line-1')));
            expect(
              find.descendant(of: total, matching: find.text('100.00')),
              findsOneWidget,
            );
            await tester.ensureVisible(total);
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Saved $title Amount Basis Confirmed $layout ${width.toInt()}',
            );
            await tap(close);
            await tap(find.byKey(const ValueKey('design-keep-editing')));
            expect(warning, findsNothing);
            expect(
              find.descendant(of: total, matching: find.text('100.00')),
              findsOneWidget,
            );
            await tap(close);
            await tap(find.byKey(const ValueKey('design-discard-changes')));
            expect(original(), before);
            await tap(edit);
            expect(
              warning,
              findsOneWidget,
              reason: 'Discard must restore the unresolved saved basis.',
            );
            await tap(close);
            expect(
              find.byKey(const ValueKey('design-discard-changes')),
              findsNothing,
            );
            expect(w.preferences.toJson(), prefs);
            expect(w.preferences.revision, prefsRevision);
            expect(original(), before);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
