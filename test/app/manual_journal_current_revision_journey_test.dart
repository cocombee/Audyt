import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/fixed_popout_host.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));
Future<void> host(WidgetTester tester, AccountingWorkspace workspace) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: JournalReviewPage(workspace: workspace, initialPosted: true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'posted manual current Journal uses original editor, actions, cancel, save, review and restart at $width',
      (tester) async {
        final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(
          () => WidgetController.hitTestWarningShouldBeFatal = oldFatal,
        );
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = Fixture();
        await f.open();
        final root = await f.post(9, 14, -10000);
        final before = f.w.database.exportDataArchive(
          f.business,
          DateTime.utc(2027),
        );
        await host(tester, f.w);
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
}
