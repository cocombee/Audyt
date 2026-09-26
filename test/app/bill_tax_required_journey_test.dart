import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Finder selector(String suffix) => find.byWidgetPredicate(
  (w) =>
      w is AccountingSelector<String> &&
      w.triggerKey is ValueKey &&
      (w.triggerKey as ValueKey).value.toString().endsWith(suffix),
);

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Bill amount/tax resolution clears only after deliberate choice at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        final root = Directory.systemTemp.createTempSync(
          'audyt-bill-required-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        final (vendor, account) = await setupBill(w);
        await w.createAccount(
          code: '2299',
          name: 'Fictional Tax Payable',
          type: AccountType.liability,
        );
        final liability = (await w.accounts())
            .singleWhere((a) => a.account.code == '2299')
            .account;
        final code = w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '8',
            effectiveFrom: DateTime(2026, 1, 1),
            effectiveThrough: DateTime(2026, 12, 31),
            application: TaxApplication.purchases,
            accountId: liability.id,
          ),
        );
        final old = billFixture(
          w,
          vendor,
          account.account.id,
          attachments: const [],
        );
        final line = old.lines.single;
        final unknown = PurchaseBillDraft(
          metadata: old.metadata,
          vendorSnapshot: vendor,
          documentNumber: old.documentNumber,
          issueDate: old.bill.issueDate,
          dueDate: old.bill.dueDate,
          terms: old.bill.terms,
          lines: [
            SalesLineItem.category(
              id: line.id,
              categoryId: line.categoryId!,
              description: line.description,
              quantity: line.quantity,
              rate: line.rate,
              discount: line.discount,
            ),
          ],
        );
        w.saveBillDraft(unknown, expectedRevision: 0);
        await tester.runAsync(() async {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        Future<void> pump() async {
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

        Future<void> choose(Finder finder, String text) async {
          await tap(finder);
          await tap(find.widgetWithText(MenuItemButton, text).last);
        }

        Future<void> discardDraft() async {
          await tap(find.byKey(const ValueKey('design-close')));
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(find.byKey(const ValueKey('design-discard-changes')));
        }

        await pump();
        await tap(find.byKey(const ValueKey('new-bill')));
        final basis = selector('design-field-Tax Mode');
        expect(
          tester.widget<AccountingSelector<String>>(basis).value,
          'Exclusive',
        );
        expect(
          tester
              .widget<AccountingSelector<String>>(basis)
              .options
              .map((o) => o.value),
          ['Exclusive', 'Inclusive'],
        );
        expect(find.text('Review Needed'), findsNothing);
        expect(
          find.byKey(const ValueKey('bill-tax-basis-warning')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsNothing,
        );
        await tap(basis);
        await captureUi(tester, 'Bill Amount Basis ${width.toInt()}');
        await tap(find.widgetWithText(MenuItemButton, 'Tax Exclusive').last);
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Date')),
          '01-09-2026',
        );
        await tester.pumpAndSettle();
        final rowTax = selector('-Tax Rate (%)').first;
        expect(
          tester
              .widget<AccountingSelector<String>>(rowTax)
              .options
              .map((o) => o.label),
          ['No Tax', code.label],
        );
        await tap(rowTax);
        expect(find.text('Custom Rate'), findsNothing);
        await captureUi(tester, 'Bill Row Tax ${width.toInt()}');
        await tap(find.widgetWithText(MenuItemButton, 'No Tax').last);
        await discardDraft();
        final before = tables(w);
        await tap(find.byKey(ValueKey('edit-bill-${unknown.id}')));
        expect(
          find.byKey(const ValueKey('bill-tax-basis-warning')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AccountingSelector<String>>(
                selector('-Tax Rate (%)').first,
              )
              .value,
          isNull,
        );
        await captureUi(tester, 'Bill Unknown Legacy ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(
          find.textContaining(
            'Select Tax Exclusive or Tax Inclusive for bill amounts',
          ),
          findsOneWidget,
        );
        expect(tables(w), before);
        await choose(selector('design-field-Tax Mode'), 'Tax Exclusive');
        expect(
          find.byKey(const ValueKey('bill-tax-basis-warning')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsOneWidget,
        );
        await choose(selector('-Tax Rate (%)').first, 'No Tax');
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsNothing,
        );
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        await discardDraft();
        expect(tables(w), before);
        expect(find.byType(FrontendFormDialog), findsNothing);
        await tap(find.byKey(ValueKey('edit-bill-${unknown.id}')));
        expect(
          find.byKey(const ValueKey('bill-tax-basis-warning')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsOneWidget,
        );
        await choose(selector('design-field-Tax Mode'), 'Tax Exclusive');
        await choose(selector('-Tax Rate (%)').first, 'No Tax');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(
          w.database.readBillDraft(w.identity.businessId, unknown.id)!.taxMode,
          'Exclusive',
        );
        expect(
          w.database
              .readBillDraft(w.identity.businessId, unknown.id)!
              .lines
              .single
              .taxRatePercent,
          '0',
        );
        expect(await w.journals(), isEmpty);
        // Date expiry is distinct from a valid saved inactive master revision.
        final base = billFixture(
          w,
          vendor,
          account.account.id,
          attachments: const [],
        );
        final values = billFormValues(base)..['Tax Mode'] = 'Exclusive';
        ((values['_lines'] as List).single as Map)['Tax Rate (%)'] =
            code.choice;
        final linked = billFromForm(
          values,
          metadata: base.metadata,
          vendor: vendor,
          purchaseAccountIds: {account.account.id.value},
          taxCodes: w.taxRates,
        );
        w.saveBillDraft(linked, expectedRevision: 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await pump();
        await tap(find.byKey(ValueKey('edit-bill-${linked.id}')));
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('design-field-Date')),
          '01-01-2027',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('bill-tax-selection-warning')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AccountingSelector<String>>(
                selector('-Tax Rate (%)').first,
              )
              .value,
          isNull,
        );
        await captureUi(tester, 'Bill Expired Tax ${width.toInt()}');
        final expiryBefore = tables(w);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(
          find.textContaining('Tax code changed or is unavailable'),
          findsOneWidget,
        );
        expect(tables(w), expiryBefore);
        await discardDraft();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(
          w.database.readBillDraft(w.identity.businessId, linked.id)!.toJson(),
          linked.toJson(),
        );
        expect(
          w.database.readBillDraft(w.identity.businessId, unknown.id)!.total,
          unknown.total,
        );
        expect(await w.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
