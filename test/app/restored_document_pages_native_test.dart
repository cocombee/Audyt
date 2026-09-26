import '../support/accounting_text_input.dart';
import '../support/generated_document_host.dart';
import '../support/fixed_popout_host.dart';

import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart' show FrontendFormDialog;
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/receipt_destination.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_category.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import '../support/attachment_preview_pump.dart';
import 'filed_document_version_relocation_test.dart'
    show FiledFixture, receiptImage, draft;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory compiler;
  late String binary;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    compiler = Directory.systemTemp.createTempSync('audyt-filed-compiler-');
    binary = '${compiler.path}/filed-document-bridge';
    final compiled = await Process.run('xcrun', [
      'swiftc',
      '-module-cache-path',
      '${compiler.path}/ModuleCache',
      '${Directory.current.path}/macos/Runner/ReceiptDestinationWriter.swift',
      '${Directory.current.path}/macos/Runner/DocumentPreviewRenderer.swift',
      '${Directory.current.path}/test/native/filed_document_versions/main.swift',
      '-o',
      binary,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
  });
  tearDownAll(() {
    if (Platform.isMacOS && compiler.existsSync()) {
      compiler.deleteSync(recursive: true);
    }
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored invoice claim and voucher page actions use exact native versions at $width',
      (tester) async {
        resetGeneratedDocumentAssetCache();
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        final fixture = (await tester.runAsync(
          () => FiledFixture.create(binary),
        ))!;
        addTearDown(() => tester.runAsync(fixture.close));
        final root = Directory.systemTemp.createTempSync(
          'audyt-filed-page-sqlite-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        Future<dynamic>? nativeRead;
        var directNative = true;
        final requests = <(String, String)>[];
        final noteStyles = <String, (double?, Color?, double?)>{};
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async {
            if (call.method == 'readDocument') {
              final args = call.arguments as Map;
              requests.add((
                args['attachmentId'] as String,
                args['expectedSha256'] as String,
              ));
              nativeRead = runGeneratedDocumentNativeCall(
                tester,
                fixture,
                call,
              );
              return await nativeRead;
            }
            return directNative
                ? fixture.channel(call)
                : runGeneratedDocumentNativeCall(tester, fixture, call);
          },
        );
        const documentChannel = MethodChannel('audyt/document-preview');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          documentChannel,
          (call) => runGeneratedDocumentNativeCall(tester, fixture, call),
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            documentChannel,
            null,
          ),
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            namingSettingsChannel,
            null,
          ),
        );
        final original = receiptImage(72, 133, 237),
            edited = receiptImage(26, 175, 135);
        final attachments = <String, List<ReceiptAttachment>>{};
        for (final kind in [
          SetupKind.invoice,
          SetupKind.claims,
          SetupKind.voucher,
        ]) {
          final first = ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: 'page-${kind.id}',
              batchId: 'page-batch',
              filename: 'Fictional ${kind.id} receipt.png',
              mimeType: 'image/png',
              bytes: original,
            ),
          );
          attachments[kind.id] = [
            first,
            first.withDerivative(
              derivativeId: '${first.originalId}-derivative-edit-1',
              bytes: edited,
              mimeType: 'image/png',
              width: 240,
              height: 320,
              printReadyAt300Dpi: false,
            ),
          ];
        }
        final workspace = await AccountingWorkspace.open(
          '${root.path}/source.sqlite',
        );
        addTearDown(workspace.dispose);
        workspace.savePaymentAccount(
          PaymentAccount.create(
            id: 'filed-fixture-cash',
            name: 'Cash',
            type: PaymentAccountType.cash,
            currencyCode: 'MYR',
          ),
        );
        await workspace.createAccount(
          code: '4000',
          name: 'Fictional Sales',
          type: AccountType.income,
        );
        final income = (await workspace.accounts()).single.account.id;
        await workspace.createAccount(
          code: '1100',
          name: 'Fictional Receivables',
          type: AccountType.asset,
        );
        await workspace.createAccount(
          code: '1000',
          name: 'Fictional Cash',
          type: AccountType.asset,
        );
        final cashLedger = (await workspace.accounts())
            .singleWhere((a) => a.account.code == '1000')
            .account
            .id;
        workspace.database.linkPaymentLedgerAccount(
          workspace.identity.businessId,
          'filed-fixture-cash',
          cashLedger,
        );
        final customer = Customer.create(
          metadata: RecordMetadata.initial(
            recordId: EntityId.random(),
            businessId: workspace.identity.businessId,
            originDeviceId: workspace.identity.deviceId,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
          displayName: 'Fictional Version Customer',
          contact: const CustomerContact(),
          taxProfile: const CustomerTaxProfile(),
          currency: Currency.parse('MYR'),
          paymentTerms: PaymentTerms.netDays(30),
        );
        workspace.saveCustomer(customer);
        final invoiceId = EntityId.random(), claimId = EntityId.random();
        final source = await workspace.saveExpenseIntake(
          draft(attachments['voucher']!.first),
        );
        final sourceRecord = workspace.vouchers.sources.singleWhere(
          (s) => s.id == source.value,
        );
        final line = SalesLineItem.category(
          id: EntityId.random(),
          categoryId: income,
          description: 'Fictional Service',
          quantity: SalesQuantity.fromInt(1),
          rate: Money.fromMinor(1250, 'MYR'),
          taxRatePercent: '0',
        );
        Invoice invoice(int version) => Invoice.draft(
          id: invoiceId,
          customerId: customer.id,
          lines: [line],
          attachments: [attachments['invoice']![version]],
          documentNumber: 'VERSION-INVOICE',
          taxMode: 'Exclusive',
          memo: version == 0 ? 'Original receipt' : 'Edited receipt',
          issueDate: DateTime.utc(2026, 9, 1),
          terms: customer.paymentTerms,
        );
        Claim claim(int version) => Claim.draft(
          id: claimId,
          vendorName: 'Fictional Version Supplier',
          amount: Money.fromMinor(1250, 'MYR'),
          claimantName: 'Fictional Staff',
          incurredOn: DateTime.utc(2026, 9, 1),
          category: ClaimCategoryCatalog.seeded.first.displayName,
          claimCategoryCode: ClaimCategoryCatalog.seeded.first.code,
          expenseCategoryCode:
              ClaimCategoryCatalog.seeded.first.expenseCategoryCode,
          expenseAccountCode:
              ClaimCategoryCatalog.seeded.first.expenseAccountCode,
          businessPurpose: version == 0 ? 'Original receipt' : 'Edited receipt',
          attachments: [attachments['claims']![version]],
        );
        PaymentVoucher voucher(int version) => PaymentVoucher.create(
          id: 'page-voucher',
          sourceType: sourceRecord.type,
          sourceId: sourceRecord.id,
          payee: sourceRecord.payee,
          amount: sourceRecord.amount,
          paymentAccount: 'Cash',
          paymentAccountId: sourceRecord.paymentAccountId,
          paymentMethod: 'Cash',
          paymentDate: sourceRecord.date,
          reference: version == 0 ? 'ORIGINAL RECEIPT' : 'EDITED RECEIPT',
          attachments: [attachments['voucher']![version]],
        );
        final archives = <(String, Map<String, dynamic>)>[];
        var revision = 0;
        for (var version = 0; version < 2; version++) {
          for (final kind in [
            SetupKind.invoice,
            SetupKind.claims,
            SetupKind.voucher,
          ]) {
            final attachment = attachments[kind.id]![version];
            await tester.runAsync(
              () => saveReceiptDestination(
                kind: kind,
                attachmentId: attachment.originalId,
                date: DateTime(2026, 9, 1),
                categoryCode: 'DOCUMENT',
                mimeType: attachment.preferredMimeType,
                bytes: attachment.preferredBytes,
              ),
            );
          }
          revision = workspace.saveInvoiceDraft(
            invoice(version),
            expectedRevision: revision,
            savedAt: DateTime.utc(2026, 9, 1 + version),
          );
          workspace.claims.saveDraft(
            claim(version),
            expectedCurrent: version == 0
                ? null
                : workspace.claims.byId(claimId),
          );
          workspace.vouchers.save(
            voucher(version),
            expectedCurrent: version == 0
                ? null
                : workspace.vouchers.byId('page-voucher'),
          );
          archives.add((
            workspace.database.exportDataArchive(
              workspace.identity.businessId,
              DateTime.now(),
            ),
            tables(workspace),
          ));
        }
        workspace.dispose();
        await tester.runAsync(() => fixture.request('prepare'));
        directNative = false;
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        Future<void> tap(Finder target) async {
          if (target.hitTestable().evaluate().isEmpty) {
            await tester.ensureVisible(target);
          }
          await tester.tap(target);
          await pumpGeneratedDocumentWork(tester);
        }

        Future<void> preview(
          Finder target,
          ReceiptAttachment expected,
          String label,
        ) async {
          nativeRead = null;
          await tap(target);
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          expect(nativeRead, isNotNull);
          await nativeRead;
          await tester.pump();
          await pumpDecodedAttachment(tester);
          final note = tester.renderObject<RenderParagraph>(
            find.textContaining('Linked filed copy'),
          );
          final style = note.text.style!;
          noteStyles[label] = (style.fontSize, style.color, style.height);
          expect(
            (tester.widget<Image>(find.byType(Image)).image as MemoryImage)
                .bytes,
            expected.preferredBytes,
          );
          expect(requests.last, (expected.originalId, expected.filedSha256));
          expect(tester.takeException(), isNull);
          await captureUi(tester, 'Filed Page $label ${width.toInt()}');
          await tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
        }

        for (var version = 0; version < archives.length; version++) {
          final path = '${root.path}/restored-$version.sqlite';
          final imported = await AccountingWorkspace.emptyRestore(
            path,
            archives[version].$1,
          );
          expect(tables(imported), archives[version].$2);
          imported.dispose();
          final restored = await AccountingWorkspace.open(path);
          addTearDown(restored.dispose);
          expect(tables(restored), archives[version].$2);
          final persisted = {
            'invoice': restored
                .invoiceDrafts()
                .single
                .invoice
                .attachments
                .single,
            'claims': restored.claims.byId(claimId)!.attachments.single,
            'voucher': restored.vouchers
                .byId('page-voucher')!
                .attachments
                .single,
          };
          expect(persisted.values.every((a) => a.preferredBytes.isEmpty), true);
          for (final kind in ['invoice', 'claims', 'voucher']) {
            final beforeKind = tables(restored);
            final initialPath = switch (kind) {
              'invoice' => '/sales-customers',
              'claims' => '/claims',
              _ => '/payment-vouchers',
            };
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: DemoCompany(
                  child: AudytApp(
                    key: ValueKey('$kind-$version'),
                    workspace: restored,
                    showInitialSetup: false,
                    initialPath: initialPath,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label = '$kind ${version == 0 ? 'Original' : 'Edited'}';
            if (kind == 'invoice') {
              await preview(
                find.byKey(
                  ValueKey(
                    'invoice-attachment-${invoiceId.value}-page-invoice',
                  ),
                ),
                attachments[kind]![version],
                label,
              );
              await tap(
                find.byKey(ValueKey('edit-invoice-${invoiceId.value}')),
              );
              await tester.pumpAndSettle();
              await preview(
                find.byKey(const ValueKey('preview-supporting-file-0')),
                attachments[kind]![version],
                '$label Editor',
              );
            } else {
              await tap(
                find.byKey(
                  ValueKey(
                    kind == 'claims'
                        ? 'claim-edit-$claimId'
                        : 'voucher-view-page-voucher',
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final failure = find.byKey(
                ValueKey('attachment-failure-page-$kind'),
              );
              await tester.ensureVisible(failure);
              await tester.pumpAndSettle();
              final card = find.byKey(ValueKey('attachment-card-page-$kind'));
              expect(
                find.descendant(of: card, matching: find.text('Failed')),
                findsNothing,
              );
              expect(
                find.descendant(
                  of: failure,
                  matching: find.text(persisted[kind]!.failureMessage!),
                ),
                findsOneWidget,
              );
              expect(
                tester.getRect(failure).top,
                greaterThan(tester.getRect(card).bottom),
              );
              await captureUi(
                tester,
                'Attachment Failure $label ${width.toInt()}',
              );
              await preview(
                find.byKey(
                  ValueKey(
                    '${kind == 'claims' ? 'expense' : 'voucher'}-attachment-view-page-$kind',
                  ),
                ),
                attachments[kind]![version],
                '$label Editor',
              );
            }
            await tap(find.bySemanticsLabel('Close').last);
            await tester.pumpAndSettle();
            expect(tables(restored), beforeKind);
            expect(tester.takeException(), isNull);

            final edit = find.byKey(
              ValueKey(switch (kind) {
                'invoice' => 'edit-invoice-${invoiceId.value}',
                'claims' => 'claim-edit-$claimId',
                _ => 'voucher-view-page-voucher',
              }),
            );
            await tap(edit);
            await tester.pumpAndSettle();
            final field = find.byKey(
              ValueKey(switch (kind) {
                'invoice' => 'design-field-Memo',
                'claims' => 'expense-field-notes',
                _ => 'voucher-reference',
              }),
            );
            await tester.ensureVisible(field);
            final changed = 'Metadata change $kind $version';
            await enterAccountingText(tester, field, changed);
            await tester.pumpAndSettle();
            if (kind != 'invoice') {
              await tap(
                find.byKey(
                  ValueKey(
                    kind == 'claims' ? 'record-claim-submit' : 'voucher-submit',
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tables(restored),
                beforeKind,
                reason: 'A native filed preview must not authorize submission with missing original evidence.',
              );
              expect(
                find.byKey(
                  ValueKey(
                    kind == 'claims'
                        ? 'expense-field-notes'
                        : 'voucher-reference',
                  ),
                ),
                findsOneWidget,
              );
              await captureUi(
                tester,
                'Restored Metadata Submit Blocked $label ${width.toInt()}',
              );
            }
            if (kind == 'invoice') {
              await tap(find.byKey(const ValueKey('design-review')));
              await tester.pumpAndSettle();
              await captureUi(
                tester,
                'Restored Metadata Review $label ${width.toInt()}',
              );
              await tap(find.byKey(const ValueKey('design-review')));
            } else {
              await tap(
                find.byKey(
                  ValueKey(
                    kind == 'claims'
                        ? 'record-claim-save-draft'
                        : 'voucher-save-draft',
                  ),
                ),
              );
            }
            await tester.pumpAndSettle();
            expect(
              field,
              findsNothing,
              reason:
                  'Actual Save Draft must close its successfully saved editor.',
            );
            await captureUi(
              tester,
              'Restored Metadata After Save $label ${width.toInt()}',
            );
            expect(
              find.byKey(
                ValueKey(
                  kind == 'invoice'
                      ? 'design-review'
                      : kind == 'claims'
                      ? 'record-claim-save-draft'
                      : 'voucher-save-draft',
                ),
              ),
              findsNothing,
              reason: 'Save must succeed and close the editor, not merely hide fields in Review.',
            );
            final afterSave = tables(restored);
            final allowed = switch (kind) {
              'invoice' => {
                'invoice_drafts',
                'invoice_draft_history',
                'ledger_audit',
                'generated_document_deliveries',
              },
              'claims' => {'claims'},
              _ => {'payment_vouchers'},
            };
            for (final table in beforeKind.keys.where(
              (name) => !allowed.contains(name),
            )) {
              expect(
                afterSave[table],
                beforeKind[table],
                reason: 'Metadata save changed unrelated table $table',
              );
            }
            final savedAttachment = switch (kind) {
              'invoice' =>
                restored.invoiceDrafts().single.invoice.attachments.singleWhere(
                  (a) => !a.isGenerated,
                ),
              'claims' => restored.claims.byId(claimId)!.attachments.single,
              _ => restored.vouchers.byId('page-voucher')!.attachments.single,
            };
            expect(
              jsonEncode(savedAttachment.toJson()),
              jsonEncode(persisted[kind]!.toJson()),
            );
            expect(switch (kind) {
              'invoice' => restored.invoiceDrafts().single.invoice.memo,
              'claims' => restored.claims.byId(claimId)!.businessPurpose,
              _ => restored.vouchers.byId('page-voucher')!.reference,
            }, changed);
            await tap(edit);
            await tester.pumpAndSettle();
            await preview(
              find.byKey(
                ValueKey(
                  kind == 'invoice'
                      ? 'preview-supporting-file-0'
                      : '${kind == 'claims' ? 'expense' : 'voucher'}-attachment-view-page-$kind',
                ),
              ),
              attachments[kind]![version],
              '$label Saved Metadata',
            );
            await tap(find.bySemanticsLabel('Close').last);
            await tester.pumpAndSettle();
            expect(tables(restored), afterSave);
          }
          // Exercise the record lifecycle through the actual restored page,
          // retaining the exact historical attachment even after recognition
          // and settlement. No live workspace or file grant is used here.
          Future<void> invoicePage(String phase) async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: DemoCompany(
                  child: AudytApp(
                    key: ValueKey('invoice-lifecycle-$version-$phase'),
                    workspace: restored,
                    showInitialSetup: false,
                    initialPath: '/sales-customers',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          final attachmentKey = ValueKey(
            'invoice-attachment-${invoiceId.value}-page-invoice',
          );
          final savedDraft = restored.invoiceDrafts().single;
          final savedSnapshot = savedDraft.invoice.draftSnapshot();
          final beforeArchive = tables(restored);
          await invoicePage('archive');
          final archiveKey = ValueKey('archive-invoice-${invoiceId.value}');
          await tap(find.byKey(archiveKey));
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('cancel-invoice-archive')));
          await tester.pumpAndSettle();
          expect(tables(restored), beforeArchive);
          await tap(find.byKey(archiveKey));
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('confirm-invoice-archive')));
          await tester.pumpAndSettle();
          expect(restored.invoiceDrafts(), isEmpty);
          expect(
            restored
                .invoiceDrafts(archived: true)
                .single
                .invoice
                .draftSnapshot(),
            savedSnapshot,
          );
          expect(
            find.byKey(const ValueKey('invoice-status-filter')),
            findsNothing,
          );
          await preview(
            find.byKey(attachmentKey),
            attachments['invoice']![version],
            'invoice ${version == 0 ? 'Original' : 'Edited'} Archived',
          );
          await captureUi(
            tester,
            'Restored Invoice Archived $version ${width.toInt()}',
          );
          await tap(find.byKey(archiveKey));
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('confirm-invoice-archive')));
          await tester.pumpAndSettle();
          expect(
            restored.invoiceDrafts().single.invoice.draftSnapshot(),
            savedSnapshot,
          );
          expect(
            restored.invoiceDrafts().single.revision,
            savedDraft.revision + 2,
          );

          await invoicePage('posting');
          final beforePost = tables(restored);
          Future<void> postingReview() async {
            await tap(find.byKey(ValueKey('post-invoice-${invoiceId.value}')));
            await tester.pumpAndSettle();
            await tap(
              find.byKey(const ValueKey('design-field-Receivable Account')),
            );
            await tester.pumpAndSettle();
            await tap(find.text('1100 · Fictional Receivables').last);
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('design-review')));
            await tester.pumpAndSettle();
          }

          await postingReview();
          await captureUi(
            tester,
            'Restored Invoice Post Review $version ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('design-close')));
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          await tap(find.byKey(const ValueKey('design-discard-changes')));
          expect(find.byType(FrontendFormDialog), findsNothing);
          await tester.pumpAndSettle();
          expect(tables(restored), beforePost);
          await postingReview();
          await tap(find.byKey(const ValueKey('design-review')));
          await tester.pumpAndSettle();
          expect(restored.invoiceDrafts(), isEmpty);
          expect(
            restored.postedInvoices().single.sourceDraft.draftSnapshot(),
            savedSnapshot,
          );
          expect(restored.postedInvoices().single.paidMinor, 0);
          expect(await restored.journals(), hasLength(1));
          await preview(
            find.byKey(attachmentKey),
            attachments['invoice']![version],
            'invoice ${version == 0 ? 'Original' : 'Edited'} Posted',
          );

          Future<void> receive(
            String amount,
            String reference, {
            bool cancel = false,
          }) async {
            await tap(
              find.byKey(ValueKey('receive-invoice-${invoiceId.value}')),
            );
            await tester.pumpAndSettle();
            final amountField = find.byKey(
              const ValueKey('design-field-Amount'),
            );
            await tester.ensureVisible(amountField);
            await enterAccountingText(tester, amountField, amount);
            final dateField = find.byKey(const ValueKey('design-field-Date'));
            await tester.ensureVisible(dateField);
            await enterAccountingText(tester, dateField, '02-09-2026');
            final refField = find.byKey(
              const ValueKey('design-field-Reference'),
            );
            await tester.ensureVisible(refField);
            await enterAccountingText(tester, refField, reference);
            await tap(find.byKey(const ValueKey('design-field-Bank Account')));
            await tester.pumpAndSettle();
            await tap(find.text('Cash · Cash · RM').last);
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('design-review')));
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Restored Invoice Receipt Review $reference $version ${width.toInt()}',
            );
            await tap(
              find.byKey(ValueKey(cancel ? 'design-close' : 'design-review')),
            );
            await tester.pumpAndSettle();
            if (cancel) {
              expect(
                find.byKey(const ValueKey('design-discard-changes')),
                findsOneWidget,
              );
              await tap(find.byKey(const ValueKey('design-discard-changes')));
              expect(find.byType(FrontendFormDialog), findsNothing);
            }
          }

          final beforeReceipt = tables(restored);
          await receive('4', 'CANCELLED-FILED-PAYMENT', cancel: true);
          expect(tables(restored), beforeReceipt);
          await receive('4', 'FILED-PARTIAL-$version');
          expect(restored.postedInvoices().single.paidMinor, 400);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  (w is Tooltip && w.message == 'Partially Paid') ||
                  (w is Text && w.data == 'Partially Paid'),
            ),
            findsWidgets,
          );
          expect(await restored.journals(), hasLength(2));
          final partialReport = await restored.report(
            from: DateTime(2026),
            through: DateTime(2026, 12, 31),
          );
          expect(
            partialReport.rows
                .singleWhere((r) => r.account.code == '1100')
                .endingNetDebit,
            BigInt.from(850),
          );
          expect(
            partialReport.rows
                .singleWhere((r) => r.account.id == cashLedger)
                .endingNetDebit,
            BigInt.from(400),
          );
          expect(partialReport.periodProfit, BigInt.from(1250));
          expect(partialReport.isBalanced, isTrue);

          await preview(
            find.byKey(attachmentKey),
            attachments['invoice']![version],
            'invoice ${version == 0 ? 'Original' : 'Edited'} Partially Paid',
          );
          await receive('8.50', 'FILED-FINAL-$version');
          expect(restored.postedInvoices().single.paidMinor, 1250);
          expect(find.text('Paid'), findsOneWidget);
          expect(
            find.byKey(ValueKey('receive-invoice-${invoiceId.value}')),
            findsNothing,
          );
          expect(
            restored.postedInvoices().single.sourceDraft.draftSnapshot(),
            savedSnapshot,
          );
          expect(await restored.journals(), hasLength(3));
          final receipts = restored.database.customerReceiptHistory(
            restored.identity.businessId,
          );
          expect(receipts, hasLength(2));
          await tap(find.byKey(ValueKey('view-invoice-${invoiceId.value}')));
          await tester.pumpAndSettle();
          expect(find.text('FILED-PARTIAL-$version'), findsOneWidget);
          expect(find.text('FILED-FINAL-$version'), findsOneWidget);
          expect(
            find.textContaining('Metadata change invoice $version'),
            findsOneWidget,
          );
          await captureUi(
            tester,
            'Restored Invoice Paid Document $version ${width.toInt()}',
          );
          await tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
          await preview(
            find.byKey(attachmentKey),
            attachments['invoice']![version],
            'invoice ${version == 0 ? 'Original' : 'Edited'} Paid',
          );
          final report = await restored.report(
            from: DateTime(2026),
            through: DateTime(2026, 12, 31),
          );
          expect(report.revenue, BigInt.from(1250));
          expect(report.expenses, BigInt.zero);
          expect(report.periodProfit, BigInt.from(1250));
          expect(report.assets, BigInt.from(1250));
          expect(report.balanceSheetDifference, BigInt.zero);
          expect(report.trialBalanceDebits, BigInt.from(1250));
          expect(report.trialBalanceCredits, BigInt.from(1250));
          expect(report.isBalanced, isTrue);
          expect(
            report.rows
                .singleWhere((r) => r.account.code == '1100')
                .endingNetDebit,
            BigInt.zero,
          );
          expect(
            report.rows
                .singleWhere((r) => r.account.id == cashLedger)
                .endingNetDebit,
            BigInt.from(1250),
          );
          final afterLifecycle = tables(restored);
          final approvalTable = afterLifecycle['journal_approvals'] as Map;
          final approvalColumns = approvalTable['columns'] as List;
          final approvalRows = approvalTable['rows'] as List;
          expect(approvalRows, hasLength(3));
          expect(
            approvalRows
                .map(
                  (row) => (row as List)[approvalColumns.indexOf('journal_id')],
                )
                .toSet(),
            (await restored.journals())
                .map((row) => row.entry.id.value)
                .toSet(),
          );
          const lifecycleTables = {
            'invoice_drafts',
            'invoice_draft_history',
            'invoice_postings',
            'customer_receipts',
            'customer_receipt_allocations',
            'journal_entries',
            'journal_lines',
            'journal_approvals',
            'ledger_audit',
            'document_numbers',
          };
          for (final name in beforeArchive.keys.where(
            (n) => !lifecycleTables.contains(n),
          )) {
            expect(
              afterLifecycle[name],
              beforeArchive[name],
              reason: 'Invoice lifecycle changed unrelated table $name',
            );
          }

          final nextYear = await restored.report(
            from: DateTime(2027),
            through: DateTime(2027, 12, 31),
          );
          expect(nextYear.periodProfit, BigInt.zero);
          expect(nextYear.assets, BigInt.from(1250));
          expect(nextYear.balanceSheetDifference, BigInt.zero);
          expect(nextYear.isBalanced, isTrue);
          final savedTables = tables(restored);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          restored.dispose();
          final reopened = await AccountingWorkspace.open(path);
          expect(tables(reopened), savedTables);
          expect(
            reopened.postedInvoices().single.sourceDraft.memo,
            'Metadata change invoice $version',
          );
          expect(
            reopened.claims.byId(claimId)!.businessPurpose,
            'Metadata change claims $version',
          );
          expect(
            reopened.vouchers.byId('page-voucher')!.reference,
            'Metadata change voucher $version',
          );
          expect(
            reopened.postedInvoices().single.sourceDraft.draftSnapshot(),
            savedSnapshot,
          );
          expect(reopened.postedInvoices().single.paidMinor, 1250);
          expect(
            reopened.database.customerReceiptHistory(
              reopened.identity.businessId,
            ),
            hasLength(2),
          );
          final reopenedReport = await reopened.report(
            from: DateTime(2026),
            through: DateTime(2026, 12, 31),
          );
          expect(reopenedReport.periodProfit, report.periodProfit);
          expect(reopenedReport.assets, report.assets);
          expect(reopenedReport.isBalanced, isTrue);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(
                  key: ValueKey('paid-reopened-$version'),
                  workspace: reopened,
                  showInitialSetup: false,
                  initialPath: '/sales-customers',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final beforeReopenedPreview = tables(reopened);
          await preview(
            find.byKey(attachmentKey),
            attachments['invoice']![version],
            'invoice ${version == 0 ? 'Original' : 'Edited'} Reopened Paid',
          );
          expect(tables(reopened), beforeReopenedPreview);
          expect(find.text('Paid'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(
                  key: ValueKey('invoice-year-reports-$version'),
                  workspace: reopened,
                  showInitialSetup: false,
                  initialPath: '/reports',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final beforeReports = tables(reopened);
          Finder total(String label) => find.byWidgetPredicate(
            (w) => w is AccountingTotalRow && w.label == label,
          );
          Finder factRow(String label) => find.byWidgetPredicate(
            (w) =>
                w is Row &&
                w.children.any(
                  (child) =>
                      child is Expanded &&
                      child.child is Text &&
                      (child.child as Text).data == label,
                ),
          );
          for (final year in [2026, 2027]) {
            await enterAccountingText(
              tester,
              find.byKey(const ValueKey('report-from')),
              '01-01-$year',
            );
            await enterAccountingText(
              tester,
              find.byKey(const ValueKey('report-through')),
              '31-12-$year',
            );
            await tap(find.byKey(const ValueKey('run-report')));
            await tester.pumpAndSettle();
            await tap(find.byKey(const ValueKey('report-tab-1')));
            await tester.pumpAndSettle();
            expect(
              tester.widget<AccountingTotalRow>(total('Period Profit')).value,
              year == 2026 ? 'RM 12.50' : 'RM 0.00',
            );
            await tester.ensureVisible(total('Period Profit'));
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Restored Invoice P&L $year $version ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('report-tab-0')));
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: factRow('Assets'),
                matching: find.text('RM 12.50'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: factRow('Balance Sheet Difference'),
                matching: find.text('RM 0.00'),
              ),
              findsOneWidget,
            );
            await tester.ensureVisible(factRow('Balance Sheet Difference'));
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Restored Invoice Balance Sheet $year $version ${width.toInt()}',
            );
            await tap(find.byKey(const ValueKey('report-tab-2')));
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: factRow('Total Debits'),
                matching: find.text('RM 12.50'),
              ),
              findsOneWidget,
            );
            expect(
              tester.widget<AccountingTotalRow>(total('Total Credits')).value,
              'RM 12.50',
            );
            await tester.ensureVisible(total('Total Credits'));
            await tester.pumpAndSettle();
            await captureUi(
              tester,
              'Restored Invoice Trial Balance $year $version ${width.toInt()}',
            );
          }
          expect(tables(reopened), beforeReports);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          reopened.dispose();
        }
        final historicalVersions = attachments.values
            .expand((versions) => versions)
            .map((a) => (a.originalId, a.filedSha256))
            .toSet();
        final historicalIds = historicalVersions.map((a) => a.$1).toSet();
        for (final request in requests.where(
          (request) => historicalIds.contains(request.$1),
        )) {
          expect(historicalVersions, contains(request));
        }
        for (final version in historicalVersions) {
          expect(
            requests.where((r) => r == version).length,
            greaterThanOrEqualTo(2),
          );
        }
        expect(requests.length, greaterThanOrEqualTo(24));
        expect(
          noteStyles.values.toSet().length,
          1,
          reason:
              'The shared filed-copy notice must keep the same painted typography across page/field callers: $noteStyles',
        );
        final native =
            await tester.runAsync(() => fixture.request('inspect')) as Map;
        expect(native['pending'], false);
        // Nine original/version links plus one generated invoice for each of
        // the three restored archive journeys; manual versions remain intact.
        expect((native['links'] as Map).length, 12);
        // The original source database was not changed by the archive journeys.
        final unchanged = await AccountingWorkspace.open(
          '${root.path}/source.sqlite',
        );
        expect(tables(unchanged), archives.last.$2);
        unchanged.dispose();
        expect(
          jsonEncode(archives.first.$2),
          isNot(jsonEncode(archives.last.$2)),
        );
      },
      skip: !Platform.isMacOS,
    );
  }
}
