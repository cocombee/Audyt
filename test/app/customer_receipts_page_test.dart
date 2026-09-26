import '../support/accounting_test_finders.dart';

import 'package:audyt/app/accounting_components.dart';

import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

void main() {
  testWidgets(
    'receive payment search frame uses level two and its text uses level three',
    (tester) async {
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      // Search is intentionally hidden below six unfiltered records.
      // Exercise its existing page layout with a sufficient real fixture.
      final source = workspace.postedInvoices().first.sourceDraft;
      final accounts = {
        for (final row in await workspace.accounts())
          row.account.code: row.account.id,
      };
      for (var i = 0; i < 4; i++) {
        final invoice = Invoice.draft(
          id: EntityId.random(),
          customerId: source.customerId,
          documentNumber: 'SEARCH-$i',
          total: Money.fromMinor(10000, 'MYR'),
          issueDate: source.issueDate,
          terms: source.terms,
        );
        workspace.saveInvoiceDraft(
          invoice,
          expectedRevision: 0,
          savedAt: source.issueDate.toUtc(),
        );
        workspace.postInvoice(
          requestId: EntityId.random(),
          invoiceId: invoice.id,
          expectedRevision: 1,
          expectedCustomerRevision: 1,
          documentNumber: invoice.documentNumber,
          receivableAccountId: accounts['1100']!,
          incomeAccountId: accounts['4000']!,
          approvedAt: DateTime.now().toUtc(),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: CustomerReceiptsPage(workspace: workspace)),
        ),
      );
      await tester.pumpAndSettle();
      final titleX = tester.getTopLeft(find.text('Receive Payment').first).dx;
      final searchField = find.byKey(const ValueKey('receipt-search'));
      final searchText = find.descendant(
        of: searchField,
        matching: find.text('Search payments'),
      );
      expect(
        titleX - tester.getTopLeft(searchField).dx,
        closeTo(accountingContentInset, 0.1),
      );
      expect(tester.getTopLeft(searchText).dx, closeTo(titleX, 0.1));
      for (final finder in [find.text('Received Payments')]) {
        expect(tester.getTopLeft(finder).dx, closeTo(titleX, 1));
      }
      expect(tester.getSize(searchField).width, 240);
      expect(tester.getSize(searchField).height, accountingControlHeight);
      final editable = find.descendant(
        of: searchField,
        matching: find.byType(EditableText),
      );
      expect(
        InputDecorator.containerOf(tester.element(editable))!.size.height,
        // The decoration container excludes the outline's 1px edge.
        closeTo(accountingControlHeight, 1.1),
      );
    },
  );

  testWidgets(
    'batch receipt selection preserves per-invoice allocation amounts',
    (tester) async {
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
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
      final accounts = await w.accounts();
      final ar = accounts
          .firstWhere((a) => a.account.code == '1100')
          .account
          .id;
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
      Invoice draft() => Invoice.draft(
        id: EntityId.random(),
        customerId: c.id,
        total: Money.fromMinor(10000, 'MYR'),
        issueDate: DateTime.utc(2026, 1, 1),
        terms: c.paymentTerms,
        reference: 'PO-001',
        memo: 'Retain the reviewed delivery note.',
        attachments: ClaimStore.demo().all.first.attachments,
      );
      final invoice = draft();
      final legacy = Map<String, dynamic>.from(invoice.draftSnapshot())
        ..remove('reference')
        ..remove('memo')
        ..remove('attachments');
      expect(Invoice.fromDraftSnapshot(legacy).draftSnapshot(), legacy);
      expect(
        () => Invoice.draft(
          id: EntityId.random(),
          customerId: c.id,
          total: invoice.total,
          issueDate: invoice.issueDate,
          attachments: [invoice.attachments.first, invoice.attachments.first],
        ),
        throwsArgumentError,
      );
      w.saveInvoiceDraft(
        invoice,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      final request = EntityId.random();
      EntityId post(
        Invoice i, {
        EntityId? requestId,
        String number = 'INV-001',
        int revision = 1,
        EntityId? income,
      }) => w.postInvoice(
        requestId: requestId ?? request,
        invoiceId: i.id,
        expectedRevision: revision,
        expectedCustomerRevision: 1,
        documentNumber: number,
        receivableAccountId: ar,
        incomeAccountId: income ?? sales,
        approvedAt: DateTime.utc(2026, 1, 3),
      );

      post(invoice);
      final second = draft();
      w.saveInvoiceDraft(
        second,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      post(second, requestId: EntityId.random(), number: 'INV-002');
      final anotherCustomer = Customer.create(
        metadata: RecordMetadata.initial(
          recordId: EntityId.random(),
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        displayName: 'Other Customer',
        contact: const CustomerContact(),
        taxProfile: const CustomerTaxProfile(),
        currency: Currency.parse('MYR'),
        paymentTerms: PaymentTerms.netDays(30),
      );
      w.saveCustomer(anotherCustomer);
      final otherInvoice = Invoice.draft(
        id: EntityId.random(),
        customerId: anotherCustomer.id,
        total: Money.fromMinor(10000, 'MYR'),
        issueDate: DateTime.utc(2026, 1, 1),
      );
      w.saveInvoiceDraft(
        otherInvoice,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      post(otherInvoice, requestId: EntityId.random(), number: 'INV-OTHER');
      await w.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bankLedger = (await w.accounts())
          .singleWhere((a) => a.account.code == '1000')
          .account
          .id;
      w.savePaymentAccount(
        PaymentAccount.create(
          id: 'receipt-ui-bank',
          name: 'Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      w.database.linkPaymentLedgerAccount(
        w.identity.businessId,
        'receipt-ui-bank',
        bankLedger,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: CustomerReceiptsPage(workspace: w)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Receive Payment Wide');
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureUi(tester, 'Receive Payment Narrow');
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('select-receipt-${invoice.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(ValueKey('select-receipt-${otherInvoice.id.value}')),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(
        find.byKey(ValueKey('select-receipt-${second.id.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receive-selected-invoices')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          RegExp(r'Amount Received.*Invoice 1.*\(RM\)', caseSensitive: false),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('design-field-Amount Received for Invoice 1'),
                ),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .prefixIcon,
        isNull,
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('design-field-Amount Received for Invoice 1'),
        ),
        '30',
      );
      await tester.enterText(
        find.byKey(
          const ValueKey('design-field-Amount Received for Invoice 2'),
        ),
        '70',
      );
      await tester.enterText(
        find.byKey(const ValueKey('design-field-Reference')),
        'BATCH-UI',
      );
      await tester.tap(find.byKey(const ValueKey('design-field-Bank Account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank · Bank · RM').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      final posted = w.postedInvoices();
      expect(
        posted.singleWhere((r) => r.documentNumber == 'INV-001').paidMinor,
        3000,
      );
      expect(
        posted.singleWhere((r) => r.documentNumber == 'INV-002').paidMinor,
        7000,
      );
      expect(await w.journals(), hasLength(4));
      final receipt = w.database
          .customerReceiptHistory(w.identity.businessId)
          .single;
      final view = find.byKey(ValueKey('view-payment-${receipt.requestId}'));
      await tester.ensureVisible(view);
      await tester.pumpAndSettle();
      await tester.tap(view);
      await tester.pumpAndSettle();
      final rows = tester
          .widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          )
          .rows;
      expect(rows, contains(('INV-001', 'RM 30.00')));
      expect(rows, contains(('INV-002', 'RM 70.00')));
      expect(
        find.descendant(
          of: find.byType(AccountingInformationRows),
          matching: find.text('RM 30.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AccountingInformationRows),
          matching: find.text('RM 70.00'),
        ),
        findsOneWidget,
      );
      await captureUi(tester, 'Payment History Review');
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-payment-history')), findsNothing);

      // Keep the search interaction above the established six-record threshold.
      for (var i = 0; i < 4; i++) {
        final extra = draft();
        w.saveInvoiceDraft(
          extra,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 1, 2),
        );
        post(extra, requestId: EntityId.random(), number: 'SEARCH-$i');
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: CustomerReceiptsPage(workspace: w)),
        ),
      );
      await tester.pumpAndSettle();
      final searchField = find.byKey(const ValueKey('receipt-search'));
      await tester.ensureVisible(searchField);
      await tester.enterText(searchField, 'BATCH-UI');
      await tester.pumpAndSettle();
      expect(view, findsOneWidget);
      await tester.enterText(searchField, 'not-a-payment');
      await tester.pumpAndSettle();
      expect(view, findsNothing);
      expect(find.text('No matching received payments.'), findsOneWidget);
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();
      expect(view, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      w.dispose();
    },
  );
}
