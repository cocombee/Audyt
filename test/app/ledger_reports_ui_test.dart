import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/presentation/ledger_reports_page.dart';

void main() {
  testWidgets('reconciliation progress follows the selected imported statement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    final first = workspace.database
        .bankStatements(workspace.identity.businessId, 'demo-bank')
        .singleWhere((item) => item.filename == 'Demo Bank.csv');
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final second = workspace.database.importBankStatement(
      id: EntityId.random(),
      businessId: workspace.identity.businessId,
      paymentAccountId: 'demo-bank',
      importedAt: now,
      statement: BankStatementImport.csv(
        filename: 'Second.csv',
        currency: 'MYR',
        bytes: Uint8List.fromList(
          utf8.encode('Date,Description,Amount\n$date,Other Payment,1.00\n'),
        ),
      ),
    );
    final selected = ValueNotifier<String?>(first.id.value);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: LedgerReportsPage(
            workspace: workspace,
            compact: true,
            selectedStatementId: selected,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final field in ['report-from', 'report-through']) {
      final label = tester.getRect(find.byKey(ValueKey('$field-label')));
      final control = tester.getRect(find.byKey(ValueKey(field)));
      expect(control.top - label.bottom, closeTo(accountingFieldLabelGap, 0.1));
      expect(label.left, closeTo(control.left, 0.1));
    }
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-1'))).data,
      '0 of 4 · 0%',
    );
    expect(
      find.text(
        'Demo Bank.csv · Auto-linked 0 · Manually linked 0 · Unlinked 4',
      ),
      findsOneWidget,
    );
    final suggestions = workspace.database.statementMatchSuggestions(
      workspace.identity.businessId,
      first.id,
    );
    expect(suggestions, hasLength(4));
    final individuallyMatchable = suggestions
        .where((item) => item.candidates.isNotEmpty)
        .take(2)
        .toList();
    expect(individuallyMatchable, hasLength(2));
    for (final (index, suggestion) in individuallyMatchable.indexed) {
      final candidate = suggestion.candidates.first;
      workspace.database.acceptStatementMatch(
        businessId: workspace.identity.businessId,
        statementId: first.id,
        sourceRow: suggestion.row.sourceRow,
        journalId: candidate.journalId,
        lineIndex: candidate.lineIndex,
        actorId: workspace.identity.ownerId,
        acceptedAt: DateTime.now(),
        automatic: index == 0,
      );
    }
    workspace.refreshBankStatementReview();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-1'))).data,
      '2 of 4 · 50%',
    );
    expect(
      find.text(
        'Demo Bank.csv · Auto-linked 1 · Manually linked 1 · Unlinked 2',
      ),
      findsOneWidget,
    );
    final autoAcceptance = workspace.database.statementMatchAcceptanceId(
      workspace.identity.businessId,
      first.id,
      individuallyMatchable.first.row.sourceRow,
    );
    workspace.database.retractStatementMatch(
      businessId: workspace.identity.businessId,
      acceptanceId: autoAcceptance!,
      actorId: workspace.identity.ownerId,
      retractedAt: DateTime.now(),
      reason: 'Correcting an automatic link',
    );
    workspace.refreshBankStatementReview();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Demo Bank.csv · Auto-linked 0 · Manually linked 1 · Unlinked 3',
      ),
      findsOneWidget,
    );
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    selected.value = second.value;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-1'))).data,
      '0 of 1 · 0%',
    );
    expect(
      find.text('Second.csv · Auto-linked 0 · Manually linked 0 · Unlinked 1'),
      findsOneWidget,
    );
  });
  testWidgets('report totals use one bar, then two-by-two and single cards', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('report-summary-layout-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final (width, columns) in [(1600.0, 4), (960.0, 2), (390.0, 1)]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(
        AudytApp(initialPath: '/reports', workspace: workspace),
      );
      await tester.pumpAndSettle();
      final cards = [
        for (final title in [
          'Posted Journals',
          'Pending Drafts',
          'Accounts Tracked',
          'Needs Review',
        ])
          find.byKey(ValueKey('report-summary-card-$title')),
      ];
      if (columns == 4) {
        expect(
          find.byKey(const ValueKey('report-summary-strip')),
          findsOneWidget,
        );
        for (final card in cards) {
          expect(card, findsNothing);
        }
        for (final title in [
          'Posted Journals',
          'Pending Drafts',
          'Accounts Tracked',
          'Needs Review',
        ]) {
          final label = find
              .descendant(
                of: find.byKey(ValueKey('report-summary-$title')),
                matching: find.byType(Text),
              )
              .first;
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.descendant(of: label, matching: find.byType(RichText)),
                )
                .didExceedMaxLines,
            isFalse,
          );
          expect(tester.widget<Text>(label).maxLines, 1);
        }
      } else {
        expect(
          find.byKey(const ValueKey('report-summary-strip')),
          findsNothing,
        );
        for (final card in cards) {
          expect(card, findsOneWidget);
        }
        final tops = [for (final card in cards) tester.getRect(card).top];
        if (columns == 2) {
          expect(tops[0], tops[1]);
          expect(tops[2], tops[3]);
          expect(tops[2], greaterThan(tops[0]));
          for (final title in [
            'Posted Journals',
            'Pending Drafts',
            'Accounts Tracked',
            'Needs Review',
          ]) {
            expect(
              find.descendant(
                of: find.byKey(ValueKey('report-summary-$title')),
                matching: find.text(title),
              ),
              findsOneWidget,
            );
          }
        } else {
          for (var index = 1; index < tops.length; index++) {
            expect(tops[index], greaterThan(tops[index - 1]));
          }
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('report views connect behind the chart with aligned labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('report-view-layout-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(initialPath: '/reports', workspace: workspace),
    );
    await tester.pumpAndSettle();

    final quality = tester.getRect(
      find.byKey(const ValueKey('report-quality-card')),
    );
    final selector = tester.getRect(
      find.byKey(const ValueKey('report-view-selector')),
    );
    final firstTab = tester.getRect(find.byKey(const ValueKey('report-tab-0')));
    final ledgerTab = tester.getRect(
      find.byKey(const ValueKey('preview-tab-reports-0')),
    );
    final labelRects = [
      for (final label in ['Balance Sheet', 'Profit And Loss', 'Trial Balance'])
        tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('report-view-selector')),
            matching: find.text(label),
          ),
        ),
    ];
    expect(
      quality.right - selector.left,
      closeTo(accountingSectionRadius, 0.1),
    );
    expect(selector.top, closeTo(quality.top, 0.1));
    for (final label in labelRects) {
      expect(label.right, closeTo(labelRects.first.right, 0.1));
    }
    final longest = labelRects.reduce((a, b) => a.width > b.width ? a : b);
    final firstIcon = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('report-tab-0')),
        matching: find.byType(AccountingIcon),
      ),
    );
    expect(firstIcon.left - longest.right, closeTo(accountingContentInset, 1));
    expect(
      selector.right - firstIcon.right,
      closeTo(accountingContentInset, 1),
    );
    expect(firstTab.height, closeTo(44, 0.1));
    expect(firstTab.height, closeTo(ledgerTab.height, 0.1));
    expect(find.text('Report insight'), findsNothing);

    final indicator = find.byKey(const ValueKey('report-selector-indicator'));
    final greyBand = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byKey(const ValueKey('report-view-selector')),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      greyBand.borderRadius,
      const BorderRadius.only(
        topRight: Radius.circular(accountingControlRadius),
        bottomRight: Radius.circular(accountingControlRadius),
      ),
    );
    final bandPadding =
        tester
                .widget<TabBar>(
                  find.descendant(
                    of: find.byKey(const ValueKey('area-tabs-reports')),
                    matching: find.byType(TabBar),
                  ),
                )
                .padding
            as EdgeInsets;
    expect(bandPadding, const EdgeInsets.all(2));
    expect(tester.getRect(indicator).top - selector.top, 3);
    expect(selector.right - tester.getRect(indicator).right, 3);
    final selectedFill = tester.widget<AnimatedContainer>(
      find.descendant(of: indicator, matching: find.byType(AnimatedContainer)),
    );
    final fillDecoration = selectedFill.decoration! as BoxDecoration;
    expect(fillDecoration.border, isNull);
    expect(
      (fillDecoration.borderRadius! as BorderRadius).topRight,
      const Radius.circular(accountingControlRadius),
    );
    expect(
      (fillDecoration.borderRadius! as BorderRadius).bottomRight,
      const Radius.circular(accountingControlRadius),
    );
    final start = tester.getRect(indicator).top;
    await tester.tap(find.byKey(const ValueKey('report-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(indicator).top, greaterThan(start));
    expect(tester.getRect(indicator).top, lessThan(start + 44));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator).top, closeTo(start + 44, 0.1));
    await tester.tap(find.byKey(const ValueKey('report-tab-2')));
    await tester.pumpAndSettle();
    expect(selector.bottom - tester.getRect(indicator).bottom, 47);
    await tester.tap(find.byKey(const ValueKey('report-tab-3')));
    await tester.pumpAndSettle();
    expect(selector.bottom - tester.getRect(indicator).bottom, 3);
    expect(find.text('Sales By Category'), findsOneWidget);
  });

  testWidgets('report date control geometry', (tester) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('report-date-geometry-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(initialPath: '/reports', workspace: workspace),
    );
    await tester.pumpAndSettle();
    final from = find.byKey(const ValueKey('report-from'));
    final through = find.byKey(const ValueKey('report-through'));
    final editableFinder = find.descendant(
      of: from,
      matching: find.byType(EditableText),
    );
    final icon = find.descendant(
      of: from,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AccountingIcon &&
            widget.icon == Icons.calendar_today_outlined,
      ),
    );
    final frame = tester.getRect(from);
    expect(tester.widget<AccountingIcon>(icon).size, 13.6);
    expect(frame.width, accountingCompactDateFieldWidth);
    expect(tester.getRect(through).left - frame.right, 20);
    expect(tester.getRect(editableFinder).left - frame.left, 20);
    expect(frame.right - tester.getRect(icon).right, 20);
    expect(tester.widget<TextField>(from).enableInteractiveSelection, true);
    final calendar = tester.widget<IconButton>(
      find.byKey(const ValueKey('calendar-button-from')),
    );
    expect(calendar.tooltip, isNull);
    expect(
      calendar.style!.overlayColor!.resolve({WidgetState.hovered}),
      Colors.transparent,
    );
    final editable = tester.widget<EditableText>(editableFinder);
    final renderEditable = tester.renderObject<RenderEditable>(
      find.descendant(
        of: editableFinder,
        matching: find.byElementPredicate(
          (element) => element.renderObject is RenderEditable,
        ),
      ),
    );
    final end = renderEditable.localToGlobal(
      renderEditable
          .getLocalRectForCaret(
            TextPosition(offset: editable.controller.text.length),
          )
          .topLeft,
    );
    expect(tester.getRect(icon).left - end.dx, closeTo(26.4, 2));
  });
  testWidgets(
    'quality bars use the report palette and balanced visible insets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('report-quality-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        AudytApp(initialPath: '/reports', workspace: workspace),
      );
      await tester.pumpAndSettle();

      final colors = AccountingColorLibrary.chartSeries.take(3).toSet();
      final usedColors = <Color>{};
      for (final index in [0, 1, 2]) {
        final bar = tester.widget<AccountingProgressBar>(
          find.byKey(ValueKey('quality-progress-$index')),
        );
        expect(bar.color, isIn(colors));
        usedColors.add(bar.color);
        expect(bar.value, 0);
        expect(find.byKey(ValueKey('quality-value-$index')), findsOneWidget);
        expect(find.text('—'), findsWidgets);
      }
      expect(usedColors, hasLength(3));
      final card = tester.getRect(
        find.byKey(const ValueKey('report-quality-card')),
      );
      final title = tester.getRect(find.text('Quality measures'));
      final lastBar = tester.getRect(
        find.byKey(const ValueKey('quality-progress-2')),
      );
      expect(title.top - card.top, closeTo(16, 1.5));
      expect(card.bottom - lastBar.bottom, closeTo(20, 1.5));
    },
  );

  testWidgets('quality values follow records while report views share them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('report-quality-values-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/ledger.sqlite',
    );
    addTearDown(workspace.dispose);
    await workspace.createAccount(
      code: '1000',
      name: 'Bank',
      type: AccountType.asset,
    );
    await workspace.createAccount(
      code: '6000',
      name: 'Expenses',
      type: AccountType.expense,
    );
    final accounts = {
      for (final stored in await workspace.accounts())
        stored.account.code: stored.account.id,
    };
    await tester.pumpWidget(
      AudytApp(initialPath: '/reports', workspace: workspace),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-2'))).data,
      '—',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-summary-Accounts Tracked')),
        matching: find.text('2 Accounts'),
      ),
      findsOneWidget,
    );

    await workspace.saveJournal(
      date: DateTime.now(),
      memo: 'Quality measure review',
      lines: [
        JournalLine.debit(
          accountId: accounts['6000']!,
          amount: Money.fromMinor(10000, 'MYR'),
        ),
        JournalLine.credit(
          accountId: accounts['1000']!,
          amount: Money.fromMinor(10000, 'MYR'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-2'))).data,
      '0%',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-summary-Pending Drafts')),
        matching: find.text('1 Draft'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('report-tab-2')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-2'))).data,
      '0%',
    );

    final journal = (await workspace.journals()).single;
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: workspace.identity.businessId,
        journalId: journal.entry.id,
        expectedRevision: journal.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-2'))).data,
      '100%',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-summary-Posted Journals')),
        matching: find.text('1 Journal'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'failed report rolls back and allows subsequent writes and reads',
    () async {
      final dir = Directory.systemTemp.createTempSync('report-rollback-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await expectLater(
        workspace.report(
          from: DateTime.utc(2026, 10, 1),
          through: DateTime.utc(2026, 9, 1),
        ),
        throwsArgumentError,
      );
      await workspace.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      final report = await workspace.report(
        from: DateTime.utc(2026),
        through: DateTime.utc(2026, 9, 30),
      );
      expect(report.rows.single.account.name, 'Bank');
      expect(report.isBalanced, isTrue);
    },
  );
  testWidgets(
    'posted activity reconciles and drafts stay outside report totals',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('reports-values-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      for (final item in [
        (AccountType.asset, '1000', 'Bank'),
        (AccountType.income, '4000', 'Sales'),
        (AccountType.expense, '5000', 'Supplies'),
      ]) {
        await workspace.createAccount(
          code: item.$2,
          name: item.$3,
          type: item.$1,
        );
      }
      final accounts = await workspace.accounts();
      EntityId account(AccountType type) =>
          accounts.singleWhere((a) => a.account.type == type).account.id;
      Future<void> transaction(
        String memo,
        DateTime date,
        AccountType debit,
        AccountType credit,
        int amount, {
        bool post = true,
      }) async {
        await workspace.saveJournal(
          date: date,
          memo: memo,
          lines: [
            JournalLine.debit(
              accountId: account(debit),
              amount: Money.fromMinor(amount, 'MYR'),
            ),
            JournalLine.credit(
              accountId: account(credit),
              amount: Money.fromMinor(amount, 'MYR'),
            ),
          ],
        );
        if (post) {
          final record = (await workspace.journals()).singleWhere(
            (r) => r.entry.memo == memo,
          );
          await workspace.approveJournal(
            JournalApproval(
              requestId: EntityId.random(),
              businessId: workspace.identity.businessId,
              journalId: record.entry.id,
              expectedRevision: record.metadata.revision,
              actorId: workspace.identity.ownerId,
              approvedAt: DateTime.now().toUtc(),
            ),
          );
        }
      }

      await transaction(
        'Sale',
        DateTime.utc(2026, 8, 1),
        AccountType.asset,
        AccountType.income,
        10000,
      );
      await transaction(
        'Supplies',
        DateTime.utc(2026, 9, 1),
        AccountType.expense,
        AccountType.asset,
        3000,
      );
      await transaction(
        'Unapproved',
        DateTime.utc(2026, 9, 2),
        AccountType.expense,
        AccountType.asset,
        5000,
        post: false,
      );
      await tester.pumpWidget(
        AudytApp(initialPath: '/reports', workspace: workspace),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Choose From'), findsNothing);
      expect(find.byTooltip('Choose Through'), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-button-from')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-button-through')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-button-from')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('audyt-year-selector')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audyt-date-close')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('report-from')),
        '01-09-2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('report-through')),
        '30-09-2026',
      );
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      void row(String label, String amount) {
        final owner = find
            .ancestor(of: find.text(label).last, matching: find.byType(Row))
            .first;
        expect(
          find.descendant(of: owner, matching: find.text(amount)),
          findsOneWidget,
        );
      }

      expect(
        find.textContaining('2 posted journals · 1 pending drafts'),
        findsOneWidget,
      );
      row('Assets', 'RM 70.00');
      row('1000 · Bank', 'RM 70.00');
      row('Total Equity', 'RM 70.00');
      row('Balance Sheet Difference', 'RM 0.00');
      // Editing controls does not change the already applied snapshot.
      await tester.enterText(
        find.byKey(const ValueKey('report-from')),
        '01-08-2026',
      );
      await tester.tap(
        find.byKey(
          ValueKey('report-account-${account(AccountType.asset).value}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account Activity'), findsOneWidget);
      row('Opening Net Debit', 'RM 100.00');
      final activity = tester.widget<AccountingInformationRows>(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.byType(AccountingInformationRows),
        ),
      );
      expect(activity.rows, contains(('Credit', 'RM 30.00')));
      row('Ending Net Debit', 'RM 70.00');
      expect(activity.rows, contains(('Date', '01-09-2026')));
      expect(activity.rows, contains(('Memo', 'Supplies')));
      expect(activity.rows, isNot(contains(('Memo', 'Sale'))));
      expect(find.textContaining('Unapproved'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is AccountingCloseIcon).last,
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('report-tab-1')));

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('report-tab-1')));
      await tester.pumpAndSettle();
      row('Revenue', 'RM 0.00');
      row('Expenses', 'RM 30.00');
      row('5000 · Supplies', 'RM 30.00');
      row('Period Profit', '-RM 30.00');
      await tester.tap(
        find.byKey(
          ValueKey('report-account-${account(AccountType.expense).value}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opening Net Debit'), findsNothing);
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.descendant(
                of: find.byType(AlertDialog).last,
                matching: find.byType(AccountingInformationRows),
              ),
            )
            .rows,
        contains(('Debit', 'RM 30.00')),
      );
      row('Operating Net Debit', 'RM 30.00');
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('report-from')),
        '01-08-2026',
      );
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      row('Period Profit', 'RM 70.00');
      row('4000 · Sales', 'RM 100.00');
      await tester.ensureVisible(find.byKey(const ValueKey('report-tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-tab-2')));
      await tester.pumpAndSettle();
      row('Total Debits', 'RM 100.00');
      row('Total Credits', 'RM 100.00');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'reports route renders ledger views and validates dates at $width',
      (tester) async {
        await loadJournalLayoutFonts();
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final dir = Directory.systemTemp.createTempSync('reports-ui-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final workspace = await AccountingWorkspace.open(
          '${dir.path}/ledger.sqlite',
        );
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(initialPath: '/reports', workspace: workspace),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Balance Sheet Difference'), findsOneWidget);
        expect(find.textContaining('0 posted journals'), findsOneWidget);
        expectHeaderPrimaryAction(tester, 'run-report');
        await captureUi(tester, 'Reports Title Action ${width.toInt()}');
        await tester.ensureVisible(find.byKey(const ValueKey('report-tab-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('Period Profit'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('report-tab-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-tab-2')));
        await tester.pumpAndSettle();
        expect(find.text('Total Debits'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('report-from')),
          '31-02-2026',
        );
        await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('run-report')));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter valid dates with the start on or before the end.'),
          findsOneWidget,
        );
        expect(find.text('Total Debits'), findsOneWidget);
        expect(find.text('Total Credits'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('report-error-notice')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
