import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/legacy_claim_expense_view.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipt_tax_test.dart' show fixture;

void main() {
  test(
    'opening original legacy data does not infer tax, payment or recognition',
    () {
      final store = ClaimStore.demo();
      addTearDown(store.dispose);
      final original = store.all.first;
      final before = original.toJson();
      final view = legacyClaimExpenseView(original);
      expect(view.taxMode, isNull);
      expect(view.lines.single.tax, 'Not Recorded');
      expect(view.claimSource, isNull);
      expect(view.paymentAccount, isEmpty);
      expect(view.amount, original.amount.toDecimalString());
      expect(
        view.attachments.map((a) => a.toJson()),
        original.attachments.map((a) => a.toJson()),
      );
      expect(original.toJson(), before);
      final revised = original.reviseExpense(view);
      expect(revised.legacySource!.toJson(), before);
      expect(
        revised.submissionErrors,
        contains('Review Tax Inclusive or Tax Exclusive before submitting.'),
      );
      expect(() => revised.submit(), throwsA(isA<ClaimValidationException>()));
    },
  );

  test('mixed receipt bases and originals survive save and restart; originals cannot be replaced', () async {
    final directory = Directory.systemTemp.createTempSync(
      'audyt-legacy-expense-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/workspace.sqlite';
    final f = await fixture(path: path);
    final original = f.claim();
    f.w.claims.saveDraft(original);
    final view = legacyClaimExpenseView(original);
    expect(view.amount, original.amount.toDecimalString());
    expect(view.receiptLineBases.values.toSet(), {'Exclusive', 'Inclusive'});
    expect(view.taxTotals!.total, original.amount);
    expect(
      view.lines.map((l) => l.toJson()),
      original.receipts.expand((r) => r.lines.map((l) => l.item.toJson())),
    );
    final revised = original.reviseExpense(view);
    f.w.claims.saveDraft(revised, expectedCurrent: original);
    final next = revised.reviseExpense(
      RecordExpenseDraft.fromJson({
        ...view.toJson(),
        'notes': 'Revised current memo',
      }),
    );
    f.w.claims.saveDraft(next, expectedCurrent: revised);
    expect(next.legacySource!.toJson(), original.toJson());
    final falsified = Claim.fromJson({
      ...next.toJson(),
      'legacySource': {
        ...original.toJson(),
        'businessPurpose': 'Replaced original',
      },
    });
    expect(
      () => f.w.claims.saveDraft(falsified, expectedCurrent: next),
      throwsStateError,
    );
    expect(await f.w.journals(), isEmpty);
    expect(await f.w.expenses(), isEmpty);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 10, 4),
    );
    final recovered = LocalAccountingDatabase.inMemory();
    addTearDown(recovered.close);
    recovered.restoreDataArchive(archive);
    final recoveredClaim = recovered
        .openClaimStore(f.w.identity.businessId)
        .byId(original.id)!;
    expect(
      recoveredClaim.legacySource!.businessPurpose,
      original.businessPurpose,
    );
    expect(
      recoveredClaim.legacySource!.receipts.map((r) => r.toJson()),
      original.receipts.map((r) => r.toJson()),
    );
    expect(
      recoveredClaim.expenseDraft!.receiptLineBases,
      view.receiptLineBases,
    );
    f.w.dispose();
    final reopened = await AccountingWorkspace.open(path);
    addTearDown(reopened.dispose);
    final saved = reopened.claims.byId(original.id)!;
    expect(saved.legacySource!.toJson(), original.toJson());
    expect(saved.expenseDraft!.notes, 'Revised current memo');
    expect(saved.expenseDraft!.receiptLineBases, view.receiptLineBases);
    // The repository must refuse removing retained original evidence.
    final dropped = Claim.fromJson(
      {
        ...saved.toJson(),
        'version': 4,
        'expenseDraft': {
          ...saved.expenseDraft!.toJson(),
          'version': 2,
          'taxMode': 'Exclusive',
          'amount': '186.32',
        }..remove('receiptLineBases'),
        'amountMinor': 18632,
      }..remove('legacySource'),
    );
    expect(
      () => reopened.claims.saveDraft(dropped, expectedCurrent: saved),
      throwsStateError,
    );
  });
}
