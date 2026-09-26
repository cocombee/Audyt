import '../../../support/accounting_test_finders.dart';

import 'package:flutter/material.dart';
import 'package:audyt/app/app.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'bank_statement_import_test.dart' show parse;

void main() {
  testWidgets(
    'candidate arrows preserve identities and accept the final suggestion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('accepted-bank-match-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
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
      final chart = await workspace.accounts();
      final bank = chart
          .singleWhere((r) => r.account.type == AccountType.asset)
          .account
          .id;
      final expense = chart
          .singleWhere((r) => r.account.type == AccountType.expense)
          .account
          .id;
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'bank',
          name: 'Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      final business = workspace.identity.businessId;
      workspace.database.linkPaymentLedgerAccount(business, 'bank', bank);
      await workspace.saveJournal(
        date: DateTime.utc(2026, 9, 1),
        memo: 'Supplies',
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
      final statementId = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: business,
        paymentAccountId: 'bank',
        importedAt: DateTime.now(),
        statement: parse(
          'Date,Description,Amount\n2026-09-01,Shop,-10.00\n2026-09-01,Shop,-10.00',
        ),
      );

      for (var i = 0; i < 11; i++) {
        await workspace.saveJournal(
          date: DateTime.utc(2026, 9, 1),
          memo: 'Repeated amount $i',
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
        final draft = (await workspace.journals()).singleWhere(
          (r) => r.entry.state == JournalEntryState.draft,
        );
        await workspace.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: business,
            journalId: draft.entry.id,
            expectedRevision: draft.metadata.revision,
            actorId: workspace.identity.ownerId,
            approvedAt: DateTime.now(),
          ),
        );
      }
      final candidates = workspace.database
          .statementMatchSuggestions(business, statementId)
          .first
          .candidates;
      expect(candidates, hasLength(12));
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/banking'),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: statementId.value);
      expect(
        find.byKey(ValueKey('accept-match-2-${candidates.first.movementId}')),
        findsOneWidget,
      );
      final next = find.byKey(const ValueKey('next-candidates-2'));
      await tester.ensureVisible(next);
      for (var index = 1; index < candidates.length; index++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            ValueKey('accept-match-2-${candidates[index].movementId}'),
          ),
          findsOneWidget,
        );
      }
      final finalMatch = find.byKey(
        ValueKey('accept-match-2-${candidates.last.movementId}'),
      );
      expect(finalMatch, findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      await tester.ensureVisible(finalMatch);
      await tester.tap(finalMatch);
      await tester.pumpAndSettle();
      expect(
        workspace.database.acceptedStatementMatches(business, statementId)[2],
        candidates.last.movementId,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    },
  );
}
