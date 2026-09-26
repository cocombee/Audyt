part of 'accounting_database.dart';

extension ApprovedClaimExpensePersistence on LocalAccountingDatabase {
  /// Current transaction for this original submission, including pending edits
  /// and later posted corrections. The immutable Claim remains a separate
  /// submission snapshot. Resolve lineage and company in one SQLite query.
  ExpenseIntakeSummary? currentClaimExpenseSummary(
    EntityId businessId,
    EntityId claimId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT e.* FROM all_claim_postings p '
      'JOIN $_currentExpenseTable e ON e.business_id=p.business_id AND e.id=p.journal_id '
      'JOIN journal_entries j ON j.business_id=e.business_id AND j.id=e.journal_id '
      "WHERE p.business_id=? AND p.claim_id=? AND e.archived_at IS NULL AND j.state='posted' "
      "AND json_extract(e.payload,'\$.claimSource.claimId')=p.claim_id "
      "AND json_extract(e.payload,'\$.claimSource.recognitionId')=p.journal_id "
      "AND NOT EXISTS(SELECT 1 FROM journal_entries r WHERE r.business_id=j.business_id AND r.reverses_id=j.id AND r.state='posted')",
      [businessId.value, claimId.value],
    );
    if (rows.length > 1) {
      throw StateError('Claim has conflicting current Expenses.');
    }
    return rows.isEmpty ? null : _expenseSummary(rows.single);
  }

  List<Row> _claimExpenseRevisionSources(EntityId businessId) =>
      _hasExpenseRevisionViews
      ? _database.select(
          'SELECT e.journal_id,e.approved_at,e.revision,d.payload AS expense_payload,p.claim_payload,p.claim_id,p.liability_account_id '
          'FROM expense_revision_postings e JOIN expense_revision_drafts d '
          'ON d.business_id=e.business_id AND d.expense_id=e.expense_id AND d.revision=e.revision '
          'JOIN expense_intakes root ON root.business_id=e.business_id AND root.id=e.expense_id '
          'JOIN all_claim_postings p ON p.business_id=root.business_id AND p.journal_id=root.journal_id '
          "WHERE e.business_id=? AND json_extract(d.payload,'\$.claimSource') IS NOT NULL",
          [businessId.value],
        )
      : const [];

  RecordExpenseDraft _claimExpenseProjection(
    Row posting, {
    String? savedAccountName,
  }) {
    final business = EntityId.parse(posting['business_id'] as String);
    final recognition = EntityId.parse(posting['journal_id'] as String);
    final claim = Claim.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(posting['claim_payload'] as String) as Map,
      ),
    );
    final journal = _database.select(
      'SELECT * FROM journal_entries WHERE business_id=? AND id=? AND state=\'posted\'',
      [business.value, recognition.value],
    );
    final account = _database.select(
      'SELECT name FROM accounts WHERE business_id=? AND id=?',
      [business.value, posting['liability_account_id']],
    );
    final signature = jsonDecode(posting['signature'] as String) as List;
    final at = DateTime.parse(signature[4] as String);
    if (claim.id.value != posting['claim_id'] ||
        journal.length != 1 ||
        account.length != 1 ||
        LocalAccountingDatabase._calendarDay(
              DateTime.parse(journal.single['entry_date'] as String),
            ) !=
            LocalAccountingDatabase._calendarDay(claim.incurredOn!) ||
        DateTime.parse(journal.single['updated_at'] as String) != at) {
      throw const FormatException(
        'Claim Expense recognition provenance does not match its posted journal.',
      );
    }
    return approvedClaimExpense(
      claim: claim,
      recognitionId: recognition,
      liabilityAccountId: EntityId.parse(
        posting['liability_account_id'] as String,
      ),
      liabilityAccountName:
          savedAccountName ?? account.single['name'] as String,
      approvedAt: at,
    );
  }

  void _writeClaimExpenseInTransaction(Row posting) {
    final business = EntityId.parse(posting['business_id'] as String);
    final recognition = EntityId.parse(posting['journal_id'] as String);
    final existing = _database.select(
      'SELECT * FROM expense_intakes WHERE id=?',
      [recognition.value],
    );
    if (existing.isNotEmpty) {
      _validateClaimExpenseRow(existing.single);
      return;
    }
    final draft = _claimExpenseProjection(posting);
    final source = draft.claimSource!;
    final amount = Money.fromDecimal(draft.amount, draft.currencyCode);
    // A journal can be presented only once as this Claim's linked Expense.
    if (_database.select('SELECT 1 FROM expense_intakes WHERE journal_id=?', [
      recognition.value,
    ]).isNotEmpty) {
      throw const FormatException(
        'Claim recognition already has a different Expense link.',
      );
    }
    _database.execute(
      '''INSERT INTO expense_intakes(id,business_id,request_id,created_at,occurred_on,amount_minor,currency,payee,category,payload,journal_id)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
      [
        recognition.value,
        business.value,
        draft.submissionId,
        source.approvedAt.toUtc().toIso8601String(),
        LocalAccountingDatabase._calendarDay(
          parseAccountingInputDate(draft.date)!,
        ),
        amount.minorUnits,
        amount.currency,
        draft.payee,
        draft.category,
        jsonEncode(draft.toJson()),
        recognition.value,
      ],
    );
  }

  void _validateClaimExpenseRow(Row row) {
    final draft = RecordExpenseDraft.fromJson(
      Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
    );
    final source = draft.claimSource;
    if (source == null ||
        row['id'] != source.recognitionId.value ||
        row['journal_id'] != source.recognitionId.value ||
        row['archived_at'] != null) {
      throw const FormatException(
        'Approved Claim Expense link is missing or altered.',
      );
    }
    final postings = _database.select(
      'SELECT * FROM all_claim_postings WHERE business_id=? AND journal_id=?',
      [row['business_id'], source.recognitionId.value],
    );
    if (postings.length != 1) {
      throw const FormatException('Claim Expense recognition is unavailable.');
    }
    final expected = _claimExpenseProjection(
      postings.single,
      savedAccountName: draft.paymentAccount,
    );
    final amount = Money.fromDecimal(expected.amount, expected.currencyCode);
    if (draft.paymentAccount.trim().isEmpty ||
        jsonEncode(expected.toJson()) != jsonEncode(draft.toJson()) ||
        row['request_id'] != expected.submissionId ||
        row['created_at'] !=
            expected.claimSource!.approvedAt.toUtc().toIso8601String() ||
        row['occurred_on'] !=
            LocalAccountingDatabase._calendarDay(
              parseAccountingInputDate(expected.date)!,
            ) ||
        row['amount_minor'] != amount.minorUnits ||
        row['currency'] != amount.currency ||
        row['payee'] != expected.payee ||
        row['category'] != expected.category ||
        _database.select('SELECT 1 FROM expense_intakes WHERE journal_id=?', [
              source.recognitionId.value,
            ]).length !=
            1) {
      throw const FormatException(
        'Claim Expense differs from the immutable recognized Claim.',
      );
    }
  }

  void _validateClaimExpenseArchive({required bool requireComplete}) {
    final linkedJournals = <String>{};
    for (final row in _database.select('SELECT * FROM expense_intakes')) {
      final json = Map<String, dynamic>.from(
        jsonDecode(row['payload'] as String) as Map,
      );
      if (json['claimSource'] != null) {
        _validateClaimExpenseRow(row);
        linkedJournals.add(row['journal_id'] as String);
      } else if (_database.select(
        'SELECT 1 FROM all_claim_postings WHERE journal_id=?',
        [row['journal_id']],
      ).isNotEmpty) {
        throw const FormatException(
          'Claim journal cannot be presented as an unrelated Expense.',
        );
      }
    }
    if (requireComplete) {
      for (final posting in _database.select(
        'SELECT * FROM all_claim_postings',
      )) {
        if (!linkedJournals.contains(posting['journal_id'])) {
          throw const FormatException(
            'Approved Claim is missing its linked Expense.',
          );
        }
      }
    }
  }
}
