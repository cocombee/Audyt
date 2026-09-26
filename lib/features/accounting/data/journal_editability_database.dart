part of 'accounting_database.dart';

/// Reconciliation is separate from posting and from an unapproved bank match.
/// UI callers may read the same decision that a correction command rechecks
/// within its write transaction. Prior journal and reconciliation evidence stays
/// immutable; a current record edit must use its own linked revision command.
extension JournalEditabilityPersistence on LocalAccountingDatabase {
  EntityId? journalReconciliationId(EntityId businessId, EntityId journalId) {
    _ensureOpen();
    // Resolve ownership and both completion families in one SQLite snapshot.
    // Approved combined matches retain every member, not just their primary
    // journal. The root's retained snapshot also identifies already-cleared
    // opening movements; outstanding opening items are excluded. Reopening
    // releases only that completion's lock. Never infer missing old snapshots.
    final rows = _database.select(
      r'''
      SELECT (
        SELECT c.id FROM bank_reconciliations c
        WHERE c.business_id=j.business_id
          AND NOT EXISTS (
            SELECT 1 FROM bank_reconciliation_reopenings r
            WHERE r.completion_id=c.id
          )
          AND (
            EXISTS (
              SELECT 1 FROM bank_reconciliation_cleared_movements m
              WHERE m.completion_id=c.id AND m.journal_id=j.id
            )
            OR EXISTS (
              SELECT 1 FROM bank_reconciliation_allocations a
              JOIN bank_match_history h ON h.acceptance_id=a.acceptance_id
              WHERE a.completion_id=c.id AND h.business_id=j.business_id
                AND (
                  h.journal_id=j.id
                  OR EXISTS (
                    SELECT 1 FROM bank_match_ledger_members l
                    WHERE l.acceptance_id=a.acceptance_id
                      AND l.business_id=j.business_id AND l.journal_id=j.id
                  )
                )
            )
            OR (
              c.previous_id IS NULL
              AND EXISTS (
                SELECT 1 FROM bank_reconciliation_ledger_snapshots s,
                  json_each(s.payload,'$.movements') m
                WHERE s.completion_id=c.id
                  AND substr(json_extract(m.value,'$.id'),1,length(j.id)+1)=j.id||':'
                  AND substr(json_extract(m.value,'$.date'),1,10)<substr(c.starts_on,1,10)
                  AND NOT EXISTS (
                    SELECT 1 FROM json_each(c.payload,'$.openingOutstanding') o
                    WHERE o.value=json_extract(m.value,'$.id')
                  )
              )
            )
          )
        ORDER BY c.approved_at DESC,c.id DESC LIMIT 1
      ) AS completion_id
      FROM journal_entries j WHERE j.business_id=? AND j.id=?
      ''',
      [businessId.value, journalId.value],
    );
    if (rows.isEmpty) {
      throw StateError('The journal is unavailable in this business.');
    }
    final completion = rows.single['completion_id'] as String?;
    return completion == null ? null : EntityId.parse(completion);
  }

  bool isJournalReconciled(EntityId businessId, EntityId journalId) =>
      journalReconciliationId(businessId, journalId) != null;

  /// Invoke again at commit, never trust eligibility captured when a form opens.
  void requireJournalUnreconciled(EntityId businessId, EntityId journalId) {
    if (isJournalReconciled(businessId, journalId)) {
      throw StateError(
        'Reopen its reconciliation before editing this transaction.',
      );
    }
  }
}
