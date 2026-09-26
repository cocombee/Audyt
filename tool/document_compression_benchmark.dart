import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/document_compression.dart';

void main(List<String> args) {
  final output = Directory(args.single)..createSync(recursive: true);
  final reports = <Map<String, Object>>[];
  for (final kind in ['clean-png', 'faded-jpeg', 'color-jpeg', 'photo-jpeg', 'already-compressed']) {
    final image = img.Image(width: 900, height: 1200);
    img.fill(image, color: img.ColorRgb8(248, 247, 242));
    if (kind == 'photo-jpeg' || kind == 'already-compressed') {
      final random = math.Random(17);
      for (final p in image) {
        final noise = random.nextInt(13) - 6;
        final shade = 235 - p.x / 100 + 8 * math.sin(p.y / 230);
        p.setRgb((shade + noise).round(), (shade + noise - 2).round(), (shade + noise - 7).round());
      }
    }
    final ink = kind == 'faded-jpeg' ? img.ColorRgb8(145, 143, 140) : img.ColorRgb8(30, 30, 30);
    img.drawString(image, 'SYNTHETIC RECEIPT - TEST ONLY', font: img.arial24, x: 45, y: 40, color: ink);
    final lines = ['Invoice INV-2026-001', 'Date 14-09-2026', 'Office Supplies 123.45',
      'Quantity 2 x 12.50', 'Tax 7.40', 'TOTAL MYR 155.85', 'Reference A8B0-105.09'];
    for (var i = 0; i < lines.length; i++) {
      img.drawString(image, lines[i], font: img.arial24, x: 45, y: 105 + i * 48, color: ink);
      img.drawString(image, 'Fine print 0123456789 0.01 8.88 1,234.56', font: img.arial14, x: 45, y: 510 + i * 35, color: ink);
    }
    if (kind == 'color-jpeg') {
      img.drawCircle(image, x: 650, y: 740, radius: 85, color: img.ColorRgb8(35, 80, 180));
      img.drawString(image, 'PAID', font: img.arial24, x: 615, y: 725, color: img.ColorRgb8(180, 25, 40));
    }
    final bytes = kind == 'clean-png' ? img.encodePng(image) : img.encodeJpg(image,
      quality: kind == 'already-compressed' ? 65 : 95, chroma: img.JpegChroma.yuv444);
    final source = img.decodeImage(bytes)!;
    final candidates = <Map<String, Object>>[];
    for (final q in [90, 85, 80, 75, 70]) {
      final jpeg = img.encodeJpg(source, quality: q, chroma: img.JpegChroma.yuv444);
      final metrics = DocumentCompression.measure(source, img.decodeJpg(jpeg)!, jpeg, q);
      File('${output.path}/$kind-q$q.jpg').writeAsBytesSync(jpeg);
      candidates.add({'quality': q, 'bytes': jpeg.length, 'savingPercent': (1 - jpeg.length / bytes.length) * 100,
        'psnr': metrics.psnr, 'edgeError': metrics.edgeError, 'inkChanges': metrics.inkChanges});
    }
    File('${output.path}/$kind-candidates.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(candidates));

    final watch = Stopwatch()..start();
    final result = DocumentCompression.choose(source);
    watch.stop();
    File('${output.path}/$kind-original.${kind == 'clean-png' ? 'png' : 'jpg'}').writeAsBytesSync(bytes);
    File('${output.path}/$kind-optimized.jpg').writeAsBytesSync(result.bytes);
    reports.add({'fixture': kind, 'sourceBytes': bytes.length, 'outputBytes': result.bytes.length,
      'savingPercent': (1 - result.bytes.length / bytes.length) * 100,
      'quality': result.quality, 'psnr': result.psnr.isFinite ? result.psnr : 999,
      'edgeMeanError': result.edgeError, 'inkChangeFraction': result.inkChanges,
      'meetsPixelChecks': result.meetsQualityFloor, 'elapsedMs': watch.elapsedMilliseconds});
    stdout.writeln(jsonEncode(reports.last));
  }
  File('${output.path}/Results.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(reports));
}
