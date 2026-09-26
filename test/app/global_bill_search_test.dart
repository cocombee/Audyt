import 'dart:io';

import 'package:audyt/app/accounting_global_search.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/application/restored_workspaces.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show billFixture, setupBill;
import '../features/accounting/data/bill_posting_test.dart' show payableAccount;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  Future<(AccountingWorkspace, String, String, String)> company({
    String marker = '',
  }) async {
    final root = Directory.systemTemp.createTempSync('audyt-global-bill-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/books.sqlite';
    final workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    final (vendor, expense) = await setupBill(workspace);
    final payable = await payableAccount(workspace);
    final draft = billFixture(
      workspace,
      vendor,
      expense.account.id,
      memo: '$marker Draft printer paper',
    );
    workspace.saveBillDraft(draft, expectedRevision: 0);
    final posted = billFixture(
      workspace,
      vendor,
      expense.account.id,
      memo: '$marker Posted printer ink',
    );
    workspace.saveBillDraft(posted, expectedRevision: 0);
    workspace.postBill(
      requestId: EntityId.random(),
      billId: posted.id,
      expectedRevision: 1,
      payableAccountId: payable.account.id,
      approvedAt: DateTime.utc(2026, 9, 28, 2),
    );
    for (var index = 0; index < 12; index++) {
      final other = billFixture(
        workspace,
        vendor,
        expense.account.id,
        memo: 'Other office supply $index',
      );
      workspace.saveBillDraft(other, expectedRevision: 0);
    }
    if (marker.isNotEmpty) {
      await workspace.createAccount(
        code: '5101',
        name: '$marker Account',
        type: AccountType.expense,
      );
      await workspace.saveJournal(
        date: DateTime.utc(2026, 9, 28),
        memo: '$marker Journal',
        lines: [
          JournalLine.debit(
            accountId: expense.account.id,
            amount: Money.fromMinor(100, 'MYR'),
          ),
          JournalLine.credit(
            accountId: payable.account.id,
            amount: Money.fromMinor(100, 'MYR'),
          ),
        ],
      );
    }
    return (workspace, draft.documentNumber, posted.documentNumber, path);
  }

  test(
    'global Bill search is company scoped, typed, bounded and read only',
    () async {
      final (workspace, draftNumber, postedNumber, _) = await company();
      final before = tables(workspace);
      final draft = searchBillResults(
        workspace: workspace,
        query: 'bill draft printer paper',
      );
      expect(draft.map((item) => item.title), [draftNumber]);
      expect(draft.single.type, 'Bill Draft');
      expect(draft.single.tab, 'Bills');
      final posted = searchBillResults(
        workspace: workspace,
        query: 'bill printer ink',
      );
      expect(posted.map((item) => item.title), [postedNumber]);
      expect(posted.single.type, 'Bill');
      expect(
        searchBillResults(workspace: workspace, query: 'SUP-001', limit: 1),
        hasLength(1),
      );
      expect(
        workspace.database.searchBillDrafts(
          businessId: EntityId.random(),
          query: 'bill',
        ),
        isEmpty,
      );
      expect(tables(workspace), before);
    },
  );

  testWidgets('replacing the active workspace clears old search suggestions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1224, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (alpha, _, _, _) = await company(marker: 'AlphaOnly');
    final (beta, _, _, _) = await company(marker: 'BetaOnly');
    await tester.pumpWidget(AudytApp(workspace: alpha));
    await tester.pumpAndSettle();
    Future<void> search(String value) async {
      await tester.enterText(
        find.byKey(const ValueKey('global-search-field')),
        value,
      );
      await tester.pumpAndSettle();
    }

    await search('AlphaOnly Account');
    expect(find.widgetWithText(ListTile, 'AlphaOnly Account'), findsOneWidget);
    await tester.pumpWidget(AudytApp(workspace: beta));
    await tester.pumpAndSettle();
    await search('AlphaOnly Account');
    expect(find.widgetWithText(ListTile, 'AlphaOnly Account'), findsNothing);
    await search('BetaOnly Account');
    expect(find.widgetWithText(ListTile, 'BetaOnly Account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('global Bill suggestion opens Bills at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (workspace, _, postedNumber, _) = await company();
      final before = tables(workspace);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(
            workspace: workspace,
            showInitialSetup: false,
            initialPath: '/home',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('global-search-field')),
        postedNumber,
      );
      await tester.pumpAndSettle();
      final result = find.widgetWithText(ListTile, postedNumber);
      expect(result, findsOneWidget);
      await captureUi(tester, 'Global Bill Search Popup ${width.toInt()}');
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(find.byType(BillsPage), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('bill-search')))
            .controller!
            .text,
        postedNumber,
      );
      expect(find.text(postedNumber), findsWidgets);
      await captureUi(tester, 'Global Bill Search Result ${width.toInt()}');
      expect(tables(workspace), before);
    });

    testWidgets(
      'company switch keeps Bill searches within each company at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (alpha, _, alphaNumber, _) = await company(marker: 'AlphaOnly');
        final (beta, _, betaNumber, betaPath) = await company(
          marker: 'BetaOnly',
        );
        final alphaTables = tables(alpha), betaTables = tables(beta);
        expect(alpha.identity.businessId, isNot(beta.identity.businessId));
        final restoredId = EntityId.random().value;
        final entry = <String, Object?>{
          'id': restoredId,
          'businessId': beta.identity.businessId.value,
          'name': 'Beta Company',
          'path': betaPath,
          'createdAt': DateTime.utc(2026, 9, 28).toIso8601String(),
          'available': true,
        };
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(RestoredWorkspaces.channel, (call) async {
              switch (call.method) {
                case 'listRestoredWorkspaces':
                  return {
                    'workspaces': [entry],
                    'issues': 0,
                  };
                case 'restoredWorkspace':
                  return entry;
                default:
                  throw MissingPluginException();
              }
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(RestoredWorkspaces.channel, null),
        );
        await tester.pumpWidget(AudytApp(workspace: alpha));
        await tester.pumpAndSettle();
        Future<void> search(String value) async {
          await tester.enterText(
            find.byKey(const ValueKey('global-search-field')),
            value,
          );
          await tester.pumpAndSettle();
        }

        await search('AlphaOnly');
        expect(find.widgetWithText(ListTile, alphaNumber), findsOneWidget);
        await search('AlphaOnly Account');
        expect(
          find.widgetWithText(ListTile, 'AlphaOnly Account'),
          findsOneWidget,
        );
        await search('AlphaOnly Journal');
        expect(
          find.widgetWithText(ListTile, 'AlphaOnly Journal'),
          findsOneWidget,
        );
        await search('BetaOnly');
        expect(find.widgetWithText(ListTile, betaNumber), findsNothing);
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('company-option-restored-$restoredId')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AccountingShell>(find.byType(AccountingShell))
              .workspace!
              .identity
              .businessId,
          beta.identity.businessId,
        );
        await search('AlphaOnly');
        expect(find.widgetWithText(ListTile, alphaNumber), findsNothing);
        await search('AlphaOnly Account');
        expect(
          find.widgetWithText(ListTile, 'AlphaOnly Account'),
          findsNothing,
        );
        await search('AlphaOnly Journal');
        expect(
          find.widgetWithText(ListTile, 'AlphaOnly Journal'),
          findsNothing,
        );
        await search('BetaOnly');
        final betaResult = find.widgetWithText(ListTile, betaNumber);
        expect(betaResult, findsOneWidget);
        await search('BetaOnly Account');
        expect(
          find.widgetWithText(ListTile, 'BetaOnly Account'),
          findsOneWidget,
        );
        await search('BetaOnly Journal');
        expect(
          find.widgetWithText(ListTile, 'BetaOnly Journal'),
          findsOneWidget,
        );
        await search('BetaOnly');
        final betaBillResult = find.widgetWithText(ListTile, betaNumber);
        await tester.tap(betaBillResult);
        await tester.pumpAndSettle();
        expect(find.byType(BillsPage), findsOneWidget);
        expect(tables(beta), betaTables);
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-option-current')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AccountingShell>(find.byType(AccountingShell))
              .workspace,
          same(alpha),
        );
        await search('BetaOnly');
        expect(find.widgetWithText(ListTile, betaNumber), findsNothing);
        await search('BetaOnly Account');
        expect(find.widgetWithText(ListTile, 'BetaOnly Account'), findsNothing);
        await search('BetaOnly Journal');
        expect(find.widgetWithText(ListTile, 'BetaOnly Journal'), findsNothing);
        await search('AlphaOnly');
        expect(find.widgetWithText(ListTile, alphaNumber), findsOneWidget);
        expect(tables(alpha), alphaTables);
        expect(tables(beta), betaTables);
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-option-demo')));
        await tester.pumpAndSettle();
        await search('AlphaOnly');
        expect(find.widgetWithText(ListTile, alphaNumber), findsNothing);
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-option-current')));
        await tester.pumpAndSettle();
        await search('AlphaOnly');
        expect(find.widgetWithText(ListTile, alphaNumber), findsOneWidget);
        expect(tables(alpha), alphaTables);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
