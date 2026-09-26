part of 'accounting_database.dart';

/// Current manual-Journal corrections reuse the append-only ledger audit,
/// original journal storage and approval owner. No old posting is overwritten.
extension ManualJournalCurrentRevisionPersistence on LocalAccountingDatabase {
  StoredManualJournalRevision _manualRevision(Map<String, dynamic> data) =>
      StoredManualJournalRevision(
        rootId: EntityId.parse(data['rootId'] as String),
        revision: data['revision'] as int,
        source: _journalDraftFromSnapshot(
          data['source'] as Map<String, dynamic>,
        ),
        draft: _journalDraftFromSnapshot(data['draft'] as Map<String, dynamic>),
      );

  StoredManualJournalRevision? manualJournalCurrentRevision(
    EntityId businessId,
    EntityId rootId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      "SELECT detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='journal.current_saved' ORDER BY sequence DESC LIMIT 1",
      [businessId.value, rootId.value],
    );
    return rows.isEmpty
        ? null
        : _manualRevision(
            jsonDecode(rows.single['detail'] as String) as Map<String, dynamic>,
          );
  }

  StoredManualJournalRevision? manualJournalRevisionForDraft(
    EntityId businessId,
    EntityId journalId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      r"SELECT detail FROM ledger_audit WHERE business_id=? AND kind='journal.current_saved' AND json_extract(detail,'$.draft.id')=?",
      [businessId.value, journalId.value],
    );
    if (rows.length > 1) {
      throw StateError('The Journal revision identity is inconsistent.');
    }
    return rows.isEmpty
        ? null
        : _manualRevision(
            jsonDecode(rows.single['detail'] as String) as Map<String, dynamic>,
          );
  }

  EntityId manualJournalCurrentPostingId(EntityId businessId, EntityId rootId) {
    _ensureOpen();
    final rows = _database.select(
      "SELECT detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='journal.current_posted' ORDER BY sequence DESC LIMIT 1",
      [businessId.value, rootId.value],
    );
    return rows.isEmpty
        ? rootId
        : EntityId.parse(
            (jsonDecode(rows.single['detail'] as String)
                    as Map<String, dynamic>)['journalId']
                as String,
          );
  }

  bool _manualFinancialHistoryBound(EntityId businessId, EntityId journalId) =>
      _database.select(
        r"SELECT 1 FROM ledger_audit WHERE business_id=?1 AND ((kind='journal.current_saved' AND json_extract(detail,'$.source.id')=?2) OR (kind='journal.current_posted' AND json_extract(detail,'$.journalId')=?2)) LIMIT 1",
        [businessId.value, journalId.value],
      ).isNotEmpty;

  EntityId? manualJournalCurrentRootForEntry(
    EntityId businessId,
    EntityId journalId,
  ) {
    _ensureOpen();
    final revision = manualJournalRevisionForDraft(businessId, journalId);
    if (revision != null) {
      return isCurrentManualJournalRoot(businessId, revision.rootId)
          ? revision.rootId
          : null;
    }
    final rows = _database.select(
      r"SELECT subject_id FROM ledger_audit WHERE business_id=? AND kind='journal.current_posted' AND json_extract(detail,'$.requestId')=?",
      [businessId.value, journalId.value],
    );
    if (rows.length == 1) {
      final root = EntityId.parse(rows.single['subject_id'] as String);
      return isCurrentManualJournalRoot(businessId, root) ? root : null;
    }
    return isCurrentManualJournalRoot(businessId, journalId) ? journalId : null;
  }

  bool isCurrentManualJournalRoot(EntityId businessId, EntityId rootId) {
    _ensureOpen();
    final root = _readJournal(rootId);
    if (root == null ||
        root.metadata.businessId != businessId ||
        root.metadata.isTombstone ||
        root.entry.state != JournalEntryState.posted ||
        root.entry.isClosing ||
        root.entry.reversesId != null ||
        _journalHasSourceOwner(businessId, rootId) ||
        manualJournalRevisionForDraft(businessId, rootId) != null) {
      return false;
    }
    final sourceId = manualJournalCurrentPostingId(businessId, rootId);
    final source = _readJournal(sourceId);
    return source != null &&
        source.metadata.businessId == businessId &&
        !source.metadata.isTombstone &&
        source.entry.state == JournalEntryState.posted &&
        !source.entry.isClosing &&
        source.entry.reversesId == null &&
        _database.select(
          "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' LIMIT 1",
          [businessId.value, sourceId.value],
        ).isEmpty;
  }

  void _requireManualJournalOwner(EntityId businessId, EntityId actorId) {
    if (_database.select(
          'SELECT 1 FROM local_workspace WHERE business_id=? AND owner_id=?',
          [businessId.value, actorId.value],
        ).length !=
        1) {
      throw StateError('Only the workspace owner can revise this Journal.');
    }
  }

  StoredManualJournalRevision saveManualJournalCurrentRevision({
    required EntityId rootId,
    required StoredJournalEntry expectedSource,
    required int expectedCurrentRevision,
    required JournalEntry replacement,
    required EntityId requestId,
    required EntityId actorId,
    required EntityId deviceId,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    final businessId = expectedSource.metadata.businessId;
    final draft = StoredJournalEntry(
      entry: replacement,
      metadata: RecordMetadata.initial(
        recordId: replacement.id,
        businessId: businessId,
        originDeviceId: deviceId,
        createdAt: savedAt,
      ),
    );
    final detail = jsonEncode({
      'rootId': rootId.value,
      'revision': expectedCurrentRevision + 1,
      'requestId': requestId.value,
      'source': _journalDraftSnapshot(expectedSource),
      'draft': _journalDraftSnapshot(draft),
    });
    late StoredManualJournalRevision result;
    _transaction(() {
      _requireManualJournalOwner(businessId, actorId);
      final retry = _database.select(
        r"SELECT * FROM ledger_audit WHERE business_id=? AND kind='journal.current_saved' AND json_extract(detail,'$.requestId')=?",
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['detail'] != detail ||
            retry.single['actor_id'] != actorId.value ||
            retry.single['occurred_at'] != savedAt.toUtc().toIso8601String()) {
          throw StateError(
            'This Journal revision request has different facts.',
          );
        }
        result = _manualRevision(jsonDecode(detail) as Map<String, dynamic>);
        return;
      }
      final source = _readJournal(expectedSource.entry.id);
      final currentRevision = manualJournalCurrentRevision(businessId, rootId);
      if (!isCurrentManualJournalRoot(businessId, rootId) ||
          manualJournalCurrentPostingId(businessId, rootId) !=
              expectedSource.entry.id ||
          (currentRevision?.revision ?? 0) != expectedCurrentRevision ||
          source == null ||
          jsonEncode(_journalDraftSnapshot(source)) !=
              jsonEncode(_journalDraftSnapshot(expectedSource))) {
        throw StateError('The current Journal changed. Reopen before editing.');
      }
      requireJournalUnreconciled(businessId, source.entry.id);
      final priorSavedAt = currentRevision?.draft.metadata.updatedAt;
      if (priorSavedAt != null && !savedAt.isAfter(priorSavedAt)) {
        throw StateError(
          'The Journal revision time must follow its saved history.',
        );
      }
      if (replacement.id != requestId ||
          _readJournal(replacement.id) != null ||
          replacement.state != JournalEntryState.draft ||
          replacement.isClosing ||
          replacement.reversesId != null ||
          !savedAt.toUtc().isAfter(source.metadata.updatedAt)) {
        throw StateError('The Journal revision identity or time is invalid.');
      }
      if (replacement.validationErrors.isNotEmpty) {
        throw JournalValidationException(replacement.validationErrors);
      }
      final policies = _database.select(
        'SELECT currency FROM ledger_policies WHERE business_id=?',
        [businessId.value],
      );
      if (policies.length != 1) {
        throw StateError('Configure the ledger currency before saving.');
      }
      if (source.entry.lines.any(
        (line) => line.amount.currency != policies.single['currency'],
      )) {
        throw StateError(
          'Retain the saved currency; foreign amounts require reviewed conversion.',
        );
      }
      // The original editor reopens the current saved correction. Its unchanged
      // unavailable selections remain facts even before that correction posts.
      final retained = (currentRevision?.draft.entry ?? source.entry).lines
          .toList();
      for (final line in replacement.lines) {
        final accounts = _database.select(
          'SELECT * FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, line.accountId.value],
        );
        if (accounts.length != 1 ||
            accounts.single['is_parent'] != 0 ||
            line.amount.currency != policies.single['currency']) {
          throw StateError(
            'Choose valid company accounts and ledger currency.',
          );
        }
        if (accounts.single['status'] != AccountStatus.active.name) {
          final index = retained.indexWhere(
            (old) =>
                old.accountId == line.accountId &&
                old.kind == line.kind &&
                old.amount == line.amount,
          );
          if (index < 0) {
            throw StateError(
              'Retain the saved unavailable account line or choose an active account.',
            );
          }
          retained.removeAt(index);
        }
      }
      _writeJournal(draft);
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'journal.current_saved',
        subjectId: rootId,
        detail: detail,
      );
      result = _manualRevision(jsonDecode(detail) as Map<String, dynamic>);
    });
    return result;
  }

  StoredJournalEntry approveManualJournalCurrentRevision(
    JournalApproval command,
  ) {
    _ensureOpen();
    late StoredJournalEntry result;
    _transaction(() {
      _requireManualJournalOwner(command.businessId, command.actorId);
      final revision = manualJournalRevisionForDraft(
        command.businessId,
        command.journalId,
      );
      if (revision == null || command.expenseIntakeId != null) {
        throw StateError('The current Journal correction is unavailable.');
      }
      final signature = jsonEncode([
        command.requestId.value,
        command.businessId.value,
        command.journalId.value,
        command.expectedRevision,
        command.actorId.value,
        command.approvedAt.toUtc().toIso8601String(),
      ]);
      final retries = _database.select(
        r"SELECT detail FROM ledger_audit WHERE business_id=? AND kind='journal.current_posted' AND json_extract(detail,'$.requestId')=?",
        [command.businessId.value, command.requestId.value],
      );
      if (retries.isNotEmpty) {
        final data = jsonDecode(
          retries.single['detail'] as String,
        ) as Map<String, dynamic>;
        if (data['signature'] != signature) {
          throw StateError(
            'This Journal correction approval has different facts.',
          );
        }
        result = _readJournal(command.journalId)!;
        return;
      }
      final fresh = manualJournalCurrentRevision(
        command.businessId,
        revision.rootId,
      );
      final source = _readJournal(revision.source.entry.id);
      final draft = _readJournal(command.journalId);
      if (!isCurrentManualJournalRoot(command.businessId, revision.rootId) ||
          fresh?.revision != revision.revision ||
          manualJournalCurrentPostingId(command.businessId, revision.rootId) !=
              revision.source.entry.id ||
          source == null ||
          draft == null ||
          jsonEncode(_journalDraftSnapshot(source)) !=
              jsonEncode(_journalDraftSnapshot(revision.source)) ||
          jsonEncode(_journalDraftSnapshot(draft)) !=
              jsonEncode(_journalDraftSnapshot(revision.draft)) ||
          draft.metadata.revision != command.expectedRevision ||
          _readJournal(command.requestId) != null ||
          !command.approvedAt.isAfter(draft.metadata.updatedAt)) {
        throw StateError(
          'The reviewed current Journal changed. Reopen before approval.',
        );
      }
      requireJournalUnreconciled(command.businessId, source.entry.id);
      final matches = _database.select(
        'SELECT acceptance_id FROM bank_statement_matches WHERE business_id=? AND journal_id=? UNION SELECT acceptance_id FROM bank_match_active_ledger_members WHERE business_id=? AND journal_id=?',
        [
          command.businessId.value,
          source.entry.id.value,
          command.businessId.value,
          source.entry.id.value,
        ],
      );
      for (final match in matches) {
        retractStatementMatch(
          businessId: command.businessId,
          acceptanceId: match['acceptance_id'] as String,
          actorId: command.actorId,
          retractedAt: command.approvedAt,
          reason:
              'Journal revision ${revision.rootId.value}:${revision.revision}',
        );
      }
      _writeJournal(
        StoredJournalEntry(
          entry: source.entry.reversal(
            id: command.requestId,
            date: source.entry.date,
            memo: 'Journal revision ${revision.revision}: previous posting',
          ),
          metadata: RecordMetadata.initial(
            recordId: command.requestId,
            businessId: command.businessId,
            originDeviceId: source.metadata.originDeviceId,
            createdAt: command.approvedAt.subtract(
              const Duration(microseconds: 1),
            ),
          ),
        ),
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: command.requestId,
          businessId: command.businessId,
          journalId: command.requestId,
          expectedRevision: 1,
          actorId: command.actorId,
          approvedAt: command.approvedAt,
        ),
        linkedManualJournalRevision: source.entry.id,
      );
      result = _approveJournalInTransaction(
        JournalApproval(
          requestId: command.journalId,
          businessId: command.businessId,
          journalId: command.journalId,
          expectedRevision: command.expectedRevision,
          actorId: command.actorId,
          approvedAt: command.approvedAt,
        ),
        linkedManualJournalRevision: command.journalId,
      );
      _appendAudit(
        businessId: command.businessId,
        actorId: command.actorId,
        at: command.approvedAt,
        kind: 'journal.current_posted',
        subjectId: revision.rootId,
        detail: jsonEncode({
          'rootId': revision.rootId.value,
          'revision': revision.revision,
          'requestId': command.requestId.value,
          'sourceJournalId': source.entry.id.value,
          'journalId': command.journalId.value,
          'signature': signature,
        }),
      );
    });
    return result;
  }

  void _validateManualJournalCurrentRevisionArchive() {
    final saved = <String, StoredManualJournalRevision>{};
    final sources = <String, EntityId>{};
    final requests = <String>{};
    final drafts = <String, StoredManualJournalRevision>{};
    final postedDrafts = <String>{};
    for (final row in _database.select(
      "SELECT * FROM ledger_audit WHERE kind IN ('journal.current_saved','journal.current_posted') ORDER BY sequence",
    )) {
      final data = jsonDecode(row['detail'] as String) as Map<String, dynamic>;
      final business = EntityId.parse(row['business_id'] as String);
      final root = EntityId.parse(data['rootId'] as String);
      final key = '${business.value}/${root.value}';
      final at = DateTime.parse(row['occurred_at'] as String);
      if (row['subject_id'] != root.value) {
        throw StateError('Journal current history identity differs.');
      }
      _requireManualJournalOwner(
        business,
        EntityId.parse(row['actor_id'] as String),
      );
      if (!requests.add(
        '${business.value}/${row['kind']}/${EntityId.parse(data['requestId'] as String).value}',
      )) {
        throw StateError('Journal current history repeats a request.');
      }
      if (row['kind'] == 'journal.current_saved') {
        final revision = _manualRevision(data);
        final original = _readJournal(root);
        final actualSource = _readJournal(revision.source.entry.id);
        final actualDraft = _readJournal(revision.draft.entry.id);
        if (original == null ||
            original.metadata.businessId != business ||
            original.entry.state != JournalEntryState.posted ||
            original.entry.isClosing ||
            original.entry.reversesId != null ||
            _journalHasSourceOwner(business, root) ||
            revision.revision != (saved[key]?.revision ?? 0) + 1 ||
            (saved[key] != null &&
                !at.isAfter(saved[key]!.draft.metadata.updatedAt)) ||
            revision.source.entry.id != (sources[key] ?? root) ||
            revision.source.metadata.businessId != business ||
            revision.source.entry.state != JournalEntryState.posted ||
            revision.draft.metadata.businessId != business ||
            revision.draft.metadata.revision != 1 ||
            revision.draft.metadata.isTombstone ||
            revision.draft.entry.state != JournalEntryState.draft ||
            revision.draft.entry.isClosing ||
            revision.draft.entry.reversesId != null ||
            revision.draft.entry.id.value != data['requestId'] ||
            revision.draft.metadata.createdAt != at ||
            revision.draft.metadata.updatedAt != at ||
            !at.isAfter(revision.source.metadata.updatedAt) ||
            revision.draft.entry.validationErrors.isNotEmpty ||
            actualSource == null ||
            jsonEncode(_journalDraftSnapshot(actualSource)) !=
                jsonEncode(_journalDraftSnapshot(revision.source)) ||
            actualDraft == null ||
            !_manualSavedDraftMatches(actualDraft, revision.draft)) {
          throw StateError(
            'Journal current revision history differs from retained facts.',
          );
        }
        for (final line in revision.draft.entry.lines) {
          if (_database.select(
                'SELECT 1 FROM accounts WHERE business_id=? AND id=?',
                [business.value, line.accountId.value],
              ).length !=
              1) {
            throw StateError('Journal current history has foreign accounts.');
          }
        }
        drafts[revision.draft.entry.id.value] = revision;
        saved[key] = revision;
      } else {
        final revision = saved[key];
        final replacement = _readJournal(
          EntityId.parse(data['journalId'] as String),
        );
        final reversal = _readJournal(
          EntityId.parse(data['requestId'] as String),
        );
        final signature = jsonEncode([
          data['requestId'],
          business.value,
          data['journalId'],
          revision?.draft.metadata.revision,
          row['actor_id'],
          at.toUtc().toIso8601String(),
        ]);
        if (revision == null ||
            revision.source.entry.id != (sources[key] ?? root) ||
            !postedDrafts.add(revision.draft.entry.id.value) ||
            data['revision'] != revision.revision ||
            data['sourceJournalId'] != revision.source.entry.id.value ||
            data['journalId'] != revision.draft.entry.id.value ||
            data['signature'] != signature ||
            replacement == null ||
            replacement.entry.state != JournalEntryState.posted ||
            replacement.metadata.revision != 2 ||
            replacement.metadata.updatedAt != at ||
            reversal == null ||
            reversal.metadata.businessId != business ||
            reversal.entry.state != JournalEntryState.posted ||
            reversal.metadata.revision != 2 ||
            reversal.metadata.updatedAt != at ||
            reversal.entry.reversesId != revision.source.entry.id ||
            reversal.entry.isClosing ||
            LocalAccountingDatabase._calendarDay(reversal.entry.date) !=
                LocalAccountingDatabase._calendarDay(
                  revision.source.entry.date,
                ) ||
            reversal.entry.memo !=
                'Journal revision ${revision.revision}: previous posting' ||
            LocalAccountingDatabase._lineSignature(reversal.entry.lines) !=
                LocalAccountingDatabase._lineSignature(
                  revision.source.entry
                      .reversal(
                        id: reversal.entry.id,
                        date: reversal.entry.date,
                        memo: reversal.entry.memo,
                      )
                      .lines,
                )) {
          throw StateError(
            'Journal current correction postings differ from reviewed facts.',
          );
        }
        for (final id in [replacement.entry.id, reversal.entry.id]) {
          final approval = _database.select(
            'SELECT signature FROM journal_approvals WHERE business_id=? AND request_id=? AND journal_id=?',
            [business.value, id.value, id.value],
          );
          final expected = jsonEncode([
            id.value,
            1,
            row['actor_id'],
            at.toUtc().toIso8601String(),
          ]);
          if (approval.length != 1 ||
              approval.single['signature'] != expected) {
            throw StateError('Journal current correction approval differs.');
          }
        }
        sources[key] = replacement.entry.id;
      }
    }
    for (final entry in drafts.entries) {
      final actual = _readJournal(EntityId.parse(entry.key))!;
      if (actual.entry.state == JournalEntryState.posted &&
          !postedDrafts.contains(entry.key)) {
        throw StateError(
          'Journal current revision has no linked correction approval.',
        );
      }
    }
  }

  bool _manualSavedDraftMatches(
    StoredJournalEntry actual,
    StoredJournalEntry saved,
  ) {
    if (actual.metadata.isTombstone ||
        actual.metadata.businessId != saved.metadata.businessId ||
        actual.metadata.originDeviceId != saved.metadata.originDeviceId ||
        actual.metadata.createdAt != saved.metadata.createdAt ||
        actual.entry.memo != saved.entry.memo ||
        LocalAccountingDatabase._calendarDay(actual.entry.date) !=
            LocalAccountingDatabase._calendarDay(saved.entry.date) ||
        actual.entry.isClosing ||
        actual.entry.reversesId != null ||
        LocalAccountingDatabase._lineSignature(actual.entry.lines) !=
            LocalAccountingDatabase._lineSignature(saved.entry.lines)) {
      return false;
    }
    return actual.entry.state == JournalEntryState.posted
        ? actual.metadata.revision == 2
        : jsonEncode(_journalDraftSnapshot(actual)) ==
              jsonEncode(_journalDraftSnapshot(saved));
  }
}
