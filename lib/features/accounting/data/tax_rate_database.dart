part of 'accounting_database.dart';

extension CompanyTaxRatePersistence on LocalAccountingDatabase {
  List<CompanyTaxRate> readTaxRates(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM company_tax_rates WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
          [businessId.value],
        )
        .map(
          (r) => CompanyTaxRate.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  List<CompanyTaxRate> taxRateHistory(EntityId businessId, EntityId id) =>
      _database
          .select(
            'SELECT payload FROM company_tax_rate_history WHERE business_id=? AND id=? ORDER BY revision',
            [businessId.value, id.value],
          )
          .map(
            (r) => CompanyTaxRate.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
  CompanyTaxRate saveTaxRate({
    required EntityId businessId,
    required EntityId actorId,
    required CompanyTaxRate rate,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    late CompanyTaxRate result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final current = _database.select(
        'SELECT revision,payload FROM company_tax_rates WHERE business_id=? AND id=?',
        [businessId.value, rate.id.value],
      );
      final revision = current.isEmpty ? 0 : current.single['revision'] as int;
      if (revision != rate.revision) {
        throw StateError('Tax code changed. Reopen before saving.');
      }
      if (_database.select(
        'SELECT 1 FROM company_tax_rates WHERE business_id=? AND normalized_name=? AND id<>?',
        [businessId.value, rate.name.toLowerCase(), rate.id.value],
      ).isNotEmpty) {
        throw StateError('This tax name already exists.');
      }
      _validateTaxAgencySnapshot(businessId, rate.agencySnapshot);
      final oldAgency = current.isEmpty
          ? null
          : CompanyTaxRate.fromJson(
              jsonDecode(current.single['payload'] as String)
                  as Map<String, dynamic>,
            ).agencySnapshot;
      if (rate.agencySnapshot != null &&
          jsonEncode(rate.agencySnapshot!.toJson()) !=
              jsonEncode(oldAgency?.toJson()) &&
          !readTaxAgencies(businessId).any(
            (a) =>
                jsonEncode(a.toJson()) ==
                jsonEncode(rate.agencySnapshot!.toJson()),
          )) {
        throw StateError('Tax agency changed. Choose its current revision.');
      }
      if (rate.accountId != null &&
          _database.select(
            "SELECT 1 FROM accounts WHERE business_id=? AND id=? AND status='active' AND is_parent=0 AND type='liability'",
            [businessId.value, rate.accountId!.value],
          ).isEmpty) {
        throw StateError(
          'Choose an active tax liability account in this company.',
        );
      }
      result = CompanyTaxRate.fromJson({
        ...rate.toJson(),
        'revision': revision + 1,
      });
      final payload = jsonEncode(result.toJson());
      _database.execute(
        'INSERT INTO company_tax_rates(business_id,id,name,normalized_name,revision,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,normalized_name=excluded.normalized_name,revision=excluded.revision,payload=excluded.payload',
        [
          businessId.value,
          rate.id.value,
          rate.name,
          rate.name.toLowerCase(),
          revision + 1,
          payload,
        ],
      );
      _database.execute(
        'INSERT INTO company_tax_rate_history(business_id,id,revision,payload,saved_at) VALUES(?,?,?,?,?)',
        [
          businessId.value,
          rate.id.value,
          revision + 1,
          payload,
          savedAt.toUtc().toIso8601String(),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'tax_code_saved',
        subjectId: rate.id,
        detail: jsonEncode({'revision': revision + 1}),
      );
    });
    return result;
  }

  void _validateTaxArchive() {
    for (final row in _database.select('SELECT * FROM company_tax_rates')) {
      final business = EntityId.parse(row['business_id'] as String);
      final code = CompanyTaxRate.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final history = taxRateHistory(business, code.id);
      if (code.id.value != row['id'] ||
          code.name != row['name'] ||
          code.name.toLowerCase() != row['normalized_name'] ||
          code.revision != row['revision'] ||
          history.length != code.revision ||
          jsonEncode(history.last.toJson()) != row['payload'] ||
          (code.accountId != null &&
              _database.select(
                "SELECT 1 FROM accounts WHERE business_id=? AND id=? AND type='liability' AND is_parent=0",
                [business.value, code.accountId!.value],
              ).isEmpty)) {
        throw const FormatException(
          'Tax code archive identity or history is inconsistent.',
        );
      }
      for (final (i, version) in history.indexed) {
        _validateTaxAgencySnapshot(business, version.agencySnapshot);
        if (version.id != code.id ||
            version.revision != i + 1 ||
            (version.accountId != null &&
                _database.select(
                  "SELECT 1 FROM accounts WHERE business_id=? AND id=? AND type='liability' AND is_parent=0",
                  [business.value, version.accountId!.value],
                ).isEmpty)) {
          throw const FormatException(
            'Tax code archive revisions are inconsistent.',
          );
        }
      }
    }
    for (final row in _database.select(
      'SELECT business_id,payload FROM expense_intakes',
    )) {
      final draft = RecordExpenseDraft.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      if (draft.claimSource != null) {
        // Provenance was checked before tax recovery. Original receipt dates
        // remain authoritative in immutable Claim recognition validation below.
        continue;
      }
      _validateExpenseTaxSnapshots(
        EntityId.parse(row['business_id'] as String),
        draft,
        historical: true,
      );
    }
    for (final row in _database.select(
      'SELECT business_id,payload FROM claims',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final claim = Claim.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      _validateClaimTaxSnapshots(business, claim, historical: true);
      _validateRecognizedClaimReceiptFacts(business, claim);
    }
    for (final row in _database.select('SELECT * FROM all_claim_postings')) {
      final claim = Claim.fromJson(
        jsonDecode(row['claim_payload'] as String) as Map<String, dynamic>,
      );
      if (claim.receipts.isEmpty) continue;
      final business = EntityId.parse(row['business_id'] as String);
      _validateClaimTaxSnapshots(business, claim, historical: true);
      final debits = <String, BigInt>{};
      final credits = <String, BigInt>{};
      for (final line in _database.select(
        'SELECT * FROM journal_lines WHERE journal_id=?',
        [row['journal_id']],
      )) {
        if (line['currency'] != claim.amount.currency) {
          throw const FormatException(
            'Claim receipt posting currency mismatch.',
          );
        }
        final side = line['kind'] == 'debit' ? debits : credits;
        side.update(
          line['account_id'] as String,
          (old) => old + BigInt.from(line['amount_minor'] as int),
          ifAbsent: () => BigInt.from(line['amount_minor'] as int),
        );
      }
      final costs = claim.receiptCostAllocations;
      if (debits.length != costs.length ||
          costs.entries.any(
            (e) => debits[e.key.value] != BigInt.from(e.value.minorUnits),
          ) ||
          credits.length != 1 ||
          credits[row['liability_account_id']] !=
              BigInt.from(claim.amount.minorUnits)) {
        throw const FormatException(
          'Claim receipt recognition does not match its retained allocations.',
        );
      }
    }
    for (final row in _database.select(
      'SELECT business_id,paid_payload FROM claim_settlement_allocations',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final claim = Claim.fromJson(
        jsonDecode(row['paid_payload'] as String) as Map<String, dynamic>,
      );
      _validateClaimTaxSnapshots(business, claim, historical: true);
      _validateRecognizedClaimReceiptFacts(business, claim);
    }
    for (final row in _database.select(
      'SELECT * FROM claim_posting_reversals',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final reviewed = Claim.fromJson(
        jsonDecode(row['reviewed_payload'] as String) as Map<String, dynamic>,
      );
      final result = Claim.fromJson(
        jsonDecode(row['result_payload'] as String) as Map<String, dynamic>,
      );
      _validateClaimTaxSnapshots(business, reviewed, historical: true);
      _validateClaimTaxSnapshots(business, result, historical: true);
      final original = _database.select(
        'SELECT claim_payload FROM all_claim_postings WHERE business_id=? AND journal_id=?',
        [business.value, row['source_journal_id']],
      );
      if (original.length != 1) {
        throw const FormatException(
          'Claim correction has no retained recognition.',
        );
      }
      final recognized = Claim.fromJson(
        jsonDecode(original.single['claim_payload'] as String)
            as Map<String, dynamic>,
      );
      if ([reviewed, result, recognized].any((c) => c.receipts.isNotEmpty) &&
          (reviewed.id != recognized.id ||
              result.id != recognized.id ||
              _receiptFacts(reviewed) != _receiptFacts(recognized) ||
              _receiptFacts(result) != _receiptFacts(recognized))) {
        throw const FormatException(
          'Claim correction changed retained receipt facts.',
        );
      }
    }
  }

  String _receiptFacts(Claim claim) =>
      jsonEncode(claim.receipts.map((r) => r.toJson()).toList());

  void _validateRecognizedClaimReceiptFacts(EntityId business, Claim claim) {
    final active = _activeClaimPostings(business, claim.id);
    // Returned/void claims may have editable facts after reversal; their frozen
    // cycles are checked independently against their own journals above.
    if (active.isEmpty) return;
    final recognized = [
      for (final row in active)
        Claim.fromJson(
          jsonDecode(row['claim_payload'] as String) as Map<String, dynamic>,
        ),
    ];
    if (claim.receipts.isEmpty && recognized.every((c) => c.receipts.isEmpty)) {
      return; // Keep legacy recovery policy unchanged.
    }
    if (recognized.length != 1 ||
        !const {
          ClaimStatus.approved,
          ClaimStatus.paid,
        }.contains(claim.status) ||
        _receiptFacts(claim) != _receiptFacts(recognized.single)) {
      throw const FormatException(
        'Claim receipt facts no longer match the active recognized costs.',
      );
    }
  }

  void _validateClaimTaxSnapshots(
    EntityId businessId,
    Claim claim, {
    Claim? existing,
    bool historical = false,
  }) {
    if (claim.expenseDraft != null) {
      _validateExpenseTaxSnapshots(
        businessId,
        claim.expenseDraft!,
        existing: existing?.expenseDraft,
        historical: historical,
      );
    }
    if (claim.receipts.isEmpty) return;
    final current = readTaxRates(businessId);
    for (final receipt in claim.receipts) {
      final priorReceipt = existing?.receipts
          .where((r) => r.id == receipt.id)
          .firstOrNull;
      for (final line in receipt.lines) {
        final priorLine = priorReceipt?.lines
            .where((l) => l.item.id == line.item.id)
            .firstOrNull;
        final accounts = _database.select(
          'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, line.expenseAccountId.value],
        );
        if (accounts.length != 1 ||
            !const {'expense', 'asset'}.contains(accounts.single['type']) ||
            accounts.single['is_parent'] != 0 ||
            (!historical &&
                priorLine?.expenseAccountId != line.expenseAccountId &&
                accounts.single['status'] != 'active')) {
          throw StateError(
            'Select a valid expense or asset posting account in this company for each receipt row.',
          );
        }
        final code = line.item.taxSnapshot;
        if (code == null) {
          continue; // Explicit No Tax; domain calculation validates it.
        }
        final serialized = jsonEncode(code.toJson());
        if (!code.applies(
              receipt.date,
              TaxApplication.purchases,
              requireActive: false,
            ) ||
            !taxRateHistory(
              businessId,
              code.id,
            ).any((c) => jsonEncode(c.toJson()) == serialized) ||
            (!historical &&
                jsonEncode(priorLine?.item.taxSnapshot?.toJson()) !=
                    serialized &&
                !current.any(
                  (c) =>
                      c.applies(receipt.date, TaxApplication.purchases) &&
                      jsonEncode(c.toJson()) == serialized,
                ))) {
          throw StateError(
            'Purchase tax changed or is unavailable in this company for this receipt date. Review the row.',
          );
        }
      }
    }
  }

  void _validateExpenseTaxSnapshots(
    EntityId businessId,
    RecordExpenseDraft draft, {
    RecordExpenseDraft? existing,
    bool historical = false,
  }) {
    if (draft.taxReviewRequired) {
      throw StateError('Review tax for this recurring expense before saving.');
    }
    if (draft.taxMode == null) return;
    final date = parseAccountingInputDate(draft.date);
    if (date == null) throw const FormatException('Review the expense date.');
    final current = readTaxRates(businessId);
    for (final line in draft.lines) {
      final code = line.taxSnapshot;
      if (code == null) {
        continue; // Explicit No Tax, checked by draft validation.
      }
      final serialized = jsonEncode(code.toJson());
      final history = taxRateHistory(businessId, code.id);
      final retained = existing?.lines
          .where((saved) => saved.id == line.id)
          .firstOrNull
          ?.taxSnapshot;
      if (!code.applies(date, TaxApplication.purchases, requireActive: false) ||
          !history.any(
            (version) => jsonEncode(version.toJson()) == serialized,
          ) ||
          (!historical &&
              jsonEncode(retained?.toJson()) != serialized &&
              !current.any(
                (version) =>
                    version.applies(date, TaxApplication.purchases) &&
                    jsonEncode(version.toJson()) == serialized,
              ))) {
        throw StateError(
          'Purchase tax changed or is unavailable in this company. Review the row.',
        );
      }
    }
  }

  void _validateLineTaxSnapshots(
    EntityId businessId,
    List<SalesLineItem> lines,
    DateTime date,
    TaxApplication purpose,
  ) {
    for (final line in lines) {
      final code = line.taxSnapshot;
      if (code == null) continue;
      final history = taxRateHistory(businessId, code.id);
      if (!code.applies(date, purpose, requireActive: false) ||
          !history.any(
            (r) => jsonEncode(r.toJson()) == jsonEncode(code.toJson()),
          )) {
        throw StateError(
          'Tax snapshot is unavailable in this company or for this date.',
        );
      }
    }
  }
}
