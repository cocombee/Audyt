import 'dart:math' as math;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks equal/content-fit headers after their measured responsive wrapping.
/// Conditional ordinary peers can appear between the listed selector triggers.
void expectFittingFieldRow(WidgetTester tester, List<String> triggerKeys) {
  expect(triggerKeys.length, greaterThanOrEqualTo(3));
  final extras = <double>[];
  final tops = <double>[];
  final widths = <double>[];
  for (final key in triggerKeys) {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is AccountingSelector<String> &&
          widget.triggerKey == ValueKey(key),
    );
    final selector = tester.widget<AccountingSelector<String>>(finder);
    final context = tester.element(finder);
    final selected = selector.options.any(
      (option) => option.value == selector.value,
    );
    final minimum = math.max(
      accountingSelectorMinimumWidth(context, [
        if (!selected) selector.hintText,
        ...selector.options.map((option) => option.label),
      ]),
      // Ordinary headers reserve their label and guidance chrome as well as
      // the selector's options. Make Recurring is wider than its choices.
      AccountingResponsive.measuredTextWidth(
            context,
            selector.hintText.replaceFirst('Select ', ''),
            AccountingTypography.fieldLabel(context),
          ) +
          28,
    );
    final rect = tester.getRect(finder);
    expect(rect.width, greaterThanOrEqualTo(minimum - .01));
    widths.add(rect.width);
    extras.add(rect.width - minimum);
    tops.add(rect.top);
  }
  var rowStart = 0;
  for (var i = 1; i < extras.length; i++) {
    if ((tops[i] - tops[rowStart]).abs() >= .01) {
      expect(tops[i], greaterThan(tops[rowStart]), reason: 'Ordered wrapping.');
      rowStart = i;
      continue;
    }
    final rowEnd = tops.indexWhere(
      (top) => (top - tops[rowStart]).abs() >= .01,
      rowStart + 1,
    );
    final rowWidths = widths.sublist(
      rowStart,
      rowEnd < 0 ? widths.length : rowEnd,
    );
    final equal = rowWidths.every(
      (value) => (value - rowWidths.first).abs() < .01,
    );
    expect(
      equal ? widths[i] : extras[i],
      closeTo(equal ? widths[rowStart] : extras[rowStart], .01),
      reason:
          'Equal shares when content fits; otherwise equal added spare width. '
          'Fields: $triggerKeys; widths: $widths; spare: $extras',
    );
  }
}
