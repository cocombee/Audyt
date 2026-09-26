import '../support/accounting_text_input.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Future<void> view(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<Color> paintedFill(WidgetTester tester, Finder finder) async {
  final rect = tester.getRect(finder);
  final point = Offset(rect.left + 5, rect.center.dy);
  late Color result;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
    result = Color.fromARGB(
      data!.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
    image.dispose();
  });
  return result;
}

Finder iconFor(String group) => find.descendant(
  of: find.byKey(ValueKey(group)),
  matching: find.byType(AccountingMetricIconBox),
);

int countFor(WidgetTester tester, String group) => int.parse(
  tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(group)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .firstWhere((s) => RegExp(r'^\d+ ').hasMatch(s))
      .split(' ')
      .first,
);

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('Home review hover matches primary button at $width', (
      tester,
    ) async {
      await view(tester, width);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: AccountingHomePage(
                data: AccountingHomeData.empty(currencyCode: 'MYR'),
                reviewCount: 3,
                onNeedsReview: () {},
                onRecordExpense: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final primary = find.widgetWithText(FilledButton, 'Record Expense').first;
      final metric = iconFor('home-kpi-Needs Review');
      expect(primary, findsOneWidget);
      final idle = await paintedFill(tester, metric);
      expect(idle, await paintedFill(tester, primary));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(primary));
      await tester.pumpAndSettle();
      final reference = await paintedFill(tester, primary);
      expect(reference.computeLuminance(), lessThan(idle.computeLuminance()));
      await mouse.moveTo(tester.getCenter(metric));
      await tester.pumpAndSettle();
      expect(await paintedFill(tester, metric), reference);
      await captureUi(tester, 'Home Review Shared Hover ${width.toInt()}');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });

    testWidgets('all report summaries navigate real restored data at $width', (
      tester,
    ) async {
      await view(tester, width);
      final root = Directory.systemTemp.createTempSync('summary-navigation-');
      addTearDown(() => root.deleteSync(recursive: true));
      final originalPath = '${root.path}/original.sqlite';
      var w = await createDemoWorkspace(databasePath: originalPath);
      final accounts = {
        for (final r in await w.accounts()) r.account.code: r.account.id,
      };
      Future<void> draft(String memo, DateTime date) => w.saveJournal(
        date: date,
        memo: memo,
        lines: [
          JournalLine.debit(
            accountId: accounts['6000']!,
            amount: Money.fromMinor(123, 'MYR'),
          ),
          JournalLine.credit(
            accountId: accounts['1000']!,
            amount: Money.fromMinor(123, 'MYR'),
          ),
        ],
      );
      final now = DateTime.now();
      await draft(
        'Prior year posted summary',
        DateTime.utc(now.year - 1, 1, 1),
      );
      final older = (await w.journals()).singleWhere(
        (j) => j.entry.memo == 'Prior year posted summary',
      );
      await w.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: older.entry.id,
          expectedRevision: older.metadata.revision,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.now().toUtc(),
        ),
      );
      await draft(
        'Prior year pending summary',
        DateTime.utc(now.year - 1, 1, 2),
      );
      await draft('Future pending summary', DateTime.utc(now.year + 1, 1, 1));
      final before = tables(w);
      w.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final restoredPath = '${root.path}/restored.sqlite';
      File(originalPath).copySync(restoredPath);
      w = await AccountingWorkspace.open(restoredPath);
      addTearDown(() => w.dispose());
      Future<void> reports() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(initialPath: '/reports', workspace: w),
          ),
        );
        await tester.pumpAndSettle();
      }

      await reports();
      final expectedPosted = countFor(tester, 'report-summary-Posted Journals');
      final expectedDrafts = countFor(tester, 'report-summary-Pending Drafts');
      final expectedAccounts = countFor(
        tester,
        'report-summary-Accounts Tracked',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final label in [
        'Posted Journals',
        'Pending Drafts',
        'Accounts Tracked',
        'Needs Review',
      ]) {
        final icon = iconFor('report-summary-$label');
        await tester.ensureVisible(icon);
        await tester.pumpAndSettle();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        final idle = await paintedFill(tester, icon);
        await mouse.moveTo(tester.getCenter(icon));
        await tester.pumpAndSettle();
        final hovered = await paintedFill(tester, icon);
        expect(
          hovered.computeLuminance(),
          lessThan(idle.computeLuminance()),
          reason: label,
        );
        // Black shading keeps each semantic colour rather than using green/white.
        expect(hovered.r / idle.r, closeTo(.96, .02), reason: label);
        expect(hovered.g / idle.g, closeTo(.96, .02), reason: label);
        expect(hovered.b / idle.b, closeTo(.96, .02), reason: label);
        await captureUi(tester, 'Report Summary Hover $label ${width.toInt()}');
      }
      await mouse.removePointer();
      await tester.ensureVisible(iconFor('report-summary-Posted Journals'));
      await tester.pumpAndSettle();
      await tester.tap(iconFor('report-summary-Posted Journals'));
      await tester.pumpAndSettle();
      expect(find.byType(JournalReviewPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('journal-summary-through')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (v) =>
              v.key is ValueKey<String> &&
              (v.key as ValueKey<String>).value.startsWith('review-journal-'),
        ),
        findsNWidgets(expectedPosted.clamp(0, 5)),
      );
      expect(find.text('1–5 of $expectedPosted'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('journal-search')),
        'Prior year posted',
      );
      await tester.pumpAndSettle();
      expect(find.text('Prior year posted summary'), findsOneWidget);
      expect(find.text('Future pending summary'), findsNothing);
      await captureUi(
        tester,
        'Report Posted Summary Destination ${width.toInt()}',
      );
      await reports();
      final pendingText = find.descendant(
        of: find.byKey(const ValueKey('report-summary-Pending Drafts')),
        matching: find.byType(AccountingMetricTextGroup),
      );
      await tester.ensureVisible(pendingText);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: pendingText, matching: find.byType(Text)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(JournalReviewPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (v) =>
              v.key is ValueKey<String> &&
              (v.key as ValueKey<String>).value.startsWith('review-journal-'),
        ),
        findsNWidgets(expectedDrafts),
      );
      expect(find.text('Prior year pending summary'), findsOneWidget);
      expect(find.text('Future pending summary'), findsNothing);
      await captureUi(
        tester,
        'Report Pending Summary Destination ${width.toInt()}',
      );
      await tester.tap(
        find.byKey(const ValueKey('clear-journal-summary-filter')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Future pending summary'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('journal-summary-through')),
        findsNothing,
      );
      await reports();
      await tester.tap(iconFor('report-summary-Accounts Tracked'));
      await tester.pumpAndSettle();
      expect(find.byType(ChartOfAccountsPage), findsOneWidget);
      expect(await w.accounts(), hasLength(expectedAccounts));
      await reports();
      await tester.tap(iconFor('report-summary-Needs Review'));
      await tester.pumpAndSettle();
      await revealAccountingRecord(
        tester,
        find.byKey(const ValueKey('review-queue-journals')),
      );
      expect(
        find.byKey(const ValueKey('review-queue-journals')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-review-journals')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-review-journals')));
      await tester.pumpAndSettle();
      expect(find.byType(JournalReviewPage), findsOneWidget);
      expect(find.text('Future pending summary'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('journal-summary-through')),
        findsNothing,
      );
      expect(
        tables(w),
        before,
        reason: 'Navigation and hover must not write accounting data.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      w.dispose();
      w = await AccountingWorkspace.open(restoredPath);
      expect(tables(w), before);
      expect(File(originalPath).readAsBytesSync(), originalBytes);
      expect(tester.takeException(), isNull);
    });
  }
}
