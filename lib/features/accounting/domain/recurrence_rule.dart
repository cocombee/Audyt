/// Calendar dates are represented in UTC without a time component here.
/// They are business dates, not timestamps of midnight in the device timezone.
enum RecurrenceUnit { days, weeks, months, years }

final class RecurrenceRule {
  RecurrenceRule({
    required DateTime startsOn,
    required this.unit,
    this.every = 1,
    DateTime? endsOn,
    this.occurrenceCount,
    this.preserveMonthEnd = true,
  }) : startsOn = _date(startsOn),
       endsOn = endsOn == null ? null : _date(endsOn) {
    if (every < 1) throw ArgumentError.value(every, 'every');
    if (occurrenceCount != null && occurrenceCount! < 1) {
      throw ArgumentError.value(occurrenceCount, 'occurrenceCount');
    }
    if (this.endsOn != null && this.endsOn!.isBefore(this.startsOn)) {
      throw ArgumentError('End date cannot precede start date.');
    }
    if (this.endsOn != null && occurrenceCount != null) {
      throw ArgumentError('Choose an end date or occurrence count, not both.');
    }
  }

  final DateTime startsOn;
  final RecurrenceUnit unit;
  final int every;
  final DateTime? endsOn;
  final int? occurrenceCount;
  final bool preserveMonthEnd;

  /// Index zero is the first occurrence. Always calculate from the anchor,
  /// never from the previously clamped occurrence (which would drift).
  DateTime? occurrenceAt(int index) {
    if (index < 0) throw RangeError.value(index, 'index');
    if (occurrenceCount != null && index >= occurrenceCount!) return null;
    final step = index * every;
    final DateTime result;
    switch (unit) {
      case RecurrenceUnit.days:
        result = startsOn.add(Duration(days: step));
      case RecurrenceUnit.weeks:
        result = startsOn.add(Duration(days: step * 7));
      case RecurrenceUnit.months:
        result = _month(startsOn.month + step);
      case RecurrenceUnit.years:
        result = _month(startsOn.month + step * 12);
    }
    if (endsOn != null && result.isAfter(endsOn!)) return null;
    return result;
  }

  List<DateTime> preview({int count = 6, int startIndex = 0}) {
    if (count < 0 || count > 1000) throw RangeError.range(count, 0, 1000);
    if (startIndex < 0) throw RangeError.value(startIndex, 'startIndex');
    final dates = <DateTime>[];
    for (var i = startIndex; i < startIndex + count; i++) {
      final next = occurrenceAt(i);
      if (next == null) break;
      dates.add(next);
    }
    return List.unmodifiable(dates);
  }

  DateTime _month(int month) {
    final last = DateTime.utc(startsOn.year, month + 1, 0);
    final anchorLast = DateTime.utc(startsOn.year, startsOn.month + 1, 0);
    final useLast = preserveMonthEnd && startsOn.day == anchorLast.day;
    final day = useLast || startsOn.day > last.day ? last.day : startsOn.day;
    return DateTime.utc(last.year, last.month, day);
  }

  Map<String, Object?> toJson() => {
    'startsOn': startsOn.toIso8601String(),
    'unit': unit.name,
    'every': every,
    'endsOn': endsOn?.toIso8601String(),
    'occurrenceCount': occurrenceCount,
    'preserveMonthEnd': preserveMonthEnd,
  };

  factory RecurrenceRule.fromJson(Map<String, Object?> json) => RecurrenceRule(
    startsOn: DateTime.parse(json['startsOn'] as String),
    unit: RecurrenceUnit.values.byName(json['unit'] as String),
    every: json['every'] as int,
    endsOn: json['endsOn'] == null
        ? null
        : DateTime.parse(json['endsOn'] as String),
    occurrenceCount: json['occurrenceCount'] as int?,
    preserveMonthEnd: json['preserveMonthEnd'] as bool,
  );

  static DateTime _date(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
