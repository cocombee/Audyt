import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/documents/generated_document.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_payment_term.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/accounting/presentation/company_payment_term_selection.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/generated_sales_document_service.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/sales_report_fixture.dart';

final class CountingWriter implements GeneratedDocumentFileWriter {
  int calls = 0;

  @override
  Future<void> writeAndVerify(
    GeneratedDocumentDelivery delivery,
    ReceiptAttachment attachment,
  ) async {
    calls++;
  }
}

Invoice sourceInvoice(
  SalesReportFixture fixture, {
  DateTime? issueDate,
  String number = 'INV-TERMS-REVIEW',
}) {
  final issue = issueDate ?? DateTime.utc(2026, 9, 1);
  return Invoice.draft(
    id: EntityId.random(),
    customerId: fixture.customer.id,
    documentNumber: number,
    issueDate: issue,
    dueDate: PaymentTerms.netDays(30).dueDateFor(issue),
    terms: PaymentTerms.netDays(30, customText: 'Old hidden Custom text'),
    taxMode: 'Exclusive',
    reference: 'Fictional reference',
    memo: 'Original memo',
    lines: [
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: fixture.income,
        description: 'Fictional production',
        quantity: SalesQuantity.fromInt(1),
        rate: Money.fromMinor(10000, 'MYR'),
        taxRatePercent: '0',
      ),
    ],
  );
}

Invoice selectTerm(
  SalesReportFixture fixture,
  Invoice source,
  String choice,
  List<CompanyPaymentTerm> templates, {
  DateTime? issueDate,
  String? customText,
  String? dueDate,
}) {
  final values = invoiceFormValues(source)..['Payment Terms'] = choice;
  if (issueDate != null) {
    final day = issueDate.day.toString().padLeft(2, '0');
    final month = issueDate.month.toString().padLeft(2, '0');
    values['Date'] = '$day-$month-${issueDate.year}';
  }
  if (customText != null) values['Custom Payment Terms'] = customText;
  if (dueDate != null) values['Due Date'] = dueDate;
  return invoiceFromForm(
    values,
    id: source.id,
    customer: fixture.customer,
    incomeAccountIds: {fixture.income.value},
    paymentTermTemplates: templates,
    existing: source,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Invoice choices resolve exact rules, collisions and generic defaults',
    () async {
      final fixture = await salesReportFixture(seedInvoices: false);
      addTearDown(fixture.workspace.dispose);
      final fixed = fixture.workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 30',
          rule: PaymentTerms.netDays(14),
        ),
      );
      final shadow = fixture.workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 30 · Saved Term',
          rule: PaymentTerms.netDays(11),
        ),
      );
      final monthly = fixture.workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Monthly',
          rule: PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5),
        ),
      );
      final templates = fixture.workspace.paymentTerms;
      final field = invoiceForm(
        {fixture.customer.id.value: fixture.customer.displayName},
        {fixture.income.value: 'Fictional Sales'},
        paymentTermTemplates: templates,
      ).fields.singleWhere((field) => field.label == 'Payment Terms');
      final labels = field.choiceLabels!;
      expect(
        labels.keys,
        containsAll([
          'Net 30',
          companyPaymentTermChoice(fixed),
          companyPaymentTermChoice(shadow),
          companyPaymentTermChoice(monthly),
        ]),
      );
      expect(
        labels.values.map((label) => label.toLowerCase()).toSet(),
        hasLength(labels.length),
      );
      expect(companyPaymentTermChoice(fixed), isNot('Net 30'));
      final source = sourceInvoice(fixture);
      final chosen = selectTerm(
        fixture,
        source,
        companyPaymentTermChoice(fixed),
        templates,
      );
      expect(chosen.terms.toJson(), PaymentTerms.netDays(14).toJson());
      expect(chosen.terms.customText, isNull);
      expect(chosen.dueDate, DateTime.utc(2026, 9, 15));
      expect(chosen.reference, source.reference);
      expect(chosen.memo, source.memo);
      expect(
        selectTerm(
          fixture,
          source,
          companyPaymentTermChoice(shadow),
          templates,
        ).terms.days,
        11,
      );
      final monthlySource = sourceInvoice(
        fixture,
        issueDate: DateTime.utc(2026, 9, 18),
        number: 'INV-MONTHLY',
      );
      final monthlyInvoice = selectTerm(
        fixture,
        monthlySource,
        companyPaymentTermChoice(monthly),
        templates,
      );
      expect(monthlyInvoice.terms.toJson(), monthly.rule.toJson());
      expect(monthlyInvoice.dueDate, DateTime.utc(2026, 10, 20));

      final ordinary = selectTerm(
        fixture,
        source,
        'Net 30',
        templates,
        customText: '',
        dueDate: '',
      );
      expect(ordinary.terms.days, 30);
      expect(ordinary.dueDate, DateTime.utc(2026, 10, 1));
      final customerDefault = selectTerm(
        fixture,
        source,
        'Use Customer Default',
        templates,
        customText: '',
        dueDate: '',
      );
      expect(
        customerDefault.terms.toJson(),
        fixture.customer.paymentTerms.toJson(),
      );
      final custom = selectTerm(
        fixture,
        source,
        'Custom',
        templates,
        customText: 'Upon approval',
        dueDate: '22-09-2026',
      );
      expect(custom.terms.kind, PaymentTermKind.custom);
      expect(custom.dueDate, DateTime.utc(2026, 9, 22));
    },
  );

  test(
    'unknown, inactive and foreign Invoice choices reject before persistence',
    () async {
      final fixture = await salesReportFixture(seedInvoices: false);
      addTearDown(fixture.workspace.dispose);
      final other = await AccountingWorkspace.open(':memory:');
      addTearDown(other.dispose);
      final local = fixture.workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Local',
          rule: PaymentTerms.netDays(7),
        ),
      );
      final foreign = other.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Other',
          rule: PaymentTerms.netDays(9),
        ),
      );
      final inactive = CompanyPaymentTerm(
        id: EntityId.random(),
        name: 'Inactive',
        rule: PaymentTerms.netDays(5),
        active: false,
        revision: 1,
        createdAt: DateTime.utc(2026, 10, 11),
      );
      final source = sourceInvoice(fixture);
      expect(fixture.workspace.paymentTerms.map((term) => term.id), [local.id]);
      expect(
        fixture.workspace.database.readPaymentTerms(other.identity.businessId),
        isEmpty,
      );
      for (final (choice, templates) in [
        (companyPaymentTermChoice(foreign), fixture.workspace.paymentTerms),
        (
          '__company_payment_term__:${EntityId.random().value}',
          fixture.workspace.paymentTerms,
        ),
        (companyPaymentTermChoice(inactive), [inactive]),
      ]) {
        expect(
          () => selectTerm(fixture, source, choice, templates),
          throwsStateError,
        );
      }
      expect(fixture.workspace.invoiceDrafts(), isEmpty);
    },
  );

  test('saved Invoice snapshots survive SQLite reopen and archive as generic rules', () async {
    final folder = Directory.systemTemp.createTempSync('audyt-invoice-terms-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/books.sqlite';
    final fixture = await salesReportFixture(path: path, seedInvoices: false);
    var workspace = fixture.workspace;
    final fixed = workspace.createPaymentTerm(
      CompanyPaymentTerm(
        id: EntityId.random(),
        name: 'Fortnight',
        rule: PaymentTerms.netDays(14),
      ),
    );
    final monthly = workspace.createPaymentTerm(
      CompanyPaymentTerm(
        id: EntityId.random(),
        name: 'Monthly',
        rule: PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5),
      ),
    );
    final initial = sourceInvoice(fixture);
    final fixedInvoice = selectTerm(
      fixture,
      initial,
      companyPaymentTermChoice(fixed),
      workspace.paymentTerms,
    );
    final monthlyInitial = sourceInvoice(
      fixture,
      issueDate: DateTime.utc(2026, 9, 18),
      number: 'INV-MONTHLY-SAVED',
    );
    final monthlyInvoice = selectTerm(
      fixture,
      monthlyInitial,
      companyPaymentTermChoice(monthly),
      workspace.paymentTerms,
    );
    workspace.saveInvoiceDraft(
      fixedInvoice,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 10, 11),
    );
    workspace.saveInvoiceDraft(
      monthlyInvoice,
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 10, 11),
    );
    final company = workspace.identity.businessId;
    final archive = workspace.database.exportDataArchive(
      company,
      DateTime.utc(2026, 10, 11),
    );
    workspace.dispose();
    // Simulate later catalogue changes outside the creation-only command.
    // Saved documents must continue to use their own frozen rule/date.
    final changedCatalog = sqlite3.open(path);
    changedCatalog.execute(
      'UPDATE company_payment_terms SET name=?,normalized_name=?,payload=? WHERE business_id=? AND id=?',
      [
        'Renamed Current Term',
        'renamed current term',
        jsonEncode({
          ...fixed.toJson(),
          'name': 'Renamed Current Term',
          'rule': PaymentTerms.netDays(9).toJson(),
        }),
        company.value,
        fixed.id.value,
      ],
    );
    changedCatalog.execute(
      'DELETE FROM company_payment_terms WHERE business_id=? AND id=?',
      [company.value, monthly.id.value],
    );
    changedCatalog.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(workspace.paymentTerms.single.name, 'Renamed Current Term');
    expect(workspace.paymentTerms.single.rule.days, 9);
    final saved = workspace.invoiceDrafts();
    final restoredFixed = saved
        .singleWhere((record) => record.invoice.id == fixedInvoice.id)
        .invoice;
    final restoredMonthly = saved
        .singleWhere((record) => record.invoice.id == monthlyInvoice.id)
        .invoice;
    expect(restoredFixed.draftSnapshot(), fixedInvoice.draftSnapshot());
    expect(restoredMonthly.draftSnapshot(), monthlyInvoice.draftSnapshot());
    expect(
      invoiceFormValues(restoredFixed)['Payment Terms'],
      'Days After Issue',
    );
    expect(invoiceFormValues(restoredMonthly)['Payment Terms'], 'Day Of Month');
    expect(
      jsonEncode(restoredFixed.draftSnapshot()),
      isNot(contains(fixed.id.value)),
    );
    expect(
      jsonEncode(restoredMonthly.draftSnapshot()),
      isNot(contains(monthly.id.value)),
    );
    final generic = selectTerm(
      fixture,
      restoredFixed,
      'Days After Issue',
      const [],
    );
    expect(generic.terms.toJson(), fixedInvoice.terms.toJson());
    expect(generic.dueDate, fixedInvoice.dueDate);
    final recovered = LocalAccountingDatabase.inMemory();
    addTearDown(recovered.close);
    recovered.restoreDataArchive(archive);
    final archived = recovered.readInvoiceDrafts(company);
    expect(
      archived
          .singleWhere((r) => r.invoice.id == fixedInvoice.id)
          .invoice
          .draftSnapshot(),
      fixedInvoice.draftSnapshot(),
    );
    expect(
      archived
          .singleWhere((r) => r.invoice.id == monthlyInvoice.id)
          .invoice
          .draftSnapshot(),
      monthlyInvoice.draftSnapshot(),
    );
  });

  test('term changed while PDF renders prevents every Invoice commit and delivery', () async {
    final folder = Directory.systemTemp.createTempSync('audyt-invoice-race-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/books.sqlite';
    final fixture = await salesReportFixture(path: path, seedInvoices: false);
    addTearDown(fixture.workspace.dispose);
    final selected = fixture.workspace.createPaymentTerm(
      CompanyPaymentTerm(
        id: EntityId.random(),
        name: 'Fortnight',
        rule: PaymentTerms.netDays(14),
      ),
    );
    final invoice = selectTerm(
      fixture,
      sourceInvoice(fixture),
      companyPaymentTermChoice(selected),
      fixture.workspace.paymentTerms,
    );
    final writer = CountingWriter();
    final pending = GeneratedSalesDocumentService(writer: writer).saveInvoice(
      workspace: fixture.workspace,
      invoice: invoice,
      customer: fixture.customer,
      filename: 'Invoice.pdf',
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 10, 11),
      selectedPaymentTerm: selected,
    );
    // saveInvoice is suspended in its awaited PDF render. Simulate a separate
    // writer changing the current catalog before the guarded commit resumes.
    final raw = sqlite3.open(path);
    final auditBefore = raw
        .select('SELECT COUNT(*) AS count FROM ledger_audit')
        .single['count'];
    raw.execute(
      'UPDATE company_payment_terms SET payload=? WHERE business_id=? AND id=?',
      [
        jsonEncode({
          ...selected.toJson(),
          'rule': PaymentTerms.netDays(9).toJson(),
        }),
        fixture.workspace.identity.businessId.value,
        selected.id.value,
      ],
    );
    expect(fixture.workspace.paymentTerms.single.rule.days, 9);
    await expectLater(pending, throwsStateError);
    expect(fixture.workspace.invoiceDrafts(), isEmpty);
    for (final table in [
      'invoice_drafts',
      'invoice_draft_history',
      'generated_document_deliveries',
      'journal_entries',
    ]) {
      expect(
        raw.select('SELECT 1 FROM $table WHERE business_id=?', [
          fixture.workspace.identity.businessId.value,
        ]),
        isEmpty,
        reason: table,
      );
    }
    expect(
      raw.select('SELECT COUNT(*) AS count FROM ledger_audit').single['count'],
      auditBefore,
    );
    expect(writer.calls, 0);
    raw.dispose();
  });
}
