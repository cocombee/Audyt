import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:convert';

import 'package:audyt/features/accounting/domain/company_preferences.dart';

import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy paired pricing switches migrate and Rate requires Quantity', () {
    final migrated = CompanyPreferences.fromJson({
      'Sales Preferences': {'Show Quantity & Rate': true},
    });
    expect(migrated.enabled('Sales Preferences', 'Show Rate'), true);
    expect(migrated.enabled('Sales Preferences', 'Show Quantity'), true);
    expect(
      migrated.toJson()['Sales Preferences'],
      isNot(contains('Show Quantity & Rate')),
    );
    final quantityOnly = CompanyPreferences.defaults().change(
      'Sales Preferences',
      {'Show Quantity': true},
    );
    expect(quantityOnly.enabled('Sales Preferences', 'Show Rate'), false);
    final rate = quantityOnly.change('Sales Preferences', {'Show Rate': true});
    expect(rate.enabled('Sales Preferences', 'Show Quantity'), true);
  });
  test(
    'every live preference survives restart, audited with stable account IDs',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-live-settings-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      for (final spec in [
        ('1100', AccountType.asset),
        ('4000', AccountType.income),
        ('2200', AccountType.liability),
      ]) {
        await workspace.createAccount(
          code: spec.$1,
          name: spec.$1,
          type: spec.$2,
        );
      }
      final accounts = {
        for (final account in await workspace.accounts())
          account.account.type: account.account.id.value,
      };
      final expected = <String, Map<String, Object?>>{};
      for (final section in workspace.preferences.sections.keys.toList()) {
        expect(section, isNotEmpty);
      }
      final sections = [
        'Business Profile',
        'Default Accounts',
        'Sales Preferences',
        'Purchase Preferences',
        'Numbering & Document Appearance',
        'Backup & Export Preferences',
      ];
      for (final section in sections) {
        final values = {...workspace.preferences.values(section)};
        for (final field in values.keys.toList()) {
          values[field] = values[field] is bool
              ? false
              : field == 'Country'
              ? 'Other Country'
              : field == 'Number Padding'
              ? '3 Digits'
              : field == 'Number Prefix'
              ? 'TEST'
              : field == 'Backup Frequency'
              ? 'Daily'
              : field == 'Export Format'
              ? 'CSV'
              : field == 'Default Tax Mode'
              ? 'Inclusive'
              : field == '_businessLogoBase64'
              ? ''
              : 'Saved $field';
        }
        if (section == 'Default Accounts') {
          values['Receivables Account'] = accounts[AccountType.asset];
          values['Payables Account'] = accounts[AccountType.liability];
          values['Income Account'] = accounts[AccountType.income];
          values['Sales Tax Liability Account'] =
              accounts[AccountType.liability];
        }
        workspace.savePreferences(
          workspace.preferences.change(section, values),
        );
        expected[section] = values;
      }
      final identity = workspace.identity;
      expect(workspace.preferences.revision, 6);
      expect(
        (await workspace.database.auditEvents(identity.businessId))
            .where((event) => event['kind'] == 'company_preferences_saved'),
        hasLength(6),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.identity.businessId, identity.businessId);
      for (final section in sections) {
        expect(
          workspace.preferences.values(section),
          expected[section],
          reason: section,
        );
      }
    },
  );

  test(
    'partial updates retain other saved values in the same section',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-settings-merge-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      workspace.savePreferences(
        workspace.preferences.change('Sales Preferences', {
          'Customer Message': 'Keep this saved message',
          'Enable Discounts': false,
        }),
      );
      workspace.savePreferences(
        workspace.preferences.change('Sales Preferences', {'Show Rate': false}),
      );
      expect(workspace.preferences.values('Sales Preferences'), {
        'Default Tax Mode': 'Exclusive',
        'Show Quantity': false,
        'Show Rate': false,
        'Enable Discounts': false,
        'Show Class': false,
        'Customer Message': 'Keep this saved message',
      });
      workspace.savePreferences(
        workspace.preferences.change('Purchase Preferences', {
          'Billable Expenses': false,
        }),
      );
      workspace.savePreferences(
        workspace.preferences.change('Purchase Preferences', {
          'Link To Customer': false,
        }),
      );
      expect(
        workspace.preferences.enabled(
          'Purchase Preferences',
          'Billable Expenses',
        ),
        false,
      );
      expect(
        () => workspace.preferences.change('Purchase Preferences', {
          'Billable Expenses': true,
        }),
        throwsFormatException,
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Keep this saved message',
      );
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Enable Discounts'),
        false,
      );
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Show Rate'),
        false,
      );
      expect(
        workspace.preferences.enabled(
          'Purchase Preferences',
          'Link To Customer',
        ),
        false,
      );
      expect(
        workspace.preferences.enabled(
          'Purchase Preferences',
          'Billable Expenses',
        ),
        false,
      );
    },
  );

  test(
    'settings reject stale revisions, wrong owners and incompatible accounts',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final stale = workspace.preferences;
      workspace.savePreferences(
        stale.change('Sales Preferences', {'Enable Discounts': false}),
      );
      expect(
        () => workspace.savePreferences(
          stale.change('Sales Preferences', {'Enable Discounts': true}),
        ),
        throwsStateError,
      );
      expect(
        () => workspace.database.saveCompanyPreferences(
          businessId: workspace.identity.businessId,
          actorId: EntityId.random(),
          preferences: workspace.preferences,
          savedAt: DateTime.now(),
        ),
        throwsStateError,
      );
      await workspace.createAccount(
        code: '6000',
        name: 'Expenses',
        type: AccountType.expense,
      );
      final expenseId = (await workspace.accounts()).single.account.id.value;
      final revision = workspace.preferences.revision;
      expect(
        () => workspace.savePreferences(
          workspace.preferences.change('Default Accounts', {
            'Income Account': expenseId,
          }),
        ),
        throwsStateError,
      );
      expect(workspace.preferences.revision, revision);
    },
  );

  test(
    'invoice prefix and every padding option affect future allocations only',
    () async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final originalId = EntityId.random();
      String allocate(EntityId id) => workspace.database.allocateDocumentNumber(
        businessId: workspace.identity.businessId,
        actorId: workspace.identity.ownerId,
        recordId: id,
        documentType: 'invoice',
        allocatedAt: DateTime.now(),
      );
      final old = allocate(originalId);
      for (final padding in [
        'None',
        '3 Digits',
        '4 Digits',
        '5 Digits',
        '6 Digits',
      ]) {
        workspace.savePreferences(
          workspace.preferences.change('Numbering & Document Appearance', {
            'Number Prefix': 'TEST',
            'Number Padding': padding,
          }),
        );
        final number = allocate(EntityId.random());
        expect(number, startsWith('TEST-'));
        expect(
          number.substring(5).length,
          padding == 'None' ? 1 : int.parse(padding[0]),
        );
        expect(allocate(originalId), old);
      }
    },
  );

  test(
    'v34 migration preserves existing books and adds empty preferences',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'audyt-settings-upgrade-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      final original = await AccountingWorkspace.open(path);
      final identity = original.identity;
      await original.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      original.dispose();
      final db = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(db);
      removeExpenseRemovalSchema(db);
      // Recreate the actual pre-35 table set. Merely changing user_version on
      // the current schema leaves newer tables in an impossible old fixture.
      db.execute('DROP VIEW all_claim_postings');
      for (final table in [
        'bill_settlement_allocations',
        'bill_settlements',
        'bill_postings',
        'bill_draft_history',
        'bill_drafts',
        'vendor_history',
        'vendor_profiles',
        'quotation_history',
        'quotation_drafts',
        'claim_posting_reversals',
        'claim_posting_cycles',
        'bank_statement_reconnections',
        'workspace_reminders',
        'company_preferences',
      ]) {
        db.execute('DROP TABLE $table');
      }
      db.execute('DROP INDEX bill_settlement_audit');
      db.execute('DROP INDEX bill_audit_company_kind_subject');
      db.execute('DROP INDEX payees_company_directory');
      db.execute('DROP TABLE IF EXISTS catalogue_items');
      db.execute('DROP TABLE IF EXISTS catalogue_categories');
      db.execute('DROP TABLE IF EXISTS generated_document_deliveries');
      db.execute('DROP TABLE IF EXISTS recurring_document_occurrences');
      db.execute('DROP TABLE IF EXISTS recurring_document_template_history');
      db.execute('DROP TABLE IF EXISTS recurring_document_templates');
      db.execute('DROP TABLE IF EXISTS company_tax_rate_history');
      db.execute('DROP TABLE IF EXISTS company_tax_rates');
      db.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      db.execute('DROP TABLE IF EXISTS tax_remittances');
      db.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      db.execute('DROP TABLE IF EXISTS company_tax_agencies');
      db.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      db.execute('DROP VIEW IF EXISTS current_expense_intakes');
      db.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      db.execute('DROP TABLE IF EXISTS expense_revision_postings');
      db.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      db.execute('PRAGMA user_version=34');
      db.dispose();
      final upgraded = await AccountingWorkspace.open(path);
      addTearDown(upgraded.dispose);
      expect(upgraded.identity.businessId, identity.businessId);
      expect((await upgraded.accounts()).single.account.name, 'Cash');
      expect(upgraded.preferences.revision, 0);
    },
  );

  test(
    'data-only archive restores books and metadata into a separate workspace',
    () async {
      final original = await createDemoWorkspace();
      addTearDown(original.dispose);
      original.savePreferences(
        original.preferences.change('Sales Preferences', {
          'Enable Discounts': false,
          'Customer Message': 'Keep this',
        }),
      );
      final journals = await original.journals();
      final invoiceCount = original.invoiceDrafts().length;
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        DateTime.now(),
      );
      final body = jsonDecode(jsonDecode(archive)['data']) as Map;
      expect(body['documentsIncluded'], false);
      final restoredDb = LocalAccountingDatabase.inMemory();
      addTearDown(restoredDb.close);
      restoredDb.restoreDataArchive(archive);
      expect(
        await restoredDb.listJournals(original.identity.businessId),
        hasLength(journals.length),
      );
      expect(
        restoredDb.readInvoiceDrafts(original.identity.businessId),
        hasLength(invoiceCount),
      );
      expect(
        restoredDb
            .readCompanyPreferences(original.identity.businessId)
            .enabled('Sales Preferences', 'Enable Discounts'),
        false,
      );
      final sourceInvoices = original.invoiceDrafts();
      for (final record in restoredDb.readInvoiceDrafts(
        original.identity.businessId,
      )) {
        for (final attachment in record.invoice.attachments) {
          expect(attachment.originalBytes, isEmpty);
          expect(attachment.failureMessage, contains('data-only restore'));
        }
      }
      for (final record in sourceInvoices) {
        for (final attachment in record.invoice.attachments) {
          expect(attachment.originalBytes, isNotEmpty);
        }
      }
      for (final account in original.paymentAccounts) {
        for (final item in original.database.bankStatements(
          original.identity.businessId,
          account.id,
        )) {
          final before = original.database.bankStatement(
            original.identity.businessId,
            item.id,
          )!;
          final after = restoredDb.bankStatement(
            original.identity.businessId,
            item.id,
          )!;
          expect(after.digest, before.digest);
          expect(after.rows.length, before.rows.length);
          expect(after.sourceAvailable, false);
          expect(before.sourceAvailable, true);
          expect(
            () => restoredDb.acceptStatementMatch(
              businessId: original.identity.businessId,
              statementId: item.id,
              sourceRow: after.rows.first.sourceRow,
              journalId: journals.first.entry.id,
              lineIndex: 0,
              actorId: original.identity.ownerId,
              acceptedAt: DateTime.now(),
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'evidence guard',
                contains('Reconnect'),
              ),
            ),
          );
          final reconnected = restoredDb.importBankStatement(
            id: EntityId.random(),
            businessId: original.identity.businessId,
            paymentAccountId: account.id,
            statement: before,
            importedAt: DateTime.now(),
          );
          expect(reconnected, item.id);
          expect(
            restoredDb
                .bankStatement(original.identity.businessId, item.id)!
                .sourceBytes,
            before.sourceBytes,
          );
        }
      }
      expect(
        () => original.database.restoreDataArchive(archive),
        throwsStateError,
      );
      final broken = jsonDecode(archive) as Map<String, dynamic>;
      broken['data'] = '${broken['data']} ';
      final empty = LocalAccountingDatabase.inMemory();
      addTearDown(empty.close);
      expect(
        () => empty.restoreDataArchive(jsonEncode(broken)),
        throwsFormatException,
      );
      expect(original.invoiceDrafts(), hasLength(invoiceCount));
    },
  );

  test('all backup frequencies cross calendar and year boundaries', () {
    final last = DateTime(2026, 12, 31, 23, 59);
    final next = DateTime(2027, 1, 1);
    expect(WorkspaceBackup.due('Manual', next, null), false);
    expect(WorkspaceBackup.due('Daily', next, last), true);
    expect(WorkspaceBackup.due('Daily', last, last), false);
    expect(WorkspaceBackup.due('Weekly', DateTime(2027, 1, 7), last), true);
    expect(WorkspaceBackup.due('Weekly', next, last), false);
    expect(WorkspaceBackup.due('Monthly', next, last), true);
    expect(WorkspaceBackup.due('Monthly', last, last), false);
  });
}
