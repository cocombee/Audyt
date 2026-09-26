import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/vendor_persistence_test.dart'
    show vendorFixture;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final consumer in ['Expense', 'Claim', 'Voucher']) {
      testWidgets('saved Vendor reaches $consumer selector at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final root = Directory.systemTemp.createTempSync(
          'audyt-vendor-selector-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final w = await AccountingWorkspace.open('${root.path}/source.sqlite');
        addTearDown(w.dispose);
        final legacy = w.payees.add(
          id: 'legacy-supplier',
          name: 'Previous supplier name',
          type: PayeeType.supplier,
        );
        final shared = w.payees;
        final first = vendorFixture(w, payee: legacy);
        w.saveVendor(first, expectedRevision: 0, expectedPayee: legacy);
        final second = vendorFixture(
          w,
          original: first,
          name: 'Fictional Current Supplier',
        );
        w.saveVendor(second, expectedRevision: 1);
        expect(identical(shared, w.payees), true);
        final before = tables(w);
        void noSave(Object _) =>
            fail('Selecting a supplier must not save or submit a transaction.');
        final page = switch (consumer) {
          'Expense' => RecordExpensePage(payeeStore: shared),
          'Claim' => ClaimEditorDialog(
            id: EntityId.random(),
            payeeStore: shared,
            onSaveDraft: noSave,
            onSubmit: noSave,
          ),
          _ => PaymentVoucherEditorDialog(
            id: 'fictional-voucher',
            payeeStore: shared,
            onSaveDraft: noSave,
            onSubmit: noSave,
          ),
        };
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: page),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(
          ValueKey(switch (consumer) {
            'Expense' => 'expense-field-payee',
            'Claim' => 'claim-payee',
            _ => 'voucher-payee',
          }),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Fictional Current');
        await tester.pumpAndSettle();
        final option = find.byKey(
          ValueKey(
            '${switch (consumer) {
              'Expense' => 'expense-payee-option',
              'Claim' => 'claim-merchant-option',
              _ => 'voucher-payee-option',
            }}-${legacy.id}',
          ),
        );
        expect(option, findsOneWidget);
        expect(find.text('Previous supplier name'), findsNothing);
        await captureUi(tester, 'Vendor $consumer Selector ${width.toInt()}');
        await tester.tap(option);
        await tester.pumpAndSettle();
        final editable = tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(editable.controller.text, second.name);
        expect(tables(w), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
