String forceTitleCase(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAllMapped(
    RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9]+'),
    (match) {
      final word = match.group(0)!;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    },
  );
}

final class ScannedDocumentFields {
  ScannedDocumentFields._({
    required this.rawVendorName,
    required this.vendorName,
    required this.documentDate,
  });

  factory ScannedDocumentFields.fromScan({
    required String rawVendorName,
    required DateTime? documentDate,
  }) {
    return ScannedDocumentFields._(
      rawVendorName: rawVendorName,
      vendorName: forceTitleCase(rawVendorName),
      documentDate: documentDate?.toUtc(),
    );
  }

  final String rawVendorName;
  final String vendorName;
  final DateTime? documentDate;
}
