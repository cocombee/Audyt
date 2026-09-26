import 'package:audyt/core/documents/scan_fields.dart';
import 'package:audyt/core/ids/entity_id.dart';

enum DocumentStatus { staged, scanned, readyToFile, filed, failed }

enum DocumentDestinationType { localFolder, googleDriveFolder }

final class DocumentPaidStamp {
  const DocumentPaidStamp({
    required this.claimId,
    required this.paymentBatchId,
    required this.paidAt,
  });

  final EntityId claimId;
  final EntityId paymentBatchId;
  final DateTime paidAt;

  String get state => 'Paid';

  String get text =>
      '$state · Claim ${claimId.value} · Batch ${paymentBatchId.value} · ${paidAt.toUtc().toIso8601String()}';

  Map<String, Object> toJson() => <String, Object>{
    'state': state,
    'claimId': claimId.value,
    'paymentBatchId': paymentBatchId.value,
    'paidAt': paidAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is DocumentPaidStamp &&
      other.claimId == claimId &&
      other.paymentBatchId == paymentBatchId &&
      other.paidAt == paidAt;

  @override
  int get hashCode => Object.hash(claimId, paymentBatchId, paidAt);
}

final class DocumentRecord {
  DocumentRecord._({
    required this.id,
    required this.transactionId,
    required this.originalFilename,
    required this.mimeType,
    required this.byteSize,
    required this.sha256,
    required this.createdAt,
    required this.status,
    required this.scanFields,
    required this.destinationType,
    required this.relativePath,
    required this.failureMessage,
    required this.paidStamp,
  });

  factory DocumentRecord.staged({
    required EntityId id,
    required EntityId transactionId,
    required String originalFilename,
    required String mimeType,
    required int byteSize,
    required String sha256,
    required DateTime createdAt,
  }) {
    if (byteSize <= 0) {
      throw ArgumentError.value(
        byteSize,
        'byteSize',
        'Document cannot be empty.',
      );
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(sha256, 'sha256', 'Document hash is invalid.');
    }
    return DocumentRecord._(
      id: id,
      transactionId: transactionId,
      originalFilename: originalFilename,
      mimeType: mimeType,
      byteSize: byteSize,
      sha256: sha256.toLowerCase(),
      createdAt: createdAt.toUtc(),
      status: DocumentStatus.staged,
      scanFields: null,
      destinationType: null,
      relativePath: null,
      failureMessage: null,
      paidStamp: null,
    );
  }

  final EntityId id;
  final EntityId transactionId;
  final String originalFilename;
  final String mimeType;
  final int byteSize;
  final String sha256;
  final DateTime createdAt;
  final DocumentStatus status;
  final ScannedDocumentFields? scanFields;
  final DocumentDestinationType? destinationType;
  final String? relativePath;
  final String? failureMessage;
  final DocumentPaidStamp? paidStamp;

  String? get rawVendorName => scanFields?.rawVendorName;
  String? get vendorName => scanFields?.vendorName;
  DateTime? get documentDate => scanFields?.documentDate;

  DocumentRecord withScan(ScannedDocumentFields fields) {
    if (status != DocumentStatus.staged && status != DocumentStatus.scanned) {
      throw StateError('Only staged documents can be scanned.');
    }
    return _copyWith(status: DocumentStatus.scanned, scanFields: fields);
  }

  DocumentRecord readyToFile({
    required DocumentDestinationType destinationType,
    required String relativePath,
  }) {
    if (status != DocumentStatus.scanned &&
        status != DocumentStatus.readyToFile) {
      throw StateError('A document must be scanned before filing.');
    }
    _validateRelativePath(relativePath);
    return _copyWith(
      status: DocumentStatus.readyToFile,
      destinationType: destinationType,
      relativePath: relativePath,
    );
  }

  DocumentRecord filed() {
    if (status != DocumentStatus.readyToFile || relativePath == null) {
      throw StateError('Only ready documents can be filed.');
    }
    return _copyWith(status: DocumentStatus.filed);
  }

  DocumentRecord filedAfterPaidTransition({
    required DocumentDestinationType destinationType,
    required String relativePath,
    required DocumentPaidStamp paidStamp,
  }) {
    if (status != DocumentStatus.filed &&
        status != DocumentStatus.readyToFile) {
      throw StateError('Only filed or ready documents can be paid-filed.');
    }
    _validateRelativePath(relativePath);
    if (this.paidStamp != null && this.paidStamp != paidStamp) {
      throw StateError('A document cannot receive a different paid stamp.');
    }
    return _copyWith(
      status: DocumentStatus.filed,
      destinationType: destinationType,
      relativePath: relativePath,
      paidStamp: paidStamp,
      failureMessage: null,
    );
  }

  DocumentRecord failed(String message) {
    if (message.trim().isEmpty) {
      throw ArgumentError.value(
        message,
        'message',
        'A failure message is required.',
      );
    }
    return _copyWith(
      status: DocumentStatus.failed,
      failureMessage: message.trim(),
    );
  }

  DocumentRecord _copyWith({
    DocumentStatus? status,
    ScannedDocumentFields? scanFields,
    DocumentDestinationType? destinationType,
    String? relativePath,
    String? failureMessage,
    DocumentPaidStamp? paidStamp,
  }) {
    return DocumentRecord._(
      id: id,
      transactionId: transactionId,
      originalFilename: originalFilename,
      mimeType: mimeType,
      byteSize: byteSize,
      sha256: sha256,
      createdAt: createdAt,
      status: status ?? this.status,
      scanFields: scanFields ?? this.scanFields,
      destinationType: destinationType ?? this.destinationType,
      relativePath: relativePath ?? this.relativePath,
      failureMessage: failureMessage,
      paidStamp: paidStamp ?? this.paidStamp,
    );
  }

  static void _validateRelativePath(String path) {
    if (path.trim().isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').contains('..')) {
      throw ArgumentError.value(
        path,
        'relativePath',
        'Document path must remain relative to the managed root.',
      );
    }
  }
}
