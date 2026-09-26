import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('restored Home groups actual claim postings at $width', (
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
      final dir = Directory.systemTemp.createTempSync('claim-home-projection-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final originalPath = '${dir.path}/original.sqlite';
      final original = await createDemoWorkspace(databasePath: originalPath);
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        DateTime.now().toUtc(),
      );
      final originalTables = tables(original);
      original.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final restoredPath = '${dir.path}/restored.sqlite';
      var w = await AccountingWorkspace.emptyRestore(restoredPath, archive);
      addTearDown(() => w.dispose());
      expect(tables(w), originalTables);
      expect(
        w.database.readClaimRecognitionSnapshots(EntityId.random()),
        isEmpty,
        reason: 'Another company must not receive these recognition labels.',
      );
      AccountingHomeData home() => tester
          .widget<AccountingHomePage>(find.byType(AccountingHomePage))
          .data;
      Future<void> showHome() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: w,
                showInitialSetup: false,
                initialPath: '/home',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder target) async {
        if (target.hitTestable().evaluate().isEmpty) {
          await tester.ensureVisible(target);
        }
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      final template = ClaimStore.demo().all.first;
      await showHome();
      for (final month in [true, false]) {
        expect(
          home()
              .expenseAccounts(month: month, grouping: 'Payee')['City Supplies']
              ?.minorUnits,
          5000,
          reason: 'The approved and paid claim expenses retain their merchant.',
        );
        expect(
          home().expenseAccounts(month: month)[template.category]?.minorUnits,
          5000,
          reason: 'Use the reviewed claim category, not an unknown label.',
        );
      }
      expect(
        tables(w),
        originalTables,
        reason: 'Home is a read-only projection.',
      );
      await captureUi(tester, 'Claim Home Categories ${width.toInt()}');
      await tap(find.byKey(const ValueKey('expense-cycle-grouping')));
      expect(find.text('City Supplies'), findsWidgets);
      await captureUi(tester, 'Claim Home Payees ${width.toInt()}');

      final now = DateTime.now();
      final claim = Claim.draft(
        id: EntityId.random(),
        vendorName: 'Workshop Claim Supplier',
        amount: Money.fromMinor(7300, 'MYR'),
        claimantName: template.claimantName,
        incurredOn: DateTime.utc(now.year, now.month, now.day),
        category: template.category,
        claimCategoryCode: template.claimCategoryCode,
        expenseCategoryCode: template.expenseCategoryCode,
        expenseAccountCode: template.expenseAccountCode,
        businessPurpose: 'Supplies personally paid for the workshop',
        attachments: template.attachments,
      );
      w.claims.saveAndSubmit(claim);
      await tester.pumpAndSettle();
      final beforeApproval = home().expensesThisMonth.minorUnits;
      expect(
        home()
            .expenseAccounts(month: true, grouping: 'Payee')
            .containsKey(claim.vendorName),
        isFalse,
        reason: 'An unrecognized claim must not appear as a ledger expense.',
      );
      final accounts = await w.accounts();
      EntityId account(String code) =>
          accounts.singleWhere((item) => item.account.code == code).account.id;
      final recognition = w.approveClaim(
        reviewedClaim: w.claims.byId(claim.id)!,
        requestId: EntityId.random(),
        expenseAccountId: account('6000'),
        liabilityAccountId: account('2100'),
        approvedAt: DateTime.now().toUtc(),
      );
      await tester.pumpAndSettle();
      final reviewedSnapshot = w.claimRecognitionSnapshots[recognition]!;
      expect(reviewedSnapshot.id, claim.id);
      expect(reviewedSnapshot.status, ClaimStatus.submitted);
      expect(reviewedSnapshot.vendorName, claim.vendorName);
      expect(reviewedSnapshot.category, claim.category);
      final recognizedDetails = reviewedSnapshot.toJson();
      expect(home().expensesThisMonth.minorUnits, beforeApproval + 7300);
      expect(
        home()
            .expenseAccounts(month: true, grouping: 'Payee')[claim.vendorName]
            ?.minorUnits,
        7300,
      );
      expect(
        home().expenseAccounts(month: true)[template.category]?.minorUnits,
        12300,
      );
      expect(find.text(claim.vendorName), findsWidgets);
      final totalsAfterRecognition = [
        for (final month in [true, false])
          for (final grouping in ['Category', 'Payee', 'Account'])
            home().expenseAccounts(month: month, grouping: grouping),
      ];
      final ledger = await w.journals();
      expect(
        ledger.singleWhere((j) => j.entry.id == recognition).entry.lines,
        hasLength(2),
      );
      w.settleClaims(
        requestId: EntityId.random(),
        reviewedClaims: [w.claims.byId(claim.id)!],
        bankAccountId: account('1000'),
        paymentReference: 'WORKSHOP CLAIM REIMBURSEMENT',
        paidAt: DateTime.utc(now.year, now.month, now.day),
        paymentAccountId: 'demo-bank',
      );
      await tester.pumpAndSettle();
      expect(w.claims.byId(claim.id)!.status, ClaimStatus.paid);
      expect(
        w.claimRecognitionSnapshots[recognition]!.toJson(),
        recognizedDetails,
      );
      expect(home().expensesThisMonth.minorUnits, beforeApproval + 7300);
      expect(
        [
          for (final month in [true, false])
            for (final grouping in ['Category', 'Payee', 'Account'])
              home().expenseAccounts(month: month, grouping: grouping),
        ],
        totalsAfterRecognition,
        reason: 'Reimbursement adds no second expense.',
      );
      final afterSettlement = tables(w);
      await captureUi(tester, 'Claim Home Settled Payee ${width.toInt()}');
      await tester.pumpWidget(const SizedBox());
      w.dispose();
      w = await AccountingWorkspace.open(restoredPath);
      expect(tables(w), afterSettlement);
      expect(
        w.claimRecognitionSnapshots[recognition]!.toJson(),
        recognizedDetails,
      );
      await showHome();
      expect(home().expensesThisMonth.minorUnits, beforeApproval + 7300);
      expect(
        home()
            .expenseAccounts(month: true, grouping: 'Payee')[claim.vendorName]
            ?.minorUnits,
        7300,
      );
      expect(
        home().expenseAccounts(month: true)[template.category]?.minorUnits,
        12300,
      );
      expect(tables(w), afterSettlement);
      expect(File(originalPath).readAsBytesSync(), originalBytes);
      expect(tester.takeException(), isNull);
      await captureUi(tester, 'Claim Home Restarted ${width.toInt()}');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
