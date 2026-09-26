/// Formats the local accounting date field as `dd-mm-yyyy`.
String formatAccountingInputDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.year.toString().padLeft(4, '0')}';
}

/// Parses only a complete, calendar-valid local accounting date.
DateTime? parseAccountingInputDate(String value) {
  final match = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// Keeps the supplied business calendar date, discarding time without changing
/// timezone. Callers converting an instant must first choose the business zone.
DateTime accountingCalendarDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
