import 'package:sqlite3/sqlite3.dart';

/// Keep a historical archive's table shape truthful without losing new facts.
void dropCurrentAccountArchiveFixtureOwner(Map<String, dynamic> archive) {
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

/// Historical fixtures cannot retain owners added after their declared schema.
/// Remove only empty later owners before the existing older-schema DDL.
/// Real retained facts are never silently discarded to create a fixture.
void dropCurrentQuotationFixtureOwner(Database database) {
  dropCurrentAccountFixtureOwner(database);
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
