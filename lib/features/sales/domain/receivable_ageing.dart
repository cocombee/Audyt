import '../../../core/dates/accounting_date.dart';
import '../../../core/dates/ageing_bucket.dart';
import '../../../core/money/money.dart';

/// Contractual overdue days, independent of approval or collection status.
String receivableAgeBucket({
  required DateTime dueDate,
  required DateTime asOf,
}) => accountingAgeBucket(dueDate: dueDate, asOf: asOf);

Money receivableRemainingAsOf({
  required Money invoiceTotal,
  required Iterable<({Money amount, DateTime date})> receipts,
  required DateTime asOf,
}) {
  var remaining = invoiceTotal;
  final date = accountingCalendarDate(asOf);
  for (final receipt in receipts) {
    if (!accountingCalendarDate(receipt.date).isAfter(date)) {
      remaining -= receipt.amount;
    }
  }
  if (remaining.isNegative) {
    throw StateError('Receipt allocations exceed the invoice total.');
  }
  return remaining;
}
