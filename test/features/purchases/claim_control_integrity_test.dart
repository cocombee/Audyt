import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/restored_page_routes_test.dart' show tables;

void main() {
  for (final operation in [
    'approve',
    'pay',
    'new approved',
    'new paid',
    'alter reviewed',
    'alter voided',
  ]) {
    test(
      'connected claims reject $operation without corresponding evidence',
      () async {
        final dir = Directory.systemTemp.createTempSync('claim-control-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        final draft = ClaimStore.demo().all.first;
        w.claims.saveAndSubmit(draft);
        final submitted = w.claims.byId(draft.id)!;
        if (operation == 'alter voided') w.claims.voidClaim(draft.id);
        final before = tables(w);
        final memory = w.claims.all.map((c) => c.toJson()).toList();
        void attempt() {
          switch (operation) {
            case 'approve':
              w.claims.approve(draft.id);
            case 'pay':
              w.claims.markPaid(
                draft.id,
                paymentBatchId: EntityId.random(),
                paidAt: DateTime.utc(2026, 9, 27),
              );
            case 'new approved':
            case 'new paid':
              var forged = Claim.fromJson({
                ...submitted.toJson(),
                'id': EntityId.random().value,
              }).approve();
              if (operation == 'new paid') {
                forged = forged.markPaid(
                  paymentBatchId: EntityId.random(),
                  paidAt: DateTime.utc(2026, 9, 27),
                );
              }
              w.claims.persistChanges!([forged]);
            case 'alter reviewed':
              w.claims.persistChanges!([
                Claim.fromJson({
                  ...submitted.returnForCorrection().toJson(),
                  'vendorName': 'Unreviewed replacement',
                }),
              ]);
            case 'alter voided':
              w.claims.persistChanges!([
                Claim.fromJson({
                  ...w.claims.byId(draft.id)!.toJson(),
                  'amountMinor': 9999,
                }),
              ]);
          }
        }

        expect(attempt, throwsStateError);
        expect(tables(w), before);
        expect(w.claims.all.map((c) => c.toJson()).toList(), memory);
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(tables(w), before);
      },
    );
  }

  test(
    'unposted claim review retains details and new submission needs evidence',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'claim-review-integrity-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      addTearDown(() => w.dispose());
      final draft = ClaimStore.demo().all.first;
      w.claims.saveAndSubmit(draft);
      final submitted = w.claims.byId(draft.id)!;
      final archive = w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 9, 27),
      );
      w.dispose();
      w = await AccountingWorkspace.emptyRestore(
        '${dir.path}/restored.sqlite',
        archive,
      );
      final saved = w.claims.byId(draft.id)!;
      expect(saved.submissionErrors, isNotEmpty);
      final unavailableNew = Claim.fromJson({
        ...saved.toJson(),
        'id': EntityId.random().value,
      });
      final before = tables(w);
      expect(
        () => w.claims.persistChanges!([unavailableNew]),
        throwsStateError,
      );
      expect(tables(w), before);
      final returned = w.claims.returnForCorrection(
        saved.id,
        expectedCurrent: saved,
      );
      expect(returned.status, ClaimStatus.returned);
      expect(returned.vendorName, submitted.vendorName);
      final correction = Claim.fromJson({
        ...returned.toJson(),
        'businessPurpose': 'Corrected pending receipt recovery',
      });
      w.claims.saveDraft(correction, expectedCurrent: returned);
      expect(
        () => w.claims.submit(correction.id),
        throwsA(isA<ClaimValidationException>()),
      );
      final voided = w.claims.voidClaim(
        correction.id,
        expectedCurrent: correction,
      );
      expect(voided.businessPurpose, correction.businessPurpose);
      expect(await w.journals(), isEmpty);
      final finalTables = tables(w);
      w.dispose();
      w = await AccountingWorkspace.open('${dir.path}/restored.sqlite');
      expect(tables(w), finalTables);
      expect(w.claims.byId(draft.id)!.status, ClaimStatus.voided);
    },
  );

  test('Demo approved and paid claims have actual recognition and settlement links', () async {
    final w = await createDemoWorkspace();
    addTearDown(w.dispose);
    final approved = w.claims.all.singleWhere(
      (c) => c.status == ClaimStatus.approved,
    );
    final paid = w.claims.all.singleWhere((c) => c.status == ClaimStatus.paid);
    final expectedExpenseDate = DateTime.utc(
      paid.paidAt!.year,
      paid.paidAt!.month,
      1,
    );
    expect(approved.incurredOn, expectedExpenseDate);
    expect(paid.incurredOn, expectedExpenseDate);
    final data = tables(w);
    List<List<dynamic>> rows(String name) =>
        (data[name]['rows'] as List).cast<List<dynamic>>();
    List<dynamic> columns(String name) => data[name]['columns'] as List;
    final postingColumns = columns('claim_postings');
    final postingIds = rows('claim_postings')
        .map((r) => r[postingColumns.indexOf('claim_id')])
        .toSet();
    expect(postingIds, containsAll([approved.id.value, paid.id.value]));
    final journals = await w.journals();
    for (final claim in [approved, paid]) {
      final recognition = rows('claim_postings').singleWhere(
        (row) => row[postingColumns.indexOf('claim_id')] == claim.id.value,
      );
      final journal = journals.singleWhere(
        (entry) =>
            entry.entry.id.value ==
            recognition[postingColumns.indexOf('journal_id')],
      );
      expect(journal.entry.date, claim.incurredOn);
    }
    expect(rows('claim_settlements'), hasLength(1));
    expect(rows('claim_settlement_allocations'), hasLength(1));
    final source = w.vouchers.sources.singleWhere(
      (s) =>
          s.type == PaymentVoucherSourceType.claimPayment &&
          s.id == paid.id.value,
    );
    expect(source.amount, paid.amount);
    final proof = w.vouchers.loadPaymentEvidence!(
      PaymentVoucher.create(
        id: 'claim-control-proof',
        sourceType: source.type,
        sourceId: source.id,
        payee: source.payee,
        amount: source.amount,
        paymentAccount: 'Demo Bank',
        paymentAccountId: source.paymentAccountId,
        paymentMethod: 'Bank Transfer',
        paymentDate: source.date,
        reference: 'CLAIM PROOF',
      ),
    );
    expect(proof, isNotNull);
    expect(proof.movementAmount, paid.amount);
    expect(proof.paymentDate, paid.paidAt);
  });
}
