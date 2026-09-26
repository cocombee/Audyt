import 'package:audyt/app/accounting_components.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

void main() {
  for (final width in [390.0, 900.0, 1224.0]) {
    testWidgets('closing controls align and reject missing inputs at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('closing-layout-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        AudytApp(initialPath: '/accountant-review', workspace: workspace),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prepare-closing')));
      await tester.pumpAndSettle();
      final date = tester.getRect(
        find.byKey(const ValueKey('closing-date-frame')),
      );
      final selector = tester.getRect(
        find.byKey(const ValueKey('closing-equity')),
      );
      expect(date.left, selector.left);
      expect(selector.width, lessThanOrEqualTo(date.width));
      expect(date.height, selector.height);
      expect(date.left, greaterThanOrEqualTo(0));
      expect(date.right, lessThanOrEqualTo(width));
      await tester.tap(find.byKey(const ValueKey('save-closing-draft')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid date and choose an equity account.'),
        findsOneWidget,
      );
      expect(await workspace.journals(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'prepare closing saves a durable draft then approves exact lines',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('closing-create-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      for (final item in [
        (AccountType.asset, '1000', 'Bank'),
        (AccountType.equity, '3000', 'Retained Earnings'),
        (AccountType.income, '4000', 'Sales'),
      ]) {
        await workspace.createAccount(
          code: item.$2,
          name: item.$3,
          type: item.$1,
        );
      }
      final chart = await workspace.accounts();
      EntityId account(AccountType type) =>
          chart.singleWhere((a) => a.account.type == type).account.id;
      await workspace.saveJournal(
        date: DateTime.utc(2026, 9, 1),
        memo: 'Sale',
        lines: [
          JournalLine.debit(
            accountId: account(AccountType.asset),
            amount: Money.fromMinor(10000, 'MYR'),
          ),
          JournalLine.credit(
            accountId: account(AccountType.income),
            amount: Money.fromMinor(10000, 'MYR'),
          ),
        ],
      );
      final sale = (await workspace.journals()).single;
      await workspace.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: workspace.identity.businessId,
          journalId: sale.entry.id,
          expectedRevision: sale.metadata.revision,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pumpWidget(
        AudytApp(initialPath: '/accounting', workspace: workspace),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('navigation-item-accounting')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Journal Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prepare-closing')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('closing-date')),
        '30-09-2026',
      );
      await tester.tap(find.byKey(const ValueKey('closing-equity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3000 · Retained Earnings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-closing-draft')));
      await tester.pumpAndSettle();
      final draft = (await workspace.journals()).singleWhere(
        (r) => r.entry.isClosing,
      );
      expect(draft.entry.state, JournalEntryState.draft);
      expect(draft.entry.lines.length, 2);
      expect(draft.entry.closingEquityAccountId, account(AccountType.equity));
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        (await workspace.database.getById(draft.entry.id))!.entry.state,
        JournalEntryState.draft,
      );
      await tester.pumpWidget(
        AudytApp(initialPath: '/accounting', workspace: workspace),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('navigation-item-accounting')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Journal Review'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('review-journal-${draft.entry.id.value}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approve-journal')));
      await tester.pumpAndSettle();
      expect(
        (await workspace.database.getById(draft.entry.id))!.entry.state,
        JournalEntryState.posted,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'review identifies closing destination and rejects unsupported close',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('closing-review-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await workspace.createAccount(
        code: '3000',
        name: 'Retained Earnings',
        type: AccountType.equity,
      );
      await workspace.createAccount(
        code: '4000',
        name: 'Sales',
        type: AccountType.income,
      );
      final accounts = await workspace.accounts();
      final equity = accounts
          .firstWhere((a) => a.account.type == AccountType.equity)
          .account
          .id;
      final income = accounts
          .firstWhere((a) => a.account.type == AccountType.income)
          .account
          .id;
      final id = EntityId.random();
      await workspace.database.save(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: id,
            date: DateTime(2026, 9, 30),
            memo: 'Closing Proposal',
            closingEquityAccountId: equity,
            lines: [
              JournalLine.debit(
                accountId: income,
                amount: Money.fromMinor(10000, 'MYR'),
              ),
              JournalLine.credit(
                accountId: equity,
                amount: Money.fromMinor(10000, 'MYR'),
              ),
            ],
          ),
          metadata: RecordMetadata.initial(
            recordId: id,
            businessId: workspace.identity.businessId,
            originDeviceId: workspace.identity.deviceId,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ),
      );
      await tester.pumpWidget(
        AudytApp(initialPath: '/accounting', workspace: workspace),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('navigation-item-accounting')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Journal Review'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Closing Entry'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('review-journal-${id.value}')));
      await tester.pumpAndSettle();
      expect(find.text('Closing Entry'), findsOneWidget);
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows,
        contains(('Equity Account', '3000 · Retained Earnings')),
      );
      await tester.tap(find.byKey(const ValueKey('approve-journal')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Closing balances changed'), findsOneWidget);
      expect(
        (await workspace.database.getById(id))!.entry.state,
        JournalEntryState.draft,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
