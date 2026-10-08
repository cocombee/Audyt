import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/reconciliation_adjustment_dialog.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import '../support/accounting_test_finders.dart';
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import 'account_reconciliation_journey_test.dart'
    show keyed, input, accountMenu;

Future<void> start(
  WidgetTester tester,
  Fixture f, {
  String closing = '90.00',
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: AudytApp(initialPath: '/banking', workspace: f.w),
    ),
  );
  await tester.pumpAndSettle();
  await accountMenu(tester, 'Reconcile Account');
  await input(tester, 'reconciliation-start', '01-09-2026');
  await input(tester, 'reconciliation-end', '30-09-2026');
  await input(tester, 'reconciliation-opening', '100.00');
  await input(tester, 'reconciliation-closing', closing);
  await tap(tester, keyed('review-reconciliation'));
  await input(tester, 'reconciliation-evidence', 'Fictional original opening');
}

Future<void> add(WidgetTester tester, String action) async {
  await tap(tester, keyed('reconciliation-other-transactions'));
  await tap(tester, keyed('reconciliation-add-$action'));
}

void retained(WidgetTester tester, {String closing = '90.00'}) {
  for (final (key, value) in [
    ('reconciliation-start', '01-09-2026'),
    ('reconciliation-end', '30-09-2026'),
    ('reconciliation-opening', '100.00'),
    ('reconciliation-closing', closing),
  ]) {
    expect(tester.widget<TextField>(keyed(key)).controller!.text, value);
  }
  expect(find.byType(StatementReconciliationDialog), findsOneWidget);
  expect(find.byType(BankingPage), findsOneWidget);
}

Future<Invoice> postedInvoice(Fixture f) async {
  final w = f.w;
  await w.createAccount(
    code: '1100',
    name: 'Fictional Receivables',
    type: AccountType.asset,
  );
  await w.createAccount(
    code: '4000',
    name: 'Fictional Income',
    type: AccountType.income,
  );
  final accounts = await w.accounts();
  final c = Customer.create(
    metadata: RecordMetadata.initial(
      recordId: EntityId.random(),
      businessId: f.business,
      originDeviceId: w.identity.deviceId,
      createdAt: DateTime.utc(2026, 9, 1),
    ),
    displayName: 'Fictional Customer',
    contact: const CustomerContact(),
    taxProfile: const CustomerTaxProfile(),
    currency: Currency.parse('MYR'),
    paymentTerms: PaymentTerms.netDays(30),
  );
  w.saveCustomer(c);
  final invoice = Invoice.draft(
    id: EntityId.random(),
    customerId: c.id,
    documentNumber: 'FIC-001',
    total: Money.fromMinor(1000, 'MYR'),
    issueDate: DateTime.utc(2026, 9, 1),
    terms: c.paymentTerms,
  );
  w.saveInvoiceDraft(
    invoice,
    expectedRevision: 0,
    savedAt: DateTime.utc(2026, 9, 1),
  );
  w.postInvoice(
    requestId: EntityId.random(),
    invoiceId: invoice.id,
    expectedRevision: 1,
    expectedCustomerRevision: 1,
    documentNumber: 'FIC-001',
    receivableAccountId: accounts
        .singleWhere((a) => a.account.code == '1100')
        .account
        .id,
    incomeAccountId: accounts
        .singleWhere((a) => a.account.code == '4000')
        .account
        .id,
    approvedAt: DateTime.now().toUtc(),
  );
  return invoice;
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final (currency, zero, entered) in [
      ('MYR', '0.00', '123456789012345678901234567890.56'),
      ('JPY', '0', '123456789012345678901234567890'),
      ('KWD', '0.000', '123456789012345678901234567890.567'),
    ]) {
      testWidgets(
        'adjustment supplied $currency zero hint and independent amount sizing at $width',
        (tester) async {
          await prepare(tester, width);
          installFixedPopoutHost(tester);
          final f = Fixture();
          await f.open();
          final accounts = await f.w.accounts();
          final before = f.w.database.exportDataArchive(
            f.business,
            DateTime.utc(2026, 10, 1),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showReconciliationAdjustment(
                        context,
                        accounts: accounts,
                        bankLedgerId: f.bank,
                        bankLabel: 'Fictional Bank',
                        currency: currency,
                        initialDate: DateTime.utc(2026, 9, 30),
                      ),
                      child: const Text('Open Adjustment'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tap(tester, find.text('Open Adjustment'));
          final amount = keyed('adjustment-amount');
          final empty = tester.widget<TextField>(amount);
          expect(empty.decoration!.hintText, zero);
          expect(empty.controller!.text, isEmpty);
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(zero))
                .didExceedMaxLines,
            isFalse,
          );
          final original = tester.getRect(amount);
          final account = tester.getRect(keyed('adjustment-account'));
          final reference = tester.getRect(keyed('adjustment-reference'));
          expect(
            original.top,
            account.top,
            reason: 'Account and Amount share the same ordinary row.',
          );
          final actualRowCount = 2 + (reference.top == original.top ? 1 : 0);
          expect(
            actualRowCount,
            2,
            reason:
                'Verify all actual peers, not just a pair of matching tops.',
          );
          await capture(
            tester,
            'Adjustment $currency Zero Hint ${width.toInt()}',
          );
          await input(tester, 'adjustment-amount', entered);
          expect(
            tester.getRect(amount),
            original,
            reason: 'This independent Amount retains its declared ordinary fit. Two-field rows must not grow; all currency variants use the normal two-field family.',
          );
          expect(
            tester
                .widget<TextField>(amount)
                .controller!
                .text
                .replaceAll(',', ''),
            entered,
          );
          expect(
            tester
                .widget<FilledButton>(keyed('save-reconciliation-adjustment'))
                .onPressed,
            isNull,
          );
          await capture(
            tester,
            'Adjustment $currency Entered Fixed Width ${width.toInt()}',
          );
          await tap(tester, keyed('adjustment-editor-close'));
          await tap(tester, keyed('adjustment-keep-editing'));
          expect(
            tester
                .widget<TextField>(amount)
                .controller!
                .text
                .replaceAll(',', ''),
            entered,
          );
          await input(tester, 'adjustment-amount', '');
          await tap(tester, keyed('adjustment-editor-close'));
          expect(
            keyed('adjustment-discard-changes'),
            findsNothing,
            reason: 'The zero hint does not populate a controller or leave a dirty draft.',
          );
          expect(find.text('Open Adjustment'), findsOneWidget);
          expect(
            f.w.database.exportDataArchive(
              f.business,
              DateTime.utc(2026, 10, 1),
            ),
            before,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual reconciliation opens reference adjustment design without saving at $width',
      (tester) async {
        await prepare(tester, width);
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        await f.w.createAccount(
          code: '4000',
          name: 'Sales',
          type: AccountType.income,
        );
        await start(tester, f);
        final before = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2026, 10, 1),
        );
        await tap(tester, keyed('reconciliation-add-transaction'));
        expect(find.text('Add Transaction'), findsOneWidget);
        expect(find.text('Apply To'), findsOneWidget);
        expect(find.text('Amount (RM)'), findsOneWidget);
        expect(find.text('*'), findsNWidgets(3));
        expect(find.text('Reference #'), findsOneWidget);
        expect(find.textContaining('cannot be saved yet'), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Reference'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.widget<TextField>(keyed('adjustment-date')).controller!.text,
          '30-09-2026',
        );
        await tap(tester, keyed('adjustment-today'));
        expect(
          tester.widget<TextField>(keyed('adjustment-date')).controller!.text,
          formatAccountingInputDate(DateTime.now()),
        );
        await input(tester, 'adjustment-date', '30-09-2026');
        expect(
          tester
              .widget<FilledButton>(keyed('save-reconciliation-adjustment'))
              .onPressed,
          isNull,
        );
        await capture(
          tester,
          'Reconciliation Adjustment Deposits ${width.toInt()}',
        );
        await tap(tester, keyed('adjustment-account'));
        expect(find.text('4000 · Sales'), findsWidgets);
        expect(find.text('5000 · Fictional Supplies'), findsNothing);
        expect(find.text('1000 · Fictional Bank'), findsNothing);
        await tap(tester, find.text('4000 · Sales').last);
        await input(tester, 'adjustment-amount', '12.34');
        await input(tester, 'adjustment-reference', 'FIC-BANK-REFERENCE');
        await tap(tester, keyed('adjustment-direction'));
        await tap(tester, find.text('Withdrawals').last);
        expect(find.text('4000 · Sales'), findsNothing);
        expect(
          tester.widget<TextField>(keyed('adjustment-amount')).controller!.text,
          '12.34',
        );
        await tap(tester, keyed('adjustment-account'));
        expect(find.text('5000 · Fictional Supplies'), findsWidgets);
        expect(find.text('1000 · Fictional Bank'), findsNothing);
        await capture(
          tester,
          'Reconciliation Adjustment Withdrawal Accounts ${width.toInt()}',
        );
        await tap(tester, find.text('5000 · Fictional Supplies').last);
        await capture(
          tester,
          'Reconciliation Adjustment Withdrawals ${width.toInt()}',
        );
        await tester.binding.setSurfaceSize(Size(width, 613));
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Reconciliation Adjustment Withdrawals Short ${width.toInt()}',
        );
        await tester.binding.setSurfaceSize(Size(width, 1000));
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        await tester.tap(keyed('adjustment-reference'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(keyed('adjustment-discard-changes'), findsOneWidget);
        await capture(
          tester,
          'Reconciliation Adjustment Discard Warning ${width.toInt()}',
        );
        await tester.binding.setSurfaceSize(Size(width, 613));
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Reconciliation Adjustment Discard Short ${width.toInt()}',
        );
        await tap(tester, keyed('adjustment-keep-editing'));
        expect(
          tester
              .widget<TextField>(keyed('adjustment-reference'))
              .controller!
              .text,
          'FIC-BANK-REFERENCE',
        );
        await tap(tester, keyed('adjustment-editor-close'));
        await tap(tester, keyed('adjustment-discard-changes'));
        retained(tester);
        final after = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2026, 10, 1),
        );
        expect(
          after,
          before,
          reason:
              'Design inspection never creates a journal or clears a movement.',
        );
        await tap(tester, keyed('reconciliation-add-transaction'));
        expect(
          tester
              .widget<TextField>(keyed('adjustment-reference'))
              .controller!
              .text,
          isEmpty,
        );
        await tap(tester, keyed('adjustment-editor-close'));
        expect(keyed('adjustment-discard-changes'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
      },
    );
    for (final income in [false, true]) {
      testWidgets(
        'actual reconciliation creates and approves ${income ? 'incoming' : 'outgoing'} journal at $width',
        (tester) async {
          await prepare(tester, width);
          installFixedPopoutHost(tester);
          final f = Fixture();
          await f.open();
          await f.post(8, 31, 10000);
          final closing = income ? '110.00' : '90.00';
          await start(tester, f, closing: closing);
          await tap(tester, keyed('reconciliation-other-transactions'));
          if (!income) {
            await capture(
              tester,
              'Reconciliation Add Transaction Menu ${width.toInt()}',
            );
          }
          await tap(tester, keyed('reconciliation-add-new-journal'));
          expect(find.text('New Journal'), findsOneWidget);
          expect(find.text('Cancel'), findsNothing);
          expect(
            tester.widget<TextField>(keyed('journal-date')).controller!.text,
            '30-09-2026',
          );
          expect(find.text('1000 · Fictional Bank'), findsOneWidget);
          if (!income) {
            await capture(
              tester,
              'Reconciliation Journal Context ${width.toInt()}',
            );
          }
          await input(
            tester,
            'journal-memo',
            income
                ? 'Fictional refunded purchase'
                : 'Fictional missing purchase',
          );
          await input(
            tester,
            income ? 'journal-debit-0' : 'journal-credit-0',
            '10.00',
          );
          await tap(tester, keyed('journal-account-1'));
          await tap(tester, find.text('5000 · Fictional Supplies').last);
          await input(
            tester,
            income ? 'journal-credit-1' : 'journal-debit-1',
            '9.00',
          );
          await tap(tester, keyed('save-journal-draft'));
          expect(
            await f.w.journals(),
            hasLength(1),
            reason: 'Unbalanced entry cannot be saved or cleared.',
          );
          await input(
            tester,
            income ? 'journal-credit-1' : 'journal-debit-1',
            '10.00',
          );
          await tap(tester, keyed('save-journal-draft'));
          expect(find.text('Review Journal'), findsOneWidget);
          final pending = (await f.w.journals()).singleWhere(
            (r) => r.entry.state == JournalEntryState.draft,
          );
          expect(
            f.review(closing: income ? 11000 : 9000).review.outstanding,
            isEmpty,
          );
          if (!income) {
            await capture(
              tester,
              'Reconciliation Journal Approval ${width.toInt()}',
            );
          }
          await tap(tester, keyed('approve-journal'));
          retained(tester, closing: closing);
          final movement = '${pending.entry.id.value}:0';
          expect(keyed('account-cleared-$movement'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(keyed('approve-reconciliation'))
                .onPressed,
            isNull,
            reason: 'Freshly posted entries must be explicitly selected, never auto-cleared.',
          );
          await tap(tester, keyed('account-cleared-$movement'));
          expect(
            tester
                .widget<FilledButton>(keyed('approve-reconciliation'))
                .onPressed,
            isNotNull,
          );
          if (!income) {
            await capture(
              tester,
              'Reconciliation Added Journal Ready ${width.toInt()}',
            );
          }
          await tap(tester, keyed('approve-reconciliation'));
          expect(keyed('reconciliation-other-transactions'), findsNothing);
          expect(f.w.database.bankStatements(f.business, 'bank'), isEmpty);
          expect(await f.w.journals(), hasLength(2));
          await tester.pumpWidget(const SizedBox());
          f.w.dispose();
          f.w = await AccountingWorkspace.open(f.path);
          final history = f.w.database.accountReconciliationHistory(
            f.business,
            'bank',
          );
          expect(history, hasLength(1));
          expect(
            f.w.database
                .reconciliationReportSnapshot(f.business, history.single.id)
                .evidence
                .selectedMovements
                .map((m) => m.id),
            contains(movement),
          );
        },
      );
    }
    testWidgets(
      'actual reconciliation expense preserves context and cancels without a posting at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        await start(tester, f);
        final before = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2026, 10, 1),
        );
        await add(tester, 'record-expense');
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(keyed('expense-field-date'))
              .controller!
              .text,
          '30-09-2026',
        );
        final page = tester.widget<RecordExpensePage>(
          find.byType(RecordExpensePage),
        );
        expect(page.initialStatementDraft!.paymentAccountId, 'bank');
        expect(page.initialStatementDraft!.currencyCode, 'MYR');
        expect(
          page.initialStatementDraft!.notes,
          isEmpty,
          reason: 'There is no fabricated statement.',
        );
        await capture(
          tester,
          'Reconciliation Expense Context ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        retained(tester);
        expect(
          f.w.database.exportDataArchive(f.business, DateTime.utc(2026, 10, 1)),
          before,
        );
        await add(tester, 'new-journal');
        await tap(tester, accountingCloseIcon().last);
        retained(tester);
        expect(await f.w.journals(), hasLength(1));
        await add(tester, 'record-expense');
        await input(tester, 'expense-field-payee', 'Fictional Supply Vendor');
        await tap(tester, keyed('expense-field-category'));
        await tap(tester, find.text('Office Operations').last);
        await input(tester, 'expense-field-amount', '10.00');
        await tap(tester, keyed('expense-field-tax'));
        await tap(tester, find.text('No Tax').last);
        await tap(tester, keyed('record-expense-save'));
        expect(find.byType(RecordExpensePage), findsNothing);
        retained(tester);
        final drafts = await f.w.expenses();
        expect(drafts, hasLength(1));
        final saved = await f.w.expense(drafts.single.id);
        expect(saved!.draft.paymentAccountId, 'bank');
        expect(saved.draft.date, '30-09-2026');
        expect(saved.draft.amount, '10.00');
        expect(
          f.review().review.outstanding,
          isEmpty,
          reason: 'Expense intake remains excluded until its ordinary approval posts it.',
        );
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        expect(
          (await f.w.expense(drafts.single.id))!.draft.toJson(),
          saved.draft.toJson(),
        );
      },
    );
    testWidgets(
      'actual reconciliation receives invoice payment into the selected account at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final invoice = await postedInvoice(f);
        await start(tester, f, closing: '110.00');
        await add(tester, 'receive-payment');
        expect(find.byType(CustomerReceiptsPage), findsOneWidget);
        final page = tester.widget<CustomerReceiptsPage>(
          find.byType(CustomerReceiptsPage),
        );
        expect(page.statementRow, isNull);
        expect(page.statementAccount!.id, 'bank');
        final checkbox = find.byType(Checkbox).last;
        await tap(tester, checkbox);
        await tap(tester, keyed('receive-selected-invoices'));
        final date = keyed('design-field-Date');
        expect(
          tester.widget<TextFormField>(date).controller!.text,
          '30-09-2026',
        );
        expect(find.text('Fictional Bank · Bank · RM'), findsWidgets);
        await input(tester, 'design-field-Reference', 'FIC-RCPT-001');
        await capture(
          tester,
          'Reconciliation Customer Payment Context ${width.toInt()}',
        );
        await tap(tester, keyed('design-review'));
        await tap(tester, keyed('design-review'));
        expect(
          f.w
              .postedInvoices()
              .singleWhere((r) => r.sourceDraft.id == invoice.id)
              .paidMinor,
          1000,
        );
        await capture(
          tester,
          'Reconciliation Customer Payment List ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        await tester.pumpAndSettle();
        retained(tester, closing: '110.00');
        final movements = f.review(closing: 11000).review.outstanding;
        expect(movements, hasLength(1));
        final movement = movements.single.id;
        await tap(tester, keyed('account-cleared-$movement'));
        await tap(tester, keyed('approve-reconciliation'));
        expect(f.w.database.bankStatements(f.business, 'bank'), isEmpty);
        expect(await f.w.journals(), hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
