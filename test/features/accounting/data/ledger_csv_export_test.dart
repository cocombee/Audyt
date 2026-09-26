import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ledger CSV scopes its company and neutralizes spreadsheet starts',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-ledger-csv-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${root.path}/book.sqlite',
      );
      addTearDown(workspace.dispose);
      final business = workspace.identity.businessId;
      await workspace.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '3000',
        name: 'Capital',
        type: AccountType.equity,
      );
      final chart = await workspace.accounts();
      final debit = chart.singleWhere(
        (record) => record.account.code == '1000',
      );
      final credit = chart.singleWhere(
        (record) => record.account.code == '3000',
      );
      final cases = <(String, String)>[
        ('=1+1', '"\'=1+1"'),
        ('\t=1+1', '"\'\t=1+1"'),
        ('\r=1+1', '"\'\r=1+1"'),
        ('\n=1+1', '"\'\n=1+1"'),
        ('  =1+1', '"\'  =1+1"'),
        ('＝1+1', '"\'＝1+1"'),
        // SQLite's string decoder removes a leading BOM before export.
        ('\uFEFF@SUM(1)', '"\'@SUM(1)"'),
        ('=1+1";,=2+2', '"\'=1+1"";,=2+2"'),
        ('Office supplies', '"Office supplies"'),
      ];
      for (final (memo, _) in cases) {
        await workspace.saveJournal(
          date: DateTime.utc(2026, 9, 29),
          memo: memo,
          lines: [
            JournalLine.debit(
              accountId: debit.account.id,
              amount: Money.fromMinor(100, 'MYR'),
            ),
            JournalLine.credit(
              accountId: credit.account.id,
              amount: Money.fromMinor(100, 'MYR'),
            ),
          ],
        );
        final storedMemo = memo.startsWith('\uFEFF') ? memo.substring(1) : memo;
        final matches = (await workspace.journals())
            .where(
              (record) =>
                  record.entry.memo == storedMemo &&
                  record.entry.state == JournalEntryState.draft,
            )
            .toList();
        expect(
          matches,
          hasLength(1),
          reason: 'memo code units: ${memo.codeUnits}',
        );
        final draft = matches.single;
        await workspace.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: business,
            journalId: draft.entry.id,
            expectedRevision: draft.metadata.revision,
            actorId: workspace.identity.ownerId,
            approvedAt: draft.metadata.updatedAt.add(
              const Duration(microseconds: 1),
            ),
          ),
        );
      }
      expect(
        () => workspace.database.exportLedgerCsv(EntityId.random()),
        throwsStateError,
      );
      final csv = workspace.database.exportLedgerCsv(business);
      expect(
        csv,
        startsWith(
          'date,journal_id,memo,account_code,account_name,side,amount_minor,currency',
        ),
      );
      for (final (_, expectedCell) in cases) {
        expect(csv, contains(expectedCell));
      }
    },
  );
}
