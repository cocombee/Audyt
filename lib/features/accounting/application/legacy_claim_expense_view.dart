import '../../../core/dates/accounting_date.dart';
import '../../purchases/domain/claim.dart';
import '../domain/expense_claim_source.dart';
import '../domain/expense_draft.dart';

/// Displays original legacy Claim facts in the existing Expense form.
/// Opening this adapter neither migrates a Claim nor posts an Expense.
RecordExpenseDraft legacyClaimExpenseView(Claim claim) {
  if (claim.expenseDraft != null) return claim.expenseDraft!;
  final bases = {for (final receipt in claim.receipts) receipt.taxMode};
  final mixed = bases.length > 1;
  final lines = [
    for (final receipt in claim.receipts)
      for (final line in receipt.lines) line.item,
    if (claim.receipts.isEmpty &&
        claim.category.isNotEmpty &&
        claim.amount.isPositive)
      ExpenseDraftLine(
        id: 'legacy-claim-${claim.id.value}',
        category: claim.category,
        description: '',
        tax: 'Not Recorded',
        amount: claim.amount.toDecimalString(),
      ),
  ];
  final draft = RecordExpenseDraft(
    amount: claim.amount.toDecimalString(),
    date: claim.incurredOn == null
        ? ''
        : formatAccountingInputDate(claim.incurredOn!),
    payee: claim.vendorName,
    paymentAccount: '',
    category: claim.category,
    tax: 'Not Recorded',
    customer: '',
    billable: false,
    dimensions: '',
    itemOrSplitDetails: '',
    notes: claim.businessPurpose,
    currencyCode: claim.amount.currency,
    submissionId: 'legacy-claim:${claim.id.value}',
    attachments: claim.attachments,
    lines: lines,
    taxMode: mixed
        ? ExpenseClaimSource.mixedBasis
        : bases.isEmpty
        ? null
        : bases.single,
    receiptLineBases: mixed
        ? {
            for (final receipt in claim.receipts)
              for (final line in receipt.lines) line.item.id: receipt.taxMode,
          }
        : const {},
  );
  // The same serialization/validation owner checks this view and its evidence.
  return RecordExpenseDraft.fromJson(draft.toJson());
}
