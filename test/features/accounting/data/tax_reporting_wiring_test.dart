import 'dart:io';

import 'package:audyt/app/demo_company.dart' show demoReceipt;
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/ledger_report.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import '../../../support/sales_report_fixture.dart';
import 'bill_draft_persistence_test.dart' show setupBill, billFixture;

void main() {
  for (final basis in ['Exclusive', 'Inclusive']) {
    test(
      '$basis configured tax reaches ledger, P&L and sales exactly once through credit, payment, restart and archive',
      () async {
        final root = Directory.systemTemp.createTempSync('tax-report-wiring-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        final fixture = await salesReportFixture(
          path: path,
          seedInvoices: false,
        );
        var w = fixture.workspace;
        addTearDown(() => w.dispose());
        await w.createAccount(
          code: '1000',
          name: 'Bank',
          type: AccountType.asset,
        );
        await w.createAccount(
          code: '2100',
          name: 'Supplier Payables',
          type: AccountType.liability,
        );
        final accounts = await w.accounts();
        final bank = accounts
            .singleWhere((a) => a.account.code == '1000')
            .account
            .id;
        final payable = accounts
            .singleWhere((a) => a.account.code == '2100')
            .account
            .id;
        final code = w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '8',
            effectiveFrom: DateTime.utc(2026),
            application: TaxApplication.both,
            accountId: fixture.tax,
          ),
        );
        final invoice = Invoice.draft(
          id: EntityId.random(),
          customerId: fixture.customer.id,
          documentNumber: 'TAX-WIRING-1',
          issueDate: DateTime.utc(2026, 9, 1),
          taxMode: basis,
          lines: [
            SalesLineItem.category(
              id: EntityId.random(),
              categoryId: fixture.income,
              description: 'Reviewed service',
              quantity: SalesQuantity.fromInt(1),
              rate: Money.fromMinor(
                basis == 'Inclusive' ? 10800 : 10000,
                'MYR',
              ),
              taxRatePercent: code.percent,
              taxSnapshot: code,
              taxInclusive: basis == 'Inclusive',
            ),
          ],
        );
        w.saveInvoiceDraft(
          invoice,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 2),
        );
        Future<LedgerReport> ledger() => w.report(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        BigInt balance(LedgerReport r, EntityId id) =>
            r.rows.singleWhere((row) => row.account.id == id).endingNetDebit;
        expect(
          (await ledger()).revenue,
          BigInt.zero,
          reason: 'Taxed drafts do not enter reports.',
        );
        final request = EntityId.random();
        EntityId post(EntityId tax) => w.postInvoice(
          requestId: request,
          invoiceId: invoice.id,
          expectedRevision: 1,
          expectedCustomerRevision: fixture.customer.metadata.revision,
          documentNumber: invoice.documentNumber,
          receivableAccountId: fixture.receivable,
          incomeAccountId: fixture.income,
          taxAccountId: tax,
          approvedAt: DateTime.utc(2026, 9, 3),
        );
        final untouched = tables(w);
        expect(
          () => post(payable),
          throwsStateError,
          reason: 'Selected code owns its reviewed sales-tax account.',
        );
        expect(tables(w), untouched);
        post(fixture.tax);
        final posted = tables(w);
        post(fixture.tax);
        expect(tables(w), posted, reason: 'Retry cannot double-charge tax.');
        final sales = await w.reportWithSales(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(sales.sales.netMinor, BigInt.from(10000));
        expect(sales.ledger.revenue, BigInt.from(10000));
        expect(sales.ledger.periodProfit, BigInt.from(10000));
        expect(balance(sales.ledger, fixture.tax), BigInt.from(-800));
        expect(balance(sales.ledger, fixture.receivable), BigInt.from(10800));
        expect(sales.ledger.isBalanced, isTrue);
        expect(
          (await w.report(
            from: DateTime.utc(2026, 10),
            through: DateTime.utc(2026, 10, 31),
          )).revenue,
          BigInt.zero,
        );

        // Purchase SST/service tax currently forms part of cost: no recovery or
        // second credit to the sales-tax liability is inferred from its name.
        final (vendor, expense) = await setupBill(w);
        final original = billFixture(
          w,
          vendor,
          expense.account.id,
          attachments: const [],
        );
        final values = billFormValues(original)..['Tax Mode'] = basis;
        final line = (values['_lines'] as List).single as Map;
        line['Quantity'] = '1';
        line['Rate'] = basis == 'Inclusive' ? '108' : '100';
        line['Amount'] = line['Rate'];
        line['Discount'] = '0';
        line['Tax Rate (%)'] = code.choice;
        final bill = billFromForm(
          values,
          metadata: original.metadata,
          vendor: vendor,
          purchaseAccountIds: {expense.account.id.value},
          taxCodes: w.taxRates,
        );
        expect(bill.lines.single.tax.minorUnits, 800);
        expect(bill.total.minorUnits, 10800);
        w.saveBillDraft(bill, expectedRevision: 0);
        expect((await ledger()).expenses, BigInt.zero);
        w.postBill(
          requestId: EntityId.random(),
          billId: bill.id,
          expectedRevision: 1,
          payableAccountId: payable,
          approvedAt: DateTime.utc(2026, 9, 28, 1),
        );
        var report = await ledger();
        expect(report.expenses, BigInt.from(10800));
        expect(report.periodProfit, BigInt.from(-800));
        expect(balance(report, payable), BigInt.from(-10800));
        expect(balance(report, fixture.tax), BigInt.from(-800));
        expect(report.isBalanced, isTrue);

        // Current settings cannot rewrite a posted document, credit or report.
        final activity = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(activity.rows, hasLength(2));
        expect(activity.salesTax, BigInt.from(800));
        expect(activity.purchaseTaxInCost, BigInt.from(800));
        expect(activity.unresolved, isEmpty);
        expect(activity.accounts.single.sourceSalesTax, BigInt.from(800));
        expect(activity.accounts.single.otherMovementCredit, BigInt.zero);

        w.saveTaxRate(
          CompanyTaxRate.fromJson({
            ...code.toJson(),
            'percent': '6',
            'active': false,
          }),
        );
        w.receiveInvoicePayment(
          requestId: EntityId.random(),
          customerId: fixture.customer.id,
          bankAccountId: bank,
          allocations: {invoice.id: Money.fromMinor(4000, 'MYR')},
          reference: 'Reviewed receipt',
          receivedAt: DateTime.utc(2026, 9, 4),
        );
        report = await ledger();
        expect(report.revenue, BigInt.from(10000));
        expect(balance(report, fixture.tax), BigInt.from(-800));
        final creditId = EntityId.random();
        w.saveInvoiceCreditDraft(
          draftId: creditId,
          invoiceId: invoice.id,
          lineCredits: {invoice.lines.single.id: Money.fromMinor(5400, 'MYR')},
          reason: 'Returned half of original service',
          creditDate: DateTime.utc(2026, 9, 6),
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 6),
          attachments: [
            demoReceipt('TAX-CREDIT', DateTime.utc(2026, 9, 6), 5400),
          ],
        );
        final review = w.reviewCreditDraft(creditId);
        w.postInvoiceCredit(
          requestId: EntityId.random(),
          draftId: creditId,
          expectedRevision: review.draft.revision,
          expectedPaidMinor: review.paidMinor,
          expectedPriorCreditMinor: review.priorCreditMinor,
          approvedAt: DateTime.utc(2026, 9, 7),
        );
        Future<void> verify() async {
          final combined = await w.reportWithSales(
            from: DateTime.utc(2026, 9),
            through: DateTime.utc(2026, 9, 30),
          );
          final r = combined.ledger;
          expect(combined.sales.netMinor, BigInt.from(5000));
          expect(r.revenue, BigInt.from(5000));
          expect(r.expenses, BigInt.from(10800));
          expect(r.periodProfit, BigInt.from(-5800));
          expect(balance(r, fixture.tax), BigInt.from(-400));
          expect(balance(r, fixture.receivable), BigInt.from(1400));
          expect(balance(r, bank), BigInt.from(4000));
          expect(r.liabilities, BigInt.from(11200));
          expect(r.isBalanced, isTrue);
          final tax = await w.taxActivity(
            from: DateTime.utc(2026, 9),
            through: DateTime.utc(2026, 9, 30),
          );
          expect(
            tax.rows,
            hasLength(3),
            reason: 'Settlement does not charge tax again.',
          );
          expect(tax.salesTax, BigInt.from(400));
          expect(tax.purchaseTaxInCost, BigInt.from(800));
          expect(tax.accounts.single.closingCredit, BigInt.from(400));
          expect(tax.rows.every((r) => r.code?.percent == '8'), isTrue);
          final later = await w.taxActivity(
            from: DateTime.utc(2026, 10),
            through: DateTime.utc(2026, 10, 31),
          );
          expect(later.rows, isEmpty);
          expect(later.accounts.single.openingCredit, BigInt.from(400));
          expect(later.accounts.single.closingCredit, BigInt.from(400));
          expect(
            w
                .postedInvoices()
                .firstWhere((d) => d.sourceDraft.id == invoice.id)
                .sourceDraft
                .lines
                .single
                .taxSnapshot!
                .percent,
            '8',
          );
        }

        await verify();
        final archive = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.now().toUtc(),
        );
        w.dispose();
        w = await AccountingWorkspace.open(path);
        await verify();
        w.dispose();
        w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        await verify();
      },
    );
  }
}
