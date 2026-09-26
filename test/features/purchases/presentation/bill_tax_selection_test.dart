import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/domain/vendor.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;

void main() {
  late AccountingWorkspace w;
  late Vendor vendor;
  late EntityId account;
  late PurchaseBillDraft old;
  late CompanyTaxRate code;
  setUp(() async {
    w = await AccountingWorkspace.open(':memory:');
    final setup = await setupBill(w);
    vendor = setup.$1;
    account = setup.$2.account.id;
    old = billFixture(w, vendor, account, attachments: const []);
    code = CompanyTaxRate(
      id: EntityId.random(),
      name: 'Service Tax',
      percent: '8',
      effectiveFrom: DateTime(2026, 1, 1),
      effectiveThrough: DateTime(2026, 12, 31),
      application: TaxApplication.purchases,
      accountId: EntityId.random(),
    );
  });
  tearDown(() => w.dispose());
  Map<String, Object?> values(String choice, [String basis = 'Exclusive']) {
    final result = billFormValues(old)..['Tax Mode'] = basis;
    ((result['_lines'] as List).single as Map)['Tax Rate (%)'] = choice;
    return result;
  }

  PurchaseBillDraft parse(
    Map<String, Object?> input, {
    PurchaseBillDraft? existing,
    List<CompanyTaxRate>? codes,
    RecordMetadata? metadata,
  }) => billFromForm(
    input,
    metadata: metadata ?? old.metadata,
    vendor: vendor,
    purchaseAccountIds: {account.value},
    taxCodes: codes ?? [code],
    existing: existing,
  );

  test(
    'new Bills expose only amount basis, no Review Needed or classification',
    () {
      final field = billForm(
        {},
        {},
      ).fields.singleWhere((f) => f.label == 'Tax Mode');
      expect(field.choiceLabels!.keys, ['Exclusive', 'Inclusive']);
      expect(field.disabledOptions, isEmpty);
      expect(billFormValues(old)['Tax Mode'], '');
      for (final bad in ['', 'Review Needed', 'Exempt', 'Out Of Scope']) {
        expect(() => parse(values('0', bad)), throwsFormatException);
      }
      expect(old.taxMode, isNull);
      expect(old.toJson()['version'], 1);
    },
  );
  test('configured mixed row codes and No Tax have exact inclusive/exclusive totals', () {
    for (final basis in ['Exclusive', 'Inclusive']) {
      final input = values(code.choice, basis);
      final first = (input['_lines'] as List).single as Map;
      input['_lines'] = [
        first,
        {
          ...first,
          '_lineId': EntityId.random().value,
          'Quantity': '1',
          'Rate': '100',
          'Discount': '0',
          'Tax Rate (%)': '0',
        },
      ];
      final bill = parse(input);
      expect(bill.lines.first.taxSnapshot!.choice, code.choice);
      expect(bill.lines.last.taxSnapshot, isNull);
      expect(bill.total.minorUnits, basis == 'Exclusive' ? 25120 : 24000);
      expect(
        PurchaseBillDraft.fromJson(jsonDecode(jsonEncode(bill.toJson())))
            .toJson(),
        bill.toJson(),
      );
    }
  });
  test(
    'unnamed positive rate cannot create a Bill or override a saved line',
    () {
      expect(() => parse(values('8')), throwsFormatException);
      expect(() => parse(values('6'), existing: old), throwsFormatException);
      for (final choice in ['', '-1', 'eight']) {
        expect(
          () => parse(values(choice), existing: old),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'exact unlinked legacy rate stays on its original line, not a new row',
    () {
      final before = jsonEncode(old.toJson());
      final input = values('8');
      expect(parse(input, existing: old).total, old.total);
      final original = (input['_lines'] as List).single as Map;
      input['_lines'] = [
        original,
        {...original, '_lineId': EntityId.random().value},
      ];
      expect(() => parse(input, existing: old), throwsFormatException);
      expect(jsonEncode(old.toJson()), before);
    },
  );
  test('saved tax facts cannot authorize a different Bill identity', () {
    final other = RecordMetadata.initial(
      recordId: EntityId.random(),
      businessId: w.identity.businessId,
      originDeviceId: w.identity.deviceId,
      createdAt: DateTime.utc(2026, 9, 28),
    );
    expect(
      () => parse(values('8'), existing: old, metadata: other),
      throwsStateError,
    );
  });
  test('historical classifications remain readable and editable but not new choices', () {
    final zero = parse(values('0'));
    for (final basis in ['Exempt', 'Out Of Scope']) {
      final archived = {...zero.toJson(), 'taxMode': basis};
      final saved = PurchaseBillDraft.fromJson(
        jsonDecode(jsonEncode(archived)),
      );
      final before = jsonEncode(saved.toJson());
      final field = billForm(
        {},
        {},
        existing: saved,
      ).fields.singleWhere((f) => f.label == 'Tax Mode');
      expect(field.choiceLabels![basis], 'Saved $basis');
      expect(field.disabledOptions, {basis});
      final edited = billFormValues(saved)..['Memo'] = 'Updated memo';
      expect(parse(edited, existing: saved).taxMode, basis);
      expect(() => parse(edited), throwsFormatException);
      expect(jsonEncode(saved.toJson()), before);
    }
  });
  test('master edit/deactivation retains the exact saved revision, never authorizes a new row', () {
    final saved = parse(values(code.choice));
    final revised = CompanyTaxRate(
      id: code.id,
      name: code.name,
      percent: '9',
      revision: 1,
      effectiveFrom: code.effectiveFrom,
      application: code.application,
      accountId: code.accountId,
      active: false,
    );
    final input = billFormValues(saved);
    final edited = parse(input, existing: saved, codes: [revised]);
    expect(edited.lines.single.taxSnapshot!.toJson(), code.toJson());
    expect(edited.total.minorUnits, 15120);
    final original = (input['_lines'] as List).single as Map;
    input['_lines'] = [
      original,
      {...original, '_lineId': EntityId.random().value},
    ];
    expect(
      () => parse(input, existing: saved, codes: [revised]),
      throwsStateError,
    );
  });
  test(
    'changed date and wrong-purpose company code require explicit resolution',
    () {
      final saved = parse(values(code.choice));
      final input = billFormValues(saved)..['Date'] = '01-01-2027';
      expect(() => parse(input, existing: saved), throwsStateError);
      final salesOnly = CompanyTaxRate(
        id: EntityId.random(),
        name: 'SST',
        percent: '5',
        effectiveFrom: code.effectiveFrom,
        application: TaxApplication.sales,
        accountId: code.accountId,
      );
      expect(
        () => parse(values(salesOnly.choice), codes: [salesOnly]),
        throwsStateError,
      );
      expect(
        parse(values('0'), codes: const []).lines.single.tax.minorUnits,
        0,
      );
    },
  );
}
