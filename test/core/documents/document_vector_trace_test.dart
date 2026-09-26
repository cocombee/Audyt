import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_vector_trace.dart';

void main() {
  test('vector trace preserves holes and isolated marks unless removal is selected', () async {
    final image = img.Image(width: 40, height: 40);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(image, x1: 8, y1: 8, x2: 31, y2: 31, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(image, x1: 14, y1: 14, x2: 25, y2: 25, color: img.ColorRgb8(255, 255, 255));
    image.setPixelRgb(3, 3, 0, 0, 0);
    final bytes = img.encodePng(image);
    final exact = await DocumentVectorTrace().trace(bytes, const DocumentTraceSettings());
    expect(exact.pathCount, 3);
    expect(exact.pointCount, 12);
    expect(exact.removedPixels, 0);
    final preview = img.decodePng(exact.preview)!;
    expect(preview.getPixel(20, 20).r, 255);
    expect(preview.getPixel(10, 10).r, 0);
    expect(preview.getPixel(3, 3).r, 0);
    final pdf = latin1.decode(exact.pdf);
    expect(pdf.startsWith('%PDF'), isTrue);
    expect(pdf.contains('/Subtype /Image'), isFalse);
    final cleaned = await DocumentVectorTrace().trace(bytes, const DocumentTraceSettings(removeSpecks: 1));
    expect(cleaned.pathCount, 2); expect(cleaned.removedPixels, 1);
    expect(img.decodePng(cleaned.preview)!.getPixel(3, 3).r, 255);
    final output = Platform.environment['AUDYT_TRACE_CAPTURE_DIR'];
    if (output != null) {
      File('$output/Hole And Dot.pdf').writeAsBytesSync(exact.pdf);
      File('$output/Hole And Dot.png').writeAsBytesSync(exact.preview);
    }
  });
  test('diagonal touching shapes remain closed and invalid settings fail', () async {
    final image = img.Image(width: 4, height: 4);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    image.setPixelRgb(1, 1, 0, 0, 0); image.setPixelRgb(2, 2, 0, 0, 0);
    final result = await DocumentVectorTrace().trace(img.encodePng(image), const DocumentTraceSettings());
    expect(result.pathCount, 2); expect(result.pointCount, 8);
    expect(() => const DocumentTraceSettings(threshold: 300).validate(), throwsFormatException);
  });
}
