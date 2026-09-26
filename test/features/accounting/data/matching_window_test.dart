import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/bank_statement_match.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> postMovement(
  AccountingWorkspace workspace,
  EntityId bank,
  DateTime date,
  Money signed,
  String memo,
) async {
  final contra = (await workspace.accounts())
      .firstWhere((item) => item.account.code == '5000')
      .account
      .id;
  await workspace.saveJournal(
    date: date,
    memo: memo,
    lines: [
      if (signed.minorUnits < 0)
        JournalLine.credit(
          accountId: bank,
          amount: Money.fromMinor(-signed.minorUnits, signed.currency),
        )
      else
        JournalLine.debit(accountId: bank, amount: signed),
      if (signed.minorUnits < 0)
        JournalLine.debit(
          accountId: contra,
          amount: Money.fromMinor(-signed.minorUnits, signed.currency),
        )
      else
        JournalLine.credit(accountId: contra, amount: signed),
    ],
  );
  final journal = (await workspace.journals()).singleWhere(
    (item) => item.entry.memo == memo,
  );
  await workspace.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: workspace.identity.businessId,
      journalId: journal.entry.id,
      expectedRevision: journal.metadata.revision,
      actorId: workspace.identity.ownerId,
      approvedAt: DateTime.now(),
    ),
  );
  return '${journal.entry.id.value}:0';
}

void main() {
  test(
    'real CSV import switches symmetric 7/30 windows and whole-file dates',
    () async {
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final business = workspace.identity.businessId;
      final bank = workspace.database.paymentLedgerAccount(
        business,
        'demo-bank',
      )!;
      final anchor = DateTime.utc(2026, 9, 15);
      final ids = <int, String>{};
      for (final offset in [-31, -30, -8, -7, 0, 7, 8, 30, 31]) {
        ids[offset] = await postMovement(
          workspace,
          bank,
          anchor.add(Duration(days: offset)),
          Money.fromMinor(-12345, 'MYR'),
          'Boundary $offset',
        );
      }
      final foreign = await postMovement(
        workspace,
        workspace.database.paymentLedgerAccount(business, 'demo-savings')!,
        anchor,
        Money.fromMinor(-12345, 'MYR'),
        'Other bank boundary',
      );
      final bytes = Uint8List.fromList(
        utf8.encode(
          'Date,Description,Amount\n2026-06-01,Period start,1.23\n2026-09-15,Boundary transaction,-123.45\n2026-12-31,Period end,1.23',
        ),
      );
      final source = BankStatementImport.csv(
        filename: 'Window.csv',
        currency: 'MYR',
        bytes: bytes,
      );
      final id = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: business,
        paymentAccountId: 'demo-bank',
        importedAt: DateTime.now(),
        statement: source,
      );
      Set<String> candidates(StatementMatchWindow window) => workspace.database
          .statementMatchSuggestions(business, id, window: window)
          .singleWhere((item) => item.row.sourceRow == 3)
          .candidates
          .map((item) => item.movementId)
          .toSet();
      expect(candidates(StatementMatchWindow.seven), {ids[-7], ids[0], ids[7]});
      expect(candidates(StatementMatchWindow.thirty), {
        for (final offset in [-30, -8, -7, 0, 7, 8, 30]) ids[offset],
      });
      expect(candidates(StatementMatchWindow.statement), ids.values.toSet());
      expect(
        candidates(StatementMatchWindow.statement),
        isNot(contains(foreign)),
      );
      expect(
        workspace.database.bankStatement(business, id)!.sourceBytes,
        bytes,
      );
      // A future +30 candidate shown by the control must remain accept-able.
      final movement = ids[30]!.split(':');
      workspace.database.acceptStatementMatch(
        businessId: business,
        statementId: id,
        sourceRow: 3,
        journalId: EntityId.parse(movement.first),
        lineIndex: 0,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
      );
      expect(
        workspace.database.acceptedStatementMatches(business, id)[3],
        ids[30],
      );
    },
  );

  test(
    'source-backed PDF Search All is its month, with inclusive endpoints',
    () async {
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final business = workspace.identity.businessId;
      final imported = workspace.database
          .bankStatements(business, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.pdf');
      final source = workspace.database.bankStatement(business, imported.id)!;
      expect(utf8.decode(source.sourceBytes.take(5).toList()), '%PDF-');
      final period = source.period;
      final row = source.rows.first;
      final bank = workspace.database.paymentLedgerAccount(
        business,
        'demo-bank',
      )!;
      final endpoints = <String>[];
      for (final date in [period.start, period.end]) {
        endpoints.add(
          await postMovement(
            workspace,
            bank,
            date,
            row.amount,
            'PDF endpoint $date',
          ),
        );
      }
      final outside = <String>[];
      for (final date in [
        period.start.subtract(const Duration(days: 1)),
        period.end.add(const Duration(days: 1)),
      ]) {
        outside.add(
          await postMovement(
            workspace,
            bank,
            date,
            row.amount,
            'PDF outside $date',
          ),
        );
      }
      final candidates = workspace.database
          .statementMatchSuggestions(
            business,
            imported.id,
            window: StatementMatchWindow.statement,
          )
          .first
          .candidates
          .map((item) => item.movementId)
          .toSet();
      expect(candidates, containsAll(endpoints));
      for (final id in outside) {
        expect(candidates, isNot(contains(id)));
      }
    },
  );
}
