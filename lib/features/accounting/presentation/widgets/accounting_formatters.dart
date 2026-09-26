import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/money/money.dart';

String formatAccountingInputAmount(Money amount) {
  final precision = Currency.parse(amount.currency).fractionDigits;
  final magnitude = BigInt.from(amount.minorUnits)
      .abs()
      .toString()
      .padLeft(precision + 1, '0');
  final split = magnitude.length - precision;
  final value = precision == 0
      ? magnitude
      : '${magnitude.substring(0, split)}.${magnitude.substring(split)}';
  return amount.isNegative ? '-$value' : value;
}

/// Formats editable money using the same comma grouping and currency precision
/// as the painted amount control. Keeps the caret on the same entered digit.
final class AccountingMoneyInputFormatter extends TextInputFormatter {
  const AccountingMoneyInputFormatter(this.fractionDigits);

  final int fractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (!RegExp(r'^-?\d*(?:\.\d*)?$').hasMatch(raw) ||
        (fractionDigits == 0 && raw.contains('.')) ||
        (raw.contains('.') &&
            raw.length - raw.indexOf('.') - 1 > fractionDigits)) {
      return oldValue;
    }
    final point = raw.indexOf('.');
    final whole = point < 0 ? raw : raw.substring(0, point);
    final fraction = point < 0 ? '' : raw.substring(point);
    final grouped = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    final formatted = '$grouped$fraction';
    int rawOffset(int offset) => newValue.text
        .substring(0, offset.clamp(0, newValue.text.length))
        .replaceAll(',', '')
        .length;
    int formattedOffset(int offset) {
      if (offset <= 0) return 0;
      var count = 0;
      for (var index = 0; index < formatted.length; index++) {
        if (formatted[index] != ',') count++;
        if (count == offset) return index + 1;
      }
      return formatted.length;
    }

    final base = newValue.selection.baseOffset < 0
        ? formatted.length
        : formattedOffset(rawOffset(newValue.selection.baseOffset));
    final extent = newValue.selection.extentOffset < 0
        ? base
        : formattedOffset(rawOffset(newValue.selection.extentOffset));
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: TextRange.empty,
    );
  }
}

String formatAccountingMoneyInputText(String value, int fractionDigits) {
  final formatter = AccountingMoneyInputFormatter(fractionDigits);
  return formatter
      .formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
      )
      .text;
}

/// Keeps date input numeric while inserting the separators for `dd-mm-yyyy`.
final class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final overwritten = _overwriteCompleteDate(oldValue, newValue);
    if (overwritten != null) return overwritten;
    final segmented = _segmentEdit(oldValue, newValue);
    if (segmented != null) return segmented;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits = digits.length > 8 ? digits.substring(0, 8) : digits;
    final formatted = _formatDigits(limitedDigits);
    final baseDigits = _digitsBefore(
      newValue.text,
      newValue.selection.baseOffset,
    ).clamp(0, limitedDigits.length);
    final extentDigits = _digitsBefore(
      newValue.text,
      newValue.selection.extentOffset,
    ).clamp(0, limitedDigits.length);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection(
        baseOffset: _offsetForDigits(formatted, baseDigits),
        extentOffset: _offsetForDigits(formatted, extentDigits),
      ),
      composing: TextRange.empty,
    );
  }

  // A complete date is a fixed-length editor. Replacing a digit keeps the
  // other characters and separators in place, including after a double-click
  // selects the whole day, month, or year segment.
  TextEditingValue? _overwriteCompleteDate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final selection = oldValue.selection;
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(oldText) ||
        !selection.isValid ||
        (selection.start == 0 && selection.end == oldText.length)) {
      return null;
    }
    final removed = selection.end - selection.start;
    if (newValue.text.length != oldText.length - removed + 1) return null;
    final prefix = oldText.substring(0, selection.start);
    final suffix = oldText.substring(selection.end);
    if (!newValue.text.startsWith(prefix) || !newValue.text.endsWith(suffix)) {
      return null;
    }
    final inserted = newValue.text.substring(
      prefix.length,
      newValue.text.length - suffix.length,
    );
    if (!RegExp(r'^\d$').hasMatch(inserted)) return null;

    var target = selection.start;
    if (target == 2 || target == 5) target += 1;
    if (target >= oldText.length || oldText[target] == '-') return null;
    if (removed > 1 &&
        !((selection.start == 0 && selection.end == 2) ||
            (selection.start == 3 && selection.end == 5) ||
            (selection.start == 6 && selection.end == 10))) {
      return null;
    }

    final text = oldText.replaceRange(target, target + 1, inserted);
    final nextSelection = switch (target) {
      1 => const TextSelection(baseOffset: 3, extentOffset: 5),
      4 => const TextSelection(baseOffset: 6, extentOffset: 10),
      _ => TextSelection.collapsed(offset: target + 1),
    };
    return newValue.copyWith(
      text: text,
      selection: nextSelection,
      composing: TextRange.empty,
    );
  }

  TextEditingValue? _segmentEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldParts = oldValue.text.split('-');
    final newParts = newValue.text.split('-');
    if (oldParts.length != 3 || newParts.length != 3) return null;
    if (oldParts[0].length > 2 ||
        oldParts[1].length > 2 ||
        oldParts[2].length > 4 ||
        newParts[0].length > 2 ||
        newParts[1].length > 2 ||
        newParts[2].length > 4 ||
        newParts.any((part) => !RegExp(r'^\d*$').hasMatch(part))) {
      return null;
    }
    final ranges = <TextRange>[
      TextRange(start: 0, end: oldParts[0].length),
      TextRange(
        start: oldParts[0].length + 1,
        end: oldParts[0].length + 1 + oldParts[1].length,
      ),
      TextRange(
        start: oldParts[0].length + oldParts[1].length + 2,
        end: oldValue.text.length,
      ),
    ];
    final oldSelection = oldValue.selection;
    final selectedSegment = oldSelection.isValid && !oldSelection.isCollapsed
        ? ranges.indexWhere(
            (range) =>
                oldSelection.start == range.start &&
                oldSelection.end == range.end,
          )
        : -1;
    final editedSegment = selectedSegment >= 0
        ? selectedSegment
        : oldSelection.isCollapsed && oldSelection.isValid
        ? ranges.indexWhere(
            (range) =>
                range.end - range.start <
                    (range.start == 0 || range.start == oldParts[0].length + 1
                        ? 2
                        : 4) &&
                oldSelection.start >= range.start &&
                oldSelection.start <= range.end,
          )
        : -1;
    if (editedSegment < 0) return null;
    for (var index = 0; index < 3; index++) {
      if (index != editedSegment && newParts[index] != oldParts[index]) {
        return null;
      }
    }
    final length = newParts[editedSegment].length;
    final capacity = editedSegment == 2 ? 4 : 2;
    if (length > capacity) return null;
    final nextStart = editedSegment == 0
        ? newParts[0].length + 1
        : newParts[0].length + newParts[1].length + 2;
    final selection = length == capacity && editedSegment < 2
        ? TextSelection(
            baseOffset: nextStart,
            extentOffset:
                nextStart +
                (editedSegment == 0 ? newParts[1].length : newParts[2].length),
          )
        : newValue.selection;
    return newValue.copyWith(selection: selection, composing: TextRange.empty);
  }

  String _formatDigits(String digits) {
    final parts = <String>[];
    if (digits.length > 2) {
      parts.add(digits.substring(0, 2));
      if (digits.length > 4) {
        parts.add(digits.substring(2, 4));
        parts.add(digits.substring(4));
      } else {
        parts.add(digits.substring(2));
      }
    } else {
      parts.add(digits);
    }
    return parts.where((part) => part.isNotEmpty).join('-');
  }

  int _digitsBefore(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    return text
        .substring(0, safeOffset)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
  }

  int _offsetForDigits(String text, int digitCount) {
    if (digitCount <= 0) return 0;
    var seen = 0;
    for (var index = 0; index < text.length; index++) {
      if (RegExp(r'[0-9]').hasMatch(text[index])) {
        seen += 1;
        if (seen == digitCount) return index + 1;
      }
    }
    return text.length;
  }
}

String formatAccountingMoney(
  BuildContext context,
  Money money, {
  bool includeCurrency = true,
}) => formatAccountingMinor(
  context,
  BigInt.from(money.minorUnits),
  money.currency,
  includeCurrency: includeCurrency,
);

/// Report totals may exceed the signed-integer range of one stored line.
String formatAccountingMinor(
  BuildContext context,
  BigInt minorUnits,
  String currencyCode, {
  bool includeCurrency = true,
}) {
  final currency = Currency.parse(currencyCode);
  final prefix = includeCurrency
      ? CurrencyPresentation.fromCode(currency.code).amountPrefix
      : '';
  final magnitude = minorUnits.abs();
  final base = BigInt.from(_powerOfTen(currency.fractionDigits));
  final wholeUnits = magnitude ~/ base;
  final fractionUnits = magnitude % base;
  // The magnitude of the minimum signed integer is not representable as int.
  // Keep that exceptional zero-decimal value exact rather than clamping it.
  final whole = wholeUnits.isValidInt
      ? MaterialLocalizations.of(context).formatDecimal(wholeUnits.toInt())
      : wholeUnits.toString();
  final sign = minorUnits.isNegative ? '-' : '';
  if (currency.fractionDigits == 0) {
    return '$sign$prefix$whole';
  }

  final fraction = fractionUnits.toString().padLeft(
    currency.fractionDigits,
    '0',
  );
  return '$sign$prefix$whole${_decimalSeparator(context)}$fraction';
}

String formatAccountingDate(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context)
      .formatMediumDate(DateTime(date.year, date.month, date.day));
}

int _powerOfTen(int exponent) {
  var value = 1;
  for (var index = 0; index < exponent; index++) {
    value *= 10;
  }
  return value;
}

String _decimalSeparator(BuildContext context) {
  final languageCode = Localizations.localeOf(context).languageCode;
  const commaDecimalLanguages = <String>{
    'ar',
    'da',
    'de',
    'el',
    'es',
    'fi',
    'fr',
    'id',
    'it',
    'ms',
    'nl',
    'no',
    'pl',
    'pt',
    'ru',
    'sv',
    'tr',
    'uk',
    'vi',
  };
  return commaDecimalLanguages.contains(languageCode) ? ',' : '.';
}
