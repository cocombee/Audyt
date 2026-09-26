import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accounting_components.dart'
    show
        accountingCompactClose,
        AccountingButton,
        AccountingSelector,
        AccountingSelectorOption;
import 'accounting_icons.dart';
import 'accounting_theme.dart';

Future<DateTime?> showAudytDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => AudytDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    ),
  );
}

class AudytDatePickerDialog extends StatefulWidget {
  const AudytDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
    this.today,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? helpText;
  final DateTime? today;

  @override
  State<AudytDatePickerDialog> createState() => _AudytDatePickerDialogState();
}

class _AudytDatePickerDialogState extends State<AudytDatePickerDialog> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  late DateTime selected;
  late DateTime visibleMonth;
  late final DateTime _firstDate = () {
    final cutoff = DateTime((widget.today ?? DateTime.now()).year - 100);
    return widget.firstDate.isAfter(cutoff) ? widget.firstDate : cutoff;
  }();

  @override
  void initState() {
    super.initState();
    final initial = DateUtils.dateOnly(widget.initialDate);
    final first = DateUtils.dateOnly(_firstDate);
    final last = DateUtils.dateOnly(widget.lastDate);
    selected = initial.isBefore(first)
        ? first
        : initial.isAfter(last)
        ? last
        : initial;
    visibleMonth = DateTime(selected.year, selected.month);
  }

  bool _allowed(DateTime date) =>
      !DateUtils.dateOnly(date).isBefore(DateUtils.dateOnly(_firstDate)) &&
      !DateUtils.dateOnly(date).isAfter(DateUtils.dateOnly(widget.lastDate));

  void _moveMonth(int amount) {
    final next = DateTime(visibleMonth.year, visibleMonth.month + amount);
    final start = DateTime(_firstDate.year, _firstDate.month);
    final end = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(start) || next.isAfter(end)) return;
    setState(() => visibleMonth = next);
  }

  int _weekCount(BuildContext context) {
    final offset = DateUtils.firstDayOffset(
      visibleMonth.year,
      visibleMonth.month,
      MaterialLocalizations.of(context),
    );
    return ((offset +
                DateUtils.getDaysInMonth(
                  visibleMonth.year,
                  visibleMonth.month,
                )) /
            7)
        .ceil();
  }

  double _dateInkBottomInset(BuildContext context) {
    // Day buttons are 34px high, but their digits have a shorter painted frame.
    // Use Inter's numeral descent so the footer gap starts at visible ink,
    // independently of the selected circle and hover surface.
    final style = Theme.of(context).textButtonTheme.style!.textStyle!
        .resolve({})!;
    final painter = TextPainter(
      text: TextSpan(text: '30', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final inset =
        (34 - painter.height) / 2 +
        painter.height -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * 20 / 2048;
    painter.dispose();
    return inset;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final summaryWidth = _summaryWidth(context);
    final dialogWidth = summaryWidth + 360;
    final compact = media.width < dialogWidth + accountingContentInset * 2;
    final border = AccountingTheme.of(context).border;
    final summaryHeight = _compactSummaryHeight(context);
    final double dayCalendarHeight =
        44 +
        26 +
        _weekCount(context) * 40 -
        3 -
        _dateInkBottomInset(context) +
        (compact ? 0 : 20 + 12 + (accountingControlHeight - 12) / 2) +
        20;
    final calendarHeight = compact
        ? dayCalendarHeight
        : math.max(dayCalendarHeight, _summaryMinimumHeight(context));

    return Dialog(
      insetPadding: const EdgeInsets.all(accountingContentInset),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(accountingSectionRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SizedBox(
            key: const ValueKey('audyt-date-surface'),
            width: compact
                ? media.width - accountingContentInset * 2
                : dialogWidth,
            height: compact
                ? summaryHeight + 1 + calendarHeight
                : calendarHeight,
            child: compact
                ? Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        key: const ValueKey('audyt-date-summary-pane'),
                        height: summaryHeight,
                        child: _summary(context, horizontal: true),
                      ),
                      Divider(height: 1, color: border),
                      Expanded(child: _calendar(context, compact: true)),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                        key: const ValueKey('audyt-date-summary-pane'),
                        width: summaryWidth,
                        child: _summary(context),
                      ),
                      VerticalDivider(width: 1, color: border),
                      Expanded(
                        child: _calendar(
                          context,
                          compact: false,
                          extraTopSpace: calendarHeight - dayCalendarHeight,
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: AccountingPopoutTokens.closeInset,
            right: AccountingPopoutTokens.closeInset,
            child: accountingCompactClose(
              context,
              key: const ValueKey('audyt-date-close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _summaryStyle(BuildContext context, {bool compact = false}) {
    final style =
        (compact
                ? Theme.of(context).textTheme.headlineSmall!
                : Theme.of(context).textTheme.headlineMedium!)
            .copyWith(fontWeight: FontWeight.w400);
    if (!compact) return style;
    // Select is below the weekday on mobile. Reserve only the shared Close
    // target beside the text, rather than a second text line or inline Select.
    final available =
        MediaQuery.sizeOf(context).width -
        accountingContentInset * 4 -
        40 -
        accountingFieldLabelGap;
    final width = _measureSummaryWidth(context, style, weekdaysOnly: true);
    return available < width
        ? style.copyWith(
            fontSize: (style.fontSize! * math.max(.5, available / width))
                .floorToDouble(),
          )
        : style;
  }

  double _summaryWidth(BuildContext context) =>
      _measureSummaryWidth(context, _summaryStyle(context)).ceilToDouble() +
      accountingContentInset * 2;

  double _measureSummaryWidth(
    BuildContext context,
    TextStyle style, {
    bool weekdaysOnly = false,
  }) {
    // Keep both requested lines intact, and keep the panel width stable while
    // choosing any weekday/month. The calendar retains its established width.
    var width = 0.0;
    double measure(String line) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final measured = painter.width;
      painter.dispose();
      return measured;
    }

    var widestDay = '1';
    var dayWidth = measure(widestDay);
    for (var day = 2; day <= 31; day++) {
      final measured = measure('$day');
      if (measured > dayWidth) {
        widestDay = '$day';
        dayWidth = measured;
      }
    }
    for (final line in [
      ..._weekdays,
      if (!weekdaysOnly)
        for (final month in _months) '$month $widestDay',
    ]) {
      width = math.max(width, measure(line));
    }
    return width;
  }

  ({double lineHeight, double bottomInset}) _compactSummaryMetrics(
    BuildContext context,
  ) {
    final style = _summaryStyle(context, compact: true);
    final painter = TextPainter(
      text: TextSpan(text: _weekdays[selected.weekday - 1], style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
    )..layout();
    // Every full weekday ends in Inter's lowercase y.
    const descender = .20800781;
    final inset =
        painter.height -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * descender;
    final result = (lineHeight: painter.height, bottomInset: inset);
    painter.dispose();
    return result;
  }

  double _summaryBottomInset(BuildContext context, {bool compact = false}) {
    if (compact) return _compactSummaryMetrics(context).bottomInset;
    final style = _summaryStyle(context);
    final painter = TextPainter(
      text: TextSpan(
        text: '${_months[selected.month - 1]} ${selected.day}',
        style: style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // A full month can descend below the date digits (September's p,
    // January's y). Measure the lowest visible ink of the complete line.
    final descent = RegExp('[gjpqy]').hasMatch(_months[selected.month - 1])
        ? .20800781
        : 20 / 2048;
    final inset =
        painter.height -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * descent;
    painter.dispose();
    return inset;
  }

  double _summaryMinimumHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Sunday', style: _summaryStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textHeight = painter.height * 2;
    painter.dispose();
    return accountingContentInset * 4 +
        10 +
        textHeight -
        _summaryBottomInset(context) +
        accountingControlHeight * 3;
  }

  double _compactSummaryHeight(BuildContext context) {
    final metrics = _compactSummaryMetrics(context);
    return accountingContentInset +
        metrics.lineHeight -
        metrics.bottomInset +
        accountingContentInset +
        10 +
        accountingControlHeight * 3 +
        accountingFieldLabelGap * 2;
  }

  Widget _dateSelectors(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingSelector<int>(
          triggerKey: const ValueKey('audyt-year-selector'),
          searchKey: const ValueKey('audyt-year-search'),
          value: visibleMonth.year,
          hintText: 'Year',
          semanticsLabel: 'Calendar Year',
          searchHintText: 'Search Year',
          assignedWidth: constraints.maxWidth,
          options: [
            for (
              var year = _firstDate.year;
              year <= widget.lastDate.year;
              year++
            )
              AccountingSelectorOption(
                value: year,
                label: '$year',
                key: ValueKey('audyt-date-year-$year'),
              ),
          ],
          onChanged: (year) {
            if (year == null) return;
            final firstMonth = year == _firstDate.year ? _firstDate.month : 1;
            final lastMonth = year == widget.lastDate.year
                ? widget.lastDate.month
                : 12;
            setState(
              () => visibleMonth = DateTime(
                year,
                visibleMonth.month.clamp(firstMonth, lastMonth),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        AccountingSelector<int>(
          triggerKey: const ValueKey('audyt-month-selector'),
          searchKey: const ValueKey('audyt-month-search'),
          value: visibleMonth.month,
          hintText: 'Month',
          semanticsLabel: 'Calendar Month',
          searchHintText: 'Search Month',
          assignedWidth: constraints.maxWidth,
          options: [
            for (var month = 1; month <= 12; month++)
              if (!DateTime(
                    visibleMonth.year,
                    month,
                  ).isBefore(DateTime(_firstDate.year, _firstDate.month)) &&
                  !DateTime(visibleMonth.year, month).isAfter(
                    DateTime(widget.lastDate.year, widget.lastDate.month),
                  ))
                AccountingSelectorOption(
                  value: month,
                  label: _months[month - 1],
                  key: ValueKey('audyt-date-month-$month'),
                ),
          ],
          onChanged: (month) {
            if (month != null) {
              setState(() => visibleMonth = DateTime(visibleMonth.year, month));
            }
          },
        ),
      ],
    ),
  );

  Widget _summaryLines(BuildContext context, {bool compact = false}) {
    final style = _summaryStyle(context, compact: compact);
    // Inter regular capital side bearings. Each line shares the same painted
    // left axis, even when the weekday/month begin with different letters.
    const bearings = {
      'M': .08789062,
      'T': .04785156,
      'W': .02539062,
      'F': .08789062,
      'S': .05664062,
      'J': .04882812,
      'A': .02539062,
      'O': .05957031,
      'N': .08789062,
      'D': .08789062,
    };
    final lines = [
      _weekdays[selected.weekday - 1],
      if (!compact) '${_months[selected.month - 1]} ${selected.day}',
    ];
    return Semantics(
      label: lines.join('\n'),
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('audyt-date-summary'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lines.length; index++) ...[
            Transform.translate(
              offset: Offset(
                -MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                        bearings[lines[index][0]]! -
                    (style.letterSpacing ?? 0) / 2,
                0,
              ),
              child: Text(
                lines[index],
                key: ValueKey(
                  index == 0 ? 'audyt-date-weekday' : 'audyt-date-month-day',
                ),
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, {bool horizontal = false}) {
    if (horizontal) {
      final metrics = _compactSummaryMetrics(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          accountingContentInset,
          accountingContentInset,
          accountingContentInset,
          accountingFieldLabelGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryLines(context, compact: true),
            SizedBox(height: accountingContentInset - metrics.bottomInset),
            _dateSelectors(context),
            const SizedBox(height: accountingFieldLabelGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _selectButton(context),
                const Spacer(),
                ..._monthArrows(context, bottomAnchored: false),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(accountingContentInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryLines(context),
          SizedBox(
            height: accountingContentInset - _summaryBottomInset(context),
          ),
          _dateSelectors(context),
          const Spacer(),
          _selectButton(context),
        ],
      ),
    );
  }

  Widget _selectButton(BuildContext context) => AccountingButton.primary(
    context,
    key: const ValueKey('audyt-date-select'),
    onPressed: () => Navigator.of(context).pop(selected),
    child: const Text('Select'),
  );

  List<Widget> _monthArrows(
    BuildContext context, {
    bool bottomAnchored = true,
  }) => [
    _arrow(
      context,
      Icons.chevron_left_rounded,
      'Previous month',
      () => _moveMonth(-1),
      bottomAnchored: bottomAnchored,
    ),
    const SizedBox(width: accountingRecordIconGap),
    _arrow(
      context,
      Icons.chevron_right_rounded,
      'Next month',
      () => _moveMonth(1),
      bottomAnchored: bottomAnchored,
    ),
  ];

  Widget _calendar(
    BuildContext context, {
    required bool compact,
    double extraTopSpace = 0,
  }) {
    return Column(
      key: const ValueKey('audyt-calendar'),
      children: [
        // Reserve only the existing Close target and its 8px top/bottom clearance.
        // Year/month navigation belongs exclusively to the summary selectors.
        const SizedBox(height: 44),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                top: extraTopSpace,
                bottom:
                    (compact ? 17 : 49 + (accountingControlHeight - 12) / 2) -
                    _dateInkBottomInset(context),
                child: _dayGrid(context),
              ),
              if (!compact)
                Positioned(
                  left: accountingContentInset,
                  right: accountingContentInset,
                  bottom: accountingContentInset,
                  child: SizedBox(
                    height: accountingControlHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(),
                        ..._monthArrows(context, bottomAnchored: false),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  ({double left, double right}) _numberInkHalves(
    BuildContext context,
    String label,
  ) {
    // Inter semibold digit side bearings, in em. Layout widths include this
    // invisible space; remove it when anchoring the outer numbers' ink edges.
    const leftBearing = [
      .05043006,
      .04582036,
      .06168032,
      .05242223,
      .05226588,
      .05125046,
      .05043006,
      .04046905,
      .05043006,
      .05043006,
    ];
    const rightBearing = [
      .05041170,
      .07289189,
      .06004006,
      .05052847,
      .04898554,
      .05031365,
      .05027461,
      .04035228,
      .05029422,
      .05027461,
    ];
    final style = Theme.of(context).textButtonTheme.style!.textStyle!
        .resolve({})!;
    final fontSize = MediaQuery.textScalerOf(context).scale(style.fontSize!);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final result = (
      left: painter.width / 2 - leftBearing[int.parse(label[0])] * fontSize,
      right:
          painter.width / 2 -
          rightBearing[int.parse(label[label.length - 1])] * fontSize,
    );
    painter.dispose();
    return result;
  }

  List<double> _dayColumnCenters(
    BuildContext context,
    double width,
    int firstOffset,
    int days,
  ) {
    var leftHalf = 0.0;
    var rightHalf = 0.0;
    for (var day = 1; day <= days; day++) {
      final column = (firstOffset + day - 1) % 7;
      if (column != 0 && column != 6) continue;
      final ink = _numberInkHalves(context, '$day');
      if (column == 0) leftHalf = math.max(leftHalf, ink.left);
      if (column == 6) rightHalf = math.max(rightHalf, ink.right);
    }
    final first = accountingContentInset + leftHalf;
    final last = width - accountingContentInset - rightHalf;
    return List.generate(7, (column) => first + (last - first) * column / 6);
  }

  double _columnCenter(
    BuildContext context,
    double width,
    List<double> centers,
    int column,
    String label, {
    bool weekday = false,
  }) {
    if (column != 0 && column != 6) return centers[column];
    late final ({double left, double right}) ink;
    if (weekday) {
      const left = {
        'M': .08789062,
        'T': .04785156,
        'W': .02539062,
        'F': .08789062,
        'S': .05664062,
      };
      const right = {
        'M': .08789062,
        'T': .04785156,
        'W': .02539062,
        'F': .0625,
        'S': .05664062,
      };
      final style = Theme.of(context).textTheme.bodySmall!;
      final size = MediaQuery.textScalerOf(context).scale(style.fontSize!);
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      ink = (
        left: painter.width / 2 - (left[label] ?? 0) * size,
        right: painter.width / 2 - (right[label] ?? 0) * size,
      );
      painter.dispose();
    } else {
      ink = _numberInkHalves(context, label);
    }
    return column == 0
        ? accountingContentInset + ink.left
        : width - accountingContentInset - ink.right;
  }

  Widget _dayGrid(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final firstOffset = DateUtils.firstDayOffset(
      visibleMonth.year,
      visibleMonth.month,
      local,
    );
    final days = DateUtils.getDaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    final weekdays = local.narrowWeekdays;
    return LayoutBuilder(
      builder: (context, constraints) {
        final centers = _dayColumnCenters(
          context,
          constraints.maxWidth,
          firstOffset,
          days,
        );
        return Column(
          children: [
            SizedBox(
              height: 26,
              child: Stack(
                children: [
                  for (var column = 0; column < 7; column++)
                    Positioned(
                      left:
                          _columnCenter(
                            context,
                            constraints.maxWidth,
                            centers,
                            column,
                            weekdays[(column + local.firstDayOfWeekIndex) % 7],
                            weekday: true,
                          ) -
                          17,
                      width: 34,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          weekdays[(column + local.firstDayOfWeekIndex) % 7],
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AccountingTheme.of(context)
                                    .mutedForeground,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  for (var day = 1; day <= days; day++)
                    Positioned(
                      left:
                          _columnCenter(
                            context,
                            constraints.maxWidth,
                            centers,
                            (firstOffset + day - 1) % 7,
                            '$day',
                          ) -
                          17,
                      top: ((firstOffset + day - 1) ~/ 7) * 40.0 + 3,
                      width: 34,
                      height: 34,
                      child: _dayButton(context, day),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dayButton(BuildContext context, int day) {
    final date = DateTime(visibleMonth.year, visibleMonth.month, day);
    final active = DateUtils.isSameDay(date, selected);
    return TextButton(
      key: ValueKey('audyt-date-day-$day'),
      onPressed: _allowed(date) ? () => setState(() => selected = date) : null,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: active
            ? Colors.white
            : AccountingTheme.of(context).foreground,
        backgroundColor: active
            ? AccountingTheme.of(context).primary
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      child: Text('$day'),
    );
  }

  Widget _arrow(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool bottomAnchored = true,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: accountingSmallControlHeight,
      // The 18px SVG's chevron occupies y=4..20 in a 24px viewBox:
      // its visible height is 12px, and right ink ends 12.25px inside the
      // 32px control. Move mark and hover together to meet the desktop row's
      // bottom; mobile keeps the visible stroke centered beside Select.
      child: Transform.translate(
        offset: Offset(
          12.25,
          bottomAnchored ? (accountingSmallControlHeight - 12) / 2 : 0,
        ),
        child: IconButton(
          key: ValueKey(tooltip),
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(
            width: accountingSmallControlHeight,
            height: accountingSmallControlHeight,
          ),
          icon: AccountingIcon(icon, size: 18),
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            hoverColor: accountingNeutralHighlight,
            foregroundColor: AccountingTheme.of(context).foreground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingSmallIconRadius),
            ),
          ),
        ),
      ),
    ),
  );
}
