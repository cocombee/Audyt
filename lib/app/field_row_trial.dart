// Shared ordinary popout field planner; custom and page/tab owners stay scoped.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'responsive.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';

/// Exactly three field-layout owners. Equal/fitted/stacked rows are strategies
/// within the shared popup owner, not additional ownership rules.
enum AccountingFieldLayoutOwner { sharedPopup, custom, pageTab }

final class TrialRow {
  const TrialRow(this.start, this.widths, this.mode);
  final int start;
  final List<double> widths;
  final String mode;
}

List<TrialRow> trialRows(
  double width,
  List<double> minima, {
  double gap = 20,
  bool preferEqual = false,
}) {
  final result = <TrialRow>[];
  var start = 0;
  while (start < minima.length) {
    var count = math.min(4, minima.length - start);
    while (count > 1 &&
        minima.sublist(start, start + count).reduce((a, b) => a + b) +
                gap * (count - 1) >
            width) {
      count--;
    }
    // Avoid a lonely full-width tail when both balanced groups still fit.
    if (count >= 3 && minima.length - start - count == 1) {
      final balanced = count - 1;
      final next = minima.sublist(start + balanced);
      if (next.reduce((a, b) => a + b) + gap * (next.length - 1) <= width) {
        count = balanced;
      }
    }
    final row = minima.sublist(start, start + count);
    final available = width - gap * (count - 1);
    final maximum = row.reduce(math.max);
    final minimum = row.reduce(math.min);
    // Ordinary groups may prefer equal shares whenever every measured minimum fits.
    final equal =
        maximum <= available / count &&
        (preferEqual || maximum - minimum <= gap);
    final extra = (available - row.reduce((a, b) => a + b)) / count;
    // A lone ordinary field uses at least the half-row track. Its measured
    // minimum and responsive usable width determine half versus full width.
    final singleWidth = count == 1
        ? [
            for (final tracks in [2, 1]) (width - gap * (tracks - 1)) / tracks,
          ].firstWhere((share) => share >= maximum, orElse: () => width)
        : width;
    result.add(
      TrialRow(
        start,
        count == 1
            ? [singleWidth]
            : equal
            ? List.filled(count, available / count)
            : [for (final value in row) value + extra],
        maximum > width
            ? 'Does not fit'
            : count == 1
            ? 'Single'
            : equal
            ? 'Equal'
            : 'Content fit',
      ),
    );
    start += count;
  }
  return result;
}

// Transaction-family metadata only. Ordinary fields do not need a form allowlist.
const trialOrdinaryGroups = <String, List<String>>{
  'Invoices': ['Date', 'Due Date', 'Reference'],
  'Quotations': ['Date', 'Expiry Date', 'Reference'],
  'Bills': ['Date', 'Due Date', 'Reference'],
  'Sales Receipts': ['Date', 'Due Date', 'Reference'],
  'Supplier Credits': ['Date', 'Due Date', 'Reference'],
  'Purchase Orders': ['Date', 'Due Date', 'Reference'],
};

/// Shared proposal owner for ordinary popout fields. Callers pass only ordinary
/// slots; custom, money and narrative controls keep their original owner.
class AccountingOrdinaryFieldRows extends StatefulWidget {
  const AccountingOrdinaryFieldRows({
    super.key,
    required this.width,
    required this.minima,
    required this.fieldBuilder,
    this.preferEqual = false,
  });
  final double width;
  final List<double> minima;
  final Widget Function(int index, double width) fieldBuilder;
  final bool preferEqual;

  @override
  State<AccountingOrdinaryFieldRows> createState() =>
      _AccountingOrdinaryFieldRowsState();
}

class _AccountingOrdinaryFieldRowsState
    extends State<AccountingOrdinaryFieldRows> {
  final _fieldKeys = <GlobalKey>[];

  @override
  Widget build(BuildContext context) {
    // Reflow changes a field's Row parent. Keep the complete control subtree
    // attached so its editor, selection and input connection survive the move.
    while (_fieldKeys.length < widget.minima.length) {
      _fieldKeys.add(GlobalKey());
    }
    if (_fieldKeys.length > widget.minima.length) {
      _fieldKeys.removeRange(widget.minima.length, _fieldKeys.length);
    }
    if (widget.minima.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = trialRows(
          math.min(widget.width, constraints.maxWidth),
          widget.minima,
          gap: AccountingResponsive.groupGap,
          preferEqual: widget.preferEqual,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.widths.length; i++) ...[
                    if (i > 0)
                      const SizedBox(width: AccountingResponsive.groupGap),
                    SizedBox(
                      key: _fieldKeys[row.start + i],
                      width: row.widths[i],
                      child: widget.fieldBuilder(row.start + i, row.widths[i]),
                    ),
                  ],
                ],
              ),
              if (row != rows.last)
                const SizedBox(height: AccountingResponsive.groupGap),
            ],
          ],
        );
      },
    );
  }
}

/// Adapter for ordinary controls owned outside FrontendFormDialog. A slot keeps
/// its real controller, validation and callbacks; this owner changes rows only.
/// Custom controls, Amount, narrative and embedded main/tab forms stay outside.
final class AccountingOrdinaryFieldSlot {
  const AccountingOrdinaryFieldSlot({
    required this.label,
    required this.builder,
    this.choices = const [],
    this.contentSample = '0000000000',
    this.date = false,
    this.headerActionLabel,
    this.hasGuidance = false,
    this.minimumRowFraction = 0,
    this.minimumControlWidth,
  });
  final String label;
  final List<String> choices;
  final String contentSample;
  final bool date;
  final bool hasGuidance;
  final double minimumRowFraction;

  /// Explicit intrinsic control floor for a labelled action slot. It does not
  /// assign the containing track width to its button or alter field defaults.
  final double? minimumControlWidth;
  // Only an existing compact Add header action contributes this extra width.
  final String? headerActionLabel;
  final Widget Function(double assignedWidth) builder;

  double minimumWidth(BuildContext context) {
    final labelWidth = accountingFieldLabelMinimumWidth(
      context,
      label,
      hasGuidance: hasGuidance,
    );
    final controlWidth = choices.isEmpty
        ? AccountingResponsive.measuredTextWidth(
                context,
                contentSample,
                AccountingTypography.controlValue(context),
              ) +
              // Outlined inputs paint four pixels beyond contentPadding on
              // each side. Measure their visible inset, as the field token
              // already does, so a fitted hint never loses those eight pixels.
              accountingContentInset * 2 +
              (date ? accountingControlHeight : 0) +
              2
        : accountingSelectorMinimumWidth(context, [
            for (final choice in choices)
              choice == 'Select ${label.replaceFirst(RegExp(r'\s*\*$'), '')}'
                  ? accountingSelectorHintText(choice)
                  : choice,
          ]);
    final headerWidth = headerActionLabel == null
        ? labelWidth
        : labelWidth +
              accountingContentInset +
              16 +
              2 +
              AccountingResponsive.measuredTextWidth(
                context,
                headerActionLabel!,
                AccountingTypography.button(context)
                    .copyWith(fontSize: accountingSmallControlFontSize),
              );
    return math.max(headerWidth, minimumControlWidth ?? controlWidth);
  }
}

class AccountingOrdinaryFields extends StatelessWidget {
  const AccountingOrdinaryFields({super.key, required this.fields});
  final List<AccountingOrdinaryFieldSlot> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AccountingOrdinaryFieldRows(
      width: constraints.maxWidth,
      minima: [
        for (final field in fields)
          math.max(
            field.minimumWidth(context),
            (constraints.maxWidth - AccountingResponsive.groupGap) *
                field.minimumRowFraction,
          ),
      ],
      preferEqual: true,
      fieldBuilder: (index, width) => fields[index].builder(width),
    ),
  );
}
