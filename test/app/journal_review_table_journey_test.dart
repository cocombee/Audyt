import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;

const approvalGuidance =
    'Approve only when the accounts, amounts, date and supporting evidence are correct. Posting preserves this revision.';
const closingGuidance =
    'This transfers earnings between nominal accounts and equity; it does not change operating profit.';

Finder keyed(String value) => find.byKey(ValueKey(value));

Future<void> host(WidgetTester tester, AccountingWorkspace workspace) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(body: JournalReviewPage(workspace: workspace)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> hoverTitle(WidgetTester tester, String title) async {
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer();
  await mouse.moveTo(tester.getCenter(find.text(title)));
  await tester.pump(accountingTooltipWaitDuration);
  await tester.pumpAndSettle();
  addTearDown(mouse.removePointer);
}

void strictClicks() {
  final before = WidgetController.hitTestWarningShouldBeFatal;
  WidgetController.hitTestWarningShouldBeFatal = true;
  addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = before);
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Journal review shares top headers, actual title hover and retained posting at $width',
      (tester) async {
        strictClicks();
        await prepare(tester, width);
        final f = Fixture();
        await f.open();
        await f.w.createAccount(
          code: '3000',
          name: 'Fictional Owner Capital For The Regional Operations And Equipment Fund',
          type: AccountType.equity,
        );
        final capital = (await f.w.accounts())
            .singleWhere((a) => a.account.code == '3000')
            .account
            .id;
        await f.w.saveJournal(
          date: DateTime.utc(2026, 9, 14),
          memo: 'Fictional retained transaction memo',
          lines: [
            JournalLine.debit(
              accountId: f.bank,
              amount: Money.fromMinor(123456789, 'MYR'),
            ),
            JournalLine.debit(
              accountId: f.expense,
              amount: Money.fromMinor(1234, 'MYR'),
            ),
            JournalLine.credit(
              accountId: capital,
              amount: Money.fromMinor(123458023, 'MYR'),
            ),
          ],
        );
        final draft = (await f.w.journals()).single;
        final financialFacts = draft.entry.lines
            .map((line) => (line.accountId, line.amount, line.kind))
            .toList();
        await host(tester, f.w);
        await tap(tester, keyed('review-journal-${draft.entry.id.value}'));
        expect(find.text('Account'), findsOneWidget);
        expect(find.text('Debit (RM)'), findsOneWidget);
        expect(find.text('Credit (RM)'), findsOneWidget);
        expect(find.text('Account 1'), findsNothing);
        expect(find.text(approvalGuidance), findsNothing);
        expect(find.text('Fictional retained transaction memo'), findsWidgets);
        final table = keyed('journal-review-lines-table');
        expect(tester.widget<Table>(table).children, hasLength(4));
        expect(
          find.descendant(of: table, matching: find.text('1,234,567.89')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: table, matching: find.text('1,234,580.23')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: table, matching: find.text('0.00')),
          findsNWidgets(3),
        );
        expect(
          tester
              .widget<AccountingInformationRows>(
                find.byType(AccountingInformationRows),
              )
              .rows,
          [('Date', '14-09-2026')],
        );
        expect(tester.takeException(), isNull);
        await captureUi(tester, 'Journal Headed Review ${width.toInt()}');
        await hoverTitle(tester, 'Review Journal');
        expect(find.text(approvalGuidance), findsOneWidget);
        await captureUi(tester, 'Journal Title Guidance ${width.toInt()}');
        await tap(tester, keyed('approve-journal'));
        final posted = (await f.w.journals()).single;
        expect(posted.entry.state, JournalEntryState.posted);
        expect(
          posted.entry.lines
              .map((line) => (line.accountId, line.amount, line.kind))
              .toList(),
          financialFacts,
        );
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        await host(tester, f.w);
        await tap(tester, keyed('review-journal-${draft.entry.id.value}'));
        expect(find.text('Posted Journal'), findsOneWidget);
        expect(keyed('approve-journal'), findsNothing);
        expect(keyed('journal-review-lines-table'), findsOneWidget);
        final restored = (await f.w.journals()).single;
        expect(
          restored.entry.lines
              .map((line) => (line.accountId, line.amount, line.kind))
              .toList(),
          financialFacts,
        );
        await captureUi(
          tester,
          'Posted Journal Headed Review ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Closing review retains its facts and conditional guidance in the title tooltip',
    (tester) async {
      strictClicks();
      await prepare(tester, 720);
      final f = Fixture();
      await f.open();
      await f.w.createAccount(
        code: '3000',
        name: 'Fictional Closing Equity',
        type: AccountType.equity,
      );
      final equity = (await f.w.accounts())
          .singleWhere((a) => a.account.code == '3000')
          .account
          .id;
      await f.post(9, 2, -1000);
      await f.w.prepareClosing(
        through: DateTime.utc(2026, 9, 30),
        equityAccountId: equity,
      );
      final closing = (await f.w.journals()).singleWhere(
        (record) => record.entry.isClosing,
      );
      await host(tester, f.w);
      await tap(tester, keyed('review-journal-${closing.entry.id.value}'));
      final facts = tester
          .widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          )
          .rows;
      expect(facts, contains(('Entry Type', 'Closing Entry')));
      expect(
        facts,
        contains(('Equity Account', '3000 · Fictional Closing Equity')),
      );
      expect(find.text(closingGuidance), findsNothing);
      expect(find.text(approvalGuidance), findsNothing);
      await captureUi(tester, 'Journal Closing Headed Review 720');
      await hoverTitle(tester, 'Review Journal');
      expect(find.text('$closingGuidance $approvalGuidance'), findsOneWidget);
      await captureUi(tester, 'Journal Closing Title Guidance 720');
      await tap(tester, keyed('approve-journal'));
      expect(
        (await f.w.database.getById(closing.entry.id))!.entry.state,
        JournalEntryState.posted,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
