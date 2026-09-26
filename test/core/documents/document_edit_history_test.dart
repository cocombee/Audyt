import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_optimization.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/receipt_review_queue.dart';

void main() {
  test('mixed edits undo chronologically after restart and branch correctly', () async {
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(originalId: 'mixed', batchId: 'b', filename: 'a.png', mimeType: 'image/png', bytes: img.encodePng(img.Image(width: 20, height: 30))));
    final queue = ReceiptReviewQueue([attachment]);
    final item = queue.current;
    item.cropHistory.updateRotation(10); item.cropHistory.endResize();
    item.applyWorkingAttachment(await const ReceiptDocumentPipeline().convertToPdf(attachment));
    item.cropHistory.updateRotation(20); item.cropHistory.endResize();
    final restored = ReceiptReviewQueue.fromJson(Map<String, dynamic>.from(queue.toJson()));
    final r = restored.current;
    r.undoLatest();
    expect(r.cropHistory.present.rotation, 10);
    expect(r.workingAttachment.pdfBytes, isNotNull);
    r.undoLatest();
    expect(r.workingAttachment.pdfBytes, isNull);
    r.undoLatest();
    expect(r.cropHistory.present.rotation, 0);
    r.redoLatest();
    expect(r.cropHistory.present.rotation, 10);
    expect(r.workingAttachment.pdfBytes, isNull);
    r.redoLatest(); r.redoLatest();
    expect(r.cropHistory.present.rotation, 20);
    expect(r.workingAttachment.pdfBytes, isNotNull);
    r.undoLatest(); r.undoLatest();
    r.cropHistory.updateRotation(30); r.cropHistory.endResize();
    expect(r.canRedoLatest, false);
    queue.dispose(); restored.dispose();
  });
  test('per-document Undo/Redo survives restart across JPEG and PDF actions', () async {
    final source = img.encodePng(img.Image(width: 20, height: 30));
    final attachment = await const ReceiptDocumentPipeline().process(ReceiptAttachmentInput(
      originalId: 'a', batchId: 'b', filename: 'a.png', mimeType: 'image/png', bytes: Uint8List.fromList(source)));
    final queue = ReceiptReviewQueue([attachment]);
    final edited = await const DocumentOptimizationEngine().optimize(attachment,
      const DocumentOptimizationRecipe(rotation: 90, quality: 80, sharpen: 0.2));
    queue.current.applyWorkingAttachment(edited);
    final pdf = await const ReceiptDocumentPipeline().convertToPdf(edited);
    queue.current.applyWorkingAttachment(pdf);
    final restored = ReceiptReviewQueue.fromJson(Map<String, dynamic>.from(queue.toJson()));
    expect(restored.current.workingAttachment.pdfBytes, isNotNull);
    restored.current.undoEdit();
    expect(restored.current.workingAttachment.pdfBytes, isNull);
    expect(restored.current.workingAttachment.derivativeSha256, edited.derivativeSha256);
    restored.current.undoEdit();
    expect(restored.current.workingAttachment.derivativeSha256, attachment.derivativeSha256);
    restored.current.redoEdit(); restored.current.redoEdit();
    expect(restored.current.workingAttachment.pdfSha256, pdf.pdfSha256);
    expect(restored.current.rawBytes, attachment.originalBytes);
    queue.dispose(); restored.dispose();
  });
}
