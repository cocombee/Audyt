part of 'accounting_database.dart';

/// Restored approvals use their retained allocation history, never today's
/// active matches. Reopening and later corrections must retain the originals.
extension ImportedReconciliationRecovery on LocalAccountingDatabase {
  void _validateImportedReconciliationArchive() {
    bool hasTable(String name) => _database.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    ).isNotEmpty;
    final hasGroups = hasTable('bank_match_group_members');
    final hasCombined = hasTable('bank_match_ledger_members');
    final hasSnapshots = hasTable('bank_reconciliation_ledger_snapshots');
    for (final row in _database.select(
      'SELECT * FROM bank_reconciliations WHERE statement_id IS NOT NULL',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final statementId = EntityId.parse(row['statement_id'] as String);
      final id = row['id'] as String;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final source = bankStatement(business, statementId);
      final imported = _database.select(
        'SELECT payment_account_id FROM bank_statement_imports WHERE business_id=? AND id=?',
        [business.value, statementId.value],
      );
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [business.value],
      );
      if (source == null ||
          imported.length != 1 ||
          owner.length != 1 ||
          owner.single['owner_id'] != row['actor_id'] ||
          imported.single['payment_account_id'] != row['payment_account_id'] ||
          source.currency != row['currency'] ||
          payload['business'] != business.value ||
          payload['statement'] != statementId.value ||
          payload['actor'] != row['actor_id'] ||
          payload['start'] != row['starts_on'] ||
          payload['end'] != row['ends_on'] ||
          payload['opening'] != row['opening_minor'] ||
          payload['closing'] != row['closing_minor'] ||
          payload['currency'] != row['currency'] ||
          payload['closingCurrency'] != row['currency'] ||
          payload['previous'] != row['previous_id'] ||
          payload['evidence'] != row['opening_evidence']) {
        throw const FormatException(
          'Approved imported reconciliation identity differs.',
        );
      }
      final start = DateTime.parse(row['starts_on'] as String),
          end = DateTime.parse(row['ends_on'] as String);
      final movements = {
        for (final movement in _statementLedgerMovements(business, statementId))
          movement.candidate.movementId: movement,
      };
      final matches = <int, String>{}, acceptances = <int, String>{};
      final grouped = <String, Money>{};
      final combined = <String, List<StatementPostedMovement>>{};
      for (final allocation in _database.select(
        'SELECT h.* FROM bank_reconciliation_allocations a JOIN bank_match_history h ON h.acceptance_id=a.acceptance_id WHERE a.completion_id=?',
        [id],
      )) {
        final acceptance = allocation['acceptance_id'] as String;
        final movementId =
            "${allocation['journal_id']}:${allocation['line_index']}";
        final movement = movements[movementId];
        if (allocation['business_id'] != business.value ||
            allocation['statement_id'] != statementId.value ||
            allocation['actor_id'] != owner.single['owner_id'] ||
            movement == null) {
          throw const FormatException(
            'Approved imported allocation ownership differs.',
          );
        }
        final rows = <int>[allocation['source_row'] as int];
        if (hasGroups) {
          for (final member in _database.select(
            'SELECT * FROM bank_match_group_members WHERE acceptance_id=?',
            [acceptance],
          )) {
            if (member['business_id'] != business.value ||
                member['statement_id'] != statementId.value) {
              throw const FormatException(
                'Approved statement group ownership differs.',
              );
            }
            rows.add(member['source_row'] as int);
          }
        }
        if (rows.length > 1) grouped[acceptance] = movement.amount;
        if (hasCombined) {
          final parts = <StatementPostedMovement>[];
          for (final member in _database.select(
            'SELECT * FROM bank_match_ledger_members WHERE acceptance_id=?',
            [acceptance],
          )) {
            final part =
                movements["${member['journal_id']}:${member['line_index']}"];
            if (member['business_id'] != business.value || part == null) {
              throw const FormatException(
                'Approved combined ledger ownership differs.',
              );
            }
            parts.add(part);
          }
          if (parts.isNotEmpty) {
            if (rows.length != 1) {
              throw const FormatException(
                'Approved allocation mixes grouped and combined matching.',
              );
            }
            combined[acceptance] = parts;
          }
        }
        for (final sourceRow in rows) {
          if (matches.containsKey(sourceRow)) {
            throw const FormatException(
              'Approved statement row is allocated twice.',
            );
          }
          matches[sourceRow] = movementId;
          acceptances[sourceRow] = acceptance;
        }
      }
      final savedMatches = payload['matches'] as Map;
      if (savedMatches.length != acceptances.length ||
          acceptances.entries.any((e) => savedMatches['${e.key}'] != e.value)) {
        throw const FormatException(
          'Approved imported match identities differ.',
        );
      }
      final review = StatementReconciliationReview.evaluate(
        startsOn: start,
        endsOn: end,
        openingBalance: Money.fromMinor(
          row['opening_minor'] as int,
          row['currency'] as String,
        ),
        closingBalance: Money.fromMinor(
          row['closing_minor'] as int,
          row['currency'] as String,
        ),
        rows: [
          for (final bankRow in source.rows)
            StatementRowSuggestions(
              row: bankRow,
              candidates: [
                if (movements[matches[bankRow.sourceRow]] case final movement?
                    when movement.amount == bankRow.amount)
                  movement.candidate,
              ],
            ),
        ],
        acceptedMatches: matches,
        acceptanceIds: acceptances,
        groupedMovementAmounts: grouped,
        combinedMovements: combined,
      );
      if (!review.rowsAndBalancesAgree) {
        throw const FormatException(
          'Approved imported statement has differences or incomplete allocations.',
        );
      }
      final previous = row['previous_id'] as String?;
      final outstanding = ((payload['openingOutstanding'] as List?) ?? const [])
          .cast<String>()
          .toSet();
      if (previous != null) {
        final parents = _database.select(
          'SELECT * FROM bank_reconciliations WHERE business_id=? AND id=? AND payment_account_id=?',
          [business.value, previous, row['payment_account_id']],
        );
        if (parents.length != 1 ||
            outstanding.isNotEmpty ||
            parents.single['currency'] != row['currency'] ||
            parents.single['closing_minor'] != row['opening_minor'] ||
            DateTime.parse(parents.single['ends_on'] as String)
                    .add(const Duration(days: 1)) !=
                start ||
            DateTime.parse(parents.single['approved_at'] as String)
                .isAfter(DateTime.parse(row['approved_at'] as String))) {
          throw const FormatException('Approved imported predecessor differs.');
        }
      } else if ((row['opening_evidence'] as String).trim().isEmpty) {
        throw const FormatException(
          'Approved imported opening evidence is unavailable.',
        );
      }
      // Schema19 predates immutable ledger snapshots. Validate its actual source
      // and allocation arithmetic above without inventing an approval snapshot.
      final snapshot = hasSnapshots
          ? reconciliationLedgerSnapshot(business, id)
          : null;
      if (snapshot != null) {
        if (snapshot.balance.currency != row['currency'] ||
            snapshot.movements.any((saved) {
              final actual = movements[saved.id];
              return actual == null ||
                  actual.amount != saved.amount ||
                  LocalAccountingDatabase._calendarDay(actual.candidate.date) !=
                      LocalAccountingDatabase._calendarDay(saved.date) ||
                  actual.candidate.memo != saved.memo ||
                  saved.date.isAfter(end);
            })) {
          throw const FormatException(
            'Approved imported ledger snapshot differs from its source.',
          );
        }
        if (previous == null &&
            (outstanding.any(
                  (selected) => !snapshot.movements.any(
                    (m) => m.id == selected && m.date.isBefore(start),
                  ),
                ) ||
                _openingAfterOutstanding(
                      snapshot.movements
                          .where((m) => m.date.isBefore(start))
                          .toList(),
                      outstanding,
                      row['currency'] as String,
                    ).minorUnits !=
                    row['opening_minor'])) {
          throw const FormatException(
            'Approved imported opening ledger differs.',
          );
        }
        final classification = _reconciliationClassification(business, id);
        if (classification == null || !classification.agrees) {
          throw const FormatException(
            'Approved imported cleared ledger has a difference.',
          );
        }
      }
      _readReconciliationAttachments(payload['attachments']);
    }
  }
}
