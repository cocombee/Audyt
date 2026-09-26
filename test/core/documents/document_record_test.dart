import 'package:audyt/core/documents/document_record.dart';
import 'package:audyt/core/documents/scan_fields.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a receipt linked through scan and filing states', () {
    final documentId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8ca101');
    final transactionId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8ca102',
    );
    final staged = DocumentRecord.staged(
      id: documentId,
      transactionId: transactionId,
      originalFilename: 'receipt.jpeg',
      mimeType: 'image/jpeg',
      byteSize: 2048,
      sha256: List.filled(64, 'a').join(),
      createdAt: DateTime.utc(2026, 8, 30, 1),
    );

    final scanned = staged.withScan(
      ScannedDocumentFields.fromScan(
        rawVendorName: 'ACME OFFICE SUPPLIES LTD',
        documentDate: DateTime.utc(2026, 8, 29),
      ),
    );
    final filed = scanned
        .readyToFile(
          destinationType: DocumentDestinationType.localFolder,
          relativePath: 'F6xF - Invoice/2026/08. August 2026/receipt.jpeg',
        )
        .filed();

    expect(scanned.status, DocumentStatus.scanned);
    expect(scanned.rawVendorName, 'ACME OFFICE SUPPLIES LTD');
    expect(scanned.vendorName, 'Acme Office Supplies Ltd');
    expect(filed.status, DocumentStatus.filed);
    expect(filed.id, documentId);
    expect(filed.transactionId, transactionId);
    expect(filed.relativePath, contains('F6xF - Invoice'));
  });
}
