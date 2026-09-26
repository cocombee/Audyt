import 'accounting_date.dart';

/// Contractual overdue age in the company's supplied calendar, for both sides
/// of the ledger. A balance due today is current, not one day overdue.
String accountingAgeBucket({
  required DateTime dueDate,
  required DateTime asOf,
}) {
  final days = accountingCalendarDate(asOf)
      .difference(accountingCalendarDate(dueDate))
      .inDays;
  if (days <= 0) return 'Current';
  if (days <= 30) return '1–30 Days';
  if (days <= 60) return '31–60 Days';
  if (days <= 90) return '61–90 Days';
  return 'Over 90 Days';
}

const accountingAgeBuckets = <String>[
  'Current',
  '1–30 Days',
  '31–60 Days',
  '61–90 Days',
  'Over 90 Days',
];
