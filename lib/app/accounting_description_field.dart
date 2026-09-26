// The editor adapter pins 11.6.0 for its configurable leading/copy APIs.
// ignore_for_file: experimental_member_use

import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as rich;
import 'package:flutter_quill/quill_delta.dart';

import '../core/text/transaction_description.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';

/// The authorized long-text variation of the existing input, not a new skin.
abstract final class AccountingDescriptionTokens {
  static const paragraphLineHeightFactor = 1.5;
  static const transactionLineAdvance = 15.0;
  static const transactionParagraphHeightFactor =
      transactionDescriptionParagraphHeightFactor;
  static const markerReserve = '00 ';
  static const minimumHeight = accountingControlHeight;
  static const defaultFixedLines = 3;
}

/// Only explicitly declared item cells receive the proportional paragraph spacing override.
enum AccountingDescriptionRole {
  narrative,
  transactionItem,
  memo,
  paymentTerms,
}

const _markerKey = 'audyt-description-marker';

List<({int offset, int end, String text, String? marker})> _paragraphs(
  rich.Document document,
) {
  final result = <({int offset, int end, String text, String? marker})>[];
  var offset = 0, start = 0;
  var text = '';
  for (final operation in document.toDelta().operations) {
    final data = operation.data;
    if (data is! String) continue;
    for (final character in data.split('')) {
      if (character == '\n') {
        result.add((
          offset: start,
          end: offset,
          text: text,
          marker: operation.attributes?[_markerKey] as String?,
        ));
        start = offset + 1;
        text = '';
      } else {
        text += character;
      }
      offset++;
    }
  }
  return result;
}

rich.Document _document(String plain) {
  final delta = Delta();
  for (final source in plain.split('\n')) {
    final paragraph = DescriptionParagraph.parse(source);
    if (paragraph.text.isNotEmpty) delta.insert(paragraph.text);
    delta.insert(
      '\n',
      paragraph.marker == null
          ? {'align': 'left'}
          : {'list': 'bullet', _markerKey: paragraph.marker},
    );
  }
  return rich.Document.fromDelta(delta);
}

String _plain(rich.Document document) =>
    _paragraphs(document)
        .map((p) => p.marker == null ? p.text : '${p.marker} ${p.text}')
        .join('\n');

/// Keeps ordinary saved String descriptions portable. The editor handles
/// cursor/selection/IME and wrapping; formatting only projects list prefixes.
class DescriptionEditingController extends rich.QuillController {
  DescriptionEditingController(String text)
    : super(
        document: _document(text),
        selection: const TextSelection.collapsed(offset: 0),
        config: rich.QuillControllerConfig(
          clipboardConfig: rich.QuillClipboardConfig(
            enableExternalRichPaste: false,
          ),
        ),
      ) {
    onReplaceText = _replace;
    addListener(_recognize);
  }
  bool _formatting = false;
  String get plainDescription => _plain(document);

  void _mark(int end, String? marker, TextSelection selection) {
    compose(
      Delta()
        ..retain(end)
        ..retain(1, {
          'list': marker == null ? null : 'bullet',
          'align': marker == null ? 'left' : null,
          _markerKey: marker,
        }),
      selection,
      rich.ChangeSource.local,
    );
  }

  bool _replace(int index, int length, Object? data) {
    if (_formatting || data != '\n') return true;
    final paragraph = _paragraphs(document)
        .firstWhere((p) => index >= p.offset && index <= p.end);
    if (paragraph.marker == null) return true;
    _formatting = true;
    try {
      if (paragraph.text.isEmpty) {
        _mark(paragraph.end, null, selection);
      } else {
        replaceText(
          index,
          length,
          '\n',
          TextSelection.collapsed(offset: index + 1),
        );
        final next = _paragraphs(document)
            .firstWhere((p) => p.offset == index + 1);
        _mark(
          next.end,
          DescriptionParagraph(
            paragraph.text,
            marker: paragraph.marker,
          ).nextMarker,
          selection,
        );
      }
    } finally {
      _formatting = false;
    }
    notifyListeners();
    return false;
  }

  bool _scheduled = false, _disposed = false;
  void _recognize() {
    if (_formatting || _scheduled || _disposed) return;
    _scheduled = true;
    // The editor inserts before deleting a replacement. Format only after that
    // atomic edit completes, so prefix removal cannot invalidate its offsets.
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) _formatPrefixes();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _formatPrefixes() {
    if (_formatting) return;
    _formatting = true;
    try {
      // Work backwards so removing prefixes leaves earlier offsets valid.
      for (final paragraph in _paragraphs(document).reversed) {
        final parsed = DescriptionParagraph.parse(paragraph.text);
        if (parsed.marker == null) continue;
        final removed = paragraph.text.length - parsed.text.length;
        final oldSelection = selection;
        int shifted(int n) =>
            n <= paragraph.offset ? n : math.max(paragraph.offset, n - removed);
        final nextSelection = TextSelection(
          baseOffset: shifted(oldSelection.baseOffset),
          extentOffset: shifted(oldSelection.extentOffset),
        );
        replaceText(paragraph.offset, removed, '', nextSelection);
        _mark(paragraph.end - removed, parsed.marker, nextSelection);
      }
    } finally {
      _formatting = false;
    }
  }

  @override
  bool clipboardSelection(bool copy) {
    final selected = selection;
    final paragraphs = _paragraphs(document);
    // External plain-text copy retains visible list markers as well as text.
    final parts = <String>[];
    for (final p in paragraphs) {
      if (p.end < selected.start || p.offset >= selected.end) continue;
      final start = math.max(0, selected.start - p.offset);
      final end = math.min(p.text.length, selected.end - p.offset);
      parts.add(
        '${start == 0 && p.marker != null ? '${p.marker} ' : ''}'
        '${p.text.substring(start, math.max(start, end))}',
      );
    }
    final result = super.clipboardSelection(copy);
    if (result) Clipboard.setData(ClipboardData(text: parts.join('\n')));
    return result;
  }
}

class AccountingDescriptionField extends StatefulWidget {
  const AccountingDescriptionField({
    super.key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.onChanged,
    this.onEscape,
    this.validator,
    this.decoration,
    this.enabled = true,
    this.readOnly = false,
    this.minimumHeight = AccountingDescriptionTokens.minimumHeight,
    this.fixedHeight,
    this.fixedLines = AccountingDescriptionTokens.defaultFixedLines,
    this.maxLength,
    this.autofocus = false,
    this.role = AccountingDescriptionRole.narrative,
  });
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  /// A guarded popout can own dismissal instead of the editor's toolbar shortcut.
  final VoidCallback? onEscape;
  final FormFieldValidator<String>? validator;
  final InputDecoration? decoration;
  final bool enabled, readOnly;
  final double minimumHeight;

  /// Existing multiline boxes wrap and scroll vertically at their fixed height.
  /// The default is the approved three-line registration box. Line-item
  /// descriptions explicitly pass fixedLines: null to wrap and grow.
  final double? fixedHeight;
  final int? fixedLines;
  final int? maxLength;
  final bool autofocus;
  final AccountingDescriptionRole role;

  @override
  State<AccountingDescriptionField> createState() =>
      AccountingDescriptionFieldState();
}

class AccountingDescriptionFieldState
    extends State<AccountingDescriptionField> {
  late DescriptionEditingController editor;
  late final FocusNode _ownedFocus = FocusNode();
  final _scroll = ScrollController();
  FocusNode get focus => widget.focusNode ?? _ownedFocus;
  bool _syncing = false;
  late String _lastAccepted;

  @override
  void initState() {
    super.initState();
    editor = DescriptionEditingController(
      widget.controller?.text ?? widget.initialValue ?? '',
    );
    _lastAccepted = editor.plainDescription;
    editor.addListener(_changed);
    widget.controller?.addListener(_externalChanged);
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (_syncing) return;
    _syncing = true;
    final plain = editor.plainDescription;
    if (widget.maxLength != null &&
        plain.characters.length > widget.maxLength! &&
        plain.characters.length > _lastAccepted.characters.length) {
      final offset = editor.selection.extentOffset;
      editor.document = _document(_lastAccepted);
      editor.updateSelection(
        TextSelection.collapsed(
          offset: math.min(offset, editor.document.length - 1),
        ),
        rich.ChangeSource.local,
      );
      _syncing = false;
      if (mounted) setState(() {});
      return;
    }
    _lastAccepted = plain;
    if (widget.controller?.text != plain) widget.controller?.text = plain;
    widget.onChanged?.call(plain);
    _syncing = false;
    if (mounted) setState(() {});
  }

  void _externalChanged() {
    if (_syncing || widget.controller!.text == editor.plainDescription) return;
    _syncing = true;
    editor.document = _document(widget.controller!.text);
    _lastAccepted = editor.plainDescription;
    _syncing = false;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AccountingDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_externalChanged);
      widget.controller?.addListener(_externalChanged);
      if (widget.controller != null) _externalChanged();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus).removeListener(_focusChanged);
      focus.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_externalChanged);
    focus.removeListener(_focusChanged);
    editor.dispose();
    _scroll.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = AccountingTypography.controlValue(context);
    final item = widget.role == AccountingDescriptionRole.transactionItem;
    final memo =
        widget.role == AccountingDescriptionRole.memo ||
        widget.role == AccountingDescriptionRole.paymentTerms;
    final style = item
        ? baseStyle.copyWith(
            height:
                AccountingDescriptionTokens.transactionLineAdvance /
                baseStyle.fontSize!,
          )
        : baseStyle;
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final lineHeight = painter.height;
    final quarterGap = memo
        ? 0.0
        : item
        ? math.max(
                0.0,
                MediaQuery.textScalerOf(context).scale(
                      baseStyle.fontSize! *
                          AccountingDescriptionTokens
                              .transactionParagraphHeightFactor,
                    ) -
                    lineHeight,
              ) /
              2
        : lineHeight *
              (AccountingDescriptionTokens.paragraphLineHeightFactor - 1) /
              2;
    double measure(String text) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return p.width;
    }

    double listWidth(rich.Block block) => block.children.fold<double>(
      0,
      (w, node) => math.max(
        w,
        measure(node.style.attributes[_markerKey]?.value as String? ?? '•') +
            measure(memo ? ' ' : AccountingDescriptionTokens.markerReserve),
      ),
    );
    editor.readOnly = widget.readOnly || !widget.enabled;
    final blockStyle = rich.DefaultTextBlockStyle(
      style,
      rich.HorizontalSpacing.zero,
      rich.VerticalSpacing(quarterGap, quarterGap),
      rich.VerticalSpacing(quarterGap, quarterGap),
      null,
    );
    final styles = rich.DefaultStyles(
      paragraph: blockStyle,
      align: blockStyle,
      lists: rich.DefaultListBlockStyle(
        style,
        rich.HorizontalSpacing.zero,
        rich.VerticalSpacing(quarterGap, quarterGap),
        rich.VerticalSpacing(quarterGap, quarterGap),
        null,
        null,
        indentWidthBuilder: (block, context, count, delegate) =>
            block.style.attributes.containsKey('list')
            ? rich.HorizontalSpacing(listWidth(block), 0)
            : rich.HorizontalSpacing.zero,
      ),
      leading: blockStyle,
    );
    final decoration = (widget.decoration ?? accountingInputDecoration(context))
        .copyWith(
          enabled: widget.enabled,
          constraints: BoxConstraints(minHeight: widget.minimumHeight),
        );
    final fixedHeight =
        widget.fixedHeight ??
        (widget.fixedLines == null
            ? null
            : math.max(
                accountingControlHeight,
                lineHeight * widget.fixedLines! +
                    (decoration.contentPadding
                            ?.resolve(Directionality.of(context))
                            .vertical ??
                        24),
              ));
    final fixedContentHeight = fixedHeight == null
        ? null
        : math.max(
            0.0,
            fixedHeight -
                (decoration.contentPadding
                        ?.resolve(Directionality.of(context))
                        .vertical ??
                    24),
          );
    Widget editorView() => _TrimParagraphEdges(
      inset: quarterGap,
      child: rich.QuillEditor(
        controller: editor,
        focusNode: focus,
        scrollController: _scroll,
        config: rich.QuillEditorConfig(
          autoFocus: widget.autofocus,
          scrollable: fixedHeight != null,
          minHeight:
              (fixedContentHeight ??
                  math.max(
                    0,
                    widget.minimumHeight -
                        (decoration.contentPadding
                                ?.resolve(Directionality.of(context))
                                .vertical ??
                            24),
                  )) +
              2 * quarterGap,
          maxHeight: fixedContentHeight == null
              ? null
              : fixedContentHeight + 2 * quarterGap,
          onKeyPressed: (event, node) {
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                widget.onEscape != null) {
              if (event is KeyDownEvent) widget.onEscape!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey != LogicalKeyboardKey.tab) return null;
            if (event is KeyDownEvent) {
              HardwareKeyboard.instance.isShiftPressed
                  ? focus.previousFocus()
                  : focus.nextFocus();
            }
            return KeyEventResult.handled;
          },
          padding: EdgeInsets.zero,
          customStyles: styles,
          customLeadingBlockBuilder: (node, config) {
            final marker =
                node.style.attributes[_markerKey]?.value as String? ?? '•';
            final block = node.parent as rich.Block;
            return SizedBox(
              width: listWidth(block),
              child: Text(marker, style: style),
            );
          },
        ),
      ),
    );
    return FormField<String>(
      initialValue: editor.plainDescription,
      validator: (_) => widget.validator?.call(editor.plainDescription),
      builder: (state) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minimumHeight),
        child: InputDecorator(
          decoration: decoration.copyWith(
            errorText: state.errorText ?? decoration.errorText,
          ),
          isFocused: focus.hasFocus,
          isEmpty: editor.plainDescription.isEmpty,
          child: Localizations.override(
            context: context,
            delegates: const [rich.FlutterQuillLocalizations.delegate],
            child: fixedContentHeight == null
                ? editorView()
                : SizedBox(
                    height: fixedContentHeight,
                    child: ClipRect(child: editorView()),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The rich editor adds paragraph spacing around the first/last paragraph.
/// Remove only those outside gaps, retaining the ordinary field's text padding.
class _TrimParagraphEdges extends SingleChildRenderObjectWidget {
  const _TrimParagraphEdges({required this.inset, required super.child});
  final double inset;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTrimParagraphEdges(inset);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTrimParagraphEdges object,
  ) {
    object.inset = inset;
  }
}

class _RenderTrimParagraphEdges extends RenderShiftedBox {
  _RenderTrimParagraphEdges(this._inset) : super(null);
  double _inset;
  set inset(double value) {
    if (_inset != value) {
      _inset = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, math.max(0, child!.size.height - 2 * _inset)),
    );
    (child!.parentData as BoxParentData).offset = Offset(0, -_inset);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final s = child!.getDryLayout(constraints.loosen());
    return constraints.constrain(
      Size(s.width, math.max(0, s.height - 2 * _inset)),
    );
  }
}
