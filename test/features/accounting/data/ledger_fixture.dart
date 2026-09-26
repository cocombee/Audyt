import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';

Future<void> seedLedger(
  LocalAccountingDatabase db,
  StoredJournalEntry draft,
) async {
  await db.configureLedger(
    businessId: draft.metadata.businessId,
    currencyCode: draft.entry.lines.first.amount.currency,
  );
  for (final line in draft.entry.lines) {
    if (await db.getAccount(line.accountId) != null) continue;
    await db.saveAccount(
      StoredAccount(
        account: Account.create(
          id: line.accountId,
          code: line.accountId.value,
          name: 'Fixture Account',
          type: AccountType.asset,
        ),
        metadata: RecordMetadata.initial(
          recordId: line.accountId,
          businessId: draft.metadata.businessId,
          originDeviceId: draft.metadata.originDeviceId,
          createdAt: draft.metadata.createdAt,
        ),
      ),
    );
  }
}

Future<StoredJournalEntry> approveFixture(
  LocalAccountingDatabase db,
  StoredJournalEntry draft,
) async {
  await seedLedger(db, draft);
  await db.save(draft);
  return db.approve(
    JournalApproval(
      requestId: draft.entry.id,
      businessId: draft.metadata.businessId,
      journalId: draft.entry.id,
      expectedRevision: draft.metadata.revision,
      actorId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-000000000099'),
      approvedAt: draft.metadata.updatedAt.add(const Duration(seconds: 1)),
    ),
  );
}
