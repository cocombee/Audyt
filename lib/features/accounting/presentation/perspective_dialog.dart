import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/documents/document_scan.dart';

class PerspectiveDialog extends StatefulWidget {
  const PerspectiveDialog({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    this.corners,
  });
  final Uint8List bytes;
  final int width, height;
  final ScanCorners? corners;
  @override
  State<PerspectiveDialog> createState() => _PerspectiveState();
}

class _PerspectiveState extends State<PerspectiveDialog> {
  late List<Offset> points =
      (widget.corners ?? [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])
          .map((p) => Offset(p.$1, p.$2))
          .toList();
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width:
          AccountingPopoutTokens.customContentWidth +
          accountingContentInset * 2,
      height: MediaQuery.sizeOf(context).height - 48,
      child: Padding(
        padding: accountingContentPadding,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Perspective',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                accountingCompactClose(
                  context,
                  key: const ValueKey('perspective-cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: AccountingTheme.of(context).muted,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final size = applyBoxFit(
                        BoxFit.contain,
                        Size(widget.width.toDouble(), widget.height.toDouble()),
                        Size(bounds.maxWidth - 24, bounds.maxHeight - 24),
                      ).destination;
                      return Center(
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Image.memory(
                                  widget.bytes,
                                  fit: BoxFit.fill,
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _QuadPainter(points),
                                  ),
                                ),
                              ),
                              for (var i = 0; i < 4; i++)
                                Positioned(
                                  left: points[i].dx * size.width - 14,
                                  top: points[i].dy * size.height - 14,
                                  child: MouseRegion(
                                    cursor: i.isEven
                                        ? SystemMouseCursors
                                              .resizeUpLeftDownRight
                                        : SystemMouseCursors
                                              .resizeUpRightDownLeft,
                                    child: GestureDetector(
                                      onPanUpdate: (d) => setState(
                                        () => points[i] = Offset(
                                          (points[i].dx +
                                                  d.delta.dx / size.width)
                                              .clamp(0, 1),
                                          (points[i].dy +
                                                  d.delta.dy / size.height)
                                              .clamp(0, 1),
                                        ),
                                      ),
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: Container(
                                            width: 9,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                color: const Color(0xFF4C4A4A)
                                                    .withValues(alpha: 0.54),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AccountingButton.primary(
                  context,
                  key: const ValueKey('perspective-apply'),
                  onPressed: () => Navigator.pop(
                    context,
                    points.map((p) => (p.dx, p.dy)).toList(),
                  ),
                  child: const Text('Correct'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addPolygon(
        points
            .map((p) => Offset(p.dx * size.width, p.dy * size.height))
            .toList(),
        true,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF4C4A4A).withValues(alpha: 0.54),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}
