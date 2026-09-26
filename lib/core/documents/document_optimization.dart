import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'receipt_document.dart';
import 'document_compression.dart';
import 'document_jpeg.dart';

/// Portable edit recipe. Crop coordinates are fractions of the oriented source,
/// before user rotation. Edits use the current image while original evidence stays immutable.
final class DocumentOptimizationRecipe {
  const DocumentOptimizationRecipe({
    this.black = 0,
    this.white = 255,
    this.gamma = 1,
    this.contrast = 1,
    this.sharpen = 0,
    this.rotation = 0,
    this.quality = 65,
    this.automaticCompression = false,
    this.left = 0,
    this.top = 0,
    this.right = 1,
    this.bottom = 1,
  });
  final bool automaticCompression;
  final int black, white, quality;
  final double contrast;
  final double gamma, sharpen, rotation, left, top, right, bottom;

  void validate() {
    if (black < 0 ||
        white > 255 ||
        black >= white ||
        !contrast.isFinite ||
        contrast < 0.2 ||
        contrast > 3 ||
        !gamma.isFinite ||
        gamma < 0.2 ||
        gamma > 5 ||
        !sharpen.isFinite ||
        sharpen < 0 ||
        sharpen > 1 ||
        !rotation.isFinite ||
        rotation < -360 ||
        rotation > 360 ||
        quality < 30 ||
        quality > 100 ||
        [left, top, right, bottom].any((v) => !v.isFinite || v < 0 || v > 1) ||
        left >= right ||
        top >= bottom) {
      throw const FormatException('Invalid document optimization settings.');
    }
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'black': black,
    'white': white,
    'gamma': gamma,
    'contrast': contrast,
    'sharpen': sharpen,
    'rotation': rotation,
    'quality': quality,
    'automaticCompression': automaticCompression,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory DocumentOptimizationRecipe.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown edit recipe.');
    }
    final recipe = DocumentOptimizationRecipe(
      black: json['black'] as int,
      white: json['white'] as int,
      gamma: (json['gamma'] as num).toDouble(),
      contrast: (json['contrast'] as num? ?? 1).toDouble(),
      sharpen: (json['sharpen'] as num? ?? 0).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      quality: json['quality'] as int,
      automaticCompression: json['automaticCompression'] as bool? ?? false,
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
    recipe.validate();
    return recipe;
  }

  DocumentOptimizationRecipe copyWith({
    int? black,
    int? white,
    double? gamma,
    double? contrast,
    double? sharpen,
    double? rotation,
    int? quality,
    bool? automaticCompression,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => DocumentOptimizationRecipe(
    black: black ?? this.black,
    white: white ?? this.white,
    gamma: gamma ?? this.gamma,
    contrast: contrast ?? this.contrast,
    sharpen: sharpen ?? this.sharpen,
    rotation: rotation ?? this.rotation,
    quality: quality ?? this.quality,
    automaticCompression: automaticCompression ?? this.automaticCompression,
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
  );
}

final class DocumentOptimizationResult {
  const DocumentOptimizationResult(
    this.jpeg,
    this.width,
    this.height,
    this.histogram, {
    this.compression,
  });
  final DocumentCompressionResult? compression;
  final Uint8List jpeg;
  final int width, height;
  final List<int> histogram;
}

/// No platform file APIs or cloud dependencies. Processing runs off the UI isolate.
final class DocumentOptimizationEngine {
  const DocumentOptimizationEngine();

  Future<Uint8List> preparePreview(Uint8List source) => Isolate.run(() {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      throw const FormatException('This image cannot be decoded.');
    }
    final oriented = img.bakeOrientation(decoded);
    final longest = math.max(oriented.width, oriented.height);
    final preview = longest <= 900
        ? oriented
        : img.copyResize(
            oriented,
            width: (oriented.width * 900 / longest).round(),
            height: (oriented.height * 900 / longest).round(),
          );
    return Uint8List.fromList(img.encodePng(preview, level: 1));
  });

  Future<DocumentOptimizationResult> render(
    Uint8List source,
    DocumentOptimizationRecipe recipe,
  ) {
    recipe.validate();
    return Isolate.run(() => renderSync(source, recipe));
  }

  static DocumentOptimizationResult renderSync(
    Uint8List source,
    DocumentOptimizationRecipe recipe,
  ) {
    recipe.validate();
    final decoder = img.findDecoderForData(source);
    final info = decoder?.startDecode(source);
    if (info == null) {
      throw const FormatException('This image cannot be decoded.');
    }
    if (info.width * info.height > 40000000) {
      throw const FormatException(
        'Image exceeds the 40 megapixel editing limit.',
      );
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('This image cannot be decoded.');
    }
    final oriented = img
        .bakeOrientation(decoded)
        .convert(format: img.Format.uint8, numChannels: 4);
    var image = img.Image(
      width: oriented.width,
      height: oriented.height,
      numChannels: 3,
    );
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(image, oriented);
    final x = (recipe.left * image.width).floor();
    final y = (recipe.top * image.height).floor();
    final right = (recipe.right * image.width).ceil().clamp(x + 1, image.width);
    final bottom = (recipe.bottom * image.height).ceil().clamp(
      y + 1,
      image.height,
    );
    image = img.copyCrop(
      image,
      x: x,
      y: y,
      width: right - x,
      height: bottom - y,
    );
    final histogram = List<int>.filled(256, 0);
    final lut = List<int>.generate(
      256,
      (v) =>
          (255 *
                  math.pow(
                    (((v - recipe.black) / (recipe.white - recipe.black) -
                                    0.5) *
                                recipe.contrast +
                            0.5)
                        .clamp(0, 1),
                    1 / recipe.gamma,
                  ))
              .round()
              .clamp(0, 255),
    );
    for (final p in image) {
      p.setRgb(lut[p.r.toInt()], lut[p.g.toInt()], lut[p.b.toInt()]);
    }
    if (recipe.sharpen > 0) {
      image = img.convolution(
        image,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: recipe.sharpen,
      );
    }
    if (recipe.rotation != 0) {
      image.backgroundColor = img.ColorRgb8(255, 255, 255);
      image = img.copyRotate(
        image,
        angle: recipe.rotation,
        interpolation: img.Interpolation.cubic,
      );
    }
    final bounds = a4OutputSize(image.width, image.height);
    if (bounds.width != image.width || bounds.height != image.height) {
      image = img.copyResize(image, width: bounds.width, height: bounds.height, interpolation: img.Interpolation.cubic);
    }
    for (final pixel in image) {
      histogram[(0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round().clamp(0, 255)]++;
    }
    final compression = recipe.automaticCompression
        ? DocumentCompression.choose(image)
        : null;
    return DocumentOptimizationResult(
      compression?.bytes ??
          DocumentJpeg.encode(image, quality: recipe.quality),
      image.width,
      image.height,
      histogram,
      compression: compression,
    );
  }

  Future<ReceiptAttachment> optimize(
    ReceiptAttachment attachment,
    DocumentOptimizationRecipe recipe,
  ) async {
    if (!attachment.isImage) {
      throw const FormatException('Select an image to optimize.');
    }
    final output = await render(attachment.preferredBytes, recipe);
    final id = sha256.convert(output.jpeg).toString().substring(0, 16);
    return attachment
        .withDerivative(
          derivativeId: '${attachment.originalId}-derivative-edit-$id',
          bytes: output.jpeg,
          mimeType: 'image/jpeg',
          width: output.width,
          height: output.height,
          printReadyAt300Dpi:
              math.min(output.width, output.height) >= 2480 &&
              math.max(output.width, output.height) >= 3508,
          processingMessage:
              'Edited JPEG · ${output.width} × ${output.height} · original retained',
        )
        .withOptimizationRecipe(recipe.toJson());
  }
}

/// User-selected A4 output envelope, orientation-aware and never upscaling.
({int width, int height}) a4OutputSize(int width, int height) {
  if (width <= 0 || height <= 0) throw ArgumentError('Positive image dimensions required.');
  final landscape = width > height;
  final scale = math.min(1.0, math.min((landscape ? 2480 : 1754) / width, (landscape ? 1754 : 2480) / height));
  return (width: math.max(1, (width * scale).round()), height: math.max(1, (height * scale).round()));
}
