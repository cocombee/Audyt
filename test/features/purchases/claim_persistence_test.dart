import '../../app/restored_page_routes_test.dart' show tables;

import 'package:audyt/features/accounting/domain/account.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/claim.dart';

void main() {
  test('second claim write failure rolls back entire payment batch and permits retry', () async {
    final dir = Directory.systemTemp.createTempSync('claim-batch-rollback-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final first = ClaimStore.demo().all.first;
    final second = Claim.fromJson({
      ...first.toJson(),
      'id': EntityId.random().value,
    });
    for (final claim in [first, second]) {
      workspace.claims.saveDraft(claim);
      workspace.claims.submit(claim.id);
    }
    final accounts = await _recognize(workspace, [first, second]);
    final reviewed = workspace.claims.all;
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER fail_second_claim BEFORE UPDATE ON claims WHEN NEW.id = '${second.id.value}' BEGIN SELECT RAISE(ABORT,'simulated second write failure'); END",
    );
    final batchId = EntityId.random();
    final paidAt = DateTime.now().toUtc();
    void pay() => workspace.settleClaims(
      reviewedClaims: reviewed,
      requestId: batchId,
      bankAccountId: accounts['1000']!,
      paidAt: paidAt,
      paymentReference: 'BATCH-001',
    );
    final beforePay = tables(workspace);
    expect(pay, throwsA(isA<SqliteException>()));
    expect(tables(workspace), beforePay);
    expect(
      workspace.claims.all.every((c) => c.status == ClaimStatus.approved),
      isTrue,
    );
    final reopened = workspace.database.openClaimStore(
      workspace.identity.businessId,
    );
    expect(reopened.all.every((c) => c.status == ClaimStatus.approved), isTrue);
    raw.execute('DROP TRIGGER fail_second_claim');
    raw.dispose();
    pay();
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    final retried = workspace.settleClaims(
      reviewedClaims: reviewed.reversed.toList(),
      bankAccountId: accounts['1000']!,
      requestId: batchId,
      paidAt: paidAt,
      paymentReference: 'BATCH-001',
    );
    expect(retried.claimIds.toSet(), {first.id, second.id});
    expect(retried.reference, 'BATCH-001');
    expect(
      () => workspace.settleClaims(
        reviewedClaims: reviewed,
        bankAccountId: accounts['1000']!,
        requestId: batchId,
        paidAt: paidAt,
        paymentReference: 'DIFFERENT',
      ),
      throwsStateError,
    );
    expect(
      () => workspace.settleClaims(
        reviewedClaims: [reviewed.first],
        bankAccountId: accounts['1000']!,
        requestId: batchId,
        paidAt: paidAt,
        paymentReference: 'BATCH-001',
      ),
      throwsStateError,
    );
    expect(
      () => workspace.settleClaims(
        reviewedClaims: reviewed,
        bankAccountId: accounts['1000']!,
        requestId: batchId,
        paidAt: paidAt.add(const Duration(seconds: 1)),
        paymentReference: 'BATCH-001',
      ),
      throwsStateError,
    );
    expect(workspace.claims.all, hasLength(2));
    expect(
      workspace.claims.all.every(
        (c) =>
            c.status == ClaimStatus.paid &&
            c.paymentBatchId == batchId &&
            c.paidAt == paidAt,
      ),
      isTrue,
    );
  });
  test(
    'actual settlements cannot append claims to a committed batch',
    () async {
      final dir = Directory.systemTemp.createTempSync('claim-batch-identity-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      final first = ClaimStore.demo().all.first;
      final second = Claim.fromJson({
        ...first.toJson(),
        'id': EntityId.random().value,
      });
      for (final claim in [first, second]) {
        workspace.claims.saveAndSubmit(claim);
      }
      final accounts = await _recognize(workspace, [first, second]);
      final reviewed = workspace.claims.all;
      final batchId = EntityId.random();
      final paidAt = DateTime.utc(2026, 9, 13);
      workspace.settleClaims(
        reviewedClaims: [reviewed.first],
        requestId: batchId,
        bankAccountId: accounts['1000']!,
        paidAt: paidAt,
        paymentReference: 'FIRST',
      );
      final beforeRetry = workspace.database.exportDataArchive(
        workspace.identity.businessId,
        paidAt,
      );
      expect(
        () => workspace.settleClaims(
          reviewedClaims: [reviewed.last],
          requestId: batchId,
          bankAccountId: accounts['1000']!,
          paidAt: paidAt,
          paymentReference: 'FIRST',
        ),
        throwsStateError,
      );
      expect(
        workspace.database.exportDataArchive(
          workspace.identity.businessId,
          paidAt,
        ),
        beforeRetry,
      );
      expect(workspace.claims.byId(second.id)!.status, ClaimStatus.approved);
      workspace.settleClaims(
        reviewedClaims: [reviewed.last],
        requestId: EntityId.random(),
        bankAccountId: accounts['1000']!,
        paidAt: paidAt,
        paymentReference: 'SECOND',
      );
      expect(workspace.claims.byId(second.id)!.status, ClaimStatus.paid);
    },
  );
  test(
    'claims survive restart and stale stores cannot overwrite changes',
    () async {
      final dir = Directory.systemTemp.createTempSync('claim-storage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final claim = ClaimStore.demo().all.first;
      workspace.claims.saveDraft(claim);
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.claims.all.single.toJson(), claim.toJson());
      final stale = workspace.database.openClaimStore(
        workspace.identity.businessId,
      );
      workspace.claims.submit(claim.id);
      expect(() => stale.voidClaim(claim.id), throwsStateError);
      expect(stale.byId(claim.id)!.status, ClaimStatus.draft);
      final restored = workspace.database.openClaimStore(
        workspace.identity.businessId,
      );
      expect(restored.byId(claim.id)!.status, ClaimStatus.submitted);
    },
  );
}

Future<Map<String, EntityId>> _recognize(
  AccountingWorkspace w,
  List<Claim> drafts,
) async {
  for (final item in [
    ('1000', AccountType.asset),
    ('5000', AccountType.expense),
    ('2100', AccountType.liability),
  ]) {
    await w.createAccount(code: item.$1, name: item.$1, type: item.$2);
  }
  final accounts = {
    for (final item in await w.accounts()) item.account.code: item.account.id,
  };
  for (final draft in drafts) {
    w.approveClaim(
      reviewedClaim: w.claims.byId(draft.id)!,
      requestId: EntityId.random(),
      expenseAccountId: accounts['5000']!,
      liabilityAccountId: accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 10),
    );
  }
  return accounts;
}
