import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../purchases/domain/claim.dart';
import '../domain/expense_claim_source.dart';
import '../domain/expense_draft.dart';

/// One Expense view of the already-posted recognition, without normalization
/// of original receipt amounts or a second accounting command.
RecordExpenseDraft approvedClaimExpense({
  required Claim claim,
  required EntityId recognitionId,
  required EntityId liabilityAccountId,
  required String liabilityAccountName,
  required DateTime approvedAt,
}) {
  final date = claim.incurredOn;
  if (date == null) {
    throw const FormatException('Claim recognition date is missing.');
  }
  final bases = {for (final receipt in claim.receipts) receipt.taxMode};
  final source = ExpenseClaimSource(
    claimId: claim.id,
    recognitionId: recognitionId,
    liabilityAccountId: liabilityAccountId,
    claimantName: claim.claimantName,
    claimantId: claim.claimantIdentity?.payeeId,
    claimantType: claim.claimantIdentity?.type.name,
    approvedAt: approvedAt,
    lineBases: {
      for (final receipt in claim.receipts)
        for (final line in receipt.lines) line.item.id: receipt.taxMode,
    },
  );
  final expense = claim.expenseDraft;
  if (expense != null) {
    return RecordExpenseDraft.fromJson({
      ...expense.toJson(),
      'version': 3,
      'claimSource': source.toJson(),
      'paymentAccount': liabilityAccountName,
      'paymentAccountId': null,
    });
  }
  final draft = RecordExpenseDraft(
    amount: claim.amount.toDecimalString(),
    date: formatAccountingInputDate(date),
    payee: claim.vendorName,
    // This is the frozen reimbursement liability, not a company bank account.
    paymentAccount: liabilityAccountName,
    category: claim.category,
    tax: 'Not Recorded',
    customer: '',
    billable: false,
    dimensions: '',
    itemOrSplitDetails: '',
    notes: claim.businessPurpose,
    currencyCode: claim.amount.currency,
    attachments: claim.attachments,
    submissionId: 'claim:${claim.id.value}:${recognitionId.value}',
    lines: [
      for (final receipt in claim.receipts)
        for (final line in receipt.lines) line.item,
    ],
    taxMode: bases.isEmpty
        ? null
        : bases.length == 1
        ? bases.single
        : ExpenseClaimSource.mixedBasis,
    claimSource: source,
  );
  draft.validateLines();
  return draft;
}
