import 'dart:convert';

import '../../../support/historical_sqlite_fixture.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'account_reconciliation_persistence_test.dart' show approve, save;
import 'archive_upgrade_test.dart' show body, envelope, historical;
import 'bank_statement_import_test.dart' show parse;
import 'journal_editability_test.dart'
    show importPayment, completeImported, reopen;

List<Map<String, dynamic>> rows(Map<String, dynamic> archive, String name) {
  final table = archive['tables'][name] as Map;
  final columns = (table['columns'] as List).cast<String>();
  return [
    for (final row in table['rows'] as List)
      {
        for (var index = 0; index < columns.length; index++)
          columns[index]: row[index],
      },
  ];
}

void alter(
  Map<String, dynamic> archive,
  String name,
  void Function(Map<String, dynamic>) change,
) {
  final table = archive['tables'][name] as Map;
  final columns = (table['columns'] as List).cast<String>();
  for (final row in table['rows'] as List) {
    final value = {for (var i = 0; i < columns.length; i++) columns[i]: row[i]};
    change(value);
    for (var i = 0; i < columns.length; i++) {
      row[i] = value[columns[i]];
    }
  }
}

void alterApproval(
  Map<String, dynamic> archive,
  void Function(Map<String, dynamic>, Map<String, dynamic>) change,
) => alter(archive, 'bank_reconciliations', (row) {
  final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
  change(row, payload);
  row['payload'] = jsonEncode(payload);
});

Future<(Fixture, EntityId, EntityId, EntityId)> approvedImport({
  bool card = false,
}) async {
  final f = Fixture();
  await f.open(liability: card);
  // Card reconciliation presents credits to its liability as positive usage.
  await f.post(8, 31, card ? -10000 : 10000);
  final payment = await f.post(9, 2, card ? 1000 : -1000);
  final statement = importPayment(f);
  f.w.database.acceptStatementMatch(
    businessId: f.business,
    statementId: statement,
    sourceRow: 2,
    journalId: payment,
    lineIndex: 0,
    actorId: f.w.identity.ownerId,
    acceptedAt: DateTime.now(),
  );
  return (f, payment, statement, completeImported(f, statement));
}

Map<String, dynamic> archive(Fixture f) =>
    body(f.w.database.exportDataArchive(f.business, DateTime.utc(2027)));

Future<void> rejectsAtomically(
  Fixture f,
  EntityId payment,
  Map<String, dynamic> forged,
) async {
  final destination = LocalAccountingDatabase.inMemory();
  addTearDown(destination.close);
  expect(
    () => destination.restoreDataArchive(envelope(forged)),
    throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
  );
  expect(await destination.getById(payment), isNull);
  // Rejection cannot leave a half-restored company or destroy its guards.
  destination.restoreDataArchive(envelope(archive(f)));
  expect(await destination.getById(payment), isNotNull);
  expect(destination.journalReconciliationId(f.business, payment), isNotNull);
}

void main() {
  for (final version in [19, 20]) {
    test(
      'schema $version archive without saved bank rows stays a recoverable rejection',
      () async {
        final (f, payment, _, completion) = await approvedImport();
        final data = archive(f);
        data['schemaVersion'] = version;
        dropCurrentAccountArchiveFixtureOwner(data);
        // Independent table set for the populated historical approval boundary.
        final names = {
          'journal_entries',
          'journal_lines',
          'accounts',
          'ledger_policies',
          'journal_approvals',
          'ledger_audit',
          'local_workspace',
          'expense_intakes',
          'payees',
          'payment_accounts',
          'claims',
          'payment_vouchers',
          'recurring_expense_templates',
          'recurring_expense_template_history',
          'recurring_expense_occurrences',
          'recurring_expense_conversions',
          'payment_ledger_links',
          'bank_statement_imports',
          'bank_statement_matches',
          'bank_match_history',
          'bank_match_retractions',
          'bank_reconciliations',
          'bank_reconciliation_allocations',
          'bank_reconciliation_reopenings',
          if (version == 20) 'bank_reconciliation_ledger_snapshots',
        };
        (data['tables'] as Map).removeWhere((name, _) => !names.contains(name));
        for (final entry in {
          'expense_intakes': ['revision', 'archived_at', 'state_changed_at'],
          'payment_accounts': ['holder_name'],
          'bank_statement_imports': ['parsed_rows'],
        }.entries) {
          final table = data['tables'][entry.key] as Map;
          final columns = table['columns'] as List;
          for (final column in entry.value) {
            final index = columns.indexOf(column);
            columns.removeAt(index);
            for (final row in table['rows'] as List) {
              row.removeAt(index);
            }
          }
        }
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        expect(
          () => restored.restoreDataArchive(envelope(data)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'original metadata unavailable',
              contains('lacks saved bank rows'),
            ),
          ),
        );
        expect(await restored.getById(payment), isNull);
        restored.restoreDataArchive(envelope(archive(f)));
        expect(
          restored.journalReconciliationId(f.business, payment),
          completion,
        );
      },
    );
  }
  for (final version in [31, 33]) {
    test(
      'schema $version retained-row approval upgrades without group/combined-table inventions',
      () async {
        final (f, payment, _, completion) = await approvedImport();
        final data = historical(
          f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
          34,
        );
        data['schemaVersion'] = version;
        dropCurrentAccountArchiveFixtureOwner(data);
        final tables = data['tables'] as Map;
        tables.remove('bank_match_ledger_members');
        tables.remove('bank_match_active_ledger_members');
        if (version < 33) {
          tables.remove('bank_match_group_members');
          tables.remove('bank_match_active_members');
          final table = tables['payment_accounts'] as Map;
          final columns = table['columns'] as List;
          final index = columns.indexOf('holder_name');
          columns.removeAt(index);
          for (final row in table['rows'] as List) {
            row.removeAt(index);
          }
        }
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(envelope(data));
        expect(
          restored.journalReconciliationId(f.business, payment),
          completion,
        );
        expect(
          restored
              .reconciliationClassification(f.business, completion.value)!
              .agrees,
          isTrue,
        );
        final recovered = body(
          restored.exportDataArchive(f.business, DateTime.utc(2027)),
        );
        expect(
          rows(recovered, 'bank_reconciliations'),
          rows(data, 'bank_reconciliations'),
        );
        expect(
          rows(recovered, 'bank_match_history'),
          rows(data, 'bank_match_history'),
        );
      },
    );
  }
  for (final imported in [false, true]) {
    test(
      'restore rejects exact one-cent difference in ${imported ? 'imported' : 'account'} approval',
      () async {
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final payment = await f.post(9, 2, -1000);
        if (imported) {
          final statement = importPayment(f);
          f.w.database.acceptStatementMatch(
            businessId: f.business,
            statementId: statement,
            sourceRow: 2,
            journalId: payment,
            lineIndex: 0,
            actorId: f.w.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
          completeImported(f, statement);
        } else {
          final review = f.review(selected: {'${payment.value}:0'});
          final draft = save(f, review);
          approve(f, review, revision: draft.revision);
        }
        final forged = archive(f);
        alterApproval(forged, (row, payload) {
          row['closing_minor'] = 9001;
          payload['closing'] = 9001;
        });
        await rejectsAtomically(f, payment, forged);
      },
    );
  }

  for (final card in [false, true]) {
    test(
      'valid ${card ? 'card' : 'bank'} restore retains exact-zero lock and originals',
      () async {
        final (f, payment, statement, completion) = await approvedImport(
          card: card,
        );
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        final source = archive(f);
        restored.restoreDataArchive(envelope(source));
        expect(
          restored.journalReconciliationId(f.business, payment),
          completion,
        );
        expect(
          restored
              .reconciliationClassification(f.business, completion.value)!
              .agrees,
          isTrue,
        );
        expect(
          restored
              .reconciliationHistory(f.business, statement)
              .single
              .closingBalance
              .minorUnits,
          9000,
        );
        final recovered = body(
          restored.exportDataArchive(f.business, DateTime.utc(2027)),
        );
        for (final table in [
          'bank_reconciliations',
          'bank_match_history',
          'bank_reconciliation_allocations',
          'bank_reconciliation_ledger_snapshots',
        ]) {
          expect(recovered['tables'][table], source['tables'][table]);
        }
      },
    );
  }

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'shifted opening and closing with statement arithmetic still zero':
        (data) => alterApproval(data, (row, payload) {
          row['opening_minor'] = 10001;
          payload['opening'] = 10001;
          row['closing_minor'] = 9001;
          payload['closing'] = 9001;
        }),
    'foreign approval actor': (data) => alterApproval(data, (row, payload) {
      row['actor_id'] = EntityId.random().value;
      payload['actor'] = row['actor_id'];
    }),
    'currency identity changed consistently in approval': (data) =>
        alterApproval(data, (row, payload) {
          row['currency'] = 'USD';
          payload['currency'] = 'USD';
          payload['closingCurrency'] = 'USD';
        }),
    'missing original accepted allocation': (data) =>
        (data['tables']['bank_reconciliation_allocations']['rows'] as List)
            .clear(),
    'foreign retained allocation actor': (data) =>
        alter(data, 'bank_match_history', (row) {
          row['actor_id'] = EntityId.random().value;
        }),
    'snapshot original memo replaced': (data) =>
        alter(data, 'bank_reconciliation_ledger_snapshots', (row) {
          final payload = jsonDecode(row['payload'] as String) as Map;
          payload['movements'][0]['memo'] = 'Forged original';
          row['payload'] = jsonEncode(payload);
        }),
    'forged predecessor': (data) => alterApproval(data, (row, payload) {
      row['previous_id'] = EntityId.random().value;
      payload['previous'] = row['previous_id'];
    }),
  };
  for (final corruption in corruptions.entries) {
    test('restore rejects ${corruption.key}', () async {
      final (f, payment, _, _) = await approvedImport();
      final data = archive(f);
      corruption.value(data);
      await rejectsAtomically(f, payment, data);
    });
  }

  test(
    'restore retains exact-zero live approval with original match timestamps',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 31, 10000);
      final payment = await f.post(9, 2, -1000);
      final statement = importPayment(f);
      // Live approval permits independent recorded match timestamps. Recovery
      // preserves those same original facts instead of inventing a stricter
      // retrospective clock policy or rewriting their history.
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: payment,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.utc(2040),
      );
      final completion = completeImported(f, statement);
      final data = archive(f);
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      restored.restoreDataArchive(envelope(data));
      expect(restored.journalReconciliationId(f.business, payment), completion);
      expect(
        rows(
          body(restored.exportDataArchive(f.business, DateTime.utc(2027))),
          'bank_match_history',
        ),
        rows(data, 'bank_match_history'),
      );
    },
  );

  test('reopened then retracted approval restores history without locking current transaction', () async {
    final (f, payment, statement, completion) = await approvedImport();
    final acceptance = f.w.database.statementMatchAcceptanceId(
      f.business,
      statement,
      2,
    )!;
    reopen(f, completion);
    f.w.database.retractStatementMatch(
      businessId: f.business,
      acceptanceId: acceptance,
      actorId: f.w.identity.ownerId,
      retractedAt: DateTime.now(),
      reason: 'Correct original match',
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    final data = archive(f);
    restored.restoreDataArchive(envelope(data));
    restored.requireJournalUnreconciled(f.business, payment);
    expect(restored.acceptedStatementMatches(f.business, statement), isEmpty);
    expect(
      restored.reconciliationHistory(f.business, statement).single.id,
      completion.value,
    );
    final recovered = body(
      restored.exportDataArchive(f.business, DateTime.utc(2027)),
    );
    for (final table in [
      'bank_reconciliations',
      'bank_match_history',
      'bank_match_retractions',
      'bank_reconciliation_reopenings',
    ]) {
      expect(recovered['tables'][table], data['tables'][table]);
    }
  });

  test(
    'restored consecutive approved periods retain both current locks',
    () async {
      final (f, first, _, parent) = await approvedImport();
      final second = await f.post(10, 2, -500);
      final statement = f.w.database.importBankStatement(
        id: EntityId.random(),
        businessId: f.business,
        paymentAccountId: 'bank',
        importedAt: DateTime.now(),
        statement: parse(
          'Date,Description,Amount\n2026-10-02,Fictional supplies,-5.00',
        ),
      );
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: second,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final completion = EntityId.random();
      f.w.database.approveStatementReconciliation(
        requestId: completion,
        businessId: f.business,
        statementId: statement,
        actorId: f.w.identity.ownerId,
        approvedAt: DateTime.now(),
        startsOn: DateTime.utc(2026, 10, 1),
        endsOn: DateTime.utc(2026, 10, 31),
        openingBalance: Money.fromMinor(9000, 'MYR'),
        closingBalance: Money.fromMinor(8500, 'MYR'),
        expectedAcceptanceIds: {
          2: f.w.database.statementMatchAcceptanceId(f.business, statement, 2)!,
        },
        expectedPreviousId: parent.value,
      );
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      restored.restoreDataArchive(envelope(archive(f)));
      expect(restored.journalReconciliationId(f.business, first), parent);
      expect(restored.journalReconciliationId(f.business, second), completion);
      expect(
        restored
            .reconciliationClassification(f.business, completion.value)!
            .agrees,
        isTrue,
      );
    },
  );

  test(
    'opening outstanding movement stays editable after restored zero approval',
    () async {
      final f = Fixture();
      await f.open();
      await f.post(8, 30, 10000);
      final outstanding = await f.post(8, 31, -500);
      final payment = await f.post(9, 2, -1000);
      final statement = importPayment(f);
      f.w.database.acceptStatementMatch(
        businessId: f.business,
        statementId: statement,
        sourceRow: 2,
        journalId: payment,
        lineIndex: 0,
        actorId: f.w.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      final completion = EntityId.random();
      f.w.database.approveStatementReconciliation(
        requestId: completion,
        businessId: f.business,
        statementId: statement,
        actorId: f.w.identity.ownerId,
        approvedAt: DateTime.now(),
        startsOn: DateTime.utc(2026, 9, 1),
        endsOn: DateTime.utc(2026, 9, 30),
        openingBalance: Money.fromMinor(10000, 'MYR'),
        closingBalance: Money.fromMinor(9000, 'MYR'),
        expectedAcceptanceIds: {
          2: f.w.database.statementMatchAcceptanceId(f.business, statement, 2)!,
        },
        expectedPreviousId: null,
        firstOpeningEvidence: 'Fictional verified opening',
        openingOutstandingIds: {'${outstanding.value}:0'},
      );
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      restored.restoreDataArchive(envelope(archive(f)));
      expect(restored.journalReconciliationId(f.business, payment), completion);
      restored.requireJournalUnreconciled(f.business, outstanding);
      expect(
        restored
            .reconciliationClassification(f.business, completion.value)!
            .outstanding
            .single
            .id,
        '${outstanding.value}:0',
      );
    },
  );

  for (final grouped in [false, true]) {
    test(
      'restores ${grouped ? 'grouped source rows' : 'combined ledger members'} without losing locks',
      () async {
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final first = await f.post(9, 2, grouped ? -1000 : -600);
        final second = grouped ? null : await f.post(9, 2, -400);
        final statement = f.w.database.importBankStatement(
          id: EntityId.random(),
          businessId: f.business,
          paymentAccountId: 'bank',
          importedAt: DateTime.now(),
          statement: parse(
            grouped
                ? 'Date,Description,Amount\n2026-09-02,First,-6.00\n2026-09-02,Second,-4.00'
                : 'Date,Description,Amount\n2026-09-02,Combined,-10.00',
          ),
        );
        if (grouped) {
          f.w.database.acceptStatementMatchGroup(
            businessId: f.business,
            statementId: statement,
            sourceRows: {2, 3},
            journalId: first,
            lineIndex: 0,
            actorId: f.w.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
        } else {
          f.w.database.acceptStatementCombinedMatch(
            businessId: f.business,
            statementId: statement,
            sourceRow: 2,
            movementIds: {'${first.value}:0', '${second!.value}:0'},
            actorId: f.w.identity.ownerId,
            acceptedAt: DateTime.now(),
          );
        }
        final completion = EntityId.random();
        f.w.database.approveStatementReconciliation(
          requestId: completion,
          businessId: f.business,
          statementId: statement,
          actorId: f.w.identity.ownerId,
          approvedAt: DateTime.now(),
          startsOn: DateTime.utc(2026, 9, 1),
          endsOn: DateTime.utc(2026, 9, 30),
          openingBalance: Money.fromMinor(10000, 'MYR'),
          closingBalance: Money.fromMinor(9000, 'MYR'),
          expectedAcceptanceIds: {
            for (final row in grouped ? [2, 3] : [2])
              row: f.w.database.statementMatchAcceptanceId(
                f.business,
                statement,
                row,
              )!,
          },
          expectedPreviousId: null,
          firstOpeningEvidence: 'Fictional verified opening',
        );
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(envelope(archive(f)));
        expect(restored.journalReconciliationId(f.business, first), completion);
        if (second != null) {
          expect(
            restored.journalReconciliationId(f.business, second),
            completion,
          );
        }
        expect(
          restored
              .reconciliationClassification(f.business, completion.value)!
              .agrees,
          isTrue,
        );
      },
    );
  }
}
