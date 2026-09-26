import 'dart:io';
import 'package:audyt/core/documents/document_jpeg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_compression.dart';
import 'package:audyt/core/documents/document_optimization.dart';

void main() {
  test('configured native engine is loaded', () {
    if (Platform.environment.containsKey('AUDYT_JPEG_LIBRARY')) expect(DocumentJpeg.usesNativeEncoder, isTrue);
  });
  test('automatic compression preserves dimensions and reports its measured quality', () {
    final source = img.Image(width: 96, height: 64);
    for (final p in source) {
      final v = (p.x % 13 < 2 && p.y > 8 && p.y < 56) ? 30 : 245;
      p.setRgb(v, v, v);
    }
    final result = DocumentCompression.choose(source);
    final decoded = DocumentJpeg.decode(result.bytes)!;
    expect(decoded.width, source.width);
    expect(decoded.height, source.height);
    final measured = DocumentCompression.measure(
      source,
      decoded,
      result.bytes,
      result.quality,
    );
    expect(result.psnr, measured.psnr);
    expect(result.meetsQualityFloor, measured.meetsQualityFloor);
    final rendered = DocumentOptimizationEngine.renderSync(
      img.encodePng(source),
      const DocumentOptimizationRecipe(automaticCompression: true),
    );
    expect(rendered.compression, isNotNull);
    expect(rendered.jpeg, rendered.compression!.bytes);
  });
  test('comparison rejects resizing and detects lost dark marks', () {
    final source = img.Image(width: 32, height: 32);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    for (var y = 8; y < 24; y++) {
      source.setPixelRgb(16, y, 0, 0, 0);
    }
    final erased = img.Image(width: 32, height: 32);
    img.fill(erased, color: img.ColorRgb8(255, 255, 255));
    final result = DocumentCompression.measure(
      source,
      erased,
      img.encodeJpg(erased),
      90,
    );
    expect(result.meetsQualityFloor, isFalse);
    expect(result.inkChanges, greaterThan(0));
    expect(
      () => DocumentCompression.measure(
        source,
        img.Image(width: 16, height: 16),
        result.bytes,
        90,
      ),
      throwsArgumentError,
    );
  });
}
