import 'dart:isolate';
import 'dart:convert';

import 'receipt_document.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final class DocumentTraceSettings {
  const DocumentTraceSettings({this.threshold = 160, this.removeSpecks = 0});
  final int threshold, removeSpecks;
  Map<String, Object> toJson() => {
    'version': 1,
    'threshold': threshold,
    'removeSpecks': removeSpecks,
  };
  void validate() {
    if (threshold < 1 ||
        threshold > 254 ||
        removeSpecks < 0 ||
        removeSpecks > 20) {
      throw const FormatException('Invalid vector trace settings.');
    }
  }
}

final class DocumentTraceResult {
  const DocumentTraceResult({
    required this.pdf,
    required this.svg,
    required this.preview,
    required this.pathCount,
    required this.pointCount,
    required this.removedPixels,
  });
  final Uint8List pdf, svg, preview;

  ReceiptAttachment attachTo(ReceiptAttachment source, {required bool asPdf}) {
    final filename = source.filename.replaceFirst(RegExp(r'\.[^.]+$'), '') + (asPdf ? '.pdf' : '.svg');
    if (asPdf) return source.withPdf(pdf).withFilename(filename);
    return source.withDerivative(
      derivativeId: "${source.derivativeId}-derivative-edit-svg",
      bytes: svg,
      mimeType: "image/svg+xml",
      width: source.derivativeWidth ?? source.originalWidth ?? 1,
      height: source.derivativeHeight ?? source.originalHeight ?? 1,
      printReadyAt300Dpi: false,
    ).withFilename(filename);
  }

  final int pathCount, pointCount, removedPixels;
}

/// Monochrome boundary tracing. Preserves holes and exact source-pixel contours,
/// merging collinear edges. This is actual PDF vector geometry, not OCR text or
/// a raster image disguised as a PDF. Photographs should retain raster output.
final class DocumentVectorTrace {
  Future<DocumentTraceResult> trace(
    Uint8List bytes,
    DocumentTraceSettings settings,
  ) => Isolate.run(() => _trace(bytes, settings));

  static Future<DocumentTraceResult> _trace(
    Uint8List bytes,
    DocumentTraceSettings settings,
  ) async {
    settings.validate();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 12000000) {
      throw const FormatException(
        'Vector trace requires a decodable image up to 12 megapixels.',
      );
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('Image cannot be decoded.');
    }
    final image = img
        .bakeOrientation(decoded)
        .convert(format: img.Format.uint8, numChannels: 4);
    final w = image.width, h = image.height;
    final mask = Uint8List(w * h);
    for (final p in image) {
      final a = p.a / 255;
      final l = (.2126 * p.r + .7152 * p.g + .0722 * p.b) * a + 255 * (1 - a);
      if (l < settings.threshold) mask[p.y * w + p.x] = 1;
    }
    var removed = 0;
    if (settings.removeSpecks > 0) {
      final visited = Uint8List(mask.length);
      final queue = <int>[];
      for (var seed = 0; seed < mask.length; seed++) {
        if (mask[seed] == 0 || visited[seed] != 0) continue;
        queue.clear();
        queue.add(seed);
        visited[seed] = 1;
        for (var i = 0; i < queue.length; i++) {
          final p = queue[i], x = p % w, y = p ~/ w;
          for (final n in [
            if (x > 0) p - 1,
            if (x + 1 < w) p + 1,
            if (y > 0) p - w,
            if (y + 1 < h) p + w,
          ]) {
            if (mask[n] != 0 && visited[n] == 0) {
              visited[n] = 1;
              queue.add(n);
            }
          }
        }
        if (queue.length <= settings.removeSpecks) {
          removed += queue.length;
          for (final p in queue) {
            mask[p] = 0;
          }
        }
      }
    }
    final edges = <int, List<int>>{};
    var edgeCount = 0;
    final stride = w + 1;
    void edge(int from, int to) {
      if (++edgeCount > 500000) {
        throw const FormatException(
          'Trace is too detailed. Increase speck removal or keep image PDF.',
        );
      }
      (edges[from] ??= []).add(to);
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (mask[y * w + x] == 0) continue;
        final a = y * stride + x, b = a + 1, c = a + stride + 1, d = a + stride;
        if (y == 0 || mask[(y - 1) * w + x] == 0) edge(a, b);
        if (x == w - 1 || mask[y * w + x + 1] == 0) edge(b, c);
        if (y == h - 1 || mask[(y + 1) * w + x] == 0) edge(c, d);
        if (x == 0 || mask[y * w + x - 1] == 0) edge(d, a);
      }
    }
    int direction(int a, int b) => b == a + 1
        ? 0
        : b == a + stride
        ? 1
        : b == a - 1
        ? 2
        : 3;
    final paths = <List<int>>[];
    while (edges.isNotEmpty) {
      final start = edges.keys.first;
      var current = start, previousDirection = -1;
      final path = <int>[];
      do {
        path.add(current);
        final options = edges[current];
        if (options == null || options.isEmpty) {
          throw StateError('Trace contour is incomplete.');
        }
        var selected = 0;
        if (options.length > 1 && previousDirection >= 0) {
          // Follow the rightmost boundary at diagonally touching components.
          final ranks = {1: 0, 0: 1, 3: 2, 2: 3};
          for (var i = 1; i < options.length; i++) {
            if (ranks[(direction(current, options[i]) - previousDirection) %
                    4]! <
                ranks[(direction(current, options[selected]) -
                        previousDirection) %
                    4]!) {
              selected = i;
            }
          }
        }
        final next = options.removeAt(selected);
        if (options.isEmpty) edges.remove(current);
        previousDirection = direction(current, next);
        current = next;
      } while (current != start);
      final corners = <int>[];
      for (var i = 0; i < path.length; i++) {
        final a = path[(i + path.length - 1) % path.length],
            b = path[i],
            c = path[(i + 1) % path.length];
        if (direction(a, b) != direction(b, c)) corners.add(b);
      }
      paths.add(corners);
    }
    final preview = img.Image(width: w, height: h);
    for (final p in preview) {
      final c = mask[p.y * w + p.x] == 0 ? 255 : 0;
      p.setRgb(c, c, c);
    }
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.AspectRatio(
            aspectRatio: w / h,
            child: pw.CustomPaint(
              painter: (canvas, size) {
                canvas.setFillColor(PdfColors.black);
                for (final path in paths) {
                  for (var i = 0; i < path.length; i++) {
                    final x = (path[i] % stride) / w * size.x;
                    final y = size.y - (path[i] ~/ stride) / h * size.y;
                    if (i == 0) {
                      canvas.moveTo(x, y);
                    } else {
                      canvas.lineTo(x, y);
                    }
                  }
                  canvas.closePath();
                }
                canvas.fillPath(evenOdd: true);
              },
            ),
          ),
        ),
      ),
    );
    final geometry = StringBuffer();
    for (final path in paths) {
      for (var i = 0; i < path.length; i++) {
        geometry.write(
          '${i == 0 ? 'M' : 'L'}${path[i] % stride} ${path[i] ~/ stride} ',
        );
      }
      geometry.write('Z ');
    }
    final svg = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h"><rect width="$w" height="$h" fill="white"/><path fill="black" fill-rule="evenodd" d="$geometry"/></svg>',
      ),
    );
    return DocumentTraceResult(
      svg: svg,
      pdf: Uint8List.fromList(await document.save()),
      preview: img.encodePng(preview),
      pathCount: paths.length,
      pointCount: paths.fold(0, (sum, p) => sum + p.length),
      removedPixels: removed,
    );
  }
}
