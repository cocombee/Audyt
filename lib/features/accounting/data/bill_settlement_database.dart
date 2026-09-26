part of 'accounting_database.dart';

/// The precise source and balance actually reviewed for one payment allocation.
final class BillSettlementAllocation {
  const BillSettlementAllocation({
    required this.billId,
    required this.revision,
    required this.expectedRemaining,
    required this.amount,
  });
  final EntityId billId;
  final int revision;
  final Money expectedRemaining, amount;

  List<Object> get signature => [
    billId.value,
    revision,
    expectedRemaining.minorUnits,
    amount.minorUnits,
    amount.currency,
  ];
}

final class StoredBillSettlement {
  StoredBillSettlement({
    required this.id,
    required this.businessId,
    required this.journalId,
    required this.bankAccountId,
    required this.paymentAccountId,
    required this.reference,
    required this.paidOn,
    required this.approvedAt,
    required this.actorId,
    required this.total,
    required List<BillSettlementAllocation> allocations,
  }) : allocations = List.unmodifiable(allocations);
  final EntityId id, businessId, journalId, bankAccountId, actorId;
  final String paymentAccountId, reference;
  final DateTime paidOn, approvedAt;
  final Money total;
  final List<BillSettlementAllocation> allocations;
}

final class StoredBillPaymentReversal {
  const StoredBillPaymentReversal({
    required this.paymentId,
    required this.journalId,
    required this.reversedOn,
    required this.reason,
    required this.approvedAt,
  });
  final EntityId paymentId, journalId;
  final DateTime reversedOn, approvedAt;
  final String reason;
}

enum PayableBillStatus { outstanding, unpaid, partiallyPaid, paid }

final class PayableBillRecord {
  const PayableBillRecord(this.source, this.remaining);
  final PurchaseBillDraft source;
  final Money remaining;
  String get status => remaining.isZero
      ? 'Paid'
      : remaining == source.total
      ? 'Unpaid'
      : 'Partially Paid';
}

final class PayableBillPage {
  const PayableBillPage(this.records, this.total, this.offset);
  final List<PayableBillRecord> records;
  final int total, offset;
}

extension BillSettlementPersistence on LocalAccountingDatabase {
  ({EntityId billId, EntityId requestId})? _billVoucherSourceIdentity(
    String id,
  ) {
    final parts = id.split('/');
    if (parts.length != 2) return null;
    try {
      return (
        billId: EntityId.parse(parts[0]),
        requestId: EntityId.parse(parts[1]),
      );
    } on FormatException {
      return null;
    }
  }

  List<PaymentVoucherSource> _billVoucherSources(
    EntityId company, {
    String? sourceId,
  }) {
    final identity = sourceId == null
        ? null
        : _billVoucherSourceIdentity(sourceId);
    if (sourceId != null && identity == null) return const [];
    final sources = <PaymentVoucherSource>[];
    for (final row in _database.select(
      'SELECT * FROM bill_settlements s WHERE business_id=?${identity == null ? '' : ' AND request_id=?'} AND NOT EXISTS(SELECT 1 FROM bill_settlement_reversals r WHERE r.business_id=s.business_id AND r.source_request_id=s.request_id) ORDER BY paid_on DESC,request_id',
      [company.value, if (identity != null) identity.requestId.value],
    )) {
      final payment = _billSettlementFromRow(row);
      for (final allocation in payment.allocations) {
        if (identity != null && allocation.billId != identity.billId) continue;
        final bill = readBillPosting(company, allocation.billId)!.source;
        sources.add(
          PaymentVoucherSource(
            type: PaymentVoucherSourceType.billSettlement,
            id: '${bill.id.value}/${payment.id.value}',
            payee: bill.vendorSnapshot.name,
            amount: allocation.amount,
            paymentAccountId: payment.paymentAccountId,
            date: payment.paidOn,
            detail:
                '${bill.documentNumber} · ${payment.id.value.substring(30)}',
          ),
        );
      }
    }
    return List.unmodifiable(sources);
  }

  /// SQL filters/counts balances before pagination. Only the requested page of
  /// immutable source payloads is decoded; paid rows cannot hide later bills.
  PayableBillPage payableBillPage({
    required EntityId businessId,
    String search = '',
    PayableBillStatus? status = PayableBillStatus.outstanding,
    int offset = 0,
    int limit = 10,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid payable bill directory range.');
    }
    final cte =
        'WITH payable AS (SELECT d.*,json_extract(d.payload,\'\$.bill.amountMinor\') AS original_minor,COALESCE((SELECT SUM(a.amount_minor) FROM bill_settlement_allocations a LEFT JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=d.business_id AND a.bill_id=d.id AND r.source_request_id IS NULL),0) AS paid_minor FROM bill_drafts d JOIN bill_postings p ON p.business_id=d.business_id AND p.bill_id=d.id WHERE d.business_id=? AND instr(d.search_text,?)>0 AND NOT EXISTS(SELECT 1 FROM bill_posting_reversals r WHERE r.business_id=d.business_id AND r.bill_id=d.id))';
    final predicate = switch (status) {
      null => '1',
      PayableBillStatus.outstanding => 'paid_minor<original_minor',
      PayableBillStatus.unpaid => 'paid_minor=0',
      PayableBillStatus.partiallyPaid =>
        'paid_minor>0 AND paid_minor<original_minor',
      PayableBillStatus.paid => 'paid_minor=original_minor',
    };
    final args = [businessId.value, search.trim().toLowerCase()];
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select(
                    '$cte SELECT count(*) AS total FROM payable WHERE $predicate',
                    args,
                  )
                  .single['total']
              as int;
      final lastOffset = total == 0 ? 0 : ((total - 1) ~/ limit) * limit;
      final actualOffset = offset > lastOffset ? lastOffset : offset;
      final records = _database
          .select(
            '$cte SELECT * FROM payable WHERE $predicate ORDER BY updated_at DESC,id LIMIT ? OFFSET ?',
            [...args, limit, actualOffset],
          )
          .map((row) {
            final source = _billDraftFromRow(row);
            final paid = row['paid_minor'] as int;
            if (paid < 0 || paid > source.total.minorUnits) {
              throw const FormatException(
                'Bill allocations exceed the payable.',
              );
            }
            return PayableBillRecord(
              source,
              source.total - Money.fromMinor(paid, source.total.currency),
            );
          })
          .toList(growable: false);
      if (ownsSnapshot) _database.execute('COMMIT');
      return PayableBillPage(List.unmodifiable(records), total, actualOffset);
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  int billSettlementCount(EntityId businessId, EntityId billId) {
    _ensureOpen();
    return _database.select(
          'SELECT count(*) AS total FROM bill_settlement_allocations WHERE business_id=? AND bill_id=?',
          [businessId.value, billId.value],
        ).single['total']
        as int;
  }

  int activeBillSettlementCount(EntityId businessId, EntityId billId) {
    _ensureOpen();
    return _database.select(
          'SELECT count(*) AS total FROM bill_settlement_allocations a LEFT JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=? AND a.bill_id=? AND r.source_request_id IS NULL',
          [businessId.value, billId.value],
        ).single['total']
        as int;
  }

  String _billSettlementSignature({
    required List<BillSettlementAllocation> allocations,
    required String paymentAccountId,
    required String reference,
    required DateTime paidOn,
    required DateTime approvedAt,
    required EntityId actorId,
  }) => jsonEncode([
    'bill-settlement-v1',
    allocations.map((a) => a.signature).toList(),
    paymentAccountId,
    reference,
    paidOn.toIso8601String(),
    actorId.value,
    approvedAt.toUtc().toIso8601String(),
  ]);

  Money billOutstanding(
    EntityId businessId,
    EntityId billId, {
    DateTime? asOf,
  }) {
    _ensureOpen();
    final posted = readBillPosting(businessId, billId);
    if (posted == null) throw StateError('Recognize the bill before payment.');
    final total = posted.source.total;
    final reversal = readBillReversal(businessId, billId);
    if (reversal != null &&
        (asOf == null ||
            !accountingCalendarDate(asOf).isBefore(reversal.reversedOn))) {
      return Money.zero(total.currency);
    }
    if (asOf != null &&
        accountingCalendarDate(asOf).isBefore(posted.source.bill.issueDate)) {
      return Money.zero(total.currency);
    }
    final row = _database.select(
      'SELECT COALESCE(SUM(a.amount_minor),0) AS paid,MIN(a.currency) AS first_currency,MAX(a.currency) AS last_currency FROM bill_settlement_allocations a JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id LEFT JOIN bill_settlement_reversals r ON r.business_id=s.business_id AND r.source_request_id=s.request_id WHERE a.business_id=? AND a.bill_id=?${asOf == null ? '' : ' AND s.paid_on<=?'}${asOf == null ? ' AND r.source_request_id IS NULL' : ' AND (r.source_request_id IS NULL OR r.reversed_on>?)'}',
      [
        businessId.value,
        billId.value,
        if (asOf != null) accountingCalendarDate(asOf).toIso8601String(),
        if (asOf != null) accountingCalendarDate(asOf).toIso8601String(),
      ],
    ).single;
    if ((row['first_currency'] != null &&
            row['first_currency'] != total.currency) ||
        (row['last_currency'] != null &&
            row['last_currency'] != total.currency)) {
      throw const FormatException(
        'Bill allocations have a different currency.',
      );
    }
    final paid = Money.fromMinor(row['paid'] as int, total.currency);
    if (paid.minorUnits > total.minorUnits) {
      throw const FormatException(
        'Bill allocations exceed the original payable.',
      );
    }
    return total - paid;
  }

  StoredBillSettlement? readBillSettlement(
    EntityId businessId,
    EntityId requestId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bill_settlements WHERE business_id=? AND request_id=?',
      [businessId.value, requestId.value],
    );
    return rows.isEmpty ? null : _billSettlementFromRow(rows.single);
  }

  List<StoredBillSettlement> billSettlementsForBill(
    EntityId businessId,
    EntityId billId, {
    int limit = 10,
    int offset = 0,
  }) {
    _ensureOpen();
    if (limit < 1 || limit > 100 || offset < 0) {
      throw ArgumentError('Invalid payment history range.');
    }
    return List.unmodifiable(
      _database
          .select(
            'SELECT s.* FROM bill_settlements s JOIN bill_settlement_allocations a ON a.business_id=s.business_id AND a.request_id=s.request_id WHERE a.business_id=? AND a.bill_id=? ORDER BY s.approved_at DESC,s.request_id LIMIT ? OFFSET ?',
            [businessId.value, billId.value, limit, offset],
          )
          .map(_billSettlementFromRow),
    );
  }

  List<JournalLine> _billPaymentLines(
    EntityId businessId,
    List<BillSettlementAllocation> allocations,
    EntityId bank,
    Money total,
  ) => [
    for (final a in allocations)
      JournalLine.debit(
        accountId: readBillPosting(businessId, a.billId)!.payableAccountId,
        amount: a.amount,
      ),
    JournalLine.credit(accountId: bank, amount: total),
  ];

  String _billPaymentAudit(StoredBillSettlement payment) => jsonEncode({
    'reference': payment.reference,
    'paymentAccountId': payment.paymentAccountId,
    'allocations': payment.allocations.map((a) => a.signature).toList(),
  });

  StoredBillSettlement _billSettlementFromRow(Row row) {
    final company = EntityId.parse(row['business_id'] as String);
    final id = EntityId.parse(row['request_id'] as String);
    final paidOn = DateTime.parse(row['paid_on'] as String);
    final at = DateTime.parse(row['approved_at'] as String);
    final actor = EntityId.parse(row['actor_id'] as String);
    final allocations = _database
        .select(
          'SELECT * FROM bill_settlement_allocations WHERE business_id=? AND request_id=? ORDER BY bill_id',
          [company.value, id.value],
        )
        .map(
          (a) => BillSettlementAllocation(
            billId: EntityId.parse(a['bill_id'] as String),
            revision: a['revision'] as int,
            expectedRemaining: Money.fromMinor(
              a['expected_remaining_minor'] as int,
              a['currency'] as String,
            ),
            amount: Money.fromMinor(
              a['amount_minor'] as int,
              a['currency'] as String,
            ),
          ),
        )
        .toList();
    var total = Money.zero(row['currency'] as String);
    if (allocations.isEmpty ||
        (row['reference'] as String).trim().isEmpty ||
        (row['reference'] as String).length > 120 ||
        row['reference'] != (row['reference'] as String).trim() ||
        paidOn != accountingCalendarDate(paidOn)) {
      throw const FormatException('Invalid saved bill payment.');
    }
    for (final a in allocations) {
      final posted = readBillPosting(company, a.billId);
      if (posted == null ||
          posted.source.metadata.revision != a.revision ||
          a.amount.currency != total.currency ||
          a.expectedRemaining.currency != total.currency ||
          !a.amount.isPositive ||
          a.amount.minorUnits > a.expectedRemaining.minorUnits ||
          a.expectedRemaining.minorUnits > posted.source.total.minorUnits ||
          paidOn.isBefore(posted.source.bill.issueDate) ||
          at.isBefore(posted.approvedAt)) {
        throw const FormatException(
          'Bill payment allocation differs from its recognized source.',
        );
      }
      total += a.amount;
    }
    if (_database.select(
      "SELECT 1 FROM journal_entries j WHERE j.business_id=? AND j.state='posted' AND ((j.reverses_id=? AND NOT EXISTS(SELECT 1 FROM bill_settlement_reversals r WHERE r.business_id=j.business_id AND r.source_request_id=? AND r.journal_id=j.id)) OR (j.reverses_id IN (SELECT journal_id FROM bill_postings WHERE business_id=? AND bill_id IN (SELECT bill_id FROM bill_settlement_allocations WHERE business_id=? AND request_id=?)) AND NOT EXISTS(SELECT 1 FROM bill_posting_reversals r WHERE r.business_id=j.business_id AND r.journal_id=j.id))) LIMIT 1",
      [
        company.value,
        id.value,
        id.value,
        company.value,
        company.value,
        id.value,
      ],
    ).isNotEmpty) {
      throw const FormatException(
        'Bill payment or its recognition has an unlinked reversal.',
      );
    }
    final payment = StoredBillSettlement(
      id: id,
      businessId: company,
      journalId: EntityId.parse(row['journal_id'] as String),
      bankAccountId: EntityId.parse(row['bank_account_id'] as String),
      paymentAccountId: row['payment_account_id'] as String,
      reference: row['reference'] as String,
      paidOn: paidOn,
      approvedAt: at,
      actorId: actor,
      total: total,
      allocations: allocations,
    );
    final journal = _readJournal(payment.journalId);
    final approval = _database.select(
      'SELECT * FROM journal_approvals WHERE business_id=? AND request_id=?',
      [company.value, id.value],
    );
    final identity = _database.select(
      'SELECT owner_id,device_id FROM local_workspace WHERE business_id=?',
      [company.value],
    );
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='bill.settled' AND subject_id=?",
      [company.value, id.value],
    );
    if (payment.journalId != id ||
        row['signature'] !=
            _billSettlementSignature(
              allocations: allocations,
              paymentAccountId: payment.paymentAccountId,
              reference: payment.reference,
              paidOn: paidOn,
              approvedAt: at,
              actorId: actor,
            ) ||
        identity.length != 1 ||
        identity.single['owner_id'] != actor.value ||
        paymentLedgerAccount(company, payment.paymentAccountId) !=
            payment.bankAccountId ||
        journal == null ||
        journal.metadata.businessId != company ||
        journal.metadata.originDeviceId.value != identity.single['device_id'] ||
        journal.metadata.isTombstone ||
        journal.metadata.revision != 2 ||
        journal.metadata.createdAt !=
            at.subtract(const Duration(microseconds: 1)) ||
        journal.metadata.updatedAt != at ||
        journal.entry.state != JournalEntryState.posted ||
        journal.entry.reversesId != null ||
        journal.entry.isClosing ||
        journal.entry.date != paidOn ||
        journal.entry.memo != 'Bill payment ${payment.reference}' ||
        LocalAccountingDatabase._lineSignature(journal.entry.lines) !=
            LocalAccountingDatabase._lineSignature(
              _billPaymentLines(
                company,
                allocations,
                payment.bankAccountId,
                total,
              ),
            ) ||
        approval.length != 1 ||
        approval.single['journal_id'] != id.value ||
        approval.single['signature'] !=
            jsonEncode([
              id.value,
              1,
              actor.value,
              at.toUtc().toIso8601String(),
            ]) ||
        audit.length != 1 ||
        audit.single['actor_id'] != actor.value ||
        audit.single['occurred_at'] != at.toUtc().toIso8601String() ||
        audit.single['detail'] != _billPaymentAudit(payment)) {
      throw const FormatException(
        'Bill payment differs from its exact approved journal or audit.',
      );
    }
    return payment;
  }

  String _billPaymentReversalSignature({
    required String sourceSignature,
    required DateTime reversedOn,
    required String reason,
    required EntityId actorId,
    required DateTime approvedAt,
  }) => jsonEncode([
    'bill-payment-reversal-v1',
    sourceSignature,
    accountingCalendarDate(reversedOn).toIso8601String(),
    reason,
    actorId.value,
    approvedAt.toUtc().toIso8601String(),
  ]);

  StoredBillPaymentReversal _billPaymentReversalFromRow(Row row) {
    final company = EntityId.parse(row['business_id'] as String);
    final paymentId = EntityId.parse(row['source_request_id'] as String);
    final request = EntityId.parse(row['request_id'] as String);
    final sourceId = EntityId.parse(row['source_journal_id'] as String);
    final journalId = EntityId.parse(row['journal_id'] as String);
    final actor = EntityId.parse(row['actor_id'] as String);
    final date = DateTime.parse(row['reversed_on'] as String);
    final at = DateTime.parse(row['approved_at'] as String);
    final reason = row['reason'] as String;
    final sourceRows = _database.select(
      'SELECT * FROM bill_settlements WHERE business_id=? AND request_id=?',
      [company.value, paymentId.value],
    );
    final payment = sourceRows.length == 1
        ? _billSettlementFromRow(sourceRows.single)
        : null;
    final original = _readJournal(sourceId);
    final journal = _readJournal(journalId);
    final approval = _database.select(
      'SELECT * FROM journal_approvals WHERE business_id=? AND request_id=?',
      [company.value, request.value],
    );
    final audit = _database.select(
      "SELECT * FROM ledger_audit WHERE business_id=? AND kind='bill.payment_reversed' AND subject_id=?",
      [company.value, paymentId.value],
    );
    if (payment == null ||
        sourceId != payment.journalId ||
        journalId != request ||
        reason.isEmpty ||
        reason != reason.trim() ||
        reason.length > 500 ||
        date != accountingCalendarDate(date) ||
        date.isBefore(payment.paidOn) ||
        !at.isAfter(payment.approvedAt) ||
        row['signature'] !=
            _billPaymentReversalSignature(
              sourceSignature: sourceRows.single['signature'] as String,
              reversedOn: date,
              reason: reason,
              actorId: actor,
              approvedAt: at,
            ) ||
        _database.select(
          "SELECT 1 FROM payment_vouchers WHERE business_id=? AND json_extract(payload,'\$.sourceType')='billSettlement' AND substr(json_extract(payload,'\$.sourceId'),-?)=? LIMIT 1",
          [company.value, paymentId.value.length + 1, '/${paymentId.value}'],
        ).isNotEmpty ||
        _journalAlreadyMatched(company, sourceId) ||
        original == null ||
        original.metadata.businessId != company ||
        original.entry.state != JournalEntryState.posted ||
        journal == null ||
        journal.metadata.businessId != company ||
        journal.metadata.originDeviceId != original.metadata.originDeviceId ||
        journal.metadata.isTombstone ||
        journal.metadata.revision != 2 ||
        journal.metadata.createdAt !=
            at.subtract(const Duration(microseconds: 1)) ||
        journal.metadata.updatedAt != at ||
        journal.entry.state != JournalEntryState.posted ||
        journal.entry.reversesId != sourceId ||
        journal.entry.date != date ||
        journal.entry.memo != 'Bill payment reversal: $reason' ||
        LocalAccountingDatabase._lineSignature(journal.entry.lines) !=
            LocalAccountingDatabase._lineSignature(
              original.entry.lines,
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
              'reversedOn': date.toIso8601String(),
              'reason': reason,
            })) {
      throw const FormatException(
        'Bill payment reversal differs from its source or approved journal.',
      );
    }
    return StoredBillPaymentReversal(
      paymentId: paymentId,
      journalId: journalId,
      reversedOn: date,
      reason: reason,
      approvedAt: at,
    );
  }

  StoredBillPaymentReversal? readBillPaymentReversal(
    EntityId businessId,
    EntityId paymentId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bill_settlement_reversals WHERE business_id=? AND source_request_id=?',
      [businessId.value, paymentId.value],
    );
    return rows.isEmpty ? null : _billPaymentReversalFromRow(rows.single);
  }

  EntityId reverseBillPayment({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required EntityId sourcePaymentId,
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
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final sourceRows = _database.select(
        'SELECT * FROM bill_settlements WHERE business_id=? AND request_id=?',
        [businessId.value, sourcePaymentId.value],
      );
      if (sourceRows.length != 1) {
        throw StateError('Bill payment is unavailable.');
      }
      final source = _billSettlementFromRow(sourceRows.single);
      final signature = _billPaymentReversalSignature(
        sourceSignature: sourceRows.single['signature'] as String,
        reversedOn: date,
        reason: explanation,
        actorId: actorId,
        approvedAt: at,
      );
      final retry = _database.select(
        'SELECT * FROM bill_settlement_reversals WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['source_request_id'] != sourcePaymentId.value ||
            retry.single['signature'] != signature) {
          throw StateError('Bill payment reversal request was reused.');
        }
        _billPaymentReversalFromRow(retry.single);
        return;
      }
      if (readBillPaymentReversal(businessId, sourcePaymentId) != null ||
          date.isBefore(source.paidOn) ||
          !at.isAfter(source.approvedAt) ||
          _readJournal(requestId) != null) {
        throw StateError(
          'Bill payment correction is stale or already recorded.',
        );
      }
      if (_database.select(
            "SELECT 1 FROM payment_vouchers WHERE business_id=? AND json_extract(payload,'\$.sourceType')='billSettlement' AND substr(json_extract(payload,'\$.sourceId'),-?)=? LIMIT 1",
            [
              businessId.value,
              sourcePaymentId.value.length + 1,
              '/${sourcePaymentId.value}',
            ],
          ).isNotEmpty ||
          _journalAlreadyMatched(businessId, source.journalId)) {
        throw StateError(
          'Unlink the payment voucher or bank statement match before correcting this payment.',
        );
      }
      final original = _readJournal(source.journalId)!;
      _writeJournal(
        StoredJournalEntry(
          entry: original.entry.reversal(
            id: requestId,
            date: date,
            memo: 'Bill payment reversal: $explanation',
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
        linkedBillPaymentReversal: source.journalId,
      );
      _database.execute(
        'INSERT INTO bill_settlement_reversals(business_id,source_request_id,request_id,source_journal_id,journal_id,reversed_on,reason,actor_id,approved_at,signature) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          sourcePaymentId.value,
          requestId.value,
          source.journalId.value,
          requestId.value,
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
        kind: 'bill.payment_reversed',
        subjectId: sourcePaymentId,
        detail: jsonEncode({
          'sourceJournalId': source.journalId.value,
          'journalId': requestId.value,
          'reversedOn': date.toIso8601String(),
          'reason': explanation,
        }),
      );
    });
    return requestId;
  }

  void _validateBillSettlementArchive() {
    if (_database
        .select(
          "SELECT 1 FROM ledger_audit a LEFT JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.subject_id WHERE a.kind='bill.settled' AND s.request_id IS NULL LIMIT 1",
        )
        .isNotEmpty) {
      throw const FormatException('Bill payment audit lost its source.');
    }
    for (final row in _database.select('SELECT * FROM bill_settlements')) {
      _billSettlementFromRow(row);
    }
    for (final row in _database.select(
      'SELECT * FROM bill_settlement_reversals',
    )) {
      _billPaymentReversalFromRow(row);
    }
    if (_database
            .select(
              "SELECT 1 FROM ledger_audit a LEFT JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.subject_id WHERE a.kind='bill.payment_reversed' AND r.source_request_id IS NULL LIMIT 1",
            )
            .isNotEmpty ||
        _database
            .select(
              "SELECT 1 FROM bill_settlements s JOIN journal_entries j ON j.business_id=s.business_id AND j.reverses_id=s.journal_id AND j.state='posted' LEFT JOIN bill_settlement_reversals r ON r.business_id=s.business_id AND r.source_request_id=s.request_id WHERE r.source_request_id IS NULL LIMIT 1",
            )
            .isNotEmpty) {
      throw const FormatException(
        'Bill payment reversal lost its source link.',
      );
    }
    for (final bill in _database.select(
      'SELECT DISTINCT business_id,bill_id FROM bill_settlement_allocations',
    )) {
      final company = EntityId.parse(bill['business_id'] as String),
          id = EntityId.parse(bill['bill_id'] as String);
      var remaining = readBillPosting(company, id)!.source.total.minorUnits;
      DateTime? approved;
      for (final row in _database.select(
        "SELECT a.expected_remaining_minor,a.amount_minor,s.approved_at AS event_at,0 AS reversed FROM bill_settlement_allocations a JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id WHERE a.business_id=? AND a.bill_id=? UNION ALL SELECT a.expected_remaining_minor,a.amount_minor,r.approved_at AS event_at,1 AS reversed FROM bill_settlement_allocations a JOIN bill_settlement_reversals r ON r.business_id=a.business_id AND r.source_request_id=a.request_id WHERE a.business_id=? AND a.bill_id=? ORDER BY event_at,reversed",
        [company.value, id.value, company.value, id.value],
      )) {
        final at = DateTime.parse(row['event_at'] as String);
        final isReversal = row['reversed'] == 1;
        if ((!isReversal && row['expected_remaining_minor'] != remaining) ||
            (approved != null && at.isBefore(approved))) {
          throw const FormatException(
            'Bill payment balance chain is incomplete or stale.',
          );
        }
        remaining += (isReversal ? 1 : -1) * (row['amount_minor'] as int);
        if (remaining < 0 ||
            remaining > readBillPosting(company, id)!.source.total.minorUnits) {
          throw const FormatException('Bill payment balance chain is invalid.');
        }
        approved = at;
      }
    }
  }

  StoredBillSettlement settleRecognizedBills({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required List<BillSettlementAllocation> allocations,
    required String paymentAccountId,
    required String paymentReference,
    required DateTime paidOn,
    required DateTime approvedAt,
  }) {
    _ensureOpen();
    final reference = paymentReference.trim(),
        date = accountingCalendarDate(paidOn),
        at = approvedAt.toUtc();
    final ordered = [...allocations]
      ..sort((a, b) => a.billId.value.compareTo(b.billId.value));
    if (ordered.isEmpty ||
        ordered.map((a) => a.billId).toSet().length != ordered.length ||
        reference.isEmpty ||
        reference.length > 120 ||
        ordered.any(
          (a) =>
              a.revision < 1 ||
              !a.amount.isPositive ||
              !a.expectedRemaining.isPositive ||
              a.amount.currency != a.expectedRemaining.currency ||
              a.amount.minorUnits > a.expectedRemaining.minorUnits,
        )) {
      throw ArgumentError(
        'Review positive bill allocations, payment date and reference.',
      );
    }
    final signature = _billSettlementSignature(
      allocations: ordered,
      paymentAccountId: paymentAccountId,
      reference: reference,
      paidOn: date,
      approvedAt: at,
      actorId: actorId,
    );
    late StoredBillSettlement result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final retry = _database.select(
        'SELECT * FROM bill_settlements WHERE business_id=? AND request_id=?',
        [businessId.value, requestId.value],
      );
      if (retry.isNotEmpty) {
        if (retry.single['signature'] != signature) {
          throw StateError(
            'Bill payment request was reused for different work.',
          );
        }
        result = _billSettlementFromRow(retry.single);
        return;
      }
      if (_readJournal(requestId) != null) {
        throw StateError('This payment identity already belongs to a journal.');
      }
      final payment = readPaymentAccounts(businessId)
          .where((p) => p.id == paymentAccountId)
          .firstOrNull;
      final bank = paymentLedgerAccount(businessId, paymentAccountId);
      if (payment == null ||
          bank == null ||
          payment.type == PaymentAccountType.card ||
          payment.currency.code != ordered.first.amount.currency) {
        throw StateError(
          'Choose a saved bank/cash payment account with its exact linked ledger and currency.',
        );
      }
      final account = _database.select(
        'SELECT * FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, bank.value],
      );
      if (account.length != 1 ||
          account.single['type'] != AccountType.asset.name ||
          account.single['status'] != AccountStatus.active.name ||
          account.single['is_parent'] != 0) {
        throw StateError('Choose an active bank/cash asset posting account.');
      }
      var total = Money.zero(payment.currency.code);
      for (final a in ordered) {
        final posted = readBillPosting(businessId, a.billId);
        final previous =
            _database.select(
                  'SELECT MAX(s.approved_at) AS latest FROM bill_settlement_allocations a JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id WHERE a.business_id=? AND a.bill_id=?',
                  [businessId.value, a.billId.value],
                ).single['latest']
                as String?;
        if (posted == null ||
            readBillReversal(businessId, a.billId) != null ||
            posted.source.metadata.revision != a.revision ||
            a.amount.currency != total.currency ||
            a.amount.currency != posted.source.total.currency ||
            a.expectedRemaining != billOutstanding(businessId, a.billId) ||
            date.isBefore(posted.source.bill.issueDate) ||
            at.isBefore(posted.approvedAt) ||
            previous != null && at.isBefore(DateTime.parse(previous))) {
          throw StateError(
            'The reviewed bill or balance changed. Review the current outstanding amount.',
          );
        }
        total += a.amount;
      }
      final device = EntityId.parse(
        _database.select(
              'SELECT device_id FROM local_workspace WHERE business_id=?',
              [businessId.value],
            ).single['device_id']
            as String,
      );
      _writeJournal(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: requestId,
            date: date,
            memo: 'Bill payment $reference',
            lines: _billPaymentLines(businessId, ordered, bank, total),
          ),
          metadata: RecordMetadata.initial(
            recordId: requestId,
            businessId: businessId,
            originDeviceId: device,
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
      );
      _database.execute(
        'INSERT INTO bill_settlements(business_id,request_id,journal_id,payment_account_id,bank_account_id,reference,currency,paid_on,actor_id,approved_at,signature) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          requestId.value,
          requestId.value,
          paymentAccountId,
          bank.value,
          reference,
          total.currency,
          date.toIso8601String(),
          actorId.value,
          at.toIso8601String(),
          signature,
        ],
      );
      for (final a in ordered) {
        _database.execute(
          'INSERT INTO bill_settlement_allocations(business_id,request_id,bill_id,revision,expected_remaining_minor,amount_minor,currency) VALUES(?,?,?,?,?,?,?)',
          [
            businessId.value,
            requestId.value,
            a.billId.value,
            a.revision,
            a.expectedRemaining.minorUnits,
            a.amount.minorUnits,
            a.amount.currency,
          ],
        );
      }
      result = StoredBillSettlement(
        id: requestId,
        businessId: businessId,
        journalId: requestId,
        bankAccountId: bank,
        paymentAccountId: paymentAccountId,
        reference: reference,
        paidOn: date,
        approvedAt: at,
        actorId: actorId,
        total: total,
        allocations: ordered,
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: at,
        kind: 'bill.settled',
        subjectId: requestId,
        detail: _billPaymentAudit(result),
      );
    });
    return result;
  }
}
