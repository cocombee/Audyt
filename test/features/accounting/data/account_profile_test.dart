import 'dart:io';
import 'dart:convert';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/historical_sqlite_fixture.dart';

void main() {
  test(
    'exact reporting/details and description survive restart and archive',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'audyt-account-profile-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final business = workspace.identity.businessId;
      final profiles = <String, Map<String, Object?>>{};
      for (final type in ReportingAccountType.values) {
        final profile = AccountProfile(
          reportingType: type,
          detailType: type.details.last,
          description: 'Purpose for ${type.label}\nRetained account facts.',
        );
        final id = await workspace.createAccount(
          code: 'REF-${type.name}',
          name: '${type.label} Sample',
          type: type.ledgerType,
          profile: profile,
        );
        profiles[id.value] = profile.toJson();
      }
      final original = (await workspace.accounts()).singleWhere(
        (record) => record.account.code == 'REF-expenses',
      );
      final editedProfile = AccountProfile(
        reportingType: ReportingAccountType.expenses,
        detailType: ReportingAccountType.expenses.details.first,
        description: 'Updated retained purpose.',
      );
      expect(
        await workspace.updateAccountMetadata(
          original: original,
          code: 'REF-EXP-EDIT',
          name: 'Edited Expense Sample',
          type: AccountType.expense,
          isParent: false,
          parentId: null,
          status: AccountStatus.locked,
          profile: editedProfile,
        ),
        original.account.id,
      );
      profiles[original.account.id.value] = editedProfile.toJson();
      final edited = (await workspace.database.getAccount(
        original.account.id,
      ))!;
      expect(edited.metadata.revision, original.metadata.revision + 1);
      expect(edited.metadata.createdAt, original.metadata.createdAt);
      expect(edited.metadata.originDeviceId, original.metadata.originDeviceId);
      expect(edited.account.status, AccountStatus.locked);
      final archive = workspace.database.exportDataArchive(
        business,
        DateTime.utc(2026, 10, 5),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final reopened = await workspace.accounts();
      expect(reopened, hasLength(15));
      for (final record in reopened) {
        expect(
          record.account.profile!.toJson(),
          profiles[record.account.id.value],
        );
        expect(record.account.validationErrors, isEmpty);
        expect(
          record.account.type,
          record.account.profile!.reportingType!.ledgerType,
        );
      }
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      restored.restoreDataArchive(archive);
      for (final record in await restored.listAccounts(business)) {
        expect(
          record.account.profile!.toJson(),
          profiles[record.account.id.value],
        );
      }
      final restoredEdit = (await restored.getAccount(original.account.id))!;
      expect(restoredEdit.account.code, 'REF-EXP-EDIT');
      expect(restoredEdit.account.name, 'Edited Expense Sample');
      expect(restoredEdit.metadata.revision, 2);
      expect(restoredEdit.account.status, AccountStatus.locked);
      expect(await workspace.journals(), isEmpty);
    },
  );

  test(
    'invalid detail and broad type reject without creating an account',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      await expectLater(
        workspace.createAccount(
          code: 'BAD-DETAIL',
          name: 'Mismatch',
          type: AccountType.asset,
          profile: const AccountProfile(
            reportingType: ReportingAccountType.cashAndCashEquivalents,
            detailType: 'Depreciation',
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        workspace.createAccount(
          code: 'BAD-CLASS',
          name: 'Mismatch',
          type: AccountType.expense,
          profile: const AccountProfile(
            reportingType: ReportingAccountType.cashAndCashEquivalents,
            detailType: 'Savings',
          ),
        ),
        throwsArgumentError,
      );
      expect(await workspace.accounts(), isEmpty);
      expect(await workspace.journals(), isEmpty);
    },
  );

  test('company tax default retains ID while unknown or foreign choices reject', () async {
    final folder = Directory.systemTemp.createTempSync('audyt-account-tax-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final taxId = AccountingWorkspace.newId();
    workspace.saveTaxRate(
      CompanyTaxRate(
        id: taxId,
        name: 'Company Purchase Tax',
        percent: '6',
        effectiveFrom: DateTime.utc(2026),
        application: TaxApplication.purchases,
      ),
    );
    final id = await workspace.createAccount(
      code: 'EXP',
      name: 'Company Expenses',
      type: AccountType.expense,
      profile: AccountProfile(
        reportingType: ReportingAccountType.expenses,
        detailType: 'Advertising/Promotional',
        defaultTaxCodeId: taxId,
      ),
    );
    await expectLater(
      workspace.createAccount(
        code: 'BAD-TAX',
        name: 'Unknown tax',
        type: AccountType.expense,
        profile: AccountProfile(defaultTaxCodeId: AccountingWorkspace.newId()),
      ),
      throwsStateError,
    );
    final foreignTax = AccountingWorkspace.newId();
    final foreignBusiness = AccountingWorkspace.newId();
    final sql = sqlite3.open(path);
    // Isolated fixture: an actual foreign company row exists in this book;
    // the normal command must never offer or accept it for the active company.
    sql.execute(
      'INSERT INTO company_tax_rates(business_id,id,name,normalized_name,revision,payload) VALUES (?,?,?,?,?,?)',
      [
        foreignBusiness.value,
        foreignTax.value,
        'Other Company Tax',
        'other company tax',
        1,
        jsonEncode(
          CompanyTaxRate(
            id: foreignTax,
            name: 'Other Company Tax',
            percent: '6',
            effectiveFrom: DateTime.utc(2026),
            application: TaxApplication.purchases,
            revision: 1,
          ).toJson(),
        ),
      ],
    );
    sql.dispose();
    await expectLater(
      workspace.createAccount(
        code: 'FOREIGN-TAX',
        name: 'Other company default',
        type: AccountType.expense,
        profile: AccountProfile(defaultTaxCodeId: foreignTax),
      ),
      throwsStateError,
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(
      (await workspace.database.getAccount(id))!
          .account
          .profile!
          .defaultTaxCodeId,
      taxId,
    );
    expect(await workspace.accounts(), hasLength(1));
    expect(await workspace.journals(), isEmpty);
  });

  test(
    'schema63 upgrade preserves legacy identity and posting authority',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'audyt-account-upgrade-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final id = await workspace.createAccount(
        code: 'LEGACY',
        name: 'Legacy Cash',
        type: AccountType.asset,
      );
      final original = (await workspace.database.getAccount(id))!;
      workspace.dispose();
      final sql = sqlite3.open(path);
      dropCurrentPaymentMethodFixtureOwner(sql);
      sql.execute('ALTER TABLE accounts DROP COLUMN profile');
      sql.execute('PRAGMA user_version=63');
      sql.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final upgraded = (await workspace.database.getAccount(id))!;
      expect(upgraded.account.profile, isNull);
      expect(upgraded.account.code, original.account.code);
      expect(upgraded.account.type, original.account.type);
      expect(upgraded.metadata.revision, original.metadata.revision);
      expect(
        await workspace.updateAccountMetadata(
          original: upgraded,
          code: 'LEGACY-EDIT',
          name: 'Legacy Cash Edited',
          type: upgraded.account.type,
          isParent: upgraded.account.isParent,
          parentId: upgraded.account.parentId,
          status: upgraded.account.status,
        ),
        id,
      );
      final edited = (await workspace.database.getAccount(id))!;
      expect(edited.account.profile, isNull);
      expect(edited.metadata.revision, original.metadata.revision + 1);
      expect(await workspace.journals(), isEmpty);
    },
  );

  test(
    'metadata command rejects stale, foreign, missing and archived accounts',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final accountId = await workspace.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      final original = (await workspace.database.getAccount(accountId))!;
      Future<EntityId> update(
        StoredAccount expected, {
        String code = '1001',
        AccountStatus status = AccountStatus.active,
      }) => workspace.updateAccountMetadata(
        original: expected,
        code: code,
        name: 'Petty Cash',
        type: AccountType.asset,
        isParent: false,
        parentId: null,
        status: status,
      );
      await update(original);
      await expectLater(update(original), throwsStateError);
      final current = (await workspace.database.getAccount(accountId))!;
      await expectLater(
        update(
          StoredAccount(
            account: current.account,
            metadata: RecordMetadata.initial(
              recordId: accountId,
              businessId: EntityId.random(),
              originDeviceId: workspace.identity.deviceId,
              createdAt: current.metadata.createdAt,
            ),
          ),
        ),
        throwsStateError,
      );
      final missingId = EntityId.random();
      await expectLater(
        update(
          StoredAccount(
            account: Account.create(
              id: missingId,
              code: 'MISSING',
              name: 'Missing',
              type: AccountType.asset,
            ),
            metadata: RecordMetadata.initial(
              recordId: missingId,
              businessId: workspace.identity.businessId,
              originDeviceId: workspace.identity.deviceId,
              createdAt: DateTime.utc(2026, 10, 10),
            ),
          ),
        ),
        throwsStateError,
      );
      await workspace.database.saveAccount(
        StoredAccount(
          account: Account.create(
            id: accountId,
            code: current.account.code,
            name: current.account.name,
            type: current.account.type,
            status: AccountStatus.archived,
          ),
          metadata: current.metadata.nextRevision(
            updatedAt: current.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        ),
      );
      final archived = (await workspace.database.getAccount(accountId))!;
      await expectLater(update(archived), throwsStateError);
      expect(archived.account.status, AccountStatus.archived);
      expect(current.metadata.revision, 2);
      expect(
        (await workspace.database.getAccount(accountId))!.account.code,
        '1001',
      );
      expect(await workspace.accounts(), hasLength(1));
      expect(await workspace.journals(), isEmpty);
    },
  );
}
