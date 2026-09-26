import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/accounting/presentation/bank_statement_upload_dialog.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;
import '../support/fixed_popout_host.dart';

Finder keyed(String name) => find.byKey(ValueKey(name));
const validCsv =
    'Date,Description,Amount,Reference\n2026-09-01,Fictional Supplies,-10.00,TEST-1';
BankStatementFile file(String name, String content) =>
    (name: name, bytes: Uint8List.fromList(utf8.encode(content)));

Future<AccountingWorkspace> fixture() async {
  final workspace = await AccountingWorkspace.open(':memory:');
  workspace.savePaymentAccount(
    PaymentAccount.create(
      id: 'bank-a',
      name: 'Fictional Business Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'MYR',
    ),
  );
  workspace.savePaymentAccount(
    PaymentAccount.create(
      id: 'bank-b',
      name: 'Fictional Foreign Bank',
      type: PaymentAccountType.bank,
      currencyCode: 'USD',
    ),
  );
  return workspace;
}

Future<void> host(
  WidgetTester tester,
  AccountingWorkspace workspace,
  Future<BankStatementFile?> Function() picker,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: BankingPage(
            workspace: workspace,
            compact: true,
            statementPicker: picker,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(keyed('banking-primary-action'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Banking ledger link uses shared title help and Close without a write at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await fixture();
        addTearDown(workspace.dispose);
        await workspace.createAccount(
          code: '1000',
          name: 'Fictional Business Bank Ledger',
          type: AccountType.asset,
        );
        await workspace.createAccount(
          code: '2000',
          name: 'Fictional Liability',
          type: AccountType.liability,
        );
        await host(tester, workspace, () async => null);
        await tester.tap(keyed('bank-statement-upload-close'));
        await tester.pumpAndSettle();
        await tester.tap(keyed('imported-account-more'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Link Ledger Account'));
        await tester.pumpAndSettle();
        expect(keyed('banking-ledger-fields'), findsOneWidget);
        final dialog = tester.getRect(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Material && widget.type == MaterialType.card,
                ),
              )
              .first,
        );
        final fields = tester.getRect(keyed('banking-ledger-fields'));
        expect(fields.width, closeTo(460, 0.1));
        expect(
          dialog.width,
          closeTo(460 + 2 * AccountingPopoutTokens.contentInset, 0.1),
        );
        expect(
          fields.left - dialog.left,
          closeTo(AccountingPopoutTokens.contentInset, 0.1),
        );
        const guidance =
            'Confirm this account carefully. The link is retained for accounting history and cannot be reassigned here.';
        expect(find.text(guidance), findsNothing);
        await capture(tester, 'Bank Ledger Link ${width.toInt()}');
        await tester.tap(find.bySemanticsLabel('Help for Ledger Account'));
        await tester.pumpAndSettle();
        expect(find.text(guidance), findsOneWidget);
        await capture(tester, 'Bank Ledger Link Help ${width.toInt()}');
        await tester.tap(find.bySemanticsLabel('Close').last);
        await tester.pumpAndSettle();
        expect(
          workspace.database.paymentLedgerAccount(
            workspace.identity.businessId,
            'bank-a',
          ),
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'actual Banking stages, retains errors and closes without import at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final workspace = await fixture();
        addTearDown(workspace.dispose);
        BankStatementFile? picked = file('Fictional Statement.csv', validCsv);
        await host(tester, workspace, () async => picked);
        expect(find.byType(BankStatementUploadDialog), findsOneWidget);
        expect(find.byType(AccountingAttachmentDropzone), findsOneWidget);
        expect(find.byType(AccountingAttachmentRecordRow), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Review Statement Import'), findsNothing);
        expect(
          workspace.database.bankStatements(
            workspace.identity.businessId,
            'bank-a',
          ),
          isEmpty,
        );
        await tester.tap(keyed('bank-statement-upload-review'));
        await tester.pumpAndSettle();
        expect(find.byType(BankStatementUploadDialog), findsOneWidget);
        expect(find.text('Review Statement Import'), findsNothing);
        await capture(tester, 'Bank Statement Upload Empty ${width.toInt()}');

        await tester.tap(keyed('bank-statement-upload-choose'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        final zone = tester.getRect(keyed('bank-statement-upload-dropzone'));
        final record = tester.getRect(keyed('bank-statement-upload-file'));
        expect(record.top - zone.bottom, closeTo(20, .1));
        expect(record.left, closeTo(zone.left, .1));
        expect(record.right, closeTo(zone.right, .1));
        await capture(tester, 'Bank Statement Upload Staged ${width.toInt()}');

        picked = file('Fictional Invalid.csv', 'not a bank statement');
        await tester.tap(keyed('bank-statement-upload-choose'));
        await tester.pumpAndSettle();
        await tester.tap(keyed('bank-statement-upload-review'));
        await tester.pumpAndSettle();
        expect(keyed('bank-statement-upload-error'), findsOneWidget);
        expect(find.text('Fictional Invalid.csv'), findsOneWidget);
        expect(find.byType(BankStatementUploadDialog), findsOneWidget);
        expect(
          workspace.database.bankStatements(
            workspace.identity.businessId,
            'bank-a',
          ),
          isEmpty,
        );
        await capture(
          tester,
          'Bank Statement Upload Validation ${width.toInt()}',
        );
        await tester.tap(keyed('bank-statement-upload-remove'));
        await tester.pumpAndSettle();
        expect(keyed('bank-statement-upload-error'), findsNothing);
        expect(find.byType(AccountingAttachmentRecordRow), findsNothing);

        picked = file('Fictional Statement.csv', validCsv);
        await tester.tap(keyed('bank-statement-upload-choose'));
        await tester.pumpAndSettle();
        await tester.tap(keyed('bank-statement-upload-review'));
        await tester.pumpAndSettle();
        expect(find.text('Review Statement Import'), findsOneWidget);
        expect(find.byType(BankStatementUploadDialog), findsNothing);
        expect(
          workspace.database.bankStatements(
            workspace.identity.businessId,
            'bank-a',
          ),
          isEmpty,
        );
        await capture(tester, 'Bank Statement Import Review ${width.toInt()}');
        await tester.tap(find.bySemanticsLabel('Close').last);
        await tester.pumpAndSettle();
        expect(
          workspace.database.bankStatements(
            workspace.identity.businessId,
            'bank-a',
          ),
          isEmpty,
        );
        expect((await workspace.journals()).length, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'account choice binds parsing and commit, preserves exact original bytes, rejects duplicate import',
    (tester) async {
      await prepare(tester, 1224);
      final workspace = await fixture();
      addTearDown(workspace.dispose);
      final selected = file('Fictional USD.csv', validCsv);
      await host(tester, workspace, () async => selected);
      await tester.tap(keyed('bank-statement-upload-choose'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('bank-statement-upload-account'));
      await tester.pumpAndSettle();
      await capture(tester, 'Bank Statement Upload Account Options 1224');
      await tester.tap(keyed('bank-statement-upload-option-bank-b'));
      await tester.pumpAndSettle();
      expect(find.text('Fictional USD.csv'), findsOneWidget);
      await tester.tap(keyed('bank-statement-upload-review'));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD'), findsWidgets);
      await tester.tap(keyed('banking-save-import'));
      await tester.pumpAndSettle();
      final rows = workspace.database.bankStatements(
        workspace.identity.businessId,
        'bank-b',
      );
      expect(rows.length, 1);
      expect(
        workspace.database.bankStatements(
          workspace.identity.businessId,
          'bank-a',
        ),
        isEmpty,
      );
      final saved = workspace.database.bankStatement(
        workspace.identity.businessId,
        rows.single.id,
      )!;
      expect(saved.currency, 'USD');
      expect(saved.sourceBytes, selected.bytes);
      expect((await workspace.journals()).length, 0);
      // Let the preceding success notification finish before testing the
      // distinct duplicate-import warning instead of its Snackbar queue.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.tap(keyed('banking-primary-action'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('bank-statement-upload-choose'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('bank-statement-upload-review'));
      await tester.pumpAndSettle();
      expect(
        find.text('This statement is already imported for this account.'),
        findsOneWidget,
      );
      expect(
        workspace.database
            .bankStatements(workspace.identity.businessId, 'bank-b')
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled chooser preserves file; unsupported format never reaches the parser',
    (tester) async {
      await prepare(tester, 720);
      final workspace = await fixture();
      addTearDown(workspace.dispose);
      BankStatementFile? picked = file('Fictional Statement.csv', validCsv);
      await host(tester, workspace, () async => picked);
      await tester.tap(keyed('bank-statement-upload-choose'));
      await tester.pumpAndSettle();
      picked = null;
      await tester.tap(keyed('bank-statement-upload-choose'));
      await tester.pumpAndSettle();
      expect(find.text('Fictional Statement.csv'), findsOneWidget);
      picked = file('Unsupported.ofx', '<OFX>');
      await tester.tap(keyed('bank-statement-upload-choose'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a CSV or supported bank PDF.'), findsOneWidget);
      expect(find.text('Fictional Statement.csv'), findsOneWidget);
      expect(find.text('Unsupported.ofx'), findsNothing);
      await tester.tap(keyed('bank-statement-upload-close'));
      await tester.pumpAndSettle();
      expect(
        workspace.database.bankStatements(
          workspace.identity.businessId,
          'bank-a',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
