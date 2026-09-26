part of 'accounting_database.dart';

/// Current converted quotations have a separate append-only owner. The
/// original converted record, invoice source and old PDF versions stay intact.
extension QuotationCurrentRevisionPersistence on LocalAccountingDatabase {
  bool get _hasQuotationCurrentVersions => _database
      .select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='converted_quotation_revisions'",
      )
      .isNotEmpty;

  String get _quotationReadSource =>
      _hasQuotationCurrentVersions ? 'current_quotations' : 'quotation_drafts';

  void _migrateCurrentQuotations() {
    _transaction(() {
      _database.execute('''
        CREATE TABLE converted_quotation_revisions(
          business_id TEXT NOT NULL, id TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK(revision>0),
          base_revision INTEGER NOT NULL CHECK(base_revision>0),
          request_id TEXT NOT NULL, actor_id TEXT NOT NULL,
          before_payload TEXT NOT NULL, before_customer_payload TEXT NOT NULL,
          payload TEXT NOT NULL, customer_payload TEXT NOT NULL,
          saved_at TEXT NOT NULL,
          PRIMARY KEY(business_id,id,revision),
          UNIQUE(business_id,request_id),
          FOREIGN KEY(business_id,id) REFERENCES quotation_drafts(business_id,id)
        )
      ''');
      for (final operation in ['UPDATE', 'DELETE']) {
        _database.execute(
          "CREATE TRIGGER converted_quotation_revisions_no_${operation.toLowerCase()} BEFORE $operation ON converted_quotation_revisions BEGIN SELECT RAISE(ABORT,'Current quotation history is immutable'); END",
        );
      }
      _database.execute('''
        CREATE VIEW current_quotations AS
        SELECT q.business_id,q.id,COALESCE(c.revision,q.revision) AS revision,
          COALESCE(json_extract(c.payload,'\$.pricing.documentNumber'),q.document_number) AS document_number,
          COALESCE(c.payload,q.payload) AS payload,
          COALESCE(c.customer_payload,q.customer_payload) AS customer_payload,
          COALESCE(c.saved_at,q.saved_at) AS saved_at,
          q.converted_invoice_id,q.conversion_signature
        FROM quotation_drafts q LEFT JOIN converted_quotation_revisions c
          ON c.business_id=q.business_id AND c.id=q.id
          AND c.revision=(SELECT MAX(last.revision)
            FROM converted_quotation_revisions last
            WHERE last.business_id=q.business_id AND last.id=q.id)
      ''');
      _database.execute('PRAGMA user_version = 63');
    });
  }

  Map<String, Object?> _currentQuotationSnapshot(StoredQuotation record) => {
    'quotation': record.quotation.snapshot(),
    'customer': jsonDecode(encodeCustomer(record.customerSnapshot)),
    'revision': record.revision,
    'savedAt': record.savedAt.toUtc().toIso8601String(),
  };

  StoredQuotation _currentQuotationFromSnapshot(Map<String, dynamic> value) =>
      StoredQuotation(
        quotation: Estimate.fromSnapshot(
          Map<String, dynamic>.from(value['quotation'] as Map),
        ),
        customerSnapshot: decodeCustomer(jsonEncode(value['customer'])),
        revision: value['revision'] as int,
        savedAt: DateTime.parse(value['savedAt'] as String),
      );

  String _currentQuotationRequestSignature(List<Object?> facts) {
    Object? stable(Object? value) {
      if (value is List) return value.map(stable).toList();
      if (value is Map) {
        final document =
            value.containsKey('originalId') &&
            value.containsKey('originalSha256');
        return {
          for (final entry in value.entries)
            if (!document ||
                !{
                  'originalBytes',
                  'derivativeBytes',
                  'pdfBytes',
                  '_evidenceUnavailable',
                  'status',
                  'failureMessage',
                }.contains(entry.key))
              entry.key: stable(entry.value),
        };
      }
      return value;
    }

    // Checksums bind evidence content without copying bytes into audit strings.
    // Data-only recovery may change its availability/processing presentation.
    return sha256.convert(utf8.encode(jsonEncode(stable(facts)))).toString();
  }

  int saveCurrentQuotation({
    required EntityId businessId,
    required EntityId actorId,
    required EntityId requestId,
    required StoredQuotation expected,
    required Estimate replacement,
    required Customer reviewedCustomer,
    required DateTime savedAt,
    DocumentRecurrenceRequest? recurrence,
  }) {
    _ensureOpen();
    final quotation = expected.quotation.reviseCurrent(replacement);
    final signature = _currentQuotationRequestSignature([
      businessId.value,
      actorId.value,
      requestId.value,
      _currentQuotationSnapshot(expected),
      quotation.snapshot(),
      savedAt.toUtc().toIso8601String(),
      recurrence?.toJson(),
      jsonDecode(encodeCustomer(reviewedCustomer)),
    ]);
    var revision = expected.revision + 1;
    _joinTransaction(() {
      _requireReconciliationOwner(businessId, actorId);
      _requireTransactionActive(
        businessId,
        TransactionRecordKind.quotation,
        quotation.id.value,
      );
      final retries = _database.select(
        r"SELECT * FROM ledger_audit WHERE business_id=? AND kind='quotation_current_saved' AND json_extract(detail,'$.requestId')=?",
        [businessId.value, requestId.value],
      );
      if (retries.isNotEmpty) {
        final detail = jsonDecode(
          retries.single['detail'] as String,
        ) as Map<String, dynamic>;
        if (detail['signature'] != signature ||
            retries.single['actor_id'] != actorId.value) {
          throw StateError('This quotation edit request has different facts.');
        }
        revision = (detail['after'] as Map)['revision'] as int;
        return;
      }
      final current = readQuotation(businessId, quotation.id);
      if (current == null ||
          expected.customerSnapshot.metadata.businessId != businessId ||
          jsonEncode(_currentQuotationSnapshot(current)) !=
              jsonEncode(_currentQuotationSnapshot(expected))) {
        throw StateError(
          'The current quotation changed. Reopen before editing.',
        );
      }
      if (current.quotation.status == EstimateStatus.draft) {
        throw StateError('Use the existing draft quotation owner.');
      }
      _requireQuotationRevision(current, expected.revision, savedAt);
      if (quotation.documentNumber.trim().isEmpty ||
          quotation.documentNumber != quotation.documentNumber.trim()) {
        throw StateError(
          'Enter a quotation number without surrounding spaces.',
        );
      }
      final customer = _validateCurrentQuotationReferences(
        businessId,
        quotation,
        current,
      );
      if (encodeCustomer(customer) != encodeCustomer(reviewedCustomer)) {
        throw StateError(
          'The quotation customer changed. Review again before saving.',
        );
      }
      final reservation = _database.select(
        "SELECT record_id FROM document_numbers WHERE business_id=? AND document_type='quotation' AND number=?",
        [businessId.value, quotation.documentNumber],
      );
      if ((reservation.isNotEmpty &&
              reservation.single['record_id'] != quotation.id.value) ||
          _database.select(
            'SELECT 1 FROM $_quotationReadSource WHERE business_id=?1 AND document_number=?2 AND id<>?3 UNION ALL SELECT 1 FROM quotation_drafts WHERE business_id=?1 AND document_number=?2 AND id<>?3 LIMIT 1',
            [businessId.value, quotation.documentNumber, quotation.id.value],
          ).isNotEmpty) {
        throw StateError('This quotation number belongs to another record.');
      }
      final after = StoredQuotation(
        quotation: quotation,
        customerSnapshot: customer,
        revision: revision,
        savedAt: savedAt,
      );
      if (quotation.status == EstimateStatus.converted) {
        final original = _database.select(
          'SELECT * FROM quotation_drafts WHERE business_id=? AND id=?',
          [businessId.value, quotation.id.value],
        ).single;
        final base = _quotationFromRow(original);
        if (base.quotation.status != EstimateStatus.converted ||
            base.quotation.convertedInvoiceId != quotation.convertedInvoiceId) {
          throw StateError('The original quotation conversion changed.');
        }
        _database.execute(
          'INSERT INTO converted_quotation_revisions(business_id,id,revision,base_revision,request_id,actor_id,before_payload,before_customer_payload,payload,customer_payload,saved_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
          [
            businessId.value,
            quotation.id.value,
            revision,
            base.revision,
            requestId.value,
            actorId.value,
            jsonEncode(current.quotation.snapshot()),
            encodeCustomer(current.customerSnapshot),
            jsonEncode(quotation.snapshot()),
            encodeCustomer(customer),
            savedAt.toUtc().toIso8601String(),
          ],
        );
      } else {
        _writeQuotation(
          businessId: businessId,
          actorId: actorId,
          quotation: quotation,
          customerPayload: encodeCustomer(customer),
          revision: revision,
          savedAt: savedAt,
          auditKind: 'quotation_current_record_saved',
        );
      }
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'quotation_current_saved',
        subjectId: quotation.id,
        detail: jsonEncode({
          'requestId': requestId.value,
          'signature': signature,
          'recurrence': recurrence?.toJson(),
          'before': _currentQuotationSnapshot(current),
          'after': _currentQuotationSnapshot(after),
        }),
      );
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

  Customer _validateCurrentQuotationReferences(
    EntityId businessId,
    Estimate quotation,
    StoredQuotation current,
  ) {
    if (quotation.lines.isEmpty ||
        quotation.lines.any((line) => line.categoryId == null) ||
        quotation.lines.map((line) => line.id).toSet().length !=
            quotation.lines.length ||
        ![
          'Exclusive',
          'Inclusive',
          'Out Of Scope',
          'Exempt',
        ].contains(quotation.taxMode)) {
      throw StateError(
        'Review the quotation lines and tax mode before saving.',
      );
    }
    _validateLineTaxSnapshots(
      businessId,
      quotation.lines,
      quotation.issueDate,
      TaxApplication.sales,
    );
    _validateSalesCatalogueReferences(
      businessId,
      quotation.pricingSnapshot(),
      quotation: true,
      retainedLines: current.quotation.lines,
    );
    final rows = _database.select(
      'SELECT payload FROM customers WHERE business_id=? AND id=?',
      [businessId.value, quotation.customerId.value],
    );
    if (rows.length != 1) {
      throw StateError('Choose a customer in this company.');
    }
    final customer = decodeCustomer(rows.single['payload'] as String);
    if (!customer.isActive && customer.id != current.quotation.customerId) {
      throw StateError('Choose an active customer in this company.');
    }
    for (final line in quotation.lines) {
      final accounts = _database.select(
        'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
        [businessId.value, line.categoryId!.value],
      );
      final retained = current.quotation.lines.any(
        (saved) => saved.id == line.id && saved.categoryId == line.categoryId,
      );
      if (accounts.length != 1 ||
          accounts.single['type'] != AccountType.income.name ||
          accounts.single['is_parent'] != 0 ||
          (accounts.single['status'] != AccountStatus.active.name &&
              !retained)) {
        throw StateError(
          'Choose an active income account for each new or changed quotation line.',
        );
      }
    }
    return customer.isActive ? customer : current.customerSnapshot;
  }

  void _validateQuotationCurrentArchive() {
    final events = _database.select(
      "SELECT * FROM ledger_audit WHERE kind='quotation_current_saved' ORDER BY sequence",
    );
    if (!_hasQuotationCurrentVersions) {
      if (events.isNotEmpty) {
        throw const FormatException(
          'Current quotation history requires its schema.',
        );
      }
      return;
    }
    final validated = <String, Map<String, dynamic>>{};
    final requests = <String>{};
    for (final event in events) {
      final businessId = EntityId.parse(event['business_id'] as String);
      final actorId = EntityId.parse(event['actor_id'] as String);
      _requireReconciliationOwner(businessId, actorId);
      final data =
          jsonDecode(event['detail'] as String) as Map<String, dynamic>;
      final before = _currentQuotationFromSnapshot(
        Map<String, dynamic>.from(data['before'] as Map),
      );
      final after = _currentQuotationFromSnapshot(
        Map<String, dynamic>.from(data['after'] as Map),
      );
      final quote = after.quotation;
      final key = '${businessId.value}/${quote.id.value}/${after.revision}';
      final signature = _currentQuotationRequestSignature([
        businessId.value,
        actorId.value,
        data['requestId'],
        _currentQuotationSnapshot(before),
        quote.snapshot(),
        after.savedAt.toUtc().toIso8601String(),
        data['recurrence'],
        jsonDecode(encodeCustomer(after.customerSnapshot)),
      ]);
      if (validated.containsKey(key) ||
          !requests.add('${businessId.value}/${data['requestId']}') ||
          EntityId.parse(data['requestId'] as String).value !=
              data['requestId'] ||
          event['subject_id'] != quote.id.value ||
          event['occurred_at'] != after.savedAt.toUtc().toIso8601String() ||
          before.quotation.id != quote.id ||
          before.quotation.status == EstimateStatus.draft ||
          before.quotation.status != quote.status ||
          before.quotation.convertedInvoiceId != quote.convertedInvoiceId ||
          before.revision + 1 != after.revision ||
          !after.savedAt.isAfter(before.savedAt) ||
          before.customerSnapshot.metadata.businessId != businessId ||
          after.customerSnapshot.metadata.businessId != businessId ||
          before.customerSnapshot.id != before.quotation.customerId ||
          after.customerSnapshot.id != quote.customerId ||
          data['signature'] != signature) {
        throw const FormatException('Current quotation audit facts differ.');
      }
      validated[key] = {
        'data': data,
        'actorId': actorId.value,
        'before': before,
        'after': after,
      };
      for (final snapshot in [before, after]) {
        final versions = _database.select(
          'SELECT payload,customer_payload,saved_at FROM quotation_history WHERE business_id=?1 AND id=?2 AND revision=?3 UNION ALL SELECT payload,customer_payload,saved_at FROM converted_quotation_revisions WHERE business_id=?1 AND id=?2 AND revision=?3',
          [businessId.value, quote.id.value, snapshot.revision],
        );
        if (versions.length != 1 ||
            jsonEncode(
                  Estimate.fromSnapshot(
                    jsonDecode(versions.single['payload'] as String)
                        as Map<String, dynamic>,
                  ).snapshot(),
                ) !=
                jsonEncode(snapshot.quotation.snapshot()) ||
            encodeCustomer(
                  decodeCustomer(versions.single['customer_payload'] as String),
                ) !=
                encodeCustomer(snapshot.customerSnapshot) ||
            versions.single['saved_at'] !=
                snapshot.savedAt.toUtc().toIso8601String()) {
          throw const FormatException(
            'Current quotation history differs from retained versions.',
          );
        }
        final customers = _database.select(
          'SELECT payload FROM customer_history WHERE business_id=? AND id=? AND revision=?',
          [
            businessId.value,
            snapshot.customerSnapshot.id.value,
            snapshot.customerSnapshot.metadata.revision,
          ],
        );
        if (customers.length != 1 ||
            encodeCustomer(
                  decodeCustomer(customers.single['payload'] as String),
                ) !=
                encodeCustomer(snapshot.customerSnapshot)) {
          throw const FormatException(
            'Current quotation customer history differs.',
          );
        }
        for (final line in snapshot.quotation.lines) {
          if (line.categoryId == null ||
              _database.select(
                    'SELECT 1 FROM accounts WHERE business_id=? AND id=?',
                    [businessId.value, line.categoryId!.value],
                  ).length !=
                  1) {
            throw const FormatException(
              'Current quotation has foreign account references.',
            );
          }
        }
      }
    }
    for (final row in _database.select(
      'SELECT * FROM converted_quotation_revisions ORDER BY business_id,id,revision',
    )) {
      final key = '${row['business_id']}/${row['id']}/${row['revision']}';
      final base = _database.select(
        'SELECT * FROM quotation_drafts WHERE business_id=? AND id=?',
        [row['business_id'], row['id']],
      );
      final quote = Estimate.fromSnapshot(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final event = validated[key];
      final before = event?['before'] as StoredQuotation?;
      if (event == null ||
          before == null ||
          base.length != 1 ||
          base.single['revision'] != row['base_revision'] ||
          row['request_id'] != (event['data'] as Map)['requestId'] ||
          row['actor_id'] != event['actorId'] ||
          jsonEncode(
                Estimate.fromSnapshot(
                  jsonDecode(row['before_payload'] as String)
                      as Map<String, dynamic>,
                ).snapshot(),
              ) !=
              jsonEncode(before.quotation.snapshot()) ||
          encodeCustomer(
                decodeCustomer(row['before_customer_payload'] as String),
              ) !=
              encodeCustomer(before.customerSnapshot) ||
          quote.status != EstimateStatus.converted ||
          quote.id.value != row['id'] ||
          quote.convertedInvoiceId?.value !=
              base.single['converted_invoice_id']) {
        throw const FormatException(
          'Current quotation has no retained conversion owner.',
        );
      }
    }
    for (final event in _database.select(
      "SELECT * FROM ledger_audit WHERE kind='quotation_current_record_saved'",
    )) {
      final data =
          jsonDecode(event['detail'] as String) as Map<String, dynamic>;
      final key =
          '${event['business_id']}/${event['subject_id']}/${data['revision']}';
      if (!validated.containsKey(key) ||
          validated[key]!['actorId'] != event['actor_id'] ||
          (validated[key]!['after'] as StoredQuotation).savedAt
                  .toUtc()
                  .toIso8601String() !=
              event['occurred_at']) {
        throw const FormatException(
          'Current quotation record has no exact revision audit.',
        );
      }
    }
  }
}
