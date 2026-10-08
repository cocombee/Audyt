import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_image_zoom.dart';

Future<void> showAttachmentPreview(
  BuildContext context,
  ReceiptAttachment attachment,
) => showDialog<void>(
  context: context,
  builder: (_) => AttachmentPreviewDialog(attachment: attachment),
);

class AttachmentPreviewDialog extends StatefulWidget {
  const AttachmentPreviewDialog({
    super.key,
    required this.attachment,
    this.embedded = false,
    this.originalOnly = false,
  });
  final ReceiptAttachment attachment;
  final bool embedded, originalOnly;
  @override
  State<AttachmentPreviewDialog> createState() =>
      _AttachmentPreviewDialogState();
}

class _AttachmentPreviewDialogState extends State<AttachmentPreviewDialog> {
  int _page = 0, _pages = 1;
  bool _filedCopy = false;
  late bool _previewIsPdf = widget.attachment.isPdf;
  Uint8List? _linkedBytes;
  Uint8List? _bytes;
  Size? _imageSize;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final attachment = widget.attachment;
      final output = widget.originalOnly
          ? attachment.originalBytes
          : attachment.preferredBytes;
      final expectedHash = widget.originalOnly
          ? attachment.originalSha256
          : attachment.filedSha256;
      if (output.isEmpty && _linkedBytes == null) {
        final linked = await const MethodChannel('audyt/naming-settings')
            .invokeMapMethod<String, dynamic>('readDocument', {
              'attachmentId': attachment.originalId,
              'expectedSha256': expectedHash,
            });
        if (linked == null) {
          throw StateError('The linked document is unavailable.');
        }
        final bytes = linked['bytes'] as Uint8List;
        if (sha256.convert(bytes).toString() != expectedHash) {
          throw PlatformException(
            code: 'document_version_unavailable',
            message: 'The filed document does not match this saved record version. Reconnect the matching file.',
          );
        }
        _linkedBytes = bytes;
        _previewIsPdf = linked['mimeType'] == 'application/pdf';
        _filedCopy = true;
      }
      if (_previewIsPdf) {
        final result = await const MethodChannel('audyt/document-preview')
            .invokeMapMethod<String, dynamic>('pdfPage', {
              'bytes': _linkedBytes ?? attachment.originalBytes,
              'page': _page,
            });
        if (!mounted) return;
        if (result == null) throw StateError('Preview unavailable');
        _bytes = result['bytes'] as Uint8List;
        _pages = result['pages'] as int;
      } else if (attachment.isImage) {
        _bytes = _linkedBytes ?? output;
      } else {
        throw StateError('This file type cannot be previewed.');
      }
      final codec = await ui.instantiateImageCodec(_bytes!);
      try {
        final frame = await codec.getNextFrame();
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      _error = error is PlatformException && error.message != null
          ? error.message!
          : 'Unable to preview this file. It may be unavailable, damaged, or password protected.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    // Dialog routes capture caller text themes. The standalone viewer owns its
    // body text so a voucher helper scope cannot change a document's notice.
    style: AccountingTypography.value(context),
    child: LayoutBuilder(
      builder: (context, constraints) => _buildPreview(context, constraints),
    ),
  );

  Widget _mediaPreview(
    BuildContext context,
    Size fitted, {
    required bool showClose,
  }) => Center(
    child: SizedBox(
      width: fitted.width,
      height: fitted.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(accountingSectionRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: AccountingImageZoom(
                key: ValueKey('attachment-preview-zoom-page-$_page'),
                child: Image.memory(
                  _bytes!,
                  key: const ValueKey('attachment-image-preview'),
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) =>
                      const Text('This image cannot be displayed.'),
                ),
              ),
            ),
            if (showClose)
              Positioned(
                top: AccountingPopoutTokens.closeInset,
                right: AccountingPopoutTokens.closeInset,
                child: accountingCompactClose(context),
              ),
            if (_filedCopy)
              Positioned(
                bottom: _previewIsPdf && _pages > 1 ? 64 : 8,
                left: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AccountingTheme.of(context).card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Linked filed copy · original evidence remains outside this data archive.',
                    ),
                  ),
                ),
              ),
            if (_previewIsPdf && _pages > 1)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AccountingTheme.of(context).card,
                      border: Border.all(
                        color: AccountingTheme.of(context).border,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AccountingButton.outline(
                            context,
                            key: null,
                            onPressed: _page == 0
                                ? null
                                : () {
                                    _page--;
                                    _load();
                                  },
                            child: const Text('Previous'),
                          ),
                          Text('Page ${_page + 1} Of $_pages'),
                          AccountingButton.outline(
                            context,
                            key: null,
                            onPressed: _page + 1 >= _pages
                                ? null
                                : () {
                                    _page++;
                                    _load();
                                  },
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _controlFitPreview(BuildContext context, double fitScale) {
    final title = TextPainter(
      text: TextSpan(
        text: widget.attachment.filename,
        style: AccountingTypography.sectionTitle(context),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final headerWidth =
        title.width + AccountingPopoutTokens.titleTrailingReserve;
    title.dispose();
    // Reuse the accepted document preview shell only when source aspect ratio
    // makes an inset overlay impossible at any viewport-fitting scale.
    return AccountingDialog.fitted(
      context,
      key: const ValueKey('attachment-control-fit-dialog'),
      title: widget.attachment.filename,
      preserveTitleCase: true,
      maxContentWidth: math.max(_imageSize!.width * fitScale, headerWidth),
      contentBuilder: (context, available) {
        final scale = math.min(
          fitScale,
          math.min(
            available.width / _imageSize!.width,
            available.height / _imageSize!.height,
          ),
        );
        final fitted = Size(
          _imageSize!.width * scale,
          _imageSize!.height * scale,
        );
        return SizedBox(
          width: available.width,
          height: fitted.height,
          child: _mediaPreview(context, fitted, showClose: false),
        );
      },
    );
  }

  Widget _buildPreview(BuildContext context, BoxConstraints constraints) {
    if ((widget.attachment.isImage || widget.attachment.isPdf) &&
        !_loading &&
        _error == null &&
        _imageSize != null) {
      final viewport = MediaQuery.sizeOf(context);
      final availableWidth = widget.embedded && constraints.hasBoundedWidth
          ? constraints.maxWidth
          : viewport.width;
      final fitScale = math.min(
        (availableWidth - 48) / _imageSize!.width,
        (viewport.height - 48) / _imageSize!.height,
      );
      // Preserve tiny files at their actual size; fit ordinary documents to
      // the available popout area while retaining their source aspect ratio.
      final scale = widget.attachment.isImage && _imageSize!.longestSide < 400
          ? math.min(1.0, fitScale)
          : fitScale;
      if (!widget.embedded) {
        // The existing Close allocation and its two edge insets must fit
        // inside the clipped media. Do not enlarge native-sized small images
        // to make room for a control; reuse the fitted document shell instead.
        final controlScale =
            (AccountingPopoutTokens.closeInset * 2 +
                AccountingDismissIcon.controlExtent) /
            _imageSize!.shortestSide;
        if (controlScale > scale) {
          return _controlFitPreview(context, scale);
        }
      }
      final fitted = Size(
        _imageSize!.width * scale,
        _imageSize!.height * scale,
      );
      return _mediaPreview(context, fitted, showClose: !widget.embedded);
    }
    final message = _loading
        ? const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          )
        : Text(_error ?? 'This file cannot be previewed.');
    if (!widget.embedded) {
      return AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        key: const ValueKey('attachment-preview-notice'),
        title: widget.attachment.filename,
        preserveTitleCase: true,
        closeKey: const ValueKey('attachment-preview-notice-close'),
        maxContentWidth: AccountingPopoutTokens.dialogContentWidth,
        fixedContentWidth: AccountingPopoutTokens.dialogContentWidth,
        content: message,
        actions: const [],
      );
    }
    // The embedded media owner has no Close bar or footer. It retains its
    // ordinary content inset without a reserved standalone close-control lane.
    return Padding(
      padding: accountingContentPadding,
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.attachment.filename,
              style: AccountingTypography.sectionTitle(context),
            ),
            const SizedBox(height: accountingContentInset),
            message,
          ],
        ),
      ),
    );
  }
}

class ReadonlyAttachmentRow extends StatelessWidget {
  const ReadonlyAttachmentRow({
    super.key,
    required this.attachment,
    required this.keyPrefix,
  });
  final ReceiptAttachment attachment;
  final String keyPrefix;
  @override
  Widget build(BuildContext context) => AccountingAttachmentRecordRow(
    attachment: attachment,
    showProcessingStatus: false,
    actions: [
      AccountingButton.iconOnly(
        context,
        key: ValueKey('$keyPrefix-attachment-view-${attachment.originalId}'),
        onPressed: () => showAttachmentPreview(context, attachment),
        icon: Icons.visibility_outlined,
        tooltip: 'View Attachment',
      ),
    ],
  );
}

String accountingAttachmentFileSummary(ReceiptAttachment attachment) {
  final type = switch (attachment.preferredMimeType.toLowerCase()) {
    'application/pdf' => 'PDF',
    'application/msword' => 'DOC',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
      'DOCX',
    'image/png' => 'PNG',
    'image/heic' || 'image/heif' => 'HEIC',
    'image/jpeg' || 'image/jpg' => 'JPEG',
    final mime => mime.split('/').last.toUpperCase(),
  };
  final size = attachment.preferredBytes.length;
  final displayedSize = size < 1024
      ? '$size B'
      : size < 1024 * 1024
      ? '${(size / 1024).toStringAsFixed(1)} KB'
      : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '$type · $displayedSize';
}

/// Attachment groups reuse the connected record-card family and its footer.
class AccountingAttachmentList extends StatelessWidget {
  const AccountingAttachmentList({
    super.key,
    required this.children,
    required this.paginationKey,
  });
  final List<Widget> children;
  final String paginationKey;
  static bool isGrouped(BuildContext context) =>
      _AccountingAttachmentGroup.active(context);
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return _AccountingAttachmentGroup(
      child: AccountingRecordList(
        paginationKey: paginationKey,
        children: children,
      ),
    );
  }
}

class _AccountingAttachmentGroup extends InheritedWidget {
  const _AccountingAttachmentGroup({required super.child});
  static bool active(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AccountingAttachmentGroup>() !=
      null;
  @override
  bool updateShouldNotify(_AccountingAttachmentGroup oldWidget) => false;
}

/// One surface and action rhythm for editable and read-only attachments.
class AccountingAttachmentRecordRow extends StatelessWidget {
  const AccountingAttachmentRecordRow({
    super.key,
    required this.attachment,
    required this.actions,
    this.statusKey,
    this.showProcessingStatus = true,
  });

  final ReceiptAttachment attachment;
  final List<Widget> actions;
  final Key? statusKey;
  final bool showProcessingStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final grouped = _AccountingAttachmentGroup.active(context);
    final failure = attachment.status == AttachmentProcessingStatus.failed
        ? attachment.failureMessage?.trim()
        : null;
    final failureText =
        'Failed - ${failure == null || failure.isEmpty ? 'Review required' : failure}';
    final failureStyle = AccountingTypography.helper(context)
        .copyWith(color: tokens.destructive);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep a short reason within the existing readable details-column
        // budget. Reserve its measured width so the action group cannot wrap
        // that reason. Longer explanations belong to the shared alert below.
        final failureMeasure =
            TextPainter(
              text: TextSpan(text: failureText, style: failureStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout(
              maxWidth: math.max(
                0,
                math.min(
                  240,
                  constraints.maxWidth - accountingContentInset * 2,
                ),
              ),
            );
        final failed = attachment.status == AttachmentProcessingStatus.failed;
        final inlineFailure = failed && !failureMeasure.didExceedMaxLines;
        final status = attachment.reviewSkipped
            ? 'Skipped · not persisted'
            : attachment.pdfBytes != null
            ? 'Ready'
            : switch (attachment.status) {
                AttachmentProcessingStatus.queued => 'Queued',
                AttachmentProcessingStatus.uploading => 'Uploading',
                AttachmentProcessingStatus.processing => 'Processing',
                AttachmentProcessingStatus.ready => 'Ready',
                AttachmentProcessingStatus.failed => 'Failed',
              };
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(accountingAttachmentFileSummary(attachment)),
            if (inlineFailure)
              Semantics(
                liveRegion: true,
                child: Text(failureText, key: statusKey, style: failureStyle),
              )
            else if (!failed && showProcessingStatus && status != 'Ready')
              Semantics(liveRegion: true, child: Text(status, key: statusKey)),
            if (!failed &&
                showProcessingStatus &&
                attachment.processingMessage != null &&
                attachment.status != AttachmentProcessingStatus.ready)
              Text(attachment.processingMessage!),
            if (showProcessingStatus &&
                (attachment.status == AttachmentProcessingStatus.uploading ||
                    attachment.status == AttachmentProcessingStatus.processing))
              const LinearProgressIndicator(minHeight: 4),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              key: ValueKey('attachment-card-${attachment.originalId}'),
              decoration: grouped
                  ? const BoxDecoration()
                  : BoxDecoration(
                      color: tokens.card,
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(
                        accountingSectionRadius,
                      ),
                    ),
              child: AccountingRecordRow(
                title: attachment.filename,
                minimumDetailsWidth: inlineFailure
                    ? math.max(160, failureMeasure.width + 1)
                    : null,
                leading: AccountingIcon(
                  attachment.isPdf
                      ? Icons.description_outlined
                      : Icons.image_outlined,
                  size: 20,
                  color: tokens.mutedForeground,
                ),
                details: details,
                trailing: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ),
            if (failed && !inlineFailure)
              Padding(
                padding: grouped
                    ? const EdgeInsets.fromLTRB(
                        accountingContentInset,
                        0,
                        accountingContentInset,
                        accountingContentInset,
                      )
                    : EdgeInsets.zero,
                child: AccountingAlert.build(
                  context,
                  key: ValueKey('attachment-failure-${attachment.originalId}'),
                  title: 'Failed',
                  description: failure ?? 'Review required',
                  destructive: true,
                  topGap: accountingContentInset,
                ),
              ),
          ],
        );
      },
    );
  }
}
