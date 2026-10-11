import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Fixture {
  _Fixture(this.directory, this.workspace, this.cash, this.other, this.cost);

  final Directory directory;
  AccountingWorkspace workspace;
  final EntityId cash;
  final EntityId other;
  final EntityId cost;

  String get path => '${directory.path}/ledger.sqlite';
  EntityId get business => workspace.identity.businessId;

  static Future<_Fixture> open() async {
    final directory = Directory.systemTemp.createTempSync(
      'expense-initial-credit-',
    );
    final workspace = await AccountingWorkspace.open(
      '${directory.path}/ledger.sqlite',
    );
    final cash = await workspace.createAccount(
      code: '1000',
      name: 'Fictional Cash',
      type: AccountType.asset,
    );
    final other = await workspace.createAccount(
      code: '1010',
      name: 'Fictional Other Bank',
      type: AccountType.asset,
    );
    final cost = await workspace.createAccount(
      code: '5000',
      name: 'Fictional Supplies',
      type: AccountType.expense,
    );
    for (final (id, name) in [
      ('cash', 'Fictional Cash'),
      ('other', 'Fictional Other Bank'),
      ('unlinked', 'Fictional Unlinked Cash'),
    ]) {
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: id,
          name: name,
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
    }
    workspace.database.linkPaymentLedgerAccount(
      workspace.identity.businessId,
      'cash',
      cash,
    );
    workspace.database.linkPaymentLedgerAccount(
      workspace.identity.businessId,
      'other',
      other,
    );
    return _Fixture(directory, workspace, cash, other, cost);
  }

  void dispose() {
    workspace.dispose();
    directory.deleteSync(recursive: true);
  }

  RecordExpenseDraft draft(String submission, {String? paymentAccountId}) =>
      RecordExpenseDraft(
        submissionId: submission,
        amount: '25.50',
        date: '13-09-2026',
        payee: 'Fictional Stationery Shop',
        paymentAccount: switch (paymentAccountId) {
          'cash' => 'Fictional Cash',
          'other' => 'Fictional Other Bank',
          'unlinked' => 'Fictional Unlinked Cash',
          _ => 'Historical Free Text Cash',
        },
        paymentAccountId: paymentAccountId,
        category: 'Office Operations',
        tax: 'Review Needed',
        customer: '',
        billable: false,
        dimensions: '',
        itemOrSplitDetails: '',
        notes: '',
      );

  Future<EntityId> journal(List<(EntityId, String)> credits) async =>
      workspace.saveJournal(
        date: DateTime.utc(2026, 9, 13),
        memo: 'Fictional reviewed Expense',
        lines: [
          JournalLine.debit(
            accountId: cost,
            amount: Money.fromDecimal('25.50', 'MYR'),
          ),
          for (final (account, amount) in credits)
            JournalLine.credit(
              accountId: account,
              amount: Money.fromDecimal(amount, 'MYR'),
            ),
        ],
      );

  Future<JournalApproval> approval(EntityId expense, EntityId journal) async {
    final reviewed = (await workspace.database.getJournal(journal))!;
    return JournalApproval(
      requestId: EntityId.random(),
      businessId: business,
      journalId: journal,
      expectedRevision: reviewed.metadata.revision,
      actorId: workspace.identity.ownerId,
      approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
      expenseIntakeId: expense,
    );
  }

  String archive() =>
      workspace.database.exportDataArchive(business, DateTime.utc(2026, 10, 1));
}

void main() {
  test(
    'wrong linked credit rejects the whole initial approval transaction',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.dispose);
      final expense = await f.workspace.saveExpenseIntake(
        f.draft('wrong-credit', paymentAccountId: 'cash'),
      );
      final journal = await f.journal([(f.other, '25.50')]);
      final command = await f.approval(expense, journal);
      final before = f.archive();

      await expectLater(
        f.workspace.approveJournal(command),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('linked payment account'),
          ),
        ),
      );

      expect(f.archive(), before);
      expect((await f.workspace.expense(expense))!.summary.journalId, isNull);
      expect(
        (await f.workspace.database.getJournal(journal))!.entry.state,
        JournalEntryState.draft,
      );
      expect(
        (await f.workspace.database.auditEvents(f.business))
            .where((event) => event['kind'] == 'journal_posted'),
        isEmpty,
      );
    },
  );

  test(
    'all linked credits can be split across rows and retry survives restart',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.dispose);
      final expense = await f.workspace.saveExpenseIntake(
        f.draft('correct-split-credit', paymentAccountId: 'cash'),
      );
      final journal = await f.journal([(f.cash, '10.00'), (f.cash, '15.50')]);
      final command = await f.approval(expense, journal);

      final posted = await f.workspace.approveJournal(command);
      expect(posted.entry.state, JournalEntryState.posted);
      final committed = f.archive();
      expect((await f.workspace.approveJournal(command)).entry.id, journal);
      expect(f.archive(), committed);

      f.workspace.dispose();
      f.workspace = await AccountingWorkspace.open(f.path);
      expect((await f.workspace.expense(expense))!.summary.journalId, journal);
      expect(
        (await f.workspace.database.getJournal(journal))!.entry.state,
        JournalEntryState.posted,
      );
      expect(
        (await f.workspace.database.auditEvents(f.business))
            .where((event) => event['kind'] == 'journal_posted'),
        hasLength(1),
      );
    },
  );

  test(
    'a matching partial credit cannot hide a credit to another ledger',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.dispose);
      final expense = await f.workspace.saveExpenseIntake(
        f.draft('mixed-credit', paymentAccountId: 'cash'),
      );
      final journal = await f.journal([(f.cash, '20.00'), (f.other, '5.50')]);
      final command = await f.approval(expense, journal);
      final before = f.archive();

      await expectLater(
        f.workspace.approveJournal(command),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('linked payment account'),
          ),
        ),
      );

      expect(f.archive(), before);
      expect((await f.workspace.expense(expense))!.summary.journalId, isNull);
    },
  );

  test('approval reads the saved payment account again after review', () async {
    final f = await _Fixture.open();
    addTearDown(f.dispose);
    final original = f.draft('changed-account', paymentAccountId: 'cash');
    final expense = await f.workspace.saveExpenseIntake(original);
    final journal = await f.journal([(f.cash, '25.50')]);
    final command = await f.approval(expense, journal);
    final saved = (await f.workspace.expense(expense))!;
    final changed = RecordExpenseDraft.fromJson({
      ...saved.draft.toJson(),
      'paymentAccountId': 'other',
      'paymentAccount': 'Fictional Other Bank',
    });
    await f.workspace.updateExpenseIntake(
      id: expense,
      expected: saved.draft,
      replacement: changed,
      expectedRevision: saved.summary.revision,
    );
    final before = f.archive();

    await expectLater(
      f.workspace.approveJournal(command),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('linked payment account'),
        ),
      ),
    );

    expect(f.archive(), before);
    expect(
      (await f.workspace.expense(expense))!.draft.paymentAccountId,
      'other',
    );
    expect((await f.workspace.expense(expense))!.summary.journalId, isNull);
  });

  test(
    'free-text and unlinked saved payment accounts retain initial approval',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.dispose);
      for (final (submission, paymentId) in [
        ('historical-free-text', null),
        ('unlinked-account', 'unlinked'),
      ]) {
        final expense = await f.workspace.saveExpenseIntake(
          f.draft(submission, paymentAccountId: paymentId),
        );
        final journal = await f.journal([(f.cash, '25.50')]);
        final command = await f.approval(expense, journal);

        await f.workspace.approveJournal(command);

        expect(
          (await f.workspace.expense(expense))!.summary.journalId,
          journal,
        );
      }
    },
  );
}
