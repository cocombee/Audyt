import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'journal_field_design_journey_test.dart' show openCurrencyFixture;
import '../support/accounting_text_input.dart';

Finder keyed(String key) => find.byKey(ValueKey(key));

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final (currency, zero, entered, formatted) in [
      ('MYR', '0.00', '123456789012.34', '123,456,789,012.34'),
      ('JPY', '0', '123456789012', '123,456,789,012'),
      ('KWD', '0.000', '123456789012.345', '123,456,789,012.345'),
    ]) {
      testWidgets(
        'saved $currency New Account zero hint retains ordinary opening width at $width',
        (tester) async {
          await prepare(tester, width);
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
                  body: ChartOfAccountsPage(
                    workspace: workspace,
                    compact: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(keyed('new-ledger-account'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('ledger-account-type'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cash And Cash Equivalents').last);
          await tester.pumpAndSettle();
          final field = keyed('ledger-opening-balance');
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          final input = tester.widget<TextField>(field);
          expect(input.controller!.text, isEmpty);
          expect(input.decoration!.hintText, zero);
          final widthBefore = tester.getSize(field).width;
          await captureUi(
            tester,
            'Saved $currency Account Opening Zero ${width.toInt()}',
          );
          await enterAccountingText(tester, field, entered);
          await tester.pumpAndSettle();
          expect(tester.getSize(field).width, closeTo(widthBefore, .01));
          expect(tester.widget<TextField>(field).controller!.text, formatted);
          await enterAccountingText(tester, field, '-$entered');
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(field).controller!.text,
            '-$formatted',
          );
          expect(tester.getSize(field).width, closeTo(widthBefore, .01));
          await captureUi(
            tester,
            'Saved $currency Account Opening Fixed ${width.toInt()}',
          );
          await tester.tap(keyed('ledger-account-close'));
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tester.tap(keyed('ledger-discard-changes'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
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
      'Actual ledger account ordinary fields and SQLite reopen at $width',
      (tester) async {
        await prepare(tester, width);
        final folder = Directory.systemTemp.createTempSync(
          'audyt-ledger-proposal-',
        );
        addTearDown(() => folder.deleteSync(recursive: true));
        final path = '${folder.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        await workspace.createAccount(
          code: '1000',
          name: 'Current Assets And Operating Accounts',
          type: AccountType.asset,
          isParent: true,
        );
        await workspace.createAccount(
          code: '2000',
          name: 'Liability Group',
          type: AccountType.liability,
          isParent: true,
        );
        final parent = (await workspace.accounts())
            .firstWhere((a) => a.account.code == '1000')
            .account;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ChartOfAccountsPage(workspace: workspace, compact: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(keyed('new-ledger-account'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsNothing);
        expect(
          find.text(
            'Bank account currencies are configured in Banking. Ledger balances are reported in the company currency.',
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(AccountingOrdinaryFields),
          ),
          findsNWidgets(2),
        );
        final initialDialog = tester.getRect(find.byType(AlertDialog));
        final groupCheckbox = tester.getRect(keyed('ledger-group-account'));
        final groupLabel = tester.getRect(find.text('Group Account'));
        expect(groupLabel.left - groupCheckbox.right, closeTo(20, 0.1));
        expect(groupLabel.center.dy, closeTo(groupCheckbox.center.dy, 1));
        await captureUi(tester, 'Ledger Account Empty ${width.toInt()}');
        await tester.tap(keyed('save-ledger-account'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter an account code, name and type.'),
          findsOneWidget,
        );
        await captureUi(tester, 'Ledger Account Validation ${width.toInt()}');
        await tester.enterText(keyed('ledger-account-code'), '1010');
        await tester.enterText(keyed('ledger-account-name'), 'Cash At Bank');
        await tester.tap(keyed('ledger-account-type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash And Cash Equivalents').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Enter an account code, name and type.'),
          findsNothing,
        );
        await tester.tap(keyed('ledger-parent-account'));
        await tester.pumpAndSettle();
        expect(find.text(parent.displayName), findsOneWidget);
        expect(find.text('2000 · Liability Group'), findsNothing);
        await captureUi(tester, 'Ledger Account Parent Menu ${width.toInt()}');
        await tester.tap(find.text(parent.displayName));
        await tester.pumpAndSettle();
        final nameState = tester.state<EditableTextState>(
          find.descendant(
            of: keyed('ledger-account-name'),
            matching: find.byType(EditableText),
          ),
        );
        await tester.enterText(
          keyed('ledger-account-name'),
          'Operating Cash At Bank For Regional Supplier Settlements',
        );
        await tester.pumpAndSettle();
        final afterState = tester.state<EditableTextState>(
          find.descendant(
            of: keyed('ledger-account-name'),
            matching: find.byType(EditableText),
          ),
        );
        expect(identical(nameState, afterState), isTrue);
        expect(afterState.widget.focusNode.hasFocus, isTrue);
        expect(
          afterState.widget.controller.selection.baseOffset,
          afterState.widget.controller.text.length,
        );
        expect(
          tester.getRect(find.byType(AlertDialog)).width,
          closeTo(initialDialog.width, 0.1),
        );
        expect(
          tester.getSize(keyed('ledger-account-name')).width,
          greaterThan(300),
        );
        await captureUi(tester, 'Ledger Account Long Name ${width.toInt()}');
        await tester.enterText(keyed('ledger-account-name'), 'Cash At Bank');
        await tester.pumpAndSettle();
        final dialog = tester.getRect(find.byType(AlertDialog));
        for (final key in [
          'ledger-account-code',
          'ledger-account-name',
          'ledger-account-type',
          'ledger-parent-account',
        ]) {
          final rect = tester.getRect(keyed(key));
          expect(rect.left, greaterThanOrEqualTo(dialog.left));
          expect(rect.right, lessThanOrEqualTo(dialog.right));
        }
        await captureUi(tester, 'Ledger Account Fitted ${width.toInt()}');
        final description = keyed('ledger-account-description');
        await tester.ensureVisible(description);
        await enterAccountingText(
          tester,
          description,
          'Cash held for regional supplier settlements.\nRetain this account purpose through save and restart.',
        );
        await tester.pumpAndSettle();
        expect((await workspace.accounts()).length, 2);
        expect(
          tester
              .state<AccountingDescriptionFieldState>(description)
              .editor
              .plainDescription,
          contains('regional supplier settlements'),
        );
        await captureUi(
          tester,
          'Ledger Account Description Ready ${width.toInt()}',
        );
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(keyed('save-ledger-account')).bottom,
          lessThanOrEqualTo(613),
        );
        expect(
          tester.getRect(keyed('ledger-account-close')).top,
          greaterThanOrEqualTo(0),
        );
        expect(
          tester
              .state<AccountingDescriptionFieldState>(description)
              .editor
              .plainDescription,
          contains('regional supplier settlements'),
        );
        expect(tester.takeException(), isNull);
        await captureUi(
          tester,
          'Ledger Account Description Short Height ${width.toInt()}',
        );
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        await tester.tap(keyed('save-ledger-account'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final created = (await workspace.accounts())
            .firstWhere((a) => a.account.code == '1010')
            .account;
        expect(created.name, 'Cash At Bank');
        expect(created.parentId, parent.id);
        expect(created.isParent, isFalse);
        expect(created.openingBalance, isNull);
        expect(
          created.profile!.reportingType,
          ReportingAccountType.cashAndCashEquivalents,
        );
        expect(
          created.profile!.description,
          contains('regional supplier settlements'),
        );
        expect(await workspace.journals(), isEmpty);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        final reopened = (await workspace.accounts())
            .firstWhere((a) => a.account.id == created.id)
            .account;
        expect(reopened.name, created.name);
        expect(reopened.parentId, parent.id);
        expect(reopened.profile!.toJson(), created.profile!.toJson());
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Actual ledger account type reset, duplicate validation and Close at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await workspace.createAccount(
          code: '1000',
          name: 'Asset Group',
          type: AccountType.asset,
          isParent: true,
        );
        await workspace.createAccount(
          code: '2000',
          name: 'Liability Group',
          type: AccountType.liability,
          isParent: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: ChartOfAccountsPage(workspace: workspace, compact: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(keyed('new-ledger-account'));
        await tester.pumpAndSettle();
        await tester.enterText(keyed('ledger-account-code'), '1000');
        await tester.enterText(keyed('ledger-account-name'), 'Duplicate Code');
        await tester.tap(keyed('ledger-account-type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash And Cash Equivalents').last);
        await tester.pumpAndSettle();
        await tester.tap(keyed('ledger-parent-account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1000 · Asset Group'));
        await tester.pumpAndSettle();
        await tester.tap(keyed('ledger-account-type'));
        await tester.pumpAndSettle();
        await tester.enterText(
          keyed('ledger-type-search'),
          'Current liabilities',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Current Liabilities').last);
        await tester.pumpAndSettle();
        final parentSelector = tester.widget<AccountingSelector<String>>(
          find.ancestor(
            of: keyed('ledger-parent-account'),
            matching: find.byType(AccountingSelector<String>),
          ),
        );
        expect(parentSelector.value, 'none');
        expect(parentSelector.options.map((o) => o.label), [
          'None',
          '2000 · Liability Group',
        ]);
        await tester.tap(keyed('save-ledger-account'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(await workspace.accounts(), hasLength(2));
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Duplicate Code',
        );
        await tester.tap(keyed('ledger-account-close'));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tester.tap(keyed('ledger-discard-changes'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(await workspace.accounts(), hasLength(2));
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'New Account keeps unsaved fields through Close, Escape and warning dismissal at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ChartOfAccountsPage(workspace: workspace, compact: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(keyed('new-ledger-account'));
        await tester.pumpAndSettle();
        // Untouched forms still dismiss immediately.
        await tester.tap(keyed('ledger-account-close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(keyed('new-ledger-account'));
        await tester.pumpAndSettle();
        final description = keyed('ledger-account-description');
        await tester.ensureVisible(description);
        await enterAccountingText(
          tester,
          description,
          'Retain this unsaved account purpose.',
        );
        await tester.tap(keyed('ledger-account-close'));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNWidgets(2));
        await captureUi(
          tester,
          'Ledger Account Discard Warning ${width.toInt()}',
        );
        await tester.tap(keyed('ledger-keep-editing'));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<AccountingDescriptionFieldState>(description)
              .editor
              .plainDescription,
          'Retain this unsaved account purpose.',
        );
        // A backdrop click must not silently dispose either editing session.
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tester.tap(keyed('ledger-keep-editing'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNWidgets(2));
        await tester.tap(keyed('ledger-discard-close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester
              .state<AccountingDescriptionFieldState>(description)
              .editor
              .plainDescription,
          'Retain this unsaved account purpose.',
        );
        // The short-height state uses the same warning and retains the editor.
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await tester.tap(keyed('ledger-account-close'));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Ledger Account Discard Short Height ${width.toInt()}',
        );
        await tester.tap(keyed('ledger-discard-changes'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(await workspace.accounts(), isEmpty);
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'New Account warns for each editable ordinary value at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: ChartOfAccountsPage(workspace: workspace, compact: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final field in ['code', 'name', 'type', 'group']) {
          await tester.tap(keyed('new-ledger-account'));
          await tester.pumpAndSettle();
          switch (field) {
            case 'code':
              await tester.enterText(keyed('ledger-account-code'), '1010');
            case 'name':
              await tester.enterText(
                keyed('ledger-account-name'),
                'Operating Cash',
              );
            case 'type':
              await tester.tap(keyed('ledger-account-type'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Cash And Cash Equivalents').last);
            case 'group':
              await tester.tap(keyed('ledger-group-account'));
          }
          await tester.pumpAndSettle();
          await tester.tap(keyed('ledger-account-close'));
          await tester.pumpAndSettle();
          expect(
            find.text('Discard Unsaved Changes?'),
            findsOneWidget,
            reason: field,
          );
          await tester.tap(keyed('ledger-discard-changes'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
        expect(await workspace.accounts(), isEmpty);
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
