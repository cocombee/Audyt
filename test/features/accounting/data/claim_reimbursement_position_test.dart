import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'approved_claim_expense_test.dart' show approve;
import 'claim_receipt_tax_test.dart' show fixture;
import 'claim_recognition_reversal_test.dart' show claimFixture;

void main() {
  test('pending current Expense edits do not alter recognized reimbursement authority', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final journal = approve(f);
    final claim = f.w.claims.all.single;
    final root = (await f.w.expense(journal))!;
    final json = root.draft.toJson();
    final lines = (json['lines'] as List).cast<Map<String, Object?>>();
    lines.first['amount'] = '101';
    json['amount'] = '183.08';
    final replacement = RecordExpenseDraft.fromJson(json);
    f.w.saveExpenseRevision(
      expenseId: journal,
      requestId: EntityId.random(),
      expectedSourceJournalId: journal,
      expectedSourceExpenseRevision: root.summary.revision,
      expectedRevision: 0,
      expected: root.draft,
      replacement: replacement,
      savedAt: DateTime.utc(2026, 9, 16),
    );
    final before = tables(f.w);
    final position = f.w.claimReimbursementPosition(
      claimId: claim.id,
      through: DateTime.utc(2026, 9, 30),
    )!;
    expect(position.recognizedMinor, BigInt.from(18200));
    expect(position.reimbursedMinor, BigInt.zero);
    expect(position.outstandingMinor, BigInt.from(18200));
    expect(position.activity.single.claim.claimantName, claim.claimantName);
    expect((await f.w.expense(journal))!.draft.amount, '183.08');
    expect(tables(f.w), before);
  });

  test('actual reimbursement, dated cutoffs, retry, restart and recovery retain exact source balance', () async {
    final f = await claimFixture();
    final w = f.w;
    final request = EntityId.random();
    void settle() => w.settleClaims(
      reviewedClaims: [f.approved],
      requestId: request,
      bankAccountId: f.bank,
      paymentReference: 'POSITION-PAY',
      paidAt: DateTime.utc(2026, 9, 17),
    );
    settle();
    final saved = tables(w);
    settle();
    expect(tables(w), saved);
    void verify(AccountingWorkspace owner) {
      final before = owner.claimReimbursementPosition(
        claimId: f.approved.id,
        through: DateTime.utc(2026, 9, 16),
      )!;
      expect(
        before.outstandingMinor,
        BigInt.from(f.approved.amount.minorUnits),
      );
      final after = owner.claimReimbursementPosition(
        claimId: f.approved.id,
        through: DateTime.utc(2026, 9, 17),
      )!;
      expect(after.recognizedMinor, BigInt.from(f.approved.amount.minorUnits));
      expect(after.reimbursedMinor, after.recognizedMinor);
      expect(after.outstandingMinor, BigInt.zero);
      expect(
        after.activity.map((e) => e.journalId),
        containsAll([f.source, request]),
      );
    }

    verify(w);
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 18),
    );
    w.dispose();
    final reopened = await AccountingWorkspace.open(f.path);
    addTearDown(reopened.dispose);
    verify(reopened);
    final recovered = await AccountingWorkspace.emptyRestore(
      '${f.path}.restored',
      archive,
    );
    addTearDown(recovered.dispose);
    verify(recovered);
  });

  test('returned recognition and corrected cycle net original and reversal without rewriting history', () async {
    final f = await claimFixture();
    final w = f.w;
    final original = tables(w)['claim_postings'];
    w.reverseClaimRecognition(
      reviewedClaim: f.approved,
      requestId: EntityId.random(),
      expectedRecognitionJournalId: f.source,
      decision: ClaimRecognitionDecision.returnForCorrection,
      reversedOn: DateTime.utc(2026, 9, 15),
      reason: 'Correct actual amount',
      changedAt: DateTime.utc(2026, 9, 15, 12),
    );
    expect(
      w
          .claimReimbursementPosition(
            claimId: f.approved.id,
            through: DateTime.utc(2026, 9, 15),
          )!
          .outstandingMinor,
      BigInt.zero,
    );
    final returned = w.claims.byId(f.approved.id)!;
    final corrected = Claim.fromJson({
      ...returned.toJson(),
      'amountMinor': 21000,
    });
    w.claims.saveDraft(corrected, expectedCurrent: returned);
    w.claims.submit(corrected.id);
    final newJournal = w.approveClaim(
      reviewedClaim: w.claims.byId(corrected.id)!,
      requestId: EntityId.random(),
      expenseAccountId: f.expense,
      liabilityAccountId: f.payable,
      approvedAt: DateTime.utc(2026, 9, 16),
    );
    final position = w.claimReimbursementPosition(
      claimId: corrected.id,
      through: DateTime.utc(2026, 9, 30),
    )!;
    expect(position.recognizedMinor, BigInt.from(21000));
    expect(position.outstandingMinor, BigInt.from(21000));
    expect(position.activity, hasLength(3));
    expect(
      position.activity.map((e) => e.journalId),
      containsAll([f.source, newJournal]),
    );
    expect(tables(w)['claim_postings'], original);
  });

  test('another Claim and manual control balance never belong to this Claim; company scope and reads retained', () async {
    final f = await claimFixture();
    final w = f.w;
    final other = Claim.fromJson({
      ...f.approved.toJson(),
      'id': EntityId.random().value,
      'status': 'draft',
      'amountMinor': 3000,
    });
    w.claims.saveAndSubmit(other);
    w.approveClaim(
      reviewedClaim: w.claims.byId(other.id)!,
      requestId: EntityId.random(),
      expenseAccountId: f.expense,
      liabilityAccountId: f.payable,
      approvedAt: DateTime.utc(2026, 9, 16),
    );
    await w.saveJournal(
      date: DateTime.utc(2026, 9, 16),
      memo: 'Unattributed control balance',
      lines: [
        JournalLine.debit(
          accountId: f.bank,
          amount: Money.fromMinor(9900, 'MYR'),
        ),
        JournalLine.credit(
          accountId: f.payable,
          amount: Money.fromMinor(9900, 'MYR'),
        ),
      ],
    );
    final manual = (await w.journals()).singleWhere(
      (j) => j.entry.state == JournalEntryState.draft,
    );
    await w.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: manual.entry.id,
        expectedRevision: manual.metadata.revision,
        actorId: w.identity.ownerId,
        approvedAt: manual.metadata.updatedAt.add(const Duration(seconds: 1)),
      ),
    );
    final before = tables(w);
    final position = w.claimReimbursementPosition(
      claimId: f.approved.id,
      through: DateTime.utc(2026, 9, 30),
    )!;
    expect(
      position.outstandingMinor,
      BigInt.from(f.approved.amount.minorUnits),
    );
    expect(position.activity, hasLength(1));
    expect(
      w.database.readClaimReimbursementPosition(
        businessId: EntityId.random(),
        claimId: f.approved.id,
        through: DateTime.utc(2026, 9, 30),
      ),
      isNull,
    );
    expect(
      w.claimReimbursementPosition(
        claimId: EntityId.random(),
        through: DateTime.utc(2026, 9, 30),
      ),
      isNull,
    );
    expect(tables(w), before);
  });
}
