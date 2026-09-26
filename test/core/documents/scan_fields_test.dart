import 'package:audyt/core/documents/scan_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps raw scan text while forcing the vendor display to Title Case',
    () {
      final fields = ScannedDocumentFields.fromScan(
        rawVendorName: 'ACME OFFICE SUPPLIES LTD',
        documentDate: DateTime.utc(2026, 1, 12),
      );

      expect(fields.rawVendorName, 'ACME OFFICE SUPPLIES LTD');
      expect(fields.vendorName, 'Acme Office Supplies Ltd');
      expect(fields.documentDate, DateTime.utc(2026, 1, 12));
    },
  );
}
