part of 'accounting_database.dart';

extension TaxRemittancePersistence on LocalAccountingDatabase {
  // Data-only archive export changes evidence key order while omitting bytes.
  // Compare complete JSON structurally; unknown/missing facts still fail.
  bool _remittanceJsonEquals(String saved, Object? value) {
    Object? ordered(Object? v) {
      if (v is List) return v.map(ordered).toList();
      if (v is Map) {
        final map = Map<String, dynamic>.from(v);
        if (map.containsKey('originalSha256') &&
            map['_evidenceUnavailable'] == true) {
          // The established receipt owner exposes a data-only restore as failed
          // availability while retaining the exact original hash and identity.
          final attachment = ReceiptAttachment.fromJson(map);
          map['status'] = attachment.status.name;
          map['failureMessage'] = attachment.failureMessage;
        }
        final keys = map.keys.toList()..sort();
        return {for (final key in keys) key: ordered(map[key])};
      }
      return v;
    }

    return jsonEncode(ordered(jsonDecode(saved))) == jsonEncode(ordered(value));
  }

  String taxRemittanceJournalFingerprint(StoredJournalEntry source) =>
      jsonEncode([
        source.entry.id.value,
        source.entry.date.toIso8601String(),
        source.entry.memo,
        source.entry.state.name,
        source.entry.reversesId?.value,
        source.entry.closingEquityAccountId?.value,
        source.metadata.businessId.value,
        source.metadata.originDeviceId.value,
        source.metadata.createdAt.toIso8601String(),
        source.metadata.updatedAt.toIso8601String(),
        source.metadata.revision,
        source.metadata.deletedAt?.toIso8601String(),
        LocalAccountingDatabase._lineSignature(source.entry.lines),
      ]);

  Set<EntityId> _remittanceLiabilityIds(EntityId company) {
    final result = <EntityId>{};
    for (final row in _database.select(
      'SELECT payload FROM company_tax_rate_history WHERE business_id=?',
      [company.value],
    )) {
      final code = CompanyTaxRate.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      if (code.application != TaxApplication.purchases) {
        result.add(code.salesAccountId);
      }
    }
    return result;
  }

  ({EntityId bank, String currency}) _remittancePaymentAccount(
    EntityId company,
    String id,
  ) {
    final payment = readPaymentAccounts(company)
        .where((p) => p.id == id)
        .firstOrNull;
    final bank = paymentLedgerAccount(company, id);
    if (payment == null ||
        bank == null ||
        !const {
          PaymentAccountType.bank,
          PaymentAccountType.cash,
        }.contains(payment.type)) {
      throw StateError(
        'Choose a company bank or cash payment account linked to its ledger.',
      );
    }
    final rows = _database.select(
      'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
      [company.value, bank.value],
    );
    if (rows.length != 1 ||
        rows.single['type'] != AccountType.asset.name ||
        rows.single['status'] != AccountStatus.active.name ||
        rows.single['is_parent'] != 0) {
      throw StateError(
        'The payment bank must be an active company asset posting account.',
      );
    }
    return (bank: bank, currency: payment.currency.code);
  }

  Map<EntityId, BigInt> _remittanceJournalDebits(
    EntityId company,
    StoredJournalEntry source,
    EntityId bank,
    String currency, {
    bool activeAccounts = false,
  }) {
    final entry = source.entry;
    if (source.metadata.businessId != company ||
        source.metadata.isTombstone ||
        entry.state != JournalEntryState.posted ||
        entry.isClosing ||
        entry.reversesId != null ||
        entry.validationErrors.isNotEmpty ||
        entry.lines.any((l) => l.amount.currency != currency)) {
      throw StateError(
        'Review an unreversed posted company tax-liability payment in the payment currency.',
      );
    }
    final ids = _remittanceLiabilityIds(company), debits = <EntityId, BigInt>{};
    var bankCredits = BigInt.zero;
    for (final line in entry.lines) {
      final account = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
        [company.value, line.accountId.value],
      );
      if (account.length != 1 ||
          account.single['is_parent'] != 0 ||
          activeAccounts &&
              account.single['status'] != AccountStatus.active.name) {
        throw StateError(
          'Remittance accounts must be company-owned posting accounts.',
        );
      }
      if (line.isCredit &&
          line.accountId == bank &&
          account.single['type'] == AccountType.asset.name) {
        bankCredits += BigInt.from(line.amount.minorUnits);
      } else if (line.isDebit &&
          ids.contains(line.accountId) &&
          account.single['type'] == AccountType.liability.name) {
        debits.update(
          line.accountId,
          (n) => n + BigInt.from(line.amount.minorUnits),
          ifAbsent: () => BigInt.from(line.amount.minorUnits),
        );
      } else {
        throw StateError(
          'Link only tax-liability debits and the selected bank credit; expense, refund and mixed-purpose journals need separate review.',
        );
      }
    }
    if (bankCredits <= BigInt.zero ||
        debits.values.fold(BigInt.zero, (n, v) => n + v) != bankCredits) {
      throw StateError(
        'Tax payment bank credit does not reconcile to liability debits.',
      );
    }
    return debits;
  }

  List<StoredAccount> readTaxRemittanceLiabilityAccounts(EntityId company) {
    _ensureOpen();
    final mapped = _remittanceLiabilityIds(company);
    return List.unmodifiable(
      _database
          .select(
            "SELECT * FROM accounts WHERE business_id=? AND type='liability' AND status='active' AND is_parent=0 ORDER BY code,id",
            [company.value],
          )
          .map(_accountFromRow)
          .where((a) => mapped.contains(a.account.id)),
    );
  }

  List<PaymentAccount> readTaxRemittancePaymentAccounts(EntityId company) {
    _ensureOpen();
    final policy = _database.select(
      'SELECT currency FROM ledger_policies WHERE business_id=?',
      [company.value],
    );
    if (policy.length != 1) {
      throw StateError(
        'Configure the company ledger before recording tax payments.',
      );
    }
    final result = <PaymentAccount>[];
    for (final profile in readPaymentAccounts(company)) {
      if (profile.currency.code != policy.single['currency']) continue;
      try {
        _remittancePaymentAccount(company, profile.id);
        result.add(profile);
      } on StateError {
        // Unlinked, inactive and unsupported profiles are deliberately ineligible.
      }
    }
    return List.unmodifiable(result);
  }

  List<TaxRemittanceCandidate> readTaxRemittanceCandidates(
    EntityId company,
    String paymentAccountId,
  ) {
    _ensureOpen();
    if (!readTaxRemittancePaymentAccounts(company)
        .any((p) => p.id == paymentAccountId)) {
      throw StateError('Choose an eligible company bank or cash account.');
    }
    // Validate existing immutable attribution before reporting unused budgets.
    readTaxRemittances(company, includeCorrected: true);
    final bank = _remittancePaymentAccount(company, paymentAccountId),
        result = <TaxRemittanceCandidate>[];
    for (final row in _database.select(
      "SELECT j.* FROM journal_entries j WHERE j.business_id=? AND j.state='posted' AND j.deleted_at IS NULL AND j.reverses_id IS NULL AND j.closing_equity_id IS NULL AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.business_id=j.business_id AND r.reverses_id=j.id AND r.state='posted') ORDER BY j.entry_date,j.id",
      [company.value],
    )) {
      final source = _readJournal(EntityId.parse(row['id'] as String))!;
      Map<EntityId, BigInt> eligible;
      try {
        eligible = _remittanceJournalDebits(
          company,
          source,
          bank.bank,
          bank.currency,
          activeAccounts: true,
        );
      } on StateError {
        continue; // Other posted purchases, receipts, refunds and mixed-purpose entries.
      }
      final used = _allocatedRemittanceDebits(company, source.entry.id),
          remaining = <EntityId, Money>{};
      for (final entry in eligible.entries) {
        final available = entry.value - (used[entry.key] ?? BigInt.zero);
        if (available < BigInt.zero) {
          throw const FormatException(
            'Saved remittance allocation exceeds the payment.',
          );
        }
        if (available > BigInt.zero) {
          remaining[entry.key] = Money.fromMinor(
            available.toInt(),
            bank.currency,
          );
        }
      }
      if (remaining.isNotEmpty) {
        result.add(
          TaxRemittanceCandidate(
            journal: source,
            paymentAccountId: paymentAccountId,
            bankAccountId: bank.bank,
            remaining: remaining,
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }

  List<TaxRemittance> readTaxRemittances(
    EntityId company, {
    bool includeCorrected = false,
  }) {
    _ensureOpen();
    final result = <TaxRemittance>[];
    for (final row in _database.select(
      'SELECT * FROM tax_remittances WHERE business_id=? ORDER BY recorded_at,id',
      [company.value],
    )) {
      final saved = _taxRemittanceFromRow(row);
      final correction = readTaxRemittanceCorrection(company, saved.id);
      if (correction == null &&
          _database.select(
            "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted'",
            [company.value, saved.journalId.value],
          ).isNotEmpty) {
        throw const FormatException(
          'Remittance attribution has an unlinked payment reversal.',
        );
      }
      if (includeCorrected || correction == null) result.add(saved);
    }
    return List.unmodifiable(result);
  }

  String _savedRemittanceSignature(TaxRemittance value) => jsonEncode([
    value.origin == TaxRemittanceOrigin.recorded ? 'record' : 'link',
    value.actorId.value,
    value.paymentAccountId,
    value.paidOn.toIso8601String(),
    value.reference,
    value.memo,
    value.recordedAt.toIso8601String(),
    value.allocations.map((a) => a.toJson()).toList(),
    value.attachments.map((a) => a.toJson()).toList(),
    value.origin == TaxRemittanceOrigin.linked
        ? value.journalFingerprint
        : null,
  ]);

  TaxRemittance _taxRemittanceFromRow(Row row) {
    final value = TaxRemittance.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    );
    final source = _readJournal(value.journalId);
    final owner = _database.select(
      'SELECT owner_id FROM local_workspace WHERE business_id=?',
      [value.businessId.value],
    );
    final payment = _database.select(
      'SELECT type,currency FROM payment_accounts WHERE business_id=? AND id=?',
      [value.businessId.value, value.paymentAccountId],
    );
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='tax.remittance_recorded' AND subject_id=?",
      [value.businessId.value, value.id.value],
    );
    if (!_remittanceJsonEquals(
          row['signature'] as String,
          jsonDecode(_savedRemittanceSignature(value)),
        ) ||
        value.id.value != row['id'] ||
        value.businessId.value != row['business_id'] ||
        value.journalId.value != row['journal_id'] ||
        value.recordedAt.toIso8601String() != row['recorded_at'] ||
        value.origin.name != row['origin'] ||
        !_remittanceJsonEquals(row['payload'] as String, value.toJson()) ||
        source == null ||
        source.metadata.revision != value.journalRevision ||
        source.entry.date != value.paidOn ||
        !value.recordedAt.isAfter(source.metadata.createdAt) ||
        value.recordedAt.isBefore(source.metadata.updatedAt) ||
        taxRemittanceJournalFingerprint(source) != value.journalFingerprint ||
        owner.length != 1 ||
        owner.single['owner_id'] != value.actorId.value ||
        payment.length != 1 ||
        payment.single['currency'] != value.total.currency ||
        !const ['bank', 'cash'].contains(payment.single['type']) ||
        audit.length != 1 ||
        audit.single['actor_id'] != value.actorId.value ||
        audit.single['occurred_at'] != value.recordedAt.toIso8601String() ||
        !_remittanceJsonEquals(
          audit.single['detail'] as String,
          value.toJson(),
        )) {
      throw const FormatException(
        'Tax remittance identity, payment journal or audit is inconsistent.',
      );
    }
    if (_database.select(
      "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' AND updated_at<=?",
      [
        value.businessId.value,
        value.journalId.value,
        value.recordedAt.toIso8601String(),
      ],
    ).isNotEmpty) {
      throw const FormatException(
        'A reversed payment cannot have received new remittance attribution.',
      );
    }
    final debits = _remittanceJournalDebits(
      value.businessId,
      source,
      value.bankAccountId,
      value.total.currency,
    );
    final totals = <EntityId, BigInt>{};
    for (final allocation in value.allocations) {
      _validateTaxAgencySnapshot(value.businessId, allocation.agency);
      totals.update(
        allocation.liabilityAccountId,
        (n) => n + BigInt.from(allocation.amount.minorUnits),
        ifAbsent: () => BigInt.from(allocation.amount.minorUnits),
      );
    }
    if (totals.entries.any((e) => e.value > (debits[e.key] ?? BigInt.zero))) {
      throw const FormatException(
        'Tax remittance allocations exceed their posted payment.',
      );
    }
    if (value.origin == TaxRemittanceOrigin.recorded) {
      final approval = _database.select(
        'SELECT signature,journal_id FROM journal_approvals WHERE business_id=? AND request_id=?',
        [value.businessId.value, value.id.value],
      );
      if (value.journalId != value.id ||
          source.metadata.revision != 2 ||
          source.metadata.createdAt !=
              value.recordedAt.subtract(const Duration(microseconds: 1)) ||
          source.metadata.updatedAt != value.recordedAt ||
          source.entry.memo !=
              'Tax remittance ${value.reference}${value.memo.isEmpty ? '' : ': ${value.memo}'}' ||
          approval.length != 1 ||
          approval.single['journal_id'] != value.id.value ||
          approval.single['signature'] !=
              jsonEncode([
                value.id.value,
                1,
                value.actorId.value,
                value.recordedAt.toIso8601String(),
              ]) ||
          totals.length != debits.length ||
          totals.entries.any((e) => e.value != debits[e.key])) {
        throw const FormatException(
          'Recorded remittance differs from its exact approved posting.',
        );
      }
    }
    return value;
  }

  Map<EntityId, BigInt> _allocatedRemittanceDebits(
    EntityId company,
    EntityId journal, {
    DateTime? before,
  }) {
    final totals = <EntityId, BigInt>{};
    for (final row in _database.select(
      'SELECT * FROM tax_remittances WHERE business_id=? AND journal_id=?',
      [company.value, journal.value],
    )) {
      final saved = TaxRemittance.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      if (before != null && !saved.recordedAt.isBefore(before)) continue;
      final corrections = _database.select(
        'SELECT recorded_at FROM tax_remittance_corrections WHERE business_id=? AND source_id=?',
        [company.value, saved.id.value],
      );
      if (corrections.isNotEmpty &&
          (before == null ||
              DateTime.parse(corrections.single['recorded_at'] as String)
                  .isBefore(before))) {
        continue;
      }
      for (final a in saved.allocations) {
        totals.update(
          a.liabilityAccountId,
          (n) => n + BigInt.from(a.amount.minorUnits),
          ifAbsent: () => BigInt.from(a.amount.minorUnits),
        );
      }
    }
    return totals;
  }

  TaxRemittance recordTaxRemittance({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required String paymentAccountId,
    required List<TaxRemittanceAllocation> allocations,
    List<ReceiptAttachment> attachments = const [],
    required DateTime paidOn,
    required String reference,
    String memo = '',
    required DateTime recordedAt,
  }) => _commitTaxRemittance(
    company: businessId,
    actor: actorId,
    request: requestId,
    paymentAccountId: paymentAccountId,
    allocations: allocations,
    attachments: attachments,
    paidOn: paidOn,
    reference: reference,
    memo: memo,
    at: recordedAt,
    reviewedJournal: null,
  );

  TaxRemittance linkTaxRemittance({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required StoredJournalEntry reviewedJournal,
    required String paymentAccountId,
    required List<TaxRemittanceAllocation> allocations,
    List<ReceiptAttachment> attachments = const [],
    required String reference,
    String memo = '',
    required DateTime recordedAt,
  }) => _commitTaxRemittance(
    company: businessId,
    actor: actorId,
    request: requestId,
    paymentAccountId: paymentAccountId,
    allocations: allocations,
    attachments: attachments,
    paidOn: reviewedJournal.entry.date,
    reference: reference,
    memo: memo,
    at: recordedAt,
    reviewedJournal: reviewedJournal,
  );

  TaxRemittance _commitTaxRemittance({
    required EntityId company,
    required EntityId actor,
    required EntityId request,
    required String paymentAccountId,
    required List<TaxRemittanceAllocation> allocations,
    List<ReceiptAttachment> attachments = const [],
    required DateTime paidOn,
    required String reference,
    required String memo,
    required DateTime at,
    required StoredJournalEntry? reviewedJournal,
  }) {
    _ensureOpen();
    final ordered = [...allocations]..sort((a, b) => a.key.compareTo(b.key));
    final date = accountingCalendarDate(paidOn),
        approved = at.toUtc(),
        ref = reference.trim(),
        note = memo.trim();
    // Construct the intent first so all field invariants also apply to retries.
    final intent = TaxRemittance(
      id: request,
      businessId: company,
      actorId: actor,
      journalId: reviewedJournal?.entry.id ?? request,
      journalRevision: reviewedJournal?.metadata.revision ?? 2,
      journalFingerprint: 'intent',
      origin: reviewedJournal == null
          ? TaxRemittanceOrigin.recorded
          : TaxRemittanceOrigin.linked,
      bankAccountId: company,
      paymentAccountId: paymentAccountId,
      paidOn: date,
      recordedAt: approved,
      reference: ref,
      memo: note,
      allocations: ordered,
      attachments: attachments,
    );
    final signature = jsonEncode([
      reviewedJournal == null ? 'record' : 'link',
      actor.value,
      paymentAccountId,
      date.toIso8601String(),
      ref,
      note,
      approved.toIso8601String(),
      ordered.map((a) => a.toJson()).toList(),
      intent.attachments.map((a) => a.toJson()).toList(),
      reviewedJournal == null
          ? null
          : taxRemittanceJournalFingerprint(reviewedJournal),
    ]);
    late TaxRemittance result;
    _transaction(() {
      _requireReconciliationOwner(company, actor);
      final retry = _database.select(
        'SELECT * FROM tax_remittances WHERE business_id=? AND id=?',
        [company.value, request.value],
      );
      if (retry.isNotEmpty) {
        if (!_remittanceJsonEquals(
          retry.single['signature'] as String,
          jsonDecode(signature),
        )) {
          throw StateError('Remittance request was reused for different work.');
        }
        result = _taxRemittanceFromRow(retry.single);
        return;
      }
      if (intent.attachments.any((a) => a.originalBytes.isEmpty)) {
        throw StateError(
          'New remittance evidence needs available original bytes.',
        );
      }
      final bank = _remittancePaymentAccount(company, paymentAccountId),
          ids = _remittanceLiabilityIds(company);
      if (ordered.any(
        (a) =>
            a.amount.currency != bank.currency ||
            !ids.contains(a.liabilityAccountId),
      )) {
        throw StateError(
          'Use configured sales-tax liability accounts and the selected payment currency.',
        );
      }
      for (final a in ordered) {
        _validateTaxAgencySnapshot(company, a.agency);
        final current = readTaxAgencies(company)
            .singleWhere((agency) => agency.id == a.agency.id);
        if (jsonEncode(current.toJson()) != jsonEncode(a.agency.toJson())) {
          throw StateError(
            'Tax agency changed. Review the current registration.',
          );
        }
      }
      final prior =
          _database.select(
                'SELECT MAX(recorded_at) AS at FROM tax_remittances WHERE business_id=?',
                [company.value],
              ).single['at']
              as String?;
      final correctionAt =
          _database.select(
                'SELECT MAX(recorded_at) AS at FROM tax_remittance_corrections WHERE business_id=?',
                [company.value],
              ).single['at']
              as String?;
      if (prior != null && !approved.isAfter(DateTime.parse(prior)) ||
          correctionAt != null &&
              !approved.isAfter(DateTime.parse(correctionAt))) {
        throw StateError('Record remittance commands in chronological order.');
      }
      StoredJournalEntry source;
      if (reviewedJournal == null) {
        if (_readJournal(request) != null) {
          throw StateError(
            'The payment identity already belongs to a journal.',
          );
        }
        final device = EntityId.parse(
          _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [company.value],
              ).single['device_id']
              as String,
        );
        final debits = <EntityId, Money>{};
        var total = Money.zero(bank.currency);
        for (final a in ordered) {
          debits.update(
            a.liabilityAccountId,
            (v) => v + a.amount,
            ifAbsent: () => a.amount,
          );
          total += a.amount;
        }
        _writeJournal(
          StoredJournalEntry(
            entry: JournalEntry.draft(
              id: request,
              date: date,
              memo: 'Tax remittance $ref${note.isEmpty ? '' : ': $note'}',
              lines: [
                for (final e in debits.entries)
                  JournalLine.debit(accountId: e.key, amount: e.value),
                JournalLine.credit(accountId: bank.bank, amount: total),
              ],
            ),
            metadata: RecordMetadata.initial(
              recordId: request,
              businessId: company,
              originDeviceId: device,
              createdAt: approved.subtract(const Duration(microseconds: 1)),
            ),
          ),
        );
        source = _approveJournalInTransaction(
          JournalApproval(
            requestId: request,
            businessId: company,
            journalId: request,
            expectedRevision: 1,
            actorId: actor,
            approvedAt: approved,
          ),
        );
      } else {
        final actual = _readJournal(reviewedJournal.entry.id);
        if (actual == null ||
            taxRemittanceJournalFingerprint(actual) !=
                taxRemittanceJournalFingerprint(reviewedJournal) ||
            approved.isBefore(actual.metadata.updatedAt)) {
          throw StateError(
            'The reviewed payment changed. Reopen the posted journal.',
          );
        }
        source = actual;
      }
      if (_database.select(
        "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted'",
        [company.value, source.entry.id.value],
      ).isNotEmpty) {
        throw StateError(
          'A reversed payment cannot receive active remittance attribution.',
        );
      }
      final eligible = _remittanceJournalDebits(
        company,
        source,
        bank.bank,
        bank.currency,
        activeAccounts: true,
      );
      final used = _allocatedRemittanceDebits(company, source.entry.id);
      for (final a in ordered) {
        used.update(
          a.liabilityAccountId,
          (v) => v + BigInt.from(a.amount.minorUnits),
          ifAbsent: () => BigInt.from(a.amount.minorUnits),
        );
      }
      if (used.entries.any((e) => e.value > (eligible[e.key] ?? BigInt.zero))) {
        throw StateError(
          'This payment amount is already allocated or exceeds the eligible liability debit.',
        );
      }
      result = TaxRemittance(
        id: request,
        businessId: company,
        actorId: actor,
        journalId: source.entry.id,
        journalRevision: source.metadata.revision,
        journalFingerprint: taxRemittanceJournalFingerprint(source),
        origin: reviewedJournal == null
            ? TaxRemittanceOrigin.recorded
            : TaxRemittanceOrigin.linked,
        bankAccountId: bank.bank,
        paymentAccountId: paymentAccountId,
        paidOn: date,
        recordedAt: approved,
        reference: ref,
        memo: note,
        allocations: ordered,
        attachments: attachments,
      );
      final payload = jsonEncode(result.toJson());
      _database.execute(
        'INSERT INTO tax_remittances(business_id,id,journal_id,origin,recorded_at,signature,payload) VALUES(?,?,?,?,?,?,?)',
        [
          company.value,
          request.value,
          source.entry.id.value,
          result.origin.name,
          approved.toIso8601String(),
          signature,
          payload,
        ],
      );
      _appendAudit(
        businessId: company,
        actorId: actor,
        at: approved,
        kind: 'tax.remittance_recorded',
        subjectId: request,
        detail: payload,
      );
      if (result.origin == TaxRemittanceOrigin.recorded) {
        _appendTransactionRootCreated(
          businessId: company,
          actorId: actor,
          at: approved,
          family: 'taxRemittance',
          recordId: request,
        );
      }
      _taxRemittanceFromRow(
        _database.select(
          'SELECT * FROM tax_remittances WHERE business_id=? AND id=?',
          [company.value, request.value],
        ).single,
      );
    });
    return result;
  }

  TaxRemittanceCorrection? readTaxRemittanceCorrection(
    EntityId company,
    EntityId source,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM tax_remittance_corrections WHERE business_id=? AND source_id=?',
      [company.value, source.value],
    );
    return rows.isEmpty ? null : _taxRemittanceCorrectionFromRow(rows.single);
  }

  TaxRemittanceCorrection _taxRemittanceCorrectionFromRow(Row row) {
    final value = TaxRemittanceCorrection.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    );
    final sources = _database.select(
      'SELECT * FROM tax_remittances WHERE business_id=? AND id=?',
      [value.businessId.value, value.sourceId.value],
    );
    final source = sources.length == 1
        ? _taxRemittanceFromRow(sources.single)
        : null;
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='tax.remittance_corrected' AND subject_id=?",
      [value.businessId.value, value.sourceId.value],
    );
    final owner = _database.select(
      'SELECT owner_id FROM local_workspace WHERE business_id=?',
      [value.businessId.value],
    );
    if (source == null ||
        !_remittanceJsonEquals(row['signature'] as String, [
          source.toJson(),
          value.toJson(),
        ]) ||
        value.id.value != row['id'] ||
        value.businessId.value != row['business_id'] ||
        value.sourceId.value != row['source_id'] ||
        value.recordedAt.toIso8601String() != row['recorded_at'] ||
        value.journalId?.value != row['journal_id'] ||
        !_remittanceJsonEquals(row['payload'] as String, value.toJson()) ||
        !value.recordedAt.isAfter(source.recordedAt) ||
        owner.length != 1 ||
        owner.single['owner_id'] != value.actorId.value ||
        value.on.isBefore(source.paidOn) ||
        audit.length != 1 ||
        audit.single['actor_id'] != value.actorId.value ||
        audit.single['occurred_at'] != value.recordedAt.toIso8601String() ||
        !_remittanceJsonEquals(
          audit.single['detail'] as String,
          value.toJson(),
        ) ||
        (value.kind == TaxRemittanceCorrectionKind.unlink) !=
            (source.origin == TaxRemittanceOrigin.linked)) {
      throw const FormatException(
        'Tax remittance correction lost its reviewed source or audit.',
      );
    }
    if (value.kind == TaxRemittanceCorrectionKind.unlink &&
        _database.select(
          "SELECT 1 FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted' AND updated_at<=?",
          [
            value.businessId.value,
            source.journalId.value,
            value.recordedAt.toIso8601String(),
          ],
        ).isNotEmpty) {
      throw const FormatException(
        'Unlink attribution before reversing its recorded journal.',
      );
    }
    if (value.kind == TaxRemittanceCorrectionKind.reversal) {
      final original = _readJournal(source.journalId)!,
          reversal = _readJournal(value.journalId!);
      final approval = _database.select(
        'SELECT signature FROM journal_approvals WHERE business_id=? AND request_id=?',
        [value.businessId.value, value.id.value],
      );
      if (value.journalId != value.id ||
          reversal == null ||
          reversal.metadata.businessId != value.businessId ||
          reversal.metadata.originDeviceId !=
              original.metadata.originDeviceId ||
          reversal.metadata.revision != 2 ||
          reversal.metadata.isTombstone ||
          reversal.metadata.createdAt !=
              value.recordedAt.subtract(const Duration(microseconds: 1)) ||
          reversal.metadata.updatedAt != value.recordedAt ||
          reversal.entry.state != JournalEntryState.posted ||
          reversal.entry.reversesId != source.journalId ||
          reversal.entry.date != value.on ||
          reversal.entry.memo != 'Tax remittance reversal: ${value.reason}' ||
          LocalAccountingDatabase._lineSignature(
                reversal.entry.lines,
                reverse: true,
              ) !=
              LocalAccountingDatabase._lineSignature(original.entry.lines) ||
          approval.length != 1 ||
          approval.single['signature'] !=
              jsonEncode([
                value.id.value,
                1,
                value.actorId.value,
                value.recordedAt.toIso8601String(),
              ])) {
        throw const FormatException(
          'Tax remittance reversal differs from its exact source payment.',
        );
      }
    }
    return value;
  }

  TaxRemittanceCorrection correctTaxRemittance({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required TaxRemittance reviewedRemittance,
    required DateTime on,
    required DateTime recordedAt,
    required String reason,
  }) {
    _ensureOpen();
    final correction = TaxRemittanceCorrection(
      id: requestId,
      sourceId: reviewedRemittance.id,
      businessId: businessId,
      actorId: actorId,
      kind: reviewedRemittance.origin == TaxRemittanceOrigin.linked
          ? TaxRemittanceCorrectionKind.unlink
          : TaxRemittanceCorrectionKind.reversal,
      journalId: reviewedRemittance.origin == TaxRemittanceOrigin.linked
          ? null
          : requestId,
      on: on,
      recordedAt: recordedAt,
      reason: reason,
    );
    final signature = jsonEncode([
      reviewedRemittance.toJson(),
      correction.toJson(),
    ]);
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT * FROM tax_remittance_corrections WHERE business_id=? AND id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (!_remittanceJsonEquals(
          retry.single['signature'] as String,
          jsonDecode(signature),
        )) {
          throw StateError('Remittance correction request was reused.');
        }
        _taxRemittanceCorrectionFromRow(retry.single);
        return;
      }
      final sources = _database.select(
        'SELECT * FROM tax_remittances WHERE business_id=? AND id=?',
        [businessId.value, reviewedRemittance.id.value],
      );
      if (sources.length != 1 ||
          jsonEncode(_taxRemittanceFromRow(sources.single).toJson()) !=
              jsonEncode(reviewedRemittance.toJson()) ||
          readTaxRemittanceCorrection(businessId, reviewedRemittance.id) !=
              null ||
          correction.on.isBefore(reviewedRemittance.paidOn) ||
          !correction.recordedAt.isAfter(reviewedRemittance.recordedAt)) {
        throw StateError(
          'The reviewed remittance is stale or already corrected.',
        );
      }
      final previous =
          _database.select(
                'SELECT MAX(at) AS at FROM (SELECT recorded_at AS at FROM tax_remittances WHERE business_id=? UNION ALL SELECT recorded_at AS at FROM tax_remittance_corrections WHERE business_id=?)',
                [businessId.value, businessId.value],
              ).single['at']
              as String?;
      if (previous != null &&
          !correction.recordedAt.isAfter(DateTime.parse(previous))) {
        throw StateError('Record correction commands in chronological order.');
      }
      if (correction.kind == TaxRemittanceCorrectionKind.reversal) {
        if (_journalAlreadyMatched(businessId, reviewedRemittance.journalId)) {
          throw StateError(
            'Unlink the bank statement match before correcting this payment.',
          );
        }
        final original = _readJournal(reviewedRemittance.journalId)!;
        _writeJournal(
          StoredJournalEntry(
            entry: original.entry.reversal(
              id: requestId,
              date: correction.on,
              memo: 'Tax remittance reversal: ${correction.reason}',
            ),
            metadata: RecordMetadata.initial(
              recordId: requestId,
              businessId: businessId,
              originDeviceId: original.metadata.originDeviceId,
              createdAt: correction.recordedAt.subtract(
                const Duration(microseconds: 1),
              ),
            ),
          ),
        );
        _approveJournalInTransaction(
          JournalApproval(
            requestId: requestId,
            businessId: businessId,
            journalId: requestId,
            expectedRevision: 1,
            actorId: actorId,
            approvedAt: correction.recordedAt,
          ),
          linkedTaxRemittanceReversal: reviewedRemittance.journalId,
        );
      }
      final payload = jsonEncode(correction.toJson());
      _database.execute(
        'INSERT INTO tax_remittance_corrections(business_id,source_id,id,journal_id,recorded_at,signature,payload) VALUES(?,?,?,?,?,?,?)',
        [
          businessId.value,
          reviewedRemittance.id.value,
          requestId.value,
          correction.journalId?.value,
          correction.recordedAt.toIso8601String(),
          signature,
          payload,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: correction.recordedAt,
        kind: 'tax.remittance_corrected',
        subjectId: reviewedRemittance.id,
        detail: payload,
      );
      _taxRemittanceCorrectionFromRow(
        _database.select(
          'SELECT * FROM tax_remittance_corrections WHERE business_id=? AND source_id=?',
          [businessId.value, reviewedRemittance.id.value],
        ).single,
      );
    });
    return correction;
  }

  void _validateTaxRemittanceArchive() {
    if (_database
        .select(
          'SELECT business_id,at,count(*) AS total FROM (SELECT business_id,recorded_at AS at FROM tax_remittances UNION ALL SELECT business_id,recorded_at AS at FROM tax_remittance_corrections) GROUP BY business_id,at HAVING total>1 LIMIT 1',
        )
        .isNotEmpty) {
      throw const FormatException(
        'Remittance command timestamps must form a strict company history.',
      );
    }
    for (final row in _database.select(
      'SELECT * FROM tax_remittances ORDER BY recorded_at,id',
    )) {
      final saved = _taxRemittanceFromRow(row),
          journal = _readJournal(EntityId.parse(row['journal_id'] as String))!;
      final eligible = _remittanceJournalDebits(
        saved.businessId,
        journal,
        saved.bankAccountId,
        saved.total.currency,
      );
      final used = _allocatedRemittanceDebits(
        saved.businessId,
        saved.journalId,
        before: saved.recordedAt,
      );
      for (final a in saved.allocations) {
        used.update(
          a.liabilityAccountId,
          (n) => n + BigInt.from(a.amount.minorUnits),
          ifAbsent: () => BigInt.from(a.amount.minorUnits),
        );
      }
      if (used.entries.any((e) => e.value > (eligible[e.key] ?? BigInt.zero))) {
        throw const FormatException(
          'Archived remittance allocation history exceeds the payment.',
        );
      }
      final corrections = readTaxRemittanceCorrection(
        saved.businessId,
        saved.id,
      );
      final reversals = _database.select(
        "SELECT id FROM journal_entries WHERE business_id=? AND reverses_id=? AND state='posted'",
        [saved.businessId.value, saved.journalId.value],
      );
      if (corrections == null && reversals.isNotEmpty ||
          corrections?.kind == TaxRemittanceCorrectionKind.reversal &&
              (reversals.length != 1 ||
                  reversals.single['id'] != corrections!.journalId!.value)) {
        throw const FormatException(
          'Tax remittance payment has an unlinked reversal.',
        );
      }
    }
    for (final row in _database.select(
      'SELECT * FROM tax_remittance_corrections',
    )) {
      _taxRemittanceCorrectionFromRow(row);
    }
    if (_database
        .select(
          "SELECT 1 FROM ledger_audit a LEFT JOIN tax_remittances r ON r.business_id=a.business_id AND r.id=a.subject_id WHERE a.kind='tax.remittance_recorded' AND r.id IS NULL UNION ALL SELECT 1 FROM ledger_audit a LEFT JOIN tax_remittance_corrections r ON r.business_id=a.business_id AND r.source_id=a.subject_id WHERE a.kind='tax.remittance_corrected' AND r.source_id IS NULL LIMIT 1",
        )
        .isNotEmpty) {
      throw const FormatException('Tax remittance audit lost its source.');
    }
  }
}
