part of 'accounting_database.dart';

/// Reuses the existing append-only ledger audit for saved draft revisions.
/// Posted and source-owned journals require their own linked correction owner.
extension JournalDraftRevisionPersistence on LocalAccountingDatabase {
  bool isManualJournalDraft(EntityId businessId, EntityId journalId) {
    _ensureOpen();
    final record = _readJournal(journalId);
    if (record == null ||
        record.metadata.businessId != businessId ||
        record.metadata.isTombstone ||
        record.entry.state != JournalEntryState.draft ||
        record.entry.isClosing ||
        record.entry.reversesId != null) {
      return false;
    }
    return !_journalHasSourceOwner(businessId, journalId) &&
        manualJournalRevisionForDraft(businessId, journalId) == null;
  }

  bool _journalHasSourceOwner(EntityId businessId, EntityId journalId) {
    return _database
        .select(
          '''
      SELECT 1 FROM expense_intakes WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM expense_revision_postings WHERE business_id=?1 AND (journal_id=?2 OR reversal_journal_id=?2)
      UNION ALL SELECT 1 FROM invoice_postings WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM customer_receipts WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM invoice_credit_postings WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM bill_postings WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM bill_settlements WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM all_claim_postings WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM claim_settlements WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM tax_remittances WHERE business_id=?1 AND journal_id=?2
      UNION ALL SELECT 1 FROM tax_remittance_corrections WHERE business_id=?1 AND journal_id=?2
      LIMIT 1
      ''',
          [businessId.value, journalId.value],
        )
        .isNotEmpty;
  }

  StoredJournalEntry reviseManualJournalDraft({
    required StoredJournalEntry expected,
    required JournalEntry replacement,
    required EntityId requestId,
    required EntityId actorId,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    final businessId = expected.metadata.businessId;
    final after = StoredJournalEntry(
      entry: replacement,
      metadata: expected.metadata.nextRevision(updatedAt: savedAt),
    );
    final detail = jsonEncode({
      'requestId': requestId.value,
      'before': _journalDraftSnapshot(expected),
      'after': _journalDraftSnapshot(after),
    });
    late StoredJournalEntry result;
    _transaction(() {
      final owners = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      if (owners.length != 1 || owners.single['owner_id'] != actorId.value) {
        throw StateError('Only the workspace owner can revise this Journal.');
      }
      final retries = _database.select(
        "SELECT * FROM ledger_audit WHERE business_id=? AND kind='journal.draft_revised' AND json_extract(detail,'\$.requestId')=?",
        [businessId.value, requestId.value],
      );
      if (retries.isNotEmpty) {
        final event = retries.single;
        if (event['subject_id'] != expected.entry.id.value ||
            event['actor_id'] != actorId.value ||
            event['occurred_at'] != savedAt.toUtc().toIso8601String() ||
            event['detail'] != detail) {
          throw StateError(
            'This Journal revision request has different facts.',
          );
        }
        result = after;
        return;
      }
      final current = _readJournal(expected.entry.id);
      if (current == null ||
          jsonEncode(_journalDraftSnapshot(current)) !=
              jsonEncode(_journalDraftSnapshot(expected))) {
        throw StateError('The Journal changed. Reopen before editing.');
      }
      if (!isManualJournalDraft(businessId, expected.entry.id) ||
          replacement.id != expected.entry.id ||
          replacement.state != JournalEntryState.draft ||
          replacement.isClosing ||
          replacement.reversesId != null) {
        throw StateError(
          'Use the current transaction owner to revise this Journal.',
        );
      }
      requireJournalUnreconciled(businessId, expected.entry.id);
      if (replacement.validationErrors.isNotEmpty) {
        throw JournalValidationException(replacement.validationErrors);
      }
      final currency = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id=?',
        [businessId.value],
      );
      if (currency.length != 1) {
        throw StateError('Configure the ledger currency before saving.');
      }
      if (expected.entry.lines.any(
        (line) => line.amount.currency != currency.single['currency'],
      )) {
        throw StateError(
          'Retain the saved currency; foreign amounts require reviewed conversion.',
        );
      }
      final retainedLines = expected.entry.lines.toList();
      for (final line in replacement.lines) {
        final accounts = _database.select(
          'SELECT * FROM accounts WHERE id=? AND business_id=?',
          [line.accountId.value, businessId.value],
        );
        if (line.amount.currency != currency.single['currency'] ||
            accounts.length != 1 ||
            accounts.single['is_parent'] != 0) {
          throw StateError(
            'Choose a valid company account and ledger currency for each changed line.',
          );
        }
        if (accounts.single['status'] != AccountStatus.active.name) {
          final retained = retainedLines.indexWhere(
            (saved) =>
                saved.accountId == line.accountId &&
                saved.kind == line.kind &&
                saved.amount == line.amount,
          );
          if (retained < 0) {
            throw StateError(
              'Retain the saved unavailable account line or choose an active account.',
            );
          }
          retainedLines.removeAt(retained);
        }
      }
      _writeJournal(after, retainedDraftRevision: true);
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'journal.draft_revised',
        subjectId: expected.entry.id,
        detail: detail,
      );
      result = after;
    });
    return result;
  }

  List<({StoredJournalEntry before, StoredJournalEntry after})>
  manualJournalDraftHistory(EntityId businessId, EntityId journalId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            "SELECT detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='journal.draft_revised' ORDER BY sequence",
            [businessId.value, journalId.value],
          )
          .map((row) {
            final data =
                jsonDecode(row['detail'] as String) as Map<String, dynamic>;
            return (
              before: _journalDraftFromSnapshot(
                data['before'] as Map<String, dynamic>,
              ),
              after: _journalDraftFromSnapshot(
                data['after'] as Map<String, dynamic>,
              ),
            );
          }),
    );
  }

  Map<String, Object?> _journalDraftSnapshot(StoredJournalEntry record) => {
    'id': record.entry.id.value,
    'businessId': record.metadata.businessId.value,
    'originDeviceId': record.metadata.originDeviceId.value,
    'createdAt': record.metadata.createdAt.toUtc().toIso8601String(),
    'updatedAt': record.metadata.updatedAt.toUtc().toIso8601String(),
    'revision': record.metadata.revision,
    'deletedAt': record.metadata.deletedAt?.toUtc().toIso8601String(),
    'date': LocalAccountingDatabase._calendarDay(record.entry.date),
    'memo': record.entry.memo,
    'state': record.entry.state.name,
    'reversesId': record.entry.reversesId?.value,
    'closingEquityId': record.entry.closingEquityAccountId?.value,
    'lines': [
      for (final line in record.entry.lines)
        {
          'accountId': line.accountId.value,
          'kind': line.kind.name,
          'minorUnits': line.amount.minorUnits,
          'currency': line.amount.currency,
        },
    ],
  };

  StoredJournalEntry _journalDraftFromSnapshot(Map<String, dynamic> data) {
    final id = EntityId.parse(data['id'] as String);
    return StoredJournalEntry(
      entry: JournalEntry.restore(
        id: id,
        date: DateTime.parse('${data['date']}T00:00:00.000Z'),
        memo: data['memo'] as String,
        state: JournalEntryState.values.byName(data['state'] as String),
        reversesId: LocalAccountingDatabase._idOrNull(data['reversesId']),
        closingEquityAccountId: LocalAccountingDatabase._idOrNull(
          data['closingEquityId'],
        ),
        lines: [
          for (final item in data['lines'] as List<dynamic>)
            if (JournalLineKind.values.byName(item['kind'] as String) ==
                JournalLineKind.debit)
              JournalLine.debit(
                accountId: EntityId.parse(item['accountId'] as String),
                amount: Money.fromMinor(
                  item['minorUnits'] as int,
                  item['currency'] as String,
                ),
              )
            else
              JournalLine.credit(
                accountId: EntityId.parse(item['accountId'] as String),
                amount: Money.fromMinor(
                  item['minorUnits'] as int,
                  item['currency'] as String,
                ),
              ),
        ],
      ),
      metadata: RecordMetadata.restore(
        recordId: id,
        businessId: EntityId.parse(data['businessId'] as String),
        originDeviceId: EntityId.parse(data['originDeviceId'] as String),
        createdAt: DateTime.parse(data['createdAt'] as String),
        updatedAt: DateTime.parse(data['updatedAt'] as String),
        revision: data['revision'] as int,
        deletedAt: data['deletedAt'] == null
            ? null
            : DateTime.parse(data['deletedAt'] as String),
      ),
    );
  }

  void _validateManualJournalDraftRevisionArchive() {
    final prior = <String, StoredJournalEntry>{};
    final requests = <String>{};
    for (final row in _database.select(
      "SELECT * FROM ledger_audit WHERE kind='journal.draft_revised' ORDER BY sequence",
    )) {
      final data = jsonDecode(row['detail'] as String) as Map<String, dynamic>;
      final before = _journalDraftFromSnapshot(
        data['before'] as Map<String, dynamic>,
      );
      final after = _journalDraftFromSnapshot(
        data['after'] as Map<String, dynamic>,
      );
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [row['business_id']],
      );
      final previous = prior[before.entry.id.value];
      if (!requests.add(
            '${row['business_id']}/${EntityId.parse(data['requestId'] as String).value}',
          ) ||
          owner.length != 1 ||
          owner.single['owner_id'] != row['actor_id'] ||
          row['business_id'] != before.metadata.businessId.value ||
          row['subject_id'] != before.entry.id.value ||
          before.entry.state != JournalEntryState.draft ||
          after.entry.state != JournalEntryState.draft ||
          before.entry.isClosing ||
          after.entry.isClosing ||
          before.entry.reversesId != null ||
          after.entry.reversesId != null ||
          before.metadata.isTombstone ||
          after.metadata.isTombstone ||
          before.entry.id != after.entry.id ||
          before.metadata.businessId != after.metadata.businessId ||
          before.metadata.originDeviceId != after.metadata.originDeviceId ||
          before.metadata.createdAt != after.metadata.createdAt ||
          after.metadata.revision != before.metadata.revision + 1 ||
          !after.metadata.updatedAt.isAfter(before.metadata.updatedAt) ||
          row['occurred_at'] != after.metadata.updatedAt.toIso8601String() ||
          before.entry.validationErrors.isNotEmpty ||
          after.entry.validationErrors.isNotEmpty ||
          (previous != null &&
              jsonEncode(_journalDraftSnapshot(previous)) !=
                  jsonEncode(_journalDraftSnapshot(before)))) {
        throw StateError(
          'Journal draft revision history has invalid identity or accounting facts.',
        );
      }
      prior[after.entry.id.value] = after;
      for (final snapshot in [before, after]) {
        for (final line in snapshot.entry.lines) {
          if (_database.select(
                'SELECT 1 FROM accounts WHERE id=? AND business_id=?',
                [line.accountId.value, snapshot.metadata.businessId.value],
              ).length !=
              1) {
            throw StateError(
              'Journal draft history references an unavailable company account.',
            );
          }
        }
      }
    }
    for (final latest in prior.values) {
      final current = _readJournal(latest.entry.id);
      if (current == null ||
          current.metadata.businessId != latest.metadata.businessId ||
          current.metadata.revision < latest.metadata.revision ||
          (current.entry.state == JournalEntryState.posted &&
              (current.entry.memo != latest.entry.memo ||
                  LocalAccountingDatabase._calendarDay(current.entry.date) !=
                      LocalAccountingDatabase._calendarDay(latest.entry.date) ||
                  LocalAccountingDatabase._lineSignature(current.entry.lines) !=
                      LocalAccountingDatabase._lineSignature(
                        latest.entry.lines,
                      ))) ||
          (current.entry.state == JournalEntryState.draft &&
              !current.metadata.isTombstone &&
              jsonEncode(_journalDraftSnapshot(current)) !=
                  jsonEncode(_journalDraftSnapshot(latest)))) {
        throw StateError(
          'Journal draft revision history has no matching current record.',
        );
      }
    }
  }
}
