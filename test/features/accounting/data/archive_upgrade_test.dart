import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/historical_sqlite_fixture.dart';

Map<String, dynamic> body(String archive) =>
    jsonDecode((jsonDecode(archive) as Map)['data'] as String)
        as Map<String, dynamic>;
String envelope(Map<String, dynamic> data) {
  final text = jsonEncode(data);
  return jsonEncode({
    'format': 'Audyt Data Archive',
    'sha256': sha256.convert(utf8.encode(text)).toString(),
    'data': text,
  });
}

// Independent historical deltas: 33/34 added source/ledger match member tables,
// 35 added company_preferences,
// 36 added workspace_reminders, 37 added bank_statement_reconnections,
// 38 added immutable claim correction history; 39 adds quotation drafts/history;
// 40 adds vendor contact profiles/history. No older
// table or column changed in these releases (the committed baseline is v34).
Map<String, dynamic> historical(String archive, int version) {
  final data = body(archive);
  data['schemaVersion'] = version;
  final tables = data['tables'] as Map;
  dropCurrentPaymentMethodArchiveFixtureOwner(data);
  if (version < 64) {
    final accounts = tables['accounts'] as Map;
    final columns = accounts['columns'] as List;
    final index = columns.indexOf('profile');
    if (index >= 0) {
      for (final row in accounts['rows'] as List) {
        if ((row as List)[index] != null) {
          throw StateError(
            'A pre64 fixture cannot contain retained account profiles.',
          );
        }
        row.removeAt(index);
      }
      columns.removeAt(index);
    }
  }
  if (version < 63) tables.remove('converted_quotation_revisions');
  if (version < 62) {
    tables.remove('expense_revision_postings');
    final revisions = tables['expense_revision_drafts'] as Map?;
    if (revisions != null) {
      final columns = revisions['columns'] as List;
      for (final column in [
        'occurred_on',
        'amount_minor',
        'currency',
        'payee',
        'category',
      ]) {
        final index = columns.indexOf(column);
        if (index < 0) continue;
        columns.removeAt(index);
        for (final row in revisions['rows'] as List) {
          (row as List).removeAt(index);
        }
      }
    }
  }
  if (version < 61) tables.remove('expense_revision_drafts');
  if (version < 60) {
    tables.remove('account_reconciliation_drafts');
    tables.remove('bank_reconciliation_cleared_movements');
  }
  if (version < 57) {
    // Linked Claim Expenses did not exist in these archives. Preserve the
    // original Expense rows; the upgrade creates links from recognition history.
    final expenses = tables['expense_intakes'] as Map;
    final payload = (expenses['columns'] as List).indexOf('payload');
    (expenses['rows'] as List).removeWhere(
      (row) =>
          (jsonDecode((row as List)[payload] as String)
              as Map)['claimSource'] !=
          null,
    );
  }
  if (version < 56) tables.remove('bank_reconciliation_drafts');
  if (version < 55) {
    tables.remove('tax_remittance_corrections');
    tables.remove('tax_remittances');
  }
  if (version < 54) {
    tables.remove('company_tax_agency_history');
    tables.remove('company_tax_agencies');
  }
  if (version < 51) tables.remove('transaction_record_removals');
  if (version < 49) {
    final expenses = tables['expense_intakes'] as Map;
    final columns = expenses['columns'] as List;
    for (final column in ['revision', 'archived_at', 'state_changed_at']) {
      final index = columns.indexOf(column);
      if (index < 0) continue;
      columns.removeAt(index);
      for (final row in expenses['rows'] as List) {
        (row as List).removeAt(index);
      }
    }
  }
  if (version < 47) {
    tables.remove('recurring_document_occurrences');
    tables.remove('recurring_document_template_history');
    tables.remove('recurring_document_templates');
  }
  if (version < 46) {
    tables.remove('company_tax_rate_history');
    tables.remove('company_tax_rates');
  }
  if (version < 45) tables.remove('generated_document_deliveries');
  if (version < 44) {
    tables.remove('catalogue_items');
    tables.remove('catalogue_categories');
  }
  if (version < 43) {
    tables.remove('bill_posting_reversals');
    tables.remove('bill_settlement_reversals');
  }
  if (version < 42) {
    tables.remove('bill_settlements');
    tables.remove('bill_settlement_allocations');
  }
  if (version < 41) {
    tables.remove('bill_drafts');
    tables.remove('bill_draft_history');
    tables.remove('bill_postings');
  }
  if (version < 40) {
    tables.remove('vendor_profiles');
    tables.remove('vendor_history');
  }
  if (version < 39) {
    tables.remove('quotation_drafts');
    tables.remove('quotation_history');
  }
  if (version < 38) {
    tables.remove('claim_posting_cycles');
    tables.remove('claim_posting_reversals');
  }
  if (version < 37) tables.remove('bank_statement_reconnections');
  if (version < 36) tables.remove('workspace_reminders');
  if (version < 35) tables.remove('company_preferences');
  if (version < 34) {
    tables.remove('bank_match_active_ledger_members');
    tables.remove('bank_match_ledger_members');
  }
  if (version < 33) {
    tables.remove('bank_match_active_members');
    tables.remove('bank_match_group_members');
  }
  return data;
}

void main() {
  for (final version in [32, 33, 34, 35, 36, 37, 38, 39, 44, 45, 46, 48]) {
    test(
      'schema $version archive upgrades without rewriting existing rows or links',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'audyt-archive-upgrade-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final originalPath = '${root.path}/original.sqlite';
        final source = await createDemoWorkspace(databasePath: originalPath);
        final identity = source.identity;
        final statementId = source.database
            .bankStatements(identity.businessId, 'demo-bank')
            .singleWhere((item) => item.filename == 'Demo Bank.csv')
            .id;
        final candidate = source.database
            .statementMatchSuggestions(identity.businessId, statementId)
            .singleWhere((entry) => entry.row.sourceRow == 2)
            .candidates
            .first;
        source.database.acceptStatementMatch(
          businessId: identity.businessId,
          statementId: statementId,
          sourceRow: 2,
          journalId: candidate.journalId,
          lineIndex: candidate.lineIndex,
          actorId: identity.ownerId,
          acceptedAt: DateTime.utc(2026, 9, 26),
        );
        final acceptanceId = source.database.statementMatchAcceptanceId(
          identity.businessId,
          statementId,
          2,
        );
        if (version >= 33) {
          final group = source.database
              .statementGroupMatchSuggestions(
                businessId: identity.businessId,
                statementId: statementId,
                sourceRows: {4, 5},
              )
              .single;
          source.database.acceptStatementMatchGroup(
            businessId: identity.businessId,
            statementId: statementId,
            sourceRows: {4, 5},
            journalId: group.journalId,
            lineIndex: group.lineIndex,
            actorId: identity.ownerId,
            acceptedAt: DateTime.utc(2026, 9, 26, 1),
          );
        }
        final journals = (await source.journals())
            .map((row) => row.entry.id)
            .toSet();
        final data = historical(
          source.database.exportDataArchive(
            identity.businessId,
            DateTime.now(),
          ),
          version,
        );
        source.dispose();
        final originalBytes = File(originalPath).readAsBytesSync();
        final path = '${root.path}/restored.sqlite';
        var restored = await AccountingWorkspace.emptyRestore(
          path,
          envelope(data),
        );
        expect(restored.identity.businessId, identity.businessId);
        expect(restored.identity.ownerId, identity.ownerId);
        expect(restored.identity.deviceId, identity.deviceId);
        expect(
          restored.database.statementMatchAcceptanceId(
            identity.businessId,
            statementId,
            2,
          ),
          acceptanceId,
        );
        expect(
          restored.database.acceptedStatementMatches(
            identity.businessId,
            statementId,
          )[2],
          candidate.movementId,
        );
        if (version >= 33) {
          final matches = restored.database.acceptedStatementMatches(
            identity.businessId,
            statementId,
          );
          expect(matches[4], isNotNull);
          expect(matches[4], matches[5]);
        }
        expect(
          (await restored.journals()).map((row) => row.entry.id).toSet(),
          journals,
        );
        final expenses = await restored.expenses();
        expect(expenses, hasLength(18));
        final derived = <String>{};
        for (final summary in expenses) {
          final draft = (await restored.expense(summary.id))!.draft;
          if (draft.claimSource != null) {
            expect(summary.journalId, draft.claimSource!.recognitionId);
            expect(summary.isPosted, isTrue);
            derived.add(summary.id.value);
          }
        }
        expect(derived, hasLength(2));
        expect(restored.invoiceDrafts(), hasLength(1));
        expect(restored.postedInvoices(), hasLength(2));
        expect(restored.claims.all, hasLength(16));
        expect(restored.vouchers.all, hasLength(15));
        expect(restored.reminders, hasLength(version < 36 ? 0 : 3));
        final after = body(
          restored.database.exportDataArchive(
            identity.businessId,
            DateTime.now(),
          ),
        );
        final beforeTables = data['tables'] as Map;
        final afterTables = after['tables'] as Map;
        // Schema 57 adds a presentation link for each existing recognition.
        // Check those links above, then compare every original row byte-for-byte.
        final expenseTable = afterTables['expense_intakes'] as Map;
        final expenseId = (expenseTable['columns'] as List).indexOf('id');
        (expenseTable['rows'] as List).removeWhere(
          (row) => derived.contains((row as List)[expenseId]),
        );
        // Schema 49 adds state only; every older intake starts active at
        // revision one, with its original scalar/payload columns unchanged.
        if (version < 49) {
          final expenses = afterTables['expense_intakes'] as Map;
          final columns = expenses['columns'] as List;
          for (final column in [
            'revision',
            'archived_at',
            'state_changed_at',
          ]) {
            final index = columns.indexOf(column);
            expect(index, greaterThanOrEqualTo(0));
            for (final row in expenses['rows'] as List) {
              expect((row as List)[index], column == 'revision' ? 1 : null);
              row.removeAt(index);
            }
            columns.removeAt(index);
          }
        }
        if (version < 64) {
          final accounts = afterTables['accounts'] as Map;
          final columns = accounts['columns'] as List;
          final index = columns.indexOf('profile');
          expect(index, greaterThanOrEqualTo(0));
          for (final row in accounts['rows'] as List) {
            expect((row as List)[index], isNull);
            row.removeAt(index);
          }
          columns.removeAt(index);
        }
        for (final table in beforeTables.keys) {
          // Includes document reference payloads, audit histories, allocation IDs,
          // revisions, reconciliation evidence and posted journal membership.
          expect(
            afterTables[table],
            beforeTables[table],
            reason: '$table changed during $version upgrade',
          );
        }
        final report = await restored.report(
          from: DateTime(2000),
          through: DateTime(2200),
        );
        expect(report.trialBalanceDebits, report.trialBalanceCredits);
        expect(report.balanceSheetDifference, BigInt.zero);
        restored.dispose();
        restored = await AccountingWorkspace.openExisting(
          path,
          businessId: identity.businessId,
          restoredCopyId: EntityId.random().value,
        );
        expect(restored.claims.all, hasLength(16));
        expect(restored.postedInvoices(), hasLength(2));
        restored.dispose();
        final raw = sqlite3.open(path, mode: OpenMode.readOnly);
        expect(
          raw.select('PRAGMA user_version').single['user_version'],
          LocalAccountingDatabase.schemaVersion,
        );
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        expect(raw.select('PRAGMA integrity_check').single.values.first, 'ok');
        raw.dispose();
        expect(File(originalPath).readAsBytesSync(), originalBytes);
      },
    );
  }

  test(
    'schema 4 journal history upgrades through all subsequent migrations',
    () async {
      final business = EntityId.random(),
          device = EntityId.random(),
          owner = EntityId.random();
      final bank = EntityId.random(),
          equity = EntityId.random(),
          journal = EntityId.random();
      final time = '2020-01-01T00:00:00.000Z';
      // Frozen initial workspace contract, without relying on a new schema factory.
      final data = <String, dynamic>{
        'version': 1,
        'schemaVersion': 4,
        'businessId': business.value,
        'createdAt': time,
        'documentsIncluded': false,
        'tables': {
          'journal_entries': {
            'columns': [
              'id',
              'entry_date',
              'memo',
              'state',
              'reverses_id',
              'business_id',
              'origin_device_id',
              'created_at',
              'updated_at',
              'revision',
              'deleted_at',
            ],
            'rows': [
              [
                journal.value,
                time,
                'Opening capital',
                'posted',
                null,
                business.value,
                device.value,
                time,
                time,
                1,
                null,
              ],
            ],
          },
          'journal_lines': {
            'columns': [
              'journal_id',
              'line_index',
              'account_id',
              'kind',
              'amount_minor',
              'currency',
            ],
            'rows': [
              [journal.value, 0, bank.value, 'debit', 123456, 'MYR'],
              [journal.value, 1, equity.value, 'credit', 123456, 'MYR'],
            ],
          },
          'accounts': {
            'columns': [
              'id',
              'business_id',
              'code',
              'name',
              'type',
              'status',
              'is_parent',
              'is_system',
              'parent_id',
              'origin_device_id',
              'created_at',
              'updated_at',
              'revision',
            ],
            'rows': [
              [
                bank.value,
                business.value,
                '1000',
                'Bank',
                'asset',
                'active',
                0,
                0,
                null,
                device.value,
                time,
                time,
                1,
              ],
              [
                equity.value,
                business.value,
                '3000',
                'Capital',
                'equity',
                'active',
                0,
                0,
                null,
                device.value,
                time,
                time,
                1,
              ],
            ],
          },
          'ledger_policies': {
            'columns': ['business_id', 'currency', 'closed_through'],
            'rows': [
              [business.value, 'MYR', null],
            ],
          },
          'ledger_audit': {
            'columns': [
              'sequence',
              'business_id',
              'actor_id',
              'occurred_at',
              'kind',
              'subject_id',
              'detail',
            ],
            'rows': [],
          },
          'local_workspace': {
            'columns': ['singleton', 'business_id', 'device_id', 'owner_id'],
            'rows': [
              [1, business.value, device.value, owner.value],
            ],
          },
          'journal_approvals': {
            'columns': ['business_id', 'request_id', 'journal_id', 'signature'],
            'rows': [],
          },
        },
      };
      final root = Directory.systemTemp.createTempSync('audyt-v4-archive-');
      addTearDown(() => root.deleteSync(recursive: true));
      final restored = await AccountingWorkspace.emptyRestore(
        '${root.path}/ledger.sqlite',
        envelope(data),
      );
      addTearDown(restored.dispose);
      expect(restored.identity.businessId, business);
      expect((await restored.journals()).single.entry.id, journal);
      expect(
        (await restored.accounts()).map((entry) => entry.account.id).toSet(),
        {bank, equity},
      );
      final report = await restored.report(
        from: DateTime(2000),
        through: DateTime(2200),
      );
      expect(report.trialBalanceDebits, BigInt.from(123456));
      expect(report.balanceSheetDifference, BigInt.zero);
      expect(restored.reminders, isEmpty);
      expect(restored.claims.all, isEmpty);
    },
  );

  test(
    'export refuses a mismatched identity or foreign-company rows',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-export-identity-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      expect(
        () => workspace.database.exportDataArchive(
          EntityId.random(),
          DateTime.now(),
        ),
        throwsStateError,
      );
      workspace.dispose();
      final raw = sqlite3.open(path);
      raw.execute(
        'INSERT INTO payees(business_id,id,name,type) VALUES (?,?,?,?)',
        [
          EntityId.random().value,
          'foreign-payee',
          'Fictional Other Company Payee',
          'vendor',
        ],
      );
      raw.dispose();
      final before = File(path).readAsBytesSync();
      workspace = await AccountingWorkspace.open(path);
      expect(
        () => workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.now(),
        ),
        throwsStateError,
      );
      workspace.dispose();
      expect(File(path).readAsBytesSync(), before);
    },
  );

  test('export rejects foreign bank data before reading its source', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-export-foreign-bank-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/ledger.sqlite';
    final workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    final foreignBusiness = EntityId.random();
    final raw = sqlite3.open(path);
    raw.execute(
      'INSERT INTO payment_accounts(business_id,id,name,type,currency,account_number,bank_id,bank_name) VALUES(?,?,?,?,?,?,?,?)',
      [
        foreignBusiness.value,
        'foreign-bank',
        'Foreign Bank',
        'bank',
        'MYR',
        '123',
        null,
        null,
      ],
    );
    raw.execute(
      "INSERT INTO bank_statement_imports(id,business_id,payment_account_id,filename,currency,digest,source,imported_at,parser_version,parsed_rows) VALUES(?,?,?,?,?,?,x'00',?,?,?)",
      [
        EntityId.random().value,
        foreignBusiness.value,
        'foreign-bank',
        'Foreign.csv',
        'MYR',
        List.filled(64, '0').join(),
        '2026-09-29T00:00:00.000Z',
        1,
        null,
      ],
    );
    raw.dispose();
    expect(
      () => workspace.database.exportDataArchive(
        workspace.identity.businessId,
        DateTime.utc(2026, 9, 29),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('another company'),
        ),
      ),
    );
  });

  test(
    'export rejects orphaned child rows without a business column',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-export-orphan-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/ledger.sqlite';
      final workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final raw = sqlite3.open(path);
      raw.execute('PRAGMA foreign_keys=OFF');
      raw.execute(
        'INSERT INTO journal_lines(journal_id,line_index,account_id,kind,amount_minor,currency) VALUES(?,?,?,?,?,?)',
        [
          EntityId.random().value,
          0,
          EntityId.random().value,
          'debit',
          100,
          'MYR',
        ],
      );
      raw.dispose();
      expect(
        () => workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.utc(2026, 9, 29),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('broken record links'),
          ),
        ),
      );
    },
  );

  test('rejected upgrades leave an empty destination reusable with triggers intact', () async {
    final source = await createDemoWorkspace();
    addTearDown(source.dispose);
    final archive = source.database.exportDataArchive(
      source.identity.businessId,
      DateTime.now(),
    );
    final empty = LocalAccountingDatabase.inMemory();
    addTearDown(empty.close);
    void rejected(Map<String, dynamic> data) {
      expect(
        () => empty.restoreDataArchive(envelope(data)),
        throwsA(isA<FormatException>()),
      );
      expect(empty.readInvoiceDrafts(source.identity.businessId), isEmpty);
      expect(empty.readReminders(source.identity.businessId), isEmpty);
    }

    final future = body(archive)
      ..['schemaVersion'] = LocalAccountingDatabase.schemaVersion + 1;
    rejected(future);
    final mismatched = body(archive)..['schemaVersion'] = 36;
    rejected(
      mismatched,
    ); // Current tables do not constitute the historical v36 schema.
    final foreign = historical(archive, 36);
    final accounts = (foreign['tables'] as Map)['accounts'] as Map;
    final businessIndex = (accounts['columns'] as List).indexOf('business_id');
    (accounts['rows'] as List).first[businessIndex] = EntityId.random().value;
    rejected(foreign);
    final brokenReference = historical(archive, 35);
    final lines = (brokenReference['tables'] as Map)['journal_lines'] as Map;
    (lines['rows'] as List).first[0] = EntityId.random().value;
    rejected(brokenReference);
    final unexpectedBytes = historical(archive, 36);
    final statements =
        (unexpectedBytes['tables'] as Map)['bank_statement_imports'] as Map;
    final sourceIndex = (statements['columns'] as List).indexOf('source');
    (statements['rows'] as List).first[sourceIndex] = [1, 2, 3];
    rejected(unexpectedBytes);
    final missingRows = historical(archive, 34);
    final oldStatements =
        (missingRows['tables'] as Map)['bank_statement_imports'] as Map;
    final parsedIndex = (oldStatements['columns'] as List).indexOf(
      'parsed_rows',
    );
    (oldStatements['rows'] as List).first[parsedIndex] = null;
    rejected(missingRows);
    empty.restoreDataArchive(envelope(historical(archive, 36)));
    expect(empty.readInvoiceDrafts(source.identity.businessId), hasLength(1));
    expect(empty.readReminders(source.identity.businessId), hasLength(3));
  });

  test(
    'recovered audit records remain immutable after archive migration',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-archive-guards-');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = await createDemoWorkspace();
      addTearDown(source.dispose);
      final archive = source.database.exportDataArchive(
        source.identity.businessId,
        DateTime.now(),
      );
      final path = '${root.path}/copy.sqlite';
      final restored = await AccountingWorkspace.emptyRestore(
        path,
        envelope(historical(archive, 34)),
      );
      restored.dispose();
      final raw = sqlite3.open(path);
      expect(
        () => raw.execute('DELETE FROM ledger_audit'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute(
          "UPDATE invoice_postings SET document_number='Changed'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        raw.select('PRAGMA user_version').single['user_version'],
        LocalAccountingDatabase.schemaVersion,
      );
      raw.dispose();
    },
  );
}
