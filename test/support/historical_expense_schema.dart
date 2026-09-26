import 'package:sqlite3/sqlite3.dart';

/// Fixtures made from today's schema must remove newer removal deltas
/// before declaring an older version. Genuine historical fixtures have none.
/// This keeps the migration test input faithful without changing production.
void removeExpenseRemovalSchema(Database database) {
  // Current projection views refer to these newer columns. Remove the views
  // before stripping columns to reconstruct a genuine pre-v49 fixture.
  database.execute('DROP VIEW IF EXISTS current_expense_intakes');
  database.execute('DROP VIEW IF EXISTS financial_expense_intakes');
  database.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
  database.execute('DROP TABLE IF EXISTS tax_remittances');
  removeTransactionRemovalSchema(database);
  final columns = database
      .select('PRAGMA table_info(expense_intakes)')
      .map((row) => row['name'])
      .toSet();
  if (!columns.contains('archived_at')) return;
  database.execute(
    'DROP TRIGGER IF EXISTS expense_intakes_protect_removed_posting',
  );
  database.execute('DROP INDEX IF EXISTS expense_intakes_active');
  for (final column in ['state_changed_at', 'archived_at', 'revision']) {
    database.execute('ALTER TABLE expense_intakes DROP COLUMN $column');
  }
}

void removeTransactionRemovalSchema(Database database) {
  final triggers = database.select(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE '%protect_removed%' OR name LIKE '%retain_removed_history%' OR name LIKE 'transaction_record_removals_%')",
  );
  for (final row in triggers) {
    // Expense v49 is removed separately by its existing fixture helper.
    if (row['name'] == 'expense_intakes_protect_removed_posting') continue;
    database.execute('DROP TRIGGER "${row['name']}"');
  }
  database.execute('DROP VIEW IF EXISTS transaction_record_removal_state');
  database.execute('DROP TABLE IF EXISTS transaction_record_removals');
}
