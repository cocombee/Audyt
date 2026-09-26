part of 'accounting_database.dart';

extension GeneratedDocumentPersistence on LocalAccountingDatabase {
  void _queueGeneratedDocument({
    required EntityId businessId,
    required EntityId recordId,
    required GeneratedDocumentKind kind,
    required int revision,
    required List<ReceiptAttachment> attachments,
  }) {
    if (_database.autocommit) {
      throw StateError(
        'Generated filing intent requires the draft transaction.',
      );
    }
    final generated = attachments.where((a) => a.isGenerated).toList();
    if (generated.length > 1) {
      throw StateError('Keep exactly one generated document per record.');
    }
    if (generated.isEmpty) return;
    final attachment = generated.single;
    final owner = attachment.generated!;
    if (owner.businessId != businessId ||
        owner.recordId != recordId ||
        owner.kind != kind ||
        attachment.originalId != owner.attachmentId ||
        !attachment.isPdf ||
        attachment.originalBytes.isEmpty ||
        attachment.derivativeBytes != null ||
        attachment.pdfBytes != null ||
        attachment.status != AttachmentProcessingStatus.ready) {
      throw StateError('Generated document does not belong to this record.');
    }
    _database.execute(
      '''INSERT INTO generated_document_deliveries
         (business_id,record_id,kind,revision,attachment_id,sha256,filename,
          document_date,status,attempts,failure)
         VALUES(?,?,?,?,?,?,?,?,'pending',0,NULL)
         ON CONFLICT(business_id,kind,record_id,revision) DO UPDATE SET
         status='pending',failure=NULL''',
      [
        businessId.value,
        recordId.value,
        kind.name,
        revision,
        attachment.originalId,
        attachment.originalSha256,
        attachment.filename,
        owner.documentDate.toIso8601String(),
      ],
    );
  }

  List<GeneratedDocumentDelivery> generatedDocumentDeliveries(
    EntityId businessId, {
    bool pendingOnly = false,
    bool latestOnly = false,
    GeneratedDocumentKind? kind,
  }) {
    _ensureOpen();
    return [
      for (final row in _database.select(
        '''SELECT * FROM generated_document_deliveries AS delivery WHERE business_id=?
           ${pendingOnly ? "AND status <> 'filed'" : ''}
           ${kind == null ? '' : 'AND kind=?'}
           ${latestOnly ? '''AND revision=(SELECT MAX(newer.revision) FROM generated_document_deliveries newer
             WHERE newer.business_id=delivery.business_id AND newer.kind=delivery.kind AND newer.record_id=delivery.record_id)''' : ''}
           ORDER BY kind,record_id,revision''',
        [businessId.value, if (kind != null) kind.name],
      ))
        GeneratedDocumentDelivery(
          businessId: EntityId.parse(row['business_id'] as String),
          recordId: EntityId.parse(row['record_id'] as String),
          kind: GeneratedDocumentKind.values.byName(row['kind'] as String),
          revision: row['revision'] as int,
          attachmentId: row['attachment_id'] as String,
          sha256: row['sha256'] as String,
          filename: row['filename'] as String,
          documentDate: DateTime.parse(row['document_date'] as String),
          status: GeneratedDocumentDeliveryStatus.values.byName(
            row['status'] as String,
          ),
          attempts: row['attempts'] as int,
          failure: row['failure'] as String?,
        ),
    ];
  }

  ReceiptAttachment generatedDocumentAttachment(
    GeneratedDocumentDelivery delivery,
  ) {
    _ensureOpen();
    // Resolve the immutable saved revision, not whatever latest draft now
    // occupies the editor. Old delivery retries retain their exact bytes.
    final table = delivery.kind == GeneratedDocumentKind.invoice
        ? 'invoice_draft_history'
        : 'quotation_history';
    final rows = _database.select(
      'SELECT payload FROM $table WHERE business_id=? AND id=? AND revision=?',
      [delivery.businessId.value, delivery.recordId.value, delivery.revision],
    );
    if (rows.length != 1) {
      throw StateError('Saved document revision unavailable.');
    }
    final snapshot =
        jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
    final attachments = delivery.kind == GeneratedDocumentKind.invoice
        ? Invoice.fromDraftSnapshot(snapshot).attachments
        : Estimate.fromSnapshot(snapshot).attachments;
    final attachment = attachments
        .where((a) => a.originalId == delivery.attachmentId)
        .single;
    if (attachment.generated?.businessId != delivery.businessId ||
        attachment.generated?.recordId != delivery.recordId ||
        attachment.generated?.kind != delivery.kind ||
        attachment.originalSha256 != delivery.sha256 ||
        attachment.filename != delivery.filename ||
        attachment.originalBytes.isEmpty ||
        sha256.convert(attachment.originalBytes).toString() !=
            delivery.sha256) {
      throw StateError(
        'Generated PDF bytes do not match their saved revision.',
      );
    }
    return attachment;
  }

  void authorizeGeneratedDocumentDelivery(
    GeneratedDocumentDelivery delivery,
    EntityId actorId,
  ) {
    _ensureOpen();
    _requireReconciliationOwner(delivery.businessId, actorId);
  }

  void finishGeneratedDocumentDelivery({
    required GeneratedDocumentDelivery delivery,
    required EntityId actorId,
    required String? failure,
  }) {
    _ensureOpen();
    _transaction(() {
      _requireReconciliationOwner(delivery.businessId, actorId);
      final existing = generatedDocumentDeliveries(delivery.businessId)
          .where(
            (item) =>
                item.kind == delivery.kind &&
                item.recordId == delivery.recordId &&
                item.revision == delivery.revision,
          )
          .single;
      if (existing.sha256 != delivery.sha256 ||
          existing.attachmentId != delivery.attachmentId) {
        throw StateError('Generated delivery identity changed. Reload.');
      }
      _database.execute(
        '''UPDATE generated_document_deliveries SET status=?,
           attempts=attempts+1,failure=? WHERE business_id=? AND kind=?
           AND record_id=? AND revision=? AND sha256=?''',
        [
          failure == null ? 'filed' : 'failed',
          failure,
          delivery.businessId.value,
          delivery.kind.name,
          delivery.recordId.value,
          delivery.revision,
          delivery.sha256,
        ],
      );
    });
  }
}
