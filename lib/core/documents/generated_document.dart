import '../ids/entity_id.dart';

enum GeneratedDocumentKind { invoice, quotation }

/// Explicit ownership of an Audyt-rendered document. Never infer ownership
/// from a filename, MIME type or a user's uploaded PDF contents.
final class GeneratedDocumentProvenance {
  GeneratedDocumentProvenance({
    required this.businessId,
    required this.recordId,
    required this.kind,
    required this.contentSha256,
    required this.documentDate,
    this.templateVersion = 1,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(contentSha256) ||
        templateVersion < 1) {
      throw const FormatException('Invalid generated-document provenance.');
    }
  }

  final EntityId businessId, recordId;
  final GeneratedDocumentKind kind;
  final String contentSha256;
  final DateTime documentDate;
  final int templateVersion;

  String get attachmentId =>
      'generated:${businessId.value}:${kind.name}:${recordId.value}';

  Map<String, Object> toJson() => {
    'businessId': businessId.value,
    'recordId': recordId.value,
    'kind': kind.name,
    'contentSha256': contentSha256,
    'documentDate': documentDate.toIso8601String(),
    'templateVersion': templateVersion,
  };

  factory GeneratedDocumentProvenance.fromJson(Map<String, dynamic> json) =>
      GeneratedDocumentProvenance(
        businessId: EntityId.parse(json['businessId'] as String),
        recordId: EntityId.parse(json['recordId'] as String),
        kind: GeneratedDocumentKind.values.byName(json['kind'] as String),
        contentSha256: json['contentSha256'] as String,
        documentDate: DateTime.parse(json['documentDate'] as String),
        templateVersion: json['templateVersion'] as int,
      );
}

enum GeneratedDocumentDeliveryStatus { pending, filed, failed }

/// Portable filing intent committed with its record revision. The native
/// adapter retains device-local paths/bookmarks and exact version links.
final class GeneratedDocumentDelivery {
  const GeneratedDocumentDelivery({
    required this.businessId,
    required this.recordId,
    required this.kind,
    required this.revision,
    required this.attachmentId,
    required this.sha256,
    required this.filename,
    required this.documentDate,
    required this.status,
    required this.attempts,
    this.failure,
  });

  final EntityId businessId, recordId;
  final GeneratedDocumentKind kind;
  final int revision, attempts;
  final String attachmentId, sha256, filename;
  final DateTime documentDate;
  final GeneratedDocumentDeliveryStatus status;
  final String? failure;
}
