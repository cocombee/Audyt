import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/documents/claim_filing.dart';
import 'package:audyt/core/documents/document_placement.dart';
import 'package:audyt/core/documents/document_record.dart';
import 'package:audyt/core/documents/document_record_store.dart';
import 'package:audyt/core/documents/folder_placement_plan.dart';
import 'package:audyt/core/documents/local_folder_document_adapter.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

export 'document_record_store.dart';

enum PaidClaimFilingStatus { pending, completed, failed }

final class PaidClaimFilingDefaults {
  PaidClaimFilingDefaults({
    required String managedRootPath,
    this.expensesFolderName = 'Expenses',
    Iterable<DocumentNamingPlan>? expenseFolderPlans,
    DocumentNamingPlan? expenseFilenamePlan,
  }) : managedRootPath = managedRootPath.trim(),
       expenseFolderPlans = List<DocumentNamingPlan>.unmodifiable(
         expenseFolderPlans ?? _defaultExpenseFolderPlans(),
       ),
       expenseFilenamePlan =
           expenseFilenamePlan ?? _defaultExpenseFilenamePlan() {
    if (this.managedRootPath.isEmpty) {
      throw ArgumentError.value(
        managedRootPath,
        'managedRootPath',
        'A managed document root is required.',
      );
    }
    if (expensesFolderName.trim().isEmpty ||
        expensesFolderName.contains('/') ||
        expensesFolderName.contains('\\') ||
        expensesFolderName == '.' ||
        expensesFolderName == '..') {
      throw ArgumentError.value(
        expensesFolderName,
        'expensesFolderName',
        'The Expenses folder name must be one path-safe segment.',
      );
    }
    final forbiddenRoot = '${Platform.environment['HOME'] ?? ''}/Documents';
    if (this.managedRootPath == forbiddenRoot ||
        this.managedRootPath.startsWith('$forbiddenRoot/')) {
      throw ArgumentError.value(
        managedRootPath,
        'managedRootPath',
        'The temporary paid-filing defaults cannot use the Documents folder.',
      );
    }
    if (this.expenseFolderPlans.isEmpty) {
      throw ArgumentError.value(
        expenseFolderPlans,
        'expenseFolderPlans',
        'At least one Expense folder naming plan is required.',
      );
    }
  }

  factory PaidClaimFilingDefaults.temporary({required String managedRootPath}) {
    return PaidClaimFilingDefaults(managedRootPath: managedRootPath);
  }

  final String managedRootPath;
  final String expensesFolderName;
  final List<DocumentNamingPlan> expenseFolderPlans;
  final DocumentNamingPlan expenseFilenamePlan;

  static List<DocumentNamingPlan> _defaultExpenseFolderPlans() => [
    DocumentNamingPlan([NamingColumn.year()]),
    DocumentNamingPlan([
      NamingColumn.monthNumber(),
      NamingColumn.separator(NamingSeparator.dot),
      NamingColumn.custom(' '),
      NamingColumn.monthName(),
      NamingColumn.custom(' '),
      NamingColumn.year(),
    ]),
  ];

  static DocumentNamingPlan _defaultExpenseFilenamePlan() =>
      DocumentNamingPlan([
        NamingColumn.custom('EXP'),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.reference(),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.field('document'),
      ]);
}

final class PaidClaimFilingDocumentResult {
  const PaidClaimFilingDocumentResult({
    required this.claimId,
    required this.documentId,
    required this.sourceRelativePath,
    required this.destinationRelativePath,
    required this.expenseFilename,
    required this.originalFilename,
    required this.originalSha256,
    required this.paidStamp,
    required this.metadataRelativePath,
  });

  final EntityId claimId;
  final EntityId documentId;
  final String sourceRelativePath;
  final String destinationRelativePath;
  final String expenseFilename;
  final String originalFilename;
  final String originalSha256;
  final DocumentPaidStamp paidStamp;
  final String metadataRelativePath;
}

final class PaidClaimFilingAuditRecord {
  PaidClaimFilingAuditRecord({
    required this.status,
    required List<EntityId> claimIds,
    required this.paymentBatchId,
    required this.paidAt,
    required List<PaidClaimFilingDocumentResult> documents,
    required List<ClaimFilingChange> claimChanges,
    required this.failureCode,
    required this.failureMessage,
  }) : claimIds = List<EntityId>.unmodifiable(claimIds),
       documents = List<PaidClaimFilingDocumentResult>.unmodifiable(documents),
       claimChanges = List<ClaimFilingChange>.unmodifiable(claimChanges);

  final PaidClaimFilingStatus status;
  final List<EntityId> claimIds;
  final EntityId paymentBatchId;
  final DateTime paidAt;
  final List<PaidClaimFilingDocumentResult> documents;
  final List<ClaimFilingChange> claimChanges;
  final String? failureCode;
  final String? failureMessage;
}

final class PaidClaimFilingResult {
  PaidClaimFilingResult({
    required this.status,
    required List<EntityId> claimIds,
    required this.paymentBatchId,
    required this.paidAt,
    required List<PaidClaimFilingDocumentResult> documents,
    required List<ClaimFilingChange> claimChanges,
    this.failureCode,
    this.failureMessage,
  }) : claimIds = List<EntityId>.unmodifiable(claimIds),
       documents = List<PaidClaimFilingDocumentResult>.unmodifiable(documents),
       claimChanges = List<ClaimFilingChange>.unmodifiable(claimChanges),
       audit = PaidClaimFilingAuditRecord(
         status: status,
         claimIds: claimIds,
         paymentBatchId: paymentBatchId,
         paidAt: paidAt,
         documents: documents,
         claimChanges: claimChanges,
         failureCode: failureCode,
         failureMessage: failureMessage,
       );

  final PaidClaimFilingStatus status;
  final List<EntityId> claimIds;
  final EntityId paymentBatchId;
  final DateTime paidAt;
  final List<PaidClaimFilingDocumentResult> documents;
  final List<ClaimFilingChange> claimChanges;
  final String? failureCode;
  final String? failureMessage;
  final PaidClaimFilingAuditRecord audit;

  EntityId? get claimId => claimIds.length == 1 ? claimIds.single : null;

  List<EntityId> get documentIds =>
      documents.map((document) => document.documentId).toList(growable: false);

  Map<EntityId, String> get sourcePaths => Map<EntityId, String>.unmodifiable({
    for (final document in documents)
      document.documentId: document.sourceRelativePath,
  });

  Map<EntityId, String> get destinationPaths =>
      Map<EntityId, String>.unmodifiable({
        for (final document in documents)
          document.documentId: document.destinationRelativePath,
      });

  /// A moved claim receipt is classification/filed metadata, not a new expense.
  EntityId? get expenseTransactionId => null;

  bool get createsExpenseTransaction => false;
}

abstract interface class PaidClaimFilingCoordinator {
  Future<PaidClaimFilingResult> markPaidAndFile({
    required EntityId claimId,
    required EntityId paymentBatchId,
    required DateTime paidAt,
  });
}

abstract interface class PaidClaimBatchFilingCoordinator {
  Future<PaidClaimFilingResult> filePaidBatch(ClaimPaymentBatch batch);
}

abstract interface class PaidClaimFilingAuditStore {
  PaidClaimFilingResult? byBatchId(EntityId paymentBatchId);

  void save(PaidClaimFilingResult result);
}

final class InMemoryPaidClaimFilingAuditStore
    implements PaidClaimFilingAuditStore {
  final Map<EntityId, PaidClaimFilingResult> _results =
      <EntityId, PaidClaimFilingResult>{};

  @override
  PaidClaimFilingResult? byBatchId(EntityId paymentBatchId) =>
      _results[paymentBatchId];

  @override
  void save(PaidClaimFilingResult result) {
    _results[result.paymentBatchId] = result;
  }

  List<PaidClaimFilingResult> get all =>
      List<PaidClaimFilingResult>.unmodifiable(_results.values);
}

final class PaidClaimFilingService
    implements PaidClaimFilingCoordinator, PaidClaimBatchFilingCoordinator {
  PaidClaimFilingService({
    required this.claimStore,
    required this.documentStore,
    required this.defaults,
    LocalFolderDocumentAdapter? adapter,
    PaidClaimFilingAuditStore? auditStore,
  }) : adapter = adapter ?? LocalFolderDocumentAdapter(),
       auditStore = auditStore ?? InMemoryPaidClaimFilingAuditStore();

  final ClaimStore claimStore;
  final DocumentRecordStore documentStore;
  final PaidClaimFilingDefaults defaults;
  final LocalFolderDocumentAdapter adapter;
  final PaidClaimFilingAuditStore auditStore;

  @override
  Future<PaidClaimFilingResult> markPaidAndFile({
    required EntityId claimId,
    required EntityId paymentBatchId,
    required DateTime paidAt,
  }) async {
    return markClaimsPaidAndFile(
      claimIds: <EntityId>[claimId],
      paymentBatchId: paymentBatchId,
      paidAt: paidAt,
    );
  }

  Future<PaidClaimFilingResult> markClaimsPaidAndFile({
    required List<EntityId> claimIds,
    required EntityId paymentBatchId,
    required DateTime paidAt,
  }) async {
    final existing = auditStore.byBatchId(paymentBatchId);
    if (existing != null) {
      if (existing.status == PaidClaimFilingStatus.completed) {
        return existing;
      }
      final batch = ClaimPaymentBatch.restore(
        id: paymentBatchId,
        claims: existing.claimIds.map(_requiredClaim).toList(growable: false),
        paidAt: existing.paidAt,
      );
      return filePaidBatch(batch);
    }

    final storedClaims = claimIds.map(_requiredClaim).toList(growable: false);
    final normalizedPaidAt = paidAt.toUtc();
    if (storedClaims.isNotEmpty &&
        storedClaims.every(
          (claim) =>
              claim.status == ClaimStatus.paid &&
              claim.paymentBatchId == paymentBatchId &&
              claim.paidAt == normalizedPaidAt,
        )) {
      return filePaidBatch(
        ClaimPaymentBatch.restore(
          id: paymentBatchId,
          claims: storedClaims,
          paidAt: normalizedPaidAt,
        ),
      );
    }

    final batch = claimStore.markPaidBatch(
      claimIds: claimIds,
      paymentBatchId: paymentBatchId,
      paidAt: paidAt,
    );
    return filePaidBatch(batch);
  }

  @override
  Future<PaidClaimFilingResult> filePaidBatch(ClaimPaymentBatch batch) async {
    final existing = auditStore.byBatchId(batch.id);
    if (existing != null &&
        existing.status == PaidClaimFilingStatus.completed) {
      return existing;
    }
    _validatePaidBatch(batch);

    final documents = <PaidClaimFilingDocumentResult>[];
    final moves = <PaidDocumentMove>[];
    final sourcePaths = <EntityId, String>{};
    final destinationPaths = <EntityId, String>{};
    PaidClaimFilingPlan? plan;
    try {
      final stampText = 'Paid · Batch ${batch.id.value}';

      for (final claim in batch.claims) {
        final records = documentStore.forTransaction(claim.id);
        if (claim.attachments.isNotEmpty && records.isEmpty) {
          throw StateError(
            'Claim ${claim.id} has attachments without document records.',
          );
        }
        for (final record in records) {
          final entry = _planDocument(
            claim: claim,
            batch: batch,
            record: record,
          );
          if (documents.any(
            (document) => document.documentId == entry.documentId,
          )) {
            throw StateError('Document ${entry.documentId} is attached twice.');
          }
          documents.add(entry);
          final alreadyFiled =
              record.paidStamp == entry.paidStamp &&
              record.relativePath == entry.destinationRelativePath;
          if (!alreadyFiled) {
            sourcePaths[claim.id] ??= _parentOrSelf(entry.sourceRelativePath);
            destinationPaths[claim.id] ??= _parentOrSelf(
              entry.destinationRelativePath,
            );
            moves.add(
              PaidDocumentMove(
                documentId: entry.documentId,
                sourceRelativePath: entry.sourceRelativePath,
                destinationRelativePath: entry.destinationRelativePath,
                expectedSha256: entry.originalSha256,
                metadataJson: _metadataJson(
                  entry,
                  batchId: batch.id,
                  paidAt: batch.paidAt,
                ),
              ),
            );
          }
        }
      }

      plan = moves.isEmpty
          ? null
          : PaidClaimFilingPlan.build(
              batch: batch,
              sourcePaths: sourcePaths,
              destinationPaths: destinationPaths,
              paidStamp: stampText,
            );
      final pending = PaidClaimFilingResult(
        status: PaidClaimFilingStatus.pending,
        claimIds: batch.claimIds,
        paymentBatchId: batch.id,
        paidAt: batch.paidAt,
        documents: documents,
        claimChanges: plan?.changes ?? const <ClaimFilingChange>[],
      );
      auditStore.save(pending);

      if (moves.isNotEmpty) {
        await adapter.movePaidDocuments(
          managedRoot: Directory(defaults.managedRootPath),
          items: moves,
        );
        for (final document in documents) {
          final current = documentStore.byId(document.documentId);
          if (current == null) {
            throw StateError(
              'Document ${document.documentId} disappeared during filing.',
            );
          }
          documentStore.save(
            current.filedAfterPaidTransition(
              destinationType: DocumentDestinationType.localFolder,
              relativePath: document.destinationRelativePath,
              paidStamp: document.paidStamp,
            ),
          );
        }
      }

      final completed = PaidClaimFilingResult(
        status: PaidClaimFilingStatus.completed,
        claimIds: batch.claimIds,
        paymentBatchId: batch.id,
        paidAt: batch.paidAt,
        documents: documents,
        claimChanges: plan?.changes ?? const <ClaimFilingChange>[],
      );
      auditStore.save(completed);
      return completed;
    } on Object catch (exception) {
      final failed = PaidClaimFilingResult(
        status: PaidClaimFilingStatus.failed,
        claimIds: batch.claimIds,
        paymentBatchId: batch.id,
        paidAt: batch.paidAt,
        documents: documents,
        claimChanges: plan?.changes ?? const <ClaimFilingChange>[],
        failureCode: _failureCode(exception),
        failureMessage: exception.toString(),
      );
      auditStore.save(failed);
      return failed;
    }
  }

  void _validatePaidBatch(ClaimPaymentBatch batch) {
    for (final claim in batch.claims) {
      final stored = claimStore.byId(claim.id);
      if (stored == null ||
          stored.status != ClaimStatus.paid ||
          stored.paymentBatchId != batch.id ||
          stored.paidAt != batch.paidAt) {
        throw StateError(
          'Only claims already paid by this payment batch can be filed.',
        );
      }
    }
  }

  Claim _requiredClaim(EntityId id) {
    final claim = claimStore.byId(id);
    if (claim == null) throw StateError('Claim $id was not found.');
    return claim;
  }

  PaidClaimFilingDocumentResult _planDocument({
    required Claim claim,
    required ClaimPaymentBatch batch,
    required DocumentRecord record,
  }) {
    final source = record.relativePath;
    if (source == null || source.trim().isEmpty) {
      throw StateError('Document ${record.id} has no current filing path.');
    }
    if (record.destinationType != DocumentDestinationType.localFolder) {
      throw StateError(
        'Document ${record.id} is not stored in the local filing destination.',
      );
    }
    if (record.status != DocumentStatus.filed &&
        record.status != DocumentStatus.readyToFile) {
      throw StateError('Document ${record.id} is not ready for paid filing.');
    }
    final stamp = DocumentPaidStamp(
      claimId: claim.id,
      paymentBatchId: batch.id,
      paidAt: batch.paidAt,
    );
    if (record.paidStamp != null && record.paidStamp != stamp) {
      throw StateError('Document ${record.id} already has another paid stamp.');
    }
    final context = NamingContext(
      date: batch.paidAt,
      fields: <String, String>{
        'receiptDate': claim.incurredOn == null
            ? ''
            : '${claim.incurredOn!.day.toString().padLeft(2, '0')}${claim.incurredOn!.month.toString().padLeft(2, '0')}',
        'claim': claim.id.value,
        'document': record.id.value,
        'vendor': claim.vendorName,
        'payee': claim.vendorName,
        'category': claim.category,
        'categoryCode': claim.expenseCategoryCode ?? '',
        'type': 'Expense',
        'originalFilename': record.originalFilename,
      },
      reference: claim.id.value,
    );
    final placement = DocumentPlacementPlan.build(
      rootPath: defaults.managedRootPath,
      folderPlans: <DocumentNamingPlan>[
        DocumentNamingPlan([NamingColumn.custom(defaults.expensesFolderName)]),
        ...defaults.expenseFolderPlans,
      ],
      filenamePlan: defaults.expenseFilenamePlan,
      context: context,
    );
    final extension = _extension(record.originalFilename);
    final expenseFilename = _filename(placement.relativePath) + extension;
    final destination = _parentOrSelf(placement.relativePath);
    final destinationRelativePath = destination == placement.relativePath
        ? expenseFilename
        : '$destination/$expenseFilename';
    return PaidClaimFilingDocumentResult(
      claimId: claim.id,
      documentId: record.id,
      sourceRelativePath: source,
      destinationRelativePath: destinationRelativePath,
      expenseFilename: expenseFilename,
      originalFilename: record.originalFilename,
      originalSha256: record.sha256,
      paidStamp: stamp,
      metadataRelativePath: LocalFolderDocumentAdapter.metadataRelativePath(
        destinationRelativePath,
      ),
    );
  }

  String _metadataJson(
    PaidClaimFilingDocumentResult document, {
    required EntityId batchId,
    required DateTime paidAt,
  }) {
    return jsonEncode(<String, Object>{
      'schema': 'audyt.paid-document.v1',
      'documentId': document.documentId.value,
      'claimId': document.claimId.value,
      'originalFilename': document.originalFilename,
      'originalSha256': document.originalSha256,
      'sourceRelativePath': document.sourceRelativePath,
      'destinationRelativePath': document.destinationRelativePath,
      'paid': <String, Object>{
        ...document.paidStamp.toJson(),
        'batchId': batchId.value,
        'paidAt': paidAt.toUtc().toIso8601String(),
      },
    });
  }

  String _failureCode(Object exception) {
    if (exception is DocumentFilingConflict) return 'destination_collision';
    if (exception is FileSystemException) return 'filesystem_failure';
    if (exception is FormatException || exception is ArgumentError) {
      return 'invalid_filing_plan';
    }
    return 'filing_failed';
  }

  String _parentOrSelf(String path) {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? path : path.substring(0, separator);
  }

  String _filename(String path) {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? path : path.substring(separator + 1);
  }

  String _extension(String filename) {
    final basename = _filename(filename);
    final separator = basename.lastIndexOf('.');
    if (separator <= 0 || separator == basename.length - 1) return '';
    return basename.substring(separator);
  }
}
