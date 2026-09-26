import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/presentation/vendors_page.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/purchases/domain/vendor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../app/restored_page_routes_test.dart' show tables;
import 'archive_upgrade_test.dart' show body, envelope;

Vendor vendorFixture(
  AccountingWorkspace w, {
  Vendor? original,
  Payee? payee,
  EntityId? id,
  EntityId? businessId,
  String name = 'Fictional Vendor',
  PayeeType type = PayeeType.supplier,
  DateTime? at,
  Map<String, String>? additionalValues,
}) {
  final profileId = original?.id ?? id ?? EntityId.random();
  return Vendor(
    additionalValues:
        additionalValues ?? original?.additionalValues ?? const {},
    metadata:
        original?.metadata.nextRevision(
          updatedAt: at ?? DateTime.utc(2026, 9, 27, 1),
        ) ??
        RecordMetadata.initial(
          recordId: profileId,
          businessId: businessId ?? w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: at ?? DateTime.utc(2026, 9, 27),
        ),
    payeeId: original?.payeeId ?? payee?.id ?? profileId.value,
    name: name,
    type: type,
    details: VendorDetails(
      values: {
        'partyType': 'Business',
        'email': 'fictional@example.invalid',
        'telephone': '+60 000 0000',
        'addressLine1': 'Fictional line one',
        'addressLine2': 'Unit 002',
        'city': 'Fictional City',
        'postcode': '00123 AB',
        'state': 'Fictional Region',
        'countryCode': 'ZZ',
        'countryName': 'Fictional Country',
        'identificationType': 'Business Registration',
        'identificationNumber': 'FICT-ID',
        'tin': 'FICT-TIN',
        'sstRegistrationNumber': 'FICT-SST',
        'notes': 'Fictional contact notes',
      },
      taxDetailsNeeded: false,
    ),
    currency: Currency.parse('SGD'),
    terms: PaymentTerms.dayOfMonth(31, rolloverWithinDays: 5),
  );
}

void main() {
  test('vendor snapshots retain every contact fact and reject malformed identities', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final vendor = vendorFixture(w);
    expect(Vendor.fromJson(vendor.toJson()).toJson(), vendor.toJson());
    expect(vendor.toJson()['version'], 1);
    expect(
      jsonEncode(Vendor.fromJson(vendor.toJson()).toJson()),
      jsonEncode(vendor.toJson()),
    );
    final extended = vendorFixture(
      w,
      additionalValues: {
        'companyName': 'Fictional Company',
        'mobileNumber': '+60 000 222',
        'supplierCategory': 'Foreign Business',
        'accountNumber': '0007 AB',
        'billingRate': '125.50',
      },
    );
    expect(extended.toJson()['version'], 2);
    expect(
      jsonEncode(Vendor.fromJson(extended.toJson()).toJson()),
      jsonEncode(extended.toJson()),
    );
    for (final values in [
      {'unknown': 'discarded'},
      {'supplierCategory': 'staff'},
      {'billingRate': '-1.00'},
      {'billingRate': 'invalid'},
    ]) {
      expect(
        () => vendorFixture(w, additionalValues: values),
        throwsFormatException,
      );
    }
    expect(
      () => Vendor.fromJson({
        ...extended.toJson(),
        'additionalValues': <String, String>{},
      }),
      throwsFormatException,
    );
    expect(vendor.details['postcode'], '00123 AB');
    expect(vendor.details.taxDetailsNeeded, false);
    expect(vendor.details['tin'], 'FICT-TIN');
    expect(
      () => Vendor.fromJson({...vendor.toJson(), 'type': 'staff'}),
      throwsFormatException,
    );
    expect(
      () => Vendor.fromJson({...vendor.toJson(), 'unexpected': true}),
      throwsFormatException,
    );
    expect(
      () => VendorDetails(values: {'countryCode': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => VendorDetails(values: {'countryName': 'Missing ISO'}),
      throwsFormatException,
    );
  });

  test('supplier identity, history, directory cache and all tables survive reopen and restore', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-vendor-persistence-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    var w = await createDemoWorkspace(databasePath: path);
    final identity = w.identity;
    final payee = w.payees.add(
      id: 'legacy-supplier-id',
      name: 'Alternative Office Supplier',
      type: PayeeType.supplier,
    );
    final before = tables(w);
    final beforeReport = (await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    ));
    final cache = w.payees;
    final first = vendorFixture(w, payee: payee);
    w.saveVendor(first, expectedRevision: 0, expectedPayee: payee);
    final second = vendorFixture(
      w,
      original: first,
      name: 'Fictional Updated Supplier',
      type: PayeeType.smallProvider,
      additionalValues: {
        'companyName': 'Fictional Updated Company',
        'mobileNumber': '+65 000 222',
        'supplierCategory': 'Foreign Business',
        'accountNumber': '0007 AB',
        'billingRate': '125.50',
      },
    );
    w.saveVendor(second, expectedRevision: 1);
    expect(identical(w.payees, cache), true);
    expect(cache.byId(payee.id)!.name, second.name);
    expect(cache.byId(payee.id)!.type, PayeeType.smallProvider);
    for (final entry in before.entries) {
      if (!{
        'payees',
        'vendor_profiles',
        'vendor_history',
        'ledger_audit',
      }.contains(entry.key)) {
        expect(
          tables(w)[entry.key],
          entry.value,
          reason: 'Master edit cannot change ${entry.key}',
        );
      }
    }
    final after = tables(w);
    expect(
      (after['ledger_audit']['rows'] as List).length,
      (before['ledger_audit']['rows'] as List).length + 2,
    );
    final archive = w.database.exportDataArchive(
      identity.businessId,
      DateTime.utc(2026, 9, 28),
    );
    w.dispose();
    final originalHash = sha256
        .convert(File(path).readAsBytesSync())
        .toString();
    w = await AccountingWorkspace.open(path);
    expect(tables(w), after);
    expect(
      w.database.readVendor(identity.businessId, first.id)!.toJson(),
      second.toJson(),
    );
    expect(
      w.database
          .vendorHistory(identity.businessId, first.id)
          .map((v) => v.toJson()),
      [first.toJson(), second.toJson()],
    );
    w.dispose();
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    restored.dispose();
    w = await AccountingWorkspace.open('${root.path}/restored.sqlite');
    addTearDown(w.dispose);
    expect(tables(w), after);
    expect(w.identity.businessId, identity.businessId);
    expect(w.payees.byId(payee.id)!.name, second.name);
    expect(w.database.vendorHistory(identity.businessId, first.id).length, 2);
    // Compare report facts separately; master contact changes do not post a journal.
    final report = await w.report(
      from: DateTime.utc(2026),
      through: DateTime.utc(2026, 12, 31),
    );
    expect(report.periodProfit, beforeReport.periodProfit);
    expect(report.assets, beforeReport.assets);
    expect(report.liabilities, beforeReport.liabilities);
    expect(report.revenue, beforeReport.revenue);
    expect(report.trialBalanceDebits, beforeReport.trialBalanceDebits);
    expect(report.trialBalanceCredits, beforeReport.trialBalanceCredits);
    expect(report.postedJournalIds, beforeReport.postedJournalIds);
    expect(
      sha256.convert(File(path).readAsBytesSync()).toString(),
      originalHash,
    );
  });

  test('supplier default account is a stable eligible ID; unavailable commands cannot save', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    await w.createAccount(
      code: '5000',
      name: 'Services',
      type: AccountType.expense,
    );
    await w.createAccount(
      code: '5100',
      name: 'Group',
      type: AccountType.expense,
      isParent: true,
    );
    await w.createAccount(code: '1000', name: 'Cash', type: AccountType.asset);
    final accounts = await w.accounts();
    final selected = accounts.singleWhere((a) => a.account.code == '5000');
    final first = vendorFixture(
      w,
      additionalValues: {'defaultExpenseAccountId': selected.account.id.value},
    );
    w.saveVendor(first, expectedRevision: 0);
    for (final id in [
      EntityId.random().value,
      ...accounts.where((a) => a != selected).map((a) => a.account.id.value),
    ]) {
      final before = tables(w);
      expect(
        () => w.saveVendor(
          vendorFixture(
            w,
            original: first,
            additionalValues: {'defaultExpenseAccountId': id},
          ),
          expectedRevision: 1,
        ),
        throwsStateError,
      );
      expect(tables(w), before);
    }
    await w.database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: selected.account.id,
          code: '5000',
          name: 'Services',
          type: AccountType.expense,
          status: AccountStatus.archived,
        ),
        metadata: selected.metadata.nextRevision(
          updatedAt: selected.metadata.updatedAt.add(
            const Duration(seconds: 1),
          ),
        ),
      ),
    );
    final retained = vendorFixture(w, original: first, name: 'Renamed contact');
    w.saveVendor(retained, expectedRevision: 1);
    expect(
      w.database
          .readVendor(w.identity.businessId, first.id)!
          .additionalValues['defaultExpenseAccountId'],
      selected.account.id.value,
    );
    final before = tables(w);
    expect(
      () => w.saveVendor(
        vendorFixture(
          w,
          additionalValues: {
            'defaultExpenseAccountId': selected.account.id.value,
          },
        ),
        expectedRevision: 0,
      ),
      throwsStateError,
    );
    for (final pending in [
      {'Opening Balance': '100.00'},
      {'Opening Balance Date': '01-10-2026'},
      {
        '_files': ['receipt.pdf'],
      },
      {
        '_attachments': ['attachment'],
      },
    ]) {
      expect(
        () => vendorFromForm(
          {...vendorFormValues(retained), ...pending},
          w,
          id: retained.id,
          payeeId: retained.payeeId,
          original: retained,
          now: retained.metadata.updatedAt.add(const Duration(seconds: 1)),
        ),
        throwsFormatException,
      );
      expect(tables(w), before);
    }
  });

  test('stale revisions, wrong actor/company and identity rewrites leave all tables and cache unchanged', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final first = vendorFixture(w);
    w.saveVendor(first, expectedRevision: 0);
    final second = vendorFixture(w, original: first, name: 'Second');
    w.saveVendor(second, expectedRevision: 1);
    final saved = tables(w);
    void unchanged() => expect(tables(w), saved);
    expect(
      () => w.saveVendor(
        vendorFixture(w, original: first, name: 'Stale'),
        expectedRevision: 1,
      ),
      throwsStateError,
    );
    unchanged();
    expect(
      () => w.database.saveVendor(
        businessId: w.identity.businessId,
        actorId: EntityId.random(),
        vendor: vendorFixture(
          w,
          original: second,
          at: DateTime.utc(2026, 9, 27, 2),
        ),
        expectedRevision: 2,
      ),
      throwsStateError,
    );
    unchanged();
    expect(
      () => w.saveVendor(
        vendorFixture(w, businessId: EntityId.random()),
        expectedRevision: 0,
      ),
      throwsStateError,
    );
    unchanged();
    final rewritten = Vendor.fromJson({
      ...vendorFixture(
        w,
        original: second,
        at: DateTime.utc(2026, 9, 27, 2),
      ).toJson(),
      'payeeId': 'rewritten',
    });
    expect(
      () => w.saveVendor(rewritten, expectedRevision: 2),
      throwsStateError,
    );
    unchanged();
    final changedOrigin = Vendor.fromJson({
      ...vendorFixture(
        w,
        original: second,
        at: DateTime.utc(2026, 9, 27, 2),
      ).toJson(),
      'deviceId': EntityId.random().value,
    });
    expect(
      () => w.saveVendor(changedOrigin, expectedRevision: 2),
      throwsStateError,
    );
    unchanged();
    expect(w.payees.byId(first.payeeId)!.name, second.name);
    expect(w.database.readVendor(EntityId.random(), first.id), null);
  });

  test('exact command retries add no history or audit and legacy writes cannot overwrite a profile', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final first = vendorFixture(w);
    w.saveVendor(first, expectedRevision: 0);
    final saved = tables(w);
    w.saveVendor(first, expectedRevision: 0);
    expect(tables(w), saved);
    w.payees.save(first.payee);
    expect(tables(w), saved);
    expect(
      () => w.payees.save(
        Payee(
          id: first.payeeId,
          name: 'Old editor rename',
          type: PayeeType.vendor,
        ),
      ),
      throwsStateError,
    );
    expect(w.payees.byId(first.payeeId)!.name, first.name);
    expect(tables(w), saved);
  });

  test('adding details checks the reviewed legacy supplier and prevents duplicate profiles', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final old = w.payees.add(
      id: 'old-string-id',
      name: 'Original',
      type: PayeeType.supplier,
    );
    final changed = w.payees.save(
      Payee(id: old.id, name: 'Changed', type: old.type),
    );
    final profile = vendorFixture(w, payee: old);
    final before = tables(w);
    expect(
      () => w.saveVendor(profile, expectedRevision: 0, expectedPayee: old),
      throwsStateError,
    );
    expect(tables(w), before);
    w.saveVendor(profile, expectedRevision: 0, expectedPayee: changed);
    final saved = tables(w);
    expect(
      () => w.saveVendor(
        vendorFixture(w, payee: profile.payee),
        expectedRevision: 0,
        expectedPayee: profile.payee,
      ),
      throwsStateError,
    );
    expect(tables(w), saved);
    expect(w.payees.byId(old.id)!.id, 'old-string-id');
  });

  test(
    'directory paging is bounded, stable and searches literal contact text',
    () async {
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      for (var i = 0; i < 23; i++) {
        final p = w.payees.add(
          id: 'legacy-$i',
          name: 'Supplier ${i.toString().padLeft(2, '0')}',
          type: PayeeType.supplier,
        );
        if (i == 22) {
          w.saveVendor(
            vendorFixture(w, payee: p, name: 'Literal 50%_'),
            expectedRevision: 0,
            expectedPayee: p,
          );
        }
      }
      w.payees.add(id: 'staff', name: 'Excluded', type: PayeeType.staff);
      final db = w.database, company = w.identity.businessId;
      expect(
        db.vendorDirectory(businessId: company, limit: 10).entries.length,
        10,
      );
      expect(
        db
            .vendorDirectory(businessId: company, limit: 10, offset: 20)
            .entries
            .length,
        3,
      );
      final outOfRange = db.vendorDirectory(
        businessId: company,
        limit: 10,
        offset: 1000,
      );
      expect(outOfRange.offset, 20);
      expect(outOfRange.total, 23);
      expect(
        db
            .vendorDirectory(businessId: company, search: '%_')
            .entries
            .single
            .payee
            .name,
        'Literal 50%_',
      );
      expect(
        db
            .vendorDirectory(businessId: company, search: 'example.invalid')
            .total,
        1,
      );
      expect(db.vendorDirectory(businessId: company, search: '+60').total, 1);
      expect(
        db.vendorDirectory(businessId: company, type: PayeeType.vendor).total,
        0,
      );
      expect(
        () => db.vendorDirectory(businessId: company, type: PayeeType.staff),
        throwsArgumentError,
      );
      expect(
        () => db.vendorDirectory(businessId: company, limit: 101),
        throwsArgumentError,
      );
      expect(db.vendorDirectory(businessId: EntityId.random()).total, 0);
    },
  );

  test('history-write failure rolls back the supplier, profile, audit and shared cache', () async {
    final root = Directory.systemTemp.createTempSync('audyt-vendor-rollback-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final first = vendorFixture(w);
    w.saveVendor(first, expectedRevision: 0);
    final before = tables(w);
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER reject_vendor_history BEFORE INSERT ON vendor_history BEGIN SELECT RAISE(ABORT,'Fictional write failure'); END",
    );
    raw.dispose();
    expect(
      () => w.saveVendor(
        vendorFixture(w, original: first, name: 'Must roll back'),
        expectedRevision: 1,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(tables(w), before);
    expect(w.payees.byId(first.payeeId)!.name, first.name);
    final clean = sqlite3.open(path);
    clean.execute('DROP TRIGGER reject_vendor_history');
    expect(
      () => clean.execute("UPDATE vendor_history SET email='wrong'"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => clean.execute('DELETE FROM vendor_history'),
      throwsA(isA<SqliteException>()),
    );
    clean.dispose();
  });

  test('strict restore rejects changed supplier links, malformed or missing revision history', () async {
    final root = Directory.systemTemp.createTempSync('audyt-vendor-archive-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/source.sqlite';
    final w = await AccountingWorkspace.open(path);
    final first = vendorFixture(w);
    w.saveVendor(first, expectedRevision: 0);
    w.saveVendor(
      vendorFixture(w, original: first, name: 'Second'),
      expectedRevision: 1,
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 9, 28),
    );
    w.dispose();
    final hash = sha256.convert(File(path).readAsBytesSync()).toString();
    List row(Map<String, dynamic> data, String table, [int index = 0]) =>
        data['tables'][table]['rows'][index] as List;
    int column(Map<String, dynamic> data, String table, String key) =>
        (data['tables'][table]['columns'] as List).indexOf(key);
    final corruptions = <void Function(Map<String, dynamic>)>[
      (data) => row(data, 'payees')[column(data, 'payees', 'name')] =
          'Wrong supplier',
      (data) => (data['tables']['vendor_history']['rows'] as List).removeAt(0),
      (data) => row(
        data,
        'vendor_profiles',
      )[column(data, 'vendor_profiles', 'email')] = 'Mismatch',
      (data) => row(
        data,
        'vendor_profiles',
      )[column(data, 'vendor_profiles', 'payload')] = '{}',
      (data) {
        final version = row(data, 'vendor_history');
        final position = column(data, 'vendor_history', 'payload');
        final payload = jsonDecode(version[position]);
        payload['deviceId'] = EntityId.random().value;
        version[position] = jsonEncode(payload);
      },
      (data) {
        final version = row(data, 'vendor_history');
        final position = column(data, 'vendor_history', 'payload');
        final payload = jsonDecode(version[position]);
        payload['terms']['unexpected'] = true;
        version[position] = jsonEncode(payload);
      },
    ];
    for (var i = 0; i < corruptions.length; i++) {
      final broken = body(archive);
      corruptions[i](broken);
      final target = LocalAccountingDatabase.inMemory();
      expect(
        () => target.restoreDataArchive(envelope(broken)),
        throwsFormatException,
        reason: 'defect $i',
      );
      target.restoreDataArchive(archive);
      expect(
        target.vendorHistory(first.metadata.businessId, first.id).length,
        2,
      );
      target.close();
      expect(sha256.convert(File(path).readAsBytesSync()).toString(), hash);
    }
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/good.sqlite',
      archive,
    );
    expect(
      restored.database
          .vendorHistory(restored.identity.businessId, first.id)
          .length,
      2,
    );
    restored.dispose();
  });
}
