import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/core/documents/document_record.dart';
import 'package:audyt/core/documents/folder_placement_plan.dart';
import 'package:audyt/core/documents/paid_claim_filing.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/scan_fields.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'paid claim moves its document to Expenses with an expense filename',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-paid-claim-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf101');
      final documentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf102');
      final paymentBatchId = EntityId.parse(
        '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf103',
      );
      final sourceRelativePath = 'Claims/2026/receipt.pdf';
      final source = File('${root.path}/$sourceRelativePath')
        ..createSync(recursive: true)
        ..writeAsStringSync('original receipt bytes');
      final hash = sha256.convert(source.readAsBytesSync()).toString();
      final document =
          DocumentRecord.staged(
                id: documentId,
                transactionId: claimId,
                originalFilename: 'receipt.pdf',
                mimeType: 'application/pdf',
                byteSize: source.lengthSync(),
                sha256: hash,
                createdAt: DateTime.utc(2026, 8, 30, 1),
              )
              .withScan(
                ScannedDocumentFields.fromScan(
                  rawVendorName: 'ACME OFFICE SUPPLIES',
                  documentDate: DateTime.utc(2026, 8, 29),
                ),
              )
              .readyToFile(
                destinationType: DocumentDestinationType.localFolder,
                relativePath: sourceRelativePath,
              )
              .filed();
      final documents = InMemoryDocumentRecordStore(records: [document]);
      final claims = ClaimStore(
        claims: [
          Claim.draft(
            id: claimId,
            vendorName: 'Acme Office Supplies',
            amount: Money.fromMinor(1250, 'MYR'),
            claimantName: 'Aina Rahman',
            incurredOn: DateTime.utc(2026, 8, 29),
            category: 'Office Supplies & Small Equipment',
            claimCategoryCode: 'office-supplies',
            expenseCategoryCode: 'office-supplies-small-equipment',
            expenseAccountCode: 'expense.office-supplies-small-equipment',
            businessPurpose: 'Client workshop',
            attachments: [
              ReceiptAttachment.queued(
                ReceiptAttachmentInput(
                  originalId: documentId.value,
                  batchId: 'claim-attachment-batch',
                  filename: 'receipt.pdf',
                  mimeType: 'application/pdf',
                  bytes: Uint8List.fromList(source.readAsBytesSync()),
                ),
              ).withStatus(AttachmentProcessingStatus.ready),
            ],
          ).submit().approve(),
        ],
      );
      final defaults = PaidClaimFilingDefaults(
        managedRootPath: root.path,
        expenseFolderPlans: [
          DocumentNamingPlan([NamingColumn.year()]),
          DocumentNamingPlan([NamingColumn.monthNumber()]),
        ],
        expenseFilenamePlan: DocumentNamingPlan([
          NamingColumn.custom('EXP'),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.day(),
          NamingColumn.monthNumber(),
          NamingColumn.yearShort(),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.field('receiptDate'),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.reference(),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.field('document'),
        ]),
      );
      final filing = PaidClaimFilingService(
        claimStore: claims,
        documentStore: documents,
        defaults: defaults,
      );

      final result = await filing.markPaidAndFile(
        claimId: claimId,
        paymentBatchId: paymentBatchId,
        paidAt: DateTime.utc(2026, 9, 3, 12),
      );

      expect(result.status, PaidClaimFilingStatus.completed);
      expect(claims.byId(claimId)?.status, ClaimStatus.paid);
      expect(result.documents, hasLength(1));
      expect(
        result.documents.single.destinationRelativePath,
        startsWith('Expenses/2026/09/'),
      );
      expect(
        result.documents.single.expenseFilename,
        startsWith('EXP-030926-2908-'),
      );
      expect(result.documents.single.expenseFilename, isNot(contains('Claim')));
      expect(result.documents.single.paidStamp.state, 'Paid');
      expect(result.documents.single.paidStamp.claimId, claimId);
      expect(result.documents.single.paidStamp.paymentBatchId, paymentBatchId);
      expect(
        result.documents.single.paidStamp.paidAt,
        DateTime.utc(2026, 9, 3, 12),
      );
      expect(source.existsSync(), isFalse);
      final destination = File(
        '${root.path}/${result.documents.single.destinationRelativePath}',
      );
      expect(destination.readAsStringSync(), 'original receipt bytes');
      expect(sha256.convert(destination.readAsBytesSync()).toString(), hash);
      final stored = documents.byId(documentId)!;
      expect(stored.status, DocumentStatus.filed);
      expect(
        stored.relativePath,
        result.documents.single.destinationRelativePath,
      );
      expect(stored.sha256, hash);
      expect(stored.paidStamp, isNotNull);
      expect(result.expenseTransactionId, isNull);

      final metadata = File(
        '${root.path}/${result.documents.single.metadataRelativePath}',
      );
      expect(metadata.existsSync(), isTrue);
      final metadataText = metadata.readAsStringSync();
      expect(metadataText, contains('"state":"Paid"'));
      expect(metadataText, contains(paymentBatchId.value));
      expect(metadataText, contains('2026-09-03T12:00:00.000Z'));

      final retry = await filing.markPaidAndFile(
        claimId: claimId,
        paymentBatchId: paymentBatchId,
        paidAt: DateTime.utc(2026, 9, 3, 12),
      );
      expect(retry.status, PaidClaimFilingStatus.completed);
      expect(
        retry.documents.single.destinationRelativePath,
        result.documents.single.destinationRelativePath,
      );
      expect(metadata.readAsStringSync(), metadataText);
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.audyt.json')),
        hasLength(1),
      );

      final auditLostRetry =
          await PaidClaimFilingService(
            claimStore: claims,
            documentStore: documents,
            defaults: defaults,
          ).markPaidAndFile(
            claimId: claimId,
            paymentBatchId: paymentBatchId,
            paidAt: DateTime.utc(2026, 9, 3, 12),
          );
      expect(auditLostRetry.status, PaidClaimFilingStatus.completed);
      expect(
        auditLostRetry.documents.single.destinationRelativePath,
        result.documents.single.destinationRelativePath,
      );
    },
  );

  test('a different destination occupant fails without overwriting or updating the record', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-paid-collision-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf104');
    final documentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf105');
    final paymentBatchId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf106',
    );
    final sourceRelativePath = 'Claims/2026/collision.pdf';
    final source = File('${root.path}/$sourceRelativePath')
      ..createSync(recursive: true)
      ..writeAsStringSync('claim source');
    final hash = sha256.convert(source.readAsBytesSync()).toString();
    final document =
        DocumentRecord.staged(
              id: documentId,
              transactionId: claimId,
              originalFilename: 'collision.pdf',
              mimeType: 'application/pdf',
              byteSize: source.lengthSync(),
              sha256: hash,
              createdAt: DateTime.utc(2026, 8, 30),
            )
            .withScan(
              ScannedDocumentFields.fromScan(
                rawVendorName: 'Collision Vendor',
                documentDate: DateTime.utc(2026, 8, 29),
              ),
            )
            .readyToFile(
              destinationType: DocumentDestinationType.localFolder,
              relativePath: sourceRelativePath,
            )
            .filed();
    final documents = InMemoryDocumentRecordStore(records: [document]);
    final claims = ClaimStore(
      claims: [
        Claim.draft(
          id: claimId,
          vendorName: 'Collision Vendor',
          amount: Money.fromMinor(100, 'MYR'),
          claimantName: 'Aina Rahman',
          incurredOn: DateTime.utc(2026, 8, 29),
          category: 'Office Supplies & Small Equipment',
          claimCategoryCode: 'office-supplies',
          expenseCategoryCode: 'office-supplies-small-equipment',
          expenseAccountCode: 'expense.office-supplies-small-equipment',
          businessPurpose: 'Collision test',
          attachments: [
            ReceiptAttachment.queued(
              ReceiptAttachmentInput(
                originalId: documentId.value,
                batchId: 'claim-attachment-batch',
                filename: 'collision.pdf',
                mimeType: 'application/pdf',
                bytes: Uint8List.fromList(source.readAsBytesSync()),
              ),
            ).withStatus(AttachmentProcessingStatus.ready),
          ],
        ).submit().approve(),
      ],
    );
    final defaults = PaidClaimFilingDefaults(
      managedRootPath: root.path,
      expenseFolderPlans: [
        DocumentNamingPlan([NamingColumn.year()]),
      ],
      expenseFilenamePlan: DocumentNamingPlan([
        NamingColumn.custom('EXP'),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.reference(),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.field('document'),
      ]),
    );
    final destination =
        File(
            '${root.path}/Expenses/2026/EXP-${claimId.value}-${documentId.value}.pdf',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('unrelated destination');

    final result =
        await PaidClaimFilingService(
          claimStore: claims,
          documentStore: documents,
          defaults: defaults,
        ).markPaidAndFile(
          claimId: claimId,
          paymentBatchId: paymentBatchId,
          paidAt: DateTime.utc(2026, 8, 30, 12),
        );

    expect(result.status, PaidClaimFilingStatus.failed);
    expect(result.failureCode, 'destination_collision');
    expect(result.documents, hasLength(1));
    expect(result.documents.single.sourceRelativePath, sourceRelativePath);
    expect(result.documents.single.destinationRelativePath, endsWith('.pdf'));
    expect(claims.byId(claimId)?.status, ClaimStatus.paid);
    expect(source.existsSync(), isTrue);
    expect(source.readAsStringSync(), 'claim source');
    expect(destination.readAsStringSync(), 'unrelated destination');
    expect(documents.byId(documentId)?.relativePath, sourceRelativePath);
    expect(documents.byId(documentId)?.paidStamp, isNull);
  });

  test('finalizes an already-paid claim when the filing audit checkpoint is absent', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-paid-recovery-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf107');
    final documentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf108');
    final paymentBatchId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf109',
    );
    final sourceRelativePath = 'Claims/2026/recovery.pdf';
    final source = File('${root.path}/$sourceRelativePath')
      ..createSync(recursive: true)
      ..writeAsStringSync('recovery source');
    final hash = sha256.convert(source.readAsBytesSync()).toString();
    final document =
        DocumentRecord.staged(
              id: documentId,
              transactionId: claimId,
              originalFilename: 'recovery.pdf',
              mimeType: 'application/pdf',
              byteSize: source.lengthSync(),
              sha256: hash,
              createdAt: DateTime.utc(2026, 8, 30),
            )
            .withScan(
              ScannedDocumentFields.fromScan(
                rawVendorName: 'Recovery Vendor',
                documentDate: DateTime.utc(2026, 8, 29),
              ),
            )
            .readyToFile(
              destinationType: DocumentDestinationType.localFolder,
              relativePath: sourceRelativePath,
            )
            .filed();
    final documents = InMemoryDocumentRecordStore(records: [document]);
    final claims = ClaimStore(
      claims: [
        Claim.draft(
          id: claimId,
          vendorName: 'Recovery Vendor',
          amount: Money.fromMinor(100, 'MYR'),
          claimantName: 'Aina Rahman',
          incurredOn: DateTime.utc(2026, 8, 29),
          category: 'Office Supplies & Small Equipment',
          claimCategoryCode: 'office-supplies',
          expenseCategoryCode: 'office-supplies-small-equipment',
          expenseAccountCode: 'expense.office-supplies-small-equipment',
          businessPurpose: 'Recovery test',
          attachments: [
            ReceiptAttachment.queued(
              ReceiptAttachmentInput(
                originalId: documentId.value,
                batchId: 'claim-attachment-batch',
                filename: 'recovery.pdf',
                mimeType: 'application/pdf',
                bytes: Uint8List.fromList(source.readAsBytesSync()),
              ),
            ).withStatus(AttachmentProcessingStatus.ready),
          ],
        ).submit().approve(),
      ],
    );
    claims.markPaid(
      claimId,
      paymentBatchId: paymentBatchId,
      paidAt: DateTime.utc(2026, 8, 30, 12),
    );

    final result =
        await PaidClaimFilingService(
          claimStore: claims,
          documentStore: documents,
          defaults: PaidClaimFilingDefaults.temporary(
            managedRootPath: root.path,
          ),
        ).markPaidAndFile(
          claimId: claimId,
          paymentBatchId: paymentBatchId,
          paidAt: DateTime.utc(2026, 8, 30, 12),
        );

    expect(result.status, PaidClaimFilingStatus.completed);
    expect(result.documents, hasLength(1));
    expect(source.existsSync(), isFalse);
    expect(documents.byId(documentId)?.status, DocumentStatus.filed);
  });

  test(
    'moves every document in a paid claim batch with one claim filing change',
    () async {
      final fixture = _makeMultiDocumentFixture();
      addTearDown(() {
        if (fixture.root.existsSync()) fixture.root.deleteSync(recursive: true);
      });

      final result = await fixture.filing.markPaidAndFile(
        claimId: fixture.claimId,
        paymentBatchId: fixture.paymentBatchId,
        paidAt: DateTime.utc(2026, 8, 30, 12),
      );

      expect(result.status, PaidClaimFilingStatus.completed);
      expect(result.documents, hasLength(2));
      expect(result.documentIds.toSet(), fixture.documentIds.toSet());
      expect(result.claimChanges, hasLength(1));
      expect(result.claimChanges.single.claimId, fixture.claimId);
      expect(result.claimChanges.single.batchId, fixture.paymentBatchId);
      expect(result.claimChanges.single.paidStamp, contains('Paid'));
      expect(result.createsExpenseTransaction, isFalse);
      expect(result.expenseTransactionId, isNull);
      for (final source in fixture.sourceFiles) {
        expect(source.existsSync(), isFalse);
      }
      for (final document in result.documents) {
        final destination = File(
          '${fixture.root.path}/${document.destinationRelativePath}',
        );
        expect(destination.existsSync(), isTrue);
        expect(
          sha256.convert(destination.readAsBytesSync()).toString(),
          document.originalSha256,
        );
        expect(
          fixture.documentStore.byId(document.documentId)?.relativePath,
          document.destinationRelativePath,
        );
        expect(
          fixture.documentStore.byId(document.documentId)?.paidStamp,
          document.paidStamp,
        );
      }
      expect(
        fixture.root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.audyt.json')),
        hasLength(2),
      );
    },
  );

  test('direct filing rejects draft, submitted, and approved claims', () async {
    final base = Claim.draft(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf130'),
      vendorName: 'Unpaid Vendor',
      amount: Money.fromMinor(100, 'MYR'),
      claimantName: 'Aina Rahman',
      incurredOn: DateTime.utc(2026, 8, 29),
      category: 'Office Supplies & Small Equipment',
      claimCategoryCode: 'office-supplies',
      expenseCategoryCode: 'office-supplies-small-equipment',
      expenseAccountCode: 'expense.office-supplies-small-equipment',
      businessPurpose: 'Unpaid lifecycle test',
      attachments: [
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'unpaid-receipt',
            batchId: 'unpaid-attachment-batch',
            filename: 'unpaid.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ).withStatus(AttachmentProcessingStatus.ready),
      ],
    );
    final claimsByState = <Claim>[base, base.submit(), base.submit().approve()];
    for (var index = 0; index < claimsByState.length; index += 1) {
      final claim = claimsByState[index];
      final root = Directory.systemTemp.createTempSync('audyt-paid-state-');
      final claims = ClaimStore(claims: [claim]);
      final filing = PaidClaimFilingService(
        claimStore: claims,
        documentStore: InMemoryDocumentRecordStore(),
        defaults: PaidClaimFilingDefaults.temporary(managedRootPath: root.path),
      );
      final batch = ClaimPaymentBatch.create(
        id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf${140 + index}'),
        claims: [base.submit()],
        paidAt: DateTime.utc(2026, 8, 30, 12),
      );

      await expectLater(
        filing.filePaidBatch(batch),
        throwsA(isA<StateError>()),
      );
      expect(claims.byId(claim.id)?.status, claim.status);
      expect(root.listSync(recursive: true), isEmpty);
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  test(
    'a failed document keeps every original and exposes a resumable error',
    () async {
      final fixture = _makeMultiDocumentFixture();
      addTearDown(() {
        if (fixture.root.existsSync()) fixture.root.deleteSync(recursive: true);
      });
      fixture.sourceFiles[1].writeAsStringSync('changed after scanning');

      final result = await fixture.filing.markPaidAndFile(
        claimId: fixture.claimId,
        paymentBatchId: fixture.paymentBatchId,
        paidAt: DateTime.utc(2026, 8, 30, 12),
      );

      expect(result.status, PaidClaimFilingStatus.failed);
      expect(result.failureCode, 'filesystem_failure');
      expect(result.documents, hasLength(2));
      expect(result.audit.status, PaidClaimFilingStatus.failed);
      expect(result.audit.failureCode, 'filesystem_failure');
      expect(
        fixture.filing.auditStore.byBatchId(fixture.paymentBatchId),
        result,
      );
      expect(
        fixture.filing.claimStore.byId(fixture.claimId)?.status,
        ClaimStatus.paid,
      );
      for (final source in fixture.sourceFiles) {
        expect(source.existsSync(), isTrue);
      }
      expect(Directory('${fixture.root.path}/Expenses').existsSync(), isFalse);
      for (final document in result.documents) {
        expect(
          fixture.documentStore.byId(document.documentId)?.relativePath,
          startsWith('Claims/'),
        );
        expect(
          fixture.documentStore.byId(document.documentId)?.paidStamp,
          isNull,
        );
      }
    },
  );

  test('temporary defaults stay behind an explicit managed root', () async {
    final root = Directory(
      '${Directory.systemTemp.path}/audyt-paid-defaults-test',
    );
    if (root.existsSync()) root.deleteSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final defaults = PaidClaimFilingDefaults.temporary(
      managedRootPath: root.path,
    );

    expect(defaults.managedRootPath, root.path);
    expect(defaults.expensesFolderName, 'Expenses');
    expect(defaults.managedRootPath, isNot(contains('/Documents')));
    expect(root.existsSync(), isFalse);

    final claim =
        Claim.draft(
          id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf150'),
          vendorName: 'Defaults Vendor',
          amount: Money.fromMinor(100, 'MYR'),
          claimantName: 'Aina Rahman',
          incurredOn: DateTime.utc(2026, 8, 29),
          category: 'Office Supplies & Small Equipment',
          claimCategoryCode: 'office-supplies',
          expenseCategoryCode: 'office-supplies-small-equipment',
          expenseAccountCode: 'expense.office-supplies-small-equipment',
          businessPurpose: 'Defaults isolation test',
          attachments: [
            ReceiptAttachment.queued(
              ReceiptAttachmentInput(
                originalId: 'defaults-receipt',
                batchId: 'defaults-batch',
                filename: 'receipt.pdf',
                mimeType: 'application/pdf',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ).withStatus(AttachmentProcessingStatus.ready),
          ],
        ).submit().markPaid(
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf151',
          ),
          paidAt: DateTime.utc(2026, 8, 30, 12),
        );
    final claims = ClaimStore(claims: [claim]);
    final result =
        await PaidClaimFilingService(
          claimStore: claims,
          documentStore: InMemoryDocumentRecordStore(),
          defaults: defaults,
        ).markPaidAndFile(
          claimId: claim.id,
          paymentBatchId: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf151',
          ),
          paidAt: DateTime.utc(2026, 8, 30, 12),
        );
    expect(result.status, PaidClaimFilingStatus.failed);
    expect(
      result.failureMessage,
      contains('attachments without document records'),
    );
    expect(root.existsSync(), isFalse);
  });
}

_MultiDocumentFixture _makeMultiDocumentFixture() {
  final root = Directory.systemTemp.createTempSync('audyt-paid-multi-');
  final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf120');
  final paymentBatchId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf121');
  final documentIds = <EntityId>[
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf122'),
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf123'),
  ];
  final sourceFiles = <File>[];
  final records = <DocumentRecord>[];
  final attachments = <ReceiptAttachment>[];
  for (var index = 0; index < documentIds.length; index += 1) {
    final filename = 'multi-$index.pdf';
    final sourceRelativePath = 'Claims/2026/$filename';
    final source = File('${root.path}/$sourceRelativePath')
      ..createSync(recursive: true)
      ..writeAsStringSync('multi document $index');
    final bytes = Uint8List.fromList(source.readAsBytesSync());
    final hash = sha256.convert(bytes).toString();
    sourceFiles.add(source);
    records.add(
      DocumentRecord.staged(
            id: documentIds[index],
            transactionId: claimId,
            originalFilename: filename,
            mimeType: 'application/pdf',
            byteSize: bytes.length,
            sha256: hash,
            createdAt: DateTime.utc(2026, 8, 30),
          )
          .withScan(
            ScannedDocumentFields.fromScan(
              rawVendorName: 'Multi Vendor',
              documentDate: DateTime.utc(2026, 8, 29),
            ),
          )
          .readyToFile(
            destinationType: DocumentDestinationType.localFolder,
            relativePath: sourceRelativePath,
          )
          .filed(),
    );
    attachments.add(
      ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: documentIds[index].value,
          batchId: 'multi-attachment-batch',
          filename: filename,
          mimeType: 'application/pdf',
          bytes: bytes,
        ),
      ).withStatus(AttachmentProcessingStatus.ready),
    );
  }
  final claim = Claim.draft(
    id: claimId,
    vendorName: 'Multi Vendor',
    amount: Money.fromMinor(500, 'MYR'),
    claimantName: 'Aina Rahman',
    incurredOn: DateTime.utc(2026, 8, 29),
    category: 'Office Supplies & Small Equipment',
    claimCategoryCode: 'office-supplies',
    expenseCategoryCode: 'office-supplies-small-equipment',
    expenseAccountCode: 'expense.office-supplies-small-equipment',
    businessPurpose: 'Multi-document test',
    attachments: attachments,
  ).submit().approve();
  final claimStore = ClaimStore(claims: [claim]);
  final documentStore = InMemoryDocumentRecordStore(records: records);
  return _MultiDocumentFixture(
    root: root,
    claimId: claimId,
    paymentBatchId: paymentBatchId,
    documentIds: documentIds,
    sourceFiles: sourceFiles,
    documentStore: documentStore,
    filing: PaidClaimFilingService(
      claimStore: claimStore,
      documentStore: documentStore,
      defaults: PaidClaimFilingDefaults.temporary(managedRootPath: root.path),
    ),
  );
}

final class _MultiDocumentFixture {
  _MultiDocumentFixture({
    required this.root,
    required this.claimId,
    required this.paymentBatchId,
    required this.documentIds,
    required this.sourceFiles,
    required this.documentStore,
    required this.filing,
  });

  final Directory root;
  final EntityId claimId;
  final EntityId paymentBatchId;
  final List<EntityId> documentIds;
  final List<File> sourceFiles;
  final InMemoryDocumentRecordStore documentStore;
  final PaidClaimFilingService filing;
}
