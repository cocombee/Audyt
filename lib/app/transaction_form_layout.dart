import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'field_guidance.dart';

/// The accepted transaction grid: 10px peers, 20px number/action boundaries.
/// Inter bearings come from the bundled font's visible-text metrics, so the
/// number's painted edge (rather than its advance box) owns the first gap.
final class AccountingTransactionGridTokens {
  static const peerGap = 10.0;
  // Existing Expense/frontend transaction Description floor. Keep the same
  // role available to custom grids such as Journal without a local estimate.
  static const descriptionMinimumWidth = 180.0;
  static const initialNumericText = {
    'Quantity': '0',
    'Rate': '000',
    'Amount': '000',
  };
  static double fieldTitleWidth(
    BuildContext context,
    String title, {
    String? guidance,
  }) => accountingFieldLabelMinimumWidth(
    context,
    title,
    alignToField: true,
    guidance: guidance,
  );

  static double numericWidth(
    BuildContext context,
    String field,
    Iterable<String> values, {
    String? minimumText,
    String? title,
    String? guidance,
  }) {
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: AccountingTypography.controlValue(context),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final contentWidth =
        [
          minimumText ?? initialNumericText[field]!,
          ...values,
        ].map(measure).reduce(math.max) +
        accountingContentInset * 2;
    return title == null
        ? contentWidth
        : math.max(
            contentWidth,
            fieldTitleWidth(context, title, guidance: guidance),
          );
  }

  /// Inline rows cap at their placeholder; shorter displayed selections shrink.
  /// Peer rows keep one column width, measured from their longest current label.
  static double selectionWidth(
    BuildContext context,
    String hintText, {
    Iterable<String?>? selectedLabels,
    String? title,
  }) {
    final displayHint = accountingSelectorHintText(hintText);
    final ceiling = accountingSelectorMinimumWidth(context, [
      displayHint,
    ], stackedLine: true);
    final titleFloor = title == null ? 0.0 : fieldTitleWidth(context, title);
    if (selectedLabels == null) return math.max(titleFloor, ceiling);
    final labels = selectedLabels
        .map((label) => label == null || label.isEmpty ? displayHint : label)
        .toList();
    if (labels.isEmpty) return math.max(titleFloor, ceiling);
    return math.max(
      titleFloor,
      math.min(
        ceiling,
        accountingSelectorMinimumWidth(context, labels, stackedLine: true),
      ),
    );
  }

  static const _digitBearings = [
    122,
    180,
    146,
    122,
    118,
    122,
    122,
    98,
    122,
    122,
  ];
  static double numberGap(BuildContext context, int number) {
    final digit = number % 10;
    final style = AccountingTypography.controlValue(context);
    return accountingContentInset -
        _digitBearings[digit] /
            2048 *
            MediaQuery.textScalerOf(context).scale(style.fontSize!);
  }
}

class AccountingTransactionColumn {
  const AccountingTransactionColumn({
    required this.title,
    required this.width,
    required this.cell,
    this.headerAlignment = Alignment.centerLeft,
    this.naturalHeaderWidth = false,
    this.guidance,
  });
  final String title;
  final double width;
  final Widget Function(int row, double width) cell;
  final Alignment headerAlignment;
  final bool naturalHeaderWidth;
  final String? guidance;
}

class AccountingTransactionGrid extends StatelessWidget {
  const AccountingTransactionGrid({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.action,
    required this.rowKey,
    this.showActions = true,
  });
  final List<AccountingTransactionColumn> columns;
  final int rowCount;
  final Widget Function(int row) action;
  final Key Function(int row) rowKey;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final numberPainter = TextPainter(
      text: TextSpan(
        text: '$rowCount',
        style: AccountingTypography.controlValue(context),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final headingWidths = [
      for (final column in columns)
        (() {
          final painter = TextPainter(
            text: TextSpan(
              text: accountingTitleCase(column.title),
              style: AccountingTypography.fieldLabel(context),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          final help = column.guidance ?? accountingFieldGuidance(column.title);
          return width + (help == null ? 0 : 24);
        })(),
    ];
    final naturalHeadings = <bool>[];
    var columnStart = 0.0;
    var previousHeadingRight = double.negativeInfinity;
    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      final rightAligned = column.headerAlignment == Alignment.centerRight;
      final naturalLeft = rightAligned
          ? columnStart + column.width - headingWidths[index]
          : columnStart;
      // A compact Amount title can extend over the adjacent Rate title. Use
      // the shared label's existing wrapping in that case, keeping input widths
      // and the fluid Description unchanged. A lone Amount keeps its right axis.
      final natural =
          column.naturalHeaderWidth &&
          (rightAligned
              ? naturalLeft >=
                    previousHeadingRight +
                        AccountingTransactionGridTokens.peerGap
              : headingWidths[index] <= column.width);
      naturalHeadings.add(natural);
      previousHeadingRight = rightAligned
          ? columnStart + column.width
          : columnStart +
                (natural
                    ? headingWidths[index]
                    : math.min(column.width, headingWidths[index]));
      columnStart += column.width + AccountingTransactionGridTokens.peerGap;
    }
    Widget heading(int index) {
      final column = columns[index];
      final label = accountingFieldLabel(
        context,
        column.title,
        alignToField: true,
        guidance: column.guidance,
      );
      if (!naturalHeadings[index]) {
        return Align(alignment: column.headerAlignment, child: label);
      }
      final painter = TextPainter(
        text: TextSpan(
          text: column.title,
          style: AccountingTypography.fieldLabel(context),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final labelHeight = math.max(20.0, painter.height);
      painter.dispose();
      return SizedBox(
        height: labelHeight,
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: column.headerAlignment,
          // The shared label already shrink-wraps its text and help control.
          // Use these natural-width constraints directly rather than adding
          // another intrinsic sizing pass. Input-column sizing remains
          // independent of the title.
          child: label,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width:
                  numberPainter.width +
                  AccountingTransactionGridTokens.numberGap(context, rowCount),
            ),
            for (var column = 0; column < columns.length; column++) ...[
              if (column > 0)
                const SizedBox(width: AccountingTransactionGridTokens.peerGap),
              SizedBox(width: columns[column].width, child: heading(column)),
            ],
          ],
        ),
        const SizedBox(height: accountingFieldLabelGap),
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0)
            const SizedBox(height: AccountingTransactionGridTokens.peerGap),
          Row(
            key: rowKey(row),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 13),
                child: SizedBox(
                  width: numberPainter.width,
                  child: Text(
                    '${row + 1}',
                    textAlign: TextAlign.right,
                    style: AccountingTypography.controlValue(context),
                  ),
                ),
              ),
              SizedBox(
                width: AccountingTransactionGridTokens.numberGap(
                  context,
                  rowCount,
                ),
              ),
              for (var column = 0; column < columns.length; column++) ...[
                if (column > 0)
                  const SizedBox(
                    width: AccountingTransactionGridTokens.peerGap,
                  ),
                SizedBox(
                  width: columns[column].width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      columns[column].cell(row, columns[column].width),
                    ],
                  ),
                ),
              ],
              if (showActions) ...[
                const SizedBox(width: accountingContentInset),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: action(row),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The accepted transaction summary rows, including the ordinary field's
/// painted left text inset when requested by a popup owner.
class AccountingTransactionSummary extends StatelessWidget {
  const AccountingTransactionSummary({
    super.key,
    required this.rows,
    this.labelInset = 0,
    this.rowKeys = const [],
    this.labelKeys = const [],
    this.valueKeys = const [],
    this.firstRowTopInset,
  });
  final List<(String, String)> rows;
  final double labelInset;
  final List<Key?> rowKeys, labelKeys, valueKeys;
  final double? firstRowTopInset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: labelInset),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: i < rowKeys.length ? rowKeys[i] : null,
            padding: EdgeInsets.only(
              top: i == 0 ? firstRowTopInset ?? 8 : 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    key: i < labelKeys.length ? labelKeys[i] : null,
                    style: i == rows.length - 1
                        ? AccountingTypography.fieldLabel(context)
                        : AccountingTypography.controlValue(context),
                  ),
                ),
                const SizedBox(width: accountingContentInset),
                Text(
                  rows[i].$2,
                  key: i < valueKeys.length ? valueKeys[i] : null,
                  style: i == rows.length - 1
                      ? AccountingTypography.fieldLabel(context)
                      : AccountingTypography.controlValue(context),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Two or more rows start beside the tall field's heading and retain their
/// existing row gap. A single total keeps its accepted bottom alignment.
/// These normalized descenders are measured from bundled Inter Semibold 600.
/// Both the total label and amount participate (including commas/brackets).
class AccountingMemoSummary extends StatelessWidget {
  const AccountingMemoSummary({
    super.key,
    required this.rows,
    this.memo,
    this.rowKeys = const [],
    this.valueKeys = const [],
    this.totalLabelKey,
    this.memoLabel = 'Memo',
    this.summaryLabelInset = 0,
  });
  final List<(String, String)> rows;
  final Widget Function(double height)? memo;
  final List<Key?> rowKeys;
  final List<Key?> valueKeys;
  final Key? totalLabelKey;
  final String memoLabel;
  final double summaryLabelInset;

  @override
  Widget build(BuildContext context) {
    final regular = AccountingTypography.controlValue(context);
    final heading = AccountingTypography.fieldLabel(context);
    TextPainter measure(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final rowHeights = [
      for (var i = 0; i < rows.length; i++)
        math.max(
          measure(rows[i].$1, i == rows.length - 1 ? heading : regular).height,
          measure(rows[i].$2, i == rows.length - 1 ? heading : regular).height,
        ),
    ];
    final total = measure(rows.last.$1, heading);
    final totalText = '${rows.last.$1}${rows.last.$2}';
    final descent = totalText.contains(',')
        ? 383.1190185546875 / 2048
        : totalText.contains('(') || totalText.contains(')')
        ? 279 / 2048
        : 23.1201171875 / 2048;
    final totalBottom =
        rowHeights.take(rows.length - 1).fold(0.0, (a, b) => a + b + 16) +
        8 +
        total.computeLineMetrics().single.baseline +
        descent * MediaQuery.textScalerOf(context).scale(heading.fontSize!);
    final labelHeight = math.max(20.0, measure(memoLabel, heading).height);
    final memoHeight = math.max(
      accountingControlHeight,
      totalBottom - labelHeight - accountingFieldLabelGap,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final summaryWidth = math.max(
          280.0,
          rows
              .map(
                (r) =>
                    measure(r.$1, heading).width +
                    measure(r.$2, heading).width +
                    accountingContentInset +
                    summaryLabelInset,
              )
              .reduce(math.max),
        );
        if (memo == null) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: math.min(constraints.maxWidth, summaryWidth),
              child: AccountingTransactionSummary(
                rows: rows,
                labelInset: summaryLabelInset,
                rowKeys: rowKeys,
                valueKeys: valueKeys,
              ),
            ),
          );
        }
        return _MemoSummaryLayout(
          summaryWidth: summaryWidth,
          totalBottom: totalBottom,
          alignToHeading: rows.length >= 2,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                accountingFieldLabel(context, memoLabel, alignToField: true),
                const SizedBox(height: accountingFieldLabelGap),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: memoHeight),
                  child: memo!(memoHeight),
                ),
              ],
            ),
            AccountingTransactionSummary(
              rows: rows,
              firstRowTopInset: rows.length >= 2
                  ? math.max(0, (labelHeight - rowHeights.first) / 2)
                  : null,
              labelInset: summaryLabelInset,
              rowKeys: rowKeys,
              valueKeys: valueKeys,
              labelKeys: [
                for (var i = 0; i < rows.length; i++)
                  i == rows.length - 1 ? totalLabelKey : null,
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Measure the fixed memo first, then keep the painted Total baseline aligned
/// with its bottom. Avoid intrinsic-height queries on the editable document.
class _MemoSummaryLayout extends MultiChildRenderObjectWidget {
  const _MemoSummaryLayout({
    required this.summaryWidth,
    required this.totalBottom,
    required this.alignToHeading,
    required super.children,
  });
  final double summaryWidth, totalBottom;
  final bool alignToHeading;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMemoSummary(summaryWidth, totalBottom, alignToHeading);
  @override
  void updateRenderObject(BuildContext context, _RenderMemoSummary object) {
    object.update(summaryWidth, totalBottom, alignToHeading);
  }
}

class _MemoParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMemoSummary extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderMemoSummary(this.summaryWidth, this.totalBottom, this.alignToHeading);
  double summaryWidth, totalBottom;
  bool alignToHeading;
  void update(double width, double bottom, bool heading) {
    if (summaryWidth == width &&
        totalBottom == bottom &&
        alignToHeading == heading) {
      return;
    }
    summaryWidth = width;
    totalBottom = bottom;
    alignToHeading = heading;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _MemoParentData();
    }
  }

  @override
  void performLayout() {
    final memo = firstChild!, summary = lastChild!;
    final width = constraints.maxWidth;
    memo.layout(
      BoxConstraints.tightFor(
        width: width - summaryWidth - accountingContentInset,
      ),
      parentUsesSize: true,
    );
    summary.layout(
      BoxConstraints.tightFor(width: summaryWidth),
      parentUsesSize: true,
    );
    final top = alignToHeading
        ? 0.0
        : math.max(0.0, memo.size.height - totalBottom);
    (memo.parentData as ContainerBoxParentData<RenderBox>).offset = Offset.zero;
    (summary.parentData as ContainerBoxParentData<RenderBox>).offset = Offset(
      width - summaryWidth,
      top,
    );
    size = constraints.constrain(
      // Total's ink already ends at Memo's bottom. The last summary line's
      // transparent descent/padding must not enlarge the next section's gap.
      Size(width, math.max(memo.size.height, top + totalBottom)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
