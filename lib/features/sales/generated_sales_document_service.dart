import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../core/documents/generated_document.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/ids/entity_id.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/data/accounting_database.dart';
import '../accounting/domain/customer.dart';
import '../accounting/domain/company_payment_term.dart';
import '../accounting/domain/recurring_document_template.dart';
import 'domain/estimate.dart';
import 'domain/invoice.dart';
import 'sales_document.dart';

abstract interface class GeneratedDocumentFileWriter {
  Future<void> writeAndVerify(
    GeneratedDocumentDelivery delivery,
    ReceiptAttachment attachment,
  );
}

/// Uses the same destination grant, writer, checksum validation and exact
/// version link as existing receipt filing. No direct unrestricted file I/O.
final class NativeGeneratedDocumentFileWriter
    implements GeneratedDocumentFileWriter {
  const NativeGeneratedDocumentFileWriter();
  static const _channel = MethodChannel('audyt/naming-settings');

  @override
  Future<void> writeAndVerify(
    GeneratedDocumentDelivery delivery,
    ReceiptAttachment attachment,
  ) async {
    final path = await _channel.invokeMethod<String>('saveDocument', {
      'kind': 'invoice',
      'generated': true,
      'attachmentId': delivery.attachmentId,
      'filename': delivery.filename,
      'year': delivery.documentDate.year,
      'month': delivery.documentDate.month,
      'bytes': attachment.originalBytes,
    });
    if (path == null || path.isEmpty) {
      throw StateError('The generated PDF destination was not confirmed.');
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'readDocument',
      {
        'attachmentId': delivery.attachmentId,
        'expectedSha256': delivery.sha256,
      },
    );
    final bytes = result?['bytes'];
    if (result?['mimeType'] != 'application/pdf' ||
        bytes is! Uint8List ||
        sha256.convert(bytes).toString() != delivery.sha256) {
      throw StateError('The filed generated PDF failed verification.');
    }
  }
}

final class GeneratedSalesDocumentSaveResult {
  const GeneratedSalesDocumentSaveResult(this.revision, this.filingFailure);
  final int revision;
  final String? filingFailure;
  bool get isFiled => filingFailure == null;
}

/// Rendering precedes the existing draft commit; physical delivery follows it.
/// A filing failure never rolls back or misreports the committed record.
final class GeneratedSalesDocumentService {
  const GeneratedSalesDocumentService({
    this.renderer = const SalesDocumentRenderer(),
    this.writer = const NativeGeneratedDocumentFileWriter(),
  });
  final SalesDocumentRenderer renderer;
  final GeneratedDocumentFileWriter writer;

  List<ReceiptAttachment> _attachments(
    Iterable<ReceiptAttachment> selected,
    ReceiptAttachment generated,
  ) {
    for (final old in selected.where((a) => a.isGenerated)) {
      if (old.originalId != generated.originalId) {
        throw StateError('Generated evidence belongs to a different record.');
      }
    }
    return [
      for (final a in selected)
        if (!a.isGenerated) a,
      generated,
    ];
  }

  Future<GeneratedSalesDocumentSaveResult> saveInvoice({
    required AccountingWorkspace workspace,
    required Invoice invoice,
    required Customer customer,
    required String filename,
    required int expectedRevision,
    required DateTime savedAt,
    Iterable<ReceiptAttachment> renderedForReview = const [],
    DocumentRecurrenceRequest? recurrence,
    CompanyPaymentTerm? selectedPaymentTerm,
  }) async {
    final businessId = workspace.identity.businessId;
    final actorId = workspace.identity.ownerId;
    final previous = workspace
        .invoiceDrafts()
        .where((r) => r.invoice.id == invoice.id)
        .firstOrNull
        ?.invoice;
    final attachment = await renderer.render(
      SalesDocumentSnapshot.invoice(
        businessId: businessId,
        invoice: invoice,
        customer: customer,
        preferences: workspace.preferences,
      ),
      filename: filename,
      previouslySaved: [
        ...renderedForReview,
        ...invoice.attachments,
        ...?previous?.attachments,
      ],
    );
    _requireSameWorkspace(workspace, businessId, actorId);
    if (selectedPaymentTerm != null) {
      final current = workspace.paymentTerms
          .where((term) => term.id == selectedPaymentTerm.id)
          .firstOrNull;
      if (!selectedPaymentTerm.active ||
          current == null ||
          !current.active ||
          current.revision != selectedPaymentTerm.revision ||
          jsonEncode(current.rule.toJson()) !=
              jsonEncode(selectedPaymentTerm.rule.toJson()) ||
          jsonEncode(invoice.terms.toJson()) !=
              jsonEncode(selectedPaymentTerm.rule.toJson()) ||
          invoice.dueDate !=
              selectedPaymentTerm.rule.dueDateFor(invoice.issueDate)) {
        throw StateError(
          'The selected company payment term changed. Reopen the invoice.',
        );
      }
    }
    final revision = workspace.saveInvoiceDraft(
      invoice.withAttachments(_attachments(invoice.attachments, attachment)),
      expectedRevision: expectedRevision,
      savedAt: savedAt,
      recurrence: recurrence,
    );
    return GeneratedSalesDocumentSaveResult(
      revision,
      await _deliver(
        workspace.database,
        businessId,
        actorId,
        GeneratedDocumentKind.invoice,
        invoice.id,
        revision,
      ),
    );
  }

  Future<GeneratedSalesDocumentSaveResult> saveQuotation({
    required AccountingWorkspace workspace,
    required Estimate quotation,
    required Customer customer,
    required String filename,
    required int expectedRevision,
    required DateTime savedAt,
    Iterable<ReceiptAttachment> renderedForReview = const [],
    DocumentRecurrenceRequest? recurrence,
    StoredQuotation? expectedCurrent,
    EntityId? currentRequestId,
  }) async {
    if ((expectedCurrent == null) != (currentRequestId == null) ||
        (expectedCurrent != null &&
            expectedCurrent.revision != expectedRevision)) {
      throw StateError(
        'Bind the current quotation save to its reviewed version.',
      );
    }
    final businessId = workspace.identity.businessId;
    final actorId = workspace.identity.ownerId;
    final previous = workspace
        .quotations()
        .where((r) => r.quotation.id == quotation.id)
        .firstOrNull
        ?.quotation;
    final attachment = await renderer.render(
      SalesDocumentSnapshot.quotation(
        businessId: businessId,
        quotation:
            expectedCurrent?.quotation.reviseCurrent(quotation) ?? quotation,
        customer: customer,
        preferences: workspace.preferences,
      ),
      filename: filename,
      previouslySaved: [
        ...renderedForReview,
        ...quotation.attachments,
        ...?previous?.attachments,
      ],
    );
    _requireSameWorkspace(workspace, businessId, actorId);
    final replacement = quotation.withAttachments(
      _attachments(quotation.attachments, attachment),
    );
    final revision = expectedCurrent == null
        ? workspace.saveQuotationDraft(
            replacement,
            expectedRevision: expectedRevision,
            savedAt: savedAt,
            recurrence: recurrence,
          )
        : workspace.saveCurrentQuotation(
            replacement,
            expected: expectedCurrent,
            reviewedCustomer: customer,
            requestId: currentRequestId!,
            savedAt: savedAt,
            recurrence: recurrence,
          );
    return GeneratedSalesDocumentSaveResult(
      revision,
      await _deliver(
        workspace.database,
        businessId,
        actorId,
        GeneratedDocumentKind.quotation,
        quotation.id,
        revision,
      ),
    );
  }

  void _requireSameWorkspace(
    AccountingWorkspace workspace,
    EntityId businessId,
    EntityId actorId,
  ) {
    if (workspace.identity.businessId != businessId ||
        workspace.identity.ownerId != actorId) {
      throw StateError('Company changed. Reopen the document before saving.');
    }
  }

  Future<String?> retry({
    required AccountingWorkspace workspace,
    required GeneratedDocumentKind kind,
    required EntityId recordId,
    required int revision,
  }) => _deliver(
    workspace.database,
    workspace.identity.businessId,
    workspace.identity.ownerId,
    kind,
    recordId,
    revision,
  );

  Future<String?> _deliver(
    LocalAccountingDatabase database,
    EntityId businessId,
    EntityId actorId,
    GeneratedDocumentKind kind,
    EntityId recordId,
    int revision,
  ) async {
    final intent = database
        .generatedDocumentDeliveries(businessId)
        .where(
          (d) =>
              d.kind == kind &&
              d.recordId == recordId &&
              d.revision == revision,
        )
        .single;
    String? failure;
    try {
      // Recheck authorization before any physical side effect, including retry.
      database.authorizeGeneratedDocumentDelivery(intent, actorId);
      final attachment = database.generatedDocumentAttachment(intent);
      await writer.writeAndVerify(intent, attachment);
    } catch (error) {
      failure = error.toString();
    }
    database.finishGeneratedDocumentDelivery(
      delivery: intent,
      actorId: actorId,
      failure: failure,
    );
    return failure;
  }
}
