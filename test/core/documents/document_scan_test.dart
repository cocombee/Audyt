import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/document_scan.dart';
import 'package:audyt/core/documents/document_optimization.dart';

void main() {
  test('detect receipt, rectify, clean and optimize', () async {
    final source = File(Platform.environment['AUDYT_RECEIPT_SAMPLE']!)
        .readAsBytesSync();
    final corners = await DocumentScan.detect(source);
    debugPrint('CORNERS $corners');
    expect(corners, isNotNull);
    final png = await DocumentScan.rectify(source, corners!, clean: true);
    final result = await const DocumentOptimizationEngine().render(
      png,
      const DocumentOptimizationRecipe(automaticCompression: true),
    );
    File('/tmp/audyt-clean-scan.jpg').writeAsBytesSync(result.jpeg);
    debugPrint(
      'SCAN ${result.width}x${result.height} ${result.jpeg.length} bytes',
    );
    expect(result.jpeg.length, lessThan(source.length));
  }, skip: !Platform.environment.containsKey('AUDYT_RECEIPT_SAMPLE'));
}
