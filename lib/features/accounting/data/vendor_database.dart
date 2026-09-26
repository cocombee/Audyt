part of 'accounting_database.dart';

final class VendorDirectoryEntry {
  const VendorDirectoryEntry(this.payee, this.vendor);
  final Payee payee;
  final Vendor? vendor;
}

final class VendorDirectoryPage {
  const VendorDirectoryPage(this.entries, this.total, this.offset);
  final List<VendorDirectoryEntry> entries;
  final int total, offset;
}

extension VendorPersistence on LocalAccountingDatabase {
  Vendor _vendorFromRow(Row row, {bool checkPayee = true}) {
    final vendor = Vendor.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    );
    if (vendor.id.value != row['id'] ||
        vendor.metadata.businessId.value != row['business_id'] ||
        vendor.payeeId != row['payee_id'] ||
        vendor.metadata.revision != row['revision'] ||
        vendor.metadata.updatedAt.toIso8601String() != row['updated_at'] ||
        vendor.details['email'] != row['email'] ||
        vendor.details['telephone'] != row['telephone'] ||
        jsonEncode(vendor.toJson()) != row['payload']) {
      throw const FormatException(
        'Vendor identity or revision does not match its saved snapshot.',
      );
    }
    if (checkPayee) {
      final payees = _database.select(
        'SELECT name,type FROM payees WHERE business_id=? AND id=?',
        [vendor.metadata.businessId.value, vendor.payeeId],
      );
      if (payees.length != 1 ||
          payees.single['name'] != vendor.name ||
          payees.single['type'] != vendor.type.name) {
        throw const FormatException(
          'Vendor contact no longer matches its supplier identity.',
        );
      }
    }
    return vendor;
  }

  Vendor? readVendor(EntityId businessId, EntityId id) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT * FROM vendor_profiles WHERE business_id=? AND id=?',
      [businessId.value, id.value],
    );
    return rows.isEmpty ? null : _vendorFromRow(rows.single);
  }

  List<Vendor> vendorHistory(EntityId businessId, EntityId id) {
    _ensureOpen();
    return List.unmodifiable(
      _database
          .select(
            'SELECT * FROM vendor_history WHERE business_id=? AND id=? ORDER BY revision',
            [businessId.value, id.value],
          )
          .map((row) => _vendorFromRow(row, checkPayee: false)),
    );
  }

  VendorDirectoryPage vendorDirectory({
    required EntityId businessId,
    String search = '',
    PayeeType? type,
    int offset = 0,
    int limit = 10,
  }) {
    _ensureOpen();
    if (offset < 0 ||
        limit < 1 ||
        limit > 100 ||
        (type != null && !vendorPayeeTypes.contains(type))) {
      throw ArgumentError('Invalid supplier directory range or type.');
    }
    final where =
        "p.business_id=? AND p.type IN ('supplier','vendor','smallProvider')"
        '${type == null ? '' : ' AND p.type=?'}'
        " AND instr(lower(p.name || ' ' || coalesce(v.email,'') || ' ' || coalesce(v.telephone,'')),?)>0";
    final args = <Object?>[
      businessId.value,
      if (type != null) type.name,
      search.trim().toLowerCase(),
    ];
    const from =
        'FROM payees p LEFT JOIN vendor_profiles v ON v.business_id=p.business_id AND v.payee_id=p.id';
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      final total =
          _database
                  .select('SELECT count(*) AS total $from WHERE $where', args)
                  .single['total']
              as int;
      final lastOffset = total == 0 ? 0 : ((total - 1) ~/ limit) * limit;
      final actualOffset = offset > lastOffset ? lastOffset : offset;
      final entries = _database
          .select(
            'SELECT p.id AS directory_id,p.name AS directory_name,p.type AS directory_type,v.* $from WHERE $where ORDER BY p.name COLLATE NOCASE,p.id LIMIT ? OFFSET ?',
            [...args, limit, actualOffset],
          )
          .map(
            (row) => VendorDirectoryEntry(
              Payee(
                id: row['directory_id'] as String,
                name: row['directory_name'] as String,
                type: PayeeType.values.byName(row['directory_type'] as String),
              ),
              row['id'] == null ? null : _vendorFromRow(row),
            ),
          )
          .toList(growable: false);
      if (ownsSnapshot) _database.execute('COMMIT');
      return VendorDirectoryPage(
        List.unmodifiable(entries),
        total,
        actualOffset,
      );
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void saveVendor({
    required EntityId businessId,
    required EntityId actorId,
    required Vendor vendor,
    required int expectedRevision,
    Payee? expectedPayee,
  }) {
    _ensureOpen();
    if (vendor.metadata.businessId != businessId ||
        expectedRevision < 0 ||
        vendor.metadata.revision != expectedRevision + 1) {
      throw StateError(
        'Vendor must match this company and the reviewed revision.',
      );
    }
    final payload = jsonEncode(vendor.toJson());
    _transaction(() {
      _requireReconciliationOwner(businessId, actorId);
      final rows = _database.select(
        'SELECT * FROM vendor_profiles WHERE business_id=? AND id=?',
        [businessId.value, vendor.id.value],
      );
      if (rows.isNotEmpty) {
        final old = _vendorFromRow(rows.single);
        if (old.metadata.revision == vendor.metadata.revision &&
            rows.single['payload'] == payload) {
          return;
        }
        if (old.metadata.revision != expectedRevision ||
            old.payeeId != vendor.payeeId ||
            old.metadata.createdAt != vendor.metadata.createdAt ||
            old.metadata.originDeviceId != vendor.metadata.originDeviceId ||
            !vendor.metadata.updatedAt.isAfter(old.metadata.updatedAt)) {
          throw StateError(
            'Vendor changed. Reopen its saved details before editing.',
          );
        }
      } else {
        if (expectedRevision != 0 ||
            vendor.metadata.createdAt != vendor.metadata.updatedAt) {
          throw StateError('New vendor profiles start at revision one.');
        }
        final payees = _database.select(
          'SELECT name,type FROM payees WHERE business_id=? AND id=?',
          [businessId.value, vendor.payeeId],
        );
        if (payees.isEmpty) {
          if (expectedPayee != null || vendor.payeeId != vendor.id.value) {
            throw StateError('The reviewed supplier identity is missing.');
          }
        } else if (expectedPayee == null ||
            expectedPayee.id != vendor.payeeId ||
            expectedPayee.name != payees.single['name'] ||
            expectedPayee.type.name != payees.single['type'] ||
            !vendorPayeeTypes.contains(expectedPayee.type)) {
          throw StateError(
            'Supplier changed. Reopen its directory entry before adding details.',
          );
        }
      }
      final selectedExpense =
          vendor.additionalValues['defaultExpenseAccountId'];
      if (selectedExpense != null) {
        final oldDefault = rows.isEmpty
            ? null
            : _vendorFromRow(rows.single)
                  .additionalValues['defaultExpenseAccountId'];
        final selected = _database.select(
          'SELECT type,status,is_parent FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, selectedExpense],
        );
        if (selectedExpense != oldDefault &&
            (selected.length != 1 ||
                selected.single['type'] != AccountType.expense.name ||
                selected.single['status'] != AccountStatus.active.name ||
                selected.single['is_parent'] != 0)) {
          throw StateError('Choose an active posting expense account.');
        }
      }
      final linked = _database.select(
        'SELECT id FROM vendor_profiles WHERE business_id=? AND payee_id=?',
        [businessId.value, vendor.payeeId],
      );
      if (linked.isNotEmpty && linked.single['id'] != vendor.id.value) {
        throw StateError('This supplier already has a vendor profile.');
      }
      _database.execute(
        'INSERT INTO payees(business_id,id,name,type) VALUES(?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,type=excluded.type',
        [businessId.value, vendor.payeeId, vendor.name, vendor.type.name],
      );
      final args = [
        businessId.value,
        vendor.id.value,
        vendor.payeeId,
        vendor.metadata.revision,
        payload,
        vendor.metadata.updatedAt.toIso8601String(),
        vendor.details['email'],
        vendor.details['telephone'],
      ];
      _database.execute(
        'INSERT INTO vendor_profiles(business_id,id,payee_id,revision,payload,updated_at,email,telephone) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(business_id,id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,updated_at=excluded.updated_at,email=excluded.email,telephone=excluded.telephone',
        args,
      );
      _database.execute(
        'INSERT INTO vendor_history(business_id,id,payee_id,revision,payload,updated_at,email,telephone) VALUES(?,?,?,?,?,?,?,?)',
        args,
      );
      _appendAudit(
        businessId: businessId,
        actorId: actorId,
        at: vendor.metadata.updatedAt,
        kind: 'vendor.saved',
        subjectId: vendor.id,
        detail: jsonEncode({
          'revision': vendor.metadata.revision,
          'payeeId': vendor.payeeId,
        }),
      );
    });
  }

  void _validateVendorArchive() {
    for (final row in _database.select('SELECT * FROM vendor_profiles')) {
      final current = _vendorFromRow(row);
      final history = vendorHistory(current.metadata.businessId, current.id);
      if (history.isEmpty ||
          history.length != current.metadata.revision ||
          jsonEncode(history.last.toJson()) != row['payload']) {
        throw const FormatException('Vendor history is incomplete.');
      }
      for (var index = 0; index < history.length; index++) {
        final version = history[index];
        if (version.metadata.revision != index + 1 ||
            version.payeeId != current.payeeId ||
            version.metadata.createdAt != current.metadata.createdAt ||
            version.metadata.originDeviceId !=
                current.metadata.originDeviceId ||
            (index == 0
                ? version.metadata.createdAt != version.metadata.updatedAt
                : !version.metadata.updatedAt.isAfter(
                    history[index - 1].metadata.updatedAt,
                  ))) {
          throw const FormatException(
            'Vendor history has invalid identity or revision order.',
          );
        }
      }
    }
  }
}
