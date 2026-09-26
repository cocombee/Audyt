import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/document_scan.dart';
import 'package:audyt/core/documents/document_optimization.dart';

void main() {
  test('user scan samples', () async {
    final paths = (jsonDecode(Platform.environment['SCAN_SAMPLES']!) as List)
        .cast<String>();
    for (var i = 0; i < paths.length; i++) {
      final bytes = File(paths[i]).readAsBytesSync();
      var corners = await DocumentScan.detect(bytes);
      debugPrint('SAMPLE ${i + 1} CORNERS $corners');
      if (corners == null) {
        debugPrint('SAMPLE ${i + 1} MANUAL FALLBACK');
        corners = [
          [(.195, .015), (.89, .033), (.915, .975), (.11, .93)],
          [(.145, .173), (.928, .147), (.91, .85), (.189, .895)],
          [(.13, .12), (.932, .105), (.995, .932), (.05, .95)],
          [(.20, .217), (.842, .243), (.98, .765), (.082, .765)],
        ][i];
      }
      final png = await DocumentScan.rectify(bytes, corners, clean: true);
      final output = await const DocumentOptimizationEngine().render(
        png,
        const DocumentOptimizationRecipe(automaticCompression: true),
      );
      File('/tmp/scan-sample-${i + 1}.jpg').writeAsBytesSync(output.jpeg);
      debugPrint(
        'SAMPLE ${i + 1} OUTPUT ${output.width}x${output.height} ${output.jpeg.length}',
      );
    }
  }, skip: !Platform.environment.containsKey('SCAN_SAMPLES'));
}
