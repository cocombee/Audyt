part of 'accounting_database.dart';

extension ExpenseRevisionPersistence on LocalAccountingDatabase {
  ExpenseRevision? readExpenseRevision(
    EntityId businessId,
    EntityId expenseId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM expense_revision_drafts WHERE business_id=? AND expense_id=? ORDER BY revision DESC LIMIT 1',
      [businessId.value, expenseId.value],
    );
    return rows.isEmpty ? null : _expenseRevision(rows.single);
  }

  List<ExpenseRevision> expenseRevisionHistory(
    EntityId businessId,
    EntityId expenseId,
  ) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM expense_revision_drafts WHERE business_id=? AND expense_id=? ORDER BY revision',
            [businessId.value, expenseId.value],
          )
          .map(_expenseRevision),
    );
  }

  ExpenseRevision _expenseRevision(Row row) => ExpenseRevision(
    requestId: EntityId.parse(row['request_id'] as String),
    expenseId: EntityId.parse(row['expense_id'] as String),
    sourceJournalId: EntityId.parse(row['source_journal_id'] as String),
    sourceExpenseRevision: row['source_revision'] as int,
    revision: row['revision'] as int,
    actorId: EntityId.parse(row['actor_id'] as String),
    savedAt: DateTime.parse(row['saved_at'] as String),
    before: _expenseRevisionDraft(row['before_payload'] as String),
    draft: _expenseRevisionDraft(row['payload'] as String),
  );

  RecordExpenseDraft _expenseRevisionDraft(String payload) =>
      RecordExpenseDraft.fromJson(jsonDecode(payload) as Map<String, dynamic>);

  String _expenseRevisionPayload(RecordExpenseDraft draft) =>
      jsonEncode(draft.toJson());

  /// Persist the edit and its audit together, without inferring posting accounts
  /// from Category text or changing existing recognition/payment allocations.
  ExpenseRevision saveExpenseRevision({
    required EntityId businessId,
    required EntityId expenseId,
    required EntityId requestId,
    required EntityId actorId,
    required EntityId expectedSourceJournalId,
    required int expectedSourceExpenseRevision,
    required int expectedRevision,
    required RecordExpenseDraft expected,
    required RecordExpenseDraft replacement,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    final checked = _expenseRevisionDraft(_expenseRevisionPayload(replacement));
    late ExpenseRevision result;
    _transaction(() {
      final owners = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId.value],
      );
      if (owners.length != 1 || owners.single['owner_id'] != actorId.value) {
        throw StateError('Only the workspace owner can revise this Expense.');
      }
      final retries = _database.select(
        'SELECT * FROM expense_revision_drafts WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retries.isNotEmpty) {
        final saved = _expenseRevision(retries.single);
        if (saved.expenseId != expenseId ||
            saved.sourceJournalId != expectedSourceJournalId ||
            saved.sourceExpenseRevision != expectedSourceExpenseRevision ||
            saved.revision != expectedRevision + 1 ||
            saved.actorId != actorId ||
            !saved.savedAt.isAtSameMomentAs(savedAt) ||
            _expenseRevisionPayload(saved.before) !=
                _expenseRevisionPayload(expected) ||
            _expenseRevisionPayload(saved.draft) !=
                _expenseRevisionPayload(checked)) {
          throw StateError(
            'This revision request was saved with different facts.',
          );
        }
        result = saved;
        return;
      }
      final sources = _database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND id=?',
        [businessId.value, expenseId.value],
      );
      final posting = expenseRevisionPosting(businessId, expenseId);
      final currentJournal =
          posting?.journalId ??
          (sources.isEmpty
              ? null
              : LocalAccountingDatabase._idOrNull(
                  sources.single['journal_id'],
                ));
      if (sources.length != 1 ||
          sources.single['archived_at'] != null ||
          currentJournal != expectedSourceJournalId ||
          sources.single['revision'] != expectedSourceExpenseRevision) {
        throw StateError('The source Expense changed. Reopen before editing.');
      }
      final source = sources.single;
      final journal = _database.select(
        "SELECT state FROM journal_entries WHERE business_id=? AND id=?",
        [businessId.value, expectedSourceJournalId.value],
      );
      if (journal.length != 1 ||
          journal.single['state'] != 'posted' ||
          _database.select(
            "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' LIMIT 1",
            [businessId.value, expectedSourceJournalId.value],
          ).isNotEmpty) {
        throw StateError(
          'The current posting is unavailable. Reopen the Expense.',
        );
      }
      requireJournalUnreconciled(businessId, expectedSourceJournalId);
      final original = _expenseRevisionDraft(source['payload'] as String);
      final head = readExpenseRevision(businessId, expenseId);
      final current = head?.draft ?? original;
      if ((head != null &&
              (posting?.revision ?? 0) < head.revision &&
              (head.sourceJournalId != expectedSourceJournalId ||
                  head.sourceExpenseRevision !=
                      expectedSourceExpenseRevision)) ||
          (head?.revision ?? 0) != expectedRevision ||
          _expenseRevisionPayload(current) !=
              _expenseRevisionPayload(expected)) {
        throw StateError('The current Expense changed. Reopen before saving.');
      }
      var lastChange =
          head?.savedAt ??
          DateTime.parse(
            (source['state_changed_at'] ?? source['created_at']) as String,
          );
      if (posting != null && posting.approvedAt.isAfter(lastChange)) {
        lastChange = posting.approvedAt;
      }
      if (savedAt.isBefore(lastChange)) {
        throw StateError(
          'An Expense revision cannot precede its saved source.',
        );
      }
      _validateExpenseRevisionFacts(businessId, original, current, checked);
      // All retained versions participate: removing and then re-adding a file
      // must not allow another original to take its stable identity.
      final retained = [
        original,
        for (final r in expenseRevisionHistory(businessId, expenseId)) r.draft,
      ];
      for (final prior in retained) {
        _requireExpenseRevisionOriginals(prior, checked);
      }
      _database.execute(
        'INSERT INTO expense_revision_drafts(business_id,expense_id,source_journal_id,source_revision,revision,request_id,actor_id,saved_at,before_payload,payload,occurred_on,amount_minor,currency,payee,category) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          expenseId.value,
          expectedSourceJournalId.value,
          expectedSourceExpenseRevision,
          expectedRevision + 1,
          requestId.value,
          actorId.value,
          savedAt.toUtc().toIso8601String(),
          _expenseRevisionPayload(current),
          _expenseRevisionPayload(checked),
          LocalAccountingDatabase._calendarDay(
            parseAccountingInputDate(checked.date)!,
          ),
          Money.fromDecimal(checked.amount, checked.currencyCode).minorUnits,
          checked.currencyCode,
          checked.payee,
          checked.category,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'expense.revision_saved',
        subjectId: expenseId,
        detail: jsonEncode({
          'requestId': requestId.value,
          'revision': expectedRevision + 1,
          'sourceJournalId': expectedSourceJournalId.value,
        }),
      );
      result = readExpenseRevision(businessId, expenseId)!;
    });
    return result;
  }

  void _requireExpenseRevisionOriginals(
    RecordExpenseDraft before,
    RecordExpenseDraft after,
  ) {
    final hashes = {
      for (final file in before.attachments)
        file.originalId: file.originalSha256,
    };
    if (after.attachments.any(
      (file) =>
          hashes.containsKey(file.originalId) &&
          hashes[file.originalId] != file.originalSha256,
    )) {
      throw StateError('Saved original attachment bytes cannot be replaced.');
    }
  }

  void _validateExpenseRevisionFacts(
    EntityId businessId,
    RecordExpenseDraft original,
    RecordExpenseDraft before,
    RecordExpenseDraft after, {
    bool historical = false,
  }) {
    final date = parseAccountingInputDate(after.date);
    if (date == null ||
        after.taxMode == null ||
        after.lines.isEmpty ||
        !Money.fromDecimal(after.amount, after.currencyCode).isPositive ||
        after.category.trim().isEmpty) {
      throw StateError(
        'Review the Expense date, categories, tax basis and lines.',
      );
    }
    if (original.submissionId != after.submissionId ||
        original.currencyCode != after.currencyCode ||
        jsonEncode(original.recurrence?.toJson()) !=
            jsonEncode(after.recurrence?.toJson())) {
      throw StateError(
        'A revision retains the Expense identity, currency and recurring source.',
      );
    }
    Map<String, Object?>? provenance(RecordExpenseDraft draft) {
      final source = draft.claimSource?.toJson();
      source?.remove('lineBases');
      return source;
    }

    if (jsonEncode(provenance(original)) != jsonEncode(provenance(after))) {
      throw StateError(
        'A revision retains the original Claim and claimant identity.',
      );
    }
    if (original.claimSource != null) {
      if (after.paymentAccountId != null ||
          after.paymentAccount != original.paymentAccount) {
        throw StateError(
          'Claim recognition retains its claimant liability; reimbursement is separate.',
        );
      }
    } else if (!historical) {
      final account = readPaymentAccounts(businessId)
          .where((a) => a.id == after.paymentAccountId)
          .firstOrNull;
      if (account == null || account.currency.code != after.currencyCode) {
        throw StateError(
          'The payment account is unavailable or uses another currency.',
        );
      }
    }
    _validateExpenseTaxSnapshots(
      businessId,
      after,
      existing: before,
      historical: historical,
    );
    _requireExpenseRevisionOriginals(before, after);
  }

  void _validateExpenseRevisionArchive() {
    final chains = <String, List<ExpenseRevision>>{};
    for (final row in _database.select(
      'SELECT * FROM expense_revision_drafts ORDER BY business_id,expense_id,revision',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final version = _expenseRevision(row);
      final source = _database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND id=?',
        [business.value, version.expenseId.value],
      );
      final owners = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [business.value],
      );
      final journals = _database.select(
        "SELECT state FROM journal_entries WHERE business_id=? AND id=?",
        [business.value, version.sourceJournalId.value],
      );
      final hasPostings = _archiveTableNames().contains(
        'expense_revision_postings',
      );
      final priorPostings = hasPostings
          ? _database.select(
              'SELECT journal_id,approved_at FROM expense_revision_postings WHERE business_id=? AND expense_id=? AND revision<? ORDER BY revision DESC LIMIT 1',
              [business.value, version.expenseId.value, version.revision],
            )
          : const <Row>[];
      final expectedSource = priorPostings.isNotEmpty
          ? priorPostings.single['journal_id']
          : source.firstOrNull?['journal_id'];
      if (source.length != 1 ||
          owners.length != 1 ||
          owners.single['owner_id'] != version.actorId.value ||
          expectedSource != version.sourceJournalId.value ||
          source.single['revision'] != version.sourceExpenseRevision ||
          source.single['archived_at'] != null ||
          journals.length != 1 ||
          journals.single['state'] != 'posted') {
        throw const FormatException(
          'Expense revision source ownership is inconsistent.',
        );
      }
      final original = _expenseRevisionDraft(
        source.single['payload'] as String,
      );
      if (row.containsKey('occurred_on') &&
          (row['occurred_on'] !=
                  LocalAccountingDatabase._calendarDay(
                    parseAccountingInputDate(version.draft.date)!,
                  ) ||
              row['amount_minor'] !=
                  Money.fromDecimal(
                    version.draft.amount,
                    version.draft.currencyCode,
                  ).minorUnits ||
              row['currency'] != version.draft.currencyCode ||
              row['payee'] != version.draft.payee ||
              row['category'] != version.draft.category)) {
        throw const FormatException(
          'Expense revision summary differs from its saved facts.',
        );
      }
      final chain = chains.putIfAbsent(
        '${business.value}:${version.expenseId.value}',
        () => [],
      );
      final prior = chain.lastOrNull;
      final previous = prior?.draft ?? original;
      var changed =
          prior?.savedAt ??
          DateTime.parse(
            (source.single['state_changed_at'] ?? source.single['created_at'])
                as String,
          );
      if (priorPostings.isNotEmpty) {
        final approved = DateTime.parse(
          priorPostings.single['approved_at'] as String,
        );
        if (approved.isAfter(changed)) changed = approved;
      }
      if (version.revision != chain.length + 1 ||
          (prior != null &&
              prior.sourceExpenseRevision != version.sourceExpenseRevision) ||
          version.savedAt.isBefore(changed) ||
          _expenseRevisionPayload(version.before) !=
              _expenseRevisionPayload(previous)) {
        throw const FormatException(
          'Expense revision history is inconsistent.',
        );
      }
      _validateExpenseRevisionFacts(
        business,
        original,
        previous,
        version.draft,
        historical: true,
      );
      for (final retained in [original, for (final item in chain) item.draft]) {
        _requireExpenseRevisionOriginals(retained, version.draft);
      }
      final audit = _database.select(
        "SELECT actor_id,occurred_at,detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='expense.revision_saved' AND json_extract(detail,'\$.requestId')=?",
        [business.value, version.expenseId.value, version.requestId.value],
      );
      if (audit.length != 1 ||
          audit.single['actor_id'] != version.actorId.value ||
          !DateTime.parse(audit.single['occurred_at'] as String)
              .isAtSameMomentAs(version.savedAt) ||
          audit.single['detail'] !=
              jsonEncode({
                'requestId': version.requestId.value,
                'revision': version.revision,
                'sourceJournalId': version.sourceJournalId.value,
              })) {
        throw const FormatException('Expense revision audit is inconsistent.');
      }
      chain.add(version);
    }
    if (_database
        .select(
          "SELECT 1 FROM ledger_audit a WHERE a.kind='expense.revision_saved' AND NOT EXISTS (SELECT 1 FROM expense_revision_drafts r WHERE r.business_id=a.business_id AND r.expense_id=a.subject_id AND r.request_id=json_extract(a.detail,'\$.requestId')) LIMIT 1",
        )
        .isNotEmpty) {
      throw const FormatException(
        'Expense revision audit lacks its retained version.',
      );
    }
  }

  void _migrateExpenseRevisions() {
    _transaction(() {
      _database.execute(
        '''CREATE TABLE expense_revision_drafts(
        business_id TEXT NOT NULL,expense_id TEXT NOT NULL REFERENCES expense_intakes(id),
        source_journal_id TEXT NOT NULL REFERENCES journal_entries(id),
        source_revision INTEGER NOT NULL CHECK(source_revision>0),
        revision INTEGER NOT NULL CHECK(revision>0),request_id TEXT NOT NULL,
        actor_id TEXT NOT NULL,saved_at TEXT NOT NULL,before_payload TEXT NOT NULL,payload TEXT NOT NULL,
        PRIMARY KEY(business_id,expense_id,revision),UNIQUE(business_id,request_id))''',
      );
      for (final operation in ['UPDATE', 'DELETE']) {
        _database.execute(
          "CREATE TRIGGER expense_revision_no_${operation.toLowerCase()} BEFORE $operation ON expense_revision_drafts BEGIN SELECT RAISE(ABORT,'Expense revisions are immutable'); END",
        );
      }
      _database.execute('PRAGMA user_version=61');
    });
  }
}
