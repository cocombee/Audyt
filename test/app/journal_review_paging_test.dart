import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import 'summary_action_wiring_test.dart' show view;
import 'restored_page_routes_test.dart' show tables;
import 'journal_workspace_integration_test.dart' show captureUi;

Future<AccountingWorkspace> fixture(String path) async {
  final w = await AccountingWorkspace.open(path);
  await w.createAccount(
    code: '1000',
    name: 'Fictional Cash',
    type: AccountType.asset,
  );
  await w.createAccount(
    code: '3000',
    name: 'Fictional Capital',
    type: AccountType.equity,
  );
  final accounts = await w.accounts();
  for (var i = 0; i < 15; i++) {
    await w.saveJournal(
      date: DateTime.utc(2026, 9, i % 2 == 0 ? 1 : 2, 23, 59),
      memo: 'Fictional Journal $i',
      lines: [
        JournalLine.debit(
          accountId: accounts.first.account.id,
          amount: Money.fromMinor(100, 'MYR'),
        ),
        JournalLine.credit(
          accountId: accounts.last.account.id,
          amount: Money.fromMinor(100, 'MYR'),
        ),
      ],
    );
  }
  final records = await w.journals();
  for (final record in records.take(2)) {
    await w.approveJournal(
      JournalApproval(
        requestId: AccountingWorkspace.newId(),
        businessId: w.identity.businessId,
        journalId: record.entry.id,
        expectedRevision: record.metadata.revision,
        actorId: w.identity.ownerId,
        approvedAt: DateTime.now().toUtc(),
      ),
    );
  }
  return w;
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored journal pages retain search, controls and exact posting at $width',
      (tester) async {
        await view(tester, width);
        final root = Directory.systemTemp.createTempSync(
          'audyt-journal-page-ui-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final source = await fixture('${root.path}/source.sqlite');
        final before = tables(source);
        final w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          source.database.exportDataArchive(
            source.identity.businessId,
            DateTime.utc(2026, 9, 3),
          ),
        );
        addTearDown(w.dispose);
        addTearDown(source.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: w,
              showInitialSetup: false,
              initialPath: '/accounting',
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        await tap(find.widgetWithText(Tab, 'Journal Review'));
        expect(find.byType(AccountingRecordRow), findsNWidgets(5));
        await captureUi(tester, 'Journal Pages Drafts ${width.toInt()}');
        await tap(find.byKey(const ValueKey('journal-page-next')));
        expect(find.byType(AccountingRecordRow), findsNWidgets(5));
        await tap(find.byKey(const ValueKey('journal-page-next')));
        expect(find.byType(AccountingRecordRow), findsNWidgets(3));
        await tap(find.byKey(const ValueKey('journal-page-previous')));
        await tap(find.byKey(const ValueKey('journal-page-previous')));
        await tap(find.byKey(const ValueKey('journal-page-size')));
        await tap(find.text('5').last);
        expect(find.byType(AccountingRecordRow), findsNWidgets(5));
        await tester.enterText(
          find.byKey(const ValueKey('journal-search')),
          'Fictional Journal 14',
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordRow), findsOneWidget);
        final target = w.database
            .readJournalPage(
              businessId: w.identity.businessId,
              state: JournalEntryState.draft,
              search: 'Fictional Journal 14',
            )
            .records
            .single;
        await tap(
          find.byKey(ValueKey('review-journal-${target.entry.id.value}')),
        );
        await captureUi(tester, 'Journal Pages Review ${width.toInt()}');
        await tap(accountingCloseIcon().last);
        expect(tables(w), before);
        await tap(find.byKey(const ValueKey('prepare-closing')));
        expect(find.text('Prepare Closing'), findsWidgets);
        await tap(find.bySemanticsLabel('Close').last);
        expect(tables(w), before);
        await tap(
          find.byKey(ValueKey('review-journal-${target.entry.id.value}')),
        );
        await tap(find.byKey(const ValueKey('approve-journal')));
        expect(find.text('No Matching Journals'), findsOneWidget);
        final posted = (await w.database.getById(target.entry.id))!;
        expect(posted.entry.state, JournalEntryState.posted);
        expect(posted.metadata.revision, target.metadata.revision + 1);
        await tap(find.byKey(const ValueKey('review-posted')));
        expect(find.byType(AccountingRecordRow), findsOneWidget);
        await tap(
          find.byKey(ValueKey('review-journal-${target.entry.id.value}')),
        );
        expect(find.text('Posted Journal'), findsOneWidget);
        expect(find.byKey(const ValueKey('approve-journal')), findsNothing);
        await tap(accountingCloseIcon().last);
        await tester.enterText(
          find.byKey(const ValueKey('journal-search')),
          '',
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordRow), findsNWidgets(3));
        await captureUi(tester, 'Journal Pages Posted ${width.toInt()}');
        await tester.enterText(
          find.byKey(const ValueKey('global-search-field')),
          'Fictional Journal 14',
        );
        await tester.pumpAndSettle();
        final globalJournal = find.widgetWithText(
          ListTile,
          'Fictional Journal 14',
        );
        expect(globalJournal, findsOneWidget);
        await captureUi(tester, 'Global Search Popup ${width.toInt()}');
        await tap(globalJournal);
        expect(find.byType(JournalReviewPage), findsOneWidget);
        final report = await w.database.readReport(
          businessId: w.identity.businessId,
          currency: 'MYR',
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.trialBalanceDebits, BigInt.from(300));
        expect(report.trialBalanceCredits, BigInt.from(300));
        final after = tables(w);
        await tester.pumpWidget(const SizedBox());
        final reopened = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        addTearDown(reopened.dispose);
        expect(tables(reopened), after);
        expect(tables(source), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'failed reads remove stale journal approval rows and Retry remains honest',
    (tester) async {
      await view(tester, 720);
      final root = Directory.systemTemp.createTempSync(
        'audyt-journal-page-failure-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final w = await fixture('${root.path}/book.sqlite');
      addTearDown(w.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: JournalReviewPage(workspace: w)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountingRecordRow), findsNWidgets(5));
      w.database.close();
      await tester.tap(find.byKey(const ValueKey('review-posted')));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(find.byType(AccountingRecordRow), findsNothing);
      await captureUi(tester, 'Journal Pages Failed 720');
      await tester.tap(find.byKey(const ValueKey('retry-journal-page')));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(find.byType(AccountingRecordRow), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('through filter and company replacement reset the bounded page', (
    tester,
  ) async {
    await view(tester, 720);
    final root = Directory.systemTemp.createTempSync(
      'audyt-journal-page-company-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final first = await fixture('${root.path}/first.sqlite');
    final second = await AccountingWorkspace.open('${root.path}/second.sqlite');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget screen(AccountingWorkspace w) => MaterialApp(
      theme: AccountingTheme.light(),
      home: Scaffold(
        body: JournalReviewPage(
          workspace: w,
          through: DateTime.utc(2026, 9, 1),
        ),
      ),
    );
    await tester.pumpWidget(screen(first));
    await tester.pumpAndSettle();
    final before = tables(first);
    expect(find.text('Through 01-09-2026'), findsOneWidget);
    expect(find.byType(AccountingRecordRow), findsNWidgets(5));
    await tester.tap(
      find.byKey(const ValueKey('clear-journal-summary-filter')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountingRecordRow), findsNWidgets(5));
    await tester.enterText(
      find.byKey(const ValueKey('journal-search')),
      'Journal',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(second));
    await tester.pumpAndSettle();
    expect(find.text('No Journal Drafts'), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-search')), findsNothing);
    expect(tables(first), before);
    await tester.pumpWidget(const SizedBox());
  });
}
