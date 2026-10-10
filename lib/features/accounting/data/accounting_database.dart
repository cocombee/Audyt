import '../application/approved_claim_expense.dart';
import '../application/tax_remittance_candidate.dart';
import '../domain/claim_recognition_proposal.dart';
import '../../sales/domain/estimate.dart';
import '../../sales/domain/product_catalogue.dart';
import '../../sales/domain/sales_report.dart';
import '../../sales/domain/sales_line_item.dart';
import '../../purchases/domain/vendor.dart';
import '../../purchases/domain/purchase_bill_draft.dart';
import '../../purchases/domain/payment_voucher_source.dart';
import '../../purchases/domain/payment_voucher_evidence.dart';
import '../domain/workspace_reminder.dart';
import '../../../core/dates/ageing_bucket.dart';

import 'package:crypto/crypto.dart';

import '../domain/company_preferences.dart';
import '../domain/company_tax_rate.dart';
import '../domain/company_tax_agency.dart';
import '../domain/tax_remittance.dart';
import '../domain/tax_activity_report.dart';
import '../domain/claimant_statement.dart';
import '../domain/claim_reimbursement_position.dart';
import '../domain/expense_revision.dart';
import '../domain/transaction_removal.dart';
import '../domain/recurring_document_template.dart';
import '../domain/recurrence_rule.dart';
import '../../sales/domain/invoice_credit_draft.dart';
import '../../sales/domain/invoice_credit_journal.dart';
import '../../../core/documents/receipt_document.dart';
import '../../../core/documents/generated_document.dart';
import '../../sales/domain/invoice_credit.dart';
import '../../sales/domain/receivable_ageing.dart';
import '../../sales/domain/invoice.dart';
import '../../sales/domain/customer_statement_activity.dart';
import 'customer_codec.dart';
import '../domain/customer.dart';
import '../domain/statement_reconciliation.dart';
import '../domain/account_reconciliation.dart';
import '../domain/bank_statement_match.dart';

import 'dart:typed_data';

import '../domain/bank_statement_import.dart';
import '../domain/recurring_expense_template.dart';
import '../../purchases/domain/payment_voucher.dart';
import '../../purchases/domain/payment_voucher_store.dart';
import '../../purchases/domain/claim.dart';
import '../../purchases/domain/claim_store.dart';
import '../../purchases/domain/claim_payment_batch.dart';
import '../domain/payment_account.dart';
import '../domain/payee.dart';

import 'package:audyt/features/accounting/domain/closing_proposal.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/expense_intake.dart';
import 'package:audyt/features/accounting/application/workspace_identity.dart';
import 'package:audyt/features/accounting/domain/ledger_report.dart';

import 'dart:convert';

import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';

part 'quotation_database.dart';
part 'vendor_database.dart';
part 'bill_database.dart';
part 'bill_settlement_database.dart';
part 'bill_ageing_database.dart';
part 'catalogue_database.dart';
part 'tax_rate_database.dart';
part 'tax_agency_database.dart';
part 'tax_remittance_database.dart';
part 'recurring_document_database.dart';
part 'sales_report_database.dart';
part 'tax_activity_database.dart';
part 'claimant_statement_database.dart';
part 'transaction_removal_database.dart';
part 'generated_document_database.dart';
part 'reconciliation_draft_database.dart';
part 'imported_reconciliation_recovery_database.dart';
part 'account_reconciliation_database.dart';
part 'journal_editability_database.dart';
part 'journal_draft_revision_database.dart';
part 'manual_journal_revision_database.dart';
part 'quotation_current_revision_database.dart';
part 'expense_revision_database.dart';
part 'expense_revision_posting_database.dart';
part 'claim_expense_database.dart';

final class LocalAccountingDatabase
    implements JournalEntryRepository, AccountRepository {
  LocalAccountingDatabase._(
    this._database, {
    int throughVersion = schemaVersion,
  }) {
    try {
      _migrate(throughVersion: throughVersion);
    } catch (_) {
      _database.dispose();
      rethrow;
    }
  }

  factory LocalAccountingDatabase.inMemory() {
    return LocalAccountingDatabase._(sqlite3.openInMemory());
  }

  factory LocalAccountingDatabase.open(String path) {
    return LocalAccountingDatabase._(sqlite3.open(path));
  }

  /// Recovery must never create a replacement file or migrate another company.
  factory LocalAccountingDatabase.openExisting(
    String path, {
    required EntityId businessId,
  }) {
    final database = sqlite3.open(path, mode: OpenMode.readWrite);
    try {
      final rows = database.select(
        'SELECT business_id FROM local_workspace WHERE singleton=1',
      );
      if (rows.length != 1 || rows.single['business_id'] != businessId.value) {
        throw StateError(
          'The restored company identity could not be verified.',
        );
      }
    } catch (_) {
      database.dispose();
      rethrow;
    }
    return LocalAccountingDatabase._(database);
  }

  List<WorkspaceReminder> readReminders(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload,revision FROM workspace_reminders WHERE business_id=? ORDER BY due_date,id',
          [businessId.value],
        )
        .map(
          (row) => WorkspaceReminder.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            revision: row['revision'] as int,
          ),
        )
        .toList();
  }

  void saveReminder({
    required EntityId businessId,
    required EntityId actorId,
    required WorkspaceReminder reminder,
    required DateTime savedAt,
    DateTime? asOfDate,
  }) => saveReminders(
    businessId: businessId,
    actorId: actorId,
    reminders: [reminder],
    savedAt: savedAt,
    asOfDate: asOfDate,
  );

  void saveReminders({
    required EntityId businessId,
    required EntityId actorId,
    required List<WorkspaceReminder> reminders,
    required DateTime savedAt,
    DateTime? asOfDate,
  }) {
    _ensureOpen();
    if (reminders.isEmpty ||
        reminders.map((r) => r.id).toSet().length != reminders.length) {
      throw const FormatException('Choose distinct reminder entries.');
    }
    _transaction(() {
      for (final reminder in reminders) {
        _saveReminder(
          businessId: businessId,
          actorId: actorId,
          reminder: reminder,
          savedAt: savedAt,
          asOfDate: asOfDate,
        );
      }
    });
  }

  void _saveReminder({
    required EntityId businessId,
    required EntityId actorId,
    required WorkspaceReminder reminder,
    required DateTime savedAt,
    DateTime? asOfDate,
  }) {
    _ensureOpen();
    _requireReconciliationOwner(businessId, actorId);
    final current = _database.select(
      'SELECT revision,business_id,payload FROM workspace_reminders WHERE id=?',
      [reminder.id.value],
    );
    if (current.isNotEmpty &&
            current.single['business_id'] != businessId.value ||
        (current.isEmpty ? 0 : current.single['revision']) !=
            reminder.revision) {
      throw StateError('This reminder changed. Reopen it before saving.');
    }
    final previous = current.isEmpty
        ? null
        : WorkspaceReminder.fromJson(
            jsonDecode(current.single['payload'] as String)
                as Map<String, dynamic>,
          );
    if (previous?.title != reminder.title &&
        reminder.title.runes.length > WorkspaceReminder.nameLimit) {
      throw const FormatException(
        'Reminder names can contain up to 16 characters.',
      );
    }
    final today = asOfDate ?? DateTime.now();
    if ((previous?.dueDate != reminder.dueDate &&
            !validNewReminderDate(reminder.dueDate, today)) ||
        (reminder.triggerDate != null &&
            previous?.triggerDate != reminder.triggerDate &&
            !validNewReminderDate(reminder.triggerDate!, today))) {
      throw const FormatException(
        'Reminder dates must be today through ten years ahead.',
      );
    }
    _database.execute(
      'INSERT INTO workspace_reminders(id,business_id,payload,due_date,revision) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,due_date=excluded.due_date,revision=excluded.revision',
      [
        reminder.id.value,
        businessId.value,
        jsonEncode(reminder.toJson()),
        reminder.dueDate.toIso8601String(),
        reminder.revision + 1,
      ],
    );
    if (reminder.completed && reminder.status != 'Not Applicable') {
      final next = reminder.nextOccurrence(today);
      if (next != null) {
        final exists = readReminders(businessId).any(
          (r) =>
              (r.seriesId ?? r.id.value) == next.seriesId &&
              r.dueDate.isAfter(reminder.dueDate),
        );
        // Saving a completed entry can enable recurrence or repair a missing
        // successor. An existing later occurrence owns that series' progress;
        // editing its older history must not create a duplicate deadline.
        if (!exists) {
          _saveReminder(
            businessId: businessId,
            actorId: actorId,
            reminder: next,
            savedAt: savedAt,
            asOfDate: today,
          );
        }
      }
    }
    _appendAudit(
      businessId: businessId,
      actorId: actorId,
      at: savedAt,
      kind: 'reminder_saved',
      subjectId: reminder.id,
      detail: jsonEncode({
        'revision': reminder.revision + 1,
        'status': reminder.status,
      }),
    );
  }

  CompanyPreferences readCompanyPreferences(EntityId businessId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT payload,revision FROM company_preferences WHERE business_id=?',
      [businessId.value],
    );
    if (rows.isEmpty) return CompanyPreferences.defaults();
    return CompanyPreferences.fromJson(
      jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      revision: rows.single['revision'] as int,
    );
  }

  CompanyPreferences saveCompanyPreferences({
    required EntityId businessId,
    required EntityId actorId,
    required CompanyPreferences preferences,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final current = readCompanyPreferences(businessId);
      if (current.revision != preferences.revision) {
        throw StateError(
          'Settings changed in another editor. Reopen Settings before saving.',
        );
      }
      final accounts = preferences.values('Default Accounts');
      for (final entry in accounts.entries) {
        if (entry.value == '') continue;
        final rows = _database.select(
          'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, entry.value],
        );
        final expected = switch (entry.key) {
          'Income Account' => 'income',
          'Receivables Account' => 'asset',
          _ => 'liability',
        };
        if (rows.isEmpty ||
            rows.single['type'] != expected ||
            rows.single['status'] != 'active' ||
            rows.single['is_parent'] != 0) {
          throw StateError(
            'Choose an active $expected account for ${entry.key}.',
          );
        }
      }
      _database.execute(
        'INSERT INTO company_preferences(business_id,payload,revision) VALUES (?,?,?) ON CONFLICT(business_id) DO UPDATE SET payload=excluded.payload,revision=excluded.revision',
        [
          businessId.value,
          jsonEncode(preferences.toJson()),
          current.revision + 1,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'company_preferences_saved',
        subjectId: businessId,
        detail: jsonEncode({
          'revision': current.revision + 1,
          'sections': preferences.sections.keys.toList(),
        }),
      );
    });
    return readCompanyPreferences(businessId);
  }

  /// Consistent data-only export; document contents stay in their original folders.
  String exportDataArchive(EntityId businessId, DateTime createdAt) {
    _ensureOpen();
    final snapshot = sqlite3.copyIntoMemory(_database);
    try {
      final identity = snapshot.select(
        'SELECT business_id FROM local_workspace',
      );
      if (identity.length != 1 ||
          identity.single['business_id'] != businessId.value) {
        throw StateError('The workspace identity is unavailable for export.');
      }
      if (snapshot.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw StateError(
          'The workspace has broken record links. Recovery is required.',
        );
      }
      Object? metadataOnly(Object? value) {
        if (value is List) return value.map(metadataOnly).toList();
        if (value is Map) {
          final map = <String, Object?>{
            for (final entry in value.entries)
              entry.key as String: metadataOnly(entry.value),
          };
          if (map.containsKey('originalBytes') &&
              map.containsKey('originalSha256')) {
            map['originalBytes'] = null;
            map['derivativeBytes'] = null;
            map['pdfBytes'] = null;
            map['_evidenceUnavailable'] = true;
          }
          if (map.containsKey('_businessLogoBase64')) {
            map['_businessLogoBase64'] = '';
          }
          return map;
        }
        return value;
      }

      final statementMetadata = <String, String>{};
      for (final row in snapshot.select(
        'SELECT id,business_id FROM bank_statement_imports WHERE business_id=?',
        [businessId.value],
      )) {
        final statement = _bankStatementFrom(
          snapshot,
          EntityId.parse(row['business_id'] as String),
          EntityId.parse(row['id'] as String),
        );
        if (statement != null) {
          statementMetadata[row['id'] as String] = statement.parsedRowsJson;
        }
      }
      final tables = <String, Object?>{};
      for (final table in snapshot.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )) {
        final name = table['name'] as String;
        final columns = snapshot.select('PRAGMA table_info("$name")');
        if (columns.any((column) => column['name'] == 'business_id') &&
            snapshot.select(
              'SELECT 1 FROM "$name" WHERE business_id IS NULL OR business_id<>? LIMIT 1',
              [businessId.value],
            ).isNotEmpty) {
          throw StateError(
            'The workspace contains records from another company. Recovery is required.',
          );
        }
        final rows = snapshot.select('SELECT * FROM "$name"');
        tables[name] = {
          'columns': columns.map((column) => column['name']).toList(),
          'rows': [
            for (final row in rows)
              [
                for (final column in columns)
                  () {
                    final value =
                        name == 'bank_statement_imports' &&
                            column['name'] == 'parsed_rows'
                        ? statementMetadata[row['id']]
                        : row[column['name'] as String];
                    if (value is Uint8List) return <int>[];
                    if (value is String &&
                        (value.startsWith('{') || value.startsWith('['))) {
                      try {
                        return jsonEncode(metadataOnly(jsonDecode(value)));
                      } on FormatException {
                        return value;
                      }
                    }
                    return value;
                  }(),
              ],
          ],
        };
      }
      final body = jsonEncode({
        'version': 1,
        'schemaVersion': schemaVersion,
        'businessId': businessId.value,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'documentsIncluded': false,
        'tables': tables,
      });
      return jsonEncode({
        'format': 'Audyt Data Archive',
        'sha256': sha256.convert(utf8.encode(body)).toString(),
        'data': body,
      });
    } finally {
      snapshot.dispose();
    }
  }

  String exportLedgerCsv(EntityId businessId) {
    _ensureOpen();
    final identity = _database.select(
      'SELECT business_id FROM local_workspace',
    );
    if (identity.length != 1 ||
        identity.single['business_id'] != businessId.value) {
      throw StateError('The workspace identity is unavailable for export.');
    }
    const harmlessLeadingSpace = {
      0x20,
      0xA0,
      0x1680,
      0x200B,
      0x202F,
      0x205F,
      0x3000,
      0xFEFF,
    };
    const formulaStarts = {
      0x00,
      0x09,
      0x0A,
      0x0D,
      0x2B,
      0x2D,
      0x3D,
      0x40,
      0xFF0B,
      0xFF0D,
      0xFF1D,
      0xFF20,
    };
    String cell(Object? value) {
      var text = '${value ?? ''}';
      var first = 0;
      while (first < text.length &&
          harmlessLeadingSpace.contains(text.codeUnitAt(first))) {
        first++;
      }
      if (first < text.length &&
          formulaStarts.contains(text.codeUnitAt(first))) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }

    final rows = _database.select(
      "SELECT j.entry_date,j.id,j.memo,a.code,a.name,l.kind,l.amount_minor,l.currency FROM journal_entries j JOIN journal_lines l ON l.journal_id=j.id JOIN accounts a ON a.id=l.account_id WHERE j.business_id=? AND j.state='posted' ORDER BY j.entry_date,j.id,l.line_index",
      [businessId.value],
    );
    return [
      'date,journal_id,memo,account_code,account_name,side,amount_minor,currency',
      for (final row in rows) row.values.map(cell).join(','),
    ].join('\r\n');
  }

  /// Import is allowed only into an empty, separate workspace database.
  void restoreDataArchive(String archive) {
    _ensureOpen();
    if (archive.length > 500000000) {
      throw const FormatException('The data archive is too large.');
    }
    final envelope = jsonDecode(archive) as Map<String, dynamic>;
    if (envelope['format'] != 'Audyt Data Archive' ||
        envelope['data'] is! String ||
        sha256.convert(utf8.encode(envelope['data'] as String)).toString() !=
            envelope['sha256']) {
      throw const FormatException('The archive is damaged or unsupported.');
    }
    final data = jsonDecode(envelope['data'] as String) as Map<String, dynamic>;
    final sourceVersion = data['schemaVersion'];
    if (data['version'] != 1 ||
        sourceVersion is! int ||
        sourceVersion < 4 ||
        sourceVersion > schemaVersion ||
        data['documentsIncluded'] != false) {
      throw const FormatException('Unsupported data archive version.');
    }
    EntityId.parse(data['businessId'] as String);
    _requireEmptyRestoreDestination();
    if (sourceVersion == schemaVersion) {
      _restoreArchiveData(data);
      return;
    }
    // Rebuild only the app-owned historical schema, never SQL from the file.
    // All upgrade work occurs in isolation; a failed migration cannot partially
    // upgrade the destination or overwrite the user's current books.
    final staged = LocalAccountingDatabase._(
      sqlite3.openInMemory(),
      throughVersion: sourceVersion,
    );
    try {
      staged._restoreArchiveData(data);
      staged._migrate();
      final tables = <String, Object?>{};
      for (final table in staged._archiveTableNames()) {
        final columns = staged._database.select('PRAGMA table_info("$table")');
        tables[table] = {
          'columns': columns.map((column) => column['name']).toList(),
          'rows': [
            for (final row in staged._database.select('SELECT * FROM "$table"'))
              [
                for (final column in columns)
                  row[column['name'] as String] is Uint8List
                      ? (row[column['name'] as String] as Uint8List).toList()
                      : row[column['name'] as String],
              ],
          ],
        };
      }
      _restoreArchiveData({
        ...data,
        'schemaVersion': schemaVersion,
        'tables': tables,
      });
    } finally {
      staged.close();
    }
  }

  Set<String> _archiveTableNames() => _database
      .select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )
      .map((row) => row['name'] as String)
      .toSet();

  void _requireEmptyRestoreDestination() {
    for (final name in _archiveTableNames()) {
      if (_database.select('SELECT 1 FROM "$name" LIMIT 1').isNotEmpty) {
        throw StateError(
          'Restore requires a new empty workspace. Your current workspace will not be replaced.',
        );
      }
    }
  }

  void _restoreArchiveData(Map<String, dynamic> data) {
    _requireEmptyRestoreDestination();
    final tables = data['tables'] as Map<String, dynamic>;
    final names = _archiveTableNames();
    if (names.length != tables.length || !names.containsAll(tables.keys)) {
      throw const FormatException('The archive table set is incomplete.');
    }
    final triggers = _database.select(
      "SELECT name,sql FROM sqlite_master WHERE type='trigger'",
    );
    _database.execute('PRAGMA foreign_keys=OFF');
    try {
      _transaction(() {
        for (final trigger in triggers) {
          _database.execute('DROP TRIGGER "${trigger['name']}"');
        }
        for (final name in names) {
          final table = tables[name] as Map<String, dynamic>;
          final columns = _database.select('PRAGMA table_info("$name")');
          final columnNames = columns
              .map((column) => column['name'] as String)
              .toList();
          if (jsonEncode(table['columns']) != jsonEncode(columnNames)) {
            throw const FormatException(
              'Archive columns do not match this version.',
            );
          }
          for (final raw in table['rows'] as List) {
            final row = raw as List;
            if (row.length != columns.length) {
              throw const FormatException('Invalid archive row.');
            }
            for (var i = 0; i < row.length; i++) {
              if (columnNames[i] == 'business_id' &&
                  row[i] != data['businessId']) {
                throw const FormatException(
                  'The archive contains another company.',
                );
              }
              if (columns[i]['type'] == 'BLOB' &&
                  (row[i] is! List || (row[i] as List).isNotEmpty)) {
                throw const FormatException(
                  'A data-only archive cannot contain file bytes.',
                );
              }
            }
            if ((data['schemaVersion'] as int) < 58 &&
                (name == 'claims' || name.startsWith('claim_'))) {
              for (var i = 0; i < row.length; i++) {
                if ((columnNames[i] == 'payload' ||
                        columnNames[i].endsWith('_payload')) &&
                    row[i] is String) {
                  final payload = jsonDecode(row[i] as String);
                  if (payload is Map &&
                      (payload['version'] == 4 ||
                          payload['expenseDraft'] != null)) {
                    throw const FormatException(
                      'Expense-backed Claims require archive version 58.',
                    );
                  }
                }
              }
            }
            final values = [
              for (var i = 0; i < row.length; i++)
                columns[i]['type'] == 'BLOB' ? Uint8List(0) : row[i],
            ];
            _database.execute(
              'INSERT INTO "$name" (${columnNames.map((c) => '"$c"').join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
              values,
            );
          }
        }
        if (_database.select('PRAGMA foreign_key_check').isNotEmpty ||
            _database.select('PRAGMA integrity_check').single.values.first !=
                'ok') {
          throw const FormatException(
            'The archive failed database integrity checks.',
          );
        }
        final identityRows = _database.select(
          'SELECT business_id FROM local_workspace',
        );
        if (identityRows.length != 1 ||
            identityRows.single['business_id'] != data['businessId']) {
          throw const FormatException(
            'Archive company identity does not match.',
          );
        }
        for (final row in _database.select('SELECT * FROM accounts')) {
          final account = _accountFromRow(row).account;
          if (account.validationErrors.isNotEmpty) {
            throw const FormatException('Archive account profile is invalid.');
          }
          final taxId = account.profile?.defaultTaxCodeId;
          if (taxId != null &&
              !readTaxRates(EntityId.parse(data['businessId'] as String))
                  .any((rate) => rate.id == taxId)) {
            throw const FormatException(
              'Archive account default tax code is missing.',
            );
          }
        }
        if (names.contains('bank_statement_imports')) {
          for (final row in _database.select(
            'SELECT * FROM bank_statement_imports',
          )) {
            if (!row.containsKey('parsed_rows') ||
                row['parsed_rows'] is! String) {
              throw const FormatException(
                'The archive lacks saved bank rows. Recover from the original database and statement files.',
              );
            }
            BankStatementImport.metadataOnly(
              filename: row['filename'] as String,
              currency: row['currency'] as String,
              digest: row['digest'] as String,
              parserVersion: row['parser_version'] as int,
              parsedRowsJson: row['parsed_rows'] as String,
            );
          }
        }
        if (_database
            .select(
              "SELECT j.id FROM journal_entries j JOIN journal_lines l ON l.journal_id=j.id WHERE j.state='posted' GROUP BY j.id,l.currency HAVING SUM(CASE WHEN l.kind='debit' THEN l.amount_minor ELSE -l.amount_minor END)<>0",
            )
            .isNotEmpty) {
          throw const FormatException(
            'The archive contains an unbalanced posted journal.',
          );
        }
        if (names.contains('recurring_document_templates')) {
          _validateDocumentScheduleArchive();
        }
        if (names.contains('claim_postings') &&
            (data['schemaVersion'] as int) >= 38) {
          _validateClaimExpenseArchive(
            requireComplete: (data['schemaVersion'] as int) >= 57,
          );
        }
        if (names.contains('company_tax_rates')) {
          if (names.contains('company_tax_agencies')) {
            _validateTaxAgencyArchive();
          }
          _validateTaxArchive();
        }
        if (names.contains('tax_remittances')) {
          _validateTaxRemittanceArchive();
        }
        if (names.contains('account_reconciliation_drafts')) {
          _validateAccountReconciliationArchive();
        }
        if (names.contains('bank_reconciliations')) {
          _validateImportedReconciliationArchive();
        }
        if (names.contains('bank_reconciliation_drafts')) {
          _validateReconciliationDraftArchive();
        }
        if (names.contains('quotation_drafts')) {
          _validateQuotationArchive();
          _validateQuotationCurrentArchive();
        }
        if (names.contains('vendor_profiles')) {
          _validateVendorArchive();
        }
        if (names.contains('bill_drafts')) {
          _validateBillDraftArchive();
        }
        if (names.contains('bill_settlements')) {
          _validateBillSettlementArchive();
        }
        if (names.contains('transaction_record_removals')) {
          _validateTransactionRemovalArchive();
        }
        if (names.contains('expense_revision_drafts')) {
          _validateExpenseRevisionArchive();
        }
        if (names.contains('expense_revision_postings')) {
          _validateExpenseRevisionPostingArchive();
        }
        if (names.contains('ledger_audit')) {
          _validateManualJournalDraftRevisionArchive();
          _validateManualJournalCurrentRevisionArchive();
        }
        if ((data['schemaVersion'] as int) >= 49) {
          for (final row in _database.select('SELECT * FROM expense_intakes')) {
            final removed = row['archived_at'] as String?;
            final changed = row['state_changed_at'] as String?;
            if ((row['revision'] as int) < 1 ||
                (changed != null && DateTime.tryParse(changed) == null) ||
                (removed != null &&
                    (DateTime.tryParse(removed) == null ||
                        row['journal_id'] != null ||
                        expenseRemovalRestriction(
                              EntityId.parse(row['business_id'] as String),
                              EntityId.parse(row['id'] as String),
                            ) !=
                            null ||
                        changed != removed))) {
              throw const FormatException('Invalid expense removal history.');
            }
          }
        }
        for (final trigger in triggers) {
          _database.execute(trigger['sql'] as String);
        }
      });
    } finally {
      _database.execute('PRAGMA foreign_keys=ON');
    }
  }

  static const schemaVersion = 64;

  final Database _database;

  // Enabled only by AccountingWorkspace.openExisting after restored identity
  // verification. Ordinary books keep their existing audit behavior.
  EntityId? _restoredTrackingBusinessId;

  void trackRestoredTransactionRoots(EntityId businessId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT business_id FROM local_workspace WHERE singleton=1',
    );
    if (rows.length != 1 || rows.single['business_id'] != businessId.value) {
      throw StateError('The restored company identity could not be verified.');
    }
    _restoredTrackingBusinessId = businessId;
  }

  /// Detects both this connection's writes and commits from another opener of
  /// the same book, matching the reconciliation snapshot cache.
  (int, int) get changeToken {
    _ensureOpen();
    return (
      _database.select('SELECT total_changes() AS count').single['count']
          as int,
      _database.select('PRAGMA data_version').single['data_version'] as int,
    );
  }

  var _closed = false;
  // A reconciliation can contain years of ledger movements. Voucher badges
  // ask for the same exact comparison several times during one UI rebuild.
  // Both counters are needed: total_changes() sees this connection's writes,
  // while data_version sees commits made by another connection.
  (int, int)? _reconciliationChangeCacheVersion;
  final Map<String, ReconciliationLedgerChanges> _reconciliationChangeCache =
      {};

  List<
    ({
      String requestId,
      String reference,
      DateTime date,
      String customer,
      Money total,
      List<({String number, Money amount})> allocations,
    })
  >
  customerReceiptHistory(EntityId businessId) {
    _ensureOpen();
    final rows = _database.select(
      '''
      SELECT r.request_id,r.reference,j.entry_date,p.customer_payload,
             p.document_number,a.amount_minor,a.currency
      FROM customer_receipts r
      JOIN journal_entries j ON j.id=r.journal_id
      JOIN customer_receipt_allocations a
        ON a.business_id=r.business_id AND a.request_id=r.request_id
      JOIN invoice_postings p
        ON p.business_id=a.business_id AND p.invoice_id=a.invoice_id
      WHERE r.business_id=?
      ORDER BY j.entry_date DESC,r.request_id,p.document_number
    ''',
      [businessId.value],
    );
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      groups.putIfAbsent(row['request_id'] as String, () => []).add(row);
    }
    return groups.entries
        .map((group) {
          final first = group.value.first;
          final allocations = group.value
              .map(
                (row) => (
                  number: row['document_number'] as String,
                  amount: Money.fromMinor(
                    row['amount_minor'] as int,
                    row['currency'] as String,
                  ),
                ),
              )
              .toList(growable: false);
          final total = allocations.fold(
            Money.fromMinor(0, first['currency'] as String),
            (sum, allocation) => sum + allocation.amount,
          );
          return (
            requestId: group.key,
            reference: first['reference'] as String,
            date: DateTime.parse(first['entry_date'] as String),
            customer: decodeCustomer(first['customer_payload'] as String)
                .displayName,
            total: total,
            allocations: allocations,
          );
        })
        .toList(growable: false);
  }

  List<({String reference, Money amount, DateTime date})> invoiceReceipts(
    EntityId businessId,
    EntityId invoiceId,
  ) {
    _ensureOpen();
    return _database
        .select(
          'SELECT r.reference,a.amount_minor,a.currency,j.entry_date AS date FROM customer_receipt_allocations a JOIN customer_receipts r ON r.business_id=a.business_id AND r.request_id=a.request_id JOIN journal_entries j ON j.id=r.journal_id WHERE a.business_id=? AND a.invoice_id=? ORDER BY j.entry_date,r.request_id',
          [businessId.value, invoiceId.value],
        )
        .map(
          (r) => (
            reference: r['reference'] as String,
            amount: Money.fromMinor(
              r['amount_minor'] as int,
              r['currency'] as String,
            ),
            date: DateTime.parse(r['date'] as String),
          ),
        )
        .toList(growable: false);
  }

  List<
    ({
      String number,
      String customer,
      DateTime dueDate,
      String bucket,
      Money remaining,
    })
  >
  receivablesAsOf(EntityId businessId, DateTime asOf) {
    _ensureOpen();
    final date = accountingCalendarDate(asOf);
    final result =
        <
          ({
            String number,
            String customer,
            DateTime dueDate,
            String bucket,
            Money remaining,
          })
        >[];
    final rows = _database.select(
      '''
      WITH paid AS (
        SELECT a.invoice_id, SUM(a.amount_minor) AS amount_minor
        FROM customer_receipt_allocations a
        JOIN customer_receipts r
          ON r.business_id=a.business_id AND r.request_id=a.request_id
        JOIN journal_entries j ON j.id=r.journal_id
        WHERE a.business_id=? AND substr(j.entry_date,1,10)<=?
        GROUP BY a.invoice_id
      ), credited AS (
        SELECT c.invoice_id,SUM(c.receivable_minor) AS amount_minor
        FROM invoice_credit_postings c JOIN journal_entries j ON j.id=c.journal_id
        WHERE c.business_id=? AND substr(j.entry_date,1,10)<=?
        GROUP BY c.invoice_id
      )
      SELECT d.payload,p.customer_payload,p.document_number,
             COALESCE(paid.amount_minor,0) + COALESCE(credited.amount_minor,0) AS paid_minor
      FROM invoice_postings p
      JOIN invoice_drafts d ON d.business_id=p.business_id AND d.id=p.invoice_id
      LEFT JOIN paid ON paid.invoice_id=p.invoice_id
      LEFT JOIN credited ON credited.invoice_id=p.invoice_id
      WHERE p.business_id=?
      ''',
      [
        businessId.value,
        date.toIso8601String().substring(0, 10),
        businessId.value,
        date.toIso8601String().substring(0, 10),
        businessId.value,
      ],
    );
    for (final row in rows) {
      final invoice = Invoice.fromDraftSnapshot(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      if (accountingCalendarDate(invoice.issueDate).isAfter(date)) continue;
      final remaining =
          invoice.total -
          Money.fromMinor(row['paid_minor'] as int, invoice.total.currency);
      if (remaining.isNegative) {
        throw StateError('Receipts exceed the invoice total.');
      }
      if (!remaining.isPositive) continue;
      result.add((
        number: row['document_number'] as String,
        customer: decodeCustomer(row['customer_payload'] as String).displayName,
        dueDate: invoice.dueDate,
        bucket: receivableAgeBucket(dueDate: invoice.dueDate, asOf: date),
        remaining: remaining,
      ));
    }
    result.sort((a, b) {
      final due = a.dueDate.compareTo(b.dueDate);
      return due == 0 ? a.number.compareTo(b.number) : due;
    });
    return result;
  }

  List<
    ({
      DateTime date,
      CustomerStatementActivity activity,
      String reference,
      Money debit,
      Money credit,
      Money balance,
    })
  >
  customerStatement(EntityId businessId, EntityId customerId, DateTime asOf) {
    _ensureOpen();
    final cutoff = accountingCalendarDate(asOf);
    final movements =
        <
          ({
            DateTime date,
            CustomerStatementActivity activity,
            String reference,
            Money debit,
            Money credit,
          })
        >[];
    for (final posted in readPostedInvoices(businessId)) {
      final invoice = posted.sourceDraft;
      if (invoice.customerId != customerId ||
          accountingCalendarDate(invoice.issueDate).isAfter(cutoff)) {
        continue;
      }
      movements.add((
        date: accountingCalendarDate(invoice.issueDate),
        activity: CustomerStatementActivity.invoice,
        reference: posted.documentNumber,
        debit: invoice.total,
        credit: Money.zero(invoice.total.currency),
      ));
    }
    final payments = _database.select(
      '''
      SELECT r.reference,j.entry_date,a.currency,SUM(a.amount_minor) AS total
      FROM customer_receipts r
      JOIN journal_entries j ON j.id=r.journal_id
      JOIN customer_receipt_allocations a ON a.business_id=r.business_id AND a.request_id=r.request_id
      WHERE r.business_id=? AND r.customer_id=? AND substr(j.entry_date,1,10)<=?
      GROUP BY r.request_id,r.reference,j.entry_date,a.currency
    ''',
      [
        businessId.value,
        customerId.value,
        cutoff.toIso8601String().substring(0, 10),
      ],
    );
    for (final payment in payments) {
      final amount = Money.fromMinor(
        payment['total'] as int,
        payment['currency'] as String,
      );
      movements.add((
        date: accountingCalendarDate(
          DateTime.parse(payment['entry_date'] as String),
        ),
        reference: payment['reference'] as String,
        activity: CustomerStatementActivity.payment,
        debit: Money.zero(amount.currency),
        credit: amount,
      ));
    }
    final credits = _database.select(
      'SELECT c.receivable_minor+c.customer_credit_minor AS total,c.currency,j.entry_date,p.document_number,p.customer_payload FROM invoice_credit_postings c JOIN journal_entries j ON j.id=c.journal_id JOIN invoice_postings p ON p.business_id=c.business_id AND p.invoice_id=c.invoice_id WHERE c.business_id=? AND substr(j.entry_date,1,10)<=?',
      [businessId.value, cutoff.toIso8601String().substring(0, 10)],
    );
    for (final credit in credits) {
      if (decodeCustomer(credit['customer_payload'] as String).id !=
          customerId) {
        continue;
      }
      final amount = Money.fromMinor(
        credit['total'] as int,
        credit['currency'] as String,
      );
      movements.add((
        date: accountingCalendarDate(
          DateTime.parse(credit['entry_date'] as String),
        ),
        reference: 'Credit · ${credit['document_number']}',
        activity: CustomerStatementActivity.credit,
        debit: Money.zero(amount.currency),
        credit: amount,
      ));
    }
    movements.sort((a, b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      final kind = (a.debit.isPositive ? 0 : 1).compareTo(
        b.debit.isPositive ? 0 : 1,
      );
      return kind != 0 ? kind : a.reference.compareTo(b.reference);
    });
    final balances = <String, Money>{};
    return movements
        .map((m) {
          final balance =
              (balances[m.debit.currency] ?? Money.zero(m.debit.currency)) +
              m.debit -
              m.credit;
          balances[m.debit.currency] = balance;
          return (
            date: m.date,
            activity: m.activity,
            reference: m.reference,
            debit: m.debit,
            credit: m.credit,
            balance: balance,
          );
        })
        .toList(growable: false);
  }

  EntityId receiveInvoicePayment({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required EntityId customerId,
    required EntityId bankAccountId,
    required Map<EntityId, Money> allocations,
    required String reference,
    required DateTime receivedAt,
    DateTime? approvedAt,
    String? paymentAccountId,
  }) {
    _ensureOpen();
    final approvalTime = (approvedAt ?? receivedAt).toUtc();
    if (allocations.isEmpty || reference.trim().isEmpty) {
      throw ArgumentError('Select invoices and enter a payment reference.');
    }
    final ordered = allocations.entries.toList()
      ..sort((a, b) => a.key.value.compareTo(b.key.value));
    final signature = jsonEncode([
      customerId.value,
      bankAccountId.value,
      reference.trim(),
      receivedAt.toUtc().toIso8601String(),
      actorId.value,
      approvalTime.toIso8601String(),
      if (paymentAccountId != null) ['paymentAccountId', paymentAccountId],
      for (final entry in ordered)
        [entry.key.value, entry.value.minorUnits, entry.value.currency],
    ]);
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT signature FROM customer_receipts WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError('Payment request was reused for different work.');
        }
        return;
      }
      if (paymentAccountId != null) {
        final payment = readPaymentAccounts(businessId)
            .where((p) => p.id == paymentAccountId)
            .firstOrNull;
        if (payment == null ||
            payment.type == PaymentAccountType.card ||
            payment.currency.code != ordered.first.value.currency ||
            paymentLedgerAccount(businessId, paymentAccountId) !=
                bankAccountId) {
          throw StateError(
            'Choose a payment account linked to the reviewed bank ledger and currency.',
          );
        }
      }
      final bank = _database.select(
        'SELECT * FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, bankAccountId.value],
      );
      if (bank.isEmpty ||
          bank.single['type'] != 'asset' ||
          bank.single['status'] != 'active' ||
          bank.single['is_parent'] != 0) {
        throw StateError('Choose an active bank/cash asset account.');
      }
      var total = Money.zero(ordered.first.value.currency);
      final lines = <JournalLine>[];
      for (final allocation in ordered) {
        if (!allocation.value.isPositive) {
          throw ArgumentError('Allocation amounts must be positive.');
        }
        final rows = _database.select(
          'SELECT d.payload,p.journal_id FROM invoice_postings p JOIN invoice_drafts d ON d.business_id=p.business_id AND d.id=p.invoice_id WHERE p.business_id=? AND p.invoice_id=?',
          [businessId.value, allocation.key.value],
        );
        if (rows.isEmpty) {
          throw StateError('Select a posted invoice in this company.');
        }
        final invoice = Invoice.fromDraftSnapshot(
          jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
        );
        if (invoice.customerId != customerId ||
            invoice.total.currency != allocation.value.currency) {
          throw StateError(
            'Invoices must belong to this customer and currency.',
          );
        }
        if (accountingCalendarDate(receivedAt).isBefore(invoice.issueDate)) {
          throw StateError('Receipt cannot precede invoice issue date.');
        }
        if (_database.select(
          "SELECT 1 FROM journal_entries WHERE reverses_id=? AND state='posted'",
          [rows.single['journal_id']],
        ).isNotEmpty) {
          throw StateError('A reversed invoice cannot receive a payment.');
        }
        final paid =
            _database.select(
                  'SELECT COALESCE(SUM(amount_minor),0) AS paid FROM customer_receipt_allocations WHERE business_id=? AND invoice_id=?',
                  [businessId.value, allocation.key.value],
                ).single['paid']
                as int;
        final credited =
            _database.select(
                  'SELECT COALESCE(SUM(receivable_minor),0) AS credited FROM invoice_credit_postings WHERE business_id=? AND invoice_id=?',
                  [businessId.value, allocation.key.value],
                ).single['credited']
                as int;
        if (allocation.value.minorUnits >
            invoice.total.minorUnits - paid - credited) {
          throw StateError(
            'The allocation exceeds the current invoice balance.',
          );
        }
        final receivable = _database.select(
          "SELECT account_id FROM journal_lines WHERE journal_id=? AND kind='debit'",
          [rows.single['journal_id']],
        );
        if (receivable.length != 1) {
          throw StateError('Invoice receivable posting requires review.');
        }
        final receivableId = EntityId.parse(
          receivable.single['account_id'] as String,
        );
        if (receivableId == bankAccountId) {
          throw StateError('Bank and receivable accounts must differ.');
        }
        lines.add(
          JournalLine.credit(accountId: receivableId, amount: allocation.value),
        );
        total += allocation.value;
      }
      lines.insert(
        0,
        JournalLine.debit(accountId: bankAccountId, amount: total),
      );
      final device =
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']
              as String;
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: receivedAt,
            memo: 'Customer payment ${reference.trim()}',
            lines: lines,
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: approvalTime.subtract(const Duration(microseconds: 1)),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: requestId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: approvalTime,
        ),
      );
      _database.execute(
        'INSERT INTO customer_receipts(business_id,request_id,customer_id,journal_id,reference,signature) VALUES (?,?,?,?,?,?)',
        [
          businessId.value,
          requestId.value,
          customerId.value,
          requestId.value,
          reference.trim(),
          signature,
        ],
      );
      for (final allocation in ordered) {
        _database.execute(
          'INSERT INTO customer_receipt_allocations(business_id,request_id,invoice_id,amount_minor,currency) VALUES (?,?,?,?,?)',
          [
            businessId.value,
            requestId.value,
            allocation.key.value,
            allocation.value.minorUnits,
            allocation.value.currency,
          ],
        );
      }
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvalTime,
        kind: 'customer_payment_received',
        subjectId: requestId,
        detail: jsonEncode({
          'reference': reference.trim(),
          'invoiceIds': ordered.map((e) => e.key.value).toList(),
        }),
      );
      _appendTransactionRootCreated(
        businessId: businessId,
        actorId: actorId,
        at: approvalTime,
        family: 'customerReceipt',
        recordId: requestId,
      );
    });
    return requestId;
  }

  String allocateDocumentNumber({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId recordId,
    required String documentType,
    required DateTime allocatedAt,
  }) {
    _ensureOpen();
    const prefixes = {
      'invoice': 'INV',
      'quotation': 'QT',
      'bill': 'BILL',
      'claim': 'CL',
      'voucher': 'PV',
      'customer_payment': 'RCPT',
    };
    final settings = readCompanyPreferences(businessId);
    final prefix = documentType == 'invoice'
        ? settings.text('Numbering & Document Appearance', 'Number Prefix')
        : prefixes[documentType];
    final padding = documentType == 'invoice'
        ? settings.text('Numbering & Document Appearance', 'Number Padding')
        : '6 Digits';
    final digits = padding == 'None' ? 0 : int.parse(padding.substring(0, 1));
    if (prefix == null) throw ArgumentError('Unsupported document type.');
    late String number;
    _joinTransaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final existing = _database.select(
        'SELECT number FROM document_numbers WHERE business_id=? AND document_type=? AND record_id=?',
        [businessId.value, documentType, recordId.value],
      );
      if (existing.isNotEmpty) {
        number = existing.single['number'] as String;
        return;
      }
      var sequence =
          (_database.select(
                'SELECT COALESCE(MAX(sequence),0) AS last FROM document_numbers WHERE business_id=? AND document_type=?',
                [businessId.value, documentType],
              ).single['last']
              as int) +
          1;
      final draftNumbers = documentType == 'invoice'
          ? _database
                .select(
                  'SELECT payload FROM invoice_drafts WHERE business_id=?',
                  [businessId.value],
                )
                .map(
                  (row) => Invoice.fromDraftSnapshot(
                    jsonDecode(row['payload'] as String)
                        as Map<String, dynamic>,
                  ).documentNumber,
                )
                .toSet()
          : documentType == 'quotation'
          ? _database
                .select(
                  'SELECT document_number FROM $_quotationReadSource WHERE business_id=?1 UNION SELECT document_number FROM quotation_drafts WHERE business_id=?1',
                  [businessId.value],
                )
                .map((row) => row['document_number'] as String)
                .toSet()
          : <String>{};
      while (true) {
        number = '$prefix-${sequence.toString().padLeft(digits, '0')}';
        if (!draftNumbers.contains(number) &&
            (documentType != 'invoice' ||
                _database.select(
                  'SELECT 1 FROM invoice_postings WHERE business_id=? AND document_number=?',
                  [businessId.value, number],
                ).isEmpty)) {
          break;
        }
        sequence++;
      }
      _database.execute(
        'INSERT INTO document_numbers(business_id,document_type,record_id,sequence,number,allocated_at,actor_id) VALUES (?,?,?,?,?,?,?)',
        [
          businessId.value,
          documentType,
          recordId.value,
          sequence,
          number,
          allocatedAt.toUtc().toIso8601String(),
          actorId.value,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: allocatedAt,
        kind: 'document_number_allocated',
        subjectId: recordId,
        detail: jsonEncode({'documentType': documentType, 'number': number}),
      );
    });
    return number;
  }

  List<({Invoice invoice, int revision})> readInvoiceDrafts(
    EntityId businessId, {
    bool archived = false,
  }) {
    _ensureOpen();
    return _database
        .select(
          'SELECT d.payload,d.revision FROM invoice_drafts d WHERE d.business_id=? AND d.archived_at IS ${archived ? 'NOT NULL' : 'NULL'} AND NOT EXISTS(SELECT 1 FROM invoice_postings p WHERE p.business_id=d.business_id AND p.invoice_id=d.id) ORDER BY d.id',
          [businessId.value],
        )
        .map(
          (r) => (
            invoice: Invoice.fromDraftSnapshot(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
            revision: r['revision'] as int,
          ),
        )
        .toList();
  }

  List<
    ({
      Invoice sourceDraft,
      Customer customerSnapshot,
      int paidMinor,
      int creditedMinor,
      String documentNumber,
      EntityId journalId,
    })
  >
  readPostedInvoices(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT d.payload,p.customer_payload,p.document_number,p.journal_id,(SELECT COALESCE(SUM(a.amount_minor),0) FROM customer_receipt_allocations a WHERE a.business_id=p.business_id AND a.invoice_id=p.invoice_id) AS paid_minor,(SELECT COALESCE(SUM(c.receivable_minor),0) FROM invoice_credit_postings c WHERE c.business_id=p.business_id AND c.invoice_id=p.invoice_id) AS credited_minor FROM invoice_postings p JOIN invoice_drafts d ON d.business_id=p.business_id AND d.id=p.invoice_id WHERE p.business_id=? ORDER BY p.document_number,p.invoice_id',
          [businessId.value],
        )
        .map(
          (row) => (
            sourceDraft: Invoice.fromDraftSnapshot(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
            customerSnapshot: decodeCustomer(row['customer_payload'] as String),
            paidMinor: row['paid_minor'] as int,
            creditedMinor: row['credited_minor'] as int,
            documentNumber: row['document_number'] as String,
            journalId: EntityId.parse(row['journal_id'] as String),
          ),
        )
        .toList(growable: false);
  }

  Customer _validateSalesDraftReferences(
    EntityId businessId,
    Invoice invoice, {
    bool quotation = false,
  }) {
    _validateLineTaxSnapshots(
      businessId,
      invoice.lines,
      invoice.issueDate,
      TaxApplication.sales,
    );
    _validateSalesCatalogueReferences(
      businessId,
      invoice,
      quotation: quotation,
    );
    final customers = _database.select(
      'SELECT payload FROM customers WHERE business_id=? AND id=?',
      [businessId.value, invoice.customerId.value],
    );
    if (customers.isEmpty ||
        !decodeCustomer(customers.single['payload'] as String).isActive) {
      throw StateError('Choose an active customer in this company.');
    }
    // Recheck selected accounts under the same write lock as the draft save.
    // An editor can stay open while master records change. Legacy amount-only
    // and product lines without a category retain their existing contract.
    for (final accountId
        in invoice.lines
            .map((line) => line.categoryId)
            .whereType<EntityId>()
            .toSet()) {
      final accounts = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, accountId.value],
      );
      if (accounts.isEmpty ||
          accounts.single['type'] != AccountType.income.name ||
          accounts.single['status'] != AccountStatus.active.name ||
          accounts.single['is_parent'] != 0) {
        throw StateError(
          'Choose an active income account for each line in this company.',
        );
      }
    }
    return decodeCustomer(customers.single['payload'] as String);
  }

  int saveInvoiceDraft({
    required EntityId businessId,
    required EntityId actorId,
    required Invoice invoice,
    required int expectedRevision,
    required DateTime savedAt,
    DocumentRecurrenceRequest? recurrence,
  }) {
    _ensureOpen();
    late int revision;
    _transaction(() {
      revision = _saveInvoiceDraftInSnapshot(
        businessId: businessId,
        actorId: actorId,
        invoice: invoice,
        expectedRevision: expectedRevision,
        savedAt: savedAt,
      );
      if (recurrence != null) {
        _saveInlineDocumentSchedule(
          businessId,
          actorId,
          RecurringDocumentKind.invoice,
          invoice.id,
          revision,
          recurrence,
          savedAt,
        );
      }
    });
    return revision;
  }

  int _saveInvoiceDraftInSnapshot({
    required EntityId businessId,
    required EntityId actorId,
    required Invoice invoice,
    required int expectedRevision,
    required DateTime savedAt,
    bool quotationConversion = false,
  }) {
    if (_database.autocommit) {
      throw StateError('Invoice saves require a transaction.');
    }
    final payload = jsonEncode(invoice.draftSnapshot());
    var revision = expectedRevision + 1;
    _requireReconciliationOwner(businessId, actorId);
    if (_database.select(
      'SELECT 1 FROM invoice_postings WHERE business_id=? AND invoice_id=?',
      [businessId.value, invoice.id.value],
    ).isNotEmpty) {
      throw StateError(
        'Posted invoices cannot be edited. Use a linked correction.',
      );
    }
    if (invoice.documentNumber.isNotEmpty) {
      final reservation = _database.select(
        "SELECT record_id FROM document_numbers WHERE business_id=? AND document_type='invoice' AND number=?",
        [businessId.value, invoice.documentNumber],
      );
      if (reservation.isNotEmpty &&
          reservation.single['record_id'] != invoice.id.value) {
        throw StateError('This invoice number is reserved for another record.');
      }
    }
    _validateSalesDraftReferences(businessId, invoice);
    final rows = _database.select(
      'SELECT * FROM invoice_drafts WHERE business_id=? AND id=?',
      [businessId.value, invoice.id.value],
    );
    if (rows.isEmpty) {
      if (invoice.sourceEstimateId != null && !quotationConversion) {
        throw StateError(
          'Use the quotation conversion command to create a linked invoice.',
        );
      }
      if (expectedRevision != 0) {
        throw StateError('New invoice drafts start at revision zero.');
      }
    } else {
      final existing = rows.single;
      final original = Invoice.fromDraftSnapshot(
        jsonDecode(existing['payload'] as String) as Map<String, dynamic>,
      );
      if (original.sourceEstimateId != invoice.sourceEstimateId ||
          invoice.lines.any((line) {
            final saved = original.lines
                .where((old) => old.id == line.id)
                .firstOrNull;
            return saved != null && saved.sourceLineId != line.sourceLineId;
          })) {
        throw StateError(
          'Preserve the saved quotation and source-line identities when editing an invoice.',
        );
      }
      if (existing['archived_at'] != null) {
        throw StateError('Restore this invoice draft before editing.');
      }
      if (existing['payload'] == payload &&
          existing['revision'] == expectedRevision + 1) {
        revision = existing['revision'] as int;
        _queueGeneratedDocument(
          businessId: businessId,
          recordId: invoice.id,
          kind: GeneratedDocumentKind.invoice,
          revision: revision,
          attachments: invoice.attachments,
        );
        return revision;
      }
      if (existing['revision'] != expectedRevision) {
        throw StateError('Invoice changed. Reload before saving.');
      }
      if (!savedAt.toUtc().isAfter(
        DateTime.parse(existing['saved_at'] as String),
      )) {
        throw StateError('Invoice revisions require a later save time.');
      }
    }
    _database.execute(
      'INSERT INTO invoice_drafts(business_id,id,revision,payload,saved_at) VALUES (?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,saved_at=excluded.saved_at',
      [
        businessId.value,
        invoice.id.value,
        revision,
        payload,
        savedAt.toUtc().toIso8601String(),
      ],
    );
    _database.execute(
      'INSERT INTO invoice_draft_history(business_id,id,revision,payload) VALUES (?,?,?,?)',
      [businessId.value, invoice.id.value, revision, payload],
    );
    _appendAudit(
      businessId: businessId,
      actorId: actorId,
      at: savedAt,
      kind: 'invoice_draft_saved',
      subjectId: invoice.id,
      detail: jsonEncode({'revision': revision}),
    );
    if (rows.isEmpty && !quotationConversion) {
      _appendTransactionRootCreated(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        family: 'invoice',
        recordId: invoice.id,
      );
    }
    _queueGeneratedDocument(
      businessId: businessId,
      recordId: invoice.id,
      kind: GeneratedDocumentKind.invoice,
      revision: revision,
      attachments: invoice.attachments,
    );
    return revision;
  }

  /// Posts the exact reviewed draft; does not send an email or submit an e-Invoice.
  ClaimPaymentBatch settleRecognizedClaims({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required List<Claim> reviewedClaims,
    required EntityId bankAccountId,
    required String paymentReference,
    required DateTime paidAt,
    String? paymentAccountId,
  }) {
    _ensureOpen();
    final reference = paymentReference.trim();
    if (reference.isEmpty || reference.length > 120 || reviewedClaims.isEmpty) {
      throw ArgumentError(
        'Select claims and a payment reference of 1–120 characters.',
      );
    }
    final ordered = [...reviewedClaims]
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    if (ordered.map((c) => c.id).toSet().length != ordered.length) {
      throw ArgumentError('A claim cannot be allocated twice.');
    }
    final signature = jsonEncode([
      ordered.map((c) => c.toJson()).toList(),
      bankAccountId.value,
      reference,
      paidAt.toUtc().toIso8601String(),
      actorId.value,
      if (paymentAccountId != null) ['paymentAccountId', paymentAccountId],
    ]);
    late ClaimPaymentBatch result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT signature FROM claim_settlements WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError('Settlement request was reused for different work.');
        }
        final rows = _database.select(
          'SELECT paid_payload FROM claim_settlement_allocations WHERE business_id=? AND request_id=? ORDER BY claim_id',
          [businessId.value, requestId.value],
        );
        result = ClaimPaymentBatch.restore(
          id: requestId,
          paidAt: paidAt,
          claims: rows
              .map(
                (r) => Claim.fromJson(
                  jsonDecode(r['paid_payload'] as String)
                      as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
        return;
      }
      if (paymentAccountId != null) {
        final payment = readPaymentAccounts(businessId)
            .where((p) => p.id == paymentAccountId)
            .firstOrNull;
        if (payment == null ||
            payment.type == PaymentAccountType.card ||
            payment.currency.code != ordered.first.amount.currency ||
            paymentLedgerAccount(businessId, paymentAccountId) !=
                bankAccountId) {
          throw StateError(
            'Choose a payment account linked to the reviewed bank ledger and currency.',
          );
        }
      }
      final bank = _database.select(
        'SELECT * FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, bankAccountId.value],
      );
      if (bank.isEmpty ||
          bank.single['type'] != AccountType.asset.name ||
          bank.single['status'] != 'active' ||
          bank.single['is_parent'] != 0) {
        throw StateError(
          'Choose an active bank/cash asset posting account in this company.',
        );
      }
      final lines = <JournalLine>[];
      for (final claim in ordered) {
        final stored = _database.select(
          'SELECT payload FROM claims WHERE business_id=? AND id=?',
          [businessId.value, claim.id.value],
        );
        if (stored.isEmpty ||
            _normalizedClaimPayload(stored.single['payload'] as String) !=
                jsonEncode(claim.toJson()) ||
            claim.status != ClaimStatus.approved) {
          throw StateError(
            'A reviewed claim changed or is no longer approved.',
          );
        }
        final recognition = _database.select(
          "SELECT p.* FROM all_claim_postings p JOIN journal_entries j ON j.id=p.journal_id AND j.business_id=p.business_id WHERE p.business_id=? AND p.claim_id=? AND j.state='posted' AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.business_id=p.business_id AND r.reverses_id=p.journal_id AND r.state='posted')",
          [businessId.value, claim.id.value],
        );
        if (recognition.isEmpty) {
          throw StateError('Recognize the claim liability before settlement.');
        }
        final linked = recognition.single;
        final original = Claim.fromJson(
          jsonDecode(linked['claim_payload'] as String) as Map<String, dynamic>,
        );
        if (_approvedRecognitionPayload(original) !=
            jsonEncode(claim.toJson())) {
          throw StateError(
            'The claim no longer matches its recognized liability.',
          );
        }
        final position = _claimReimbursementPosition(
          businessId: businessId,
          claimId: claim.id,
          through: paidAt,
        );
        if (position == null ||
            position.currency != claim.amount.currency ||
            position.outstandingMinor != BigInt.from(claim.amount.minorUnits)) {
          throw StateError(
            'Review the current recognized and reimbursed Claim balance before payment.',
          );
        }
        if (paidAt.toUtc().isBefore(claim.incurredOn!)) {
          throw StateError('Payment cannot precede the claim expense date.');
        }
        if (_database.select(
          "SELECT 1 FROM journal_entries WHERE reverses_id=? AND state='posted'",
          [linked['journal_id']],
        ).isNotEmpty) {
          throw StateError('A reversed claim liability cannot be settled.');
        }
        lines.add(
          JournalLine.debit(
            accountId: EntityId.parse(linked['liability_account_id'] as String),
            amount: claim.amount,
          ),
        );
      }
      result = ClaimPaymentBatch.create(
        id: requestId,
        claims: ordered,
        paidAt: paidAt,
        paymentReference: reference,
      );
      lines.add(
        JournalLine.credit(accountId: bankAccountId, amount: result.total),
      );
      final device =
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']
              as String;
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: paidAt,
            memo: 'Claim payment $reference',
            lines: lines,
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: paidAt.subtract(const Duration(microseconds: 1)),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: requestId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: paidAt,
        ),
      );
      _database.execute(
        'INSERT INTO claim_settlements(business_id,request_id,journal_id,reference,signature) VALUES(?,?,?,?,?)',
        [
          businessId.value,
          requestId.value,
          requestId.value,
          reference,
          signature,
        ],
      );
      for (final claim in result.claims) {
        final payload = jsonEncode(claim.toJson());
        _database.execute(
          'INSERT INTO claim_settlement_allocations(business_id,request_id,claim_id,amount_minor,currency,paid_payload) VALUES(?,?,?,?,?,?)',
          [
            businessId.value,
            requestId.value,
            claim.id.value,
            claim.amount.minorUnits,
            claim.amount.currency,
            payload,
          ],
        );
        _database.execute(
          'UPDATE claims SET payload=? WHERE business_id=? AND id=?',
          [payload, businessId.value, claim.id.value],
        );
      }
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: paidAt,
        kind: 'claims_settled',
        subjectId: requestId,
        detail: jsonEncode({
          'reference': reference,
          'claimIds': result.claimIds.map((id) => id.value).toList(),
        }),
      );
      _appendTransactionRootCreated(
        businessId: businessId,
        actorId: actorId,
        at: paidAt,
        family: 'claimSettlement',
        recordId: requestId,
      );
    });
    return result;
  }

  // Historical recognition already proved approval. A data-only restore can
  // lack receipt bytes; changing its comparison status must not approve again.
  String _approvedRecognitionPayload(Claim claim) =>
      jsonEncode(claim.toJson()..['status'] = ClaimStatus.approved.name);

  // Decode persisted and reviewed snapshots through the same domain contract.
  // Data-only restores normalize missing receipt bytes and JSON key order.
  String _normalizedClaimPayload(String payload) => jsonEncode(
    Claim.fromJson(jsonDecode(payload) as Map<String, dynamic>).toJson(),
  );

  List<Row> _activeClaimPostings(EntityId businessId, EntityId claimId) =>
      _database.select(
        "SELECT p.* FROM all_claim_postings p JOIN journal_entries j ON j.id=p.journal_id AND j.business_id=p.business_id WHERE p.business_id=? AND p.claim_id=? AND j.state='posted' AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.business_id=p.business_id AND r.reverses_id=p.journal_id AND r.state='posted')",
        [businessId.value, claimId.value],
      );

  EntityId? activeClaimRecognitionId(EntityId businessId, EntityId claimId) {
    _ensureOpen();
    final revisions = _claimExpenseRevisionSources(businessId)
        .where(
          (row) =>
              row['claim_id'] == claimId.value &&
              _database.select(
                "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' LIMIT 1",
                [businessId.value, row['journal_id']],
              ).isEmpty,
        )
        .toList();
    final rows = _activeClaimPostings(businessId, claimId);
    if (rows.length + revisions.length > 1) {
      throw StateError('Claim has conflicting active recognitions.');
    }
    if (revisions.isNotEmpty) {
      return EntityId.parse(revisions.single['journal_id'] as String);
    }
    return rows.isEmpty
        ? null
        : EntityId.parse(rows.single['journal_id'] as String);
  }

  /// Reverse an unpaid recognition and its exact reviewed status atomically.
  EntityId reverseClaimRecognition({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required Claim reviewedClaim,
    required EntityId expectedRecognitionJournalId,
    required ClaimRecognitionDecision decision,
    required DateTime reversedOn,
    required String reason,
    required DateTime changedAt,
  }) {
    _ensureOpen();
    final explanation = reason.trim();
    if (explanation.isEmpty || explanation.length > 500) {
      throw ArgumentError('Enter a correction reason of 1–500 characters.');
    }
    final snapshot = jsonEncode(reviewedClaim.toJson());
    final signature = jsonEncode([
      snapshot,
      expectedRecognitionJournalId.value,
      decision.name,
      _calendarDay(reversedOn),
      explanation,
      actorId.value,
      changedAt.toUtc().toIso8601String(),
    ]);
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT signature FROM claim_posting_reversals WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError(
            'Claim reversal request was reused for different work.',
          );
        }
        return;
      }
      final current = _database.select(
        'SELECT payload FROM claims WHERE business_id=? AND id=?',
        [businessId.value, reviewedClaim.id.value],
      );
      if (current.isEmpty ||
          _normalizedClaimPayload(current.single['payload'] as String) !=
              snapshot ||
          reviewedClaim.status != ClaimStatus.approved) {
        throw StateError(
          'The reviewed claim changed or is no longer approved.',
        );
      }
      final active = _activeClaimPostings(businessId, reviewedClaim.id);
      if (active.length != 1 ||
          active.single['journal_id'] != expectedRecognitionJournalId.value) {
        throw StateError(
          'The reviewed claim recognition changed. Reopen before correcting.',
        );
      }
      final recognition = active.single;
      final originalClaim = Claim.fromJson(
        jsonDecode(recognition['claim_payload'] as String)
            as Map<String, dynamic>,
      );
      if (_approvedRecognitionPayload(originalClaim) != snapshot) {
        throw StateError(
          'The claim no longer matches its recognized liability.',
        );
      }
      if (_database.select(
        'SELECT 1 FROM claim_settlement_allocations WHERE business_id=? AND claim_id=?',
        [businessId.value, reviewedClaim.id.value],
      ).isNotEmpty) {
        throw StateError(
          'A settled claim cannot be returned or voided through this action.',
        );
      }
      final original = _readJournal(expectedRecognitionJournalId);
      if (original == null ||
          original.metadata.businessId != businessId ||
          original.metadata.isTombstone ||
          original.entry.state != JournalEntryState.posted ||
          original.entry.reversesId != null ||
          !changedAt.toUtc().isAfter(original.metadata.updatedAt)) {
        throw StateError(
          'The claim recognition is unavailable or the correction time is stale.',
        );
      }
      final result = switch (decision) {
        ClaimRecognitionDecision.returnForCorrection =>
          reviewedClaim.returnForCorrection(),
        ClaimRecognitionDecision.voidClaim => reviewedClaim.voidClaim(),
      };
      final reversal = original.entry.reversal(
        id: requestId,
        date: reversedOn,
        memo:
            'Claim ${decision == ClaimRecognitionDecision.voidClaim ? 'void' : 'return'}: $explanation',
      );
      _writeJournal(
        StoredJournalEntry(
          entry: reversal,
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: original.metadata.originDeviceId,
            createdAt: changedAt.subtract(const Duration(microseconds: 1)),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: requestId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: changedAt,
        ),
        linkedClaimReversal: expectedRecognitionJournalId,
      );
      _database.execute(
        'INSERT INTO claim_posting_reversals(business_id,claim_id,request_id,source_journal_id,journal_id,decision,reversed_on,reason,reviewed_payload,result_payload,signature) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          reviewedClaim.id.value,
          requestId.value,
          expectedRecognitionJournalId.value,
          requestId.value,
          decision.name,
          _calendarDay(reversedOn),
          explanation,
          snapshot,
          jsonEncode(result.toJson()),
          signature,
        ],
      );
      _database.execute(
        'UPDATE claims SET payload=? WHERE business_id=? AND id=?',
        [jsonEncode(result.toJson()), businessId.value, reviewedClaim.id.value],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: 'claim_recognition_reversed',
        subjectId: reviewedClaim.id,
        detail: jsonEncode({
          'sourceJournalId': expectedRecognitionJournalId.value,
          'journalId': requestId.value,
          'decision': decision.name,
          'reason': explanation,
        }),
      );
    });
    return requestId;
  }

  /// Labels come from the exact claim reviewed for the posted recognition,
  /// rather than the mutable/current reimbursement lifecycle snapshot.
  Map<EntityId, Claim> readClaimRecognitionSnapshots(EntityId businessId) {
    _ensureOpen();
    final result = <EntityId, Claim>{};
    for (final row in _database.select(
      "SELECT p.journal_id,p.claim_id,p.claim_payload FROM all_claim_postings p JOIN journal_entries j ON j.id=p.journal_id AND j.business_id=p.business_id WHERE p.business_id=? AND j.state='posted' ORDER BY p.journal_id",
      [businessId.value],
    )) {
      final claim = Claim.fromJson(
        jsonDecode(row['claim_payload'] as String) as Map<String, dynamic>,
      );
      if (claim.id.value != row['claim_id']) {
        throw const FormatException('Claim recognition snapshot ID mismatch.');
      }
      result[EntityId.parse(row['journal_id'] as String)] = claim;
    }
    for (final row in _claimExpenseRevisionSources(businessId)) {
      result[EntityId.parse(row['journal_id'] as String)] = Claim.fromJson(
        jsonDecode(row['claim_payload'] as String) as Map<String, dynamic>,
      );
    }
    return Map.unmodifiable(result);
  }

  EntityId approveClaimPosting({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required Claim reviewedClaim,
    EntityId? expenseAccountId,
    Map<String, EntityId>? expenseLineAccounts,
    required EntityId liabilityAccountId,
    required DateTime approvedAt,
  }) {
    _ensureOpen();
    final snapshot = jsonEncode(reviewedClaim.toJson());
    if (reviewedClaim.expenseDraft == null && expenseLineAccounts != null) {
      throw StateError(
        'Legacy Claim receipt allocations cannot be overridden.',
      );
    }
    final recognitionClaim = reviewedClaim.expenseDraft == null
        ? reviewedClaim
        : reviewedClaim.withExpensePostingAccounts(
            expenseLineAccounts ?? const {},
          );
    final signature = jsonEncode([
      snapshot,
      expenseAccountId?.value,
      liabilityAccountId.value,
      actorId.value,
      approvedAt.toUtc().toIso8601String(),
      if (reviewedClaim.expenseDraft != null)
        {
          for (final line in reviewedClaim.expenseDraft!.lines)
            line.id: expenseLineAccounts![line.id]!.value,
        },
    ]);
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT * FROM all_claim_postings WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError(
            'Claim posting request was reused for different work.',
          );
        }
        _writeClaimExpenseInTransaction(retry.single);
        return;
      }
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.claim,
        reviewedClaim.id.value,
      );
      final rows = _database.select(
        'SELECT payload FROM claims WHERE business_id=? AND id=?',
        [businessId.value, reviewedClaim.id.value],
      );
      if (rows.isEmpty ||
          _normalizedClaimPayload(rows.single['payload'] as String) !=
              snapshot) {
        throw StateError('The reviewed claim changed or is unavailable.');
      }
      if (reviewedClaim.status != ClaimStatus.submitted ||
          reviewedClaim.incurredOn == null ||
          !reviewedClaim.amount.isPositive) {
        throw StateError(
          'A submitted positive claim with an expense date is required.',
        );
      }
      if (_activeClaimPostings(businessId, reviewedClaim.id).isNotEmpty) {
        throw StateError('The claim expense is already recognized.');
      }
      _validateClaimTaxSnapshots(
        businessId,
        recognitionClaim,
        historical: true,
      );
      final chart = _database
          .select('SELECT * FROM accounts WHERE business_id=?', [
            businessId.value,
          ])
          .map((r) => _accountFromRow(r).account)
          .toList();
      final liability = chart
          .where((a) => a.id == liabilityAccountId)
          .firstOrNull;
      if (liability == null) {
        throw StateError('Choose a liability account in this company.');
      }
      final costs = recognitionClaim.receiptCostAllocations;
      if (recognitionClaim.receipts.isEmpty) {
        final expense = chart
            .where((a) => a.id == expenseAccountId)
            .firstOrNull;
        if (expense == null || expense.type != AccountType.expense) {
          throw StateError('Choose an active expense account in this company.');
        }
      } else if (expenseAccountId != null &&
          (costs.length != 1 || costs.keys.single != expenseAccountId)) {
        throw StateError(
          'Receipt allocations own the posting accounts; a different single expense override is not permitted.',
        );
      }
      final proposal = ClaimRecognitionProposal.create(
        claim: recognitionClaim,
        liabilityAccount: liability,
        accounts: chart,
        allocations: recognitionClaim.receipts.isEmpty
            ? [
                JournalLine.debit(
                  accountId: expenseAccountId!,
                  amount: reviewedClaim.amount,
                ),
              ]
            : [
                for (final entry in costs.entries)
                  JournalLine.debit(accountId: entry.key, amount: entry.value),
              ],
      );
      final device =
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']
              as String;
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: reviewedClaim.incurredOn!,
            memo: 'Claim ${reviewedClaim.vendorName}',
            lines: proposal.lines,
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: approvedAt.subtract(const Duration(microseconds: 1)),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: requestId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: approvedAt,
        ),
      );
      final postingTable =
          _database.select(
            'SELECT 1 FROM claim_postings WHERE business_id=? AND claim_id=?',
            [businessId.value, reviewedClaim.id.value],
          ).isEmpty
          ? 'claim_postings'
          : 'claim_posting_cycles';
      _database.execute(
        'INSERT INTO $postingTable(business_id,claim_id,request_id,journal_id,liability_account_id,claim_payload,signature) VALUES(?,?,?,?,?,?,?)',
        [
          businessId.value,
          reviewedClaim.id.value,
          requestId.value,
          requestId.value,
          liabilityAccountId.value,
          jsonEncode(recognitionClaim.toJson()),
          signature,
        ],
      );
      _writeClaimExpenseInTransaction(
        _database.select(
          'SELECT * FROM all_claim_postings WHERE business_id=? AND request_id=?',
          [businessId.value, requestId.value],
        ).single,
      );
      _database.execute(
        'UPDATE claims SET payload=? WHERE business_id=? AND id=?',
        [
          jsonEncode(recognitionClaim.approve().toJson()),
          businessId.value,
          reviewedClaim.id.value,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvedAt,
        kind: 'claim_recognized',
        subjectId: reviewedClaim.id,
        detail: jsonEncode({'journalId': requestId.value}),
      );
    });
    return requestId;
  }

  int setInvoiceDraftArchived({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId invoiceId,
    required int expectedRevision,
    required bool archived,
    required DateTime changedAt,
  }) {
    _ensureOpen();
    late int revision;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      if (_database.select(
        'SELECT 1 FROM invoice_postings WHERE business_id=? AND invoice_id=?',
        [businessId.value, invoiceId.value],
      ).isNotEmpty) {
        throw StateError(
          'Posted invoices cannot be removed or restored as drafts.',
        );
      }
      final rows = _database.select(
        'SELECT * FROM invoice_drafts WHERE business_id=? AND id=?',
        [businessId.value, invoiceId.value],
      );
      if (rows.isEmpty) throw StateError('Invoice draft is unavailable.');
      final row = rows.single;
      final currentArchived = row['archived_at'] != null;
      revision = row['revision'] as int;
      if (currentArchived == archived &&
          revision == expectedRevision + 1 &&
          row['saved_at'] == changedAt.toUtc().toIso8601String()) {
        return;
      }
      if (revision != expectedRevision || currentArchived == archived) {
        throw StateError(
          'Invoice changed. Reload before changing its archive state.',
        );
      }
      if (!changedAt.toUtc().isAfter(
        DateTime.parse(row['saved_at'] as String),
      )) {
        throw StateError('Archive changes require a later time.');
      }
      revision++;
      _database.execute(
        'UPDATE invoice_drafts SET archived_at=?,revision=?,saved_at=? WHERE business_id=? AND id=?',
        [
          archived ? changedAt.toUtc().toIso8601String() : null,
          revision,
          changedAt.toUtc().toIso8601String(),
          businessId.value,
          invoiceId.value,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: archived ? 'invoice_draft_archived' : 'invoice_draft_restored',
        subjectId: invoiceId,
        detail: jsonEncode({'revision': revision}),
      );
    });
    return revision;
  }

  ({
    EntityId receivable,
    EntityId income,
    EntityId? tax,
    Map<EntityId, EntityId> lineIncome,
  })?
  invoicePostingAccounts(EntityId businessId, EntityId invoiceId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT signature FROM invoice_postings WHERE business_id=? AND invoice_id=?',
      [businessId.value, invoiceId.value],
    );
    if (rows.isEmpty) return null;
    final signature =
        jsonDecode(rows.single['signature'] as String) as List<dynamic>;
    if ((signature.length != 9 && signature.length != 10) ||
        signature.first != invoiceId.value) {
      throw StateError('Unsupported invoice posting account snapshot.');
    }
    final overrides = <EntityId, EntityId>{};
    if (signature.length == 10) {
      for (final pair in signature[9] as List<dynamic>) {
        final line = EntityId.parse(pair[0] as String);
        if (overrides.containsKey(line)) {
          throw StateError('Duplicate invoice posting line mapping.');
        }
        overrides[line] = EntityId.parse(pair[1] as String);
      }
    }
    return (
      receivable: EntityId.parse(signature[4] as String),
      income: EntityId.parse(signature[5] as String),
      tax: signature[6] == null ? null : EntityId.parse(signature[6] as String),
      lineIncome: Map.unmodifiable(overrides),
    );
  }

  List<
    ({
      EntityId id,
      EntityId invoiceId,
      int revision,
      DateTime savedAt,
      Map<String, dynamic> snapshot,
    })
  >
  readInvoiceCreditDrafts(EntityId businessId, {bool includeRemoved = false}) {
    _ensureOpen();
    return _database
        .select(
          'SELECT * FROM invoice_credit_drafts WHERE business_id=? AND ${includeRemoved ? '1' : _activeTransactionSql(TransactionRecordKind.invoiceCredit)} ORDER BY saved_at DESC,id',
          [businessId.value],
        )
        .map(
          (row) => (
            id: EntityId.parse(row['id'] as String),
            invoiceId: EntityId.parse(row['invoice_id'] as String),
            revision: row['revision'] as int,
            savedAt: DateTime.parse(row['saved_at'] as String),
            snapshot:
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  List<({int revision, DateTime savedAt, Map<String, dynamic> snapshot})>
  invoiceCreditDraftHistory(EntityId businessId, EntityId draftId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT revision,saved_at,payload FROM invoice_credit_draft_history WHERE business_id=? AND id=? ORDER BY revision DESC',
          [businessId.value, draftId.value],
        )
        .map(
          (row) => (
            revision: row['revision'] as int,
            savedAt: DateTime.parse(row['saved_at'] as String),
            snapshot:
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Map<EntityId, Money> invoicePriorCreditLines(
    EntityId businessId,
    EntityId invoiceId,
  ) {
    _ensureOpen();
    return Map.unmodifiable({
      for (final row in _database.select(
        'SELECT l.line_id,SUM(l.gross_minor) AS gross,l.currency FROM invoice_credit_lines l JOIN invoice_credit_postings p ON p.business_id=l.business_id AND p.draft_id=l.draft_id WHERE p.business_id=? AND p.invoice_id=? GROUP BY l.line_id,l.currency',
        [businessId.value, invoiceId.value],
      ))
        EntityId.parse(row['line_id'] as String): Money.fromMinor(
          row['gross'] as int,
          row['currency'] as String,
        ),
    });
  }

  ({
    EntityId journalId,
    int revision,
    Money receivableReduction,
    Money customerCredit,
  })?
  invoiceCreditPosting(EntityId businessId, EntityId draftId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM invoice_credit_postings WHERE business_id=? AND draft_id=?',
      [businessId.value, draftId.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (
      journalId: EntityId.parse(row['journal_id'] as String),
      revision: row['revision'] as int,
      receivableReduction: Money.fromMinor(
        row['receivable_minor'] as int,
        row['currency'] as String,
      ),
      customerCredit: Money.fromMinor(
        row['customer_credit_minor'] as int,
        row['currency'] as String,
      ),
    );
  }

  EntityId postInvoiceCredit({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required EntityId draftId,
    required int expectedRevision,
    required int expectedPaidMinor,
    required int expectedPriorCreditMinor,
    required DateTime approvedAt,
    EntityId? customerCreditAccount,
  }) {
    _ensureOpen();
    final signature = jsonEncode([
      draftId.value,
      expectedRevision,
      expectedPaidMinor,
      expectedPriorCreditMinor,
      customerCreditAccount?.value,
      actorId.value,
      approvedAt.toUtc().toIso8601String(),
    ]);
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT signature FROM invoice_credit_postings WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError('Credit request was reused for different work.');
        }
        return;
      }
      if (_database.select(
        'SELECT 1 FROM invoice_credit_postings WHERE business_id=? AND draft_id=?',
        [businessId.value, draftId.value],
      ).isNotEmpty) {
        throw StateError('Credit is already posted.');
      }
      final row = readInvoiceCreditDrafts(businessId)
          .where((r) => r.id == draftId)
          .firstOrNull;
      if (row == null || row.revision != expectedRevision) {
        throw StateError('Credit draft changed; review again.');
      }
      final draft = InvoiceCreditDraft.fromSnapshot(
        id: row.id,
        invoiceId: row.invoiceId,
        revision: row.revision,
        savedAt: row.savedAt,
        snapshot: row.snapshot,
      );
      if (draft.attachments.isEmpty ||
          draft.attachments.any(
            (a) => a.status != AttachmentProcessingStatus.ready,
          )) {
        throw StateError(
          'Review ready supporting evidence before posting credit.',
        );
      }
      if (approvedAt.toUtc().isBefore(draft.savedAt.toUtc())) {
        throw StateError('Approval cannot precede the saved draft.');
      }
      final invoice = readPostedInvoices(businessId)
          .singleWhere((r) => r.sourceDraft.id == draft.invoiceId);
      final prior = invoicePriorCreditLines(businessId, draft.invoiceId);
      final totalPrior = prior.values.fold(
        Money.zero(draft.total.currency),
        (a, b) => a + b,
      );
      if (invoice.paidMinor != expectedPaidMinor ||
          totalPrior.minorUnits != expectedPriorCreditMinor) {
        throw StateError('Invoice payments or credits changed; review again.');
      }
      final amounts = allocateInvoiceCreditLines(
        originalLines: invoice.sourceDraft.lines,
        priorGrossCredits: prior,
        requestedGrossCredits: draft.lineCredits,
      );
      final allocation = InvoiceCreditAllocation.calculate(
        invoiceTotal: invoice.sourceDraft.total,
        priorCredits: totalPrior,
        receiptsApplied: Money.fromMinor(
          invoice.paidMinor,
          draft.total.currency,
        ),
        credit: draft.total,
      );
      final original = invoicePostingAccounts(businessId, draft.invoiceId)!;
      void account(EntityId id, AccountType type) {
        final rows = _database.select(
          'SELECT * FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, id.value],
        );
        if (rows.isEmpty ||
            rows.single['type'] != type.name ||
            rows.single['status'] != 'active' ||
            rows.single['is_parent'] != 0) {
          throw StateError('Credit account is unavailable for posting.');
        }
      }

      account(original.receivable, AccountType.asset);
      for (final id in amounts.keys) {
        account(original.lineIncome[id] ?? original.income, AccountType.income);
      }
      if (amounts.values.any((a) => a.tax.isPositive)) {
        if (original.tax == null) {
          throw StateError('Original tax account is missing.');
        }
        account(original.tax!, AccountType.liability);
      }
      if (allocation.customerCredit.isPositive) {
        if (customerCreditAccount == null ||
            customerCreditAccount == original.tax) {
          throw StateError(
            'Choose a separate customer credit liability account.',
          );
        }
        account(customerCreditAccount, AccountType.liability);
      }
      final lines = buildInvoiceCreditJournal(
        lineCredits: amounts,
        originalLineIncomeAccounts: original.lineIncome,
        originalIncomeAccount: original.income,
        originalReceivableAccount: original.receivable,
        originalTaxAccount: original.tax,
        customerCreditAccount: customerCreditAccount,
        allocation: allocation,
      );
      final device =
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']
              as String;
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: draft.date,
            memo: 'Credit for ${invoice.documentNumber}: ${draft.reason}',
            lines: lines,
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: draft.savedAt,
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: requestId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: approvedAt,
        ),
      );
      _database.execute(
        'INSERT INTO invoice_credit_postings VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          draftId.value,
          draft.invoiceId.value,
          requestId.value,
          requestId.value,
          expectedRevision,
          signature,
          allocation.receivableReduction.minorUnits,
          allocation.customerCredit.minorUnits,
          draft.total.currency,
        ],
      );
      for (final line in amounts.entries) {
        _database.execute(
          'INSERT INTO invoice_credit_lines VALUES(?,?,?,?,?,?,?)',
          [
            businessId.value,
            draftId.value,
            line.key.value,
            line.value.total.minorUnits,
            line.value.net.minorUnits,
            line.value.tax.minorUnits,
            draft.total.currency,
          ],
        );
      }
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvedAt,
        kind: 'invoice_credit_posted',
        subjectId: draftId,
        detail: signature,
      );
    });
    return requestId;
  }

  int saveInvoiceCreditDraft({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId draftId,
    required EntityId invoiceId,
    required Map<EntityId, Money> lineCredits,
    required String reason,
    required DateTime creditDate,
    required int expectedRevision,
    required DateTime savedAt,
    List<ReceiptAttachment> attachments = const [],
  }) {
    _ensureOpen();
    if (attachments.map((a) => a.originalId).toSet().length !=
        attachments.length) {
      throw ArgumentError('Credit attachments must have unique identities.');
    }
    for (final a in attachments) {
      ReceiptAttachment.fromJson(a.toJson());
    }
    if (reason.trim().isEmpty || expectedRevision < 0) {
      throw ArgumentError('A credit reason and valid revision are required.');
    }
    final ordered = lineCredits.entries.toList()
      ..sort((a, b) => a.key.value.compareTo(b.key.value));
    final payload = jsonEncode({
      'invoiceId': invoiceId.value,
      'reason': reason.trim(),
      'date': accountingCalendarDate(creditDate).toIso8601String(),
      if (attachments.isNotEmpty)
        'attachments': [for (final a in attachments) a.toJson()],
      'lines': [
        for (final e in ordered)
          {
            'id': e.key.value,
            'minor': e.value.minorUnits,
            'currency': e.value.currency,
          },
      ],
    });
    final revision = expectedRevision + 1;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      if (_database.select(
        'SELECT 1 FROM invoice_credit_postings WHERE business_id=? AND draft_id=?',
        [businessId.value, draftId.value],
      ).isNotEmpty) {
        throw StateError('Posted credits cannot be edited or restored.');
      }
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.invoiceCredit,
        draftId.value,
      );
      final invoice = readPostedInvoices(businessId)
          .where((r) => r.sourceDraft.id == invoiceId)
          .firstOrNull;
      if (invoice == null) {
        throw StateError('Choose a posted invoice in this company.');
      }
      if (accountingCalendarDate(creditDate)
          .isBefore(accountingCalendarDate(invoice.sourceDraft.issueDate))) {
        throw StateError('Credit date cannot precede the invoice.');
      }
      allocateInvoiceCreditLines(
        originalLines: invoice.sourceDraft.lines,
        priorGrossCredits: invoicePriorCreditLines(businessId, invoiceId),
        requestedGrossCredits: lineCredits,
      );
      final rows = _database.select(
        'SELECT * FROM invoice_credit_drafts WHERE business_id=? AND id=?',
        [businessId.value, draftId.value],
      );
      if (rows.isNotEmpty) {
        final row = rows.single;
        if (row['revision'] == revision &&
            row['payload'] == payload &&
            row['saved_at'] == savedAt.toUtc().toIso8601String()) {
          return;
        }
        if (row['revision'] != expectedRevision ||
            row['invoice_id'] != invoiceId.value ||
            DateTime.parse(row['saved_at'] as String)
                .isAfter(savedAt.toUtc())) {
          throw StateError('Credit draft changed; reload before saving.');
        }
        final historicalOriginals = <String, String>{};
        for (final history in _database.select(
          'SELECT payload FROM invoice_credit_draft_history WHERE business_id=? AND id=?',
          [businessId.value, draftId.value],
        )) {
          final snapshot =
              jsonDecode(history['payload'] as String) as Map<String, dynamic>;
          for (final raw in snapshot['attachments'] as List? ?? const []) {
            final attachment = ReceiptAttachment.fromJson(
              Map<String, dynamic>.from(raw as Map),
            );
            historicalOriginals[attachment.originalId] =
                attachment.originalSha256;
          }
        }
        for (final attachment in attachments) {
          final originalHash = historicalOriginals[attachment.originalId];
          if (originalHash != null &&
              originalHash != attachment.originalSha256) {
            throw StateError(
              'An attachment identity cannot replace its retained original.',
            );
          }
        }
      } else if (expectedRevision != 0) {
        throw StateError('Credit draft does not exist.');
      }
      _database.execute(
        'INSERT INTO invoice_credit_drafts VALUES(?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,saved_at=excluded.saved_at',
        [
          businessId.value,
          draftId.value,
          invoiceId.value,
          payload,
          revision,
          savedAt.toUtc().toIso8601String(),
        ],
      );
      _database.execute(
        'INSERT INTO invoice_credit_draft_history VALUES(?,?,?,?,?)',
        [
          businessId.value,
          draftId.value,
          revision,
          payload,
          savedAt.toUtc().toIso8601String(),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'invoice_credit_draft_saved',
        subjectId: draftId,
        detail: payload,
      );
      if (rows.isEmpty) {
        _appendTransactionRootCreated(
          businessId: businessId,
          actorId: actorId,
          at: savedAt,
          family: 'invoiceCredit',
          recordId: draftId,
        );
      }
    });
    return revision;
  }

  EntityId postInvoice({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required EntityId invoiceId,
    required int expectedRevision,
    required int expectedCustomerRevision,
    required String documentNumber,
    required EntityId receivableAccountId,
    required EntityId incomeAccountId,
    EntityId? taxAccountId,
    Map<EntityId, EntityId> lineIncomeAccounts = const {},
    required DateTime approvedAt,
  }) {
    _ensureOpen();
    final number = documentNumber.trim();
    if (number.isEmpty) {
      throw ArgumentError('A reviewed invoice number is required.');
    }
    final orderedOverrides = lineIncomeAccounts.entries.toList()
      ..sort((a, b) => a.key.value.compareTo(b.key.value));
    final signature = jsonEncode([
      invoiceId.value,
      expectedRevision,
      expectedCustomerRevision,
      number,
      receivableAccountId.value,
      incomeAccountId.value,
      taxAccountId?.value,
      actorId.value,
      approvedAt.toUtc().toIso8601String(),
      if (orderedOverrides.isNotEmpty)
        orderedOverrides.map((e) => [e.key.value, e.value.value]).toList(),
    ]);
    late EntityId journalId;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT * FROM invoice_postings WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError('Posting request was reused for different work.');
        }
        journalId = EntityId.parse(retry.single['journal_id'] as String);
        return;
      }
      if (_database.select(
        'SELECT 1 FROM invoice_postings WHERE business_id=? AND invoice_id=?',
        [businessId.value, invoiceId.value],
      ).isNotEmpty) {
        throw StateError('This invoice is already posted.');
      }
      final reservation = _database.select(
        "SELECT record_id FROM document_numbers WHERE business_id=? AND document_type='invoice' AND number=?",
        [businessId.value, number],
      );
      if (reservation.isNotEmpty &&
          reservation.single['record_id'] != invoiceId.value) {
        throw StateError('This invoice number is reserved for another record.');
      }
      final drafts = _database.select(
        'SELECT * FROM invoice_drafts WHERE business_id=? AND id=?',
        [businessId.value, invoiceId.value],
      );
      if (drafts.isEmpty ||
          drafts.single['revision'] != expectedRevision ||
          drafts.single['archived_at'] != null) {
        throw StateError('The reviewed invoice changed or is unavailable.');
      }
      final draft = drafts.single;
      final invoice = Invoice.fromDraftSnapshot(
        jsonDecode(draft['payload'] as String) as Map<String, dynamic>,
      );
      if (invoice.documentNumber.isNotEmpty &&
          invoice.documentNumber != number) {
        throw StateError(
          'The posting number must match the reviewed invoice draft.',
        );
      }
      final customerRows = _database.select(
        'SELECT payload FROM customers WHERE business_id=? AND id=?',
        [businessId.value, invoice.customerId.value],
      );
      if (customerRows.isEmpty) throw StateError('Customer is unavailable.');
      final customer = decodeCustomer(customerRows.single['payload'] as String);
      if (!customer.isActive ||
          customer.metadata.revision != expectedCustomerRevision) {
        throw StateError('Customer changed. Review the invoice again.');
      }
      void account(EntityId id, AccountType type) {
        final rows = _database.select(
          'SELECT * FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, id.value],
        );
        if (rows.isEmpty ||
            rows.single['type'] != type.name ||
            rows.single['status'] != 'active' ||
            rows.single['is_parent'] != 0) {
          throw StateError(
            'Choose an active posting account of the correct type in this company.',
          );
        }
      }

      account(receivableAccountId, AccountType.asset);
      account(incomeAccountId, AccountType.income);
      final lineIds = invoice.lines.map((line) => line.id).toSet();
      if (lineIncomeAccounts.keys.any((id) => !lineIds.contains(id))) {
        throw StateError(
          'An income account override refers to an unavailable invoice line.',
        );
      }
      for (final id in lineIncomeAccounts.values.toSet()) {
        account(id, AccountType.income);
      }
      var tax = Money.zero(invoice.total.currency);
      for (final line in invoice.lines) {
        tax += line.tax;
      }
      if (tax.isPositive) {
        if (taxAccountId == null) {
          throw StateError(
            'Tax-bearing invoices require a reviewed tax liability account.',
          );
        }
        account(taxAccountId, AccountType.liability);
        final selectedAccounts = invoice.lines
            .where((line) => line.tax.isPositive && line.taxSnapshot != null)
            .map((line) => line.taxSnapshot!.salesAccountId)
            .toSet();
        if (selectedAccounts.any((id) => id != taxAccountId)) {
          throw StateError(
            'The reviewed tax liability account must match the saved tax codes.',
          );
        }
      } else if (taxAccountId != null) {
        throw StateError(
          'A zero-tax invoice must not select a tax posting account.',
        );
      }
      final net = invoice.total - tax;
      if (net.isNegative) {
        throw StateError('Tax cannot exceed the invoice total.');
      }
      final lines = [
        JournalLine.debit(
          accountId: receivableAccountId,
          amount: invoice.total,
        ),
        if (lineIncomeAccounts.isEmpty && net.isPositive)
          JournalLine.credit(accountId: incomeAccountId, amount: net),
        if (lineIncomeAccounts.isNotEmpty)
          for (final line in invoice.lines)
            if (line.subtotal.isPositive)
              JournalLine.credit(
                accountId: lineIncomeAccounts[line.id] ?? incomeAccountId,
                amount: line.subtotal,
              ),
        if (tax.isPositive)
          JournalLine.credit(accountId: taxAccountId!, amount: tax),
      ];
      final device =
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']
              as String;
      journalId = requestId;
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: journalId,
            date: invoice.issueDate,
            memo: 'Invoice $number',
            lines: lines,
          ),
          metadata: RecordMetadata.initial(
            recordId: journalId,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: DateTime.parse(draft['saved_at'] as String),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: requestId,
          businessId: businessId,
          journalId: journalId,
          expectedRevision: 1,
          actorId: actorId,
          approvedAt: approvedAt,
        ),
      );
      _database.execute(
        'INSERT INTO invoice_postings(business_id,invoice_id,request_id,journal_id,document_number,revision,customer_payload,signature) VALUES (?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          invoiceId.value,
          requestId.value,
          journalId.value,
          number,
          expectedRevision,
          customerRows.single['payload'],
          signature,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvedAt,
        kind: 'invoice_posted',
        subjectId: invoiceId,
        detail: jsonEncode({
          'journalId': journalId.value,
          'documentNumber': number,
          'revision': expectedRevision,
        }),
      );
    });
    return journalId;
  }

  List<Customer> readCustomers(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM customers WHERE business_id=? ORDER BY name,id',
          [businessId.value],
        )
        .map((row) => decodeCustomer(row['payload'] as String))
        .toList();
  }

  void saveCustomer(Customer customer, {required EntityId actorId}) {
    _ensureOpen();
    final m = customer.metadata;
    if (m.isTombstone) {
      throw StateError('Deactivate customers to preserve source links.');
    }
    final payload = encodeCustomer(customer);
    _transaction(() {
      _requireReconciliationOwner(m.businessId, actorId);
      for (final id in [
        customer.defaultIncomeAccountId,
        customer.defaultTaxAccountId,
      ]) {
        if (id == null) continue;
        final accounts = _database.select(
          'SELECT * FROM accounts WHERE id=? AND business_id=?',
          [id.value, m.businessId.value],
        );
        if (accounts.isEmpty) {
          throw StateError('Default accounts must belong to this company.');
        }
      }
      final rows = _database.select(
        'SELECT payload FROM customers WHERE business_id=? AND id=?',
        [m.businessId.value, customer.id.value],
      );
      final parentId = customer.additionalValues['parentCustomerId'];
      if (parentId != null) {
        final previousParent = rows.isEmpty
            ? null
            : decodeCustomer(rows.single['payload'] as String)
                  .additionalValues['parentCustomerId'];
        final seen = {customer.id.value};
        String? nextParent = parentId;
        while (nextParent != null) {
          if (!seen.add(nextParent)) {
            throw StateError(
              'Customer parent relationships cannot form a cycle.',
            );
          }
          final candidates = _database.select(
            'SELECT payload FROM customers WHERE business_id=? AND id=?',
            [m.businessId.value, nextParent],
          );
          if (candidates.isEmpty) {
            throw StateError('Parent customer must belong to this company.');
          }
          final parent = decodeCustomer(candidates.single['payload'] as String);
          if (nextParent == parentId &&
              !parent.isActive &&
              parentId != previousParent) {
            throw StateError('Choose an active parent customer.');
          }
          nextParent = parent.additionalValues['parentCustomerId'];
        }
      }
      if (rows.isEmpty) {
        if (m.revision != 1) {
          throw StateError('New customers must start at revision one.');
        }
      } else {
        if (rows.single['payload'] == payload) {
          return; // Exact retry is harmless.
        }
        final previous = decodeCustomer(rows.single['payload'] as String)
            .metadata;
        if (m.revision != previous.revision + 1 ||
            m.createdAt != previous.createdAt ||
            m.originDeviceId != previous.originDeviceId ||
            !m.updatedAt.isAfter(previous.updatedAt)) {
          throw StateError('Customer changed. Reload before saving.');
        }
      }
      _database.execute(
        'INSERT INTO customers(business_id,id,name,payload) VALUES (?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,payload=excluded.payload',
        [m.businessId.value, customer.id.value, customer.displayName, payload],
      );
      _database.execute(
        'INSERT INTO customer_history(business_id,id,revision,payload) VALUES (?,?,?,?)',
        [m.businessId.value, customer.id.value, m.revision, payload],
      );
      _appendAudit(
        businessId: m.businessId,
        actorId: actorId,
        at: m.updatedAt,
        kind: 'customer_saved',
        subjectId: customer.id,
        detail: jsonEncode({
          'revision': m.revision,
          'status': customer.status.name,
        }),
      );
    });
  }

  Future<StoredJournalEntry?> getJournal(EntityId id) => getById(id);

  Future<void> saveJournal(StoredJournalEntry record) => save(record);

  @override
  Future<StoredJournalEntry?> getById(EntityId id) async {
    _ensureOpen();
    return _readJournal(id);
  }

  StoredJournalEntry? _readJournal(EntityId id) {
    final rows = _database.select(
      'SELECT * FROM journal_entries WHERE id = ?',
      [id.value],
    );
    if (rows.isEmpty) {
      return null;
    }

    final lineRows = _database.select(
      'SELECT * FROM journal_lines WHERE journal_id = ? ORDER BY line_index',
      [id.value],
    );
    return _journalFromRows(rows.first, lineRows.map(_lineFromRow).toList());
  }

  StoredJournalEntry _journalFromRows(
    Map<String, Object?> row,
    List<JournalLine> lines,
  ) {
    final entry = JournalEntry.restore(
      id: EntityId.parse(row['id'] as String),
      date: DateTime.parse(row['entry_date'] as String),
      memo: row['memo'] as String,
      lines: lines,
      state: JournalEntryState.values.byName(row['state'] as String),
      reversesId: _idOrNull(row['reverses_id']),
      closingEquityAccountId: _idOrNull(row['closing_equity_id']),
    );
    final metadata = RecordMetadata.initial(
      recordId: EntityId.parse(row['id'] as String),
      businessId: EntityId.parse(row['business_id'] as String),
      originDeviceId: EntityId.parse(row['origin_device_id'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
    return StoredJournalEntry(
      entry: entry,
      metadata: _metadataWithStoredRevision(
        metadata,
        revision: row['revision'] as int,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deletedAt: _dateOrNull(row['deleted_at']),
      ),
    );
  }

  /// Caller holds one read/write snapshot for both queries. Preserve every
  /// stored state and revision; report validation still owns their meaning.
  List<StoredJournalEntry> _readJournalBatch(
    EntityId businessId, {
    bool includeDeleted = true,
    bool newestFirst = false,
  }) {
    final deletionFilter = includeDeleted ? '' : ' AND e.deleted_at IS NULL';
    final rows = _database.select(
      'SELECT e.* FROM journal_entries e WHERE e.business_id=?$deletionFilter '
      'ORDER BY e.entry_date${newestFirst ? ' DESC' : ''},e.id',
      [businessId.value],
    );
    final linesByJournal = <String, List<JournalLine>>{};
    for (final row in _database.select(
      'SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id=l.journal_id '
      'WHERE e.business_id=?$deletionFilter ORDER BY l.journal_id,l.line_index',
      [businessId.value],
    )) {
      (linesByJournal[row['journal_id'] as String] ??= []).add(
        _lineFromRow(row),
      );
    }
    return [
      for (final row in rows)
        _journalFromRows(row, linesByJournal[row['id']] ?? const []),
    ];
  }

  List<StoredJournalEntry> _readJournalSnapshot(
    EntityId businessId, {
    bool includeDeleted = true,
    bool newestFirst = false,
  }) {
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final records = List<StoredJournalEntry>.unmodifiable(
        _readJournalBatch(
          businessId,
          includeDeleted: includeDeleted,
          newestFirst: newestFirst,
        ),
      );
      if (ownsSnapshot) _database.execute('COMMIT');
      return records;
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> save(StoredJournalEntry record) async {
    _ensureOpen();
    if (record.entry.state != JournalEntryState.draft) {
      throw StateError('Posting requires approval of a saved draft.');
    }
    _transaction(() {
      final existing = _database.select(
        'SELECT 1 FROM journal_entries WHERE id=?',
        [record.entry.id.value],
      ).isNotEmpty;
      _writeJournal(record);
      if (!existing) {
        _appendTransactionRootCreated(
          businessId: record.metadata.businessId,
          at: record.metadata.createdAt,
          family: 'manualJournal',
          recordId: record.entry.id,
        );
      }
    });
  }

  void _writeJournal(
    StoredJournalEntry record, {
    bool retainedDraftRevision = false,
  }) {
    if (record.metadata.recordId != record.entry.id) {
      throw ArgumentError('Journal metadata must reference the journal entry.');
    }
    final existing = _database.select(
      'SELECT * FROM journal_entries WHERE id = ?',
      [record.entry.id.value],
    );
    if (existing.isNotEmpty) {
      if (!retainedDraftRevision &&
          _database.select(
            "SELECT 1 FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='journal.draft_revised' LIMIT 1",
            [record.metadata.businessId.value, record.entry.id.value],
          ).isNotEmpty) {
        throw StateError(
          'Use the retained Journal revision command to save this draft.',
        );
      }
      if (!retainedDraftRevision &&
          manualJournalRevisionForDraft(
                record.metadata.businessId,
                record.entry.id,
              ) !=
              null) {
        throw StateError('Use the current Journal revision command.');
      }
      final previous = existing.first;
      if (previous['state'] != JournalEntryState.draft.name) {
        throw StateError('Posted journals are immutable. Create a reversal.');
      }
      if (previous['deleted_at'] != null ||
          previous['business_id'] != record.metadata.businessId.value ||
          previous['origin_device_id'] !=
              record.metadata.originDeviceId.value ||
          previous['created_at'] !=
              record.metadata.createdAt.toUtc().toIso8601String()) {
        throw StateError('Journal identity and ownership cannot change.');
      }
      if (record.metadata.revision != (previous['revision'] as int) + 1 ||
          !record.metadata.updatedAt.isAfter(
            DateTime.parse(previous['updated_at'] as String),
          )) {
        throw StateError(
          'Journal changed since it was read. Reload before saving.',
        );
      }
    } else if (record.metadata.revision != 1) {
      throw StateError('A new local journal must begin at revision one.');
    }
    if (record.entry.state != JournalEntryState.draft &&
        record.metadata.isTombstone) {
      throw StateError('Posted journals cannot be deleted. Create a reversal.');
    }
    _database.execute(
      '''
        INSERT INTO journal_entries (
          id, entry_date, memo, state, reverses_id, business_id,
          origin_device_id, created_at, updated_at, revision, deleted_at, closing_equity_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET entry_date=excluded.entry_date, memo=excluded.memo,
          state=excluded.state, reverses_id=excluded.reverses_id, closing_equity_id=excluded.closing_equity_id,
          updated_at=excluded.updated_at, revision=excluded.revision, deleted_at=excluded.deleted_at
        ''',
      [
        record.entry.id.value,
        '${_calendarDay(record.entry.date)}T00:00:00.000Z',
        record.entry.memo,
        record.entry.state.name,
        record.entry.reversesId?.value,
        record.metadata.businessId.value,
        record.metadata.originDeviceId.value,
        record.metadata.createdAt.toUtc().toIso8601String(),
        record.metadata.updatedAt.toUtc().toIso8601String(),
        record.metadata.revision,
        record.metadata.deletedAt?.toUtc().toIso8601String(),
        record.entry.closingEquityAccountId?.value,
      ],
    );
    _database.execute('DELETE FROM journal_lines WHERE journal_id = ?', [
      record.entry.id.value,
    ]);
    for (var index = 0; index < record.entry.lines.length; index++) {
      final line = record.entry.lines[index];
      _database.execute(
        '''
          INSERT INTO journal_lines (
            journal_id, line_index, account_id, kind, amount_minor, currency
          ) VALUES (?, ?, ?, ?, ?, ?)
          ''',
        [
          record.entry.id.value,
          index,
          line.accountId.value,
          line.kind.name,
          line.amount.minorUnits,
          line.amount.currency,
        ],
      );
    }
  }

  /// Currency is immutable here; conversion requires a separate reviewed migration.
  Future<void> configureLedger({
    required EntityId businessId,
    required String currencyCode,
  }) async {
    _ensureOpen();
    final currency = Currency.parse(currencyCode).code;
    _transaction(() {
      final rows = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id = ?',
        [businessId.value],
      );
      if (rows.isNotEmpty && rows.first['currency'] != currency) {
        throw StateError(
          'Changing ledger currency requires a reviewed conversion.',
        );
      }
      _database.execute(
        'INSERT OR IGNORE INTO ledger_policies(business_id,currency) VALUES (?,?)',
        [businessId.value, currency],
      );
    });
  }

  /// Inclusive date lock. Reopening will require a separate audited operation.
  Future<void> closeThrough({
    required EntityId businessId,
    required DateTime date,
    required EntityId actorId,
    required DateTime changedAt,
    required String reason,
  }) async {
    _ensureOpen();
    if (reason.trim().isEmpty) {
      throw ArgumentError('A closing reason is required.');
    }
    final day = _calendarDay(date);
    _transaction(() {
      final rows = _database.select(
        'SELECT * FROM ledger_policies WHERE business_id = ?',
        [businessId.value],
      );
      if (rows.isEmpty) throw StateError('Configure the ledger first.');
      final previous = rows.first['closed_through'] as String?;
      if (previous != null && day.compareTo(previous) <= 0) {
        throw StateError(
          'The closing date must advance. Reopening requires a separate review.',
        );
      }
      _database.execute(
        'UPDATE ledger_policies SET closed_through = ? WHERE business_id = ?',
        [day, businessId.value],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: 'period_closed',
        subjectId: businessId,
        detail: jsonEncode({
          'previous': previous,
          'through': day,
          'reason': reason.trim(),
        }),
      );
    });
  }

  @override
  Future<StoredJournalEntry> approve(JournalApproval command) async {
    _ensureOpen();
    late StoredJournalEntry result;
    _transaction(() {
      result = _approveJournalInTransaction(command);
    });
    return result;
  }

  StoredJournalEntry _approveJournalInTransaction(
    JournalApproval command, {
    EntityId? linkedClaimReversal,
    EntityId? linkedBillReversal,
    EntityId? linkedBillPaymentReversal,
    EntityId? linkedTaxRemittanceReversal,
    EntityId? linkedManualJournalRevision,
  }) {
    _ensureOpen();
    if (command.expectedRevision < 1) {
      throw ArgumentError('A reviewed revision is required.');
    }
    late StoredJournalEntry result;
    final signature = jsonEncode([
      command.journalId.value,
      command.expectedRevision,
      command.actorId.value,
      command.approvedAt.toUtc().toIso8601String(),
      if (command.expenseIntakeId != null) command.expenseIntakeId!.value,
    ]);
    void commit() {
      final retries = _database.select(
        'SELECT * FROM journal_approvals WHERE business_id = ? AND request_id = ?',
        [command.businessId.value, command.requestId.value],
      );
      if (retries.isNotEmpty) {
        if (retries.first['signature'] != signature) {
          throw StateError(
            'An approval request ID cannot be reused for different work.',
          );
        }
        result = _readJournal(command.journalId)!;
        return;
      }
      if (manualJournalRevisionForDraft(
                command.businessId,
                command.journalId,
              ) !=
              null &&
          linkedManualJournalRevision != command.journalId) {
        throw StateError('Use the linked current Journal correction review.');
      }
      final draft = _readJournal(command.journalId);
      if (draft == null || draft.metadata.businessId != command.businessId) {
        throw StateError('The journal does not belong to this business.');
      }
      if (draft.entry.state != JournalEntryState.draft ||
          draft.metadata.isTombstone ||
          draft.metadata.revision != command.expectedRevision) {
        throw StateError(
          'The reviewed draft changed or was already posted. Reload before approval.',
        );
      }
      final posted = draft.entry.post();
      final expenseId = command.expenseIntakeId;
      if (expenseId != null) {
        final expenses = _database.select(
          'SELECT * FROM expense_intakes WHERE business_id = ? AND id = ?',
          [command.businessId.value, expenseId.value],
        );
        if (expenses.isEmpty ||
            expenses.single['journal_id'] != null ||
            expenses.single['archived_at'] != null) {
          throw StateError('The expense is unavailable or already posted.');
        }
        final expense = expenses.single;
        final debits = posted.lines
            .where((line) => line.isDebit)
            .fold<BigInt>(
              BigInt.zero,
              (sum, line) => sum + BigInt.from(line.amount.minorUnits),
            );
        if (posted.isClosing ||
            posted.reversesId != null ||
            _calendarDay(posted.date) != expense['occurred_on'] ||
            debits != BigInt.from(expense['amount_minor'] as int) ||
            posted.lines.any(
              (line) => line.amount.currency != expense['currency'],
            )) {
          throw StateError(
            'The reviewed journal must match the expense date, currency and total.',
          );
        }
        final otherLinks = _database.select(
          'SELECT id FROM expense_intakes WHERE journal_id = ?',
          [command.journalId.value],
        );
        if (otherLinks.isNotEmpty) {
          throw StateError('The journal already belongs to another expense.');
        }
      }
      final policies = _database.select(
        'SELECT * FROM ledger_policies WHERE business_id = ?',
        [command.businessId.value],
      );
      if (policies.isEmpty) {
        throw StateError('Configure the ledger currency before posting.');
      }
      final policy = policies.first;
      final closed = policy['closed_through'] as String?;
      if (closed != null && _calendarDay(posted.date).compareTo(closed) <= 0) {
        throw StateError('The journal date is in a closed accounting period.');
      }
      for (final line in posted.lines) {
        if (line.amount.currency != policy['currency']) {
          throw StateError(
            'Convert foreign amounts using an explicit reviewed exchange rate before posting.',
          );
        }
        final rows = _database.select('SELECT * FROM accounts WHERE id = ?', [
          line.accountId.value,
        ]);
        if (rows.isEmpty ||
            rows.first['business_id'] != command.businessId.value ||
            rows.first['status'] != AccountStatus.active.name ||
            rows.first['is_parent'] != 0) {
          throw StateError(
            'Every posting account must be active, non-parent and owned by this business.',
          );
        }
      }
      if (posted.reversesId != null) {
        if (_manualFinancialHistoryBound(
              command.businessId,
              posted.reversesId!,
            ) &&
            linkedManualJournalRevision != posted.reversesId) {
          throw StateError('Use the linked current Journal correction review.');
        }
        requireJournalUnreconciled(command.businessId, posted.reversesId!);
        if (_journalAlreadyMatched(command.businessId, posted.reversesId!)) {
          throw StateError(
            'Unlink the bank statement match before reversing this journal.',
          );
        }
        if (_database.select(
              'SELECT 1 FROM tax_remittances t WHERE t.business_id=? AND t.journal_id=? AND NOT EXISTS(SELECT 1 FROM tax_remittance_corrections c WHERE c.business_id=t.business_id AND c.source_id=t.id)',
              [command.businessId.value, posted.reversesId!.value],
            ).isNotEmpty &&
            linkedTaxRemittanceReversal != posted.reversesId) {
          throw StateError(
            'Unlink remittance attribution or use the linked tax payment reversal before reversing this journal.',
          );
        }
        if (_database.select('SELECT 1 FROM bill_postings WHERE journal_id=?', [
              posted.reversesId!.value,
            ]).isNotEmpty &&
            linkedBillReversal != posted.reversesId) {
          throw StateError(
            'Bill corrections require a linked purchase adjustment.',
          );
        }
        if (_database.select(
              'SELECT 1 FROM bill_settlements WHERE journal_id=?',
              [posted.reversesId!.value],
            ).isNotEmpty &&
            linkedBillPaymentReversal != posted.reversesId) {
          throw StateError(
            'Bill payment corrections require a linked payment adjustment.',
          );
        }
        if (_database.select(
              'SELECT 1 FROM all_claim_postings WHERE journal_id=? UNION ALL SELECT 1 FROM claim_settlements WHERE journal_id=?'
              '${_hasExpenseRevisionViews ? " UNION ALL SELECT 1 FROM expense_revision_postings e JOIN expense_revision_drafts d ON d.business_id=e.business_id AND d.expense_id=e.expense_id AND d.revision=e.revision WHERE e.journal_id=? AND json_extract(d.payload,'\$.claimSource') IS NOT NULL" : ''}',
              [
                posted.reversesId!.value,
                posted.reversesId!.value,
                if (_hasExpenseRevisionViews) posted.reversesId!.value,
              ],
            ).isNotEmpty &&
            linkedClaimReversal != posted.reversesId) {
          throw StateError(
            'Claim corrections require a linked claim reversal so allocations and status remain consistent.',
          );
        }
        if (_database.select(
          'SELECT 1 FROM invoice_postings WHERE journal_id=? UNION ALL SELECT 1 FROM customer_receipts WHERE journal_id=? UNION ALL SELECT 1 FROM invoice_credit_postings WHERE journal_id=?',
          [
            posted.reversesId!.value,
            posted.reversesId!.value,
            posted.reversesId!.value,
          ],
        ).isNotEmpty) {
          throw StateError(
            'Invoice corrections require a linked sales adjustment.',
          );
        }
        final original = _readJournal(posted.reversesId!);
        if (original == null ||
            original.metadata.businessId != command.businessId ||
            original.entry.state != JournalEntryState.posted ||
            posted.closingEquityAccountId !=
                original.entry.closingEquityAccountId ||
            _calendarDay(posted.date)
                    .compareTo(_calendarDay(original.entry.date)) <
                0 ||
            _lineSignature(posted.lines, reverse: true) !=
                _lineSignature(original.entry.lines)) {
          throw StateError(
            'A reversal must exactly reverse a posted journal from this business.',
          );
        }
        final prior = _database.select(
          "SELECT id FROM journal_entries WHERE reverses_id = ? AND state = 'posted'",
          [posted.reversesId!.value],
        );
        if (prior.isNotEmpty) {
          throw StateError(
            'The original journal already has a posted reversal.',
          );
        }
      }
      if (posted.isClosing && posted.reversesId == null) {
        final accounts = _database
            .select('SELECT * FROM accounts WHERE business_id = ?', [
              command.businessId.value,
            ])
            .map(_accountFromRow)
            .toList();
        final journals = _database
            .select(
              'SELECT id FROM journal_entries WHERE business_id = ? AND id <> ?',
              [command.businessId.value, posted.id.value],
            )
            .map((row) => _readJournal(EntityId.parse(row['id'] as String))!)
            .toList();
        final snapshot = LedgerReport.build(
          businessId: command.businessId,
          currency: policy['currency'] as String,
          from: DateTime.utc(1),
          through: posted.date,
          accounts: accounts,
          journals: journals,
        );
        final proposal = ClosingProposal.fromReport(
          snapshot,
          equityAccountId: posted.closingEquityAccountId!,
        );
        if (proposal.isEmpty ||
            _lineSignature(proposal.lines) != _lineSignature(posted.lines)) {
          throw StateError(
            'Closing balances changed or the proposal is invalid. Recalculate and review.',
          );
        }
      }
      result = StoredJournalEntry(
        entry: posted,
        metadata: draft.metadata.nextRevision(updatedAt: command.approvedAt),
      );
      // Approval already checked the exact persisted revision; preserve its
      // draft history while changing only the reviewed posting state.
      _writeJournal(result, retainedDraftRevision: true);
      if (command.expenseIntakeId != null) {
        _database.execute(
          'UPDATE expense_intakes SET journal_id = ? WHERE id = ? AND business_id = ?',
          [
            command.journalId.value,
            command.expenseIntakeId!.value,
            command.businessId.value,
          ],
        );
      }
      _database.execute(
        'INSERT INTO journal_approvals(business_id,request_id,journal_id,signature) VALUES (?,?,?,?)',
        [
          command.businessId.value,
          command.requestId.value,
          command.journalId.value,
          signature,
        ],
      );
      _appendAudit(
        businessId: command.businessId,
        actorId: command.actorId,
        at: command.approvedAt,
        kind: 'journal_posted',
        subjectId: command.journalId,
        detail: jsonEncode({
          'requestId': command.requestId.value,
          'reviewedRevision': command.expectedRevision,
          'postedRevision': result.metadata.revision,
          'reversesId': posted.reversesId?.value,
          'closingEquityAccountId': posted.closingEquityAccountId?.value,
          if (command.expenseIntakeId != null)
            'expenseIntakeId': command.expenseIntakeId!.value,
        }),
      );
    }

    commit();
    return result;
  }

  Future<List<Map<String, Object?>>> auditEvents(EntityId businessId) async {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM ledger_audit WHERE business_id = ? ORDER BY sequence',
            [businessId.value],
          )
          .map((row) => Map<String, Object?>.unmodifiable(row)),
    );
  }

  /// Newest-first keyset page. A stable upper sequence can freeze a browsing
  /// session while later events continue to be recorded.
  Future<List<Map<String, Object?>>> auditEventPage(
    EntityId businessId, {
    int limit = 50,
    int? beforeSequence,
    int? throughSequence,
    EntityId? actorId,
    EntityId? subjectId,
    String? kind,
    DateTime? occurredFrom,
    DateTime? occurredBefore,
  }) async {
    _ensureOpen();
    if (limit < 1 ||
        limit > 200 ||
        (beforeSequence != null && beforeSequence < 1) ||
        (throughSequence != null && throughSequence < 1)) {
      throw ArgumentError('Invalid audit page bounds.');
    }
    final query = _auditEventConditions(
      businessId,
      beforeSequence: beforeSequence,
      throughSequence: throughSequence,
      actorId: actorId,
      subjectId: subjectId,
      kind: kind,
      occurredFrom: occurredFrom,
      occurredBefore: occurredBefore,
    );
    final parameters = [...query.parameters];
    parameters.add(limit);
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM ledger_audit WHERE ${query.where} ORDER BY sequence DESC LIMIT ?',
            parameters,
          )
          .map((row) => Map<String, Object?>.unmodifiable(row)),
    );
  }

  /// Counts before pagination using the same company, snapshot and filter
  /// boundaries as the keyset query. Unfiltered count owns control visibility.
  Future<int> auditEventCount(
    EntityId businessId, {
    int? throughSequence,
    EntityId? actorId,
    EntityId? subjectId,
    String? kind,
    DateTime? occurredFrom,
    DateTime? occurredBefore,
  }) async {
    _ensureOpen();
    final query = _auditEventConditions(
      businessId,
      throughSequence: throughSequence,
      actorId: actorId,
      subjectId: subjectId,
      kind: kind,
      occurredFrom: occurredFrom,
      occurredBefore: occurredBefore,
    );
    return _database
            .select(
              'SELECT COUNT(*) AS count FROM ledger_audit WHERE ${query.where}',
              query.parameters,
            )
            .single['count']
        as int;
  }

  List<String> auditEventKinds(EntityId businessId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT DISTINCT kind FROM ledger_audit WHERE business_id = ? ORDER BY kind',
            [businessId.value],
          )
          .map((row) => row['kind'] as String),
    );
  }

  ({String where, List<Object?> parameters}) _auditEventConditions(
    EntityId businessId, {
    int? beforeSequence,
    int? throughSequence,
    EntityId? actorId,
    EntityId? subjectId,
    String? kind,
    DateTime? occurredFrom,
    DateTime? occurredBefore,
  }) {
    if (throughSequence != null && throughSequence < 1) {
      throw ArgumentError('Invalid audit snapshot bounds.');
    }
    if (occurredFrom != null &&
        occurredBefore != null &&
        !occurredFrom.isBefore(occurredBefore)) {
      throw ArgumentError('Audit event date range must increase.');
    }
    final conditions = <String>['business_id = ?'];
    final parameters = <Object?>[businessId.value];
    void filter(String condition, Object? value) {
      if (value != null) {
        conditions.add(condition);
        parameters.add(value);
      }
    }

    filter('sequence < ?', beforeSequence);
    filter('sequence <= ?', throughSequence);
    filter('actor_id = ?', actorId?.value);
    filter('subject_id = ?', subjectId?.value);
    filter('kind = ?', kind);
    // Stored event instants are UTC ISO strings. Remove the Z terminator so
    // millisecond values sort correctly beside nonzero microsecond values.
    filter(
      "replace(occurred_at, 'Z', '') >= ?",
      occurredFrom?.toUtc().toIso8601String().replaceAll('Z', ''),
    );
    filter(
      "replace(occurred_at, 'Z', '') < ?",
      occurredBefore?.toUtc().toIso8601String().replaceAll('Z', ''),
    );
    return (where: conditions.join(' AND '), parameters: parameters);
  }

  void _appendAudit({
    required EntityId businessId,
    required EntityId actorId,
    required DateTime at,
    required String kind,
    required EntityId subjectId,
    required String detail,
  }) {
    _database.execute(
      'INSERT INTO ledger_audit(business_id,actor_id,occurred_at,kind,subject_id,detail) VALUES (?,?,?,?,?,?)',
      [
        businessId.value,
        actorId.value,
        at.toUtc().toIso8601String(),
        kind,
        subjectId.value,
        detail,
      ],
    );
  }

  /// One event for each newly persisted transaction root. Recovery copies use
  /// an audit-sequence watermark, so this must share the record's transaction.
  void _appendTransactionRootCreated({
    required EntityId businessId,
    EntityId? actorId,
    required DateTime at,
    required String family,
    required EntityId recordId,
    String? recordKey,
  }) {
    if (_restoredTrackingBusinessId != businessId) return;
    if (_database.autocommit) {
      throw StateError('Transaction creation must share the record commit.');
    }
    var owner = actorId;
    if (owner == null) {
      final rows = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      // A direct database save may validly have no local device workspace.
      // Never invent an actor or reject that transaction for display status.
      if (rows.isEmpty) return;
      owner = EntityId.parse(rows.single['owner_id'] as String);
    }
    _appendAudit(
      businessId: businessId,
      actorId: owner,
      at: at,
      kind: 'transaction_root_created',
      subjectId: recordId,
      detail: recordKey == null ? family : '$family/$recordKey',
    );
  }

  static String _calendarDay(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().substring(0, 10);

  static String _lineSignature(
    List<JournalLine> lines, {
    bool reverse = false,
  }) {
    final values =
        lines
            .map(
              (line) => jsonEncode([
                line.accountId.value,
                reverse ? (line.isDebit ? 'credit' : 'debit') : line.kind.name,
                line.amount.currency,
                line.amount.minorUnits,
              ]),
            )
            .toList()
          ..sort();
    return jsonEncode(values);
  }

  Future<EntityId> saveExpenseIntake({
    required EntityId id,
    required EntityId businessId,
    required RecordExpenseDraft draft,
    required DateTime createdAt,
    String? recurringOccurrenceIdentity,
  }) async {
    _ensureOpen();
    if (draft.claimSource != null) {
      throw StateError(
        'Approved Claim Expenses can only be created by Claim approval.',
      );
    }
    final request = draft.submissionId;
    final date = parseAccountingInputDate(draft.date);
    final amount = Money.fromDecimal(draft.amount, draft.currencyCode);
    if (request == null ||
        request.isEmpty ||
        date == null ||
        !amount.isPositive ||
        draft.category.trim().isEmpty ||
        draft.paymentAccount.trim().isEmpty) {
      throw ArgumentError(
        'An expense needs a stable submission ID, valid date, positive amount, category and payment account.',
      );
    }
    final payload = jsonEncode(draft.toJson());
    // Validate receipt bytes before accepting a durable copy.
    RecordExpenseDraft.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    late EntityId savedId;
    _transaction(() {
      final previous = _database.select(
        'SELECT id,payload,archived_at FROM expense_intakes WHERE business_id = ? AND request_id = ?',
        [businessId.value, request],
      );
      _validateExpenseTaxSnapshots(
        businessId,
        draft,
        existing: previous.isEmpty
            ? null
            : RecordExpenseDraft.fromJson(
                jsonDecode(previous.single['payload'] as String)
                    as Map<String, dynamic>,
              ),
      );
      final occurrenceIdentity = recurringOccurrenceIdentity;
      if (occurrenceIdentity != null) {
        final occurrences = _database.select(
          'SELECT identity FROM recurring_expense_occurrences WHERE business_id = ? AND identity = ?',
          [businessId.value, occurrenceIdentity],
        );
        if (occurrences.isEmpty) {
          throw StateError(
            'Prepare this recurring suggestion before saving it.',
          );
        }
        final links = _database.select(
          'SELECT expense_id FROM recurring_expense_conversions WHERE business_id = ? AND identity = ?',
          [businessId.value, occurrenceIdentity],
        );
        if (links.isNotEmpty &&
            (previous.isEmpty ||
                links.single['expense_id'] != previous.single['id'])) {
          throw StateError(
            'This recurring suggestion already has a saved expense.',
          );
        }
      }
      if (previous.isNotEmpty) {
        if (previous.single['archived_at'] != null) {
          throw StateError(
            'Restore the removed expense before reusing its submission.',
          );
        }
        final links = _database.select(
          'SELECT identity FROM recurring_expense_conversions WHERE business_id = ? AND expense_id = ?',
          [businessId.value, previous.single['id']],
        );
        final savedOccurrence = links.isEmpty ? null : links.single['identity'];
        if (savedOccurrence != occurrenceIdentity) {
          throw StateError(
            'This expense submission has a different recurring source.',
          );
        }
        if (previous.first['payload'] != payload) {
          throw StateError(
            'This expense submission was already saved with different details.',
          );
        }
        savedId = EntityId.parse(previous.first['id'] as String);
        return;
      }
      final paymentId = draft.paymentAccountId;
      if (paymentId != null) {
        final account = _database.select(
          'SELECT currency FROM payment_accounts WHERE business_id = ? AND id = ?',
          [businessId.value, paymentId],
        );
        if (account.isEmpty || account.single['currency'] != amount.currency) {
          throw StateError(
            'The payment account must belong to this business and match the expense currency.',
          );
        }
      }
      _database.execute(
        '''INSERT INTO expense_intakes(id,business_id,request_id,created_at,occurred_on,
        amount_minor,currency,payee,category,payload) VALUES (?,?,?,?,?,?,?,?,?,?)''',
        [
          id.value,
          businessId.value,
          request,
          createdAt.toUtc().toIso8601String(),
          _calendarDay(date),
          amount.minorUnits,
          amount.currency,
          draft.payee,
          draft.category,
          payload,
        ],
      );
      _appendTransactionRootCreated(
        businessId: businessId,
        at: createdAt,
        family: 'expense',
        recordId: id,
      );
      if (occurrenceIdentity != null) {
        _database.execute(
          'INSERT INTO recurring_expense_conversions(business_id,identity,expense_id) VALUES(?,?,?)',
          [businessId.value, occurrenceIdentity, id.value],
        );
      }
      if (draft.recurrence case final schedule?) {
        final template = RecurringExpenseTemplate(
          id: 'expense-${id.value}',
          revision: 1,
          sourceExpenseId: id.value,
          schedule: schedule,
          defaults: draft,
        );
        final templatePayload = jsonEncode(template.toJson());
        _database.execute(
          'INSERT INTO recurring_expense_templates(business_id,id,revision,payload) VALUES(?,?,?,?)',
          [businessId.value, template.id, 1, templatePayload],
        );
        _database.execute(
          'INSERT INTO recurring_expense_template_history(business_id,id,revision,payload) VALUES(?,?,?,?)',
          [businessId.value, template.id, 1, templatePayload],
        );
      }
      savedId = id;
    });
    return savedId;
  }

  Future<void> updateExpenseIntake({
    required EntityId businessId,
    required EntityId id,
    required EntityId actorId,
    required RecordExpenseDraft expected,
    required RecordExpenseDraft replacement,
    required DateTime changedAt,
    int? expectedRevision,
  }) async {
    _ensureOpen();
    if (expected.claimSource != null || replacement.claimSource != null) {
      throw StateError(
        'Approved Claim Expenses retain their recognition snapshot.',
      );
    }
    final date = parseAccountingInputDate(replacement.date);
    final amount = Money.fromDecimal(
      replacement.amount,
      replacement.currencyCode,
    );
    if (date == null ||
        !amount.isPositive ||
        replacement.category.trim().isEmpty ||
        replacement.payee.trim().isEmpty ||
        replacement.paymentAccountId == null) {
      throw ArgumentError(
        'Review the expense date, amount, category, payee and payment account.',
      );
    }
    final payload = jsonEncode(replacement.toJson());
    final checked = RecordExpenseDraft.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    if (expected.submissionId != checked.submissionId ||
        expected.currencyCode != checked.currencyCode ||
        jsonEncode(expected.recurrence?.toJson()) !=
            jsonEncode(checked.recurrence?.toJson())) {
      throw StateError(
        'Editing intake cannot change its identity, currency or recurring template.',
      );
    }
    final originals = {
      for (final item in checked.attachments)
        item.originalId: item.originalSha256,
    };
    if (expected.attachments.any(
      (item) =>
          originals.containsKey(item.originalId) &&
          originals[item.originalId] != item.originalSha256,
    )) {
      throw StateError('Saved original attachment bytes cannot be replaced.');
    }
    _transaction(() {
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      if (owner.isEmpty || owner.single['owner_id'] != actorId.value) {
        throw StateError('Only the workspace owner can edit this intake.');
      }
      final rows = _database.select(
        'SELECT payload,journal_id,revision,archived_at FROM expense_intakes WHERE business_id=? AND id=?',
        [businessId.value, id.value],
      );
      if (rows.isEmpty ||
          rows.single['journal_id'] != null ||
          rows.single['archived_at'] != null) {
        throw StateError('The intake is unavailable or already posted.');
      }
      if (expectedRevision != null &&
          rows.single['revision'] != expectedRevision) {
        throw StateError('The saved expense changed. Reopen before editing.');
      }
      final previous = rows.single['payload'] as String;
      // Compare the same decoded snapshot that the editor receives. A
      // data-only restore normalizes unavailable evidence and JSON key order;
      // neither is a concurrent edit of the saved intake.
      final previousSnapshot = jsonEncode(
        RecordExpenseDraft.fromJson(
          jsonDecode(previous) as Map<String, dynamic>,
        ).toJson(),
      );
      if (previousSnapshot == jsonEncode(checked.toJson())) return;
      if (previousSnapshot != jsonEncode(expected.toJson())) {
        throw StateError('The saved expense changed. Reopen before editing.');
      }
      _validateExpenseTaxSnapshots(businessId, checked, existing: expected);
      final accounts = readPaymentAccounts(businessId)
          .where((account) => account.id == checked.paymentAccountId);
      if (accounts.isEmpty ||
          accounts.single.currency.code != checked.currencyCode) {
        throw StateError(
          'The payment account is unavailable or uses another currency.',
        );
      }
      _database.execute(
        'UPDATE expense_intakes SET occurred_on=?,amount_minor=?,payee=?,category=?,payload=?,revision=revision+1,state_changed_at=? WHERE business_id=? AND id=?',
        [
          _calendarDay(date),
          amount.minorUnits,
          checked.payee,
          checked.category,
          payload,
          changedAt.toUtc().toIso8601String(),
          businessId.value,
          id.value,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: 'expense_intake_edited',
        subjectId: id,
        detail: jsonEncode({
          'before': jsonDecode(previous),
          'after': checked.toJson(),
        }),
      );
    });
  }

  /// The same protection is consulted by list actions and by the commit.
  /// Retain linked financial/evidence history instead of orphaning it.
  String? expenseRemovalRestriction(EntityId businessId, EntityId id) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT journal_id FROM expense_intakes WHERE business_id=? AND id=?',
      [businessId.value, id.value],
    );
    if (rows.isEmpty) return 'The saved expense is unavailable.';
    if (rows.single['journal_id'] != null) {
      return 'Posted record: use an accounting correction';
    }
    if (_database.select(
      "SELECT 1 FROM payment_vouchers WHERE business_id=? AND json_extract(payload,'\$.sourceType')='directExpense' AND json_extract(payload,'\$.sourceId')=? LIMIT 1",
      [businessId.value, id.value],
    ).isNotEmpty) {
      return 'A linked voucher retains this expense as its source.';
    }
    if (_database.select(
      "SELECT 1 FROM recurring_expense_templates WHERE business_id=? AND json_extract(payload,'\$.sourceExpenseId')=? AND json_extract(payload,'\$.paused')=0 LIMIT 1",
      [businessId.value, id.value],
    ).isNotEmpty) {
      return 'Pause the recurring schedule before removing its source.';
    }
    return null;
  }

  int setExpenseIntakeArchived({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId id,
    required int expectedRevision,
    required bool archived,
    required DateTime changedAt,
  }) {
    _ensureOpen();
    late int nextRevision;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final restriction = expenseRemovalRestriction(businessId, id);
      if (restriction != null) throw StateError(restriction);
      final row = _database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND id=?',
        [businessId.value, id.value],
      ).single;
      final revision = row['revision'] as int;
      final currentArchived = row['archived_at'] != null;
      final at = changedAt.toUtc().toIso8601String();
      if (currentArchived == archived &&
          revision == expectedRevision + 1 &&
          row['state_changed_at'] == at) {
        nextRevision = revision;
        return;
      }
      if (revision != expectedRevision || currentArchived == archived) {
        throw StateError(
          'The saved expense changed. Reload before removing or restoring it.',
        );
      }
      if (!changedAt.toUtc().isAfter(
        DateTime.parse(
          (row['state_changed_at'] ?? row['created_at']) as String,
        ),
      )) {
        throw StateError('Removal and restore require a later time.');
      }
      nextRevision = revision + 1;
      _database.execute(
        'UPDATE expense_intakes SET archived_at=?,revision=?,state_changed_at=? WHERE business_id=? AND id=?',
        [archived ? at : null, nextRevision, at, businessId.value, id.value],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: archived ? 'expense_intake_archived' : 'expense_intake_restored',
        subjectId: id,
        detail: jsonEncode({'revision': nextRevision}),
      );
    });
    return nextRevision;
  }

  Future<List<ExpenseIntakeSummary>> listExpenseIntakes(
    EntityId businessId, {
    bool archived = false,
  }) async {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            '''SELECT id,created_at,occurred_on,amount_minor,currency,payee,category,journal_id,revision,archived_at,$_expensePendingColumn
      FROM $_currentExpenseTable WHERE business_id = ? AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'} ORDER BY occurred_on DESC,created_at DESC,id''',
            [businessId.value],
          )
          .map(_expenseSummary),
    );
  }

  /// Return only the visible expense summaries. Filters and counts stay
  /// scoped to the selected business, and full draft payloads are not read.
  ExpenseIntakePageResult readExpenseIntakePage({
    required EntityId businessId,
    bool archived = false,
    bool? posted,
    String? category,
    String? payee,
    int offset = 0,
    int limit = 10,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 50) {
      throw ArgumentError(
        'Expense pages require a nonnegative offset and 1–50 rows.',
      );
    }
    final where = StringBuffer(
      'business_id=? AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'}',
    );
    final args = <Object?>[businessId.value];
    if (posted != null) {
      where.write(
        posted
            ? ' AND NOT $_pendingExpensePredicate'
            : ' AND $_pendingExpensePredicate',
      );
    }
    if (category != null) {
      where.write(' AND category=?');
      args.add(category);
    }
    if (payee != null) {
      where.write(' AND payee=?');
      args.add(payee);
    }
    final total =
        _database
                .select(
                  'SELECT COUNT(*) AS count FROM $_currentExpenseTable WHERE $where',
                  args,
                )
                .single['count']
            as int;
    final start = total == 0
        ? 0
        : offset >= total
        ? ((total - 1) ~/ limit) * limit
        : offset;
    final rows = _database.select(
      'SELECT id,created_at,occurred_on,amount_minor,currency,payee,category,journal_id,revision,archived_at,$_expensePendingColumn '
      'FROM $_currentExpenseTable WHERE $where '
      'ORDER BY occurred_on DESC,created_at DESC,id LIMIT ? OFFSET ?',
      [...args, limit, start],
    );
    return ExpenseIntakePageResult(
      records: List.unmodifiable(rows.map(_expenseSummary)),
      total: total,
      offset: start,
    );
  }

  ({int count, List<ExpenseIntakeSummary> recent}) readPendingExpenseIntakes({
    required EntityId businessId,
    int limit = 50,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Choose 1–100 notifications.');
    }
    final count =
        _database.select(
              'SELECT COUNT(*) AS count FROM $_currentExpenseTable '
              'WHERE business_id=? AND archived_at IS NULL AND $_pendingExpensePredicate',
              [businessId.value],
            ).single['count']
            as int;
    final rows = _database.select(
      'SELECT id,created_at,occurred_on,amount_minor,currency,payee,category,journal_id,revision,archived_at,$_expensePendingColumn '
      'FROM $_currentExpenseTable WHERE business_id=? AND archived_at IS NULL AND $_pendingExpensePredicate '
      'ORDER BY created_at DESC,id LIMIT ?',
      [businessId.value, limit],
    );
    return (count: count, recent: List.unmodifiable(rows.map(_expenseSummary)));
  }

  ({
    int expensesWithReceipts,
    int expensesInRange,
    int pendingExpenses,
    int postedJournalsInRange,
    int journalsInRange,
    int pendingJournals,
  })
  readReportQualityCounts({
    required EntityId businessId,
    required DateTime from,
    required DateTime through,
  }) {
    _ensureOpen();
    final fromDay = _calendarDay(from);
    final throughDay = _calendarDay(through);
    if (fromDay.compareTo(throughDay) > 0) {
      throw ArgumentError('Report start must not follow its end.');
    }
    final afterThrough = _calendarDay(
      DateTime.utc(through.year, through.month, through.day + 1),
    );
    final expenses = _database.select(
      'SELECT COUNT(*) AS total, '
      "COALESCE(SUM(CASE WHEN json_array_length(payload,'\$.attachments')>0 "
      'THEN 1 ELSE 0 END),0) AS with_receipts, '
      "COALESCE(SUM(CASE WHEN json_type(payload,'\$.attachments')='array' "
      'THEN 0 ELSE 1 END),0) AS invalid_attachments '
      'FROM $_currentExpenseTable WHERE business_id=? AND archived_at IS NULL '
      'AND occurred_on>=? AND occurred_on<?',
      [businessId.value, fromDay, afterThrough],
    ).single;
    if (expenses['invalid_attachments'] != 0) {
      throw StateError(
        'An expense receipt list is invalid; accounting review is required.',
      );
    }
    final pendingExpenses =
        _database.select(
              'SELECT COUNT(*) AS count FROM $_currentExpenseTable '
              'WHERE business_id=? AND archived_at IS NULL AND $_pendingExpensePredicate',
              [businessId.value],
            ).single['count']
            as int;
    final journals = _database.select(
      'SELECT '
      'COALESCE(SUM(CASE WHEN entry_date>=? AND entry_date<? THEN 1 ELSE 0 END),0) AS total, '
      "COALESCE(SUM(CASE WHEN state='posted' AND entry_date>=? AND entry_date<? "
      'THEN 1 ELSE 0 END),0) AS posted, '
      "COALESCE(SUM(CASE WHEN state='draft' THEN 1 ELSE 0 END),0) AS pending "
      'FROM journal_entries WHERE business_id=? AND deleted_at IS NULL',
      [fromDay, afterThrough, fromDay, afterThrough, businessId.value],
    ).single;
    return (
      expensesWithReceipts: expenses['with_receipts'] as int,
      expensesInRange: expenses['total'] as int,
      pendingExpenses: pendingExpenses,
      postedJournalsInRange: journals['posted'] as int,
      journalsInRange: journals['total'] as int,
      pendingJournals: journals['pending'] as int,
    );
  }

  List<ExpenseIntakeSummary> readRecentPostedExpenseIntakes({
    required EntityId businessId,
    required DateTime through,
    int limit = 6,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Choose 1–50 recent expenses.');
    }
    final rows = _database.select(
      'SELECT id,created_at,occurred_on,amount_minor,currency,payee,category,journal_id,revision,archived_at,$_expensePendingColumn '
      'FROM $_financialExpenseTable WHERE business_id=? AND journal_id IS NOT NULL '
      'AND occurred_on<=? ORDER BY occurred_on DESC,created_at DESC,id LIMIT ?',
      [businessId.value, _calendarDay(through), limit],
    );
    return List.unmodifiable(rows.map(_expenseSummary));
  }

  /// The Home chart needs source names for its report journals, including an
  /// older expense journal reversed inside the current reporting year.
  Map<String, ({String payee, String category})>
  expenseSourceLabelsForJournals({
    required EntityId businessId,
    required Iterable<EntityId> journalIds,
  }) {
    _ensureOpen();
    final ids = journalIds.map((id) => id.value).toSet().toList();
    final labels = <String, ({String payee, String category})>{};
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(
        start,
        start + 500 > ids.length ? ids.length : start + 500,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final row in _database.select(
        'SELECT journal_id,payee,category FROM expense_intakes '
        'WHERE business_id=? AND journal_id IN ($placeholders)',
        [businessId.value, ...chunk],
      )) {
        labels[row['journal_id'] as String] = (
          payee: row['payee'] as String,
          category: row['category'] as String,
        );
      }
      if (_hasExpenseRevisionViews) {
        for (final row in _database.select(
          'SELECT p.journal_id,d.payee,d.category FROM expense_revision_postings p '
          'JOIN expense_revision_drafts d ON d.business_id=p.business_id AND d.expense_id=p.expense_id AND d.revision=p.revision '
          'WHERE p.business_id=? AND p.journal_id IN ($placeholders)',
          [businessId.value, ...chunk],
        )) {
          labels[row['journal_id'] as String] = (
            payee: row['payee'] as String,
            category: row['category'] as String,
          );
        }
      }
    }
    return Map.unmodifiable(labels);
  }

  ({List<String> categories, List<String> payees}) expenseIntakeFilterOptions(
    EntityId businessId, {
    bool archived = false,
  }) {
    _ensureOpen();
    List<String> values(String column) => List.unmodifiable(
      _database
          .select(
            'SELECT DISTINCT $column FROM $_currentExpenseTable '
            'WHERE business_id=? AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'} AND $column<>? ORDER BY $column',
            [businessId.value, ''],
          )
          .map((row) => row[column] as String),
    );
    return (categories: values('category'), payees: values('payee'));
  }

  /// Global search needs only a bounded page of company expense summaries.
  /// Keep matching in SQLite so a source-rich book is not decoded into the
  /// app shell just to display a small suggestion popup.
  List<ExpenseIntakeSummary> searchExpenseIntakes({
    required EntityId businessId,
    required String query,
    int limit = 12,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Choose 1–50 suggestions.');
    }
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    if (words.isEmpty) return const [];
    final select =
        'SELECT id,created_at,occurred_on,amount_minor,currency,payee,category,journal_id,revision,archived_at,$_expensePendingColumn '
        'FROM $_currentExpenseTable';
    const order = ' ORDER BY occurred_on DESC,created_at DESC,id LIMIT ?';
    const haystack =
        "lower(payee || ' Expense ' || category || ' ' || id || ' ' || "
        "currency || ':' || amount_minor)";
    if (!words.any((word) => word.runes.any((rune) => rune > 127))) {
      final where = StringBuffer('business_id=? AND archived_at IS NULL');
      final args = <Object?>[businessId.value];
      for (final word in words) {
        where.write(' AND instr($haystack,?)>0');
        args.add(word);
      }
      return [
        for (final row in _database.select('$select WHERE $where$order', [
          ...args,
          limit,
        ]))
          _expenseSummary(row),
      ];
    }

    // SQLite lower() folds ASCII only. Page scalar summaries for Unicode
    // terms and apply the same Dart case fold as the visible search result.
    final results = <ExpenseIntakeSummary>[];
    String? lastDate;
    String? lastCreated;
    String? lastId;
    while (results.length < limit) {
      final cursor = lastDate == null
          ? ''
          : ' AND (occurred_on<? OR (occurred_on=? AND '
                '(created_at<? OR (created_at=? AND id>?))))';
      final rows = _database.select(
        '$select WHERE business_id=? AND archived_at IS NULL$cursor$order',
        [
          businessId.value,
          if (lastDate != null) ...[
            lastDate,
            lastDate,
            lastCreated,
            lastCreated,
            lastId,
          ],
          200,
        ],
      );
      for (final row in rows) {
        final summary = _expenseSummary(row);
        final text =
            '${summary.payee} Expense ${summary.category} '
                    '${summary.id.value} ${summary.amount}'
                .toLowerCase();
        if (words.every(text.contains)) {
          results.add(summary);
          if (results.length == limit) break;
        }
      }
      if (rows.length < 200) break;
      lastDate = rows.last['occurred_on'] as String;
      lastCreated = rows.last['created_at'] as String;
      lastId = rows.last['id'] as String;
    }
    return results;
  }

  Future<ExpenseIntakeRecord?> getExpenseIntake(
    EntityId businessId,
    EntityId id, {
    bool includeArchived = false,
  }) async {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM $_currentExpenseTable WHERE business_id = ? AND id = ?${includeArchived ? '' : ' AND archived_at IS NULL'}',
      [businessId.value, id.value],
    );
    if (rows.isEmpty) {
      return null;
    }
    return ExpenseIntakeRecord(
      summary: _expenseSummary(rows.first),
      currentRevision: _hasExpenseRevisionViews
          ? readExpenseRevision(businessId, id)
          : null,
      draft: RecordExpenseDraft.fromJson(
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
      ),
    );
  }

  ExpenseIntakeSummary _expenseSummary(Row row) => ExpenseIntakeSummary(
    id: EntityId.parse(row['id'] as String),
    occurredOn: DateTime.parse(row['occurred_on'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    amount: Money.fromMinor(
      row['amount_minor'] as int,
      row['currency'] as String,
    ),
    payee: row['payee'] as String,
    category: row['category'] as String,
    journalId: _idOrNull(row['journal_id']),
    revision: row['revision'] as int,
    archivedAt: _dateOrNull(row['archived_at']),
    pendingRevision: row.containsKey('pending_revision')
        ? row['pending_revision'] as int
        : 0,
  );

  /// All report inputs are read within one SQLite snapshot, including line rows.
  Future<LedgerReport> readReport({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
  }) async => _readReportSnapshot(
    () => _buildLedgerReport(
      businessId: businessId,
      currency: currency,
      from: from,
      through: through,
    ),
  );

  /// Ledger totals and their saved sales attribution share one SQLite snapshot.
  /// Home retains readReport; no second revenue calculation or schema is added.
  Future<({LedgerReport ledger, SalesReport sales})> readReportWithSales({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
  }) async => _readReportSnapshot(() {
    final ledger = _buildLedgerReport(
      businessId: businessId,
      currency: currency,
      from: from,
      through: through,
    );
    return (
      ledger: ledger,
      sales: SalesReport.build(
        ledger: ledger,
        allocations: _readSalesIncomeAllocations(ledger),
      ),
    );
  });

  Future<TaxActivityReport> readTaxActivity({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
  }) async => _readReportSnapshot(
    () => _buildTaxActivityReport(
      _buildLedgerReport(
        businessId: businessId,
        currency: currency,
        from: from,
        through: through,
      ),
    ),
  );

  Future<ClaimantStatementReport> readClaimantStatement({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
  }) async => _readReportSnapshot(
    () => _buildClaimantStatement(
      _buildLedgerReport(
        businessId: businessId,
        currency: currency,
        from: from,
        through: through,
      ),
    ),
  );

  T _readReportSnapshot<T>(T Function() read) {
    _ensureOpen();
    _database.execute('BEGIN');
    try {
      final result = read();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  LedgerReport _buildLedgerReport({
    required EntityId businessId,
    required String currency,
    required DateTime from,
    required DateTime through,
  }) => LedgerReport.build(
    businessId: businessId,
    currency: currency,
    from: from,
    through: through,
    accounts: _database
        .select(
          'SELECT * FROM accounts WHERE business_id = ? ORDER BY code,id',
          [businessId.value],
        )
        .map(_accountFromRow)
        .toList(),
    journals: _readJournalBatch(businessId),
  );

  List<RecurringExpenseOccurrence> recurringExpenseSuggestions(
    EntityId businessId,
  ) {
    _ensureOpen();
    return _database
        .select(
          'SELECT o.*,t.payload AS template_payload,c.expense_id AS saved_expense_id FROM recurring_expense_occurrences o JOIN recurring_expense_template_history t ON t.business_id=o.business_id AND t.id=o.template_id AND t.revision=o.template_revision LEFT JOIN recurring_expense_conversions c ON c.business_id=o.business_id AND c.identity=o.identity WHERE o.business_id = ? ORDER BY o.occurs_on,o.identity',
          [businessId.value],
        )
        .map((row) {
          final template = RecurringExpenseTemplate.fromJson(
            jsonDecode(row['template_payload'] as String)
                as Map<String, dynamic>,
          );
          return RecurringExpenseOccurrence(
            identity: row['identity'] as String,
            savedExpenseId: row['saved_expense_id'] as String?,
            templateId: row['template_id'] as String,
            templateRevision: row['template_revision'] as int,
            sourceExpenseId: template.sourceExpenseId,
            occursOn: DateTime.parse(row['occurs_on'] as String),
            suggestion: RecordExpenseDraft.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
          );
        })
        .toList(growable: false);
  }

  /// Prepare review suggestions through a business date, never future payments.
  /// Each suggestion commits independently so interrupted catch-up is retryable.
  Future<({int prepared, bool hasMore})> prepareDueRecurringExpenses(
    EntityId businessId, {
    required DateTime through,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) throw RangeError.range(limit, 1, 1000);
    final day = DateTime.utc(through.year, through.month, through.day);
    var prepared = 0;
    var examined = 0;
    for (final template in recurringExpenseTemplates(businessId)) {
      if (template.paused) continue;
      final source = _database.select(
        'SELECT occurred_on FROM expense_intakes WHERE business_id = ? AND id = ? AND archived_at IS NULL',
        [businessId.value, template.sourceExpenseId],
      );
      if (source.isEmpty) continue;
      for (var index = 0; ; index++) {
        if (++examined % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
          _ensureOpen();
        }
        final date = template.schedule.occurrenceAt(index);
        if (date == null || date.isAfter(day)) break;
        if (_calendarDay(date) == source.single['occurred_on']) continue;
        final occurrence = template.occurrenceAt(index)!;
        final existing = _database.select(
          'SELECT identity FROM recurring_expense_occurrences WHERE business_id = ? AND identity = ?',
          [businessId.value, occurrence.identity],
        );
        if (existing.isNotEmpty) continue;
        if (prepared == limit) return (prepared: prepared, hasMore: true);
        prepareRecurringExpenseOccurrence(
          businessId,
          template.id,
          expectedRevision: template.revision,
          index: index,
        );
        prepared++;
      }
    }
    return (prepared: prepared, hasMore: false);
  }

  RecordExpenseDraft prepareRecurringExpenseOccurrence(
    EntityId businessId,
    String templateId, {
    required int expectedRevision,
    required int index,
  }) {
    _ensureOpen();
    late RecordExpenseDraft result;
    _transaction(() {
      final rows = _database.select(
        'SELECT payload FROM recurring_expense_templates WHERE business_id = ? AND id = ?',
        [businessId.value, templateId],
      );
      if (rows.isEmpty) throw StateError('Recurring template was not found.');
      final template = RecurringExpenseTemplate.fromJson(
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      );
      if (template.revision != expectedRevision) {
        throw StateError(
          'Recurring template changed. Review the current schedule.',
        );
      }
      final occurrence = template.occurrenceAt(index);
      if (occurrence == null) {
        throw StateError('This occurrence is paused or outside the schedule.');
      }
      final source = _database.select(
        'SELECT occurred_on FROM expense_intakes WHERE business_id = ? AND id = ? AND archived_at IS NULL',
        [businessId.value, template.sourceExpenseId],
      );
      if (source.isEmpty ||
          source.single['occurred_on'] == _calendarDay(occurrence.occursOn)) {
        throw StateError(
          'The source expense already represents this date, or is unavailable.',
        );
      }
      final existing = _database.select(
        'SELECT payload FROM recurring_expense_occurrences WHERE business_id = ? AND identity = ?',
        [businessId.value, occurrence.identity],
      );
      if (existing.isNotEmpty) {
        result = RecordExpenseDraft.fromJson(
          jsonDecode(existing.single['payload'] as String)
              as Map<String, dynamic>,
        );
        return;
      }
      result = occurrence.suggestion;
      _database.execute(
        'INSERT INTO recurring_expense_occurrences(business_id,identity,template_id,template_revision,occurs_on,payload) VALUES(?,?,?,?,?,?)',
        [
          businessId.value,
          occurrence.identity,
          templateId,
          template.revision,
          _calendarDay(occurrence.occursOn),
          jsonEncode(result.toJson()),
        ],
      );
    });
    return result;
  }

  List<RecurringExpenseTemplate> recurringExpenseTemplates(
    EntityId businessId,
  ) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM recurring_expense_templates WHERE business_id = ? ORDER BY id',
          [businessId.value],
        )
        .map(
          (row) => RecurringExpenseTemplate.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  List<RecurringExpenseTemplate> recurringExpenseTemplateHistory(
    EntityId businessId,
    String templateId,
  ) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM recurring_expense_template_history WHERE business_id = ? AND id = ? ORDER BY revision',
          [businessId.value, templateId],
        )
        .map(
          (row) => RecurringExpenseTemplate.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  void saveRecurringExpenseTemplate(
    EntityId businessId,
    RecurringExpenseTemplate template,
  ) {
    _ensureOpen();
    final payload = jsonEncode(template.toJson());
    RecurringExpenseTemplate.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    _transaction(() {
      final source = _database.select(
        'SELECT id FROM expense_intakes WHERE business_id = ? AND id = ? AND archived_at IS NULL',
        [businessId.value, template.sourceExpenseId],
      );
      if (source.isEmpty) {
        throw StateError(
          'Recurring expense source does not belong to this business.',
        );
      }
      final rows = _database.select(
        'SELECT revision,payload FROM recurring_expense_templates WHERE business_id = ? AND id = ?',
        [businessId.value, template.id],
      );
      if (rows.isEmpty) {
        if (template.revision != 1) {
          throw StateError('A new template must start at revision one.');
        }
      } else {
        if (rows.single['payload'] == payload) return;
        final previous = RecurringExpenseTemplate.fromJson(
          jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
        );
        if (template.revision != previous.revision + 1 ||
            template.sourceExpenseId != previous.sourceExpenseId) {
          throw StateError(
            'Template changed since it was loaded, or its source changed. Reopen before saving.',
          );
        }
      }
      _database.execute(
        'INSERT INTO recurring_expense_templates(business_id,id,revision,payload) VALUES(?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload',
        [businessId.value, template.id, template.revision, payload],
      );
      _database.execute(
        'INSERT INTO recurring_expense_template_history(business_id,id,revision,payload) VALUES(?,?,?,?)',
        [businessId.value, template.id, template.revision, payload],
      );
    });
  }

  List<PaymentVoucherSource> readVoucherSources(EntityId businessId) =>
      _readVoucherSources(businessId);

  List<PaymentVoucherSource> _readVoucherSources(
    EntityId businessId, {
    PaymentVoucherSourceType? type,
    String? sourceId,
  }) {
    _ensureOpen();
    final accounts = readPaymentAccounts(businessId);
    final sources = <PaymentVoucherSource>[];
    if (type == null || type == PaymentVoucherSourceType.directExpense) {
      for (final row in _database.select(
        'SELECT * FROM $_financialExpenseTable WHERE business_id=? AND archived_at IS NULL${sourceId == null ? '' : ' AND id=?'} ORDER BY occurred_on DESC,created_at DESC,id',
        [businessId.value, ?sourceId],
      )) {
        final draft = RecordExpenseDraft.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        );
        if (draft.claimSource != null) {
          continue; // Reimbursement owns the payment voucher.
        }
        final amount = Money.fromMinor(
          row['amount_minor'] as int,
          row['currency'] as String,
        );
        final matching = accounts
            .where(
              (a) =>
                  a.currency.code == amount.currency &&
                  (draft.paymentAccountId == null
                      ? a.name == draft.paymentAccount
                      : a.id == draft.paymentAccountId),
            )
            .toList();
        // A historical free-text account cannot be silently mapped when ambiguous.
        if (matching.length != 1) continue;
        sources.add(
          PaymentVoucherSource(
            type: PaymentVoucherSourceType.directExpense,
            id: row['id'] as String,
            payee: row['payee'] as String,
            amount: amount,
            paymentAccountId: matching.single.id,
            date: DateTime.parse(row['occurred_on'] as String),
          ),
        );
      }
    }
    if (type == null || type == PaymentVoucherSourceType.claimPayment) {
      for (final row in _database.select(
        """SELECT c.payload,a.paid_payload,a.request_id,s.journal_id
      FROM claims c JOIN claim_settlement_allocations a
        ON a.business_id=c.business_id AND a.claim_id=c.id
      JOIN claim_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id
      JOIN journal_entries j ON j.id=s.journal_id AND j.business_id=s.business_id
      WHERE c.business_id=?${sourceId == null ? '' : ' AND c.id=?'} AND j.state='posted'
        AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.reverses_id=j.id AND r.state='posted')
      ORDER BY c.id""",
        [businessId.value, ?sourceId],
      )) {
        final claim = Claim.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        );
        final paid = Claim.fromJson(
          jsonDecode(row['paid_payload'] as String) as Map<String, dynamic>,
        );
        if (claim.status != ClaimStatus.paid ||
            claim.paymentBatchId?.value != row['request_id'] ||
            jsonEncode(claim.toJson()) != jsonEncode(paid.toJson())) {
          continue;
        }
        final bank = _database.select(
          """SELECT l.payment_account_id FROM journal_lines j JOIN payment_ledger_links l
          ON l.ledger_account_id=j.account_id
        WHERE l.business_id=? AND j.journal_id=? AND j.kind='credit' AND j.amount_minor>0""",
          [businessId.value, row['journal_id']],
        );
        if (bank.length != 1) continue;
        final account = accounts
            .where(
              (a) =>
                  a.id == bank.single['payment_account_id'] &&
                  a.currency.code == claim.amount.currency,
            )
            .firstOrNull;
        if (account == null || claim.paidAt == null) continue;
        sources.add(
          PaymentVoucherSource(
            type: PaymentVoucherSourceType.claimPayment,
            id: claim.id.value,
            payee: claim.claimantName,
            amount: claim.amount,
            paymentAccountId: account.id,
            date: claim.paidAt!,
          ),
        );
      }
    }
    if (type == null || type == PaymentVoucherSourceType.billSettlement) {
      sources.addAll(_billVoucherSources(businessId, sourceId: sourceId));
    }
    return List.unmodifiable(sources);
  }

  void _requireVoucherSource(EntityId businessId, PaymentVoucher voucher) {
    if (voucher.status == PaymentVoucherStatus.cancelled) return;
    final source =
        _readVoucherSources(
              businessId,
              type: voucher.sourceType,
              sourceId: voucher.sourceId,
            )
            .where(
              (s) => s.type == voucher.sourceType && s.id == voucher.sourceId,
            )
            .firstOrNull;
    if (source == null) {
      throw StateError('Choose an available saved source in this company.');
    }
    if (source.payee != voucher.payee ||
        source.amount != voucher.amount ||
        source.paymentAccountId != voucher.paymentAccountId ||
        voucher.sourceType == PaymentVoucherSourceType.billSettlement &&
            accountingCalendarDate(voucher.paymentDate) != source.date) {
      throw StateError(
        'The source payee, amount, currency, payment account or date changed. Reopen and review the saved source.',
      );
    }
  }

  PaymentVoucherPaymentEvidence _voucherPaymentEvidence(
    EntityId businessId,
    PaymentVoucher voucher,
  ) {
    _ensureOpen();
    _requireVoucherSource(businessId, voucher);
    final journalRows = switch (voucher.sourceType) {
      PaymentVoucherSourceType.directExpense => _database.select(
        'SELECT journal_id FROM $_financialExpenseTable WHERE business_id=? AND id=?',
        [businessId.value, voucher.sourceId],
      ),
      PaymentVoucherSourceType.claimPayment => _database.select(
        "SELECT s.journal_id FROM claim_settlement_allocations a JOIN claim_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id JOIN journal_entries j ON j.business_id=s.business_id AND j.id=s.journal_id WHERE a.business_id=? AND a.claim_id=? AND j.state='posted' AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.business_id=j.business_id AND r.reverses_id=j.id AND r.state='posted')",
        [businessId.value, voucher.sourceId],
      ),
      PaymentVoucherSourceType.billSettlement => _database.select(
        'SELECT journal_id FROM bill_settlements WHERE business_id=? AND request_id=?',
        [
          businessId.value,
          _billVoucherSourceIdentity(voucher.sourceId)!.requestId.value,
        ],
      ),
    };
    if (journalRows.length != 1 || journalRows.single['journal_id'] == null) {
      throw StateError(
        'Review and post the source payment before recording it on this voucher.',
      );
    }
    final journalId = EntityId.parse(
      journalRows.single['journal_id'] as String,
    );
    final journal = _readJournal(journalId);
    if (journal == null ||
        journal.metadata.businessId != businessId ||
        journal.metadata.isTombstone ||
        journal.entry.state != JournalEntryState.posted ||
        journal.entry.validationErrors.isNotEmpty ||
        _database.select(
          "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted'",
          [businessId.value, journalId.value],
        ).isNotEmpty) {
      throw StateError(
        'The linked source payment is unavailable or reversed. Review its accounting correction.',
      );
    }
    final ledger = voucher.paymentAccountId == null
        ? null
        : paymentLedgerAccount(businessId, voucher.paymentAccountId!);
    final credits = journal.entry.lines
        .asMap()
        .entries
        .where(
          (e) =>
              e.value.accountId == ledger &&
              !e.value.isDebit &&
              e.value.amount.currency == voucher.amount.currency,
        )
        .toList();
    if (credits.length != 1) {
      throw StateError(
        'The source needs one exact posted credit to the selected payment account.',
      );
    }
    final credit = credits.single;
    var expected = BigInt.from(voucher.amount.minorUnits);
    if (voucher.sourceType == PaymentVoucherSourceType.claimPayment) {
      final allocations = _database.select(
        'SELECT amount_minor,currency FROM claim_settlement_allocations WHERE business_id=? AND request_id=(SELECT request_id FROM claim_settlements WHERE business_id=? AND journal_id=?)',
        [businessId.value, businessId.value, journalId.value],
      );
      if (allocations.isEmpty ||
          allocations.any((a) => a['currency'] != voucher.amount.currency)) {
        throw StateError('Review the linked claim payment allocations.');
      }
      expected = allocations.fold(
        BigInt.zero,
        (sum, a) => sum + BigInt.from(a['amount_minor'] as int),
      );
    }
    if (voucher.sourceType == PaymentVoucherSourceType.billSettlement) {
      // The voucher covers one allocation; the bank credit covers the batch.
      // Source validation above ties its amount/payee to that exact allocation.
      expected = BigInt.from(
        readBillSettlement(
          businessId,
          _billVoucherSourceIdentity(voucher.sourceId)!.requestId,
        )!.total.minorUnits,
      );
    }
    if (BigInt.from(credit.value.amount.minorUnits) != expected) {
      throw StateError(
        'The posted payment amount does not match the linked source allocation.',
      );
    }
    return PaymentVoucherPaymentEvidence(
      journalId: journalId,
      lineIndex: credit.key,
      movementAmount: credit.value.amount,
      paymentDate: journal.entry.date,
    );
  }

  PaymentVoucherReconciliationEvidence _voucherReconciliationEvidence(
    EntityId businessId,
    PaymentVoucher voucher,
    PaymentVoucherPaymentEvidence payment,
  ) {
    _ensureOpen();
    final rows = _database.select(
      '''
      SELECT DISTINCT r.id,r.approved_at,m.acceptance_id FROM (
        SELECT acceptance_id,business_id,statement_id FROM bank_statement_matches WHERE business_id=? AND journal_id=? AND line_index=?
        UNION
        SELECT b.acceptance_id,b.business_id,b.statement_id FROM bank_match_active_ledger_members l
          JOIN bank_statement_matches b ON b.business_id=l.business_id AND b.acceptance_id=l.acceptance_id
          WHERE l.business_id=? AND l.journal_id=? AND l.line_index=?
      ) m JOIN bank_reconciliation_allocations a ON a.acceptance_id=m.acceptance_id
      JOIN bank_reconciliations r ON r.id=a.completion_id AND r.business_id=m.business_id AND r.statement_id=m.statement_id
      WHERE r.business_id=? AND r.payment_account_id=?
        AND NOT EXISTS(SELECT 1 FROM bank_reconciliation_reopenings x WHERE x.completion_id=r.id)
      ''',
      [
        businessId.value,
        payment.journalId.value,
        payment.lineIndex,
        businessId.value,
        payment.journalId.value,
        payment.lineIndex,
        businessId.value,
        voucher.paymentAccountId,
      ],
    );
    if (rows.length != 1) {
      throw StateError(
        'Complete the current bank reconciliation for this exact source payment before confirming the voucher.',
      );
    }
    final row = rows.single;
    if (!_reconciliationLedgerChanges(
      businessId,
      row['id'] as String,
    ).unchanged) {
      throw StateError(
        'The completed bank review changed. Reopen and review the reconciliation.',
      );
    }
    return PaymentVoucherReconciliationEvidence(
      acceptanceId: EntityId.parse(row['acceptance_id'] as String),
      completionId: EntityId.parse(row['id'] as String),
      approvedAt: DateTime.parse(row['approved_at'] as String),
    );
  }

  void _requireVoucherFinancialEvidence(
    EntityId businessId,
    PaymentVoucher voucher,
  ) {
    if (!{
      PaymentVoucherStatus.paid,
      PaymentVoucherStatus.processed,
      PaymentVoucherStatus.reconciled,
    }.contains(voucher.status)) {
      return;
    }
    final payment = _voucherPaymentEvidence(businessId, voucher);
    if (voucher.paymentEvidence != payment) {
      throw StateError('Review and confirm the exact posted source payment.');
    }
    if (voucher.status == PaymentVoucherStatus.reconciled &&
        voucher.reconciliationEvidence !=
            _voucherReconciliationEvidence(businessId, voucher, payment)) {
      throw StateError(
        'The bank reconciliation changed. Reopen and confirm its current completed review.',
      );
    }
  }

  void _requireVoucherTransition(
    PaymentVoucher? previous,
    PaymentVoucher voucher,
  ) {
    if (previous == null) {
      if (voucher.status != PaymentVoucherStatus.draft &&
          voucher.status != PaymentVoucherStatus.pendingApproval) {
        throw StateError(
          'A new voucher must be saved or submitted as a draft.',
        );
      }
      return;
    }
    final allowed = switch (previous.status) {
      PaymentVoucherStatus.draft => {
        PaymentVoucherStatus.draft,
        PaymentVoucherStatus.pendingApproval,
        PaymentVoucherStatus.approved,
        PaymentVoucherStatus.cancelled,
      },
      PaymentVoucherStatus.pendingApproval => {
        PaymentVoucherStatus.pendingApproval,
        PaymentVoucherStatus.approved,
        PaymentVoucherStatus.cancelled,
      },
      PaymentVoucherStatus.approved => {
        PaymentVoucherStatus.approved,
        PaymentVoucherStatus.paymentOrdered,
        PaymentVoucherStatus.paid,
        PaymentVoucherStatus.cancelled,
      },
      PaymentVoucherStatus.paymentOrdered => {
        PaymentVoucherStatus.paymentOrdered,
        PaymentVoucherStatus.paid,
        PaymentVoucherStatus.cancelled,
      },
      PaymentVoucherStatus.paid => {
        PaymentVoucherStatus.paid,
        PaymentVoucherStatus.processed,
        PaymentVoucherStatus.reconciled,
      },
      PaymentVoucherStatus.processed => {
        PaymentVoucherStatus.processed,
        PaymentVoucherStatus.reconciled,
      },
      PaymentVoucherStatus.reconciled => {PaymentVoucherStatus.reconciled},
      PaymentVoucherStatus.onHold => {
        PaymentVoucherStatus.onHold,
        PaymentVoucherStatus.cancelled,
      },
      PaymentVoucherStatus.cancelled => {PaymentVoucherStatus.cancelled},
    };
    if (!allowed.contains(voucher.status)) {
      throw StateError(
        'The voucher workflow changed. Reopen and use its current action.',
      );
    }
    if (previous.status == PaymentVoucherStatus.draft) return;
    final before = previous.toJson(), after = voucher.toJson();
    final changing = <String>{'status'};
    if (previous.status == PaymentVoucherStatus.pendingApproval &&
        voucher.status == PaymentVoucherStatus.approved) {
      changing.add('approver');
    }
    if (voucher.paymentEvidence != null &&
        {
          PaymentVoucherStatus.paid,
          PaymentVoucherStatus.processed,
          PaymentVoucherStatus.reconciled,
        }.contains(voucher.status)) {
      changing.addAll(['paidAt', 'paymentDate', 'paymentEvidence']);
    }
    if (voucher.status == PaymentVoucherStatus.reconciled) {
      changing.addAll(['reconciledAt', 'reconciliationEvidence']);
    }
    for (final key in changing) {
      before.remove(key);
      after.remove(key);
    }
    if (jsonEncode(before) != jsonEncode(after)) {
      throw StateError(
        'Submitted voucher details must retain the exact reviewed source and payment instructions.',
      );
    }
  }

  PaymentVoucherStore openVoucherStore(
    EntityId businessId, {
    EntityId? actorId,
  }) {
    _ensureOpen();
    final owners = _database.select(
      'SELECT owner_id FROM local_workspace WHERE business_id=?',
      [businessId.value],
    );
    if (owners.isEmpty) throw StateError('Voucher company is unavailable.');
    final actor =
        actorId ?? EntityId.parse(owners.single['owner_id'] as String);
    final rows = _database.select(
      'SELECT id,payload FROM payment_vouchers WHERE business_id = ? AND ${_activeTransactionSql(TransactionRecordKind.paymentVoucher)}',
      [businessId.value],
    );
    final snapshots = {
      for (final row in rows) row['id'] as String: row['payload'] as String,
    };
    return PaymentVoucherStore(
      loadVouchers: () {
        _ensureOpen();
        final current = _database.select(
          'SELECT id,payload FROM payment_vouchers WHERE business_id=? AND ${_activeTransactionSql(TransactionRecordKind.paymentVoucher)}',
          [businessId.value],
        );
        snapshots
          ..clear()
          ..addAll({
            for (final row in current)
              row['id'] as String: row['payload'] as String,
          });
        return snapshots.values
            .map(
              (payload) => PaymentVoucher.fromJson(
                jsonDecode(payload) as Map<String, dynamic>,
              ),
            )
            .toList();
      },
      loadSources: () => readVoucherSources(businessId),
      approverIdentity: actor.value,
      loadPaymentEvidence: (voucher) =>
          _voucherPaymentEvidence(businessId, voucher),
      loadReconciliationEvidence: (voucher, payment) {
        late PaymentVoucherReconciliationEvidence evidence;
        _transaction(
          () => evidence = _voucherReconciliationEvidence(
            businessId,
            voucher,
            payment,
          ),
        );
        return evidence;
      },
      vouchers: snapshots.values.map(
        (payload) => PaymentVoucher.fromJson(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      ),
      persist: (voucher) {
        _ensureOpen();
        final payload = jsonEncode(voucher.toJson());
        PaymentVoucher.fromJson(jsonDecode(payload) as Map<String, dynamic>);
        _transaction(() {
          _requireReconciliationOwner(businessId, actor);
          _requireTransactionActive(
            businessId,
            TransactionRecordKind.paymentVoucher,
            voucher.id,
          );
          final rows = _database.select(
            'SELECT payload FROM payment_vouchers WHERE business_id = ? AND id = ?',
            [businessId.value, voucher.id],
          );
          final stored = rows.isEmpty ? null : rows.single['payload'];
          if (stored != snapshots[voucher.id]) {
            throw StateError(
              'Voucher changed since it was loaded. Reopen before saving.',
            );
          }
          final previous = stored == null
              ? null
              : PaymentVoucher.fromJson(
                  jsonDecode(stored as String) as Map<String, dynamic>,
                );
          _requireVoucherTransition(previous, voucher);
          if (voucher.status == PaymentVoucherStatus.approved &&
              previous?.status != PaymentVoucherStatus.approved &&
              voucher.approver != actor.value) {
            throw StateError(
              'Voucher approval must identify the current local owner.',
            );
          }
          if (voucher.paymentAccountId != null) {
            final accounts = _database.select(
              'SELECT currency FROM payment_accounts WHERE business_id = ? AND id = ?',
              [businessId.value, voucher.paymentAccountId],
            );
            if (accounts.isEmpty ||
                accounts.single['currency'] != voucher.amount.currency) {
              throw StateError(
                'Choose a payment account in this business with the voucher currency.',
              );
            }
          }
          _requireVoucherSource(businessId, voucher);
          _requireVoucherFinancialEvidence(businessId, voucher);
          if (stored == payload) return;
          _database.execute(
            'INSERT INTO payment_vouchers(business_id,id,payload) VALUES(?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET payload=excluded.payload',
            [businessId.value, voucher.id, payload],
          );
          if (previous == null) {
            _appendTransactionRootCreated(
              businessId: businessId,
              actorId: actor,
              at: DateTime.now().toUtc(),
              family: 'paymentVoucher',
              recordId: businessId,
              recordKey: voucher.id,
            );
          }
          if (voucher.paymentEvidence != null ||
              (previous != null && previous.status != voucher.status) ||
              (previous == null &&
                  voucher.status == PaymentVoucherStatus.pendingApproval)) {
            _appendAudit(
              businessId: businessId,
              actorId: actor,
              at: DateTime.now().toUtc(),
              kind: 'voucher_control_confirmed',
              subjectId: businessId,
              detail: jsonEncode({
                'voucherId': voucher.id,
                'sourceType': voucher.sourceType.name,
                'sourceId': voucher.sourceId,
                'previousStatus': previous?.status.name,
                'status': voucher.status.name,
                'previousPaymentDate': previous?.paymentDate.toIso8601String(),
                'paymentEvidence': voucher.paymentEvidence?.toJson(),
                'previousReconciliationEvidence': previous
                    ?.reconciliationEvidence
                    ?.toJson(),
                'reconciliationEvidence': voucher.reconciliationEvidence
                    ?.toJson(),
              }),
            );
          }
        });
        snapshots[voucher.id] = payload;
      },
    );
  }

  ClaimStore openClaimStore(EntityId businessId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT id,payload FROM claims WHERE business_id = ? AND ${_activeTransactionSql(TransactionRecordKind.claim)}',
      [businessId.value],
    );
    final snapshots = {
      for (final row in rows) row['id'] as String: row['payload'] as String,
    };
    return ClaimStore(
      loadClaims: () {
        _ensureOpen();
        final current = _database.select(
          'SELECT id,payload FROM claims WHERE business_id=? AND ${_activeTransactionSql(TransactionRecordKind.claim)}',
          [businessId.value],
        );
        final loaded = current
            .map(
              (row) => Claim.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              ),
            )
            .toList();
        snapshots
          ..clear()
          ..addAll({
            for (final row in current)
              row['id'] as String: row['payload'] as String,
          });
        return loaded;
      },
      claims: snapshots.values.map(
        (payload) =>
            Claim.fromJson(jsonDecode(payload) as Map<String, dynamic>),
      ),
      persistChanges: (changes) {
        _ensureOpen();
        final updates = <String, String>{};
        _transaction(() {
          final paymentIds = changes
              .map((claim) => claim.paymentBatchId)
              .whereType<EntityId>()
              .toSet();
          if (paymentIds.isNotEmpty) {
            final existing = _database.select(
              'SELECT payload FROM claims WHERE business_id = ?',
              [businessId.value],
            );
            for (final row in existing) {
              final claim = Claim.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              );
              if (paymentIds.contains(claim.paymentBatchId)) {
                throw StateError(
                  'Payment batch ID has already been committed. Reopen before retrying.',
                );
              }
            }
          }
          for (final claim in changes) {
            final id = claim.id.value;
            _requireTransactionActive(
              businessId,
              TransactionRecordKind.claim,
              id,
            );
            if (updates.containsKey(id)) {
              throw StateError('Duplicate claim in batch.');
            }
            final previous = _database.select(
              'SELECT payload FROM claims WHERE business_id = ? AND id = ?',
              [businessId.value, id],
            );
            final stored = previous.isEmpty ? null : previous.single['payload'];
            if (stored != snapshots[id]) {
              throw StateError(
                'Claim changed since it was loaded. Reopen before saving.',
              );
            }
            final recognized = _activeClaimPostings(businessId, claim.id);
            if (recognized.isNotEmpty) {
              throw StateError(
                'A recognized claim requires ledger settlement or reversal; status-only changes are not permitted.',
              );
            }
            final payload = jsonEncode(claim.toJson());
            Claim.fromJson(jsonDecode(payload) as Map<String, dynamic>);
            if (claim.status == ClaimStatus.approved ||
                claim.status == ClaimStatus.paid) {
              throw StateError(
                'Claim approval and payment require linked ledger recognition and settlement.',
              );
            }
            final prior = stored == null
                ? null
                : Claim.fromJson(
                    jsonDecode(stored as String) as Map<String, dynamic>,
                  );
            prior?.validateClaimantReplacement(claim);
            if (prior == null && claim.legacySource != null) {
              throw StateError(
                'Original Claim evidence requires a saved Claim.',
              );
            }
            prior?.validateExpenseOriginalReplacement(claim);
            _validateClaimTaxSnapshots(businessId, claim, existing: prior);
            final identity = claim.claimantIdentity;
            if (identity != null &&
                (prior?.claimantIdentity?.payeeId != identity.payeeId ||
                    prior?.claimantIdentity?.type != identity.type ||
                    prior?.claimantName != claim.claimantName)) {
              final directory = _database.select(
                'SELECT name,type FROM payees WHERE business_id=? AND id=?',
                [businessId.value, identity.payeeId],
              );
              if (directory.length != 1 ||
                  directory.single['type'] != identity.type.name ||
                  directory.single['name'] != claim.claimantName) {
                throw StateError(
                  'Select the saved employee or director in this company. The claimant changed or is unavailable.',
                );
              }
            }
            final allowed = switch (prior?.status) {
              null => {ClaimStatus.draft, ClaimStatus.submitted},
              ClaimStatus.draft => {
                ClaimStatus.draft,
                ClaimStatus.submitted,
                ClaimStatus.voided,
              },
              ClaimStatus.returned => {
                ClaimStatus.returned,
                ClaimStatus.submitted,
                ClaimStatus.voided,
              },
              ClaimStatus.submitted => {
                ClaimStatus.submitted,
                ClaimStatus.returned,
                ClaimStatus.declined,
                ClaimStatus.voided,
              },
              ClaimStatus.declined => {
                ClaimStatus.declined,
                ClaimStatus.voided,
              },
              ClaimStatus.voided => {ClaimStatus.voided},
              ClaimStatus.approved || ClaimStatus.paid => <ClaimStatus>{},
            };
            if (!allowed.contains(claim.status)) {
              throw StateError(
                'This claim transition requires linked accounting review.',
              );
            }
            // A review decision can change status, never the reviewed expense.
            // Decode both snapshots so restored unavailable attachments retain
            // the same known metadata without pretending their bytes exist.
            if (prior != null &&
                (prior.status != ClaimStatus.draft &&
                        prior.status != ClaimStatus.returned ||
                    claim.status == ClaimStatus.voided)) {
              final reviewed = prior.toJson()..remove('status');
              final proposed = claim.toJson()..remove('status');
              if (jsonEncode(reviewed) != jsonEncode(proposed)) {
                throw StateError(
                  'Reviewed claim details cannot change with a status decision.',
                );
              }
            }
            if (claim.status == ClaimStatus.submitted &&
                prior?.status != ClaimStatus.submitted &&
                claim.submissionErrors.isNotEmpty) {
              throw StateError(
                'A new claim submission requires valid details and reviewable evidence.',
              );
            }
            _database.execute(
              'INSERT INTO claims(business_id,id,payload) VALUES(?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET payload=excluded.payload',
              [businessId.value, id, payload],
            );
            if (prior == null) {
              _appendTransactionRootCreated(
                businessId: businessId,
                at: DateTime.now().toUtc(),
                family: 'claim',
                recordId: claim.id,
              );
            }
            updates[id] = payload;
          }
        });
        snapshots.addAll(updates);
      },
    );
  }

  ReconciliationClassification? reconciliationClassification(
    EntityId businessId,
    String completionId,
  ) {
    _ensureOpen();
    ReconciliationClassification? result;
    _transaction(
      () => result = _reconciliationClassification(businessId, completionId),
    );
    return result;
  }

  ReconciliationClassification? _reconciliationClassification(
    EntityId businessId,
    String completionId,
  ) {
    final chain = <Row>[];
    final visited = <String>{};
    String? next = completionId;
    String? payment;
    while (next != null) {
      if (!visited.add(next)) {
        throw StateError('Reconciliation chain contains a cycle.');
      }
      final rows = _database.select(
        'SELECT * FROM bank_reconciliations WHERE business_id=? AND id=?',
        [businessId.value, next],
      );
      if (rows.isEmpty) {
        throw StateError('Reconciliation chain is unavailable.');
      }
      final row = rows.single;
      payment ??= row['payment_account_id'] as String;
      if (payment != row['payment_account_id']) {
        throw StateError('Reconciliation chain mixes payment accounts.');
      }
      chain.add(row);
      next = row['previous_id'] as String?;
    }
    final current = reconciliationLedgerSnapshot(businessId, completionId);
    final root = chain.last;
    final initial = reconciliationLedgerSnapshot(
      businessId,
      root['id'] as String,
    );
    if (current == null || initial == null) return null;
    final rootPayload =
        jsonDecode(root['payload'] as String) as Map<String, dynamic>;
    final initialOutstanding =
        ((rootPayload['openingOutstanding'] as List?) ?? const [])
            .cast<String>()
            .toSet();
    final starts = DateTime.parse(root['starts_on'] as String);
    final clearedIds = {
      for (final m in initial.movements)
        if (m.date.isBefore(starts) && !initialOutstanding.contains(m.id)) m.id,
    };
    final unresolved = <String>{};
    final hasCombinedMembers = _database
        .select(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='bank_match_ledger_members'",
        )
        .isNotEmpty;
    for (final completion in chain.reversed) {
      final allocations = _database.select(
        'SELECT h.journal_id,h.line_index,h.business_id FROM bank_reconciliation_allocations a JOIN bank_match_history h ON h.acceptance_id=a.acceptance_id WHERE a.completion_id=?'
        '${hasCombinedMembers ? ' UNION SELECT m.journal_id,m.line_index,m.business_id FROM bank_reconciliation_allocations a JOIN bank_match_ledger_members m ON m.acceptance_id=a.acceptance_id WHERE a.completion_id=?' : ''}',
        [completion['id'], if (hasCombinedMembers) completion['id']],
      );
      final manual =
          _database
              .select(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='bank_reconciliation_cleared_movements'",
              )
              .isEmpty
          ? <Row>[]
          : _database.select(
              'SELECT m.journal_id,m.line_index,c.business_id FROM bank_reconciliation_cleared_movements m JOIN bank_reconciliations c ON c.id=m.completion_id WHERE c.id=?',
              [completion['id']],
            );
      for (final row in [...allocations, ...manual]) {
        if (row['business_id'] != businessId.value) {
          throw StateError('Allocation ownership differs.');
        }
        final id = "${row['journal_id']}:${row['line_index']}";
        if (!clearedIds.add(id)) unresolved.add(id);
      }
    }
    final present = current.movements.map((m) => m.id).toSet();
    unresolved.addAll(clearedIds.difference(present));
    final cleared = current.movements
        .where((m) => clearedIds.contains(m.id))
        .toList();
    final outstanding = current.movements
        .where((m) => !clearedIds.contains(m.id))
        .toList();
    final currency = chain.first['currency'] as String;
    final clearedBalance = _openingAfterOutstanding(cleared, {}, currency);
    return ReconciliationClassification(
      cleared: cleared,
      outstanding: outstanding,
      unresolved: unresolved,
      clearedBalance: clearedBalance,
      outstandingBalance: _openingAfterOutstanding(outstanding, {}, currency),
      closingDifference:
          Money.fromMinor(chain.first['closing_minor'] as int, currency) -
          clearedBalance,
    );
  }

  ReconciliationLedgerChanges reconciliationLedgerChanges(
    EntityId businessId,
    String completionId,
  ) {
    _ensureOpen();
    late ReconciliationLedgerChanges changes;
    _transaction(
      () => changes = _reconciliationLedgerChanges(businessId, completionId),
    );
    return changes;
  }

  ReconciliationLedgerChanges _reconciliationLedgerChanges(
    EntityId businessId,
    String completionId,
  ) {
    final version = (
      _database.select('SELECT total_changes() AS count').single['count']
          as int,
      _database.select('PRAGMA data_version').single['data_version'] as int,
    );
    if (_reconciliationChangeCacheVersion != version) {
      _reconciliationChangeCache.clear();
      _reconciliationChangeCacheVersion = version;
    }
    final cacheKey = '${businessId.value}:$completionId';
    final cached = _reconciliationChangeCache[cacheKey];
    if (cached != null) return cached;
    final snapshot = reconciliationLedgerSnapshot(businessId, completionId);
    if (snapshot == null) {
      final changes = ReconciliationLedgerChanges(
        snapshotAvailable: false,
        added: [],
        missing: [],
        changed: {},
      );
      _cacheReconciliationChanges(cacheKey, version, changes);
      return changes;
    }
    final completion = _database.select(
      'SELECT payment_account_id,ends_on,currency FROM bank_reconciliations WHERE business_id=? AND id=?',
      [businessId.value, completionId],
    ).single;
    final current = _openingLedgerMovements(
      businessId,
      completion['payment_account_id'] as String,
      DateTime.parse(completion['ends_on'] as String)
          .add(const Duration(days: 1)),
      completion['currency'] as String,
    );
    final before = {for (final m in snapshot.movements) m.id: m};
    final after = {for (final m in current) m.id: m};
    final changes = ReconciliationLedgerChanges(
      snapshotAvailable: true,
      added: current.where((m) => !before.containsKey(m.id)).toList(),
      missing: snapshot.movements
          .where((m) => !after.containsKey(m.id))
          .toList(),
      changed: {
        for (final m in current)
          if (before.containsKey(m.id) &&
              (before[m.id]!.amount != m.amount ||
                  before[m.id]!.date != m.date ||
                  before[m.id]!.memo != m.memo))
            m.id,
      },
    );
    _cacheReconciliationChanges(cacheKey, version, changes);
    return changes;
  }

  void _cacheReconciliationChanges(
    String key,
    (int, int) version,
    ReconciliationLedgerChanges changes,
  ) {
    final currentVersion = (
      _database.select('SELECT total_changes() AS count').single['count']
          as int,
      _database.select('PRAGMA data_version').single['data_version'] as int,
    );
    if (currentVersion != version) return;
    if (_reconciliationChangeCache.length >= 32) {
      _reconciliationChangeCache.remove(_reconciliationChangeCache.keys.first);
    }
    _reconciliationChangeCache[key] = changes;
  }

  ReconciliationLedgerSnapshot? reconciliationLedgerSnapshot(
    EntityId businessId,
    String completionId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT s.payload FROM bank_reconciliations c LEFT JOIN bank_reconciliation_ledger_snapshots s ON s.completion_id=c.id WHERE c.business_id=? AND c.id=?',
      [businessId.value, completionId],
    );
    if (rows.isEmpty) throw StateError('Reconciliation is unavailable.');
    if (rows.single['payload'] == null) return null;
    final data =
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw StateError('Ledger snapshot version is unsupported.');
    }
    final currency = data['currency'] as String;
    final movements = (data['movements'] as List).map((value) {
      final item = value as Map<String, dynamic>;
      return OpeningLedgerMovement(
        id: item['id'] as String,
        date: DateTime.parse(item['date'] as String),
        memo: item['memo'] as String,
        amount: Money.fromMinor(item['minor'] as int, currency),
      );
    }).toList();
    if (movements.map((m) => m.id).toSet().length != movements.length) {
      throw StateError('Duplicate snapshot movement.');
    }
    return ReconciliationLedgerSnapshot(
      movements: movements,
      balance: _openingAfterOutstanding(movements, {}, currency),
    );
  }

  ReconciliationReportSnapshot reconciliationReportSnapshot(
    EntityId businessId,
    String completionId,
  ) {
    _ensureOpen();
    late ReconciliationReportSnapshot result;
    _transaction(() {
      final rows = _database.select(
        'SELECT payment_account_id FROM bank_reconciliations WHERE business_id=? AND id=?',
        [businessId.value, completionId],
      );
      if (rows.isEmpty) throw StateError('Reconciliation is unavailable.');
      final approval = accountReconciliationHistory(
        businessId,
        rows.single['payment_account_id'] as String,
      ).singleWhere((a) => a.id == completionId);
      result = ReconciliationReportSnapshot(
        approval: approval,
        evidence: _reconciliationEvidence(businessId, completionId),
        ledger: reconciliationLedgerSnapshot(businessId, completionId),
        classification: _reconciliationClassification(businessId, completionId),
        changes: _reconciliationLedgerChanges(businessId, completionId),
        generatedAt: DateTime.now().toUtc(),
      );
    });
    return result;
  }

  ReconciliationEvidence reconciliationEvidence(
    EntityId businessId,
    String completionId,
  ) {
    _ensureOpen();
    late ReconciliationEvidence result;
    _transaction(
      () => result = _reconciliationEvidence(businessId, completionId),
    );
    return result;
  }

  ReconciliationEvidence _reconciliationEvidence(
    EntityId businessId,
    String completionId,
  ) {
    final completion = _database.select(
      'SELECT statement_id,payload,payment_account_id,starts_on,currency FROM bank_reconciliations WHERE business_id=? AND id=?',
      [businessId.value, completionId],
    );
    if (completion.isEmpty) {
      throw StateError('Reconciliation is unavailable.');
    }
    if (completion.single['statement_id'] == null) {
      return _accountReconciliationEvidence(
        businessId,
        completionId,
        completion.single,
      );
    }
    final statementId = EntityId.parse(
      completion.single['statement_id'] as String,
    );
    final statement = bankStatement(businessId, statementId)!;
    final source = {for (final row in statement.rows) row.sourceRow: row};
    final allocations = _database.select(
      'SELECT h.* FROM bank_reconciliation_allocations a JOIN bank_match_history h ON h.acceptance_id=a.acceptance_id WHERE a.completion_id=? ORDER BY h.source_row',
      [completionId],
    );
    final postedEvidence = {
      for (final movement in _statementLedgerMovements(businessId, statementId))
        movement.candidate.movementId: movement,
    };
    final evidence = <ReconciliationMatchedEvidence>[];
    for (final row in allocations) {
      if (row['business_id'] != businessId.value ||
          row['statement_id'] != statementId.value ||
          !source.containsKey(row['source_row'])) {
        throw StateError(
          'Reconciliation evidence ownership or source is invalid.',
        );
      }
      final journal = _readJournal(EntityId.parse(row['journal_id'] as String));
      final line = row['line_index'] as int;
      if (journal == null ||
          journal.metadata.businessId != businessId ||
          journal.entry.state != JournalEntryState.posted ||
          line < 0 ||
          line >= journal.entry.lines.length) {
        throw StateError('Approved ledger evidence is unavailable.');
      }
      final memberRows = [
        row['source_row'] as int,
        for (final member in _database.select(
          'SELECT source_row FROM bank_match_group_members WHERE acceptance_id=? ORDER BY source_row',
          [row['acceptance_id']],
        ))
          member['source_row'] as int,
      ];
      for (final sourceRow in memberRows) {
        if (!source.containsKey(sourceRow)) {
          throw StateError('Reconciliation group evidence is incomplete.');
        }
        evidence.add(
          ReconciliationMatchedEvidence(
            statementRow: source[sourceRow]!,
            acceptanceId: row['acceptance_id'] as String,
            journalId: row['journal_id'] as String,
            lineIndex: line,
            journalDate: journal.entry.date,
            journalMemo: journal.entry.memo,
            combinedMovements: [
              for (final member in statementMatchLedgerMembers(
                businessId,
                row['acceptance_id'] as String,
              ))
                if (statementMatchLedgerMembers(
                      businessId,
                      row['acceptance_id'] as String,
                    ).length >
                    1)
                  postedEvidence[member] ??
                      (throw StateError(
                        'Combined ledger evidence is unavailable.',
                      )),
            ],
          ),
        );
      }
    }
    if (evidence.length != statement.rows.length) {
      throw StateError('Reconciliation evidence is incomplete.');
    }
    final payload = jsonDecode(
      completion.single['payload'] as String,
    ) as Map<String, dynamic>;
    final selected = ((payload['openingOutstanding'] as List?) ?? const [])
        .cast<String>()
        .toSet();
    final opening = selected.isEmpty
        ? const <OpeningLedgerMovement>[]
        : _openingLedgerMovements(
            businessId,
            completion.single['payment_account_id'] as String,
            DateTime.parse(completion.single['starts_on'] as String),
            completion.single['currency'] as String,
          ).where((movement) => selected.contains(movement.id)).toList();
    if (opening.length != selected.length) {
      throw StateError('Approved opening evidence is unavailable.');
    }
    return ReconciliationEvidence(
      filename: statement.filename,
      sourceDigest: statement.digest,
      matches: evidence,
      openingOutstanding: opening,
      attachments: _readReconciliationAttachments(payload['attachments']),
    );
  }

  List<StatementReconciliationHistory> reconciliationHistory(
    EntityId businessId,
    EntityId statementId,
  ) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT c.*,r.reopened_at,r.actor_id AS reopened_by,r.reason AS reopening_reason '
            'FROM bank_reconciliations c LEFT JOIN bank_reconciliation_reopenings r ON r.completion_id=c.id '
            'WHERE c.business_id=? AND c.statement_id=? ORDER BY c.approved_at DESC,c.id DESC',
            [businessId.value, statementId.value],
          )
          .map(_reconciliationHistoryFromRow),
    );
  }

  StatementReconciliationHistory _reconciliationHistoryFromRow(
    Map<String, Object?> row,
  ) => StatementReconciliationHistory(
    id: row['id'] as String,
    paymentAccountId: row['payment_account_id'] as String,
    startsOn: DateTime.parse(row['starts_on'] as String),
    endsOn: DateTime.parse(row['ends_on'] as String),
    openingBalance: Money.fromMinor(
      row['opening_minor'] as int,
      row['currency'] as String,
    ),
    closingBalance: Money.fromMinor(
      row['closing_minor'] as int,
      row['currency'] as String,
    ),
    actorId: row['actor_id'] as String,
    approvedAt: DateTime.parse(row['approved_at'] as String),
    openingEvidence: row['opening_evidence'] as String,
    previousId: row['previous_id'] as String?,
    reopenedAt: row['reopened_at'] == null
        ? null
        : DateTime.parse(row['reopened_at'] as String),
    reopenedBy: row['reopened_by'] as String?,
    reopeningReason: row['reopening_reason'] as String?,
  );

  String? latestReconciliationId(EntityId businessId, String paymentAccountId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT c.id FROM bank_reconciliations c WHERE c.business_id=? AND c.payment_account_id=? '
      'AND NOT EXISTS(SELECT 1 FROM bank_reconciliation_reopenings r WHERE r.completion_id=c.id) '
      'ORDER BY c.ends_on DESC,c.id DESC LIMIT 1',
      [businessId.value, paymentAccountId],
    );
    return rows.isEmpty ? null : rows.single['id'] as String;
  }

  bool isStatementReconciled(EntityId businessId, EntityId statementId) {
    _ensureOpen();
    return _database.select(
      'SELECT c.id FROM bank_reconciliations c '
      'WHERE c.business_id=? AND c.statement_id=? '
      'AND NOT EXISTS(SELECT 1 FROM bank_reconciliation_reopenings r WHERE r.completion_id=c.id) LIMIT 1',
      [businessId.value, statementId.value],
    ).isNotEmpty;
  }

  List<OpeningLedgerMovement> _openingLedgerMovements(
    EntityId businessId,
    String payment,
    DateTime startsOn,
    String currency,
  ) {
    final ledgerId = paymentLedgerAccount(businessId, payment);
    if (ledgerId == null) {
      throw StateError('Link the payment account to its ledger first.');
    }
    final account = _database.select(
      'SELECT * FROM accounts WHERE id=? AND business_id=?',
      [ledgerId.value, businessId.value],
    );
    if (account.isEmpty) throw StateError('Ledger account is unavailable.');
    final type = _accountFromRow(account.single).account.type;
    final start = DateTime.utc(startsOn.year, startsOn.month, startsOn.day);
    final movements = <OpeningLedgerMovement>[];
    // The reconciliation concerns one linked ledger account. Start from its
    // indexed lines so a large book with few bank movements does not decode
    // every unrelated journal before showing a voucher or bank review.
    final rows = _database.select(
      '''
      SELECT e.*,l.line_index,l.account_id,l.kind,l.amount_minor,l.currency
      FROM (SELECT DISTINCT journal_id FROM journal_lines WHERE account_id=?) relevant
      JOIN journal_entries e ON e.id=relevant.journal_id
      JOIN journal_lines l ON l.journal_id=e.id
      WHERE e.business_id=? AND e.state='posted' AND e.entry_date<?
      ORDER BY e.entry_date,e.id,l.line_index
      ''',
      [ledgerId.value, businessId.value, start.toIso8601String()],
    );
    final journals = <String, Map<String, Object?>>{};
    final linesByJournal = <String, List<JournalLine>>{};
    for (final row in rows) {
      final id = row['id'] as String;
      journals.putIfAbsent(id, () => row);
      (linesByJournal[id] ??= []).add(_lineFromRow(row));
    }
    for (final row in journals.values) {
      final record = _journalFromRows(
        row,
        linesByJournal[row['id']] ?? const <JournalLine>[],
      );
      final date = DateTime.utc(
        record.entry.date.year,
        record.entry.date.month,
        record.entry.date.day,
      );
      if (record.metadata.isTombstone ||
          record.entry.validationErrors.isNotEmpty) {
        throw StateError('Opening ledger contains invalid posted evidence.');
      }
      for (var index = 0; index < record.entry.lines.length; index++) {
        final line = record.entry.lines[index];
        if (line.accountId != ledgerId) continue;
        if (line.amount.currency != currency) {
          throw StateError('Opening ledger currency differs.');
        }
        var amount =
            BigInt.from(line.amount.minorUnits) *
            BigInt.from(line.isDebit ? 1 : -1);
        if (type == AccountType.liability) amount = -amount;
        movements.add(
          OpeningLedgerMovement(
            id: '${record.entry.id.value}:$index',
            date: date,
            memo: record.entry.memo,
            amount: Money.fromMinor(amount.toInt(), currency),
          ),
        );
      }
    }
    movements.sort((a, b) {
      final dates = a.date.compareTo(b.date);
      return dates == 0 ? a.id.compareTo(b.id) : dates;
    });
    return List.unmodifiable(movements);
  }

  Money _openingAfterOutstanding(
    List<OpeningLedgerMovement> movements,
    Set<String> outstanding,
    String currency,
  ) {
    if (!outstanding.every((id) => movements.any((m) => m.id == id))) {
      throw StateError('Opening outstanding item is unavailable.');
    }
    var total = BigInt.zero;
    for (final movement in movements) {
      if (!outstanding.contains(movement.id)) {
        total += BigInt.from(movement.amount.minorUnits);
      }
    }
    if (total < BigInt.parse('-9223372036854775808') ||
        total > BigInt.parse('9223372036854775807')) {
      throw RangeError('Opening balance exceeds supported range.');
    }
    return Money.fromMinor(total.toInt(), currency);
  }

  void approveStatementReconciliation({
    required EntityId requestId,
    required EntityId businessId,
    required EntityId statementId,
    required EntityId actorId,
    required DateTime approvedAt,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    required Map<int, String> expectedAcceptanceIds,
    required String? expectedPreviousId,
    String firstOpeningEvidence = '',
    Set<String> openingOutstandingIds = const {},
    List<ReceiptAttachment> attachments = const [],
  }) {
    _ensureOpen();
    String day(DateTime d) =>
        DateTime.utc(d.year, d.month, d.day).toIso8601String();
    final ordered = expectedAcceptanceIds.keys.toList()..sort();
    final payload = jsonEncode({
      'business': businessId.value,
      'statement': statementId.value,
      'actor': actorId.value,
      'start': day(startsOn),
      'end': day(endsOn),
      'opening': openingBalance.minorUnits,
      'closing': closingBalance.minorUnits,
      'currency': openingBalance.currency,
      'closingCurrency': closingBalance.currency,
      'previous': expectedPreviousId,
      'evidence': firstOpeningEvidence.trim(),
      if (attachments.isNotEmpty)
        'attachments': jsonDecode(_reconciliationAttachmentsJson(attachments)),
      if (openingOutstandingIds.isNotEmpty)
        'openingOutstanding': (openingOutstandingIds.toList()..sort()),
      'matches': {
        for (final row in ordered) '$row': expectedAcceptanceIds[row],
      },
    });
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final priorRequest = _database.select(
        'SELECT payload FROM bank_reconciliations WHERE id=?',
        [requestId.value],
      );
      if (priorRequest.isNotEmpty) {
        if (priorRequest.single['payload'] != payload) {
          throw StateError('Approval request changed.');
        }
        return;
      }
      _requireStatementEvidence(businessId, statementId);
      final imports = _database.select(
        'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
        [businessId.value, statementId.value],
      );
      if (imports.isEmpty) throw StateError('Statement is unavailable.');
      final payment = imports.single['payment_account_id'] as String;
      final duplicate = _database.select(
        'SELECT c.id FROM bank_reconciliations c WHERE c.statement_id=? AND NOT EXISTS(SELECT 1 FROM bank_reconciliation_reopenings r WHERE r.completion_id=c.id)',
        [statementId.value],
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Statement is already reconciled.');
      }
      final latest = latestReconciliationId(businessId, payment);
      if (latest != expectedPreviousId) {
        throw StateError('Previous reconciliation changed. Review again.');
      }
      if (latest != null &&
          !_reconciliationLedgerChanges(businessId, latest).unchanged) {
        throw StateError(
          'The previous reconciliation ledger changed or lacks a snapshot. Reopen and review it before continuing.',
        );
      }
      if (latest == null) {
        if (firstOpeningEvidence.trim().isEmpty) {
          throw ArgumentError(
            'Document the first opening balance and any outstanding items.',
          );
        }
      } else {
        final previous = _database.select(
          'SELECT ends_on,closing_minor,currency FROM bank_reconciliations WHERE id=?',
          [latest],
        ).single;
        final next = DateTime.parse(previous['ends_on'] as String)
            .add(const Duration(days: 1));
        if (day(startsOn) != next.toIso8601String() ||
            previous['closing_minor'] != openingBalance.minorUnits ||
            previous['currency'] != openingBalance.currency) {
          throw StateError(
            'Statement must continue the previous period and closing balance.',
          );
        }
      }
      final active = _activeStatementAcceptanceIds(businessId, statementId);
      if (active.length != expectedAcceptanceIds.length ||
          active.entries.any(
            (row) => expectedAcceptanceIds[row.key] != row.value,
          )) {
        throw StateError('Accepted matches changed. Review again.');
      }
      if (latest != null && openingOutstandingIds.isNotEmpty) {
        throw StateError(
          'Opening outstanding selection applies only to the first reconciliation.',
        );
      }
      if (latest == null &&
          _openingAfterOutstanding(
                _openingLedgerMovements(
                  businessId,
                  payment,
                  startsOn,
                  openingBalance.currency,
                ),
                openingOutstandingIds,
                openingBalance.currency,
              ) !=
              openingBalance) {
        throw StateError(
          'The first statement opening differs from the recorded ledger. Review the opening entries and outstanding items before approval.',
        );
      }
      final review = StatementReconciliationReview.evaluate(
        startsOn: startsOn,
        endsOn: endsOn,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        rows: _statementMatchSuggestions(
          businessId,
          statementId,
          unrestrictedDates: true,
        ),
        acceptedMatches: acceptedStatementMatches(businessId, statementId),
        acceptanceIds: _activeStatementAcceptanceIds(businessId, statementId),
        combinedMovements: _activeCombinedMovements(businessId, statementId),
        groupedMovementAmounts: _activeGroupMovementAmounts(
          businessId,
          statementId,
        ),
      );
      if (!review.rowsAndBalancesAgree) {
        throw StateError(
          'Resolve statement differences and unmatched rows first.',
        );
      }
      _database.execute(
        'INSERT INTO bank_reconciliations(id,business_id,payment_account_id,statement_id,starts_on,ends_on,opening_minor,closing_minor,currency,actor_id,approved_at,previous_id,opening_evidence,payload) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          requestId.value,
          businessId.value,
          payment,
          statementId.value,
          day(startsOn),
          day(endsOn),
          openingBalance.minorUnits,
          closingBalance.minorUnits,
          openingBalance.currency,
          actorId.value,
          approvedAt.toUtc().toIso8601String(),
          latest,
          firstOpeningEvidence.trim(),
          payload,
        ],
      );
      final ledgerAtApproval = _openingLedgerMovements(
        businessId,
        payment,
        DateTime.utc(
          endsOn.year,
          endsOn.month,
          endsOn.day,
        ).add(const Duration(days: 1)),
        openingBalance.currency,
      );
      _database.execute(
        'INSERT INTO bank_reconciliation_ledger_snapshots(completion_id,payload) VALUES(?,?)',
        [
          requestId.value,
          jsonEncode({
            'version': 1,
            'currency': openingBalance.currency,
            'movements': [
              for (final movement in ledgerAtApproval)
                {
                  'id': movement.id,
                  'date': movement.date.toIso8601String(),
                  'memo': movement.memo,
                  'minor': movement.amount.minorUnits,
                },
            ],
          }),
        ],
      );
      for (final acceptanceId in active.values.toSet()) {
        _database.execute(
          'INSERT INTO bank_reconciliation_allocations(completion_id,acceptance_id) VALUES(?,?)',
          [requestId.value, acceptanceId],
        );
      }
      final classification = _reconciliationClassification(
        businessId,
        requestId.value,
      );
      if (classification == null || !classification.agrees) {
        throw StateError(
          'Cleared ledger movements do not support the statement closing balance. Review the opening and match dates.',
        );
      }
      _database.execute(
        'DELETE FROM bank_reconciliation_drafts WHERE business_id=? AND statement_id=?',
        [businessId.value, statementId.value],
      );
    });
  }

  void _requireReconciliationOwner(EntityId businessId, EntityId actorId) {
    final owner = _database.select(
      'SELECT owner_id FROM local_workspace WHERE business_id=?',
      [businessId.value],
    );
    if (owner.isEmpty || owner.single['owner_id'] != actorId.value) {
      throw StateError('The business owner must approve this action.');
    }
  }

  void reopenStatementReconciliation({
    required EntityId businessId,
    required String completionId,
    required EntityId actorId,
    required DateTime reopenedAt,
    required String reason,
  }) {
    _ensureOpen();
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reopening reason is required.');
    }
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final completion = _database.select(
        'SELECT payment_account_id FROM bank_reconciliations WHERE business_id=? AND id=?',
        [businessId.value, completionId],
      );
      if (completion.isEmpty) {
        throw StateError('Reconciliation is unavailable.');
      }
      final old = _database.select(
        'SELECT actor_id,reason FROM bank_reconciliation_reopenings WHERE completion_id=?',
        [completionId],
      );
      if (old.isNotEmpty) {
        if (old.single['actor_id'] != actorId.value ||
            old.single['reason'] != reason.trim()) {
          throw StateError('Reopening request changed.');
        }
        return;
      }
      if (latestReconciliationId(
            businessId,
            completion.single['payment_account_id'] as String,
          ) !=
          completionId) {
        throw StateError('Reopen later reconciliations first.');
      }
      _database.execute(
        'INSERT INTO bank_reconciliation_reopenings(completion_id,actor_id,reopened_at,reason) VALUES(?,?,?,?)',
        [
          completionId,
          actorId.value,
          reopenedAt.toUtc().toIso8601String(),
          reason.trim(),
        ],
      );
    });
  }

  StatementReconciliationReview reviewStatementReconciliation({
    required EntityId businessId,
    required EntityId statementId,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
  }) => prepareStatementReconciliation(
    businessId: businessId,
    statementId: statementId,
    startsOn: startsOn,
    endsOn: endsOn,
    openingBalance: openingBalance,
    closingBalance: closingBalance,
  ).review;

  StatementReconciliationSnapshot prepareStatementReconciliation({
    required EntityId businessId,
    required EntityId statementId,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    Set<String> openingOutstandingIds = const {},
  }) {
    _ensureOpen();
    late StatementReconciliationSnapshot snapshot;
    _transaction(() {
      final review = StatementReconciliationReview.evaluate(
        startsOn: startsOn,
        endsOn: endsOn,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        rows: _statementMatchSuggestions(
          businessId,
          statementId,
          unrestrictedDates: true,
        ),
        acceptedMatches: acceptedStatementMatches(businessId, statementId),
        acceptanceIds: _activeStatementAcceptanceIds(businessId, statementId),
        combinedMovements: _activeCombinedMovements(businessId, statementId),
        groupedMovementAmounts: _activeGroupMovementAmounts(
          businessId,
          statementId,
        ),
      );
      final payment =
          _database.select(
                'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
                [businessId.value, statementId.value],
              ).single['payment_account_id']
              as String;
      final matches = _activeStatementAcceptanceIds(businessId, statementId);
      final previousId = latestReconciliationId(businessId, payment);
      final previous = previousId == null
          ? null
          : _database.select(
              'SELECT closing_minor,currency,ends_on FROM bank_reconciliations WHERE id=?',
              [previousId],
            ).single;
      if (previous != null && openingOutstandingIds.isNotEmpty) {
        throw StateError(
          'Opening outstanding selection applies only to the first reconciliation.',
        );
      }
      final openingMovements = previous == null
          ? _openingLedgerMovements(
              businessId,
              payment,
              startsOn,
              openingBalance.currency,
            )
          : const <OpeningLedgerMovement>[];
      final recordedOpening = previous == null
          ? _openingAfterOutstanding(
              openingMovements,
              openingOutstandingIds,
              openingBalance.currency,
            )
          : Money.fromMinor(
              previous['closing_minor'] as int,
              previous['currency'] as String,
            );
      snapshot = StatementReconciliationSnapshot(
        review: review,
        startsOn: startsOn,
        endsOn: endsOn,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        previousId: previousId,
        recordedOpening: recordedOpening,
        previousLedgerUnchanged:
            previousId == null ||
            _reconciliationLedgerChanges(businessId, previousId).unchanged,
        openingMovements: openingMovements,
        openingOutstandingIds: openingOutstandingIds,
        requiredStart: previous == null
            ? null
            : DateTime.parse(previous['ends_on'] as String)
                  .add(const Duration(days: 1)),
        acceptanceIds: matches,
      );
    });
    return snapshot;
  }

  List<StatementPostedMovement> _statementLedgerMovements(
    EntityId businessId,
    EntityId statementId,
  ) {
    final source = bankStatement(businessId, statementId);
    if (source == null) throw StateError('Statement is unavailable.');
    final imported = _database.select(
      'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
      [businessId.value, statementId.value],
    ).single;
    final ledgerId = paymentLedgerAccount(
      businessId,
      imported['payment_account_id'] as String,
    );
    if (ledgerId == null) {
      throw StateError('Link a ledger account before reviewing matches.');
    }
    final account = _database.select(
      'SELECT type FROM accounts WHERE business_id=? AND id=?',
      [businessId.value, ledgerId.value],
    );
    if (account.isEmpty) {
      throw StateError('Linked ledger account is unavailable.');
    }
    final liability = account.single['type'] == AccountType.liability.name;
    final movements = <StatementPostedMovement>[];
    for (final journal in _readJournalSnapshot(businessId)) {
      if (journal.entry.state != JournalEntryState.posted) continue;
      if (journal.metadata.isTombstone ||
          journal.entry.validationErrors.isNotEmpty) {
        throw StateError('Invalid posted journal requires accounting review.');
      }
      for (var index = 0; index < journal.entry.lines.length; index++) {
        final line = journal.entry.lines[index];
        if (line.accountId != ledgerId) continue;
        if (line.amount.currency != source.currency) {
          throw StateError('Statement and ledger movement currencies differ.');
        }
        final amount = Money.fromMinor(
          line.amount.minorUnits * (line.isDebit != liability ? 1 : -1),
          source.currency,
        );
        movements.add(
          StatementPostedMovement(
            candidate: StatementMatchCandidate(
              journalId: journal.entry.id,
              lineIndex: index,
              date: journal.entry.date,
              memo: journal.entry.memo,
              daysApart: 0,
            ),
            amount: amount,
          ),
        );
      }
    }
    return movements;
  }

  bool _journalAlreadyMatched(EntityId businessId, EntityId journalId) =>
      _database.select(
        'SELECT 1 FROM bank_statement_matches WHERE business_id=? AND journal_id=? UNION ALL SELECT 1 FROM bank_match_active_ledger_members WHERE business_id=? AND journal_id=? LIMIT 1',
        [businessId.value, journalId.value, businessId.value, journalId.value],
      ).isNotEmpty;

  bool _movementAlreadyMatched(EntityId businessId, String movement) {
    final split = movement.split(':');
    return _database.select(
      'SELECT 1 FROM bank_statement_matches WHERE business_id=? AND journal_id=? AND line_index=? UNION ALL SELECT 1 FROM bank_match_active_ledger_members WHERE business_id=? AND journal_id=? AND line_index=? LIMIT 1',
      [
        businessId.value,
        split.first,
        int.parse(split.last),
        businessId.value,
        split.first,
        int.parse(split.last),
      ],
    ).isNotEmpty;
  }

  /// Scoped to one bank row. Other signs, currencies, accounts, drafts and
  /// already allocated movements never enter the selectable list.
  List<StatementPostedMovement> statementMatchSearchCandidates({
    required EntityId businessId,
    required EntityId statementId,
    required int sourceRow,
    String query = '',
    DateTime? from,
    DateTime? through,
  }) {
    _ensureOpen();
    final statement = bankStatement(businessId, statementId);
    final rows = statement?.rows
        .where((row) => row.sourceRow == sourceRow)
        .toList();
    if (rows == null || rows.length != 1) {
      throw StateError('Statement transaction is unavailable.');
    }
    final anchor = rows.single;
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    if (from != null && through != null && day(from).isAfter(day(through))) {
      throw ArgumentError('Enter a valid date range.');
    }
    final candidates =
        _statementLedgerMovements(businessId, statementId)
            .where(
              (movement) =>
                  !movement.amount.isZero &&
                  (movement.amount.minorUnits > 0) ==
                      (anchor.amount.minorUnits > 0) &&
                  !_movementAlreadyMatched(
                    businessId,
                    movement.candidate.movementId,
                  ) &&
                  movement.candidate.memo.toLowerCase().contains(
                    query.trim().toLowerCase(),
                  ) &&
                  (from == null ||
                      !day(movement.candidate.date).isBefore(day(from))) &&
                  (through == null ||
                      !day(movement.candidate.date).isAfter(day(through))),
            )
            .toList()
          ..sort((a, b) {
            final days = day(a.candidate.date)
                .difference(day(anchor.date))
                .inDays
                .abs()
                .compareTo(
                  day(b.candidate.date)
                      .difference(day(anchor.date))
                      .inDays
                      .abs(),
                );
            if (days != 0) return days;
            final memo = a.candidate.memo.compareTo(b.candidate.memo);
            return memo != 0
                ? memo
                : a.candidate.movementId.compareTo(b.candidate.movementId);
          });
    return List.unmodifiable(candidates);
  }

  List<String> statementMatchLedgerMembers(
    EntityId businessId,
    String acceptanceId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT journal_id,line_index FROM bank_match_ledger_members WHERE business_id=? AND acceptance_id=? ORDER BY journal_id,line_index',
      [businessId.value, acceptanceId],
    );
    if (rows.isNotEmpty) {
      return List.unmodifiable(
        rows.map((row) => "${row['journal_id']}:${row['line_index']}"),
      );
    }
    return List.unmodifiable(
      _database
          .select(
            'SELECT journal_id,line_index FROM bank_match_history WHERE business_id=? AND acceptance_id=?',
            [businessId.value, acceptanceId],
          )
          .map((row) => "${row['journal_id']}:${row['line_index']}"),
    );
  }

  void _requireStatementEvidence(EntityId businessId, EntityId statementId) {
    if (bankStatement(businessId, statementId)?.sourceAvailable != true) {
      throw StateError(
        'Reconnect the original bank statement before matching or approving new reconciliation changes. Retained history remains available.',
      );
    }
  }

  void acceptStatementCombinedMatch({
    required EntityId businessId,
    required EntityId statementId,
    required int sourceRow,
    required Set<String> movementIds,
    required EntityId actorId,
    required DateTime acceptedAt,
  }) {
    _ensureOpen();
    if (movementIds.isEmpty) {
      throw ArgumentError('Select posted records to match.');
    }
    // Single selection keeps the established acceptance contract and history.
    if (movementIds.length == 1) {
      final parts = movementIds.single.split(':');
      acceptStatementMatch(
        businessId: businessId,
        statementId: statementId,
        sourceRow: sourceRow,
        journalId: EntityId.parse(parts.first),
        lineIndex: int.parse(parts.last),
        actorId: actorId,
        acceptedAt: acceptedAt,
      );
      return;
    }
    _transaction(() {
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      if (owner.isEmpty || owner.single['owner_id'] != actorId.value) {
        throw StateError('The current business owner must approve the match.');
      }
      _requireStatementEvidence(businessId, statementId);
      if (isStatementReconciled(businessId, statementId)) {
        throw StateError(
          'Reopen the approved reconciliation before changing its matches.',
        );
      }
      final existing = statementMatchAcceptanceId(
        businessId,
        statementId,
        sourceRow,
      );
      if (existing != null) {
        final members = statementMatchLedgerMembers(
          businessId,
          existing,
        ).toSet();
        if (members.length == movementIds.length &&
            members.containsAll(movementIds)) {
          return;
        }
        throw StateError('This statement row already has an accepted match.');
      }
      final candidates = {
        for (final movement in statementMatchSearchCandidates(
          businessId: businessId,
          statementId: statementId,
          sourceRow: sourceRow,
        ))
          movement.candidate.movementId: movement,
      };
      if (!movementIds.every(candidates.containsKey)) {
        throw StateError(
          'Selected posted records are unavailable or already matched. Reload the search.',
        );
      }
      final source = bankStatement(
        businessId,
        statementId,
      )!.rows.singleWhere((row) => row.sourceRow == sourceRow);
      final total = movementIds.fold<BigInt>(
        BigInt.zero,
        (sum, id) => sum + BigInt.from(candidates[id]!.amount.minorUnits),
      );
      if (total != BigInt.from(source.amount.minorUnits)) {
        throw StateError(
          'Selected posted records must total the exact bank transaction amount.',
        );
      }
      final ordered = movementIds.toList()..sort();
      final first = ordered.first.split(':');
      final acceptance = EntityId.random().value;
      final timestamp = acceptedAt.toUtc().toIso8601String();
      _database.execute(
        'INSERT INTO bank_match_history(acceptance_id,business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          acceptance,
          businessId.value,
          statementId.value,
          sourceRow,
          first.first,
          int.parse(first.last),
          actorId.value,
          timestamp,
        ],
      );
      _database.execute(
        'INSERT INTO bank_statement_matches(business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at,acceptance_id) VALUES(?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          statementId.value,
          sourceRow,
          first.first,
          int.parse(first.last),
          actorId.value,
          timestamp,
          acceptance,
        ],
      );
      for (final id in ordered) {
        final parts = id.split(':');
        _database.execute(
          'INSERT INTO bank_match_ledger_members(acceptance_id,business_id,journal_id,line_index) VALUES(?,?,?,?)',
          [acceptance, businessId.value, parts.first, int.parse(parts.last)],
        );
        _database.execute(
          'INSERT INTO bank_match_active_ledger_members(acceptance_id,business_id,journal_id,line_index) VALUES(?,?,?,?)',
          [acceptance, businessId.value, parts.first, int.parse(parts.last)],
        );
      }
    });
  }

  Map<String, List<StatementPostedMovement>> _activeCombinedMovements(
    EntityId businessId,
    EntityId statementId,
  ) {
    final posted = {
      for (final movement in _statementLedgerMovements(businessId, statementId))
        movement.candidate.movementId: movement,
    };
    final result = <String, List<StatementPostedMovement>>{};
    for (final acceptance in _database.select(
      'SELECT acceptance_id FROM bank_statement_matches WHERE business_id=? AND statement_id=? AND EXISTS(SELECT 1 FROM bank_match_active_ledger_members m WHERE m.acceptance_id=bank_statement_matches.acceptance_id)',
      [businessId.value, statementId.value],
    )) {
      final id = acceptance['acceptance_id'] as String;
      final members = statementMatchLedgerMembers(businessId, id);
      final active = _database
          .select(
            'SELECT journal_id,line_index FROM bank_match_active_ledger_members WHERE business_id=? AND acceptance_id=?',
            [businessId.value, id],
          )
          .map((row) => "${row['journal_id']}:${row['line_index']}")
          .toSet();
      if (members.length < 2 ||
          members.length != active.length ||
          !active.containsAll(members) ||
          !members.every(posted.containsKey)) {
        throw StateError('Combined match evidence is incomplete.');
      }
      result[id] = [for (final member in members) posted[member]!];
    }
    return result;
  }

  List<StatementRowSuggestions> statementMatchSuggestions(
    EntityId businessId,
    EntityId statementId, {
    bool includeOlderMovements = false,
    StatementMatchWindow? window,
    bool unrestrictedDates = false,
  }) {
    _ensureOpen();
    late List<StatementRowSuggestions> result;
    _transaction(
      () => result = _statementMatchSuggestions(
        businessId,
        statementId,
        includeOlderMovements: includeOlderMovements,
        window: window,
        unrestrictedDates: unrestrictedDates,
      ),
    );
    return result;
  }

  List<StatementRowSuggestions> _statementMatchSuggestions(
    EntityId businessId,
    EntityId statementId, {
    bool includeOlderMovements = false,
    StatementMatchWindow? window,
    bool unrestrictedDates = false,
  }) {
    final imported = _database.select(
      'SELECT payment_account_id FROM bank_statement_imports WHERE business_id = ? AND id = ?',
      [businessId.value, statementId.value],
    );
    if (imported.isEmpty) throw StateError('Statement is unavailable.');
    final ledgerId = paymentLedgerAccount(
      businessId,
      imported.single['payment_account_id'] as String,
    );
    if (ledgerId == null) {
      throw StateError('Link a ledger account before reviewing matches.');
    }
    final accounts = _database.select(
      'SELECT * FROM accounts WHERE business_id = ? AND id = ?',
      [businessId.value, ledgerId.value],
    );
    if (accounts.isEmpty) {
      throw StateError('Linked ledger account is unavailable.');
    }
    final journals = _readJournalSnapshot(businessId);
    final suggestions = suggestStatementMatches(
      businessId: businessId,
      ledgerAccount: _accountFromRow(accounts.single).account,
      statement: bankStatement(businessId, statementId)!,
      includeOlderMovements: includeOlderMovements,
      window: window,
      unrestrictedDates: unrestrictedDates,
      journals: journals,
    );
    final accepted = acceptedStatementMatches(businessId, statementId);
    return [
      for (final suggestion in suggestions)
        StatementRowSuggestions(
          row: suggestion.row,
          candidates: List.unmodifiable(
            suggestion.candidates.where(
              (candidate) =>
                  accepted[suggestion.row.sourceRow] == candidate.movementId ||
                  !_movementAlreadyMatched(businessId, candidate.movementId),
            ),
          ),
        ),
    ];
  }

  Map<int, String> acceptedStatementMatches(
    EntityId businessId,
    EntityId statementId,
  ) {
    _ensureOpen();
    return Map.unmodifiable({
      for (final row in _database.select(
        'SELECT source_row,journal_id,line_index FROM bank_statement_matches WHERE business_id = ? AND statement_id = ?',
        [businessId.value, statementId.value],
      ))
        row['source_row'] as int: "${row['journal_id']}:${row['line_index']}",
      for (final row in _database.select(
        'SELECT m.source_row,b.journal_id,b.line_index FROM bank_match_active_members m JOIN bank_statement_matches b ON b.acceptance_id=m.acceptance_id WHERE m.business_id=? AND m.statement_id=?',
        [businessId.value, statementId.value],
      ))
        row['source_row'] as int: "${row['journal_id']}:${row['line_index']}",
    });
  }

  /// Headers for movements accepted on one statement. Match review needs
  /// their memo and date, never every journal and its lines in the company.
  Map<String, ({DateTime date, String memo})> journalMatchHeaders(
    EntityId businessId,
    EntityId statementId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      '''SELECT j.id,j.entry_date,j.memo FROM journal_entries j
      WHERE j.business_id=? AND j.id IN (
        SELECT m.journal_id FROM bank_statement_matches m
          WHERE m.business_id=? AND m.statement_id=?
        UNION
        SELECT l.journal_id FROM bank_match_active_ledger_members l
          JOIN bank_statement_matches m ON m.acceptance_id=l.acceptance_id
          WHERE l.business_id=? AND m.business_id=? AND m.statement_id=?
      )''',
      [
        businessId.value,
        businessId.value,
        statementId.value,
        businessId.value,
        businessId.value,
        statementId.value,
      ],
    );
    return Map.unmodifiable({
      for (final row in rows)
        row['id'] as String: (
          date: DateTime.parse(row['entry_date'] as String),
          memo: row['memo'] as String,
        ),
    });
  }

  /// Every member shares one acceptance ID, so reconciliation allocates the
  /// posted bank movement once while still covering each source row.
  Map<int, String> _activeStatementAcceptanceIds(
    EntityId businessId,
    EntityId statementId,
  ) => Map.unmodifiable({
    for (final row in _database.select(
      'SELECT source_row,acceptance_id FROM bank_statement_matches WHERE business_id=? AND statement_id=?',
      [businessId.value, statementId.value],
    ))
      row['source_row'] as int: row['acceptance_id'] as String,
    for (final row in _database.select(
      'SELECT source_row,acceptance_id FROM bank_match_active_members WHERE business_id=? AND statement_id=?',
      [businessId.value, statementId.value],
    ))
      row['source_row'] as int: row['acceptance_id'] as String,
  });

  Map<String, Money> _activeGroupMovementAmounts(
    EntityId businessId,
    EntityId statementId,
  ) => Map.unmodifiable({
    for (final row in _database.select(
      'SELECT b.acceptance_id,l.amount_minor,l.currency,l.kind,a.type FROM bank_statement_matches b JOIN journal_lines l ON l.journal_id=b.journal_id AND l.line_index=b.line_index JOIN accounts a ON a.id=l.account_id WHERE b.business_id=? AND b.statement_id=? AND EXISTS(SELECT 1 FROM bank_match_active_members m WHERE m.acceptance_id=b.acceptance_id)',
      [businessId.value, statementId.value],
    ))
      row['acceptance_id'] as String: Money.fromMinor(
        (row['amount_minor'] as int) *
            ((row['kind'] == JournalLineKind.debit.name) ==
                    (row['type'] == AccountType.asset.name)
                ? 1
                : -1),
        row['currency'] as String,
      ),
  });

  /// Suggests one posted bank movement for the exact signed sum of selected
  /// rows. This never accepts or posts a transaction.
  List<StatementMatchCandidate> statementGroupMatchSuggestions({
    required EntityId businessId,
    required EntityId statementId,
    required Set<int> sourceRows,
    bool includeOlderMovements = false,
    DateTime? from,
    DateTime? through,
  }) {
    _ensureOpen();
    if (sourceRows.length < 2) {
      throw ArgumentError('Select at least two statement transactions.');
    }
    final statement = bankStatement(businessId, statementId);
    if (statement == null) throw StateError('Statement is unavailable.');
    final selected = statement.rows
        .where((row) => sourceRows.contains(row.sourceRow))
        .toList();
    if (selected.length != sourceRows.length ||
        selected.any((row) => row.amount.isZero) ||
        selected.any(
          (row) =>
              (row.amount.minorUnits > 0) !=
              (selected.first.amount.minorUnits > 0),
        )) {
      throw StateError('Selected rows must exist and have the same direction.');
    }
    final total = selected.fold<BigInt>(
      BigInt.zero,
      (sum, row) => sum + BigInt.from(row.amount.minorUnits),
    );
    final imported = _database.select(
      'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
      [businessId.value, statementId.value],
    );
    final ledgerId = paymentLedgerAccount(
      businessId,
      imported.single['payment_account_id'] as String,
    );
    if (ledgerId == null) {
      throw StateError('Link a ledger account before reviewing matches.');
    }
    final ledger = _database.select(
      'SELECT type FROM accounts WHERE business_id=? AND id=?',
      [businessId.value, ledgerId.value],
    );
    if (ledger.isEmpty) {
      throw StateError('Linked ledger account is unavailable.');
    }
    final liability = ledger.single['type'] == AccountType.liability.name;
    DateTime day(DateTime value) =>
        DateTime.utc(value.year, value.month, value.day);
    final earliest = selected
        .map((row) => day(row.date))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final candidates = <StatementMatchCandidate>[];
    for (final stored in _readJournalSnapshot(businessId)) {
      if (stored.entry.state != JournalEntryState.posted ||
          stored.metadata.isTombstone ||
          stored.entry.validationErrors.isNotEmpty) {
        continue;
      }
      final journal = stored.entry;
      final date = day(journal.date);
      if ((from != null && date.isBefore(day(from))) ||
          (through != null && date.isAfter(day(through)))) {
        continue;
      }
      final maxDays = selected
          .map((bankRow) => date.difference(day(bankRow.date)).inDays.abs())
          .reduce((a, b) => a > b ? a : b);
      if (maxDays > 3 && !(includeOlderMovements && date.isBefore(earliest))) {
        continue;
      }
      for (var index = 0; index < journal.lines.length; index++) {
        final line = journal.lines[index];
        if (line.accountId != ledgerId ||
            line.amount.currency != statement.currency) {
          continue;
        }
        final signed =
            BigInt.from(line.amount.minorUnits) *
            BigInt.from(line.isDebit != liability ? 1 : -1);
        if (signed != total) continue;
        if (_database.select(
          'SELECT 1 FROM bank_statement_matches WHERE business_id=? AND journal_id=? AND line_index=?',
          [businessId.value, journal.id.value, index],
        ).isNotEmpty) {
          continue;
        }
        candidates.add(
          StatementMatchCandidate(
            journalId: journal.id,
            lineIndex: index,
            date: date,
            memo: journal.memo,
            daysApart: maxDays,
          ),
        );
      }
    }
    candidates.sort((a, b) {
      final days = a.daysApart.compareTo(b.daysApart);
      if (days != 0) return days;
      final reference = a.memo.compareTo(b.memo);
      return reference != 0 ? reference : a.movementId.compareTo(b.movementId);
    });
    return List.unmodifiable(candidates);
  }

  /// The current accepted links only. Retracted historical links are excluded.
  /// Automatic links are recorded with the dedicated `automatic` actor ID.
  Map<int, bool> statementMatchAutomaticFlags(
    EntityId businessId,
    EntityId statementId,
  ) {
    _ensureOpen();
    return Map.unmodifiable({
      for (final row in _database.select(
        'SELECT source_row,actor_id FROM bank_statement_matches WHERE business_id = ? AND statement_id = ?',
        [businessId.value, statementId.value],
      ))
        row['source_row'] as int: row['actor_id'] == 'automatic',
      for (final row in _database.select(
        'SELECT m.source_row,b.actor_id FROM bank_match_active_members m JOIN bank_statement_matches b ON b.acceptance_id=m.acceptance_id WHERE m.business_id=? AND m.statement_id=?',
        [businessId.value, statementId.value],
      ))
        row['source_row'] as int: row['actor_id'] == 'automatic',
    });
  }

  List<
    ({
      String acceptanceId,
      int sourceRow,
      String movementId,
      List<String> movementIds,
      String actorId,
      DateTime acceptedAt,
      String? correctionActorId,
      DateTime? retractedAt,
      String? reason,
    })
  >
  statementMatchHistory(EntityId businessId, EntityId statementId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT h.*,members.source_row AS member_source_row,r.actor_id AS correction_actor_id,r.retracted_at,r.reason '
            'FROM (SELECT acceptance_id,source_row FROM bank_match_history UNION ALL SELECT acceptance_id,source_row FROM bank_match_group_members) members '
            'JOIN bank_match_history h ON h.acceptance_id=members.acceptance_id '
            'LEFT JOIN bank_match_retractions r '
            'ON r.acceptance_id=h.acceptance_id AND r.business_id=h.business_id '
            'WHERE h.business_id=? AND h.statement_id=? '
            'ORDER BY h.accepted_at,h.acceptance_id,members.source_row',
            [businessId.value, statementId.value],
          )
          .map(
            (row) => (
              acceptanceId: row['acceptance_id'] as String,
              sourceRow: row['member_source_row'] as int,
              movementId: "${row['journal_id']}:${row['line_index']}",
              movementIds: statementMatchLedgerMembers(
                businessId,
                row['acceptance_id'] as String,
              ),
              actorId: row['actor_id'] as String,
              acceptedAt: DateTime.parse(row['accepted_at'] as String),
              correctionActorId: row['correction_actor_id'] as String?,
              retractedAt: row['retracted_at'] == null
                  ? null
                  : DateTime.parse(row['retracted_at'] as String),
              reason: row['reason'] as String?,
            ),
          ),
    );
  }

  String? statementMatchAcceptanceId(
    EntityId businessId,
    EntityId statementId,
    int sourceRow,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT acceptance_id FROM bank_statement_matches WHERE business_id = ? AND statement_id = ? AND source_row = ?',
      [businessId.value, statementId.value, sourceRow],
    );
    if (rows.isNotEmpty) return rows.single['acceptance_id'] as String;
    final member = _database.select(
      'SELECT acceptance_id FROM bank_match_active_members WHERE business_id=? AND statement_id=? AND source_row=?',
      [businessId.value, statementId.value, sourceRow],
    );
    return member.isEmpty ? null : member.single['acceptance_id'] as String;
  }

  void retractStatementMatch({
    required EntityId businessId,
    required String acceptanceId,
    required EntityId actorId,
    required DateTime retractedAt,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A correction reason is required.');
    }
    _ensureOpen();
    _joinTransaction(() {
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id = ?',
        [businessId.value],
      );
      if (owner.isEmpty || owner.single['owner_id'] != actorId.value) {
        throw StateError(
          'The current business owner must approve the correction.',
        );
      }
      final previous = _database.select(
        'SELECT actor_id,reason FROM bank_match_retractions WHERE business_id = ? AND acceptance_id = ?',
        [businessId.value, acceptanceId],
      );
      if (previous.isNotEmpty) {
        if (previous.single['actor_id'] == actorId.value &&
            previous.single['reason'] == reason.trim()) {
          return;
        }
        throw StateError('This match correction has already been recorded.');
      }
      final active = _database.select(
        'SELECT acceptance_id,statement_id FROM bank_statement_matches WHERE business_id = ? AND acceptance_id = ?',
        [businessId.value, acceptanceId],
      );
      if (active.isEmpty) {
        throw StateError('The reviewed match is no longer active.');
      }
      if (isStatementReconciled(
        businessId,
        EntityId.parse(active.single['statement_id'] as String),
      )) {
        throw StateError(
          'Reopen the approved reconciliation before changing its matches.',
        );
      }
      final members = _database.select(
        'SELECT journal_id FROM bank_statement_matches WHERE business_id=? AND acceptance_id=? UNION SELECT journal_id FROM bank_match_active_ledger_members WHERE business_id=? AND acceptance_id=?',
        [businessId.value, acceptanceId, businessId.value, acceptanceId],
      );
      for (final member in members) {
        requireJournalUnreconciled(
          businessId,
          EntityId.parse(member['journal_id'] as String),
        );
      }
      final history = _database.select(
        'SELECT accepted_at FROM bank_match_history WHERE business_id=? AND acceptance_id=?',
        [businessId.value, acceptanceId],
      );
      if (history.length != 1 ||
          retractedAt.isBefore(
            DateTime.parse(history.single['accepted_at'] as String),
          )) {
        throw StateError(
          'A match correction cannot precede its retained acceptance.',
        );
      }
      _database.execute(
        'INSERT INTO bank_match_retractions(acceptance_id,business_id,actor_id,retracted_at,reason) VALUES(?,?,?,?,?)',
        [
          acceptanceId,
          businessId.value,
          actorId.value,
          retractedAt.toUtc().toIso8601String(),
          reason.trim(),
        ],
      );
      _database.execute(
        'DELETE FROM bank_match_active_ledger_members WHERE business_id=? AND acceptance_id=?',
        [businessId.value, acceptanceId],
      );
      _database.execute(
        'DELETE FROM bank_match_active_members WHERE business_id=? AND acceptance_id=?',
        [businessId.value, acceptanceId],
      );
      _database.execute(
        'DELETE FROM bank_statement_matches WHERE business_id = ? AND acceptance_id = ?',
        [businessId.value, acceptanceId],
      );
    });
  }

  void acceptStatementMatch({
    required EntityId businessId,
    required EntityId statementId,
    required int sourceRow,
    required EntityId journalId,
    required int lineIndex,
    required EntityId actorId,
    required DateTime acceptedAt,
    bool automatic = false,
  }) {
    _ensureOpen();
    _transaction(() {
      final actor = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id = ?',
        [businessId.value],
      );
      if (actor.isEmpty || actor.single['owner_id'] != actorId.value) {
        throw StateError('The current business owner must approve the match.');
      }
      _requireStatementEvidence(businessId, statementId);
      if (isStatementReconciled(businessId, statementId)) {
        throw StateError(
          'Reopen the approved reconciliation before changing its matches.',
        );
      }
      final previous = acceptedStatementMatches(
        businessId,
        statementId,
      )[sourceRow];
      final movementId = '${journalId.value}:$lineIndex';
      if (previous != null) {
        if (previous == movementId) return;
        throw StateError('This statement row already has an accepted match.');
      }
      if (_movementAlreadyMatched(businessId, movementId)) {
        throw StateError('This posted movement is already matched.');
      }
      final rows = _statementMatchSuggestions(
        businessId,
        statementId,
        unrestrictedDates: true,
      );
      final selected = rows.where((row) => row.row.sourceRow == sourceRow);
      if (selected.isEmpty ||
          !selected.single.candidates.any((c) => c.movementId == movementId)) {
        throw StateError(
          'The reviewed match is no longer valid. Reload suggestions.',
        );
      }
      final acceptanceId = EntityId.random().value;
      _database.execute(
        'INSERT INTO bank_match_history(acceptance_id,business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          acceptanceId,
          businessId.value,
          statementId.value,
          sourceRow,
          journalId.value,
          lineIndex,
          automatic ? 'automatic' : actorId.value,
          acceptedAt.toUtc().toIso8601String(),
        ],
      );
      _database.execute(
        'INSERT INTO bank_statement_matches(business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at,acceptance_id) VALUES(?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          statementId.value,
          sourceRow,
          journalId.value,
          lineIndex,
          automatic ? 'automatic' : actorId.value,
          acceptedAt.toUtc().toIso8601String(),
          acceptanceId,
        ],
      );
    });
  }

  /// Records one verified posted movement against several original bank rows.
  /// The legacy acceptance remains the primary row so existing reconciliation
  /// allocations still point to one movement, while member evidence is durable.
  void acceptStatementMatchGroup({
    required EntityId businessId,
    required EntityId statementId,
    required Set<int> sourceRows,
    required EntityId journalId,
    required int lineIndex,
    required EntityId actorId,
    required DateTime acceptedAt,
  }) {
    _ensureOpen();
    _transaction(() {
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      if (owner.isEmpty || owner.single['owner_id'] != actorId.value) {
        throw StateError('The current business owner must approve the match.');
      }
      if (isStatementReconciled(businessId, statementId)) {
        throw StateError(
          'Reopen the approved reconciliation before changing its matches.',
        );
      }
      final occupied = acceptedStatementMatches(businessId, statementId);
      if (sourceRows.any(occupied.containsKey)) {
        throw StateError('A selected statement row is already connected.');
      }
      final movementId = '${journalId.value}:$lineIndex';
      if (_movementAlreadyMatched(businessId, movementId)) {
        throw StateError('This posted movement is already matched.');
      }
      if (!statementGroupMatchSuggestions(
        businessId: businessId,
        statementId: statementId,
        sourceRows: sourceRows,
        includeOlderMovements: true,
      ).any((candidate) => candidate.movementId == movementId)) {
        throw StateError(
          'The selected rows no longer match this posted movement.',
        );
      }
      final ordered = sourceRows.toList()..sort();
      final acceptanceId = EntityId.random().value;
      final at = acceptedAt.toUtc().toIso8601String();
      _database.execute(
        'INSERT INTO bank_match_history(acceptance_id,business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          acceptanceId,
          businessId.value,
          statementId.value,
          ordered.first,
          journalId.value,
          lineIndex,
          actorId.value,
          at,
        ],
      );
      _database.execute(
        'INSERT INTO bank_statement_matches(business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at,acceptance_id) VALUES(?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          statementId.value,
          ordered.first,
          journalId.value,
          lineIndex,
          actorId.value,
          at,
          acceptanceId,
        ],
      );
      for (final sourceRow in ordered.skip(1)) {
        _database.execute(
          'INSERT INTO bank_match_group_members(acceptance_id,business_id,statement_id,source_row) VALUES(?,?,?,?)',
          [acceptanceId, businessId.value, statementId.value, sourceRow],
        );
        _database.execute(
          'INSERT INTO bank_match_active_members(business_id,statement_id,source_row,acceptance_id) VALUES(?,?,?,?)',
          [businessId.value, statementId.value, sourceRow, acceptanceId],
        );
      }
    });
  }

  /// Connects only unambiguous outgoing rows whose external reference appears
  /// in the one exact-amount, nearby posted ledger movement. Incoming receipts,
  /// missing references and repeated candidates stay for human allocation.
  int autoConnectStatementMatches({
    required EntityId businessId,
    required EntityId statementId,
    required EntityId actorId,
    required DateTime connectedAt,
  }) {
    _ensureOpen();
    final import = _database.select(
      'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
      [businessId.value, statementId.value],
    );
    if (import.isEmpty) throw StateError('Statement is unavailable.');
    final paymentId = import.single['payment_account_id'] as String;
    final payment = _database.select(
      'SELECT type FROM payment_accounts WHERE business_id=? AND id=?',
      [businessId.value, paymentId],
    );
    if (payment.isEmpty ||
        payment.single['type'] != 'bank' ||
        paymentLedgerAccount(businessId, paymentId) == null) {
      return 0;
    }
    final accepted = acceptedStatementMatches(businessId, statementId);
    final suggestions = statementMatchSuggestions(businessId, statementId);
    var connected = 0;
    for (final suggestion in suggestions) {
      final row = suggestion.row;
      if (row.amount.minorUnits >= 0 ||
          accepted.containsKey(row.sourceRow) ||
          suggestion.candidates.length != 1) {
        continue;
      }
      final reference = row.reference.toUpperCase().replaceAll(
        RegExp(r'[^A-Z0-9]'),
        '',
      );
      if (reference.length < 5) continue;
      final candidate = suggestion.candidates.single;
      final memo = candidate.memo.toUpperCase().replaceAll(
        RegExp(r'[^A-Z0-9]'),
        '',
      );
      if (!memo.contains(reference)) continue;
      try {
        acceptStatementMatch(
          businessId: businessId,
          statementId: statementId,
          sourceRow: row.sourceRow,
          journalId: candidate.journalId,
          lineIndex: candidate.lineIndex,
          actorId: actorId,
          acceptedAt: connectedAt,
          automatic: true,
        );
        connected++;
      } on StateError {
        // A movement already connected elsewhere remains for manual review.
      }
    }
    return connected;
  }

  EntityId importBankStatement({
    required EntityId id,
    required EntityId businessId,
    required String paymentAccountId,
    required BankStatementImport statement,
    required DateTime importedAt,
  }) {
    _ensureOpen();
    late EntityId result;
    _transaction(() {
      final payment = _database.select(
        'SELECT currency FROM payment_accounts WHERE business_id = ? AND id = ?',
        [businessId.value, paymentAccountId],
      );
      if (payment.isEmpty || payment.single['currency'] != statement.currency) {
        throw StateError(
          'Statement currency and payment account must match this business.',
        );
      }
      final existing = _database.select(
        'SELECT id,source,parsed_rows FROM bank_statement_imports WHERE business_id = ? AND payment_account_id = ? AND digest = ?',
        [businessId.value, paymentAccountId, statement.digest],
      );
      if (existing.isNotEmpty) {
        result = EntityId.parse(existing.single['id'] as String);
        if (bankStatement(businessId, result)?.sourceAvailable != true &&
            statement.sourceAvailable) {
          final retained = existing.single['parsed_rows'] as String?;
          if (retained != null &&
              jsonEncode(jsonDecode(retained)) !=
                  jsonEncode(jsonDecode(statement.parsedRowsJson))) {
            throw StateError(
              'The reconnected statement differs from the retained parsed records. Review the archive and source.',
            );
          }
          _database.execute(
            'INSERT INTO bank_statement_reconnections(business_id,statement_id,source,digest,reconnected_at) VALUES(?,?,?,?,?) ON CONFLICT(business_id,statement_id) DO UPDATE SET source=excluded.source',
            [
              businessId.value,
              result.value,
              statement.sourceBytes,
              statement.digest,
              importedAt.toUtc().toIso8601String(),
            ],
          );
        }
        return;
      }
      _database.execute(
        'INSERT INTO bank_statement_imports(id,business_id,payment_account_id,filename,currency,digest,source,imported_at,parser_version,parsed_rows) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          id.value,
          businessId.value,
          paymentAccountId,
          statement.filename,
          statement.currency,
          statement.digest,
          statement.sourceBytes,
          importedAt.toUtc().toIso8601String(),
          statement.parserVersion,
          statement.parserVersion == 2 ? statement.parsedRowsJson : null,
        ],
      );
      result = id;
    });
    return result;
  }

  List<({EntityId id, String filename})> bankStatements(
    EntityId businessId,
    String paymentAccountId,
  ) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT id,filename FROM bank_statement_imports WHERE business_id = ? AND payment_account_id = ? ORDER BY imported_at DESC,id',
            [businessId.value, paymentAccountId],
          )
          .map(
            (row) => (
              id: EntityId.parse(row['id'] as String),
              filename: row['filename'] as String,
            ),
          ),
    );
  }

  BankStatementImport? bankStatement(EntityId businessId, EntityId id) {
    _ensureOpen();
    return _bankStatementFrom(_database, businessId, id);
  }

  BankStatementImport? _bankStatementFrom(
    Database sourceDatabase,
    EntityId businessId,
    EntityId id,
  ) {
    final rows = sourceDatabase.select(
      'SELECT * FROM bank_statement_imports WHERE business_id = ? AND id = ?',
      [businessId.value, id.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    var source = row['source'] as Uint8List;
    if (source.isEmpty &&
        sourceDatabase
            .select(
              "SELECT 1 FROM sqlite_master WHERE type='table' AND name='bank_statement_reconnections'",
            )
            .isNotEmpty) {
      final reconnected = sourceDatabase.select(
        'SELECT source FROM bank_statement_reconnections WHERE business_id=? AND statement_id=?',
        [businessId.value, id.value],
      );
      if (reconnected.isNotEmpty) {
        source = reconnected.single['source'] as Uint8List;
      }
    }
    if (source.isEmpty && row['parsed_rows'] != null) {
      return BankStatementImport.metadataOnly(
        filename: row['filename'] as String,
        currency: row['currency'] as String,
        digest: row['digest'] as String,
        parserVersion: row['parser_version'] as int,
        parsedRowsJson: row['parsed_rows'] as String,
      );
    }
    if (row['parser_version'] != 1 && row['parser_version'] != 2) {
      throw StateError('Unsupported statement parser version.');
    }
    final statement = row['parser_version'] == 2
        ? BankStatementImport.restorePdf(
            filename: row['filename'] as String,
            currency: row['currency'] as String,
            bytes: source,
            parsedRowsJson: row['parsed_rows'] as String,
          )
        : BankStatementImport.csv(
            filename: row['filename'] as String,
            currency: row['currency'] as String,
            bytes: source,
          );
    if (statement.digest != row['digest']) {
      throw StateError('Statement source integrity check failed.');
    }
    return statement;
  }

  EntityId? paymentLedgerAccount(EntityId businessId, String paymentAccountId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT ledger_account_id FROM payment_ledger_links WHERE business_id = ? AND payment_account_id = ?',
      [businessId.value, paymentAccountId],
    );
    return rows.isEmpty
        ? null
        : EntityId.parse(rows.single['ledger_account_id'] as String);
  }

  /// One physical payment account maps to one dedicated ledger account.
  /// Existing links cannot silently redirect historical reconciliation activity.
  void linkPaymentLedgerAccount(
    EntityId businessId,
    String paymentAccountId,
    EntityId ledgerAccountId,
  ) {
    _ensureOpen();
    _transaction(() {
      final existing = paymentLedgerAccount(businessId, paymentAccountId);
      if (existing != null) {
        if (existing == ledgerAccountId) return;
        throw StateError('This payment account already has a ledger link.');
      }
      final payments = _database.select(
        'SELECT type,currency FROM payment_accounts WHERE business_id = ? AND id = ?',
        [businessId.value, paymentAccountId],
      );
      final accounts = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id = ? AND id = ?',
        [businessId.value, ledgerAccountId.value],
      );
      final policies = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id = ?',
        [businessId.value],
      );
      if (payments.isEmpty || accounts.isEmpty || policies.isEmpty) {
        throw StateError(
          'Payment account and ledger account must belong to this configured business.',
        );
      }
      final payment = payments.single;
      final account = accounts.single;
      if (payment['currency'] != policies.single['currency']) {
        throw StateError(
          'Foreign-currency reconciliation needs an exchange-rate policy before linking.',
        );
      }
      final type = account['type'];
      final expected = payment['type'] == PaymentAccountType.card.name
          ? AccountType.liability.name
          : AccountType.asset.name;
      if (type != expected ||
          account['status'] != AccountStatus.active.name ||
          account['is_parent'] != 0) {
        throw StateError(
          'Choose an active posting account: a liability for cards or an asset for other payment accounts.',
        );
      }
      _database.execute(
        'INSERT INTO payment_ledger_links(business_id,payment_account_id,ledger_account_id) VALUES(?,?,?)',
        [businessId.value, paymentAccountId, ledgerAccountId.value],
      );
    });
  }

  List<PaymentAccount> readPaymentAccounts(EntityId businessId) {
    return _database
        .select(
          'SELECT * FROM payment_accounts WHERE business_id = ? ORDER BY name,id',
          [businessId.value],
        )
        .map(
          (row) => PaymentAccount.create(
            id: row['id'] as String,
            name: row['name'] as String,
            type: PaymentAccountType.values.byName(row['type'] as String),
            currencyCode: row['currency'] as String,
            accountNumber: row['account_number'] as String,
            accountHolderName: row['holder_name'] as String,
            bankId: row['bank_id'] as String?,
            bankName: row['bank_name'] as String?,
          ),
        )
        .toList(growable: false);
  }

  void savePaymentAccount(EntityId businessId, PaymentAccount account) {
    if (account.id.trim().isEmpty) {
      throw ArgumentError('Account identity is required.');
    }
    _transaction(() {
      final imported = _database.select(
        'SELECT currency FROM bank_statement_imports WHERE business_id = ? AND payment_account_id = ? LIMIT 1',
        [businessId.value, account.id],
      );
      if (imported.isNotEmpty &&
          imported.single['currency'] != account.currency.code) {
        throw StateError(
          'An account with imported statements cannot change currency.',
        );
      }
      if (imported.isNotEmpty) {
        final oldType = _database.select(
          'SELECT type FROM payment_accounts WHERE business_id = ? AND id = ?',
          [businessId.value, account.id],
        ).single['type'];
        if (oldType != account.type.name) {
          throw StateError(
            'An account with imported statements cannot change type.',
          );
        }
      }
      final linked = paymentLedgerAccount(businessId, account.id);
      if (linked != null) {
        final original = _database.select(
          'SELECT currency,type FROM payment_accounts WHERE business_id = ? AND id = ?',
          [businessId.value, account.id],
        ).single;
        if (original['currency'] != account.currency.code ||
            original['type'] != account.type.name) {
          throw StateError(
            'A linked payment account cannot change currency or type.',
          );
        }
      }
      final previous = _database.select(
        'SELECT currency FROM payment_accounts WHERE business_id = ? AND id = ?',
        [businessId.value, account.id],
      );
      if (previous.isNotEmpty &&
          previous.single['currency'] != account.currency.code) {
        final references = _database.select(
          'SELECT payload FROM expense_intakes WHERE business_id = ? '
          'UNION ALL SELECT payload FROM payment_vouchers WHERE business_id = ?',
          [businessId.value, businessId.value],
        );
        if (references.any(
          (row) =>
              (jsonDecode(row['payload'] as String)
                  as Map<String, dynamic>)['paymentAccountId'] ==
              account.id,
        )) {
          throw StateError(
            'A referenced payment account cannot change currency. Create a separate account.',
          );
        }
      }
      _database.execute(
        'INSERT INTO payment_accounts(business_id,id,name,type,currency,account_number,bank_id,bank_name,holder_name) VALUES(?,?,?,?,?,?,?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,type=excluded.type,currency=excluded.currency,account_number=excluded.account_number,bank_id=excluded.bank_id,bank_name=excluded.bank_name,holder_name=excluded.holder_name',
        [
          businessId.value,
          account.id,
          account.name,
          account.type.name,
          account.currency.code,
          account.accountNumber,
          account.bankId,
          account.bankName,
          account.accountHolderName,
        ],
      );
    });
  }

  List<Payee> readPayees(EntityId businessId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT id,name,type FROM payees WHERE business_id = ? ORDER BY name,id',
            [businessId.value],
          )
          .map(
            (row) => Payee(
              id: row['id'] as String,
              name: row['name'] as String,
              type: PayeeType.values.byName(row['type'] as String),
            ),
          ),
    );
  }

  void savePayee(EntityId businessId, Payee payee) {
    _ensureOpen();
    if (payee.id.trim().isEmpty || payee.name.trim().isEmpty) {
      throw ArgumentError('Payee identity and name are required.');
    }
    _transaction(() {
      final profile = _database.select(
        'SELECT * FROM vendor_profiles WHERE business_id=? AND payee_id=?',
        [businessId.value, payee.id],
      );
      if (profile.isNotEmpty) {
        final vendor = _vendorFromRow(profile.single);
        if (vendor.name != payee.name || vendor.type != payee.type) {
          throw StateError(
            'Edit this supplier in Vendors to preserve its revision history.',
          );
        }
      }
      _database.execute(
        'INSERT INTO payees(business_id,id,name,type) VALUES(?,?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,type=excluded.type',
        [businessId.value, payee.id, payee.name, payee.type.name],
      );
    });
  }

  StoredJournalPage readJournalPage({
    required EntityId businessId,
    JournalEntryState? state,
    DateTime? through,
    String search = '',
    int offset = 0,
    int limit = 10,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 50) {
      throw ArgumentError(
        'Journal pages require a nonnegative offset and 1–50 rows.',
      );
    }
    final where = StringBuffer('business_id=? AND deleted_at IS NULL');
    final args = <Object?>[businessId.value];
    if (state != null) {
      where.write(' AND state=?');
      args.add(state.name);
    }
    if (through != null) {
      final day = accountingCalendarDate(through);
      where.write(' AND substr(entry_date,1,10)<=?');
      args.add(
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      );
    }
    final term = search.trim();
    if (term.isNotEmpty) {
      final literal = term
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      where.write(r" AND (memo LIKE ? ESCAPE '\' OR id LIKE ? ESCAPE '\')");
      args.addAll(['%$literal%', '%$literal%']);
    }
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select(
                    'SELECT COUNT(*) AS count FROM journal_entries WHERE $where',
                    args,
                  )
                  .single['count']
              as int;
      final start = total == 0
          ? 0
          : offset >= total
          ? ((total - 1) ~/ limit) * limit
          : offset;
      final rows = _database.select(
        'SELECT * FROM journal_entries WHERE $where ORDER BY entry_date DESC,id LIMIT ? OFFSET ?',
        [...args, limit, start],
      );
      final lines = <String, List<JournalLine>>{};
      if (rows.isNotEmpty) {
        final ids = rows.map((row) => row['id'] as String).toList();
        for (final row in _database.select(
          'SELECT * FROM journal_lines WHERE journal_id IN (${List.filled(ids.length, '?').join(',')}) ORDER BY journal_id,line_index',
          ids,
        )) {
          (lines[row['journal_id'] as String] ??= []).add(_lineFromRow(row));
        }
      }
      final page = StoredJournalPage(
        records: rows.map(
          (row) => _journalFromRows(row, lines[row['id']] ?? const []),
        ),
        total: total,
        offset: start,
        limit: limit,
      );
      if (ownsSnapshot) _database.execute('COMMIT');
      return page;
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Global-search suggestions need only these three stored fields. Keep the
  /// scan inside SQLite and never materialize the journal lines or full book.
  List<({String id, String memo, String state})> searchJournalSummaries({
    required EntityId businessId,
    required String query,
    int limit = 12,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Choose 1–50 suggestions.');
    }
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    final base = 'business_id=? AND deleted_at IS NULL';
    final order = ' ORDER BY entry_date DESC,id LIMIT ?';
    if (!words.any((word) => word.runes.any((rune) => rune > 127))) {
      final where = StringBuffer(base);
      final args = <Object?>[businessId.value];
      for (final word in words) {
        if ('journal'.contains(word)) continue;
        final literal = word
            .replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        where.write(
          r" AND (memo LIKE ? ESCAPE '\' OR id LIKE ? ESCAPE '\' OR state LIKE ? ESCAPE '\')",
        );
        args.addAll(['%$literal%', '%$literal%', '%$literal%']);
      }
      return [
        for (final row in _database.select(
          'SELECT id,memo,state FROM journal_entries WHERE $where$order',
          [...args, limit],
        ))
          (
            id: row['id'] as String,
            memo: row['memo'] as String,
            state: row['state'] as String,
          ),
      ];
    }

    // SQLite's LIKE folds ASCII only. For Unicode terms, retain Dart's
    // existing case-insensitive matching while paging summaries by key.
    final results = <({String id, String memo, String state})>[];
    String? lastDate;
    String? lastId;
    while (results.length < limit) {
      final cursor = lastDate == null
          ? ''
          : ' AND (entry_date<? OR (entry_date=? AND id>?))';
      final rows = _database.select(
        'SELECT id,memo,state,entry_date FROM journal_entries '
        'WHERE $base$cursor$order',
        [
          businessId.value,
          if (lastDate != null) ...[lastDate, lastDate, lastId],
          200,
        ],
      );
      for (final row in rows) {
        final id = row['id'] as String;
        final memo = row['memo'] as String;
        final state = row['state'] as String;
        final haystack = '$memo Journal $state $id'.toLowerCase();
        if (words.every(haystack.contains)) {
          results.add((id: id, memo: memo, state: state));
          if (results.length == limit) break;
        }
      }
      if (rows.length < 200) break;
      lastDate = rows.last['entry_date'] as String;
      lastId = rows.last['id'] as String;
    }
    return results;
  }

  Future<List<StoredJournalEntry>> listJournals(EntityId businessId) async {
    _ensureOpen();
    return _readJournalSnapshot(
      businessId,
      includeDeleted: false,
      newestFirst: true,
    );
  }

  Future<WorkspaceIdentity> openWorkspace({
    required EntityId newBusinessId,
    required EntityId newDeviceId,
    required EntityId newOwnerId,
    required String defaultCurrency,
    bool createIfMissing = true,
  }) async {
    _ensureOpen();
    late WorkspaceIdentity identity;
    _transaction(() {
      final existing = _database.select(
        'SELECT * FROM local_workspace WHERE singleton = 1',
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        final policy = _database.select(
          'SELECT currency FROM ledger_policies WHERE business_id = ?',
          [row['business_id']],
        );
        if (policy.length != 1) {
          throw StateError(
            'The saved workspace currency is missing. Recovery is required.',
          );
        }
        identity = WorkspaceIdentity(
          businessId: EntityId.parse(row['business_id'] as String),
          deviceId: EntityId.parse(row['device_id'] as String),
          ownerId: EntityId.parse(row['owner_id'] as String),
          currency: policy.first['currency'] as String,
        );
        return;
      }
      if (!createIfMissing) {
        throw StateError('The saved workspace identity needs recovery.');
      }
      final businesses = _database.select(
        '''SELECT business_id FROM journal_entries
        UNION SELECT business_id FROM accounts UNION SELECT business_id FROM ledger_policies UNION SELECT business_id FROM expense_intakes UNION SELECT business_id FROM payees UNION SELECT business_id FROM payment_accounts UNION SELECT business_id FROM claims UNION SELECT business_id FROM payment_vouchers''',
      );
      if (businesses.length > 1) {
        throw StateError(
          'Multiple existing businesses require explicit workspace selection.',
        );
      }
      final business = businesses.isEmpty
          ? newBusinessId
          : EntityId.parse(businesses.first['business_id'] as String);
      final policy = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id = ?',
        [business.value],
      );
      final currencies = _database.select(
        '''SELECT DISTINCT currency FROM journal_lines
        JOIN journal_entries ON journal_entries.id = journal_lines.journal_id
        WHERE journal_entries.business_id = ?''',
        [business.value],
      );
      if (currencies.length > 1) {
        throw StateError(
          'Existing mixed currencies require a reviewed conversion policy.',
        );
      }
      final currency = policy.isNotEmpty
          ? policy.first['currency'] as String
          : currencies.isNotEmpty
          ? currencies.first['currency'] as String
          : Currency.parse(defaultCurrency).code;
      if (currencies.isNotEmpty && currencies.first['currency'] != currency) {
        throw StateError(
          'Existing journals conflict with the saved currency policy.',
        );
      }
      _database.execute(
        'INSERT OR IGNORE INTO ledger_policies(business_id,currency) VALUES (?,?)',
        [business.value, currency],
      );
      _database.execute(
        'INSERT INTO local_workspace(singleton,business_id,device_id,owner_id) VALUES (1,?,?,?)',
        [business.value, newDeviceId.value, newOwnerId.value],
      );
      identity = WorkspaceIdentity(
        businessId: business,
        deviceId: newDeviceId,
        ownerId: newOwnerId,
        currency: currency,
      );
    });
    return identity;
  }

  Future<LedgerReport> report({
    required EntityId businessId,
    required DateTime from,
    required DateTime through,
  }) async {
    _ensureOpen();
    late LedgerReport result;
    // One snapshot prevents account and journal reads straddling another commit.
    _transaction(() {
      final policy = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id = ?',
        [businessId.value],
      );
      if (policy.isEmpty) {
        throw StateError('Configure the ledger before reporting.');
      }
      final accounts = _database
          .select('SELECT * FROM accounts WHERE business_id = ?', [
            businessId.value,
          ])
          .map(_accountFromRow)
          .toList();
      final journals = _readJournalBatch(businessId);
      result = LedgerReport.build(
        businessId: businessId,
        currency: policy.first['currency'] as String,
        from: from,
        through: through,
        accounts: accounts,
        journals: journals,
      );
    });
    return result;
  }

  @override
  Future<StoredAccount?> getAccount(EntityId id) async {
    _ensureOpen();
    final rows = _database.select('SELECT * FROM accounts WHERE id = ?', [
      id.value,
    ]);
    return rows.isEmpty ? null : _accountFromRow(rows.first);
  }

  @override
  Future<List<StoredAccount>> listAccounts(EntityId businessId) async {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM accounts WHERE business_id = ? ORDER BY code, id',
            [businessId.value],
          )
          .map(_accountFromRow),
    );
  }

  @override
  Future<void> saveAccount(StoredAccount record) async {
    _ensureOpen();
    final account = record.account;
    final metadata = record.metadata;
    if (metadata.recordId != account.id ||
        account.validationErrors.isNotEmpty) {
      throw ArgumentError(
        'Account identity, code, name and hierarchy must be valid.',
      );
    }
    if (metadata.isTombstone) {
      throw StateError(
        'Archive accounts instead of deleting accounting history.',
      );
    }
    if (account.openingBalance != null) {
      throw StateError('Opening balances require a dated balanced journal.');
    }
    _transaction(() {
      final rows = _database.select('SELECT * FROM accounts WHERE id = ?', [
        account.id.value,
      ]);
      if (rows.isEmpty) {
        if (metadata.revision != 1) {
          throw StateError('A new account must begin at revision one.');
        }
      } else {
        final previous = _accountFromRow(rows.first);
        if (previous.account.profile != null && account.profile == null) {
          throw StateError(
            'Retain the saved account profile when updating this account.',
          );
        }
        if (previous.metadata.businessId != metadata.businessId ||
            previous.metadata.originDeviceId != metadata.originDeviceId ||
            previous.metadata.createdAt != metadata.createdAt ||
            previous.account.isSystem != account.isSystem) {
          throw StateError(
            'Account ownership and system identity cannot change.',
          );
        }
        if (metadata.revision != previous.metadata.revision + 1 ||
            !metadata.updatedAt.isAfter(previous.metadata.updatedAt)) {
          throw StateError(
            'Account changed since it was read. Reload before saving.',
          );
        }
        final used = _database.select(
          'SELECT 1 FROM journal_lines WHERE account_id = ? LIMIT 1',
          [account.id.value],
        ).isNotEmpty;
        final linked = _database.select(
          'SELECT 1 FROM payment_ledger_links WHERE ledger_account_id = ? LIMIT 1',
          [account.id.value],
        ).isNotEmpty;
        if ((used || linked) &&
            (account.type != previous.account.type ||
                account.isParent != previous.account.isParent)) {
          throw StateError(
            'An account referenced by journals cannot change type or posting role.',
          );
        }
      }
      final defaultTaxId = account.profile?.defaultTaxCodeId;
      if (defaultTaxId != null) {
        final rates = readTaxRates(metadata.businessId);
        final matching = rates
            .where((rate) => rate.id == defaultTaxId)
            .toList();
        final retained =
            rows.isNotEmpty &&
            _accountFromRow(rows.first).account.profile?.defaultTaxCodeId ==
                defaultTaxId;
        if (matching.length != 1 || !retained && !matching.single.active) {
          throw StateError(
            'Choose an active tax code belonging to this company.',
          );
        }
      }
      if (account.parentId != null) {
        final parents = _database.select(
          'SELECT * FROM accounts WHERE id = ?',
          [account.parentId!.value],
        );
        if (parents.isEmpty) {
          throw StateError('The parent account does not exist.');
        }
        final parent = _accountFromRow(parents.first);
        if (parent.metadata.businessId != metadata.businessId ||
            Account.validateParent(
              child: account,
              parent: parent.account,
            ).isNotEmpty) {
          throw StateError(
            'The parent must be an active parent of the same business and account type.',
          );
        }
        var ancestor = account.parentId;
        final visited = <EntityId>{account.id};
        while (ancestor != null) {
          if (!visited.add(ancestor)) {
            throw StateError('Account hierarchy cannot contain a cycle.');
          }
          final ancestors = _database.select(
            'SELECT parent_id FROM accounts WHERE id = ?',
            [ancestor.value],
          );
          ancestor = ancestors.isEmpty
              ? null
              : _idOrNull(ancestors.first['parent_id']);
        }
      }
      final children = _database.select(
        'SELECT * FROM accounts WHERE parent_id = ?',
        [account.id.value],
      );
      if (children.isNotEmpty &&
          (!account.isParent ||
              account.status != AccountStatus.active ||
              children.any((child) => child['type'] != account.type.name))) {
        throw StateError(
          'Move subaccounts before changing their parent type, role or status.',
        );
      }
      final duplicate = _database.select(
        'SELECT id FROM accounts WHERE business_id = ? AND code = ? COLLATE NOCASE AND id <> ?',
        [metadata.businessId.value, account.code, account.id.value],
      );
      if (duplicate.isNotEmpty) {
        throw StateError('This account code is already used by the business.');
      }
      _database.execute(
        '''INSERT INTO accounts (
        id, business_id, code, name, type, status, is_parent, is_system, parent_id,
        origin_device_id, created_at, updated_at, revision, profile
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET code=excluded.code, name=excluded.name,
        type=excluded.type, status=excluded.status, is_parent=excluded.is_parent,
        parent_id=excluded.parent_id, updated_at=excluded.updated_at, revision=excluded.revision,
        profile=excluded.profile
      ''',
        [
          account.id.value,
          metadata.businessId.value,
          account.code,
          account.name,
          account.type.name,
          account.status.name,
          account.isParent ? 1 : 0,
          account.isSystem ? 1 : 0,
          account.parentId?.value,
          metadata.originDeviceId.value,
          metadata.createdAt.toIso8601String(),
          metadata.updatedAt.toIso8601String(),
          metadata.revision,
          account.profile == null
              ? null
              : jsonEncode(account.profile!.toJson()),
        ],
      );
    });
  }

  StoredAccount _accountFromRow(Row row) => StoredAccount(
    account: Account.create(
      id: EntityId.parse(row['id'] as String),
      code: row['code'] as String,
      name: row['name'] as String,
      type: AccountType.values.byName(row['type'] as String),
      status: AccountStatus.values.byName(row['status'] as String),
      isParent: row['is_parent'] == 1,
      isSystem: row['is_system'] == 1,
      parentId: _idOrNull(row['parent_id']),
      profile: row['profile'] == null
          ? null
          : AccountProfile.fromJson(
              jsonDecode(row['profile'] as String) as Map<String, dynamic>,
            ),
    ),
    metadata: RecordMetadata.restore(
      recordId: EntityId.parse(row['id'] as String),
      businessId: EntityId.parse(row['business_id'] as String),
      originDeviceId: EntityId.parse(row['origin_device_id'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      revision: row['revision'] as int,
      deletedAt: null,
    ),
  );

  void close() {
    if (_closed) {
      return;
    }
    _database.dispose();
    _closed = true;
  }

  void _migrate({int throughVersion = schemaVersion}) {
    _database.execute('PRAGMA foreign_keys = ON');
    final version =
        _database.select('PRAGMA user_version').first['user_version'] as int;
    if (version > throughVersion) {
      throw StateError(
        'Database schema version $version is newer than the app.',
      );
    }
    if (version < 34 && throughVersion >= 34) {
      for (final trigger in [
        'bank_match_reserve_ledger',
        'bank_match_ledger_reserve_primary',
      ]) {
        _database.execute('DROP TRIGGER IF EXISTS $trigger');
      }
      for (final table in [
        'bank_match_active_ledger_members',
        'bank_match_ledger_members',
      ]) {
        if (_database.select(
          'SELECT 1 FROM sqlite_master WHERE type=? AND name=?',
          ['table', table],
        ).isEmpty) {
          continue;
        }
        if (_database.select('SELECT 1 FROM $table LIMIT 1').isNotEmpty) {
          throw StateError('Combined match data requires schema version 34.');
        }
        _database.execute('DROP TABLE $table');
      }
    }
    // A partially restored older snapshot can retain empty v33 tables while
    // its user_version points to an earlier schema. Remove only those empty
    // tables before earlier migrations touch bank_statement_matches.
    if (version < 33 && throughVersion >= 33) {
      for (final table in [
        'bank_match_active_members',
        'bank_match_group_members',
      ]) {
        final exists = _database.select(
          'SELECT 1 FROM sqlite_master WHERE type=? AND name=?',
          ['table', table],
        ).isNotEmpty;
        if (!exists) continue;
        if (_database.select('SELECT 1 FROM $table LIMIT 1').isNotEmpty) {
          throw StateError('Group match data requires schema version 33.');
        }
        _database.execute('DROP TABLE $table');
      }
    }
    if (version == 0) {
      _transaction(() {
        _database.execute('''
          CREATE TABLE journal_entries (
            id TEXT PRIMARY KEY,
            entry_date TEXT NOT NULL,
            memo TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('draft', 'posted', 'voided')),
            reverses_id TEXT,
            business_id TEXT NOT NULL,
            origin_device_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK (revision > 0),
            deleted_at TEXT
          )
        ''');
        _database.execute('''
          CREATE TABLE journal_lines (
            journal_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
            line_index INTEGER NOT NULL CHECK (line_index >= 0),
            account_id TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('debit', 'credit')),
            amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            PRIMARY KEY (journal_id, line_index)
          )
        ''');
        _database.execute('PRAGMA user_version = 1');
      });
    }
    if (version < 2 && throughVersion >= 2) {
      _transaction(() {
        _database.execute('''CREATE TABLE accounts (
          id TEXT PRIMARY KEY, business_id TEXT NOT NULL,
          code TEXT NOT NULL COLLATE NOCASE, name TEXT NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('asset','liability','equity','income','expense')),
          status TEXT NOT NULL CHECK(status IN ('active','locked','archived')),
          is_parent INTEGER NOT NULL CHECK(is_parent IN (0,1)),
          is_system INTEGER NOT NULL CHECK(is_system IN (0,1)),
          parent_id TEXT REFERENCES accounts(id), origin_device_id TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK(revision > 0), UNIQUE(business_id, code)
        )''');
        _database.execute(
          'CREATE INDEX accounts_parent ON accounts(parent_id)',
        );
        _database.execute(
          'CREATE INDEX journal_lines_account ON journal_lines(account_id)',
        );
        _database.execute('PRAGMA user_version = 2');
      });
    }
    if (version < 3 && throughVersion >= 3) {
      _transaction(() {
        _database.execute(
          '''CREATE TABLE ledger_policies (
          business_id TEXT PRIMARY KEY, currency TEXT NOT NULL, closed_through TEXT)''',
        );
        _database.execute('''CREATE TABLE journal_approvals (
          business_id TEXT NOT NULL, request_id TEXT NOT NULL,
          journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id), signature TEXT NOT NULL,
          PRIMARY KEY(business_id,request_id))''');
        _database.execute('''CREATE TABLE ledger_audit (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,
          actor_id TEXT NOT NULL, occurred_at TEXT NOT NULL, kind TEXT NOT NULL,
          subject_id TEXT NOT NULL, detail TEXT NOT NULL)''');
        _database.execute(
          'CREATE INDEX ledger_audit_business ON ledger_audit(business_id,sequence)',
        );
        _database.execute(
          '''CREATE TRIGGER ledger_audit_no_update BEFORE UPDATE ON ledger_audit
          BEGIN SELECT RAISE(ABORT,'Audit events are immutable'); END''',
        );
        _database.execute(
          '''CREATE TRIGGER ledger_audit_no_delete BEFORE DELETE ON ledger_audit
          BEGIN SELECT RAISE(ABORT,'Audit events are immutable'); END''',
        );
        _database.execute('PRAGMA user_version = 3');
      });
    }
    if (version < 4 && throughVersion >= 4) {
      _transaction(() {
        _database.execute('''CREATE TABLE local_workspace (
          singleton INTEGER PRIMARY KEY CHECK(singleton = 1), business_id TEXT NOT NULL,
          device_id TEXT NOT NULL, owner_id TEXT NOT NULL)''');
        _database.execute('PRAGMA user_version = 4');
      });
    }
    if (version < 5 && throughVersion >= 5) {
      _transaction(() {
        _database.execute(
          '''CREATE TABLE expense_intakes (
          id TEXT PRIMARY KEY,business_id TEXT NOT NULL,request_id TEXT NOT NULL,created_at TEXT NOT NULL,
          occurred_on TEXT NOT NULL,amount_minor INTEGER NOT NULL CHECK(amount_minor>0),currency TEXT NOT NULL,
          payee TEXT NOT NULL,category TEXT NOT NULL,payload TEXT NOT NULL,
          journal_id TEXT UNIQUE REFERENCES journal_entries(id),UNIQUE(business_id,request_id))''',
        );
        _database.execute(
          'CREATE INDEX expense_intakes_business_date ON expense_intakes(business_id,occurred_on)',
        );
        _database.execute('PRAGMA user_version = 5');
      });
    }
    if (version < 6 && throughVersion >= 6) {
      _transaction(() {
        _database.execute(
          'ALTER TABLE journal_entries ADD COLUMN closing_equity_id TEXT REFERENCES accounts(id)',
        );
        _database.execute('PRAGMA user_version = 6');
      });
    }
    if (version < 7 && throughVersion >= 7) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE payees (business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,type TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 7');
      });
    }
    if (version < 8 && throughVersion >= 8) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE payment_accounts (business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,type TEXT NOT NULL,currency TEXT NOT NULL,account_number TEXT NOT NULL,bank_id TEXT,bank_name TEXT,PRIMARY KEY(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 8');
      });
    }
    if (version < 9 && throughVersion >= 9) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE claims(business_id TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 9');
      });
    }
    if (version < 10 && throughVersion >= 10) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE payment_vouchers(business_id TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 10');
      });
    }
    if (version < 11 && throughVersion >= 11) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE recurring_expense_templates(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision > 0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 11');
      });
    }
    if (version < 12 && throughVersion >= 12) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE recurring_expense_template_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision > 0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id,revision))',
        );
        _database.execute(
          'INSERT INTO recurring_expense_template_history SELECT business_id,id,revision,payload FROM recurring_expense_templates',
        );
        _database.execute(
          "CREATE TRIGGER recurring_history_no_update BEFORE UPDATE ON recurring_expense_template_history BEGIN SELECT RAISE(ABORT, 'Recurring template history is immutable'); END",
        );
        _database.execute(
          "CREATE TRIGGER recurring_history_no_delete BEFORE DELETE ON recurring_expense_template_history BEGIN SELECT RAISE(ABORT, 'Recurring template history is immutable'); END",
        );
        _database.execute('PRAGMA user_version = 12');
      });
    }
    if (version < 13 && throughVersion >= 13) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE recurring_expense_occurrences(business_id TEXT NOT NULL,identity TEXT NOT NULL,template_id TEXT NOT NULL,template_revision INTEGER NOT NULL,occurs_on TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,identity))',
        );
        _database.execute('PRAGMA user_version = 13');
      });
    }
    if (version < 14 && throughVersion >= 14) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE recurring_expense_conversions(business_id TEXT NOT NULL,identity TEXT NOT NULL,expense_id TEXT NOT NULL,PRIMARY KEY(business_id,identity),UNIQUE(business_id,expense_id),FOREIGN KEY(business_id,identity) REFERENCES recurring_expense_occurrences(business_id,identity),FOREIGN KEY(expense_id) REFERENCES expense_intakes(id))',
        );
        _database.execute(
          "CREATE TRIGGER recurring_conversion_no_update BEFORE UPDATE ON recurring_expense_conversions BEGIN SELECT RAISE(ABORT, 'Recurring conversion is immutable'); END",
        );
        _database.execute(
          "CREATE TRIGGER recurring_conversion_no_delete BEFORE DELETE ON recurring_expense_conversions BEGIN SELECT RAISE(ABORT, 'Recurring conversion is immutable'); END",
        );
        _database.execute('PRAGMA user_version = 14');
      });
    }
    if (version < 15 && throughVersion >= 15) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE payment_ledger_links(business_id TEXT NOT NULL,payment_account_id TEXT NOT NULL,ledger_account_id TEXT NOT NULL UNIQUE,PRIMARY KEY(business_id,payment_account_id),FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id),FOREIGN KEY(ledger_account_id) REFERENCES accounts(id))',
        );
        _database.execute(
          "CREATE TRIGGER payment_ledger_no_update BEFORE UPDATE ON payment_ledger_links BEGIN SELECT RAISE(ABORT, 'Payment ledger link is immutable'); END",
        );
        _database.execute(
          "CREATE TRIGGER payment_ledger_no_delete BEFORE DELETE ON payment_ledger_links BEGIN SELECT RAISE(ABORT, 'Payment ledger link is immutable'); END",
        );
        _database.execute('PRAGMA user_version = 15');
      });
    }
    if (version < 16 && throughVersion >= 16) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_statement_imports(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,payment_account_id TEXT NOT NULL,filename TEXT NOT NULL,currency TEXT NOT NULL,digest TEXT NOT NULL,source BLOB NOT NULL,imported_at TEXT NOT NULL,parser_version INTEGER NOT NULL,UNIQUE(business_id,payment_account_id,digest),FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        _database.execute(
          "CREATE TRIGGER bank_statement_no_update BEFORE UPDATE ON bank_statement_imports BEGIN SELECT RAISE(ABORT, 'Statement originals are immutable'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_statement_no_delete BEFORE DELETE ON bank_statement_imports BEGIN SELECT RAISE(ABORT, 'Statement originals are immutable'); END",
        );
        _database.execute('PRAGMA user_version = 16');
      });
    }
    if (version < 17 && throughVersion >= 17) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_statement_matches(business_id TEXT NOT NULL,statement_id TEXT NOT NULL,source_row INTEGER NOT NULL,journal_id TEXT NOT NULL,line_index INTEGER NOT NULL,actor_id TEXT NOT NULL,accepted_at TEXT NOT NULL,PRIMARY KEY(statement_id,source_row),UNIQUE(business_id,journal_id,line_index),FOREIGN KEY(statement_id) REFERENCES bank_statement_imports(id),FOREIGN KEY(journal_id,line_index) REFERENCES journal_lines(journal_id,line_index))',
        );
        _database.execute(
          "CREATE TRIGGER bank_match_no_update BEFORE UPDATE ON bank_statement_matches BEGIN SELECT RAISE(ABORT, 'Accepted matches are immutable'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_no_delete BEFORE DELETE ON bank_statement_matches BEGIN SELECT RAISE(ABORT, 'Accepted matches are immutable'); END",
        );
        _database.execute('PRAGMA user_version = 17');
      });
    }
    if (version < 18 && throughVersion >= 18) {
      _transaction(() {
        _database.execute('DROP TRIGGER bank_match_no_update');
        _database.execute('DROP TRIGGER bank_match_no_delete');
        _database.execute(
          'ALTER TABLE bank_statement_matches ADD COLUMN acceptance_id TEXT',
        );
        _database.execute(
          "UPDATE bank_statement_matches SET acceptance_id = statement_id || ':' || source_row",
        );
        _database.execute(
          'CREATE UNIQUE INDEX bank_match_acceptance_id ON bank_statement_matches(acceptance_id)',
        );
        _database.execute(
          'CREATE TABLE bank_match_history(acceptance_id TEXT PRIMARY KEY,business_id TEXT NOT NULL,statement_id TEXT NOT NULL,source_row INTEGER NOT NULL,journal_id TEXT NOT NULL,line_index INTEGER NOT NULL,actor_id TEXT NOT NULL,accepted_at TEXT NOT NULL)',
        );
        _database.execute(
          'INSERT INTO bank_match_history SELECT acceptance_id,business_id,statement_id,source_row,journal_id,line_index,actor_id,accepted_at FROM bank_statement_matches',
        );
        _database.execute(
          'CREATE TABLE bank_match_retractions(acceptance_id TEXT PRIMARY KEY REFERENCES bank_match_history(acceptance_id),business_id TEXT NOT NULL,actor_id TEXT NOT NULL,retracted_at TEXT NOT NULL,reason TEXT NOT NULL)',
        );
        for (final table in ['bank_match_history', 'bank_match_retractions']) {
          _database.execute(
            "CREATE TRIGGER ${table}_no_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT, 'Match history is immutable'); END",
          );
          _database.execute(
            "CREATE TRIGGER ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT, 'Match history is immutable'); END",
          );
        }
        _database.execute(
          "CREATE TRIGGER bank_match_no_update BEFORE UPDATE ON bank_statement_matches BEGIN SELECT RAISE(ABORT, 'Active matches cannot be rewritten'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_no_delete BEFORE DELETE ON bank_statement_matches WHEN NOT EXISTS(SELECT 1 FROM bank_match_retractions WHERE acceptance_id=OLD.acceptance_id AND business_id=OLD.business_id) BEGIN SELECT RAISE(ABORT, 'Record a correction before removing an active match'); END",
        );
        _database.execute('PRAGMA user_version = 18');
      });
    }
    if (version < 19 && throughVersion >= 19) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_reconciliations(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,payment_account_id TEXT NOT NULL,statement_id TEXT NOT NULL REFERENCES bank_statement_imports(id),starts_on TEXT NOT NULL,ends_on TEXT NOT NULL,opening_minor INTEGER NOT NULL,closing_minor INTEGER NOT NULL,currency TEXT NOT NULL,actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,previous_id TEXT REFERENCES bank_reconciliations(id),opening_evidence TEXT NOT NULL,payload TEXT NOT NULL,FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE bank_reconciliation_allocations(completion_id TEXT NOT NULL REFERENCES bank_reconciliations(id),acceptance_id TEXT NOT NULL REFERENCES bank_match_history(acceptance_id),PRIMARY KEY(completion_id,acceptance_id))',
        );
        _database.execute(
          'CREATE TABLE bank_reconciliation_reopenings(completion_id TEXT PRIMARY KEY REFERENCES bank_reconciliations(id),actor_id TEXT NOT NULL,reopened_at TEXT NOT NULL,reason TEXT NOT NULL)',
        );
        for (final table in [
          'bank_reconciliations',
          'bank_reconciliation_allocations',
          'bank_reconciliation_reopenings',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT, 'Reconciliation history is immutable'); END",
            );
          }
        }
        _database.execute(
          "CREATE TRIGGER reconciled_match_no_retraction BEFORE INSERT ON bank_match_retractions WHEN EXISTS(SELECT 1 FROM bank_reconciliation_allocations a WHERE a.acceptance_id=NEW.acceptance_id AND NOT EXISTS(SELECT 1 FROM bank_reconciliation_reopenings r WHERE r.completion_id=a.completion_id)) BEGIN SELECT RAISE(ABORT, 'Reopen reconciliation before correcting its matches'); END",
        );
        _database.execute(
          'CREATE INDEX bank_reconciliation_account ON bank_reconciliations(business_id,payment_account_id,ends_on)',
        );
        _database.execute('PRAGMA user_version = 19');
      });
    }
    if (version < 20 && throughVersion >= 20) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_reconciliation_ledger_snapshots(completion_id TEXT PRIMARY KEY REFERENCES bank_reconciliations(id),payload TEXT NOT NULL)',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER bank_reconciliation_ledger_no_${operation.toLowerCase()} BEFORE $operation ON bank_reconciliation_ledger_snapshots BEGIN SELECT RAISE(ABORT, 'Approved ledger snapshot is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 20');
      });
    }
    if (version < 21 && throughVersion >= 21) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE customers(business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE customer_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id,revision))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER customer_history_no_${operation.toLowerCase()} BEFORE $operation ON customer_history BEGIN SELECT RAISE(ABORT, 'Customer history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 21');
      });
    }
    if (version < 22 && throughVersion >= 22) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE invoice_drafts(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE invoice_draft_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id,revision))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER invoice_draft_history_no_${operation.toLowerCase()} BEFORE $operation ON invoice_draft_history BEGIN SELECT RAISE(ABORT, 'Invoice draft history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 22');
      });
    }
    if (version < 23 && throughVersion >= 23) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE invoice_postings(business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),document_number TEXT NOT NULL,revision INTEGER NOT NULL,customer_payload TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,invoice_id),UNIQUE(business_id,request_id),UNIQUE(business_id,document_number),FOREIGN KEY(business_id,invoice_id) REFERENCES invoice_drafts(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER invoice_postings_no_${operation.toLowerCase()} BEFORE $operation ON invoice_postings BEGIN SELECT RAISE(ABORT, 'Invoice posting history is immutable'); END",
          );
          _database.execute(
            "CREATE TRIGGER posted_invoice_no_${operation.toLowerCase()} BEFORE $operation ON invoice_drafts WHEN EXISTS(SELECT 1 FROM invoice_postings p WHERE p.business_id=OLD.business_id AND p.invoice_id=OLD.id) BEGIN SELECT RAISE(ABORT, 'Posted invoices are immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 23');
      });
    }
    if (version < 24 && throughVersion >= 24) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE claim_postings(business_id TEXT NOT NULL,claim_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),liability_account_id TEXT NOT NULL REFERENCES accounts(id),claim_payload TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,claim_id),UNIQUE(business_id,request_id),FOREIGN KEY(business_id,claim_id) REFERENCES claims(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER claim_postings_no_${operation.toLowerCase()} BEFORE $operation ON claim_postings BEGIN SELECT RAISE(ABORT, 'Claim recognition is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 24');
      });
    }
    if (version < 25 && throughVersion >= 25) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE claim_settlements(business_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),reference TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,request_id))',
        );
        _database.execute(
          'CREATE TABLE claim_settlement_allocations(business_id TEXT NOT NULL,request_id TEXT NOT NULL,claim_id TEXT NOT NULL,amount_minor INTEGER NOT NULL CHECK(amount_minor>0),currency TEXT NOT NULL,paid_payload TEXT NOT NULL,PRIMARY KEY(business_id,claim_id),FOREIGN KEY(business_id,request_id) REFERENCES claim_settlements(business_id,request_id),FOREIGN KEY(business_id,claim_id) REFERENCES claim_postings(business_id,claim_id))',
        );
        for (final table in [
          'claim_settlements',
          'claim_settlement_allocations',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT, 'Claim settlement is immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 25');
      });
    }
    if (version < 26 && throughVersion >= 26) {
      _transaction(() {
        _database.execute(
          'ALTER TABLE invoice_drafts ADD COLUMN archived_at TEXT',
        );
        _database.execute('PRAGMA user_version = 26');
      });
    }
    if (version < 27 && throughVersion >= 27) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE document_numbers(business_id TEXT NOT NULL,document_type TEXT NOT NULL,record_id TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),number TEXT NOT NULL,allocated_at TEXT NOT NULL,actor_id TEXT NOT NULL,PRIMARY KEY(business_id,document_type,record_id),UNIQUE(business_id,document_type,sequence),UNIQUE(business_id,document_type,number))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER document_numbers_no_${operation.toLowerCase()} BEFORE $operation ON document_numbers BEGIN SELECT RAISE(ABORT, 'Document numbers are retained'); END",
          );
        }
        _database.execute('PRAGMA user_version = 27');
      });
    }
    if (version < 28 && throughVersion >= 28) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE customer_receipts(business_id TEXT NOT NULL,request_id TEXT NOT NULL,customer_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),reference TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,request_id))',
        );
        _database.execute(
          'CREATE TABLE customer_receipt_allocations(business_id TEXT NOT NULL,request_id TEXT NOT NULL,invoice_id TEXT NOT NULL,amount_minor INTEGER NOT NULL CHECK(amount_minor>0),currency TEXT NOT NULL,PRIMARY KEY(business_id,request_id,invoice_id),FOREIGN KEY(business_id,request_id) REFERENCES customer_receipts(business_id,request_id),FOREIGN KEY(business_id,invoice_id) REFERENCES invoice_postings(business_id,invoice_id))',
        );
        for (final table in [
          'customer_receipts',
          'customer_receipt_allocations',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT, 'Customer receipt history is immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 28');
      });
    }
    if (version < 29 && throughVersion >= 29) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE invoice_credit_drafts(business_id TEXT NOT NULL,id TEXT NOT NULL,invoice_id TEXT NOT NULL,payload TEXT NOT NULL,revision INTEGER NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id),FOREIGN KEY(business_id,invoice_id) REFERENCES invoice_postings(business_id,invoice_id))',
        );
        _database.execute(
          'CREATE TABLE invoice_credit_draft_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER credit_history_no_${operation.toLowerCase()} BEFORE $operation ON invoice_credit_draft_history BEGIN SELECT RAISE(ABORT,'Credit draft history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 29');
      });
    }
    if (version < 30 && throughVersion >= 30) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE invoice_credit_postings(business_id TEXT NOT NULL,draft_id TEXT NOT NULL,invoice_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),revision INTEGER NOT NULL,signature TEXT NOT NULL,receivable_minor INTEGER NOT NULL CHECK(receivable_minor>=0),customer_credit_minor INTEGER NOT NULL CHECK(customer_credit_minor>=0),currency TEXT NOT NULL,PRIMARY KEY(business_id,draft_id),UNIQUE(business_id,request_id),FOREIGN KEY(business_id,draft_id) REFERENCES invoice_credit_drafts(business_id,id),FOREIGN KEY(business_id,invoice_id) REFERENCES invoice_postings(business_id,invoice_id))',
        );
        _database.execute(
          'CREATE TABLE invoice_credit_lines(business_id TEXT NOT NULL,draft_id TEXT NOT NULL,line_id TEXT NOT NULL,gross_minor INTEGER NOT NULL CHECK(gross_minor>0),net_minor INTEGER NOT NULL CHECK(net_minor>=0),tax_minor INTEGER NOT NULL CHECK(tax_minor>=0),currency TEXT NOT NULL,CHECK(gross_minor=net_minor+tax_minor),PRIMARY KEY(business_id,draft_id,line_id),FOREIGN KEY(business_id,draft_id) REFERENCES invoice_credit_postings(business_id,draft_id))',
        );
        for (final table in [
          'invoice_credit_postings',
          'invoice_credit_lines',
        ]) {
          _database.execute(
            "CREATE TRIGGER ${table}_no_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Posted credits are immutable'); END",
          );
          _database.execute(
            "CREATE TRIGGER ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Posted credits are immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 30');
      });
    }
    if (version < 31 && throughVersion >= 31) {
      _transaction(() {
        if (!_database
            .select('PRAGMA table_info(bank_statement_imports)')
            .any((row) => row['name'] == 'parsed_rows')) {
          _database.execute(
            'ALTER TABLE bank_statement_imports ADD COLUMN parsed_rows TEXT',
          );
        }
        _database.execute('PRAGMA user_version = 31');
      });
    }
    if (version < 32 && throughVersion >= 32) {
      _transaction(() {
        if (!_database
            .select('PRAGMA table_info(payment_accounts)')
            .any((row) => row['name'] == 'holder_name')) {
          _database.execute(
            "ALTER TABLE payment_accounts ADD COLUMN holder_name TEXT NOT NULL DEFAULT ''",
          );
        }
        _database.execute('PRAGMA user_version = 32');
      });
    }
    if (version < 33 && throughVersion >= 33) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_match_group_members(acceptance_id TEXT NOT NULL REFERENCES bank_match_history(acceptance_id),business_id TEXT NOT NULL,statement_id TEXT NOT NULL,source_row INTEGER NOT NULL,PRIMARY KEY(acceptance_id,source_row))',
        );
        _database.execute(
          'CREATE TABLE bank_match_active_members(business_id TEXT NOT NULL,statement_id TEXT NOT NULL,source_row INTEGER NOT NULL,acceptance_id TEXT NOT NULL REFERENCES bank_statement_matches(acceptance_id),PRIMARY KEY(statement_id,source_row))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER bank_match_group_members_no_${operation.toLowerCase()} BEFORE $operation ON bank_match_group_members BEGIN SELECT RAISE(ABORT,'Group match history is immutable'); END",
          );
        }
        _database.execute(
          "CREATE TRIGGER bank_match_active_members_no_update BEFORE UPDATE ON bank_match_active_members BEGIN SELECT RAISE(ABORT,'Active group members cannot be rewritten'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_active_members_no_delete BEFORE DELETE ON bank_match_active_members WHEN NOT EXISTS(SELECT 1 FROM bank_match_retractions WHERE acceptance_id=OLD.acceptance_id AND business_id=OLD.business_id) BEGIN SELECT RAISE(ABORT,'Record a correction before removing a group member'); END",
        );
        _database.execute('PRAGMA user_version = 33');
      });
    }
    if (version < 34 && throughVersion >= 34) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_match_ledger_members(acceptance_id TEXT NOT NULL REFERENCES bank_match_history(acceptance_id),business_id TEXT NOT NULL,journal_id TEXT NOT NULL,line_index INTEGER NOT NULL,PRIMARY KEY(acceptance_id,journal_id,line_index),FOREIGN KEY(journal_id,line_index) REFERENCES journal_lines(journal_id,line_index))',
        );
        _database.execute(
          'CREATE TABLE bank_match_active_ledger_members(acceptance_id TEXT NOT NULL REFERENCES bank_statement_matches(acceptance_id),business_id TEXT NOT NULL,journal_id TEXT NOT NULL,line_index INTEGER NOT NULL,PRIMARY KEY(business_id,journal_id,line_index),FOREIGN KEY(journal_id,line_index) REFERENCES journal_lines(journal_id,line_index))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER bank_match_ledger_members_no_${operation.toLowerCase()} BEFORE $operation ON bank_match_ledger_members BEGIN SELECT RAISE(ABORT,'Combined match history is immutable'); END",
          );
        }
        _database.execute(
          "CREATE TRIGGER bank_match_active_ledger_no_update BEFORE UPDATE ON bank_match_active_ledger_members BEGIN SELECT RAISE(ABORT,'Active combined matches cannot be rewritten'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_active_ledger_no_delete BEFORE DELETE ON bank_match_active_ledger_members WHEN NOT EXISTS(SELECT 1 FROM bank_match_retractions WHERE acceptance_id=OLD.acceptance_id AND business_id=OLD.business_id) BEGIN SELECT RAISE(ABORT,'Record a correction before removing combined matches'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_reserve_ledger BEFORE INSERT ON bank_statement_matches WHEN EXISTS(SELECT 1 FROM bank_match_active_ledger_members m WHERE m.business_id=NEW.business_id AND m.journal_id=NEW.journal_id AND m.line_index=NEW.line_index AND m.acceptance_id<>NEW.acceptance_id) BEGIN SELECT RAISE(ABORT,'Posted movement is already matched'); END",
        );
        _database.execute(
          "CREATE TRIGGER bank_match_ledger_reserve_primary BEFORE INSERT ON bank_match_active_ledger_members WHEN EXISTS(SELECT 1 FROM bank_statement_matches b WHERE b.business_id=NEW.business_id AND b.journal_id=NEW.journal_id AND b.line_index=NEW.line_index AND b.acceptance_id<>NEW.acceptance_id) BEGIN SELECT RAISE(ABORT,'Posted movement is already matched'); END",
        );
        _database.execute('PRAGMA user_version = 34');
      });
    }
    if (version < 35 && throughVersion >= 35) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS company_preferences(business_id TEXT PRIMARY KEY,payload TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0))',
        );
        _database.execute('PRAGMA user_version = 35');
      });
    }
    if (version < 36 && throughVersion >= 36) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS workspace_reminders(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,payload TEXT NOT NULL,due_date TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0))',
        );
        _database.execute(
          'CREATE INDEX IF NOT EXISTS workspace_reminders_company_date ON workspace_reminders(business_id,due_date)',
        );
        _database.execute('PRAGMA user_version = 36');
      });
    }
    if (version < 37 && throughVersion >= 37) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bank_statement_reconnections(business_id TEXT NOT NULL,statement_id TEXT NOT NULL REFERENCES bank_statement_imports(id),source BLOB NOT NULL,digest TEXT NOT NULL,reconnected_at TEXT NOT NULL,PRIMARY KEY(business_id,statement_id))',
        );
        _database.execute(
          "CREATE TRIGGER IF NOT EXISTS bank_reconnection_no_delete BEFORE DELETE ON bank_statement_reconnections BEGIN SELECT RAISE(ABORT,'Reconnected statement evidence is retained'); END",
        );
        _database.execute(
          "CREATE TRIGGER IF NOT EXISTS bank_reconnection_fill_once BEFORE UPDATE ON bank_statement_reconnections WHEN length(OLD.source)>0 OR length(NEW.source)=0 OR NEW.business_id<>OLD.business_id OR NEW.statement_id<>OLD.statement_id OR NEW.digest<>OLD.digest OR NEW.reconnected_at<>OLD.reconnected_at BEGIN SELECT RAISE(ABORT,'Reconnected statement evidence is immutable'); END",
        );
        _database.execute('PRAGMA user_version = 37');
      });
    }
    if (version < 38 && throughVersion >= 38) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS claim_posting_cycles(business_id TEXT NOT NULL,claim_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),liability_account_id TEXT NOT NULL REFERENCES accounts(id),claim_payload TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,request_id),FOREIGN KEY(business_id,claim_id) REFERENCES claim_postings(business_id,claim_id))',
        );
        _database.execute(
          "CREATE TABLE IF NOT EXISTS claim_posting_reversals(business_id TEXT NOT NULL,claim_id TEXT NOT NULL,request_id TEXT NOT NULL,source_journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),decision TEXT NOT NULL CHECK(decision IN ('returnForCorrection','voidClaim')),reversed_on TEXT NOT NULL,reason TEXT NOT NULL,reviewed_payload TEXT NOT NULL,result_payload TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,request_id),FOREIGN KEY(business_id,claim_id) REFERENCES claim_postings(business_id,claim_id))",
        );
        _database.execute(
          'CREATE VIEW IF NOT EXISTS all_claim_postings AS SELECT * FROM claim_postings UNION ALL SELECT * FROM claim_posting_cycles',
        );
        for (final table in [
          'claim_posting_cycles',
          'claim_posting_reversals',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER IF NOT EXISTS ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Claim correction history is immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 38');
      });
    }
    if (version < 39 && throughVersion >= 39) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS quotation_drafts(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),document_number TEXT NOT NULL,payload TEXT NOT NULL,customer_payload TEXT NOT NULL,saved_at TEXT NOT NULL,converted_invoice_id TEXT,conversion_signature TEXT,PRIMARY KEY(business_id,id),UNIQUE(business_id,document_number),UNIQUE(business_id,converted_invoice_id),FOREIGN KEY(business_id,converted_invoice_id) REFERENCES invoice_drafts(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS quotation_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,customer_payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES quotation_drafts(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS quotation_history_no_${operation.toLowerCase()} BEFORE $operation ON quotation_history BEGIN SELECT RAISE(ABORT,'Quotation history is immutable'); END",
          );
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS converted_quotation_no_${operation.toLowerCase()} BEFORE $operation ON quotation_drafts WHEN OLD.converted_invoice_id IS NOT NULL BEGIN SELECT RAISE(ABORT,'Converted quotations are immutable'); END",
          );
        }
        _database.execute(
          'CREATE INDEX IF NOT EXISTS quotation_drafts_company_saved ON quotation_drafts(business_id,saved_at DESC,id)',
        );
        _database.execute('PRAGMA user_version = 39');
      });
    }
    if (version < 40 && throughVersion >= 40) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS vendor_profiles(business_id TEXT NOT NULL,id TEXT NOT NULL,payee_id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,updated_at TEXT NOT NULL,email TEXT NOT NULL,telephone TEXT NOT NULL,PRIMARY KEY(business_id,id),UNIQUE(business_id,payee_id),FOREIGN KEY(business_id,payee_id) REFERENCES payees(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS vendor_history(business_id TEXT NOT NULL,id TEXT NOT NULL,payee_id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,updated_at TEXT NOT NULL,email TEXT NOT NULL,telephone TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES vendor_profiles(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS vendor_history_no_${operation.toLowerCase()} BEFORE $operation ON vendor_history BEGIN SELECT RAISE(ABORT,'Vendor history is immutable'); END",
          );
        }
        _database.execute(
          'CREATE INDEX IF NOT EXISTS payees_company_directory ON payees(business_id,type,name,id)',
        );
        _database.execute('PRAGMA user_version = 40');
      });
    }
    if (version < 41 && throughVersion >= 41) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_drafts(business_id TEXT NOT NULL,id TEXT NOT NULL,vendor_id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),document_number TEXT NOT NULL,search_text TEXT NOT NULL,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(business_id,id),UNIQUE(business_id,document_number),FOREIGN KEY(business_id,vendor_id) REFERENCES vendor_profiles(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_draft_history(business_id TEXT NOT NULL,id TEXT NOT NULL,vendor_id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),document_number TEXT NOT NULL,search_text TEXT NOT NULL,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES bill_drafts(business_id,id),FOREIGN KEY(business_id,vendor_id) REFERENCES vendor_profiles(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS bill_draft_history_no_${operation.toLowerCase()} BEFORE $operation ON bill_draft_history BEGIN SELECT RAISE(ABORT,'Bill draft history is immutable'); END",
          );
        }
        _database.execute(
          'CREATE INDEX IF NOT EXISTS bill_drafts_company_updated ON bill_drafts(business_id,updated_at DESC,id)',
        );
        _database.execute(
          "CREATE INDEX IF NOT EXISTS bill_audit_company_kind_subject ON ledger_audit(business_id,kind,subject_id) WHERE kind='bill.draft_saved' OR kind='bill.posted'",
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_postings(business_id TEXT NOT NULL,bill_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),revision INTEGER NOT NULL,payable_account_id TEXT NOT NULL REFERENCES accounts(id),actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,bill_id),UNIQUE(business_id,request_id),FOREIGN KEY(business_id,bill_id) REFERENCES bill_drafts(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS bill_postings_no_${operation.toLowerCase()} BEFORE $operation ON bill_postings BEGIN SELECT RAISE(ABORT,'Bill postings are immutable'); END",
          );
          _database.execute(
            "CREATE TRIGGER IF NOT EXISTS posted_bill_no_${operation.toLowerCase()} BEFORE $operation ON bill_drafts WHEN EXISTS(SELECT 1 FROM bill_postings p WHERE p.business_id=OLD.business_id AND p.bill_id=OLD.id) BEGIN SELECT RAISE(ABORT,'Posted bills are immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 41');
      });
    }
    if (version < 42 && throughVersion >= 42) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_settlements(business_id TEXT NOT NULL,request_id TEXT NOT NULL,journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),payment_account_id TEXT NOT NULL,bank_account_id TEXT NOT NULL REFERENCES accounts(id),reference TEXT NOT NULL,currency TEXT NOT NULL,paid_on TEXT NOT NULL,actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,request_id),FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_settlement_allocations(business_id TEXT NOT NULL,request_id TEXT NOT NULL,bill_id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),expected_remaining_minor INTEGER NOT NULL CHECK(expected_remaining_minor>0),amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=expected_remaining_minor),currency TEXT NOT NULL,PRIMARY KEY(business_id,request_id,bill_id),FOREIGN KEY(business_id,request_id) REFERENCES bill_settlements(business_id,request_id),FOREIGN KEY(business_id,bill_id) REFERENCES bill_postings(business_id,bill_id))',
        );
        _database.execute(
          'CREATE INDEX IF NOT EXISTS bill_settlement_balance ON bill_settlement_allocations(business_id,bill_id,expected_remaining_minor DESC)',
        );
        _database.execute(
          'CREATE INDEX IF NOT EXISTS bill_settlement_dates ON bill_settlements(business_id,paid_on,request_id)',
        );
        _database.execute(
          "CREATE INDEX IF NOT EXISTS bill_settlement_audit ON ledger_audit(business_id,kind,subject_id) WHERE kind='bill.settled'",
        );
        for (final table in [
          'bill_settlements',
          'bill_settlement_allocations',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER IF NOT EXISTS ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Bill settlements are immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 42');
      });
    }
    if (version < 43 && throughVersion >= 43) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_posting_reversals(business_id TEXT NOT NULL,bill_id TEXT NOT NULL,request_id TEXT NOT NULL,source_journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),revision INTEGER NOT NULL CHECK(revision>0),reversed_on TEXT NOT NULL,reason TEXT NOT NULL,actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,bill_id),UNIQUE(business_id,request_id),FOREIGN KEY(business_id,bill_id) REFERENCES bill_postings(business_id,bill_id))',
        );
        _database.execute(
          'CREATE TABLE IF NOT EXISTS bill_settlement_reversals(business_id TEXT NOT NULL,source_request_id TEXT NOT NULL,request_id TEXT NOT NULL,source_journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),journal_id TEXT NOT NULL UNIQUE REFERENCES journal_entries(id),reversed_on TEXT NOT NULL,reason TEXT NOT NULL,actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(business_id,source_request_id),UNIQUE(business_id,request_id),FOREIGN KEY(business_id,source_request_id) REFERENCES bill_settlements(business_id,request_id))',
        );
        for (final table in [
          'bill_posting_reversals',
          'bill_settlement_reversals',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER IF NOT EXISTS ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Bill reversals are immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 43');
      });
    }
    if (version < 44 && throughVersion >= 44) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE catalogue_categories(business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,normalized_name TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),PRIMARY KEY(business_id,id),UNIQUE(business_id,normalized_name))',
        );
        _database.execute(
          'CREATE TABLE catalogue_items(business_id TEXT NOT NULL,id TEXT NOT NULL,category_id TEXT NOT NULL,income_account_id TEXT NOT NULL,name TEXT NOT NULL,normalized_name TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id),UNIQUE(business_id,normalized_name),FOREIGN KEY(business_id,category_id) REFERENCES catalogue_categories(business_id,id),FOREIGN KEY(income_account_id) REFERENCES accounts(id))',
        );
        _database.execute('PRAGMA user_version = 44');
      });
    }
    if (version < 45 && throughVersion >= 45) {
      _transaction(() {
        _database.execute(
          "CREATE TABLE generated_document_deliveries(business_id TEXT NOT NULL,record_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('invoice','quotation')),revision INTEGER NOT NULL CHECK(revision>0),attachment_id TEXT NOT NULL,sha256 TEXT NOT NULL,filename TEXT NOT NULL,document_date TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('pending','filed','failed')),attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts>=0),failure TEXT,PRIMARY KEY(business_id,kind,record_id,revision))",
        );
        _database.execute(
          'CREATE INDEX generated_document_pending ON generated_document_deliveries(business_id,status,kind,record_id,revision)',
        );
        _database.execute('PRAGMA user_version = 45');
      });
    }
    if (version < 46 && throughVersion >= 46) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE company_tax_rates(business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,normalized_name TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id),UNIQUE(business_id,normalized_name))',
        );
        _database.execute(
          'CREATE TABLE company_tax_rate_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES company_tax_rates(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER tax_history_no_${operation.toLowerCase()} BEFORE $operation ON company_tax_rate_history BEGIN SELECT RAISE(ABORT,'Tax rate history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 46');
      });
    }
    if (version < 47 && throughVersion >= 47) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE recurring_document_templates(business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute(
          'CREATE TABLE recurring_document_template_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES recurring_document_templates(business_id,id))',
        );
        _database.execute(
          "CREATE TABLE recurring_document_occurrences(business_id TEXT NOT NULL,template_id TEXT NOT NULL,template_revision INTEGER NOT NULL,occurs_on TEXT NOT NULL,occurrence_index INTEGER NOT NULL CHECK(occurrence_index>=0),draft_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('invoice','bill')),PRIMARY KEY(business_id,template_id,occurs_on),UNIQUE(business_id,kind,draft_id),FOREIGN KEY(business_id,template_id,template_revision) REFERENCES recurring_document_template_history(business_id,id,revision))",
        );
        for (final table in [
          'recurring_document_template_history',
          'recurring_document_occurrences',
        ]) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Recurring document history is immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 47');
      });
    }
    if (version < 48 && throughVersion >= 48) {
      _transaction(() {
        // Extend the existing occurrence owner without losing its immutable
        // invoice/bill history or weakening its uniqueness constraints.
        _database.execute(
          'ALTER TABLE recurring_document_occurrences RENAME TO recurring_document_occurrences_v47',
        );
        _database.execute(
          "CREATE TABLE recurring_document_occurrences(business_id TEXT NOT NULL,template_id TEXT NOT NULL,template_revision INTEGER NOT NULL,occurs_on TEXT NOT NULL,occurrence_index INTEGER NOT NULL CHECK(occurrence_index>=0),draft_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('invoice','bill','quotation')),PRIMARY KEY(business_id,template_id,occurs_on),UNIQUE(business_id,kind,draft_id),FOREIGN KEY(business_id,template_id,template_revision) REFERENCES recurring_document_template_history(business_id,id,revision))",
        );
        _database.execute(
          'INSERT INTO recurring_document_occurrences SELECT * FROM recurring_document_occurrences_v47',
        );
        _database.execute('DROP TABLE recurring_document_occurrences_v47');
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER recurring_document_occurrences_no_${operation.toLowerCase()} BEFORE $operation ON recurring_document_occurrences BEGIN SELECT RAISE(ABORT,'Recurring document history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 48');
      });
    }
    if (version < 49 && throughVersion >= 49) {
      _transaction(() {
        _database.execute(
          'ALTER TABLE expense_intakes ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>=1)',
        );
        _database.execute(
          'ALTER TABLE expense_intakes ADD COLUMN archived_at TEXT',
        );
        _database.execute(
          'ALTER TABLE expense_intakes ADD COLUMN state_changed_at TEXT',
        );
        _database.execute(
          'CREATE INDEX expense_intakes_active ON expense_intakes(business_id,archived_at,occurred_on)',
        );
        _database.execute(
          "CREATE TRIGGER expense_intakes_protect_removed_posting BEFORE UPDATE ON expense_intakes WHEN NEW.archived_at IS NOT NULL AND NEW.journal_id IS NOT NULL BEGIN SELECT RAISE(ABORT,'Removed expenses cannot be posted'); END",
        );
        _database.execute('PRAGMA user_version = 49');
      });
    }
    if (version < 50 && throughVersion >= 50) {
      // Claim v2 stores a stable claimant identity. No historical payload or
      // journal is rewritten; older builds must refuse this storage contract.
      _transaction(() => _database.execute('PRAGMA user_version = 50'));
    }
    if (version < 51 && throughVersion >= 51) {
      _transaction(() {
        _createTransactionRemovalSchema();
        _database.execute('PRAGMA user_version = 51');
      });
    }
    if (version < 52 && throughVersion >= 52) {
      // Claim v3 retains per-receipt tax/allocation facts. Never rewrite old
      // claim payloads or journals; older builds must reject this contract.
      _transaction(() => _database.execute('PRAGMA user_version = 52'));
    }
    if (version < 53 && throughVersion >= 53) {
      // Tax code v2 explicitly records purchase tax in cost without a dummy
      // liability mapping. Preserve all existing payloads and journal history.
      _transaction(() => _database.execute('PRAGMA user_version = 53'));
    }
    if (version < 54 && throughVersion >= 54) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE company_tax_agencies(business_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,normalized_name TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,PRIMARY KEY(business_id,id),UNIQUE(business_id,normalized_name))',
        );
        _database.execute(
          'CREATE TABLE company_tax_agency_history(business_id TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),payload TEXT NOT NULL,saved_at TEXT NOT NULL,PRIMARY KEY(business_id,id,revision),FOREIGN KEY(business_id,id) REFERENCES company_tax_agencies(business_id,id))',
        );
        for (final operation in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER tax_agency_history_no_${operation.toLowerCase()} BEFORE $operation ON company_tax_agency_history BEGIN SELECT RAISE(ABORT,'Tax agency history is immutable'); END",
          );
        }
        _database.execute('PRAGMA user_version = 54');
      });
    }
    if (version < 55 && throughVersion >= 55) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE tax_remittances(business_id TEXT NOT NULL,id TEXT NOT NULL,journal_id TEXT NOT NULL,origin TEXT NOT NULL,recorded_at TEXT NOT NULL,signature TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,id))',
        );
        _database.execute(
          'CREATE INDEX tax_remittance_journal ON tax_remittances(business_id,journal_id)',
        );
        _database.execute(
          'CREATE TABLE tax_remittance_corrections(business_id TEXT NOT NULL,source_id TEXT NOT NULL,id TEXT NOT NULL,journal_id TEXT,recorded_at TEXT NOT NULL,signature TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,source_id),UNIQUE(business_id,id),FOREIGN KEY(business_id,source_id) REFERENCES tax_remittances(business_id,id))',
        );
        for (final table in ['tax_remittances', 'tax_remittance_corrections']) {
          for (final operation in ['UPDATE', 'DELETE']) {
            _database.execute(
              "CREATE TRIGGER ${table}_no_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Tax remittance history is immutable'); END",
            );
          }
        }
        _database.execute('PRAGMA user_version = 55');
      });
    }
    if (version < 56 && throughVersion >= 56) {
      _transaction(() {
        _database.execute(
          'CREATE TABLE bank_reconciliation_drafts(business_id TEXT NOT NULL,statement_id TEXT NOT NULL REFERENCES bank_statement_imports(id),payment_account_id TEXT NOT NULL,starts_on TEXT NOT NULL,ends_on TEXT NOT NULL,opening_minor INTEGER NOT NULL,closing_minor INTEGER NOT NULL,currency TEXT NOT NULL,opening_evidence TEXT NOT NULL,outstanding_ids TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),saved_at TEXT NOT NULL,PRIMARY KEY(business_id,statement_id),FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        _database.execute('PRAGMA user_version = 56');
      });
    }
    if (version < 57 && throughVersion >= 57) {
      _transaction(() {
        for (final posting in _database.select(
          'SELECT * FROM all_claim_postings',
        )) {
          _writeClaimExpenseInTransaction(posting);
        }
        _validateClaimExpenseArchive(requireComplete: true);
        _database.execute('PRAGMA user_version = 57');
      });
    }
    if (version < 58 && throughVersion >= 58) {
      // Compatibility marker for complete Expense-backed Claim snapshots.
      // Existing Claim/Expense history and journal rows are not rewritten.
      _transaction(() => _database.execute('PRAGMA user_version = 58'));
    }
    if (version < 59 && throughVersion >= 59) {
      _transaction(() {
        _database.execute(
          "ALTER TABLE bank_reconciliation_drafts ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'",
        );
        _database.execute('PRAGMA user_version = 59');
      });
    }
    if (version < 60 && throughVersion >= 60) {
      _migrateAccountReconciliation();
    }
    if (version < 61 && throughVersion >= 61) {
      _migrateExpenseRevisions();
    }
    if (version < 62 && throughVersion >= 62) {
      _migrateExpenseRevisionPostings();
    }
    if (version < 63 && throughVersion >= 63) {
      _migrateCurrentQuotations();
    }
    if (version < 64 && throughVersion >= 64) {
      _transaction(() {
        _database.execute('ALTER TABLE accounts ADD COLUMN profile TEXT');
        _database.execute('PRAGMA user_version = 64');
      });
    }
  }

  JournalLine _lineFromRow(Row row) {
    final accountId = EntityId.parse(row['account_id'] as String);
    final amount = Money.fromMinor(
      row['amount_minor'] as int,
      row['currency'] as String,
    );
    return row['kind'] == JournalLineKind.debit.name
        ? JournalLine.debit(accountId: accountId, amount: amount)
        : JournalLine.credit(accountId: accountId, amount: amount);
  }

  void _joinTransaction(void Function() action) {
    if (_database.autocommit) {
      _transaction(action);
    } else {
      action();
    }
  }

  void _transaction(void Function() action) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      action();
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('The accounting database is closed.');
    }
  }

  static EntityId? _idOrNull(Object? value) {
    return value == null ? null : EntityId.parse(value as String);
  }

  static DateTime? _dateOrNull(Object? value) {
    return value == null ? null : DateTime.parse(value as String);
  }

  static RecordMetadata _metadataWithStoredRevision(
    RecordMetadata initial, {
    required int revision,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  }) {
    return RecordMetadata.restore(
      recordId: initial.recordId,
      businessId: initial.businessId,
      originDeviceId: initial.originDeviceId,
      createdAt: initial.createdAt,
      updatedAt: updatedAt,
      revision: revision,
      deletedAt: deletedAt,
    );
  }
}
