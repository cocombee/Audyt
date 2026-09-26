import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/naming_setup.dart' show namingSettingsChannel;
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/payables_ageing_page.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/app/accounting_theme.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show billFixture;
import '../features/accounting/data/bill_settlement_test.dart'
    show settlementFixture, allocation;
import '../support/accounting_test_finders.dart';
import 'summary_action_wiring_test.dart' show view;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  testWidgets(
    'failed reads clear stale totals and changing company resets the report',
    (tester) async {
      await view(tester, 720);
      final root = Directory.systemTemp.createTempSync(
        'audyt-payables-report-state-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/first.sqlite';
      final (first, ids, _, payable) = await settlementFixture(path);
      final second = await AccountingWorkspace.open(
        '${root.path}/second.sqlite',
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget screen(AccountingWorkspace w) => MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: PayablesAgeingPage(workspace: w)),
      );
      await tester.pumpWidget(screen(first));
      await tester.pumpAndSettle();
      final date = find.byKey(const ValueKey('payables-ageing-date'));
      await tester.enterText(date, '31-12-2026');
      await tester.tap(find.byKey(const ValueKey('run-payables-ageing')));
      await tester.pumpAndSettle();
      expect(find.text('RM 302.40'), findsWidgets);
      final sql = sqlite3.open(path);
      addTearDown(sql.dispose);
      final journal = first.database
          .readBillPosting(first.identity.businessId, ids.first)!
          .journalId;
      sql.execute("UPDATE journal_entries SET deleted_at=? WHERE id=?", [
        DateTime.utc(2027).toIso8601String(),
        journal.value,
      ]);
      first.savePreferences(
        first.preferences.change('Default Accounts', {
          'Payables Account': payable.value,
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payables-ageing-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payables-ageing-summary')),
        findsNothing,
      );
      expect(find.text('RM 302.40'), findsNothing);
      await tester.pumpWidget(screen(second));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payables-ageing-error')), findsNothing);
      expect(
        find.text('No outstanding posted Bills for this date.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(date).controller!.text,
        isNot('31-12-2026'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Reports route preserves applied date, pages, views and recovered sources at $width',
      (tester) async {
        await view(tester, width);
        final root = Directory.systemTemp.createTempSync(
          'audyt-payables-report-ui-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final (source, ids, _, payable) = await settlementFixture(
          '${root.path}/source.sqlite',
        );
        final first = source.database.readBillDraft(
          source.identity.businessId,
          ids.first,
        )!;
        for (var i = 0; i < 9; i++) {
          final b = billFixture(
            source,
            first.vendorSnapshot,
            first.lines.first.categoryId!,
          );
          source.saveBillDraft(b, expectedRevision: 0);
          source.postBill(
            requestId: EntityId.random(),
            billId: b.id,
            expectedRevision: 1,
            payableAccountId: payable,
            approvedAt: DateTime.utc(2026, 9, 28, 1),
          );
        }
        source.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(ids[1], 15120, 120)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'Fictional year-end',
          paidOn: DateTime.utc(2026, 12, 31),
          approvedAt: DateTime.utc(2027, 1, 2),
        );
        source.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(ids[0], 15120, 15120)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'Fictional next-year',
          paidOn: DateTime.utc(2027, 1, 1),
          approvedAt: DateTime.utc(2027, 1, 2, 1),
        );
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.utc(2027, 1, 3),
        );
        final before = tables(source);
        source.dispose();
        final w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restore.sqlite',
          archive,
        );
        addTearDown(w.dispose);
        expect(tables(w), before);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: w),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('navigation-item-reports')));
        await tester.pumpAndSettle();
        final tabs = tester.widget<AccountingTabs>(
          find.byKey(const ValueKey('area-tabs-reports')),
        );
        final index = tabs.labels.indexOf('Payables Ageing');
        expect(index, greaterThanOrEqualTo(0));
        final tab = find.byKey(ValueKey('preview-tab-reports-$index'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.byType(PayablesAgeingPage), findsOneWidget);
        final date = find.byKey(const ValueKey('payables-ageing-date'));
        final run = find.byKey(const ValueKey('run-payables-ageing'));
        Future<void> apply(String value) async {
          await tester.ensureVisible(date);
          await tester.pumpAndSettle();
          await tester.enterText(date, value);
          await tester.ensureVisible(run);
          await tester.pumpAndSettle();
          await tester.tap(run);
          await tester.pumpAndSettle();
        }

        await tester.tap(find.byKey(const ValueKey('calendar-button-as-of')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('audyt-year-selector')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('audyt-date-close')));
        await tester.pumpAndSettle();
        await apply('31-12-2026');
        expect(find.text('As of 31-12-2026'), findsOneWidget);
        expect(find.text('RM 1,662.00'), findsWidgets);
        expect(find.text('RM 0.00'), findsWidgets);
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        Scrollable.of(tester.element(date)).position.jumpTo(0);
        await tester.pumpAndSettle();
        expectHeaderPrimaryAction(tester, 'run-payables-ageing');
        await captureUi(tester, 'Payables Ageing Summary ${width.toInt()}');
        // Merely changing the field, then refreshing actual Settings, keeps the
        // last successful report date rather than silently applying typed input.
        await tester.enterText(date, '01-01-2027');
        expect(tables(w), before);
        w.savePreferences(
          w.preferences.change('Default Accounts', {
            'Payables Account': payable.value,
          }),
        );
        final afterSettings = tables(w);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(date).controller!.text, '01-01-2027');
        expect(find.text('As of 31-12-2026'), findsOneWidget);
        await apply('31-02-2027');
        expect(find.text('Enter a valid date.'), findsOneWidget);
        expect(find.text('As of 31-12-2026'), findsOneWidget);
        await apply('31-12-2026');
        final next = find.byKey(const ValueKey('payables-ageing-page-next'));
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('6–10 of 11'), findsOneWidget);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('11–11 of 11'), findsOneWidget);
        final previous = find.byKey(
          const ValueKey('payables-ageing-page-previous'),
        );
        await tester.tap(previous);
        await tester.pumpAndSettle();
        expect(find.text('6–10 of 11'), findsOneWidget);
        final report = w.database.payablesAgeing(
          businessId: w.identity.businessId,
          currency: 'MYR',
          asOf: DateTime.utc(2026, 12, 31),
          offset: 5,
        );
        final record = report.records.first;
        final eye = find.byKey(
          ValueKey('view-payables-ageing-${record.posting.source.id}'),
        );
        await tester.ensureVisible(eye);
        await tester.pumpAndSettle();
        await captureUi(tester, 'Payables Ageing Rows ${width.toInt()}');
        await tester.tap(eye);
        await tester.pumpAndSettle();
        expect(find.text('View Payable Balance'), findsOneWidget);
        expect(find.byType(AccountingInformationRows), findsOneWidget);
        await captureUi(tester, 'Payable Balance View ${width.toInt()}');
        await tester.ensureVisible(find.text(record.posting.journalId.value));
        await tester.pumpAndSettle();
        expect(find.text(record.posting.journalId.value), findsOneWidget);
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        final attachmentEye = find.byKey(
          ValueKey(
            'ageing-attachment-${record.posting.source.id}-${record.posting.source.attachments.first.originalId}',
          ),
        );
        await tester.ensureVisible(attachmentEye);
        await tester.pumpAndSettle();
        await tester.tap(attachmentEye);
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        expect(
          find.text(
            'Unable to preview this file. It may be unavailable, damaged, or password protected.',
          ),
          findsOneWidget,
        );
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentPreviewDialog), findsNothing);

        await tester.tap(accountingCloseIcon());
        await tester.pumpAndSettle();
        expect(find.text('View Payable Balance'), findsNothing);
        Future<void> rows(String size) async {
          final selector = find.byKey(
            const ValueKey('payables-ageing-page-size'),
          );
          await tester.ensureVisible(selector);
          await tester.pumpAndSettle();
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.text(size).last);
          await tester.pumpAndSettle();
        }

        await rows('10');
        expect(find.text('1–10 of 11'), findsOneWidget);
        await rows('5');
        expect(find.text('1–5 of 11'), findsOneWidget);

        await apply('01-01-2027');
        expect(find.text('RM 1,510.80'), findsWidgets);
        await apply('31-08-2026');
        expect(
          find.text('No outstanding posted Bills for this date.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // The only write was the deliberately exercised default-setting command.
        expect(tables(w), afterSettings);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
