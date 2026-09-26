import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthly month-end anchors do not drift after February', () {
    final rule = RecurrenceRule(
      startsOn: DateTime(2026, 1, 31),
      unit: RecurrenceUnit.months,
    );
    expect(rule.preview(count: 4), [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 2, 28),
      DateTime.utc(2026, 3, 31),
      DateTime.utc(2026, 4, 30),
    ]);
    final fixedDay = RecurrenceRule(
      startsOn: DateTime(2026, 1, 30),
      unit: RecurrenceUnit.months,
    );
    expect(fixedDay.occurrenceAt(2), DateTime.utc(2026, 3, 30));
  });
  test('quarterly means calendar months and end date is inclusive', () {
    final rule = RecurrenceRule(
      startsOn: DateTime(2026, 1, 31),
      unit: RecurrenceUnit.months,
      every: 3,
      endsOn: DateTime(2026, 7, 31),
    );
    expect(rule.preview(), [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 4, 30),
      DateTime.utc(2026, 7, 31),
    ]);
  });
  test('annual leap-day occurrence returns to leap day', () {
    final rule = RecurrenceRule(
      startsOn: DateTime(2024, 2, 29),
      unit: RecurrenceUnit.years,
    );
    expect(rule.occurrenceAt(1), DateTime.utc(2025, 2, 28));
    expect(rule.occurrenceAt(4), DateTime.utc(2028, 2, 29));
  });
  test('custom interval and occurrence count survive serialization', () {
    final rule = RecurrenceRule.fromJson(
      RecurrenceRule(
        startsOn: DateTime(2026, 9, 13, 17),
        unit: RecurrenceUnit.days,
        every: 10,
        occurrenceCount: 3,
      ).toJson(),
    );
    expect(rule.preview(), [
      DateTime.utc(2026, 9, 13),
      DateTime.utc(2026, 9, 23),
      DateTime.utc(2026, 10, 3),
    ]);
    expect(rule.occurrenceAt(3), isNull);
  });
  test('invalid interval and incompatible ends are rejected', () {
    expect(
      () => RecurrenceRule(
        startsOn: DateTime(2026),
        unit: RecurrenceUnit.days,
        every: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => RecurrenceRule(
        startsOn: DateTime(2026),
        unit: RecurrenceUnit.days,
        endsOn: DateTime(2025),
      ),
      throwsArgumentError,
    );
    expect(
      () => RecurrenceRule(
        startsOn: DateTime(2026),
        unit: RecurrenceUnit.days,
        endsOn: DateTime(2027),
        occurrenceCount: 2,
      ),
      throwsArgumentError,
    );
  });
}
