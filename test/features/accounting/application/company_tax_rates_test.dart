import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AccountingWorkspace w;
  late EntityId taxAccount;
  late Set<String> incomeIds;
  setUp(() async {
    w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    await w.createAccount(
      code: '2200',
      name: 'Tax Payable',
      type: AccountType.liability,
    );
    incomeIds = {
      for (final r in await w.accounts())
        if (r.account.type == AccountType.income) r.account.id.value,
    };
    taxAccount = (await w.accounts())
        .singleWhere((r) => r.account.code == '2200')
        .account
        .id;
  });
  tearDown(() => w.dispose());
  CompanyTaxRate rate({
    String percent = '8',
    TaxApplication application = TaxApplication.both,
    EntityId? account,
  }) => CompanyTaxRate(
    id: EntityId.random(),
    name: 'Explicit Example Tax',
    percent: percent,
    effectiveFrom: DateTime(2026, 1, 1),
    effectiveThrough: DateTime(2026, 12, 31),
    application: application,
    accountId: account ?? taxAccount,
  );
  test('effective dates, applicability and exact inclusive/exclusive arithmetic are explicit', () {
    final code = w.saveTaxRate(
      rate(percent: '6.1234', application: TaxApplication.sales),
    );
    expect(code.applies(DateTime(2026, 1, 1), TaxApplication.sales), isTrue);
    expect(code.applies(DateTime(2026, 12, 31), TaxApplication.sales), isTrue);
    expect(code.applies(DateTime(2027), TaxApplication.sales), isFalse);
    expect(code.applies(DateTime(2026, 2), TaxApplication.purchases), isFalse);
    expect(() => rate(percent: '8.00001'), throwsFormatException);
    final current = w.invoiceDrafts().first.invoice;
    final values = invoiceFormValues(current)..['Tax Mode'] = 'Exclusive';
    final line = (values['_lines'] as List).first as Map;
    line['Tax Rate (%)'] = code.choice;
    line['Amount'] = '100.00';
    line['Rate'] = '100.00';
    final invoice = invoiceFromForm(
      values,
      id: current.id,
      customer: w.customers().singleWhere((c) => c.id == current.customerId),
      incomeAccountIds: incomeIds,
      existing: current,
      taxCodes: w.taxRates,
    );
    expect(invoice.lines.first.tax, Money.fromMinor(612, 'MYR'));
    expect(invoice.lines.first.taxSnapshot!.revision, 1);
    expect(
      Invoice.fromDraftSnapshot(invoice.draftSnapshot())
          .lines
          .first
          .taxSnapshot!
          .choice,
      code.choice,
    );
  });
  test('edit and deactivate retain the saved document snapshot; new stale selection is rejected', () {
    final code = w.saveTaxRate(rate());
    final old = w.invoiceDrafts().first.invoice;
    final values = invoiceFormValues(old)..['Tax Mode'] = 'Exclusive';
    ((values['_lines'] as List).first as Map)['Tax Rate (%)'] = code.choice;
    Invoice resolve(Map<String, Object?> input, {Invoice? existing}) =>
        invoiceFromForm(
          input,
          id: old.id,
          customer: w.customers().singleWhere((c) => c.id == old.customerId),
          incomeAccountIds: incomeIds,
          existing: existing,
          taxCodes: w.taxRates,
        );
    final saved = resolve(values, existing: old);
    w.saveInvoiceDraft(
      saved,
      expectedRevision: 1,
      savedAt: DateTime.now().toUtc(),
    );
    final changed = w.saveTaxRate(
      CompanyTaxRate.fromJson({
        ...code.toJson(),
        'percent': '9',
        'active': false,
      }),
    );
    expect(changed.revision, 2);
    expect(() => w.saveTaxRate(code), throwsStateError);
    expect(() => resolve(values), throwsStateError);
    final edited = resolve(invoiceFormValues(saved), existing: saved);
    expect(edited.lines.first.tax, saved.lines.first.tax);
    expect(edited.lines.first.taxSnapshot!.percent, '8');
    w.saveInvoiceDraft(
      edited,
      expectedRevision: 2,
      savedAt: DateTime.now().toUtc(),
    );
    expect(
      w.database.taxRateHistory(w.identity.businessId, code.id),
      hasLength(2),
    );
  });
  test(
    'foreign account and actor are rejected without changing company state',
    () async {
      final other = await AccountingWorkspace.open(':memory:');
      addTearDown(other.dispose);
      await other.createAccount(
        code: '2200',
        name: 'Other Tax',
        type: AccountType.liability,
      );
      final foreign = (await other.accounts()).single.account.id;
      expect(() => w.saveTaxRate(rate(account: foreign)), throwsStateError);
      expect(
        () => w.database.saveTaxRate(
          businessId: w.identity.businessId,
          actorId: EntityId.random(),
          rate: rate(),
          savedAt: DateTime.now(),
        ),
        throwsStateError,
      );
      expect(w.taxRates, isEmpty);
    },
  );
  test('tax master and revisions survive data archive restore', () async {
    final first = w.saveTaxRate(rate());
    w.saveTaxRate(
      CompanyTaxRate.fromJson({...first.toJson(), 'name': 'Edited Example'}),
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.now().toUtc(),
    );
    final target = LocalAccountingDatabase.inMemory();
    addTearDown(target.close);
    target.restoreDataArchive(archive);
    expect(
      target.readTaxRates(w.identity.businessId).single.name,
      'Edited Example',
    );
    expect(
      target.taxRateHistory(w.identity.businessId, first.id),
      hasLength(2),
    );
  });
  test(
    'document tax is enforced while mixed saved line facts remain editable',
    () {
      final code = w.saveTaxRate(rate());
      final old = w.invoiceDrafts().first.invoice;
      final values = invoiceFormValues(old)..['Tax Mode'] = 'Exclusive';
      final first = (values['_lines'] as List).first as Map;
      first['Tax Rate (%)'] = code.choice;
      final second = Map<String, String>.from(first)
        ..['_lineId'] = EntityId.random().value
        ..['Tax Rate (%)'] = '0';
      (values['_lines'] as List).add(second);
      Invoice resolve(Map<String, Object?> input, {Invoice? existing}) =>
          invoiceFromForm(
            input,
            id: old.id,
            customer: w.customers().singleWhere((c) => c.id == old.customerId),
            incomeAccountIds: incomeIds,
            existing: existing,
            taxCodes: w.taxRates,
          );
      // Historic callers can supply mixed line tax; the new form preserves it.
      final mixed = resolve(values, existing: old);
      final edit = invoiceFormValues(mixed)
        ..['_documentTaxChoice'] = null
        ..['Memo'] = 'Memo amendment';
      final preserved = resolve(edit, existing: mixed);
      expect(
        preserved.lines.map((l) => l.taxSnapshot?.choice ?? l.taxRatePercent),
        mixed.lines.map((l) => l.taxSnapshot?.choice ?? l.taxRatePercent),
      );
      expect(preserved.total, mixed.total);

      (edit['_lines'] as List).add(
        Map<String, String>.from(second)..['_lineId'] = EntityId.random().value,
      );
      expect(() => resolve(edit, existing: mixed), throwsFormatException);
      (edit['_lines'] as List).removeLast();
      edit['_documentTaxChoice'] = code.choice;
      expect(() => resolve(edit, existing: mixed), throwsFormatException);
      for (final line in edit['_lines'] as List) {
        (line as Map)['Tax Rate (%)'] = code.choice;
      }
      expect(
        resolve(
          edit,
          existing: mixed,
        ).lines.every((l) => l.taxSnapshot?.choice == code.choice),
        isTrue,
      );
      edit['_documentTaxChoice'] = '0';
      for (final line in edit['_lines'] as List) {
        (line as Map)['Tax Rate (%)'] = '0';
      }
      final noTax = resolve(edit, existing: mixed);
      expect(noTax.lines.every((l) => l.tax.minorUnits == 0), isTrue);
      expect(noTax.lines.every((l) => l.taxSnapshot == null), isTrue);
    },
  );
}
