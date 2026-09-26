import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));

Future<void> host(
  WidgetTester tester,
  AccountingWorkspace workspace, {
  bool create = false,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: create
              ? ChartOfAccountsPage(workspace: workspace, compact: true)
              : JournalReviewPage(workspace: workspace),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final create in [true, false]) {
      final title = create ? 'New' : 'Edit';
      testWidgets(
        '$title Journal retains all unsaved inputs and guarded dismissal at $width',
        (tester) async {
          final before = WidgetController.hitTestWarningShouldBeFatal;
          WidgetController.hitTestWarningShouldBeFatal = true;
          addTearDown(
            () => WidgetController.hitTestWarningShouldBeFatal = before,
          );
          await prepare(tester, width);
          installFixedPopoutHost(tester);
          final f = Fixture();
          await f.open();
          final id = await f.post(9, 14, -10000, approve: false);
          final original = (await f.w.database.getById(id))!;
          await host(tester, f.w, create: create);
          final entry = create
              ? keyed('new-journal')
              : keyed('edit-journal-${id.value}');
          await tap(tester, entry);
          // Merely opening an existing record or returning rows to their
          // opening state must not create a dirty session.
          await tap(tester, keyed('add-journal-line'));
          await tap(tester, keyed('remove-journal-line-2'));
          await tap(tester, keyed('journal-editor-close'));
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          expect(keyed('journal-editor-close'), findsNothing);
          await tap(tester, entry);
          final memo = keyed('journal-memo');
          await enterAccountingText(
            tester,
            memo,
            'Retain this unsaved journal memo.',
          );
          await tap(tester, keyed('journal-editor-close'));
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await captureUi(
            tester,
            '$title Journal Discard Warning ${width.toInt()}',
          );
          await tap(tester, keyed('journal-keep-editing'));
          expect(
            tester
                .state<AccountingDescriptionFieldState>(memo)
                .editor
                .plainDescription,
            'Retain this unsaved journal memo.',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(tester, keyed('journal-discard-close'));
          expect(
            tester
                .state<AccountingDescriptionFieldState>(memo)
                .editor
                .plainDescription,
            'Retain this unsaved journal memo.',
          );
          await tester.tapAt(const Offset(2, 2));
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(tester, keyed('journal-keep-editing'));
          final accommodatedWidth = tester.view.physicalSize.width;
          tester.view.physicalSize = Size(accommodatedWidth, 613);
          await tester.pumpAndSettle();
          await tap(tester, keyed('journal-editor-close'));
          await captureUi(
            tester,
            '$title Journal Discard Short Height ${width.toInt()}',
          );
          await tap(tester, keyed('journal-discard-changes'));
          expect(keyed('journal-editor-close'), findsNothing);
          tester.view.physicalSize = Size(accommodatedWidth, 1000);
          await tester.pumpAndSettle();
          for (final input in [
            'date',
            'account',
            'debit',
            'credit',
            'add',
            'remove',
          ]) {
            await tap(tester, entry);
            switch (input) {
              case 'date':
                await tester.enterText(keyed('journal-date'), '15-09-2026');
              case 'account':
                await tap(tester, keyed('journal-account-0'));
                await tap(
                  tester,
                  find.ancestor(
                    of: find.text('5000 · Fictional Supplies'),
                    matching: find.byType(MenuItemButton),
                  ),
                );
                expect(
                  find.descendant(
                    of: keyed('journal-account-0'),
                    matching: find.text('5000 · Fictional Supplies'),
                  ),
                  findsOneWidget,
                );
              case 'debit':
                await tester.enterText(keyed('journal-debit-0'), '50.00');
              case 'credit':
                await tester.enterText(keyed('journal-credit-0'), '120.00');
              case 'add':
                await tap(tester, keyed('add-journal-line'));
              case 'remove':
                await tap(tester, keyed('remove-journal-line-1'));
            }
            await tester.pumpAndSettle();
            await tap(tester, keyed('journal-editor-close'));
            expect(
              find.text('Discard Unsaved Changes?'),
              findsOneWidget,
              reason: input,
            );
            await tap(tester, keyed('journal-discard-changes'));
            expect(keyed('journal-editor-close'), findsNothing);
          }
          expect(await f.w.journals(), hasLength(1));
          expect(
            (await f.w.database.getById(id))!.metadata.revision,
            original.metadata.revision,
          );
          final changes = (await f.w.database.auditEvents(f.business))
              .where((event) => event['kind'] == 'journal.draft_revised');
          expect(changes, isEmpty);
          await tester.pumpWidget(const SizedBox());
          f.w.dispose();
          f.w = await AccountingWorkspace.open(f.path);
          final reopened = (await f.w.database.getById(id))!;
          expect(reopened.entry.memo, original.entry.memo);
          expect(reopened.entry.date, original.entry.date);
          expect(
            reopened.entry.lines.map((line) => line.amount.minorUnits),
            original.entry.lines.map((line) => line.amount.minorUnits),
          );
          expect(reopened.metadata.revision, original.metadata.revision);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('saved manual Journal draft edits same identity at $width', (
      tester,
    ) async {
      final before = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = before);
      await prepare(tester, width);
      installFixedPopoutHost(tester);
      final f = Fixture();
      await f.open();
      final id = await f.post(9, 14, -10000, approve: false);
      final original = (await f.w.database.getById(id))!;
      await host(tester, f.w);
      await tap(tester, keyed('edit-journal-${id.value}'));
      expect(find.text('Edit Journal'), findsOneWidget);
      expect(
        tester.widget<TextField>(keyed('journal-date')).controller!.text,
        '14-09-2026',
      );
      expect(
        tester.widget<TextField>(keyed('journal-credit-0')).controller!.text,
        '100.00',
      );
      expect(
        tester.widget<TextField>(keyed('journal-debit-1')).controller!.text,
        '100.00',
      );
      await tap(tester, keyed('add-journal-line'));
      expect(keyed('journal-line-2'), findsOneWidget);
      await captureUi(
        tester,
        'Journal Draft Edit Original Actions ${width.toInt()}',
      );
      await tap(tester, keyed('remove-journal-line-2'));
      expect(keyed('journal-line-2'), findsNothing);
      await tester.enterText(keyed('journal-credit-0'), '120.00');
      await tap(tester, keyed('add-journal-line'));
      await tap(tester, keyed('journal-account-2'));
      await tap(tester, find.text('5000 · Fictional Supplies').last);
      await tester.enterText(keyed('journal-debit-2'), '20.00');
      await tap(tester, keyed('save-journal-draft'));
      expect(find.text('Edit Journal'), findsNothing);
      final changed = (await f.w.database.getById(id))!;
      expect(await f.w.journals(), hasLength(1));
      expect(changed.metadata.revision, original.metadata.revision + 1);
      expect(changed.entry.lines.map((l) => l.amount.minorUnits), [
        12000,
        10000,
        2000,
      ]);
      final events = (await f.w.database.auditEvents(f.business))
          .where((e) => e['kind'] == 'journal.draft_revised');
      expect(events, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      f.w.dispose();
      f.w = await AccountingWorkspace.open(f.path);
      await host(tester, f.w);
      await tap(tester, keyed('edit-journal-${id.value}'));
      expect(
        tester.widget<TextField>(keyed('journal-credit-0')).controller!.text,
        '120.00',
      );
      expect(find.byType(AccountingTransactionGrid), findsOneWidget);
      expect(
        tester.widget<TextField>(keyed('journal-debit-2')).controller!.text,
        '20.00',
      );
      await captureUi(tester, 'Journal Draft Edit Saved ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
