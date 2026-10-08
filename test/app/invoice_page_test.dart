import '../support/accounting_text_input.dart';
import '../support/generated_document_host.dart';

import '../support/accounting_test_finders.dart';

import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_image_zoom.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1162.0]) {
    testWidgets('invoice archive warning cancel and recovery at $width', (
      t,
    ) async {
      await prepare(t, width);
      t.view.physicalSize = Size(width, 809);
      final w = await createDemoWorkspace(includeRowReview: true);
      addTearDown(w.dispose);
      final draft = w.invoiceDrafts().first.invoice;
      final original = draft.draftSnapshot();
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(body: InvoicePage(workspace: w)),
          ),
        ),
      );
      await t.pumpAndSettle();
      final action = find.byKey(ValueKey('archive-invoice-${draft.id.value}'));
      final confirm = find.byKey(const ValueKey('confirm-invoice-archive'));
      final close = find.byKey(const ValueKey('cancel-invoice-archive'));
      await tap(t, action);
      expect(find.text('Archive Invoice Draft'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      await capture(t, 'Invoice Archive Warning ${width.toInt()}');
      await tap(t, close);
      expect(tables(w), before);
      await tap(t, action);
      await tap(t, confirm);
      expect(
        w.invoiceDrafts(archived: true).single.invoice.draftSnapshot(),
        original,
      );
      await tap(t, find.byKey(const ValueKey('invoice-status-filter')));
      await tap(t, find.text('Archived').last);
      await tap(t, action);
      expect(find.text('Restore Invoice Draft'), findsOneWidget);
      await capture(t, 'Invoice Restore Warning ${width.toInt()}');
      final archived = tables(w);
      await tap(t, close);
      expect(tables(w), archived);
      await tap(t, action);
      await tap(t, confirm);
      expect(w.invoiceDrafts(archived: true), isEmpty);
      expect(
        w
            .invoiceDrafts()
            .singleWhere((r) => r.invoice.id == draft.id)
            .invoice
            .draftSnapshot(),
        original,
      );
      final after = tables(w);
      for (final entry in before.entries) {
        if (entry.key == 'invoice_drafts' || entry.key == 'ledger_audit') {
          continue;
        }
        expect(after[entry.key], entry.value, reason: entry.key);
      }
      final priorAudit = before['ledger_audit']['rows'] as List;
      final currentAudit = after['ledger_audit']['rows'] as List;
      expect(currentAudit.take(priorAudit.length).toList(), priorAudit);
      expect(currentAudit.length, priorAudit.length + 2);
      expect(
        currentAudit[currentAudit.length - 2][4],
        'invoice_draft_archived',
      );
      expect(currentAudit.last[4], 'invoice_draft_restored');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('invoice form edits and posts through the operational page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await installGeneratedDocumentHost(tester);
    final dir = Directory.systemTemp.createTempSync('invoice-posting-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    await w.createAccount(
      code: '1100',
      name: 'Receivables',
      type: AccountType.asset,
    );
    await w.createAccount(
      code: '4000',
      name: 'Sales',
      type: AccountType.income,
    );
    await w.createAccount(
      code: '2200',
      name: 'Tax Payable',
      type: AccountType.liability,
    );
    final accounts = await w.accounts();
    final ar = accounts.firstWhere((a) => a.account.code == '1100').account.id;
    final sales = accounts
        .firstWhere((a) => a.account.code == '4000')
        .account
        .id;
    final c = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: EntityId.random(),
        businessId: w.identity.businessId,
        originDeviceId: w.identity.deviceId,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      displayName: 'Test Customer',
      contact: const CustomerContact(),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
    );
    w.saveCustomer(c);
    final invoice = invoiceFromForm(
      {
        'Counterparty': c.id.value,
        'Date': '01-01-2026',
        'Document Number': 'INV-UI-1',
        'Currency': 'MYR',
        'Payment Terms': 'Use Customer Default',
        'Tax Mode': 'Inclusive',
        'Reference': 'PO-1',
        'Class': 'Projects',
        'Location': 'Branch',
        'Memo': 'Keep this',
        '_lines': [
          {
            '_lineId': EntityId.random().value,
            'Description': 'Services',
            'Quantity': '1',
            'Rate': '108',
            'Discount': '0',
            'Tax Rate (%)': '8',
            'Account': sales.value,
          },
        ],
        '_files': [],
        '_attachments': [],
      },
      id: EntityId.random(),
      customer: c,
      incomeAccountIds: {sales.value},
    );
    w.saveInvoiceDraft(
      invoice,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 1, 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: InvoicePage(workspace: w)),
      ),
    );
    await tester.tap(
      find.byKey(ValueKey('archive-invoice-${invoice.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-invoice-archive')));
    await tester.pumpAndSettle();
    expect(w.invoiceDrafts().single.revision, 1);
    await tester.tap(
      find.byKey(ValueKey('archive-invoice-${invoice.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-invoice-archive')));
    await tester.pumpAndSettle();
    expect(w.invoiceDrafts(), isEmpty);
    expect(find.byKey(const ValueKey('invoice-status-filter')), findsNothing);
    expect(
      find.byKey(ValueKey('edit-invoice-${invoice.id.value}')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(ValueKey('archive-invoice-${invoice.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-invoice-archive')));
    await tester.pumpAndSettle();
    expect(w.invoiceDrafts().single.revision, 3);
    expect(
      w.invoiceDrafts().single.invoice.draftSnapshot(),
      invoice.draftSnapshot(),
    );
    expect(find.byKey(const ValueKey('invoice-status-filter')), findsNothing);
    await tester.tap(find.byKey(ValueKey('edit-invoice-${invoice.id.value}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    expect(w.invoiceDrafts().single.revision, 4);
    expect(
      w.invoiceDrafts().single.invoice.draftSnapshot()..remove('attachments'),
      invoice.draftSnapshot()..remove('attachments'),
    );
    expect(
      w.invoiceDrafts().single.invoice.attachments.single.isGenerated,
      true,
    );
    await tester.tap(find.byKey(ValueKey('post-invoice-${invoice.id.value}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('design-field-Receivable Account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('design-field-Receivable Account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1100 · Receivables').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('design-field-Tax Account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-field-Tax Account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2200 · Tax Payable').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    expect(w.invoiceDrafts(), isEmpty);
    expect(w.postedInvoices().single.documentNumber, 'INV-UI-1');
    final lines = (await w.journals()).single.entry.lines;
    expect(
      lines.singleWhere((l) => l.accountId == sales).amount.minorUnits,
      10000,
    );
    expect(
      lines.singleWhere((l) => l.accountId == ar).amount.minorUnits,
      10800,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('invoice-status-filter')), findsNothing);
    await tester.tap(find.byKey(ValueKey('view-invoice-${invoice.id.value}')));
    await tester.pumpAndSettle();
    final document = tester.getRect(
      find.byKey(const ValueKey('invoice-document-page')),
    );
    expect(document.width, lessThanOrEqualTo(960));
    expect(document.height, lessThanOrEqualTo(952));
    expect(document.height, greaterThan(300));
    final content = tester.getRect(
      find.byKey(const ValueKey('accounting-fitted-popout-content')),
    );
    expect(
      (document.width - content.width).abs() <= .01 ||
          (document.height - content.height).abs() <= .01,
      isTrue,
      reason: 'The fitted document must fill its limiting width or height.',
    );
    final zoom = tester.widget<InteractiveViewer>(
      find.descendant(
        of: find.byType(AccountingImageZoom),
        matching: find.byType(InteractiveViewer),
      ),
    );
    final controller = zoom.transformationController!;
    final title = find.descendant(
      of: find.byKey(const ValueKey('invoice-document-dialog')),
      matching: find.text('INV-UI-1'),
    );
    final titleRect = tester.getRect(title);
    await tester.tapAt(document.center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(document.center);
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
    expect(tester.getRect(title), titleRect);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(document.center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(document.center);
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
    expect(find.textContaining('PO-1'), findsOneWidget);
    expect(find.textContaining('Projects'), findsOneWidget);
    expect(find.textContaining('Branch'), findsOneWidget);
    expect(find.textContaining('Keep this'), findsOneWidget);
    expect(find.text('Inclusive · 8%'), findsOneWidget);
    expect(find.textContaining('4000 · Sales'), findsOneWidget);
    await tester.tap(accountingCloseIcon().last);
    await tester.pumpAndSettle();
    await w.createAccount(
      code: '1000',
      name: 'Receipt Bank',
      type: AccountType.asset,
    );
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'receipt-bank-ui',
        name: 'Receipt Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'receipt-bank-ui',
      (await w.accounts())
          .singleWhere((a) => a.account.code == '1000')
          .account
          .id,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('receive-invoice-${invoice.id.value}')),
    );
    await tester.pumpAndSettle();
    await enterAccountingText(
      tester,
      find.byKey(const ValueKey('design-field-Amount')),
      '40',
    );
    await enterAccountingText(
      tester,
      find.byKey(const ValueKey('design-field-Reference')),
      'BANK-UI-1',
    );
    await tester.tap(find.byKey(const ValueKey('design-field-Bank Account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receipt Bank · Bank · RM').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    expect(w.postedInvoices().single.paidMinor, 4000);
    expect(find.textContaining('Partially Paid'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('view-invoice-${invoice.id.value}')));
    await tester.pumpAndSettle();
    expect(find.text('BANK-UI-1'), findsOneWidget);
    expect(find.text('RM 40.00'), findsOneWidget);
    await tester.tap(accountingCloseIcon().last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invoice-status-filter')), findsNothing);
    expect(
      find.byKey(ValueKey('receive-invoice-${invoice.id.value}')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: CustomerReceiptsPage(workspace: w)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('select-receipt-${invoice.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receive-selected-invoices')));
    await tester.pumpAndSettle();
    await enterAccountingText(
      tester,
      find.byKey(const ValueKey('design-field-Reference')),
      'BANK-UI-2',
    );
    await tester.tap(find.byKey(const ValueKey('design-field-Bank Account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receipt Bank · Bank · RM').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await pumpGeneratedDocumentWork(tester);
    expect(w.postedInvoices().single.paidMinor, 10800);
    expect(find.text('No outstanding invoices.'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: InvoicePage(workspace: w)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invoice-status-filter')), findsNothing);
    final legacy = Invoice.draft(
      id: EntityId.random(),
      customerId: c.id,
      total: Money.fromMinor(1000, 'MYR'),
      issueDate: DateTime.utc(2026, 1, 1),
    );
    w.saveInvoiceDraft(
      legacy,
      expectedRevision: 0,
      savedAt: DateTime.now().toUtc(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('edit-invoice-${legacy.id.value}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('This older invoice uses'), findsOneWidget);
    expect(
      w.invoiceDrafts().single.invoice.draftSnapshot(),
      legacy.draftSnapshot(),
    );
    await tester.tap(accountingCloseIcon().last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('post-invoice-${legacy.id.value}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Each invoice line needs'), findsOneWidget);
    expect(await w.journals(), hasLength(3));
    await tester.pumpWidget(const SizedBox());
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(w.postedInvoices().single.sourceDraft.memo, 'Keep this');
    expect(w.postedInvoices().single.paidMinor, 10800);
    w.dispose();
  });
}
