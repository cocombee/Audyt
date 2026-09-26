import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';

import '../support/accounting_test_finders.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mountBanking(
  WidgetTester tester,
  AccountingWorkspace workspace,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: BankingPage(workspace: workspace, compact: true)),
    ),
  );
  await tester.pumpAndSettle();
  final csv = workspace.database
      .bankStatements(workspace.identity.businessId, 'demo-bank')
      .singleWhere((item) => item.filename == 'Demo Bank.csv');
  await openStatementReview(tester, statementId: csv.id.value);
}

void main() {
  testWidgets(
    'date search filters bank rows and retains eligible creation actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BankingPage(
              workspace: workspace,
              compact: true,
              onReceivePayment: (row, account) async {},
              onCreateInvoice: (row, account) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final small = workspace.database
          .bankStatements(workspace.identity.businessId, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.csv');
      await openStatementReview(tester, statementId: small.id.value);
      expect(find.byKey(const ValueKey('match-search')), findsNothing);
      expect(find.byKey(const ValueKey('match-page-size')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final id = EntityId.random();
      workspace.database.importBankStatement(
        id: id,
        businessId: workspace.identity.businessId,
        paymentAccountId: 'demo-bank',
        importedAt: DateTime.utc(2026, 9, 30),
        statement: BankStatementImport.csv(
          filename: 'Test Six Rows.csv',
          currency: 'MYR',
          bytes: Uint8List.fromList(
            utf8.encode(
              'Date,Description,Amount,Reference\n2026-09-01,SR-001 Customer Payment,680000.00,SR-001\n2026-09-01,EXP-001 Office Supplies,-185.00,\n2026-09-30,Meridian Trading Instalment 1,200.00,DEMO-RCPT-001-A\n2026-09-30,Meridian Trading Instalment 2,300.00,DEMO-RCPT-001-B\n2026-09-30,Test Fifth,1.00,T5\n2026-09-30,Test Sixth,1.00,T6\n',
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BankingPage(
              workspace: workspace,
              compact: true,
              onReceivePayment: (row, account) async {},
              onCreateInvoice: (row, account) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openStatementReview(tester, statementId: id.value);
      expect(find.byKey(const ValueKey('match-page-size')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('missing-receive-payment-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('missing-create-invoice-4')),
        findsOneWidget,
      );
      final detail = tester.getRect(
        find.byKey(const ValueKey('match-detail-padding-4')),
      );
      final row = tester.getRect(
        find.byKey(const ValueKey('no-suggestion-row-4')),
      );
      final label = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('no-suggestion-row-4')),
          matching: find.text('No Suggested Match'),
        ),
      );
      final receive = tester.getRect(
        find.byKey(const ValueKey('missing-receive-payment-4')),
      );
      final invoice = tester.getRect(
        find.byKey(const ValueKey('missing-create-invoice-4')),
      );
      expect(label.center.dy, closeTo(receive.center.dy, 0.1));
      expect(label.center.dy, closeTo(invoice.center.dy, 0.1));
      expect(row.top - detail.top, closeTo(20, 0.1));
      expect(detail.bottom - row.bottom, closeTo(20, 0.1));
      final mainSearch = find.byKey(const ValueKey('match-search'));
      expect(tester.getSize(mainSearch).width, closeTo(240, 0.1));
      final fileHeader = tester.getRect(
        find.byKey(const ValueKey('statement-match-file-header')),
      );
      final searchBox = tester.getRect(mainSearch);
      final searchHint = tester.getRect(find.text('Search bank transactions'));
      expect(searchBox.left, closeTo(fileHeader.left, 0.1));
      expect(searchHint.left, closeTo(fileHeader.left + 20, 0.1));
      for (final field in ['match-from', 'match-through']) {
        final label = tester.getRect(find.byKey(ValueKey('$field-label')));
        final control = tester.getRect(find.byKey(ValueKey(field)));
        expect(control.top - label.bottom, closeTo(8, 0.1));
        expect(label.left, closeTo(control.left, 0.1));
      }
      await tester.enterText(mainSearch, 'Office Supplies');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statement-match-card-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statement-match-card-2')),
        findsNothing,
      );
      await tester.enterText(mainSearch, '');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('match-from')),
        '02-09-2026',
      );
      await tester.tap(find.byKey(const ValueKey('run-match-date-range')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statement-match-card-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('statement-match-card-3')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('missing-receive-payment-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('missing-create-invoice-4')),
        findsOneWidget,
      );
    },
  );

  testWidgets('no-suggestion actions share the label center at narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BankingPage(
            workspace: workspace,
            compact: true,
            onReceivePayment: (row, account) async {},
            onCreateInvoice: (row, account) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final csv = workspace.database
        .bankStatements(workspace.identity.businessId, 'demo-bank')
        .singleWhere((item) => item.filename == 'Demo Bank.csv');
    await openStatementReview(tester, statementId: csv.id.value);
    final row = find.byKey(const ValueKey('no-suggestion-row-4'));
    final label = tester.getRect(
      find.descendant(of: row, matching: find.text('No Suggested Match')),
    );
    final receive = tester.getRect(
      find.byKey(const ValueKey('missing-receive-payment-4')),
    );
    final invoice = tester.getRect(
      find.byKey(const ValueKey('missing-create-invoice-4')),
    );
    expect(label.center.dy, closeTo(receive.center.dy, 0.1));
    expect(label.center.dy, closeTo(invoice.center.dy, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('import preserves source and returns to Imported Statements', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('bank-import-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/books.sqlite',
    );
    addTearDown(workspace.dispose);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    await workspace.createAccount(
      code: '1000',
      name: 'Bank Ledger',
      type: AccountType.asset,
    );
    final ledger = (await workspace.accounts()).single.account;
    workspace.database.linkPaymentLedgerAccount(
      workspace.identity.businessId,
      'bank',
      ledger.id,
    );
    final bytes = Uint8List.fromList(
      utf8.encode('Date,Description,Amount\n2026-09-01,Stationery,-10.00'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BankingPage(
            workspace: workspace,
            compact: true,
            statementPicker: () async => (name: 'September.csv', bytes: bytes),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('banking-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-statement-upload-choose')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-statement-upload-review')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review Statement Import'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pumpAndSettle();
    expect(
      workspace.database.bankStatements(workspace.identity.businessId, 'bank'),
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('banking-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-statement-upload-choose')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-statement-upload-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('banking-save-import')));
    await tester.pumpAndSettle();
    final imported = workspace.database
        .bankStatements(workspace.identity.businessId, 'bank')
        .single;
    expect(
      workspace.database
          .bankStatement(workspace.identity.businessId, imported.id)!
          .sourceBytes,
      bytes,
    );
    expect(find.text('September.csv'), findsWidgets);
    expect(
      find.byKey(const ValueKey('imported-statements-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('statement-match-file-header')),
      findsNothing,
    );
  });

  testWidgets(
    'changing account updates balance and statement, and source switch works',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final statements = workspace.database.bankStatements(
        workspace.identity.businessId,
        'demo-bank',
      );
      final pdf = statements.singleWhere(
        (item) => item.filename == 'Demo Bank.pdf',
      );
      expect(
        workspace.database
            .bankStatement(workspace.identity.businessId, pdf.id)!
            .sourceBytes
            .take(5)
            .toList(),
        '%PDF-'.codeUnits,
      );
      await mountBanking(tester, workspace);
      expect(find.text('Demo Bank.csv'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('banking-account-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('banking-account-option-demo-savings')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo Savings.csv'), findsWidgets);
      expect(
        find.byKey(const ValueKey('banking-account-demo-savings-0')),
        findsOneWidget,
      );
      expect(find.text('RM 25,150.00'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('review-account-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('review-statement-switcher-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('review-statement-option-${pdf.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo Bank.pdf'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('review-view-statement')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-download-statement')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reconciliation approval is discoverable and blocked until review passes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      await mountBanking(tester, workspace);
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('review-open-reconciliation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reconciliation-form-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('approve-reconciliation')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('approve-reconciliation')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('back-to-matches')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('back-to-matches')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statement-match-file-header')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('banking-account-demo-bank-2')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reconciliation-form-card')),
        findsOneWidget,
      );
    },
  );
}
