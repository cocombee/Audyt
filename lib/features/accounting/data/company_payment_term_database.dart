part of 'accounting_database.dart';

extension CompanyPaymentTermPersistence on LocalAccountingDatabase {
  List<CompanyPaymentTerm> readPaymentTerms(EntityId businessId) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT payload FROM company_payment_terms WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
            [businessId.value],
          )
          .map(
            (row) => CompanyPaymentTerm.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
          ),
    );
  }

  CompanyPaymentTerm createPaymentTerm({
    required EntityId businessId,
    required EntityId actorId,
    required CompanyPaymentTerm term,
    required DateTime createdAt,
  }) {
    _ensureOpen();
    if (!term.active || term.revision != 0 || term.createdAt != null) {
      throw StateError('Only a new active payment term can be created.');
    }
    late CompanyPaymentTerm saved;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      if (_database.select('SELECT 1 FROM company_payment_terms WHERE id=?', [
        term.id.value,
      ]).isNotEmpty) {
        throw StateError('Payment term identity already exists.');
      }
      if (_database.select(
        'SELECT 1 FROM company_payment_terms WHERE business_id=? AND normalized_name=?',
        [businessId.value, term.name.toLowerCase()],
      ).isNotEmpty) {
        throw StateError('This payment term name already exists.');
      }
      saved = CompanyPaymentTerm(
        id: term.id,
        name: term.name,
        rule: term.rule,
        revision: 1,
        createdAt: createdAt.toUtc(),
      );
      _database.execute(
        'INSERT INTO company_payment_terms(business_id,id,name,normalized_name,revision,active,payload,created_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          businessId.value,
          saved.id.value,
          saved.name,
          saved.name.toLowerCase(),
          saved.revision,
          1,
          jsonEncode(saved.toJson()),
          saved.createdAt!.toIso8601String(),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: saved.createdAt!,
        kind: 'payment_term_created',
        subjectId: saved.id,
        detail: jsonEncode({'revision': 1}),
      );
    });
    return saved;
  }

  void _validatePaymentTermArchive() {
    final seenIds = <String>{};
    for (final row in _database.select('SELECT * FROM company_payment_terms')) {
      final businessId = row['business_id'] as String;
      final id = row['id'] as String;
      final payload = row['payload'] as String;
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Payment term payload is invalid.');
      }
      final term = CompanyPaymentTerm.fromJson(decoded);
      final createdAt = row['created_at'] as String;
      final audit = _database.select(
        "SELECT actor_id,occurred_at,detail FROM ledger_audit WHERE business_id=? AND subject_id=? AND kind='payment_term_created'",
        [businessId, id],
      );
      final owner = _database.select(
        'SELECT owner_id FROM local_workspace WHERE business_id=?',
        [businessId],
      );
      if (!seenIds.add(id) ||
          owner.length != 1 ||
          term.id.value != id ||
          term.name != row['name'] ||
          term.name.toLowerCase() != row['normalized_name'] ||
          term.revision != 1 ||
          row['revision'] != 1 ||
          !term.active ||
          row['active'] != 1 ||
          term.createdAt?.toIso8601String() != createdAt ||
          payload != jsonEncode(term.toJson()) ||
          audit.length != 1 ||
          audit.single['actor_id'] != owner.single['owner_id'] ||
          audit.single['occurred_at'] != createdAt ||
          audit.single['detail'] != jsonEncode({'revision': 1})) {
        throw const FormatException('Payment term archive is inconsistent.');
      }
    }
    final events = _database.select(
      "SELECT business_id,subject_id FROM ledger_audit WHERE kind='payment_term_created'",
    );
    if (events.length != seenIds.length ||
        events.any(
          (event) =>
              _database.select(
                'SELECT 1 FROM company_payment_terms WHERE business_id=? AND id=?',
                [event['business_id'], event['subject_id']],
              ).length !=
              1,
        )) {
      throw const FormatException('Payment term creation audit has no owner.');
    }
  }
}
