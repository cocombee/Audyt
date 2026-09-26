part of 'accounting_database.dart';

extension _ClaimantStatementReads on LocalAccountingDatabase {
  ClaimReimbursementPosition? _claimReimbursementPosition({
    required EntityId businessId,
    required EntityId claimId,
    required DateTime through,
  }) {
    final source = _database.select(
      'SELECT payload FROM claims WHERE business_id=? AND id=?',
      [businessId.value, claimId.value],
    );
    if (source.isEmpty) return null;
    final claim = Claim.fromJson(
      jsonDecode(source.single['payload'] as String) as Map<String, dynamic>,
    );
    final report = _buildClaimantStatement(
      _buildLedgerReport(
        businessId: businessId,
        currency: claim.amount.currency,
        from: DateTime.utc(1),
        through: through,
      ),
    );
    return ClaimReimbursementPosition(
      businessId: businessId,
      claimId: claimId,
      currency: claim.amount.currency,
      through: accountingCalendarDate(through),
      activity: report.statements
          .expand((statement) => statement.events)
          .where((event) => event.claim.id == claimId),
    );
  }

  ClaimantStatementReport _buildClaimantStatement(LedgerReport ledger) {
    final business = ledger.businessId;
    final journals = {for (final j in ledger.postedEntries) j.id: j};
    final postingOrder = {
      for (final row in _database.select(
        "SELECT subject_id,sequence FROM ledger_audit WHERE business_id=? AND kind='journal_posted'",
        [business.value],
      ))
        EntityId.parse(row['subject_id'] as String): row['sequence'] as int,
    };
    final reversals = <EntityId, List<JournalEntry>>{};
    for (final j in journals.values) {
      if (j.reversesId != null) {
        reversals.putIfAbsent(j.reversesId!, () => []).add(j);
      }
    }
    final events = <ClaimantStatementEvent>[];
    void add(
      Claim claim,
      EntityId journalId,
      EntityId accountId,
      ClaimantEventKind kind,
      BigInt change, {
      String reference = '',
    }) {
      final original = journals[journalId];
      if (original == null) return;
      events.add(
        ClaimantStatementEvent(
          claim: claim,
          journalId: journalId,
          accountId: accountId,
          date: original.date,
          kind: kind,
          balanceChangeMinor: change,
          reference: reference,
        ),
      );
      for (final reversal in reversals[journalId] ?? <JournalEntry>[]) {
        events.add(
          ClaimantStatementEvent(
            claim: claim,
            journalId: reversal.id,
            accountId: accountId,
            date: reversal.date,
            kind: kind == ClaimantEventKind.recognition
                ? ClaimantEventKind.recognitionReversal
                : ClaimantEventKind.reimbursementReversal,
            balanceChangeMinor: -change,
            reference: reference,
          ),
        );
      }
    }

    final recognitions =
        <({Claim claim, EntityId journal, EntityId account})>[];
    for (final row in _database.select(
      'SELECT claim_payload,journal_id,liability_account_id FROM all_claim_postings WHERE business_id=?',
      [business.value],
    )) {
      final claim = Claim.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(row['claim_payload'] as String) as Map,
        ),
      );
      final journal = EntityId.parse(row['journal_id'] as String);
      final account = EntityId.parse(row['liability_account_id'] as String);
      recognitions.add((claim: claim, journal: journal, account: account));
      add(
        claim,
        journal,
        account,
        ClaimantEventKind.recognition,
        BigInt.from(claim.amount.minorUnits),
      );
    }
    for (final row in _database.select(
      '''
      SELECT s.journal_id,s.reference,s.signature,a.claim_id,a.amount_minor,a.currency,a.paid_payload
      FROM claim_settlements s JOIN claim_settlement_allocations a
        ON a.business_id=s.business_id AND a.request_id=s.request_id WHERE s.business_id=?
      ''',
      [business.value],
    )) {
      final journalId = EntityId.parse(row['journal_id'] as String);
      final journal = journals[journalId];
      if (journal == null) continue;
      // Settlement signatures retain the exact reviewed approved payloads.
      // Never infer the claimant or control account from the mutable claim.
      final signature = jsonDecode(row['signature'] as String) as List;
      final reviewed = (signature.first as List).cast<Map>().singleWhere(
        (c) => c['id'] == row['claim_id'],
      );
      final paid = Claim.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(row['paid_payload'] as String) as Map,
        ),
      );
      final matching = recognitions.where((r) {
        if (r.claim.id != paid.id || !journals.containsKey(r.journal)) {
          return false;
        }
        // A later accounting correction may reverse the old recognition at its
        // original date. That must not detach an already-posted reimbursement
        // from the exact recognition reviewed when the payment was committed.
        // Entered accounting/approval timestamps can be backdated. Immutable
        // audit sequence records the real committed posting order.
        final paidSequence = postingOrder[journalId];
        final sourceSequence = postingOrder[r.journal];
        if (paidSequence == null || sourceSequence == null) {
          throw StateError('Claim reimbursement posting order is unavailable.');
        }
        if (sourceSequence >= paidSequence ||
            (reversals[r.journal] ?? <JournalEntry>[]).any(
              (j) =>
                  postingOrder[j.id] == null ||
                  postingOrder[j.id]! <= paidSequence,
            )) {
          return false;
        }
        return jsonEncode({
              ...r.claim.toJson(),
              'status': ClaimStatus.approved.name,
            }) ==
            jsonEncode(
              Claim.fromJson(Map<String, dynamic>.from(reviewed)).toJson(),
            );
      }).toList();
      if (matching.length != 1 ||
          row['currency'] != paid.amount.currency ||
          row['amount_minor'] != paid.amount.minorUnits) {
        throw StateError(
          'A claim reimbursement has no exact recognized source.',
        );
      }
      add(
        paid,
        journalId,
        matching.single.account,
        ClaimantEventKind.reimbursement,
        -BigInt.from(row['amount_minor'] as int),
        reference: row['reference'] as String,
      );
    }
    for (final row in _claimExpenseRevisionSources(business)) {
      final original = Claim.fromJson(
        jsonDecode(row['claim_payload'] as String) as Map<String, dynamic>,
      );
      final draft = _expenseRevisionDraft(row['expense_payload'] as String);
      add(
        original,
        EntityId.parse(row['journal_id'] as String),
        EntityId.parse(row['liability_account_id'] as String),
        ClaimantEventKind.recognition,
        BigInt.from(
          Money.fromDecimal(draft.amount, draft.currencyCode).minorUnits,
        ),
      );
    }
    return ClaimantStatementReport.build(
      ledger: ledger,
      activity: events,
      controlAccountIds: recognitions.map((r) => r.account),
      currentlyAwaitingReview: _database
          .select(
            'SELECT payload FROM claims WHERE business_id=? AND ${_activeTransactionSql(TransactionRecordKind.claim)}',
            [business.value],
          )
          .map(
            (r) => Claim.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(r['payload'] as String) as Map,
              ),
            ),
          )
          .where((c) => c.status == ClaimStatus.submitted),
    );
  }
}

extension ClaimReimbursementReads on LocalAccountingDatabase {
  /// Uses the same validated historical sources as claimant statements. Payment
  /// commands call the internal reader inside their own fresh write snapshot.
  ClaimReimbursementPosition? readClaimReimbursementPosition({
    required EntityId businessId,
    required EntityId claimId,
    required DateTime through,
  }) => _readReportSnapshot(
    () => _claimReimbursementPosition(
      businessId: businessId,
      claimId: claimId,
      through: through,
    ),
  );
}
