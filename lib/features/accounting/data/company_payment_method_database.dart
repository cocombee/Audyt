part of 'accounting_database.dart';

extension CompanyPaymentMethodPersistence on LocalAccountingDatabase {
  List<CompanyPaymentMethod> readPaymentMethods(EntityId businessId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT payload FROM company_payment_methods WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
            [businessId.value],
          )
          .map(
            (row) => CompanyPaymentMethod.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
          ),
    );
  }

  List<CompanyPaymentMethod> paymentMethodHistory(
    EntityId businessId,
    EntityId id,
  ) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT payload FROM company_payment_method_history WHERE business_id=? AND id=? ORDER BY revision',
            [businessId.value, id.value],
          )
          .map(
            (row) => CompanyPaymentMethod.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
          ),
    );
  }

  CompanyPaymentMethod savePaymentMethod({
    required EntityId businessId,
    required EntityId actorId,
    required CompanyPaymentMethod method,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    late CompanyPaymentMethod saved;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final owners = _database.select(
        'SELECT business_id,revision FROM company_payment_methods WHERE id=?',
        [method.id.value],
      );
      if (owners.any((row) => row['business_id'] != businessId.value)) {
        throw StateError('Payment method belongs to another company.');
      }
      final current = owners.firstOrNull;
      final revision = current == null ? 0 : current['revision'] as int;
      if (revision != method.revision) {
        throw StateError('Payment method changed. Reopen before saving.');
      }
      if (_database.select(
        'SELECT 1 FROM company_payment_methods WHERE business_id=? AND normalized_name=? AND id<>?',
        [businessId.value, method.name.toLowerCase(), method.id.value],
      ).isNotEmpty) {
        throw StateError('This payment method name already exists.');
      }
      saved = CompanyPaymentMethod.fromJson({
        ...method.toJson(),
        'revision': revision + 1,
      });
      final payload = jsonEncode(saved.toJson());
      _database.execute(
        'INSERT INTO company_payment_methods(business_id,id,name,normalized_name,revision,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,normalized_name=excluded.normalized_name,revision=excluded.revision,payload=excluded.payload',
        [
          businessId.value,
          saved.id.value,
          saved.name,
          saved.name.toLowerCase(),
          saved.revision,
          payload,
        ],
      );
      _database.execute(
        'INSERT INTO company_payment_method_history(business_id,id,revision,payload,saved_at) VALUES(?,?,?,?,?)',
        [
          businessId.value,
          saved.id.value,
          saved.revision,
          payload,
          savedAt.toUtc().toIso8601String(),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'payment_method_saved',
        subjectId: saved.id,
        detail: jsonEncode({'revision': saved.revision}),
      );
    });
    return saved;
  }

  void _validateExpensePaymentMethodSnapshot(
    EntityId businessId,
    RecordExpenseDraft draft, {
    RecordExpenseDraft? existing,
    bool historical = false,
  }) {
    final method = draft.paymentMethod;
    if (method == null) return;
    final serialized = jsonEncode(method.toJson());
    if (!paymentMethodHistory(
      businessId,
      method.id,
    ).any((version) => jsonEncode(version.toJson()) == serialized)) {
      throw StateError(
        'Payment method snapshot is unavailable in this company.',
      );
    }
    if (historical ||
        jsonEncode(existing?.paymentMethod?.toJson()) == serialized) {
      return;
    }
    if (!readPaymentMethods(businessId).any(
      (current) => current.active && jsonEncode(current.toJson()) == serialized,
    )) {
      throw StateError('Choose a current active payment method.');
    }
  }

  void _validatePaymentMethodArchive() {
    final seenIds = <String>{};
    for (final row in _database.select(
      'SELECT * FROM company_payment_methods',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      final id = row['id'] as String;
      if (!seenIds.add(id) ||
          _database.select(
                'SELECT 1 FROM local_workspace WHERE business_id=?',
                [business.value],
              ).length !=
              1) {
        throw const FormatException(
          'Payment method archive company or identity is inconsistent.',
        );
      }
      final method = CompanyPaymentMethod.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final history = _database.select(
        'SELECT business_id,id,revision,payload,saved_at FROM company_payment_method_history WHERE business_id=? AND id=? ORDER BY revision',
        [business.value, id],
      );
      if (method.id.value != row['id'] ||
          method.name != row['name'] ||
          method.name.toLowerCase() != row['normalized_name'] ||
          method.revision != row['revision'] ||
          history.isEmpty ||
          history.length != method.revision ||
          history.last['payload'] != row['payload']) {
        throw const FormatException(
          'Payment method archive identity or history is inconsistent.',
        );
      }
      for (final (index, versionRow) in history.indexed) {
        final version = CompanyPaymentMethod.fromJson(
          jsonDecode(versionRow['payload'] as String) as Map<String, dynamic>,
        );
        final savedAt = versionRow['saved_at'] as String;
        if (versionRow['business_id'] != business.value ||
            versionRow['id'] != id ||
            versionRow['revision'] != index + 1 ||
            version.id != method.id ||
            version.revision != index + 1 ||
            DateTime.tryParse(savedAt)?.isUtc != true) {
          throw const FormatException(
            'Payment method archive revisions are inconsistent.',
          );
        }
      }
    }
    if (_database
            .select('SELECT id FROM company_payment_method_history')
            .length !=
        _database
            .select(
              'SELECT h.id FROM company_payment_method_history h JOIN company_payment_methods m ON m.business_id=h.business_id AND m.id=h.id',
            )
            .length) {
      throw const FormatException('Payment method history has no owner.');
    }
    for (final row in _database.select(
      'SELECT business_id,payload FROM expense_intakes',
    )) {
      _validateExpensePaymentMethodSnapshot(
        EntityId.parse(row['business_id'] as String),
        RecordExpenseDraft.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        ),
        historical: true,
      );
    }
    for (final row in _database.select(
      'SELECT business_id,before_payload,payload FROM expense_revision_drafts',
    )) {
      final business = EntityId.parse(row['business_id'] as String);
      for (final column in ['before_payload', 'payload']) {
        _validateExpensePaymentMethodSnapshot(
          business,
          RecordExpenseDraft.fromJson(
            jsonDecode(row[column] as String) as Map<String, dynamic>,
          ),
          historical: true,
        );
      }
    }
    for (final row in _database.select(
      'SELECT business_id,payload FROM recurring_expense_template_history',
    )) {
      final template = RecurringExpenseTemplate.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      _validateExpensePaymentMethodSnapshot(
        EntityId.parse(row['business_id'] as String),
        RecordExpenseDraft.fromJson(
          Map<String, dynamic>.from(template.toJson()['defaults'] as Map),
        ),
        historical: true,
      );
    }
  }
}
