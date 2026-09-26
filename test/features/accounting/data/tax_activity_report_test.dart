import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/restored_page_routes_test.dart' show tables;

void main() {
  test('unknown claim tax, dated manual movements, company isolation and read-only snapshot', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    for (final account in [
      ('1000', AccountType.asset),
      ('2100', AccountType.liability),
      ('2200', AccountType.liability),
      ('5000', AccountType.expense),
    ]) {
      await w.createAccount(
        code: account.$1,
        name: account.$1,
        type: account.$2,
      );
    }
    final accounts = await w.accounts();
    EntityId account(String code) =>
        accounts.singleWhere((a) => a.account.code == code).account.id;
    w.saveTaxRate(
      CompanyTaxRate(
        id: EntityId.random(),
        name: 'Service Tax',
        percent: '8',
        effectiveFrom: DateTime.utc(2026),
        application: TaxApplication.both,
        accountId: account('2200'),
      ),
    );
    final claim = Claim.fromJson({
      ...ClaimStore.demo().all.first.toJson(),
      'incurredOn': '2026-09-01T00:00:00.000Z',
    });
    w.claims.saveDraft(claim);
    w.claims.submit(claim.id);
    Future<dynamic> report(DateTime start) =>
        w.taxActivity(from: start, through: DateTime.utc(2026, 9, 30));
    expect((await report(DateTime.utc(2026, 9))).rows, isEmpty);
    w.approveClaim(
      requestId: EntityId.random(),
      reviewedClaim: w.claims.byId(claim.id)!,
      expenseAccountId: account('5000'),
      liabilityAccountId: account('2100'),
      approvedAt: DateTime.utc(2026, 9, 14),
    );
    Future<void> manual(DateTime date, int amount) async {
      await w.saveJournal(
        date: date,
        memo: 'Reviewed manual tax balance',
        lines: [
          JournalLine.debit(
            accountId: account(amount < 0 ? '2200' : '1000'),
            amount: Money.fromMinor(amount.abs(), 'MYR'),
          ),
          JournalLine.credit(
            accountId: account(amount < 0 ? '1000' : '2200'),
            amount: Money.fromMinor(amount.abs(), 'MYR'),
          ),
        ],
      );
      final journal = (await w.journals()).singleWhere(
        (j) => j.entry.state == JournalEntryState.draft,
      );
      await w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: journal.entry.id,
          expectedRevision: 1,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
        ),
      );
    }

    await manual(DateTime.utc(2026, 8, 31), 1000);
    await manual(DateTime.utc(2026, 9, 30), -300);
    await manual(DateTime.utc(2026, 10, 1), 500);
    final before = tables(w);
    final activity = await report(DateTime.utc(2026, 9));
    expect(activity.rows, hasLength(1));
    expect(activity.unresolved, hasLength(1));
    expect(
      activity.rows.single.grossMinor,
      BigInt.from(claim.amount.minorUnits),
    );
    expect(
      activity.rows.single.taxMinor,
      isNull,
      reason: 'Missing claim tax is not zero.',
    );
    expect(activity.accounts.single.openingCredit, BigInt.from(1000));
    expect(activity.accounts.single.sourceSalesTax, BigInt.zero);
    expect(activity.accounts.single.otherMovementCredit, BigInt.from(-300));
    expect(activity.accounts.single.closingCredit, BigInt.from(700));
    expect(tables(w), before);
    final foreign = await w.database.readTaxActivity(
      businessId: EntityId.random(),
      currency: 'MYR',
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(foreign.rows, isEmpty);
    expect(foreign.accounts, isEmpty);
    await expectLater(
      w.taxActivity(
        from: DateTime.utc(2026, 10),
        through: DateTime.utc(2026, 9),
      ),
      throwsArgumentError,
    );
    expect(
      (await report(DateTime.utc(2026, 9))).accounts.single.closingCredit,
      BigInt.from(700),
      reason: 'Failed read rolls back and releases the snapshot.',
    );
  });
}
