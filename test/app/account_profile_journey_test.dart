import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import 'claim_receipts_proposal_test.dart' show prepare, tap;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Finder keyed(String key) => find.byKey(ValueKey(key));
void expectTaxAndGroupInline(WidgetTester tester) {
  final tax = tester.getRect(keyed('ledger-default-tax'));
  final group = tester.getRect(keyed('ledger-group-account'));
  expect(
    group.left,
    greaterThanOrEqualTo(tax.right + accountingContentInset - .01),
  );
  expect(group.center.dy, closeTo(tax.center.dy, .01));
}

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
Future<void> chooseType(WidgetTester tester, String query, String label) async {
  await tap(tester, keyed('ledger-account-type'));
  await tester.enterText(keyed('ledger-type-search'), query);
  await tester.pumpAndSettle();
  await tap(tester, find.text(label).last);
}

void main() {
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'Saved Account View and Edit save metadata without changing postings at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        final folder = Directory.systemTemp.createTempSync(
          'audyt-saved-account-edit-',
        );
        addTearDown(() => folder.deleteSync(recursive: true));
        final path = '${folder.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        final parent = await workspace.createAccount(
          code: '1000',
          name: 'Cash Group',
          type: AccountType.asset,
          isParent: true,
        );
        final id = await workspace.createAccount(
          code: '1010',
          name: 'Petty Cash',
          type: AccountType.asset,
          parentId: parent,
          profile: const AccountProfile(
            reportingType: ReportingAccountType.cashAndCashEquivalents,
            detailType: 'Cash on hand',
            description: 'Office cash held for small purchases.',
          ),
        );
        final equityId = await workspace.createAccount(
          code: '3000',
          name: 'Owner Capital',
          type: AccountType.equity,
        );
        final journalId = await workspace.saveJournal(
          date: DateTime.utc(2026, 9, 1),
          memo: 'Saved account balance fixture',
          lines: [
            JournalLine.debit(
              accountId: id,
              amount: Money.fromDecimal('123.45', workspace.identity.currency),
            ),
            JournalLine.credit(
              accountId: equityId,
              amount: Money.fromDecimal('123.45', workspace.identity.currency),
            ),
          ],
        );
        final journal = (await workspace.journals()).single;
        await workspace.approveJournal(
          JournalApproval(
            requestId: EntityId.random(),
            businessId: workspace.identity.businessId,
            journalId: journalId,
            expectedRevision: journal.metadata.revision,
            actorId: workspace.identity.ownerId,
            approvedAt: DateTime.now().toUtc(),
          ),
        );
        final before = tables(workspace);
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await captureUi(tester, 'Saved Account Actions ${width.toInt()}');
        await tap(tester, keyed('ledger-account-view-${id.value}'));
        expect(find.text('Saved Account Details'), findsOneWidget);
        expect(find.text('Cash on hand'), findsOneWidget);
        expect(find.text('1000 · Cash Group'), findsOneWidget);
        expect(
          find.text('Office cash held for small purchases.'),
          findsOneWidget,
        );
        expect(tables(workspace), before);
        final facts = find.byType(AccountingInformationRows);
        final factRows = tester.widget<AccountingInformationRows>(facts).rows;
        final tableRect = tester.getRect(facts);
        final labelRects = [
          for (final row in factRows)
            tester.getRect(
              find.descendant(of: facts, matching: find.text(row.$1)),
            ),
        ];
        final longestLabel = labelRects
            .map((r) => r.width)
            .reduce((a, b) => a > b ? a : b);
        final separators = find.descendant(
          of: facts,
          matching: find.text(AccountingSidewaysDetailsTokens.separator),
        );
        // Card's shape paints inside its frame without an extra layout inset.
        for (var i = 0; i < factRows.length; i++) {
          final colon = tester.getRect(separators.at(i));
          final value = tester.getRect(
            find.descendant(of: facts, matching: find.text(factRows[i].$2)),
          );
          expect(
            labelRects[i].left - tableRect.left,
            closeTo(AccountingSidewaysDetailsTokens.horizontalInset, .01),
          );
          expect(
            colon.left - labelRects[i].left - longestLabel,
            closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
          );
          expect(
            value.left - colon.right,
            closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
          );
        }
        await captureUi(tester, 'Saved Account View ${width.toInt()}');
        await tap(tester, keyed('ledger-account-view-close'));
        await tap(tester, keyed('ledger-account-edit-${id.value}'));
        expect(find.text('Edit Account'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Petty Cash',
        );
        expect(find.text('Cash On Hand'), findsOneWidget);
        expect(find.text('1000 · Cash Group'), findsOneWidget);
        expect(keyed('ledger-opening-balance'), findsNothing);
        expect(
          tester.widget<FilledButton>(keyed('save-ledger-account')).onPressed,
          isNotNull,
        );
        await tester.ensureVisible(find.text('Reporting Currency'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(keyed('ledger-group-account'));
        await tester.pumpAndSettle();
        expectTaxAndGroupInline(tester);
        await captureUi(tester, 'Account Tax Group Saved ${width.toInt()}');
        await tap(tester, keyed('ledger-group-account'));
        tester.view.physicalSize = const Size(440, 809);
        await tester.pumpAndSettle();
        await tester.ensureVisible(keyed('ledger-group-account'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(keyed('ledger-group-account')).top,
          greaterThan(tester.getRect(keyed('ledger-default-tax')).bottom),
        );
        expect(
          tester.widget<Checkbox>(keyed('ledger-group-account')).value,
          isTrue,
        );
        expect(tables(workspace), before);
        await captureUi(
          tester,
          'Account Tax Group Forced Stack ${width.toInt()}',
        );
        tester.view.physicalSize = Size(width, 809);
        await tester.pumpAndSettle();
        expectTaxAndGroupInline(tester);
        await tap(tester, keyed('ledger-group-account'));

        await tester.ensureVisible(find.text('Reporting Currency'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Saved Account Edit ${width.toInt()}');
        await Scrollable.ensureVisible(
          tester.element(keyed('ledger-account-type')),
          alignment: 0,
        );
        await tester.pumpAndSettle();
        await tap(tester, keyed('ledger-account-type'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Saved Account Type Menu ${width.toInt()}');
        await tap(tester, find.text('Other Expense').last);
        expect(find.text('Change Account Classification'), findsOneWidget);
        await captureUi(
          tester,
          'Saved Account Classification Warning ${width.toInt()}',
        );
        await tap(tester, keyed('ledger-classification-keep'));
        expect(find.text('Cash On Hand'), findsOneWidget);
        // Declining keeps both the reporting type and the exact original detail.
        expect(tables(workspace), before);
        await tap(tester, keyed('ledger-account-close'));
        expect(find.text('Edit Account'), findsNothing);
        expect(keyed('ledger-discard-changes'), findsNothing);
        await tap(tester, keyed('ledger-account-edit-${id.value}'));
        await tester.ensureVisible(keyed('ledger-account-name'));
        await tester.enterText(
          keyed('ledger-account-name'),
          'Local draft only',
        );
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-keep-editing'));
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Local draft only',
        );
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-discard-changes'));
        await tap(tester, keyed('ledger-account-edit-${id.value}'));
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Petty Cash',
        );
        await tester.ensureVisible(keyed('ledger-lock-account'));
        await tester.pumpAndSettle();
        expect(find.text('Posted Balance'), findsOneWidget);
        expect(find.text('RM 123.45 Dr'), findsOneWidget);
        await captureUi(tester, 'Saved Account Edit Balance ${width.toInt()}');
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.enterText(keyed('ledger-account-code'), '3000');
        await tester.enterText(
          keyed('ledger-account-name'),
          'Office Petty Cash',
        );
        await tap(tester, keyed('save-ledger-account'));
        expect(find.text('Edit Account'), findsOneWidget);
        expect(find.textContaining('already used'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Office Petty Cash',
        );
        expect(tables(workspace), before);
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.enterText(keyed('ledger-account-code'), '1011');
        await tester.ensureVisible(keyed('ledger-account-description'));
        await enterAccountingText(
          tester,
          keyed('ledger-account-description'),
          'Updated office cash purpose.',
        );
        final accountScroll = tester.state<ScrollableState>(
          find
              .ancestor(
                of: keyed('ledger-lock-account'),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        accountScroll.position.jumpTo(accountScroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Saved Account Lock After Error ${width.toInt()}',
        );
        expect(keyed('ledger-lock-account').hitTestable(), findsOneWidget);
        await tap(tester, keyed('ledger-lock-account'));
        await tap(tester, keyed('save-ledger-account'));
        expect(find.text('Edit Account'), findsNothing);
        final edited = (await workspace.database.getAccount(id))!;
        expect(edited.account.id, id);
        expect(edited.account.code, '1011');
        expect(edited.account.name, 'Office Petty Cash');
        expect(edited.account.parentId, parent);
        expect(edited.account.status, AccountStatus.locked);
        expect(edited.account.profile!.detailType, 'Cash on hand');
        expect(
          edited.account.profile!.description,
          'Updated office cash purpose.',
        );
        expect(edited.metadata.revision, 2);
        expect(edited.metadata.createdAt, isNotNull);
        expect((await workspace.accounts()), hasLength(3));
        expect((await workspace.journals()), hasLength(1));
        final after = tables(workspace);
        expect(
          Map.of(after)..remove('accounts'),
          Map.of(before)..remove('accounts'),
        );
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        final reopened = (await workspace.database.getAccount(id))!;
        expect(reopened.account.code, '1011');
        expect(
          reopened.account.profile!.description,
          'Updated office cash purpose.',
        );
        expect(reopened.metadata.revision, 2);
        expect((await workspace.journals()).single.entry.id, journalId);
        final report = await workspace.report(
          from: DateTime.utc(1),
          through: DateTime.now(),
        );
        expect(
          report.rows.singleWhere((row) => row.account.id == id).endingNetDebit,
          BigInt.from(12345),
        );
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await tap(tester, keyed('ledger-account-edit-${id.value}'));
        expect(find.text('RM 123.45 Dr'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(keyed('ledger-account-name'))
              .controller!
              .text,
          'Office Petty Cash',
        );
        await tap(tester, keyed('ledger-account-close'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'New Account reveals blocked Save without manual scrolling at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 809);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        final groupId = await workspace.createAccount(
          code: 'QA-GROUP',
          name: 'Existing Group',
          type: AccountType.asset,
          isParent: true,
        );
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await tap(tester, keyed('new-ledger-account'));
        await tester.ensureVisible(keyed('ledger-group-account'));
        await tester.pumpAndSettle();
        expectTaxAndGroupInline(tester);
        await captureUi(tester, 'Account Tax Group New ${width.toInt()}');

        Future<void> expectVisibleError(String message, String capture) async {
          final error = find.text(message);
          expect(error, findsOneWidget);
          final viewport = find
              .ancestor(of: error, matching: find.byType(SingleChildScrollView))
              .first;
          final bounds = tester.getRect(error);
          final visible = tester.getRect(viewport);
          expect(bounds.top, greaterThanOrEqualTo(visible.top));
          expect(bounds.bottom, lessThanOrEqualTo(visible.bottom));
          expect(
            bounds.bottom,
            lessThan(tester.getRect(keyed('save-ledger-account')).top),
          );
          expect(error.hitTestable(), findsOneWidget);
          expect(await workspace.accounts(), hasLength(1));
          expect(await workspace.journals(), isEmpty);
          await captureUi(
            tester,
            'Account Save Error $capture ${width.toInt()}',
          );
        }

        await tap(tester, keyed('save-ledger-account'));
        await expectVisibleError(
          'Enter an account code, name and type.',
          'Required',
        );
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.enterText(keyed('ledger-account-code'), 'QA-CHILD');
        await tester.enterText(keyed('ledger-account-name'), 'Retained Child');
        await chooseType(tester, 'Current assets', 'Current Assets');
        await tap(tester, keyed('ledger-parent-account'));
        await tap(tester, find.text('QA-GROUP · Existing Group').last);
        await tester.ensureVisible(keyed('ledger-opening-balance'));
        await tester.enterText(keyed('ledger-opening-balance'), '100');
        // Save from the top of the form: the error starts below the viewport.
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.pumpAndSettle();
        await tap(tester, keyed('save-ledger-account'));
        await expectVisibleError(
          'Opening balances require a dated balanced journal. This step is not connected to account creation yet.',
          'Opening',
        );
        expect(
          tester
              .widget<TextField>(keyed('ledger-opening-balance'))
              .controller!
              .text,
          '100',
        );
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-keep-editing'));
        expect(find.text('Retained Child'), findsOneWidget);
        final parent = tester.widget<AccountingSelector<String>>(
          find.ancestor(
            of: keyed('ledger-parent-account'),
            matching: find.byType(AccountingSelector<String>),
          ),
        );
        expect(parent.value, groupId.toString());
        await tester.ensureVisible(keyed('ledger-opening-balance'));
        await tester.enterText(keyed('ledger-opening-balance'), '');
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.enterText(keyed('ledger-account-code'), 'QA-GROUP');
        await tap(tester, keyed('save-ledger-account'));
        final error = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data != null &&
              widget.data!.contains('already'),
        );
        expect(error, findsOneWidget);
        await expectVisibleError(tester.widget<Text>(error).data!, 'Duplicate');
        await tester.ensureVisible(keyed('ledger-account-code'));
        await tester.enterText(keyed('ledger-account-code'), 'QA-CHILD');
        await tap(tester, keyed('save-ledger-account'));
        expect(find.byType(AlertDialog), findsNothing);
        final child = (await workspace.accounts())
            .singleWhere((row) => row.account.code == 'QA-CHILD')
            .account;
        expect(child.name, 'Retained Child');
        expect(child.parentId, groupId);
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual account profile keeps facts, saves and reopens at $width',
      (tester) async {
        await prepare(tester, width);
        final folder = Directory.systemTemp.createTempSync(
          'audyt-account-profile-ui-',
        );
        addTearDown(() => folder.deleteSync(recursive: true));
        final path = '${folder.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        final taxId = AccountingWorkspace.newId();
        workspace.saveTaxRate(
          CompanyTaxRate(
            id: taxId,
            name: 'Company Purchase Tax',
            percent: '6',
            effectiveFrom: DateTime.utc(2026),
            application: TaxApplication.purchases,
          ),
        );
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await tap(tester, keyed('new-ledger-account'));
        final detail = tester.widget<AccountingSelector<String>>(
          find.ancestor(
            of: keyed('ledger-detail-type'),
            matching: find.byType(AccountingSelector<String>),
          ),
        );
        expect(detail.enabled, isFalse);
        await captureUi(tester, 'Account Profile Empty ${width.toInt()}');
        await tester.enterText(keyed('ledger-account-code'), 'EXP-10');
        await tester.enterText(
          keyed('ledger-account-name'),
          'Regional Office Expenses',
        );
        await tap(tester, keyed('ledger-account-type'));
        final type = tester.widget<AccountingSelector<ReportingAccountType>>(
          find.ancestor(
            of: keyed('ledger-account-type'),
            matching: find.byType(AccountingSelector<ReportingAccountType>),
          ),
        );
        expect(type.options, hasLength(15));
        await captureUi(tester, 'Account Profile Type Menu ${width.toInt()}');
        await tester.enterText(keyed('ledger-type-search'), 'Expenses');
        await tester.pumpAndSettle();
        await tap(tester, find.text('Expenses').last);
        expect(keyed('ledger-opening-balance'), findsNothing);
        await tap(tester, keyed('ledger-detail-type'));
        await captureUi(tester, 'Account Profile Detail Menu ${width.toInt()}');
        final lastDetail = ReportingAccountType.expenses.details.last;
        await tester.enterText(keyed('ledger-detail-search'), lastDetail);
        await tester.pumpAndSettle();
        await tap(tester, find.text(accountingTitleCase(lastDetail)).last);
        await tap(tester, keyed('ledger-default-tax'));
        await tap(tester, find.text('Company Purchase Tax · 6%').last);
        await enterAccountingText(
          tester,
          keyed('ledger-account-description'),
          'Office costs for regional operations.',
        );
        await tap(tester, keyed('ledger-lock-account'));
        await captureUi(
          tester,
          'Account Profile Description And Lock ${width.toInt()}',
        );
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-keep-editing'));
        expect(
          tester
              .state<AccountingDescriptionFieldState>(
                keyed('ledger-account-description'),
              )
              .editor
              .plainDescription,
          'Office costs for regional operations.',
        );
        tester.view.physicalSize = Size(width, 613);
        await tester.pumpAndSettle();
        await tester.ensureVisible(keyed('ledger-lock-account'));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Account Profile Short Height ${width.toInt()}',
        );
        expect(
          tester.getRect(keyed('save-ledger-account')).bottom,
          lessThanOrEqualTo(613),
        );
        await tap(tester, keyed('save-ledger-account'));
        expect(find.byType(AlertDialog), findsNothing);
        final saved = (await workspace.accounts()).single.account;
        expect(saved.type, AccountType.expense);
        expect(saved.status, AccountStatus.locked);
        expect(saved.profile!.reportingType, ReportingAccountType.expenses);
        expect(saved.profile!.detailType, lastDetail);
        expect(saved.profile!.defaultTaxCodeId, taxId);
        expect(saved.profile!.description, contains('regional operations'));
        expect(await workspace.journals(), isEmpty);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        expect(
          (await workspace.accounts()).single.account.profile!.toJson(),
          saved.profile!.toJson(),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'opening branch retains hidden facts and cannot fake a journal at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await host(tester, workspace);
        await tester.pumpAndSettle();
        await tap(tester, keyed('new-ledger-account'));
        await tester.enterText(keyed('ledger-account-code'), 'CASH-10');
        await tester.enterText(keyed('ledger-account-name'), 'Regional Cash');
        await chooseType(tester, 'Cash', 'Cash And Cash Equivalents');
        await captureUi(
          tester,
          'Account Profile Cash Opening ${width.toInt()}',
        );
        await tester.enterText(keyed('ledger-opening-balance'), '16.50');
        await tester.enterText(keyed('ledger-opening-date'), '01-10-2026');
        await chooseType(tester, 'Expenses', 'Expenses');
        expect(keyed('ledger-opening-balance'), findsNothing);
        await chooseType(tester, 'Cash', 'Cash And Cash Equivalents');
        expect(
          tester
              .widget<TextField>(keyed('ledger-opening-balance'))
              .controller!
              .text,
          '16.50',
        );
        await tap(tester, keyed('save-ledger-account'));
        expect(
          find.text(
            'Opening balances require a dated balanced journal. This step is not connected to account creation yet.',
          ),
          findsOneWidget,
        );
        expect(await workspace.accounts(), isEmpty);
        expect(await workspace.journals(), isEmpty);
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-keep-editing'));
        expect(
          tester
              .widget<TextField>(keyed('ledger-opening-balance'))
              .controller!
              .text,
          '16.50',
        );
        await tap(tester, keyed('ledger-account-close'));
        await tap(tester, keyed('ledger-discard-changes'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(await workspace.accounts(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
