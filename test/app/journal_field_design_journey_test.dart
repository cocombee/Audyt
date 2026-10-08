import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/attachment_preview_pump.dart';
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;

Finder key(String name) => find.byKey(ValueKey(name));

/// Creates a disposable saved identity through the database's real currency
/// policy, then reopens it through the normal workspace entry point.
Future<AccountingWorkspace> openCurrencyFixture(String currency) async {
  final directory = Directory.systemTemp.createTempSync(
    'audyt-saved-currency-',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  final path = '${directory.path}/ledger.sqlite';
  final database = LocalAccountingDatabase.open(path);
  await database.openWorkspace(
    newBusinessId: EntityId.random(),
    newDeviceId: EntityId.random(),
    newOwnerId: EntityId.random(),
    defaultCurrency: currency,
  );
  database.close();
  final workspace = await AccountingWorkspace.open(path);
  addTearDown(workspace.dispose);
  expect(workspace.identity.currency, currency);
  return workspace;
}

void main() {
  for (final width in [720.0, 1162.0]) {
    for (final (currency, decimal, displayed) in [
      ('MYR', '1234567.89', '1,234,567.89'),
      ('JPY', '1234567', '1,234,567'),
      ('KWD', '1234567.891', '1,234,567.891'),
    ]) {
      for (final posted in [false, true]) {
        final state = posted ? 'Posted' : 'Draft';
        testWidgets(
          'Journal saved amount initialization $currency $state at $width',
          (tester) async {
            await prepare(tester, width);
            tester.view.physicalSize = Size(width, 809);
            installFixedPopoutHost(tester);
            final workspace = await openCurrencyFixture(currency);
            final cash = await workspace.createAccount(
              code: '1000',
              name: 'Cash',
              type: AccountType.asset,
            );
            final capital = await workspace.createAccount(
              code: '3000',
              name: 'Capital',
              type: AccountType.equity,
            );
            final amount = Money.fromDecimal(decimal, currency);
            await workspace.saveJournal(
              date: DateTime.utc(2026, 10, 7),
              memo: 'Saved exact amount',
              lines: [
                JournalLine.debit(accountId: cash, amount: amount),
                JournalLine.credit(accountId: capital, amount: amount),
              ],
            );
            final draft = (await workspace.journals()).single;
            if (posted) {
              await workspace.approveJournal(
                JournalApproval(
                  requestId: EntityId.random(),
                  businessId: workspace.identity.businessId,
                  journalId: draft.entry.id,
                  expectedRevision: draft.metadata.revision,
                  actorId: workspace.identity.ownerId,
                  approvedAt: DateTime.now().toUtc(),
                ),
              );
            }
            final before = workspace.database.exportDataArchive(
              workspace.identity.businessId,
              DateTime.utc(2026, 10, 8),
            );
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AccountingTheme.light(),
                  home: Scaffold(
                    body: JournalReviewPage(
                      workspace: workspace,
                      initialPosted: posted,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tap(tester, key('edit-journal-${draft.entry.id.value}'));
            for (final field in ['journal-debit-0', 'journal-credit-1']) {
              expect(
                tester.widget<TextField>(key(field)).controller!.text,
                displayed,
              );
            }
            for (final field in ['journal-credit-0', 'journal-debit-1']) {
              expect(
                tester.widget<TextField>(key(field)).controller!.text,
                isEmpty,
              );
            }
            await captureUi(
              tester,
              'Journal Saved Amount $currency $state ${width.toInt()}',
            );
            await tap(tester, key('journal-editor-close'));
            expect(find.text('Discard Unsaved Changes?'), findsNothing);
            expect(
              workspace.database.exportDataArchive(
                workspace.identity.businessId,
                DateTime.utc(2026, 10, 8),
              ),
              before,
            );
            expect(
              (await workspace.journals()).single.entry.lines.map(
                (line) => line.amount,
              ),
              [amount, amount],
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final width in [720.0, 1224.0]) {
    for (final (currency, zero, entered) in [
      ('MYR', '0.00', '123456789012.34'),
      ('JPY', '0', '123456789012'),
      ('KWD', '0.000', '123456789012.345'),
    ]) {
      testWidgets(
        'saved $currency Journal zero hints retain transaction growth and untouched dismissal at $width',
        (tester) async {
          await prepare(tester, width);
          installFixedPopoutHost(tester);
          final workspace = await openCurrencyFixture(currency);
          final before = workspace.database.exportDataArchive(
            workspace.identity.businessId,
            DateTime.utc(2026, 10, 6),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async => showJournalEditor(
                        context,
                        workspace,
                        await workspace.accounts(),
                      ),
                      child: const Text('Open Journal'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tap(tester, find.text('Open Journal'));
          final symbol = CurrencyPresentation.fromCode(currency).amountSymbol;
          final widths = <String, double>{};
          for (final name in ['debit', 'credit']) {
            final field = key('journal-$name-0');
            final input = tester.widget<TextField>(field);
            expect(input.controller!.text, isEmpty);
            expect(input.decoration!.hintText, zero);
            widths[name] = tester.getSize(field).width;
          }
          expect(find.text('Debit ($symbol)'), findsOneWidget);
          expect(find.text('Credit ($symbol)'), findsOneWidget);
          await captureUi(
            tester,
            'Saved $currency Journal Zero ${width.toInt()}',
          );
          await enterAccountingText(tester, key('journal-debit-0'), entered);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(key('journal-debit-0')).width,
            greaterThan(widths['debit']!),
          );
          expect(
            tester.getSize(key('journal-credit-0')).width,
            closeTo(widths['credit']!, .01),
          );
          await captureUi(
            tester,
            'Saved $currency Journal Growing Debit ${width.toInt()}',
          );
          await enterAccountingText(tester, key('journal-debit-0'), '');
          await tester.pumpAndSettle();
          await tap(tester, key('journal-editor-close'));
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          expect(
            workspace.database.exportDataArchive(
              workspace.identity.businessId,
              DateTime.utc(2026, 10, 6),
            ),
            before,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Journal fields preserve draft command and reject unstored facts at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final directory = Directory.systemTemp.createTempSync(
          'audyt-journal-fields-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());
        final cash = await workspace.createAccount(
          code: '1000',
          name: 'Cash',
          type: AccountType.asset,
        );
        final capital = await workspace.createAccount(
          code: '3000',
          name: 'Capital',
          type: AccountType.equity,
        );
        final png = Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async => showJournalEditor(
                      context,
                      workspace,
                      await workspace.accounts(),
                      onAttachmentsPick: (_) async => [
                        PickedExpenseAttachment(
                          name: 'Journal evidence.png',
                          mimeType: 'image/png',
                          bytes: png,
                        ),
                      ],
                    ),
                    child: const Text('New Journal'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tap(tester, find.text('New Journal'));
        final grid = tester.widget<AccountingTransactionGrid>(
          find.byType(AccountingTransactionGrid),
        );
        expect(grid.columns.map((column) => column.title), [
          'Account',
          'Debit (RM)',
          'Credit (RM)',
          'Description',
          'Name',
          'Tax',
        ]);
        expect(
          grid.columns[3].width,
          greaterThanOrEqualTo(
            AccountingTransactionGridTokens.descriptionMinimumWidth,
          ),
        );
        for (final column in ['name', 'tax']) {
          final selector = tester.widget<AccountingSelector<String?>>(
            find.ancestor(
              of: key('journal-$column-0'),
              matching: find.byType(AccountingSelector<String?>),
            ),
          );
          expect(selector.enabled, isFalse);
          expect(selector.options, isEmpty);
        }
        void expectEntireHeaderAndActionLaneVisible() {
          final body = tester.getRect(key('journal-editor-horizontal-scroll'));
          for (final name in [
            'journal-date',
            'journal-number',
            'add-journal-line',
          ]) {
            final field = tester.getRect(key(name));
            expect(field.left, greaterThanOrEqualTo(body.left - 0.01));
            expect(field.right, lessThanOrEqualTo(body.right + 0.01));
          }
        }

        expectEntireHeaderAndActionLaneVisible();
        void expectHeadingsWithinFieldEdges() {
          for (final column in ['Debit', 'Credit']) {
            final help = find.byWidgetPredicate(
              (widget) =>
                  widget is AccountingFieldHelp &&
                  widget.label == '$column (RM)',
            );
            final input = tester.getRect(
              key('journal-${column.toLowerCase()}-0'),
            );
            expect(tester.getRect(help).right, closeTo(input.right, 0.01));
          }
        }

        expectHeadingsWithinFieldEdges();
        final numericContext = tester.element(key('journal-debit-0'));
        final emptyWidths = <String, double>{};
        for (final column in ['Debit', 'Credit']) {
          final title = '$column (RM)';
          final expectedWidth = AccountingTransactionGridTokens.numericWidth(
            numericContext,
            'Amount',
            ['0.00'],
            title: title,
            guidance: grid.columns[column == 'Debit' ? 1 : 2].guidance,
          );
          emptyWidths[column] = expectedWidth;
          expect(
            tester.getSize(key('journal-${column.toLowerCase()}-0')).width,
            closeTo(expectedWidth, 0.01),
          );
          expect(
            expectedWidth,
            greaterThanOrEqualTo(
              AccountingTransactionGridTokens.fieldTitleWidth(
                numericContext,
                title,
              ),
            ),
          );
        }
        await tester.enterText(key('journal-debit-0'), '123456789012.34');
        await tester.pumpAndSettle();
        final grownAmountWidth = AccountingTransactionGridTokens.numericWidth(
          numericContext,
          'Amount',
          [tester.widget<TextField>(key('journal-debit-0')).controller!.text],
          title: 'Debit (RM)',
          guidance: grid.columns[1].guidance,
        );
        expect(
          tester.getSize(key('journal-debit-0')).width,
          closeTo(grownAmountWidth, 0.01),
        );
        expect(
          tester.getSize(key('journal-credit-0')).width,
          closeTo(emptyWidths['Credit']!, 0.01),
        );
        expectHeadingsWithinFieldEdges();
        await captureUi(tester, 'Journal Amount Token Growth ${width.toInt()}');
        await tester.enterText(key('journal-debit-0'), '');
        await tester.pumpAndSettle();
        expect(
          tester.getSize(key('journal-debit-0')).width,
          closeTo(emptyWidths['Debit']!, 0.01),
        );
        expect(
          tester.getSize(key('journal-description-0')).height,
          closeTo(tester.getSize(key('journal-debit-0')).height, 0.01),
        );
        await captureUi(tester, 'Journal Field Design Empty ${width.toInt()}');
        await tap(tester, key('add-journal-line'));
        expect(key('journal-description-2'), findsOneWidget);
        await enterAccountingText(
          tester,
          key('journal-description-2'),
          'Temporary line',
        );
        await tap(tester, key('remove-journal-line-2'));
        expect(key('journal-description-2'), findsNothing);
        AccountingSelector<EntityId?> selector(int row) => tester.widget(
          find.ancestor(
            of: key('journal-account-$row'),
            matching: find.byType(AccountingSelector<EntityId?>),
          ),
        );
        await tap(tester, key('journal-account-0'));
        await tap(tester, find.text('1000 · Cash').last);
        await tap(tester, key('journal-account-1'));
        await tap(tester, find.text('3000 · Capital').last);
        expect(selector(0).value, cash);
        expect(selector(1).value, capital);
        await tester.enterText(key('journal-debit-0'), '125.00');
        await tester.enterText(key('journal-credit-1'), '125.00');
        await enterAccountingText(
          tester,
          key('journal-memo'),
          'Retained balanced journal',
        );
        await tester.enterText(key('journal-number'), 'J-101');
        expectEntireHeaderAndActionLaneVisible();
        await tap(tester, key('save-journal-draft'));
        expect(await workspace.journals(), isEmpty);
        expect(find.textContaining('Journal number saving'), findsOneWidget);
        expect(
          tester.widget<TextField>(key('journal-number')).controller!.text,
          'J-101',
        );
        await captureUi(tester, 'Journal Number Save Guard ${width.toInt()}');
        await tester.enterText(key('journal-number'), '');
        await tester.pumpAndSettle();
        expect(find.textContaining('Journal number saving'), findsNothing);
        await enterAccountingText(
          tester,
          key('journal-description-0'),
          'Per-line explanation that wraps without expanding the fixed monetary columns.\nAdditional context.',
        );
        await tap(tester, key('save-journal-draft'));
        expect(await workspace.journals(), isEmpty);
        expect(
          find.textContaining('Per-line Description saving'),
          findsOneWidget,
        );
        expect(
          tester.getSize(key('journal-description-0')).height,
          greaterThan(tester.getSize(key('journal-debit-0')).height),
        );
        await captureUi(tester, 'Journal Wrapped Description ${width.toInt()}');
        await enterAccountingText(
          tester,
          key('journal-description-0'),
          'Retained line description',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(key('journal-keep-editing'), findsOneWidget);
        await captureUi(
          tester,
          'Journal Description Discard Guard ${width.toInt()}',
        );
        await tap(tester, key('journal-keep-editing'));
        expect(
          accountingDescriptionText('Retained line description'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(key('journal-debit-0')).controller!.text,
          '125.00',
        );
        await enterAccountingText(tester, key('journal-description-0'), '');
        await tap(tester, key('journal-choose-files'));
        expect(find.text('Journal evidence.png'), findsOneWidget);
        await captureUi(tester, 'Journal Staged File List ${width.toInt()}');
        await tap(tester, key('save-journal-draft'));
        expect(await workspace.journals(), isEmpty);
        expect(
          find.textContaining('Journal attachment saving'),
          findsOneWidget,
        );
        final view = find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains('journal-attachment-view-') ==
              true,
        );
        await tester.ensureVisible(view);
        await tester.pumpAndSettle();
        await tester.tap(view);
        await pumpDecodedAttachment(tester);
        expect(find.text('Journal evidence.png'), findsWidgets);
        await captureUi(
          tester,
          'Journal Original File Preview ${width.toInt()}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final remove = find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains('journal-attachment-remove-') ==
              true,
        );
        await tap(tester, remove);
        await tap(tester, find.text('Delete').last);
        expect(find.text('Journal evidence.png'), findsNothing);
        expect(find.textContaining('Journal attachment saving'), findsNothing);
        await captureUi(
          tester,
          'Journal Existing Command Ready ${width.toInt()}',
        );
        await tap(tester, key('save-journal-draft'));
        final saved = (await workspace.journals()).single;
        expect(saved.entry.memo, 'Retained balanced journal');
        expect(saved.entry.lines.map((line) => line.amount.toDecimalString()), [
          '125.00',
          '125.00',
        ]);
        final id = saved.entry.id;
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        final reopened = (await workspace.journals()).single;
        expect(reopened.entry.id, id);
        expect(reopened.entry.memo, saved.entry.memo);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
