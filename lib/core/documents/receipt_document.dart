import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'crop_edit.dart';
import 'generated_document.dart';

enum AttachmentProcessingStatus { queued, uploading, processing, ready, failed }

final class ReceiptAttachmentInput {
  const ReceiptAttachmentInput({
    required this.originalId,
    required this.batchId,
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  final String originalId;
  final String batchId;
  final String filename;
  final String mimeType;
  final Uint8List bytes;
}

final class ReceiptAttachment {
  ReceiptAttachment._({
    required this.originalId,
    required this.derivativeId,
    required this.batchId,
    required this.filename,
    required this.originalMimeType,
    required this.derivativeMimeType,
    required this.originalBytes,
    required this.originalSha256,
    required this.derivativeBytes,
    required this.derivativeSha256,
    required this.originalWidth,
    required this.originalHeight,
    required this.derivativeWidth,
    required this.derivativeHeight,
    required this.printReadyAt300Dpi,
    required this.processingMessage,
    required this.failureMessage,
    required this.pdfBytes,
    required this.pdfSha256,
    required this.status,
    required this.reviewSkipped,
    this.optimizationRecipe,
    this.generated,
  });

  factory ReceiptAttachment.queued(ReceiptAttachmentInput input) {
    final originalBytes = Uint8List.fromList(input.bytes);
    return ReceiptAttachment._(
      originalId: input.originalId,
      derivativeId: '${input.originalId}-derivative',
      batchId: input.batchId,
      filename: input.filename,
      originalMimeType: input.mimeType,
      derivativeMimeType: input.mimeType,
      originalBytes: originalBytes,
      originalSha256: _sha256(originalBytes),
      derivativeBytes: null,
      derivativeSha256: null,
      originalWidth: null,
      originalHeight: null,
      derivativeWidth: null,
      derivativeHeight: null,
      printReadyAt300Dpi: false,
      processingMessage: null,
      failureMessage: null,
      pdfBytes: null,
      pdfSha256: null,
      status: AttachmentProcessingStatus.queued,
      reviewSkipped: false,
    );
  }

  factory ReceiptAttachment.generatedPdf({
    required GeneratedDocumentProvenance provenance,
    required String filename,
    required Uint8List bytes,
  }) {
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('Generated output must be a PDF.');
    }
    return ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: provenance.attachmentId,
        batchId: provenance.attachmentId,
        filename: filename,
        mimeType: 'application/pdf',
        bytes: bytes,
      ),
    )._copy(status: AttachmentProcessingStatus.ready, generated: provenance);
  }

  factory ReceiptAttachment.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported receipt snapshot version.');
    }
    Uint8List? bytes(String field, String hashField, {bool required = false}) {
      final value = json[field];
      final hash = json[hashField];
      if (json['_evidenceUnavailable'] == true &&
          value == null &&
          hash is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        return required ? Uint8List(0) : null;
      }
      if (value == null && hash == null && !required) {
        return null;
      }
      if (value is! String || hash is! String) {
        throw FormatException('Missing receipt bytes or checksum: $field');
      }
      final decoded = base64Decode(value);
      if (_sha256(decoded) != hash) {
        throw FormatException('Receipt checksum mismatch: $field');
      }
      return decoded.asUnmodifiableView();
    }

    String text(String field) {
      final value = json[field];
      if (value is! String || value.isEmpty) {
        throw FormatException('Missing receipt field: $field');
      }
      return value;
    }

    int? dimension(String field) {
      final value = json[field];
      if (value == null) {
        return null;
      }
      if (value is! int || value < 1) {
        throw FormatException('Invalid image dimension: $field');
      }
      return value;
    }

    final original = bytes('originalBytes', 'originalSha256', required: true)!;
    final derivative = bytes('derivativeBytes', 'derivativeSha256');
    final pdf = bytes('pdfBytes', 'pdfSha256');
    return ReceiptAttachment._(
      originalId: text('originalId'),
      derivativeId: text('derivativeId'),
      batchId: text('batchId'),
      filename: text('filename'),
      originalMimeType: text('originalMimeType'),
      derivativeMimeType: text('derivativeMimeType'),
      originalBytes: original,
      originalSha256: text('originalSha256'),
      derivativeBytes: derivative,
      derivativeSha256: json['derivativeSha256'] as String?,
      originalWidth: dimension('originalWidth'),
      originalHeight: dimension('originalHeight'),
      derivativeWidth: dimension('derivativeWidth'),
      derivativeHeight: dimension('derivativeHeight'),
      printReadyAt300Dpi: json['printReadyAt300Dpi'] as bool,
      processingMessage: json['processingMessage'] as String?,
      failureMessage: json['_evidenceUnavailable'] == true
          ? 'This data-only restore retains the document reference and checksum. Reconnect the original file to view it.'
          : json['failureMessage'] as String?,
      pdfBytes: pdf,
      pdfSha256: json['pdfSha256'] as String?,
      status: json['_evidenceUnavailable'] == true
          ? AttachmentProcessingStatus.failed
          : AttachmentProcessingStatus.values.byName(text('status')),
      reviewSkipped: json['reviewSkipped'] as bool,
      optimizationRecipe: (json['optimizationRecipe'] as Map?)
          ?.cast<String, Object>(),
      generated: json['generated'] == null
          ? null
          : GeneratedDocumentProvenance.fromJson(
              (json['generated'] as Map).cast<String, dynamic>(),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'originalId': originalId,
    if (generated != null) 'generated': generated!.toJson(),
    'derivativeId': derivativeId,
    'batchId': batchId,
    'filename': filename,
    'originalMimeType': originalMimeType,
    'derivativeMimeType': derivativeMimeType,
    'originalBytes': originalBytes.isEmpty ? null : base64Encode(originalBytes),
    if (originalBytes.isEmpty) '_evidenceUnavailable': true,
    'originalSha256': originalSha256,
    'derivativeBytes': derivativeBytes == null
        ? null
        : base64Encode(derivativeBytes!),
    'derivativeSha256': derivativeSha256,
    'originalWidth': originalWidth,
    'originalHeight': originalHeight,
    'derivativeWidth': derivativeWidth,
    'derivativeHeight': derivativeHeight,
    'printReadyAt300Dpi': printReadyAt300Dpi,
    'processingMessage': processingMessage,
    'failureMessage': failureMessage,
    'pdfBytes': pdfBytes == null ? null : base64Encode(pdfBytes!),
    'pdfSha256': pdfSha256,
    'status': status.name,
    'reviewSkipped': reviewSkipped,
    'optimizationRecipe': optimizationRecipe,
  };

  final Map<String, Object>? optimizationRecipe;
  final String originalId;
  final String derivativeId;
  final String batchId;
  final String filename;
  final String originalMimeType;
  final String derivativeMimeType;
  final Uint8List originalBytes;
  final String originalSha256;
  final Uint8List? derivativeBytes;
  final String? derivativeSha256;
  final int? originalWidth;
  final int? originalHeight;
  final int? derivativeWidth;
  final int? derivativeHeight;
  final bool printReadyAt300Dpi;
  final String? processingMessage;
  final String? failureMessage;
  final Uint8List? pdfBytes;
  final String? pdfSha256;
  final AttachmentProcessingStatus status;
  final bool reviewSkipped;

  int get originalByteSize => originalBytes.length;
  final GeneratedDocumentProvenance? generated;
  bool get isGenerated => generated != null;
  int? get derivativeByteSize => derivativeBytes?.length;
  bool get isImage => originalMimeType.toLowerCase().startsWith('image/');
  bool get isPdf => originalMimeType.toLowerCase() == 'application/pdf';
  bool get canConvertToPdf =>
      isImage &&
      (derivativeBytes != null ||
          (originalWidth != null && originalHeight != null)) &&
      status == AttachmentProcessingStatus.ready;
  Uint8List get preferredBytes {
    final derivative = derivativeBytes;
    if (derivative != null &&
        (derivativeId.contains('-derivative-crop-') ||
            derivativeId.contains('-derivative-edit-'))) {
      return derivative;
    }
    return originalBytes;
  }

  String get preferredMimeType {
    final derivative = derivativeBytes;
    if (derivative != null &&
        (derivativeId.contains('-derivative-crop-') ||
            derivativeId.contains('-derivative-edit-'))) {
      return derivativeMimeType;
    }
    return originalMimeType;
  }

  /// The exact output filed by receipt review, also retained in data-only
  /// archives. An attachment ID alone cannot identify an older edited output.
  String get filedSha256 {
    if (pdfSha256 case final digest?) return digest;
    if (derivativeSha256 != null &&
        (derivativeId.contains('-derivative-crop-') ||
            derivativeId.contains('-derivative-edit-'))) {
      return derivativeSha256!;
    }
    return originalSha256;
  }

  double get reductionPercent {
    if (originalBytes.isEmpty) {
      return 0;
    }
    final reduction = originalBytes.length - preferredBytes.length;
    return reduction <= 0 ? 0 : reduction * 100 / originalBytes.length;
  }

  ReceiptAttachment withFilename(String name) => _copy(filename: name);

  ReceiptAttachment withStatus(AttachmentProcessingStatus nextStatus) {
    return _copy(status: nextStatus);
  }

  ReceiptAttachment withReviewSkipped([bool value = true]) {
    return _copy(reviewSkipped: value);
  }

  ReceiptAttachment withFailure(String message) {
    return _copy(
      status: AttachmentProcessingStatus.failed,
      failureMessage: message.trim(),
    );
  }

  ReceiptAttachment withDerivative({
    required String derivativeId,
    required Uint8List bytes,
    required String mimeType,
    required int width,
    required int height,
    required bool printReadyAt300Dpi,
    String? processingMessage,
  }) {
    return _copy(
      derivativeId: derivativeId,
      derivativeMimeType: mimeType,
      derivativeBytes: Uint8List.fromList(bytes),
      derivativeSha256: _sha256(bytes),
      derivativeWidth: width,
      derivativeHeight: height,
      printReadyAt300Dpi: printReadyAt300Dpi,
      processingMessage: processingMessage,
      status: AttachmentProcessingStatus.ready,
      failureMessage: null,
    );
  }

  ReceiptAttachment withOptimizationRecipe(Map<String, Object> recipe) =>
      _copy(optimizationRecipe: Map.unmodifiable(recipe));

  ReceiptAttachment withPdf(Uint8List bytes) {
    return _copy(
      pdfBytes: Uint8List.fromList(bytes),
      pdfSha256: _sha256(bytes),
    );
  }

  ReceiptAttachment _copy({
    String? originalId,
    String? derivativeId,
    String? batchId,
    String? filename,
    String? originalMimeType,
    String? derivativeMimeType,
    Uint8List? originalBytes,
    String? originalSha256,
    Uint8List? derivativeBytes,
    String? derivativeSha256,
    int? originalWidth,
    int? originalHeight,
    int? derivativeWidth,
    int? derivativeHeight,
    bool? printReadyAt300Dpi,
    String? processingMessage,
    String? failureMessage,
    Uint8List? pdfBytes,
    String? pdfSha256,
    AttachmentProcessingStatus? status,
    bool? reviewSkipped,
    Map<String, Object>? optimizationRecipe,
    GeneratedDocumentProvenance? generated,
  }) {
    return ReceiptAttachment._(
      originalId: originalId ?? this.originalId,
      derivativeId: derivativeId ?? this.derivativeId,
      batchId: batchId ?? this.batchId,
      filename: filename ?? this.filename,
      originalMimeType: originalMimeType ?? this.originalMimeType,
      derivativeMimeType: derivativeMimeType ?? this.derivativeMimeType,
      originalBytes: originalBytes ?? this.originalBytes,
      originalSha256: originalSha256 ?? this.originalSha256,
      derivativeBytes: derivativeBytes ?? this.derivativeBytes,
      derivativeSha256: derivativeSha256 ?? this.derivativeSha256,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      derivativeWidth: derivativeWidth ?? this.derivativeWidth,
      derivativeHeight: derivativeHeight ?? this.derivativeHeight,
      printReadyAt300Dpi: printReadyAt300Dpi ?? this.printReadyAt300Dpi,
      processingMessage: processingMessage ?? this.processingMessage,
      failureMessage: failureMessage,
      pdfBytes: derivativeBytes != null ? null : pdfBytes ?? this.pdfBytes,
      pdfSha256: derivativeBytes != null ? null : pdfSha256 ?? this.pdfSha256,
      status: status ?? this.status,
      reviewSkipped: reviewSkipped ?? this.reviewSkipped,
      optimizationRecipe: optimizationRecipe ?? this.optimizationRecipe,
      generated: generated ?? this.generated,
    );
  }
}

final class ReceiptAttachmentBatch {
  const ReceiptAttachmentBatch({required this.id, required this.attachments});

  final String id;
  final List<ReceiptAttachment> attachments;
}

abstract interface class ReceiptArtifactStore {
  Future<void> put(ReceiptAttachment attachment);
  ReceiptAttachment? get(String originalId);
}

final class InMemoryReceiptArtifactStore implements ReceiptArtifactStore {
  final Map<String, ReceiptAttachment> _attachments =
      <String, ReceiptAttachment>{};

  @override
  Future<void> put(ReceiptAttachment attachment) async {
    _attachments[attachment.originalId] = attachment;
  }

  @override
  ReceiptAttachment? get(String originalId) => _attachments[originalId];
}

final class ReceiptDocumentPipeline {
  const ReceiptDocumentPipeline();

  Future<ReceiptAttachment> process(ReceiptAttachmentInput input) async {
    var attachment = ReceiptAttachment.queued(input)
        .withStatus(AttachmentProcessingStatus.uploading)
        .withStatus(AttachmentProcessingStatus.processing);
    if (attachment.originalBytes.isEmpty) {
      return attachment.withFailure('The selected file is empty.');
    }

    if (attachment.isPdf) {
      return attachment._copy(
        status: AttachmentProcessingStatus.ready,
        processingMessage:
            'PDF preserved byte-for-byte; no image derivative is needed.',
      );
    }

    if (!attachment.isImage) {
      return attachment.withFailure(
        'This file type is not supported. Choose a PDF, JPEG, PNG, or HEIC image.',
      );
    }

    image.Image? decoded;
    try {
      decoded = image.decodeImage(attachment.originalBytes);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      if (_isHeic(attachment)) {
        return attachment._copy(
          status: AttachmentProcessingStatus.ready,
          processingMessage: 'HEIC kept as the original. An optimized derivative requires a platform HEIC decoder.',
        );
      }
      return attachment.withFailure(
        'The image could not be decoded on this platform; the original was not changed.',
      );
    }

    // Import validates and measures only; edits are explicitly applied later.
    return attachment._copy(
      originalWidth: decoded.width,
      originalHeight: decoded.height,
      status: AttachmentProcessingStatus.ready,
      printReadyAt300Dpi: _isPrintReady(decoded.width, decoded.height),
    );
  }

  Future<ReceiptAttachmentBatch> processBatch(
    Iterable<ReceiptAttachmentInput> inputs, {
    required String batchId,
  }) async {
    final attachments = <ReceiptAttachment>[];
    for (final input in inputs) {
      attachments.add(
        await process(
          ReceiptAttachmentInput(
            originalId: input.originalId,
            batchId: batchId,
            filename: input.filename,
            mimeType: input.mimeType,
            bytes: input.bytes,
          ),
        ),
      );
    }
    return ReceiptAttachmentBatch(
      id: batchId,
      attachments: List<ReceiptAttachment>.unmodifiable(attachments),
    );
  }

  Future<ReceiptAttachment> rotateQuarterTurn(
    ReceiptAttachment attachment,
  ) => Isolate.run(() {
    final decoded = image.decodeImage(attachment.preferredBytes);
    if (decoded == null) {
      throw const FormatException('Unable to decode image for rotation.');
    }
    final rotated = image.copyRotate(image.bakeOrientation(decoded), angle: 90);
    final bytes = Uint8List.fromList(image.encodePng(rotated, level: 1));
    return attachment.withDerivative(
      derivativeId:
          '${attachment.originalId}-derivative-crop-rotate-${sha256.convert(bytes)}',
      bytes: bytes,
      mimeType: 'image/png',
      width: rotated.width,
      height: rotated.height,
      printReadyAt300Dpi: _isPrintReady(rotated.width, rotated.height),
      processingMessage: null,
    );
  });

  /// Rotates current pixels beneath an upright crop frame; retains original evidence.
  Future<ReceiptAttachment> crop(
    ReceiptAttachment attachment,
    NormalizedCropRect cropRect, {
    Uint8List? sourceBytes,
  }) => Isolate.run(
    () => _cropSync(attachment, cropRect, sourceBytes: sourceBytes),
  );

  ReceiptAttachment _cropSync(
    ReceiptAttachment attachment,
    NormalizedCropRect cropRect, {
    Uint8List? sourceBytes,
  }) {
    if (!attachment.isImage) {
      return attachment.withFailure(
        'Crop is only available for decoded image files.',
      );
    }
    image.Image? decoded;
    try {
      decoded = image.decodeImage(sourceBytes ?? attachment.preferredBytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null || decoded.width < 2 || decoded.height < 2) {
      return attachment.withFailure(
        'The image could not be decoded for cropping.',
      );
    }

    final normalized = cropRect.clamped;
    if (normalized.rotation != 0) {
      final source = decoded;
      final rotated = image.Image(width: source.width, height: source.height);
      image.fill(rotated, color: image.ColorRgb8(255, 255, 255));
      final radians = normalized.rotation * math.pi / 180;
      final cosine = math.cos(radians), sine = math.sin(radians);
      final fitScale = rotationFitScale(
        source.width.toDouble(),
        source.height.toDouble(),
        normalized.rotation,
      );
      final cx = (source.width - 1) / 2, cy = (source.height - 1) / 2;
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final sx = (cosine * (x - cx) + sine * (y - cy)) / fitScale + cx;
          final sy = (-sine * (x - cx) + cosine * (y - cy)) / fitScale + cy;
          if (sx >= 0 &&
              sy >= 0 &&
              sx <= source.width - 1 &&
              sy <= source.height - 1) {
            rotated.setPixel(
              x,
              y,
              source.getPixelInterpolate(
                sx,
                sy,
                interpolation: image.Interpolation.linear,
              ),
            );
          }
        }
      }
      decoded = rotated;
    }
    final left = (decoded.width * normalized.left)
        .floor()
        .clamp(0, decoded.width - 1)
        .toInt();
    final top = (decoded.height * normalized.top)
        .floor()
        .clamp(0, decoded.height - 1)
        .toInt();
    final right = (decoded.width * normalized.right)
        .ceil()
        .clamp(left + 1, decoded.width)
        .toInt();
    final bottom = (decoded.height * normalized.bottom)
        .ceil()
        .clamp(top + 1, decoded.height)
        .toInt();
    final cropped = image.copyCrop(
      decoded,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    // Crop changes geometry only; PNG avoids another lossy compression pass.
    const mimeType = 'image/png';
    final bytes = Uint8List.fromList(image.encodePng(cropped, level: 1));
    final printReady = _isPrintReady(cropped.width, cropped.height);
    final result = attachment.withDerivative(
      derivativeId:
          '${attachment.originalId}-derivative-crop-${sha256.convert(bytes).toString()}',
      bytes: bytes,
      mimeType: mimeType,
      width: cropped.width,
      height: cropped.height,
      printReadyAt300Dpi: printReady,
      processingMessage: printReady
          ? 'Crop applied locally; original remains available for fallback.'
          : 'Crop applied locally. Cropped source is below A4 at 300 DPI; it was not upscaled.',
    );
    if (attachment.originalWidth == null || attachment.originalHeight == null) {
      return result._copy(
        originalWidth: decoded.width,
        originalHeight: decoded.height,
      );
    }
    return result;
  }

  /// Preserves the legacy action while routing it through exact crop semantics.
  Future<ReceiptAttachment> cropCenter(ReceiptAttachment attachment) {
    return crop(
      attachment,
      const NormalizedCropRect(
        left: 0.05,
        top: 0.05,
        right: 0.95,
        bottom: 0.95,
      ),
    );
  }

  Future<ReceiptAttachment> convertToPdf(ReceiptAttachment attachment) async {
    if (!attachment.canConvertToPdf) {
      return attachment.withFailure(
        'PDF conversion is available only for decoded image files.',
      );
    }
    final document = pw.Document();
    final imageProvider = pw.MemoryImage(attachment.preferredBytes);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) =>
            pw.Center(child: pw.Image(imageProvider, fit: pw.BoxFit.contain)),
      ),
    );
    final pdfBytes = Uint8List.fromList(await document.save());
    return attachment.withPdf(pdfBytes);
  }

  bool _isHeic(ReceiptAttachment attachment) {
    final lowerName = attachment.filename.toLowerCase();
    final lowerMime = attachment.originalMimeType.toLowerCase();
    return lowerMime == 'image/heic' ||
        lowerMime == 'image/heif' ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif');
  }

  bool _isPrintReady(int width, int height) {
    if (width >= height) {
      return width >= 3508 && height >= 2480;
    }
    return width >= 2480 && height >= 3508;
  }
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
