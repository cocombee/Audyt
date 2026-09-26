import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/invoice_credit.dart';
import 'package:audyt/features/sales/domain/invoice_credit_journal.dart';

void main(){
  test('credit proposal uses original accounts and separates excess credit',(){
    Money m(int n)=>Money.fromMinor(n,'MYR');
    final line=EntityId.random(),sales=EntityId.random(),tax=EntityId.random(),ar=EntityId.random(),liability=EntityId.random();
    final amounts=InvoiceCreditLineAmounts.calculate(originalNet:m(10000),originalTax:m(800),priorGrossCredit:m(0),grossCredit:m(5400));
    final allocation=InvoiceCreditAllocation.calculate(invoiceTotal:m(10800),priorCredits:m(0),receiptsApplied:m(8000),credit:m(5400));
    proposal({EntityId? taxAccount,EntityId? creditAccount})=>buildInvoiceCreditJournal(lineCredits:{line:amounts},originalLineIncomeAccounts:{line:sales},originalIncomeAccount:EntityId.random(),originalReceivableAccount:ar,originalTaxAccount:taxAccount,customerCreditAccount:creditAccount,allocation:allocation);
    final lines=proposal(taxAccount:tax,creditAccount:liability);
    expect(lines.singleWhere((l)=>l.accountId==sales).amount,m(5000));
    expect(lines.singleWhere((l)=>l.accountId==tax).amount,m(400));
    expect(lines.singleWhere((l)=>l.accountId==ar).amount,m(2800));
    expect(lines.singleWhere((l)=>l.accountId==liability).amount,m(2600));
    expect(()=>proposal(creditAccount:liability),throwsStateError);
    expect(()=>proposal(taxAccount:tax),throwsStateError);
  });
}
