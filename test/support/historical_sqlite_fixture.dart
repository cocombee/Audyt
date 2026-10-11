import 'package:sqlite3/sqlite3.dart';

/// Keep a historical archive's table shape truthful without losing new facts.
void dropCurrentAccountArchiveFixtureOwner(Map<String, dynamic> archive) {
  dropCurrentPaymentTermArchiveFixtureOwner(archive);
  dropCurrentPaymentMethodArchiveFixtureOwner(archive);
  final table = (archive['tables'] as Map)['accounts'] as Map;
  final columns = table['columns'] as List;
  final index = columns.indexOf('profile');
  if (index < 0) return;
  for (final row in table['rows'] as List) {
    if (row[index] != null) {
      throw StateError(
        'An older fixture cannot retain schema-64 account profiles.',
      );
    }
  }
  for (final row in table['rows'] as List) {
    row.removeAt(index);
  }
  columns.removeAt(index);
}

/// A pre-v65 archive cannot retain owners introduced by the v65 migration.
/// Refuse to discard saved method facts while building a historical fixture.
void dropCurrentPaymentMethodArchiveFixtureOwner(Map<String, dynamic> archive) {
  dropCurrentPaymentTermArchiveFixtureOwner(archive);
  final version = archive['schemaVersion'];
  if (version is! int || version >= 65) return;
  final tables = archive['tables'] as Map;
  for (final name in [
    'company_payment_method_history',
    'company_payment_methods',
  ]) {
    final table = tables[name];
    if (table is Map &&
        table['rows'] is List &&
        (table['rows'] as List).isNotEmpty) {
      throw StateError(
        'A pre-v65 fixture cannot discard saved company payment-method rows.',
      );
    }
    tables.remove(name);
  }
}

/// A historical archive must keep its declared schema's table set.
void dropCurrentPaymentTermArchiveFixtureOwner(Map<String, dynamic> archive) {
  final version = archive['schemaVersion'];
  if (version is! int || version >= 66) return;
  final tables = archive['tables'] as Map;
  final table = tables['company_payment_terms'];
  if (table is Map &&
      table['rows'] is List &&
      (table['rows'] as List).isNotEmpty) {
    throw StateError('A pre-v66 fixture cannot discard saved payment terms.');
  }
  tables.remove('company_payment_terms');
}

/// Historical fixtures cannot retain owners added after their declared schema.
/// Remove only empty later owners before the existing older-schema DDL.
/// Real retained facts are never silently discarded to create a fixture.
void dropCurrentQuotationFixtureOwner(Database database) {
  dropCurrentPaymentTermFixtureOwner(database);
  dropCurrentAccountFixtureOwner(database);
  dropCurrentPaymentMethodFixtureOwner(database);
  final exists = database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='converted_quotation_revisions'",
      )
      .isNotEmpty;
  if (exists &&
      database
              .select(
                'SELECT COUNT(*) AS count FROM converted_quotation_revisions',
              )
              .single['count'] !=
          0) {
    throw StateError(
      'An older fixture cannot retain schema-63 quotation revisions.',
    );
  }
  database.execute('DROP VIEW IF EXISTS current_quotations');
  database.execute('DROP TABLE IF EXISTS converted_quotation_revisions');
}

void dropCurrentAccountFixtureOwner(Database database) {
  dropCurrentPaymentTermFixtureOwner(database);
  final hasProfile = database
      .select('PRAGMA table_info(accounts)')
      .any((column) => column['name'] == 'profile');
  if (hasProfile) {
    if (database
        .select('SELECT 1 FROM accounts WHERE profile IS NOT NULL LIMIT 1')
        .isNotEmpty) {
      throw StateError(
        'An older fixture cannot retain schema-64 account profiles.',
      );
    }
    database.execute('ALTER TABLE accounts DROP COLUMN profile');
  }
}

/// Removes empty v65 owners before a local database fixture is downgraded.
/// Dropping the history table also removes its immutable history triggers.
void dropCurrentPaymentMethodFixtureOwner(Database database) {
  dropCurrentPaymentTermFixtureOwner(database);
  final hasMethods = database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='company_payment_methods'",
      )
      .isNotEmpty;
  final hasHistory = database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='company_payment_method_history'",
      )
      .isNotEmpty;
  if (!hasMethods && !hasHistory) return;
  if ((hasMethods &&
          database
              .select('SELECT 1 FROM company_payment_methods LIMIT 1')
              .isNotEmpty) ||
      (hasHistory &&
          database
              .select('SELECT 1 FROM company_payment_method_history LIMIT 1')
              .isNotEmpty)) {
    throw StateError(
      'A pre-v65 fixture cannot discard saved company payment-method rows.',
    );
  }
  database.execute(
    'DROP TRIGGER IF EXISTS company_payment_method_history_no_update',
  );
  database.execute(
    'DROP TRIGGER IF EXISTS company_payment_method_history_no_delete',
  );
  database.execute('DROP TABLE IF EXISTS company_payment_method_history');
  database.execute('DROP TABLE IF EXISTS company_payment_methods');
}

void dropCurrentPaymentTermFixtureOwner(Database database) {
  final exists = database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='company_payment_terms'",
      )
      .isNotEmpty;
  if (!exists) return;
  if (database
      .select('SELECT 1 FROM company_payment_terms LIMIT 1')
      .isNotEmpty) {
    throw StateError('A pre-v66 fixture cannot discard saved payment terms.');
  }
  database.execute('DROP TABLE company_payment_terms');
}
