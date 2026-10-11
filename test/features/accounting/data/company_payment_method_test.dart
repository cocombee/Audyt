import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_payment_method.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'expense_revision_test.dart' show archive, change, line, save, source;

RecordExpenseDraft expense({CompanyPaymentMethod? method}) =>
    RecordExpenseDraft(
      amount: '25.50',
      date: '10-10-2026',
      payee: 'Fictional Supplier',
      paymentAccount: 'Fictional Bank',
      paymentAccountId: 'bank',
      paymentMethod: method,
      category: 'Office Operations',
      tax: 'Review Needed',
      customer: '',
      billable: false,
      dimensions: '',
      itemOrSplitDetails: '',
      notes: 'Original note',
      submissionId: 'payment-method-expense',
    );

String repackage(Map<String, dynamic> data) {
  final encoded = jsonEncode(data);
  return jsonEncode({
    'format': 'Audyt Data Archive',
    'sha256': sha256.convert(utf8.encode(encoded)).toString(),
    'data': encoded,
  });
}

void main() {
  test(
    'company methods retain owner, revisions, audit and immutable history',
    () async {
      final folder = Directory.systemTemp.createTempSync('audyt-methods-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final id = EntityId.random();
      final first = workspace.savePaymentMethod(
        CompanyPaymentMethod(id: id, name: '  Cheque  '),
      );
      expect(first.name, 'Cheque');
      expect(first.cardPayment, isFalse);
      expect(first.active, isTrue);
      expect(first.revision, 1);
      expect(first.choice, '${id.value}:1');
      expect(workspace.paymentMethods.single.toJson(), first.toJson());
      expect(
        () => workspace.savePaymentMethod(
          CompanyPaymentMethod(id: EntityId.random(), name: 'CHEQUE'),
        ),
        throwsStateError,
      );
      final second = workspace.savePaymentMethod(
        CompanyPaymentMethod(
          id: id,
          name: 'Company Card',
          cardPayment: true,
          active: false,
          revision: first.revision,
        ),
      );
      expect(second.revision, 2);
      expect(workspace.paymentMethodHistory(id).map((m) => m.toJson()), [
        first.toJson(),
        second.toJson(),
      ]);
      expect(() => workspace.savePaymentMethod(first), throwsStateError);
      expect(
        () => workspace.database.savePaymentMethod(
          businessId: workspace.identity.businessId,
          actorId: EntityId.random(),
          method: second,
          savedAt: DateTime.now().toUtc(),
        ),
        throwsStateError,
      );
      expect(
        () => workspace.database.savePaymentMethod(
          businessId: EntityId.random(),
          actorId: workspace.identity.ownerId,
          method: second,
          savedAt: DateTime.now().toUtc(),
        ),
        throwsStateError,
      );
      final raw = sqlite3.open(path);
      expect(
        raw.select(
          "SELECT kind FROM ledger_audit WHERE kind='payment_method_saved'",
        ),
        hasLength(2),
      );
      expect(
        () => raw.execute(
          'UPDATE company_payment_method_history SET payload=? WHERE business_id=? AND id=? AND revision=1',
          ['{}', workspace.identity.businessId.value, id.value],
        ),
        throwsA(isA<SqliteException>()),
      );
      raw.dispose();
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.paymentMethods.single.toJson(), second.toJson());
      expect(workspace.paymentMethodHistory(id).map((m) => m.toJson()), [
        first.toJson(),
        second.toJson(),
      ]);
    },
  );

  test(
    'Expense saves exact current method and retains historical snapshot',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'audyt-expense-method-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'bank',
          name: 'Fictional Bank',
          type: PaymentAccountType.bank,
          currencyCode: workspace.identity.currency,
        ),
      );
      final first = workspace.savePaymentMethod(
        CompanyPaymentMethod(id: EntityId.random(), name: 'Cheque'),
      );
      final original = expense(method: first);
      final savedId = await workspace.saveExpenseIntake(original);
      expect(
        (await workspace.expense(savedId))!.draft.paymentMethod!.toJson(),
        first.toJson(),
      );
      final inactive = workspace.savePaymentMethod(
        CompanyPaymentMethod(
          id: first.id,
          name: 'Renamed Cheque',
          active: false,
          revision: first.revision,
        ),
      );
      expect(await workspace.saveExpenseIntake(original), savedId);
      await expectLater(
        workspace.saveExpenseIntake(
          RecordExpenseDraft.fromJson({
            ...expense(method: inactive).toJson(),
            'submissionId': 'new-inactive-method',
          }),
        ),
        throwsStateError,
      );
      await expectLater(
        workspace.saveExpenseIntake(
          RecordExpenseDraft.fromJson({
            ...original.toJson(),
            'submissionId': 'new-stale-method',
          }),
        ),
        throwsStateError,
      );
      await expectLater(
        workspace.updateExpenseIntake(
          id: savedId,
          expected: original,
          replacement: RecordExpenseDraft.fromJson({
            ...original.toJson(),
            'paymentMethod': inactive.toJson(),
          }),
        ),
        throwsStateError,
      );
      final foreign = await AccountingWorkspace.open(':memory:');
      addTearDown(foreign.dispose);
      final foreignMethod = foreign.savePaymentMethod(
        CompanyPaymentMethod(id: EntityId.random(), name: 'Foreign Cheque'),
      );
      await expectLater(
        workspace.saveExpenseIntake(
          RecordExpenseDraft.fromJson({
            ...expense(method: foreignMethod).toJson(),
            'submissionId': 'foreign-method',
          }),
        ),
        throwsStateError,
      );
      final forged = CompanyPaymentMethod.fromJson({
        ...first.toJson(),
        'name': 'Forged Cheque',
      });
      await expectLater(
        workspace.saveExpenseIntake(
          RecordExpenseDraft.fromJson({
            ...expense(method: forged).toJson(),
            'submissionId': 'forged-method',
          }),
        ),
        throwsStateError,
      );
      await workspace.updateExpenseIntake(
        id: savedId,
        expected: original,
        replacement: RecordExpenseDraft.fromJson({
          ...original.toJson(),
          'notes': 'Historical method retained.',
        }),
      );
      final edited = (await workspace.expense(savedId))!.draft;
      expect(edited.paymentMethod!.toJson(), first.toJson());
      expect(edited.notes, 'Historical method retained.');
      final archive = workspace.database.exportDataArchive(
        workspace.identity.businessId,
        DateTime.utc(2026, 10, 11),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(
        (await workspace.expense(savedId))!.draft.paymentMethod!.toJson(),
        first.toJson(),
      );
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      restored.restoreDataArchive(archive);
      expect(
        (await restored.getExpenseIntake(
          workspace.identity.businessId,
          savedId,
        ))!.draft.paymentMethod!.toJson(),
        first.toJson(),
      );
      final data = jsonDecode(
        (jsonDecode(archive) as Map)['data'] as String,
      ) as Map<String, dynamic>;
      final table = (data['tables'] as Map)['expense_intakes'] as Map;
      final columns = table['columns'] as List;
      final payload = columns.indexOf('payload');
      final row = (table['rows'] as List).single as List;
      final corrupted =
          jsonDecode(row[payload] as String) as Map<String, dynamic>;
      corrupted['paymentMethod'] = forged.toJson();
      row[payload] = jsonEncode(corrupted);
      final rejected = LocalAccountingDatabase.inMemory();
      addTearDown(rejected.close);
      expect(
        () => rejected.restoreDataArchive(repackage(data)),
        throwsStateError,
      );

      for (final corruption in ['revision', 'saved_at', 'payload_id']) {
        final broken = jsonDecode(
          (jsonDecode(archive) as Map)['data'] as String,
        ) as Map<String, dynamic>;
        final history =
            (broken['tables'] as Map)['company_payment_method_history'] as Map;
        final historyColumns = history['columns'] as List;
        final historyRow = (history['rows'] as List).first as List;
        switch (corruption) {
          case 'revision':
            historyRow[historyColumns.indexOf('revision')] = 99;
          case 'saved_at':
            historyRow[historyColumns.indexOf('saved_at')] = 'not-a-date';
          case 'payload_id':
            final payloadIndex = historyColumns.indexOf('payload');
            final payload = jsonDecode(
              historyRow[payloadIndex] as String,
            ) as Map<String, dynamic>;
            payload['id'] = EntityId.random().value;
            historyRow[payloadIndex] = jsonEncode(payload);
        }
        final malformed = LocalAccountingDatabase.inMemory();
        addTearDown(malformed.close);
        expect(
          () => malformed.restoreDataArchive(repackage(broken)),
          throwsFormatException,
          reason: 'Archive must reject a malformed $corruption history row.',
        );
      }
    },
  );

  test(
    'posted Expense revisions reject forged or inactive new method facts',
    () async {
      final fixture = Fixture();
      await fixture.open();
      final original = await source(fixture);
      final first = fixture.w.savePaymentMethod(
        CompanyPaymentMethod(id: EntityId.random(), name: 'Cheque'),
      );
      final reviewed = change(
        original.draft,
        [line('original', '11')],
        '11',
        fields: {'paymentMethod': first.toJson()},
      );
      final saved = save(fixture, original, reviewed);
      expect(saved.draft.paymentMethod!.toJson(), first.toJson());
      final inactive = fixture.w.savePaymentMethod(
        CompanyPaymentMethod(
          id: first.id,
          name: 'Retired Cheque',
          active: false,
          revision: first.revision,
        ),
      );
      final before = archive(fixture);
      final forged = change(
        saved.draft,
        [line('original', '12')],
        '12',
        fields: {
          'paymentMethod': {...first.toJson(), 'name': 'Forged Cheque'},
        },
      );
      expect(
        () => save(fixture, original, forged, revision: 1, before: saved.draft),
        throwsStateError,
      );
      final relinked = change(
        saved.draft,
        [line('original', '12')],
        '12',
        fields: {'paymentMethod': inactive.toJson()},
      );
      expect(
        () =>
            save(fixture, original, relinked, revision: 1, before: saved.draft),
        throwsStateError,
      );
      expect(archive(fixture), before);
      final retained = change(saved.draft, [line('original', '12')], '12');
      final next = save(
        fixture,
        original,
        retained,
        revision: 1,
        before: saved.draft,
      );
      expect(next.draft.paymentMethod!.toJson(), first.toJson());
    },
  );

  test('schema 64 Expense and Voucher survive database and archive upgrade unchanged', () async {
    final folder = Directory.systemTemp.createTempSync('audyt-method-upgrade-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/legacy.sqlite';
    final original = await AccountingWorkspace.open(path);
    original.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Fictional Bank',
        type: PaymentAccountType.bank,
        currencyCode: original.identity.currency,
      ),
    );
    final expenseId = await original.saveExpenseIntake(expense());
    final voucherSource = original.vouchers.sources.singleWhere(
      (source) => source.id == expenseId.value,
    );
    original.vouchers.save(
      PaymentVoucher.create(
        id: 'legacy-voucher',
        sourceType: voucherSource.type,
        sourceId: voucherSource.id,
        payee: voucherSource.payee,
        amount: voucherSource.amount,
        paymentAccount: 'Fictional Bank',
        paymentAccountId: 'bank',
        paymentMethod: 'Legacy Bank Transfer',
        paymentDate: voucherSource.date,
        reference: 'Legacy voucher',
      ),
    );
    final business = original.identity.businessId;
    final exported = original.database.exportDataArchive(
      business,
      DateTime.utc(2026, 10, 11),
    );
    final baseline = jsonDecode(
      (jsonDecode(exported) as Map)['data'] as String,
    ) as Map<String, dynamic>;
    baseline['schemaVersion'] = 64;
    final oldTables = baseline['tables'] as Map;
    expect((oldTables.remove('company_payment_terms') as Map)['rows'], isEmpty);
    for (final table in [
      'company_payment_method_history',
      'company_payment_methods',
    ]) {
      expect((oldTables.remove(table) as Map)['rows'], isEmpty);
    }
    final expenseTable = oldTables['expense_intakes'] as Map;
    final expensePayloadColumn = (expenseTable['columns'] as List).indexOf(
      'payload',
    );
    final legacyExpensePayload =
        ((expenseTable['rows'] as List).single as List)[expensePayloadColumn]
            as String;
    expect(
      (jsonDecode(legacyExpensePayload) as Map).containsKey('paymentMethod'),
      isFalse,
    );
    final voucherTable = oldTables['payment_vouchers'] as Map;
    final voucherPayloadColumn = (voucherTable['columns'] as List).indexOf(
      'payload',
    );
    final legacyVoucherPayload =
        ((voucherTable['rows'] as List).single as List)[voucherPayloadColumn]
            as String;
    expect(legacyVoucherPayload, contains('Legacy Bank Transfer'));
    original.dispose();

    // Reconstruct the exact old table set from an empty v65 owner, then let
    // the production opener perform the genuine 64 -> 65 migration.
    final raw = sqlite3.open(path);
    expect(raw.select('SELECT 1 FROM company_payment_methods'), isEmpty);
    expect(raw.select('SELECT 1 FROM company_payment_method_history'), isEmpty);
    expect(raw.select('SELECT 1 FROM company_payment_terms'), isEmpty);
    raw.execute('DROP TABLE company_payment_terms');
    raw.execute('DROP TABLE company_payment_method_history');
    raw.execute('DROP TABLE company_payment_methods');
    raw.execute('PRAGMA user_version=64');
    expect(raw.select('PRAGMA user_version').single.values.single, 64);
    raw.dispose();

    void expectOldRowsUnchanged(AccountingWorkspace workspace) {
      final current = jsonDecode(
        (jsonDecode(
              workspace.database.exportDataArchive(
                business,
                DateTime.utc(2026, 10, 11),
              ),
            ) as Map)['data']
            as String,
      ) as Map<String, dynamic>;
      final tables = current['tables'] as Map;
      for (final entry in oldTables.entries) {
        expect(tables[entry.key], entry.value, reason: entry.key as String);
      }
      expect((tables['company_payment_methods'] as Map)['rows'], isEmpty);
      expect(
        (tables['company_payment_method_history'] as Map)['rows'],
        isEmpty,
      );
      expect(
        ((tables['expense_intakes'] as Map)['rows'] as List)
            .single[expensePayloadColumn],
        legacyExpensePayload,
      );
      expect(
        ((tables['payment_vouchers'] as Map)['rows'] as List)
            .single[voucherPayloadColumn],
        legacyVoucherPayload,
      );
    }

    final upgraded = await AccountingWorkspace.open(path);
    addTearDown(upgraded.dispose);
    expectOldRowsUnchanged(upgraded);
    final restored = await AccountingWorkspace.emptyRestore(
      '${folder.path}/restored.sqlite',
      repackage(baseline),
    );
    addTearDown(restored.dispose);
    expectOldRowsUnchanged(restored);

    upgraded.savePaymentMethod(
      CompanyPaymentMethod(id: EntityId.random(), name: 'Cheque'),
    );
    final afterMethod = jsonDecode(
      (jsonDecode(
            upgraded.database.exportDataArchive(
              business,
              DateTime.utc(2026, 10, 11),
            ),
          ) as Map)['data']
          as String,
    ) as Map<String, dynamic>;
    final afterTables = afterMethod['tables'] as Map;
    for (final entry in oldTables.entries) {
      if (entry.key == 'ledger_audit') continue;
      expect(afterTables[entry.key], entry.value, reason: entry.key as String);
    }
    final auditBefore = (oldTables['ledger_audit'] as Map)['rows'] as List;
    final auditAfter = (afterTables['ledger_audit'] as Map)['rows'] as List;
    expect(auditAfter.take(auditBefore.length).toList(), auditBefore);
    expect(auditAfter.length, auditBefore.length + 1);
  });

  test('recurring defaults retain source method but reject forged or foreign snapshots', () async {
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Fictional Bank',
        type: PaymentAccountType.bank,
        currencyCode: workspace.identity.currency,
      ),
    );
    final originalMethod = workspace.savePaymentMethod(
      CompanyPaymentMethod(id: EntityId.random(), name: 'Source Cheque'),
    );
    final originalDraft = expense(method: originalMethod);
    final sourceId = await workspace.saveExpenseIntake(originalDraft);
    workspace.savePaymentMethod(
      CompanyPaymentMethod(
        id: originalMethod.id,
        name: 'Retired Cheque',
        active: false,
        revision: originalMethod.revision,
      ),
    );
    final business = workspace.identity.businessId;
    RecurringExpenseTemplate template(String id, RecordExpenseDraft defaults) =>
        RecurringExpenseTemplate(
          id: id,
          revision: 1,
          sourceExpenseId: sourceId.value,
          schedule: RecurrenceRule(
            startsOn: DateTime.utc(2026, 11, 10),
            unit: RecurrenceUnit.months,
          ),
          defaults: defaults,
        );

    final valid = template('retained-source', originalDraft);
    workspace.database.saveRecurringExpenseTemplate(business, valid);
    final forged = CompanyPaymentMethod.fromJson({
      ...originalMethod.toJson(),
      'name': 'Forged Cheque',
    });
    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        business,
        template('forged', expense(method: forged)),
      ),
      throwsStateError,
    );
    final foreign = await AccountingWorkspace.open(':memory:');
    addTearDown(foreign.dispose);
    final foreignMethod = foreign.savePaymentMethod(
      CompanyPaymentMethod(id: EntityId.random(), name: 'Foreign Cheque'),
    );
    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        business,
        template('foreign', expense(method: foreignMethod)),
      ),
      throwsStateError,
    );
    final unrelated = workspace.savePaymentMethod(
      CompanyPaymentMethod(id: EntityId.random(), name: 'Another Cheque'),
    );
    final priorChoice = template(
      'previous-default',
      expense(method: unrelated),
    );
    workspace.database.saveRecurringExpenseTemplate(business, priorChoice);
    final retiredUnrelated = workspace.savePaymentMethod(
      CompanyPaymentMethod(
        id: unrelated.id,
        name: 'Retired Other Cheque',
        active: false,
        revision: unrelated.revision,
      ),
    );
    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        business,
        template('inactive-relink', expense(method: retiredUnrelated)),
      ),
      throwsStateError,
    );
    final edited = valid.withPaused(true);
    workspace.database.saveRecurringExpenseTemplate(business, edited);
    final editedPriorChoice = priorChoice.withPaused(true);
    workspace.database.saveRecurringExpenseTemplate(
      business,
      editedPriorChoice,
    );
    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        business,
        RecurringExpenseTemplate.fromJson({
          ...editedPriorChoice.toJson(),
          'revision': 3,
          'defaults': originalDraft.toJson(),
        }),
      ),
      throwsStateError,
      reason: 'An inactive source method is not a previous template default.',
    );
    expect(
      workspace.database.recurringExpenseTemplates(business),
      hasLength(2),
    );
    expect(
      workspace.database
          .recurringExpenseTemplateHistory(business, valid.id)
          .map((item) => item.revision),
      [1, 2],
    );
    final recovered = LocalAccountingDatabase.inMemory();
    addTearDown(recovered.close);
    recovered.restoreDataArchive(
      workspace.database.exportDataArchive(
        business,
        DateTime.utc(2026, 10, 11),
      ),
    );
    expect(
      recovered
          .recurringExpenseTemplateHistory(business, valid.id)
          .map((item) => item.toJson()),
      [valid.toJson(), edited.toJson()],
    );
    expect(
      recovered
          .recurringExpenseTemplateHistory(business, priorChoice.id)
          .map((item) => item.toJson()),
      [priorChoice.toJson(), editedPriorChoice.toJson()],
    );
  });
}
