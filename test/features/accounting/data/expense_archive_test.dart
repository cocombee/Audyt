import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'expense_intake_test.dart' show draft;
import 'archive_upgrade_test.dart' show body, envelope;

void main() {
  test('removal survives restart and data recovery, retains evidence and hides pending/search', () async {
    final root = Directory.systemTemp.createTempSync('expense-removal-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/books.sqlite';
    var w = await AccountingWorkspace.open(path);
    final evidence = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'original-receipt',
        batchId: 'batch',
        filename: 'receipt.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    final original = draft(attachments: [evidence]);
    final id = await w.saveExpenseIntake(original);
    final at = DateTime.now().toUtc().add(const Duration(seconds: 1));
    int change({
      required bool removed,
      int revision = 1,
      EntityId? actor,
      EntityId? company,
      DateTime? time,
    }) => w.database.setExpenseIntakeArchived(
      businessId: company ?? w.identity.businessId,
      actorId: actor ?? w.identity.ownerId,
      id: id,
      expectedRevision: revision,
      archived: removed,
      changedAt: time ?? at,
    );
    expect(
      () => change(removed: true, actor: EntityId.random()),
      throwsStateError,
    );
    expect(
      () => change(removed: true, company: EntityId.random()),
      throwsStateError,
    );
    expect(() => change(removed: true, revision: 3), throwsStateError);
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER reject_removal_audit BEFORE INSERT ON ledger_audit BEGIN SELECT RAISE(ABORT,'Simulated audit failure'); END",
    );
    expect(() => change(removed: true), throwsA(isA<SqliteException>()));
    expect((await w.expense(id))!.summary.revision, 1);
    raw.execute('DROP TRIGGER reject_removal_audit');
    raw.dispose();
    expect(change(removed: true), 2);
    expect(change(removed: true), 2); // Exact command retry, one audit event.
    expect(await w.expense(id), isNull);
    expect(await w.expenses(), isEmpty);
    expect(
      w.database.searchExpenseIntakes(
        businessId: w.identity.businessId,
        query: 'Stationery',
      ),
      isEmpty,
    );
    expect(
      w.database.searchExpenseIntakes(
        businessId: w.identity.businessId,
        query: 'Ž',
      ),
      isEmpty,
    );
    expect(
      w.database
          .readPendingExpenseIntakes(businessId: w.identity.businessId)
          .count,
      0,
    );
    expect(
      w.database.readExpenseIntakePage(businessId: w.identity.businessId).total,
      0,
    );
    expect(
      w.database.expenseIntakeFilterOptions(w.identity.businessId).categories,
      isEmpty,
    );
    expect(
      w.database
          .readReportQualityCounts(
            businessId: w.identity.businessId,
            from: DateTime.utc(2026, 1, 1),
            through: DateTime.utc(2026, 12, 31),
          )
          .expensesInRange,
      0,
    );
    await expectLater(w.saveExpenseIntake(original), throwsStateError);
    await expectLater(
      w.updateExpenseIntake(
        id: id,
        expected: original,
        replacement: RecordExpenseDraft.fromJson({
          ...original.toJson(),
          'paymentAccountId': 'cash',
        }),
      ),
      throwsStateError,
    );
    final archive = w.database.exportDataArchive(w.identity.businessId, at);
    final tampered = body(archive);
    final expenseTable = (tampered['tables'] as Map)['expense_intakes'] as Map;
    final archivedIndex = (expenseTable['columns'] as List).indexOf(
      'archived_at',
    );
    ((expenseTable['rows'] as List).single as List)[archivedIndex] =
        'invalid-date';
    await expectLater(
      AccountingWorkspace.emptyRestore(
        '${root.path}/invalid.sqlite',
        envelope(tampered),
      ),
      throwsFormatException,
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final saved = (await w.expense(id, includeArchived: true))!;
    expect(saved.summary.isArchived, isTrue);
    expect(saved.summary.revision, 2);
    expect(saved.draft.toJson(), original.toJson());
    expect(saved.draft.attachments.single.originalBytes, [1, 2, 3]);
    expect(await w.database.auditEvents(w.identity.businessId), hasLength(1));
    final recovered = await AccountingWorkspace.emptyRestore(
      '${root.path}/recovered.sqlite',
      archive,
    );
    addTearDown(recovered.dispose);
    expect(await recovered.expenses(), isEmpty);
    final recoveredSaved = (await recovered.expense(
      id,
      includeArchived: true,
    ))!;
    expect(recoveredSaved.summary.revision, 2);
    expect(
      recoveredSaved.draft.attachments.single.originalSha256,
      evidence.originalSha256,
    );
    expect(recoveredSaved.draft.attachments.single.originalBytes, isEmpty);
    recovered.database.setExpenseIntakeArchived(
      businessId: recovered.identity.businessId,
      actorId: recovered.identity.ownerId,
      id: id,
      expectedRevision: 2,
      archived: false,
      changedAt: at.add(const Duration(seconds: 2)),
    );
    expect((await recovered.expenses()).single.id, id);
    expect(
      () => change(
        removed: false,
        revision: 1,
        time: at.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    expect(
      change(
        removed: false,
        revision: 2,
        time: at.add(const Duration(seconds: 1)),
      ),
      3,
    );
    expect((await w.expense(id))!.draft.attachments.single.originalBytes, [
      1,
      2,
      3,
    ]);
    expect(
      w.database
          .readPendingExpenseIntakes(businessId: w.identity.businessId)
          .count,
      1,
    );
    expect(
      w.database
          .searchExpenseIntakes(
            businessId: w.identity.businessId,
            query: 'Stationery',
          )
          .single
          .id,
      id,
    );
    expect(await w.database.auditEvents(w.identity.businessId), hasLength(2));
  });

  test(
    'removal blocks a reviewed posting and posted expense cannot be removed',
    () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      await w.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      await w.createAccount(
        code: '5000',
        name: 'Supplies',
        type: AccountType.expense,
      );
      final accounts = await w.accounts();
      final cash = accounts
          .singleWhere((a) => a.account.code == '1000')
          .account
          .id;
      final cost = accounts
          .singleWhere((a) => a.account.code == '5000')
          .account
          .id;
      final id = await w.saveExpenseIntake(draft());
      await w.saveJournal(
        date: DateTime.utc(2026, 9, 13),
        memo: 'Reviewed expense',
        lines: [
          JournalLine.debit(
            accountId: cost,
            amount: Money.fromDecimal('25.50', 'MYR'),
          ),
          JournalLine.credit(
            accountId: cash,
            amount: Money.fromDecimal('25.50', 'MYR'),
          ),
        ],
      );
      final journal = (await w.journals()).single;
      final command = JournalApproval(
        requestId: EntityId.random(),
        businessId: w.identity.businessId,
        journalId: journal.entry.id,
        expectedRevision: 1,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
        expenseIntakeId: id,
      );
      w.setExpenseIntakeArchived(id: id, expectedRevision: 1, archived: true);
      await expectLater(w.approveJournal(command), throwsStateError);
      expect((await w.journals()).single.entry.state, JournalEntryState.draft);
      w.setExpenseIntakeArchived(id: id, expectedRevision: 2, archived: false);
      await w.approveJournal(command);
      expect(
        w.database.expenseRemovalRestriction(w.identity.businessId, id),
        contains('Posted'),
      );
      expect(
        () => w.setExpenseIntakeArchived(
          id: id,
          expectedRevision: 3,
          archived: true,
        ),
        throwsStateError,
      );
      expect((await w.expense(id))!.summary.isPosted, isTrue);
    },
  );

  test('stale edit cannot remove newer facts and a linked voucher protects its source', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    w.savePaymentAccount(
      PaymentAccount.create(
        id: 'cash',
        name: 'Cash',
        type: PaymentAccountType.cash,
        currencyCode: 'MYR',
      ),
    );
    final original = draft(paymentAccountId: 'cash');
    final id = await w.saveExpenseIntake(original);
    final replacement = RecordExpenseDraft.fromJson({
      ...original.toJson(),
      'notes': 'New reviewed facts',
    });
    await w.updateExpenseIntake(
      id: id,
      expected: original,
      replacement: replacement,
      expectedRevision: 1,
    );
    expect(
      () => w.setExpenseIntakeArchived(
        id: id,
        expectedRevision: 1,
        archived: true,
      ),
      throwsStateError,
    );
    expect((await w.expense(id))!.summary.revision, 2);
    w.vouchers.save(
      PaymentVoucher.create(
        id: 'linked-voucher',
        sourceType: PaymentVoucherSourceType.directExpense,
        sourceId: id.value,
        payee: 'Stationery Shop',
        amount: Money.fromDecimal('25.50', 'MYR'),
        paymentAccount: 'Cash',
        paymentAccountId: 'cash',
        paymentMethod: 'Cash',
        paymentDate: DateTime.utc(2026, 9, 13),
        reference: 'Linked source',
      ),
    );
    expect(
      w.database.expenseRemovalRestriction(w.identity.businessId, id),
      contains('linked voucher'),
    );
    expect(
      () => w.setExpenseIntakeArchived(
        id: id,
        expectedRevision: 2,
        archived: true,
      ),
      throwsStateError,
    );
    expect((await w.expense(id))!.draft.notes, 'New reviewed facts');
  });

  test('active recurring source is protected; paused removal cannot resume or convert twice', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final id = await w.saveExpenseIntake(
      draft(
        recurrence: RecurrenceRule(
          startsOn: DateTime.utc(2026, 9, 13),
          unit: RecurrenceUnit.months,
          every: 1,
          occurrenceCount: 4,
        ),
      ),
    );
    final template = w.database
        .recurringExpenseTemplates(w.identity.businessId)
        .single;
    expect(
      () => w.setExpenseIntakeArchived(
        id: id,
        expectedRevision: 1,
        archived: true,
      ),
      throwsStateError,
    );
    final paused = template.withPaused(true);
    w.database.saveRecurringExpenseTemplate(w.identity.businessId, paused);
    w.setExpenseIntakeArchived(id: id, expectedRevision: 1, archived: true);
    expect(
      () => w.database.saveRecurringExpenseTemplate(
        w.identity.businessId,
        paused.withPaused(false),
      ),
      throwsStateError,
    );
    expect(
      () => w.database.prepareRecurringExpenseOccurrence(
        w.identity.businessId,
        template.id,
        expectedRevision: 2,
        index: 1,
      ),
      throwsStateError,
    );
    expect(
      (await w.database.prepareDueRecurringExpenses(
        w.identity.businessId,
        through: DateTime.utc(2026, 12, 31),
      )).prepared,
      0,
    );
    w.setExpenseIntakeArchived(id: id, expectedRevision: 2, archived: false);
    w.database.saveRecurringExpenseTemplate(
      w.identity.businessId,
      paused.withPaused(false),
    );
    expect(
      (await w.database.prepareDueRecurringExpenses(
        w.identity.businessId,
        through: DateTime.utc(2026, 12, 31),
      )).prepared,
      3,
    );
  });
}
