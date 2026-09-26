import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/money/money.dart';
import 'accounting_formatters.dart';

/// A source movement, never a display total. The chart buckets these by date.
class SalesTrendActivity {
  const SalesTrendActivity({
    required this.date,
    this.invoicedMinor = 0,
    this.receivedMinor = 0,
    this.costMinor = 0,
    this.directCostMinor = 0,
    this.invoiceCount = 0,
    this.receiptCount = 0,
  });
  final DateTime date;
  final int invoicedMinor;
  final int receivedMinor;
  final int costMinor;
  final int directCostMinor;
  final int invoiceCount;
  final int receiptCount;
}

enum SalesTrendPeriod { monthly, quarterly, sixMonths, yearly }

const _trendMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// The card supplies its 20px inset. Keep the x-axis labels inside the plot
// widget without adding a second bottom gutter beneath them.
Rect salesTrendPlotRect(Size size) =>
    Rect.fromLTRB(4, 12, size.width - 4, size.height - 17);

double salesTrendDateFraction(
  DateTime date,
  DateTime firstDay,
  DateTime lastDay,
) {
  final span = lastDay.difference(firstDay).inDays;
  return span == 0 ? 0.5 : date.difference(firstDay).inDays / span;
}

class SalesTrendPoint {
  const SalesTrendPoint({
    required this.date,
    required this.salesMinor,
    required this.costMinor,
    required this.saleCount,
  });
  final DateTime date;
  String get label =>
      '${date.day} ${_trendMonths[date.month - 1]} ${date.year}';
  String get axisLabel => '${date.day} ${_trendMonths[date.month - 1]}';
  final int salesMinor;
  final int costMinor;
  final int saleCount;
  int get profitMinor => salesMinor - costMinor;
}

/// Plot every recorded movement in the selected window, including cost-only
/// days. Empty calendar days remain in the timeline but do not add false dips.
List<SalesTrendPoint> salesTrendDisplayPoints(List<SalesTrendPoint> points) =>
    points
        .where((point) => point.salesMinor != 0 || point.costMinor != 0)
        .toList();

/// The period control selects a calendar window. Its axis ends on the latest
/// visible movement, so unrecorded days after the data do not fill the chart.
List<SalesTrendPoint> salesTrendPoints({
  required List<SalesTrendActivity> activities,
  required DateTime asOf,
  required SalesTrendPeriod period,
  required bool receivedSales,
  required bool allCosts,
}) {
  DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  final now = DateTime.now();
  final endOfTomorrow = DateTime.utc(
    now.year,
    now.month,
    now.day + 2,
  ).subtract(const Duration(microseconds: 1));
  final requestedEnd = asOf.isAfter(endOfTomorrow) ? endOfTomorrow : asOf;
  final lastDay = day(requestedEnd);
  final windowStart = switch (period) {
    SalesTrendPeriod.monthly => DateTime.utc(lastDay.year, lastDay.month, 1),
    SalesTrendPeriod.quarterly => DateTime.utc(
      lastDay.year,
      ((lastDay.month - 1) ~/ 3) * 3 + 1,
      1,
    ),
    SalesTrendPeriod.sixMonths => DateTime.utc(
      lastDay.year,
      lastDay.month - 5,
      1,
    ),
    SalesTrendPeriod.yearly => DateTime.utc(lastDay.year, 1, 1),
  };
  final recorded = activities
      .where(
        (activity) =>
            !activity.date.isAfter(requestedEnd) &&
            (activity.invoicedMinor != 0 ||
                activity.receivedMinor != 0 ||
                activity.costMinor != 0 ||
                activity.directCostMinor != 0 ||
                activity.invoiceCount != 0 ||
                activity.receiptCount != 0),
      )
      .toList();
  final firstDay = windowStart;
  final byDay = <DateTime, List<int>>{};
  for (final activity in recorded) {
    final date = day(activity.date);
    if (date.isBefore(firstDay) || date.isAfter(lastDay)) continue;
    final totals = byDay.putIfAbsent(date, () => [0, 0, 0]);
    totals[0] += receivedSales
        ? activity.receivedMinor
        : activity.invoicedMinor;
    totals[1] += allCosts ? activity.costMinor : activity.directCostMinor;
    totals[2] += receivedSales ? activity.receiptCount : activity.invoiceCount;
  }
  final plottedDays = byDay.entries
      .where((entry) => entry.value[0] != 0 || entry.value[1] != 0)
      .map((entry) => entry.key);
  // Keep the selected calendar period as the filter, but use its recorded
  // endpoints for the plot so empty months never consume chart width.
  final chartFirstDay = plottedDays.isEmpty
      ? windowStart
      : plottedDays.reduce(
          (earliest, date) => date.isBefore(earliest) ? date : earliest,
        );
  final chartLastDay = plottedDays.isEmpty
      ? lastDay
      : plottedDays.reduce(
          (latest, date) => date.isAfter(latest) ? date : latest,
        );
  return [
    for (
      var date = chartFirstDay;
      !date.isAfter(chartLastDay);
      date = date.add(const Duration(days: 1))
    )
      SalesTrendPoint(
        date: date,
        salesMinor: byDay[date]?[0] ?? 0,
        costMinor: byDay[date]?[1] ?? 0,
        saleCount: byDay[date]?[2] ?? 0,
      ),
  ];
}

class SalesProfitChart extends StatefulWidget {
  const SalesProfitChart({
    super.key,
    required this.activities,
    required this.currencyCode,
    required this.asOf,
    required this.receivedSales,
    required this.allCosts,
    required this.period,
    required this.onSalesToggle,
    required this.onCostToggle,
    required this.onPeriodCycle,
    this.fillHeight = false,
  });
  final List<SalesTrendActivity> activities;
  final String currencyCode;
  final DateTime asOf;
  final bool receivedSales;
  final bool allCosts;
  final SalesTrendPeriod period;
  final VoidCallback onSalesToggle;
  final VoidCallback onCostToggle;
  final VoidCallback onPeriodCycle;
  final bool fillHeight;

  @override
  State<SalesProfitChart> createState() => _SalesProfitChartState();
}

class _SalesProfitChartState extends State<SalesProfitChart> {
  int? hovered;
  // The reference chart uses a warm coral revenue line and fill.
  static const salesColor = Color(0xffee6958);
  static const costColor = Color(0xffee5967);
  static const profitColor = Color(0xffe0aa38);

  @override
  Widget build(BuildContext context) {
    final points = salesTrendPoints(
      activities: widget.activities,
      asOf: widget.asOf,
      period: widget.period,
      receivedSales: widget.receivedSales,
      allCosts: widget.allCosts,
    );
    final chartPoints = salesTrendDisplayPoints(points);
    final firstDay = points.first.date;
    final lastDay = points.last.date;

    final periodLabel = switch (widget.period) {
      SalesTrendPeriod.monthly =>
        '${_trendMonths[lastDay.month - 1]} ${lastDay.year}',
      SalesTrendPeriod.quarterly =>
        'Q${(lastDay.month - 1) ~/ 3 + 1} ${lastDay.year}',
      SalesTrendPeriod.sixMonths =>
        '6 months through ${_trendMonths[lastDay.month - 1]} ${lastDay.year}',
      SalesTrendPeriod.yearly => '${lastDay.year}',
    };
    final subtitle =
        '${widget.receivedSales ? 'Received' : 'Invoiced'} vs '
        '${widget.allCosts ? 'posted costs' : 'direct costs'} · $periodLabel';
    final plot = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final plotRect = salesTrendPlotRect(Size(width, constraints.maxHeight));
        final index = chartPoints.isEmpty
            ? null
            : hovered?.clamp(0, chartPoints.length - 1);
        return Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                onExit: (_) => setState(() => hovered = null),
                onHover: (event) => _setHover(
                  event.localPosition,
                  Size(width, constraints.maxHeight),
                  points,
                  chartPoints,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (event) => _setHover(
                    event.localPosition,
                    Size(width, constraints.maxHeight),
                    points,
                    chartPoints,
                  ),
                  child: Semantics(
                    image: true,
                    label:
                        'Sales and cost on recorded sales dates in the ${widget.period.name} window. '
                        'The shaded gap shows profit or loss. Hover or tap a line for exact values.',
                    child: CustomPaint(
                      key: const ValueKey('sales-profit-plot'),
                      painter: _TrendPainter(
                        chartPoints,
                        timeline: points,
                        hovered: index,
                        salesColor: salesColor,
                        costColor: costColor,
                        profitColor: profitColor,
                        labelColor: AccountingTheme.of(context).mutedForeground,
                        gridColor: AccountingTheme.of(context).border,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (chartPoints.isEmpty)
              const Center(child: Text('No activity for this period.')),
            if (index != null)
              Positioned(
                top: 4,
                left: math.min(
                  math.max(0, width - 236),
                  math.max(
                    0,
                    plotRect.left +
                        plotRect.width *
                            salesTrendDateFraction(
                              chartPoints[index].date,
                              firstDay,
                              lastDay,
                            ) -
                        115,
                  ),
                ),
                child: IgnorePointer(
                  child: _pointTooltip(context, chartPoints[index]),
                ),
              ),
          ],
        );
      },
    );
    return AccountingCard.surface(
      context,
      child: Padding(
        padding: accountingContentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountingSectionTitle(context, 'Sales & Profit'),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AccountingTypography.helper(
                        context,
                      ).copyWith(height: 17 / accountingSmallControlFontSize),
                    ),
                  ],
                );
                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toggle(
                      context,
                      const ValueKey('sales-chart-sales-mode'),
                      widget.receivedSales
                          ? Icons.note_add_outlined
                          : Icons.attach_money,
                      widget.receivedSales
                          ? 'Invoiced Sales'
                          : 'Received Sales',
                      widget.onSalesToggle,
                      asset: widget.receivedSales
                          ? '044-invoice.svg'
                          : '052-receive-money.svg',
                    ),
                    const SizedBox(width: accountingRecordIconGap),
                    _toggle(
                      context,
                      const ValueKey('sales-chart-cost-mode'),
                      widget.allCosts
                          ? Icons.inventory_2_outlined
                          : Icons.trending_down_outlined,
                      widget.allCosts ? 'Direct Costs' : 'All Posted Costs',
                      widget.onCostToggle,
                      asset: widget.allCosts
                          ? '065-money-bag.svg'
                          : '066-money.svg',
                    ),
                    const SizedBox(width: accountingRecordIconGap),
                    _toggle(
                      context,
                      const ValueKey('sales-chart-period'),
                      Icons.calendar_today_outlined,
                      switch (widget.period) {
                        SalesTrendPeriod.monthly => 'Quarterly',
                        SalesTrendPeriod.quarterly => '6 Months',
                        SalesTrendPeriod.sixMonths => 'Yearly',
                        SalesTrendPeriod.yearly => 'Monthly',
                      },
                      widget.onPeriodCycle,
                      asset: switch (widget.period) {
                        SalesTrendPeriod.monthly => '067-month-clock.svg',
                        SalesTrendPeriod.quarterly =>
                          '064-quarter-calendar.svg',
                        SalesTrendPeriod.sixMonths =>
                          '073-six-month-calendar.svg',
                        SalesTrendPeriod.yearly => '074-year-calendar.svg',
                      },
                    ),
                  ],
                );
                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: accountingContentInset),
                      Align(alignment: Alignment.centerRight, child: controls),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: accountingContentInset),
                    controls,
                  ],
                );
              },
            ),
            const SizedBox(height: accountingContentInset),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _seriesLabel('Sales', salesColor),
                _seriesLabel('Cost', costColor),
                _seriesLabel('Profit', profitColor),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.fillHeight)
              Expanded(child: plot)
            else
              SizedBox(height: 228, child: plot),
          ],
        ),
      ),
    );
  }

  void _setHover(
    Offset position,
    Size size,
    List<SalesTrendPoint> timeline,
    List<SalesTrendPoint> points,
  ) {
    int? next;
    if (points.isNotEmpty && timeline.isNotEmpty) {
      final plot = salesTrendPlotRect(size);
      if (plot.inflate(10).contains(position)) {
        final dayOffset = timeline.length == 1
            ? 0
            : ((position.dx - plot.left) / plot.width * (timeline.length - 1))
                  .round()
                  .clamp(0, timeline.length - 1);
        final day = timeline[dayOffset];
        final nearest = points.indexWhere((point) => point.date == day.date);
        final dayX = timeline.length == 1
            ? plot.center.dx
            : plot.left + plot.width * dayOffset / (timeline.length - 1);
        final dayWidth = timeline.length == 1
            ? plot.width
            : plot.width / (timeline.length - 1);
        if (nearest < 0 ||
            (position.dx - dayX).abs() >
                math.min(10.0, math.max(4.0, dayWidth * 0.45))) {
          if (hovered != null) setState(() => hovered = null);
          return;
        }
        final values = [
          for (final point in points) ...[point.salesMinor, point.costMinor],
        ];
        final low = math.min(0, values.reduce(math.min));
        final high = math.max(1, values.reduce(math.max));
        for (final read in <int Function(SalesTrendPoint)>[
          (point) => point.salesMinor,
          (point) => point.costMinor,
        ]) {
          if (read(points[nearest]) == 0) continue;
          final value = read(points[nearest]);
          final lineY =
              plot.bottom - (value - low) / (high - low) * plot.height;
          if ((position.dy - lineY).abs() <= 10) {
            next = nearest;
            break;
          }
        }
      }
    }
    if (next != hovered) setState(() => hovered = next);
  }

  Widget _pointTooltip(BuildContext context, SalesTrendPoint point) {
    String amount(int minor) => formatAccountingMoney(
      context,
      Money.fromMinor(minor, widget.currencyCode),
    );
    return DecoratedBox(
      key: const ValueKey('sales-profit-point-tooltip'),
      decoration: BoxDecoration(
        color: AccountingTheme.of(context).card,
        border: Border.all(color: AccountingTheme.of(context).border),
        borderRadius: BorderRadius.circular(accountingControlRadius),
        boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 218,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                point.label,
                style: AccountingTypography.fieldLabel(context),
              ),
              Text(
                '${widget.receivedSales ? 'Received' : 'Invoiced'} sales  ${amount(point.salesMinor)}',
              ),
              Text(
                '${widget.allCosts ? 'Posted' : 'Direct'} costs  ${amount(point.costMinor)}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seriesLabel(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );

  Widget _toggle(
    BuildContext context,
    Key key,
    IconData icon,
    String next,
    VoidCallback onPressed, {
    String? asset,
  }) => Tooltip(
    message: 'Switch to $next',
    child: SizedBox.square(
      dimension: accountingSmallControlHeight,
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(accountingSmallControlHeight),
          foregroundColor: AccountingTheme.of(context).foreground,
          backgroundColor: AccountingTheme.of(context).card,
          side: BorderSide(color: AccountingTheme.of(context).input),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(accountingSmallIconRadius),
          ),
        ),
        child: Builder(
          builder: (iconContext) => Center(
            child: asset == null
                ? AccountingIcon.smallAction(
                    icon,
                    color: IconTheme.of(iconContext).color,
                  )
                : SizedBox.square(
                    dimension: AccountingIcon.smallCanvasSizeForAsset(asset),
                    child: SvgPicture.asset(
                      'assets/icons/small/$asset',
                      colorFilter: ColorFilter.mode(
                        IconTheme.of(iconContext).color ??
                            AccountingTheme.of(iconContext).foreground,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(
    this.points, {
    required this.timeline,
    required this.hovered,
    required this.salesColor,
    required this.costColor,
    required this.profitColor,
    required this.labelColor,
    required this.gridColor,
  });
  final List<SalesTrendPoint> points;
  final List<SalesTrendPoint> timeline;
  final int? hovered;
  final Color salesColor, costColor, profitColor, labelColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plot = salesTrendPlotRect(size);
    final values = [
      for (final point in points) ...[point.salesMinor, point.costMinor],
    ];
    final low = math.min(0, values.reduce(math.min));
    final high = math.max(1, values.reduce(math.max));
    final span = high - low;
    final firstDay = timeline.first.date;
    final totalDays = timeline.last.date.difference(firstDay).inDays;
    double x(int index) =>
        plot.left +
        plot.width *
            salesTrendDateFraction(
              points[index].date,
              firstDay,
              timeline.last.date,
            );
    double y(int value) => plot.bottom - (value - low) / span * plot.height;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var line = 0; line <= 3; line++) {
      final yy = plot.top + plot.height * line / 3;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
    }
    if (hovered != null) {
      canvas.drawLine(
        Offset(x(hovered!), plot.top),
        Offset(x(hovered!), plot.bottom),
        Paint()
          ..color = labelColor.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }
    final series = <(Color, int Function(SalesTrendPoint))>[
      (salesColor, (point) => point.salesMinor),
      (costColor, (point) => point.costMinor),
    ];
    int score(int index) =>
        math.max(points[index].salesMinor.abs(), points[index].costMinor.abs());
    final ranked = [
      for (var index = 0; index < points.length; index++)
        if (score(index) > 0) index,
    ]..sort((left, right) => score(right).compareTo(score(left)));
    final majorDays = ranked.take(8).toSet();
    canvas.save();
    canvas.clipRect(plot);
    Paint areaFill(Color color) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.20)],
      ).createShader(plot);
    // Cost owns the red area below its line. The profit band between cost and
    // sales uses the same fade in orange, preserving two distinct fills.
    final area = Path()
      ..moveTo(points.length == 1 ? plot.left : x(0), plot.bottom);
    if (points.length == 1) {
      area
        ..lineTo(plot.left, y(points.single.costMinor))
        ..lineTo(plot.right, y(points.single.costMinor));
    } else {
      for (var index = 0; index < points.length; index++) {
        area.lineTo(x(index), y(points[index].costMinor));
      }
    }
    area
      ..lineTo(
        points.length == 1 ? plot.right : x(points.length - 1),
        plot.bottom,
      )
      ..close();
    canvas.drawPath(area, areaFill(costColor));
    if (points.length == 1) {
      final saleY = y(points.single.salesMinor);
      final costY = y(points.single.costMinor);
      if (saleY != costY) {
        canvas.drawRect(
          Rect.fromLTRB(
            plot.left,
            math.min(saleY, costY),
            plot.right,
            math.max(saleY, costY),
          ),
          areaFill(points.single.profitMinor >= 0 ? profitColor : costColor),
        );
      }
    }
    // Profit is the area between the two actual series, rather than a third
    // line that overlaps them. Split a segment at a crossing so a loss never
    // inherits the positive-margin color.
    for (var index = 0; index + 1 < points.length; index++) {
      final left = points[index];
      final right = points[index + 1];
      final differenceLeft = left.profitMinor.toDouble();
      final differenceRight = right.profitMinor.toDouble();
      final leftSales = Offset(x(index), y(left.salesMinor));
      final leftCost = Offset(x(index), y(left.costMinor));
      final rightSales = Offset(x(index + 1), y(right.salesMinor));
      final rightCost = Offset(x(index + 1), y(right.costMinor));
      void fillBand(
        Offset firstSales,
        Offset lastSales,
        Offset lastCost,
        Offset firstCost,
        bool gain,
      ) {
        final band = Path()
          ..moveTo(firstSales.dx, firstSales.dy)
          ..lineTo(lastSales.dx, lastSales.dy)
          ..lineTo(lastCost.dx, lastCost.dy)
          ..lineTo(firstCost.dx, firstCost.dy)
          ..close();
        canvas.drawPath(band, areaFill(gain ? profitColor : costColor));
      }

      if ((differenceLeft >= 0) == (differenceRight >= 0)) {
        fillBand(
          leftSales,
          rightSales,
          rightCost,
          leftCost,
          differenceLeft >= 0,
        );
      } else {
        final fraction =
            differenceLeft.abs() /
            (differenceLeft.abs() + differenceRight.abs());
        final crossing = Offset.lerp(leftSales, rightSales, fraction)!;
        fillBand(leftSales, crossing, crossing, leftCost, differenceLeft >= 0);
        fillBand(
          crossing,
          rightSales,
          rightCost,
          crossing,
          differenceRight >= 0,
        );
      }
    }
    for (final (color, read) in series) {
      final path = Path();
      if (points.length == 1) {
        path
          ..moveTo(plot.left, y(read(points.single)))
          ..lineTo(plot.right, y(read(points.single)));
      } else {
        for (var index = 0; index < points.length; index++) {
          final point = Offset(x(index), y(read(points[index])));
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
      }
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.40625
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (color == costColor) {
        for (final metric in path.computeMetrics()) {
          for (double distance = 0; distance < metric.length; distance += 10) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 6, metric.length),
              ),
              linePaint,
            );
          }
        }
      } else {
        canvas.drawPath(path, linePaint);
      }
      for (var index = 0; index < points.length; index++) {
        if (index != hovered &&
            (!majorDays.contains(index) || read(points[index]) == 0)) {
          continue;
        }
        canvas.drawCircle(
          Offset(x(index), y(read(points[index]))),
          index == hovered ? 4 : 2.5,
          Paint()..color = color,
        );
      }
    }
    canvas.restore();
    final tickCount = math.min(6, timeline.length);
    final tickIndices = <int>{
      for (var tick = 0; tick < tickCount; tick++)
        (tick * (timeline.length - 1) / math.max(1, tickCount - 1)).round(),
    };
    for (final index in tickIndices) {
      final label = timeline[index].axisLabel;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontFamily: 'Inter',
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          ((totalDays == 0
                      ? plot.center.dx
                      : plot.left + plot.width * index / totalDays) -
                  painter.width / 2)
              .clamp(0, size.width - painter.width),
          plot.bottom + 7,
        ),
      );
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
