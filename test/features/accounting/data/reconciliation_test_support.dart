import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

/// Explicit test fixture: owner contributed MYR100 on 31 August.
Future<void> seedRecordedOpening(
  AccountingWorkspace workspace,
  EntityId bank,
) async {
  await workspace.createAccount(
    code: '3000',
    name: 'Owner Capital',
    type: AccountType.equity,
  );
  final equity = (await workspace.accounts())
      .singleWhere((r) => r.account.code == '3000')
      .account
      .id;
  await workspace.saveJournal(
    date: DateTime.utc(2026, 8, 31),
    memo: 'Owner capital contributed',
    lines: [
      JournalLine.debit(accountId: bank, amount: Money.fromMinor(10000, 'MYR')),
      JournalLine.credit(
        accountId: equity,
        amount: Money.fromMinor(10000, 'MYR'),
      ),
    ],
  );
  final draft = (await workspace.journals()).singleWhere(
    (r) => r.entry.state == JournalEntryState.draft,
  );
  await workspace.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: workspace.identity.businessId,
      journalId: draft.entry.id,
      expectedRevision: draft.metadata.revision,
      actorId: workspace.identity.ownerId,
      approvedAt: DateTime.now(),
    ),
  );
}
