import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/account_reconciliation.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bank_statement_import_test.dart' show parse;

final class Fixture {
  late Directory dir;
  late AccountingWorkspace w;
  late EntityId bank;
  late EntityId expense;
  String get path => '${dir.path}/ledger.sqlite';
  EntityId get business => w.identity.businessId;

  Future<void> open({bool liability = false}) async {
    dir = Directory.systemTemp.createTempSync('account-period-review-');
    w = await AccountingWorkspace.open(path);
    await w.createAccount(
      code: '1000',
      name: 'Fictional Bank',
      type: liability ? AccountType.liability : AccountType.asset,
    );
    await w.createAccount(
      code: '5000',
      name: 'Fictional Supplies',
      type: AccountType.expense,
    );
    final accounts = await w.accounts();
    bank = accounts.singleWhere((a) => a.account.code == '1000').account.id;
    expense = accounts.singleWhere((a) => a.account.code == '5000').account.id;
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Fictional Bank',
        type: liability ? PaymentAccountType.card : PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    w.database.linkPaymentLedgerAccount(business, 'bank', bank);
    addTearDown(() {
      w.dispose();
      dir.deleteSync(recursive: true);
    });
  }

  Future<EntityId> post(
    int month,
    int day,
    int signedMinor, {
    bool approve = true,
  }) async {
    final before = (await w.journals()).map((j) => j.entry.id).toSet();
    final amount = Money.fromMinor(signedMinor.abs(), 'MYR');
    await w.saveJournal(
      date: DateTime.utc(2026, month, day),
      memo: 'Fictional $month/$day',
      lines: [
        if (signedMinor > 0)
          JournalLine.debit(accountId: bank, amount: amount)
        else
          JournalLine.credit(accountId: bank, amount: amount),
        if (signedMinor > 0)
          JournalLine.credit(accountId: expense, amount: amount)
        else
          JournalLine.debit(accountId: expense, amount: amount),
      ],
    );
    final draft = (await w.journals()).singleWhere(
      (j) => !before.contains(j.entry.id),
    );
    if (approve) {
      await w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: business,
          journalId: draft.entry.id,
          expectedRevision: draft.metadata.revision,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.now(),
        ),
      );
    }
    return draft.entry.id;
  }

  AccountReconciliationSnapshot review({
    int month = 9,
    int startDay = 1,
    int opening = 10000,
    int closing = 9000,
    Set<String> selected = const {},
    Set<String> outstanding = const {},
    EntityId? scope,
    String payment = 'bank',
    String currency = 'MYR',
  }) => w.database.prepareAccountReconciliation(
    businessId: scope ?? business,
    paymentAccountId: payment,
    startsOn: DateTime.utc(2026, month, startDay),
    endsOn: DateTime.utc(2026, month + 1, 0),
    openingBalance: Money.fromMinor(opening, currency),
    closingBalance: Money.fromMinor(closing, currency),
    selectedMovementIds: selected,
    openingOutstandingIds: outstanding,
  );

  Future<EntityId> approveImportedSeptember(EntityId journal) async {
    final statement = w.database.importBankStatement(
      id: EntityId.random(),
      businessId: business,
      paymentAccountId: 'bank',
      importedAt: DateTime.now(),
      statement: parse(
        'Date,Description,Amount\n2026-09-02,Fictional supplies,-10.00',
      ),
    );
    w.database.acceptStatementMatch(
      businessId: business,
      statementId: statement,
      sourceRow: 2,
      journalId: journal,
      lineIndex: 0,
      actorId: w.identity.ownerId,
      acceptedAt: DateTime.now(),
    );
    final completion = EntityId.random();
    w.database.approveStatementReconciliation(
      requestId: completion,
      businessId: business,
      statementId: statement,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.now(),
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(9000, 'MYR'),
      expectedAcceptanceIds: {
        2: w.database.statementMatchAcceptanceId(business, statement, 2)!,
      },
      expectedPreviousId: null,
      firstOpeningEvidence: 'Fictional verified opening',
    );
    return completion;
  }
}

void main() {
  test('actual posted ledger clears without imports and remains read-only across restart', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final payment = await f.post(9, 2, -1000);
    final outstanding = await f.post(9, 3, 500);
    await f.post(10, 1, 250);
    await f.post(9, 4, -250, approve: false);
    final at = DateTime.utc(2026, 10, 1);
    final original = f.w.database.exportDataArchive(f.business, at);
    final result = f.review(selected: {'${payment.value}:0'});
    expect(result.reviewAgrees, isTrue);
    expect(result.review.outstanding.single.id, '${outstanding.value}:0');
    expect(result.ledgerMovements, hasLength(3));
    expect(() => result.ledgerMovements.clear(), throwsUnsupportedError);
    expect(f.w.database.exportDataArchive(f.business, at), original);
    final raw = sqlite3.open(f.path);
    expect(
      raw
          .select('SELECT COUNT(*) AS n FROM bank_statement_imports')
          .single['n'],
      0,
    );
    expect(
      raw.select('PRAGMA user_version').single['user_version'],
      LocalAccountingDatabase.schemaVersion,
    );
    raw.dispose();
    f.w.dispose();
    f.w = await AccountingWorkspace.open(f.path);
    final reopened = f.review(selected: {'${payment.value}:0'});
    expect(reopened.reviewAgrees, isTrue);
    expect(reopened.review.clearedBalance, result.review.clearedBalance);
  });
  test(
    'opening outstanding entries remain selectable without double counting',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 30, 10000);
      final old = await f.post(8, 31, -1000);
      final result = f.review(
        outstanding: {'${old.value}:0'},
        selected: {'${old.value}:0'},
      );
      expect(result.recordedOpening, Money.fromMinor(10000, 'MYR'));
      expect(result.reviewAgrees, isTrue);
      expect(result.review.selected.single.id, '${old.value}:0');
      expect(() => f.review(outstanding: {'unknown'}), throwsStateError);
      expect(
        f
            .review(
              opening: 9999,
              outstanding: {'${old.value}:0'},
              selected: {'${old.value}:0'},
            )
            .reviewAgrees,
        isFalse,
      );
    },
  );
  test(
    'account/company/currency/link boundaries reject foreign review',
    () async {
      final f = Fixture();
      await f.open();
      expect(() => f.review(scope: EntityId.random()), throwsStateError);
      expect(() => f.review(payment: 'missing'), throwsStateError);
      expect(() => f.review(currency: 'USD'), throwsArgumentError);
      f.w.savePaymentAccount(
        PaymentAccount.create(
          id: 'unlinked',
          name: 'Fictional Unlinked',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      expect(() => f.review(payment: 'unlinked'), throwsStateError);
      await f.w.createAccount(
        code: '1001',
        name: 'Fictional Other Bank',
        type: AccountType.asset,
      );
      final other = (await f.w.accounts())
          .singleWhere((a) => a.account.code == '1001')
          .account
          .id;
      f.w.savePaymentAccount(
        PaymentAccount.create(
          id: 'other',
          name: 'Fictional Other Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      f.w.database.linkPaymentLedgerAccount(f.business, 'other', other);
      await f.post(9, 2, -1000);
      expect(
        f.review(payment: 'other', opening: 0, closing: 0).ledgerMovements,
        isEmpty,
      );
      expect(
        f
            .review(
              payment: 'other',
              opening: 0,
              closing: 0,
              selected: {'foreign:0'},
            )
            .reviewAgrees,
        isFalse,
      );
    },
  );
  test(
    'credit-card liability sign follows existing reconciliation owner',
    () async {
      final f = Fixture();
      await f.open(liability: true);
      final charge = await f.post(9, 2, -1000);
      final result = f.review(
        opening: 0,
        closing: 1000,
        selected: {'${charge.value}:0'},
      );
      expect(result.reviewAgrees, isTrue);
      expect(result.review.clearedMovement, Money.fromMinor(1000, 'MYR'));
    },
  );
  test('imported predecessor fixes next start/opening and excludes already cleared movements', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final september = await f.post(9, 2, -1000);
    final carried = await f.post(9, 3, -500);
    final completion = await f.approveImportedSeptember(september);
    final october = await f.post(10, 2, -1000);
    final result = f.review(
      month: 10,
      opening: 9000,
      closing: 7500,
      selected: {'${carried.value}:0', '${october.value}:0'},
    );
    expect(result.previousId, completion.value);
    expect(result.reviewAgrees, isTrue);
    expect(result.requiredStart, DateTime.utc(2026, 10, 1));
    expect(result.review.selected, hasLength(2));
    expect(
      f
          .review(
            month: 10,
            opening: 9000,
            closing: 9000,
            selected: {'${september.value}:0'},
          )
          .review
          .unresolved,
      {'${september.value}:0'},
    );
    expect(
      f
          .review(month: 10, startDay: 2, opening: 9000, closing: 9000)
          .periodContinues,
      isFalse,
    );
    expect(
      f.review(month: 10, opening: 8000, closing: 8000).reviewAgrees,
      isFalse,
    );
    expect(
      () => f.review(month: 10, outstanding: {'${carried.value}:0'}),
      throwsStateError,
    );
  });
  test('new backdated posted ledger evidence invalidates a prior account-period review', () async {
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final september = await f.post(9, 2, -1000);
    await f.approveImportedSeptember(september);
    expect(
      f.review(month: 10, opening: 9000, closing: 9000).reviewAgrees,
      isTrue,
    );
    await f.post(9, 4, 250);
    final changed = f.review(month: 10, opening: 9000, closing: 9000);
    expect(changed.review.balancesAndSelectionAgree, isTrue);
    expect(changed.previousLedgerUnchanged, isFalse);
    expect(changed.reviewAgrees, isFalse);
  });
}
