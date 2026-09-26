import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_spacing_visual_test.dart' show capture;

void main() {
  for (final width in [1224.0, 720.0, 620.0]) {
    testWidgets('populated page rows share the accepted inline gap at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final claims = ClaimStore.demo();
      final vouchers = PaymentVoucherStore.demo();
      addTearDown(claims.dispose);
      addTearDown(vouchers.dispose);
      final pages = <String, Widget>{
        'Expenses': ExpenseIntakePage(
          workspace: workspace,
          onRecordExpense: () {},
        ),
        'Claims': ClaimsPage(store: claims),
        'Vouchers': PaymentVouchersPage(store: vouchers),
        'Invoices': InvoicePage(workspace: workspace),
        'Customer Receipts': CustomerReceiptsPage(workspace: workspace),
      };
      for (final page in pages.entries) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: page.value),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rows = tester
            .widgetList<AccountingRecordRow>(find.byType(AccountingRecordRow))
            .where((row) => row.status != null)
            .toList();
        expect(rows, isNotEmpty, reason: page.key);
        var adjacent = 0;
        for (final row in rows) {
          final owner = find.byWidget(row);
          final status = find.descendant(
            of: owner,
            matching: find.byWidget(row.status!),
          );
          if (status.evaluate().isEmpty) continue;
          final label = find
              .descendant(of: status, matching: find.byType(Text))
              .first;
          final statusBox = tester.getRect(status);
          final labelBox = tester.getRect(label);
          expect(
            labelBox.left - statusBox.left,
            closeTo(8, .1),
            reason: '${page.key}: badge left padding',
          );
          expect(
            statusBox.right - labelBox.right,
            closeTo(8, .1),
            reason: '${page.key}: badge right padding',
          );
          final title = find
              .descendant(
                of: owner,
                matching: find.byWidgetPredicate(
                  (widget) => widget is Text && widget.data == row.title,
                ),
              )
              .first;
          final a = tester.getRect(title);
          final b = tester.getRect(status);
          if ((a.center.dy - b.center.dy).abs() >= 2) continue;
          adjacent++;
          expect(
            b.left - a.right,
            closeTo(accountingRecordTitleLabelGap, 0.1),
            reason: '${page.key}: ${row.title}',
          );
        }
        if (width == 1224) expect(adjacent, greaterThan(0), reason: page.key);
        expect(tester.takeException(), isNull, reason: page.key);
        await capture(tester, key, 'Row Labels ${page.key} ${width.toInt()}');
      }
    });
    testWidgets('boxed list footer keeps its existing text axis at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingRecordList(
              children: [
                for (var index = 0; index < 6; index++)
                  AccountingRecordRow(
                    title: 'Fuel $index',
                    titleKey: ValueKey('fuel-title-$index'),
                    details: const Text('01-09-2026'),
                    trailing: const Text('RM 20.00'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getRect(
        find.byKey(const ValueKey('record-page-size-label')),
      );
      expect(
        label.left,
        tester.getRect(find.byKey(const ValueKey('fuel-title-0'))).left,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('record-page-size'))).left -
            label.right,
        closeTo(accountingContentInset, 0.1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
