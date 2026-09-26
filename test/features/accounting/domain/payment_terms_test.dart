import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stored terms retain monthly cutoff and reject contradictory payloads',
    () {
      for (final terms in [
        PaymentTerms.daysAfterIssue(30),
        PaymentTerms.dayOfMonth(31, rolloverWithinDays: 5),
      ]) {
        final restored = PaymentTerms.fromJson(terms.toJson());
        expect(restored.toJson(), terms.toJson());
        expect(
          restored.dueOn(DateTime(2026, 12, 28)),
          terms.dueOn(DateTime(2026, 12, 28)),
        );
      }
      for (final json in [
        {'version': 2, 'kind': 'daysAfterIssue', 'days': 30},
        {'version': 1, 'kind': 'daysAfterIssue', 'days': 30, 'dayOfMonth': 15},
        {
          'version': 1,
          'kind': 'dayOfMonth',
          'dayOfMonth': 32,
          'rolloverWithinDays': 0,
        },
        {
          'version': 1,
          'kind': 'dayOfMonth',
          'dayOfMonth': 15,
          'rolloverWithinDays': -1,
        },
      ]) {
        expect(() => PaymentTerms.fromJson(json), throwsFormatException);
      }
    },
  );
  test('net days cross year and preserve business calendar date', () {
    expect(
      PaymentTerms.daysAfterIssue(30).dueOn(DateTime(2026, 12, 15, 23)),
      DateTime.utc(2027, 1, 14),
    );
    expect(
      PaymentTerms.daysAfterIssue(0).dueOn(DateTime(2026, 9, 13)),
      DateTime.utc(2026, 9, 13),
    );
  });
  test('monthly cutoff rolls once and includes cutoff boundary', () {
    final terms = PaymentTerms.dayOfMonth(20, rolloverWithinDays: 5);
    expect(terms.dueOn(DateTime(2026, 9, 14)), DateTime.utc(2026, 9, 20));
    expect(terms.dueOn(DateTime(2026, 9, 15)), DateTime.utc(2026, 10, 20));
    expect(terms.dueOn(DateTime(2026, 9, 25)), DateTime.utc(2026, 10, 20));
  });
  test('day31 clamps correctly including leap year and year rollover', () {
    expect(
      PaymentTerms.dayOfMonth(31).dueOn(DateTime(2024, 2, 1)),
      DateTime.utc(2024, 2, 29),
    );
    expect(
      PaymentTerms.dayOfMonth(31).dueOn(DateTime(2026, 2, 1)),
      DateTime.utc(2026, 2, 28),
    );
    expect(
      PaymentTerms.dayOfMonth(1).dueOn(DateTime(2026, 12, 31)),
      DateTime.utc(2027, 1, 1),
    );
  });
  test('invalid terms are rejected', () {
    expect(() => PaymentTerms.daysAfterIssue(-1), throwsArgumentError);
    expect(() => PaymentTerms.dayOfMonth(32), throwsRangeError);
    expect(
      () => PaymentTerms.dayOfMonth(15, rolloverWithinDays: -1),
      throwsRangeError,
    );
  });
}
