import 'dart:io';

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

Finder keyed(String key) => find.byKey(ValueKey(key));
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
