part of 'accounting_database.dart';

extension ExpenseRevisionPostingPersistence on LocalAccountingDatabase {
  bool get _hasExpenseRevisionViews =>
      (_database.select('PRAGMA user_version').single['user_version'] as int) >=
      62;
  String get _currentExpenseTable =>
      _hasExpenseRevisionViews ? 'current_expense_intakes' : 'expense_intakes';
  String get _financialExpenseTable => _hasExpenseRevisionViews
      ? 'financial_expense_intakes'
      : 'expense_intakes';
  String get _expensePendingColumn =>
      _hasExpenseRevisionViews ? 'pending_revision' : '0 AS pending_revision';
  String get _pendingExpensePredicate => _hasExpenseRevisionViews
      ? '(journal_id IS NULL OR pending_revision>0)'
      : 'journal_id IS NULL';

  Future<ExpenseIntakeRecord?> getOriginalExpenseIntake(
    EntityId businessId,
    EntityId expenseId, {
    bool includeArchived = false,
  }) async {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM expense_intakes WHERE business_id=? AND id=?${includeArchived ? '' : ' AND archived_at IS NULL'}',
      [businessId.value, expenseId.value],
    );
    if (rows.isEmpty) return null;
    return ExpenseIntakeRecord(
      summary: _expenseSummary(rows.single),
      draft: _expenseRevisionDraft(rows.single['payload'] as String),
    );
  }

  ExpenseRevisionPosting? expenseRevisionPosting(
    EntityId businessId,
    EntityId expenseId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM expense_revision_postings WHERE business_id=? AND expense_id=? ORDER BY revision DESC LIMIT 1',
      [businessId.value, expenseId.value],
    );
    return rows.isEmpty ? null : _expenseRevisionPosting(rows.single);
  }

  ExpenseRevisionPosting _expenseRevisionPosting(Row row) =>
      ExpenseRevisionPosting(
        requestId: EntityId.parse(row['request_id'] as String),
        expenseId: EntityId.parse(row['expense_id'] as String),
        revision: row['revision'] as int,
        sourceJournalId: EntityId.parse(row['source_journal_id'] as String),
        journalId: EntityId.parse(row['journal_id'] as String),
        reversalJournalId: EntityId.parse(row['reversal_journal_id'] as String),
        actorId: EntityId.parse(row['actor_id'] as String),
        approvedAt: DateTime.parse(row['approved_at'] as String),
      );

  String _expenseApprovalSignature(ExpenseRevisionApproval c) => jsonEncode([
    c.expenseId.value,
    c.expectedRevision,
    c.expectedSourceJournalId.value,
    c.journalId.value,
    c.expectedJournalRevision,
    c.actorId.value,
    c.approvedAt.toUtc().toIso8601String(),
  ]);

  /// Existing balanced-journal review supplies accounts; Category text never
  /// supplies a posting account. Recognition, reversal, match correction and
  /// retained source attribution commit as one transaction.
  ExpenseRevisionPosting approveExpenseRevision(
    ExpenseRevisionApproval command,
  ) => _approveExpenseRevision(command);

  ExpenseRevisionPosting approveClaimExpenseRevision(
    ClaimExpenseRevisionApproval command,
  ) => _approveExpenseRevision(
    command.approval,
    claimLineAccounts: command.lineAccounts,
  );

  String _revisionPostingSignature(
    ExpenseRevisionApproval command,
    Map<String, EntityId>? accounts,
  ) => accounts == null
      ? _expenseApprovalSignature(command)
      : jsonEncode([
          _expenseApprovalSignature(command),
          'claimExpense',
          {
            for (final key in accounts.keys.toList()..sort())
              key: accounts[key]!.value,
          },
        ]);

  ExpenseRevisionPosting _approveExpenseRevision(
    ExpenseRevisionApproval command, {
    Map<String, EntityId>? claimLineAccounts,
  }) {
    _ensureOpen();
    late ExpenseRevisionPosting result;
    _transaction(() {
      final owners = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [command.businessId.value],
      );
      if (owners.length != 1 ||
          owners.single['owner_id'] != command.actorId.value) {
        throw StateError(
          'Only the workspace owner can approve this Expense revision.',
        );
      }
      final signature = _revisionPostingSignature(command, claimLineAccounts);
      final retries = _database.select(
        'SELECT * FROM expense_revision_postings WHERE business_id=? AND request_id=?',
        [command.businessId.value, command.requestId.value],
      );
      if (retries.isNotEmpty) {
        if (retries.single['signature'] != signature) {
          throw StateError(
            'This Expense revision approval request has different facts.',
          );
        }
        result = _expenseRevisionPosting(retries.single);
        return;
      }
      final revision = readExpenseRevision(
        command.businessId,
        command.expenseId,
      );
      final sources = _database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND id=?',
        [command.businessId.value, command.expenseId.value],
      );
      final prior = expenseRevisionPosting(
        command.businessId,
        command.expenseId,
      );
      final sourceId =
          prior?.journalId ??
          (sources.isEmpty
              ? null
              : LocalAccountingDatabase._idOrNull(
                  sources.single['journal_id'],
                ));
      if (revision == null ||
          sources.length != 1 ||
          sources.single['archived_at'] != null ||
          revision.revision != command.expectedRevision ||
          revision.sourceExpenseRevision != sources.single['revision'] ||
          sourceId != command.expectedSourceJournalId ||
          revision.sourceJournalId != sourceId ||
          (prior?.revision ?? 0) >= revision.revision ||
          command.approvedAt.isBefore(revision.savedAt)) {
        throw StateError(
          'The reviewed Expense revision changed. Reopen before approval.',
        );
      }
      if ((revision.draft.claimSource != null) != (claimLineAccounts != null)) {
        throw StateError(
          'Claim revisions require their linked recognition and reimbursement review.',
        );
      }
      final original = _readJournal(sourceId!);
      final reviewed = _readJournal(command.journalId);
      if (original == null ||
          original.metadata.businessId != command.businessId ||
          original.entry.state != JournalEntryState.posted ||
          original.entry.isClosing ||
          original.entry.reversesId != null ||
          reviewed == null ||
          reviewed.metadata.businessId != command.businessId ||
          reviewed.metadata.isTombstone ||
          reviewed.entry.state != JournalEntryState.draft ||
          reviewed.metadata.revision != command.expectedJournalRevision ||
          !command.approvedAt.isAfter(original.metadata.updatedAt) ||
          !command.approvedAt.isAfter(reviewed.metadata.updatedAt) ||
          _readJournal(command.requestId) != null) {
        throw StateError(
          'The current posting or reviewed journal changed. Reopen before approval.',
        );
      }
      if (_database.select(
        "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' LIMIT 1",
        [command.businessId.value, sourceId.value],
      ).isNotEmpty) {
        throw StateError(
          'The current posting was reversed. Reopen before approval.',
        );
      }
      requireJournalUnreconciled(command.businessId, sourceId);
      final originalDraft = _expenseRevisionDraft(
        sources.single['payload'] as String,
      );
      _validateExpenseRevisionFacts(
        command.businessId,
        originalDraft,
        revision.before,
        revision.draft,
      );
      if (claimLineAccounts == null) {
        _requireExpenseJournalMatchesDraft(
          command.businessId,
          reviewed.entry,
          revision.draft,
        );
      } else {
        _validateClaimExpenseRow(sources.single);
        _requireTransactionActive(
          command.businessId,
          TransactionRecordKind.claim,
          revision.draft.claimSource!.claimId.value,
        );
        _requireClaimExpenseJournalMatchesDraft(
          command.businessId,
          reviewed.entry,
          revision.draft,
          claimLineAccounts,
        );
      }
      if (_database.select(
        'SELECT 1 FROM expense_intakes WHERE journal_id=? UNION ALL SELECT 1 FROM expense_revision_postings WHERE journal_id=? OR reversal_journal_id=? LIMIT 1',
        [
          command.journalId.value,
          command.journalId.value,
          command.journalId.value,
        ],
      ).isNotEmpty) {
        throw StateError('The reviewed journal already belongs to an Expense.');
      }
      final matches = _database.select(
        'SELECT acceptance_id FROM bank_statement_matches WHERE business_id=? AND journal_id=? UNION SELECT acceptance_id FROM bank_match_active_ledger_members WHERE business_id=? AND journal_id=?',
        [
          command.businessId.value,
          sourceId.value,
          command.businessId.value,
          sourceId.value,
        ],
      );
      for (final match in matches) {
        retractStatementMatch(
          businessId: command.businessId,
          acceptanceId: match['acceptance_id'] as String,
          actorId: command.actorId,
          retractedAt: command.approvedAt,
          reason:
              'Expense revision ${command.expenseId.value}:${revision.revision}',
        );
      }
      _writeJournal(
        StoredJournalEntry(
          entry: original.entry.reversal(
            id: command.requestId,
            date: original.entry.date,
            memo: 'Expense revision ${revision.revision}: previous posting',
          ),
          metadata: RecordMetadata.initial(
            recordId: command.requestId,
            businessId: command.businessId,
            originDeviceId: original.metadata.originDeviceId,
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
        linkedClaimReversal: claimLineAccounts == null ? null : sourceId,
      );
      _approveJournalInTransaction(
        JournalApproval(
          requestId: command.journalId,
          businessId: command.businessId,
          journalId: command.journalId,
          expectedRevision: command.expectedJournalRevision,
          actorId: command.actorId,
          approvedAt: command.approvedAt,
        ),
      );
      _database.execute(
        'INSERT INTO expense_revision_postings(business_id,expense_id,revision,request_id,source_journal_id,journal_id,reversal_journal_id,actor_id,approved_at,journal_revision,signature) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          command.businessId.value,
          command.expenseId.value,
          revision.revision,
          command.requestId.value,
          sourceId.value,
          command.journalId.value,
          command.requestId.value,
          command.actorId.value,
          command.approvedAt.toUtc().toIso8601String(),
          command.expectedJournalRevision,
          signature,
        ],
      );
      _appendAudit(
        businessId: command.businessId,
        actorId: command.actorId,
        at: command.approvedAt,
        kind: 'expense.revision_posted',
        subjectId: command.expenseId,
        detail: jsonEncode({
          'requestId': command.requestId.value,
          'revision': revision.revision,
          'sourceJournalId': sourceId.value,
          'journalId': command.journalId.value,
          'reversalJournalId': command.requestId.value,
        }),
      );
      result = expenseRevisionPosting(command.businessId, command.expenseId)!;
    });
    return result;
  }

  void _requireExpenseJournalMatchesDraft(
    EntityId business,
    JournalEntry entry,
    RecordExpenseDraft draft, {
    bool historical = false,
  }) {
    final amount = Money.fromDecimal(draft.amount, draft.currencyCode);
    final date = parseAccountingInputDate(draft.date);
    final bank = draft.paymentAccountId == null
        ? null
        : paymentLedgerAccount(business, draft.paymentAccountId!);
    final debits = entry.lines
        .where((l) => l.isDebit)
        .fold<BigInt>(
          BigInt.zero,
          (n, l) => n + BigInt.from(l.amount.minorUnits),
        );
    final credits = entry.lines
        .where((l) => l.isCredit && l.accountId == bank)
        .fold<BigInt>(
          BigInt.zero,
          (n, l) => n + BigInt.from(l.amount.minorUnits),
        );
    if (date == null ||
        entry.isClosing ||
        entry.reversesId != null ||
        bank == null ||
        LocalAccountingDatabase._calendarDay(date) !=
            LocalAccountingDatabase._calendarDay(entry.date) ||
        debits != BigInt.from(amount.minorUnits) ||
        credits != debits ||
        entry.lines.any((l) => l.amount.currency != amount.currency)) {
      throw StateError(
        'The reviewed journal must match the Expense date, currency, total and linked payment account.',
      );
    }
  }

  void _requireClaimExpenseJournalMatchesDraft(
    EntityId business,
    JournalEntry entry,
    RecordExpenseDraft draft,
    Map<String, EntityId> accounts, {
    bool historical = false,
  }) {
    final source = draft.claimSource;
    if (source == null ||
        draft.lines.isEmpty ||
        accounts.length != draft.lines.length ||
        draft.lines.any((line) => !accounts.containsKey(line.id))) {
      throw StateError(
        'Review an account for every current Claim Expense row.',
      );
    }
    final chart = {
      for (final row in _database.select(
        'SELECT * FROM accounts WHERE business_id=?',
        [business.value],
      ))
        EntityId.parse(row['id'] as String): _accountFromRow(row).account,
    };
    bool usable(Account? account) =>
        account != null &&
        !account.isParent &&
        account.validationErrors.isEmpty &&
        (historical || account.status == AccountStatus.active);
    final liability = chart[source.liabilityAccountId];
    if (!usable(liability) || liability!.type != AccountType.liability) {
      throw StateError(
        'Review the original Claim liability account in this company.',
      );
    }
    final expected = <EntityId, BigInt>{};
    for (final line in draft.lines) {
      final account = chart[accounts[line.id]];
      if (!usable(account) ||
          !const {
            AccountType.expense,
            AccountType.asset,
          }.contains(account!.type)) {
        throw StateError(
          'Review active expense or asset accounts for every Claim row.',
        );
      }
      final basis = source.lineBases[line.id];
      if (basis == null) {
        throw StateError('Review a tax basis for every Claim row.');
      }
      final amount = line.calculation(draft.currencyCode, basis).total;
      expected.update(
        account.id,
        (n) => n + BigInt.from(amount.minorUnits),
        ifAbsent: () => BigInt.from(amount.minorUnits),
      );
    }
    final actual = <EntityId, BigInt>{};
    var credit = BigInt.zero;
    for (final line in entry.lines) {
      if (line.amount.currency != draft.currencyCode) {
        throw StateError('Claim revision currency changed.');
      }
      if (line.isDebit) {
        actual.update(
          line.accountId,
          (n) => n + BigInt.from(line.amount.minorUnits),
          ifAbsent: () => BigInt.from(line.amount.minorUnits),
        );
      } else {
        if (line.accountId != source.liabilityAccountId) {
          throw StateError(
            'Claim recognition must credit its retained liability account.',
          );
        }
        credit += BigInt.from(line.amount.minorUnits);
      }
    }
    if (entry.isClosing ||
        entry.reversesId != null ||
        formatAccountingInputDate(entry.date) != draft.date ||
        credit !=
            BigInt.from(
              Money.fromDecimal(draft.amount, draft.currencyCode).minorUnits,
            ) ||
        expected.length != actual.length ||
        expected.entries.any((e) => actual[e.key] != e.value)) {
      throw StateError(
        'The reviewed Claim journal differs from its exact row accounts, date, tax and total.',
      );
    }
  }

  void _validateExpenseRevisionPostingArchive() {
    final previous = <String, ExpenseRevisionPosting>{};
    for (final row in _database.select(
      'SELECT * FROM expense_revision_postings ORDER BY business_id,expense_id,revision',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final posting = _expenseRevisionPosting(row);
      final roots = _database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND id=?',
        [business.value, posting.expenseId.value],
      );
      final versions = _database.select(
        'SELECT * FROM expense_revision_drafts WHERE business_id=? AND expense_id=? AND revision=?',
        [business.value, posting.expenseId.value, posting.revision],
      );
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [business.value],
      );
      final key = '${business.value}:${posting.expenseId.value}';
      final prior = previous[key];
      final sourceId =
          prior?.journalId ??
          (roots.isEmpty
              ? null
              : LocalAccountingDatabase._idOrNull(roots.single['journal_id']));
      if (roots.length != 1 ||
          versions.length != 1 ||
          owner.length != 1 ||
          owner.single['owner_id'] != posting.actorId.value ||
          sourceId != posting.sourceJournalId ||
          posting.requestId != posting.reversalJournalId ||
          (prior?.revision ?? 0) >= posting.revision) {
        throw const FormatException(
          'Expense revision posting lineage is inconsistent.',
        );
      }
      final version = _expenseRevision(versions.single);
      final original = _readJournal(posting.sourceJournalId);
      final journal = _readJournal(posting.journalId);
      final reversal = _readJournal(posting.reversalJournalId);
      final command = ExpenseRevisionApproval(
        requestId: posting.requestId,
        businessId: business,
        expenseId: posting.expenseId,
        expectedRevision: posting.revision,
        expectedSourceJournalId: posting.sourceJournalId,
        journalId: posting.journalId,
        expectedJournalRevision: row['journal_revision'] as int,
        actorId: posting.actorId,
        approvedAt: posting.approvedAt,
      );
      Map<String, EntityId>? claimAccounts;
      if (version.draft.claimSource != null) {
        final signature = jsonDecode(row['signature'] as String);
        if (signature is! List ||
            signature.length != 3 ||
            signature[1] != 'claimExpense' ||
            signature[2] is! Map) {
          throw const FormatException(
            'Claim Expense revision approval account evidence is missing.',
          );
        }
        claimAccounts = {
          for (final e in (signature[2] as Map).entries)
            e.key as String: EntityId.parse(e.value as String),
        };
        _validateClaimExpenseRow(roots.single);
      }
      if (version.sourceJournalId != posting.sourceJournalId ||
          posting.approvedAt.isBefore(version.savedAt) ||
          (prior != null && !posting.approvedAt.isAfter(prior.approvedAt)) ||
          original == null ||
          journal == null ||
          reversal == null ||
          original.metadata.businessId != business ||
          journal.metadata.businessId != business ||
          reversal.metadata.businessId != business ||
          original.entry.state != JournalEntryState.posted ||
          journal.entry.state != JournalEntryState.posted ||
          reversal.entry.state != JournalEntryState.posted ||
          journal.metadata.revision != command.expectedJournalRevision + 1 ||
          reversal.metadata.revision != 2 ||
          !journal.metadata.updatedAt.isAtSameMomentAs(posting.approvedAt) ||
          !reversal.metadata.updatedAt.isAtSameMomentAs(posting.approvedAt) ||
          reversal.entry.reversesId != posting.sourceJournalId ||
          LocalAccountingDatabase._calendarDay(reversal.entry.date) !=
              LocalAccountingDatabase._calendarDay(original.entry.date) ||
          reversal.entry.memo !=
              'Expense revision ${posting.revision}: previous posting' ||
          LocalAccountingDatabase._lineSignature(
                reversal.entry.lines,
                reverse: true,
              ) !=
              LocalAccountingDatabase._lineSignature(original.entry.lines) ||
          row['signature'] !=
              _revisionPostingSignature(command, claimAccounts)) {
        throw const FormatException(
          'Expense correction differs from its reviewed revision and postings.',
        );
      }
      if (claimAccounts == null) {
        _requireExpenseJournalMatchesDraft(
          business,
          journal.entry,
          version.draft,
          historical: true,
        );
      } else {
        _requireClaimExpenseJournalMatchesDraft(
          business,
          journal.entry,
          version.draft,
          claimAccounts,
          historical: true,
        );
      }
      for (final pair in [
        (posting.requestId, posting.reversalJournalId, 1),
        (posting.journalId, posting.journalId, command.expectedJournalRevision),
      ]) {
        final approvals = _database.select(
          'SELECT signature FROM journal_approvals WHERE business_id=? AND request_id=? AND journal_id=?',
          [business.value, pair.$1.value, pair.$2.value],
        );
        if (approvals.length != 1 ||
            approvals.single['signature'] !=
                jsonEncode([
                  pair.$2.value,
                  pair.$3,
                  posting.actorId.value,
                  posting.approvedAt.toUtc().toIso8601String(),
                ])) {
          throw const FormatException(
            'Expense correction journal approval is inconsistent.',
          );
        }
      }
      final audits = _database.select(
        "SELECT actor_id,occurred_at,detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='expense.revision_posted' AND json_extract(detail,'\$.requestId')=?",
        [business.value, posting.expenseId.value, posting.requestId.value],
      );
      if (audits.length != 1 ||
          audits.single['actor_id'] != posting.actorId.value ||
          !DateTime.parse(audits.single['occurred_at'] as String)
              .isAtSameMomentAs(posting.approvedAt) ||
          audits.single['detail'] !=
              jsonEncode({
                'requestId': posting.requestId.value,
                'revision': posting.revision,
                'sourceJournalId': posting.sourceJournalId.value,
                'journalId': posting.journalId.value,
                'reversalJournalId': posting.reversalJournalId.value,
              })) {
        throw const FormatException(
          'Expense revision posting audit is inconsistent.',
        );
      }
      previous[key] = posting;
    }
    if (_database
        .select(
          "SELECT 1 FROM ledger_audit a WHERE a.kind='expense.revision_posted' AND NOT EXISTS(SELECT 1 FROM expense_revision_postings p WHERE p.business_id=a.business_id AND p.expense_id=a.subject_id AND p.request_id=json_extract(a.detail,'\$.requestId')) LIMIT 1",
        )
        .isNotEmpty) {
      throw const FormatException(
        'Expense posting audit lacks its retained revision.',
      );
    }
  }

  void _migrateExpenseRevisionPostings() {
    _transaction(() {
      _database.execute('DROP TRIGGER expense_revision_no_update');
      for (final definition in [
        'occurred_on TEXT',
        'amount_minor INTEGER',
        'currency TEXT',
        'payee TEXT',
        'category TEXT',
      ]) {
        _database.execute(
          'ALTER TABLE expense_revision_drafts ADD COLUMN $definition',
        );
      }
      for (final row in _database.select(
        'SELECT * FROM expense_revision_drafts',
      )) {
        final draft = _expenseRevisionDraft(row['payload'] as String);
        final date = parseAccountingInputDate(draft.date);
        final amount = Money.fromDecimal(draft.amount, draft.currencyCode);
        if (date == null || !amount.isPositive) {
          throw const FormatException(
            'Expense revision summary is inconsistent.',
          );
        }
        _database.execute(
          'UPDATE expense_revision_drafts SET occurred_on=?,amount_minor=?,currency=?,payee=?,category=? WHERE business_id=? AND expense_id=? AND revision=?',
          [
            LocalAccountingDatabase._calendarDay(date),
            amount.minorUnits,
            amount.currency,
            draft.payee,
            draft.category,
            row['business_id'],
            row['expense_id'],
            row['revision'],
          ],
        );
      }
      _database.execute(
        "CREATE TRIGGER expense_revision_no_update BEFORE UPDATE ON expense_revision_drafts BEGIN SELECT RAISE(ABORT,'Expense revisions are immutable'); END",
      );
      _database.execute(
        '''CREATE TABLE expense_revision_postings(
        business_id TEXT NOT NULL,expense_id TEXT NOT NULL,revision INTEGER NOT NULL,
        request_id TEXT NOT NULL,source_journal_id TEXT NOT NULL REFERENCES journal_entries(id),
        journal_id TEXT NOT NULL REFERENCES journal_entries(id),
        reversal_journal_id TEXT NOT NULL REFERENCES journal_entries(id),actor_id TEXT NOT NULL,
        approved_at TEXT NOT NULL,journal_revision INTEGER NOT NULL CHECK(journal_revision>0),signature TEXT NOT NULL,
        PRIMARY KEY(business_id,expense_id,revision),UNIQUE(business_id,request_id),
        UNIQUE(business_id,journal_id),UNIQUE(business_id,source_journal_id),
        FOREIGN KEY(business_id,expense_id,revision) REFERENCES expense_revision_drafts(business_id,expense_id,revision))''',
      );
      for (final operation in ['UPDATE', 'DELETE']) {
        _database.execute(
          "CREATE TRIGGER expense_revision_posting_no_${operation.toLowerCase()} BEFORE $operation ON expense_revision_postings BEGIN SELECT RAISE(ABORT,'Expense revision postings are immutable'); END",
        );
      }
      for (final financial in [false, true]) {
        final name = financial
            ? 'financial_expense_intakes'
            : 'current_expense_intakes';
        final headCondition = financial
            ? 'h.revision=p.revision'
            : 'h.revision=(SELECT MAX(r.revision) FROM expense_revision_drafts r WHERE r.business_id=e.business_id AND r.expense_id=e.id)';
        _database.execute(
          '''CREATE VIEW $name AS SELECT
          e.id,e.business_id,e.request_id,e.created_at,
          COALESCE(h.occurred_on,e.occurred_on) AS occurred_on,
          COALESCE(h.amount_minor,e.amount_minor) AS amount_minor,
          COALESCE(h.currency,e.currency) AS currency,
          COALESCE(h.payee,e.payee) AS payee,COALESCE(h.category,e.category) AS category,
          COALESCE(h.payload,e.payload) AS payload,COALESCE(p.journal_id,e.journal_id) AS journal_id,
          e.revision,e.archived_at,COALESCE(h.saved_at,e.state_changed_at) AS state_changed_at,
          CASE WHEN h.revision>COALESCE(p.revision,0) THEN h.revision ELSE 0 END AS pending_revision
          FROM expense_intakes e
          LEFT JOIN expense_revision_postings p ON p.business_id=e.business_id AND p.expense_id=e.id
            AND p.revision=(SELECT MAX(a.revision) FROM expense_revision_postings a WHERE a.business_id=e.business_id AND a.expense_id=e.id)
          LEFT JOIN expense_revision_drafts h ON h.business_id=e.business_id AND h.expense_id=e.id AND $headCondition''',
        );
      }
      _database.execute('PRAGMA user_version=62');
    });
  }
}
