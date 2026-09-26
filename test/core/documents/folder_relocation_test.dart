import 'dart:io';

import 'package:audyt/core/documents/folder_relocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves every nested file when a managed root changes', () {
    final source = Directory.systemTemp.createTempSync('audyt-source-');
    final destination = Directory.systemTemp.createTempSync(
      'audyt-destination-',
    );
    addTearDown(() => source.deleteSync(recursive: true));
    addTearDown(() => destination.deleteSync(recursive: true));

    final nested = Directory(
      '${source.path}/C7 - Invoice/2026/01. January 2026/receipts',
    )..createSync(recursive: true);
    File('${nested.path}/C7-IN-12.01.26').writeAsStringSync('invoice');
    File('${nested.path}/receipt.jpeg').writeAsStringSync('receipt');
    File('${nested.path}/PAID.stamp').writeAsStringSync('paid');

    final plan = LocalFolderRelocationPlan.build(
      sourceRoot: source,
      destinationRoot: destination,
    );

    expect(plan.items.map((item) => item.relativePath).toList(), [
      'C7 - Invoice/2026/01. January 2026/receipts/C7-IN-12.01.26',
      'C7 - Invoice/2026/01. January 2026/receipts/PAID.stamp',
      'C7 - Invoice/2026/01. January 2026/receipts/receipt.jpeg',
    ]);
    expect(
      plan.items.every(
        (item) => item.destinationPath.startsWith(destination.path),
      ),
      isTrue,
    );
  });
}
