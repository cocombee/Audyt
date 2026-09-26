import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/expense_revision.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'approved_claim_expense_test.dart' show approve;
import 'claim_receipt_tax_test.dart' show fixture, Fixture;
import 'archive_upgrade_test.dart' show body, envelope;

final stamp = DateTime.utc(2027, 1, 1);

Future<ClaimExpenseRevisionApproval> prepare(
  Fixture f,
  EntityId expense, {
  String firstAmount = '101',
  Map<String, EntityId>? lineAccounts,
  int step = 0,
}) async {
  final current = (await f.w.expense(expense))!;
  final json = current.draft.toJson();
  final lines = (json['lines'] as List).cast<Map<String, Object?>>();
  lines.first['amount'] = firstAmount;
  final inputs = lines
      .map((l) => ExpenseDraftLine.fromJson(Map<String, dynamic>.from(l)))
      .toList();
  var total = Money.zero(current.draft.currencyCode);
  final costs = <EntityId, Money>{};
  final maps =
      lineAccounts ??
      {
        inputs[0].id: f.accounts['5000']!,
        inputs[1].id: f.accounts['1500']!,
        inputs[2].id: f.accounts['5100']!,
      };
  for (final line in inputs) {
    final gross = line
        .calculation(
          current.draft.currencyCode,
          current.draft.claimSource!.lineBases[line.id]!,
        )
        .total;
    total += gross;
    costs.update(maps[line.id]!, (m) => m + gross, ifAbsent: () => gross);
  }
  json['amount'] = total.toDecimalString();
  final replacement = RecordExpenseDraft.fromJson(json);
  final at = stamp.add(Duration(days: step));
  f.w.saveExpenseRevision(
    expenseId: expense,
    requestId: EntityId.random(),
    expectedSourceJournalId: current.summary.journalId!,
    expectedSourceExpenseRevision: current.summary.revision,
    expectedRevision: current.currentRevision?.revision ?? 0,
    expected: current.draft,
    replacement: replacement,
    savedAt: at,
  );
  final journal = EntityId.random();
  await f.w.database.save(
    StoredJournalEntry(
      entry: JournalEntry.draft(
        id: journal,
        date: DateTime.utc(2026, 9, 14),
        memo: 'Reviewed current Claim cost accounts',
        lines: [
          for (final pair in costs.entries)
            JournalLine.debit(accountId: pair.key, amount: pair.value),
          JournalLine.credit(accountId: f.accounts['2100']!, amount: total),
        ],
      ),
      metadata: RecordMetadata.initial(
        recordId: journal,
        businessId: f.w.identity.businessId,
        originDeviceId: f.w.identity.deviceId,
        createdAt: at.add(const Duration(seconds: 1)),
      ),
    ),
  );
  return ClaimExpenseRevisionApproval(
    approval: ExpenseRevisionApproval(
      requestId: EntityId.random(),
      businessId: f.w.identity.businessId,
      expenseId: expense,
      expectedRevision: (current.currentRevision?.revision ?? 0) + 1,
      expectedSourceJournalId: current.summary.journalId!,
      journalId: journal,
      expectedJournalRevision: 1,
      actorId: f.w.identity.ownerId,
      approvedAt: at.add(const Duration(seconds: 2)),
    ),
    lineAccounts: maps,
  );
}

void main() {
  test('backdated payment retains actual recognition commit order through correction', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final root = approve(f);
    final claim = f.w.claims.all.single;
    f.w.settleClaims(
      reviewedClaims: [claim],
      requestId: EntityId.random(),
      bankAccountId: f.accounts['1000']!,
      paymentReference: 'BACKDATED-PAID',
      paidAt: DateTime.utc(2026, 9, 14),
    );
    final paid = f.w.claims.byId(claim.id)!.toJson();
    expect(
      f.w
          .claimReimbursementPosition(
            claimId: claim.id,
            through: DateTime.utc(2026, 9, 14),
          )!
          .outstandingMinor,
      BigInt.zero,
    );
    final command = await prepare(f, root);
    f.w.approveClaimExpenseRevision(command);
    expect(
      f.w
          .claimReimbursementPosition(
            claimId: claim.id,
            through: DateTime.utc(2027, 1, 31),
          )!
          .outstandingMinor,
      BigInt.from(108),
    );
    expect(f.w.claims.byId(claim.id)!.toJson(), paid);
  });
  test(
    'generic journal reversal cannot bypass current Claim correction lineage',
    () async {
      final f = await fixture();
      addTearDown(f.w.dispose);
      final root = approve(f);
      final command = await prepare(f, root);
      final posting = f.w.approveClaimExpenseRevision(command);
      final original = (await f.w.database.getJournal(posting.journalId))!;
      final id = EntityId.random();
      final at = stamp.add(const Duration(days: 1));
      await f.w.database.save(
        StoredJournalEntry(
          entry: original.entry.reversal(
            id: id,
            date: original.entry.date,
            memo: 'Attempted generic Claim reversal',
          ),
          metadata: RecordMetadata.initial(
            recordId: id,
            businessId: f.w.identity.businessId,
            originDeviceId: f.w.identity.deviceId,
            createdAt: at,
          ),
        ),
      );
      await expectLater(
        f.w.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: f.w.identity.businessId,
            journalId: id,
            expectedRevision: 1,
            actorId: f.w.identity.ownerId,
            approvedAt: at.add(const Duration(seconds: 1)),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Claim corrections'),
          ),
        ),
      );
      expect(
        f.w.activeClaimRecognitionId(f.w.claims.all.single.id),
        posting.journalId,
      );
      expect(
        (await f.w.database.getJournal(id))!.entry.state,
        JournalEntryState.draft,
      );
    },
  );
  test('Claim correction retains original source, row accounts, tax, current balance and exact retry/recovery', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final root = approve(f);
    final claim = f.w.claims.all.single;
    final original = (await f.w.originalExpense(root))!.draft.toJson();
    final command = await prepare(f, root);
    final posting = f.w.approveClaimExpenseRevision(command);
    expect(
      f.w.approveClaimExpenseRevision(command).journalId,
      posting.journalId,
    );
    expect((await f.w.journals()), hasLength(3));
    expect((await f.w.expense(root))!.summary.hasPendingRevision, isFalse);
    expect((await f.w.expense(root))!.draft.amount, '183.08');
    expect((await f.w.originalExpense(root))!.draft.toJson(), original);
    expect(f.w.claims.byId(claim.id)!.toJson(), claim.toJson());
    expect(f.w.activeClaimRecognitionId(claim.id), posting.journalId);
    expect(
      f.w
          .claimReimbursementPosition(
            claimId: claim.id,
            through: DateTime.utc(2027, 1, 31),
          )!
          .outstandingMinor,
      BigInt.from(18308),
    );
    final tax = await f.w.taxActivity(
      from: DateTime.utc(2026),
      through: DateTime.utc(2027, 1, 31),
    );
    expect(tax.rows, hasLength(9));
    expect(
      tax.rows.fold(BigInt.zero, (n, r) => n + r.grossMinor),
      BigInt.from(18308),
    );
    expect(f.w.database.readVoucherSources(f.w.identity.businessId), isEmpty);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      stamp.add(const Duration(days: 1)),
    );
    final copy = LocalAccountingDatabase.inMemory();
    addTearDown(copy.close);
    copy.restoreDataArchive(archive);
    expect(
      copy.activeClaimRecognitionId(f.w.identity.businessId, claim.id),
      posting.journalId,
    );
    expect(
      copy
          .readClaimReimbursementPosition(
            businessId: f.w.identity.businessId,
            claimId: claim.id,
            through: DateTime.utc(2027, 1, 31),
          )!
          .outstandingMinor,
      BigInt.from(18308),
    );
  });
  for (final amount in ['101', '90']) {
    test(
      'paid Claim corrected to $amount retains reimbursement and signed outstanding balance',
      () async {
        final f = await fixture();
        addTearDown(f.w.dispose);
        final root = approve(f);
        final claim = f.w.claims.all.single;
        f.w.settleClaims(
          reviewedClaims: [claim],
          requestId: EntityId.random(),
          bankAccountId: f.accounts['1000']!,
          paymentReference: 'ORIGINAL-PAID',
          paidAt: DateTime.utc(2026, 9, 17),
        );
        final paid = f.w.claims.byId(claim.id)!.toJson();
        final command = await prepare(f, root, firstAmount: amount);
        f.w.approveClaimExpenseRevision(command);
        final pos = f.w.claimReimbursementPosition(
          claimId: claim.id,
          through: DateTime.utc(2027, 1, 31),
        )!;
        expect(pos.reimbursedMinor, BigInt.from(18200));
        expect(
          pos.outstandingMinor,
          BigInt.from(amount == '101' ? 108 : -1080),
        );
        expect(f.w.claims.byId(claim.id)!.toJson(), paid);
        final archive = f.w.database.exportDataArchive(
          f.w.identity.businessId,
          stamp.add(const Duration(days: 1)),
        );
        final copy = LocalAccountingDatabase.inMemory();
        addTearDown(copy.close);
        copy.restoreDataArchive(archive);
        expect(
          copy
              .readClaimReimbursementPosition(
                businessId: f.w.identity.businessId,
                claimId: claim.id,
                through: DateTime.utc(2027, 1, 31),
              )!
              .outstandingMinor,
          pos.outstandingMinor,
        );
      },
    );
  }
  test('second correction uses current financial source and retains the first reviewed accounts', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final root = approve(f);
    final claim = f.w.claims.all.single;
    final first = await prepare(f, root);
    final p1 = f.w.approveClaimExpenseRevision(first);
    final second = await prepare(f, root, firstAmount: '102', step: 1);
    final p2 = f.w.approveClaimExpenseRevision(second);
    expect(p2.sourceJournalId, p1.journalId);
    expect(await f.w.journals(), hasLength(5));
    expect(
      f.w
          .claimReimbursementPosition(
            claimId: claim.id,
            through: DateTime.utc(2027, 1, 31),
          )!
          .outstandingMinor,
      BigInt.from(18416),
    );
    final copy = LocalAccountingDatabase.inMemory();
    addTearDown(copy.close);
    copy.restoreDataArchive(
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        stamp.add(const Duration(days: 3)),
      ),
    );
    expect(
      copy.activeClaimRecognitionId(f.w.identity.businessId, claim.id),
      p2.journalId,
    );
  });
  test('ordinary endpoint, incomplete or changed account review and forged archive evidence cannot approve Claim', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final root = approve(f);
    final command = await prepare(f, root);
    final before = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      stamp.add(const Duration(days: 1)),
    );
    expect(
      () => f.w.approveExpenseRevision(command.approval),
      throwsStateError,
    );
    for (final map in [
      <String, EntityId>{},
      {
        ...command.lineAccounts,
        command.lineAccounts.keys.first: f.accounts['1500']!,
      },
    ]) {
      expect(
        () => f.w.approveClaimExpenseRevision(
          ClaimExpenseRevisionApproval(
            approval: command.approval,
            lineAccounts: map,
          ),
        ),
        throwsStateError,
      );
      expect(
        f.w.database.exportDataArchive(
          f.w.identity.businessId,
          stamp.add(const Duration(days: 1)),
        ),
        before,
      );
    }
    f.w.approveClaimExpenseRevision(command);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      stamp.add(const Duration(days: 1)),
    );
    final data = body(archive);
    final table = (data['tables'] as Map)['expense_revision_postings'] as Map;
    final cols = (table['columns'] as List).cast<String>();
    final row = (table['rows'] as List).single as List;
    final sig = jsonDecode(row[cols.indexOf('signature')] as String) as List;
    (sig[2] as Map)[command.lineAccounts.keys.first] =
        f.accounts['1500']!.value;
    row[cols.indexOf('signature')] = jsonEncode(sig);
    final copy = LocalAccountingDatabase.inMemory();
    addTearDown(copy.close);
    expect(
      () => copy.restoreDataArchive(envelope(data)),
      throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
    );
  });
  test('audit failure rolls back Claim revision recognition and retained reversal together', () async {
    final dir = Directory.systemTemp.createTempSync('claim-expense-atomic-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(path: path);
    addTearDown(f.w.dispose);
    final root = approve(f);
    final command = await prepare(f, root);
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER fail_claim_revision BEFORE INSERT ON ledger_audit WHEN NEW.kind='expense.revision_posted' BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    raw.dispose();
    expect(
      () => f.w.approveClaimExpenseRevision(command),
      throwsA(isA<SqliteException>()),
    );
    expect(await f.w.journals(), hasLength(2));
    expect(f.w.activeClaimRecognitionId(f.w.claims.all.single.id), root);
    expect((await f.w.expense(root))!.summary.hasPendingRevision, isTrue);
  });
}
