part of 'accounting_database.dart';

final class StoredQuotation {
  const StoredQuotation({
    required this.quotation,
    required this.customerSnapshot,
    required this.revision,
    required this.savedAt,
  });
  final Estimate quotation;
  final Customer customerSnapshot;
  final int revision;
  final DateTime savedAt;
}

enum QuotationAction { shared, accepted, declined, closed, reopened, revised }

extension QuotationDatabase on LocalAccountingDatabase {
  StoredQuotation _quotationFromRow(Row row) {
    final quotation = Estimate.fromSnapshot(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    );
    final customer = decodeCustomer(row['customer_payload'] as String);
    if (quotation.id.value != row['id'] ||
        quotation.documentNumber != row['document_number'] ||
        quotation.convertedInvoiceId?.value != row['converted_invoice_id'] ||
        customer.id != quotation.customerId ||
        customer.metadata.businessId.value != row['business_id']) {
      throw const FormatException('Saved quotation identity is inconsistent.');
    }
    return StoredQuotation(
      quotation: quotation,
      customerSnapshot: customer,
      revision: row['revision'] as int,
      savedAt: DateTime.parse(row['saved_at'] as String),
    );
  }

  StoredQuotation? readQuotation(
    EntityId businessId,
    EntityId quotationId, {
    bool includeRemoved = false,
  }) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM $_quotationReadSource AS quotation_drafts WHERE business_id=? AND id=? AND ${includeRemoved ? '1' : _activeTransactionSql(TransactionRecordKind.quotation)}',
      [businessId.value, quotationId.value],
    );
    return rows.isEmpty ? null : _quotationFromRow(rows.single);
  }

  Invoice? quotationInvoice(EntityId businessId, EntityId invoiceId) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT payload FROM invoice_drafts WHERE business_id=? AND id=?',
      [businessId.value, invoiceId.value],
    );
    return rows.isEmpty
        ? null
        : Invoice.fromDraftSnapshot(
            jsonDecode(rows.single['payload'] as String)
                as Map<String, dynamic>,
          );
  }

  void _validateQuotationArchive() {
    for (final row in _database.select('SELECT * FROM quotation_drafts')) {
      final record = _quotationFromRow(row);
      final businessId = EntityId.parse(row['business_id'] as String);
      final history = _database.select(
        'SELECT * FROM quotation_history WHERE business_id=? AND id=? ORDER BY revision',
        [businessId.value, record.quotation.id.value],
      );
      if (history.length != record.revision || history.isEmpty) {
        throw const FormatException('Quotation history is incomplete.');
      }
      DateTime? previous;
      for (var i = 0; i < history.length; i++) {
        final item = history[i];
        final quote = Estimate.fromSnapshot(
          jsonDecode(item['payload'] as String) as Map<String, dynamic>,
        );
        final customer = decodeCustomer(item['customer_payload'] as String);
        final at = DateTime.parse(item['saved_at'] as String);
        if (item['revision'] != i + 1 ||
            quote.id != record.quotation.id ||
            customer.id != quote.customerId ||
            customer.metadata.businessId != businessId ||
            (previous != null && !at.isAfter(previous))) {
          throw const FormatException('Quotation history is inconsistent.');
        }
        previous = at;
      }
      for (final column in ['payload', 'customer_payload', 'saved_at']) {
        if (history.last[column] != row[column]) {
          throw const FormatException(
            'Quotation does not match its latest saved revision.',
          );
        }
      }
      final quote = record.quotation;
      if (quote.convertedInvoiceId == null) {
        if (row['conversion_signature'] != null) {
          throw const FormatException(
            'Unconverted quotation has a conversion signature.',
          );
        }
        continue;
      }
      final invoices = _database.select(
        'SELECT payload FROM invoice_draft_history WHERE business_id=? AND id=? AND revision=1',
        [businessId.value, quote.convertedInvoiceId!.value],
      );
      if (invoices.length != 1 || record.revision < 2) {
        throw const FormatException(
          'Converted quotation lacks its original invoice.',
        );
      }
      final invoice = Invoice.fromDraftSnapshot(
        jsonDecode(invoices.single['payload'] as String)
            as Map<String, dynamic>,
      );
      final accepted = Estimate.fromSnapshot(
        jsonDecode(history[history.length - 2]['payload'] as String)
            as Map<String, dynamic>,
      );
      final expected = accepted.convertToInvoice(
        invoiceId: invoice.id,
        invoiceLineIds: {
          for (final line in invoice.lines) line.sourceLineId!: line.id,
        },
        issueDate: invoice.issueDate,
        dueDate: invoice.dueDate,
        documentNumber: invoice.documentNumber,
      );
      final signature = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                quote.id.value,
                record.revision - 1,
                invoice.id.value,
                invoice.documentNumber,
                invoice.issueDate.toIso8601String(),
                invoice.dueDate.toIso8601String(),
              ]),
            ),
          )
          .toString();
      if (jsonEncode(expected.invoice.draftSnapshot()) !=
              jsonEncode(invoice.draftSnapshot()) ||
          jsonEncode(expected.estimate.snapshot()) !=
              jsonEncode(quote.snapshot()) ||
          row['conversion_signature'] != signature) {
        throw const FormatException(
          'Quotation conversion lineage does not match the original invoice.',
        );
      }
    }
  }

  List<StoredQuotation> readQuotations(
    EntityId businessId, {
    bool includeRemoved = false,
  }) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM $_quotationReadSource AS quotation_drafts WHERE business_id=? AND ${includeRemoved ? '1' : _activeTransactionSql(TransactionRecordKind.quotation)} ORDER BY saved_at DESC,id',
            [businessId.value],
          )
          .map(_quotationFromRow),
    );
  }

  ({List<StoredQuotation> records, int total, List<String> currencies})
  quotationPage(
    EntityId businessId, {
    required int offset,
    required int pageSize,
    String search = '',
    EstimateStatus? status,
    String? currency,
    required DateTime asOf,
  }) {
    _ensureOpen();
    if (offset < 0 || pageSize < 1 || pageSize > 100) {
      throw ArgumentError(
        'Use a nonnegative offset and page size from 1 to 100.',
      );
    }
    final state =
        "CASE WHEN json_extract(payload,'\$.status') IN ('sent','viewed') AND json_extract(payload,'\$.validUntil') < ? THEN 'expired' ELSE json_extract(payload,'\$.status') END";
    final where = StringBuffer(
      'business_id=? AND ${_activeTransactionSql(TransactionRecordKind.quotation)}',
    );
    final args = <Object?>[businessId.value];
    final query = search.trim().toLowerCase();
    if (query.isNotEmpty) {
      where.write(
        " AND (instr(lower(document_number),?)>0 OR instr(lower(json_extract(customer_payload,'\$.name')),?)>0 OR instr(lower(COALESCE(json_extract(payload,'\$.pricing.reference'),'')),?)>0)",
      );
      args.addAll([query, query, query]);
    }
    if (status != null) {
      where.write(' AND ($state)=?');
      args.addAll([
        accountingCalendarDate(asOf).toIso8601String(),
        status.name,
      ]);
    }
    if (currency != null) {
      where.write(" AND json_extract(payload,'\$.pricing.currency')=?");
      args.add(currency);
    }
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select(
                    'SELECT COUNT(*) AS total FROM $_quotationReadSource AS quotation_drafts WHERE $where',
                    args,
                  )
                  .single['total']
              as int;
      final records = List<StoredQuotation>.unmodifiable(
        _database
            .select(
              'SELECT * FROM $_quotationReadSource AS quotation_drafts WHERE $where ORDER BY saved_at DESC,id LIMIT ? OFFSET ?',
              [...args, pageSize, offset],
            )
            .map(_quotationFromRow),
      );
      final currencies = List<String>.unmodifiable(
        _database
            .select(
              "SELECT DISTINCT json_extract(payload,'\$.pricing.currency') AS currency FROM $_quotationReadSource AS quotation_drafts WHERE business_id=? AND ${_activeTransactionSql(TransactionRecordKind.quotation)} ORDER BY currency",
              [businessId.value],
            )
            .map((row) => row['currency'] as String),
      );
      if (ownsSnapshot) _database.execute('COMMIT');
      return (records: records, total: total, currencies: currencies);
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Customer _validateQuotationReferences(EntityId businessId, Estimate quote) {
    if (quote.lines.isEmpty ||
        quote.lines.any((line) => line.categoryId == null) ||
        quote.lines.map((line) => line.id).toSet().length !=
            quote.lines.length) {
      throw StateError(
        'Choose an income account for each distinct quotation line.',
      );
    }
    if (![
      'Exclusive',
      'Inclusive',
      'Out Of Scope',
      'Exempt',
    ].contains(quote.taxMode)) {
      throw StateError('Review the quotation tax mode before saving.');
    }
    return _validateSalesDraftReferences(
      businessId,
      quote.pricingSnapshot(),
      quotation: true,
    );
  }

  void _writeQuotation({
    required EntityId businessId,
    required EntityId actorId,
    required Estimate quotation,
    required String customerPayload,
    required int revision,
    required DateTime savedAt,
    String? conversionSignature,
    required String auditKind,
  }) {
    if (_database.autocommit) {
      throw StateError('Quotation writes require a transaction.');
    }
    final payload = jsonEncode(quotation.snapshot());
    final time = savedAt.toUtc().toIso8601String();
    _database.execute(
      'INSERT INTO quotation_drafts(business_id,id,revision,document_number,payload,customer_payload,saved_at,converted_invoice_id,conversion_signature) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET revision=excluded.revision,document_number=excluded.document_number,payload=excluded.payload,customer_payload=excluded.customer_payload,saved_at=excluded.saved_at,converted_invoice_id=excluded.converted_invoice_id,conversion_signature=excluded.conversion_signature',
      [
        businessId.value,
        quotation.id.value,
        revision,
        quotation.documentNumber,
        payload,
        customerPayload,
        time,
        quotation.convertedInvoiceId?.value,
        conversionSignature,
      ],
    );
    _database.execute(
      'INSERT INTO quotation_history(business_id,id,revision,payload,customer_payload,saved_at) VALUES(?,?,?,?,?,?)',
      [
        businessId.value,
        quotation.id.value,
        revision,
        payload,
        customerPayload,
        time,
      ],
    );
    _appendAudit(
      businessId: businessId,
      actorId: actorId,
      at: savedAt,
      kind: auditKind,
      subjectId: quotation.id,
      detail: jsonEncode({
        'revision': revision,
        'status': quotation.status.name,
        'invoiceId': quotation.convertedInvoiceId?.value,
      }),
    );
  }

  int saveQuotationDraft({
    required EntityId businessId,
    required EntityId actorId,
    required Estimate quotation,
    required int expectedRevision,
    required DateTime savedAt,
    DocumentRecurrenceRequest? recurrence,
  }) {
    _ensureOpen();
    if (quotation.status != EstimateStatus.draft ||
        quotation.convertedInvoiceId != null) {
      throw StateError(
        'Save only draft quotations; use a lifecycle command for other states.',
      );
    }
    if (quotation.documentNumber.trim().isEmpty ||
        quotation.documentNumber != quotation.documentNumber.trim()) {
      throw StateError('Enter a quotation number without surrounding spaces.');
    }
    var revision = expectedRevision + 1;
    _joinTransaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.quotation,
        quotation.id.value,
      );
      final customer = _validateQuotationReferences(businessId, quotation);
      final customerPayload = encodeCustomer(customer);
      final rows = _database.select(
        'SELECT * FROM quotation_drafts WHERE business_id=? AND id=?',
        [businessId.value, quotation.id.value],
      );
      if (rows.isEmpty) {
        if (expectedRevision != 0) {
          throw StateError('New quotations start at revision zero.');
        }
      } else {
        final existing = _quotationFromRow(rows.single);
        if (existing.quotation.status != EstimateStatus.draft) {
          throw StateError(
            'Only draft quotations can be edited. Keep the shared or accepted version intact.',
          );
        }
        if (existing.revision == expectedRevision + 1 &&
            rows.single['payload'] == jsonEncode(quotation.snapshot()) &&
            rows.single['customer_payload'] == customerPayload) {
          revision = existing.revision;
          _queueGeneratedDocument(
            businessId: businessId,
            recordId: quotation.id,
            kind: GeneratedDocumentKind.quotation,
            revision: revision,
            attachments: quotation.attachments,
          );
          if (recurrence != null) {
            _saveInlineDocumentSchedule(
              businessId,
              actorId,
              RecurringDocumentKind.quotation,
              quotation.id,
              revision,
              recurrence,
              savedAt,
            );
          }
          return;
        }
        _requireQuotationRevision(existing, expectedRevision, savedAt);
      }
      final reservation = _database.select(
        "SELECT record_id FROM document_numbers WHERE business_id=? AND document_type='quotation' AND number=?",
        [businessId.value, quotation.documentNumber],
      );
      if (reservation.isNotEmpty &&
          reservation.single['record_id'] != quotation.id.value) {
        throw StateError(
          'This quotation number is reserved for another record.',
        );
      }
      if (_database.select(
        'SELECT 1 FROM $_quotationReadSource AS quotation_drafts WHERE business_id=? AND document_number=? AND id<>?',
        [businessId.value, quotation.documentNumber, quotation.id.value],
      ).isNotEmpty) {
        throw StateError('This quotation number belongs to another record.');
      }
      _writeQuotation(
        businessId: businessId,
        actorId: actorId,
        quotation: quotation,
        customerPayload: customerPayload,
        revision: revision,
        savedAt: savedAt,
        auditKind: 'quotation_draft_saved',
      );
      if (rows.isEmpty) {
        _appendTransactionRootCreated(
          businessId: businessId,
          actorId: actorId,
          at: savedAt,
          family: 'quotation',
          recordId: quotation.id,
        );
      }
      _queueGeneratedDocument(
        businessId: businessId,
        recordId: quotation.id,
        kind: GeneratedDocumentKind.quotation,
        revision: revision,
        attachments: quotation.attachments,
      );
      if (recurrence != null) {
        _saveInlineDocumentSchedule(
          businessId,
          actorId,
          RecurringDocumentKind.quotation,
          quotation.id,
          revision,
          recurrence,
          savedAt,
        );
      }
    });
    return revision;
  }

  void _requireQuotationRevision(
    StoredQuotation record,
    int expectedRevision,
    DateTime changedAt,
  ) {
    if (record.revision != expectedRevision) {
      throw StateError('Quotation changed. Reload before continuing.');
    }
    if (!changedAt.toUtc().isAfter(record.savedAt)) {
      throw StateError('Quotation revisions require a later save time.');
    }
  }

  int changeQuotationState({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId quotationId,
    required int expectedRevision,
    required QuotationAction action,
    required DateTime changedAt,
  }) {
    _ensureOpen();
    late int revision;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.quotation,
        quotationId.value,
      );
      final record = readQuotation(businessId, quotationId);
      if (record == null) {
        throw StateError('This quotation is unavailable in this company.');
      }
      _requireQuotationRevision(record, expectedRevision, changedAt);
      final quote = record.quotation;
      if (action == QuotationAction.shared ||
          action == QuotationAction.accepted) {
        _validateQuotationReferences(businessId, quote);
        if (accountingCalendarDate(changedAt).isAfter(quote.validUntil)) {
          throw StateError(
            'The quotation has expired. Review its validity before continuing.',
          );
        }
      }
      final next = switch (action) {
        QuotationAction.shared => quote.send(),
        QuotationAction.accepted => quote.accept(),
        QuotationAction.declined => quote.decline(),
        QuotationAction.closed => quote.close(),
        QuotationAction.reopened => quote.reopen(),
        QuotationAction.revised => quote.revise(),
      };
      revision = record.revision + 1;
      _writeQuotation(
        businessId: businessId,
        actorId: actorId,
        quotation: next,
        customerPayload: encodeCustomer(record.customerSnapshot),
        revision: revision,
        savedAt: changedAt,
        auditKind: 'quotation_${action.name}',
      );
    });
    return revision;
  }

  EntityId convertQuotationToInvoice({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId quotationId,
    required int expectedRevision,
    required EntityId invoiceId,
    required String documentNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    required DateTime convertedAt,
  }) {
    _ensureOpen();
    final signature = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              quotationId.value,
              expectedRevision,
              invoiceId.value,
              documentNumber,
              accountingCalendarDate(issueDate).toIso8601String(),
              accountingCalendarDate(dueDate).toIso8601String(),
            ]),
          ),
        )
        .toString();
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.quotation,
        quotationId.value,
      );
      final rows = _database.select(
        'SELECT * FROM quotation_drafts WHERE business_id=? AND id=?',
        [businessId.value, quotationId.value],
      );
      if (rows.isEmpty) {
        throw StateError('This quotation is unavailable in this company.');
      }
      final record = _quotationFromRow(rows.single);
      if (record.quotation.status == EstimateStatus.converted) {
        if (rows.single['conversion_signature'] == signature &&
            record.quotation.convertedInvoiceId == invoiceId) {
          return;
        }
        throw StateError(
          'This quotation already belongs to a different invoice conversion.',
        );
      }
      _requireQuotationRevision(record, expectedRevision, convertedAt);
      if (documentNumber.trim().isEmpty ||
          documentNumber != documentNumber.trim()) {
        throw StateError('Enter a distinct invoice number.');
      }
      if (invoiceId == quotationId ||
          accountingCalendarDate(issueDate)
              .isBefore(record.quotation.issueDate)) {
        throw StateError(
          'Use a new invoice identity and an issue date on or after the quotation.',
        );
      }
      if (_database.select(
        'SELECT 1 FROM invoice_drafts WHERE business_id=? AND id=?',
        [businessId.value, invoiceId.value],
      ).isNotEmpty) {
        throw StateError(
          'The invoice identity already belongs to another saved draft.',
        );
      }
      if (_database.select(
        "SELECT 1 FROM invoice_drafts WHERE business_id=? AND json_extract(payload,'\$.documentNumber')=? UNION ALL SELECT 1 FROM invoice_postings WHERE business_id=? AND document_number=? LIMIT 1",
        [businessId.value, documentNumber, businessId.value, documentNumber],
      ).isNotEmpty) {
        throw StateError(
          'This invoice number already belongs to another invoice.',
        );
      }
      final converted = record.quotation.convertToInvoice(
        invoiceId: invoiceId,
        invoiceLineIds: {
          for (final line in record.quotation.lines) line.id: EntityId.random(),
        },
        issueDate: issueDate,
        dueDate: dueDate,
        documentNumber: documentNumber,
      );
      _saveInvoiceDraftInSnapshot(
        businessId: businessId,
        actorId: actorId,
        invoice: converted.invoice,
        expectedRevision: 0,
        savedAt: convertedAt,
        quotationConversion: true,
      );
      _writeQuotation(
        businessId: businessId,
        actorId: actorId,
        quotation: converted.estimate,
        customerPayload: encodeCustomer(record.customerSnapshot),
        revision: record.revision + 1,
        savedAt: convertedAt,
        conversionSignature: signature,
        auditKind: 'quotation_converted',
      );
    });
    return invoiceId;
  }
}
