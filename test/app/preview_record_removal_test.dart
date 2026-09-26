import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final (area, title) in [
      ('taxes', 'Tax Overview'),
      ('taxes', 'Returns & Payments'),
      ('sales-customers', 'Sales Receipts'),
      ('sales-customers', 'Refunds'),
      ('expenses-vendors', 'Supplier Credits'),
      ('expenses-vendors', 'Purchase Orders'),
    ]) {
      testWidgets(
        '$title preview removal cancels, persists in session and restores at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final w = await AccountingWorkspace.open(':memory:');
          addTearDown(w.dispose);
          final before = tables(w);
          final form = frontendAreas[area]!.singleWhere(
            (f) => f.title == title,
          );
          final records = demoRecords(form);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: DemoCompany(
                  child: Scaffold(
                    body: FrontendAreaPage(
                      area: area,
                      title: title,
                      formsOverride: [form],
                      workspace: w,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> tap(Finder f) async {
            await tester.ensureVisible(f);
            await tester.pumpAndSettle();
            await tester.tap(f);
            await tester.pumpAndSettle();
          }

          Finder delete(Map<String, Object?> r) =>
              find.byKey(ValueKey('delete-record-${r['_reference']}'));
          for (final r in records) {
            final permitted = const {
              'Draft',
              'Pending Review',
              'Pending Approval',
              'Rejected',
              'Declined',
            }.contains(r['_status']);
            expect(
              tester.widget<IconButton>(delete(r)).onPressed != null,
              permitted,
              reason: '${r['_status']}',
            );
          }
          await tap(delete(records.first));
          await tap(find.byKey(const ValueKey('cancel-remove-preview')));
          expect(delete(records.first), findsOneWidget);
          for (final r in records.take(2)) {
            await tap(delete(r));
            await tap(find.byKey(const ValueKey('confirm-remove-preview')));
            expect(delete(r), findsNothing);
          }
          // A rebuild used to regenerate every fixture row. Removed identities
          // must stay absent while another preview form opens and cancels.
          await tap(find.byKey(const ValueKey('design-open-form')));
          // Linked Refund/Supplier Credit routes are Close-only reviews;
          // ordinary editable preview forms expose the existing Cancel footer.
          final cancel = find.byKey(const ValueKey('design-cancel'));
          await tap(
            cancel.evaluate().isNotEmpty ? cancel : accountingCloseIcon().last,
          );
          for (final r in records.take(2)) {
            expect(delete(r), findsNothing);
          }
          if (title == 'Tax Overview') {
            await captureUi(tester, 'Preview Tax Removal ${width.toInt()}');
          }
          await tap(find.byKey(ValueKey('restore-previews-$title')));
          for (final r in records.take(2)) {
            expect(delete(r), findsOneWidget);
          }
          expect(tables(w), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
