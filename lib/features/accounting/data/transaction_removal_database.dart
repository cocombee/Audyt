part of 'accounting_database.dart';

extension TransactionRemovalDatabase on LocalAccountingDatabase {
  Claim readRetainedClaim(EntityId businessId, EntityId id) => Claim.fromJson(
    jsonDecode(
      _removalSource(
            businessId,
            TransactionRecordKind.claim,
            id.value,
          )['payload']
          as String,
    ) as Map<String, dynamic>,
  );

  PaymentVoucher readRetainedVoucher(EntityId businessId, String id) =>
      PaymentVoucher.fromJson(
        jsonDecode(
          _removalSource(
                businessId,
                TransactionRecordKind.paymentVoucher,
                id,
              )['payload']
              as String,
        ) as Map<String, dynamic>,
      );
  static const _removalSources = {
    TransactionRecordKind.claim: 'claims',
    TransactionRecordKind.paymentVoucher: 'payment_vouchers',
    TransactionRecordKind.bill: 'bill_drafts',
    TransactionRecordKind.quotation: 'quotation_drafts',
    TransactionRecordKind.invoiceCredit: 'invoice_credit_drafts',
  };

  bool get _hasTransactionRemovalSchema => _database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='transaction_record_removals'",
      )
      .isNotEmpty;

  String _activeTransactionSql(TransactionRecordKind kind, {String? alias}) {
    if (!_hasTransactionRemovalSchema) return '1';
    final source = alias ?? _removalSources[kind]!;
    return "NOT EXISTS(SELECT 1 FROM transaction_record_removal_state tr "
        "WHERE tr.business_id=$source.business_id AND tr.kind='${kind.name}' "
        'AND tr.record_id=$source.id AND tr.removed=1)';
  }

  bool transactionRecordRemoved({
    required EntityId businessId,
    required TransactionRecordKind kind,
    required String recordId,
  }) {
    _ensureOpen();
    if (!_hasTransactionRemovalSchema) return false;
    return _database.select(
      'SELECT 1 FROM transaction_record_removal_state WHERE business_id=? AND kind=? AND record_id=? AND removed=1',
      [businessId.value, kind.name, recordId],
    ).isNotEmpty;
  }

  void _requireTransactionActive(
    EntityId businessId,
    TransactionRecordKind kind,
    String id,
  ) {
    if (transactionRecordRemoved(
      businessId: businessId,
      kind: kind,
      recordId: id,
    )) {
      throw StateError(
        'This record was removed. Restore it before making changes.',
      );
    }
  }

  Row _removalSource(
    EntityId businessId,
    TransactionRecordKind kind,
    String id,
  ) {
    final rows = _database.select(
      'SELECT * FROM ${_removalSources[kind]} WHERE business_id=? AND id=?',
      [businessId.value, id],
    );
    if (rows.isEmpty) {
      throw StateError('The record is unavailable in this company.');
    }
    return rows.single;
  }

  String? _transactionRemovalRestriction(
    EntityId businessId,
    TransactionRecordKind kind,
    Row source,
  ) {
    final id = source['id'] as String;
    bool exists(String sql) =>
        _database.select(sql, [businessId.value, id]).isNotEmpty;
    switch (kind) {
      case TransactionRecordKind.claim:
        final claim = Claim.fromJson(
          jsonDecode(source['payload'] as String) as Map<String, dynamic>,
        );
        if (exists(
              'SELECT 1 FROM all_claim_postings WHERE business_id=? AND claim_id=?',
            ) ||
            exists(
              'SELECT 1 FROM claim_settlement_allocations WHERE business_id=? AND claim_id=?',
            ) ||
            claim.paymentBatchId != null) {
          return 'This claim has recognition or payment history. Use its financial correction workflow.';
        }
        if (!const {
          ClaimStatus.draft,
          ClaimStatus.submitted,
          ClaimStatus.returned,
          ClaimStatus.declined,
        }.contains(claim.status)) {
          return 'Only unrecognized draft or review-stage claims can be removed.';
        }
      case TransactionRecordKind.paymentVoucher:
        final voucher = PaymentVoucher.fromJson(
          jsonDecode(source['payload'] as String) as Map<String, dynamic>,
        );
        if (!const {
              PaymentVoucherStatus.draft,
              PaymentVoucherStatus.pendingApproval,
            }.contains(voucher.status) ||
            voucher.paymentEvidence != null ||
            voucher.reconciliationEvidence != null ||
            voucher.paidAt != null ||
            voucher.reconciledAt != null ||
            voucher.approver != null ||
            exists(
              "SELECT 1 FROM ledger_audit WHERE business_id=? AND kind='voucher_control_confirmed' AND json_extract(detail,'\$.voucherId')=? AND json_extract(detail,'\$.status') NOT IN ('draft','pendingApproval')",
            )) {
          return 'This voucher has approval or payment history. Keep its source evidence.';
        }
      case TransactionRecordKind.bill:
        if (exists(
          'SELECT 1 FROM bill_postings WHERE business_id=? AND bill_id=?',
        )) {
          return 'This bill has posting history. Use its financial correction workflow.';
        }
      case TransactionRecordKind.quotation:
        final quotation = _quotationFromRow(source).quotation;
        if (quotation.convertedInvoiceId != null ||
            const {
              EstimateStatus.accepted,
              EstimateStatus.converted,
            }.contains(quotation.status) ||
            exists(
              "SELECT 1 FROM quotation_history WHERE business_id=? AND id=? AND json_extract(payload,'\$.status') IN ('accepted','converted')",
            )) {
          return 'This quotation has acceptance or conversion history. Keep its document lineage.';
        }
      case TransactionRecordKind.invoiceCredit:
        if (exists(
          'SELECT 1 FROM invoice_credit_postings WHERE business_id=? AND draft_id=?',
        )) {
          return 'This credit has posting history. Use its financial correction workflow.';
        }
    }
    if (kind == TransactionRecordKind.bill ||
        kind == TransactionRecordKind.quotation) {
      if (_database.select(
        "SELECT 1 FROM recurring_document_templates WHERE business_id=? AND json_extract(payload,'\$.kind')=? AND json_extract(payload,'\$.sourceId')=? AND json_extract(payload,'\$.cancelled')=0",
        [businessId.value, kind.name, id],
      ).isNotEmpty) {
        return 'Cancel the recurring schedule before removing its source.';
      }
    }
    return null;
  }

  TransactionRemovalReview reviewTransactionRemoval({
    required EntityId businessId,
    required TransactionRecordKind kind,
    required String recordId,
  }) {
    _ensureOpen();
    final source = _removalSource(businessId, kind, recordId);
    final state = !_hasTransactionRemovalSchema
        ? null
        : _database.select(
            'SELECT * FROM transaction_record_removal_state WHERE business_id=? AND kind=? AND record_id=?',
            [businessId.value, kind.name, recordId],
          ).firstOrNull;
    final payload =
        jsonDecode(source['payload'] as String) as Map<String, dynamic>;
    final (label, status) = switch (kind) {
      TransactionRecordKind.claim => (
        Claim.fromJson(payload).vendorName,
        Claim.fromJson(payload).status.label,
      ),
      TransactionRecordKind.paymentVoucher => (
        PaymentVoucher.fromJson(payload).reference,
        PaymentVoucher.fromJson(payload).status.label,
      ),
      TransactionRecordKind.bill => (
        source['document_number'] as String,
        'Draft',
      ),
      TransactionRecordKind.quotation => (
        source['document_number'] as String,
        switch (_quotationFromRow(source).quotation.status) {
          EstimateStatus.sent => 'Shared',
          EstimateStatus.draft => 'Draft',
          EstimateStatus.viewed => 'Viewed',
          EstimateStatus.accepted => 'Accepted',
          EstimateStatus.declined => 'Declined',
          EstimateStatus.closed => 'Closed',
          EstimateStatus.converted => 'Converted',
          EstimateStatus.expired => 'Expired',
        },
      ),
      TransactionRecordKind.invoiceCredit => (
        'Credit · ${_database.select('SELECT document_number FROM invoice_postings WHERE business_id=? AND invoice_id=?', [businessId.value, source['invoice_id']]).single['document_number']}',
        'Draft',
      ),
    };
    return TransactionRemovalReview(
      businessId: businessId,
      kind: kind,
      recordId: recordId,
      sourceFingerprint: sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'kind': kind.name,
                'source': {for (final key in source.keys) key: source[key]},
              }),
            ),
          )
          .toString(),
      revision: state?['revision'] as int? ?? 0,
      removed: state?['removed'] == 1,
      changedAt: state == null
          ? null
          : DateTime.parse(state['changed_at'] as String),
      label: label.isEmpty ? recordId : label,
      status: status,
      amount: switch (kind) {
        TransactionRecordKind.claim => Claim.fromJson(payload).amount,
        TransactionRecordKind.paymentVoucher => PaymentVoucher.fromJson(
          payload,
        ).amount,
        TransactionRecordKind.bill => _billDraftFromRow(source).total,
        TransactionRecordKind.quotation => _quotationFromRow(
          source,
        ).quotation.total,
        TransactionRecordKind.invoiceCredit => InvoiceCreditDraft.fromSnapshot(
          id: EntityId.parse(recordId),
          invoiceId: EntityId.parse(source['invoice_id'] as String),
          revision: source['revision'] as int,
          savedAt: DateTime.parse(source['saved_at'] as String),
          snapshot: payload,
        ).total,
      },
      restriction: _transactionRemovalRestriction(businessId, kind, source),
    );
  }

  ({List<TransactionRemovalReview> records, int total}) removedTransactionPage({
    required EntityId businessId,
    required TransactionRecordKind kind,
    int offset = 0,
    int limit = 5,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid removed-record page range.');
    }
    if (!_hasTransactionRemovalSchema) return (records: const [], total: 0);
    const where = 'business_id=? AND kind=? AND removed=1';
    final args = [businessId.value, kind.name];
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select(
                    'SELECT COUNT(*) AS n FROM transaction_record_removal_state WHERE $where',
                    args,
                  )
                  .single['n']
              as int;
      final page = (
        total: total,
        records: [
          for (final row in _database.select(
            'SELECT record_id FROM transaction_record_removal_state WHERE $where ORDER BY changed_at DESC,record_id LIMIT ? OFFSET ?',
            [...args, limit, offset],
          ))
            reviewTransactionRemoval(
              businessId: businessId,
              kind: kind,
              recordId: row['record_id'] as String,
            ),
        ],
      );
      if (ownsSnapshot) _database.execute('COMMIT');
      return page;
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  int setTransactionRemoved({
    required EntityId businessId,
    required EntityId actorId,
    required TransactionRemovalReview reviewed,
    required bool removed,
    required DateTime changedAt,
  }) {
    _ensureOpen();
    late int next;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      if (reviewed.businessId != businessId || reviewed.removed == removed) {
        throw StateError(
          'Review the current record before removing or restoring it.',
        );
      }
      final current = reviewTransactionRemoval(
        businessId: businessId,
        kind: reviewed.kind,
        recordId: reviewed.recordId,
      );
      final at = changedAt.toUtc().toIso8601String();
      final state = _database.select(
        'SELECT * FROM transaction_record_removal_state WHERE business_id=? AND kind=? AND record_id=?',
        [businessId.value, reviewed.kind.name, reviewed.recordId],
      ).firstOrNull;
      if (current.revision == reviewed.revision + 1 &&
          current.removed == removed &&
          current.sourceFingerprint == reviewed.sourceFingerprint &&
          state?['changed_at'] == at &&
          state?['actor_id'] == actorId.value &&
          state?['source_digest'] == reviewed.sourceFingerprint) {
        next = current.revision;
        return;
      }
      if (current.revision != reviewed.revision ||
          current.removed != reviewed.removed ||
          current.sourceFingerprint != reviewed.sourceFingerprint) {
        throw StateError(
          'The record changed. Reload and review it before removing or restoring.',
        );
      }
      if (current.restriction != null) throw StateError(current.restriction!);
      final source = _removalSource(
        businessId,
        reviewed.kind,
        reviewed.recordId,
      );
      final sourceAt = source['saved_at'] ?? source['updated_at'];
      if ((current.changedAt != null &&
              !changedAt.toUtc().isAfter(current.changedAt!)) ||
          (sourceAt is String &&
              !changedAt.toUtc().isAfter(DateTime.parse(sourceAt)))) {
        throw StateError('Removal and restore require a later time.');
      }
      next = current.revision + 1;
      final detail = jsonEncode({
        'kind': reviewed.kind.name,
        'recordId': reviewed.recordId,
        'revision': next,
        'removed': removed,
        'sourceDigest': reviewed.sourceFingerprint,
      });
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: changedAt,
        kind: removed
            ? 'transaction_record_removed'
            : 'transaction_record_restored',
        subjectId: businessId,
        detail: detail,
      );
      final audit =
          _database.select('SELECT last_insert_rowid() AS id').single['id']
              as int;
      _database.execute(
        'INSERT INTO transaction_record_removals(business_id,kind,record_id,revision,removed,changed_at,actor_id,source_digest,audit_sequence) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          reviewed.kind.name,
          reviewed.recordId,
          next,
          removed ? 1 : 0,
          at,
          actorId.value,
          reviewed.sourceFingerprint,
          audit,
        ],
      );
    });
    return next;
  }

  void _validateTransactionRemovalArchive() {
    final chains = <String, ({int revision, bool removed, DateTime at})>{};
    for (final row in _database.select(
      'SELECT * FROM transaction_record_removals ORDER BY business_id,kind,record_id,revision',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final kind = TransactionRecordKind.values.byName(row['kind'] as String);
      final id = row['record_id'] as String;
      final revision = row['revision'] as int;
      final removed = row['removed'] == 1;
      final at = DateTime.tryParse(row['changed_at'] as String);
      final digest = row['source_digest'] as String;
      final key = '${business.value}:${kind.name}:$id';
      final old = chains[key];
      if (id.isEmpty ||
          at == null ||
          !at.isUtc ||
          at.toIso8601String() != row['changed_at'] ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
          revision != (old?.revision ?? 0) + 1 ||
          removed == (old?.removed ?? false) ||
          (old != null && !at.isAfter(old.at))) {
        throw const FormatException('Invalid recoverable removal history.');
      }
      final actor = EntityId.parse(row['actor_id'] as String);
      try {
        _requireReconciliationOwner(business, actor);
        _removalSource(business, kind, id);
      } on StateError {
        throw const FormatException(
          'Removal history has an unavailable source or unauthorized actor.',
        );
      }
      final audit = _database.select(
        'SELECT * FROM ledger_audit WHERE sequence=?',
        [row['audit_sequence']],
      );
      final detail = jsonEncode({
        'kind': kind.name,
        'recordId': id,
        'revision': revision,
        'removed': removed,
        'sourceDigest': digest,
      });
      if (audit.length != 1 ||
          audit.single['business_id'] != business.value ||
          audit.single['actor_id'] != actor.value ||
          audit.single['occurred_at'] != row['changed_at'] ||
          audit.single['subject_id'] != business.value ||
          audit.single['kind'] !=
              (removed
                  ? 'transaction_record_removed'
                  : 'transaction_record_restored') ||
          audit.single['detail'] != detail) {
        throw const FormatException(
          'Removal history does not match its audit evidence.',
        );
      }
      chains[key] = (revision: revision, removed: removed, at: at);
    }
    for (final row in _database.select(
      'SELECT * FROM transaction_record_removal_state WHERE removed=1',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final kind = TransactionRecordKind.values.byName(row['kind'] as String);
      if (_transactionRemovalRestriction(
            business,
            kind,
            _removalSource(business, kind, row['record_id'] as String),
          ) !=
          null) {
        throw const FormatException(
          'A removed record has protected financial or schedule history.',
        );
      }
    }
  }

  void _createTransactionRemovalSchema() {
    _database.execute(
      "CREATE TABLE IF NOT EXISTS transaction_record_removals(business_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('claim','paymentVoucher','bill','quotation','invoiceCredit')),record_id TEXT NOT NULL CHECK(length(record_id)>0),revision INTEGER NOT NULL CHECK(revision>0),removed INTEGER NOT NULL CHECK(removed IN (0,1)),changed_at TEXT NOT NULL,actor_id TEXT NOT NULL,source_digest TEXT NOT NULL CHECK(length(source_digest)=64),audit_sequence INTEGER NOT NULL UNIQUE REFERENCES ledger_audit(sequence),PRIMARY KEY(business_id,kind,record_id,revision))",
    );
    _database.execute(
      'CREATE VIEW IF NOT EXISTS transaction_record_removal_state AS SELECT r.* FROM transaction_record_removals r WHERE NOT EXISTS(SELECT 1 FROM transaction_record_removals later WHERE later.business_id=r.business_id AND later.kind=r.kind AND later.record_id=r.record_id AND later.revision>r.revision)',
    );
    _database.execute(
      "CREATE TRIGGER IF NOT EXISTS transaction_record_removals_validate_insert BEFORE INSERT ON transaction_record_removals WHEN NEW.revision != COALESCE((SELECT revision+1 FROM transaction_record_removal_state WHERE business_id=NEW.business_id AND kind=NEW.kind AND record_id=NEW.record_id),1) OR NEW.removed = COALESCE((SELECT removed FROM transaction_record_removal_state WHERE business_id=NEW.business_id AND kind=NEW.kind AND record_id=NEW.record_id),0) OR EXISTS(SELECT 1 FROM transaction_record_removal_state WHERE business_id=NEW.business_id AND kind=NEW.kind AND record_id=NEW.record_id AND changed_at>=NEW.changed_at) BEGIN SELECT RAISE(ABORT,'Invalid removal history transition'); END",
    );
    for (final operation in ['UPDATE', 'DELETE']) {
      _database.execute(
        "CREATE TRIGGER IF NOT EXISTS transaction_record_removals_no_${operation.toLowerCase()} BEFORE $operation ON transaction_record_removals BEGIN SELECT RAISE(ABORT,'Removal history is immutable'); END",
      );
    }
    for (final entry in _removalSources.entries) {
      _database.execute(
        "CREATE TRIGGER IF NOT EXISTS ${entry.value}_protect_removed_update BEFORE UPDATE ON ${entry.value} WHEN EXISTS(SELECT 1 FROM transaction_record_removal_state r WHERE r.business_id=OLD.business_id AND r.kind='${entry.key.name}' AND r.record_id=OLD.id AND r.removed=1) BEGIN SELECT RAISE(ABORT,'Restore the removed record before changing it'); END",
      );
      _database.execute(
        "CREATE TRIGGER IF NOT EXISTS ${entry.value}_retain_removed_history BEFORE DELETE ON ${entry.value} WHEN EXISTS(SELECT 1 FROM transaction_record_removals r WHERE r.business_id=OLD.business_id AND r.kind='${entry.key.name}' AND r.record_id=OLD.id) BEGIN SELECT RAISE(ABORT,'Removed and restored records are retained'); END",
      );
    }
    for (final entry in {
      'claim_postings': (TransactionRecordKind.claim, 'claim_id'),
      'claim_posting_cycles': (TransactionRecordKind.claim, 'claim_id'),
      'claim_settlement_allocations': (TransactionRecordKind.claim, 'claim_id'),
      'bill_postings': (TransactionRecordKind.bill, 'bill_id'),
      'invoice_credit_postings': (
        TransactionRecordKind.invoiceCredit,
        'draft_id',
      ),
    }.entries) {
      _database.execute(
        "CREATE TRIGGER IF NOT EXISTS ${entry.key}_protect_removed_insert BEFORE INSERT ON ${entry.key} WHEN EXISTS(SELECT 1 FROM transaction_record_removal_state r WHERE r.business_id=NEW.business_id AND r.kind='${entry.value.$1.name}' AND r.record_id=NEW.${entry.value.$2} AND r.removed=1) BEGIN SELECT RAISE(ABORT,'Removed records cannot be posted or settled'); END",
      );
    }
    for (final operation in ['INSERT', 'UPDATE']) {
      _database.execute(
        "CREATE TRIGGER IF NOT EXISTS recurring_documents_protect_removed_${operation.toLowerCase()} BEFORE $operation ON recurring_document_templates WHEN json_extract(NEW.payload,'\$.cancelled')=0 AND EXISTS(SELECT 1 FROM transaction_record_removal_state r WHERE r.business_id=NEW.business_id AND r.kind=json_extract(NEW.payload,'\$.kind') AND r.record_id=json_extract(NEW.payload,'\$.sourceId') AND r.removed=1) BEGIN SELECT RAISE(ABORT,'Restore the source before scheduling it'); END",
      );
    }
  }
}
