import '../support/accounting_text_input.dart';
import '../support/accounting_test_finders.dart';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_recognition_reversal_test.dart'
    show claimFixture, net, expectClaimReports;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final (width, height) in [
    (720.0, 809.0),
    (1162.0, 809.0),
    (720.0, 1000.0),
    (1224.0, 1000.0),
    (720.0, 580.0),
    (1224.0, 580.0),
  ]) {
    for (final returning in [true, false]) {
      final action = returning ? 'Return' : 'Void';
      testWidgets(
        'approved claim $action review and durable reversal at ${width}x$height',
        (tester) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final f = await claimFixture();
          final w = f.w;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(
                  workspace: w,
                  showInitialSetup: false,
                  initialPath: '/claims',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> tap(Finder target) async {
            if (target.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(target);
            }
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          Future<void> review() async {
            await tap(find.byKey(ValueKey('claim-more-${f.approved.id}')));
            await tap(
              find.byKey(
                ValueKey(
                  'claim-${returning ? 'return' : 'void'}-${f.approved.id}',
                ),
              ),
            );
            expect(find.text('$action Approved Claim'), findsOneWidget);
          }

          final baseline = tables(w);
          await review();
          final dialog = find.byKey(
            ValueKey('claim-recognition-correction-${f.approved.id}'),
          );
          final rows = tester
              .widget<AccountingInformationRows>(
                find.descendant(
                  of: dialog,
                  matching: find.byType(AccountingInformationRows),
                ),
              )
              .rows;
          final amount = formatAccountingMoney(
            tester.element(dialog),
            f.approved.amount,
          );
          expect(
            rows,
            containsAll([
              ('Claimant', f.approved.claimantName),
              ('Payee', f.approved.vendorName),
              ('Claim Amount', amount),
              ('Business Purpose', f.approved.businessPurpose),
              ('Original Journal', f.source.value),
              ('Original Posting Date', '01-09-2026'),
              ('Reversal Credit · 5000 · 5000', amount),
              ('Reversal Debit · 2100 · 2100', amount),
            ]),
          );
          expect(
            find.byKey(const ValueKey('claim-reversal-ordinary-fields')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<AccountingDescriptionField>(
                  find.byKey(const ValueKey('claim-reversal-reason')),
                )
                .fixedLines,
            2,
          );
          for (final (label, key) in [
            ('Reversal Date', 'claim-reversal-date'),
            ('Reason', 'claim-reversal-reason'),
          ]) {
            final frame = find.byKey(ValueKey(key));
            await tester.ensureVisible(frame);
            await tester.pumpAndSettle();
            expectPopupFieldTitleAligned(tester, label, frame);
          }
          final sizeLabel = '${width.toInt()}x${height.toInt()}';
          await captureUi(tester, 'Approved Claim $action Facts $sizeLabel');
          await tap(find.byKey(const ValueKey('claim-reversal-confirm')));
          expect(
            find.text('Enter a valid reversal date and a reason.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Text>(
                  find.text('Enter a valid reversal date and a reason.'),
                )
                .style!
                .color,
            AccountingColorLibrary.grapefruit,
          );
          expect(tables(w), baseline);
          await tester.ensureVisible(
            find.text('Enter a valid reversal date and a reason.'),
          );
          await tester.pumpAndSettle();
          await captureUi(tester, 'Approved Claim $action Review $sizeLabel');
          await tap(find.byKey(const ValueKey('claim-reversal-cancel')));
          expect(tables(w), baseline);
          expect(tester.takeException(), isNull);
          await review();
          final reasonField = find.byKey(
            const ValueKey('claim-reversal-reason'),
          );
          await tester.ensureVisible(reasonField);
          await tester.pumpAndSettle();
          await enterAccountingText(
            tester,
            reasonField,
            'Unsaved correction explanation',
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          expect(tables(w), baseline);
          await captureUi(tester, 'Approved Claim $action Dirty $sizeLabel');
          await tap(find.text('Keep Editing'));
          expect(
            tester
                .widget<AccountingDescriptionField>(reasonField)
                .controller!
                .text,
            'Unsaved correction explanation',
          );
          await tap(find.byKey(const ValueKey('claim-reversal-cancel')));
          await tap(find.text('Discard'));
          expect(find.text('$action Approved Claim'), findsNothing);
          expect(tables(w), baseline);
          await review();
          await tester.ensureVisible(
            find.byKey(const ValueKey('claim-reversal-date')),
          );
          await tester.pumpAndSettle();
          await enterAccountingText(
            tester,
            find.byKey(const ValueKey('claim-reversal-date')),
            '15-09-2026',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('claim-reversal-reason')),
          );
          await tester.pumpAndSettle();
          await enterAccountingText(
            tester,
            find.byKey(const ValueKey('claim-reversal-reason')),
            'Receipt correction reviewed',
          );
          await tap(find.byKey(const ValueKey('claim-reversal-confirm')));
          expect(find.text('$action Approved Claim'), findsNothing);
          expect(
            w.claims.byId(f.approved.id)!.status,
            returning ? ClaimStatus.returned : ClaimStatus.voided,
          );
          expect(await net(w, f.expense), 0);
          expect(await net(w, f.payable), 0);
          expect(w.activeClaimRecognitionId(f.approved.id), isNull);
          await expectClaimReports(w, expense: 0, payable: 0, bank: 0);
          await captureUi(tester, 'Approved Claim $action Result $sizeLabel');
          await tap(find.byKey(const ValueKey('navigation-item-reports')));
          for (final (key, value) in [
            ('report-from', '01-01-2026'),
            ('report-through', '31-12-2026'),
          ]) {
            await tester.ensureVisible(find.byKey(ValueKey(key)));
            await tester.pumpAndSettle();
            await tester.enterText(find.byKey(ValueKey(key)), value);
          }
          await tap(find.byKey(const ValueKey('run-report')));
          void reportRow(String label, String amount) {
            final owner = find
                .ancestor(of: find.text(label).last, matching: find.byType(Row))
                .first;
            expect(
              find.descendant(of: owner, matching: find.text(amount)),
              findsOneWidget,
            );
          }

          reportRow('Assets', 'RM 0.00');
          reportRow('Liabilities', 'RM 0.00');
          reportRow('Balance Sheet Difference', 'RM 0.00');
          await tap(find.byKey(const ValueKey('report-tab-1')));
          reportRow('Expenses', 'RM 0.00');
          reportRow('Period Profit', 'RM 0.00');
          await tester.ensureVisible(find.text('Period Profit'));
          await tester.pumpAndSettle();
          await captureUi(
            tester,
            'Approved Claim $action Profit And Loss $sizeLabel',
          );
          await tap(find.byKey(const ValueKey('report-tab-2')));
          reportRow('Total Debits', 'RM 0.00');
          reportRow('Total Credits', 'RM 0.00');
          expect(tester.takeException(), isNull);
          final finalTables = tables(w);
          await tester.pumpWidget(const SizedBox());
          w.dispose();
          final reopened = await AccountingWorkspace.open(f.path);
          addTearDown(reopened.dispose);
          expect(tables(reopened), finalTables);
          await expectClaimReports(reopened, expense: 0, payable: 0, bank: 0);
          await expectClaimReports(
            reopened,
            year: 2027,
            expense: 0,
            payable: 0,
            bank: 0,
            periodExpense: 0,
          );
        },
      );
    }
  }

  testWidgets('an open Void review cannot reverse a newly settled claim', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final f = await claimFixture();
    final w = f.w;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: DemoCompany(
          child: AudytApp(
            workspace: w,
            showInitialSetup: false,
            initialPath: '/claims',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(ValueKey('claim-more-${f.approved.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('claim-more-${f.approved.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(ValueKey('claim-void-${f.approved.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('claim-void-${f.approved.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('claim-reversal-reason')),
    );
    await tester.pumpAndSettle();
    await enterAccountingText(
      tester,
      find.byKey(const ValueKey('claim-reversal-reason')),
      'Reviewed cancellation',
    );
    w.settleClaims(
      reviewedClaims: [f.approved],
      requestId: EntityId.random(),
      bankAccountId: f.bank,
      paymentReference: 'PAID-WHILE-REVIEW-OPEN',
      paidAt: DateTime.utc(2026, 9, 18),
    );
    await tester.pumpAndSettle();
    final paidTables = tables(w);
    await tester.tap(find.byKey(const ValueKey('claim-reversal-confirm')));
    await tester.pumpAndSettle();
    final error = find.textContaining('Claim could not be corrected:');
    expect(error, findsOneWidget);
    expect(find.text('Void Approved Claim'), findsOneWidget);
    expect(tables(w), paidTables);
    expect(w.claims.byId(f.approved.id)!.status, ClaimStatus.paid);
    await expectClaimReports(
      w,
      expense: f.approved.amount.minorUnits,
      payable: 0,
      bank: -f.approved.amount.minorUnits,
    );
    await tester.ensureVisible(error);
    await tester.pumpAndSettle();
    await captureUi(tester, 'Approved Claim Stale Paid Review 720x580');
    await tester.tap(find.byKey(const ValueKey('claim-reversal-cancel')));
    await tester.pumpAndSettle();
    expect(tables(w), paidTables);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
