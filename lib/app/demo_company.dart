import 'demo_row_review.dart';
import '../features/accounting/domain/workspace_reminder.dart';

import 'package:image/image.dart' as raster;

import '../core/documents/receipt_document.dart';
import '../features/purchases/domain/claim.dart';
import '../features/purchases/domain/claim_store.dart';
import '../features/purchases/domain/payment_voucher.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/ids/entity_id.dart';
import '../core/money/currency.dart';
import '../core/money/money.dart';
import '../core/storage/record_metadata.dart';
import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/application/journal_entry_repository.dart';
import '../features/accounting/domain/account.dart';
import '../features/accounting/domain/customer.dart';
import '../features/accounting/domain/journal_entry.dart';
import '../features/accounting/domain/expense_draft.dart';
import '../features/accounting/domain/payment_account.dart';
import '../features/accounting/domain/bank_statement_import.dart';
import '../features/sales/domain/invoice.dart';
import '../features/sales/domain/sales_line_item.dart';
import 'app.dart';
import 'routing.dart';
import 'sample_catalog.dart';
import 'frontend_catalog.dart';

class DemoCompany extends InheritedWidget {
  const DemoCompany({super.key, required super.child, this.asOf});
  final DateTime? asOf;
  static DateTime? referenceDate(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoCompany>()?.asOf;
  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoCompany>() != null;
  @override
  bool updateShouldNotify(DemoCompany oldWidget) => asOf != oldWidget.asOf;
}

/// Uses SQLite :memory: in the app. Tests may pass a temporary path to verify
/// reopen behavior; this never calls openDefault or native storage channels.
Future<AccountingWorkspace> createDemoWorkspace({
  String databasePath = ':memory:',
  DateTime? asOf,
  bool includeRowReview = false,
}) async {
  final w = await AccountingWorkspace.open(databasePath);
  try {
    for (final spec in [
      ('1000', 'Demo Bank', AccountType.asset),
      ('1010', 'Demo Savings', AccountType.asset),
      ('1100', 'Trade Receivables', AccountType.asset),
      ('3000', 'Owner Capital', AccountType.equity),
      ('2100', 'Claims Payable', AccountType.liability),
      ('4000', 'Sales', AccountType.income),
      ('5000', 'Cost of Sales', AccountType.expense),
      ('6000', 'Operating Expenses', AccountType.expense),
      ('6100', 'Office Supplies', AccountType.expense),
      ('6200', 'Fuel', AccountType.expense),
      ('6300', 'Rent', AccountType.expense),
      ('6400', 'Professional Services', AccountType.expense),
      ('6500', 'Travel', AccountType.expense),
    ]) {
      await w.createAccount(code: spec.$1, name: spec.$2, type: spec.$3);
    }
    final accounts = {
      for (final a in await w.accounts()) a.account.code: a.account.id,
    };
    final now = asOf ?? DateTime.now();
    Future<void> post(
      String memo,
      DateTime date,
      int minor,
      String debit,
      String credit, {
      EntityId? intake,
    }) async {
      await w.saveJournal(
        date: date,
        memo: memo,
        lines: [
          JournalLine.debit(
            accountId: accounts[debit]!,
            amount: Money.fromMinor(minor, 'MYR'),
          ),
          JournalLine.credit(
            accountId: accounts[credit]!,
            amount: Money.fromMinor(minor, 'MYR'),
          ),
        ],
      );
      final entry = (await w.journals()).firstWhere(
        (j) => j.entry.memo == memo,
      );
      await w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: entry.entry.id,
          expectedRevision: entry.metadata.revision,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.now().toUtc(),
          expenseIntakeId: intake,
        ),
      );
    }

    await post(
      'DEMO Opening Capital',
      DateTime(now.year, 1, 1),
      45000000,
      '1000',
      '3000',
    );
    await post(
      'DEMO Sales Receipt SR-001',
      DateTime(now.year, now.month, 1),
      68000000,
      '1000',
      '4000',
    );
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'demo-bank',
        name: 'Demo Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
        accountNumber: 'DEMO-001',
      ),
    );
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'demo-savings',
        name: 'Demo Savings',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
        accountNumber: 'DEMO-002',
      ),
    );
    await post(
      'DEMO Savings Opening',
      DateTime(now.year, 1, 1),
      2500000,
      '1010',
      '3000',
    );
    await post(
      'DEMO Savings Transfer TR-001',
      DateTime(now.year, now.month, now.day),
      15000,
      '1010',
      '1000',
    );
    for (var i = 0; i < 6; i++) {
      final date = i < 3
          ? DateTime(now.year, now.month, 1 + i)
          : DateTime(now.year, 1 + i, 5);
      final amount = [18500, 8000, 120000, 45000, 24000, 32000][i];
      final payee = [
        'Northwind Office Supplies',
        'City Fuel',
        'Workspace Rental',
        'Bright Services',
        'Metro Travel',
        'Studio Supplies',
      ][i];
      final intake = await w.saveExpenseIntake(
        RecordExpenseDraft(
          submissionId: 'demo-expense-$i',
          attachments: [demoReceipt('EXP-00${i + 1}', date, amount)],
          amount: (amount / 100).toStringAsFixed(2),
          date:
              '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}',
          payee: payee,
          paymentAccount: 'Demo Bank',
          paymentAccountId: 'demo-bank',
          category: [
            'Office Supplies',
            'Fuel',
            'Rent',
            'Professional Services',
            'Travel',
            'Office Supplies',
          ][i],
          tax: 'Out Of Scope',
          customer: '',
          billable: false,
          dimensions: 'Main Office',
          itemOrSplitDetails: '',
          notes: 'Fictional demo expense EXP-00${i + 1}',
        ),
      );
      if (i != 5) {
        await post(
          'DEMO Expense EXP-00${i + 1} · $payee',
          date,
          amount,
          ['6100', '6200', '6300', '6400', '6500', '6100'][i],
          '1000',
          intake: intake,
        );
      }
    }
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'demo-bank',
      accounts['1000']!,
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'demo-savings',
      accounts['1010']!,
    );
    _seedDemoSales(w, accounts, now);
    for (final spec in [
      ('SST Return', 'SST Return', 'Kastam / RMCD', 5),
      ('Income Tax', 'Income Tax Return', 'LHDN / HASiL', 1),
      ('Annual Return', 'SSM Annual Return', 'SSM', 0),
    ]) {
      w.saveReminder(
        WorkspaceReminder(
          id: EntityId.random(),
          title: spec.$1,
          obligation: spec.$2,
          agency: spec.$3,
          dueDate: DateTime.now().add(Duration(days: spec.$4)),
          legalSource: 'Fictional sample dates for interface testing',
        ),
      );
    }
    // Feed the dashboard from posted journal movements. Most sampled days
    // earn a margin; two days carry a genuine cost-over-sales loss.
    final sampleDays = [1, 3, 5, 7, 9, 11];
    final salesMinor = [0, 32000000, 29000000, 41000000, 25000000, 36000000];
    final costMinor = [
      31000000,
      15500000,
      33500000,
      18000000,
      27000000,
      16500000,
    ];
    for (var index = 0; index < sampleDays.length; index++) {
      final day = sampleDays[index];
      if (day > now.day) break;
      final date = DateTime(now.year, now.month, day);
      if (salesMinor[index] > 0) {
        await post(
          'DEMO Chart Sale $day',
          date,
          salesMinor[index],
          '1000',
          '4000',
        );
      }
      await post(
        'DEMO Chart Direct Cost $day',
        date,
        costMinor[index],
        '5000',
        '1000',
      );
    }
    await w.saveJournal(
      date: now.subtract(const Duration(days: 2)),
      memo: 'DEMO Accrued supplier service',
      lines: [
        JournalLine.debit(
          accountId: accounts['6000']!,
          amount: Money.fromMinor(7500, 'MYR'),
        ),
        JournalLine.credit(
          accountId: accounts['2100']!,
          amount: Money.fromMinor(7500, 'MYR'),
        ),
      ],
    );
    final template = ClaimStore.demo().all.first;
    for (var i = 0; i < 7; i++) {
      final id = EntityId.random();
      final claim = Claim.draft(
        id: id,
        vendorName: 'City Supplies',
        amount: Money.fromMinor(2500, 'MYR'),
        claimantName: i.isEven ? 'Aina Rahman' : 'Daniel Lim',
        incurredOn: DateTime.utc(now.year, now.month, 1),
        category: template.category,
        claimCategoryCode: template.claimCategoryCode,
        expenseCategoryCode: template.expenseCategoryCode,
        expenseAccountCode: template.expenseAccountCode,
        businessPurpose: 'DEMO CL-00${i + 1} · Office stationery',
        attachments: [
          demoReceipt('CL-00${i + 1}', DateTime(now.year, now.month, 1), 2500),
        ],
      );
      w.claims.saveDraft(claim);
      if (i > 0) w.claims.submit(id);
      if (i == 2 || i == 5) {
        w.approveClaim(
          reviewedClaim: w.claims.byId(id)!,
          requestId: EntityId.random(),
          expenseAccountId: accounts['6000']!,
          liabilityAccountId: accounts['2100']!,
          approvedAt: DateTime.now().toUtc(),
        );
      }
      if (i == 3) w.claims.returnForCorrection(id);
      if (i == 4) w.claims.decline(id);
      if (i == 5) {
        w.settleClaims(
          reviewedClaims: [w.claims.byId(id)!],
          requestId: EntityId.random(),
          bankAccountId: accounts['1000']!,
          paymentAccountId: 'demo-bank',
          paymentReference: 'DEMO Claim Payment CL-006',
          paidAt: DateTime.utc(now.year, now.month, 1),
        );
      }
      if (i == 6) w.claims.voidClaim(id);
    }
    for (var i = 0; i < 9; i++) {
      final number = i + 8;
      final id = EntityId.random();
      w.claims.saveAndSubmit(
        Claim.draft(
          id: id,
          vendorName: [
            'City Supplies',
            'Metro Travel',
            'Bright Services',
          ][i % 3],
          amount: Money.fromMinor(2500 + i * 1250, 'MYR'),
          claimantName: i.isEven ? 'Aina Rahman' : 'Daniel Lim',
          incurredOn: now.subtract(Duration(days: i + 1)),
          category: template.category,
          claimCategoryCode: template.claimCategoryCode,
          expenseCategoryCode: template.expenseCategoryCode,
          expenseAccountCode: template.expenseAccountCode,
          businessPurpose:
              'DEMO CL-${number.toString().padLeft(3, '0')} · Review sample',
          attachments: [
            demoReceipt(
              'CL-${number.toString().padLeft(3, '0')}',
              now.subtract(Duration(days: i + 1)),
              2500 + i * 1250,
            ),
          ],
        ),
      );
    }
    final directSources = w.database
        .readVoucherSources(w.identity.businessId)
        .where((s) => s.type == PaymentVoucherSourceType.directExpense)
        .map((s) => s.id)
        .toSet();
    final expenses = (await w.expenses())
        .where((e) => directSources.contains(e.id.value))
        .toList();
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      final id = 'demo-voucher-$i';
      w.vouchers.save(
        PaymentVoucher.create(
          id: id,
          sourceType: PaymentVoucherSourceType.directExpense,
          sourceId: e.id.value,
          payee: e.payee,
          amount: e.amount,
          paymentAccount: 'Demo Bank',
          paymentAccountId: 'demo-bank',
          paymentMethod: 'Bank Transfer',
          paymentDate: e.occurredOn,
          reference: 'DEMO-PV-00${i + 1}',
          attachments: [
            demoReceipt('PV-00${i + 1}', e.occurredOn, e.amount.minorUnits),
          ],
          preparer: 'Demo Preparer',
        ),
      );
      if (i > 0) w.vouchers.submit(id);
      if (i > 1) w.vouchers.approve(id, approver: 'Demo Approver');
      if (i > 2) w.vouchers.orderPayment(id);
      if (i > 3) w.vouchers.recordPayment(id);
      // Reconciliation is reached through the actual completed bank review.
      // Demo vouchers must not stamp an unmatched payment as reconciled.
    }
    for (var i = 0; i < 9; i++) {
      final number = i + 7;
      final date = now.subtract(Duration(days: i + 1));
      final amount = 6200 + i * 1800;
      final payee = [
        'Cerah Internet',
        'Northwind Office Supplies',
        'Metro Travel',
      ][i % 3];
      final sourceId = await w.saveExpenseIntake(
        RecordExpenseDraft(
          submissionId: 'demo-expense-review-$i',
          attachments: [
            demoReceipt(
              'EXP-${number.toString().padLeft(3, '0')}',
              date,
              amount,
            ),
          ],
          amount: (amount / 100).toStringAsFixed(2),
          date:
              '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}',
          payee: payee,
          paymentAccount: 'Demo Bank',
          paymentAccountId: 'demo-bank',
          category: 'Operating Expenses',
          tax: 'Out Of Scope',
          customer: '',
          billable: false,
          dimensions: 'Main Office',
          itemOrSplitDetails: '',
          notes:
              'Fictional review expense EXP-${number.toString().padLeft(3, '0')}',
        ),
      );
      w.vouchers.saveAndSubmit(
        PaymentVoucher.create(
          id: 'demo-voucher-review-$i',
          sourceType: PaymentVoucherSourceType.directExpense,
          sourceId: sourceId.value,
          payee: payee,
          amount: Money.fromMinor(amount, 'MYR'),
          paymentAccount: 'Demo Bank',
          paymentAccountId: 'demo-bank',
          paymentMethod: 'Bank Transfer',
          paymentDate: date,
          reference: 'DEMO-PV-${number.toString().padLeft(3, '0')}',
          attachments: [
            demoReceipt(
              'PV-${number.toString().padLeft(3, '0')}',
              date,
              amount,
            ),
          ],
          preparer: 'Demo Preparer',
        ),
      );
    }
    final alternateExpenseDate = DateTime(now.year, now.month, 1);
    final alternateExpense = await w.saveExpenseIntake(
      RecordExpenseDraft(
        submissionId: 'demo-expense-alternative-001',
        attachments: [demoReceipt('EXP-016', alternateExpenseDate, 18500)],
        amount: '185.00',
        date: '01-${now.month.toString().padLeft(2, '0')}-${now.year}',
        payee: 'Alternative Office Supplier',
        paymentAccount: 'Demo Bank',
        paymentAccountId: 'demo-bank',
        category: 'Office Supplies',
        tax: 'Out Of Scope',
        customer: '',
        billable: false,
        dimensions: 'Main Office',
        itemOrSplitDetails: '',
        notes: 'Fictional alternative bank-match candidate EXP-016',
      ),
    );
    await post(
      'DEMO Expense EXP-016 Alternative Office Supplier',
      alternateExpenseDate,
      18500,
      '6100',
      '1000',
      intake: alternateExpense,
    );
    final pdfDate = DateTime(now.year, now.month, 2);
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Demo Bank Statement', style: pw.TextStyle(fontSize: 20)),
            pw.SizedBox(height: 16),
            pw.Text('Account: DEMO-001'),
            pw.Text('Holder: Demo Company'),
            pw.Text(
              'Date: ${pdfDate.year}-${pdfDate.month.toString().padLeft(2, '0')}-02',
            ),
            pw.SizedBox(height: 16),
            pw.Text('EXP-002 Fuel                         -RM 80.00'),
            pw.Text('Opening balance: RM 1,000.00'),
            pw.Text('Closing balance: RM 920.00'),
          ],
        ),
      ),
    );
    w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'demo-bank',
      importedAt: DateTime.now().subtract(const Duration(seconds: 1)),
      statement: BankStatementImport.parsedPdf(
        filename: 'Demo Bank.pdf',
        currency: 'MYR',
        bytes: Uint8List.fromList(await pdf.save()),
        rows: [
          BankStatementRow(
            sourceRow: 1,
            sourcePage: 1,
            date: pdfDate,
            description: 'EXP-002 Fuel',
            amount: Money.fromMinor(-8000, 'MYR'),
            reference: '',
          ),
        ],
        statementDate: pdfDate,
        accountHolderName: 'Demo Company',
        accountNumber: 'DEMO-001',
        openingBalance: Money.fromMinor(100000, 'MYR'),
        closingBalance: Money.fromMinor(92000, 'MYR'),
      ),
    );
    w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'demo-bank',
      importedAt: DateTime.now(),
      statement: BankStatementImport.csv(
        filename: 'Demo Bank.csv',
        currency: 'MYR',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Date,Description,Amount,Reference\n${now.year}-${now.month.toString().padLeft(2, '0')}-01,SR-001 Customer Payment,680000.00,SR-001\n${now.year}-${now.month.toString().padLeft(2, '0')}-01,EXP-001 Office Supplies,-185.00,\n${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')},Meridian Trading Instalment 1,200.00,DEMO-RCPT-001-A\n${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')},Meridian Trading Instalment 2,300.00,DEMO-RCPT-001-B\n',
          ),
        ),
      ),
    );
    w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'demo-savings',
      importedAt: DateTime.now(),
      statement: BankStatementImport.csv(
        filename: 'Demo Savings.csv',
        currency: 'MYR',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Date,Description,Amount,Reference\n${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')},Transfer from Demo Bank,150.00,TR-001\n',
          ),
        ),
      ),
    );
    if (includeRowReview) {
      await seedDemoRowReview(w, now, receiptFactory: demoReceipt);
    }
    return w;
  } catch (_) {
    w.dispose();
    rethrow;
  }
}

void _seedDemoSales(
  AccountingWorkspace workspace,
  Map<String, EntityId> accounts,
  DateTime now,
) {
  final customers = <Customer>[];
  for (final (index, name) in [
    'Meridian Trading',
    'Northwind Services',
    'Bright Studio',
  ].indexed) {
    final customer = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: EntityId.random(),
        businessId: workspace.identity.businessId,
        originDeviceId: workspace.identity.deviceId,
        createdAt: now.toUtc(),
      ),
      displayName: name,
      contact: CustomerContact(
        contactName: name,
        email: 'accounts${index + 1}@example.test',
      ),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
    );
    workspace.saveCustomer(customer);
    customers.add(customer);
  }

  final posted = <(Invoice, EntityId)>[];
  for (final (index, customer) in customers.take(2).indexed) {
    final issueDate = DateTime(now.year, now.month - (index == 0 ? 1 : 0), 1);
    final lineId = EntityId.random();
    final invoice = Invoice.draft(
      id: EntityId.random(),
      customerId: customer.id,
      documentNumber: 'DEMO-INV-00${index + 1}',
      reference: 'DEMO-PO-00${index + 1}',
      memo: 'Fictional service invoice for design review',
      issueDate: issueDate,
      terms: customer.paymentTerms,
      lines: [
        SalesLineItem.category(
          id: lineId,
          categoryId: accounts['4000']!,
          description: index == 0 ? 'Monthly design services' : 'Office setup',
          quantity: SalesQuantity.fromInt(1),
          rate: Money.fromMinor(index == 0 ? 361445045 : 291473, 'MYR'),
        ),
      ],
    );
    workspace.saveInvoiceDraft(
      invoice,
      expectedRevision: 0,
      savedAt: issueDate.toUtc(),
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
    posted.add((invoice, lineId));
  }

  final draft = Invoice.draft(
    id: EntityId.random(),
    customerId: customers.last.id,
    documentNumber: 'DEMO-INV-003',
    issueDate: now,
    terms: customers.last.paymentTerms,
    lines: [
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: accounts['4000']!,
        description: 'Consulting session',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromMinor(32000, 'MYR'),
      ),
    ],
  );
  workspace.saveInvoiceDraft(draft, expectedRevision: 0, savedAt: now.toUtc());

  workspace.saveInvoiceCreditDraft(
    draftId: EntityId.random(),
    invoiceId: posted.first.$1.id,
    lineCredits: {posted.first.$2: Money.fromMinor(20000, 'MYR')},
    reason: 'Fictional partial service credit',
    creditDate: now,
    expectedRevision: 0,
    savedAt: now.toUtc(),
  );
  workspace.receiveInvoicePayment(
    requestId: EntityId.random(),
    customerId: customers.first.id,
    bankAccountId: accounts['1000']!,
    allocations: {posted.first.$1.id: Money.fromMinor(50000, 'MYR')},
    reference: 'DEMO-RCPT-001',
    receivedAt: now,
    approvedAt: DateTime.now().toUtc(),
    paymentAccountId: 'demo-bank',
  );
}

class DemoCompanyPage extends StatefulWidget {
  const DemoCompanyPage({super.key});
  @override
  State<DemoCompanyPage> createState() => _DemoCompanyPageState();
}

class _DemoCompanyPageState extends State<DemoCompanyPage> {
  final _future = createDemoWorkspace(includeRowReview: true);
  AccountingWorkspace? _workspace;
  @override
  void dispose() {
    _workspace?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AccountingWorkspace>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(child: Text('Demo could not open: ${snapshot.error}')),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      _workspace = snapshot.data;
      return DemoCompany(
        child: Column(
          children: [
            Expanded(
              child: AccountingShell(
                initialRoute: AccountingRouting.resolve('/home')!,
                workspace: _workspace,
              ),
            ),
          ],
        ),
      );
    },
  );
}

List<Map<String, Object?>> demoRecords(DesignForm form) => [
  for (var i = 0; i < sampleStates(form.title).length; i++)
    {
      ...sampleValues(form, i),
      '_status': sampleStates(form.title)[i],
      '_reference':
          'DEMO-${form.title.replaceAll(' ', '').toUpperCase()}-${i + 1}',
      'Date':
          '${(i + 1).toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}',
      if (form.fields.any((f) => f.label == 'Counterparty'))
        'Counterparty': i.isEven ? 'Meridian Trading' : 'Northwind Services',
      if (form.fields.any((f) => f.label == 'Amount'))
        'Amount': i == 0 ? '12000.00' : '350.00',
    },
];

ReceiptAttachment demoReceipt(String reference, DateTime date, int amount) {
  final sheet = raster.Image(width: 600, height: 800);
  raster.fill(sheet, color: raster.ColorRgb8(255, 255, 255));
  final lines = [
    'FICTIONAL DEMO RECEIPT',
    reference,
    '${date.day}-${date.month}-${date.year}',
    'Office / Business Purchase',
    'RM ${(amount / 100).toStringAsFixed(2)}',
    'Not a valid tax invoice',
  ];
  for (var i = 0; i < lines.length; i++) {
    raster.drawString(
      sheet,
      lines[i],
      font: raster.arial24,
      x: 30,
      y: 50 + i * 90,
      color: raster.ColorRgb8(30, 30, 30),
    );
  }
  final bytes = Uint8List.fromList(raster.encodePng(sheet));
  return ReceiptAttachment.queued(
    ReceiptAttachmentInput(
      originalId: 'demo-$reference',
      batchId: 'demo',
      filename: '$reference.png',
      mimeType: 'image/png',
      bytes: bytes,
    ),
  ).withDerivative(
    derivativeId: 'demo-view-$reference',
    bytes: bytes,
    mimeType: 'image/png',
    width: 600,
    height: 800,
    printReadyAt300Dpi: false,
  );
}
