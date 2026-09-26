import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/document_optimization.dart';
import 'package:audyt/core/documents/document_jpeg.dart';

void main() {
  test('receipt Quick Optimize uses native comparison and stays below 1 MB', () async {
    final source = File(Platform.environment['AUDYT_RECEIPT_SAMPLE']!)
        .readAsBytesSync();
    final timer = Stopwatch()..start();
    final result = await const DocumentOptimizationEngine().render(
      source,
      const DocumentOptimizationRecipe(automaticCompression: true),
    );
    if (Platform.environment['AUDYT_TEST_OUTPUT'] case final path?) {
      File(path).writeAsBytesSync(result.jpeg);
    }
    debugPrint('SOURCE ${source.length} DIM ${result.width}x${result.height}');
    debugPrint(
      'NATIVE ${DocumentJpeg.usesNativeEncoder} BYTES ${result.jpeg.length} Q ${result.compression?.quality} PSNR ${result.compression?.psnr} EDGE ${result.compression?.edgeError} INK ${result.compression?.inkChanges} MS ${timer.elapsedMilliseconds}',
    );
    expect(DocumentJpeg.usesNativeEncoder, isTrue);
    expect(result.jpeg.length, lessThan(1000000));
  }, skip: !Platform.environment.containsKey('AUDYT_RECEIPT_SAMPLE'));
}
