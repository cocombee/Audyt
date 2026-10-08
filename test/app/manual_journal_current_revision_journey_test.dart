import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/fixed_popout_host.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));
Future<void> host(
  WidgetTester tester,
  AccountingWorkspace workspace, {
  bool initialPosted = true,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: JournalReviewPage(
            workspace: workspace,
            initialPosted: initialPosted,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    testWidgets(
      'posted manual current Journal uses original editor, actions, cancel, save, review and restart at $width',
      (tester) async {
        final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(
          () => WidgetController.hitTestWarningShouldBeFatal = oldFatal,
        );
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        final root = await f.post(9, 14, -10000);
        final before = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2027),
        );
        await host(tester, f.w);
        await tap(tester, keyed('review-journal-${root.value}'));
        expect(find.text('Posted Journal'), findsOneWidget);
        expect(find.text('Review Journal Correction'), findsNothing);
        expect(find.text('Original Posting'), findsNothing);
        expect(keyed('journal-original-review-lines-table'), findsNothing);
        await captureUi(
          tester,
          'Journal Correction Protected Original Review ${width.toInt()}',
        );
        await tap(tester, find.byType(AccountingCloseIcon));
        expect(
          f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
          before,
        );
        await tap(tester, keyed('edit-journal-${root.value}'));
        expect(find.text('Edit Journal'), findsOneWidget);
        expect(
          tester.widget<TextField>(keyed('journal-credit-0')).controller!.text,
          '100.00',
        );
        await tap(tester, keyed('add-journal-line'));
        expect(keyed('journal-line-2'), findsOneWidget);
        await captureUi(
          tester,
          'Journal Current Edit Original Actions ${width.toInt()}',
        );
        await tap(tester, keyed('remove-journal-line-2'));
        expect(keyed('journal-line-2'), findsNothing);
        await tap(tester, find.byType(AccountingCloseIcon));
        expect(
          f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
          before,
        );
        await tap(tester, keyed('edit-journal-${root.value}'));
        await tester.enterText(keyed('journal-credit-0'), '120.00');
        await tap(tester, keyed('add-journal-line'));
        await tap(tester, keyed('journal-account-2'));
        await tap(tester, find.text('5000 · Fictional Supplies').last);
        await tester.enterText(keyed('journal-debit-2'), '20.00');
        await tap(tester, keyed('save-journal-draft'));
        final revision = f.w.database.manualJournalCurrentRevision(
          f.business,
          root,
        )!;
        expect(revision.draft.entry.lines.map((l) => l.amount.minorUnits), [
          12000,
          10000,
          2000,
        ]);
        expect(
          (await f.w.database.getById(root))!
              .entry
              .lines
              .first
              .amount
              .minorUnits,
          10000,
        );
        await tap(
          tester,
          keyed('review-journal-${revision.draft.entry.id.value}'),
        );
        expect(find.text('Review Journal Correction'), findsOneWidget);
        expect(find.text('Journal Correction'), findsOneWidget);
        expect(find.text('Approve & Post Correction'), findsOneWidget);
        final original = keyed('journal-original-review-lines-table');
        final replacement = keyed('journal-review-lines-table');
        expect(
          find.descendant(of: original, matching: find.text('100.00')),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: original, matching: find.text('120.00')),
          findsNothing,
        );
        expect(
          find.descendant(of: replacement, matching: find.text('120.00')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: replacement, matching: find.text('20.00')),
          findsOneWidget,
        );
        final reviewed = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2027),
        );
        await captureUi(
          tester,
          'Journal Correction Original And Replacement Review ${width.toInt()}',
        );
        await tester.ensureVisible(
          find.descendant(of: replacement, matching: find.text('20.00')),
        );
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Journal Correction Replacement Lower Review ${width.toInt()}',
        );
        await tap(tester, find.byType(AccountingCloseIcon));
        expect(
          f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
          reviewed,
        );
        await tap(
          tester,
          keyed('review-journal-${revision.draft.entry.id.value}'),
        );
        await tap(tester, keyed('approve-journal'));
        expect(
          f.w.database.manualJournalCurrentPostingId(f.business, root),
          revision.draft.entry.id,
        );
        final report = await f.w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2027),
        );
        expect(
          report.rows.singleWhere((r) => r.account.id == f.bank).endingNetDebit,
          BigInt.from(-12000),
        );
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        await host(tester, f.w);
        await tap(tester, keyed('edit-journal-${root.value}'));
        expect(
          tester.widget<TextField>(keyed('journal-credit-0')).controller!.text,
          '120.00',
        );
        expect(
          tester.widget<TextField>(keyed('journal-debit-2')).controller!.text,
          '20.00',
        );
        expect(find.byType(AccountingTransactionGrid), findsOneWidget);
        await captureUi(tester, 'Journal Current Edit Saved ${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1162.0]) {
    testWidgets('manual correction history distinguishes postings at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      tester.view.physicalSize = Size(width, 809);
      final f = Fixture();
      await f.open();
      final root = await f.post(9, 14, -10000);
      await host(tester, f.w);
      expect(find.textContaining('Original Posting'), findsNothing);
      expect(find.textContaining('Replacement Posting'), findsNothing);
      final original = (await f.w.database.getById(root))!;

      for (var revisionNumber = 1; revisionNumber <= 2; revisionNumber++) {
        final postingId = f.w.database.manualJournalCurrentPostingId(
          f.business,
          root,
        );
        final source = (await f.w.database.getById(postingId))!;
        final amount = Money.fromMinor(11000 + revisionNumber * 1000, 'MYR');
        final correction = f.w.saveManualJournalRevision(
          rootId: root,
          expectedSource: source,
          expectedCurrentRevision: revisionNumber - 1,
          date: source.entry.date,
          // Identical Memo/date/line count must still distinguish the postings.
          memo: original.entry.memo,
          lines: [
            JournalLine.credit(accountId: f.bank, amount: amount),
            JournalLine.debit(accountId: f.expense, amount: amount),
          ],
          requestId: AccountingWorkspace.newId(),
          savedAt: source.metadata.updatedAt.add(const Duration(seconds: 1)),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: keyed('journal-row-${root.value}'),
            matching: find.text('14-09-2026 · 2 Lines · Original Posting'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: keyed('journal-row-${correction.draft.entry.id.value}'),
            matching: find.text(
              '14-09-2026 · 2 Lines · Journal Correction · Revision $revisionNumber',
            ),
          ),
          findsOneWidget,
        );
        if (revisionNumber == 1) {
          await captureUi(tester, 'Journal History Pending ${width.toInt()}');
        }
        f.w.approveManualJournalRevision(
          JournalApproval(
            requestId: AccountingWorkspace.newId(),
            businessId: f.business,
            journalId: correction.draft.entry.id,
            expectedRevision: correction.draft.metadata.revision,
            actorId: f.w.identity.ownerId,
            approvedAt: correction.draft.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: keyed('journal-row-${correction.draft.entry.id.value}'),
            matching: find.text(
              '14-09-2026 · 2 Lines · Replacement Posting · Revision $revisionNumber',
            ),
          ),
          findsOneWidget,
        );
        expect(
          (await f.w.database.getById(root))!
              .entry
              .lines
              .first
              .amount
              .minorUnits,
          10000,
        );
      }
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2027),
      );
      await tester.pumpWidget(const SizedBox());
      f.w.dispose();
      f.w = await AccountingWorkspace.open(f.path);
      await host(tester, f.w);
      expect(
        find.text('14-09-2026 · 2 Lines · Original Posting'),
        findsOneWidget,
      );
      for (final revisionNumber in [1, 2]) {
        expect(
          find.text(
            '14-09-2026 · 2 Lines · Replacement Posting · Revision $revisionNumber',
          ),
          findsOneWidget,
        );
      }
      expect(find.textContaining('Journal Correction'), findsNothing);
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
        before,
      );
      final report = await f.w.report(
        from: DateTime.utc(2026),
        through: DateTime.utc(2027),
      );
      expect(
        report.rows.singleWhere((r) => r.account.id == f.bank).endingNetDebit,
        BigInt.from(-13000),
      );
      await captureUi(tester, 'Journal History Posted ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
    testWidgets('saved correction review at fresh $width keeps exact facts', (
      tester,
    ) async {
      await prepare(tester, width);
      tester.view.physicalSize = Size(width, 809);
      installFixedPopoutHost(tester);
      final f = Fixture();
      await f.open();
      final root = await f.post(9, 14, -10000);
      final source = (await f.w.database.getById(root))!;
      final correction = f.w.saveManualJournalRevision(
        rootId: root,
        expectedSource: source,
        expectedCurrentRevision: 0,
        date: source.entry.date,
        memo: 'Proposed replacement',
        lines: [
          JournalLine.credit(
            accountId: f.bank,
            amount: Money.fromMinor(12000, 'MYR'),
          ),
          JournalLine.debit(
            accountId: f.expense,
            amount: Money.fromMinor(12000, 'MYR'),
          ),
        ],
        requestId: AccountingWorkspace.newId(),
        savedAt: DateTime.now().toUtc(),
      );
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2027),
      );
      await host(tester, f.w, initialPosted: false);
      await tap(
        tester,
        keyed('review-journal-${correction.draft.entry.id.value}'),
      );
      expect(find.text('Review Journal Correction'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Fictional 9/14'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Proposed replacement'),
        ),
        findsOneWidget,
      );
      final original = keyed('journal-original-review-lines-table');
      final replacement = keyed('journal-review-lines-table');
      expect(
        find.descendant(of: original, matching: find.text('100.00')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: replacement, matching: find.text('120.00')),
        findsNWidgets(2),
      );
      await captureUi(
        tester,
        'Journal Correction Fresh Saved Review ${width.toInt()}',
      );
      await tester.ensureVisible(
        find.descendant(of: replacement, matching: find.text('120.00')).last,
      );
      await tester.pumpAndSettle();
      await captureUi(
        tester,
        'Journal Correction Fresh Saved Lower Review ${width.toInt()}',
      );
      await tap(tester, find.byType(AccountingCloseIcon));
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
        before,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('ordinary Draft review excludes correction at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      tester.view.physicalSize = Size(width, 809);
      installFixedPopoutHost(tester);
      final f = Fixture();
      await f.open();
      final id = await f.post(9, 14, -10000, approve: false);
      final before = f.w.database.exportDataArchive(
        f.business,
        DateTime.utc(2027),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(body: JournalReviewPage(workspace: f.w)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, keyed('review-journal-${id.value}'));
      expect(find.text('Review Journal'), findsOneWidget);
      expect(find.text('Approve & Post'), findsOneWidget);
      expect(find.text('Review Journal Correction'), findsNothing);
      expect(find.text('Original Posting'), findsNothing);
      expect(keyed('journal-original-review-lines-table'), findsNothing);
      await captureUi(
        tester,
        'Journal Correction Protected Draft Review ${width.toInt()}',
      );
      await tap(tester, find.byType(AccountingCloseIcon));
      expect(
        f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
        before,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
