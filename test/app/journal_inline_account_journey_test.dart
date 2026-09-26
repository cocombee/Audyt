import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;

Finder keyed(String key) => find.byKey(ValueKey(key));

AccountingSelector<EntityId?> accountSelector(WidgetTester tester, int row) =>
    tester.widget(
      find.ancestor(
        of: keyed('journal-account-$row'),
        matching: find.byType(AccountingSelector<EntityId?>),
      ),
    );

Future<void> host(WidgetTester tester, AccountingWorkspace workspace) =>
    tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: Scaffold(body: ChartOfAccountsPage(workspace: workspace)),
        ),
      ),
    );

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Journal inline account cancel, exact selection and restart at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final folder = Directory.systemTemp.createTempSync(
          'audyt-inline-account-',
        );
        addTearDown(() => folder.deleteSync(recursive: true));
        final path = '${folder.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());
        await workspace.createAccount(
          code: '1000',
          name: 'Cash',
          type: AccountType.asset,
        );
        final capitalId = await workspace.createAccount(
          code: '3000',
          name: 'Capital',
          type: AccountType.equity,
        );
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await tap(tester, keyed('new-journal'));
        await enterAccountingText(
          tester,
          keyed('journal-memo'),
          'Retained Journal Memo',
        );
        await tester.enterText(keyed('journal-debit-0'), '12.50');
        await tap(tester, keyed('journal-account-0'));
        final selector = accountSelector(tester, 0);
        expect(selector.options.first.label, 'Add Account');
        expect(selector.options.first.onPressed, isNotNull);
        await captureUi(tester, 'Journal Add Account Menu ${width.toInt()}');
        await tap(tester, keyed('journal-add-account-0'));
        expect(find.text('New Account'), findsWidgets);
        expect(keyed('ledger-account-code'), findsOneWidget);
        await captureUi(
          tester,
          'Journal Existing Account Popup ${width.toInt()}',
        );
        await tap(tester, keyed('ledger-account-close'));
        expect((await workspace.accounts()).length, 2);
        expect(
          tester.widget<TextField>(keyed('journal-debit-0')).controller!.text,
          '12.50',
        );
        expect(accountSelector(tester, 0).value, isNull);
        expect(
          accountingDescriptionText('Retained Journal Memo'),
          findsOneWidget,
        );

        await tap(tester, keyed('journal-account-0'));
        await tap(tester, keyed('journal-add-account-0'));
        await tester.enterText(keyed('ledger-account-code'), '1100');
        await tester.enterText(
          keyed('ledger-account-name'),
          'Inline Cash Account',
        );
        await tap(tester, keyed('ledger-account-type'));
        await tap(tester, find.text('Cash And Cash Equivalents').last);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(keyed('ledger-keep-editing'), findsOneWidget);
        await tap(tester, keyed('ledger-keep-editing'));
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Inline Cash Account',
        );
        await tap(tester, keyed('save-ledger-account'));
        final savedAccount = (await workspace.accounts()).singleWhere(
          (r) => r.account.code == '1100',
        );
        expect(savedAccount.account.name, 'Inline Cash Account');
        expect(accountSelector(tester, 0).value, savedAccount.account.id);
        expect(
          tester.widget<TextField>(keyed('journal-debit-0')).controller!.text,
          '12.50',
        );
        expect(
          accountingDescriptionText('Retained Journal Memo'),
          findsOneWidget,
        );
        await tap(tester, keyed('journal-account-1'));
        await tap(tester, find.text('3000 · Capital').last);
        await tester.enterText(keyed('journal-credit-1'), '12.50');
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Journal Inline Account Selected ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tap(tester, keyed('save-journal-draft'));
        final saved = (await workspace.journals()).single;
        expect(saved.entry.memo, 'Retained Journal Memo');
        expect(saved.entry.lines.first.accountId, savedAccount.account.id);
        expect(saved.entry.lines.last.accountId, capitalId);
        expect(saved.entry.lines.first.amount.toDecimalString(), '12.50');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(
          (await workspace.accounts())
              .singleWhere((r) => r.account.code == '1100')
              .account
              .id,
          savedAccount.account.id,
        );
        final restored = (await workspace.journals()).single;
        expect(restored.entry.id, saved.entry.id);
        expect(restored.entry.memo, 'Retained Journal Memo');
        expect(restored.entry.lines.first.accountId, savedAccount.account.id);
        expect(restored.entry.lines.last.accountId, capitalId);
      },
    );
  }

  testWidgets('Inline group creation retains the existing posting account', (
    tester,
  ) async {
    await prepare(tester, 720);
    installFixedPopoutHost(tester);
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    final cashId = await workspace.createAccount(
      code: '1000',
      name: 'Cash',
      type: AccountType.asset,
    );
    await workspace.createAccount(
      code: '3000',
      name: 'Capital',
      type: AccountType.equity,
    );
    await host(tester, workspace);
    await tester.pumpAndSettle();
    await tap(tester, keyed('new-journal'));
    await tap(tester, keyed('journal-account-0'));
    await tap(tester, find.text('1000 · Cash').last);
    await tap(tester, keyed('journal-account-0'));
    await tap(tester, keyed('journal-add-account-0'));
    await tester.enterText(keyed('ledger-account-code'), '1500');
    await tester.enterText(keyed('ledger-account-name'), 'Asset Group');
    await tap(tester, keyed('ledger-account-type'));
    await tap(tester, find.text('Cash And Cash Equivalents').last);
    await tap(tester, keyed('ledger-group-account'));
    await tap(tester, keyed('save-ledger-account'));
    expect(
      (await workspace.accounts())
          .singleWhere((r) => r.account.code == '1500')
          .account
          .isParent,
      isTrue,
    );
    final selector = accountSelector(tester, 0);
    expect(selector.value, cashId);
    expect(
      selector.options.any((o) => o.label.contains('Asset Group')),
      isFalse,
    );
    expect(
      find.text(
        'Group accounts cannot be used in journal lines. Choose a posting account.',
      ),
      findsOneWidget,
    );
    expect((await workspace.journals()), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('locked inline account retains the previous journal selection', (
    tester,
  ) async {
    await prepare(tester, 720);
    installFixedPopoutHost(tester);
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    final cashId = await workspace.createAccount(
      code: '1000',
      name: 'Cash',
      type: AccountType.asset,
    );
    await workspace.createAccount(
      code: '3000',
      name: 'Capital',
      type: AccountType.equity,
    );
    await host(tester, workspace);
    await tester.pumpAndSettle();
    await tap(tester, keyed('new-journal'));
    await tester.enterText(keyed('journal-debit-0'), '12.50');
    await tap(tester, keyed('journal-account-0'));
    await tap(tester, find.text('1000 · Cash').last);
    await tap(tester, keyed('journal-account-0'));
    await tap(tester, keyed('journal-add-account-0'));
    await tester.enterText(keyed('ledger-account-code'), '1200');
    await tester.enterText(keyed('ledger-account-name'), 'Locked Cash');
    await tap(tester, keyed('ledger-account-type'));
    await tap(tester, find.text('Cash And Cash Equivalents').last);
    await tap(tester, keyed('ledger-lock-account'));
    await tap(tester, keyed('save-ledger-account'));
    expect(accountSelector(tester, 0).value, cashId);
    expect(
      accountSelector(
        tester,
        0,
      ).options.any((o) => o.label.contains('Locked Cash')),
      isFalse,
    );
    expect(
      (await workspace.accounts())
          .singleWhere((r) => r.account.code == '1200')
          .account
          .status,
      AccountStatus.locked,
    );
    expect(
      tester.widget<TextField>(keyed('journal-debit-0')).controller!.text,
      '12.50',
    );
    expect(
      find.text(
        'The saved account is locked or unavailable. Choose an active posting account.',
      ),
      findsOneWidget,
    );
    expect(await workspace.journals(), isEmpty);
    await captureUi(tester, 'Journal Locked Inline Account Retained 720');
    expect(tester.takeException(), isNull);
  });
}
