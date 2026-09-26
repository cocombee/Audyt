import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'document_jpeg.dart';

final class DocumentCompressionResult {
  const DocumentCompressionResult({
    required this.bytes,
    required this.quality,
    required this.psnr,
    required this.edgeError,
    required this.inkChanges,
    required this.meetsQualityFloor,
  });
  final Uint8List bytes;
  final int quality;
  final double psnr, edgeError, inkChanges;
  final bool meetsQualityFloor;
}

/// Local full-resolution JPEG search. These conservative pixel checks are a
/// guard, not OCR or proof that every document remains readable. Never resize
/// or discard source evidence in order to hit a target percentage.
final class DocumentCompression {
  static DocumentCompressionResult choose(img.Image source) {
    DocumentCompressionResult? highest;
    for (final quality in [55, 60, 65, 70, 75, 80, 85, 90, 95, 100]) {
      final encoded = DocumentJpeg.encode(source, quality: quality);
      final decoded = DocumentJpeg.decode(encoded)!;
      final result = measure(source, decoded, encoded, quality);
      if (quality == 100) highest = result;
      if (result.meetsQualityFloor) return result;

    }
    return highest!;
  }

  static DocumentCompressionResult measure(
    img.Image source,
    img.Image decoded,
    Uint8List encoded,
    int quality,
  ) {
    if (source.width != decoded.width || source.height != decoded.height) {
      throw ArgumentError(
        'Compression comparison requires matching dimensions.',
      );
    }
    double squaredError = 0, edgeError = 0;
    var edgeCount = 0, inkChanges = 0;
    double luminance(img.Pixel p) => .2126 * p.r + .7152 * p.g + .0722 * p.b;
    for (final p in source) {
      final q = decoded.getPixel(p.x, p.y);
      squaredError +=
          math.pow(p.r - q.r, 2) +
          math.pow(p.g - q.g, 2) +
          math.pow(p.b - q.b, 2);
      final l = luminance(p);
      final horizontal = p.x + 1 < source.width
          ? (l - luminance(source.getPixel(p.x + 1, p.y))).abs()
          : 0;
      final vertical = p.y + 1 < source.height
          ? (l - luminance(source.getPixel(p.x, p.y + 1))).abs()
          : 0;
      if (horizontal >= 12 || vertical >= 12) {
        edgeCount++;
        final decodedL = luminance(q);
        edgeError += (l - decodedL).abs();
        // Ignore near-threshold source pixels, whose classification is ambiguous.
        if ((l < 112 && decodedL >= 128) || (l > 144 && decodedL < 128)) {
          inkChanges++;
        }
      }
    }
    final mse = squaredError / (source.width * source.height * 3);
    final psnr = mse == 0
        ? double.infinity
        : 10 * math.log(255 * 255 / mse) / math.ln10;
    final meanEdge = edgeCount == 0 ? 0.0 : edgeError / edgeCount;
    final changed = edgeCount == 0 ? 0.0 : inkChanges / edgeCount;
    return DocumentCompressionResult(
      bytes: encoded,
      quality: quality,
      psnr: psnr,
      edgeError: meanEdge,
      inkChanges: changed,
      meetsQualityFloor: psnr >= 36 && meanEdge <= 6 && changed <= 0.001,
    );
  }
}
