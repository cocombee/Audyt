part of 'accounting_database.dart';

final class PurchaseBillDraftPage {
  const PurchaseBillDraftPage(this.records, this.total, this.offset);
  final List<PurchaseBillDraft> records;
  final int total, offset;
}

/// Recognition is separate from its immutable source and later settlements.
final class StoredPostedBill {
  const StoredPostedBill({
    required this.source,
    required this.journalId,
    required this.payableAccountId,
    required this.approvedAt,
  });
  final PurchaseBillDraft source;
  final EntityId journalId, payableAccountId;
  final DateTime approvedAt;
}

final class StoredBillReversal {
  const StoredBillReversal({
    required this.billId,
    required this.journalId,
    required this.sourceJournalId,
    required this.reversedOn,
    required this.reason,
    required this.approvedAt,
  });
  final EntityId billId, journalId, sourceJournalId;
  final DateTime reversedOn, approvedAt;
  final String reason;
}

extension PurchaseBillDraftPersistence on LocalAccountingDatabase {
  String _billSearchText(PurchaseBillDraft bill) => [
    bill.documentNumber,
    bill.vendorSnapshot.name,
    bill.supplierReference,
    bill.memo,
  ].join(' ').toLowerCase();

  PurchaseBillDraft _billDraftFromRow(Row row) {
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final bill = PurchaseBillDraft.fromJson(payload);
    if (bill.id.value != row['id'] ||
        bill.metadata.businessId.value != row['business_id'] ||
        bill.vendorSnapshot.id.value != row['vendor_id'] ||
        bill.metadata.revision != row['revision'] ||
        bill.documentNumber != row['document_number'] ||
        _billSearchText(bill) != row['search_text'] ||
        bill.metadata.updatedAt.toIso8601String() != row['updated_at'] ||
        PurchaseBillDraft.snapshotSignature(bill.toJson()) !=
            PurchaseBillDraft.snapshotSignature(payload)) {
      throw const FormatException(
        'Bill identity/revision differs from its snapshot.',
      );
    }
    return bill;
  }

  PurchaseBillDraft? readBillDraft(
    EntityId businessId,
    EntityId id, {
    bool includeRemoved = false,
  }) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bill_drafts WHERE business_id=? AND id=? AND ${includeRemoved ? '1' : _activeTransactionSql(TransactionRecordKind.bill)}',
      [businessId.value, id.value],
    );
    return rows.isEmpty ? null : _billDraftFromRow(rows.single);
  }

  List<PurchaseBillDraft> billDraftHistory(EntityId businessId, EntityId id) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM bill_draft_history WHERE business_id=? AND id=? ORDER BY revision',
            [businessId.value, id.value],
          )
          .map(_billDraftFromRow),
    );
  }

  PurchaseBillDraftPage billDraftPage({
    required EntityId businessId,
    String search = '',
    int offset = 0,
    int limit = 10,
    bool? posted = false,
    bool? reversed,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid bill directory range.');
    }
    final where = [
      'business_id=?',
      _activeTransactionSql(TransactionRecordKind.bill),
      'instr(search_text,?)>0',
      if (posted != null)
        '${posted ? '' : 'NOT '}EXISTS(SELECT 1 FROM bill_postings p WHERE p.business_id=bill_drafts.business_id AND p.bill_id=bill_drafts.id)',
      if (reversed != null)
        '${reversed ? '' : 'NOT '}EXISTS(SELECT 1 FROM bill_posting_reversals r WHERE r.business_id=bill_drafts.business_id AND r.bill_id=bill_drafts.id)',
    ].join(' AND ');
    final args = [businessId.value, search.trim().toLowerCase()];
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select(
                    'SELECT count(*) AS total FROM bill_drafts WHERE $where',
                    args,
                  )
                  .single['total']
              as int;
      final lastOffset = total == 0 ? 0 : ((total - 1) ~/ limit) * limit;
      final actualOffset = offset > lastOffset ? lastOffset : offset;
      final records = _database
          .select(
            'SELECT * FROM bill_drafts WHERE $where ORDER BY updated_at DESC,id LIMIT ? OFFSET ?',
            [...args, limit, actualOffset],
          )
          .map(_billDraftFromRow)
          .toList(growable: false);
      if (ownsSnapshot) _database.execute('COMMIT');
      return PurchaseBillDraftPage(
        List.unmodifiable(records),
        total,
        actualOffset,
      );
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Search current company Bills without decoding the whole source directory.
  /// Suggestions include drafts and posted sources; historical revisions are
  /// reached from the Bills page rather than returned as separate records.
  List<({PurchaseBillDraft bill, bool posted, bool reversed})>
  searchBillDrafts({
    required EntityId businessId,
    required String query,
    int limit = 12,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Choose 1–50 suggestions.');
    }
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    if (words.isEmpty) return const [];
    final where = StringBuffer(
      'b.business_id=? AND ${_activeTransactionSql(TransactionRecordKind.bill, alias: 'b')}',
    );
    final args = <Object?>[businessId.value];
    for (final word in words) {
      where.write(
        " AND (instr(b.search_text,?)>0 OR instr(lower(b.id),?)>0 OR "
        "instr(CASE WHEN r.bill_id IS NOT NULL THEN 'reversed bill' WHEN p.bill_id IS NULL THEN 'bill draft' ELSE 'bill' END,?)>0)",
      );
      args.addAll([word, word, word]);
    }
    return [
      for (final row in _database.select(
        'SELECT b.*,p.bill_id IS NOT NULL AS posted,r.bill_id IS NOT NULL AS reversed FROM bill_drafts b '
        'LEFT JOIN bill_postings p ON p.business_id=b.business_id AND p.bill_id=b.id '
        'LEFT JOIN bill_posting_reversals r ON r.business_id=b.business_id AND r.bill_id=b.id '
        'WHERE $where ORDER BY b.updated_at DESC,b.id LIMIT ?',
        [...args, limit],
      ))
        (
          bill: _billDraftFromRow(row),
          posted: row['posted'] == 1,
          reversed: row['reversed'] == 1,
        ),
    ];
  }

  void _validateBillDraftReferences(
    PurchaseBillDraft bill, {
    PurchaseBillDraft? previous,
  }) {
    final company = bill.metadata.businessId;
    final supplier = readVendor(company, bill.vendorSnapshot.id);
    final history = _database.select(
      'SELECT payload FROM vendor_history WHERE business_id=? AND id=? AND revision=?',
      [
        company.value,
        bill.vendorSnapshot.id.value,
        bill.vendorSnapshot.metadata.revision,
      ],
    );
    final vendorPayload = jsonEncode(bill.vendorSnapshot.toJson());
    final preservingSupplier =
        previous != null &&
        jsonEncode(previous.vendorSnapshot.toJson()) == vendorPayload;
    if (supplier == null ||
        history.length != 1 ||
        history.single['payload'] != vendorPayload ||
        (!preservingSupplier &&
            jsonEncode(supplier.toJson()) != vendorPayload)) {
      throw StateError(
        'Supplier changed. Review current vendor details before saving.',
      );
    }
    _validateLineTaxSnapshots(
      company,
      bill.lines,
      bill.bill.issueDate,
      TaxApplication.purchases,
    );
    for (final line in bill.lines) {
      final rows = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
        [company.value, line.categoryId!.value],
      );
      if (rows.length != 1 ||
          rows.single['status'] != 'active' ||
          rows.single['is_parent'] != 0 ||
          !const {'expense', 'asset'}.contains(rows.single['type'])) {
        throw StateError(
          'Choose an active purchase expense or asset account in this company.',
        );
      }
    }
    final number = _database.select(
      "SELECT number FROM document_numbers WHERE business_id=? AND document_type='bill' AND record_id=?",
      [company.value, bill.id.value],
    );
    if (number.length != 1 || number.single['number'] != bill.documentNumber) {
      throw StateError('Use this bill’s reserved document number.');
    }
  }

  void saveBillDraft({
    required EntityId businessId,
    required EntityId actorId,
    required PurchaseBillDraft bill,
    required int expectedRevision,
    DocumentRecurrenceRequest? recurrence,
  }) {
    _ensureOpen();
    if (businessId != bill.metadata.businessId ||
        expectedRevision < 0 ||
        bill.metadata.revision != expectedRevision + 1) {
      throw StateError('Bill must match the company and reviewed revision.');
    }
    final payload = jsonEncode(bill.toJson());
    _joinTransaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.bill,
        bill.id.value,
      );
      final rows = _database.select(
        'SELECT * FROM bill_drafts WHERE business_id=? AND id=?',
        [businessId.value, bill.id.value],
      );
      PurchaseBillDraft? previous;
      if (rows.isNotEmpty) {
        previous = _billDraftFromRow(rows.single);
        if (previous.metadata.revision == bill.metadata.revision &&
            rows.single['payload'] == payload) {
          if (recurrence != null) {
            _saveInlineDocumentSchedule(
              businessId,
              actorId,
              RecurringDocumentKind.bill,
              bill.id,
              bill.metadata.revision,
              recurrence,
              bill.metadata.updatedAt,
            );
          }
          return;
        }
        if (readBillPosting(businessId, bill.id) != null) {
          throw StateError(
            'Posted bills are immutable. Use a linked correction.',
          );
        }
        if (previous.metadata.revision != expectedRevision ||
            previous.metadata.createdAt != bill.metadata.createdAt ||
            previous.metadata.originDeviceId != bill.metadata.originDeviceId ||
            previous.documentNumber != bill.documentNumber ||
            !bill.metadata.updatedAt.isAfter(previous.metadata.updatedAt)) {
          throw StateError(
            'Bill changed. Reopen its saved revision before editing.',
          );
        }
      } else if (expectedRevision != 0 ||
          bill.metadata.createdAt != bill.metadata.updatedAt ||
          bill.metadata.originDeviceId.value !=
              _database.select(
                'SELECT device_id FROM local_workspace WHERE business_id=?',
                [businessId.value],
              ).single['device_id']) {
        throw StateError(
          'New bill drafts require their initial local revision.',
        );
      }
      _validateBillDraftReferences(bill, previous: previous);
      final values = [
        businessId.value,
        bill.id.value,
        bill.vendorSnapshot.id.value,
        bill.metadata.revision,
        bill.documentNumber,
        _billSearchText(bill),
        payload,
        bill.metadata.updatedAt.toIso8601String(),
      ];
      _database.execute(
        'INSERT INTO bill_drafts(business_id,id,vendor_id,revision,document_number,search_text,payload,updated_at) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET vendor_id=excluded.vendor_id,revision=excluded.revision,search_text=excluded.search_text,payload=excluded.payload,updated_at=excluded.updated_at',
        values,
      );
      _database.execute(
        'INSERT INTO bill_draft_history(business_id,id,vendor_id,revision,document_number,search_text,payload,updated_at) VALUES(?,?,?,?,?,?,?,?)',
        values,
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: bill.metadata.updatedAt,
        kind: 'bill.draft_saved',
        subjectId: bill.id,
        detail: jsonEncode({
          'revision': bill.metadata.revision,
          'vendorId': bill.vendorSnapshot.id.value,
          'payeeId': bill.vendorSnapshot.payeeId,
        }),
      );
      if (recurrence != null) {
        _saveInlineDocumentSchedule(
          businessId,
          actorId,
          RecurringDocumentKind.bill,
          bill.id,
          bill.metadata.revision,
          recurrence,
          bill.metadata.updatedAt,
        );
      }
    });
  }

  void _validateBillDraftArchive() {
    if (_database
            .select(
              "SELECT 1 FROM ledger_audit a LEFT JOIN bill_drafts b ON b.business_id=a.business_id AND b.id=a.subject_id WHERE (a.kind='bill.draft_saved' OR a.kind='bill.posted') AND b.id IS NULL LIMIT 1",
            )
            .isNotEmpty ||
        _database
            .select(
              "SELECT 1 FROM ledger_audit a LEFT JOIN bill_postings p ON p.business_id=a.business_id AND p.bill_id=a.subject_id WHERE a.kind='bill.posted' AND p.bill_id IS NULL LIMIT 1",
            )
            .isNotEmpty) {
      throw const FormatException(
        'A recorded bill or posting link is missing.',
      );
    }
    for (final row in _database.select('SELECT * FROM bill_drafts')) {
      final current = _billDraftFromRow(row);
      final history = billDraftHistory(current.metadata.businessId, current.id);
      if (history.length != current.metadata.revision ||
          history.isEmpty ||
          PurchaseBillDraft.snapshotSignature(history.last.toJson()) !=
              PurchaseBillDraft.snapshotSignature(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              )) {
        throw const FormatException('Bill draft history is incomplete.');
      }
      DateTime? previousTime;
      for (var index = 0; index < history.length; index++) {
        final item = history[index];
        final savedAudit = _database.select(
          "SELECT * FROM ledger_audit WHERE business_id=? AND kind='bill.draft_saved' AND subject_id=? AND json_extract(detail,'\$.revision')=?",
          [
            item.metadata.businessId.value,
            item.id.value,
            item.metadata.revision,
          ],
        );
        if (savedAudit.length != 1 ||
            savedAudit.single['actor_id'] !=
                _database.select(
                  'SELECT owner_id FROM local_workspace WHERE business_id=?',
                  [item.metadata.businessId.value],
                ).single['owner_id'] ||
            savedAudit.single['occurred_at'] !=
                item.metadata.updatedAt.toUtc().toIso8601String() ||
            savedAudit.single['detail'] !=
                jsonEncode({
                  'revision': item.metadata.revision,
                  'vendorId': item.vendorSnapshot.id.value,
                  'payeeId': item.vendorSnapshot.payeeId,
                })) {
          throw const FormatException(
            'Bill history differs from its saved audit evidence.',
          );
        }
        final vendor = _database.select(
          'SELECT payload FROM vendor_history WHERE business_id=? AND id=? AND revision=?',
          [
            item.metadata.businessId.value,
            item.vendorSnapshot.id.value,
            item.vendorSnapshot.metadata.revision,
          ],
        );
        if (item.metadata.revision != index + 1 ||
            item.metadata.createdAt != current.metadata.createdAt ||
            item.metadata.originDeviceId != current.metadata.originDeviceId ||
            item.documentNumber != current.documentNumber ||
            (index == 0 &&
                item.metadata.createdAt != item.metadata.updatedAt) ||
            (previousTime != null &&
                !item.metadata.updatedAt.isAfter(previousTime)) ||
            vendor.length != 1 ||
            vendor.single['payload'] !=
                jsonEncode(item.vendorSnapshot.toJson())) {
          throw const FormatException(
            'Bill history or supplier snapshot is inconsistent.',
          );
        }
        // Historical accounts may now be locked/reclassified. Their company
        // identity must still exist; new saves recheck posting eligibility.
        for (final line in item.lines) {
          if (_database.select(
                'SELECT 1 FROM accounts WHERE business_id=? AND id=?',
                [item.metadata.businessId.value, line.categoryId!.value],
              ).length !=
              1) {
            throw const FormatException(
              'Bill history has an unavailable account reference.',
            );
          }
        }
        previousTime = item.metadata.updatedAt;
      }
      final number = _database.select(
        "SELECT number FROM document_numbers WHERE business_id=? AND document_type='bill' AND record_id=?",
        [current.metadata.businessId.value, current.id.value],
      );
      if (number.length != 1 ||
          number.single['number'] != current.documentNumber) {
        throw const FormatException(
          'Bill number does not match its reservation.',
        );
      }
    }
    for (final row in _database.select('SELECT * FROM bill_postings')) {
      _billPostingFromRow(row);
    }
    if (_archiveTableNames().contains('bill_posting_reversals')) {
      _validateBillReversalArchive();
    }
  }

  String _billPostingSignature({
    required EntityId billId,
    required int revision,
    required EntityId payableAccountId,
    required EntityId actorId,
    required DateTime approvedAt,
  }) => jsonEncode([
    'purchase-cost-v1',
    billId.value,
    revision,
    payableAccountId.value,
    actorId.value,
    approvedAt.toUtc().toIso8601String(),
  ]);

  List<JournalLine> _billRecognitionLines(
    PurchaseBillDraft bill,
    EntityId payableAccountId,
  ) => [
    // Explicit gross purchase cost. No input-tax recovery or FX is inferred.
    for (final line in bill.lines)
      if (line.total.isPositive)
        JournalLine.debit(accountId: line.categoryId!, amount: line.total),
    JournalLine.credit(accountId: payableAccountId, amount: bill.total),
  ];

  StoredPostedBill _billPostingFromRow(Row row) {
    final company = EntityId.parse(row['business_id'] as String);
    final id = EntityId.parse(row['bill_id'] as String);
    final source = readBillDraft(company, id);
    final journalId = EntityId.parse(row['journal_id'] as String);
    final payableId = EntityId.parse(row['payable_account_id'] as String);
    final actorId = EntityId.parse(row['actor_id'] as String);
    final approvedAt = DateTime.parse(row['approved_at'] as String);
    final journal = _readJournal(journalId);
    final approval = _database.select(
      'SELECT * FROM journal_approvals WHERE business_id=? AND request_id=?',
      [company.value, row['request_id']],
    );
    final owner = _database.select(
      'SELECT owner_id FROM local_workspace WHERE business_id=?',
      [company.value],
    );
    final payable = _database.select(
      'SELECT 1 FROM accounts WHERE business_id=? AND id=?',
      [company.value, payableId.value],
    );
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='bill.posted' AND subject_id=?",
      [company.value, id.value],
    );
    if (source == null ||
        source.metadata.revision != row['revision'] ||
        row['request_id'] != journalId.value ||
        row['signature'] !=
            _billPostingSignature(
              billId: id,
              revision: source.metadata.revision,
              payableAccountId: payableId,
              actorId: actorId,
              approvedAt: approvedAt,
            ) ||
        owner.length != 1 ||
        owner.single['owner_id'] != actorId.value ||
        payable.length != 1 ||
        audit.length != 1 ||
        audit.single['actor_id'] != actorId.value ||
        audit.single['occurred_at'] != approvedAt.toUtc().toIso8601String() ||
        audit.single['detail'] !=
            jsonEncode({
              'journalId': journalId.value,
              'revision': source.metadata.revision,
              'taxTreatment': 'purchaseCost',
            }) ||
        journal == null ||
        journal.metadata.businessId != company ||
        journal.metadata.originDeviceId != source.metadata.originDeviceId ||
        journal.metadata.isTombstone ||
        journal.metadata.revision != 2 ||
        journal.metadata.createdAt != source.metadata.updatedAt ||
        journal.metadata.updatedAt != approvedAt ||
        journal.entry.state != JournalEntryState.posted ||
        journal.entry.reversesId != null ||
        journal.entry.isClosing ||
        journal.entry.date != source.bill.issueDate ||
        journal.entry.memo != 'Bill ${source.documentNumber}' ||
        LocalAccountingDatabase._lineSignature(journal.entry.lines) !=
            LocalAccountingDatabase._lineSignature(
              _billRecognitionLines(source, payableId),
            ) ||
        approval.length != 1 ||
        approval.single['journal_id'] != journalId.value ||
        approval.single['signature'] !=
            jsonEncode([
              journalId.value,
              1,
              actorId.value,
              approvedAt.toUtc().toIso8601String(),
            ])) {
      throw const FormatException(
        'Bill posting differs from its source or approved journal.',
      );
    }
    return StoredPostedBill(
      source: source,
      journalId: journalId,
      payableAccountId: payableId,
      approvedAt: approvedAt,
    );
  }

  StoredPostedBill? readBillPosting(EntityId businessId, EntityId billId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bill_postings WHERE business_id=? AND bill_id=?',
      [businessId.value, billId.value],
    );
    return rows.isEmpty ? null : _billPostingFromRow(rows.single);
  }

  String _billReversalReviewSignature(PurchaseBillDraft bill) => jsonEncode([
    PurchaseBillDraft.snapshotSignature({
      ...bill.toJson(),
      'attachments': <Object>[],
    }),
    for (final attachment in bill.attachments)
      [
        attachment.originalId,
        attachment.originalSha256,
        attachment.derivativeId,
        attachment.derivativeSha256,
        attachment.pdfSha256,
      ],
  ]);

  String _billReversalSignature({
    required PurchaseBillDraft bill,
    required EntityId sourceJournalId,
    required DateTime reversedOn,
    required String reason,
    required EntityId actorId,
    required DateTime approvedAt,
  }) => jsonEncode([
    'bill-reversal-v1',
    _billReversalReviewSignature(bill),
    sourceJournalId.value,
    accountingCalendarDate(reversedOn).toIso8601String(),
    reason,
    actorId.value,
    approvedAt.toUtc().toIso8601String(),
  ]);

  StoredBillReversal _billReversalFromRow(Row row) {
    final company = EntityId.parse(row['business_id'] as String);
    final billId = EntityId.parse(row['bill_id'] as String);
    final request = EntityId.parse(row['request_id'] as String);
    final sourceId = EntityId.parse(row['source_journal_id'] as String);
    final journalId = EntityId.parse(row['journal_id'] as String);
    final actor = EntityId.parse(row['actor_id'] as String);
    final date = DateTime.parse(row['reversed_on'] as String);
    final at = DateTime.parse(row['approved_at'] as String);
    final reason = row['reason'] as String;
    final posting = readBillPosting(company, billId);
    final source = _readJournal(sourceId);
    final journal = _readJournal(journalId);
    final approval = _database.select(
      'SELECT * FROM journal_approvals WHERE business_id=? AND request_id=?',
      [company.value, request.value],
    );
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='bill.reversed' AND subject_id=?",
      [company.value, billId.value],
    );
    final paymentCorrections = _database.select(
      'SELECT MAX(r.reversed_on) AS latest_date,MAX(r.approved_at) AS latest_at FROM bill_settlement_allocations a JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=? AND a.bill_id=?',
      [company.value, billId.value],
    ).single;
    if (posting == null ||
        posting.journalId != sourceId ||
        posting.source.metadata.revision != row['revision'] ||
        source == null ||
        journal == null ||
        journalId != request ||
        reason.trim() != reason ||
        reason.isEmpty ||
        reason.length > 500 ||
        date != accountingCalendarDate(date) ||
        date.isBefore(source.entry.date) ||
        !at.isAfter(posting.approvedAt) ||
        (paymentCorrections['latest_date'] != null &&
            date.isBefore(
              DateTime.parse(paymentCorrections['latest_date'] as String),
            )) ||
        (paymentCorrections['latest_at'] != null &&
            !at.isAfter(
              DateTime.parse(paymentCorrections['latest_at'] as String),
            )) ||
        row['signature'] !=
            _billReversalSignature(
              bill: posting.source,
              sourceJournalId: sourceId,
              reversedOn: date,
              reason: reason,
              actorId: actor,
              approvedAt: at,
            ) ||
        _database.select(
          'SELECT 1 FROM bill_settlement_allocations a LEFT JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=? AND a.bill_id=? AND r.source_request_id IS NULL LIMIT 1',
          [company.value, billId.value],
        ).isNotEmpty ||
        journal.metadata.businessId != company ||
        journal.metadata.originDeviceId !=
            posting.source.metadata.originDeviceId ||
        journal.metadata.isTombstone ||
        journal.metadata.revision != 2 ||
        journal.metadata.createdAt !=
            at.subtract(const Duration(microseconds: 1)) ||
        journal.metadata.updatedAt != at ||
        journal.entry.state != JournalEntryState.posted ||
        journal.entry.reversesId != sourceId ||
        journal.entry.date != date ||
        journal.entry.memo != 'Bill reversal: $reason' ||
        LocalAccountingDatabase._lineSignature(journal.entry.lines) !=
            LocalAccountingDatabase._lineSignature(
              source.entry.lines,
              reverse: true,
            ) ||
        approval.length != 1 ||
        approval.single['journal_id'] != request.value ||
        approval.single['signature'] !=
            jsonEncode([request.value, 1, actor.value, at.toIso8601String()]) ||
        audit.length != 1 ||
        audit.single['actor_id'] != actor.value ||
        audit.single['occurred_at'] != at.toIso8601String() ||
        audit.single['detail'] !=
            jsonEncode({
              'sourceJournalId': sourceId.value,
              'journalId': journalId.value,
              'revision': posting.source.metadata.revision,
              'reversedOn': date.toIso8601String(),
              'reason': reason,
            })) {
      throw const FormatException(
        'Bill reversal differs from its source or approved journal.',
      );
    }
    return StoredBillReversal(
      billId: billId,
      journalId: journalId,
      sourceJournalId: sourceId,
      reversedOn: date,
      reason: reason,
      approvedAt: at,
    );
  }

  StoredBillReversal? readBillReversal(EntityId businessId, EntityId billId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bill_posting_reversals WHERE business_id=? AND bill_id=?',
      [businessId.value, billId.value],
    );
    return rows.isEmpty ? null : _billReversalFromRow(rows.single);
  }

  void _validateBillReversalArchive() {
    for (final row in _database.select(
      'SELECT * FROM bill_posting_reversals',
    )) {
      _billReversalFromRow(row);
    }
    if (_database
            .select(
              "SELECT 1 FROM ledger_audit a LEFT JOIN bill_posting_reversals r ON r.business_id=a.business_id AND r.bill_id=a.subject_id WHERE a.kind='bill.reversed' AND r.bill_id IS NULL LIMIT 1",
            )
            .isNotEmpty ||
        _database
            .select(
              "SELECT 1 FROM bill_postings p JOIN journal_entries j ON j.business_id=p.business_id AND j.reverses_id=p.journal_id AND j.state='posted' LEFT JOIN bill_posting_reversals r ON r.business_id=p.business_id AND r.bill_id=p.bill_id WHERE r.bill_id IS NULL LIMIT 1",
            )
            .isNotEmpty) {
      throw const FormatException('Bill reversal lost its source link.');
    }
  }

  /// Reverse an unpaid posted purchase and its payable in one transaction.
  EntityId reverseBillRecognition({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required PurchaseBillDraft reviewedBill,
    required EntityId expectedRecognitionJournalId,
    required DateTime reversedOn,
    required String reason,
    required DateTime approvedAt,
  }) {
    _ensureOpen();
    final explanation = reason.trim();
    final date = accountingCalendarDate(reversedOn);
    final at = approvedAt.toUtc();
    if (explanation.isEmpty || explanation.length > 500) {
      throw ArgumentError('Enter a correction reason of 1–500 characters.');
    }
    final signature = _billReversalSignature(
      bill: reviewedBill,
      sourceJournalId: expectedRecognitionJournalId,
      reversedOn: date,
      reason: explanation,
      actorId: actorId,
      approvedAt: at,
    );
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT * FROM bill_posting_reversals WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError(
            'Bill reversal request was reused for different work.',
          );
        }
        _billReversalFromRow(retry.single);
        return;
      }
      final posting = readBillPosting(businessId, reviewedBill.id);
      if (posting == null ||
          posting.journalId != expectedRecognitionJournalId ||
          PurchaseBillDraft.snapshotSignature(posting.source.toJson()) !=
              PurchaseBillDraft.snapshotSignature(reviewedBill.toJson())) {
        throw StateError(
          'The reviewed Bill changed. Reopen before correcting.',
        );
      }
      if (readBillReversal(businessId, reviewedBill.id) != null) {
        throw StateError('This Bill has already been reversed.');
      }
      if (activeBillSettlementCount(businessId, reviewedBill.id) != 0) {
        throw StateError(
          'Correct linked Bill payments before reversing this purchase.',
        );
      }
      final paymentCorrections = _database.select(
        'SELECT MAX(r.reversed_on) AS latest_date,MAX(r.approved_at) AS latest_at FROM bill_settlement_allocations a JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=? AND a.bill_id=?',
        [businessId.value, reviewedBill.id.value],
      ).single;
      if ((paymentCorrections['latest_date'] != null &&
              date.isBefore(
                DateTime.parse(paymentCorrections['latest_date'] as String),
              )) ||
          (paymentCorrections['latest_at'] != null &&
              !at.isAfter(
                DateTime.parse(paymentCorrections['latest_at'] as String),
              ))) {
        throw StateError(
          'Reverse the Bill after its linked payment corrections.',
        );
      }
      final original = _readJournal(expectedRecognitionJournalId);
      if (original == null ||
          original.metadata.businessId != businessId ||
          original.metadata.isTombstone ||
          original.entry.state != JournalEntryState.posted ||
          original.entry.reversesId != null ||
          date.isBefore(original.entry.date) ||
          !at.isAfter(original.metadata.updatedAt) ||
          _readJournal(requestId) != null) {
        throw StateError(
          'The Bill recognition is unavailable or the correction time is stale.',
        );
      }
      _writeJournal(
        StoredJournalEntry(
          entry: original.entry.reversal(
            id: requestId,
            date: date,
            memo: 'Bill reversal: $explanation',
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: original.metadata.originDeviceId,
            createdAt: at.subtract(const Duration(microseconds: 1)),
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
          approvedAt: at,
        ),
        linkedBillReversal: expectedRecognitionJournalId,
      );
      _database.execute(
        'INSERT INTO bill_posting_reversals(business_id,bill_id,request_id,source_journal_id,journal_id,revision,reversed_on,reason,actor_id,approved_at,signature) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          reviewedBill.id.value,
          requestId.value,
          expectedRecognitionJournalId.value,
          requestId.value,
          reviewedBill.metadata.revision,
          date.toIso8601String(),
          explanation,
          actorId.value,
          at.toIso8601String(),
          signature,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: at,
        kind: 'bill.reversed',
        subjectId: reviewedBill.id,
        detail: jsonEncode({
          'sourceJournalId': expectedRecognitionJournalId.value,
          'journalId': requestId.value,
          'revision': reviewedBill.metadata.revision,
          'reversedOn': date.toIso8601String(),
          'reason': explanation,
        }),
      );
    });
    return requestId;
  }

  /// Approve the exact saved purchase cost and create its payable once.
  EntityId postBill({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required EntityId billId,
    required int expectedRevision,
    required EntityId payableAccountId,
    required DateTime approvedAt,
  }) {
    _ensureOpen();
    final signature = _billPostingSignature(
      billId: billId,
      revision: expectedRevision,
      payableAccountId: payableAccountId,
      actorId: actorId,
      approvedAt: approvedAt,
    );
    late EntityId result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retries = _database.select(
        'SELECT * FROM bill_postings WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retries.isNotEmpty) {
        if (retries.single['signature'] != signature) {
          throw StateError('Posting request was reused for different work.');
        }
        result = _billPostingFromRow(retries.single).journalId;
        return;
      }
      if (readBillPosting(businessId, billId) != null) {
        throw StateError('This bill is already posted.');
      }
      final bill = readBillDraft(businessId, billId);
      if (bill == null || bill.metadata.revision != expectedRevision) {
        throw StateError('The reviewed bill changed or is unavailable.');
      }
      _validateBillDraftReferences(bill, previous: bill);
      final account = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, payableAccountId.value],
      );
      if (account.length != 1 ||
          account.single['type'] != 'liability' ||
          account.single['status'] != 'active' ||
          account.single['is_parent'] != 0) {
        throw StateError(
          'Choose an active payable liability account in this company.',
        );
      }
      if (_readJournal(requestId) != null) {
        throw StateError('This request identity already belongs to a journal.');
      }
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: bill.bill.issueDate,
            memo: 'Bill ${bill.documentNumber}',
            lines: _billRecognitionLines(bill, payableAccountId),
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: bill.metadata.originDeviceId,
            createdAt: bill.metadata.updatedAt,
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
          approvedAt: approvedAt,
        ),
      );
      _database.execute(
        'INSERT INTO bill_postings(business_id,bill_id,request_id,journal_id,revision,payable_account_id,actor_id,approved_at,signature) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          billId.value,
          requestId.value,
          requestId.value,
          expectedRevision,
          payableAccountId.value,
          actorId.value,
          approvedAt.toUtc().toIso8601String(),
          signature,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: approvedAt,
        kind: 'bill.posted',
        subjectId: billId,
        detail: jsonEncode({
          'journalId': requestId.value,
          'revision': expectedRevision,
          'taxTreatment': 'purchaseCost',
        }),
      );
      result = requestId;
    });
    return result;
  }
}
