import 'package:audyt/app/accounting_components.dart';

import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final changesWhileOpen in [false, true]) {
      testWidgets(
        'restored payment ${changesWhileOpen ? 'concurrent changes' : 'batch journey'} at $width',
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
          final root = Directory.systemTemp.createTempSync(
            'audyt-payment-journey-',
          );
          addTearDown(() => root.deleteSync(recursive: true));
          final sourcePath = '${root.path}/source.sqlite';
          final original = await createDemoWorkspace(databasePath: sourcePath);
          final accounts = await original.accounts();
          final bank = accounts.singleWhere((a) => a.account.code == '1000');
          final ar = accounts.singleWhere((a) => a.account.code == '1100');
          final income = accounts.singleWhere((a) => a.account.code == '4000');
          final customer = original.customers().last;
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final invoices = <Invoice>[];
          for (final (index, amount) in [10000, 20000].indexed) {
            final invoice = Invoice.draft(
              id: EntityId.random(),
              customerId: customer.id,
              total: Money.fromMinor(amount, 'MYR'),
              documentNumber: 'PAYMENT-JOURNEY-${index + 1}',
              issueDate: day,
              reference: 'Saved source reference',
              memo: 'Saved source memo',
              classification: 'Saved Class',
              location: 'Saved Branch',
              attachments: ClaimStore.demo().all.first.attachments,
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
              receivableAccountId: ar.account.id,
              incomeAccountId: income.account.id,
              approvedAt: now.toUtc(),
            );
            invoices.add(invoice);
          }
          final originalTables = tables(original);
          final archive = original.database.exportDataArchive(
            original.identity.businessId,
            now,
          );
          original.dispose();
          final sourceBytes = File(sourcePath).readAsBytesSync();
          final path = '${root.path}/restored.sqlite';
          var workspace = await AccountingWorkspace.emptyRestore(path, archive);
          addTearDown(() => workspace.dispose());
          expect(tables(workspace), originalTables);
          final savedSnapshots = {
            for (final invoice in invoices)
              invoice.id: workspace
                  .postedInvoices()
                  .singleWhere((r) => r.sourceDraft.id == invoice.id)
                  .sourceDraft
                  .draftSnapshot(),
          };

          Future<void> tap(Finder finder) async {
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            await tester.tap(finder);
            await tester.pumpAndSettle();
          }

          Future<void> discardPaymentDraft() async {
            await tap(find.byKey(const ValueKey('design-close')));
            expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
            await tap(find.byKey(const ValueKey('design-discard-changes')));
          }

          Future<void> showPage() async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: DemoCompany(
                  child: AudytApp(
                    workspace: workspace,
                    showInitialSetup: false,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tap(
              find.byKey(const ValueKey('navigation-item-sales-customers')),
            );
            await tap(find.text('Receive Payment').first);
          }

          Future<void> select(Invoice invoice) async {
            final finder = find.byKey(
              ValueKey('select-receipt-${invoice.id.value}'),
            );
            if (tester.widget<Checkbox>(finder).value != true) {
              await tap(finder);
            }
          }

          Future<void> enter(String field, String value) async {
            final finder = find.byKey(ValueKey('design-field-$field'));
            await tester.ensureVisible(finder);
            await tester.enterText(finder, value);
            await tester.pumpAndSettle();
          }

          Future<void> openPayment(
            String reference,
            Map<EntityId, int> allocations,
          ) async {
            await tap(find.byKey(const ValueKey('receive-selected-invoices')));
            await enter('Reference', reference);
            final ordered = workspace
                .postedInvoices()
                .where((r) => allocations.containsKey(r.sourceDraft.id))
                .toList();
            for (final (i, record) in ordered.indexed) {
              await enter(
                'Amount Received for Invoice ${i + 1}',
                (allocations[record.sourceDraft.id]! / 100).toStringAsFixed(2),
              );
            }
            await tap(find.byKey(const ValueKey('design-field-Bank Account')));
            await tap(find.text('Demo Bank · Bank · RM').last);
            await tap(find.byKey(const ValueKey('design-review')));
          }

          Future<void> capture(String label) =>
              captureUi(tester, 'Restored Payment $label ${width.toInt()}');
          Future<void> reopen() async {
            final saved = tables(workspace);
            await tester.pumpWidget(const SizedBox());
            workspace.dispose();
            workspace = await AccountingWorkspace.open(path);
            expect(tables(workspace), saved);
            expect(File(sourcePath).readAsBytesSync(), sourceBytes);
            for (final invoice in invoices) {
              expect(
                workspace
                    .postedInvoices()
                    .singleWhere((r) => r.sourceDraft.id == invoice.id)
                    .sourceDraft
                    .draftSnapshot(),
                savedSnapshots[invoice.id],
              );
            }
            await showPage();
          }

          await showPage();
          await select(invoices.first);
          final other = workspace.postedInvoices().firstWhere(
            (r) => r.sourceDraft.customerId != customer.id,
          );
          expect(
            tester
                .widget<Checkbox>(
                  find.byKey(
                    ValueKey('select-receipt-${other.sourceDraft.id.value}'),
                  ),
                )
                .onChanged,
            isNull,
          );
          if (!changesWhileOpen) await select(invoices.last);
          final allocation = {
            invoices.first.id: 3000,
            if (!changesWhileOpen) invoices.last.id: 7000,
          };
          final beforeCancel = tables(workspace);
          await openPayment('CANCELLED-JOURNEY', allocation);
          await capture('Cancel Review');
          await discardPaymentDraft();
          expect(tables(workspace), beforeCancel);

          final journalCount = (await workspace.journals()).length;
          final receiptCount = workspace.database
              .customerReceiptHistory(workspace.identity.businessId)
              .length;
          if (changesWhileOpen) {
            await openPayment('LOCKED-JOURNEY', {invoices.first.id: 3000});
            Future<void> bankStatus(AccountStatus status) async {
              final current = (await workspace.accounts()).singleWhere(
                (r) => r.account.id == bank.account.id,
              );
              final account = current.account;
              await workspace.database.saveAccount(
                StoredAccount(
                  account: Account.create(
                    id: account.id,
                    code: account.code,
                    name: account.name,
                    type: account.type,
                    status: status,
                    isParent: account.isParent,
                    isSystem: account.isSystem,
                    parentId: account.parentId,
                    openingBalance: account.openingBalance,
                  ),
                  metadata: current.metadata.nextRevision(
                    updatedAt: current.metadata.updatedAt.add(
                      const Duration(seconds: 1),
                    ),
                  ),
                ),
              );
            }

            await bankStatus(AccountStatus.locked);
            final afterLock = tables(workspace);
            await tap(find.byKey(const ValueKey('design-review')));
            expect(
              find.textContaining('Choose an active bank/cash asset account.'),
              findsOneWidget,
            );
            expect(tables(workspace), afterLock);
            await capture('Locked After Review');
            await discardPaymentDraft();
            await bankStatus(AccountStatus.active);
            await openPayment('BALANCE-JOURNEY', {invoices.first.id: 10000});
            workspace.receiveInvoicePayment(
              requestId: EntityId.random(),
              customerId: customer.id,
              bankAccountId: bank.account.id,
              paymentAccountId: 'demo-bank',
              allocations: {invoices.first.id: Money.fromMinor(6000, 'MYR')},
              reference: 'OTHER-REVIEWED-PAYMENT',
              receivedAt: day,
              approvedAt: now.toUtc(),
            );
            final afterOtherPayment = tables(workspace);
            await tap(find.byKey(const ValueKey('design-review')));
            expect(
              find.textContaining(
                'The allocation exceeds the current invoice balance.',
              ),
              findsOneWidget,
            );
            expect(tables(workspace), afterOtherPayment);
            await capture('Balance Changed After Review');
            await discardPaymentDraft();
            await reopen();
            expect(
              workspace
                  .postedInvoices()
                  .singleWhere((r) => r.sourceDraft.id == invoices.first.id)
                  .paidMinor,
              6000,
            );
            await select(invoices.first);
            await openPayment('REVIEWED-REMAINDER', {invoices.first.id: 4000});
            await tap(find.byKey(const ValueKey('design-review')));
            expect(
              find.byKey(ValueKey('select-receipt-${invoices.first.id.value}')),
              findsNothing,
            );
            expect(
              workspace
                  .postedInvoices()
                  .singleWhere((r) => r.sourceDraft.id == invoices.first.id)
                  .paidMinor,
              10000,
            );
            expect((await workspace.journals()).length, journalCount + 2);
            expect(
              workspace.database
                  .customerReceiptHistory(workspace.identity.businessId)
                  .length,
              receiptCount + 2,
            );
          } else {
            await openPayment('BATCH-JOURNEY', allocation);
            await capture('Batch Review');
            await tap(find.byKey(const ValueKey('design-review')));
            expect((await workspace.journals()).length, journalCount + 1);
            final receipts = workspace.database.customerReceiptHistory(
              workspace.identity.businessId,
            );
            expect(receipts.length, receiptCount + 1);
            final receipt = receipts.singleWhere(
              (r) => r.reference == 'BATCH-JOURNEY',
            );
            expect(receipt.total, Money.fromMinor(10000, 'MYR'));
            for (final invoice in invoices) {
              expect(
                workspace
                    .postedInvoices()
                    .singleWhere((r) => r.sourceDraft.id == invoice.id)
                    .paidMinor,
                allocation[invoice.id],
              );
            }
            final journal = (await workspace.journals())
                .singleWhere((r) => r.entry.id.value == receipt.requestId)
                .entry;
            expect(
              journal.lines.where((l) => l.isDebit).single.accountId,
              bank.account.id,
            );
            expect(
              journal.lines.where((l) => l.isDebit).single.amount.minorUnits,
              10000,
            );
            expect(
              journal.lines
                  .where((l) => l.isCredit)
                  .fold<int>(0, (sum, line) => sum + line.amount.minorUnits),
              10000,
            );
            await reopen();
            final view = find.byKey(
              ValueKey('view-payment-${receipt.requestId}'),
            );
            await tap(view);
            final savedRows = tester
                .widget<AccountingInformationRows>(
                  find.byType(AccountingInformationRows),
                )
                .rows;
            expect(savedRows, contains(('PAYMENT-JOURNEY-1', 'RM 30.00')));
            expect(savedRows, contains(('PAYMENT-JOURNEY-2', 'RM 70.00')));
            await capture('Saved History');
            await tap(accountingCloseIcon().last);
            final locked = find.byKey(
              ValueKey('locked-payment-${receipt.requestId}'),
            );
            expect(tester.widget<IconButton>(locked).onPressed, isNull);
          }
          await capture(
            changesWhileOpen ? 'Remainder Saved' : 'Partial Batch Saved',
          );
          await reopen();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
