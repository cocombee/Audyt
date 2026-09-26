import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../support/accounting_text_input.dart';
import '../support/fitting_field_row.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'configured Bill tax reviews, cancels, saves and survives restart at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('audyt-bill-tax-');
        addTearDown(() => dir.deleteSync(recursive: true));
        var w = await AccountingWorkspace.open('${dir.path}/book.sqlite');
        addTearDown(() => w.dispose());
        final (vendor, account) = await setupBill(w);
        await w.createAccount(
          code: '2299',
          name: 'Fictional Tax Payable',
          type: AccountType.liability,
        );
        final taxAccount = (await w.accounts())
            .singleWhere((a) => a.account.code == '2299')
            .account;
        final code = w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '8',
            effectiveFrom: DateTime(2026, 1, 1),
            application: TaxApplication.purchases,
            accountId: taxAccount.id,
          ),
        );
        final source = billFixture(
          w,
          vendor,
          account.account.id,
          attachments: const [],
        );
        final values = billFormValues(source)..['Tax Mode'] = 'Exclusive';
        ((values['_lines'] as List).single as Map)['Tax Rate (%)'] =
            code.choice;
        final bill = billFromForm(
          values,
          metadata: source.metadata,
          vendor: vendor,
          purchaseAccountIds: {account.account.id.value},
          taxCodes: w.taxRates,
        );
        w.saveBillDraft(bill, expectedRevision: 0);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        Future<void> pumpPage() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(body: BillsPage(workspace: w)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await pumpPage();
        final before = tables(w);
        await tap(find.byKey(ValueKey('edit-bill-${bill.id}')));
        expectFittingFieldRow(tester, [
          'design-field-Payment Terms',
          'design-field-Currency',
          'design-field-Tax Mode',
          'design-field-Make Recurring',
        ]);
        final termsRect = tester.getRect(
          find.byKey(const ValueKey('design-field-Payment Terms')),
        );
        final daysRect = tester.getRect(
          find.byKey(const ValueKey('design-field-Number Of Days')),
        );
        final currencyRect = tester.getRect(
          find.byKey(const ValueKey('design-field-Currency')),
        );
        expect(daysRect.top, closeTo(termsRect.top, .01));
        expect(daysRect.width, closeTo(termsRect.width, .01));
        expect(currencyRect.width, closeTo(daysRect.width, .01));
        expect(daysRect.left - termsRect.right, closeTo(20, .01));
        expect(currencyRect.left - daysRect.right, closeTo(20, .01));
        await captureUi(tester, 'Configured Bill Tax Editor ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.textContaining('Could not review:'), findsNothing);
        expect(find.byType(AccountingInformationRows), findsWidgets);
        expect(find.text('RM 151.20'), findsWidgets);
        await captureUi(tester, 'Configured Bill Tax Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-close')));
        expect(tables(w), before);

        // Reopen an existing historical code after a master edit/deactivation.
        // Its frozen 8% revision must remain reviewable, rather than resolving 9%.
        w.saveTaxRate(
          CompanyTaxRate.fromJson({
            ...code.toJson(),
            'percent': '9',
            'active': false,
          }),
        );
        await pumpPage();
        await tap(find.byKey(ValueKey('edit-bill-${bill.id}')));
        final memo = find.byKey(const ValueKey('design-field-Memo'));
        await tester.ensureVisible(memo);
        await enterAccountingText(tester, memo, 'Saved configured tax review');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.textContaining('Could not review:'), findsNothing);
        expect(find.text('RM 151.20'), findsWidgets);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(await w.journals(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open('${dir.path}/book.sqlite');
        final saved = w.database.readBillDraft(w.identity.businessId, bill.id)!;
        expect(saved.memo, 'Saved configured tax review');
        expect(saved.lines.single.taxSnapshot!.choice, code.choice);
        expect(saved.lines.single.taxSnapshot!.percent, '8');
        expect(saved.total.minorUnits, 15120);
        expect(await w.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
