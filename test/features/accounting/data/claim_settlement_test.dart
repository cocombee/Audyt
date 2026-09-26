import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test('settlement allocations and journal roll back together, retry and restart', () async {
    final dir = Directory.systemTemp.createTempSync('claim-settlement-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    for (final item in [
      ('5000', AccountType.expense),
      ('2100', AccountType.liability),
      ('1000', AccountType.asset),
    ]) {
      await w.createAccount(code: item.$1, name: item.$1, type: item.$2);
    }
    final accounts = await w.accounts();
    EntityId account(String code) =>
        accounts.firstWhere((a) => a.account.code == code).account.id;
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'claim-bank',
        name: 'Claim Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(
      w.identity.businessId,
      'claim-bank',
      account('1000'),
    );
    final first = ClaimStore.demo().all.first;
    final second = Claim.fromJson({
      ...first.toJson(),
      'id': EntityId.random().value,
    });
    for (final draft in [first, second]) {
      w.claims.saveDraft(draft);
      w.claims.submit(draft.id);
      w.approveClaim(
        requestId: EntityId.random(),
        reviewedClaim: w.claims.byId(draft.id)!,
        expenseAccountId: account('5000'),
        liabilityAccountId: account('2100'),
        approvedAt: DateTime.utc(2026, 9, 14),
      );
    }
    final reviewed = w.database.openClaimStore(w.identity.businessId).all;
    final request = EntityId.random();
    final paidAt = DateTime.utc(2026, 9, 15);
    settle({String reference = 'PAY-001'}) => w.settleClaims(
      requestId: request,
      reviewedClaims: reviewed,
      bankAccountId: account('1000'),
      paymentAccountId: 'claim-bank',
      paymentReference: reference,
      paidAt: paidAt,
    );
    await w.database.closeThrough(
      businessId: w.identity.businessId,
      date: DateTime.utc(2026, 9, 14),
      actorId: w.identity.ownerId,
      changedAt: DateTime.utc(2026, 9, 15),
      reason: 'Boundary test',
    );
    attempt({
      EntityId? actor,
      EntityId? bank,
      DateTime? date,
      List<Claim>? claims,
      EntityId? company,
      String paymentId = 'claim-bank',
    }) => w.database.settleRecognizedClaims(
      businessId: company ?? w.identity.businessId,
      actorId: actor ?? w.identity.ownerId,
      requestId: request,
      reviewedClaims: claims ?? reviewed,
      bankAccountId: bank ?? account('1000'),
      paymentAccountId: paymentId,
      paymentReference: 'PAY-001',
      paidAt: date ?? paidAt,
    );
    expect(() => attempt(paymentId: 'missing'), throwsStateError);
    expect(() => attempt(date: DateTime.utc(2026, 9, 14)), throwsStateError);
    expect(() => attempt(bank: account('5000')), throwsStateError);
    expect(() => attempt(actor: EntityId.random()), throwsStateError);
    expect(() => attempt(company: EntityId.random()), throwsStateError);
    expect(
      () => attempt(claims: [reviewed.first, reviewed.first]),
      throwsArgumentError,
    );
    expect(await w.journals(), hasLength(2));
    expect(w.claims.all.every((c) => c.status == ClaimStatus.approved), isTrue);
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER fail_allocation BEFORE INSERT ON claim_settlement_allocations WHEN NEW.claim_id='${second.id.value}' BEGIN SELECT RAISE(ABORT,'injected allocation failure'); END",
    );
    expect(() => settle(), throwsA(isA<SqliteException>()));
    expect(await w.journals(), hasLength(2));
    expect(
      w.database
          .openClaimStore(w.identity.businessId)
          .all
          .every((c) => c.status == ClaimStatus.approved),
      isTrue,
    );
    expect(raw.select('SELECT * FROM claim_settlements'), isEmpty);
    raw.execute('DROP TRIGGER fail_allocation');
    final batch = settle();
    expect(batch.claims, hasLength(2));
    expect(w.claims.all.every((c) => c.status == ClaimStatus.paid), isTrue);
    expect(await w.journals(), hasLength(3));
    expect(
      raw.select('SELECT * FROM claim_settlement_allocations'),
      hasLength(2),
    );
    final lines = raw.select(
      'SELECT kind,amount_minor FROM journal_lines WHERE journal_id=?',
      [request.value],
    );
    expect(lines.where((r) => r['kind'] == 'debit'), hasLength(2));
    expect(
      lines.where((r) => r['kind'] == 'credit').single['amount_minor'],
      batch.total.minorUnits,
    );
    expect(() => settle(reference: 'PAY-002'), throwsStateError);
    raw.dispose();
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(settle().reference, 'PAY-001');
    expect(await w.journals(), hasLength(3));
    for (final original in await w.journals()) {
      final reversal = original.entry.reversal(
        id: EntityId.random(),
        date: DateTime.utc(2026, 9, 16),
        memo: 'Unlinked reversal',
      );
      await w.database.save(
        StoredJournalEntry(
          entry: reversal,
          metadata: RecordMetadata.initial(
            recordId: reversal.id,
            businessId: w.identity.businessId,
            originDeviceId: w.identity.deviceId,
            createdAt: DateTime.utc(2026, 9, 16),
          ),
        ),
      );
      await expectLater(
        w.database.approve(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: w.identity.businessId,
            journalId: reversal.id,
            expectedRevision: 1,
            actorId: w.identity.ownerId,
            approvedAt: DateTime.utc(2026, 9, 17),
          ),
        ),
        throwsStateError,
      );
    }
    expect(w.claims.all.every((c) => c.status == ClaimStatus.paid), isTrue);
  });
}
