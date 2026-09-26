import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/invoice_credit_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('restored credit edit/history commands at $width', (
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
      final root = Directory.systemTemp.createTempSync('audyt-credit-journey-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sourcePath = '${root.path}/source.sqlite';
      final original = await createDemoWorkspace(databasePath: sourcePath);
      await original.createAccount(
        code: '2200',
        name: 'Fictional Tax Payable',
        type: AccountType.liability,
      );
      await original.createAccount(
        code: '4200',
        name: 'Fictional Services',
        type: AccountType.income,
      );
      final accounts = await original.accounts();
      EntityId account(String code) =>
          accounts.singleWhere((r) => r.account.code == code).account.id;
      final customer = original.customers().last;
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final firstLine = EntityId.random(), secondLine = EntityId.random();
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: customer.id,
        documentNumber: 'CREDIT-JOURNEY',
        issueDate: day,
        reference: 'Original reference',
        memo: 'Original memo',
        classification: 'Saved Class',
        location: 'Saved Branch',
        lines: [
          SalesLineItem.category(
            id: firstLine,
            categoryId: account('4000'),
            description: 'Returned goods',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(10000, 'MYR'),
            taxRatePercent: '8',
          ),
          SalesLineItem.category(
            id: secondLine,
            categoryId: account('4200'),
            description: 'Returned service',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(5000, 'MYR'),
          ),
        ],
      );
      original.saveInvoiceDraft(
        invoice,
        expectedRevision: 0,
        savedAt: day.toUtc(),
      );
      original.postInvoice(
        requestId: EntityId.random(),
        invoiceId: invoice.id,
        expectedRevision: 1,
        expectedCustomerRevision: customer.metadata.revision,
        documentNumber: invoice.documentNumber,
        receivableAccountId: account('1100'),
        incomeAccountId: account('4000'),
        taxAccountId: account('2200'),
        lineIncomeAccounts: {
          firstLine: account('4000'),
          secondLine: account('4200'),
        },
        approvedAt: now.toUtc(),
      );
      final creditId = EntityId.random();
      original.saveInvoiceCreditDraft(
        draftId: creditId,
        invoiceId: invoice.id,
        lineCredits: {
          firstLine: Money.fromMinor(2700, 'MYR'),
          secondLine: Money.fromMinor(1000, 'MYR'),
        },
        reason: 'Original returned goods',
        creditDate: day,
        expectedRevision: 0,
        savedAt: day.toUtc(),
        attachments: ClaimStore.demo().all.first.attachments,
      );
      final originalTables = tables(original);
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        now,
      );
      original.dispose();
      final originalBytes = File(sourcePath).readAsBytesSync();
      final path = '${root.path}/restored.sqlite';
      var workspace = await AccountingWorkspace.emptyRestore(path, archive);
      addTearDown(() => workspace.dispose());
      expect(tables(workspace), originalTables);
      final savedInvoice = workspace
          .postedInvoices()
          .singleWhere((r) => r.sourceDraft.id == invoice.id)
          .sourceDraft
          .draftSnapshot();
      final savedAttachment = workspace
          .creditDrafts()
          .singleWhere((d) => d.id == creditId)
          .attachments
          .single;
      final journalCount = (await workspace.journals()).length;
      final postedBalance = workspace.postedInvoices().singleWhere(
        (r) => r.sourceDraft.id == invoice.id,
      );

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Finder field(String label) => label == 'Reason'
          ? find.byKey(const ValueKey('credit-reason'))
          : find.byKey(
              ValueKey(
                'credit-amount-${invoice.lines.singleWhere((line) => line.description == label).id}',
              ),
            );
      Future<void> enter(String label, String value) async {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), value);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String label) =>
          captureUi(tester, 'Restored Credit $label ${width.toInt()}');
      Future<void> page() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: workspace, showInitialSetup: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(
          find.byKey(const ValueKey('navigation-item-sales-customers')),
        );
        await tap(find.text('Credit Notes').first);
      }

      Future<void> unchangedPosting() async {
        final posted = workspace.postedInvoices().singleWhere(
          (r) => r.sourceDraft.id == invoice.id,
        );
        expect(posted.paidMinor, postedBalance.paidMinor);
        expect(posted.creditedMinor, postedBalance.creditedMinor);
        expect(posted.sourceDraft.draftSnapshot(), savedInvoice);
        expect((await workspace.journals()).length, journalCount);
      }

      Future<void> updateElsewhere(String reason) async {
        final current = workspace.creditDrafts().singleWhere(
          (d) => d.id == creditId,
        );
        workspace.saveInvoiceCreditDraft(
          draftId: creditId,
          invoiceId: invoice.id,
          lineCredits: current.lineCredits,
          reason: reason,
          creditDate: current.date,
          expectedRevision: current.revision,
          savedAt: DateTime.now(),
          attachments: current.attachments,
        );
        await tester.pumpAndSettle();
      }

      await page();
      final initial = tables(workspace);
      await tap(find.byKey(ValueKey(creditId)));
      await tap(find.byKey(ValueKey('remove-${savedAttachment.originalId}')));
      await enter('Reason', 'Cancelled edit');
      await tap(find.byKey(const ValueKey('cancel-credit')));
      expect(tables(workspace), initial);
      await tap(find.text('Choose Invoice To Credit').first);
      await tap(find.text('CREDIT-JOURNEY · ${customer.displayName}').last);
      await enter('Reason', 'Another return');
      await enter('Returned goods', '999');
      await tap(find.byKey(const ValueKey('save-credit')));
      expect(
        find.textContaining('Cumulative line credit exceeds the posted line.'),
        findsOneWidget,
      );
      expect(tables(workspace), initial);
      await capture('Excess Rejected');
      await enter('Returned goods', '54');
      await enter('Returned service', '10');
      await tap(find.byKey(const ValueKey('save-credit')));
      expect(find.byType(InvoiceCreditEditor), findsNothing);
      final newDraft = workspace.creditDrafts().singleWhere(
        (d) => d.invoiceId == invoice.id && d.id != creditId,
      );
      expect(newDraft.total.minorUnits, 6400);
      await unchangedPosting();
      await tap(find.byKey(ValueKey(creditId)));
      await enter('Reason', 'Reviewed return');
      await enter('Returned goods', '32.40');
      await tap(find.byKey(const ValueKey('save-credit')));
      expect(
        workspace.creditDrafts().singleWhere((d) => d.id == creditId).revision,
        2,
      );
      expect(
        workspace
            .creditDrafts()
            .singleWhere((d) => d.id == creditId)
            .total
            .minorUnits,
        4240,
      );
      await tap(find.byKey(ValueKey(creditId)));
      await enter('Reason', 'Stale overwrite');
      await updateElsewhere('Newer saved reason');
      final afterOtherSave = tables(workspace);
      await tap(find.byKey(const ValueKey('save-credit')));
      expect(
        find.textContaining('Credit draft changed; reload before saving.'),
        findsOneWidget,
      );
      expect(tables(workspace), afterOtherSave);
      await capture('Stale Edit Rejected');
      await tap(find.byKey(const ValueKey('cancel-credit')));
      await tap(find.byKey(ValueKey('history-$creditId')));
      await updateElsewhere('Latest saved reason');
      final afterLatestSave = tables(workspace);
      await tap(find.byKey(const ValueKey('restore-credit-1')));
      expect(tables(workspace), afterLatestSave);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(const ValueKey('credit-history-error')),
        ),
        findsOneWidget,
      );
      await capture('Stale History Rejected');
      await tap(find.byKey(const ValueKey('reload-credit-history')));
      expect(find.text('Revision 4'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('credit-history-revision-4')),
          matching: find.text('RM 42.40'),
        ),
        findsOneWidget,
      );
      await capture('History Reloaded');
      await tap(find.byKey(const ValueKey('restore-credit-1')));
      final restored = workspace.creditDrafts().singleWhere(
        (d) => d.id == creditId,
      );
      expect(restored.revision, 5);
      expect(restored.reason, 'Original returned goods');
      expect(restored.total.minorUnits, 3700);
      expect(restored.attachments.single.toJson(), savedAttachment.toJson());
      expect(workspace.creditDraftHistory(creditId).map((d) => d.revision), [
        5,
        4,
        3,
        2,
        1,
      ]);
      await unchangedPosting();
      final beforeMissingEvidence = tables(workspace);
      expect(
        () => workspace.database.postInvoiceCredit(
          businessId: workspace.identity.businessId,
          actorId: workspace.identity.ownerId,
          requestId: EntityId.random(),
          draftId: creditId,
          expectedRevision: 5,
          expectedPaidMinor: 0,
          expectedPriorCreditMinor: 0,
          approvedAt: DateTime.now(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Review ready supporting evidence before posting credit.',
          ),
        ),
      );
      expect(tables(workspace), beforeMissingEvidence);
      final saved = tables(workspace);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(tables(workspace), saved);
      expect(File(sourcePath).readAsBytesSync(), originalBytes);
      await page();
      await tap(find.byKey(ValueKey('history-$creditId')));
      expect(find.text('Revision 5'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('credit-history-revision-5')),
          matching: find.text('RM 37.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Revision 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('credit-history-revision-1')),
          matching: find.text('RM 37.00'),
        ),
        findsOneWidget,
      );
      await capture('Saved History');
      await tap(accountingCloseIcon().last);
      await unchangedPosting();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
