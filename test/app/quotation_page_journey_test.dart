import '../support/accounting_text_input.dart';

import 'package:audyt/app/accounting_description_field.dart';

import '../support/generated_document_host.dart';

import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/accounting/presentation/recurring_transactions_dialog.dart';
import 'package:audyt/features/accounting/domain/recurring_document_template.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/quotation_persistence_test.dart'
    show quotationWorkspace, quotationDraft;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored quotation controls create, revise, convert and post at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        await installGeneratedDocumentHost(tester);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = Directory.systemTemp.createTempSync('audyt-quotation-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final (source, customer, account) = await quotationWorkspace(
          '${root.path}/source.sqlite',
        );
        await source.createAccount(
          code: '1100',
          name: 'Fictional Receivables',
          type: AccountType.asset,
        );
        await source.createAccount(
          code: '2200',
          name: 'Fictional Tax Payable',
          type: AccountType.liability,
        );
        final configuredTax = source.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Fictional Sales Tax',
            percent: '6',
            effectiveFrom: DateTime.utc(2026, 1, 1),
            application: TaxApplication.sales,
            accountId: (await source.accounts())
                .singleWhere((a) => a.account.code == '2200')
                .account
                .id,
          ),
        );
        source.savePreferences(
          source.preferences.change('Default Accounts', {
            'Income Account': account.account.id.value,
          }),
        );
        source.savePreferences(
          source.preferences.change('Sales Preferences', {
            'Show Rate': true,
            'Enable Discounts': true,
          }),
        );
        final category = source.saveCatalogueCategory(
          CatalogueCategory(id: EntityId.random(), name: 'Video'),
        );
        source.saveCatalogueItem(
          CatalogueItem(
            id: EntityId.random(),
            categoryId: category.id,
            name: 'Fictional Service',
            type: CatalogueItemType.service,
            incomeAccountId: account.account.id,
            description: 'UI fictional service',
            taxRatePercent: '6',
          ),
        );
        final legacy = Estimate.fromSnapshot({
          ...quotationDraft(customer, account).snapshot(),
          'validUntil': DateTime.now()
              .add(const Duration(days: 30))
              .toIso8601String(),
        });
        source.saveQuotationDraft(
          legacy,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 1),
        );
        final original = tables(source);
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.now(),
        );
        source.dispose();
        final sourceHash = sha256
            .convert(File('${root.path}/source.sqlite').readAsBytesSync())
            .toString();
        var workspace = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        workspace.dispose();
        workspace = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        addTearDown(() => workspace.dispose());
        expect(tables(workspace), original);
        // Layout assertions use Audyt's fonts even without screenshot output.
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: workspace,
              initialPath: '/sales-customers',
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

        Future<void> text(String label, String value) async {
          final finder = find.byKey(ValueKey('design-field-$label'));
          await tester.ensureVisible(finder);
          await enterAccountingText(tester, finder, value);
          await tester.pumpAndSettle();
        }

        Future<void> tab(String label) async {
          final tabs = tester.widget<AccountingTabs>(
            find.byKey(const ValueKey('area-tabs-sales-customers')),
          );
          await tap(
            find.byKey(
              ValueKey(
                'preview-tab-sales-customers-${tabs.labels.indexOf(label)}',
              ),
            ),
          );
        }

        Future<void> line(String label, String value) async {
          final finder = find.byWidgetPredicate(
            (widget) =>
                (widget is TextFormField ||
                    widget is AccountingDescriptionField) &&
                widget.key is ValueKey &&
                (widget.key as ValueKey).value.toString().endsWith('-$label'),
          );
          await tester.ensureVisible(finder);
          await enterAccountingText(tester, finder, value);
          await tester.pumpAndSettle();
        }

        Future<void> choice(String label, String value) async {
          await tap(find.byKey(ValueKey('design-field-$label')));
          await tap(find.widgetWithText(MenuItemButton, value).last);
        }

        Future<void> close() async => tap(accountingCloseIcon().last);
        await tab('Quotations');
        expect(find.byType(QuotationPage), findsOneWidget);
        expect(find.byType(AccountingRecordPagination), findsNothing);
        await tap(find.byKey(const ValueKey('open-recurring-transactions')));
        expect(
          tester
              .widget<RecurringTransactionsDialog>(
                find.byType(RecurringTransactionsDialog),
              )
              .initialKind,
          RecurringDocumentKind.quotation,
        );
        await close();
        final eye = find.byKey(ValueKey('preview-quotation-${legacy.id}'));
        expect(tester.widget(eye), isA<IconButton>());
        expect(tester.getSize(eye), const Size(32, 32));
        expect(
          tester
              .widget<AccountingIcon>(
                find.descendant(of: eye, matching: find.byType(AccountingIcon)),
              )
              .icon,
          Icons.preview_outlined,
        );
        final view = find.byKey(ValueKey('view-quotation-${legacy.id}'));
        expect(
          tester
              .widget<AccountingIcon>(
                find.descendant(
                  of: view,
                  matching: find.byType(AccountingIcon),
                ),
              )
              .icon,
          Icons.visibility_outlined,
        );

        await captureUi(tester, 'Quotation Records ${width.toInt()}');
        final beforeClose = tables(workspace);
        await tap(find.byKey(ValueKey('quotation-more-${legacy.id}')));
        await tap(find.byKey(ValueKey('quotation-closed-${legacy.id}')));
        await tap(find.byKey(const ValueKey('cancel-quotation-state')));
        expect(tables(workspace), beforeClose);
        for (final (action, expected) in [
          ('closed', EstimateStatus.closed),
          ('reopened', EstimateStatus.sent),
          ('declined', EstimateStatus.declined),
          ('revised', EstimateStatus.draft),
        ]) {
          await tap(find.byKey(ValueKey('quotation-more-${legacy.id}')));
          await tap(find.byKey(ValueKey('quotation-$action-${legacy.id}')));
          await tap(find.byKey(const ValueKey('confirm-quotation-state')));
          expect(workspace.quotations().single.quotation.status, expected);
        }

        // Opening reserves a unique number; cancelling must not create a quotation/invoice/posting.
        await tap(find.byKey(const ValueKey('new-quotation')));
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsNothing,
        );
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(workspace.quotations().length, 1);
        expect(workspace.invoiceDrafts(), isEmpty);
        expect(await workspace.journals(), isEmpty);
        await tap(find.byKey(const ValueKey('new-quotation')));
        expect(
          find.byKey(const ValueKey('design-field-Location')),
          findsNothing,
        );
        await choice('Counterparty', customer.displayName);
        await text('Date', '01-09-2026');
        await choice('Validity', '60 Days');
        expect(
          find.byKey(const ValueKey('design-field-Expiry Date')),
          findsNothing,
        );
        await text('Reference', 'PO-UI-QUOTE');
        await text('Memo', 'UI quoted memo');
        expect(
          find.byKey(const ValueKey('design-field-Tax Mode')),
          findsNothing,
        );
        await tap(find.byKey(const ValueKey('design-document-tax')));
        await tap(
          find.widgetWithText(MenuItemButton, configuredTax.label).last,
        );
        await choice('Make Recurring', 'Monthly');
        await tester.ensureVisible(find.text('Customer').last);
        await tester.pumpAndSettle();
        await captureUi(tester, 'Quotation Fields ${width.toInt()}');
        final itemSelector = find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey is ValueKey &&
              (w.triggerKey as ValueKey).value.toString().endsWith(
                '-Product / Service',
              ),
        );
        await tap(itemSelector);
        await tap(find.text('Fictional Service').last);
        await line('Description', 'UI fictional service');
        await line('Quantity', '3');
        await line('Rate', '50');
        await line('Discount', '5');
        final accountSelector = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey is ValueKey &&
              (widget.triggerKey as ValueKey).value.toString().endsWith(
                '-Product / Service',
              ),
        );
        final rateField = find.byWidgetPredicate(
          (widget) =>
              (widget is TextFormField ||
                  widget is AccountingDescriptionField) &&
              widget.key is ValueKey &&
              (widget.key as ValueKey).value.toString().endsWith('-Rate'),
        );
        expect(
          tester.getSize(accountSelector).width,
          greaterThan(tester.getSize(rateField).width),
        );
        await captureUi(tester, 'Quotation Editor ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await captureUi(tester, 'Quotation Save Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        final created = workspace.quotations().singleWhere(
          (r) => r.quotation.id != legacy.id,
        );
        final id = created.quotation.id;
        expect(
          workspace.database
              .documentSchedules(workspace.identity.businessId)
              .single
              .sourceId,
          id.value,
        );
        expect(created.quotation.total.minorUnits, 15370);
        expect(created.quotation.validUntil, DateTime.utc(2026, 10, 31));
        expect(created.quotation.terms.days, 45);
        expect(created.quotation.reference, 'PO-UI-QUOTE');
        expect(created.quotation.classification, isEmpty);
        expect(created.quotation.lines.single.catalogue!.categoryName, 'Video');
        expect(await workspace.journals(), isEmpty);
        // Existing legacy Location remains editable; Cancel preserves its exact saved snapshot.
        var before = tables(workspace);
        await tap(find.byKey(ValueKey('edit-quotation-${legacy.id}')));
        expect(
          find.byKey(const ValueKey('design-field-Location')),
          findsOneWidget,
        );
        await text('Memo', 'Cancelled edit');
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-discard-changes')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(workspace), before);
        await tap(find.byKey(ValueKey('edit-quotation-$id')));
        await text('Memo', 'Saved UI revised memo');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(
          workspace
              .quotations()
              .singleWhere((r) => r.quotation.id == id)
              .revision,
          2,
        );
        await tap(find.byKey(ValueKey('preview-quotation-$id')));
        expect(find.text('Expiry Date'), findsNothing);
        expect(find.text('Valid Until'), findsOneWidget);
        expect(find.text('31-10-2026'), findsOneWidget);
        expect(find.text('Due'), findsNothing);
        await captureUi(tester, 'Quotation Preview ${width.toInt()}');
        await close();
        final savedQuote = workspace
            .quotations()
            .singleWhere((r) => r.quotation.id == id)
            .quotation
            .snapshot();
        workspace.savePreferences(
          workspace.preferences.change('Sales Preferences', {
            'Show Rate': false,
            'Enable Discounts': false,
          }),
        );
        workspace.savePreferences(
          workspace.preferences.change('Numbering & Document Appearance', {
            'Show Tax Breakdown': false,
          }),
        );
        await tester.pumpAndSettle();
        await tap(find.byKey(ValueKey('preview-quotation-$id')));
        expect(find.text('Quantity × Rate'), findsOneWidget);
        expect(find.text('Discount'), findsOneWidget);
        expect(find.text('Tax Rate'), findsOneWidget);
        expect(find.text('Tax'), findsOneWidget);
        expect(find.text('RM 153.70'), findsWidgets);
        await captureUi(tester, 'Quotation Hidden Details ${width.toInt()}');
        await close();
        expect(
          workspace
              .quotations()
              .singleWhere((r) => r.quotation.id == id)
              .quotation
              .snapshot(),
          savedQuote,
        );
        workspace.savePreferences(
          workspace.preferences.change('Sales Preferences', {
            'Show Rate': true,
            'Enable Discounts': true,
          }),
        );
        workspace.savePreferences(
          workspace.preferences.change('Numbering & Document Appearance', {
            'Show Tax Breakdown': true,
          }),
        );
        await tester.pumpAndSettle();
        before = tables(workspace);
        await tap(find.byKey(ValueKey('quotation-more-$id')));
        await tap(find.byKey(ValueKey('quotation-shared-$id')));
        await tap(find.byKey(const ValueKey('cancel-quotation-state')));
        expect(tables(workspace), before);
        for (final action in ['shared', 'accepted']) {
          await tap(find.byKey(ValueKey('quotation-more-$id')));
          await tap(find.byKey(ValueKey('quotation-$action-$id')));
          await tap(find.byKey(const ValueKey('confirm-quotation-state')));
        }
        expect(
          workspace
              .quotations()
              .singleWhere((r) => r.quotation.id == id)
              .quotation
              .status,
          EstimateStatus.accepted,
        );
        // The shared owner renders a single remaining action directly.
        await tap(find.byKey(ValueKey('convert-quotation-$id')));
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsNothing,
        );
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(workspace.invoiceDrafts(), isEmpty);
        expect(await workspace.journals(), isEmpty);
        // The shared owner renders a single remaining action directly.
        await tap(find.byKey(ValueKey('convert-quotation-$id')));
        await text('Date', '27-09-2026');
        await captureUi(tester, 'Quotation Conversion ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final invoice = workspace.invoiceDrafts().single.invoice;
        expect(invoice.sourceEstimateId, id);
        expect(invoice.dueDate, DateTime.utc(2026, 11, 11));
        expect(invoice.total.minorUnits, 15370);
        expect(
          invoice.lines.single.sourceLineId,
          created.quotation.lines.single.id,
        );
        expect(await workspace.journals(), isEmpty);
        await tab('Invoices');
        await tap(find.byKey(ValueKey('edit-invoice-${invoice.id}')));
        await text('Memo', 'Later invoice edit preserves quote source');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final editedInvoice = workspace.invoiceDrafts().single.invoice;
        expect(editedInvoice.sourceEstimateId, id);
        expect(editedInvoice.lines.single.id, invoice.lines.single.id);
        expect(
          editedInvoice.lines.single.sourceLineId,
          invoice.lines.single.sourceLineId,
        );
        await tap(find.byKey(ValueKey('post-invoice-${invoice.id}')));
        await choice('Receivable Account', '1100 · Fictional Receivables');
        await choice('Tax Account', '2200 · Fictional Tax Payable');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(workspace.invoiceDrafts(), isEmpty);
        expect(
          workspace.postedInvoices().single.sourceDraft.sourceEstimateId,
          id,
        );
        final report = await workspace.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.revenue, BigInt.from(14500));
        expect(report.periodProfit, BigInt.from(14500));
        expect(report.assets, BigInt.from(15370));
        await tab('Quotations');
        await tap(find.byKey(ValueKey('view-quotation-$id')));
        expect(find.text(invoice.documentNumber), findsOneWidget);
        final details = find.byKey(ValueKey('quotation-details-$id'));
        final savedCustomer = find.descendant(
          of: details,
          matching: find.text(customer.displayName),
        );
        expectSingleLineText(tester, savedCustomer);
        await captureUi(tester, 'Quotation Details ${width.toInt()}');
        await tap(find.byKey(ValueKey('quotation-invoice-preview-$id')));
        expect(find.text('11-11-2026'), findsOneWidget);
        await captureUi(
          tester,
          'Quotation Linked Posted Invoice ${width.toInt()}',
        );
        await close();
        await close();
        for (var i = 0; i < 12; i++) {
          workspace.saveQuotationDraft(
            quotationDraft(customer, account, number: 'QT-FILTER-$i'),
            expectedRevision: 0,
            savedAt: DateTime.now().toUtc().add(Duration(seconds: i)),
          );
        }
        await tester.pumpAndSettle();
        await tap(find.byKey(const ValueKey('quotation-page-size')));
        final menuOption = find.widgetWithText(MenuItemButton, '5').last;
        expect(
          tester.getRect(menuOption).top,
          greaterThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('quotation-page-size')))
                .bottom,
          ),
        );
        expect(tester.getRect(menuOption).bottom, lessThanOrEqualTo(992));
        await captureUi(tester, 'Quotation Paging Menu ${width.toInt()}');

        await tap(find.widgetWithText(MenuItemButton, '5').last);
        expect(find.text('1–5 of 14'), findsOneWidget);
        expect(find.byType(AccountingRecordPagination), findsOneWidget);
        await tap(find.byKey(const ValueKey('quotation-page-next')));
        expect(find.text('6–10 of 14'), findsOneWidget);
        await tap(find.byKey(const ValueKey('quotation-page-next')));
        expect(find.text('11–14 of 14'), findsOneWidget);
        await tap(find.byKey(const ValueKey('quotation-page-previous')));
        expect(find.text('6–10 of 14'), findsOneWidget);
        final beforeFilters = tables(workspace);
        final search = find.byKey(const ValueKey('quotation-search'));
        await tester.ensureVisible(search);
        await enterAccountingText(tester, search, 'PO-UI-QUOTE');
        await tester.pumpAndSettle();
        expect(find.text('1–1 of 1'), findsOneWidget);
        expect(find.byKey(ValueKey('quotation-row-$id')), findsOneWidget);
        await tap(find.byKey(const ValueKey('quotation-status-filter')));
        await tap(find.widgetWithText(MenuItemButton, 'Converted').last);
        expect(find.text('1–1 of 1'), findsOneWidget);
        await tap(find.byKey(const ValueKey('quotation-currency-filter')));
        await tap(find.widgetWithText(MenuItemButton, 'MYR').last);
        await tap(find.byKey(const ValueKey('clear-quotation-filter')));
        expect(find.text('1–5 of 14'), findsOneWidget);
        expect(tables(workspace), beforeFilters);
        before = tables(workspace);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        expect(tables(workspace), before);
        final finalArchive = workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.now(),
        );
        final restoredAgain = await AccountingWorkspace.emptyRestore(
          '${root.path}/second.sqlite',
          finalArchive,
        );
        expect(tables(restoredAgain), before);
        expect(
          restoredAgain
              .quotations()
              .singleWhere((r) => r.quotation.id == id)
              .quotation
              .convertedInvoiceId,
          invoice.id,
        );
        restoredAgain.dispose();
        expect(
          sha256
              .convert(File('${root.path}/source.sqlite').readAsBytesSync())
              .toString(),
          sourceHash,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
