import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:audyt/core/documents/document_record.dart';

import 'package:audyt/core/documents/paid_claim_filing.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/scan_fields.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('claims is a registered Money Out destination', () {
    final feature = FeatureRegistry.byPath('/claims');
    expect(feature, isNotNull);
    expect(feature!.id, 'claims');
    expect(feature.groupId, 'money-out');
  });

  testWidgets(
    'reaches the seeded claims list with truthful lifecycle actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const AudytApp(initialPath: '/claims'));

      expect(find.byKey(const ValueKey('page-title-claims')), findsOneWidget);
      expect(find.textContaining('Aina Rahman'), findsWidgets);
      expect(find.textContaining('Review'), findsWidgets);
      expect(find.text('Paid'), findsWidgets);
      expect(find.byKey(const ValueKey('claims-create')), findsOneWidget);
    },
  );

  testWidgets(
    'submits, approves, and pays one saved draft with receipt evidence',
    (tester) async {
      final store = ClaimStore.demo();
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: ClaimsPage(store: store)));
      await tester.pumpAndSettle();
      final created = store.all.singleWhere(
        (claim) => claim.status == ClaimStatus.draft,
      );
      expect(created.attachments, isNotEmpty);
      final open = find.byKey(ValueKey('claim-edit-${created.id}'));
      await tester.ensureVisible(open);
      expect(tester.widget<IconButton>(open), isNotNull);
      expect(find.byKey(ValueKey('claim-more-${created.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('claim-delete-${created.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey('claim-preview-${created.attachments.first.originalId}'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(ValueKey('claim-more-${created.id}')));
      await tester.pumpAndSettle();
      final submitAction = find.byKey(
        ValueKey<String>('claim-submit-${created.id}'),
      );
      expect(
        tester.getRect(submitAction).top,
        greaterThan(
          tester
              .getRect(find.byKey(ValueKey('claim-more-${created.id}')))
              .bottom,
        ),
      );
      await tester.ensureVisible(submitAction);
      await tester.tap(submitAction);
      await tester.pumpAndSettle();
      expect(store.byId(created.id)?.status, ClaimStatus.submitted);
      await tester.tap(find.byKey(ValueKey('claim-more-${created.id}')));
      await tester.pumpAndSettle();
      final approveAction = find.byKey(
        ValueKey<String>('claim-approve-${created.id}'),
      );
      await tester.ensureVisible(approveAction);
      await tester.tap(approveAction);
      await tester.pumpAndSettle();
      expect(store.byId(created.id)?.status, ClaimStatus.approved);
      await tester.tap(find.byKey(ValueKey('claim-more-${created.id}')));
      await tester.pumpAndSettle();
      final payAction = find.byKey(ValueKey<String>('claim-pay-${created.id}'));
      await tester.ensureVisible(payAction);
      await tester.tap(payAction);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey<String>('claim-payment-confirmation-${created.id}'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey<String>('claim-confirm-pay-${created.id}')),
      );
      await tester.pumpAndSettle();
      expect(store.byId(created.id)?.status, ClaimStatus.paid);
      expect(store.byId(created.id)?.amount.currency, 'MYR');
      expect(find.text('Payment recorded'), findsOneWidget);
    },
  );

  testWidgets(
    'does not create an unregistered Claim when registration is unavailable',
    (tester) async {
      final store = ClaimStore(claims: const []);
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: ClaimsPage(store: store)));
      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(ClaimEditorDialog), findsNothing);
      expect(find.text('Registration Required'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('record-claim-save-draft')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('record-claim-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(store.all, isEmpty);
    },
  );

  testWidgets(
    'records payment through the paid-claim filing coordinator when supplied',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('audyt-claims-ui-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf110');
      final documentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf111');
      final sourceRelativePath = 'Claims/2026/ui-receipt.pdf';
      final source = File('${root.path}/$sourceRelativePath')
        ..createSync(recursive: true)
        ..writeAsStringSync('ui receipt');
      final bytes = Uint8List.fromList(source.readAsBytesSync());
      final hash = sha256.convert(bytes).toString();
      final attachment = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: documentId.value,
          batchId: 'ui-claim-attachment-batch',
          filename: 'ui-receipt.pdf',
          mimeType: 'application/pdf',
          bytes: bytes,
        ),
      ).withStatus(AttachmentProcessingStatus.ready);
      final claim = Claim.draft(
        id: claimId,
        vendorName: 'UI Filing Vendor',
        amount: Money.fromMinor(100, 'MYR'),
        claimantName: 'Aina Rahman',
        incurredOn: DateTime.utc(2026, 8, 29),
        category: 'Office Supplies & Small Equipment',
        claimCategoryCode: 'office-supplies',
        expenseCategoryCode: 'office-supplies-small-equipment',
        expenseAccountCode: 'expense.office-supplies-small-equipment',
        businessPurpose: 'UI filing test',
        attachments: [attachment],
      ).submit().approve();
      final store = ClaimStore(claims: [claim]);
      final documentStore = InMemoryDocumentRecordStore(
        records: [
          DocumentRecord.staged(
                id: documentId,
                transactionId: claimId,
                originalFilename: 'ui-receipt.pdf',
                mimeType: 'application/pdf',
                byteSize: bytes.length,
                sha256: hash,
                createdAt: DateTime.utc(2026, 8, 30),
              )
              .withScan(
                ScannedDocumentFields.fromScan(
                  rawVendorName: 'UI Filing Vendor',
                  documentDate: DateTime.utc(2026, 8, 29),
                ),
              )
              .readyToFile(
                destinationType: DocumentDestinationType.localFolder,
                relativePath: sourceRelativePath,
              )
              .filed(),
        ],
      );
      final filing = _RecordingPaidClaimFilingCoordinator(store);

      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(store: store, paidClaimFilingService: filing),
        ),
      );
      await tester.tap(find.byKey(ValueKey<String>('claim-more-$claimId')));
      await tester.pumpAndSettle();
      final payAction = find.byKey(ValueKey<String>('claim-pay-$claimId'));
      await tester.ensureVisible(payAction);
      await tester.tap(payAction);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(ValueKey<String>('claim-confirm-pay-$claimId')),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pumpAndSettle();
      expect(store.byId(claimId)?.status, ClaimStatus.paid);
      expect(filing.calls, 1);
      expect(documentStore.byId(documentId)?.status, DocumentStatus.filed);
      expect(find.text('Payment recorded and filed'), findsOneWidget);
    },
  );
}

final class _RecordingPaidClaimFilingCoordinator
    implements PaidClaimFilingCoordinator {
  _RecordingPaidClaimFilingCoordinator(this.store);

  final ClaimStore store;
  int calls = 0;

  @override
  Future<PaidClaimFilingResult> markPaidAndFile({
    required EntityId claimId,
    required EntityId paymentBatchId,
    required DateTime paidAt,
  }) async {
    calls += 1;
    final batch = store.markPaid(
      claimId,
      paymentBatchId: paymentBatchId,
      paidAt: paidAt,
    );
    return PaidClaimFilingResult(
      status: PaidClaimFilingStatus.completed,
      claimIds: batch.claimIds,
      paymentBatchId: paymentBatchId,
      paidAt: paidAt,
      documents: const <PaidClaimFilingDocumentResult>[],
      claimChanges: const [],
    );
  }
}
