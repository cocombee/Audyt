import 'dart:io';
import 'dart:convert';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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
      expect(await workspace.journals(), isEmpty);
    },
  );
}
