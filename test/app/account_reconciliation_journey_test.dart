
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/reconciliation_history_dialog.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import '../support/accounting_text_input.dart';
import 'reconciliation_list_scope_test.dart' as imported;
import 'restored_page_routes_test.dart' show tables;

Finder keyed(String value) => find.byKey(ValueKey(value));

Future<void> input(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(keyed(key));
  await enterAccountingText(tester, keyed(key), text);
  await tester.pumpAndSettle();
}

Future<void> period(WidgetTester tester) async {
  await input(tester, 'reconciliation-start', '01-09-2026');
  await input(tester, 'reconciliation-end', '30-09-2026');
  await input(tester, 'reconciliation-opening', '100.00');
  await input(tester, 'reconciliation-closing', '90.00');
  await tap(tester, keyed('review-reconciliation'));
}

Future<void> bankHost(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(body: BankingPage(workspace: f.w, compact: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> accountMenu(WidgetTester tester, String action) async {
  await tap(tester, keyed('imported-account-more'));
  await tap(tester, find.text(action));
}

Uint8List original() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 120, height: 80)));

Future<void> directHost(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-account-period'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => StatementReconciliationDialog.account(
                  workspace: f.w,
                  paymentAccountId: 'bank',
                  currency: 'MYR',
                  sourceLabel: 'Fictional Bank',
                  onAttachmentsPick: (_) async => [
                    PickedExpenseAttachment(
                      name: 'Fictional opening.png',
                      mimeType: 'image/png',
                      bytes: original(),
                    ),
                  ],
                ),
              ),
              child: const Text('Reconcile Account'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, keyed('open-account-period'));
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final accountMode in [true, false]) {
      final title = accountMode ? 'Account' : 'Statement';
      testWidgets('$title reconciliation guards unsaved work at $width', (
        tester,
      ) async {
        await prepare(tester, width);
        final account = Fixture();
        await account.open();
        final source = await imported.fixture(1);
        addTearDown(source.w.dispose);
        final workspace = accountMode ? account.w : source.w;
        final before = tables(workspace);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open-discard-reconciliation'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => accountMode
                          ? StatementReconciliationDialog.account(
                              workspace: workspace,
                              paymentAccountId: 'bank',
                              currency: 'MYR',
                              sourceLabel: 'Fictional Bank',
                            )
                          : StatementReconciliationDialog(
                              workspace: workspace,
                              statementId: source.statement,
                              currency: 'MYR',
                            ),
                    ),
                    child: const Text('Open Reconciliation'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tap(tester, keyed('open-discard-reconciliation'));
        await tap(tester, keyed('reconciliation-editor-close'));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        await tap(tester, keyed('open-discard-reconciliation'));
        await input(tester, 'reconciliation-closing', '90.00');
        await tester.tap(keyed('reconciliation-closing'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(
          tester,
          '$title Reconciliation Discard Warning ${width.toInt()}',
        );
        await tap(tester, keyed('reconciliation-keep-editing'));
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-closing'))
              .controller!
              .text,
          '90.00',
        );
        await tap(tester, keyed('reconciliation-editor-close'));
        await tap(tester, keyed('reconciliation-discard-close'));
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-closing'))
              .controller!
              .text,
          '90.00',
        );
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(tester, keyed('reconciliation-keep-editing'));
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await tap(tester, keyed('reconciliation-editor-close'));
        await capture(
          tester,
          '$title Reconciliation Discard Short ${width.toInt()}',
        );
        await tap(tester, keyed('reconciliation-discard-changes'));
        expect(find.byType(StatementReconciliationDialog), findsNothing);
        expect(tables(workspace), before);
        await tap(tester, keyed('open-discard-reconciliation'));
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-closing'))
              .controller!
              .text,
          isNot('90.00'),
        );
        await tap(tester, keyed('reconciliation-editor-close'));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
      });
    }
    testWidgets(
      'embedded reconciliation guards Back and saved draft baseline at $width',
      (tester) async {
        await prepare(tester, width);
        final f = await imported.fixture(1);
        addTearDown(f.w.dispose);
        var showing = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => showing
                    ? SingleChildScrollView(
                        child: StatementReconciliationDialog(
                          workspace: f.w,
                          statementId: f.statement,
                          currency: 'MYR',
                          embedded: true,
                          onBack: () => setState(() => showing = false),
                        ),
                      )
                    : const Text('Returned to Banking'),
              ),
            ),
          ),
        );
        await period(tester);
        await input(
          tester,
          'reconciliation-evidence',
          'Retained opening evidence',
        );
        await tap(tester, keyed('back-to-banking'));
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(tester, keyed('reconciliation-keep-editing'));
        await tap(tester, keyed('save-reconciliation-draft'));
        expect(
          f.w.database
              .readReconciliationDraft(f.w.identity.businessId, f.statement)!
              .openingEvidence,
          'Retained opening evidence',
        );
        await tap(tester, keyed('back-to-banking'));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(find.text('Returned to Banking'), findsOneWidget);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Banking account review, approval, evidence and reopen without imports at $width',
      (tester) async {
        await prepare(tester, width);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final cleared = await f.post(9, 2, -1000);
        await f.post(9, 3, -400);
        await bankHost(tester, f);
        expect(f.w.database.bankStatements(f.business, 'bank'), isEmpty);
        await accountMenu(tester, 'Reconcile Account');
        expect(find.text('Account Reconciliation'), findsOneWidget);
        await period(tester);
        final opening = tester.getRect(keyed('reconciliation-opening'));
        final closing = tester.getRect(keyed('reconciliation-closing'));
        expect(opening.top, closeTo(closing.top, .01));
        expect(opening.width, closeTo(closing.width, .01));
        expect(
          closing.left - opening.right,
          closeTo(accountingContentInset, .01),
        );
        await tap(tester, keyed('account-cleared-$cleared:0'));
        expect(
          tester
              .widget<FilledButton>(keyed('approve-reconciliation'))
              .onPressed,
          isNotNull,
        );
        // The command enforces first-opening evidence even with zero difference.
        await tap(tester, keyed('approve-reconciliation'));
        expect(
          f.w.database.accountReconciliationHistory(f.business, 'bank'),
          isEmpty,
        );
        expect(
          find.text(
            'Document the first opening balance and outstanding items.',
          ),
          findsOneWidget,
        );
        await input(
          tester,
          'reconciliation-evidence',
          'Fictional verified opening',
        );
        await tester.ensureVisible(keyed('reconciliation-date-fields'));
        await tester.pumpAndSettle();
        await capture(tester, 'Account Reconciliation Header ${width.toInt()}');
        await tester.ensureVisible(
          keyed('reconciliation-account-transactions'),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'Account Reconciliation Ready ${width.toInt()}');
        await tap(tester, keyed('approve-reconciliation'));
        expect(find.text('Reconciliation Approved'), findsOneWidget);
        final completion = f.w.database
            .accountReconciliationHistory(f.business, 'bank')
            .single;
        final evidence = f.w.database.reconciliationEvidence(
          f.business,
          completion.id,
        );
        expect(evidence.isAccountPeriod, isTrue);
        expect(evidence.selectedMovements.single.id, '$cleared:0');
        expect(evidence.matches, isEmpty);
        expect(f.w.database.bankStatements(f.business, 'bank'), isEmpty);
        expect(await f.w.journals(), hasLength(3));
        expect(
          tester.widget<TextField>(keyed('reconciliation-closing')).readOnly,
          isTrue,
        );
        await tap(tester, find.bySemanticsLabel('Close').last);
        await accountMenu(tester, 'Reconciliation History');
        expect(find.byType(ReconciliationHistoryDialog), findsOneWidget);
        await capture(
          tester,
          'Account Reconciliation History ${width.toInt()}',
        );
        await tap(tester, keyed('reconciliation-evidence-${completion.id}'));
        expect(find.text('Approved Statement Matches'), findsNothing);
        expect(find.textContaining('Source SHA-256:'), findsNothing);
        expect(find.textContaining('Selected This Period'), findsOneWidget);
        expect(find.textContaining('Outstanding'), findsWidgets);
        await capture(
          tester,
          'Account Reconciliation Evidence ${width.toInt()}',
        );
        await tap(tester, find.bySemanticsLabel('Close').last);
        await tap(tester, keyed('reopen-reconciliation-${completion.id}'));
        await input(
          tester,
          'reconciliation-reopening-reason',
          'Fictional correction',
        );
        await tap(tester, keyed('confirm-reconciliation-reopening'));
        expect(
          f.w.database
              .accountReconciliationHistory(f.business, 'bank')
              .single
              .reopenedAt,
          isNotNull,
        );
        expect(f.w.database.latestReconciliationId(f.business, 'bank'), isNull);
        expect(
          f.w.database
              .reconciliationEvidence(f.business, completion.id)
              .selectedMovements
              .single
              .id,
          '$cleared:0',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'account selections and original files resume from durable draft at $width',
      (tester) async {
        await prepare(tester, width);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final cleared = await f.post(9, 2, -1000);
        await directHost(tester, f);
        await period(tester);
        await tap(tester, keyed('account-cleared-$cleared:0'));
        await input(
          tester,
          'reconciliation-evidence',
          'Fictional saved opening',
        );
        await tap(tester, keyed('reconciliation-file-choose'));
        expect(find.text('Fictional opening.png'), findsOneWidget);
        await tap(tester, keyed('save-reconciliation-draft'));
        final draft = f.w.database.readAccountReconciliationDraft(
          f.business,
          'bank',
        )!;
        expect(draft.selectedIds, {'$cleared:0'});
        expect(draft.attachments.single.originalBytes, original());
        expect(draft.revision, 1);
        await tester.pumpWidget(const SizedBox());
        f.w.dispose();
        f.w = await AccountingWorkspace.open(f.path);
        await directHost(tester, f);
        expect(
          tester
              .widget<TextField>(keyed('reconciliation-closing'))
              .controller!
              .text,
          '90.00',
        );
        expect(find.text('Fictional opening.png'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(keyed('approve-reconciliation'))
              .onPressed,
          isNull,
        );
        await tap(tester, keyed('review-reconciliation'));
        expect(
          tester.widget<Checkbox>(keyed('account-cleared-$cleared:0')).value,
          isTrue,
        );
        await tap(tester, keyed('approve-reconciliation'));
        expect(find.text('Reconciliation Approved'), findsOneWidget);
        expect(
          f.w.database.readAccountReconciliationDraft(f.business, 'bank'),
          isNull,
        );
        final completion = f.w.database
            .accountReconciliationHistory(f.business, 'bank')
            .single;
        expect(
          f.w.database
              .reconciliationEvidence(f.business, completion.id)
              .attachments
              .single
              .originalBytes,
          original(),
        );
        expect(f.w.database.bankStatements(f.business, 'bank'), isEmpty);
        expect(await f.w.journals(), hasLength(2));
        await capture(
          tester,
          'Account Reconciliation Supporting Files ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('fresh posting after account review prevents stale UI approval', (
    tester,
  ) async {
    await prepare(tester, 720);
    final f = Fixture();
    await f.open();
    await f.post(8, 31, 10000);
    final cleared = await f.post(9, 2, -1000);
    await directHost(tester, f);
    await period(tester);
    await tap(tester, keyed('account-cleared-$cleared:0'));
    await input(tester, 'reconciliation-evidence', 'Fictional opening');
    await f.post(9, 3, -500);
    await tap(tester, keyed('approve-reconciliation'));
    expect(
      find.text(
        'Reconciliation ledger or previous period changed. Review again.',
      ),
      findsOneWidget,
    );
    expect(
      f.w.database.accountReconciliationHistory(f.business, 'bank'),
      isEmpty,
    );
    await tap(tester, keyed('review-reconciliation'));
    await tap(tester, keyed('approve-reconciliation'));
    expect(
      f.w.database.accountReconciliationHistory(f.business, 'bank'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
}
