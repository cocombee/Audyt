import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';

enum EstimateStatus {
  draft,
  sent,
  viewed,
  accepted,
  declined,
  closed,
  converted,
  expired,
}

final class Estimate {
  Estimate._({
    required this.id,
    required this.customerId,
    required this.total,
    required List<SalesLineItem> lines,
    required this.issueDate,
    required this.validUntil,
    required this.terms,
    required this.status,
    this.convertedInvoiceId,
    required this.documentNumber,
    required this.reference,
    required this.memo,
    required this.classification,
    required this.location,
    required this.taxMode,
    required List<ReceiptAttachment> attachments,
  }) : lines = List.unmodifiable(lines),
       attachments = List.unmodifiable(attachments);

  factory Estimate.draft({
    required EntityId id,
    required EntityId customerId,
    Money? total,
    List<SalesLineItem> lines = const [],
    required DateTime issueDate,
    required DateTime validUntil,
    PaymentTerms? terms,
    String documentNumber = '',
    String reference = '',
    String memo = '',
    String classification = '',
    String location = '',
    String taxMode = '',
    List<ReceiptAttachment> attachments = const [],
  }) {
    final normalizedIssueDate = accountingCalendarDate(issueDate);
    final normalizedValidUntil = accountingCalendarDate(validUntil);
    if (normalizedValidUntil.isBefore(normalizedIssueDate)) {
      throw ArgumentError.value(
        validUntil,
        'validUntil',
        'An estimate cannot expire before it is issued.',
      );
    }

    final resolvedTotal = lines.isEmpty ? total : SalesLineItem.totalFor(lines);
    if (resolvedTotal == null) {
      throw ArgumentError.value(
        total,
        'total',
        'An estimate requires a total or at least one line.',
      );
    }
    if (lines.isNotEmpty && total != null && total != resolvedTotal) {
      throw ArgumentError.value(
        total,
        'total',
        'An estimate total must equal the sum of its lines.',
      );
    }
    if (!resolvedTotal.isPositive) {
      throw ArgumentError.value(
        resolvedTotal,
        'total',
        'An estimate total must be positive.',
      );
    }

    return Estimate._(
      id: id,
      customerId: customerId,
      total: resolvedTotal,
      lines: lines,
      issueDate: normalizedIssueDate,
      validUntil: normalizedValidUntil,
      terms:
          terms ??
          PaymentTerms.netDays(
            normalizedValidUntil.difference(normalizedIssueDate).inDays,
          ),
      status: EstimateStatus.draft,
      documentNumber: documentNumber,
      reference: reference,
      memo: memo,
      classification: classification,
      location: location,
      taxMode: taxMode,
      attachments: attachments,
    );
  }

  final EntityId id;
  final EntityId customerId;
  final Money total;
  final List<SalesLineItem> lines;
  final DateTime issueDate;
  final DateTime validUntil;
  final PaymentTerms terms;
  final EstimateStatus status;
  final EntityId? convertedInvoiceId;
  final String documentNumber;
  final String reference;
  final String memo;
  final String classification;
  final String location;
  final String taxMode;
  final List<ReceiptAttachment> attachments;

  Invoice pricingSnapshot() => Invoice.draft(
    id: id,
    customerId: customerId,
    total: lines.isEmpty ? total : null,
    lines: lines,
    issueDate: issueDate,
    terms: terms,
    dueDate: terms.kind == PaymentTermKind.custom ? validUntil : null,
    documentNumber: documentNumber,
    reference: reference,
    memo: memo,
    classification: classification,
    location: location,
    taxMode: taxMode,
    attachments: attachments,
  );

  Map<String, Object?> snapshot() => {
    'pricing': pricingSnapshot().draftSnapshot(),
    'validUntil': validUntil.toIso8601String(),
    'status': status.name,
    'convertedInvoiceId': convertedInvoiceId?.value,
  };

  factory Estimate.fromSnapshot(Map<String, dynamic> value) {
    final pricing = Invoice.fromDraftSnapshot(
      Map<String, dynamic>.from(value['pricing'] as Map),
    );
    final status = EstimateStatus.values.byName(value['status'] as String);
    final converted = value['convertedInvoiceId'] as String?;
    if ((status == EstimateStatus.converted) != (converted != null)) {
      throw const FormatException(
        'Quotation conversion lineage is inconsistent.',
      );
    }
    final draft = Estimate.draft(
      id: pricing.id,
      customerId: pricing.customerId,
      total: pricing.total,
      lines: pricing.lines,
      issueDate: pricing.issueDate,
      validUntil: DateTime.parse(value['validUntil'] as String),
      terms: pricing.terms,
      documentNumber: pricing.documentNumber,
      reference: pricing.reference,
      memo: pricing.memo,
      classification: pricing.classification,
      location: pricing.location,
      taxMode: pricing.taxMode,
      attachments: pricing.attachments,
    );
    return draft._copyWith(
      status: status,
      convertedInvoiceId: converted == null ? null : EntityId.parse(converted),
    );
  }

  Estimate revise() {
    if (status == EstimateStatus.accepted ||
        status == EstimateStatus.converted) {
      throw StateError('Accepted or converted quotation pricing is immutable.');
    }
    return _copyWith(status: EstimateStatus.draft);
  }

  /// Current commercial edits preserve lifecycle and conversion ownership.
  /// The retained accepted/conversion snapshots remain separate history.
  Estimate reviseCurrent(Estimate replacement) {
    if (replacement.id != id ||
        replacement.status != EstimateStatus.draft ||
        replacement.convertedInvoiceId != null) {
      throw StateError('Use the same quotation identity for current edits.');
    }
    return replacement._copyWith(
      status: status,
      convertedInvoiceId: convertedInvoiceId,
    );
  }

  Estimate send() {
    if (status != EstimateStatus.draft) {
      throw StateError('Only draft estimates can be sent.');
    }
    return _copyWith(status: EstimateStatus.sent);
  }

  Estimate view() {
    if (status != EstimateStatus.sent) {
      throw StateError('Only sent estimates can be viewed.');
    }
    return _copyWith(status: EstimateStatus.viewed);
  }

  Estimate decline() {
    if (status != EstimateStatus.sent && status != EstimateStatus.viewed) {
      throw StateError('Only sent estimates can be declined.');
    }
    return _copyWith(status: EstimateStatus.declined);
  }

  Estimate close() {
    if (status != EstimateStatus.draft &&
        status != EstimateStatus.sent &&
        status != EstimateStatus.viewed &&
        status != EstimateStatus.declined) {
      throw StateError('Only an open estimate can be closed.');
    }
    return _copyWith(status: EstimateStatus.closed);
  }

  Estimate reopen() {
    if (status != EstimateStatus.closed &&
        status != EstimateStatus.declined &&
        status != EstimateStatus.expired) {
      throw StateError('Only a closed estimate can be reopened.');
    }
    return _copyWith(status: EstimateStatus.sent);
  }

  Estimate expire({required DateTime asOf}) {
    final normalizedAsOf = accountingCalendarDate(asOf);
    if (normalizedAsOf.isBefore(validUntil) ||
        normalizedAsOf == validUntil ||
        (status != EstimateStatus.sent && status != EstimateStatus.viewed)) {
      return this;
    }
    return _copyWith(status: EstimateStatus.expired);
  }

  Estimate accept() {
    if (status != EstimateStatus.sent && status != EstimateStatus.viewed) {
      throw StateError('Only sent estimates can be accepted.');
    }
    return _copyWith(status: EstimateStatus.accepted);
  }

  EstimateConversion convertToInvoice({
    required EntityId invoiceId,
    Map<EntityId, EntityId> invoiceLineIds = const {},
    required DateTime issueDate,
    required DateTime dueDate,
    String documentNumber = '',
  }) {
    if (status != EstimateStatus.accepted) {
      throw StateError('Only accepted estimates can become invoices.');
    }
    if (lines.isNotEmpty &&
        (invoiceLineIds.length != lines.length ||
            !lines.every((line) => invoiceLineIds.containsKey(line.id)) ||
            invoiceLineIds.values.toSet().length != lines.length ||
            invoiceLineIds.values.any(
              (id) => lines.any((line) => line.id == id),
            ))) {
      throw ArgumentError.value(
        invoiceLineIds,
        'invoiceLineIds',
        'Every estimate line requires one distinct invoice line ID.',
      );
    }
    final invoiceLines = lines
        .map(
          (line) =>
              line.copyForInvoice(invoiceLineId: invoiceLineIds[line.id]!),
        )
        .toList(growable: false);
    final invoice = Invoice.draft(
      id: invoiceId,
      customerId: customerId,
      total: invoiceLines.isEmpty ? total : null,
      lines: invoiceLines,
      issueDate: issueDate,
      dueDate: dueDate,
      sourceEstimateId: id,
      terms: terms,
      documentNumber: documentNumber,
      reference: reference,
      memo: memo,
      classification: classification,
      location: location,
      taxMode: taxMode,
      // The quotation owns its generated PDF. The invoice will render its own
      // output; manually supplied evidence retains its original identity/bytes.
      attachments: attachments.where((a) => !a.isGenerated).toList(),
    );
    return EstimateConversion(
      estimate: _copyWith(
        status: EstimateStatus.converted,
        convertedInvoiceId: invoiceId,
      ),
      invoice: invoice,
      sourceEstimateId: id,
    );
  }

  Estimate _copyWith({
    required EstimateStatus status,
    EntityId? convertedInvoiceId,
    List<ReceiptAttachment>? attachments,
  }) {
    return Estimate._(
      id: id,
      customerId: customerId,
      total: total,
      lines: lines,
      issueDate: issueDate,
      validUntil: validUntil,
      terms: terms,
      status: status,
      convertedInvoiceId: convertedInvoiceId ?? this.convertedInvoiceId,
      documentNumber: documentNumber,
      reference: reference,
      memo: memo,
      classification: classification,
      location: location,
      taxMode: taxMode,
      attachments: attachments ?? this.attachments,
    );
  }

  Estimate withAttachments(List<ReceiptAttachment> values) =>
      _copyWith(status: status, attachments: List.unmodifiable(values));
}

final class EstimateConversion {
  const EstimateConversion({
    required this.estimate,
    required this.invoice,
    required this.sourceEstimateId,
  });

  final Estimate estimate;
  final Invoice invoice;
  final EntityId sourceEstimateId;
}
