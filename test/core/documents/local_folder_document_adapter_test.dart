import 'dart:io';

import 'package:audyt/core/documents/folder_relocation.dart';
import 'package:audyt/core/documents/local_folder_document_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves and verifies the complete managed subtree', () async {
    final source = Directory.systemTemp.createTempSync('audyt-source-');
    final destination = Directory.systemTemp.createTempSync(
      'audyt-destination-',
    );
    addTearDown(() {
      if (source.existsSync()) {
        source.deleteSync(recursive: true);
      }
    });
    addTearDown(() => destination.deleteSync(recursive: true));

    final nested = Directory(
      '${source.path}/F6xF - Invoice/2026/01. January 2026/receipts',
    )..createSync(recursive: true);
    final invoice = File('${nested.path}/F6xF-IN-12.01.26')
      ..writeAsStringSync('invoice');
    final receipt = File('${nested.path}/receipt.jpeg')
      ..writeAsStringSync('receipt');

    final result = await LocalFolderDocumentAdapter().move(
      LocalFolderRelocationPlan.build(
        sourceRoot: source,
        destinationRoot: destination,
      ),
    );

    expect(result.movedFiles, 2);
    expect(result.verifiedFiles, 2);
    expect(
      File(
        '${destination.path}/F6xF - Invoice/2026/01. January 2026/receipts/F6xF-IN-12.01.26',
      ).readAsStringSync(),
      'invoice',
    );
    expect(
      File(
        '${destination.path}/F6xF - Invoice/2026/01. January 2026/receipts/receipt.jpeg',
      ).readAsStringSync(),
      'receipt',
    );
    expect(invoice.existsSync(), isFalse);
    expect(receipt.existsSync(), isFalse);
  });

  test(
    'stops on a different destination collision without deleting source data',
    () async {
      final source = Directory.systemTemp.createTempSync('audyt-source-');
      final destination = Directory.systemTemp.createTempSync(
        'audyt-destination-',
      );
      addTearDown(() {
        if (source.existsSync()) {
          source.deleteSync(recursive: true);
        }
        if (destination.existsSync()) {
          destination.deleteSync(recursive: true);
        }
      });

      final sourceFile = File('${source.path}/F6xF - Invoice/2026/invoice.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('source');
      final destinationFile =
          File('${destination.path}/F6xF - Invoice/2026/invoice.pdf')
            ..createSync(recursive: true)
            ..writeAsStringSync('different');

      expect(
        () => LocalFolderDocumentAdapter().move(
          LocalFolderRelocationPlan.build(
            sourceRoot: source,
            destinationRoot: destination,
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(sourceFile.readAsStringSync(), 'source');
      expect(destinationFile.readAsStringSync(), 'different');
    },
  );
}
