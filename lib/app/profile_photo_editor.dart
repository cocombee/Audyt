import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as raster;

import '../core/documents/crop_edit.dart';
import '../core/documents/receipt_document.dart';
import 'accounting_photo_controls.dart';
import 'accounting_crop_editor.dart';
import 'accounting_theme.dart';

/// Decode and orient once; retain these pixels until the user accepts or cancels.
Uint8List prepareProfilePhoto(Uint8List bytes) {
  final decoded = raster.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Choose a supported image.');
  var image = raster.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > 1536) {
    image = raster.copyResize(
      image,
      width: image.width >= image.height ? 1536 : null,
      height: image.height > image.width ? 1536 : null,
    );
  }
  return Uint8List.fromList(raster.encodePng(image, level: 1));
}

Future<String?> showProfilePhotoEditor(
  BuildContext context,
  Uint8List bytes,
) async {
  final prepared = await compute(prepareProfilePhoto, bytes);
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProfilePhotoEditor(bytes: prepared),
  );
}

class ProfilePhotoEditor extends StatefulWidget {
  const ProfilePhotoEditor({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<ProfilePhotoEditor> createState() => _ProfilePhotoEditorState();
}

class _ProfilePhotoEditorState extends State<ProfilePhotoEditor> {
  late final image = raster.decodeImage(widget.bytes)!;
  late final double side = math.min(image.width, image.height).toDouble();
  late final history = CropEditHistory(
    normalizedAspectRatio: image.height / image.width,
    initial: NormalizedCropRect(
      left: (image.width - side) / (2 * image.width),
      top: (image.height - side) / (2 * image.height),
      right: (image.width + side) / (2 * image.width),
      bottom: (image.height + side) / (2 * image.height),
    ),
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    history.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await const ReceiptDocumentPipeline().crop(
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'profile-photo',
            batchId: 'profile-photo',
            filename: 'Profile Photo.png',
            mimeType: 'image/png',
            bytes: widget.bytes,
          ),
        ),
        history.present,
      );
      if (result.failureMessage != null) {
        throw StateError('Crop could not be applied.');
      }
      final crop = raster.decodeImage(result.preferredBytes)!;
      final square = raster.copyResizeCropSquare(crop, size: 256);
      final encoded = base64Encode(raster.encodeJpg(square, quality: 90));
      if (mounted) Navigator.pop(context, encoded);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not apply the crop. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return Dialog(
      key: const ValueKey('profile-photo-editor'),
      backgroundColor: tokens.card,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: (MediaQuery.sizeOf(context).height - 160).clamp(
                  240.0,
                  500.0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ColoredBox(
                    color: tokens.muted,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
                            child: Center(
                              child: AccountingCropReviewEditor(
                                imageBytes: widget.bytes,
                                cropHistory: history,
                                imageWidth: image.width,
                                imageHeight: image.height,
                                circularPreview: true,
                                allowMove: true,
                                showHistoryControls: false,
                                maxPreviewHeight: 440,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AccountingPhotoButton(
                                key: const ValueKey('profile-crop'),
                                icon: Icons.crop,
                                tooltip: 'Crop',
                                onPressed: saving
                                    ? null
                                    : () => history.reset(),
                              ),
                              const SizedBox(width: 4),
                              AccountingPhotoButton(
                                key: const ValueKey('profile-rotate'),
                                icon: Icons.rotate_right,
                                tooltip: 'Rotate 90°',
                                onPressed: saving
                                    ? null
                                    : () {
                                        var angle =
                                            history.present.rotation + 90;
                                        if (angle > 180) angle -= 360;
                                        history.updateRotation(angle);
                                        history.endResize();
                                      },
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AccountingPhotoButton(
                                key: const ValueKey('cancel-profile-crop'),
                                icon: Icons.close,
                                tooltip: 'Cancel',
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 4),
                              AccountingPhotoButton(
                                key: const ValueKey('save-profile-crop'),
                                icon: Icons.check_circle_outline,
                                tooltip: 'Save',
                                onPressed: saving ? null : _accept,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (error != null)
                Text(error!, style: TextStyle(color: tokens.destructive)),
            ],
          ),
        ),
      ),
    );
  }
}
