import 'tax_remittance_candidate.dart';
import '../../sales/domain/estimate.dart';
import '../../sales/domain/product_catalogue.dart';
import '../../sales/domain/sales_report.dart';
import '../domain/workspace_reminder.dart';
import '../domain/company_preferences.dart';
import '../domain/expense_revision.dart';
import '../domain/company_tax_rate.dart';
import '../domain/company_tax_agency.dart';
import '../domain/tax_remittance.dart';
import '../domain/recurring_document_template.dart';
import '../domain/recurrence_rule.dart';
import '../../../core/documents/receipt_document.dart';
import '../../../core/money/money.dart';
import '../../purchases/domain/claim.dart';
import '../../purchases/domain/claim_payment_batch.dart';
import '../../sales/domain/invoice.dart';
import '../../sales/domain/invoice_credit_draft.dart';
import '../../sales/domain/invoice_credit.dart';
import '../../sales/domain/invoice_credit_journal.dart';
import '../domain/customer.dart';
import '../../purchases/domain/payment_voucher_store.dart';
import '../../purchases/domain/claim_store.dart';
import '../domain/payment_account.dart';
import '../domain/payee.dart';

import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

import '../domain/closing_proposal.dart';
import '../domain/ledger_report.dart';
import '../domain/tax_activity_report.dart';
import '../domain/claimant_statement.dart';
import '../domain/claim_reimbursement_position.dart';
import '../domain/transaction_removal.dart';
import '../domain/expense_draft.dart';
import '../domain/expense_intake.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/workspace_identity.dart';

import '../../purchases/domain/vendor.dart';
import '../../purchases/domain/purchase_bill_draft.dart';

import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';

final class BankReviewNotice {
  const BankReviewNotice({
    required this.id,
    required this.title,
    required this.date,
    required this.isStatement,
  });

  final String id;
  final String title;
  final DateTime date;
  final bool isStatement;
}

final class BankReviewSnapshot {
  const BankReviewSnapshot({
    required this.unresolvedRows,
    required this.awaitingApproval,
    required this.recent,
  });

  final int unresolvedRows;
  final int awaitingApproval;
  final List<BankReviewNotice> recent;
  int get total => unresolvedRows + awaitingApproval;
}

int _compareBankReviewNotices(BankReviewNotice a, BankReviewNotice b) {
  final byDate = b.date.compareTo(a.date);
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

final class AccountingWorkspace extends ChangeNotifier {
  AccountingWorkspace._(this.database, this.identity, {this.restoredCopyId}) {
    vouchers = database.openVoucherStore(
      identity.businessId,
      actorId: identity.ownerId,
    );
    claims = database.openClaimStore(identity.businessId);
    payees = PayeeStore(
      payees: database.readPayees(identity.businessId),
      persist: (payee) => database.savePayee(identity.businessId, payee),
    );
  }
  RecurringDocumentTemplate saveDocumentSchedule({
    required String id,
    required String name,
    required RecurringDocumentKind kind,
    required EntityId sourceId,
    required int sourceRevision,
    required int expectedRevision,
    required RecurrenceRule schedule,
    bool paused = false,
  }) {
    final result = database.saveDocumentSchedule(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      id: id,
      name: name,
      kind: kind,
      sourceId: sourceId,
      sourceRevision: sourceRevision,
      expectedRevision: expectedRevision,
      schedule: schedule,
      savedAt: DateTime.now().toUtc(),
      paused: paused,
    );
    notifyListeners();
    return result;
  }

  void changeDocumentScheduleState(
    RecurringDocumentTemplate template, {
    bool? paused,
    bool cancel = false,
  }) {
    database.changeDocumentScheduleState(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      id: template.id,
      expectedRevision: template.revision,
      savedAt: DateTime.now().toUtc(),
      paused: paused,
      cancel: cancel,
    );
    notifyListeners();
  }

  String prepareDocumentOccurrence(
    RecurringDocumentTemplate template,
    int index,
  ) {
    final now = DateTime.now();
    final result = database.prepareDocumentOccurrence(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      templateId: template.id,
      expectedRevision: template.revision,
      index: index,
      preparedAt: now.toUtc(),
      asOf: now,
    );
    notifyListeners();
    return result;
  }

  List<StoredAccount> get taxRemittanceLiabilityAccounts =>
      database.readTaxRemittanceLiabilityAccounts(identity.businessId);
  List<PaymentAccount> get taxRemittancePaymentAccounts =>
      database.readTaxRemittancePaymentAccounts(identity.businessId);
  List<TaxRemittanceCandidate> taxRemittanceCandidates(
    String paymentAccountId,
  ) => database.readTaxRemittanceCandidates(
    identity.businessId,
    paymentAccountId,
  );

  List<TaxRemittance> taxRemittances({bool includeCorrected = false}) =>
      database.readTaxRemittances(
        identity.businessId,
        includeCorrected: includeCorrected,
      );
  TaxRemittance recordTaxRemittance({
    required EntityId requestId,
    required String paymentAccountId,
    required List<TaxRemittanceAllocation> allocations,
    List<ReceiptAttachment> attachments = const [],
    required DateTime paidOn,
    required String reference,
    String memo = '',
    required DateTime recordedAt,
  }) {
    final result = database.recordTaxRemittance(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      paymentAccountId: paymentAccountId,
      allocations: allocations,
      attachments: attachments,
      paidOn: paidOn,
      reference: reference,
      memo: memo,
      recordedAt: recordedAt,
    );
    notifyListeners();
    return result;
  }

  TaxRemittance linkTaxRemittance({
    required EntityId requestId,
    required StoredJournalEntry reviewedJournal,
    required String paymentAccountId,
    required List<TaxRemittanceAllocation> allocations,
    List<ReceiptAttachment> attachments = const [],
    required String reference,
    String memo = '',
    required DateTime recordedAt,
  }) {
    final result = database.linkTaxRemittance(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedJournal: reviewedJournal,
      paymentAccountId: paymentAccountId,
      allocations: allocations,
      attachments: attachments,
      reference: reference,
      memo: memo,
      recordedAt: recordedAt,
    );
    notifyListeners();
    return result;
  }

  TaxRemittanceCorrection correctTaxRemittance({
    required EntityId requestId,
    required TaxRemittance reviewedRemittance,
    required DateTime on,
    required DateTime recordedAt,
    required String reason,
  }) {
    final result = database.correctTaxRemittance(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedRemittance: reviewedRemittance,
      on: on,
      recordedAt: recordedAt,
      reason: reason,
    );
    notifyListeners();
    return result;
  }

  List<CompanyTaxAgency> get taxAgencies =>
      database.readTaxAgencies(identity.businessId);
  CompanyTaxAgency saveTaxAgency(CompanyTaxAgency agency) {
    final saved = database.saveTaxAgency(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      agency: agency,
      savedAt: DateTime.now().toUtc(),
    );
    notifyListeners();
    return saved;
  }

  List<CompanyTaxRate> get taxRates =>
      database.readTaxRates(identity.businessId);
  CompanyTaxRate saveTaxRate(CompanyTaxRate rate) {
    final saved = database.saveTaxRate(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      rate: rate,
      savedAt: DateTime.now().toUtc(),
    );
    notifyListeners();
    return saved;
  }

  List<WorkspaceReminder> get reminders =>
      database.readReminders(identity.businessId);
  void saveReminder(WorkspaceReminder reminder) => saveReminders([reminder]);
  void saveReminders(List<WorkspaceReminder> reminders) {
    database.saveReminders(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      reminders: reminders,
      savedAt: DateTime.now().toUtc(),
    );
    if (!_closed) notifyListeners();
  }

  CompanyPreferences get preferences =>
      database.readCompanyPreferences(identity.businessId);
  List<CatalogueCategory> get catalogueCategories =>
      database.readCatalogueCategories(identity.businessId);
  List<CatalogueItem> get catalogueItems =>
      database.readCatalogueItems(identity.businessId);
  CatalogueCategory saveCatalogueCategory(CatalogueCategory category) {
    final saved = database.saveCatalogueCategory(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      category: category,
      savedAt: DateTime.now().toUtc(),
    );
    if (!_closed) notifyListeners();
    return saved;
  }

  CatalogueItem saveCatalogueItem(CatalogueItem item) {
    final saved = database.saveCatalogueItem(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      item: item,
      savedAt: DateTime.now().toUtc(),
    );
    if (!_closed) notifyListeners();
    return saved;
  }

  void savePreferences(CompanyPreferences preferences) {
    database.saveCompanyPreferences(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      preferences: preferences,
      savedAt: DateTime.now().toUtc(),
    );
    if (!_closed) notifyListeners();
  }

  late final PayeeStore payees;
  late final ClaimStore claims;
  Map<EntityId, Claim> get claimRecognitionSnapshots =>
      database.readClaimRecognitionSnapshots(identity.businessId);
  late final PaymentVoucherStore vouchers;
  EntityId approveClaim({
    required Claim reviewedClaim,
    required EntityId requestId,
    EntityId? expenseAccountId,
    Map<String, EntityId>? expenseLineAccounts,
    required EntityId liabilityAccountId,
    required DateTime approvedAt,
  }) {
    final result = database.approveClaimPosting(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedClaim: reviewedClaim,
      expenseAccountId: expenseAccountId,
      expenseLineAccounts: expenseLineAccounts,
      liabilityAccountId: liabilityAccountId,
      approvedAt: approvedAt,
    );
    claims.reload();
    if (!_closed) notifyListeners();
    return result;
  }

  EntityId? activeClaimRecognitionId(EntityId claimId) =>
      database.activeClaimRecognitionId(identity.businessId, claimId);

  EntityId reverseClaimRecognition({
    required Claim reviewedClaim,
    required EntityId requestId,
    required EntityId expectedRecognitionJournalId,
    required ClaimRecognitionDecision decision,
    required DateTime reversedOn,
    required String reason,
    required DateTime changedAt,
  }) {
    final result = database.reverseClaimRecognition(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedClaim: reviewedClaim,
      expectedRecognitionJournalId: expectedRecognitionJournalId,
      decision: decision,
      reversedOn: reversedOn,
      reason: reason,
      changedAt: changedAt,
    );
    claims.reload();
    if (!_closed) notifyListeners();
    return result;
  }

  ClaimPaymentBatch settleClaims({
    required List<Claim> reviewedClaims,
    required EntityId requestId,
    required EntityId bankAccountId,
    required String paymentReference,
    required DateTime paidAt,
    String? paymentAccountId,
  }) {
    final result = database.settleRecognizedClaims(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedClaims: reviewedClaims,
      bankAccountId: bankAccountId,
      paymentReference: paymentReference,
      paidAt: paidAt,
      paymentAccountId: paymentAccountId,
    );
    claims.reload();
    if (!_closed) notifyListeners();
    return result;
  }

  List<PaymentAccount> get paymentAccounts =>
      database.readPaymentAccounts(identity.businessId);

  BankReviewSnapshot? _bankReviewSnapshot;
  (int, int)? _bankReviewSnapshotChangeToken;

  /// Retain only the newest notices for the top bar while keeping exact badge
  /// totals. A SQLite write invalidates the snapshot, including direct banking
  /// commands that do not pass through a workspace wrapper.
  BankReviewSnapshot get bankReviewSnapshot {
    final changeToken = database.changeToken;
    if (_bankReviewSnapshot != null &&
        _bankReviewSnapshotChangeToken == changeToken) {
      return _bankReviewSnapshot!;
    }
    var unresolved = 0;
    var awaitingApproval = 0;
    final recent = <BankReviewNotice>[];
    void keep(BankReviewNotice notice) {
      if (recent.length == 50 &&
          _compareBankReviewNotices(notice, recent.last) >= 0) {
        return;
      }
      recent.add(notice);
      recent.sort(_compareBankReviewNotices);
      if (recent.length > 50) recent.removeLast();
    }

    for (final account in paymentAccounts) {
      for (final item in database.bankStatements(
        identity.businessId,
        account.id,
      )) {
        final statement = database.bankStatement(identity.businessId, item.id);
        if (statement == null) continue;
        final accepted = database.acceptedStatementMatches(
          identity.businessId,
          item.id,
        );
        for (final row in statement.rows) {
          if (accepted.containsKey(row.sourceRow)) continue;
          unresolved++;
          keep(
            BankReviewNotice(
              id: 'bank-${item.id.value}-${row.sourceRow}',
              title: row.description.isEmpty ? item.filename : row.description,
              date: row.date,
              isStatement: false,
            ),
          );
        }
        if (!database.isStatementReconciled(identity.businessId, item.id)) {
          awaitingApproval++;
          keep(
            BankReviewNotice(
              id: 'statement-${item.id.value}',
              title: item.filename,
              date:
                  statement.statementDate ??
                  (statement.rows.isEmpty
                      ? DateTime.fromMillisecondsSinceEpoch(0)
                      : statement.rows.last.date),
              isStatement: true,
            ),
          );
        }
      }
    }
    final snapshot = BankReviewSnapshot(
      unresolvedRows: unresolved,
      awaitingApproval: awaitingApproval,
      recent: List.unmodifiable(recent),
    );
    _bankReviewSnapshot = snapshot;
    _bankReviewSnapshotChangeToken = changeToken;
    return snapshot;
  }

  int get unresolvedBankStatementRows => bankReviewSnapshot.unresolvedRows;
  int get bankStatementsAwaitingApproval => bankReviewSnapshot.awaitingApproval;
  int get bankReviewNotificationCount => bankReviewSnapshot.total;

  void refreshBankStatementReview() {
    _bankReviewSnapshot = null;
    if (!_closed) notifyListeners();
  }

  void savePaymentAccount(PaymentAccount account) {
    database.savePaymentAccount(identity.businessId, account);
    notifyListeners();
  }

  static const storageChannel = MethodChannel('audyt/local-storage');
  final LocalAccountingDatabase database;
  final WorkspaceIdentity identity;

  /// Device-local recovery identity; never changes accounting record ownership.
  final String? restoredCopyId;
  bool _closed = false;

  static Future<AccountingWorkspace> openDefault() async {
    final path = await storageChannel.invokeMethod<String>('databasePath');
    if (path == null || path.isEmpty) {
      throw StateError('The local accounting storage location is unavailable.');
    }
    return open(path);
  }

  static Future<AccountingWorkspace> open(String path) async {
    final database = LocalAccountingDatabase.open(path);
    try {
      final identity = await database.openWorkspace(
        newBusinessId: newId(),
        newDeviceId: newId(),
        newOwnerId: newId(),
        defaultCurrency: 'MYR',
      );
      return AccountingWorkspace._(database, identity);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  static Future<AccountingWorkspace> emptyRestore(
    String path,
    String archive,
  ) async {
    final database = LocalAccountingDatabase.open(path);
    try {
      database.restoreDataArchive(archive);
      final identity = await database.openWorkspace(
        newBusinessId: newId(),
        newDeviceId: newId(),
        newOwnerId: newId(),
        defaultCurrency: 'MYR',
      );
      return AccountingWorkspace._(database, identity);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  static Future<AccountingWorkspace> openExisting(
    String path, {
    required EntityId businessId,
    required String restoredCopyId,
  }) async {
    EntityId.parse(restoredCopyId);
    final database = LocalAccountingDatabase.openExisting(
      path,
      businessId: businessId,
    );
    try {
      final identity = await database.openWorkspace(
        newBusinessId: newId(),
        newDeviceId: newId(),
        newOwnerId: newId(),
        defaultCurrency: 'MYR',
        createIfMissing: false,
      );
      database.trackRestoredTransactionRoots(identity.businessId);
      return AccountingWorkspace._(
        database,
        identity,
        restoredCopyId: restoredCopyId,
      );
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  List<({Invoice invoice, int revision})> invoiceDrafts({
    bool archived = false,
  }) => database.readInvoiceDrafts(identity.businessId, archived: archived);

  List<
    ({
      Invoice sourceDraft,
      Customer customerSnapshot,
      int paidMinor,
      int creditedMinor,
      String documentNumber,
      EntityId journalId,
    })
  >
  postedInvoices() => database.readPostedInvoices(identity.businessId);

  List<
    ({
      EntityId id,
      EntityId invoiceId,
      int revision,
      DateTime savedAt,
      Map<String, dynamic> snapshot,
    })
  >
  invoiceCreditDrafts({bool includeRemoved = false}) =>
      database.readInvoiceCreditDrafts(
        identity.businessId,
        includeRemoved: includeRemoved,
      );

  List<InvoiceCreditDraft> creditDrafts({bool includeRemoved = false}) => [
    for (final row in invoiceCreditDrafts(includeRemoved: includeRemoved))
      InvoiceCreditDraft.fromSnapshot(
        id: row.id,
        invoiceId: row.invoiceId,
        revision: row.revision,
        savedAt: row.savedAt,
        snapshot: row.snapshot,
      ),
  ];

  ({
    InvoiceCreditDraft draft,
    Map<EntityId, InvoiceCreditLineAmounts> lines,
    InvoiceCreditAllocation allocation,
    int paidMinor,
    int priorCreditMinor,
  })
  reviewCreditDraft(EntityId draftId) {
    final draft = creditDrafts().where((d) => d.id == draftId).firstOrNull;
    if (draft == null) throw StateError('Credit draft is unavailable.');
    final invoice = postedInvoices()
        .where((r) => r.sourceDraft.id == draft.invoiceId)
        .firstOrNull;
    if (invoice == null ||
        database.invoicePostingAccounts(identity.businessId, draft.invoiceId) ==
            null) {
      throw StateError('Original invoice posting is unavailable.');
    }
    final priorLines = database.invoicePriorCreditLines(
      identity.businessId,
      draft.invoiceId,
    );
    final priorTotal = priorLines.values.fold(
      Money.zero(draft.total.currency),
      (a, b) => a + b,
    );
    final lines = allocateInvoiceCreditLines(
      originalLines: invoice.sourceDraft.lines,
      priorGrossCredits: priorLines,
      requestedGrossCredits: draft.lineCredits,
    );
    final allocation = InvoiceCreditAllocation.calculate(
      invoiceTotal: invoice.sourceDraft.total,
      priorCredits: priorTotal,
      receiptsApplied: Money.fromMinor(invoice.paidMinor, draft.total.currency),
      credit: draft.total,
    );
    return (
      draft: draft,
      lines: lines,
      allocation: allocation,
      paidMinor: invoice.paidMinor,
      priorCreditMinor: priorTotal.minorUnits,
    );
  }

  EntityId postInvoiceCredit({
    required EntityId requestId,
    required EntityId draftId,
    required int expectedRevision,
    required int expectedPaidMinor,
    required int expectedPriorCreditMinor,
    required DateTime approvedAt,
    EntityId? customerCreditAccount,
  }) {
    final id = database.postInvoiceCredit(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      draftId: draftId,
      expectedRevision: expectedRevision,
      expectedPaidMinor: expectedPaidMinor,
      expectedPriorCreditMinor: expectedPriorCreditMinor,
      approvedAt: approvedAt,
      customerCreditAccount: customerCreditAccount,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  Future<List<JournalLine>> creditDraftJournal(
    EntityId draftId, {
    EntityId? customerCreditAccount,
  }) async {
    final available = {
      for (final stored in await accounts()) stored.account.id: stored.account,
    };
    final review = reviewCreditDraft(draftId);
    final original = database.invoicePostingAccounts(
      identity.businessId,
      review.draft.invoiceId,
    )!;
    void validate(EntityId id, AccountType type) {
      final account = available[id];
      if (account == null ||
          account.type != type ||
          account.status != AccountStatus.active ||
          account.isParent) {
        throw StateError(
          'Credit review requires active posting accounts in this company.',
        );
      }
    }

    validate(original.receivable, AccountType.asset);
    for (final line in review.lines.keys) {
      validate(
        original.lineIncome[line] ?? original.income,
        AccountType.income,
      );
    }
    if (review.lines.values.any((line) => line.tax.isPositive)) {
      if (original.tax == null) {
        throw StateError('Original invoice tax account is missing.');
      }
      validate(original.tax!, AccountType.liability);
    }
    if (review.allocation.customerCredit.isPositive) {
      if (customerCreditAccount == null) {
        throw StateError('Choose a customer credit liability account.');
      }
      validate(customerCreditAccount, AccountType.liability);
      if (customerCreditAccount == original.tax) {
        throw StateError(
          'Customer credit must use a separate liability account from tax.',
        );
      }
    }
    return buildInvoiceCreditJournal(
      lineCredits: review.lines,
      originalLineIncomeAccounts: original.lineIncome,
      originalIncomeAccount: original.income,
      originalReceivableAccount: original.receivable,
      originalTaxAccount: original.tax,
      customerCreditAccount: customerCreditAccount,
      allocation: review.allocation,
    );
  }

  List<InvoiceCreditDraft> creditDraftHistory(EntityId draftId) => [
    for (final row in database.invoiceCreditDraftHistory(
      identity.businessId,
      draftId,
    ))
      InvoiceCreditDraft.fromSnapshot(
        id: draftId,
        invoiceId: EntityId.parse(row.snapshot['invoiceId'] as String),
        revision: row.revision,
        savedAt: row.savedAt,
        snapshot: row.snapshot,
      ),
  ];

  int restoreCreditDraftRevision({
    required EntityId draftId,
    required int sourceRevision,
    required int expectedRevision,
    required DateTime restoredAt,
  }) {
    final source = creditDraftHistory(draftId)
        .where((r) => r.revision == sourceRevision)
        .firstOrNull;
    if (source == null) {
      throw StateError('Saved credit revision is unavailable.');
    }
    return saveInvoiceCreditDraft(
      draftId: draftId,
      invoiceId: source.invoiceId,
      lineCredits: source.lineCredits,
      reason: source.reason,
      creditDate: source.date,
      expectedRevision: expectedRevision,
      savedAt: restoredAt,
      attachments: source.attachments,
    );
  }

  int saveInvoiceCreditDraft({
    List<ReceiptAttachment> attachments = const [],
    required EntityId draftId,
    required EntityId invoiceId,
    required Map<EntityId, Money> lineCredits,
    required String reason,
    required DateTime creditDate,
    required int expectedRevision,
    required DateTime savedAt,
  }) {
    final revision = database.saveInvoiceCreditDraft(
      attachments: attachments,
      businessId: identity.businessId,
      actorId: identity.ownerId,
      draftId: draftId,
      invoiceId: invoiceId,
      lineCredits: lineCredits,
      reason: reason,
      creditDate: creditDate,
      expectedRevision: expectedRevision,
      savedAt: savedAt,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  EntityId receiveInvoicePayment({
    required EntityId requestId,
    required EntityId customerId,
    required EntityId bankAccountId,
    required Map<EntityId, Money> allocations,
    required String reference,
    required DateTime receivedAt,
    DateTime? approvedAt,
    String? paymentAccountId,
  }) {
    final result = database.receiveInvoicePayment(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      customerId: customerId,
      bankAccountId: bankAccountId,
      allocations: allocations,
      reference: reference,
      receivedAt: receivedAt,
      approvedAt: approvedAt,
      paymentAccountId: paymentAccountId,
    );
    notifyListeners();
    return result;
  }

  int setInvoiceDraftArchived({
    required EntityId invoiceId,
    required int expectedRevision,
    required bool archived,
    required DateTime changedAt,
  }) {
    final revision = database.setInvoiceDraftArchived(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      invoiceId: invoiceId,
      expectedRevision: expectedRevision,
      archived: archived,
      changedAt: changedAt,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  List<StoredQuotation> quotations() =>
      database.readQuotations(identity.businessId);

  int saveQuotationDraft(
    Estimate quotation, {
    required int expectedRevision,
    required DateTime savedAt,
    DocumentRecurrenceRequest? recurrence,
  }) {
    final revision = database.saveQuotationDraft(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotation: quotation,
      expectedRevision: expectedRevision,
      savedAt: savedAt,
      recurrence: recurrence,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  int saveCurrentQuotation(
    Estimate replacement, {
    required StoredQuotation expected,
    required EntityId requestId,
    required DateTime savedAt,
    required Customer reviewedCustomer,
    DocumentRecurrenceRequest? recurrence,
  }) {
    final revision = database.saveCurrentQuotation(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      expected: expected,
      replacement: replacement,
      reviewedCustomer: reviewedCustomer,
      savedAt: savedAt,
      recurrence: recurrence,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  int changeQuotationState(
    EntityId quotationId, {
    required int expectedRevision,
    required QuotationAction action,
    required DateTime changedAt,
  }) {
    final revision = database.changeQuotationState(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotationId: quotationId,
      expectedRevision: expectedRevision,
      action: action,
      changedAt: changedAt,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  EntityId convertQuotationToInvoice(
    EntityId quotationId, {
    required int expectedRevision,
    required EntityId invoiceId,
    required String documentNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    required DateTime convertedAt,
  }) {
    final id = database.convertQuotationToInvoice(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      quotationId: quotationId,
      expectedRevision: expectedRevision,
      invoiceId: invoiceId,
      documentNumber: documentNumber,
      issueDate: issueDate,
      dueDate: dueDate,
      convertedAt: convertedAt,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  int saveInvoiceDraft(
    Invoice invoice, {
    required int expectedRevision,
    required DateTime savedAt,
    DocumentRecurrenceRequest? recurrence,
  }) {
    final revision = database.saveInvoiceDraft(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      invoice: invoice,
      expectedRevision: expectedRevision,
      savedAt: savedAt,
      recurrence: recurrence,
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  EntityId postInvoice({
    required EntityId requestId,
    required EntityId invoiceId,
    required int expectedRevision,
    required int expectedCustomerRevision,
    required String documentNumber,
    required EntityId receivableAccountId,
    required EntityId incomeAccountId,
    EntityId? taxAccountId,
    Map<EntityId, EntityId> lineIncomeAccounts = const {},
    required DateTime approvedAt,
  }) {
    final id = database.postInvoice(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      invoiceId: invoiceId,
      expectedRevision: expectedRevision,
      expectedCustomerRevision: expectedCustomerRevision,
      documentNumber: documentNumber,
      receivableAccountId: receivableAccountId,
      incomeAccountId: incomeAccountId,
      taxAccountId: taxAccountId,
      lineIncomeAccounts: lineIncomeAccounts,
      approvedAt: approvedAt,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  List<Customer> customers() => database.readCustomers(identity.businessId);

  void saveVendor(
    Vendor vendor, {
    required int expectedRevision,
    Payee? expectedPayee,
  }) {
    database.saveVendor(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      vendor: vendor,
      expectedRevision: expectedRevision,
      expectedPayee: expectedPayee,
    );
    payees.reload(database.readPayees(identity.businessId));
    notifyListeners();
  }

  void saveBillDraft(
    PurchaseBillDraft bill, {
    required int expectedRevision,
    DocumentRecurrenceRequest? recurrence,
  }) {
    database.saveBillDraft(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      bill: bill,
      expectedRevision: expectedRevision,
      recurrence: recurrence,
    );
    if (!_closed) notifyListeners();
  }

  EntityId postBill({
    required EntityId requestId,
    required EntityId billId,
    required int expectedRevision,
    required EntityId payableAccountId,
    required DateTime approvedAt,
  }) {
    final id = database.postBill(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      billId: billId,
      expectedRevision: expectedRevision,
      payableAccountId: payableAccountId,
      approvedAt: approvedAt,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  EntityId reverseBillRecognition({
    required EntityId requestId,
    required PurchaseBillDraft reviewedBill,
    required EntityId expectedRecognitionJournalId,
    required DateTime reversedOn,
    required String reason,
    required DateTime approvedAt,
  }) {
    final id = database.reverseBillRecognition(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      reviewedBill: reviewedBill,
      expectedRecognitionJournalId: expectedRecognitionJournalId,
      reversedOn: reversedOn,
      reason: reason,
      approvedAt: approvedAt,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  EntityId reverseBillPayment({
    required EntityId requestId,
    required EntityId sourcePaymentId,
    required DateTime reversedOn,
    required String reason,
    required DateTime approvedAt,
  }) {
    final id = database.reverseBillPayment(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      sourcePaymentId: sourcePaymentId,
      reversedOn: reversedOn,
      reason: reason,
      approvedAt: approvedAt,
    );
    if (!_closed) notifyListeners();
    return id;
  }

  StoredBillSettlement settleRecognizedBills({
    required EntityId requestId,
    required List<BillSettlementAllocation> allocations,
    required String paymentAccountId,
    required String paymentReference,
    required DateTime paidOn,
    required DateTime approvedAt,
  }) {
    final payment = database.settleRecognizedBills(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      requestId: requestId,
      allocations: allocations,
      paymentAccountId: paymentAccountId,
      paymentReference: paymentReference,
      paidOn: paidOn,
      approvedAt: approvedAt,
    );
    if (!_closed) notifyListeners();
    return payment;
  }

  void saveCustomer(Customer customer) {
    if (customer.metadata.businessId != identity.businessId) {
      throw StateError('Customer must belong to the active company.');
    }
    database.saveCustomer(customer, actorId: identity.ownerId);
    if (!_closed) notifyListeners();
  }

  Future<List<StoredAccount>> accounts() =>
      database.listAccounts(identity.businessId);

  Future<EntityId> createAccount({
    required String code,
    required String name,
    required AccountType type,
    bool isParent = false,
    EntityId? parentId,
    AccountProfile? profile,
    AccountStatus status = AccountStatus.active,
  }) async {
    final id = newId();
    await database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: id,
          code: code,
          name: name,
          type: type,
          isParent: isParent,
          parentId: parentId,
          profile: profile,
          status: status,
        ),
        metadata: RecordMetadata.initial(
          recordId: id,
          businessId: identity.businessId,
          originDeviceId: identity.deviceId,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
    );
    if (!_closed) notifyListeners();
    return id;
  }

  Future<EntityId> updateAccountMetadata({
    required StoredAccount original,
    required String code,
    required String name,
    required AccountType type,
    required bool isParent,
    required EntityId? parentId,
    required AccountStatus status,
    AccountProfile? profile,
  }) async {
    final id = original.account.id;
    if (original.metadata.recordId != id ||
        original.metadata.businessId != identity.businessId ||
        original.metadata.isTombstone) {
      throw StateError('The account does not belong to the active company.');
    }
    final current = await database.getAccount(id);
    if (current == null ||
        current.metadata.isTombstone ||
        current.metadata.businessId != identity.businessId ||
        current.metadata.revision != original.metadata.revision) {
      throw StateError(
        'Account changed since it was read. Reload before saving.',
      );
    }
    if (current.account.status == AccountStatus.archived ||
        status == AccountStatus.archived) {
      throw StateError('Archived accounts cannot be edited here.');
    }
    final now = DateTime.now().toUtc();
    final updatedAt = now.isAfter(current.metadata.updatedAt)
        ? now
        : current.metadata.updatedAt.add(const Duration(microseconds: 1));
    await database.saveAccount(
      StoredAccount(
        account: Account.create(
          id: id,
          code: code,
          name: name,
          type: type,
          status: status,
          isParent: isParent,
          isSystem: current.account.isSystem,
          parentId: parentId,
          profile: profile ?? current.account.profile,
        ),
        metadata: current.metadata.nextRevision(updatedAt: updatedAt),
      ),
    );
    if (!_closed) notifyListeners();
    return id;
  }

  Future<List<StoredJournalEntry>> journals() =>
      database.listJournals(identity.businessId);

  Future<EntityId> saveJournal({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  }) async {
    final id = newId();
    final entry = JournalEntry.draft(
      id: id,
      date: date,
      memo: memo,
      lines: lines,
    );
    if (entry.validationErrors.isNotEmpty) {
      throw JournalValidationException(entry.validationErrors);
    }
    await database.save(
      StoredJournalEntry(
        entry: entry,
        metadata: RecordMetadata.initial(
          recordId: id,
          businessId: identity.businessId,
          originDeviceId: identity.deviceId,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
    );
    if (!_closed) {
      notifyListeners();
    }
    return id;
  }

  StoredJournalEntry reviseJournalDraft({
    required StoredJournalEntry expected,
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
    required EntityId requestId,
    required DateTime savedAt,
  }) {
    if (expected.metadata.businessId != identity.businessId) {
      throw StateError('The Journal is unavailable in this business.');
    }
    final saved = database.reviseManualJournalDraft(
      expected: expected,
      replacement: JournalEntry.draft(
        id: expected.entry.id,
        date: date,
        memo: memo,
        lines: lines,
      ),
      requestId: requestId,
      actorId: identity.ownerId,
      savedAt: savedAt,
    );
    if (!_closed) notifyListeners();
    return saved;
  }

  StoredManualJournalRevision saveManualJournalRevision({
    required EntityId rootId,
    required StoredJournalEntry expectedSource,
    required int expectedCurrentRevision,
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
    required EntityId requestId,
    required DateTime savedAt,
  }) {
    if (expectedSource.metadata.businessId != identity.businessId) {
      throw StateError('The Journal is unavailable in this business.');
    }
    final result = database.saveManualJournalCurrentRevision(
      rootId: rootId,
      expectedSource: expectedSource,
      expectedCurrentRevision: expectedCurrentRevision,
      replacement: JournalEntry.draft(
        id: requestId,
        date: date,
        memo: memo,
        lines: lines,
      ),
      requestId: requestId,
      actorId: identity.ownerId,
      deviceId: identity.deviceId,
      savedAt: savedAt,
    );
    if (!_closed) notifyListeners();
    return result;
  }

  StoredJournalEntry approveManualJournalRevision(JournalApproval command) {
    if (command.businessId != identity.businessId ||
        command.actorId != identity.ownerId) {
      throw StateError('The Journal is unavailable in this business.');
    }
    final result = database.approveManualJournalCurrentRevision(command);
    if (!_closed) notifyListeners();
    return result;
  }

  Future<LedgerReport> report({
    required DateTime from,
    required DateTime through,
  }) => database.readReport(
    businessId: identity.businessId,
    currency: identity.currency,
    from: from,
    through: through,
  );

  Future<({LedgerReport ledger, SalesReport sales})> reportWithSales({
    required DateTime from,
    required DateTime through,
  }) => database.readReportWithSales(
    businessId: identity.businessId,
    currency: identity.currency,
    from: from,
    through: through,
  );

  TransactionRemovalReview reviewTransactionRemoval(
    TransactionRecordKind kind,
    String recordId,
  ) => database.reviewTransactionRemoval(
    businessId: identity.businessId,
    kind: kind,
    recordId: recordId,
  );

  ({List<TransactionRemovalReview> records, int total}) removedTransactionPage(
    TransactionRecordKind kind, {
    int offset = 0,
    int limit = 5,
  }) => database.removedTransactionPage(
    businessId: identity.businessId,
    kind: kind,
    offset: offset,
    limit: limit,
  );

  int setTransactionRemoved({
    required TransactionRemovalReview reviewed,
    required bool removed,
    required DateTime changedAt,
  }) {
    final revision = database.setTransactionRemoved(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      reviewed: reviewed,
      removed: removed,
      changedAt: changedAt,
    );
    if (reviewed.kind == TransactionRecordKind.claim) claims.reload();
    if (reviewed.kind == TransactionRecordKind.paymentVoucher) {
      vouchers.reload();
    }
    if (!_closed) notifyListeners();
    return revision;
  }

  Future<TaxActivityReport> taxActivity({
    required DateTime from,
    required DateTime through,
  }) => database.readTaxActivity(
    businessId: identity.businessId,
    currency: identity.currency,
    from: from,
    through: through,
  );

  Future<ClaimantStatementReport> claimantStatements({
    required DateTime from,
    required DateTime through,
  }) => database.readClaimantStatement(
    businessId: identity.businessId,
    currency: identity.currency,
    from: from,
    through: through,
  );

  ClaimReimbursementPosition? claimReimbursementPosition({
    required EntityId claimId,
    required DateTime through,
  }) => database.readClaimReimbursementPosition(
    businessId: identity.businessId,
    claimId: claimId,
    through: through,
  );

  /// Creates a reviewable draft only. Approval recalculates balances atomically.
  Future<void> prepareClosing({
    required DateTime through,
    required EntityId equityAccountId,
  }) async {
    final proposal = ClosingProposal.fromReport(
      await report(from: DateTime.utc(1), through: through),
      equityAccountId: equityAccountId,
    );
    if (proposal.isEmpty) {
      throw StateError(
        'There are no remaining income or expense balances to close.',
      );
    }
    final id = newId();
    await database.save(
      StoredJournalEntry(
        entry: JournalEntry.draft(
          id: id,
          date: proposal.through,
          memo: 'Closing Entry',
          lines: proposal.lines,
          closingEquityAccountId: proposal.equityAccountId,
        ),
        metadata: RecordMetadata.initial(
          recordId: id,
          businessId: identity.businessId,
          originDeviceId: identity.deviceId,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
    );
    if (!_closed) notifyListeners();
  }

  Future<StoredJournalEntry> approveJournal(JournalApproval command) async {
    if (command.businessId != identity.businessId ||
        command.actorId != identity.ownerId) {
      throw StateError(
        'Approval must belong to the active local workspace owner.',
      );
    }
    final result = await database.approve(command);
    if (!_closed) {
      notifyListeners();
    }
    return result;
  }

  Future<EntityId> saveExpenseIntake(
    RecordExpenseDraft draft, {
    String? recurringOccurrenceIdentity,
  }) async {
    final id = await database.saveExpenseIntake(
      id: newId(),
      businessId: identity.businessId,
      draft: draft,
      recurringOccurrenceIdentity: recurringOccurrenceIdentity,
      createdAt: DateTime.now().toUtc(),
    );
    if (!_closed) {
      notifyListeners();
    }
    return id;
  }

  Future<void> updateExpenseIntake({
    required EntityId id,
    required RecordExpenseDraft expected,
    required RecordExpenseDraft replacement,
    int? expectedRevision,
  }) async {
    await database.updateExpenseIntake(
      businessId: identity.businessId,
      id: id,
      actorId: identity.ownerId,
      expected: expected,
      replacement: replacement,
      changedAt: DateTime.now().toUtc(),
      expectedRevision: expectedRevision,
    );
    if (!_closed) notifyListeners();
  }

  ExpenseRevision saveExpenseRevision({
    required EntityId expenseId,
    required EntityId requestId,
    required EntityId expectedSourceJournalId,
    required int expectedSourceExpenseRevision,
    required int expectedRevision,
    required RecordExpenseDraft expected,
    required RecordExpenseDraft replacement,
    required DateTime savedAt,
  }) {
    final saved = database.saveExpenseRevision(
      businessId: identity.businessId,
      expenseId: expenseId,
      requestId: requestId,
      actorId: identity.ownerId,
      expectedSourceJournalId: expectedSourceJournalId,
      expectedSourceExpenseRevision: expectedSourceExpenseRevision,
      expectedRevision: expectedRevision,
      expected: expected,
      replacement: replacement,
      savedAt: savedAt,
    );
    if (!_closed) notifyListeners();
    return saved;
  }

  ExpenseRevision? expenseRevision(EntityId expenseId) =>
      database.readExpenseRevision(identity.businessId, expenseId);

  ExpenseRevisionPosting approveExpenseRevision(
    ExpenseRevisionApproval command,
  ) {
    if (command.businessId != identity.businessId ||
        command.actorId != identity.ownerId) {
      throw StateError(
        'The Expense revision approval does not belong to this workspace owner.',
      );
    }
    final result = database.approveExpenseRevision(command);
    if (!_closed) notifyListeners();
    return result;
  }

  ExpenseRevisionPosting approveClaimExpenseRevision(
    ClaimExpenseRevisionApproval command,
  ) {
    if (command.approval.businessId != identity.businessId ||
        command.approval.actorId != identity.ownerId) {
      throw StateError(
        'The Claim revision approval does not belong to this workspace owner.',
      );
    }
    final result = database.approveClaimExpenseRevision(command);
    if (!_closed) notifyListeners();
    return result;
  }

  Future<ExpenseIntakeRecord?> originalExpense(
    EntityId id, {
    bool includeArchived = false,
  }) => database.getOriginalExpenseIntake(
    identity.businessId,
    id,
    includeArchived: includeArchived,
  );

  int setExpenseIntakeArchived({
    required EntityId id,
    required int expectedRevision,
    required bool archived,
  }) {
    final revision = database.setExpenseIntakeArchived(
      businessId: identity.businessId,
      actorId: identity.ownerId,
      id: id,
      expectedRevision: expectedRevision,
      archived: archived,
      changedAt: DateTime.now().toUtc(),
    );
    if (!_closed) notifyListeners();
    return revision;
  }

  Future<List<ExpenseIntakeSummary>> expenses({bool archived = false}) =>
      database.listExpenseIntakes(identity.businessId, archived: archived);
  Future<ExpenseIntakeRecord?> expense(
    EntityId id, {
    bool includeArchived = false,
  }) => database.getExpenseIntake(
    identity.businessId,
    id,
    includeArchived: includeArchived,
  );

  static EntityId newId() => EntityId.random();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    database.close();
    super.dispose();
  }
}
