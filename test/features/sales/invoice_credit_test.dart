import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice_credit.dart';

void main() {
  Money m(int amount) => Money.fromMinor(amount, 'MYR');
  test('credit reduces unpaid balance and retains excess customer credit', () {
    final result = InvoiceCreditAllocation.calculate(
      invoiceTotal: m(10000),
      priorCredits: m(0),
      receiptsApplied: m(6000),
      credit: m(7000),
    );
    expect(result.receivableReduction, m(4000));
    expect(result.customerCredit, m(3000));
    expect(result.remainingReceivable, m(0));
    final next = InvoiceCreditAllocation.calculate(
      invoiceTotal: m(10000),
      priorCredits: m(7000),
      receiptsApplied: m(6000),
      credit: m(3000),
    );
    expect(next.receivableReduction, m(0));
    expect(next.customerCredit, m(3000));
  });
  test('unpaid, fully paid and cumulative limits use exact minor units', () {
    for (final paid in [0, 1, 9999, 10000]) {
      final r = InvoiceCreditAllocation.calculate(
        invoiceTotal: m(10000),
        priorCredits: m(0),
        receiptsApplied: m(paid),
        credit: m(10000),
      );
      expect(r.receivableReduction + m(paid), m(10000));
      expect(r.customerCredit, m(paid));
      expect(r.remainingReceivable, m(0));
    }
    expect(
      () => InvoiceCreditAllocation.calculate(
        invoiceTotal: m(10000),
        priorCredits: m(9000),
        receiptsApplied: m(0),
        credit: m(1001),
      ),
      throwsStateError,
    );
    expect(
      () => InvoiceCreditAllocation.calculate(
        invoiceTotal: m(10000),
        priorCredits: m(0),
        receiptsApplied: m(0),
        credit: Money.fromMinor(1, 'USD'),
      ),
      throwsArgumentError,
    );
    expect(
      () => InvoiceCreditAllocation.calculate(
        invoiceTotal: m(10000),
        priorCredits: m(0),
        receiptsApplied: m(-1),
        credit: m(1),
      ),
      throwsArgumentError,
    );
  });
  test(
    'successive credit lines retain original tax without cumulative drift',
    () {
      for (final net in [1, 17, 100, 6481]) {
        final originalTax = net ~/ 8 + 1;
        final gross = net + originalTax;
        var prior = 0;
        var totalNet = 0;
        var totalTax = 0;
        while (prior < gross) {
          final chunk = (gross - prior) > 13 ? 13 : gross - prior;
          final result = InvoiceCreditLineAmounts.calculate(
            originalNet: m(net),
            originalTax: m(originalTax),
            priorGrossCredit: m(prior),
            grossCredit: m(chunk),
          );
          expect(result.total, m(chunk));
          expect(result.net.isNegative, isFalse);
          expect(result.tax.isNegative, isFalse);
          totalNet += result.net.minorUnits;
          totalTax += result.tax.minorUnits;
          prior += chunk;
        }
        expect(totalNet, net);
        expect(totalTax, originalTax);
      }
      expect(
        () => InvoiceCreditLineAmounts.calculate(
          originalNet: m(100),
          originalTax: m(8),
          priorGrossCredit: m(108),
          grossCredit: m(1),
        ),
        throwsStateError,
      );
    },
  );
  test('credit amounts bind only to original stable line identities', () {
    final line=SalesLineItem.category(id:EntityId.random(),categoryId:EntityId.random(),description:'Service',quantity:SalesQuantity.fromInt(1),rate:m(10800),taxRatePercent:'8',taxInclusive:true);
    final result=allocateInvoiceCreditLines(originalLines:[line],priorGrossCredits:{},requestedGrossCredits:{line.id:m(5400)});
    expect(result[line.id]!.net,m(5000));
    expect(result[line.id]!.tax,m(400));
    expect(()=>allocateInvoiceCreditLines(originalLines:[line],priorGrossCredits:{},requestedGrossCredits:{EntityId.random():m(1)}),throwsArgumentError);
    expect(()=>allocateInvoiceCreditLines(originalLines:[line,line],priorGrossCredits:{},requestedGrossCredits:{line.id:m(1)}),throwsStateError);
    expect(()=>allocateInvoiceCreditLines(originalLines:[line],priorGrossCredits:{line.id:m(10801)},requestedGrossCredits:{line.id:m(1)}),throwsStateError);
  });

}
