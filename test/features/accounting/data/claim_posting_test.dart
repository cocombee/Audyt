import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test(
    'claim recognition is atomic, snapshot bound and restart idempotent',
    () async {
      final dir = Directory.systemTemp.createTempSync('claim-recognition-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      await w.createAccount(
        code: '5000',
        name: 'Office',
        type: AccountType.expense,
      );
      await w.createAccount(
        code: '2100',
        name: 'Claims Payable',
        type: AccountType.liability,
      );
      final accounts = await w.accounts();
      final expense = accounts
          .firstWhere((a) => a.account.code == '5000')
          .account
          .id;
      final liability = accounts
          .firstWhere((a) => a.account.code == '2100')
          .account
          .id;
      final draft = ClaimStore.demo().all.first;
      w.claims.saveDraft(draft);
      w.claims.submit(draft.id);
      final reviewed = w.claims.byId(draft.id)!;
      final request = EntityId.random();
      EntityId post({Claim? claim, EntityId? expenseId, EntityId? actor}) =>
          w.database.approveClaimPosting(
            businessId: w.identity.businessId,
            actorId: actor ?? w.identity.ownerId,
            requestId: request,
            reviewedClaim: claim ?? reviewed,
            expenseAccountId: expenseId ?? expense,
            liabilityAccountId: liability,
            approvedAt: DateTime.utc(2026, 9, 14),
          );
      expect(() => post(claim: draft), throwsStateError);
      expect(() => post(expenseId: liability), throwsStateError);
      expect(() => post(actor: EntityId.random()), throwsStateError);
      expect(await w.journals(), isEmpty);
      expect(
        w.database.openClaimStore(w.identity.businessId).byId(draft.id)!.status,
        ClaimStatus.submitted,
      );
      expect(post(), request);
      expect(post(), request);
      expect(await w.journals(), hasLength(1));
      expect(
        w.database.openClaimStore(w.identity.businessId).byId(draft.id)!.status,
        ClaimStatus.approved,
      );
      w.dispose();
      w = await AccountingWorkspace.open(path);
      addTearDown(w.dispose);
      expect(post(), request);
      expect(await w.journals(), hasLength(1));
      expect(() => post(expenseId: liability), throwsStateError);
    },
  );
}
