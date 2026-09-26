import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart' show FrontendFormDialog;
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/sales/domain/customer_statement_activity.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/credit_posting_fixture.dart';
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  testWidgets('saved credit exposes the actual posting review command', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1224, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = await creditPostingFixture();
    await tester.pumpWidget(
      DemoCompany(child: AudytApp(workspace: f.w, showInitialSetup: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit Notes').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('post-credit-${f.creditId.value}')),
      findsOneWidget,
    );
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'credit information rows remain actionable in a short window at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 580);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final f = await creditPostingFixture(paidMinor: 8000);
        final w = f.w;
        Future<void> tap(Finder target) async {
          if (target.hitTestable().evaluate().isEmpty) {
            await tester.ensureVisible(target);
          }
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

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
          find.byKey(const ValueKey('navigation-item-sales-customers')),
        );
        await tap(find.text('Credit Notes').first);
        final baseline = tables(w);
        await tap(find.byKey(ValueKey('post-credit-${f.creditId.value}')));
        final table = find.byType(AccountingInformationRows);
        expect(
          tester.widget<AccountingInformationRows>(table).rows,
          contains(('Total Credit', 'RM 54.00')),
        );
        await captureUi(
          tester,
          'Credit Information Rows ${width.toInt()} Short Top',
        );
        await tap(
          find.byKey(const ValueKey('design-field-Customer Credit Account')),
        );
        await tap(
          find.widgetWithText(MenuItemButton, '2300 · Customer Credits').last,
        );
        await captureUi(
          tester,
          'Credit Information Rows ${width.toInt()} Short Fields',
        );
        expect(
          find.byKey(const ValueKey('design-review')).hitTestable(),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-review')));
        await captureUi(
          tester,
          'Credit Information Rows ${width.toInt()} Short Approval',
        );
        await tap(find.byKey(const ValueKey('design-back')));
        await tap(accountingCloseIcon().last);
        expect(tables(w), baseline);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'missing credit evidence is explained and cannot post at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = await creditPostingFixture(evidence: false);
        final before = tables(f.w);
        await tester.pumpWidget(
          DemoCompany(child: AudytApp(workspace: f.w, showInitialSetup: false)),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('navigation-item-sales-customers')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Credit Notes').first);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('post-credit-${f.creditId.value}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Credit Review Unavailable'), findsOneWidget);
        expect(
          find.textContaining('Add ready supporting evidence in Edit'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('design-review')), findsNothing);
        expect(tables(f.w), before);
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey(f.creditId)), findsOneWidget);
        expect(tables(f.w), before);
        expect(tester.takeException(), isNull);
      },
    );
    for (final paidMinor in [0, 8000]) {
      testWidgets(
        'credit approval reaches ledger, invoice and statement at $width paid $paidMinor',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final f = await creditPostingFixture(paidMinor: paidMinor);
          final w = f.w;
          Future<void> tap(Finder target) async {
            if (target.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(target);
            }
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

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
            find.byKey(const ValueKey('navigation-item-sales-customers')),
          );
          await tap(find.text('Credit Notes').first);
          Future<void> open() =>
              tap(find.byKey(ValueKey('post-credit-${f.creditId.value}')));
          Future<void> review() async {
            if (paidMinor > 0) {
              await tap(
                find.byKey(
                  const ValueKey('design-field-Customer Credit Account'),
                ),
              );
              expect(
                find.widgetWithText(
                  MenuItemButton,
                  '2200 · Fictional Tax Payable',
                ),
                findsNothing,
              );
              await tap(find.text('2300 · Customer Credits').last);
            }
            await tap(find.byKey(const ValueKey('design-review')));
          }

          final baseline = tables(w);
          final bank = await creditLedgerBalance(w, f.bank);
          await open();
          final information = tester.widget<AccountingInformationRows>(
            find.descendant(
              of: find.byKey(
                ValueKey('credit-posting-review-${f.creditId.value}'),
              ),
              matching: find.byType(AccountingInformationRows),
            ),
          );
          expect(
            information.rows,
            containsAll([
              ('Total Credit', 'RM 54.00'),
              ('Credit Date', '06-09-2026'),
              ('Net', 'RM 50.00'),
              ('Tax', 'RM 4.00'),
            ]),
          );
          expect(find.text('Total Credit'), findsOneWidget);
          final preview = find.byKey(
            const ValueKey('credit-posting-evidence-demo-CREDIT-SUPPORT'),
          );
          await tester.ensureVisible(preview);
          await tester.tap(preview);
          await tester.pump();
          final loading = find.descendant(
            of: find.byType(AttachmentPreviewDialog),
            matching: find.byType(CircularProgressIndicator),
          );
          for (
            var attempt = 0;
            attempt < 250 && loading.evaluate().isNotEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tap(accountingCloseIcon().last);
          await review();
          await captureUi(
            tester,
            'Credit Posting Review ${width.toInt()} Paid $paidMinor',
          );
          await tap(accountingCloseIcon().last);
          if (paidMinor > 0) {
            // The selected customer-credit account is unsaved working input.
            expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
            await tap(find.byKey(const ValueKey('design-discard-changes')));
          }
          expect(find.byType(FrontendFormDialog), findsNothing);
          expect(tables(w), baseline);
          await open();
          await review();
          await tap(find.byKey(const ValueKey('design-review')));
          expect(
            find.byKey(ValueKey('credit-posting-review-${f.creditId.value}')),
            findsNothing,
          );
          final posted = w.database.invoiceCreditPosting(
            w.identity.businessId,
            f.creditId,
          )!;
          expect(
            posted.receivableReduction.minorUnits,
            paidMinor == 0 ? 5400 : 2800,
          );
          expect(posted.customerCredit.minorUnits, paidMinor == 0 ? 0 : 2600);
          expect(await creditLedgerBalance(w, f.bank), bank);
          expect(await creditLedgerBalance(w, f.income), -5000);
          expect(await creditLedgerBalance(w, f.tax), -400);
          expect(
            await creditLedgerBalance(w, f.receivable),
            paidMinor == 0 ? 5400 : 0,
          );
          expect(
            await creditLedgerBalance(w, f.liability),
            paidMinor == 0 ? 0 : -2600,
          );
          expect(
            find.byKey(ValueKey('post-credit-${f.creditId.value}')),
            findsNothing,
          );
          expect(find.text('Posted'), findsOneWidget);
          await tap(find.byKey(ValueKey(f.creditId)));
          expect(find.text('Posted Credit'), findsOneWidget);
          expect(find.textContaining(posted.journalId.value), findsOneWidget);
          await captureUi(
            tester,
            'Credit Posted View ${width.toInt()} Paid $paidMinor',
          );
          await tap(accountingCloseIcon().last);
          await tap(find.text('Invoices').first);
          final expectedStatus = paidMinor == 0
              ? 'Partially Credited'
              : 'Settled';
          final short = paidMinor == 0 ? 'Part Credit' : 'Settled';
          expect(
            find.text(expectedStatus).evaluate().isNotEmpty ||
                find.text(short).evaluate().isNotEmpty,
            isTrue,
          );
          expect(
            find.byKey(ValueKey('receive-invoice-${f.invoice.id.value}')),
            paidMinor == 0 ? findsOneWidget : findsNothing,
          );
          // Approved short lists omit the search/filter toolbar. Status is
          // still verified above; exercise filtering when that owner is visible.
          final statusFilter = find.byKey(
            const ValueKey('invoice-status-filter'),
          );
          if (statusFilter.evaluate().isNotEmpty) {
            await tap(statusFilter);
            await tap(find.text(expectedStatus).last);
          }
          expect(find.byKey(ValueKey(f.invoice.id.value)), findsOneWidget);
          await captureUi(
            tester,
            'Credit Invoice Status ${width.toInt()} Paid $paidMinor',
          );
          await tap(find.text('Receive Payment').first);
          if (paidMinor == 0) {
            expect(
              find.text('Partially Credited').evaluate().isNotEmpty ||
                  find.text('Part Credit').evaluate().isNotEmpty,
              isTrue,
            );
          } else {
            expect(find.text('No outstanding invoices.'), findsOneWidget);
          }
          await tap(find.text('Customer Statements').first);
          expect(
            find.byKey(const ValueKey('customer-statement-summary')),
            findsOneWidget,
          );
          final statement = w.database.customerStatement(
            w.identity.businessId,
            f.customer.id,
            DateTime.now(),
          );
          expect(
            statement.last.balance.minorUnits,
            paidMinor == 0 ? 5400 : -2600,
          );
          expect(
            statement
                .where((r) => r.activity == CustomerStatementActivity.credit)
                .single
                .credit
                .minorUnits,
            5400,
          );
          expect(
            statement
                .where((r) => r.activity == CustomerStatementActivity.payment)
                .fold<int>(0, (sum, r) => sum + r.credit.minorUnits),
            paidMinor,
          );
          final summary = tester.widget<AccountingSummaryTableCard>(
            find.byKey(const ValueKey('customer-statement-summary')),
          );
          expect(
            summary.rows.singleWhere((r) => r.$1 == 'Payments').$2,
            paidMinor == 0 ? 'RM 0.00' : 'RM 80.00',
          );
          expect(
            summary.rows.singleWhere((r) => r.$1 == 'Credits').$2,
            'RM 54.00',
          );
          expect(find.textContaining('06-09-2026 · Credit'), findsOneWidget);
          // Use the displayed default customer and a cutoff before the credit.
          await tester.enterText(
            find.byKey(const ValueKey('statement-date')),
            '05-09-2026',
          );
          await tap(find.byKey(const ValueKey('run-statement')));
          final earlier = tester.widget<AccountingSummaryTableCard>(
            find.byKey(const ValueKey('customer-statement-summary')),
          );
          expect(
            earlier.rows.singleWhere((r) => r.$1 == 'Credits').$2,
            'RM 0.00',
          );
          expect(
            earlier.rows.singleWhere((r) => r.$1 == 'Closing Balance').$2,
            paidMinor == 0 ? 'RM 108.00' : 'RM 28.00',
          );
          expect(find.textContaining('06-09-2026 · Credit'), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey('statement-date')),
            '27-09-2026',
          );
          await tap(find.byKey(const ValueKey('run-statement')));
          expect(find.textContaining('06-09-2026 · Credit'), findsOneWidget);
          await captureUi(
            tester,
            'Credit Customer Statement ${width.toInt()} Paid $paidMinor',
          );
          expect(tester.takeException(), isNull);
          final finalTables = tables(w);
          final archive = w.database.exportDataArchive(
            w.identity.businessId,
            DateTime.now(),
          );
          final sourceBytes = File(f.path).readAsBytesSync();
          final copy = await AccountingWorkspace.emptyRestore(
            '${File(f.path).parent.path}/restored.sqlite',
            archive,
          );
          addTearDown(copy.dispose);
          expect(tables(copy), finalTables);
          expect(
            copy.database
                .invoiceCreditPosting(copy.identity.businessId, f.creditId)!
                .journalId,
            posted.journalId,
          );
          expect(
            copy.creditDrafts().single.attachments.single.originalSha256,
            w.creditDrafts().single.attachments.single.originalSha256,
          );
          expect(
            copy.creditDrafts().single.attachments.single.originalBytes,
            isEmpty,
          );
          expect(await creditLedgerBalance(copy, f.bank), bank);
          expect(File(f.path).readAsBytesSync(), sourceBytes);
          await tester.pumpWidget(const SizedBox());
          w.dispose();
          final reopened = await AccountingWorkspace.open(f.path);
          addTearDown(reopened.dispose);
          expect(tables(reopened), finalTables);
        },
      );
    }

    for (final change in ['payment', 'draft', 'account']) {
      testWidgets(
        'credit review rejects changed $change without writes at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = await creditPostingFixture(paidMinor: 8000);
          final w = f.w;
          Future<void> tap(Finder target) async {
            if (target.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(target);
            }
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          await tester.pumpWidget(
            DemoCompany(child: AudytApp(workspace: w, showInitialSetup: false)),
          );
          await tester.pumpAndSettle();
          await tap(
            find.byKey(const ValueKey('navigation-item-sales-customers')),
          );
          await tap(find.text('Credit Notes').first);
          await tap(find.byKey(ValueKey('post-credit-${f.creditId.value}')));
          await tap(
            find.byKey(const ValueKey('design-field-Customer Credit Account')),
          );
          await tap(find.text('2300 · Customer Credits').last);
          await tap(find.byKey(const ValueKey('design-review')));
          if (change == 'payment') {
            w.receiveInvoicePayment(
              requestId: EntityId.random(),
              customerId: f.customer.id,
              bankAccountId: f.bank,
              allocations: {f.invoice.id: Money.fromMinor(1000, 'MYR')},
              reference: 'Changed after review',
              receivedAt: DateTime.utc(2026, 9, 7),
            );
          } else if (change == 'draft') {
            final draft = w.creditDrafts().single;
            w.saveInvoiceCreditDraft(
              draftId: draft.id,
              invoiceId: draft.invoiceId,
              lineCredits: draft.lineCredits,
              reason: 'Changed after review',
              creditDate: draft.date,
              expectedRevision: draft.revision,
              savedAt: DateTime.now(),
              attachments: draft.attachments,
            );
          } else {
            final raw = sqlite3.open(f.path);
            addTearDown(raw.dispose);
            raw.execute("UPDATE accounts SET status='archived' WHERE id=?", [
              f.liability.value,
            ]);
          }
          await tester.pumpAndSettle();
          final baseline = tables(w);
          await tap(find.byKey(const ValueKey('design-review')));
          expect(
            find.byKey(ValueKey('credit-posting-review-${f.creditId.value}')),
            findsOneWidget,
          );
          expect(find.textContaining('Could not save:'), findsOneWidget);
          expect(tables(w), baseline);
          expect(
            w.database.invoiceCreditPosting(w.identity.businessId, f.creditId),
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tap(accountingCloseIcon().last);
          expect(tables(w), baseline);
        },
      );
    }
  }
}
