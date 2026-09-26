part of 'accounting_database.dart';

extension AccountReconciliationPreparation on LocalAccountingDatabase {
  /// Read one account period without requiring or creating a bank import.
  AccountReconciliationSnapshot prepareAccountReconciliation({
    required EntityId businessId,
    required String paymentAccountId,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    Set<String> selectedMovementIds = const {},
    Set<String> openingOutstandingIds = const {},
  }) {
    _ensureOpen();
    DateTime day(DateTime value) =>
        DateTime.utc(value.year, value.month, value.day);
    final start = day(startsOn);
    final end = day(endsOn);
    if (end.isBefore(start)) {
      throw ArgumentError('Reconciliation end must not precede its start.');
    }
    late AccountReconciliationSnapshot snapshot;
    _joinTransaction(() {
      final payment = _database.select(
        'SELECT currency FROM payment_accounts WHERE business_id=? AND id=?',
        [businessId.value, paymentAccountId],
      );
      if (payment.isEmpty) throw StateError('Payment account is unavailable.');
      final currency = payment.single['currency'] as String;
      if (openingBalance.currency != currency ||
          closingBalance.currency != currency) {
        throw ArgumentError(
          'Reconciliation balances differ from account currency.',
        );
      }
      // Reuse the indexed, validated posted ledger reader. Its boundary is
      // exclusive; the next day includes the entire selected end date.
      final ledger = _openingLedgerMovements(
        businessId,
        paymentAccountId,
        end.add(const Duration(days: 1)),
        currency,
      );
      final previousId = latestReconciliationId(businessId, paymentAccountId);
      Money recordedOpening;
      DateTime? requiredStart;
      var previousUnchanged = true;
      Set<String> cleared;
      if (previousId == null) {
        final opening = ledger.where((m) => m.date.isBefore(start)).toList();
        recordedOpening = _openingAfterOutstanding(
          opening,
          openingOutstandingIds,
          currency,
        );
        cleared = opening
            .where((m) => !openingOutstandingIds.contains(m.id))
            .map((m) => m.id)
            .toSet();
      } else {
        if (openingOutstandingIds.isNotEmpty) {
          throw StateError(
            'Opening outstanding selection applies only to the first reconciliation.',
          );
        }
        final previous = _database.select(
          'SELECT closing_minor,currency,ends_on FROM bank_reconciliations WHERE business_id=? AND id=?',
          [businessId.value, previousId],
        ).single;
        if (previous['currency'] != currency) {
          throw StateError('Previous reconciliation currency differs.');
        }
        recordedOpening = Money.fromMinor(
          previous['closing_minor'] as int,
          currency,
        );
        requiredStart = day(DateTime.parse(previous['ends_on'] as String))
            .add(const Duration(days: 1));
        previousUnchanged = _reconciliationLedgerChanges(
          businessId,
          previousId,
        ).unchanged;
        final classification = _reconciliationClassification(
          businessId,
          previousId,
        );
        if (classification == null) {
          throw StateError(
            'Previous reconciliation ledger evidence is unavailable.',
          );
        }
        previousUnchanged = previousUnchanged && classification.agrees;
        cleared = classification.cleared.map((m) => m.id).toSet();
      }
      final eligible = ledger.where((m) => !cleared.contains(m.id)).toList();
      snapshot = AccountReconciliationSnapshot(
        paymentAccountId: paymentAccountId,
        startsOn: start,
        endsOn: end,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        recordedOpening: recordedOpening,
        previousId: previousId,
        requiredStart: requiredStart,
        previousLedgerUnchanged: previousUnchanged,
        ledgerMovements: ledger,
        openingOutstandingIds: openingOutstandingIds,
        review: AccountReconciliationReview.evaluate(
          openingBalance: openingBalance,
          closingBalance: closingBalance,
          eligibleMovements: eligible,
          selectedIds: selectedMovementIds,
        ),
        ledgerFingerprint: _accountLedgerFingerprint(ledger, currency),
      );
    });
    return snapshot;
  }
}

extension AccountReconciliationPersistence on LocalAccountingDatabase {
  String _accountLedgerFingerprint(
    List<OpeningLedgerMovement> rows,
    String currency,
  ) => sha256
      .convert(utf8.encode(_accountLedgerJson(rows, currency)))
      .toString();

  String _accountLedgerJson(
    List<OpeningLedgerMovement> rows,
    String currency,
  ) => jsonEncode({
    'version': 1,
    'currency': currency,
    'movements': [
      for (final m in rows)
        {
          'id': m.id,
          'date': m.date.toUtc().toIso8601String(),
          'memo': m.memo,
          'minor': m.amount.minorUnits,
        },
    ],
  });

  void _migrateAccountReconciliation() {
    // SQLite's create/copy/drop/rename migration. Enforcement is restored even
    // when validation, replacement or object recreation rolls back.
    if (!_database.autocommit) {
      throw StateError('Schema migration requires its own transaction.');
    }
    if (_database.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError(
        'Repair existing reconciliation links before migrating.',
      );
    }
    final objects = _database
        .select(
          "SELECT sql FROM sqlite_master WHERE tbl_name='bank_reconciliations' AND type IN ('index','trigger') AND sql IS NOT NULL",
        )
        .map((r) => r['sql'] as String)
        .toList();
    _database.execute('PRAGMA foreign_keys=OFF');
    try {
      _transaction(() {
        for (final name in [
          'account_reconciliation_drafts',
          'bank_reconciliation_cleared_movements',
        ]) {
          if (_database.select(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            [name],
          ).isNotEmpty) {
            if (_database.select('SELECT 1 FROM $name LIMIT 1').isNotEmpty) {
              throw StateError('Account-period data requires schema 60.');
            }
            _database.execute('DROP TABLE $name');
          }
        }
        _database.execute(
          'CREATE TABLE bank_reconciliations_v60(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,payment_account_id TEXT NOT NULL,statement_id TEXT REFERENCES bank_statement_imports(id),starts_on TEXT NOT NULL,ends_on TEXT NOT NULL,opening_minor INTEGER NOT NULL,closing_minor INTEGER NOT NULL,currency TEXT NOT NULL,actor_id TEXT NOT NULL,approved_at TEXT NOT NULL,previous_id TEXT REFERENCES bank_reconciliations(id),opening_evidence TEXT NOT NULL,payload TEXT NOT NULL,FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        _database.execute(
          'INSERT INTO bank_reconciliations_v60 SELECT * FROM bank_reconciliations',
        );
        _database.execute('DROP TABLE bank_reconciliations');
        _database.execute(
          'ALTER TABLE bank_reconciliations_v60 RENAME TO bank_reconciliations',
        );
        for (final sql in objects) {
          _database.execute(sql);
        }
        _database.execute(
          'CREATE TABLE bank_reconciliation_cleared_movements(completion_id TEXT NOT NULL REFERENCES bank_reconciliations(id),journal_id TEXT NOT NULL,line_index INTEGER NOT NULL,PRIMARY KEY(completion_id,journal_id,line_index),FOREIGN KEY(journal_id,line_index) REFERENCES journal_lines(journal_id,line_index))',
        );
        for (final op in ['UPDATE', 'DELETE']) {
          _database.execute(
            "CREATE TRIGGER bank_reconciliation_cleared_no_${op.toLowerCase()} BEFORE $op ON bank_reconciliation_cleared_movements BEGIN SELECT RAISE(ABORT,'Approved clearance is immutable'); END",
          );
        }
        _database.execute(
          'CREATE TABLE account_reconciliation_drafts(business_id TEXT NOT NULL,payment_account_id TEXT NOT NULL,starts_on TEXT NOT NULL,ends_on TEXT NOT NULL,opening_minor INTEGER NOT NULL,closing_minor INTEGER NOT NULL,currency TEXT NOT NULL,opening_evidence TEXT NOT NULL,selected_ids TEXT NOT NULL,outstanding_ids TEXT NOT NULL,previous_id TEXT REFERENCES bank_reconciliations(id),revision INTEGER NOT NULL CHECK(revision>0),saved_at TEXT NOT NULL,attachments TEXT NOT NULL,PRIMARY KEY(business_id,payment_account_id),FOREIGN KEY(business_id,payment_account_id) REFERENCES payment_accounts(business_id,id))',
        );
        if (_database.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw StateError('Reconciliation migration broke a record link.');
        }
        _database.execute('PRAGMA user_version=60');
      });
    } finally {
      _database.execute('PRAGMA foreign_keys=ON');
    }
  }

  Set<String> _accountSelection(Object? raw) {
    if (raw is! List || raw.any((id) => id is! String || id.isEmpty)) {
      throw const FormatException('Reconciliation selection is inconsistent.');
    }
    final ids = raw.cast<String>();
    if (ids.toSet().length != ids.length) {
      throw const FormatException('Duplicate reconciliation selection.');
    }
    return ids.toSet();
  }

  AccountReconciliationDraft? readAccountReconciliationDraft(
    EntityId businessId,
    String paymentAccountId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM account_reconciliation_drafts WHERE business_id=? AND payment_account_id=?',
      [businessId.value, paymentAccountId],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final payment = _database.select(
      'SELECT currency FROM payment_accounts WHERE business_id=? AND id=?',
      [businessId.value, paymentAccountId],
    );
    final start = DateTime.parse(r['starts_on'] as String),
        end = DateTime.parse(r['ends_on'] as String);
    final selected = _accountSelection(jsonDecode(r['selected_ids'] as String));
    final outstanding = _accountSelection(
      jsonDecode(r['outstanding_ids'] as String),
    );
    final previous = r['previous_id'] as String?;
    if (payment.length != 1 ||
        payment.single['currency'] != r['currency'] ||
        end.isBefore(start) ||
        (r['revision'] as int) < 1 ||
        (previous != null &&
            _database.select(
              'SELECT 1 FROM bank_reconciliations WHERE id=? AND business_id=? AND payment_account_id=?',
              [previous, businessId.value, paymentAccountId],
            ).isEmpty)) {
      throw const FormatException(
        'Saved account reconciliation is inconsistent.',
      );
    }
    return AccountReconciliationDraft(
      paymentAccountId: paymentAccountId,
      startsOn: start,
      endsOn: end,
      openingBalance: Money.fromMinor(
        r['opening_minor'] as int,
        r['currency'] as String,
      ),
      closingBalance: Money.fromMinor(
        r['closing_minor'] as int,
        r['currency'] as String,
      ),
      openingEvidence: r['opening_evidence'] as String,
      expectedPreviousId: previous,
      revision: r['revision'] as int,
      savedAt: DateTime.parse(r['saved_at'] as String),
      selectedIds: selected,
      openingOutstandingIds: outstanding,
      attachments: _readReconciliationAttachments(
        jsonDecode(r['attachments'] as String),
      ),
    );
  }

  AccountReconciliationDraft saveAccountReconciliationDraft({
    required EntityId businessId,
    required String paymentAccountId,
    required EntityId actorId,
    required int expectedRevision,
    required String? expectedPreviousId,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    required DateTime savedAt,
    String openingEvidence = '',
    Set<String> selectedIds = const {},
    Set<String> openingOutstandingIds = const {},
    List<ReceiptAttachment> attachments = const [],
  }) {
    _ensureOpen();
    late AccountReconciliationDraft result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final current = readAccountReconciliationDraft(
        businessId,
        paymentAccountId,
      );
      if ((current?.revision ?? 0) != expectedRevision) {
        throw StateError(
          'The account reconciliation draft changed. Reopen before saving.',
        );
      }
      final fresh = prepareAccountReconciliation(
        businessId: businessId,
        paymentAccountId: paymentAccountId,
        startsOn: startsOn,
        endsOn: endsOn,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        selectedMovementIds: selectedIds,
        openingOutstandingIds: openingOutstandingIds,
      );
      if (fresh.previousId != expectedPreviousId ||
          fresh.review.unresolved.isNotEmpty) {
        throw StateError(
          'Reconciliation source or selection changed. Review again.',
        );
      }
      final files = _reconciliationAttachmentsJson(attachments);
      _database.execute(
        'INSERT INTO account_reconciliation_drafts(business_id,payment_account_id,starts_on,ends_on,opening_minor,closing_minor,currency,opening_evidence,selected_ids,outstanding_ids,previous_id,revision,saved_at,attachments) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(business_id,payment_account_id) DO UPDATE SET starts_on=excluded.starts_on,ends_on=excluded.ends_on,opening_minor=excluded.opening_minor,closing_minor=excluded.closing_minor,currency=excluded.currency,opening_evidence=excluded.opening_evidence,selected_ids=excluded.selected_ids,outstanding_ids=excluded.outstanding_ids,previous_id=excluded.previous_id,revision=excluded.revision,saved_at=excluded.saved_at,attachments=excluded.attachments',
        [
          businessId.value,
          paymentAccountId,
          fresh.startsOn.toIso8601String(),
          fresh.endsOn.toIso8601String(),
          openingBalance.minorUnits,
          closingBalance.minorUnits,
          openingBalance.currency,
          openingEvidence,
          jsonEncode(selectedIds.toList()..sort()),
          jsonEncode(openingOutstandingIds.toList()..sort()),
          expectedPreviousId,
          expectedRevision + 1,
          savedAt.toUtc().toIso8601String(),
          files,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'reconciliation.account_draft_saved',
        subjectId: businessId,
        detail: jsonEncode({
          'account': paymentAccountId,
          'revision': expectedRevision + 1,
        }),
      );
      result = readAccountReconciliationDraft(businessId, paymentAccountId)!;
    });
    return result;
  }

  void approveAccountReconciliation({
    required EntityId requestId,
    required EntityId businessId,
    required String paymentAccountId,
    required EntityId actorId,
    required DateTime approvedAt,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    required Set<String> selectedMovementIds,
    required String expectedLedgerFingerprint,
    required String? expectedPreviousId,
    int? expectedDraftRevision,
    String firstOpeningEvidence = '',
    Set<String> openingOutstandingIds = const {},
    List<ReceiptAttachment> attachments = const [],
  }) {
    _ensureOpen();
    String day(DateTime d) =>
        DateTime.utc(d.year, d.month, d.day).toIso8601String();
    final payload = jsonEncode({
      'mode': 'account',
      'business': businessId.value,
      'account': paymentAccountId,
      'actor': actorId.value,
      'start': day(startsOn),
      'end': day(endsOn),
      'opening': openingBalance.minorUnits,
      'closing': closingBalance.minorUnits,
      'currency': openingBalance.currency,
      'closingCurrency': closingBalance.currency,
      'previous': expectedPreviousId,
      'evidence': firstOpeningEvidence.trim(),
      'selected': selectedMovementIds.toList()..sort(),
      'ledgerFingerprint': expectedLedgerFingerprint,
      'draftRevision': expectedDraftRevision,
      if (openingOutstandingIds.isNotEmpty)
        'openingOutstanding': openingOutstandingIds.toList()..sort(),
      if (attachments.isNotEmpty)
        'attachments': jsonDecode(_reconciliationAttachmentsJson(attachments)),
    });
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final old = _database.select(
        'SELECT payload FROM bank_reconciliations WHERE id=?',
        [requestId.value],
      );
      if (old.isNotEmpty) {
        if (old.single['payload'] != payload) {
          throw StateError('Approval request changed.');
        }
        return;
      }
      final draft = readAccountReconciliationDraft(
        businessId,
        paymentAccountId,
      );
      if (draft?.revision != expectedDraftRevision) {
        throw StateError(
          'The saved account reconciliation changed. Review again.',
        );
      }
      final fresh = prepareAccountReconciliation(
        businessId: businessId,
        paymentAccountId: paymentAccountId,
        startsOn: startsOn,
        endsOn: endsOn,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        selectedMovementIds: selectedMovementIds,
        openingOutstandingIds: openingOutstandingIds,
      );
      if (fresh.previousId != expectedPreviousId ||
          fresh.ledgerFingerprint != expectedLedgerFingerprint) {
        throw StateError(
          'Reconciliation ledger or previous period changed. Review again.',
        );
      }
      if (!fresh.reviewAgrees) {
        throw StateError(
          'Resolve opening, period, selection and closing differences first.',
        );
      }
      if (fresh.previousId == null && firstOpeningEvidence.trim().isEmpty) {
        throw ArgumentError(
          'Document the first opening balance and outstanding items.',
        );
      }
      if (fresh.previousId != null) {
        final previous = _database.select(
          'SELECT approved_at FROM bank_reconciliations WHERE id=?',
          [fresh.previousId],
        ).single;
        if (approvedAt.toUtc().isBefore(
          DateTime.parse(previous['approved_at'] as String),
        )) {
          throw StateError('Approval precedes its previous period approval.');
        }
      }
      _database.execute(
        'INSERT INTO bank_reconciliations(id,business_id,payment_account_id,statement_id,starts_on,ends_on,opening_minor,closing_minor,currency,actor_id,approved_at,previous_id,opening_evidence,payload) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          requestId.value,
          businessId.value,
          paymentAccountId,
          null,
          day(startsOn),
          day(endsOn),
          openingBalance.minorUnits,
          closingBalance.minorUnits,
          openingBalance.currency,
          actorId.value,
          approvedAt.toUtc().toIso8601String(),
          fresh.previousId,
          firstOpeningEvidence.trim(),
          payload,
        ],
      );
      _database.execute(
        'INSERT INTO bank_reconciliation_ledger_snapshots(completion_id,payload) VALUES(?,?)',
        [
          requestId.value,
          _accountLedgerJson(fresh.ledgerMovements, openingBalance.currency),
        ],
      );
      for (final movement in fresh.review.selected) {
        final split = movement.id.lastIndexOf(':');
        _database.execute(
          'INSERT INTO bank_reconciliation_cleared_movements(completion_id,journal_id,line_index) VALUES(?,?,?)',
          [
            requestId.value,
            movement.id.substring(0, split),
            int.parse(movement.id.substring(split + 1)),
          ],
        );
      }
      final classification = _reconciliationClassification(
        businessId,
        requestId.value,
      );
      if (classification == null || !classification.agrees) {
        throw StateError(
          'Selected ledger evidence does not support the closing balance.',
        );
      }
      _database.execute(
        'DELETE FROM account_reconciliation_drafts WHERE business_id=? AND payment_account_id=?',
        [businessId.value, paymentAccountId],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvedAt,
        kind: 'reconciliation.account_approved',
        subjectId: requestId,
        detail: jsonEncode({
          'account': paymentAccountId,
          'selected': selectedMovementIds.length,
        }),
      );
    });
  }

  List<StatementReconciliationHistory> accountReconciliationHistory(
    EntityId businessId,
    String paymentAccountId,
  ) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT c.*,r.reopened_at,r.actor_id AS reopened_by,r.reason AS reopening_reason FROM bank_reconciliations c LEFT JOIN bank_reconciliation_reopenings r ON r.completion_id=c.id WHERE c.business_id=? AND c.payment_account_id=? ORDER BY c.approved_at DESC,c.id DESC',
            [businessId.value, paymentAccountId],
          )
          .map(_reconciliationHistoryFromRow),
    );
  }

  ReconciliationEvidence _accountReconciliationEvidence(
    EntityId businessId,
    String id,
    Map<String, Object?> row,
  ) {
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final ledger = reconciliationLedgerSnapshot(businessId, id);
    if (ledger == null || payload['mode'] != 'account') {
      throw StateError(
        'Approved account-period ledger evidence is unavailable.',
      );
    }
    final selected = _accountSelection(payload['selected']);
    final outstanding = _accountSelection(
      payload['openingOutstanding'] ?? const [],
    );
    final byId = {for (final m in ledger.movements) m.id: m};
    if (!byId.keys.toSet().containsAll({...selected, ...outstanding})) {
      throw StateError('Approved account selection is unavailable.');
    }
    return ReconciliationEvidence(
      filename: '',
      sourceDigest: '',
      matches: [],
      isAccountPeriod: true,
      selectedMovements: [
        for (final m in ledger.movements)
          if (selected.contains(m.id)) m,
      ],
      openingOutstanding: [
        for (final m in ledger.movements)
          if (outstanding.contains(m.id)) m,
      ],
      attachments: _readReconciliationAttachments(payload['attachments']),
    );
  }

  void _validateAccountReconciliationArchive() {
    for (final row in _database.select(
      'SELECT * FROM bank_reconciliations WHERE statement_id IS NULL',
    )) {
      final business = EntityId.parse(row['business_id'] as String),
          id = row['id'] as String;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final selected = _accountSelection(payload['selected']);
      final outstanding = _accountSelection(
        payload['openingOutstanding'] ?? const [],
      );
      final ledger = reconciliationLedgerSnapshot(business, id);
      final payment = _database.select(
        'SELECT currency FROM payment_accounts WHERE business_id=? AND id=?',
        [business.value, row['payment_account_id']],
      );
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [business.value],
      );
      if (ledger == null ||
          payment.length != 1 ||
          payment.single['currency'] != row['currency'] ||
          owner.length != 1 ||
          owner.single['owner_id'] != row['actor_id'] ||
          payload['mode'] != 'account' ||
          payload['business'] != business.value ||
          payload['account'] != row['payment_account_id'] ||
          payload['actor'] != row['actor_id'] ||
          payload['start'] != row['starts_on'] ||
          payload['end'] != row['ends_on'] ||
          payload['opening'] != row['opening_minor'] ||
          payload['closing'] != row['closing_minor'] ||
          payload['currency'] != row['currency'] ||
          payload['closingCurrency'] != row['currency'] ||
          payload['previous'] != row['previous_id'] ||
          payload['evidence'] != row['opening_evidence'] ||
          payload['ledgerFingerprint'] !=
              _accountLedgerFingerprint(
                ledger.movements,
                row['currency'] as String,
              )) {
        throw const FormatException(
          'Approved account reconciliation identity differs.',
        );
      }
      final start = DateTime.parse(row['starts_on'] as String),
          end = DateTime.parse(row['ends_on'] as String);
      final currentById = {
        for (final m in _openingLedgerMovements(
          business,
          row['payment_account_id'] as String,
          end.add(const Duration(days: 1)),
          row['currency'] as String,
        ))
          m.id: m,
      };
      if (ledger.movements.any(
        (m) =>
            !currentById.containsKey(m.id) ||
            currentById[m.id]!.amount != m.amount ||
            currentById[m.id]!.date != m.date ||
            currentById[m.id]!.memo != m.memo,
      )) {
        throw const FormatException(
          'Approved ledger snapshot differs from its posted source.',
        );
      }
      if (end.isBefore(start) ||
          ledger.movements.any((m) => m.date.isAfter(end)) ||
          outstanding.any(
            (id) => !ledger.movements.any(
              (m) => m.id == id && m.date.isBefore(start),
            ),
          )) {
        throw const FormatException(
          'Approved account reconciliation period differs.',
        );
      }
      final allocations = _database
          .select(
            'SELECT journal_id,line_index FROM bank_reconciliation_cleared_movements WHERE completion_id=?',
            [id],
          )
          .map((r) => "${r['journal_id']}:${r['line_index']}")
          .toSet();
      if (allocations.length != selected.length ||
          !allocations.containsAll(selected)) {
        throw const FormatException(
          'Approved account reconciliation allocation differs.',
        );
      }
      final previous = row['previous_id'] as String?;
      if (previous == null) {
        if ((row['opening_evidence'] as String).trim().isEmpty ||
            _openingAfterOutstanding(
                  ledger.movements
                      .where((m) => m.date.isBefore(start))
                      .toList(),
                  outstanding,
                  row['currency'] as String,
                ).minorUnits !=
                row['opening_minor']) {
          throw const FormatException('Approved opening evidence differs.');
        }
      } else {
        final parents = _database.select(
          'SELECT * FROM bank_reconciliations WHERE id=? AND business_id=? AND payment_account_id=?',
          [previous, business.value, row['payment_account_id']],
        );
        if (parents.length != 1 ||
            outstanding.isNotEmpty ||
            DateTime.parse(parents.single['ends_on'] as String)
                    .add(const Duration(days: 1)) !=
                start ||
            parents.single['closing_minor'] != row['opening_minor'] ||
            parents.single['currency'] != row['currency'] ||
            DateTime.parse(parents.single['approved_at'] as String)
                .isAfter(DateTime.parse(row['approved_at'] as String))) {
          throw const FormatException(
            'Approved account reconciliation predecessor differs.',
          );
        }
      }
      final classification = _reconciliationClassification(business, id);
      if (classification == null || !classification.agrees) {
        throw const FormatException(
          'Approved account clearing does not agree.',
        );
      }
      _accountReconciliationEvidence(business, id, row);
    }
    if (_database.select(
      'SELECT 1 FROM bank_reconciliation_cleared_movements m JOIN bank_reconciliations c ON c.id=m.completion_id JOIN journal_entries j ON j.id=m.journal_id WHERE c.statement_id IS NOT NULL OR c.business_id<>j.business_id OR j.state<>? LIMIT 1',
      [JournalEntryState.posted.name],
    ).isNotEmpty) {
      throw const FormatException('Approved clearance ownership differs.');
    }
    for (final r in _database.select(
      'SELECT business_id,payment_account_id FROM account_reconciliation_drafts',
    )) {
      final business = EntityId.parse(r['business_id'] as String);
      final draft = readAccountReconciliationDraft(
        business,
        r['payment_account_id'] as String,
      )!;
      final ledger = _openingLedgerMovements(
        business,
        draft.paymentAccountId,
        draft.endsOn.add(const Duration(days: 1)),
        draft.openingBalance.currency,
      );
      final ids = ledger.map((m) => m.id).toSet();
      if (!ids.containsAll({
            ...draft.selectedIds,
            ...draft.openingOutstandingIds,
          }) ||
          draft.openingOutstandingIds.any(
            (id) => !ledger.any(
              (m) => m.id == id && m.date.isBefore(draft.startsOn),
            ),
          )) {
        throw const FormatException(
          'Saved account reconciliation selection differs.',
        );
      }
    }
  }
}
