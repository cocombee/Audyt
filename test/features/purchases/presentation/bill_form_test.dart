import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;

void main() {
  test('basic bill amount is exact and historic quantity/discount remain available', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, account) = await setupBill(w);
    final old = billFixture(
      w,
      vendor,
      account.account.id,
      attachments: const [],
    );
    final choices = {account.account.id.value: account.account.name};
    final preferences = CompanyPreferences.defaults();
    final basic = billForm(
      {vendor.id.value: vendor.name},
      choices,
      preferences: preferences,
    );
    expect(basic.lineFields, [
      'Account',
      'Description',
      'Tax Rate (%)',
      'Amount',
    ]);
    final historic = billForm(
      {vendor.id.value: vendor.name},
      choices,
      preferences: preferences,
      existing: old,
    );
    expect(historic.lineFields, containsAll(['Quantity', 'Rate', 'Discount']));
    final values = {
      ...billFormValues(old),
      'Tax Mode': 'Exclusive',
      '_lines': [
        {
          '_lineId': old.lines.single.id.value,
          'Account': account.account.id.value,
          'Description': 'Exact basic purchase',
          'Amount': '1,234,567.89',
          // Retained inactive input cannot replace the visible Amount.
          'Quantity': '9',
          'Rate': '99',
          'Discount': '0',
          'Tax Rate (%)': '0',
        },
      ],
    };
    // The live form serializes only visible pricing fields. Exercise the same
    // boundary instead of sending contradictory Amount and Rate modes.
    final submitted = {
      ...values,
      '_lines': [
        for (final raw in values['_lines'] as List)
          {
            for (final entry in (raw as Map<String, String>).entries)
              if (!const {'Quantity', 'Rate', 'Amount'}.contains(entry.key) ||
                  basic.lineFields!.contains(entry.key))
                entry.key: entry.value,
          },
      ],
    };
    final bill = billFromForm(
      submitted,
      metadata: old.metadata,
      vendor: vendor,
      purchaseAccountIds: choices.keys.toSet(),
    );
    expect(bill.total.minorUnits, 123456789);
    expect(bill.lines.single.quantity, SalesQuantity.fromInt(1));
    expect(bill.lines.single.rate.minorUnits, 123456789);
    w.saveBillDraft(bill, expectedRevision: 0);
    expect(
      w.database.readBillDraft(w.identity.businessId, bill.id)!.toJson(),
      bill.toJson(),
    );
  });

  test('explicit bill tax modes round-trip without inventing a mode for legacy sources', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, account) = await setupBill(w);
    final old = billFixture(
      w,
      vendor,
      account.account.id,
      attachments: const [],
    );
    expect(old.taxMode, isNull);
    expect(
      PurchaseBillDraft.fromJson(jsonDecode(jsonEncode(old.toJson()))).toJson(),
      old.toJson(),
    );
    for (final mode in ['Exclusive', 'Inclusive']) {
      final values = billFormValues(old);
      values['Tax Mode'] = mode;
      final lines = values['_lines'] as List;
      (lines.single as Map)['Tax Rate (%)'] =
          mode == 'Exclusive' || mode == 'Inclusive' ? '8' : '0';
      final bill = billFromForm(
        values,
        metadata: old.metadata,
        vendor: vendor,
        purchaseAccountIds: {account.account.id.value},
        existing: old,
      );
      final restored = PurchaseBillDraft.fromJson(
        jsonDecode(jsonEncode(bill.toJson())),
      );
      expect(restored.taxMode, mode);
      expect(restored.toJson(), bill.toJson());
      expect(restored.total.minorUnits, mode == 'Exclusive' ? 15120 : 14000);
      final bad = jsonDecode(jsonEncode(bill.toJson())) as Map<String, dynamic>;
      bad['taxMode'] = mode == 'Inclusive' ? 'Exclusive' : 'Inclusive';
      expect(() => PurchaseBillDraft.fromJson(bad), throwsFormatException);
    }
    final values = billFormValues(old);
    expect(
      () => billFromForm(
        values,
        metadata: old.metadata,
        vendor: vendor,
        purchaseAccountIds: {account.account.id.value},
      ),
      throwsFormatException,
    );
  });

  test('vendor currency and monthly terms resolve exactly and invalid account/evidence selections reject', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final (vendor, account) = await setupBill(w);
    final old = billFixture(
      w,
      vendor,
      account.account.id,
      attachments: const [],
    );
    final values = {
      ...billFormValues(old),
      'Currency': 'Use Counterparty Default',
      'Payment Terms': 'Use Vendor Default',
      'Due Date': '',
      'Tax Mode': 'Exclusive',
    };
    PurchaseBillDraft parse() => billFromForm(
      values,
      metadata: old.metadata,
      vendor: vendor,
      purchaseAccountIds: {account.account.id.value},
      existing: old,
    );
    expect(parse().total.currency, 'SGD');
    expect(parse().total.minorUnits, 15120);
    expect(parse().bill.dueDate, DateTime.utc(2026, 9, 30));
    expect(parse().bill.terms.dayOfMonth, 31);
    final line = (values['_lines'] as List).single as Map;
    line['Account'] = EntityId.random().value;
    expect(parse, throwsStateError);
    line['Account'] = account.account.id.value;
    values['_files'] = ['missing.pdf'];
    expect(parse, throwsStateError);
    values['_files'] = <String>[];
    values['Tax Mode'] = 'Exempt';
    expect(parse, throwsFormatException);
  });
}
