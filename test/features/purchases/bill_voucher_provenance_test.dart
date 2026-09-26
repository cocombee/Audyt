import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/restored_page_routes_test.dart' show tables;
import '../accounting/data/bank_statement_import_test.dart' show parse;
import '../accounting/data/bill_settlement_test.dart'
    show settlementFixture, allocation;
import '../accounting/data/reconciliation_test_support.dart'
    show seedRecordedOpening;

final class BillVoucherFixture {
  BillVoucherFixture(this.w, this.ids, this.first, this.second);
  final AccountingWorkspace w;
  final List<EntityId> ids;
  final StoredBillSettlement first, second;
  static Future<BillVoucherFixture> create(String path) async {
    final (w, ids, bank, payable) = await settlementFixture(path);
    await seedRecordedOpening(w, bank);
    final first = w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [
        allocation(ids[0], 15120, 6000),
        allocation(ids[1], 15120, 4000),
      ],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional voucher batch',
      paidOn: DateTime.utc(2026, 9, 15),
      approvedAt: DateTime.utc(2026, 9, 29),
    );
    final second = w.settleRecognizedBills(
      requestId: EntityId.random(),
      allocations: [allocation(ids[0], 9120, 1000)],
      paymentAccountId: 'fictional-bank',
      paymentReference: 'Fictional later payment',
      paidOn: DateTime.utc(2026, 9, 20),
      approvedAt: DateTime.utc(2026, 9, 30),
    );
    return BillVoucherFixture(w, ids, first, second);
  }

  List<PaymentVoucherSource> get sources => w.vouchers.sources
      .where((s) => s.type == PaymentVoucherSourceType.billSettlement)
      .toList();
  PaymentVoucher voucher(PaymentVoucherSource s, {String? id}) =>
      PaymentVoucher.create(
        id: id ?? EntityId.random().value,
        sourceType: s.type,
        sourceId: s.id,
        payee: s.payee,
        amount: s.amount,
        paymentAccount: 'Fictional Bank',
        paymentAccountId: s.paymentAccountId,
        paymentMethod: 'Bank Transfer',
        paymentDate: s.date,
        reference: 'Fictional voucher',
      );
  PaymentVoucher approve(PaymentVoucher v) {
    w.vouchers.saveAndSubmit(v);
    return w.vouchers.approve(v.id);
  }

  EntityId acceptMatches() {
    final statement = w.database.importBankStatement(
      id: EntityId.random(),
      businessId: w.identity.businessId,
      paymentAccountId: 'fictional-bank',
      importedAt: DateTime.utc(2026, 10, 1),
      statement: parse(
        'Date,Description,Amount\n2026-09-15,Fictional voucher batch,-100.00\n2026-09-20,Fictional later payment,-10.00',
      ),
    );
    for (final entry in [(2, first), (3, second)]) {
      w.database.acceptStatementMatch(
        businessId: w.identity.businessId,
        statementId: statement,
        sourceRow: entry.$1,
        journalId: entry.$2.journalId,
        lineIndex: entry.$2.allocations.length,
        actorId: w.identity.ownerId,
        acceptedAt: DateTime.utc(2026, 10, 1),
      );
    }
    return statement;
  }

  EntityId complete(EntityId statement) {
    final request = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: request,
      businessId: w.identity.businessId,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.utc(2026, 10, 2),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(-1000, 'MYR'),
      expectedAcceptanceIds: {
        for (final row in [2, 3])
          row: w.database.statementMatchAcceptanceId(
            w.identity.businessId,
            statement,
            row,
          )!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence:
          'Fictional owner contribution and statement opening reviewed',
    );
    return request;
  }
}

void main() {
  test('bill vouchers identify each partial allocation and acknowledge the batch bank credit without another payment', () async {
    final root = Directory.systemTemp.createTempSync('audyt-bill-voucher-');
    addTearDown(() => root.deleteSync(recursive: true));
    final f = await BillVoucherFixture.create('${root.path}/source.sqlite');
    addTearDown(f.w.dispose);
    final sources = f.sources;
    expect(sources, hasLength(3));
    expect(sources.map((s) => s.id).toSet(), hasLength(3));
    expect(
      sources
          .where((s) => s.id.startsWith('${f.ids[0].value}/'))
          .map((s) => s.amount.minorUnits)
          .toSet(),
      {6000, 1000},
    );
    expect(sources.map((s) => s.detail), everyElement(contains('BILL-')));
    final originals = [
      for (final id in f.ids)
        f.w.database.readBillDraft(f.w.identity.businessId, id)!.toJson(),
    ];
    final before = tables(f.w);
    for (final s in sources) {
      final v = f.approve(f.voucher(s));
      final paid = f.w.vouchers.recordPayment(v.id);
      final expected = s.id.endsWith(f.first.id.value) ? f.first : f.second;
      expect(paid.paymentEvidence!.journalId, expected.journalId);
      expect(paid.paymentEvidence!.lineIndex, expected.allocations.length);
      expect(paid.paymentEvidence!.movementAmount, expected.total);
      expect(paid.amount, s.amount);
      expect(paid.paidAt, s.date);
      final paidTables = tables(f.w);
      expect(f.w.vouchers.recordPayment(v.id).toJson(), paid.toJson());
      expect(tables(f.w), paidTables);
    }
    final after = tables(f.w);
    for (final name in before.keys.where(
      (name) => !{'payment_vouchers', 'ledger_audit'}.contains(name),
    )) {
      expect(after[name], before[name], reason: name);
    }
    expect([
      for (final id in f.ids)
        f.w.database.readBillDraft(f.w.identity.businessId, id)!.toJson(),
    ], originals);
    final report = await f.w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(report.periodProfit, BigInt.from(-30240));
    expect(report.assets, BigInt.from(-1000));
    expect(report.liabilities, BigInt.from(19240));
    expect(report.isBalanced, isTrue);
  });

  test('foreign, legacy and altered bill voucher sources reject without changing records', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bill-voucher-reject-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final f = await BillVoucherFixture.create('${root.path}/source.sqlite');
    addTearDown(f.w.dispose);
    final source = f.sources.first;
    final candidate = f.voucher(source);
    final before = tables(f.w);
    for (final changes in <Map<String, Object?>>[
      {'sourceId': f.ids[0].value},
      {'sourceId': '${EntityId.random().value}/${f.first.id.value}'},
      {'sourceId': '${f.ids[0].value}/${EntityId.random().value}'},
      {'payee': 'Different fictional payee'},
      {'amountMinor': source.amount.minorUnits + 1},
      {'paymentAccountId': 'missing-bank'},
      {'paymentDate': DateTime.utc(2026, 9, 14).toIso8601String()},
    ]) {
      final bad = PaymentVoucher.fromJson({...candidate.toJson(), ...changes});
      expect(() => f.w.vouchers.save(bad), throwsStateError);
      expect(tables(f.w), before);
    }
    expect(f.w.database.readVoucherSources(EntityId.random()), isEmpty);
  });

  test('bill voucher bank match completion and reopening remain linked through archive restore', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bill-voucher-recovery-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    final f = await BillVoucherFixture.create(path);
    final ids = <String>[];
    for (final s in f.sources) {
      final v = f.approve(f.voucher(s));
      f.w.vouchers.recordPayment(v.id);
      ids.add(v.id);
    }
    final statement = f.acceptMatches();
    final matched = tables(f.w);
    for (final id in ids) {
      expect(() => f.w.vouchers.reconcile(id), throwsStateError);
    }
    expect(tables(f.w), matched);
    final completion = f.complete(statement);
    for (final id in ids) {
      final v = f.w.vouchers.reconcile(id);
      expect(v.reconciliationEvidence!.completionId, completion);
    }
    final before = tables(f.w);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 10, 3),
    );
    f.w.dispose();
    final sourceBytes = File(path).readAsBytesSync();
    final reopened = await AccountingWorkspace.open(path);
    expect(tables(reopened), before);
    reopened.dispose();
    var restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    expect(tables(restored), before);
    restored.dispose();
    restored = await AccountingWorkspace.open('${root.path}/restored.sqlite');
    addTearDown(restored.dispose);
    expect(tables(restored), before);
    expect(
      restored.vouchers.sources.where(
        (s) => s.type == PaymentVoucherSourceType.billSettlement,
      ),
      hasLength(3),
    );
    for (final id in ids) {
      expect(
        restored.vouchers.verification(restored.vouchers.byId(id)!).status,
        PaymentVoucherStatus.reconciled,
      );
    }
    restored.database.reopenStatementReconciliation(
      businessId: restored.identity.businessId,
      completionId: completion.value,
      actorId: restored.identity.ownerId,
      reopenedAt: DateTime.utc(2026, 10, 4),
      reason: 'Fictional bank recheck',
    );
    final changed = tables(restored);
    for (final id in ids) {
      final v = restored.vouchers.byId(id)!;
      expect(
        restored.vouchers.verification(v).status,
        PaymentVoucherStatus.paid,
      );
      expect(v.reconciliationEvidence!.completionId, completion);
      expect(() => restored.vouchers.reconcile(id), throwsStateError);
    }
    expect(tables(restored), changed);
    expect(File(path).readAsBytesSync(), sourceBytes);
  });
}
