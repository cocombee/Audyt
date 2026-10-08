import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/documents/document_vector_trace.dart';
import '../../../../core/documents/receipt_document.dart';

final class DocumentTraceChoice {
  const DocumentTraceChoice(this.settings, this.result, this.all);
  final DocumentTraceSettings settings;
  final DocumentTraceResult result;
  final bool all;
}

class DocumentTraceDialog extends StatefulWidget {
  const DocumentTraceDialog({
    super.key,
    required this.attachment,
    required this.count,
  });
  final ReceiptAttachment attachment;
  final int count;
  @override
  State<DocumentTraceDialog> createState() => _DocumentTraceDialogState();
}

class _DocumentTraceDialogState extends State<DocumentTraceDialog> {
  var _settings = const DocumentTraceSettings();
  DocumentTraceResult? _result;
  bool _busy = false, _stale = true, _showOriginal = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _preview();
  }

  Future<void> _preview() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await DocumentVectorTrace().trace(
        widget.attachment.preferredBytes,
        _settings,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _stale = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(bool all) =>
      Navigator.pop(context, DocumentTraceChoice(_settings, _result!, all));
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: SizedBox(
      width:
          AccountingPopoutTokens.widerContentWidth + accountingContentInset * 2,
      height: MediaQuery.sizeOf(context).height - 40,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountingDialogHeading(
              context,
              'Trace to Vector PDF',
              closeKey: const ValueKey('trace-cancel'),
              onClose: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
            const Text(
              'For text and line art. Compare faint marks and decimal points before applying. Photos and colours become black and white.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  SizedBox(
                    height: 240,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 6,
                      child: Image.memory(
                        _showOriginal || _result == null
                            ? widget.attachment.preferredBytes
                            : _result!.preview,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: AccountingTheme.of(context).destructive,
                      ),
                    ),
                  if (_result != null)
                    Text(
                      '${_result!.pathCount} paths · ${(_result!.pdf.length / 1024).toStringAsFixed(1)} KB PDF · ${_result!.removedPixels} speck pixels removed',
                    ),
                  const SizedBox(height: 12),
                  Text('Black/white threshold: ${_settings.threshold}'),
                  Slider(
                    key: const ValueKey('trace-threshold'),
                    value: _settings.threshold.toDouble(),
                    min: 1,
                    max: 254,
                    divisions: 253,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _settings = DocumentTraceSettings(
                              threshold: value.round(),
                              removeSpecks: _settings.removeSpecks,
                            );
                            _stale = true;
                          }),
                  ),
                  Text(
                    'Remove isolated marks up to ${_settings.removeSpecks} pixels',
                  ),
                  Slider(
                    key: const ValueKey('trace-specks'),
                    value: _settings.removeSpecks.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _settings = DocumentTraceSettings(
                              threshold: _settings.threshold,
                              removeSpecks: value.round(),
                            );
                            _stale = true;
                          }),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AccountingButton.preview(
                        context,
                        key: const ValueKey('trace-preview'),
                        onPressed: _busy || !_stale ? null : _preview,
                        label: 'Preview Trace',
                      ),
                      AccountingButton.outline(
                        context,
                        key: const ValueKey('trace-compare'),
                        onPressed: () =>
                            setState(() => _showOriginal = !_showOriginal),
                        child: Text(
                          _showOriginal ? 'Show Trace' : 'Show Original',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.count > 1)
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('trace-apply-all'),
                    onPressed: _busy || _stale || _result == null
                        ? null
                        : () => _finish(true),
                    child: Text('Apply to All (${widget.count})'),
                  ),
                AccountingButton.primary(
                  context,
                  key: const ValueKey('trace-apply'),
                  onPressed: _busy || _stale || _result == null
                      ? null
                      : () => _finish(false),
                  child: const Text('Use Vector PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
