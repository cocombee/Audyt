import 'package:flutter/material.dart';

/// The same zoom gestures for attachment previews and the image editor.
/// Scroll and trackpad gestures zoom around the pointer; double-clicking
/// zooms into that point, and a second double-click returns to fit.
class AccountingImageZoom extends StatefulWidget {
  const AccountingImageZoom({
    super.key,
    required this.child,
    this.transformationController,
    this.minScale = 1,
    this.maxScale = 5,
    this.panEnabled = true,
  });

  final Widget child;
  final TransformationController? transformationController;
  final double minScale;
  final double maxScale;
  final bool panEnabled;

  @override
  State<AccountingImageZoom> createState() => _AccountingImageZoomState();
}

class _AccountingImageZoomState extends State<AccountingImageZoom> {
  final TransformationController _ownedController = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  TransformationController get _controller =>
      widget.transformationController ?? _ownedController;

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final controller = _controller;
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
      return;
    }
    final scale = 2.5.clamp(widget.minScale, widget.maxScale).toDouble();
    final scenePoint = controller.toScene(_doubleTapPosition);
    controller.value = Matrix4.identity()
      ..translateByDouble(
        _doubleTapPosition.dx - scenePoint.dx * scale,
        _doubleTapPosition.dy - scenePoint.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
    onDoubleTap: _toggleZoom,
    child: InteractiveViewer(
      transformationController: _controller,
      trackpadScrollCausesScale: true,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      panEnabled: widget.panEnabled,
      child: widget.child,
    ),
  );
}
