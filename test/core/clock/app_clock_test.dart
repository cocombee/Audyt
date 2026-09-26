import 'package:audyt/core/clock/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixed clocks provide deterministic UTC timestamps', () {
    final localValue = DateTime(2026, 8, 30, 9);
    final clock = FixedClock(localValue);
    final expectedUtc = localValue.toUtc();

    expect(clock.nowUtc(), expectedUtc);
    expect(
      clock.todayUtc(),
      DateTime.utc(expectedUtc.year, expectedUtc.month, expectedUtc.day),
    );
  });
}
