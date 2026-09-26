import 'dart:convert';

import '../../../support/historical_sqlite_fixture.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_upgrade_test.dart' show body, envelope;
import 'claim_receipt_tax_test.dart' show fixture, Fixture, report;

RecordExpenseDraft expenseBody(Fixture f) {
  final original = f.claim();
  return RecordExpenseDraft(
    amount: '186.32',
    date: '14-09-2026',
    payee: 'Sample Supplier',
    paymentAccount: '',
    category: 'Multiple Categories',
    tax: 'Multiple Taxes',
    customer: 'Sample Customer',
    billable: true,
    dimensions: 'Department: Operations',
    itemOrSplitDetails: 'Project: September',
    notes: 'Approved business purpose\nSecond memo line',
    documentNumber: 'SUPPLIER-2026-09',
    recurrence: RecurrenceRule(
      startsOn: DateTime.utc(2026, 9, 14),
      unit: RecurrenceUnit.months,
      occurrenceCount: 3,
    ),
    attachments: original.attachments,
    submissionId: 'claim-form-snapshot',
    taxMode: 'Exclusive',
    lines: [
      for (final r in original.receipts)
        for (final line in r.lines) line.item,
    ],
  );
}

Map<String, EntityId> accounts(Fixture f, RecordExpenseDraft d) => {
  d.lines[0].id: f.accounts['5000']!,
  d.lines[1].id: f.accounts['1500']!,
  d.lines[2].id: f.accounts['5100']!,
};

void main() {
  test('complete Expense body survives Claim submission, approval, restart and data-only recovery', () async {
    final dir = Directory.systemTemp.createTempSync('claim-expense-snapshot-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(path: path);
    final draft = expenseBody(f);
    final claim = Claim.expense(
      id: EntityId.random(),
      draft: draft,
      claimantName: 'Registered Employee',
    );
    expect(claim.toJson()['version'], 4);
    expect(claim.expenseDraft!.toJson(), draft.toJson());
    f.w.claims.saveAndSubmit(claim);
    final submitted = f.w.claims.byId(claim.id)!;
    expect(submitted.receipts, isEmpty);
    expect(submitted.expenseDraft!.toJson(), draft.toJson());
    final request = EntityId.random();
    EntityId approve() => f.w.approveClaim(
      reviewedClaim: submitted,
      requestId: request,
      expenseLineAccounts: accounts(f, draft),
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    expect(approve(), request);
    expect(approve(), request);
    expect(await f.w.journals(), hasLength(1));
    expect(await f.w.expenses(), hasLength(1));
    final approved = f.w.claims.byId(claim.id)!;
    expect(approved.expenseDraft!.toJson(), draft.toJson());
    expect(approved.receiptCostAllocations[f.accounts['5000']], isNotNull);
    final linked = (await f.w.expense(request))!.draft;
    for (final key in [
      'documentNumber',
      'customer',
      'billable',
      'dimensions',
      'itemOrSplitDetails',
      'notes',
      'recurrence',
      'lines',
      'attachments',
      'reviewSnapshots',
    ]) {
      expect(linked.toJson()[key], draft.toJson()[key], reason: key);
    }
    expect(linked.paymentAccountId, isNull);
    expect(linked.taxTotals!.net.minorUnits, 17400);
    expect(linked.taxTotals!.tax.minorUnits, 1232);
    expect(linked.taxTotals!.total.minorUnits, 18632);
    expect((await report(f.w)).rows, hasLength(3));
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 9, 16),
    );
    f.w.dispose();
    final reopened = await AccountingWorkspace.open(path);
    addTearDown(reopened.dispose);
    expect(
      reopened.claims.byId(claim.id)!.expenseDraft!.toJson(),
      draft.toJson(),
    );
    expect((await reopened.expense(request))!.draft.toJson(), linked.toJson());
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive);
    final recovered = (await restored.getExpenseIntake(
      reopened.identity.businessId,
      request,
    ))!.draft;
    expect(recovered.documentNumber, draft.documentNumber);
    expect(recovered.recurrence!.toJson(), draft.recurrence!.toJson());
    expect(recovered.claimSource!.claimantName, 'Registered Employee');
    expect(recovered.attachments.single.originalBytes, isEmpty);
    expect(
      recovered.attachments.single.originalSha256,
      draft.attachments.single.originalSha256,
    );
    expect(recovered.taxTotals!.total.minorUnits, 18632);
  });

  test('approval requires exact line mapping and cannot infer, replace or use foreign accounts', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final draft = expenseBody(f);
    final claim = Claim.expense(
      id: EntityId.random(),
      draft: draft,
      claimantName: 'Registered Employee',
    );
    f.w.claims.saveAndSubmit(claim);
    final submitted = f.w.claims.byId(claim.id)!;
    for (final mapping in <Map<String, EntityId>?>[
      null,
      {draft.lines.first.id: f.accounts['5000']!},
      {...accounts(f, draft), 'extra-line': f.accounts['5000']!},
      {...accounts(f, draft), draft.lines.first.id: EntityId.random()},
      {...accounts(f, draft), draft.lines.first.id: f.accounts['2100']!},
    ]) {
      expect(
        () => f.w.approveClaim(
          reviewedClaim: submitted,
          requestId: EntityId.random(),
          expenseLineAccounts: mapping,
          liabilityAccountId: f.accounts['2100']!,
          approvedAt: DateTime.utc(2026, 9, 15),
        ),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
      expect(await f.w.journals(), isEmpty);
      expect(await f.w.expenses(), isEmpty);
      expect(f.w.claims.byId(claim.id)!.status, ClaimStatus.submitted);
    }
  });

  test(
    'older archive cannot carry a new Expense-backed Claim payload',
    () async {
      final f = await fixture();
      addTearDown(f.w.dispose);
      f.w.claims.saveAndSubmit(
        Claim.expense(
          id: EntityId.random(),
          draft: expenseBody(f),
          claimantName: 'Registered Employee',
        ),
      );
      final archive = body(
        f.w.database.exportDataArchive(
          f.w.identity.businessId,
          DateTime.utc(2026, 9, 16),
        ),
      );
      (archive['tables'] as Map).remove('expense_revision_postings');
      (archive['tables'] as Map).remove('expense_revision_drafts');
      archive['schemaVersion'] = 57;
      dropCurrentAccountArchiveFixtureOwner(archive);
      (archive['tables'] as Map).remove('converted_quotation_revisions');
      (archive['tables'] as Map).remove('account_reconciliation_drafts');
      (archive['tables'] as Map).remove(
        'bank_reconciliation_cleared_movements',
      );
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      expect(
        () => restored.restoreDataArchive(envelope(archive)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Expense-backed Claims require archive version 58.',
          ),
        ),
      );
      expect(
        await restored.listExpenseIntakes(f.w.identity.businessId),
        isEmpty,
      );
    },
  );

  test('identified Claim cannot change claimant through repository or durable adapter', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    f.w.payees.save(
      const Payee(id: 'employee-a', name: 'Person A', type: PayeeType.staff),
    );
    f.w.payees.save(
      const Payee(id: 'employee-b', name: 'Person B', type: PayeeType.staff),
    );
    final first = Claim.expense(
      id: EntityId.random(),
      draft: expenseBody(f),
      claimantName: 'Person A',
      claimantIdentity: ClaimantIdentity(
        payeeId: 'employee-a',
        type: ClaimantType.staff,
      ),
    );
    f.w.claims.saveDraft(first);
    final replacement = Claim.expense(
      id: first.id,
      draft: first.expenseDraft!,
      claimantName: 'Person B',
      claimantIdentity: ClaimantIdentity(
        payeeId: 'employee-b',
        type: ClaimantType.staff,
      ),
    );
    expect(() => f.w.claims.saveDraft(replacement), throwsStateError);
    // Exercise the SQLite adapter independently of the repository guard.
    expect(() => f.w.claims.persistChanges!([replacement]), throwsStateError);
    expect(f.w.claims.byId(first.id)!.toJson(), first.toJson());
    final disposable = ClaimStore(claims: [first]);
    expect(() => disposable.saveAndSubmit(replacement), throwsStateError);
    disposable.dispose();
  });

  test('forged duplicate Expense facts and recovered snapshot changes are rejected', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final claim = Claim.expense(
      id: EntityId.random(),
      draft: expenseBody(f),
      claimantName: 'Registered Employee',
    );
    for (final field in [
      'amountMinor',
      'vendorName',
      'businessPurpose',
      'category',
      'incurredOn',
    ]) {
      final json = Map<String, dynamic>.from(claim.toJson());
      json[field] = field == 'amountMinor'
          ? 99999
          : field == 'incurredOn'
          ? '2026-09-15T00:00:00.000Z'
          : 'Altered';
      expect(() => Claim.fromJson(json), throwsFormatException, reason: field);
    }
    f.w.claims.saveAndSubmit(claim);
    final request = f.w.approveClaim(
      reviewedClaim: f.w.claims.byId(claim.id)!,
      requestId: EntityId.random(),
      expenseLineAccounts: accounts(f, claim.expenseDraft!),
      liabilityAccountId: f.accounts['2100']!,
      approvedAt: DateTime.utc(2026, 9, 15),
    );
    final archive = body(
      f.w.database.exportDataArchive(
        f.w.identity.businessId,
        DateTime.utc(2026, 9, 16),
      ),
    );
    final table = (archive['tables'] as Map)['expense_intakes'] as Map;
    final payloadIndex = (table['columns'] as List).indexOf('payload');
    final row = (table['rows'] as List).single as List;
    final payload = jsonDecode(row[payloadIndex] as String) as Map;
    payload['documentNumber'] = 'Changed During Recovery';
    row[payloadIndex] = jsonEncode(payload);
    final rejected = LocalAccountingDatabase.inMemory();
    addTearDown(rejected.close);
    expect(
      () => rejected.restoreDataArchive(envelope(archive)),
      throwsFormatException,
    );
    expect(
      (await f.w.expense(request))!.draft.documentNumber,
      claim.expenseDraft!.documentNumber,
    );
  });
}
