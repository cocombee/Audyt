import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_optimization.dart';
void main() {
  test('A4 envelope fits both orientations without upscaling or stretching', () {
    expect(a4OutputSize(2448, 3264), (width: 1754, height: 2339));
    expect(a4OutputSize(4960, 7016), (width: 1753, height: 2480));
    expect(a4OutputSize(7016, 4960), (width: 2480, height: 1753));
    expect(a4OutputSize(1000, 10000), (width: 248, height: 2480));
    expect(a4OutputSize(10000, 1000), (width: 2480, height: 248));
    expect(a4OutputSize(100, 200), (width: 100, height: 200));
  });
  test('actual optimized JPEG respects A4 height bound', () {
    final source = Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 4000)));
    final result = DocumentOptimizationEngine.renderSync(source, const DocumentOptimizationRecipe());
    final decoded = img.decodeJpg(result.jpeg)!;
    expect(decoded.width, 62);
    expect(decoded.height, 2480);
    expect(result.width, decoded.width);
    expect(result.height, decoded.height);
  });
}
