import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../support/accounting_test_finders.dart';
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final journey in ['Claim', 'Voucher', 'Voucher Evidence']) {
      testWidgets('restored $journey edit commands at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final root = Directory.systemTemp.createTempSync(
          'audyt-purchase-edit-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final sourcePath = '${root.path}/source.sqlite';
        final source = await createDemoWorkspace(databasePath: sourcePath);
        final claimId = source.claims.all
            .firstWhere((c) => c.status == ClaimStatus.draft)
            .id;
        final expense = (await source.expenses()).first;
        const voucherId = 'audit-purchase-edit';
        final evidence = journey == 'Voucher Evidence';
        source.vouchers.save(
          PaymentVoucher.create(
            id: voucherId,
            sourceType: PaymentVoucherSourceType.directExpense,
            sourceId: expense.id.value,
            payee: expense.payee,
            amount: expense.amount,
            paymentAccount: 'Demo Bank',
            paymentAccountId: 'demo-bank',
            paymentMethod: 'Bank Transfer',
            paymentDate: expense.occurredOn,
            reference: 'AUDIT-PV-ORIGINAL',
            allocations: ['Saved allocation'],
            attachments: evidence
                ? source.claims.byId(claimId)!.attachments
                : [],
          ),
        );
        final before = tables(source);
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.now(),
        );
        source.dispose();
        final sourceBytes = File(sourcePath).readAsBytesSync();
        final path = '${root.path}/restored.sqlite';
        var workspace = await AccountingWorkspace.emptyRestore(path, archive);
        addTearDown(() => workspace.dispose());
        expect(tables(workspace), before);
        final isClaim = journey == 'Claim';
        final originalClaim = workspace.claims.byId(claimId)!;
        final originalVoucher = workspace.vouchers.byId(voucherId)!;
        final journalCount = (await workspace.journals()).length;
        final attachment = evidence ? originalVoucher.attachments.single : null;
        if (attachment != null) {
          expect(attachment.originalBytes, isEmpty);
          expect(attachment.status, AttachmentProcessingStatus.failed);
        }

        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        Future<void> enter(String key, String value) async {
          final f = find.byKey(ValueKey(key));
          await tester.ensureVisible(f);
          await enterAccountingText(tester, f, value);
          await tester.pumpAndSettle();
        }

        Future<void> capture(String state) => captureUi(
          tester,
          'Restored Purchase $journey $state ${width.toInt()}',
        );
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
            find.byKey(const ValueKey('navigation-item-expenses-vendors')),
          );
          await tap(find.text(isClaim ? 'Claims' : 'Payment Vouchers').first);
          expect(
            find.byType(isClaim ? ClaimsPage : PaymentVouchersPage),
            findsOneWidget,
          );
          await tap(
            find.byKey(
              ValueKey(isClaim ? 'claims-filter' : 'payment-voucher-filter'),
            ),
          );
          await tap(find.text('Draft').hitTestable().first);
          await capture('Draft List');
        }

        Future<void> open() => tap(
          find.byKey(
            ValueKey(
              isClaim ? 'claim-edit-$claimId' : 'voucher-view-$voucherId',
            ),
          ),
        );
        Future<void> cancel() async {
          await tap(find.bySemanticsLabel('Close').last);
          final discard = find.byKey(const ValueKey('expense-discard-changes'));
          if (discard.evaluate().isNotEmpty) {
            await tap(find.byKey(const ValueKey('expense-keep-editing')));
            expect(find.byType(RecordExpensePage), findsOneWidget);
            await tap(find.bySemanticsLabel('Close').last);
            await tap(discard);
          }
          expect(
            find.byType(
              isClaim ? RecordExpensePage : PaymentVoucherEditorDialog,
            ),
            findsNothing,
          );
        }

        Future<void> save() => tap(
          find.byKey(
            ValueKey(
              isClaim ? 'record-claim-save-draft' : 'voucher-save-draft',
            ),
          ),
        );
        Future<void> change(String value) =>
            enter(isClaim ? 'expense-field-notes' : 'voucher-reference', value);
        await page();
        await open();
        await change('Cancelled change');
        if (isClaim) {
          await tap(
            find.byKey(
              ValueKey(
                'expense-attachment-remove-${originalClaim.attachments.single.originalId}',
              ),
            ),
          );
          await tap(find.text('Delete').last);
        }
        await cancel();
        expect(tables(workspace), before);

        if (evidence) {
          await open();
          await change('AUDIT-PV-REVIEWED');
          await save();
          await capture('Metadata Save Attempt');
          expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
          final saved = workspace.vouchers.byId(voucherId)!;
          expect(saved.reference, 'AUDIT-PV-REVIEWED');
          expect(saved.attachments.single.toJson(), attachment!.toJson());
          expect(saved.toJson(), {
            ...originalVoucher.toJson(),
            'reference': 'AUDIT-PV-REVIEWED',
          });
          await capture('Saved Metadata');
          // Saving metadata cannot silently turn missing originals into evidence.
          await open();
          await tap(find.byKey(const ValueKey('voucher-submit')));
          expect(
            find.byKey(const ValueKey('voucher-editor-error')),
            findsOneWidget,
          );
          expect(
            workspace.vouchers.byId(voucherId)!.status,
            PaymentVoucherStatus.draft,
          );
          await capture('Submission Rejected');
          await cancel();
          final unchanged = tables(workspace);
          await tap(
            find.byKey(const ValueKey('voucher-more-audit-purchase-edit')),
          );
          await tap(
            find.byKey(const ValueKey('voucher-submit-audit-purchase-edit')),
          );
          expect(
            find.textContaining('Reconnect or review unavailable').first,
            findsOneWidget,
          );
          expect(tables(workspace), unchanged);
          expect(
            find.byKey(const ValueKey('payment-voucher-feedback')),
            findsOneWidget,
          );
          expect(find.text('Voucher Action Failed'), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          await capture('Row Submission Rejected');
          final pending = PaymentVoucher.fromJson({
            ...saved.toJson(),
            'status': PaymentVoucherStatus.pendingApproval.name,
          });
          expect(() => pending.approve(), throwsStateError);
        } else {
          await open();
          await change('Stale overwrite');
          if (isClaim) {
            workspace.claims.saveDraft(
              Claim.fromJson({
                ...workspace.claims.byId(claimId)!.toJson(),
                'businessPurpose': 'Newer saved purpose',
              }),
            );
          } else {
            workspace.vouchers.save(
              PaymentVoucher.fromJson({
                ...workspace.vouchers.byId(voucherId)!.toJson(),
                'reference': 'NEWER-PV-REFERENCE',
              }),
            );
          }
          final newer = tables(workspace);
          await save();
          await capture('Concurrent Save Attempt');
          expect(
            isClaim
                ? workspace.claims.byId(claimId)!.businessPurpose
                : workspace.vouchers.byId(voucherId)!.reference,
            isClaim ? 'Newer saved purpose' : 'NEWER-PV-REFERENCE',
            reason: 'An older open editor must not overwrite the newer saved value.',
          );
          expect(
            find.textContaining('changed since it was opened'),
            findsOneWidget,
          );
          expect(tables(workspace), newer);
          await capture('Stale Edit Rejected');
          await cancel();
          // A freshly opened editor can commit against the new current snapshot.
          await open();
          final field = find.byKey(
            ValueKey(isClaim ? 'expense-field-notes' : 'voucher-reference'),
          );
          if (isClaim) {
            expect(
              accountingDescriptionText('Newer saved purpose'),
              findsOneWidget,
            );
          } else {
            expect(
              tester.widget<TextFormField>(field).controller!.text,
              'NEWER-PV-REFERENCE',
            );
          }
          await change('Fresh reviewed edit');
          await save();
          expect(
            find.byType(
              isClaim ? RecordExpensePage : PaymentVoucherEditorDialog,
            ),
            findsNothing,
          );
          if (isClaim) {
            final current = workspace.claims.byId(claimId)!;
            expect(current.legacySource!.toJson(), {
              ...originalClaim.toJson(),
              'businessPurpose': 'Newer saved purpose',
            });
            expect(current.expenseDraft!.notes, 'Fresh reviewed edit');
            expect(current.claimantName, originalClaim.claimantName);
            expect(
              current.attachments.single.toJson(),
              originalClaim.attachments.single.toJson(),
            );
            expect(current.amount, originalClaim.amount);
          } else {
            expect(workspace.vouchers.byId(voucherId)!.toJson(), {
              ...originalVoucher.toJson(),
              'reference': 'Fresh reviewed edit',
              'preparer': null,
              'approver': null,
            });
          }
          await capture('Fresh Edit Saved');
          await open();
          await enter(
            isClaim ? 'expense-field-date' : 'voucher-date',
            '02-10-2026',
          );
          await save();
          expect(
            isClaim
                ? workspace.claims.byId(claimId)!.incurredOn
                : workspace.vouchers.byId(voucherId)!.paymentDate,
            DateTime.utc(2026, 10, 2),
          );
          await open();
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(
                    ValueKey(isClaim ? 'expense-field-date' : 'voucher-date'),
                  ),
                )
                .controller!
                .text,
            '02-10-2026',
          );
          await capture('Changed Calendar Date');
          await cancel();
        }
        expect((await workspace.journals()).length, journalCount);
        final savedTables = tables(workspace);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(tables(workspace), savedTables);
        expect(File(sourcePath).readAsBytesSync(), sourceBytes);
        await page();
        await open();
        await capture('Restarted Editor');
        await cancel();
        expect(tables(workspace), savedTables);
        if (isClaim) {
          await tap(find.byKey(ValueKey('claim-more-$claimId')));
          await tap(find.byKey(ValueKey('claim-submit-$claimId')));
          expect(find.byKey(const ValueKey('claims-feedback')), findsOneWidget);
          expect(find.text('Claim Action Failed'), findsOneWidget);
          expect(
            find.textContaining('Claim could not be submitted'),
            findsOneWidget,
          );
          expect(find.byType(SnackBar), findsNothing);
          expect(tables(workspace), savedTables);
          await capture('Row Submission Rejected');
          final submitted = workspace.claims.all.firstWhere(
            (c) => c.status == ClaimStatus.submitted,
          );
          await tap(find.byKey(const ValueKey('claims-filter')));
          await tap(find.text(ClaimStatus.submitted.label).hitTestable().first);
          await tap(find.byKey(ValueKey('claim-edit-${submitted.id}')));
          await capture('Submitted Current Editor');
          expect(
            find.byKey(const ValueKey('record-claim-save-draft')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('record-claim-submit')),
            findsOneWidget,
          );
          for (final key in [
            'record-claim-save-draft',
            'record-claim-submit',
          ]) {
            expect(
              tester
                  .widget<ButtonStyleButton>(find.byKey(ValueKey(key)))
                  .onPressed,
              isNull,
            );
          }
          await tap(find.byKey(const ValueKey('expense-add-line')));
          await tap(find.byKey(const ValueKey('expense-remove-line-1')));
          await tap(
            find
                .ancestor(
                  of: accountingCloseIcon(),
                  matching: find.byType(IconButton),
                )
                .first,
          );
          expect(tables(workspace), savedTables);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
