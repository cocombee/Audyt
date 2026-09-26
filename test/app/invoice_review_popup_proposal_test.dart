import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restored_page_routes_test.dart' show tables;

void main() {
  test('live invoice shortcut retains command keys and currency; extension is opt-in', () {
    final invoice = Invoice.draft(
      id: EntityId.random(),
      customerId: EntityId.random(),
      total: Money.fromMinor(10000, 'USD'),
      issueDate: DateTime(2026, 10, 2),
    );
    final current = invoicePaymentReviewForm(
      invoice: invoice,
      paymentAccounts: {'bank': 'Example Bank'},
      paidMinor: 2000,
      creditedMinor: 1000,
    );
    expect(current.fields.map((f) => f.label), [
      'Amount',
      'Date',
      'Reference',
      'Bank Account',
    ]);
    expect(current.defaultCurrencyCode, 'USD');
    expect(current.fields.first.currencyCode, 'USD');
    expect(current.description, contains('70.00'));
    expect(current.evidence, isFalse);
    final proposed = invoicePaymentReviewForm(
      invoice: invoice,
      paymentAccounts: {'bank': 'Example Bank'},
      paidMinor: 2000,
      creditedMinor: 1000,
      proposal: true,
    );
    expect(
      proposed.fields.where((f) => f.currencyCode != null).single.label,
      'Amount Received',
    );
    expect(
      proposed.fields.last.descriptionRole,
      AccountingDescriptionRole.memo,
    );
    expect(proposed.evidence, isTrue);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'invoice shortcut proposal fits ordinary fields and protects Amount/Memo at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final before = tables(w);
        final record = w.postedInvoices().firstWhere(
          (record) => record.documentNumber == 'DEMO-INV-001',
        );
        final invoice = record.sourceDraft;
        final outstanding = invoiceMoney(
          Money.fromMinor(
            invoice.total.minorUnits - record.paidMinor - record.creditedMinor,
            invoice.total.currency,
          ),
        );
        final form = invoicePaymentReviewForm(
          invoice: invoice,
          paymentAccounts: {'bank': 'Demo Bank · Bank · RM'},
          paidMinor: record.paidMinor,
          creditedMinor: record.creditedMinor,
          proposal: true,
        );
        Map<String, Object?>? kept;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    kept = await showDialog<Map<String, Object?>>(
                      context: context,
                      builder: (_) => FrontendFormDialog(
                        form: form,
                        informationRows: [('Outstanding', outstanding)],
                        initial: {
                          'Payment Date': '02-10-2026',
                          'Reference': 'BANK-001',
                          'Payment Method': 'Bank Transfer',
                          'Deposit To': 'bank',
                          'Amount Received': '750.00',
                          'Memo': 'Payment for the selected invoice.',
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FrontendFormDialog>(find.byType(FrontendFormDialog))
              .onCommit,
          isNull,
        );
        final dialog = tester.getRect(find.byType(AlertDialog));
        for (final label in [
          'Payment Date',
          'Reference',
          'Payment Method',
          'Deposit To',
          'Amount Received',
        ]) {
          final rect = tester.getRect(
            find.byKey(ValueKey('design-field-$label')),
          );
          expect(rect.left, greaterThanOrEqualTo(dialog.left));
          expect(rect.right, lessThanOrEqualTo(dialog.right));
          expect(rect.height, accountingControlHeight);
        }
        expect(
          tester
              .getRect(find.byKey(const ValueKey('design-field-Payment Date')))
              .top,
          tester
              .getRect(find.byKey(const ValueKey('design-field-Reference')))
              .top,
        );
        expect(find.text('Amount Received (RM)'), findsOneWidget);
        expect(find.text(outstanding), findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-field-Outstanding')),
          findsNothing,
        );
        final amount = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('design-field-Amount Received')),
            matching: find.byType(TextField),
          ),
        );
        expect(amount.decoration!.prefixText, isNull);
        expect(amount.decoration!.prefixIcon, isNull);
        expect(
          tester
              .widget<AccountingDescriptionField>(
                find.byKey(const ValueKey('design-field-Memo')),
              )
              .role,
          AccountingDescriptionRole.memo,
        );
        expect(
          find.byKey(const ValueKey('design-choose-files')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('receipt-example-records')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(tables(w), before);
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(kept!['Amount Received'], '750.00');
        expect(kept!['Payment Method'], 'Bank Transfer');
        expect(kept!['Deposit To'], 'bank');
        expect(tables(w), before);
        expect(tester.takeException(), isNull);
      },
    );

    for (final hasTax in [false, true]) {
      testWidgets(
        'actual posting review ${hasTax ? 'with' : 'without'} tax at $width keeps source unchanged',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final w = await createDemoWorkspace();
          addTearDown(w.dispose);
          final before = tables(w);
          final accounts = (await w.accounts())
              .map((r) => r.account)
              .where((a) => a.status == AccountStatus.active && !a.isParent)
              .toList();
          final taxAccount = Account.create(
            id: EntityId.random(),
            code: '2200',
            name: 'Service Tax Payable',
            type: AccountType.liability,
          );
          if (hasTax) accounts.add(taxAccount);
          final form = invoicePostingReviewForm(
            hasTax: hasTax,
            accounts: accounts,
          );
          Map<String, Object?>? kept;
          await tester.pumpWidget(
            MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      kept = await showDialog<Map<String, Object?>>(
                        context: context,
                        builder: (_) => FrontendFormDialog(
                          form: form,
                          initial: {
                            'Document Number': 'DEMO-INV-003',
                            'Receivable Account': accounts
                                .firstWhere((a) => a.code == '1100')
                                .id
                                .value,
                            if (hasTax) 'Tax Account': taxAccount.id.value,
                          },
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final dialog = tester.getRect(find.byType(AlertDialog));
          for (final field in form.fields) {
            final rect = tester.getRect(
              find.byKey(ValueKey('design-field-${field.label}')),
            );
            expect(rect.left, greaterThanOrEqualTo(dialog.left));
            expect(rect.right, lessThanOrEqualTo(dialog.right));
            expect(rect.height, accountingControlHeight);
          }
          expect(
            find.byKey(const ValueKey('design-field-Tax Account')),
            hasTax ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('design-review')));
          await tester.pumpAndSettle();
          expect(tables(w), before);
          await tester.tap(find.byKey(const ValueKey('design-review')));
          await tester.pumpAndSettle();
          expect(kept!['Document Number'], 'DEMO-INV-003');
          expect(tables(w), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
