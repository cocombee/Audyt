import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'bank_statement_import_test.dart' show parse;

void main() {
  for (final future in [true, false]) {
    test(
      'approval rolls back ${future ? 'future ledger match' : 'already cleared opening match'}',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'reconciliation-rollback-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/ledger.sqlite';
        final workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        await workspace.createAccount(
          code: '1000',
          name: 'Bank',
          type: AccountType.asset,
        );
        await workspace.createAccount(
          code: '5000',
          name: 'Expense',
          type: AccountType.expense,
        );
        final accounts = await workspace.accounts();
        final bank = accounts
            .singleWhere((r) => r.account.type == AccountType.asset)
            .account
            .id;
        final expense = accounts
            .singleWhere((r) => r.account.type == AccountType.expense)
            .account
            .id;
        final business = workspace.identity.businessId;
        workspace.savePaymentAccount(
          PaymentAccount.create(
            id: 'bank',
            name: 'Bank',
            type: PaymentAccountType.bank,
            currencyCode: 'MYR',
          ),
        );
        workspace.database.linkPaymentLedgerAccount(business, 'bank', bank);
        await workspace.saveJournal(
          date: future ? DateTime.utc(2026, 10, 1) : DateTime.utc(2026, 8, 31),
          memo: 'Recorded expense',
          lines: [
            JournalLine.debit(
              accountId: expense,
              amount: Money.fromMinor(1000, 'MYR'),
            ),
            JournalLine.credit(
              accountId: bank,
              amount: Money.fromMinor(1000, 'MYR'),
            ),
          ],
        );
        final journal = (await workspace.journals()).single;
        await workspace.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: business,
            journalId: journal.entry.id,
            expectedRevision: journal.metadata.revision,
            actorId: workspace.identity.ownerId,
            approvedAt: DateTime.now(),
          ),
        );
        final statement = workspace.database.importBankStatement(
          id: EntityId.random(),
          businessId: business,
          paymentAccountId: 'bank',
          importedAt: DateTime.now(),
          statement: parse(
            'Date,Description,Amount\n2026-09-${future ? '30' : '01'},Payment,-10.00',
          ),
        );
        workspace.database.acceptStatementMatch(
          businessId: business,
          statementId: statement,
          sourceRow: 2,
          journalId: journal.entry.id,
          lineIndex: 1,
          actorId: workspace.identity.ownerId,
          acceptedAt: DateTime.now(),
        );
        final request = EntityId.random();
        expect(
          () => workspace.database.approveStatementReconciliation(
            requestId: request,
            businessId: business,
            statementId: statement,
            actorId: workspace.identity.ownerId,
            approvedAt: DateTime.now(),
            startsOn: DateTime.utc(2026, 9, 1),
            endsOn: DateTime.utc(2026, 9, 30),
            openingBalance: Money.fromMinor(future ? 0 : -1000, 'MYR'),
            closingBalance: Money.fromMinor(future ? -1000 : -2000, 'MYR'),
            expectedAcceptanceIds: {
              2: workspace.database.statementMatchAcceptanceId(
                business,
                statement,
                2,
              )!,
            },
            expectedPreviousId: null,
            firstOpeningEvidence: 'Test evidence',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'reason',
              contains('Cleared ledger movements'),
            ),
          ),
        );
        final raw = sqlite3.open(path);
        for (final table in [
          'bank_reconciliations',
          'bank_reconciliation_allocations',
          'bank_reconciliation_ledger_snapshots',
        ]) {
          expect(raw.select('SELECT * FROM $table'), isEmpty, reason: table);
        }
        raw.dispose();
        expect(
          workspace.database.acceptedStatementMatches(business, statement),
          hasLength(1),
        );
        expect(await workspace.journals(), hasLength(1));
      },
    );
  }
}
