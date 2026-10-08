import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_image_zoom.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/documents/document_optimization.dart';
import '../../../../core/documents/receipt_document.dart';
import '../../../../core/documents/document_vector_trace.dart';

final class DocumentOptimizationChoice {
  const DocumentOptimizationChoice(
    this.recipe,
    this.all,
    this.includeGeometry, {
    this.result,
  });
  final ReceiptAttachment? result;
  final DocumentOptimizationRecipe recipe;
  final bool all, includeGeometry;
}

/// An editor for a recipe, never for the preserved evidence bytes themselves.
class DocumentOptimizationDialog extends StatefulWidget {
  const DocumentOptimizationDialog({
    super.key,
    required this.attachment,
    required this.initialRecipe,
    required this.batchCount,
    this.onComplete,
    this.section,
    this.onRecipeChanged,
    this.onClosePanel,
    this.onOutputChanged,
    this.transformationController,
    this.vectorPreview = false,
    this.vectorPdf = false,
    this.previewQuarterTurns = 0,
  });
  final ReceiptAttachment attachment;
  final DocumentOptimizationRecipe initialRecipe;
  final int batchCount;
  final ValueChanged<DocumentOptimizationChoice?>? onComplete;
  final String? section;
  final ValueChanged<DocumentOptimizationRecipe>? onRecipeChanged;
  final VoidCallback? onClosePanel;
  final ValueChanged<ReceiptAttachment?>? onOutputChanged;
  final TransformationController? transformationController;
  final bool vectorPreview;
  final bool vectorPdf;
  final int previewQuarterTurns;
  @override
  State<DocumentOptimizationDialog> createState() =>
      DocumentOptimizationDialogState();
}

class DocumentOptimizationDialogState
    extends State<DocumentOptimizationDialog> {
  late DocumentOptimizationRecipe _recipe;
  late ReceiptAttachment _comparisonSource;
  final _past = <DocumentOptimizationRecipe>[];
  final _future = <DocumentOptimizationRecipe>[];
  DocumentOptimizationResult? _preview;
  DocumentOptimizationResult? _baseline;
  DocumentOptimizationRecipe _renderedRecipe =
      const DocumentOptimizationRecipe();
  Future<Uint8List>? _previewSource;
  Timer? _timer;
  Timer? _outputTimer;
  int _outputRevision = 0;
  ReceiptAttachment? output;
  void _scheduleOutput() {
    if (widget.onOutputChanged == null) return;
    final revision = ++_outputRevision;
    output = null;
    widget.onOutputChanged!(null);
    _outputTimer?.cancel();
    if (!widget.vectorPreview &&
        !widget.attachment.derivativeId.contains('-derivative-crop-') &&
        jsonEncode(_recipe.toJson()) ==
            jsonEncode(const DocumentOptimizationRecipe().toJson())) {
      output = widget.attachment;
      widget.onOutputChanged!(output);
      return;
    }
    _outputTimer = Timer(const Duration(milliseconds: 160), () async {
      try {
        var result = await const DocumentOptimizationEngine().optimize(
          widget.attachment,
          _recipe,
        );
        if (widget.vectorPreview) {
          final traced = await DocumentVectorTrace().trace(
            result.preferredBytes,
            const DocumentTraceSettings(),
          );
          result = traced
              .attachTo(result, asPdf: widget.vectorPdf)
              .withOptimizationRecipe({
                ..._recipe.toJson(),
                'vectorTrace': const DocumentTraceSettings().toJson(),
                'vectorPreviewPng': base64Encode(traced.preview),
              });
        }
        if (!mounted || revision != _outputRevision) return;
        setState(() => output = result);
        widget.onOutputChanged!(result);
      } catch (error) {
        if (mounted && revision == _outputRevision) {
          setState(() => _error = error.toString());
        }
      }
    });
  }

  void quickOptimize() => _change(_recipe.copyWith(automaticCompression: true));
  int _revision = 0;
  bool _busy = false, _original = false;
  bool _applying = false;
  Offset _panelOffset = const Offset(8, 8);
  final _panelKey = GlobalKey();
  String? _error;
  bool _rendering = false, _pendingRender = false;

  @override
  void initState() {
    super.initState();
    _comparisonSource = widget.attachment;
    _recipe = widget.initialRecipe;
    _render();
    if (widget.attachment.derivativeId.contains('-derivative-crop-')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleOutput();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _outputTimer?.cancel();
    _outputRevision++;
    _revision++;
    super.dispose();
  }

  void reset() => _change(const DocumentOptimizationRecipe());
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  void undo() {
    if (!canUndo) return;
    _future.add(_recipe);
    setState(() => _recipe = _past.removeLast());
    widget.onRecipeChanged?.call(_recipe);
    _scheduleOutput();
    _render();
  }

  void redo() {
    if (!canRedo) return;
    _past.add(_recipe);
    setState(() => _recipe = _future.removeLast());
    widget.onRecipeChanged?.call(_recipe);
    _scheduleOutput();
    _render();
  }

  @override
  void didUpdateWidget(covariant DocumentOptimizationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vectorPreview != widget.vectorPreview ||
        oldWidget.vectorPdf != widget.vectorPdf) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleOutput();
      });
    }
    if (oldWidget.section != widget.section) _panelOffset = const Offset(8, 8);
    if (oldWidget.attachment.originalId != widget.attachment.originalId) {
      _comparisonSource = widget.attachment;
      _recipe = widget.initialRecipe;
      _past.clear();
      _future.clear();
    }
    if (oldWidget.attachment.preferredBytes !=
        widget.attachment.preferredBytes) {
      _past.clear();
      _future.clear();
      output = null;
      _outputRevision++;
      _recipe = widget.initialRecipe;
      _previewSource = null;
      _preview = null;
      _baseline = null;
      _render();
      if (widget.onRecipeChanged != null ||
          widget.initialRecipe != const DocumentOptimizationRecipe()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scheduleOutput();
        });
      }
    }
  }

  DocumentOptimizationRecipe? _sliderStart;
  void _endSlider() {
    final start = _sliderStart;
    _sliderStart = null;
    if (start != null &&
        start.toJson().toString() != _recipe.toJson().toString()) {
      _past.add(start);
      _future.clear();
      setState(() {});
      widget.onRecipeChanged?.call(_recipe);
    }
  }

  void _resetPanel() {
    const defaults = DocumentOptimizationRecipe();
    _change(switch (widget.section) {
      'Levels' => _recipe.copyWith(
        black: defaults.black,
        white: defaults.white,
      ),
      'Contrast' => _recipe.copyWith(contrast: defaults.contrast),
      'Sharpen' => _recipe.copyWith(sharpen: defaults.sharpen),
      'Quality' => _recipe.copyWith(
        quality: defaults.quality,
        automaticCompression: defaults.automaticCompression,
      ),
      _ => _recipe,
    });
  }

  void _change(DocumentOptimizationRecipe recipe) {
    final needsRender = true;
    if (_sliderStart == null) {
      _past.add(_recipe);
      _future.clear();
    }
    setState(() {
      _recipe = recipe;
      _busy = _preview == null;
      _error = null;
    });
    widget.onRecipeChanged?.call(recipe);
    _scheduleOutput();
    if (needsRender) _revision++;
    if (needsRender) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 16), _render);
    }
  }

  Future<void> _render() async {
    if (!mounted) return;
    if (widget.attachment.preferredMimeType == 'image/svg+xml') {
      setState(() => _busy = false);
      return;
    }
    if (_rendering) {
      _pendingRender = true;
      return;
    }
    _rendering = true;
    final revision = ++_revision;
    final renderingRecipe = _recipe;
    setState(() {
      _busy = _preview == null;
      _error = null;
    });
    try {
      final source = await (_previewSource ??=
          const DocumentOptimizationEngine().preparePreview(
            widget.attachment.preferredBytes,
          ));
      _baseline ??= await const DocumentOptimizationEngine().render(
        source,
        const DocumentOptimizationRecipe(),
      );
      final result = await const DocumentOptimizationEngine().render(
        source,
        renderingRecipe.copyWith(automaticCompression: false),
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _preview = result;
        _renderedRecipe = renderingRecipe;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    } finally {
      _rendering = false;
      if (_pendingRender && mounted) {
        _pendingRender = false;
        _render();
      }
    }
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed, {
    int? divisions,
    String? display,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(display ?? value.toStringAsFixed(0)),
        ],
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          trackShape: const _LevelsGradientTrack(),
          thumbColor: Colors.white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
        ),
        child: Slider(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          key: ValueKey('optimize-${label.toLowerCase().replaceAll(' ', '-')}'),
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChangeStart: (_) => _sliderStart = _recipe,
          onChangeEnd: (_) => _endSlider(),
          onChanged: changed,
        ),
      ),
    ],
  );

  Future<void> _finish(bool all) async {
    setState(() => _applying = true);
    try {
      final result = await const DocumentOptimizationEngine().optimize(
        widget.attachment,
        _recipe,
      );
      if (!mounted) return;
      await precacheImage(MemoryImage(result.preferredBytes), context);
      if (!mounted) return;
      final choice = DocumentOptimizationChoice(
        _recipe,
        all,
        false,
        result: result,
      );
      if (widget.onComplete != null) {
        widget.onComplete!(choice);
      } else {
        Navigator.pop(context, choice);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _applying = false;
        });
      }
    }
  }

  List<double> _toneMatrix() {
    final targetScale =
        255 * _recipe.contrast / (_recipe.white - _recipe.black);
    final baseScale = _preview == null
        ? 1.0
        : 255 *
              _renderedRecipe.contrast /
              (_renderedRecipe.white - _renderedRecipe.black);
    final baseOffset = _preview == null
        ? 0.0
        : 127.5 * (1 - _renderedRecipe.contrast) -
              _renderedRecipe.black * baseScale;
    final scale = _original ? 1.0 : targetScale / baseScale;
    final offset = _original
        ? 0.0
        : 127.5 * (1 - _recipe.contrast) -
              _recipe.black * targetScale -
              baseOffset * scale;
    return [
      scale,
      0,
      0,
      0,
      offset,
      0,
      scale,
      0,
      0,
      offset,
      0,
      0,
      scale,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  List<int> _liveHistogram() {
    if (_recipe.black == _renderedRecipe.black &&
        _recipe.white == _renderedRecipe.white &&
        _recipe.contrast == _renderedRecipe.contrast &&
        _preview != null) {
      return _preview!.histogram;
    }
    final counts = List<int>.filled(256, 0);
    final source = _baseline?.histogram ?? _preview?.histogram ?? counts;
    for (var i = 0; i < source.length; i++) {
      final target =
          (255 *
                  (((i - _recipe.black) / (_recipe.white - _recipe.black) -
                              .5) *
                          _recipe.contrast +
                      .5))
              .round()
              .clamp(0, 255);
      counts[target] += source[i];
    }
    return counts;
  }

  Widget buildCropPreview() {
    final unchanged =
        jsonEncode(_recipe.toJson()) ==
        jsonEncode(const DocumentOptimizationRecipe().toJson());
    if (_original ||
        (!widget.vectorPreview &&
            unchanged &&
            !widget.attachment.derivativeId.contains('-derivative-crop-')) ||
        output != null) {
      final current = _original
          ? _comparisonSource
          : (output ?? widget.attachment);
      final vectorRaster = current.optimizationRecipe?['vectorPreviewPng'];
      return Image.memory(
        current.preferredMimeType == 'image/svg+xml' && vectorRaster is String
            ? base64Decode(vectorRaster)
            : current.preferredBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    final bakedPreview =
        widget.attachment.optimizationRecipe?['vectorPreviewPng'];
    if (widget.attachment.preferredMimeType == 'image/svg+xml' &&
        bakedPreview is String) {
      return Image.memory(
        base64Decode(bakedPreview),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        widget.vectorPreview
            ? const [
                54.213,
                182.376,
                18.411,
                0,
                -40672.5,
                54.213,
                182.376,
                18.411,
                0,
                -40672.5,
                54.213,
                182.376,
                18.411,
                0,
                -40672.5,
                0,
                0,
                0,
                1,
                0,
              ]
            : const [
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ],
      ),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_toneMatrix()),
        child: Image.memory(
          _original || _preview == null
              ? widget.attachment.preferredBytes
              : _preview!.jpeg,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              const Center(child: Text('Image preview unavailable.')),
        ),
      ),
    );
  }

  Widget _editorContent(BuildContext context, double availableHeight) {
    final preview = <Widget>[
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AccountingTheme.of(context).muted,
          borderRadius: BorderRadius.circular(10),
        ),
        width: double.infinity,
        height: availableHeight,
        child: AccountingImageZoom(
          transformationController: widget.transformationController,
          minScale: 1,
          maxScale: 5,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.onRecipeChanged != null ? 72 : 0,
            ),
            child: RotatedBox(
              key: const ValueKey('instant-rotation-preview'),
              quarterTurns: widget.previewQuarterTurns,
              child: buildCropPreview(),
            ),
          ),
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: AccountingTheme.of(context).destructive),
        ),
    ];
    final controls = <Widget>[
      const SizedBox(height: 8),
      if (_preview != null &&
          (widget.onRecipeChanged == null ||
              widget.section == 'Levels' ||
              widget.section == 'Contrast'))
        SizedBox(
          height: 48,
          child: CustomPaint(
            painter: _HistogramPainter(
              _liveHistogram(),
              AccountingTheme.of(context).mutedForeground,
            ),
          ),
        ),
      if (_preview != null &&
          (widget.onRecipeChanged == null ||
              widget.section == 'Levels' ||
              widget.section == 'Contrast'))
        const SizedBox(height: 8),

      if (widget.onRecipeChanged == null || widget.section == 'Levels')
        _slider(
          'Black Point',
          _recipe.black.toDouble(),
          0,
          255,
          (v) => _change(
            _recipe.copyWith(black: v.round().clamp(0, _recipe.white - 1)),
          ),
        ),
      if (widget.onRecipeChanged == null || widget.section == 'Levels')
        _slider(
          'White Point',
          _recipe.white.toDouble(),
          0,
          255,
          (v) => _change(
            _recipe.copyWith(white: v.round().clamp(_recipe.black + 1, 255)),
          ),
        ),
      if (widget.onRecipeChanged == null || widget.section == 'Contrast')
        _slider(
          'Contrast',
          _recipe.contrast,
          0.2,
          3,
          (v) => _change(_recipe.copyWith(contrast: v)),
          display: _recipe.contrast.toStringAsFixed(2),
        ),
      if (widget.onRecipeChanged == null || widget.section == 'Quality')
        Tooltip(
          message: 'Use detail-preserving compression when you apply these settings.',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Expanded(child: Text('Detail preserving')),
                SizedBox(
                  width: 20,
                  height: 24,
                  child: Checkbox(
                    key: const ValueKey('optimize-automatic-compression'),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    value: _recipe.automaticCompression,
                    onChanged: (value) =>
                        _change(_recipe.copyWith(automaticCompression: value!)),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (widget.onRecipeChanged == null || widget.section == 'Quality')
        _slider(
          'JPEG Quality',
          _recipe.quality.toDouble(),
          30,
          100,
          (value) => _change(
            _recipe.copyWith(
              quality: value.round(),
              automaticCompression: false,
            ),
          ),
          divisions: 70,
        ),
      if (widget.onRecipeChanged == null || widget.section == 'Sharpen')
        _slider(
          'Sharpen',
          _recipe.sharpen,
          0,
          1,
          (v) => _change(_recipe.copyWith(sharpen: v)),
          display: _recipe.sharpen.toStringAsFixed(2),
        ),

      if (widget.onRecipeChanged == null)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AccountingButton.outline(
              context,
              key: const ValueKey('optimize-compare'),
              onPressed: () => setState(() => _original = !_original),
              child: Text(_original ? 'Show Edited' : 'Show Before'),
            ),
            AccountingButton.outline(
              context,
              key: const ValueKey('optimize-undo'),
              onPressed: _past.isEmpty
                  ? null
                  : () {
                      _future.add(_recipe);
                      setState(() => _recipe = _past.removeLast());
                      _timer?.cancel();
                      _render();
                    },
              child: const Text('Undo'),
            ),
            AccountingButton.outline(
              context,
              key: const ValueKey('optimize-redo'),
              onPressed: _future.isEmpty
                  ? null
                  : () {
                      _past.add(_recipe);
                      setState(() => _recipe = _future.removeLast());
                      _timer?.cancel();
                      _render();
                    },
              child: const Text('Redo'),
            ),
            AccountingButton.outline(
              context,
              key: const ValueKey('optimize-reset'),
              onPressed: () => _change(const DocumentOptimizationRecipe()),
              child: const Text('Reset'),
            ),
          ],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.onRecipeChanged != null) {
          if (widget.section == null) return preview.first;
          Widget panelLane(double width, double height) => SizedBox(
            width: width,
            height: height,
            child: LayoutBuilder(
              builder: (context, lane) {
                final panelWidth = (width - 32).clamp(1.0, 288.0);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      top: _panelOffset.dy.clamp(
                        0.0,
                        (height - 80).clamp(0.0, height),
                      ),
                      left: _panelOffset.dx.clamp(0.0, width - panelWidth),
                      width: panelWidth,
                      child: Container(
                        key: _panelKey,
                        constraints: BoxConstraints(
                          maxHeight: (height - _panelOffset.dy).clamp(
                            1.0,
                            height,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: AccountingTheme.of(context).card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AccountingTheme.of(context).border,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      key: const ValueKey(
                                        'adjustment-panel-drag',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onPanUpdate: (details) {
                                        final box =
                                            _panelKey.currentContext
                                                    ?.findRenderObject()
                                                as RenderBox?;
                                        final panelHeight =
                                            box?.size.height ?? height;
                                        setState(
                                          () => _panelOffset = Offset(
                                            (_panelOffset.dx + details.delta.dx)
                                                .clamp(0.0, width - panelWidth),
                                            (_panelOffset.dy + details.delta.dy)
                                                .clamp(
                                                  0.0,
                                                  (height - panelHeight).clamp(
                                                    0.0,
                                                    height,
                                                  ),
                                                ),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              widget.section!,
                                              style:
                                                  AccountingTypography.sectionTitle(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 60),
                                        ],
                                      ),
                                    ),
                                    ...controls,
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: AccountingPopoutTokens.closeInset,
                              right: AccountingPopoutTokens.closeInset + 28 + 8,
                              child: IconButton(
                                key: const ValueKey('adjustment-panel-reset'),
                                tooltip: 'Reset panel',
                                onPressed: _resetPanel,
                                icon: const AccountingIcon(
                                  Icons.restart_alt,
                                  size: 15.3,
                                ),
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                  backgroundColor: AccountingTheme.of(context)
                                      .card,
                                  side: BorderSide(
                                    color: AccountingTheme.of(context).border,
                                  ),
                                ),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Positioned(
                              top: AccountingPopoutTokens.closeInset,
                              right: AccountingPopoutTokens.closeInset,
                              child: accountingCompactClose(
                                context,
                                key: const ValueKey('adjustment-panel-close'),
                                onPressed: widget.onClosePanel,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
          return Stack(
            children: [
              Positioned.fill(child: preview.first),
              Positioned(
                top: 0,
                bottom: 0,
                left: 68,
                right: 68,
                child: panelLane(
                  (constraints.maxWidth - 136).clamp(1.0, constraints.maxWidth),
                  availableHeight,
                ),
              ),
            ],
          );
        }
        if (constraints.maxWidth >= 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.onComplete == null ? 300 : 250,
                height: availableHeight,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null) Text(_error!),
                      ...controls,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: availableHeight,
                  child: Center(child: preview.first),
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [...preview, ...controls],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onRecipeChanged != null) {
      return LayoutBuilder(
        builder: (context, bounds) => _editorContent(context, bounds.maxHeight),
      );
    }
    if (widget.onComplete != null) {
      return AbsorbPointer(
        absorbing: _applying,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) =>
                    _editorContent(context, bounds.maxHeight),
              ),
            ),
            const SizedBox(height: 8),
            if (_applying) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                AccountingButton.outline(
                  context,
                  key: const ValueKey('optimize-cancel'),
                  onPressed: () => widget.onComplete!(null),
                  child: const Text('Cancel'),
                ),
                if (widget.batchCount > 1)
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('optimize-apply-all'),
                    onPressed: _busy ? null : () => _finish(true),
                    child: const Text('Apply to All'),
                  ),
                AccountingButton.primary(
                  context,
                  key: const ValueKey('optimize-apply'),
                  onPressed: _busy ? null : () => _finish(false),
                  child: Text(_applying ? 'Applying…' : 'Apply'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width:
            AccountingPopoutTokens.customContentWidth +
            accountingContentInset * 2,
        height: MediaQuery.sizeOf(context).height - 40,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Optimize Document',
                    style: AccountingTypography.sectionTitle(context),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) =>
                          _editorContent(context, bounds.maxHeight),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.batchCount > 1)
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('optimize-apply-all'),
                          onPressed: _busy || _error != null
                              ? null
                              : () => _finish(true),
                          child: Text('Apply to All (${widget.batchCount})'),
                        ),
                      AccountingButton.primary(
                        context,
                        key: const ValueKey('optimize-apply'),
                        onPressed: _busy || _error != null
                            ? null
                            : () => _finish(false),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: AccountingPopoutTokens.closeInset,
              right: AccountingPopoutTokens.closeInset,
              child: accountingCompactClose(
                context,
                key: const ValueKey('optimize-cancel'),
                enabled: !_applying,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.bins, this.color);
  final List<int> bins;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final max = bins.fold<int>(1, (a, b) => a > b ? a : b);
    final paint = Paint()..color = color;
    for (var i = 0; i < bins.length; i++) {
      final height = bins[i] / max * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          i * size.width / bins.length,
          size.height - height,
          size.width / bins.length,
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.bins != bins || old.color != color;
}

class _LevelsGradientTrack extends RoundedRectSliderTrackShape {
  const _LevelsGradientTrack();
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()
        ..shader = const LinearGradient(colors: [Colors.black, Colors.white])
            .createShader(rect),
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()
        ..color = const Color(0xFFBDBDBD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5,
    );
  }
}
