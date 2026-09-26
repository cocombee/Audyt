import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('Settings saves preserve the applied report range at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final root = Directory.systemTemp.createTempSync('audyt-applied-report-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/ledger.sqlite';
      var workspace = await createDemoWorkspace(databasePath: path);
      addTearDown(() => workspace.dispose());
      final now = DateTime.now();
      final from = DateTime(now.year);
      final through = DateTime(now.year, now.month, now.day);
      final initial = await workspace.report(from: from, through: through);
      expect(initial.periodProfit, isNot(BigInt.zero));
      Future<void> mount() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: workspace,
                initialPath: '/reports',
                showInitialSetup: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Finder profit() => find.byWidgetPredicate(
        (w) => w is AccountingTotalRow && w.label == 'Period Profit',
      );
      Future<void> showProfit() =>
          tap(find.byKey(const ValueKey('report-tab-1')));
      String period(DateTime a, DateTime b) =>
          'Report period: ${formatAccountingInputDate(a)} – ${formatAccountingInputDate(b)}';
      Future<void> settings(String message) async {
        await tap(find.byKey(const ValueKey('accounting-settings')));
        await tap(find.text('Sales Preferences').first);
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Customer Message')),
          message,
        );
        await tap(find.byKey(const ValueKey('design-save-settings')));
        expect(
          workspace.preferences.text('Sales Preferences', 'Customer Message'),
          message,
        );
        await tap(
          find
              .byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Close',
              )
              .last,
        );
      }

      await mount();
      await showProfit();
      final initialProfit = tester.widget<AccountingTotalRow>(profit()).value;
      final recordsBefore = tables(workspace);
      final nextFrom = DateTime(now.year + 1);
      final nextThrough = DateTime(now.year + 1, 1, 31);
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('report-from')),
        formatAccountingInputDate(nextFrom),
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('report-through')),
        formatAccountingInputDate(nextThrough),
      );
      await settings('Report range stays applied until Run Report');
      expect(find.text(period(from, through)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, initialProfit);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report-from')))
            .controller!
            .text,
        formatAccountingInputDate(nextFrom),
      );
      for (final name in recordsBefore.keys.where(
        (n) => !{'company_preferences', 'ledger_audit'}.contains(n),
      )) {
        expect(tables(workspace)[name], recordsBefore[name], reason: name);
      }
      await captureUi(
        tester,
        'Report Draft Range After Settings ${width.toInt()}',
      );
      final accounts = {
        for (final record in await workspace.accounts())
          record.account.code: record.account.id,
      };
      await workspace.saveJournal(
        date: through,
        memo: 'Applied report data update',
        lines: [
          JournalLine.debit(
            accountId: accounts['6000']!,
            amount: Money.fromMinor(1250, 'MYR'),
          ),
          JournalLine.credit(
            accountId: accounts['1000']!,
            amount: Money.fromMinor(1250, 'MYR'),
          ),
        ],
      );
      final draft = (await workspace.journals()).singleWhere(
        (r) => r.entry.memo == 'Applied report data update',
      );
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
      await tester.pumpAndSettle();
      final updated = await workspace.report(from: from, through: through);
      expect(updated.periodProfit, initial.periodProfit - BigInt.from(1250));
      expect(updated.isBalanced, isTrue);
      expect(
        updated.postedJournalIds.length,
        initial.postedJournalIds.length + 1,
      );
      final updatedProfit = formatAccountingMoney(
        tester.element(profit()),
        Money.fromMinor(updated.periodProfit.toInt(), 'MYR'),
      );
      expect(find.text(period(from, through)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, updatedProfit);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report-from')))
            .controller!
            .text,
        formatAccountingInputDate(nextFrom),
      );
      await captureUi(
        tester,
        'Report Posted Update With Draft Range ${width.toInt()}',
      );

      await tap(find.byKey(const ValueKey('run-report')));
      expect(find.text(period(nextFrom, nextThrough)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, 'RM 0.00');
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('report-from')),
        '31-02-${now.year + 1}',
      );
      await settings('Invalid draft also stays separate');
      expect(find.text(period(nextFrom, nextThrough)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, 'RM 0.00');
      await tap(find.byKey(const ValueKey('run-report')));
      expect(
        find.text('Enter valid dates with the start on or before the end.'),
        findsOneWidget,
      );
      expect(find.text(period(nextFrom, nextThrough)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, 'RM 0.00');
      await settings('Invalid range remains visible after refresh');
      expect(
        find.text('Enter valid dates with the start on or before the end.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('report-error-notice')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-error-notice')),
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Report Invalid Range ${width.toInt()}');
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('report-from')),
        formatAccountingInputDate(from),
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('report-through')),
        formatAccountingInputDate(through),
      );
      await tap(find.byKey(const ValueKey('run-report')));
      expect(tester.widget<AccountingTotalRow>(profit()).value, updatedProfit);
      final saved = tables(workspace);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(tables(workspace), saved);
      final reopened = await workspace.report(from: from, through: through);
      expect(reopened.periodProfit, updated.periodProfit);
      expect(reopened.balanceSheetDifference, BigInt.zero);
      expect(reopened.isBalanced, isTrue);
      await mount();
      await showProfit();
      expect(find.text(period(from, through)), findsOneWidget);
      expect(tester.widget<AccountingTotalRow>(profit()).value, updatedProfit);
      await captureUi(tester, 'Report Reopened Range ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
