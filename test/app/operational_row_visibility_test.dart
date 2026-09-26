import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/purchases/presentation/vendors_page.dart';
import 'package:audyt/features/purchases/presentation/pay_bills_page.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/invoice_credit_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

import '../support/credit_posting_fixture.dart';

void main() {
  setUp(AccountingRecordPageSizes.reset);
  tearDown(AccountingRecordPageSizes.reset);
  final pages = <String, Widget Function(AccountingWorkspace)>{
    'Invoices': (w) => InvoicePage(workspace: w),
    'Credit Notes': (w) => InvoiceCreditPage(workspace: w),
    'Quotations': (w) => QuotationPage(workspace: w),
    'Customers': (w) => CustomerPage(workspace: w),
    'Receipts': (w) => CustomerReceiptsPage(workspace: w),
    'Products': (w) => ProductCataloguePage(workspace: w),
    'Bills': (w) => BillsPage(workspace: w),
    'Vendors': (w) => VendorsPage(workspace: w),
    'Pay Bills': (w) => PayBillsPage(workspace: w),
    'Expenses': (w) => ExpenseIntakePage(workspace: w, onRecordExpense: () {}),
    'Journals': (w) => JournalReviewPage(workspace: w),
    'Accounts': (w) => ChartOfAccountsPage(workspace: w),
  };
  for (final page in pages.entries) {
    testWidgets(
      '${page.key} empty default list hides row controls and retains actions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1224, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: page.value(w)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordPagination), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Rows'), findsNothing);
        expect(tester.takeException(), isNull);
        if (page.key == 'Journals') {
          expect(find.byKey(const ValueKey('prepare-closing')), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final count in [1, 2, 3, 4, 5]) {
    testWidgets(
      'credit list with $count drafts hides paging and retains edits',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1224, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = await creditPostingFixture();
        for (var i = 1; i < count; i++) {
          f.w.saveInvoiceCreditDraft(
            draftId: EntityId.random(),
            invoiceId: f.invoice.id,
            lineCredits: {
              f.invoice.lines.single.id: Money.fromMinor(100, 'MYR'),
            },
            reason: 'Fictional row $i',
            creditDate: DateTime(2026, 9, 6),
            expectedRevision: 0,
            savedAt: DateTime.utc(2026, 9, 6, i),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: InvoiceCreditPage(workspace: f.w)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Rows'), findsNothing);
        expect(find.text('Previous'), findsNothing);
        expect(find.text('Next'), findsNothing);
        for (final draft in f.w.creditDrafts()) {
          expect(find.byKey(ValueKey(draft.id)), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('sixth credit enables paging; saved row choice survives return', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = await creditPostingFixture();
    final journalIds = (await f.w.journals()).map((r) => r.entry.id).toList();
    final invoiceBefore = f.w.postedInvoices().single;
    for (var i = 1; i < 5; i++) {
      f.w.saveInvoiceCreditDraft(
        draftId: EntityId.random(),
        invoiceId: f.invoice.id,
        lineCredits: {f.invoice.lines.single.id: Money.fromMinor(100, 'MYR')},
        reason: 'Fictional row $i',
        creditDate: DateTime(2026, 9, 6),
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 9, 6, i),
      );
    }
    Widget host() => MaterialApp(
      theme: AccountingTheme.light(),
      home: Scaffold(body: InvoiceCreditPage(workspace: f.w)),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Rows'), findsNothing);
    final sixth = EntityId.random();
    f.w.saveInvoiceCreditDraft(
      draftId: sixth,
      invoiceId: f.invoice.id,
      lineCredits: {f.invoice.lines.single.id: Money.fromMinor(100, 'MYR')},
      reason: 'Fictional sixth row',
      creditDate: DateTime(2026, 9, 6),
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 6, 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('1–5 of 6'), findsOneWidget);
    final hidden = f.w.creditDrafts().last.id;
    expect(find.byKey(ValueKey(hidden)), findsNothing);
    final next = find.byKey(const ValueKey('invoice-credit-1-page-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('6–6 of 6'), findsOneWidget);
    expect(find.byKey(ValueKey(hidden)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invoice-credit-1-page-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '10').last);
    await tester.pumpAndSettle();
    expect(find.text('1–6 of 6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('1–6 of 6'), findsOneWidget);
    expect(
      tester
          .widget<AccountingRecordPagination>(
            find.byType(AccountingRecordPagination),
          )
          .pageSize,
      10,
    );
    expect((await f.w.journals()).map((r) => r.entry.id), journalIds);
    final invoiceAfter = f.w.postedInvoices().single;
    expect(invoiceAfter.paidMinor, invoiceBefore.paidMinor);
    expect(invoiceAfter.creditedMinor, invoiceBefore.creditedMinor);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'account table shows no controls at five; sixth reveals both; filtered one retains controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      for (var i = 0; i < 5; i++) {
        await w.createAccount(
          code: '${1000 + i}',
          name: 'Test Account $i',
          type: AccountType.asset,
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: ChartOfAccountsPage(workspace: w)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-search')), findsNothing);
      expect(find.text('Rows'), findsNothing);
      for (var i = 0; i < 5; i++) {
        expect(find.text('Test Account $i'), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('new-journal')), findsOneWidget);
      await w.createAccount(
        code: '1005',
        name: 'Test Account 5',
        type: AccountType.asset,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-search')), findsOneWidget);
      expect(find.text('1–5 of 6'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('account-search')),
        'Test Account 5',
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Account 5'), findsNWidgets(2));
      expect(find.text('1–1 of 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
