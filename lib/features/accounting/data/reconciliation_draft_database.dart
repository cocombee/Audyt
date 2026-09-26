part of 'accounting_database.dart';

extension ReconciliationDraftPersistence on LocalAccountingDatabase {
  List<ReceiptAttachment> _readReconciliationAttachments(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const FormatException('Reconciliation files are inconsistent.');
    }
    final files = <ReceiptAttachment>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException('Reconciliation file is inconsistent.');
      }
      final file = ReceiptAttachment.fromJson(Map<String, dynamic>.from(item));
      if (!ids.add(file.originalId)) {
        throw const FormatException('Duplicate reconciliation file identity.');
      }
      files.add(file);
    }
    return List.unmodifiable(files);
  }

  String _reconciliationAttachmentsJson(List<ReceiptAttachment> attachments) {
    final files = _readReconciliationAttachments(
      attachments.map((file) => file.toJson()).toList(),
    );
    if (files.any(
      (file) =>
          file.originalBytes.isEmpty ||
          file.status != AttachmentProcessingStatus.ready,
    )) {
      throw StateError('Supporting files need available original evidence.');
    }
    return jsonEncode(files.map((file) => file.toJson()).toList());
  }

  StatementReconciliationDraft? readReconciliationDraft(
    EntityId businessId,
    EntityId statementId,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM bank_reconciliation_drafts WHERE business_id=? AND statement_id=?',
      [businessId.value, statementId.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final start = DateTime.parse(row['starts_on'] as String);
    final end = DateTime.parse(row['ends_on'] as String);
    final outstanding = (jsonDecode(row['outstanding_ids'] as String) as List)
        .cast<String>();
    final source = _database.select(
      'SELECT payment_account_id,currency FROM bank_statement_imports WHERE business_id=? AND id=?',
      [businessId.value, statementId.value],
    );
    if (source.length != 1 ||
        source.single['payment_account_id'] != row['payment_account_id'] ||
        source.single['currency'] != row['currency'] ||
        end.isBefore(start) ||
        outstanding.toSet().length != outstanding.length ||
        (row['revision'] as int) < 1 ||
        isStatementReconciled(businessId, statementId)) {
      throw const FormatException(
        'Saved reconciliation inputs are inconsistent.',
      );
    }
    return StatementReconciliationDraft(
      paymentAccountId: row['payment_account_id'] as String,
      startsOn: start,
      endsOn: end,
      openingBalance: Money.fromMinor(
        row['opening_minor'] as int,
        row['currency'] as String,
      ),
      closingBalance: Money.fromMinor(
        row['closing_minor'] as int,
        row['currency'] as String,
      ),
      openingEvidence: row['opening_evidence'] as String,
      openingOutstandingIds: outstanding.toSet(),
      revision: row['revision'] as int,
      savedAt: DateTime.parse(row['saved_at'] as String),
      attachments: _readReconciliationAttachments(
        row.keys.contains('attachments')
            ? jsonDecode(row['attachments'] as String)
            : null,
      ),
    );
  }

  StatementReconciliationDraft saveReconciliationDraft({
    required EntityId businessId,
    required EntityId statementId,
    required EntityId actorId,
    required int expectedRevision,
    required DateTime startsOn,
    required DateTime endsOn,
    required Money openingBalance,
    required Money closingBalance,
    required DateTime savedAt,
    String openingEvidence = '',
    Set<String> openingOutstandingIds = const {},
    List<ReceiptAttachment> attachments = const [],
  }) {
    _ensureOpen();
    final start = DateTime.utc(startsOn.year, startsOn.month, startsOn.day);
    final end = DateTime.utc(endsOn.year, endsOn.month, endsOn.day);
    if (end.isBefore(start) ||
        openingBalance.currency != closingBalance.currency) {
      throw ArgumentError('Use an ordered statement period and one currency.');
    }
    late StatementReconciliationDraft result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireStatementEvidence(businessId, statementId);
      if (isStatementReconciled(businessId, statementId)) {
        throw StateError('The statement is already reconciled.');
      }
      final source = _database.select(
        'SELECT payment_account_id,currency FROM bank_statement_imports WHERE business_id=? AND id=?',
        [businessId.value, statementId.value],
      ).single;
      if (source['currency'] != openingBalance.currency) {
        throw ArgumentError('Draft balances must use the statement currency.');
      }
      final current = readReconciliationDraft(businessId, statementId);
      if ((current?.revision ?? 0) != expectedRevision) {
        throw StateError(
          'The saved reconciliation draft changed. Reopen before saving.',
        );
      }
      final revision = expectedRevision + 1;
      final files = _reconciliationAttachmentsJson(attachments);
      final outstanding = openingOutstandingIds.toList()..sort();
      _database.execute(
        'INSERT INTO bank_reconciliation_drafts(business_id,statement_id,payment_account_id,starts_on,ends_on,opening_minor,closing_minor,currency,opening_evidence,outstanding_ids,revision,saved_at,attachments) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(business_id,statement_id) DO UPDATE SET starts_on=excluded.starts_on,ends_on=excluded.ends_on,opening_minor=excluded.opening_minor,closing_minor=excluded.closing_minor,opening_evidence=excluded.opening_evidence,outstanding_ids=excluded.outstanding_ids,revision=excluded.revision,saved_at=excluded.saved_at,attachments=excluded.attachments',
        [
          businessId.value,
          statementId.value,
          source['payment_account_id'],
          start.toIso8601String(),
          end.toIso8601String(),
          openingBalance.minorUnits,
          closingBalance.minorUnits,
          openingBalance.currency,
          openingEvidence,
          jsonEncode(outstanding),
          revision,
          savedAt.toUtc().toIso8601String(),
          files,
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'reconciliation.draft_saved',
        subjectId: statementId,
        detail: jsonEncode({'revision': revision}),
      );
      result = readReconciliationDraft(businessId, statementId)!;
    });
    return result;
  }

  void _validateReconciliationDraftArchive() {
    for (final row in _database.select(
      'SELECT business_id,statement_id FROM bank_reconciliation_drafts',
    )) {
      readReconciliationDraft(
        EntityId.parse(row['business_id'] as String),
        EntityId.parse(row['statement_id'] as String),
      );
    }
    for (final row in _database.select(
      'SELECT payload FROM bank_reconciliations',
    )) {
      final payload = jsonDecode(row['payload'] as String) as Map;
      _readReconciliationAttachments(payload['attachments']);
    }
  }
}
