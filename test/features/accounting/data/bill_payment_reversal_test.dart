import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'bill_settlement_test.dart' show allocation, settlementFixture;

void main() {
  test('linked payment reversal restores both Bills, history and dated controls', () async {
    final root = Directory.systemTemp.createTempSync('audyt-payment-reversal-');
    addTearDown(() => root.deleteSync(recursive: true));
    final (w, ids, _, _) = await settlementFixture(
      '${root.path}/source.sqlite',
    );
    addTearDown(w.dispose);
    final originals = [
      for (final id in ids)
        w.database.readBillPosting(w.identity.businessId, id)!.source.total,
    ];
    final payment = w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [
        allocation(ids[0], originals[0].minorUnits, 100),
        allocation(ids[1], originals[1].minorUnits, 200),
      ],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Supplier batch',
      paidOn: DateTime.utc(2026, 9, 28),
      approvedAt: DateTime.utc(2026, 9, 28, 2),
    );
    final request = EntityId.random();
    EntityId reverse() => w.reverseBillPayment(
      requestId: request,
      sourcePaymentId: payment.id,
      reversedOn: DateTime.utc(2026, 9, 29),
      reason: 'Bank payment duplicated',
      approvedAt: DateTime.utc(2026, 9, 29, 12),
    );
    expect(reverse(), request);
    final saved = tables(w);
    expect(reverse(), request);
    expect(tables(w), saved);
    expect(
      w.database
          .readBillPaymentReversal(w.identity.businessId, payment.id)!
          .journalId,
      request,
    );
    for (var i = 0; i < ids.length; i++) {
      expect(
        w.database.billOutstanding(w.identity.businessId, ids[i]),
        originals[i],
      );
      expect(
        w.database
            .billOutstanding(
              w.identity.businessId,
              ids[i],
              asOf: DateTime.utc(2026, 9, 28),
            )
            .minorUnits,
        originals[i].minorUnits - (i == 0 ? 100 : 200),
      );
    }
    final ageing = w.database.payablesAgeing(
      businessId: w.identity.businessId,
      currency: 'MYR',
      asOf: DateTime.utc(2026, 9, 29),
    );
    expect(
      ageing.outstandingMinor,
      originals.fold(BigInt.zero, (sum, m) => sum + BigInt.from(m.minorUnits)),
    );
    expect(ageing.controls.single.differenceMinor, BigInt.zero);
    expect(
      w.database.payableBillPage(businessId: w.identity.businessId).total,
      2,
    );
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 9, 30),
      ),
    );
    addTearDown(restored.dispose);
    expect(tables(restored), saved);
    expect(
      restored.database.readBillPaymentReversal(
        restored.identity.businessId,
        payment.id,
      ),
      isNotNull,
    );

    // A later payment uses the restored balance, and the archived chain retains
    // both the old payment and its linked correction.
    w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [allocation(ids[0], originals[0].minorUnits, 300)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Corrected supplier payment',
      paidOn: DateTime.utc(2026, 9, 30),
      approvedAt: DateTime.utc(2026, 9, 30, 12),
    );
    final replacementArchive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 1),
    );
    final replacement = await AccountingWorkspace.emptyRestore(
      '${root.path}/replacement.sqlite',
      replacementArchive,
    );
    addTearDown(replacement.dispose);
    expect(
      replacement.database
          .billOutstanding(replacement.identity.businessId, ids[0])
          .minorUnits,
      originals[0].minorUnits - 300,
    );
    expect(tables(replacement), tables(w));

    final second = w.database.readBillPosting(w.identity.businessId, ids[1])!;
    final beforeBillCorrection = tables(w);
    expect(
      () => w.reverseBillRecognition(
        requestId: EntityId.random(),
        reviewedBill: second.source,
        expectedRecognitionJournalId: second.journalId,
        reversedOn: DateTime.utc(2026, 9, 28),
        reason: 'Backdated purchase correction',
        approvedAt: DateTime.utc(2026, 10, 1, 11),
      ),
      throwsStateError,
    );
    expect(tables(w), beforeBillCorrection);
    w.reverseBillRecognition(
      requestId: EntityId.random(),
      reviewedBill: second.source,
      expectedRecognitionJournalId: second.journalId,
      reversedOn: DateTime.utc(2026, 10, 1),
      reason: 'Purchase also duplicated',
      approvedAt: DateTime.utc(2026, 10, 1, 12),
    );
    final finalCopy = await AccountingWorkspace.emptyRestore(
      '${root.path}/final.sqlite',
      w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.utc(2026, 10, 2),
      ),
    );
    addTearDown(finalCopy.dispose);
    expect(tables(finalCopy), tables(w));
    expect(
      finalCopy.database
          .billOutstanding(finalCopy.identity.businessId, ids[1])
          .isZero,
      isTrue,
    );
  });

  for (final failure in [
    'foreign company',
    'foreign actor',
    'wrong payment',
    'closed period',
    'injected storage failure',
  ]) {
    test('payment reversal rejects $failure atomically', () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-payment-reversal-fail-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      final (w, ids, _, _) = await settlementFixture(path);
      addTearDown(w.dispose);
      final total = w.database
          .readBillPosting(w.identity.businessId, ids.first)!
          .source
          .total;
      final payment = w.settleRecognizedBills(
        requestId: EntityId.random(),
        allocations: [allocation(ids.first, total.minorUnits, 100)],
        paymentAccountId: 'fictional-bank',
        paymentReference: 'Original payment',
        paidOn: DateTime.utc(2026, 9, 28),
        approvedAt: DateTime.utc(2026, 9, 28, 2),
      );
      if (failure == 'closed period') {
        await w.database.closeThrough(
          businessId: w.identity.businessId,
          date: DateTime.utc(2026, 9, 29),
          actorId: w.identity.ownerId,
          changedAt: DateTime.utc(2026, 9, 30),
          reason: 'Period review',
        );
      }
      final raw = sqlite3.open(path);
      addTearDown(raw.dispose);
      if (failure == 'injected storage failure') {
        raw.execute(
          "CREATE TRIGGER reject_payment_reversal BEFORE INSERT ON bill_settlement_reversals BEGIN SELECT RAISE(ABORT,'injected failure'); END",
        );
      }
      final before = tables(w);
      expect(
        () => w.database.reverseBillPayment(
          businessId: failure == 'foreign company'
              ? EntityId.random()
              : w.identity.businessId,
          actorId: failure == 'foreign actor'
              ? EntityId.random()
              : w.identity.ownerId,
          requestId: EntityId.random(),
          sourcePaymentId: failure == 'wrong payment'
              ? EntityId.random()
              : payment.id,
          reversedOn: DateTime.utc(2026, 9, 29),
          reason: 'Correct duplicate',
          approvedAt: DateTime.utc(2026, 9, 29, 12),
        ),
        failure == 'injected storage failure'
            ? throwsA(isA<SqliteException>())
            : throwsStateError,
      );
      expect(tables(w), before);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
