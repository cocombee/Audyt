import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../features/accounting/data/bill_posting_test.dart' show payableAccount;
import '../support/fixed_popout_host.dart';
import '../support/accounting_test_finders.dart';
import 'restored_page_routes_test.dart' show tables;

void main() {
  final inventory = <Map<String, Object?>>[];
  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Bill dialogs preserve owner boundaries and cancel at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 2300);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      installFixedPopoutHost(t);
      final root = Directory.systemTemp.createTempSync('audyt-bill-owner-');
      addTearDown(() => root.deleteSync(recursive: true));
      final w = await AccountingWorkspace.open('${root.path}/books.sqlite');
      addTearDown(w.dispose);
      final (vendor, purchase) = await setupBill(w);
      final payable = await payableAccount(w);
      for (final font in [
        ('Inter', 'assets/fonts/Inter-Variable.woff2'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
      }
      final purchaseTax = w.saveTaxRate(
        CompanyTaxRate(
          id: EntityId.random(),
          name: 'Service Tax',
          percent: '8',
          effectiveFrom: DateTime(2026, 1, 1),
          effectiveThrough: DateTime(2026, 12, 31),
          application: TaxApplication.purchases,
        ),
      );
      final excluded = <CompanyTaxRate>[
        CompanyTaxRate(
          id: EntityId.random(),
          name: 'SST',
          percent: '10',
          effectiveFrom: DateTime(2026, 1, 1),
          application: TaxApplication.sales,
          accountId: payable.account.id,
        ),
        CompanyTaxRate(
          id: EntityId.random(),
          name: 'Expired Service Tax',
          percent: '6',
          effectiveFrom: DateTime(2025, 1, 1),
          effectiveThrough: DateTime(2025, 12, 31),
          application: TaxApplication.purchases,
        ),
        CompanyTaxRate(
          id: EntityId.random(),
          name: 'Inactive Service Tax',
          percent: '8',
          effectiveFrom: DateTime(2026, 1, 1),
          application: TaxApplication.purchases,
          active: false,
        ),
      ].map(w.saveTaxRate).toList();
      final original = billFixture(
        w,
        vendor,
        purchase.account.id,
        attachments: const [],
      );
      final values = billFormValues(original)..['Tax Mode'] = 'Exclusive';
      ((values['_lines'] as List).single as Map)['Tax Rate (%)'] =
          purchaseTax.choice;
      final draft = billFromForm(
        values,
        metadata: original.metadata,
        vendor: vendor,
        purchaseAccountIds: {purchase.account.id.value},
        taxCodes: w.taxRates,
      );
      w.saveBillDraft(draft, expectedRevision: 0);
      final posted = billFixture(
        w,
        vendor,
        purchase.account.id,
        attachments: const [],
      );
      w.saveBillDraft(posted, expectedRevision: 0);
      w.postBill(
        requestId: EntityId.random(),
        billId: posted.id,
        expectedRevision: posted.metadata.revision,
        payableAccountId: payable.account.id,
        approvedAt: DateTime.utc(2026, 10, 2),
      );
      final before = tables(w);
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }

      Future<void> pump() async {
        t.view.physicalSize = Size(width, 2300);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('bill-owner-capture'),
            child: MaterialApp(
              key: UniqueKey(),
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: BillsPage(workspace: w)),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      Future<void> capture(String title, String note) async {
        final directory = Platform.environment['AUDYT_BILL_OWNER_DIR'];
        if (directory == null) return;
        final file = '$title ${width.toInt()}.png';
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('bill-owner-capture')),
        );
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/$file')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        inventory.add({
          'category': 'Accounting popouts',
          'title': title,
          'width': width.toInt(),
          'renderedViewportWidth': t.view.physicalSize.width,
          'file': file,
          'note': note,
          'fields': [
            for (final e in find.byType(FrontendFormDialog).evaluate())
              ...(e.widget as FrontendFormDialog).form.fields.map(
                (f) => f.label,
              ),
          ],
          'fieldMetadata': 'Actual BillsPage opener; isolated records, cancel-only interaction. Fixed entry popup may acquire native width.',
        });
      }

      const ownerNote =
          'Proposal only. Actual BillsPage opener and accepted shared tokens. Ordinary popup fields inherit the measured planner; custom transaction rows, Amount, Memo, information and main-page layouts retain their owners. Fixtures are isolated; every opened workflow is cancelled.';
      await pump();
      await tap(find.byKey(ValueKey('edit-bill-${draft.id}')));
      final form = t.widget<FrontendFormDialog>(
        find.byType(FrontendFormDialog),
      );
      expect(
        form.onCommit,
        isNotNull,
      ); // Real opener, never invoked in this review.
      final date = t.getRect(find.byKey(const ValueKey('design-field-Date')));
      final reference = t.getRect(
        find.byKey(const ValueKey('design-field-Reference')),
      );
      expect(date.width, greaterThanOrEqualTo(accountingCompactDateFieldWidth));
      expect(reference.width, greaterThan(100));
      expect(date.top, lessThanOrEqualTo(reference.top));
      expect(find.byType(AccountingOrdinaryFieldRows), findsWidgets);
      expect(find.byKey(const ValueKey('design-field-Due Date')), findsNothing);
      await capture('Bill Entry · Actual Owner', ownerNote);
      final tax = find
          .byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey is ValueKey &&
                (widget.triggerKey as ValueKey).value.toString().endsWith(
                  '-Tax Rate (%)',
                ),
          )
          .first;
      final offered = t.widget<AccountingSelector<String>>(tax).options;
      expect(
        offered.any((o) => o.value == purchaseTax.choice && o.enabled),
        isTrue,
      );
      expect(offered.any((o) => o.value == '0' && o.enabled), isTrue);
      for (final code in excluded) {
        expect(offered.any((o) => o.value == code.choice), isFalse);
      }
      await tap(tax);
      await capture(
        'Bill Tax Choices · Actual Owner',
        '$ownerNote Purchase/date/status eligible choices only, with full labels in the open menu. Service Tax 8% is manual example company data, not inferred statutory treatment.',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await tap(find.byKey(const ValueKey('design-close')));
      expect(tables(w), before);
      // Reset the fixed entry host's acquired width for ordinary dialog proof.
      t.view.physicalSize = Size(width, 2300);
      await t.pumpAndSettle();
      await tap(find.byKey(ValueKey('bill-more-${draft.id}')));
      await tap(find.byKey(ValueKey('post-bill-${draft.id}')));
      expect(
        t
            .widget<FrontendFormDialog>(find.byType(FrontendFormDialog))
            .form
            .fields
            .single
            .label,
        'Payable Account',
      );
      await capture(
        'Post Bill · Actual Owner',
        '$ownerNote Saved totals are read-only; Payable Account uses current liability eligibility. More precise payables mapping remains a proposed domain change.',
      );
      await tap(find.byKey(const ValueKey('design-close')));
      await tap(find.byKey(ValueKey('bill-more-${posted.id}')));
      await tap(find.byKey(ValueKey('reverse-bill-${posted.id}')));
      expect(
        t
            .widget<FrontendFormDialog>(find.byType(FrontendFormDialog))
            .form
            .fields
            .last
            .multiline,
        isTrue,
      );
      await capture(
        'Reverse Bill · Actual Owner',
        '$ownerNote Reversal Date is ordinary; Reason remains a tall narrative. Original posted purchase is not deleted.',
      );
      await tap(find.byKey(const ValueKey('design-close')));
      await tap(find.byKey(ValueKey('view-bill-${posted.id}')));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Posting Journal'), findsOneWidget);
      await capture(
        'View Posted Bill · Actual Owner',
        '$ownerNote Read-only saved information; no ordinary input planner is applied.',
      );
      await tap(accountingCloseIcon().last);
      await tap(find.byKey(ValueKey('bill-more-${draft.id}')));
      await tap(find.byKey(ValueKey('bill-history-${draft.id}')));
      await capture(
        'Bill History · Actual Owner',
        '$ownerNote Existing record-list and revision-view actions.',
      );
      await tap(
        find.byKey(
          ValueKey('view-bill-revision-${draft.id}-${draft.metadata.revision}'),
        ),
      );
      expect(find.text('Historical Revision'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await capture(
        'View Bill Revision · Actual Owner',
        '$ownerNote Historical snapshot stays read-only and does not inherit current posting facts.',
      );
      await tap(accountingCloseIcon().last);
      await tap(accountingCloseIcon().last);
      expect(tables(w), before);
      expect(t.takeException(), isNull);
    });
  }
  tearDownAll(() {
    final directory = Platform.environment['AUDYT_BILL_OWNER_DIR'];
    if (directory != null) {
      File('$directory/Bill Owner Inventory.json')
          .writeAsStringSync('${jsonEncode(inventory)}\n');
    }
  });
}
