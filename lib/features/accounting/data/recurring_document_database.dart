part of 'accounting_database.dart';

extension RecurringDocumentPersistence on LocalAccountingDatabase {
  String _documentSourceTable(RecurringDocumentKind kind) => switch (kind) {
    RecurringDocumentKind.invoice => 'invoice_drafts',
    RecurringDocumentKind.bill => 'bill_drafts',
    RecurringDocumentKind.quotation => 'quotation_drafts',
  };

  Map<String, dynamic> _documentScheduleSource(
    RecurringDocumentKind kind,
    Map<String, dynamic> source,
  ) {
    if (kind == RecurringDocumentKind.quotation) {
      (source['pricing'] as Map).remove('attachments');
    } else {
      source.remove('attachments');
      if (kind == RecurringDocumentKind.bill) {
        source['attachments'] = <Object>[];
      }
    }
    return source;
  }

  void _saveInlineDocumentSchedule(
    EntityId businessId,
    EntityId actorId,
    RecurringDocumentKind kind,
    EntityId sourceId,
    int sourceRevision,
    DocumentRecurrenceRequest request,
    DateTime at,
  ) {
    final old = documentSchedules(businessId)
        .where((s) => s.id == request.id)
        .firstOrNull;
    if (old != null) {
      if (old.kind != kind ||
          old.sourceId != sourceId.value ||
          old.sourceRevision != sourceRevision ||
          old.name != request.name.trim() ||
          old.paused ||
          old.cancelled ||
          jsonEncode(old.schedule.toJson()) !=
              jsonEncode(request.schedule.toJson())) {
        throw StateError(
          'The recurring schedule changed. Reopen before saving.',
        );
      }
      return;
    }
    saveDocumentSchedule(
      businessId: businessId,
      actorId: actorId,
      id: request.id,
      name: request.name,
      kind: kind,
      sourceId: sourceId,
      sourceRevision: sourceRevision,
      expectedRevision: 0,
      schedule: request.schedule,
      savedAt: at,
    );
  }

  List<({Invoice invoice, int revision})> recurringInvoiceSources(
    EntityId businessId,
  ) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload,revision FROM invoice_drafts WHERE business_id=? AND archived_at IS NULL ORDER BY id',
          [businessId.value],
        )
        .map(
          (row) => (
            invoice: Invoice.fromDraftSnapshot(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
            revision: row['revision'] as int,
          ),
        )
        .toList(growable: false);
  }

  List<RecurringDocumentTemplate> documentSchedules(EntityId businessId) =>
      _database
          .select(
            'SELECT payload FROM recurring_document_templates WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
            [businessId.value],
          )
          .map(
            (r) => RecurringDocumentTemplate.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
  List<RecurringDocumentOccurrence> documentOccurrences(
    EntityId businessId,
    String templateId,
  ) => _database
      .select(
        'SELECT * FROM recurring_document_occurrences WHERE business_id=? AND template_id=? ORDER BY occurs_on',
        [businessId.value, templateId],
      )
      .map(
        (r) => RecurringDocumentOccurrence(
          templateId: templateId,
          templateRevision: r['template_revision'] as int,
          index: r['occurrence_index'] as int,
          date: DateTime.parse(r['occurs_on'] as String),
          draftId: r['draft_id'] as String,
          kind: RecurringDocumentKind.values.byName(r['kind'] as String),
        ),
      )
      .toList(growable: false);
  void _writeDocumentSchedule(
    EntityId businessId,
    EntityId actorId,
    RecurringDocumentTemplate template,
    int expectedRevision,
    DateTime at,
  ) {
    _requireReconciliationOwner(businessId, actorId);
    final old = documentSchedules(businessId)
        .where((s) => s.id == template.id)
        .firstOrNull;
    if ((old?.revision ?? 0) != expectedRevision ||
        template.revision != expectedRevision + 1 ||
        old != null &&
            (old.cancelled ||
                old.kind != template.kind ||
                old.sourceId != template.sourceId)) {
      throw StateError(
        'Schedule changed or was cancelled. Reopen before editing.',
      );
    }
    final payload = jsonEncode(template.toJson());
    _database.execute(
      'INSERT INTO recurring_document_templates(business_id,id,name,revision,payload) VALUES(?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,revision=excluded.revision,payload=excluded.payload',
      [
        businessId.value,
        template.id,
        template.name,
        template.revision,
        payload,
      ],
    );
    _database.execute(
      'INSERT INTO recurring_document_template_history(business_id,id,revision,payload,saved_at) VALUES(?,?,?,?,?)',
      [
        businessId.value,
        template.id,
        template.revision,
        payload,
        at.toUtc().toIso8601String(),
      ],
    );
    _appendAudit(
      businessId: businessId,
      actorId: actorId,
      at: at,
      kind: 'recurring_document_saved',
      subjectId: EntityId.parse(template.id),
      detail: jsonEncode({'revision': template.revision}),
    );
  }

  RecurringDocumentTemplate saveDocumentSchedule({
    required EntityId businessId,
    required EntityId actorId,
    required String id,
    required String name,
    required RecurringDocumentKind kind,
    required EntityId sourceId,
    required int sourceRevision,
    required int expectedRevision,
    required RecurrenceRule schedule,
    required DateTime savedAt,
    bool paused = false,
  }) {
    _ensureOpen();
    late RecurringDocumentTemplate result;
    _joinTransaction(() {
      _requireReconciliationOwner(businessId, actorId);
      if (kind != RecurringDocumentKind.invoice) {
        _requireTransactionActive(
          businessId,
          kind == RecurringDocumentKind.bill
              ? TransactionRecordKind.bill
              : TransactionRecordKind.quotation,
          sourceId.value,
        );
      }
      final table = _documentSourceTable(kind);
      final rows = _database.select(
        'SELECT payload,revision FROM $table WHERE business_id=? AND id=?',
        [businessId.value, sourceId.value],
      );
      if (rows.length != 1 || rows.single['revision'] != sourceRevision) {
        throw StateError(
          'Source transaction changed. Review its saved revision.',
        );
      }
      final payload =
          jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
      result = RecurringDocumentTemplate(
        id: id,
        name: name.trim(),
        kind: kind,
        sourceId: sourceId.value,
        sourceRevision: sourceRevision,
        revision: expectedRevision + 1,
        schedule: schedule,
        source: _documentScheduleSource(kind, payload),
        paused: paused,
      );
      _writeDocumentSchedule(
        businessId,
        actorId,
        result,
        expectedRevision,
        savedAt,
      );
    });
    return result;
  }

  void changeDocumentScheduleState({
    required EntityId businessId,
    required EntityId actorId,
    required String id,
    required int expectedRevision,
    required DateTime savedAt,
    bool? paused,
    bool cancel = false,
  }) {
    _ensureOpen();
    _transaction(() {
      final old = documentSchedules(businessId).singleWhere((s) => s.id == id);
      final changed = RecurringDocumentTemplate.fromJson({
        ...old.toJson(),
        'revision': expectedRevision + 1,
        'paused': paused ?? old.paused,
        'cancelled': cancel,
      });
      _writeDocumentSchedule(
        businessId,
        actorId,
        changed,
        expectedRevision,
        savedAt,
      );
    });
  }

  String prepareDocumentOccurrence({
    required EntityId businessId,
    required EntityId actorId,
    required String templateId,
    required int expectedRevision,
    required int index,
    required DateTime preparedAt,
    DateTime? asOf,
  }) {
    _ensureOpen();
    late String result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final template = documentSchedules(businessId)
          .singleWhere((s) => s.id == templateId);
      if (template.revision != expectedRevision ||
          template.paused ||
          template.cancelled) {
        throw StateError('Review the latest active schedule.');
      }
      final date = template.schedule.occurrenceAt(index);
      if (date == null) {
        throw StateError('This occurrence is outside the schedule.');
      }
      if (date.isAfter(accountingCalendarDate(asOf ?? preparedAt))) {
        throw StateError('The occurrence is not due yet.');
      }
      final old = documentOccurrences(
        businessId,
        templateId,
      ).where((o) => o.date == date).firstOrNull;
      if (old != null) {
        result = old.draftId;
        return;
      }
      final id = EntityId.random();
      result = id.value;
      final number = allocateDocumentNumber(
        businessId: businessId,
        actorId: actorId,
        recordId: id,
        documentType: template.kind.name,
        allocatedAt: preparedAt,
      );
      final pricing = template.kind == RecurringDocumentKind.quotation
          ? template.source['pricing'] as Map
          : template.source;
      final lines = (pricing['lines'] as List).map((raw) {
        final value = Map<String, dynamic>.from(raw as Map)
          ..['id'] = EntityId.random().value;
        value.remove('sourceLine');
        return SalesLineItem.fromJson(value);
      }).toList();
      if (template.kind == RecurringDocumentKind.invoice) {
        final source = Invoice.fromDraftSnapshot(template.source);
        final draft = Invoice.draft(
          id: id,
          customerId: source.customerId,
          documentNumber: number,
          issueDate: date,
          terms: source.terms,
          dueDate: source.terms.kind == PaymentTermKind.custom
              ? date.add(source.dueDate.difference(source.issueDate))
              : null,
          lines: lines,
          memo: source.memo,
          reference: source.reference,
          taxMode: source.taxMode,
          classification: source.classification,
          location: source.location,
        );
        _saveInvoiceDraftInSnapshot(
          businessId: businessId,
          actorId: actorId,
          invoice: draft,
          expectedRevision: 0,
          savedAt: preparedAt,
        );
      } else if (template.kind == RecurringDocumentKind.quotation) {
        final source = Estimate.fromSnapshot(template.source);
        saveQuotationDraft(
          businessId: businessId,
          actorId: actorId,
          expectedRevision: 0,
          savedAt: preparedAt,
          quotation: Estimate.draft(
            id: id,
            customerId: source.customerId,
            documentNumber: number,
            issueDate: date,
            validUntil: date.add(
              source.validUntil.difference(source.issueDate),
            ),
            terms: source.terms,
            lines: lines,
            memo: source.memo,
            reference: source.reference,
            taxMode: source.taxMode,
            classification: source.classification,
            location: source.location,
          ),
        );
      } else {
        final source = PurchaseBillDraft.fromJson(template.source);
        final device =
            _database.select(
                  'SELECT device_id FROM local_workspace WHERE business_id=?',
                  [businessId.value],
                ).single['device_id']
                as String;
        final draft = PurchaseBillDraft(
          metadata: RecordMetadata.initial(
            recordId: id,
            businessId: businessId,
            originDeviceId: EntityId.parse(device),
            createdAt: preparedAt.toUtc(),
          ),
          vendorSnapshot: source.vendorSnapshot,
          documentNumber: number,
          issueDate: date,
          dueDate: source.bill.terms.kind == PaymentTermKind.custom
              ? date.add(source.bill.dueDate.difference(source.bill.issueDate))
              : source.bill.terms.dueDateFor(date),
          terms: source.bill.terms,
          lines: lines,
          memo: source.memo,
          taxMode: source.taxMode,
          classification: source.classification,
          location: source.location,
        );
        saveBillDraft(
          businessId: businessId,
          actorId: actorId,
          bill: draft,
          expectedRevision: 0,
        );
      }
      _database.execute(
        'INSERT INTO recurring_document_occurrences(business_id,template_id,template_revision,occurs_on,occurrence_index,draft_id,kind) VALUES(?,?,?,?,?,?,?)',
        [
          businessId.value,
          templateId,
          template.revision,
          date.toIso8601String(),
          index,
          id.value,
          template.kind.name,
        ],
      );
    });
    return result;
  }

  void _validateDocumentScheduleArchive() {
    for (final row in _database.select(
      'SELECT * FROM recurring_document_templates',
    )) {
      final template = RecurringDocumentTemplate.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final history = _database.select(
        'SELECT payload,revision FROM recurring_document_template_history WHERE business_id=? AND id=? ORDER BY revision',
        [row['business_id'], row['id']],
      );
      if (template.id != row['id'] ||
          template.revision != row['revision'] ||
          template.name != row['name'] ||
          history.length != template.revision ||
          history.last['payload'] != row['payload']) {
        throw const FormatException(
          'Recurring schedule history is inconsistent.',
        );
      }
      final sourceTable = switch (template.kind) {
        RecurringDocumentKind.invoice => 'invoice_draft_history',
        RecurringDocumentKind.bill => 'bill_draft_history',
        RecurringDocumentKind.quotation => 'quotation_history',
      };
      final sourceRows = _database.select(
        'SELECT payload FROM $sourceTable WHERE business_id=? AND id=? AND revision=?',
        [row['business_id'], template.sourceId, template.sourceRevision],
      );
      if (sourceRows.length != 1) {
        throw const FormatException('Recurring source history is unavailable.');
      }
      final source = jsonDecode(
        sourceRows.single['payload'] as String,
      ) as Map<String, dynamic>;
      _documentScheduleSource(template.kind, source);
      if (jsonEncode(source) != jsonEncode(template.source)) {
        throw const FormatException(
          'Recurring source snapshot is inconsistent.',
        );
      }
      for (final (i, h) in history.indexed) {
        final version = RecurringDocumentTemplate.fromJson(
          jsonDecode(h['payload'] as String) as Map<String, dynamic>,
        );
        if (version.id != template.id ||
            version.revision != i + 1 ||
            version.kind != template.kind ||
            version.sourceId != template.sourceId) {
          throw const FormatException(
            'Recurring schedule revisions are inconsistent.',
          );
        }
      }
      for (final occurrence in documentOccurrences(
        EntityId.parse(row['business_id'] as String),
        template.id,
      )) {
        if (occurrence.templateRevision < 1 ||
            occurrence.templateRevision > history.length) {
          throw const FormatException(
            'Recurring occurrence revision is unavailable.',
          );
        }
        final version = RecurringDocumentTemplate.fromJson(
          jsonDecode(
            history[occurrence.templateRevision - 1]['payload'] as String,
          ) as Map<String, dynamic>,
        );
        if (version.schedule.occurrenceAt(occurrence.index) !=
            occurrence.date) {
          throw const FormatException(
            'Recurring occurrence date is inconsistent.',
          );
        }
        final table = _documentSourceTable(occurrence.kind);
        if (occurrence.templateRevision > template.revision ||
            occurrence.kind != template.kind ||
            _database.select(
              'SELECT 1 FROM $table WHERE business_id=? AND id=?',
              [row['business_id'], occurrence.draftId],
            ).isEmpty) {
          throw const FormatException(
            'Recurring occurrence draft is unavailable.',
          );
        }
      }
    }
  }
}
