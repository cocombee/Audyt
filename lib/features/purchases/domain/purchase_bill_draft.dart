import 'dart:convert';

import '../../../core/documents/receipt_document.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../../core/storage/record_metadata.dart';
import '../../accounting/domain/payment_terms.dart';
import '../../sales/domain/sales_line_item.dart';
import '../../sales/domain/invoice_tax.dart';
import 'bill.dart';
import 'vendor.dart';

/// A purchase snapshot, not a posted payable. Shared line types own arithmetic
/// only; purchase account eligibility is rechecked at the commit boundary.
final class PurchaseBillDraft {
  PurchaseBillDraft({
    required this.metadata,
    required this.vendorSnapshot,
    required String documentNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    required PaymentTerms terms,
    required List<SalesLineItem> lines,
    List<ReceiptAttachment> attachments = const [],
    String supplierReference = '',
    this.memo = '',
    this.classification = '',
    this.location = '',
    this.taxMode,
  }) : documentNumber = documentNumber.trim(),
       supplierReference = supplierReference.trim(),
       lines = List.unmodifiable(lines),
       attachments = List.unmodifiable(attachments),
       bill = Bill.draft(
         id: metadata.recordId,
         vendorId: vendorSnapshot.id,
         total: SalesLineItem.totalFor(lines),
         issueDate: issueDate,
         dueDate: dueDate,
         terms: terms,
       ) {
    if (metadata.isTombstone ||
        metadata.businessId != vendorSnapshot.metadata.businessId ||
        this.documentNumber.isEmpty ||
        lines.any((l) => l.categoryId == null || l.sourceLineId != null) ||
        attachments.map((a) => a.originalId).toSet().length !=
            attachments.length) {
      throw ArgumentError(
        'Invalid bill identity, supplier, lines or evidence.',
      );
    }
    // Version-one sources have no overall tax-mode fact. Preserve them without
    // guessing Exempt/Out Of Scope from a zero rate. New UI sources record it.
    if (taxMode != null &&
        (!const [
              'Exclusive',
              'Inclusive',
              'Out Of Scope',
              'Exempt',
            ].contains(taxMode) ||
            lines.any(
              (line) =>
                  line.taxRatePercent == null ||
                  line.taxInclusive != (taxMode == 'Inclusive') ||
                  (const ['Exempt', 'Out Of Scope'].contains(taxMode) &&
                      InvoiceTaxRate.fromPercent(line.taxRatePercent!).units !=
                          0),
            ))) {
      throw ArgumentError(
        'Bill tax mode must agree with its exact line pricing.',
      );
    }
  }

  final RecordMetadata metadata;
  final Vendor vendorSnapshot;
  final Bill bill;
  final List<SalesLineItem> lines;
  final List<ReceiptAttachment> attachments;
  final String? taxMode;
  final String documentNumber,
      supplierReference,
      memo,
      classification,
      location;
  EntityId get id => metadata.recordId;
  Money get total => bill.total;

  Map<String, Object?> toJson() => {
    'version': taxMode == null ? 1 : 2,
    if (taxMode != null) 'taxMode': taxMode,
    'id': id.value,
    'businessId': metadata.businessId.value,
    'deviceId': metadata.originDeviceId.value,
    'createdAt': metadata.createdAt.toIso8601String(),
    'updatedAt': metadata.updatedAt.toIso8601String(),
    'revision': metadata.revision,
    'vendor': vendorSnapshot.toJson(),
    'bill': bill.draftSnapshot(),
    'documentNumber': documentNumber,
    'supplierReference': supplierReference,
    'memo': memo,
    'classification': classification,
    'location': location,
    'lines': lines.map((l) => l.toJson()).toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  /// JSON object order is irrelevant. Data-only recovery deliberately changes
  /// document availability, not its identity/checksums or financial facts.
  static String snapshotSignature(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    normalized['attachments'] = (json['attachments'] as List).map((raw) {
      final fields = raw as Map<String, dynamic>;
      final attachment = ReceiptAttachment.fromJson(fields);
      final saved = attachment.toJson();
      if (fields.length != saved.length ||
          fields.keys.any((k) => !saved.containsKey(k)) ||
          !AttachmentProcessingStatus.values.any(
            (s) => s.name == fields['status'],
          ) ||
          (fields['failureMessage'] != null &&
              fields['failureMessage'] is! String) ||
          (fields['_evidenceUnavailable'] == true &&
              [
                'originalBytes',
                'derivativeBytes',
                'pdfBytes',
              ].any((k) => fields[k] != null))) {
        throw const FormatException('Invalid bill evidence snapshot.');
      }
      return saved;
    }).toList();
    Object? ordered(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: ordered(value[k])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode(ordered(normalized));
  }

  factory PurchaseBillDraft.fromJson(Map<String, dynamic> json) {
    final keys = {
      'version',
      'id',
      'businessId',
      'deviceId',
      'createdAt',
      'updatedAt',
      'revision',
      'vendor',
      'bill',
      'documentNumber',
      'supplierReference',
      'memo',
      'classification',
      'location',
      'lines',
      'attachments',
      if (json['version'] == 2) 'taxMode',
    };
    if (!const [1, 2].contains(json['version']) ||
        json.length != keys.length ||
        json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unsupported purchase bill snapshot.');
    }
    try {
      final core = Bill.restoreDraft(json['bill'] as Map<String, dynamic>);
      final draft = PurchaseBillDraft(
        metadata: RecordMetadata.restore(
          recordId: EntityId.parse(json['id'] as String),
          businessId: EntityId.parse(json['businessId'] as String),
          originDeviceId: EntityId.parse(json['deviceId'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          updatedAt: DateTime.parse(json['updatedAt'] as String),
          revision: json['revision'] as int,
          deletedAt: null,
        ),
        vendorSnapshot: Vendor.fromJson(json['vendor'] as Map<String, dynamic>),
        documentNumber: json['documentNumber'] as String,
        issueDate: core.issueDate,
        dueDate: core.dueDate,
        terms: core.terms,
        lines: (json['lines'] as List)
            .map((l) => SalesLineItem.fromJson(l as Map<String, dynamic>))
            .toList(),
        attachments: (json['attachments'] as List)
            .map((a) => ReceiptAttachment.fromJson(a as Map<String, dynamic>))
            .toList(),
        supplierReference: json['supplierReference'] as String,
        memo: json['memo'] as String,
        classification: json['classification'] as String,
        location: json['location'] as String,
        taxMode: json['version'] == 2 ? json['taxMode'] as String : null,
      );
      // IDs, total, exact line/evidence fields and canonical dates must agree.
      if (snapshotSignature(draft.toJson()) != snapshotSignature(json)) {
        throw const FormatException('Inconsistent purchase bill snapshot.');
      }
      return draft;
    } catch (_) {
      throw const FormatException('Invalid purchase bill snapshot.');
    }
  }
}
