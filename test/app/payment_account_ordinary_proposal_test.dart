import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/payment_account_dialog.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare;
import 'journal_workspace_integration_test.dart' show captureUi;

Finder keyed(String name) => find.byKey(ValueKey(name));

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Banking Add Account measured fields and database save at $width scale $scale',
        (tester) async {
          await prepare(tester, width);
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          final originalCount = workspace.paymentAccounts.length;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: BankingPage(workspace: workspace, compact: true),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(keyed('documents-add-bank'));
          await tester.tap(keyed('documents-add-bank'));
          await tester.pumpAndSettle();
          expect(find.text('Cancel'), findsNothing);
          expect(keyed('payment-account-number'), findsNothing);
          await captureUi(
            tester,
            'Bank Account Empty ${width.toInt()}${scale == 1 ? '' : ' Scale 2'}',
          );
          await tester.tap(keyed('payment-account-create'));
          await tester.pumpAndSettle();
          expect(find.text('Choose a bank to continue.'), findsOneWidget);
          await tester.tap(keyed('payment-account-bank-control'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-bank-option-cimb-bank'));
          await tester.pumpAndSettle();
          expect(keyed('payment-account-number'), findsOneWidget);
          final groups = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(AccountingOrdinaryFields),
          );
          expect(groups, findsOneWidget);
          final bank = tester.getRect(keyed('payment-account-bank-control'));
          final type = tester.getRect(keyed('payment-account-type-control'));
          if (scale == 1) {
            expect(type.top, closeTo(bank.top, 0.1));
            expect(type.left - bank.right, closeTo(20, 0.1));
          } else {
            expect(type.top, greaterThan(bank.bottom));
            expect(type.left, closeTo(bank.left, 0.1));
          }
          expect(
            find.descendant(
              of: keyed('payment-account-currency-control'),
              matching: find.text('RM'),
            ),
            findsOneWidget,
          );
          await tester.enterText(
            keyed('payment-account-number'),
            '123456789012',
          );
          await tester.enterText(
            keyed('payment-account-holder'),
            'Aina Rahman',
          );
          await tester.enterText(
            keyed('payment-account-name'),
            'operating Account',
          );
          await tester.pumpAndSettle();
          await captureUi(
            tester,
            'Bank Account Fitted ${width.toInt()}${scale == 1 ? '' : ' Scale 2'}',
          );
          final holderState = tester.state<EditableTextState>(
            find.descendant(
              of: keyed('payment-account-holder'),
              matching: find.byType(EditableText),
            ),
          );
          await tester.tap(keyed('payment-account-holder'));
          await tester.enterText(
            keyed('payment-account-holder'),
            'Aina Nur Rahman Bin Abdullah Company Holdings',
          );
          await tester.pumpAndSettle();
          final afterState = tester.state<EditableTextState>(
            find.descendant(
              of: keyed('payment-account-holder'),
              matching: find.byType(EditableText),
            ),
          );
          expect(identical(holderState, afterState), isTrue);
          expect(afterState.widget.focusNode.hasFocus, isTrue);
          expect(
            afterState.widget.controller.selection.baseOffset,
            afterState.widget.controller.text.length,
          );
          await captureUi(
            tester,
            'Bank Account Long Name ${width.toInt()}${scale == 1 ? '' : ' Scale 2'}',
          );
          await tester.tap(keyed('payment-account-currency-control'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-currency-option-USD'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-bank-control'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-bank-option-bank-islam'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-create'));
          await tester.pumpAndSettle();
          expect(
            find.text('Choose a currency supported by Bank Islam.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(keyed('payment-account-number'))
                .controller!
                .text,
            '123456789012',
          );
          expect(
            tester
                .widget<TextField>(keyed('payment-account-name'))
                .controller!
                .text,
            'Operating Account',
          );
          await tester.tap(keyed('payment-account-currency-control'));
          await tester.pumpAndSettle();
          expect(keyed('payment-account-currency-option-USD'), findsNothing);
          await tester.tap(keyed('payment-account-currency-option-MYR'));
          await tester.pumpAndSettle();
          await tester.tap(keyed('payment-account-create'));
          await tester.pumpAndSettle();
          expect(workspace.paymentAccounts.length, originalCount + 1);
          final saved = workspace.paymentAccounts.singleWhere(
            (a) => a.name == 'Operating Account',
          );
          expect(saved.bankId, 'bank-islam');
          expect(saved.currency.code, 'MYR');
          expect(saved.accountNumber, '123456789012');
          expect(
            saved.accountHolderName,
            'Aina Nur Rahman Bin Abdullah Company Holdings',
          );
          final stored = workspace.database
              .readPaymentAccounts(workspace.identity.businessId)
              .singleWhere((a) => a.id == saved.id);
          expect(stored.name, saved.name);
          expect(stored.bankId, saved.bankId);
          expect(stored.accountHolderName, saved.accountHolderName);
          expect(stored.accountNumber, saved.accountNumber);
          expect(stored.currency, saved.currency);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      testWidgets(
        'Edit Account reflow, currency change and Close preserve source at $width scale $scale',
        (tester) async {
          await prepare(tester, width);
          final initial = PaymentAccount.create(
            id: 'retained-account',
            name: 'Operating Account',
            type: PaymentAccountType.bank,
            currencyCode: 'MYR',
            bankId: 'cimb-bank',
            bankName: 'CIMB Bank',
            accountNumber: '123456',
            accountHolderName: 'Aina Rahman',
          );
          PaymentAccount? result;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      child: const Text('Edit'),
                      onPressed: () async {
                        result = await showPaymentAccountDialog(
                          context,
                          preferredCurrencyCode: 'MYR',
                          newId: () => throw StateError('Edit must retain ID'),
                          initial: initial,
                          buildLabel: (c, l, r) =>
                              accountingFieldLabel(c, l, alignToField: true),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          await tester.enterText(keyed('payment-account-name'), 'changed');
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(result, isNull);
          expect(initial.name, 'Operating Account');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
