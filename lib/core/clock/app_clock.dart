abstract interface class AppClock {
  DateTime nowUtc();

  DateTime todayUtc();
}

final class SystemClock implements AppClock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime todayUtc() {
    final now = nowUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }
}

final class FixedClock implements AppClock {
  FixedClock(DateTime value) : _value = value.toUtc();

  final DateTime _value;

  @override
  DateTime nowUtc() => _value;

  @override
  DateTime todayUtc() => DateTime.utc(_value.year, _value.month, _value.day);
}
