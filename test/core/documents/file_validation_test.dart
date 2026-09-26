import 'package:audyt/core/documents/file_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts accounting document formats and rejects unsupported or oversize files', () {
    const validator = DocumentFileValidator(maxBytes: 10 * 1024 * 1024);

    for (final filename in [
      'receipt.heif',
      'receipt.png',
      'receipt.jpeg',
      'invoice.pdf',
      'invoice.doc',
      'invoice.docx',
    ]) {
      expect(validator.validate(filename: filename, byteSize: 1024), isEmpty);
    }

    expect(
      validator.validate(filename: 'script.exe', byteSize: 1024),
      contains('This document format is not supported.'),
    );
    expect(
      validator.validate(filename: 'invoice.pdf', byteSize: 11 * 1024 * 1024),
      contains('The document is larger than the allowed limit.'),
    );
  });
}
