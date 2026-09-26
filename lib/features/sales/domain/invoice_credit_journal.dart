import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../accounting/domain/journal_entry.dart';
import 'invoice_credit.dart';

/// Proposed entries only. Persistence must validate original account ownership,
/// posting eligibility, period, reviewed revision and current prior allocations.
List<JournalLine> buildInvoiceCreditJournal({
  required Map<EntityId, InvoiceCreditLineAmounts> lineCredits,
  required Map<EntityId, EntityId> originalLineIncomeAccounts,
  required EntityId originalIncomeAccount,
  required EntityId originalReceivableAccount,
  required EntityId? originalTaxAccount,
  required EntityId? customerCreditAccount,
  required InvoiceCreditAllocation allocation,
}) {
  if (lineCredits.isEmpty) throw ArgumentError('Select credit lines.');
  final currency = allocation.receivableReduction.currency;
  var total = Money.zero(currency);
  final debits = <EntityId, Money>{};
  void debit(EntityId account, Money amount) {
    if (amount.isPositive) {
      debits.update(account, (old) => old + amount, ifAbsent: () => amount);
    }
  }

  for (final entry in lineCredits.entries) {
    total += entry.value.total;
    debit(
      originalLineIncomeAccounts[entry.key] ?? originalIncomeAccount,
      entry.value.net,
    );
    if (entry.value.tax.isPositive) {
      if (originalTaxAccount == null) {
        throw StateError('The original tax account is required.');
      }
      debit(originalTaxAccount, entry.value.tax);
    }
  }
  if (total != allocation.receivableReduction + allocation.customerCredit) {
    throw StateError('Credit lines must reconcile to the reviewed allocation.');
  }
  if (allocation.customerCredit.isPositive && customerCreditAccount == null) {
    throw StateError('Review a customer credit liability account.');
  }
  return List.unmodifiable([
    for (final entry in debits.entries)
      JournalLine.debit(accountId: entry.key, amount: entry.value),
    if (allocation.receivableReduction.isPositive)
      JournalLine.credit(
        accountId: originalReceivableAccount,
        amount: allocation.receivableReduction,
      ),
    if (allocation.customerCredit.isPositive)
      JournalLine.credit(
        accountId: customerCreditAccount!,
        amount: allocation.customerCredit,
      ),
  ]);
}
