import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/data/accounting_database.dart';
import '../features/accounting/domain/expense_intake.dart';
import '../features/purchases/domain/claim_store.dart';
import '../features/purchases/domain/claim.dart';
import '../features/purchases/domain/payment_voucher_store.dart';
import '../features/purchases/domain/payment_voucher.dart';
import 'feature_registry.dart';
import '../core/money/currency_presentation.dart';

/// One visible recommendation in the app-wide search.
class AccountingSearchResult {
  const AccountingSearchResult({
    required this.title,
    required this.type,
    required this.detail,
    required this.featureId,
    this.tab,
    this.extraTerms = '',
  });

  final String title;
  final String type;
  final String detail;
  final String featureId;
  final String? tab;
  final String extraTerms;

  bool matches(String query) {
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final haystack = '$title $type $detail $extraTerms'.toLowerCase();
    return words.every(haystack.contains);
  }
}

/// Cache connected non-journal destinations. Journal suggestions are queried
/// separately so a search never loads every journal and its lines.
Future<List<AccountingSearchResult>> loadNonJournalSearchResults({
  required ClaimStore claims,
  required PaymentVoucherStore vouchers,
  AccountingWorkspace? workspace,
  bool includeExpenses = true,
}) async {
  final results = <AccountingSearchResult>[
    for (final group in FeatureRegistry.navigationGroups)
      for (final feature in group.features)
        AccountingSearchResult(
          title: feature.label,
          type: 'Page',
          detail: group.label,
          featureId: feature.id,
        ),
    for (final claim in claims.all)
      AccountingSearchResult(
        title: claim.vendorName,
        type: 'Claim',
        detail: '${claim.claimantName} · ${claim.status.label}',
        extraTerms: '${claim.id.value} ${claim.businessPurpose}',
        featureId: 'claims',
        tab: 'Claims',
      ),
    for (final voucher in vouchers.all)
      AccountingSearchResult(
        title: voucher.payee,
        type: 'Payment Voucher',
        detail: '${voucher.reference} · ${voucher.status.label}',
        extraTerms: '${voucher.id} ${voucher.sourceId}',
        featureId: 'payment-vouchers',
        tab: 'Payment Vouchers',
      ),
  ];
  if (workspace == null) return results;

  final expenses = includeExpenses
      ? await workspace.expenses()
      : const <ExpenseIntakeSummary>[];
  final accounts = await workspace.accounts();
  results.addAll([
    for (final expense in expenses)
      AccountingSearchResult(
        title: expense.payee,
        type: 'Expense',
        detail: expense.category,
        extraTerms: '${expense.id.value} ${expense.amount}',
        featureId: 'expenses-vendors',
        tab: 'Expenses',
      ),
    for (final template in workspace.database.recurringExpenseTemplates(
      workspace.identity.businessId,
    ))
      AccountingSearchResult(
        title: template.payee,
        type: 'Recurring Expense',
        detail: template.paused ? 'Paused' : 'Active',
        extraTerms: '${template.id} ${template.sourceExpenseId}',
        featureId: 'expenses-vendors',
        tab: 'Expenses',
      ),
    for (final customer in workspace.customers())
      AccountingSearchResult(
        title: customer.displayName,
        type: 'Customer',
        detail: customer.contact.email ?? '',
        extraTerms: '${customer.contact.phone ?? ''} ${customer.id.value}',
        featureId: 'sales-customers',
        tab: 'Customers',
      ),
    for (final record in workspace.invoiceDrafts())
      AccountingSearchResult(
        title: record.invoice.documentNumber.isEmpty
            ? 'Invoice Draft'
            : record.invoice.documentNumber,
        type: 'Invoice Draft',
        detail: record.invoice.reference,
        extraTerms: '${record.invoice.memo} ${record.invoice.id.value}',
        featureId: 'sales-customers',
        tab: 'Invoices',
      ),
    for (final record in workspace.postedInvoices())
      AccountingSearchResult(
        title: record.documentNumber,
        type: 'Invoice',
        detail: record.sourceDraft.reference,
        extraTerms: '${record.sourceDraft.memo} ${record.sourceDraft.id.value}',
        featureId: 'sales-customers',
        tab: 'Invoices',
      ),
    for (final credit in workspace.creditDrafts())
      AccountingSearchResult(
        title: credit.reason,
        type: 'Credit Note',
        detail: credit.id.value,
        extraTerms: credit.invoiceId.value,
        featureId: 'sales-customers',
        tab: 'Credit Notes',
      ),
    for (final account in accounts)
      AccountingSearchResult(
        title: account.account.name,
        type: 'Account',
        detail: account.account.code,
        extraTerms: account.account.id.value,
        featureId: 'accounting',
        tab: 'Chart Of Accounts',
      ),
    for (final paymentAccount in workspace.paymentAccounts)
      AccountingSearchResult(
        title: paymentAccount.name,
        type: 'Payment Account',
        detail: CurrencyPresentation.fromCode(paymentAccount.currency.code)
            .amountSymbol,
        extraTerms: '${paymentAccount.id} ${paymentAccount.currency.code}',
        featureId: 'banking',
        tab: 'Bank Activity',
      ),
    for (final paymentAccount in workspace.paymentAccounts)
      for (final statement in workspace.database.bankStatements(
        workspace.identity.businessId,
        paymentAccount.id,
      ))
        AccountingSearchResult(
          title: statement.filename,
          type: 'Bank Statement',
          detail: paymentAccount.name,
          extraTerms: statement.id.value,
          featureId: 'banking',
          tab: 'Bank Activity',
        ),
    for (final receipt in workspace.database.customerReceiptHistory(
      workspace.identity.businessId,
    ))
      AccountingSearchResult(
        title: receipt.reference,
        type: 'Customer Receipt',
        detail: receipt.customer,
        extraTerms:
            '${receipt.requestId} ${receipt.allocations.map((a) => a.number).join(' ')}',
        featureId: 'sales-customers',
        tab: 'Receive Payment',
      ),
  ]);
  return results;
}

/// On-demand expense suggestions preserve the existing visible result fields
/// and order without materializing every expense in the shell cache.
List<AccountingSearchResult> searchExpenseResults({
  required AccountingWorkspace workspace,
  required String query,
  int limit = 12,
}) => [
  for (final expense in workspace.database.searchExpenseIntakes(
    businessId: workspace.identity.businessId,
    query: query,
    limit: limit,
  ))
    AccountingSearchResult(
      title: expense.payee,
      type: 'Expense',
      detail: expense.category,
      extraTerms: '${expense.id.value} ${expense.amount}',
      featureId: 'expenses-vendors',
      tab: 'Expenses',
    ),
];

/// Search only stored company journal summaries, preserving the existing
/// title, detail and destination contract without reading journal lines.
List<AccountingSearchResult> searchJournalResults({
  required AccountingWorkspace workspace,
  required String query,
  int limit = 12,
}) => [
  for (final journal in workspace.database.searchJournalSummaries(
    businessId: workspace.identity.businessId,
    query: query,
    limit: limit,
  ))
    AccountingSearchResult(
      title: journal.memo,
      type: 'Journal',
      detail: journal.state,
      extraTerms: journal.id,
      featureId: 'accountant-review',
      tab: 'Journal Review',
    ),
];

/// Query Bill suggestions on demand so global search never loads every Bill
/// source or its immutable revisions into the shell cache.
List<AccountingSearchResult> searchBillResults({
  required AccountingWorkspace workspace,
  required String query,
  int limit = 12,
}) => [
  for (final match in workspace.database.searchBillDrafts(
    businessId: workspace.identity.businessId,
    query: query,
    limit: limit,
  ))
    AccountingSearchResult(
      title: match.bill.documentNumber,
      type: match.reversed
          ? 'Reversed Bill'
          : match.posted
          ? 'Bill'
          : 'Bill Draft',
      detail: match.bill.vendorSnapshot.name,
      extraTerms:
          '${match.bill.supplierReference} ${match.bill.memo} ${match.bill.id.value}',
      featureId: 'expenses-vendors',
      tab: 'Bills',
    ),
];
