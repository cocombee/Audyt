import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/sales/domain/receivable_ageing.dart';
import 'package:audyt/core/money/money.dart';
void main() {
 test('age buckets use contractual due date boundaries', () {
  final due=DateTime.utc(2026,1,1);
  for(final entry in {-1:'Current',0:'Current',1:'1–30 Days',30:'1–30 Days',31:'31–60 Days',60:'31–60 Days',61:'61–90 Days',90:'61–90 Days',91:'Over 90 Days'}.entries) {
   expect(receivableAgeBucket(dueDate:due,asOf:due.add(Duration(days:entry.key))),entry.value);
  }
 });
 test('historical balances exclude later receipts and include the entire as-of day', () {
  final total=Money.fromMinor(10000,'MYR');
  final receipts=[(amount:Money.fromMinor(3000,'MYR'),date:DateTime.utc(2026,1,5,23)),(amount:Money.fromMinor(7000,'MYR'),date:DateTime.utc(2026,1,10))];
  expect(receivableRemainingAsOf(invoiceTotal:total,receipts:receipts,asOf:DateTime.utc(2026,1,4)).minorUnits,10000);
  expect(receivableRemainingAsOf(invoiceTotal:total,receipts:receipts,asOf:DateTime.utc(2026,1,5)).minorUnits,7000);
  expect(receivableRemainingAsOf(invoiceTotal:total,receipts:receipts,asOf:DateTime.utc(2026,1,10)).minorUnits,0);
 });
}
