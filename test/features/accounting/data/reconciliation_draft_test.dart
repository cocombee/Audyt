import '../../../support/historical_sqlite_fixture.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bank_statement_import_test.dart' show parse;

Future<EntityId> statement(AccountingWorkspace w) async {
  w.savePaymentAccount(
    PaymentAccount.create(
      id: 'bank',
      name: 'Fictional Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    ),
  );
  return w.database.importBankStatement(
    id: EntityId.random(),
    businessId: w.identity.businessId,
    paymentAccountId: 'bank',
    importedAt: DateTime.utc(2026, 9, 30),
    statement: parse(
      'Date,Description,Amount\n2026-09-02,Fictional payment,-10.00',
    ),
  );
}

void main() {
  test('unfinished inputs survive restart; stale writers, company and actor changes are blocked', () async {
    final dir = Directory.systemTemp.createTempSync('reconciliation-draft-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var w = await AccountingWorkspace.open(path);
    final id = await statement(w);
    final business = w.identity.businessId;
    final actor = w.identity.ownerId;
    void save({
      int revision = 0,
      EntityId? scope,
      EntityId? by,
      String currency = 'MYR',
    }) {
      w.database.saveReconciliationDraft(
        businessId: scope ?? business,
        statementId: id,
        actorId: by ?? actor,
        expectedRevision: revision,
        startsOn: DateTime.utc(2026, 9, 1),
        endsOn: DateTime.utc(2026, 9, 30),
        openingBalance: Money.fromMinor(10000, currency),
        closingBalance: Money.fromMinor(9123, currency),
        openingEvidence: 'Fictional opening source\nOutstanding payment',
        openingOutstandingIds: {'recorded-opening:0'},
        savedAt: DateTime.utc(2026, 10, 3),
      );
    }

    save();
    expect(await w.journals(), isEmpty);
    expect(w.database.isStatementReconciled(business, id), isFalse);
    expect(w.database.acceptedStatementMatches(business, id), isEmpty);
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final draft = w.database.readReconciliationDraft(business, id)!;
    expect(draft.revision, 1);
    expect(draft.closingBalance.minorUnits, 9123);
    expect(
      draft.openingEvidence,
      'Fictional opening source\nOutstanding payment',
    );
    expect(draft.openingOutstandingIds, {'recorded-opening:0'});
    expect(() => draft.openingOutstandingIds.clear(), throwsUnsupportedError);
    expect(() => save(), throwsStateError);
    expect(() => save(revision: 1, scope: EntityId.random()), throwsStateError);
    expect(() => save(revision: 1, by: EntityId.random()), throwsStateError);
    expect(() => save(revision: 1, currency: 'USD'), throwsArgumentError);
    expect(w.database.readReconciliationDraft(EntityId.random(), id), isNull);
    save(revision: 1);
    expect(w.database.readReconciliationDraft(business, id)!.revision, 2);
    expect(w.database.isStatementReconciled(business, id), isFalse);
  });

  test('schema 55 upgrade preserves statement evidence and adds an empty draft owner', () async {
    final dir = Directory.systemTemp.createTempSync('reconciliation-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var w = await AccountingWorkspace.open(path);
    final id = await statement(w);
    final business = w.identity.businessId;
    final bytes = w.database.bankStatement(business, id)!.sourceBytes;
    w.dispose();
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    old.execute('DROP TABLE bank_reconciliation_drafts');
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version=55');
    old.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(w.database.bankStatement(business, id)!.sourceBytes, bytes);
    expect(w.database.readReconciliationDraft(business, id), isNull);
  });

  test('data archive retains draft inputs without trusting approval or missing original bytes', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final id = await statement(w);
    final business = w.identity.businessId;
    w.database.saveReconciliationDraft(
      businessId: business,
      statementId: id,
      actorId: w.identity.ownerId,
      expectedRevision: 0,
      startsOn: DateTime.utc(2026, 9, 1),
      endsOn: DateTime.utc(2026, 9, 30),
      openingBalance: Money.fromMinor(10000, 'MYR'),
      closingBalance: Money.fromMinor(9000, 'MYR'),
      openingEvidence: 'Fictional source verified',
      savedAt: DateTime.utc(2026, 10, 3),
    );
    final archive = w.database.exportDataArchive(
      business,
      DateTime.utc(2026, 10, 3),
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive);
    expect(
      restored.readReconciliationDraft(business, id)!.openingEvidence,
      'Fictional source verified',
    );
    expect(restored.isStatementReconciled(business, id), isFalse);
    expect(
      () => restored.saveReconciliationDraft(
        businessId: business,
        statementId: id,
        actorId: w.identity.ownerId,
        expectedRevision: 1,
        startsOn: DateTime.utc(2026, 9, 1),
        endsOn: DateTime.utc(2026, 9, 30),
        openingBalance: Money.fromMinor(10000, 'MYR'),
        closingBalance: Money.fromMinor(9000, 'MYR'),
        savedAt: DateTime.utc(2026, 10, 3),
      ),
      throwsStateError,
    );
  });
}
