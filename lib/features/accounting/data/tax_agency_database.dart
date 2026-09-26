part of 'accounting_database.dart';

extension CompanyTaxAgencyPersistence on LocalAccountingDatabase {
  List<CompanyTaxAgency> readTaxAgencies(EntityId businessId) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM company_tax_agencies WHERE business_id=? ORDER BY name COLLATE NOCASE,id',
          [businessId.value],
        )
        .map(
          (r) => CompanyTaxAgency.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  List<CompanyTaxAgency> taxAgencyHistory(EntityId businessId, EntityId id) {
    _ensureOpen();
    return _database
        .select(
          'SELECT payload FROM company_tax_agency_history WHERE business_id=? AND id=? ORDER BY revision',
          [businessId.value, id.value],
        )
        .map(
          (r) => CompanyTaxAgency.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  CompanyTaxAgency saveTaxAgency({
    required EntityId businessId,
    required EntityId actorId,
    required CompanyTaxAgency agency,
    required DateTime savedAt,
  }) {
    _ensureOpen();
    late CompanyTaxAgency result;
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final current = _database.select(
        'SELECT revision FROM company_tax_agencies WHERE business_id=? AND id=?',
        [businessId.value, agency.id.value],
      );
      final revision = current.isEmpty ? 0 : current.single['revision'] as int;
      if (revision != agency.revision) {
        throw StateError('Tax agency changed. Reopen before saving.');
      }
      if (_database.select(
        'SELECT 1 FROM company_tax_agencies WHERE business_id=? AND normalized_name=? AND id<>?',
        [businessId.value, agency.name.toLowerCase(), agency.id.value],
      ).isNotEmpty) {
        throw StateError('This tax agency name already exists.');
      }
      result = CompanyTaxAgency.fromJson({
        ...agency.toJson(),
        'revision': revision + 1,
      });
      final payload = jsonEncode(result.toJson());
      _database.execute(
        'INSERT INTO company_tax_agencies(business_id,id,name,normalized_name,revision,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,normalized_name=excluded.normalized_name,revision=excluded.revision,payload=excluded.payload',
        [
          businessId.value,
          agency.id.value,
          result.name,
          result.name.toLowerCase(),
          result.revision,
          payload,
        ],
      );
      _database.execute(
        'INSERT INTO company_tax_agency_history(business_id,id,revision,payload,saved_at) VALUES(?,?,?,?,?)',
        [
          businessId.value,
          agency.id.value,
          result.revision,
          payload,
          savedAt.toUtc().toIso8601String(),
        ],
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: savedAt,
        kind: 'tax_agency_saved',
        subjectId: agency.id,
        detail: jsonEncode({'revision': result.revision}),
      );
    });
    return result;
  }

  void _validateTaxAgencySnapshot(
    EntityId businessId,
    CompanyTaxAgency? agency,
  ) {
    if (agency == null) return;
    if (!taxAgencyHistory(
      businessId,
      agency.id,
    ).any((a) => jsonEncode(a.toJson()) == jsonEncode(agency.toJson()))) {
      throw StateError('Tax agency snapshot is unavailable in this company.');
    }
  }

  void _validateTaxAgencyArchive() {
    for (final row in _database.select('SELECT * FROM company_tax_agencies')) {
      final business = EntityId.parse(row['business_id'] as String);
      final agency = CompanyTaxAgency.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final history = taxAgencyHistory(business, agency.id);
      if (agency.id.value != row['id'] ||
          agency.name != row['name'] ||
          agency.name.toLowerCase() != row['normalized_name'] ||
          agency.revision != row['revision'] ||
          history.length != agency.revision ||
          jsonEncode(history.last.toJson()) != row['payload']) {
        throw const FormatException(
          'Tax agency archive identity or history is inconsistent.',
        );
      }
      for (final (i, version) in history.indexed) {
        if (version.id != agency.id || version.revision != i + 1) {
          throw const FormatException(
            'Tax agency archive revisions are inconsistent.',
          );
        }
      }
    }
  }
}
