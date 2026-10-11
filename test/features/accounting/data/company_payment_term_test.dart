import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_payment_method.dart';
import 'package:audyt/features/accounting/domain/company_payment_term.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

String package(Map<String, dynamic> body) {
  final encoded = jsonEncode(body);
  return jsonEncode({
    'format': 'Audyt Data Archive',
    'sha256': sha256.convert(utf8.encode(encoded)).toString(),
    'data': encoded,
  });
}

Map<String, dynamic> body(String archive) =>
    jsonDecode((jsonDecode(archive) as Map)['data'] as String)
        as Map<String, dynamic>;

void changeCell(
  Map<String, dynamic> data,
  String table,
  String column,
  Object? value,
) {
  final owner = (data['tables'] as Map)[table] as Map;
  final offset = (owner['columns'] as List).indexOf(column);
  (owner['rows'] as List).single[offset] = value;
}

void main() {
  test('named terms validate exact rules and retain stable JSON', () {
    final id = EntityId.random();
    final term = CompanyPaymentTerm(
      id: id,
      name: '  End of Month  ',
      rule: PaymentTerms.dayOfMonth(15, rolloverWithinDays: 3),
    );
    expect(term.name, 'End of Month');
    expect(CompanyPaymentTerm.fromJson(term.toJson()).toJson(), term.toJson());
    expect(
      () =>
          CompanyPaymentTerm(id: id, name: ' ', rule: PaymentTerms.netDays(7)),
      throwsFormatException,
    );
    expect(
      () => CompanyPaymentTerm(
        id: id,
        name: 'x' * 201,
        rule: PaymentTerms.netDays(7),
      ),
      throwsFormatException,
    );
    expect(
      () => CompanyPaymentTerm(
        id: id,
        name: 'Custom',
        rule: PaymentTerms.custom('Upon receipt'),
      ),
      throwsFormatException,
    );
    expect(
      () => CompanyPaymentTerm(
        id: id,
        name: 'Net 7',
        rule: PaymentTerms.netDays(7, customText: 'Hidden'),
      ),
      throwsFormatException,
    );
  });

  test(
    'create is owner-only, company-scoped, unique, audited and durable',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-terms-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final business = workspace.identity.businessId;
      final owner = workspace.identity.ownerId;
      final id = EntityId.random();
      final input = CompanyPaymentTerm(
        id: id,
        name: '  Net Seven  ',
        rule: PaymentTerms.netDays(7),
      );
      final before = workspace.database.exportDataArchive(
        business,
        DateTime.utc(2026, 10, 11),
      );
      expect(
        () => workspace.database.createPaymentTerm(
          businessId: business,
          actorId: EntityId.random(),
          term: input,
          createdAt: DateTime.utc(2026, 10, 11),
        ),
        throwsStateError,
      );
      expect(
        () => workspace.database.createPaymentTerm(
          businessId: EntityId.random(),
          actorId: owner,
          term: input,
          createdAt: DateTime.utc(2026, 10, 11),
        ),
        throwsStateError,
      );
      expect(
        workspace.database.exportDataArchive(
          business,
          DateTime.utc(2026, 10, 11),
        ),
        before,
      );
      final saved = workspace.createPaymentTerm(input);
      expect(saved.name, 'Net Seven');
      expect(saved.revision, 1);
      expect(saved.active, isTrue);
      expect(saved.createdAt?.isUtc, isTrue);
      expect(workspace.paymentTerms.single.toJson(), saved.toJson());
      for (final duplicate in [
        input,
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'net seven',
          rule: PaymentTerms.netDays(30),
        ),
      ]) {
        expect(() => workspace.createPaymentTerm(duplicate), throwsStateError);
      }
      expect(() => workspace.createPaymentTerm(saved), throwsStateError);
      expect(
        () => workspace.createPaymentTerm(
          CompanyPaymentTerm(
            id: EntityId.random(),
            name: 'Inactive',
            rule: PaymentTerms.netDays(5),
            active: false,
          ),
        ),
        throwsStateError,
      );
      final monthly = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Monthly',
          rule: PaymentTerms.dayOfMonth(20),
        ),
      );
      expect(workspace.paymentTerms.map((term) => term.name), [
        'Monthly',
        'Net Seven',
      ]);
      final raw = sqlite3.open(path);
      expect(
        raw.select(
          "SELECT kind,actor_id FROM ledger_audit WHERE kind='payment_term_created'",
        ),
        hasLength(2),
      );
      expect(
        raw.select("SELECT actor_id FROM ledger_audit WHERE subject_id=?", [
          id.value,
        ]).single['actor_id'],
        owner.value,
      );
      raw.dispose();
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.paymentTerms.map((term) => term.toJson()), [
        monthly.toJson(),
        saved.toJson(),
      ]);
      expect(workspace.database.readPaymentTerms(EntityId.random()), isEmpty);
    },
  );

  test(
    'archive restores exact terms and rejects tampered facts or audit',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-term-archive-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${folder.path}/source.sqlite',
      );
      addTearDown(workspace.dispose);
      final saved = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Monthly Cutoff',
          rule: PaymentTerms.dayOfMonth(25, rolloverWithinDays: 5),
        ),
      );
      final original = body(
        workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.utc(2026, 10, 11),
        ),
      );
      final recovered = LocalAccountingDatabase.inMemory();
      addTearDown(recovered.close);
      recovered.restoreDataArchive(package(original));
      expect(
        recovered
            .readPaymentTerms(workspace.identity.businessId)
            .single
            .toJson(),
        saved.toJson(),
      );

      final owner = (original['tables'] as Map)['company_payment_terms'] as Map;
      final columns = owner['columns'] as List;
      final row = (owner['rows'] as List).single as List;
      final payload = jsonDecode(
        row[columns.indexOf('payload')] as String,
      ) as Map<String, dynamic>;
      final cases = <void Function(Map<String, dynamic>)>[
        (data) => changeCell(data, 'company_payment_terms', 'name', 'Other'),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'normalized_name',
          'wrong',
        ),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'created_at',
          DateTime.utc(2020).toIso8601String(),
        ),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'business_id',
          EntityId.random().value,
        ),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'id',
          EntityId.random().value,
        ),
        (data) => changeCell(data, 'company_payment_terms', 'revision', 2),
        (data) => changeCell(data, 'company_payment_terms', 'active', 0),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'payload',
          jsonEncode({...payload, 'name': 'Other'}),
        ),
        (data) => changeCell(
          data,
          'company_payment_terms',
          'payload',
          jsonEncode({
            ...payload,
            'rule': PaymentTerms.custom('When ready').toJson(),
          }),
        ),
        (data) => changeCell(
          data,
          'ledger_audit',
          'actor_id',
          EntityId.random().value,
        ),
        (data) => changeCell(
          data,
          'ledger_audit',
          'occurred_at',
          DateTime.utc(2020).toIso8601String(),
        ),
      ];
      for (final tamper in cases) {
        final changed =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        tamper(changed);
        final target = LocalAccountingDatabase.inMemory();
        try {
          expect(
            () => target.restoreDataArchive(package(changed)),
            throwsA(anything),
          );
          expect(
            target.readPaymentTerms(workspace.identity.businessId),
            isEmpty,
          );
        } finally {
          target.close();
        }
      }
    },
  );

  test(
    'restored copy retains owner, rule, audit and accepts new terms',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-term-copy-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final original = await AccountingWorkspace.open(
        '${folder.path}/original.sqlite',
      );
      addTearDown(original.dispose);
      final saved = original.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Cutoff',
          rule: PaymentTerms.dayOfMonth(12, rolloverWithinDays: 2),
        ),
      );
      final archived = original.database.exportDataArchive(
        original.identity.businessId,
        DateTime.utc(2026, 10, 11),
      );
      final copyPath = '${folder.path}/copy.sqlite';
      var copy = await AccountingWorkspace.emptyRestore(copyPath, archived);
      expect(copy.identity.businessId, original.identity.businessId);
      expect(copy.identity.ownerId, original.identity.ownerId);
      expect(copy.paymentTerms.single.toJson(), saved.toJson());
      copy.dispose();
      copy = await AccountingWorkspace.openExisting(
        copyPath,
        businessId: original.identity.businessId,
        restoredCopyId: EntityId.random().value,
      );
      addTearDown(copy.dispose);
      expect(copy.paymentTerms.single.toJson(), saved.toJson());
      final next = copy.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 14',
          rule: PaymentTerms.netDays(14),
        ),
      );
      expect(copy.paymentTerms, hasLength(2));
      expect(original.paymentTerms.single.toJson(), saved.toJson());
      expect(next.revision, 1);
      final verified = LocalAccountingDatabase.inMemory();
      addTearDown(verified.close);
      verified.restoreDataArchive(
        copy.database.exportDataArchive(
          copy.identity.businessId,
          DateTime.utc(2026, 10, 11),
        ),
      );
      expect(verified.readPaymentTerms(copy.identity.businessId), hasLength(2));
    },
  );

  test(
    'schema 65 upgrades additively without changing existing rows',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-term-v65-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final business = workspace.identity.businessId;
      workspace.savePaymentMethod(
        CompanyPaymentMethod(id: EntityId.random(), name: 'Cheque'),
      );
      final baseline = body(
        workspace.database.exportDataArchive(
          business,
          DateTime.utc(2026, 10, 11),
        ),
      );
      workspace.dispose();
      final raw = sqlite3.open(path);
      expect(raw.select('SELECT 1 FROM company_payment_terms'), isEmpty);
      raw.execute('DROP TABLE company_payment_terms');
      raw.execute('PRAGMA user_version=65');
      raw.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final upgraded = sqlite3.open(path);
      expect(upgraded.select('PRAGMA user_version').single.values.single, 66);
      upgraded.dispose();
      final after = body(
        workspace.database.exportDataArchive(
          business,
          DateTime.utc(2026, 10, 11),
        ),
      );
      final beforeTables = baseline['tables'] as Map;
      final afterTables = after['tables'] as Map;
      for (final entry in beforeTables.entries) {
        if (entry.key == 'company_payment_terms') continue;
        expect(
          afterTables[entry.key],
          entry.value,
          reason: entry.key as String,
        );
      }
      expect((afterTables['company_payment_terms'] as Map)['rows'], isEmpty);
      final archive65 =
          jsonDecode(jsonEncode(baseline)) as Map<String, dynamic>;
      archive65['schemaVersion'] = 65;
      (archive65['tables'] as Map).remove('company_payment_terms');
      final recovered = LocalAccountingDatabase.inMemory();
      addTearDown(recovered.close);
      recovered.restoreDataArchive(package(archive65));
      expect(recovered.readPaymentMethods(business).single.name, 'Cheque');
      expect(recovered.readPaymentTerms(business), isEmpty);
    },
  );
}
