import 'dart:math' as math;

import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../../app/accounting_components.dart';
import '../../../../../core/money/money.dart';
import 'accounting_formatters.dart';

/// Largest-remainder rounding keeps displayed shares at exactly 100.0%.
List<int> expensePercentTenths(List<int> amounts) {
  if (amounts.any((amount) => amount < 0)) {
    throw ArgumentError('Pie slices cannot be negative.');
  }
  final total = amounts.fold<BigInt>(
    BigInt.zero,
    (sum, amount) => sum + BigInt.from(amount),
  );
  if (total == BigInt.zero) return List.filled(amounts.length, 0);
  final numerators = amounts
      .map((amount) => BigInt.from(amount) * BigInt.from(1000))
      .toList();
  final shares = numerators
      .map((numerator) => (numerator ~/ total).toInt())
      .toList();
  final order = List.generate(amounts.length, (index) => index)
    ..sort((left, right) {
      final comparison = (numerators[right] % total).compareTo(
        numerators[left] % total,
      );
      return comparison == 0 ? left.compareTo(right) : comparison;
    });
  final missing = 1000 - shares.fold<int>(0, (sum, share) => sum + share);
  for (var index = 0; index < missing; index++) {
    shares[order[index]]++;
  }
  return shares;
}

class ExpensePieChart extends StatelessWidget {
  const ExpensePieChart({
    super.key,
    required this.amounts,
    required this.total,
    this.periodControl,
    this.barChart = false,
    this.grouping = 'Category',
  });

  final Map<String, Money> amounts;
  final Money total;
  final Widget? periodControl;
  final bool barChart;
  final String grouping;
  static const colors = AccountingColorLibrary.chartSeries;

  @override
  Widget build(BuildContext context) {
    final entries =
        amounts.entries.where((entry) => !entry.value.isZero).toList()..sort(
          (left, right) =>
              right.value.minorUnits.compareTo(left.value.minorUnits),
        );
    final valid =
        entries.every((entry) => entry.value.currency == total.currency) &&
        entries.fold<BigInt>(
              BigInt.zero,
              (sum, entry) => sum + BigInt.from(entry.value.minorUnits),
            ) ==
            BigInt.from(total.minorUnits);
    final canPlot =
        valid &&
        total.isPositive &&
        entries.every((entry) => !entry.value.isNegative);
    final percentages = canPlot
        ? expensePercentTenths(
            entries.map((entry) => entry.value.minorUnits).toList(),
          )
        : <int>[];

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountingSectionTitle(context, 'Expenses'),
        const SizedBox(height: AccountingResponsive.titleSubtitleGap),
        accountingHelperText(context, 'Expenses by ${grouping.toLowerCase()}'),
      ],
    );

    return AccountingCard.surface(
      context,
      child: Padding(
        padding: canPlot && !barChart
            ? AccountingRoundChartTokens.cardPadding
            : accountingContentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canPlot && !barChart)
              LayoutBuilder(
                builder: (context, constraints) => _ExpensePieLayout(
                  title: title,
                  controls: periodControl ?? const SizedBox.shrink(),
                  circle: Semantics(
                    label:
                        'Expense distribution. Percentages are listed below.',
                    image: true,
                    child: SizedBox.square(
                      key: const ValueKey('expense-pie-circle'),
                      child: CustomPaint(
                        painter: _PiePainter(
                          entries
                              .map(
                                (entry) =>
                                    entry.value.minorUnits / total.minorUnits,
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                  legend: _ExpenseLegend(
                    entries: entries,
                    percentages: percentages,
                    width: constraints.maxWidth,
                  ),
                ),
              ),
            if (!canPlot || barChart) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  if (periodControl == null) return title;
                  if (constraints.maxWidth < 320) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        const SizedBox(height: accountingContentInset),
                        Align(
                          alignment: Alignment.centerRight,
                          child: periodControl!,
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: accountingContentInset),
                      periodControl!,
                    ],
                  );
                },
              ),
              const SizedBox(height: accountingContentInset),
              if (!valid)
                const Text(
                  'Expense breakdown is unavailable. Refresh to reconcile the totals.',
                )
              else if (entries.isEmpty)
                const Text('No posted expenses for this period.')
              else if (!canPlot)
                const Text(
                  'Net credits cannot be shown as a pie chart for this period.',
                )
              else if (barChart)
                _ExpenseBars(entries: entries, percentages: percentages),
            ],
          ],
        ),
      ),
    );
  }
}

/// The painted circle owns its clearance, including the free curved corners
/// beside the legend. Its enclosing square does not reserve an extra bottom gap.
class _ExpensePieLayout extends MultiChildRenderObjectWidget {
  _ExpensePieLayout({
    required Widget title,
    required Widget controls,
    required Widget circle,
    required Widget legend,
  }) : super(children: [title, controls, circle, legend]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExpensePieLayout();
}

class _ExpensePieParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderExpensePieLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ExpensePieParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ExpensePieParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ExpensePieParentData) {
      child.parentData = _ExpensePieParentData();
    }
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final title = firstChild!;
    final controls = childAfter(title)!;
    final circle = childAfter(controls)!;
    final legend = lastChild!;
    final width = constraints.maxWidth;
    Size measure(RenderBox child, BoxConstraints limits) {
      if (dry) return child.getDryLayout(limits);
      child.layout(limits, parentUsesSize: true);
      return child.size;
    }

    final controlSize = measure(controls, BoxConstraints(maxWidth: width));
    final stackedControls = width < 320 && controlSize.height > 0;
    final titleSize = measure(
      title,
      BoxConstraints(
        maxWidth: stackedControls
            ? width
            : math.max(
                0,
                width -
                    controlSize.width -
                    (controlSize.width > 0 ? accountingContentInset : 0),
              ),
      ),
    );
    final controlTop = stackedControls
        ? titleSize.height + accountingContentInset
        : 0.0;
    final headerHeight = math.max(
      titleSize.height,
      controlTop + controlSize.height,
    );
    final freeHalfWidth = math.max(
      0.0,
      width / 2 -
          math.max(titleSize.width, controlSize.width) -
          AccountingRoundChartTokens.circumferenceClearance,
    );
    final clearanceHeight =
        headerHeight + AccountingRoundChartTokens.circumferenceClearance;
    final baseDiameter = math.min(200.0, width);
    final plotBottom = clearanceHeight + baseDiameter;
    // Preserve upward growth and the top clearance; bottom card height is
    // determined separately by the circle and the actual legend content.
    final diameterForClearance = baseDiameter == 0
        ? 0.0
        : freeHalfWidth >= baseDiameter
        ? freeHalfWidth * 2
        : (freeHalfWidth * freeHalfWidth + baseDiameter * baseDiameter) /
              baseDiameter;
    final diameter = math.min(
      width,
      math.min(plotBottom, math.max(baseDiameter, diameterForClearance)),
    );
    final circleTop = plotBottom - diameter;
    final circleSize = measure(
      circle,
      BoxConstraints.tight(Size.square(diameter)),
    );
    final legendSize = measure(legend, BoxConstraints.tightFor(width: width));
    final center = Offset(width / 2, circleTop + diameter / 2);
    final clearanceRadius =
        diameter / 2 + AccountingRoundChartTokens.circumferenceClearance;
    // The outer Padding already supplies the card-edge inset. The legend may
    // rise into the pie's lower corners until either its content reaches the
    // circumference clearance or the circle reaches that bottom card inset.
    var legendTop = math.max(
      headerHeight + accountingContentInset,
      plotBottom - legendSize.height,
    );
    final occupied = dry
        ? [Offset.zero & legendSize]
        : _legendContentBounds(legend);
    for (final rect in occupied) {
      final nearestX = center.dx.clamp(rect.left, rect.right);
      final horizontal = (nearestX - center.dx).abs();
      if (horizontal >= clearanceRadius) continue;
      final clearanceY = math.sqrt(
        clearanceRadius * clearanceRadius - horizontal * horizontal,
      );
      legendTop = math.max(legendTop, center.dy + clearanceY - rect.top);
    }
    if (!dry) {
      (title.parentData! as _ExpensePieParentData).offset = Offset.zero;
      (controls.parentData! as _ExpensePieParentData).offset = Offset(
        width - controlSize.width,
        controlTop,
      );
      (circle.parentData! as _ExpensePieParentData).offset = Offset(
        (width - circleSize.width) / 2,
        circleTop,
      );
      (legend.parentData! as _ExpensePieParentData).offset = Offset(
        0,
        legendTop,
      );
    }
    return constraints.constrain(
      Size(width, math.max(plotBottom, legendTop + legendSize.height)),
    );
  }

  /// A stretched label's empty line width is not visible legend content.
  /// Text selection boxes retain each real line's width, including wrapping;
  /// dot frames are tight to their painted circles. Font line height is a
  /// conservative envelope for the glyph ink, never less than its clearance.
  List<Rect> _legendContentBounds(RenderBox legend) {
    final bounds = <Rect>[];
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        for (final box in object.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: object.text.toPlainText().length,
          ),
        )) {
          bounds.add(
            MatrixUtils.transformRect(
              object.getTransformTo(legend),
              box.toRect(),
            ),
          );
        }
      } else if (object is RenderDecoratedBox &&
          object.decoration is BoxDecoration &&
          (object.decoration as BoxDecoration).shape == BoxShape.circle) {
        bounds.add(
          MatrixUtils.transformRect(
            object.getTransformTo(legend),
            Offset.zero & object.constraints.biggest,
          ),
        );
      } else {
        object.visitChildren(visit);
      }
    }

    legend.visitChildren(visit);
    return bounds;
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _layout(BoxConstraints(maxWidth: width), dry: true).height;
  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Controls and legend tooltips keep priority in transparent pie corners.
    final title = firstChild!;
    final controls = childAfter(title)!;
    final circle = childAfter(controls)!;
    for (final current in [title, controls, lastChild!, circle]) {
      final data = current.parentData! as _ExpensePieParentData;
      if (result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, position) =>
            current.hitTest(result, position: position),
      )) {
        return true;
      }
    }
    return false;
  }
}

class _ExpenseBars extends StatelessWidget {
  const _ExpenseBars({required this.entries, required this.percentages});
  final List<MapEntry<String, Money>> entries;
  final List<int> percentages;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < entries.length; index++) ...[
        if (index > 0) const SizedBox(height: AccountingProgressBar.rowGap),
        Row(
          children: [
            Expanded(
              child: Text(
                entries[index].key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: accountingContentInset),
            Text('${(percentages[index] / 10).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: AccountingProgressBar.labelGap),
        AccountingProgressBar(
          value:
              entries[index].value.minorUnits /
              entries.fold<int>(
                0,
                (sum, entry) => sum + entry.value.minorUnits,
              ),
          color: ExpensePieChart.colors[index % ExpensePieChart.colors.length],
          height: 8,
        ),
      ],
    ],
  );
}

class _ExpenseLegend extends StatelessWidget {
  const _ExpenseLegend({
    required this.entries,
    required this.percentages,
    required this.width,
  });
  final List<MapEntry<String, Money>> entries;
  final List<int> percentages;
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final percentStyle = Theme.of(context).textTheme.bodySmall;
    final dotSize = accountingColourIndicatorExtent(context);
    final requiredWidths = <double>[];
    for (var index = 0; index < entries.length; index++) {
      final labelWidth = AccountingResponsive.measuredTextWidth(
        context,
        entries[index].key,
        style,
      );
      final percentWidth = AccountingResponsive.measuredTextWidth(
        context,
        '${(percentages[index] / 10).toStringAsFixed(1)}%',
        percentStyle,
      );
      requiredWidths.add(dotSize + 6 + labelWidth + 6 + percentWidth);
    }
    var columns = 1;
    var columnWidths = <double>[width];
    for (
      var candidate = math.min(3, entries.length);
      candidate > 1;
      candidate--
    ) {
      final widths = List<double>.filled(candidate, 0);
      for (var index = 0; index < requiredWidths.length; index++) {
        widths[index % candidate] = math.max(
          widths[index % candidate],
          requiredWidths[index],
        );
      }
      if (widths.reduce((a, b) => a + b) +
              (candidate - 1) * accountingContentInset <=
          width) {
        columns = candidate;
        columnWidths = widths;
        break;
      }
    }
    if (columns == 1 && entries.length > 1 && width >= 460) {
      columns = 2;
      columnWidths = List<double>.filled(
        2,
        (width - accountingContentInset) / 2,
      );
    }
    final columnGap = columns == 1
        ? 0.0
        : (width - columnWidths.reduce((a, b) => a + b)) / (columns - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var start = 0; start < entries.length; start += columns) ...[
          if (start > 0)
            const SizedBox(height: accountingUndividedRowVerticalInset * 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var offset = 0;
                offset < columns && start + offset < entries.length;
                offset++
              ) ...[
                if (offset > 0) SizedBox(width: columnGap),
                SizedBox(
                  key: ValueKey('expense-legend-${start + offset}'),
                  width: columnWidths[offset],
                  child: Tooltip(
                    message:
                        '${entries[start + offset].key} · ${formatAccountingMoney(context, entries[start + offset].value)}',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AccountingColourIndicator(
                          key: ValueKey('expense-legend-dot-${start + offset}'),
                          color:
                              ExpensePieChart.colors[(start + offset) %
                                  ExpensePieChart.colors.length],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entries[start + offset].key,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(percentages[start + offset] / 10).toStringAsFixed(1)}%',
                          style: percentStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.shares);
  final List<double> shares;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var index = 0; index < shares.length; index++) {
      final sweep = shares[index] * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color =
              ExpensePieChart.colors[index % ExpensePieChart.colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => true;
}
