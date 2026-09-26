import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import '../core/documents/crop_edit.dart';

/// Interactive crop surface used by Receipt Review for one image at a time.
final class AccountingCropReviewEditor extends StatelessWidget {
  const AccountingCropReviewEditor({
    required this.imageBytes,
    required this.cropHistory,
    required this.imageWidth,
    required this.imageHeight,
    this.exposeFrameSemantics = true,
    this.showHistoryControls = true,
    this.maxPreviewHeight = 260,
    this.rotationOnly = false,
    this.circularPreview = false,
    this.allowMove = false,
    this.previewImage,
    this.onRotationEnd,
    super.key,
  });

  final Uint8List imageBytes;
  final Widget? previewImage;
  final CropEditHistory cropHistory;
  final int imageWidth;
  final int imageHeight;
  final bool exposeFrameSemantics;
  final bool showHistoryControls;
  final double maxPreviewHeight;
  final bool rotationOnly;
  final bool circularPreview;
  final bool allowMove;
  final VoidCallback? onRotationEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cropHistory,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const rotationGutter = 26.0;
            final availableWidth =
                constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? (constraints.maxWidth - rotationGutter * 2).clamp(
                    1.0,
                    double.infinity,
                  )
                : 520.0;
            final sourceAspect = imageWidth > 0 && imageHeight > 0
                ? imageWidth / imageHeight
                : 1.5;
            var previewWidth = availableWidth
                .clamp(1.0, double.infinity)
                .toDouble();
            var previewHeight = previewWidth / sourceAspect;
            if (previewHeight >
                (constraints.hasBoundedHeight
                    ? math.min(
                        maxPreviewHeight,
                        constraints.maxHeight - rotationGutter * 2,
                      )
                    : maxPreviewHeight)) {
              previewHeight =
                  ((constraints.hasBoundedHeight
                          ? math.min(
                              maxPreviewHeight,
                              constraints.maxHeight - rotationGutter * 2,
                            )
                          : maxPreviewHeight))
                      .clamp(1.0, double.infinity);
              previewWidth = previewHeight * sourceAspect;
            }

            final previewSize = Size(previewWidth, previewHeight);
            final canvasSize = Size(
              previewSize.width > 2 ? previewSize.width - 2 : 1,
              previewSize.height > 2 ? previewSize.height - 2 : 1,
            );
            final fitScale = rotationFitScale(
              canvasSize.width,
              canvasSize.height,
              cropHistory.present.rotation,
            );
            final rotationFrame = _cropRect(canvasSize, cropHistory.present);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: previewSize.width + rotationGutter * 2,
                    height: previewSize.height + rotationGutter * 2,
                    child: Stack(
                      children: [
                        Positioned(
                          left: rotationGutter,
                          top: rotationGutter,
                          child: Container(
                            key: const ValueKey('accounting-crop-preview'),
                            width: previewSize.width,
                            height: previewSize.height,
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              color: AccountingTheme.of(context).background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AccountingTheme.of(context).border,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(1),
                              child: Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.hardEdge,
                                children: <Widget>[
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..rotateZ(
                                        cropHistory.present.rotation *
                                            math.pi /
                                            180,
                                      )
                                      ..scaleByDouble(
                                        fitScale,
                                        fitScale,
                                        fitScale,
                                        1,
                                      ),
                                    child:
                                        previewImage ??
                                        Image.memory(
                                          imageBytes,
                                          fit: BoxFit.fill,
                                          gaplessPlayback: true,
                                          semanticLabel:
                                              'Receipt image for cropping',
                                          errorBuilder:
                                              (
                                                context,
                                                error,
                                                stackTrace,
                                              ) => Center(
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  color: AccountingTheme.of(
                                                    context,
                                                  ).mutedForeground,
                                                  semanticLabel: 'Image preview unavailable',
                                                ),
                                              ),
                                        ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _CropOverlayPainter(
                                          crop: _cropRect(
                                            canvasSize,
                                            cropHistory.present,
                                          ),
                                          color: Colors.white,
                                          showGrid:
                                              !rotationOnly && !circularPreview,
                                          circular: circularPreview,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!rotationOnly)
                                    _buildFrame(context, canvasSize),
                                  for (final handle
                                      in rotationOnly
                                          ? <CropHandle>[]
                                          : CropHandle.values)
                                    _buildHandle(context, canvasSize, handle),
                                ],
                              ),
                            ),
                          ),
                        ),
                        for (final horizontal in [-1, 1])
                          for (final vertical in [-1, 1])
                            Positioned(
                              left:
                                  rotationGutter +
                                  (horizontal < 0
                                      ? rotationFrame.left - 26
                                      : rotationFrame.right + 2),
                              top:
                                  rotationGutter +
                                  (vertical < 0
                                      ? rotationFrame.top - 26
                                      : rotationFrame.bottom + 2),
                              child: _RotationCorner(
                                key: ValueKey(
                                  'crop-rotate-$horizontal-$vertical',
                                ),
                                history: cropHistory,
                                onEnd: onRotationEnd,
                                vector: Offset(
                                  (horizontal < 0
                                          ? rotationFrame.left - 12
                                          : rotationFrame.right + 12) -
                                      previewSize.width / 2,
                                  (vertical < 0
                                          ? rotationFrame.top - 12
                                          : rotationFrame.bottom + 12) -
                                      previewSize.height / 2,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                if (showHistoryControls) const SizedBox(height: 12),
                if (showHistoryControls)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _historyButton(
                        context,
                        key: const ValueKey('accounting-crop-undo'),
                        icon: Icons.undo_rounded,
                        tooltip: 'Undo crop change',
                        onPressed: cropHistory.canUndo
                            ? cropHistory.undo
                            : null,
                      ),
                      _historyButton(
                        context,
                        key: const ValueKey('accounting-crop-redo'),
                        icon: Icons.redo_rounded,
                        tooltip: 'Redo crop change',
                        onPressed: cropHistory.canRedo
                            ? cropHistory.redo
                            : null,
                      ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Rect _cropRect(Size previewSize, NormalizedCropRect crop) {
    return Rect.fromLTRB(
      crop.left * previewSize.width,
      crop.top * previewSize.height,
      crop.right * previewSize.width,
      crop.bottom * previewSize.height,
    );
  }

  Widget _buildFrame(BuildContext context, Size previewSize) {
    final frame = _cropRect(previewSize, cropHistory.present);
    final frameChild = GestureDetector(
      onPanStart: allowMove ? (_) => cropHistory.beginResize() : null,
      onPanUpdate: allowMove
          ? (details) => cropHistory.updateTranslation(
              details.delta.dx / previewSize.width,
              details.delta.dy / previewSize.height,
            )
          : null,
      onPanEnd: allowMove ? (_) => cropHistory.endResize() : null,
      child: Container(
        key: const ValueKey('accounting-crop-frame'),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1),
        ),
      ),
    );
    return Positioned(
      left: frame.left,
      top: frame.top,
      width: frame.width,
      height: frame.height,
      child: exposeFrameSemantics
          ? Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Crop frame',
              child: frameChild,
            )
          : frameChild,
    );
  }

  Widget _buildHandle(
    BuildContext context,
    Size previewSize,
    CropHandle handle,
  ) {
    final frame = _cropRect(previewSize, cropHistory.present);
    final point = switch (handle) {
      CropHandle.top => frame.topCenter,
      CropHandle.bottom => frame.bottomCenter,
      CropHandle.left => frame.centerLeft,
      CropHandle.right => frame.centerRight,
      CropHandle.topLeft => frame.topLeft,
      CropHandle.topRight => frame.topRight,
      CropHandle.bottomLeft => frame.bottomLeft,
      CropHandle.bottomRight => frame.bottomRight,
    };
    const handleSize = 44.0;
    final left = (point.dx - handleSize / 2)
        .clamp(
          0.0,
          (previewSize.width - handleSize).clamp(0.0, double.infinity),
        )
        .toDouble();
    final top = (point.dy - handleSize / 2)
        .clamp(
          0.0,
          (previewSize.height - handleSize).clamp(0.0, double.infinity),
        )
        .toDouble();
    final label = switch (handle) {
      CropHandle.top => 'Top crop handle',
      CropHandle.bottom => 'Bottom crop handle',
      CropHandle.left => 'Left crop handle',
      CropHandle.right => 'Right crop handle',
      CropHandle.topLeft => 'Top left crop handle',
      CropHandle.topRight => 'Top right crop handle',
      CropHandle.bottomLeft => 'Bottom left crop handle',
      CropHandle.bottomRight => 'Bottom right crop handle',
    };
    return Positioned(
      left: left,
      top: top,
      width: handleSize,
      height: handleSize,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        child: _CropResizeCursor(
          handle: handle,
          child: RawGestureDetector(
            key: ValueKey<String>(
              'accounting-crop-handle-${_handleName(handle)}',
            ),
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _CropHandleDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _CropHandleDragRecognizer
                  >(
                    () => _CropHandleDragRecognizer(
                      onStart: cropHistory.beginResize,
                      onUpdate: (delta) {
                        cropHistory.updateResize(
                          handle,
                          deltaX: delta.dx / previewSize.width,
                          deltaY: delta.dy / previewSize.height,
                        );
                      },
                      onEnd: cropHistory.endResize,
                    ),
                    (_) {},
                  ),
            },
            child: Stack(
              children: [
                Positioned(
                  left: (point.dx - left - 4).clamp(0.0, handleSize - 8),
                  top: (point.dy - top - 4).clamp(0.0, handleSize - 8),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accountingNeutralSurface,
                      shape: BoxShape.rectangle,
                      border: Border.all(
                        color: const Color(0xCC4C4A4A),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: AccountingButton.compact(
        context,
        key: key,
        leadingIcon: icon,
        onPressed: onPressed,
        semanticsLabel: tooltip,
        child: Text(tooltip.split(' ').first),
      ),
    );
  }

  String _handleName(CropHandle handle) => switch (handle) {
    CropHandle.top => 'top',
    CropHandle.bottom => 'bottom',
    CropHandle.left => 'left',
    CropHandle.right => 'right',
    CropHandle.topLeft => 'top-left',
    CropHandle.topRight => 'top-right',
    CropHandle.bottomLeft => 'bottom-left',
    CropHandle.bottomRight => 'bottom-right',
  };
}

final class _CropHandleDragRecognizer extends OneSequenceGestureRecognizer {
  _CropHandleDragRecognizer({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  bool _ended = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _ended = false;
    startTrackingPointer(event.pointer);
    resolve(GestureDisposition.accepted);
    onStart();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate(event.delta);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _finish();
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    onEnd();
  }

  @override
  String get debugDescription => 'crop handle drag';
}

final class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.crop,
    required this.color,
    this.showGrid = true,
    this.circular = false,
  });

  final Rect crop;
  final Color color;
  final bool showGrid;
  final bool circular;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()
      ..color = const Color(0xFF4C4A4A).withValues(alpha: 0.42);
    final cutout = Path();
    if (circular) {
      cutout.addOval(crop);
    } else {
      cutout.addRect(crop);
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        cutout,
      ),
      overlay,
    );
    if (circular) {
      canvas.drawOval(
        crop,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
    }
    if (showGrid) {
      final grid = Path()..addRect(crop.deflate(0.5));
      for (final fraction in [1 / 3, 2 / 3]) {
        final x = crop.left + crop.width * fraction;
        final y = crop.top + crop.height * fraction;
        grid
          ..moveTo(x, crop.top)
          ..lineTo(x, crop.bottom)
          ..moveTo(crop.left, y)
          ..lineTo(crop.right, y);
      }
      canvas.drawPath(
        grid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x994C4A4A),
      );
      canvas.drawPath(
        grid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop ||
      oldDelegate.color != color ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.circular != circular;
}

class _RotationCorner extends StatefulWidget {
  const _RotationCorner({
    super.key,
    required this.history,
    required this.vector,
    this.onEnd,
  });
  final CropEditHistory history;
  final Offset vector;
  final VoidCallback? onEnd;
  @override
  State<_RotationCorner> createState() => _RotationCornerState();
}

class _RotationCornerState extends State<_RotationCorner> {
  bool hovered = false;
  Offset pointerPosition = const Offset(12, 12);
  double? startAngle;
  double startRotation = 0;
  double angle(Offset position) {
    final p = position - const Offset(12, 12) + widget.vector;
    return math.atan2(p.dy, p.dx);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.none,
    onHover: (event) => setState(() => pointerPosition = event.localPosition),
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Tooltip(
      message: 'Drag to rotate',
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (details) {
            startAngle = angle(details.localPosition);
            startRotation = widget.history.present.rotation;
            widget.history.beginResize();
          },
          onPointerMove: (details) {
            if (startAngle == null) return;
            setState(() => pointerPosition = details.localPosition);
            var delta = angle(details.localPosition) - startAngle!;
            delta = math.atan2(math.sin(delta), math.cos(delta));
            widget.history.updateRotation(
              startRotation + delta * 180 / math.pi,
            );
          },
          onPointerUp: (_) {
            widget.history.endResize();
            startAngle = null;
            widget.onEnd?.call();
          },
          onPointerCancel: (_) {
            widget.history.endResize();
            startAngle = null;
          },
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (hovered || startAngle != null)
                  Positioned(
                    left: pointerPosition.dx - 9,
                    top: pointerPosition.dy - 9,
                    child: const IgnorePointer(
                      child: Icon(Icons.rotate_right, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pending rotation is local to a gesture; committing creates one image edit.
class AccountingEditedRotationPreview extends StatefulWidget {
  const AccountingEditedRotationPreview({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.maxHeight,
    required this.onRotate,
  });
  final Uint8List bytes;
  final int width, height;
  final double maxHeight;
  final ValueChanged<double> onRotate;
  @override
  State<AccountingEditedRotationPreview> createState() =>
      _AccountingEditedRotationPreviewState();
}

class _AccountingEditedRotationPreviewState
    extends State<AccountingEditedRotationPreview> {
  final history = CropEditHistory();
  @override
  void dispose() {
    history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountingCropReviewEditor(
    imageBytes: widget.bytes,
    imageWidth: widget.width,
    imageHeight: widget.height,
    cropHistory: history,
    maxPreviewHeight: widget.maxHeight,
    showHistoryControls: false,
    rotationOnly: true,
    onRotationEnd: () => widget.onRotate(history.present.rotation),
  );
}

class _CropResizeCursor extends StatefulWidget {
  const _CropResizeCursor({required this.handle, required this.child});
  final CropHandle handle;
  final Widget child;
  @override
  State<_CropResizeCursor> createState() => _CropResizeCursorState();
}

class _CropResizeCursorState extends State<_CropResizeCursor> {
  final overlay = OverlayPortalController();
  Offset position = Offset.zero;
  bool dragging = false;
  void track(Offset global) {
    final box = Overlay.of(context).context.findRenderObject() as RenderBox;
    setState(() => position = box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.none,
    onEnter: (event) {
      track(event.position);
      overlay.show();
    },
    onHover: (event) => track(event.position),
    onExit: (_) {
      if (!dragging) overlay.hide();
    },
    child: OverlayPortal(
      controller: overlay,
      overlayChildBuilder: (_) => Positioned(
        left: position.dx - 9,
        top: position.dy - 9,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: switch (widget.handle) {
              CropHandle.topLeft || CropHandle.bottomRight => math.pi / 4,
              CropHandle.topRight || CropHandle.bottomLeft => -math.pi / 4,
              CropHandle.top || CropHandle.bottom => math.pi / 2,
              _ => 0,
            },
            child: const CustomPaint(
              key: ValueKey('crop-resize-cursor'),
              size: Size(18, 18),
              painter: _ResizeArrowPainter(),
            ),
          ),
        ),
      ),
      child: Listener(
        onPointerDown: (event) {
          dragging = true;
          track(event.position);
          overlay.show();
        },
        onPointerMove: (event) => track(event.position),
        onPointerUp: (_) {
          dragging = false;
          overlay.hide();
        },
        onPointerCancel: (_) {
          dragging = false;
          overlay.hide();
        },
        child: widget.child,
      ),
    ),
  );
}

/// One solid double-headed shaft, rotated by the handle's direction.
class _ResizeArrowPainter extends CustomPainter {
  const _ResizeArrowPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 10)
      ..lineTo(5, 6)
      ..lineTo(5, 9)
      ..lineTo(15, 9)
      ..lineTo(15, 6)
      ..lineTo(19, 10)
      ..lineTo(15, 14)
      ..lineTo(15, 11)
      ..lineTo(5, 11)
      ..lineTo(5, 14)
      ..close();
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFF4C4A4A));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ResizeArrowPainter oldDelegate) => false;
}
