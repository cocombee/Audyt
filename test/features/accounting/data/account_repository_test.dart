import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/core/money/money.dart';

EntityId id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
StoredAccount account(
  int n, {
  int business = 90,
  String? code,
  int? parent,
  bool isParent = false,
  AccountStatus status = AccountStatus.active,
  AccountType type = AccountType.asset,
  RecordMetadata? metadata,
}) => StoredAccount(
  account: Account.create(
    id: id(n),
    code: code ?? '$n',
    name: 'Account $n',
    type: type,
    status: status,
    isParent: isParent,
    parentId: parent == null ? null : id(parent),
  ),
  metadata:
      metadata ??
      RecordMetadata.initial(
        recordId: id(n),
        businessId: id(business),
        originDeviceId: id(91),
        createdAt: DateTime.utc(2026, 9, 13),
      ),
);
void main() {
  test(
    'accounts survive restart with hierarchy, status and ownership',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-accounts-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var db = LocalAccountingDatabase.open(path);
      await db.saveAccount(account(1, isParent: true));
      await db.saveAccount(account(2, parent: 1, status: AccountStatus.locked));
      await db.saveAccount(account(3, business: 92));
      db.close();
      db = LocalAccountingDatabase.open(path);
      addTearDown(db.close);
      final records = await db.listAccounts(id(90));
      expect(records.map((r) => r.account.id), [id(1), id(2)]);
      expect(records.last.account.parentId, id(1));
      expect(records.last.account.status, AccountStatus.locked);
      expect(records.last.metadata.revision, 1);
    },
  );
  test(
    'stale updates and ownership changes cannot overwrite an account',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      final original = account(1);
      await db.saveAccount(original);
      final updated = account(
        1,
        code: 'CASH',
        metadata: original.metadata.nextRevision(
          updatedAt: DateTime.utc(2026, 9, 14),
        ),
      );
      await db.saveAccount(updated);
      await expectLater(db.saveAccount(updated), throwsStateError);
      await expectLater(
        db.saveAccount(account(1, business: 92)),
        throwsStateError,
      );
      expect((await db.getAccount(id(1)))!.account.code, 'CASH');
      expect((await db.getAccount(id(1)))!.metadata.businessId, id(90));
    },
  );
  test('code uniqueness is case insensitive and scoped to business', () async {
    final db = LocalAccountingDatabase.inMemory();
    addTearDown(db.close);
    await db.saveAccount(account(1, code: 'Cash'));
    await expectLater(
      db.saveAccount(account(2, code: 'CASH')),
      throwsStateError,
    );
    await db.saveAccount(account(2, code: 'CASH', business: 92));
    final editable = account(3, code: 'Petty');
    await db.saveAccount(editable);
    await expectLater(
      db.saveAccount(
        account(
          3,
          code: 'cAsH',
          metadata: editable.metadata.nextRevision(
            updatedAt: DateTime.utc(2026, 9, 14),
          ),
        ),
      ),
      throwsStateError,
    );
    expect((await db.getAccount(id(3)))!.account.code, 'Petty');
    expect((await db.getAccount(id(3)))!.metadata.revision, 1);
    expect(await db.listAccounts(id(90)), hasLength(2));
  });
  test(
    'parent must exist and share business and type; cycles are rejected',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await expectLater(
        db.saveAccount(account(2, parent: 1)),
        throwsStateError,
      );
      final parent = account(1, isParent: true);
      await db.saveAccount(parent);
      await expectLater(
        db.saveAccount(account(2, parent: 1, business: 92)),
        throwsStateError,
      );
      await expectLater(
        db.saveAccount(account(2, parent: 1, type: AccountType.expense)),
        throwsStateError,
      );
      await db.saveAccount(account(2, isParent: true, parent: 1));
      await expectLater(
        db.saveAccount(
          account(
            1,
            isParent: true,
            parent: 2,
            metadata: parent.metadata.nextRevision(
              updatedAt: DateTime.utc(2026, 9, 14),
            ),
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        db.saveAccount(
          account(
            1,
            status: AccountStatus.archived,
            metadata: parent.metadata.nextRevision(
              updatedAt: DateTime.utc(2026, 9, 14),
            ),
          ),
        ),
        throwsStateError,
      );
      expect((await db.getAccount(id(1)))!.account.parentId, isNull);
      expect((await db.getAccount(id(1)))!.metadata.revision, 1);
    },
  );
  test('journal-used account keeps type and posting role atomically', () async {
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    final usedId = await workspace.createAccount(
      code: '1000',
      name: 'Bank',
      type: AccountType.asset,
    );
    final otherId = await workspace.createAccount(
      code: '3000',
      name: 'Capital',
      type: AccountType.equity,
    );
    await workspace.saveJournal(
      date: DateTime.utc(2026, 10, 10),
      memo: 'Retained posting identity',
      lines: [
        JournalLine.debit(
          accountId: usedId,
          amount: Money.fromDecimal('1.00', 'MYR'),
        ),
        JournalLine.credit(
          accountId: otherId,
          amount: Money.fromDecimal('1.00', 'MYR'),
        ),
      ],
    );
    final original = (await workspace.database.getAccount(usedId))!;
    Future<void> rejected(AccountType type, bool isParent) async {
      await expectLater(
        workspace.updateAccountMetadata(
          original: original,
          code: '1001',
          name: 'Changed Bank',
          type: type,
          isParent: isParent,
          parentId: null,
          status: AccountStatus.active,
        ),
        throwsStateError,
      );
      final retained = (await workspace.database.getAccount(usedId))!;
      expect(retained.account.code, '1000');
      expect(retained.account.type, AccountType.asset);
      expect(retained.account.isParent, isFalse);
      expect(retained.metadata.revision, original.metadata.revision);
      expect(await workspace.journals(), hasLength(1));
    }

    await rejected(AccountType.expense, false);
    await rejected(AccountType.asset, true);
    await workspace.updateAccountMetadata(
      original: original,
      code: '1001',
      name: 'Changed Bank',
      type: AccountType.asset,
      isParent: false,
      parentId: null,
      status: AccountStatus.locked,
    );
    expect((await workspace.database.getAccount(usedId))!.metadata.revision, 2);
    expect(await workspace.journals(), hasLength(1));
  });

  test(
    'payment-linked account keeps type and posting role atomically',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final linkedId = await workspace.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'bank-one',
          name: 'Bank One',
          type: PaymentAccountType.bank,
          currencyCode: workspace.identity.currency,
        ),
      );
      workspace.database.linkPaymentLedgerAccount(
        workspace.identity.businessId,
        'bank-one',
        linkedId,
      );
      final original = (await workspace.database.getAccount(linkedId))!;
      for (final (type, isParent) in [
        (AccountType.liability, false),
        (AccountType.asset, true),
      ]) {
        await expectLater(
          workspace.updateAccountMetadata(
            original: original,
            code: '1001',
            name: 'Changed Bank',
            type: type,
            isParent: isParent,
            parentId: null,
            status: AccountStatus.active,
          ),
          throwsStateError,
        );
        final retained = (await workspace.database.getAccount(linkedId))!;
        expect(retained.account.code, '1000');
        expect(retained.metadata.revision, 1);
        expect(
          workspace.database.paymentLedgerAccount(
            workspace.identity.businessId,
            'bank-one',
          ),
          linkedId,
        );
      }
    },
  );
  test('v1 migration preserves historical journals without guessing account records', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-v1-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    removeExpenseRemovalSchema(old);
    old.execute(
      '''CREATE TABLE journal_entries (
      id TEXT PRIMARY KEY, entry_date TEXT NOT NULL, memo TEXT NOT NULL, state TEXT NOT NULL,
      reverses_id TEXT, business_id TEXT NOT NULL, origin_device_id TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, revision INTEGER NOT NULL, deleted_at TEXT)''',
    );
    old.execute('''CREATE TABLE journal_lines (
      journal_id TEXT NOT NULL REFERENCES journal_entries(id), line_index INTEGER NOT NULL,
      account_id TEXT NOT NULL, kind TEXT NOT NULL, amount_minor INTEGER NOT NULL,
      currency TEXT NOT NULL, PRIMARY KEY(journal_id,line_index))''');
    old.execute('INSERT INTO journal_entries VALUES (?,?,?,?,?,?,?,?,?,?,?)', [
      id(5).value,
      '2026-09-13T00:00:00.000Z',
      'Preserved Draft',
      'draft',
      null,
      id(90).value,
      id(91).value,
      '2026-09-13T00:00:00.000Z',
      '2026-09-13T00:00:00.000Z',
      1,
      null,
    ]);
    old.execute('DROP TABLE IF EXISTS catalogue_items');
    old.execute('DROP TABLE IF EXISTS catalogue_categories');
    old.execute('DROP TABLE IF EXISTS generated_document_deliveries');
    old.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
    old.execute('DROP TABLE IF EXISTS recurring_document_template_history');
    old.execute('DROP TABLE IF EXISTS recurring_document_templates');
    old.execute('DROP TABLE IF EXISTS company_tax_rate_history');
    old.execute('DROP TABLE IF EXISTS company_tax_rates');
    old.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
    old.execute('DROP TABLE IF EXISTS tax_remittances');
    old.execute('DROP TABLE IF EXISTS company_tax_agency_history');
    old.execute('DROP TABLE IF EXISTS company_tax_agencies');
    old.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version = 1');
    old.dispose();
    var db = LocalAccountingDatabase.open(path);
    expect((await db.getJournal(id(5)))!.entry.memo, 'Preserved Draft');
    expect(await db.listAccounts(id(90)), isEmpty);
    await db.saveAccount(account(1));
    db.close();
    db = LocalAccountingDatabase.open(path);
    addTearDown(db.close);
    expect((await db.getJournal(id(5)))!.metadata.revision, 1);
    expect(await db.listAccounts(id(90)), hasLength(1));
  });
}
