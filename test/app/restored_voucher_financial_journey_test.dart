import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../features/purchases/voucher_financial_evidence_test.dart'
    show VoucherFinancialFixture;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('restored voucher payment and current bank status at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final root = Directory.systemTemp.createTempSync('voucher-financial-ui-');
      addTearDown(() => root.deleteSync(recursive: true));
      final originalPath = '${root.path}/original.sqlite';
      final original = await VoucherFinancialFixture.create(originalPath);
      final voucher = original.approveVoucher();
      final baseline = tables(original.workspace);
      final archive = original.workspace.database.exportDataArchive(
        original.workspace.identity.businessId,
        DateTime.utc(2026, 9, 27),
      );
      original.workspace.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final path = '${root.path}/restored.sqlite';
      var w = await AccountingWorkspace.emptyRestore(path, archive);
      addTearDown(() => w.dispose());
      final f = VoucherFinancialFixture(
        w,
        original.expense,
        original.bank,
        original.cost,
      );
      expect(tables(w), baseline);
      Future<void> tap(Finder finder) async {
        if (finder.hitTestable().evaluate().isEmpty) {
          await tester.ensureVisible(finder);
        }
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) =>
          captureUi(tester, 'Voucher Financial $state ${width.toInt()}');
      Future<void> action(String suffix) async {
        final target = find.byKey(ValueKey('voucher-$suffix-${voucher.id}'));
        if (target.evaluate().isEmpty) {
          await tap(find.byKey(ValueKey('voucher-more-${voucher.id}')));
        }
        await tap(target);
      }

      Future<void> page() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: w, showInitialSetup: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(
          find.byKey(const ValueKey('navigation-item-expenses-vendors')),
        );
        await tap(find.text('Payment Vouchers').first);
      }

      await page();
      await action('pay');
      expect(
        find.byKey(ValueKey('voucher-payment-confirmation-${voucher.id}')),
        findsNothing,
      );
      expect(
        find.textContaining('Review and post the source payment'),
        findsOneWidget,
      );
      expect(tables(w), baseline);
      await capture('Unposted Rejected');
      await f.postExpense();
      final posted = tables(w);
      await action('pay');
      final confirmationRows = tester
          .widget<AccountingInformationRows>(
            find.descendant(
              of: find.byKey(
                ValueKey('voucher-payment-confirmation-${voucher.id}'),
              ),
              matching: find.byType(AccountingInformationRows),
            ),
          )
          .rows;
      expect(confirmationRows, contains(('Posted Date', '13-09-2026')));
      expect(confirmationRows, contains(('Payee', voucher.payee)));
      expect(
        confirmationRows,
        contains(('Payment Account', voucher.paymentAccount)),
      );
      expect(
        confirmationRows,
        contains((
          'Source',
          '${voucher.sourceType.label} · ${voucher.sourceId}',
        )),
      );
      await capture('Source Payment Confirmation');
      expect(
        w.vouchers.byId(voucher.id)!.status,
        PaymentVoucherStatus.approved,
      );
      await capture('Payment Confirmation');
      await tap(find.bySemanticsLabel('Close').last);
      expect(tables(w), posted);
      await action('pay');
      // A concurrent workflow change cannot be overwritten by the reviewed dialog.
      w.vouchers.orderPayment(voucher.id);
      final ordered = tables(w);
      await tap(find.byKey(ValueKey('voucher-confirm-pay-${voucher.id}')));
      expect(
        find.textContaining('Voucher changed since it was opened'),
        findsOneWidget,
      );
      expect(tables(w), ordered);
      await capture('Stale Confirmation Rejected');
      await action('pay');
      await tap(find.byKey(ValueKey('voucher-confirm-pay-${voucher.id}')));
      final paid = w.vouchers.byId(voucher.id)!;
      expect(paid.status, PaymentVoucherStatus.paid);
      expect(paid.paymentEvidence!.journalId, f.journal);
      final paidTables = tables(w);
      for (final key in ordered.keys.where(
        (k) => !{'payment_vouchers', 'ledger_audit'}.contains(k),
      )) {
        expect(paidTables[key], ordered[key], reason: key);
      }
      await capture('Paid');
      await tap(find.byKey(ValueKey('voucher-view-${voucher.id}')));
      expect(
        find.text('The linked posted payment has been verified.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('current completed bank review have been verified'),
        findsNothing,
      );
      await capture('Posted Payment Verified Without Bank Review');
      await tap(find.byKey(const ValueKey('voucher-editor-close')));
      expect(tables(w), paidTables);
      final statement = f.acceptBankMatch();
      final matched = tables(w);
      await action('reconcile');
      expect(
        find.textContaining('Complete the current bank reconciliation'),
        findsOneWidget,
      );
      expect(tables(w), matched);
      await capture('Incomplete Bank Review Rejected');
      final completion = f.completeBankReview(statement);
      // Completion locks the current payment even before the voucher's saved
      // acknowledgement changes from Paid to Reconciled.
      final completedTables = tables(w);
      await tap(find.byKey(ValueKey('voucher-view-${voucher.id}')));
      expect(
        tester
            .widget<PaymentVoucherEditorDialog>(
              find.byType(PaymentVoucherEditorDialog),
            )
            .readOnly,
        isTrue,
      );
      expect(find.byKey(const ValueKey('voucher-save-current')), findsNothing);
      await capture('Completed Payment View Before Acknowledgement');
      await tap(find.byKey(const ValueKey('voucher-editor-close')));
      expect(tables(w), completedTables);
      await action('reconcile');
      final reconciled = w.vouchers.byId(voucher.id)!;
      expect(reconciled.reconciliationEvidence!.completionId, completion);
      await capture('Reconciled');
      await tap(find.byKey(ValueKey('voucher-view-${voucher.id}')));
      expect(
        find.text(
          'The linked payment and current completed bank review have been verified.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PaymentVoucherEditorDialog>(
              find.byType(PaymentVoucherEditorDialog),
            )
            .readOnly,
        isTrue,
      );
      await capture('Current Completed Bank Review Verified');
      await tap(find.byKey(const ValueKey('voucher-editor-close')));
      expect(
        find.byKey(const ValueKey('payment-voucher-filter')),
        findsNothing,
      );
      expect(find.byKey(ValueKey('voucher-row-${voucher.id}')), findsOneWidget);
      w.database.reopenStatementReconciliation(
        businessId: w.identity.businessId,
        completionId: completion.value,
        actorId: w.identity.ownerId,
        reopenedAt: DateTime.utc(2026, 9, 16),
        reason: 'Fictional bank review reopened',
      );
      // Re-enter the actual route so its current evidence and filters reload.
      await tap(find.byKey(const ValueKey('navigation-item-expenses-vendors')));
      await tap(find.text('Payment Vouchers').first);
      expect(
        find.byKey(const ValueKey('payment-voucher-filter')),
        findsNothing,
      );
      expect(find.byKey(ValueKey('voucher-row-${voucher.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('voucher-row-${voucher.id}')), findsOneWidget);
      await capture('Reopened Paid Filter');
      final reopened = tables(w);
      await tap(find.byKey(ValueKey('voucher-view-${voucher.id}')));
      expect(
        find.byKey(const ValueKey('voucher-current-verification')),
        findsOneWidget,
      );
      expect(find.textContaining(completion.value), findsOneWidget);
      expect(
        find.textContaining('current completed bank review have been verified'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('voucher-save-draft')), findsNothing);
      expect(
        tester
            .widget<PaymentVoucherEditorDialog>(
              find.byType(PaymentVoucherEditorDialog),
            )
            .readOnly,
        isFalse,
      );
      expect(
        find.byWidgetPredicate(
          (v) =>
              v is ButtonStyleButton &&
              v.key == const ValueKey('voucher-save-current') &&
              v.onPressed == null,
        ),
        findsOneWidget,
      );
      await capture('Reopened Current Edit With Historical Evidence');
      await tap(
        find
            .ancestor(
              of: accountingCloseIcon(),
              matching: find.byType(IconButton),
            )
            .last,
      );
      expect(tables(w), reopened);
      w.database.retractStatementMatch(
        businessId: w.identity.businessId,
        acceptanceId: reconciled.reconciliationEvidence!.acceptanceId.value,
        actorId: w.identity.ownerId,
        retractedAt: DateTime.utc(2026, 9, 16),
        reason: 'Correct fictional source payment',
      );
      await f.reversePayment();
      expect(
        find.byKey(const ValueKey('payment-voucher-filter')),
        findsNothing,
      );
      expect(find.byKey(ValueKey('voucher-row-${voucher.id}')), findsOneWidget);
      await capture('Reversed On Hold');
      await tap(find.byKey(ValueKey('voucher-view-${voucher.id}')));
      expect(find.textContaining('unavailable or reversed'), findsOneWidget);
      await capture('Reversed Historical View');
      await tap(
        find
            .ancestor(
              of: accountingCloseIcon(),
              matching: find.byType(IconButton),
            )
            .last,
      );
      final finalTables = tables(w);
      await tap(find.byKey(const ValueKey('navigation-item-home')));
      final review = find.byKey(const ValueKey('home-kpi-Needs Review'));
      expect(
        find.descendant(of: review, matching: find.text('1 Item')),
        findsOneWidget,
      );
      await capture('Reversal Home Review Count');
      await tap(find.byKey(const ValueKey('global-notifications')));
      await tap(find.byKey(const ValueKey('notifications-read-more')));
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('notification-voucher-${voucher.id}')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('notification-panel')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Voucher payment needs review'),
        findsOneWidget,
      );
      await capture('Reversal Notification');
      await tap(find.byKey(const ValueKey('global-notifications')));
      await tap(
        find.descendant(
          of: review,
          matching: find.byType(AccountingMetricIconBox),
        ),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('review-queue-count-vouchers')),
            )
            .data,
        '1',
      );
      await capture('Reversal Review Queue');
      await tap(find.byKey(const ValueKey('open-review-vouchers')));
      expect(find.byKey(ValueKey('voucher-row-${voucher.id}')), findsOneWidget);
      expect(tables(w), finalTables);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(tables(w), finalTables);
      expect(w.vouchers.byId(voucher.id)!.toJson(), reconciled.toJson());
      expect(
        w.vouchers.verification(w.vouchers.byId(voucher.id)!).status,
        PaymentVoucherStatus.onHold,
      );
      expect(File(originalPath).readAsBytesSync(), originalBytes);
      expect(tester.takeException(), isNull);
    });
  }
}
