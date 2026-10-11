import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_payment_term.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import '../support/accounting_text_input.dart' show enterAccountingText;
import 'claim_receipts_proposal_test.dart' show capture, prepare, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1162.0]) {
    testWidgets('Bill selects exact named rule and reopens generic at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      final root = Directory.systemTemp.createTempSync('bill-term-choice-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/books.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      final (vendor, _) = await setupBill(workspace);
      final fixed = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Net 30', // Deliberately differs from its 45-day rule.
          rule: PaymentTerms.daysAfterIssue(45),
        ),
      );
      final monthly = workspace.createPaymentTerm(
        CompanyPaymentTerm(
          id: EntityId.random(),
          name: 'Monthly 20',
          rule: PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5),
        ),
      );
      Finder key(String name) => find.byKey(ValueKey(name)).last;
      Future<void> host() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: BillsPage(workspace: workspace)),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> fill(String name, String value) =>
          enterAccountingText(tester, key('design-field-$name'), value);
      Future<void> choose(String name, String label) async {
        await tap(tester, key('design-field-$name'));
        await tap(tester, find.text(label).last);
      }

      Future<void> fillLine(String suffix, String value) async {
        final field = find.byWidgetPredicate(
          (widget) =>
              (widget is TextFormField ||
                  widget is AccountingDescriptionField) &&
              widget.key is ValueKey &&
              (widget.key as ValueKey).value.toString().endsWith('-$suffix'),
        );
        await tester.ensureVisible(field);
        await enterAccountingText(tester, field, value);
        await tester.pumpAndSettle();
      }

      AccountingSelector<String> selectorFor(String label) =>
          tester.widget<AccountingSelector<String>>(
            find
                .ancestor(
                  of: key('design-field-$label'),
                  matching: find.byType(AccountingSelector<String>),
                )
                .last,
          );
      AccountingSelector<String> termsSelector() =>
          selectorFor('Payment Terms');

      await host();
      await tap(tester, key('new-bill'));
      await choose('Counterparty', vendor.name);
      await fill('Date', '01-09-2026');
      await fill('Reference', 'Named Bill reference');
      final accountSelector = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            widget.triggerKey is ValueKey &&
            (widget.triggerKey as ValueKey).value.toString().endsWith(
              '-Account',
            ),
      );
      await tap(tester, accountSelector);
      await tap(tester, find.text('Fictional Purchase').last);
      await fillLine('Description', 'Fictional named purchase');
      await fillLine('Amount', '100');
      final parentBeforeChild = tables(workspace);

      await tap(tester, key('design-field-Payment Terms'));
      expect(find.text('Net 30'), findsOneWidget);
      expect(find.text('Net 30 · Saved Term'), findsOneWidget);
      await tap(tester, find.text('Add Term'));
      await fill('Name', 'Cancelled Child');
      await tap(tester, accountingCloseIcon().last);
      await tap(tester, find.text('Discard').last);
      expect(tables(workspace), parentBeforeChild);
      expect(termsSelector().value, 'Use Vendor Default');

      await tap(tester, key('design-field-Payment Terms'));
      await tap(tester, find.text('Add Term'));
      await fill('Name', 'Inline 12');
      await fill('Due In Days', '12');
      await tap(tester, key('design-review'));
      await tap(tester, key('design-review'));
      expect(workspace.paymentTerms, hasLength(3));
      expect(termsSelector().value, 'Use Vendor Default');
      expect(
        tester
            .widget<TextFormField>(key('design-field-Reference'))
            .controller!
            .text,
        'Named Bill reference',
      );
      await tap(tester, key('design-field-Payment Terms'));
      expect(find.text('Inline 12'), findsOneWidget);
      await capture(tester, 'Bill Named Terms Refreshed ${width.toInt()}');
      await tap(tester, find.text('Net 30 · Saved Term'));
      expect(termsSelector().value, isNot('Net 30'));
      await capture(tester, 'Bill Named Fixed Selected ${width.toInt()}');
      await tap(tester, key('design-review'));
      expect(find.text('Net 45'), findsWidgets);
      await capture(tester, 'Bill Named Fixed Review ${width.toInt()}');
      await tap(tester, key('design-review'));

      var bill = workspace.database
          .billDraftPage(
            businessId: workspace.identity.businessId,
            posted: null,
          )
          .records
          .singleWhere(
            (bill) => bill.supplierReference == 'Named Bill reference',
          );
      expect(bill.bill.terms.toJson(), fixed.rule.toJson());
      expect(bill.bill.dueDate, DateTime.utc(2026, 10, 16));
      expect(bill.supplierReference, 'Named Bill reference');
      expect(await workspace.journals(), isEmpty);

      await tap(tester, key('edit-bill-${bill.id}'));
      expect(termsSelector().value, 'Days After Issue');
      expect(
        tester
            .widget<TextFormField>(key('design-field-Number Of Days'))
            .controller!
            .text,
        '45',
      );
      await capture(tester, 'Bill Named Generic Reopen ${width.toInt()}');
      await fill('Date', '18-09-2026');
      await choose('Payment Terms', 'Monthly 20');
      await capture(tester, 'Bill Named Monthly Selected ${width.toInt()}');
      await tap(tester, key('design-review'));
      await capture(tester, 'Bill Named Monthly Review ${width.toInt()}');
      await tap(tester, key('design-review'));
      bill = workspace.database.readBillDraft(
        workspace.identity.businessId,
        bill.id,
      )!;
      expect(bill.bill.terms.toJson(), monthly.rule.toJson());
      expect(bill.bill.dueDate, DateTime.utc(2026, 10, 20));
      expect(bill.supplierReference, 'Named Bill reference');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      bill = workspace.database.readBillDraft(
        workspace.identity.businessId,
        bill.id,
      )!;
      expect(bill.bill.terms.toJson(), monthly.rule.toJson());
      expect(bill.bill.dueDate, DateTime.utc(2026, 10, 20));
      await host();
      await tap(tester, key('edit-bill-${bill.id}'));
      expect(termsSelector().value, 'Day Of Month');
      expect(selectorFor('Monthly Due Day').value, '20');
      expect(
        tester
            .widget<TextFormField>(key('design-field-Rollover Within Days'))
            .controller!
            .text,
        '5',
      );
      await capture(tester, 'Bill Named Generic Restart ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
