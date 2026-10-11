import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_payment_term.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../accounting/data/bill_draft_persistence_test.dart'
    show billFixture, setupBill;

void main() {
  test(
    'colliding saved labels keep distinct selector identities and rules',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final (vendor, account) = await setupBill(workspace);
      final first = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 15',
          rule: PaymentTerms.netDays(5),
        ),
      );
      final second = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 15 · Saved Term',
          rule: PaymentTerms.netDays(11),
        ),
      );
      final templates = workspace.paymentTerms;
      final form = billForm(
        {vendor.id.value: vendor.name},
        {account.account.id.value: account.account.name},
        paymentTermTemplates: templates,
      );
      final labels = form.fields
          .singleWhere((field) => field.label == 'Payment Terms')
          .choiceLabels!;
      expect(
        labels.values.map((label) => label.toLowerCase()).toSet(),
        hasLength(labels.length),
      );
      expect(
        billPaymentTermChoice(first),
        isNot(billPaymentTermChoice(second)),
      );
      final source = billFixture(
        workspace,
        vendor,
        account.account.id,
        attachments: const [],
      );
      final values = billFormValues(source)..['Tax Mode'] = 'Exclusive';
      ((values['_lines'] as List).single as Map)['Tax Rate (%)'] = '0';
      PurchaseBillDraft selected(CompanyPaymentTerm term) => billFromForm(
        {...values, 'Payment Terms': billPaymentTermChoice(term)},
        metadata: source.metadata,
        vendor: vendor,
        purchaseAccountIds: {account.account.id.value},
        paymentTermTemplates: templates,
      );
      expect(
        selected(first).bill.terms.toJson(),
        PaymentTerms.netDays(5).toJson(),
      );
      expect(
        selected(second).bill.terms.toJson(),
        PaymentTerms.netDays(11).toJson(),
      );
    },
  );

  test(
    'named fixed and monthly terms save exact generic Bill snapshots',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-bill-terms-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/books.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final (vendor, account) = await setupBill(workspace);
      final accountIds = {account.account.id.value};
      final fixed = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 30',
          rule: PaymentTerms.netDays(14),
        ),
      );
      final monthly = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Monthly Cutoff',
          rule: PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5),
        ),
      );
      final choices = workspace.paymentTerms;
      final form = billForm(
        {vendor.id.value: vendor.name},
        {account.account.id.value: account.account.name},
        paymentTermTemplates: choices,
      );
      final field = form.fields.singleWhere(
        (field) => field.label == 'Payment Terms',
      );
      expect(
        field.choiceLabels!.keys,
        containsAll(['Net 30', billPaymentTermChoice(fixed)]),
      );
      expect(
        field.choiceLabels![billPaymentTermChoice(fixed)],
        'Net 30 · Saved Term',
      );
      expect(billPaymentTermChoice(fixed), isNot('Net 30'));

      final oldJson = jsonDecode(
        jsonEncode(
          billFixture(
            workspace,
            vendor,
            account.account.id,
            attachments: const [],
          ).toJson(),
        ),
      ) as Map<String, dynamic>;
      ((oldJson['bill'] as Map)['terms'] as Map)['customText'] =
          'Old hidden Custom text';
      final old = PurchaseBillDraft.fromJson(oldJson);
      workspace.saveBillDraft(old, expectedRevision: 0);
      final fixedValues = billFormValues(old)
        ..['Payment Terms'] = billPaymentTermChoice(fixed)
        ..['Tax Mode'] = 'Exclusive';
      expect(fixedValues['Due Date'], '01-10-2026');
      expect(fixedValues['Custom Payment Terms'], 'Old hidden Custom text');
      final fixedDraft = billFromForm(
        fixedValues,
        metadata: old.metadata.nextRevision(
          updatedAt: DateTime.utc(2026, 10, 11),
        ),
        vendor: vendor,
        purchaseAccountIds: accountIds,
        paymentTermTemplates: choices,
        existing: old,
      );
      expect(fixedDraft.bill.dueDate, DateTime.utc(2026, 9, 15));
      expect(fixedDraft.bill.terms.toJson(), PaymentTerms.netDays(14).toJson());
      expect(fixedDraft.bill.terms.customText, isNull);
      expect(fixedDraft.supplierReference, old.supplierReference);
      expect(fixedDraft.vendorSnapshot.toJson(), old.vendorSnapshot.toJson());
      workspace.saveBillDraft(fixedDraft, expectedRevision: 1);

      final monthlySource = billFixture(
        workspace,
        vendor,
        account.account.id,
        attachments: const [],
      );
      final monthlyValues = billFormValues(monthlySource)
        ..['Date'] = '18-09-2026'
        ..['Payment Terms'] = billPaymentTermChoice(monthly)
        ..['Tax Mode'] = 'Exclusive';
      ((monthlyValues['_lines'] as List).single as Map)['Tax Rate (%)'] = '0';
      final monthlyDraft = billFromForm(
        monthlyValues,
        metadata: monthlySource.metadata,
        vendor: vendor,
        purchaseAccountIds: accountIds,
        paymentTermTemplates: choices,
      );
      expect(monthlyDraft.bill.dueDate, DateTime.utc(2026, 10, 20));
      expect(monthlyDraft.bill.terms.toJson(), monthly.rule.toJson());
      workspace.saveBillDraft(monthlyDraft, expectedRevision: 0);

      final ordinary = billFromForm(
        {...monthlyValues, 'Payment Terms': 'Net 30', 'Due Date': ''},
        metadata: monthlySource.metadata,
        vendor: vendor,
        purchaseAccountIds: accountIds,
        paymentTermTemplates: choices,
      );
      expect(ordinary.bill.terms.days, 30);
      expect(ordinary.bill.dueDate, DateTime.utc(2026, 10, 18));

      final businessId = workspace.identity.businessId;
      final archive = workspace.database.exportDataArchive(
        businessId,
        DateTime.utc(2026, 10, 11),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final reopenedFixed = workspace.database.readBillDraft(
        businessId,
        fixedDraft.id,
      )!;
      final reopenedMonthly = workspace.database.readBillDraft(
        businessId,
        monthlyDraft.id,
      )!;
      expect(reopenedFixed.toJson(), fixedDraft.toJson());
      expect(reopenedMonthly.toJson(), monthlyDraft.toJson());
      expect(
        billFormValues(reopenedFixed)['Payment Terms'],
        'Days After Issue',
      );
      expect(billFormValues(reopenedMonthly)['Payment Terms'], 'Day Of Month');
      final genericReopen = billFromForm(
        billFormValues(reopenedFixed),
        metadata: reopenedFixed.metadata.nextRevision(
          updatedAt: DateTime.utc(2026, 10, 12),
        ),
        vendor: reopenedFixed.vendorSnapshot,
        purchaseAccountIds: accountIds,
        existing: reopenedFixed,
        paymentTermTemplates: const [],
      );
      expect(genericReopen.bill.terms.toJson(), fixedDraft.bill.terms.toJson());
      expect(genericReopen.bill.dueDate, fixedDraft.bill.dueDate);
      expect(
        jsonEncode(reopenedFixed.toJson()),
        isNot(contains(fixed.id.value)),
      );
      expect(
        jsonEncode(reopenedMonthly.toJson()),
        isNot(contains(monthly.id.value)),
      );
      expect(
        jsonEncode(reopenedFixed.toJson()),
        isNot(contains('Net 30 · Saved Term')),
      );

      final recovered = LocalAccountingDatabase.inMemory();
      addTearDown(recovered.close);
      recovered.restoreDataArchive(archive);
      expect(
        recovered.readBillDraft(businessId, fixedDraft.id)!.toJson(),
        fixedDraft.toJson(),
      );
      expect(
        recovered.readBillDraft(businessId, monthlyDraft.id)!.toJson(),
        monthlyDraft.toJson(),
      );
      expect(recovered.readPaymentTerms(businessId), hasLength(2));
    },
  );

  test(
    'missing, inactive and foreign named choices cannot save a Bill',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'audyt-bill-term-guard-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${folder.path}/company.sqlite',
      );
      addTearDown(workspace.dispose);
      final other = await AccountingWorkspace.open(
        '${folder.path}/other.sqlite',
      );
      addTearDown(other.dispose);
      final (vendor, account) = await setupBill(workspace);
      final source = billFixture(
        workspace,
        vendor,
        account.account.id,
        attachments: const [],
      );
      final local = workspace.createPaymentTerm(
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
      expect(workspace.paymentTerms.map((term) => term.id), [local.id]);
      expect(
        workspace.database.readPaymentTerms(other.identity.businessId),
        isEmpty,
      );
      final inactive = CompanyPaymentTerm(
        id: EntityId.random(),
        name: 'Inactive',
        rule: PaymentTerms.netDays(3),
        active: false,
        revision: 1,
        createdAt: DateTime.utc(2026, 10, 11),
      );
      final base = billFormValues(source)..['Tax Mode'] = 'Exclusive';
      PurchaseBillDraft convert(
        String choice,
        List<CompanyPaymentTerm> templates,
      ) => billFromForm(
        {...base, 'Payment Terms': choice},
        metadata: source.metadata,
        vendor: vendor,
        purchaseAccountIds: {account.account.id.value},
        paymentTermTemplates: templates,
      );
      expect(
        () => convert(billPaymentTermChoice(foreign), workspace.paymentTerms),
        throwsStateError,
      );
      expect(
        () => convert(
          '__company_payment_term__:${EntityId.random().value}',
          workspace.paymentTerms,
        ),
        throwsStateError,
      );
      expect(
        () => convert(billPaymentTermChoice(inactive), [inactive]),
        throwsStateError,
      );
      final form = billForm(
        {vendor.id.value: vendor.name},
        {account.account.id.value: account.account.name},
        paymentTermTemplates: [inactive],
      );
      final field = form.fields.singleWhere(
        (field) => field.label == 'Payment Terms',
      );
      expect(
        field.choiceLabels!.keys,
        isNot(contains(billPaymentTermChoice(inactive))),
      );
      expect(
        workspace.database.readBillDraft(
          workspace.identity.businessId,
          source.id,
        ),
        isNull,
      );
    },
  );
}
