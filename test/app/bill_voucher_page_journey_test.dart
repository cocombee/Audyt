import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/purchases/bill_voucher_provenance_test.dart'
    show BillVoucherFixture;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored Bill voucher picker and payment/bank confirmations use real allocation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
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
          'audyt-bill-voucher-ui-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final f = await BillVoucherFixture.create('${root.path}/source.sqlite');
        final source = f.sources.singleWhere(
          (s) => s.id == '${f.ids[0].value}/${f.first.id.value}',
        );
        final archive = f.w.database.exportDataArchive(
          f.w.identity.businessId,
          DateTime.utc(2026, 10, 1),
        );
        final initial = tables(f.w);
        f.w.dispose();
        final originalBytes = File('${root.path}/source.sqlite')
            .readAsBytesSync();
        final w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        addTearDown(w.dispose);
        expect(tables(w), initial);
        final restored = BillVoucherFixture(w, f.ids, f.first, f.second);
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> enter(String key, String value) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.enterText(finder, value);
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: w,
                showInitialSetup: false,
                initialPath: '/expenses-vendors',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = tester.widget<AccountingTabs>(
          find.byKey(const ValueKey('area-tabs-expenses-vendors')),
        );
        await tap(
          find.byKey(
            ValueKey(
              'preview-tab-expenses-vendors-${tabs.labels.indexOf('Payment Vouchers')}',
            ),
          ),
        );
        Future<void> choose() async {
          await tap(find.byKey(const ValueKey('voucher-source-selector')));
          await captureUi(
            tester,
            'Bill Voucher Source Picker ${width.toInt()}',
          );
          await tap(
            find
                .widgetWithText(
                  MenuItemButton,
                  '${source.payee} · RM 60.00 · ${source.detail}',
                )
                .last,
          );
        }

        await tap(find.text('New Voucher'));
        await choose();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('voucher-amount')),
              )
              .controller!
              .text,
          '60.00',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('voucher-account')),
            matching: find.textContaining('Fictional Bank'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('voucher-date')))
              .controller!
              .text,
          '15-09-2026',
        );
        await captureUi(
          tester,
          'Bill Voucher Selected Source ${width.toInt()}',
        );
        await tap(find.bySemanticsLabel('Close').last);
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(find.byKey(const ValueKey('voucher-discard-changes')));
        expect(tables(w), initial);
        await tap(find.text('New Voucher'));
        await choose();
        await tap(find.byKey(const ValueKey('voucher-method')));
        await tap(find.widgetWithText(MenuItemButton, 'Bank Transfer').last);
        await enter('voucher-reference', 'Fictional Bill voucher UI');
        await enter('voucher-amount', '61');
        await tap(find.byKey(const ValueKey('voucher-save-draft')));
        expect(
          find.byKey(const ValueKey('voucher-editor-error')),
          findsOneWidget,
        );
        expect(tables(w), initial);
        await enter('voucher-amount', '60');
        await tap(find.byKey(const ValueKey('voucher-submit')));
        expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
        final voucher = w.vouchers.all.single;
        expect(voucher.sourceId, source.id);
        Future<void> action(String suffix) async {
          final target = find.byKey(ValueKey('voucher-$suffix-${voucher.id}'));
          if (target.evaluate().isEmpty) {
            await tap(find.byKey(ValueKey('voucher-more-${voucher.id}')));
          }
          await tap(target);
        }

        await action('approve');
        expect(
          w.vouchers.byId(voucher.id)!.status,
          PaymentVoucherStatus.approved,
        );
        var before = tables(w);
        await action('pay');
        final rows = tester
            .widget<AccountingInformationRows>(
              find.descendant(
                of: find.byKey(
                  ValueKey('voucher-payment-confirmation-${voucher.id}'),
                ),
                matching: find.byType(AccountingInformationRows),
              ),
            )
            .rows;
        expect(rows, contains(('Amount', 'RM 60.00')));
        expect(rows, contains(('Bank Movement', 'RM 100.00')));
        expect(rows, contains(('Posted Date', '15-09-2026')));
        expect(
          rows,
          contains(('Source', 'Bill Settlement · ${source.detail}')),
        );
        await captureUi(
          tester,
          'Bill Voucher Batch Confirmation ${width.toInt()}',
        );
        await tap(find.bySemanticsLabel('Close').last);
        expect(tables(w), before);
        await action('pay');
        await tap(find.byKey(ValueKey('voucher-confirm-pay-${voucher.id}')));
        final paid = w.vouchers.byId(voucher.id)!;
        expect(paid.paymentEvidence!.journalId, f.first.journalId);
        final paidTables = tables(w);
        for (final name in before.keys.where(
          (n) => !{'payment_vouchers', 'ledger_audit'}.contains(n),
        )) {
          expect(paidTables[name], before[name], reason: name);
        }
        final statement = restored.acceptMatches();
        before = tables(w);
        await action('reconcile');
        expect(
          find.textContaining('Complete the current bank reconciliation'),
          findsOneWidget,
        );
        expect(tables(w), before);
        final completion = restored.complete(statement);
        await action('reconcile');
        expect(
          w.vouchers.byId(voucher.id)!.reconciliationEvidence!.completionId,
          completion,
        );
        await captureUi(tester, 'Bill Voucher Reconciled ${width.toInt()}');
        before = tables(w);
        final recovery = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.utc(2026, 10, 3),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        w.dispose();
        final reopened = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        expect(tables(reopened), before);
        reopened.dispose();
        final recovered = await AccountingWorkspace.emptyRestore(
          '${root.path}/again.sqlite',
          recovery,
        );
        expect(tables(recovered), before);
        expect(
          recovered.vouchers
              .verification(recovered.vouchers.byId(voucher.id)!)
              .status,
          PaymentVoucherStatus.reconciled,
        );
        recovered.dispose();
        expect(
          File('${root.path}/source.sqlite').readAsBytesSync(),
          originalBytes,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
