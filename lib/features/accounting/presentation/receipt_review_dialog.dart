import 'dart:convert';

import '../../../../app/receipt_destination.dart';
import '../../../../core/documents/receipt_edit_files.dart';
import '../../../../app/naming_setup.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_photo_controls.dart';
import '../../../../app/accounting_crop_editor.dart';
import '../../../../app/accounting_image_zoom.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../core/documents/crop_edit.dart';
import '../../../../core/documents/receipt_document.dart';
import 'receipt_review_queue.dart';
import 'perspective_dialog.dart';
import '../../../../core/documents/document_scan.dart';
import 'document_optimization_dialog.dart';
import '../../../../core/documents/document_vector_trace.dart';
import '../../../../core/documents/document_optimization.dart';

typedef ReceiptReviewAttachmentAction = Future<ReceiptAttachment> Function(
  ReceiptAttachment attachment,
);
typedef ReceiptReviewCropAction = Future<ReceiptAttachment> Function(
  ReceiptAttachment attachment,
  NormalizedCropRect crop,
);
typedef ReceiptReviewSaveAction = Future<void> Function(
  ReceiptAttachment attachment,
);

final class ReceiptReviewDialog extends StatefulWidget {
  const ReceiptReviewDialog({
    required this.queue,
    super.key,
    this.onSave,
    this.setupKind,
    this.editFiles,
    this.destinationDate,
    this.categoryCode = '',
    this.onRetry,
    this.onApplyCrop,
    this.onApplyCropWithRect,
    this.onConvertToPdf,
    this.onFinished,
  });

  final ReceiptReviewQueue queue;
  final SetupKind? setupKind;
  final ReceiptEditFiles? editFiles;
  final DateTime? destinationDate;
  final String categoryCode;
  final ReceiptReviewSaveAction? onSave;
  final ReceiptReviewAttachmentAction? onRetry;
  @Deprecated('Use onApplyCropWithRect for the current crop draft.')
  final ReceiptReviewAttachmentAction? onApplyCrop;
  final ReceiptReviewCropAction? onApplyCropWithRect;
  final ReceiptReviewAttachmentAction? onConvertToPdf;
  final ValueChanged<ReceiptReviewQueue>? onFinished;

  @override
  State<ReceiptReviewDialog> createState() => _ReceiptReviewDialogState();
}

class _ReceiptReviewDialogState extends State<ReceiptReviewDialog> {
  ReceiptEditFiles? _files;
  final Map<String, Uint8List> _previewBytes = {};
  bool _busy = false;
  bool _closePromptOpen = false;
  bool _cropEnabled = true;
  int _previewQuarterTurns = 0;
  ReceiptAttachment? _cropStart;
  String? _toolSection;
  final _editorKey = GlobalKey<DocumentOptimizationDialogState>();
  final _zoom = TransformationController();
  Size _previewViewport = Size.zero;
  void _centerAtMinimum() {
    if (_zoom.value.getMaxScaleOnAxis() <= 1.00001 &&
        _zoom.value != Matrix4.identity()) {
      _zoom.value = Matrix4.identity();
    }
  }

  void _zoomBy(double factor) {
    final current = _zoom.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 5.0);
    if (next <= 1) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final center = Offset(
      _previewViewport.width / 2,
      _previewViewport.height / 2,
    );
    final scene = _zoom.toScene(center);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - scene.dx * next,
        center.dy - scene.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  final Map<String, DocumentOptimizationRecipe> _pendingRecipes = {};
  final Map<String, ReceiptAttachment> _expectedOutputs = {};
  final Set<String> _vectorDrafts = {};
  final Set<String> _pdfDrafts = {};
  final Map<String, ReceiptAttachment> _savedOutputs = {};
  final Map<String, String> _savedStates = {};
  String _editState(ReceiptReviewItem item) {
    final id = item.attachment.originalId;
    return '${item.workingAttachment.derivativeId}|${item.workingAttachment.pdfSha256}|${_pendingRecipes[id]?.toJson()}|${_vectorDrafts.contains(id)}|${_pdfDrafts.contains(id)}|${item.cropHistory.present.stableId}';
  }

  Future<void> _finishSession() async {
    for (final item in widget.queue.items.where((item) => !item.isResolved)) {
      final saved = _savedOutputs[item.attachment.originalId];
      if (saved != null) {
        item.applyWorkingAttachment(saved);
        item.save();
      } else {
        item.discard();
      }
    }
    await _files?.discardAll();
    widget.onFinished?.call(widget.queue);
    if (mounted) Navigator.of(context).pop();
  }

  void _openTool(String section) => setState(() {
    _cropEnabled = false;
    _toolSection = section;
  });
  final CropEditHistory _freshCropHistory = CropEditHistory();
  CropEditHistory get _activeCropHistory =>
      _hasWorkingChange ? _freshCropHistory : _item.cropHistory;
  @override
  void initState() {
    super.initState();
    _zoom.addListener(_centerAtMinimum);
    _cropEnabled = !_hasWorkingChange;
    _cropStart = _attachment;
    for (final item in widget.queue.items) {
      if (item.workingAttachment.derivativeId.contains('-derivative-crop-')) {
        _pendingRecipes[item.workingAttachment.originalId] =
            const DocumentOptimizationRecipe();
      }
    }
    _files =
        widget.editFiles ??
        (widget.setupKind == null ? null : ReceiptEditFiles());
    if (_files != null) {
      _busy = true;
      _prepareFiles();
    }
  }

  Future<void> _prepareFiles() async {
    try {
      await _syncFiles();
    } catch (error) {
      if (mounted) _actionError = 'Unable to prepare receipt: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncFiles() async {
    final files = _files;
    if (files == null) return;
    for (final item in widget.queue.items.where((item) => !item.isResolved)) {
      final id = item.attachment.originalId;
      await files.update(id, item.workingAttachment.preferredBytes);
      _previewBytes[id] = await files.read(id);
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    _freshCropHistory.dispose();
    super.dispose();
  }

  void _startCrop() {
    setState(() {
      _cropStart = _attachment;
      _toolSection = null;
      _toolSection = null;
      _freshCropHistory.reset();
      _cropEnabled = true;
    });
  }

  bool _showRecoveredStatus = false;
  String? _actionError;

  ReceiptReviewItem get _item => widget.queue.current;
  ReceiptAttachment get _attachment => _item.workingAttachment;
  bool get _hasWorkingChange =>
      _item.workingAttachment.derivativeId != _item.attachment.derivativeId;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height - 48;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleClose,
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _handleClose();
          },
          child: Dialog(
            key: const ValueKey('expense-receipt-review-dialog'),
            insetPadding: const EdgeInsets.all(24),
            backgroundColor: tokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: tokens.border),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    AccountingPopoutTokens.customContentWidth +
                    AccountingPopoutTokens.contentInset * 2,
                minHeight: maxHeight,
                maxHeight: maxHeight,
              ),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: 'Receipt Review',
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildHeader(context),
                          const SizedBox(height: 20),
                          Flexible(child: _buildBody(context)),
                        ],
                      ),
                    ),
                    Positioned(
                      top: AccountingPopoutTokens.closeInset,
                      right: AccountingPopoutTokens.closeInset,
                      child: accountingCompactClose(
                        context,
                        key: const ValueKey('receipt-review-close'),
                        enabled: !_busy,
                        onPressed: _handleClose,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final theme = Theme.of(context);
    final queue = widget.queue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                'Receipt Review',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 28),
          ],
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          label:
              'Receipt ${queue.index + 1} of ${queue.totalCount}. ${queue.savedCount} saved, ${queue.skippedCount} skipped, ${queue.remainingCount} remaining.',
          child: Text(
            'Receipt ${queue.index + 1} of ${queue.totalCount}',
            key: const ValueKey('receipt-review-counter'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${queue.savedCount} saved · ${queue.skippedCount} skipped · ${queue.remainingCount} remaining',
          key: const ValueKey('receipt-review-progress'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final attachment = _attachment;
    final isFailed = attachment.status == AttachmentProcessingStatus.failed;
    return LayoutBuilder(
      builder: (context, bodyBounds) => SingleChildScrollView(
        child: _ReceiptPreviewLayout(
          availableHeight: bodyBounds.maxHeight,
          imagePreview: !isFailed && attachment.isImage,
          preview: Container(
            key: const ValueKey('receipt-review-preview'),
            width: double.infinity,
            constraints: isFailed || !attachment.isImage
                ? const BoxConstraints(minHeight: 180, maxHeight: 360)
                : null,
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _buildPreview(context, attachment, isFailed),
          ),
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFooter(context, attachment),
              if (attachment.status != AttachmentProcessingStatus.ready)
                const SizedBox(height: 12),
              if (attachment.status != AttachmentProcessingStatus.ready)
                Semantics(
                  liveRegion: true,
                  label: 'Receipt status ${_statusLabel(attachment)}',
                  child: Text(
                    _statusLabel(attachment),
                    key: const ValueKey('receipt-review-status'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isFailed ? tokens.destructive : tokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (attachment.status != AttachmentProcessingStatus.ready &&
                  attachment.processingMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  attachment.processingMessage!,
                  key: const ValueKey('receipt-review-processing-message'),
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.mutedForeground),
                ),
              ],
              if (attachment.failureMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  attachment.failureMessage!,
                  key: const ValueKey('receipt-review-failure-message'),
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.destructive),
                ),
              ],
              if (_actionError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _actionError!,
                  key: const ValueKey('receipt-review-action-error'),
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.destructive),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ReceiptAttachment attachment) {
    final tokens = AccountingTheme.of(context);
    final filename = _vectorDrafts.contains(attachment.originalId)
        ? attachment.filename.replaceFirst(RegExp(r'\.[^.]+$'), '') +
              (_pdfDrafts.contains(attachment.originalId) ? '.pdf' : '.svg')
        : attachment.filename;
    final metadata = _pendingRecipes.containsKey(attachment.originalId)
        ? (_expectedOutputs[attachment.originalId] == null
              ? 'JPEG · Calculating size…'
              : '${_vectorDrafts.contains(attachment.originalId) ? (_pdfDrafts.contains(attachment.originalId) ? 'PDF' : 'SVG') : 'JPEG'} · ${_formatBytes((_expectedOutputs[attachment.originalId]!.pdfBytes ?? _expectedOutputs[attachment.originalId]!.preferredBytes).length)}')
        : '${_typeLabel(attachment)} · ${_formatBytes((_previewBytes[attachment.originalId] ?? attachment.preferredBytes).length)}';
    final filenameStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: tokens.foreground, fontWeight: FontWeight.w600);
    final metadataStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: tokens.mutedForeground);
    var minimumDetailsWidth = AccountingResponsive.measuredTextWidth(
      context,
      metadata,
      metadataStyle,
    );
    // Preserve full filenames and normal word wrapping. The metadata and the
    // longest filename word set the readable lane; actual actions are measured
    // by the established record layout rather than a screen-width cutoff.
    for (final word in filename.split(RegExp(r'\s+'))) {
      final width = AccountingResponsive.measuredTextWidth(
        context,
        word,
        filenameStyle,
      );
      if (width > minimumDetailsWidth) minimumDetailsWidth = width;
    }
    return AccountingRecordBodyLayout(
      key: const ValueKey('receipt-review-footer'),
      minimumDetailsWidth: minimumDetailsWidth,
      columnGap: accountingContentInset,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            filename,
            key: const ValueKey('receipt-review-filename'),
            softWrap: true,
            style: filenameStyle,
          ),
          const SizedBox(height: 4),
          Text(
            metadata,
            key: const ValueKey('receipt-review-file-metadata'),
            softWrap: true,
            style: metadataStyle,
          ),
        ],
      ),
      actions: _buildActions(context),
    );
  }

  Widget _photoButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) => AccountingPhotoButton(
    key: key,
    icon: icon,
    tooltip: tooltip,
    onPressed: onPressed == null
        ? null
        : () {
            if (_cropEnabled &&
                ![
                  'Crop',
                  'Apply Crop',
                  'Cancel Crop',
                  'Undo',
                  'Redo',
                ].contains(tooltip)) {
              setState(() {
                _activeCropHistory.reset();
                _cropEnabled = false;
              });
            }
            onPressed();
          },
  );

  Widget _buildPreview(
    BuildContext context,
    ReceiptAttachment attachment,
    bool isFailed,
  ) {
    final content = _buildPreviewContent(context, attachment, isFailed);
    if (!attachment.isImage || isFailed) return content;
    return AnimatedBuilder(
      animation: _activeCropHistory,
      builder: (context, _) => LayoutBuilder(
        builder: (context, bounds) {
          _previewViewport = bounds.biggest;
          const count = 8;
          final toolbarHeight =
              count * AccountingPhotoButton.extent +
              (count - 1) * 4 +
              10.2 +
              14.2;
          final top = ((bounds.maxHeight - toolbarHeight) / 2).clamp(
            12.0,
            bounds.maxHeight,
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Stack(
                    children: [
                      Offstage(
                        offstage: _cropEnabled,
                        child: DocumentOptimizationDialog(
                          key: _editorKey,
                          attachment: attachment,
                          transformationController: _zoom,
                          vectorPreview: _vectorDrafts.contains(
                            attachment.originalId,
                          ),
                          vectorPdf: _pdfDrafts.contains(attachment.originalId),
                          previewQuarterTurns: _previewQuarterTurns,
                          initialRecipe:
                              _pendingRecipes[attachment.originalId] ??
                              const DocumentOptimizationRecipe(),
                          batchCount: widget.queue.totalCount,
                          section: _toolSection,
                          onClosePanel: () =>
                              setState(() => _toolSection = null),
                          onRecipeChanged: (recipe) => setState(
                            () =>
                                _pendingRecipes[attachment.originalId] = recipe,
                          ),
                          onOutputChanged: (result) {
                            if (!mounted) return;
                            setState(() {
                              if (result == null) {
                                _expectedOutputs.remove(attachment.originalId);
                              } else {
                                _expectedOutputs[attachment.originalId] =
                                    result;
                              }
                            });
                          },
                        ),
                      ),
                      if (_cropEnabled)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ColoredBox(
                              color: AccountingTheme.of(context).muted,
                              child: AccountingImageZoom(
                                transformationController: _zoom,
                                minScale: 1,
                                maxScale: 5,
                                panEnabled: false,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 72,
                                  ),
                                  child: Center(child: content),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  top: top,
                  child: Container(
                    key: const ValueKey('receipt-left-toolbar'),
                    constraints: BoxConstraints(
                      maxHeight: (bounds.maxHeight - top - 12).clamp(
                        0.0,
                        bounds.maxHeight,
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: AccountingTheme.of(context).card,
                      borderRadius: BorderRadius.circular(15.3),
                      border: Border.all(
                        color: AccountingTheme.of(context).border,
                      ),
                    ),
                    padding: const EdgeInsets.all(5.1),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-start-crop'),
                            icon: Icons.crop,
                            tooltip: 'Crop',
                            onPressed: _busy || _item.isResolved
                                ? null
                                : _startCrop,
                          ),
                          const SizedBox(height: 4),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-perspective'),
                            icon: Icons.transform,
                            tooltip: 'Perspective',
                            onPressed: _busy ? null : _perspective,
                          ),
                          const SizedBox(height: 4),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-rotate'),
                            icon: Icons.rotate_right,
                            tooltip: 'Rotate 90°',
                            onPressed: _busy || _item.isResolved
                                ? null
                                : _rotateCurrent,
                          ),
                          const SizedBox(height: 4),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-optimize'),
                            icon: Icons.auto_fix_high,
                            tooltip: 'Optimize',
                            onPressed: _busy || _item.isResolved
                                ? null
                                : () => _quickOptimize(),
                          ),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-clean-scan'),
                            icon: Icons.document_scanner_outlined,
                            tooltip: 'Clean Scan',
                            onPressed: _busy ? null : () => _cleanScan(),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 27.2,
                            height: 18.2,
                            child: Divider(
                              height: 18.2,
                              thickness: 1,
                              color: AccountingTheme.of(context).border,
                            ),
                          ),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-contrast'),
                            icon: Icons.contrast,
                            tooltip: 'Contrast',
                            onPressed:
                                _busy ||
                                    (attachment
                                            .optimizationRecipe?['vectorTrace'] !=
                                        null)
                                ? null
                                : () => _openTool('Contrast'),
                          ),
                          const SizedBox(height: 4),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-levels'),
                            icon: Icons.tune,
                            tooltip: 'Levels',
                            onPressed: _busy ? null : () => _openTool('Levels'),
                          ),
                          const SizedBox(height: 4),
                          _photoButton(
                            context,
                            key: const ValueKey('receipt-review-trace'),
                            icon: Icons.polyline_outlined,
                            tooltip: 'Vectorize',
                            onPressed: _busy || _item.isResolved
                                ? null
                                : _trace,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: top,
                  child: ConstrainedBox(
                    key: const ValueKey('receipt-right-toolbar-viewport'),
                    constraints: BoxConstraints(
                      maxHeight:
                          (bounds.maxHeight -
                                  top -
                                  12 -
                                  (_cropEnabled
                                      ? AccountingPhotoButton.extent + 4
                                      : 0))
                              .clamp(0.0, bounds.maxHeight),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        key: const ValueKey('receipt-right-toolbar'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            key: const ValueKey('receipt-history-toolbar'),
                            decoration: BoxDecoration(
                              color: AccountingTheme.of(context).card,
                              borderRadius: BorderRadius.circular(15.3),
                              border: Border.all(
                                color: AccountingTheme.of(context).border,
                              ),
                            ),
                            padding: const EdgeInsets.all(5.1),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _photoButton(
                                  context,
                                  key: const ValueKey('accounting-crop-undo'),
                                  icon: Icons.undo_rounded,
                                  tooltip: 'Undo',
                                  onPressed:
                                      _busy ||
                                          !((_editorKey.currentState?.canUndo ??
                                                  false) ||
                                              (_cropEnabled &&
                                                  _hasWorkingChange &&
                                                  _freshCropHistory.canUndo) ||
                                              _item.canUndoLatest)
                                      ? null
                                      : () => _run(() async {
                                          if (!_cropEnabled &&
                                              (_editorKey
                                                      .currentState
                                                      ?.canUndo ??
                                                  false)) {
                                            _editorKey.currentState!.undo();
                                          } else if (_cropEnabled &&
                                              _hasWorkingChange &&
                                              _freshCropHistory.canUndo) {
                                            _freshCropHistory.undo();
                                          } else {
                                            _item.undoLatest();
                                          }
                                        }),
                                ),
                                const SizedBox(height: 4),
                                _photoButton(
                                  context,
                                  key: const ValueKey('accounting-crop-redo'),
                                  icon: Icons.redo_rounded,
                                  tooltip: 'Redo',
                                  onPressed:
                                      _busy ||
                                          !((_editorKey.currentState?.canRedo ??
                                                  false) ||
                                              (_cropEnabled &&
                                                  _hasWorkingChange &&
                                                  _freshCropHistory.canRedo) ||
                                              _item.canRedoLatest)
                                      ? null
                                      : () => _run(() async {
                                          if (!_cropEnabled &&
                                              (_editorKey
                                                      .currentState
                                                      ?.canRedo ??
                                                  false)) {
                                            _editorKey.currentState!.redo();
                                          } else if (_cropEnabled &&
                                              _hasWorkingChange &&
                                              _freshCropHistory.canRedo) {
                                            _freshCropHistory.redo();
                                          } else {
                                            _item.redoLatest();
                                          }
                                        }),
                                ),
                                const SizedBox(height: 4),
                                _photoButton(
                                  context,
                                  key: const ValueKey(
                                    'receipt-review-cancel-crop',
                                  ),
                                  icon: Icons.restart_alt,
                                  tooltip: 'Reset',
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          _editorKey.currentState?.reset();
                                          _vectorDrafts.remove(
                                            _attachment.originalId,
                                          );
                                          _pdfDrafts.remove(
                                            _attachment.originalId,
                                          );
                                          _cropEnabled = false;
                                          _activeCropHistory.reset();
                                          _pendingRecipes.remove(
                                            _attachment.originalId,
                                          );
                                          _expectedOutputs.remove(
                                            _attachment.originalId,
                                          );
                                          _zoom.value = Matrix4.identity();
                                          _cancelCrop();
                                        },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: toolbarHeight - 260.8),
                          Container(
                            key: const ValueKey('receipt-zoom-toolbar'),
                            decoration: BoxDecoration(
                              color: AccountingTheme.of(context).card,
                              borderRadius: BorderRadius.circular(15.3),
                              border: Border.all(
                                color: AccountingTheme.of(context).border,
                              ),
                            ),
                            padding: const EdgeInsets.all(5.1),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _photoButton(
                                  context,
                                  key: const ValueKey('receipt-zoom-in'),
                                  icon: Icons.zoom_in,
                                  tooltip: 'Zoom In',
                                  onPressed: () => _zoomBy(1.25),
                                ),
                                const SizedBox(height: 4),
                                _photoButton(
                                  context,
                                  key: const ValueKey('receipt-zoom-out'),
                                  icon: Icons.zoom_out,
                                  tooltip: 'Zoom Out',
                                  onPressed: () => _zoomBy(.8),
                                ),
                                const SizedBox(height: 4),
                                _photoButton(
                                  context,
                                  key: const ValueKey('receipt-zoom-fit'),
                                  icon: Icons.fit_screen,
                                  tooltip: 'Zoom to Fit',
                                  onPressed: () =>
                                      _zoom.value = Matrix4.identity(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_cropEnabled)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _photoButton(
                          context,
                          key: const ValueKey('receipt-review-dismiss-crop'),
                          icon: Icons.close,
                          tooltip: 'Cancel Crop',
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  if (_cropStart case final previous?) {
                                    if (previous.derivativeId !=
                                        _attachment.derivativeId) {
                                      _item.applyWorkingAttachment(previous);
                                    }
                                  }
                                  _activeCropHistory.reset();
                                  _cropEnabled = false;
                                  _toolSection = null;
                                  _zoom.value = Matrix4.identity();
                                }),
                        ),
                        const SizedBox(width: 4),
                        _photoButton(
                          context,
                          key: const ValueKey('receipt-review-apply-crop'),
                          icon: Icons.check,
                          tooltip: 'Apply Crop',
                          onPressed: _busy || _item.isResolved
                              ? null
                              : _applyCrop,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewContent(
    BuildContext context,
    ReceiptAttachment attachment,
    bool isFailed,
  ) {
    final tokens = AccountingTheme.of(context);
    if (isFailed) {
      return Center(
        child: Icon(
          attachment.isPdf
              ? Icons.picture_as_pdf_outlined
              : Icons.broken_image_outlined,
          size: 48,
          color: tokens.destructive,
          semanticLabel: 'Receipt preview unavailable',
        ),
      );
    }
    if (!_cropEnabled && attachment.isImage) {
      return AccountingEditedRotationPreview(
        key: ValueKey(attachment.derivativeId),
        bytes:
            _previewBytes[attachment.originalId] ?? attachment.preferredBytes,
        width: attachment.derivativeWidth ?? attachment.originalWidth ?? 1,
        height: attachment.derivativeHeight ?? attachment.originalHeight ?? 1,
        maxHeight: double.infinity,
        onRotate: (angle) {
          if (_busy || _item.isResolved || angle == 0) return;
          _run(() async {
            final rotated = await const ReceiptDocumentPipeline().crop(
              attachment,
              NormalizedCropRect(
                left: 0,
                top: 0,
                right: 1,
                bottom: 1,
                rotation: angle,
              ),
            );
            _item.applyWorkingAttachment(rotated);
          });
        },
      );
    }
    if (attachment.isImage) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Crop frame',
        child: AccountingCropReviewEditor(
          showHistoryControls: false,
          previewImage: _editorKey.currentState?.buildCropPreview(),
          imageBytes:
              _previewBytes[attachment.originalId] ?? attachment.preferredBytes,
          cropHistory: _activeCropHistory,
          imageWidth:
              attachment.derivativeWidth ?? attachment.originalWidth ?? 1,
          imageHeight:
              attachment.derivativeHeight ?? attachment.originalHeight ?? 1,
          maxPreviewHeight: double.infinity,
          exposeFrameSemantics: false,
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            attachment.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.description_outlined,
            size: 48,
            color: tokens.mutedForeground,
            semanticLabel: '${_typeLabel(attachment)} preview',
          ),
          const SizedBox(height: 8),
          Text(
            attachment.isPdf
                ? 'PDF preview is available after saving.'
                : 'Document preview is not available for this file type.',
            textAlign: TextAlign.center,
            softWrap: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final queue = widget.queue;
    final attachment = _attachment;
    final isReady = attachment.status == AttachmentProcessingStatus.ready;
    final isFailed = attachment.status == AttachmentProcessingStatus.failed;
    final canSave = isReady && !queue.current.isResolved && !_busy;
    final canMove = !_busy;
    final actionChildren = <Widget>[
      if (queue.totalCount > 1)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-review-previous'),
          onPressed: canMove && queue.index > 0 ? _previous : null,
          leadingIcon: Icons.chevron_left_rounded,
          child: const Text('Previous'),
        ),
      if (queue.totalCount > 1)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-review-next'),
          onPressed: canMove && queue.index < queue.totalCount - 1
              ? _next
              : null,
          leadingIcon: Icons.chevron_right_rounded,
          child: const Text('Next'),
        ),
      if (queue.items.where((item) => item.workingAttachment.isImage).length >
          1)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-review-batch-optimize'),
          onPressed: _busy ? null : () => _quickOptimize(all: true),
          child: const Text('Optimize All'),
        ),
      if (attachment.canConvertToPdf &&
          attachment.pdfBytes == null &&
          !queue.current.isResolved)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-review-convert-pdf'),
          onPressed: _busy ? null : _convertToPdf,
          child: const Text('Convert to PDF'),
        ),
      if (isFailed)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-review-retry'),
          onPressed: _busy ? null : _retry,
          child: const Text('Retry'),
        ),
      AccountingButton.outline(
        context,
        key: const ValueKey('receipt-review-skip'),
        onPressed: _busy || queue.current.isResolved ? null : _skip,
        child: const Text('Skip'),
      ),
      if (queue.items.where((item) => item.workingAttachment.isImage).length >
          1)
        AccountingButton.outline(
          context,
          key: const ValueKey('receipt-clean-scan-all'),
          onPressed: _busy ? null : () => _cleanScan(all: true),
          child: const Text('Clean Scan All'),
        ),
      AccountingButton.primary(
        context,
        key: const ValueKey('receipt-review-save'),
        onPressed: canSave ? _save : null,
        child: const Text('Save'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: actionChildren,
        ),
        if (queue.remainingCount > 1) ...<Widget>[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: AccountingButton.ghost(
              context,
              key: const ValueKey('receipt-review-skip-all'),
              onPressed: _busy ? null : _skipAll,
              child: const Text('Skip All'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_busy ||
        !_item.isResolved &&
            _attachment.status != AttachmentProcessingStatus.ready) {
      return;
    }
    if (widget.setupKind case final kind?) {
      if (!await openNamingSetup(context, kind: kind, onlyIfMissing: true)) {
        return;
      }
      if (!mounted) return;
    }
    await _run(() async {
      var attachment = _attachment;
      final pending = _pendingRecipes[_attachment.originalId];
      if (pending != null) {
        var processed =
            _expectedOutputs[_attachment.originalId] ??
            await const DocumentOptimizationEngine().optimize(
              _attachment,
              pending,
            );
        if (_vectorDrafts.contains(_attachment.originalId) &&
            processed.optimizationRecipe?['vectorTrace'] == null) {
          final trace = await DocumentVectorTrace().trace(
            processed.preferredBytes,
            const DocumentTraceSettings(),
          );
          processed = trace
              .attachTo(
                processed,
                asPdf: _pdfDrafts.contains(_attachment.originalId),
              )
              .withOptimizationRecipe({
                ...pending.toJson(),
                'vectorTrace': const DocumentTraceSettings().toJson(),
                'vectorPreviewPng': base64Encode(trace.preview),
              });
        }
        attachment = processed;
      }
      final files = _files;
      if (files != null) {
        await files.update(
          attachment.originalId,
          attachment.pdfBytes ?? attachment.preferredBytes,
        );
        await files.save(attachment.originalId, (bytes) async {
          if (widget.setupKind case final kind?) {
            final date = widget.destinationDate;
            if (date == null) {
              throw StateError('Enter a valid record date before saving.');
            }
            await saveReceiptDestination(
              kind: kind,
              attachmentId: attachment.originalId,
              date: date,
              categoryCode: widget.categoryCode,
              mimeType: attachment.pdfBytes != null
                  ? 'application/pdf'
                  : attachment.preferredMimeType,
              bytes: bytes,
            );
          }
          await widget.onSave?.call(attachment);
        });
      } else {
        await widget.onSave?.call(attachment);
      }
      _savedOutputs[attachment.originalId] = attachment;
      _savedStates[attachment.originalId] = _editState(_item);
      _showRecoveredStatus = false;
    });
  }

  Future<void> _retry() async {
    await _run(() async {
      final action = widget.onRetry ?? _defaultRetry;
      final recovered = await action(_attachment);
      widget.queue.applyWorkingAttachment(recovered);
      _showRecoveredStatus =
          recovered.status == AttachmentProcessingStatus.ready;
    });
  }

  Future<void> _trace() async {
    setState(() {
      if (!_vectorDrafts.add(_attachment.originalId)) {
        _vectorDrafts.remove(_attachment.originalId);
      }
      _pendingRecipes[_attachment.originalId] =
          _pendingRecipes[_attachment.originalId] ??
          const DocumentOptimizationRecipe();
      _cropEnabled = false;
      _toolSection = null;
    });
  }

  Future<void> _perspective() async {
    final source = _expectedOutputs[_attachment.originalId] ?? _attachment;
    ScanCorners? detected;
    await _run(() async {
      detected = await DocumentScan.detect(source.preferredBytes);
    });
    if (!mounted) return;
    final corners = await showDialog<ScanCorners>(
      context: context,
      builder: (_) => PerspectiveDialog(
        bytes: source.preferredBytes,
        width: source.derivativeWidth ?? source.originalWidth ?? 1,
        height: source.derivativeHeight ?? source.originalHeight ?? 1,
        corners: detected,
      ),
    );
    if (corners == null) return;
    await _run(() async {
      final pixels = await DocumentScan.rectify(source.preferredBytes, corners);
      final result = await const DocumentOptimizationEngine().render(
        pixels,
        const DocumentOptimizationRecipe(),
      );
      _acceptScan(_item, result);
    });
  }

  void _acceptScan(ReceiptReviewItem item, DocumentOptimizationResult result) {
    final current = item.workingAttachment;
    item.applyWorkingAttachment(
      current.withDerivative(
        derivativeId:
            '${current.originalId}-derivative-edit-scan-${DateTime.now().microsecondsSinceEpoch}',
        bytes: result.jpeg,
        mimeType: 'image/jpeg',
        width: result.width,
        height: result.height,
        printReadyAt300Dpi: false,
        processingMessage: null,
      ),
    );
    _pendingRecipes.remove(current.originalId);
    _expectedOutputs.remove(current.originalId);
    _cropEnabled = false;
  }

  Future<void> _cleanScan({bool all = false}) async {
    if (_busy) return;
    setState(() {
      _cropEnabled = false;
      _toolSection = null;
    });
    final navigator = Navigator.of(context);
    bool progressOpen = false;
    void progress() {
      progressOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const ReceiptProcessingNotice(message: 'Cleaning scan…'),
      );
    }

    progress();
    await WidgetsBinding.instance.endOfFrame;
    await _run(() async {
      for (final item in (all ? widget.queue.items : [_item]).where(
        (i) => !i.isResolved && i.workingAttachment.isImage,
      )) {
        final source =
            _expectedOutputs[item.workingAttachment.originalId] ??
            item.workingAttachment;
        var corners = await DocumentScan.detect(source.preferredBytes);
        if (corners == null) {
          navigator.pop();
          progressOpen = false;
          if (!mounted) return;
          corners = await showDialog<ScanCorners>(
            context: context,
            builder: (_) => PerspectiveDialog(
              bytes: source.preferredBytes,
              width: source.derivativeWidth ?? source.originalWidth ?? 1,
              height: source.derivativeHeight ?? source.originalHeight ?? 1,
            ),
          );
          if (!mounted) return;
          progress();
          await WidgetsBinding.instance.endOfFrame;
          if (corners == null) continue;
        }
        final pixels = await DocumentScan.rectify(
          source.preferredBytes,
          corners,
          clean: true,
        );
        final result = await const DocumentOptimizationEngine().render(
          pixels,
          const DocumentOptimizationRecipe(automaticCompression: true),
        );
        _acceptScan(item, result);
      }
    });
    if (mounted && progressOpen) navigator.pop();
  }

  Future<void> _quickOptimize({bool all = false}) async {
    if (_busy) return;
    setState(() {
      _cropEnabled = false;
      _activeCropHistory.reset();
      _toolSection = null;
    });
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReceiptProcessingNotice(message: 'Optimizing…'),
    );
    await WidgetsBinding.instance.endOfFrame;
    await _run(() async {
      final targets = (all ? widget.queue.items : [_item])
          .where(
            (item) =>
                !item.isResolved &&
                item.workingAttachment.isImage &&
                item.workingAttachment.status ==
                    AttachmentProcessingStatus.ready,
          )
          .toList();
      final results = <ReceiptReviewItem, ReceiptAttachment>{};
      for (final item in targets) {
        final current = item.workingAttachment;
        final result = await const DocumentOptimizationEngine().render(
          current.preferredBytes,
          (_pendingRecipes[current.originalId] ??
                  const DocumentOptimizationRecipe())
              .copyWith(automaticCompression: true),
        );
        if (result.compression?.meetsQualityFloor != true ||
            result.jpeg.length >= current.preferredBytes.length) {
          continue;
        }
        results[item] = current.withDerivative(
          derivativeId:
              '${current.originalId}-derivative-edit-size-${DateTime.now().microsecondsSinceEpoch}',
          bytes: result.jpeg,
          mimeType: 'image/jpeg',
          width: result.width,
          height: result.height,
          printReadyAt300Dpi:
              (result.width >= 2480 && result.height >= 3508) ||
              (result.width >= 3508 && result.height >= 2480),
          processingMessage: null,
        );
      }
      for (final entry in results.entries) {
        entry.key.applyWorkingAttachment(entry.value);
        _pendingRecipes.remove(entry.value.originalId);
        _expectedOutputs.remove(entry.value.originalId);
      }
      _cropEnabled = false;
    });
    if (mounted) navigator.pop();
  }

  Future<void> _rotateCurrent() async {
    if (_busy) return;
    final wasCropping = _cropEnabled;
    setState(() {
      _previewQuarterTurns = 1;
      _cropEnabled = false;
      _zoom.value = Matrix4.identity();
    });
    await _run(() async {
      final rotated = await const ReceiptDocumentPipeline().rotateQuarterTurn(
        _attachment,
      );
      _item.applyWorkingAttachment(rotated);
      _pendingRecipes.putIfAbsent(
        rotated.originalId,
        () => const DocumentOptimizationRecipe(),
      );
      _expectedOutputs.remove(rotated.originalId);
      _freshCropHistory.reset();
    });
    if (mounted) {
      setState(() {
        _previewQuarterTurns = 0;
        _cropEnabled = wasCropping;
      });
    }
  }

  Future<void> _applyCrop() async {
    if (!_cropEnabled) return;
    await _run(() async {
      final cropped = widget.onApplyCropWithRect != null
          ? await widget.onApplyCropWithRect!.call(
              _attachment,
              _activeCropHistory.present,
            )
          : widget.onApplyCrop != null
          ? await widget.onApplyCrop!.call(_attachment)
          : await _defaultCrop(_attachment, _activeCropHistory.present);
      widget.queue.applyWorkingAttachment(cropped);
      _pendingRecipes.putIfAbsent(
        cropped.originalId,
        () => const DocumentOptimizationRecipe(),
      );
      _expectedOutputs.remove(cropped.originalId);
      _cropEnabled = false;
      _showRecoveredStatus = false;
    });
  }

  Future<void> _convertToPdf() async {
    if (_vectorDrafts.contains(_attachment.originalId)) {
      setState(() {
        _pdfDrafts.add(_attachment.originalId);
        _expectedOutputs.remove(_attachment.originalId);
      });
      return;
    }
    await _run(() async {
      final action = widget.onConvertToPdf ?? _defaultConvertToPdf;
      final converted = await action(_attachment);
      widget.queue.applyWorkingAttachment(converted);
      _showRecoveredStatus = false;
    });
  }

  void _cancelCrop() {
    _run(() async {
      widget.queue.cancelWorkingAttachment();
      _showRecoveredStatus = false;
      _actionError = null;
    });
  }

  void _skip() {
    if (_busy || widget.queue.current.isResolved) return;
    setState(() {
      widget.queue.markSkipped();
      _actionError = null;
      _showRecoveredStatus = false;
      if (!widget.queue.moveToNextUnresolved() && widget.queue.isComplete) {
        widget.onFinished?.call(widget.queue);
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _skipAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        title: 'Skip all receipts?',
        content: const Text(
          'Every unresolved receipt will remain available in the form but will not be saved as an attachment.',
        ),
        actions: <Widget>[
          AccountingButton.ghost(
            dialogContext,
            key: const ValueKey('receipt-review-cancel-skip-all'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Editing'),
          ),
          AccountingButton.primary(
            dialogContext,
            key: const ValueKey('receipt-review-confirm-skip-all'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Skip All'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        widget.queue.skipAll(confirmed: true);
        _showRecoveredStatus = false;
      });
      widget.onFinished?.call(widget.queue);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _previous() {
    if (!widget.queue.movePrevious()) return;
    setState(() {
      _actionError = null;
      _showRecoveredStatus = false;
    });
  }

  void _next() {
    if (!widget.queue.moveNext()) return;
    setState(() {
      _actionError = null;
      _showRecoveredStatus = false;
    });
  }

  Future<void> _handleClose() async {
    if (_busy || _closePromptOpen) return;
    if (widget.queue.items
        .where((item) => !item.isResolved)
        .every(
          (item) =>
              _savedStates[item.attachment.originalId] == _editState(item),
        )) {
      await _finishSession();
      return;
    }
    _closePromptOpen = true;
    try {
      final leave = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('receipt-review-discard-close'),
        keepEditingKey: const ValueKey('receipt-review-keep-reviewing'),
        discardKey: const ValueKey('receipt-review-leave-review'),
      );
      if (leave && mounted) {
        await _run(() async {
          await _finishSession();
        });
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      await _syncFiles();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _actionError = 'Receipt action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ReceiptAttachment> _defaultRetry(ReceiptAttachment attachment) {
    return const ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: attachment.originalId,
        batchId: attachment.batchId,
        filename: attachment.filename,
        mimeType: attachment.originalMimeType,
        bytes: attachment.originalBytes,
      ),
    );
  }

  Future<ReceiptAttachment> _defaultCrop(
    ReceiptAttachment attachment,
    NormalizedCropRect crop,
  ) {
    return const ReceiptDocumentPipeline().crop(
      attachment,
      crop,
      sourceBytes: attachment.preferredBytes,
    );
  }

  Future<ReceiptAttachment> _defaultConvertToPdf(ReceiptAttachment attachment) {
    return const ReceiptDocumentPipeline().convertToPdf(attachment);
  }

  String _statusLabel(ReceiptAttachment attachment) {
    if (_showRecoveredStatus &&
        attachment.status == AttachmentProcessingStatus.ready) {
      return 'Ready';
    }
    if (attachment.status == AttachmentProcessingStatus.failed) return 'Failed';
    if (attachment.isPdf) return 'PDF ready';
    return 'Preview ready';
  }

  String _typeLabel(ReceiptAttachment attachment) {
    final mime = attachment.preferredMimeType.toLowerCase();
    if (mime == 'application/pdf') return 'PDF';
    if (mime == 'application/msword') return 'DOC';
    if (mime ==
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return 'DOCX';
    }
    if (mime == 'image/png') return 'PNG';
    if (mime == 'image/svg+xml') return 'SVG';
    if (mime == 'image/heic' || mime == 'image/heif') return 'HEIC';
    return 'JPEG';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
}

/// Keep this custom media owner's existing footer and scrolling behavior. The
/// rendered footer (including wrapped actions, filename and triggered notices)
/// owns its height; the image uses the space actually left in the viewport.
class _ReceiptPreviewLayout extends MultiChildRenderObjectWidget {
  _ReceiptPreviewLayout({
    required Widget preview,
    required Widget footer,
    required this.availableHeight,
    required this.imagePreview,
  }) : super(children: [preview, footer]);

  final double availableHeight;
  final bool imagePreview;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReceiptPreview(availableHeight, imagePreview);

  @override
  void updateRenderObject(BuildContext context, _RenderReceiptPreview object) {
    if (object.availableHeight == availableHeight &&
        object.imagePreview == imagePreview) {
      return;
    }
    object.availableHeight = availableHeight;
    object.imagePreview = imagePreview;
    object.markNeedsLayout();
  }
}

class _ReceiptPreviewParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderReceiptPreview extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderReceiptPreview(this.availableHeight, this.imagePreview);
  double availableHeight;
  bool imagePreview;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _ReceiptPreviewParentData();
    }
  }

  @override
  void performLayout() {
    final preview = firstChild!, footer = lastChild!;
    final width = constraints.maxWidth;
    // Do not query intrinsic heights through the footer's LayoutBuilder.
    footer.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    preview.layout(
      BoxConstraints.tightFor(
        width: width,
        height: imagePreview
            ? (availableHeight - footer.size.height - 16).clamp(120.0, 1200.0)
            : null,
      ),
      parentUsesSize: true,
    );
    (preview.parentData as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    (footer.parentData as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      preview.size.height + 16,
    );
    size = constraints.constrain(
      Size(width, preview.size.height + 16 + footer.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Blocking receipt processing, using the standard accounting notice shell.
class ReceiptProcessingNotice extends StatelessWidget {
  const ReceiptProcessingNotice({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.dialog,
      key: const ValueKey('receipt-processing-notice'),
      title: message,
      closeKey: const ValueKey('receipt-processing-close'),
      canClose: false,
      content: Semantics(
        liveRegion: true,
        label: message,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      actions: const [],
    ),
  );
}
