import 'dart:convert';

import '../../../core/dates/accounting_date.dart';
import '../../accounting/domain/expense_draft.dart';
import 'claim_receipt.dart';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

/// Lifecycle for a staff-paid expense claim.
///
/// A direct expense is already paid from a company account. A [Claim] records
/// money a claimant paid personally and that the company may reimburse.
enum ClaimRecognitionDecision { returnForCorrection, voidClaim }

enum ClaimantType { staff, director }

/// Identity in the company's payee directory; Claim.claimantName is its
/// historical display-name snapshot. Names never establish identity.
final class ClaimantIdentity {
  ClaimantIdentity({required this.payeeId, required this.type}) {
    if (payeeId.isEmpty || payeeId != payeeId.trim()) {
      throw ArgumentError('A saved claimant identity is required.');
    }
  }
  final String payeeId;
  final ClaimantType type;
  String get label => type == ClaimantType.director ? 'Director' : 'Employee';
  Map<String, Object?> toJson() => {'payeeId': payeeId, 'type': type.name};
  factory ClaimantIdentity.fromJson(Map<String, dynamic> json) {
    final id = json['payeeId'];
    final type = json['type'];
    if (id is! String ||
        id.isEmpty ||
        id != id.trim() ||
        type is! String ||
        !ClaimantType.values.any((t) => t.name == type)) {
      throw const FormatException('Invalid saved claimant identity.');
    }
    return ClaimantIdentity(
      payeeId: id,
      type: ClaimantType.values.byName(type),
    );
  }
}

enum ClaimStatus {
  draft,
  submitted,
  approved,
  returned,
  declined,
  paid,
  voided,
}

extension ClaimStatusLabel on ClaimStatus {
  String get label => switch (this) {
    ClaimStatus.draft => 'Draft',
    ClaimStatus.submitted => 'Submitted / To Review',
    ClaimStatus.approved => 'Approved / Awaiting Payment',
    ClaimStatus.returned => 'Returned',
    ClaimStatus.declined => 'Declined',
    ClaimStatus.paid => 'Paid',
    ClaimStatus.voided => 'Voided',
  };

  String get compactLabel => switch (this) {
    ClaimStatus.submitted => 'Review',
    ClaimStatus.approved => 'Awaiting Payment',
    _ => label,
  };
}

final class ClaimValidationException implements Exception {
  ClaimValidationException(Iterable<String> errors)
    : errors = List<String>.unmodifiable(errors);

  final List<String> errors;

  @override
  String toString() => errors.join(' ');
}

final class Claim {
  Claim._({
    required this.id,
    required this.vendorName,
    required this.amount,
    required this.status,
    required this.paymentBatchId,
    this.paymentReference,
    required this.paidAt,
    required this.claimantName,
    this.claimantIdentity,
    required this.incurredOn,
    required this.category,
    required this.claimCategoryCode,
    required this.expenseCategoryCode,
    required this.expenseAccountCode,
    required this.businessPurpose,
    required this.personallyPaid,
    required List<String> receiptDocumentNames,
    required List<ReceiptAttachment> attachments,
    List<ClaimReceipt> receipts = const [],
    this.expenseDraft,
    this.legacySource,
  }) : receiptDocumentNames = List.unmodifiable(
         receiptDocumentNames.isEmpty
             ? attachments.map((attachment) => attachment.filename)
             : receiptDocumentNames,
       ),
       attachments = List.unmodifiable(attachments),
       receipts = List.unmodifiable(receipts) {
    _validateExpenseFacts();
    _validateReceiptFacts();
  }

  factory Claim.draft({
    required EntityId id,
    required String vendorName,
    required Money amount,
    String claimantName = '',
    ClaimantIdentity? claimantIdentity,
    DateTime? incurredOn,
    String category = '',
    String? claimCategoryCode,
    String? expenseCategoryCode,
    String? expenseAccountCode,
    String businessPurpose = '',
    bool personallyPaid = true,
    List<String> receiptDocumentNames = const <String>[],
    List<ReceiptAttachment> attachments = const <ReceiptAttachment>[],
    List<ClaimReceipt> receipts = const [],
  }) {
    return Claim._(
      id: id,
      vendorName: vendorName.trim(),
      amount: amount,
      status: ClaimStatus.draft,
      paymentBatchId: null,
      paidAt: null,
      claimantName: claimantName.trim(),
      claimantIdentity: claimantIdentity,
      incurredOn: incurredOn?.toUtc(),
      category: category.trim(),
      claimCategoryCode: claimCategoryCode?.trim(),
      expenseCategoryCode: expenseCategoryCode?.trim(),
      expenseAccountCode: expenseAccountCode?.trim(),
      businessPurpose: businessPurpose.trim(),
      personallyPaid: personallyPaid,
      receiptDocumentNames: receiptDocumentNames,
      attachments: attachments,
      receipts: receipts,
    );
  }

  /// Preserve the existing Expense body; claimant is its additional fact.
  factory Claim.expense({
    required EntityId id,
    required RecordExpenseDraft draft,
    required String claimantName,
    ClaimantIdentity? claimantIdentity,
    Claim? legacySource,
  }) {
    // Own a frozen copy of the existing body, including original bytes.
    draft = RecordExpenseDraft.fromJson(draft.toJson());
    final date = parseAccountingInputDate(draft.date);
    return Claim._(
      id: id,
      vendorName: draft.payee.trim(),
      amount: Money.fromDecimal(draft.amount, draft.currencyCode),
      status: ClaimStatus.draft,
      paymentBatchId: null,
      paidAt: null,
      claimantName: claimantName.trim(),
      claimantIdentity: claimantIdentity,
      incurredOn: date == null ? null : accountingCalendarDate(date),
      category: draft.category,
      claimCategoryCode: null,
      expenseCategoryCode: null,
      expenseAccountCode: null,
      businessPurpose: draft.notes,
      personallyPaid: legacySource?.personallyPaid ?? true,
      receiptDocumentNames: const [],
      attachments: draft.attachments,
      expenseDraft: draft,
      legacySource: legacySource,
    );
  }

  /// Revise the same draft/returned Claim without replacing its claimant or
  /// resetting lifecycle status. Submitted recognition facts are immutable.
  Claim reviseExpense(RecordExpenseDraft draft) {
    if (!const {ClaimStatus.draft, ClaimStatus.returned}.contains(status)) {
      throw StateError(
        'Only draft or returned Expense-backed Claims can be revised.',
      );
    }
    if (draft.submissionId !=
            (expenseDraft?.submissionId ?? 'legacy-claim:${id.value}') ||
        draft.currencyCode != amount.currency) {
      throw const FormatException(
        'Claim revision must retain its submission identity.',
      );
    }
    final revised = Claim.expense(
      id: id,
      draft: draft,
      claimantName: claimantName,
      claimantIdentity: claimantIdentity,
      legacySource:
          legacySource ??
          (expenseDraft == null ? Claim.fromJson(toJson()) : null),
    );
    return revised._copyWith(status: status);
  }

  /// Accounting review supplies accounts explicitly, never from category names.
  Claim withExpensePostingAccounts(Map<String, EntityId> accounts) {
    final draft = expenseDraft;
    if (draft == null ||
        accounts.length != draft.lines.length ||
        draft.lines.any((line) => !accounts.containsKey(line.id))) {
      throw const FormatException('Review an account for every Expense row.');
    }
    final receipt = ClaimReceipt(
      id: 'expense-${id.value}',
      merchant: vendorName,
      date: incurredOn!,
      currency: amount.currency,
      taxMode: draft.taxMode!,
      originalDocumentIds: [for (final a in attachments) a.originalId],
      lines: [
        for (final line in draft.lines)
          ClaimReceiptLine(expenseAccountId: accounts[line.id]!, item: line),
      ],
    );
    return Claim.fromJson({
      ...toJson(),
      'receipts': [receipt.toJson()],
    });
  }

  Map<String, Object?> toJson() => {
    'version': legacySource != null
        ? 5
        : expenseDraft != null
        ? 4
        : receipts.isNotEmpty
        ? 3
        : claimantIdentity == null
        ? 1
        : 2,
    if (expenseDraft != null) 'expenseDraft': expenseDraft!.toJson(),
    if (legacySource != null) 'legacySource': legacySource!.toJson(),
    'id': id.value,
    'vendorName': vendorName,
    'amountMinor': amount.minorUnits,
    'currency': amount.currency,
    'status': status.name,
    'paymentBatchId': paymentBatchId?.value,
    'paymentReference': paymentReference,
    'paidAt': paidAt?.toUtc().toIso8601String(),
    'claimantName': claimantName,
    if (claimantIdentity != null)
      'claimantIdentity': claimantIdentity!.toJson(),
    'incurredOn': incurredOn?.toUtc().toIso8601String(),
    'category': category,
    'claimCategoryCode': claimCategoryCode,
    'expenseCategoryCode': expenseCategoryCode,
    'expenseAccountCode': expenseAccountCode,
    'businessPurpose': businessPurpose,
    'personallyPaid': personallyPaid,
    'receiptDocumentNames': receiptDocumentNames,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    if (receipts.isNotEmpty)
      'receipts': receipts.map((r) => r.toJson()).toList(),
  };

  factory Claim.fromJson(Map<String, dynamic> json) {
    if (!const {1, 2, 3, 4, 5}.contains(json['version'])) {
      throw const FormatException('Unsupported claim version.');
    }
    if ((const {4, 5}.contains(json['version'])) !=
        (json['expenseDraft'] is Map)) {
      throw const FormatException(
        'Expense snapshot does not match Claim version.',
      );
    }
    if ((json['version'] == 5) != (json['legacySource'] is Map) ||
        (json['version'] != 5 && json.containsKey('legacySource')) ||
        (json['version'] == 5 &&
            !const {
              1,
              2,
              3,
            }.contains((json['legacySource'] as Map)['version']))) {
      throw const FormatException('Legacy Claim evidence version mismatch.');
    }
    if ((json['version'] == 1 && json.containsKey('claimantIdentity')) ||
        (json['version'] == 2 && json['claimantIdentity'] is! Map) ||
        (const {3, 4, 5}.contains(json['version']) &&
            json.containsKey('claimantIdentity') &&
            json['claimantIdentity'] is! Map)) {
      throw const FormatException(
        'Claimant identity does not match its version.',
      );
    }
    if (json['version'] == 3
        ? json['receipts'] is! List || (json['receipts'] as List).isEmpty
        : !const {4, 5}.contains(json['version']) &&
              json.containsKey('receipts')) {
      throw const FormatException(
        'Receipt tax facts do not match the claim version.',
      );
    }
    final status = ClaimStatus.values.byName(json['status'] as String);
    final batch = json['paymentBatchId'] as String?;
    final paid = json['paidAt'] as String?;
    final reference = json['paymentReference'] as String?;
    if (reference != null &&
        (status != ClaimStatus.paid ||
            reference.trim().isEmpty ||
            reference.length > 120 ||
            reference != reference.trim())) {
      throw const FormatException('Invalid claim payment reference.');
    }
    if ((status == ClaimStatus.paid && (batch == null || paid == null)) ||
        (status != ClaimStatus.paid && (batch != null || paid != null))) {
      throw const FormatException(
        'Claim payment references do not match its status.',
      );
    }
    final attachments = (json['attachments'] as List)
        .map(
          (a) =>
              ReceiptAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        )
        .toList();
    if (attachments.map((a) => a.originalId).toSet().length !=
        attachments.length) {
      throw const FormatException('Duplicate claim receipt identity.');
    }
    final receipts = [
      for (final r in json['receipts'] as List? ?? const [])
        ClaimReceipt.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
    final result = Claim._(
      id: EntityId.parse(json['id'] as String),
      vendorName: json['vendorName'] as String,
      amount: Money.fromMinor(
        json['amountMinor'] as int,
        json['currency'] as String,
      ),
      status: status,
      paymentBatchId: batch == null ? null : EntityId.parse(batch),
      paymentReference: reference,
      paidAt: paid == null ? null : DateTime.parse(paid).toUtc(),
      claimantName: json['claimantName'] as String,
      claimantIdentity: json['claimantIdentity'] == null
          ? null
          : ClaimantIdentity.fromJson(
              Map<String, dynamic>.from(json['claimantIdentity'] as Map),
            ),
      incurredOn: json['incurredOn'] == null
          ? null
          : DateTime.parse(json['incurredOn'] as String).toUtc(),
      category: json['category'] as String,
      claimCategoryCode: json['claimCategoryCode'] as String?,
      expenseCategoryCode: json['expenseCategoryCode'] as String?,
      expenseAccountCode: json['expenseAccountCode'] as String?,
      businessPurpose: json['businessPurpose'] as String,
      personallyPaid: json['personallyPaid'] as bool,
      receiptDocumentNames: (json['receiptDocumentNames'] as List)
          .cast<String>(),
      attachments: attachments,
      receipts: receipts,
      expenseDraft: json['expenseDraft'] == null
          ? null
          : RecordExpenseDraft.fromJson(
              Map<String, dynamic>.from(json['expenseDraft'] as Map),
            ),
      legacySource: json['legacySource'] == null
          ? null
          : Claim.fromJson(
              Map<String, dynamic>.from(json['legacySource'] as Map),
            ),
    );
    // A data-only recovery retains historical submission, not receipt bytes.
    // Reading that history must not re-submit it or claim evidence is viewable.
    final savedErrors = result._submissionErrors(allowArchivedReceipt: true);
    if ((status == ClaimStatus.submitted ||
            status == ClaimStatus.approved ||
            status == ClaimStatus.paid) &&
        savedErrors.isNotEmpty) {
      throw ClaimValidationException(savedErrors);
    }
    return result;
  }

  final EntityId id;

  /// The merchant or supplier where the expense was incurred.
  final String vendorName;
  final Money amount;
  final ClaimStatus status;
  final EntityId? paymentBatchId;
  final String? paymentReference;
  final DateTime? paidAt;
  final String claimantName;
  final ClaimantIdentity? claimantIdentity;
  String get claimantIdentityLabel =>
      claimantIdentity?.label ?? 'Unlinked Recorded Name';
  final DateTime? incurredOn;
  final String category;
  final String? claimCategoryCode;
  final String? expenseCategoryCode;
  final String? expenseAccountCode;
  final String businessPurpose;
  final bool personallyPaid;
  final List<String> receiptDocumentNames;
  final List<ReceiptAttachment> attachments;
  final List<ClaimReceipt> receipts;
  final RecordExpenseDraft? expenseDraft;

  /// Exact original legacy receipt/category/personal-payment facts, retained
  /// when the current draft starts using the existing Expense body.
  final Claim? legacySource;

  void validateClaimantReplacement(Claim replacement) {
    if (claimantName.isEmpty && claimantIdentity == null) return;
    if (replacement.claimantName != claimantName ||
        replacement.claimantIdentity?.payeeId != claimantIdentity?.payeeId ||
        replacement.claimantIdentity?.type != claimantIdentity?.type) {
      throw StateError(
        'An existing Claim cannot be changed to another claimant. Create a new Claim for that person.',
      );
    }
  }

  /// Once adopted, the legacy submission remains immutable evidence.
  void validateExpenseOriginalReplacement(Claim replacement) {
    if (replacement.legacySource != null) {
      final original = legacySource ?? this;
      if (jsonEncode(original.toJson()) !=
          jsonEncode(replacement.legacySource!.toJson())) {
        throw StateError(
          'Retain the exact original Claim when updating its Expense body.',
        );
      }
    } else if (legacySource != null) {
      throw StateError('Original Claim evidence cannot be removed.');
    }
  }

  void _validateExpenseFacts() {
    final source = legacySource;
    if (source != null &&
        (expenseDraft == null ||
            source.expenseDraft != null ||
            source.legacySource != null ||
            source.id != id ||
            source.amount.currency != amount.currency ||
            source.claimantName != claimantName ||
            jsonEncode(source.claimantIdentity?.toJson()) !=
                jsonEncode(claimantIdentity?.toJson()) ||
            !const {
              ClaimStatus.draft,
              ClaimStatus.returned,
            }.contains(source.status))) {
      throw const FormatException(
        'Legacy Claim evidence must retain its original identity and draft.',
      );
    }
    final draft = expenseDraft;
    if (draft == null) return;
    draft.validateLines();
    final date = parseAccountingInputDate(draft.date);
    if (draft.claimSource != null ||
        draft.paymentAccountId != null ||
        draft.paymentAccount.isNotEmpty ||
        draft.taxReviewRequired ||
        (!const {'Exclusive', 'Inclusive'}.contains(draft.taxMode) &&
            !(source != null &&
                const {
                  ClaimStatus.draft,
                  ClaimStatus.returned,
                }.contains(status))) ||
        draft.lines.isEmpty ||
        date == null ||
        incurredOn == null ||
        formatAccountingInputDate(incurredOn!) !=
            formatAccountingInputDate(date) ||
        Money.fromDecimal(draft.amount, draft.currencyCode) != amount ||
        draft.payee.trim() != vendorName ||
        draft.category != category ||
        draft.notes != businessPurpose ||
        (source == null
            ? !personallyPaid
            : personallyPaid != source.personallyPaid) ||
        jsonEncode(draft.attachments.map((a) => a.toJson()).toList()) !=
            jsonEncode(attachments.map((a) => a.toJson()).toList())) {
      throw const FormatException(
        'Claim must retain its exact personally-paid Expense facts.',
      );
    }
    if (receipts.isNotEmpty) {
      if (receipts.length != 1) {
        throw const FormatException(
          'One Expense snapshot owns its recognition rows.',
        );
      }
      final r = receipts.single;
      if (r.merchant != vendorName ||
          formatAccountingInputDate(r.date) != draft.date ||
          r.taxMode != draft.taxMode ||
          jsonEncode(r.lines.map((l) => l.item.toJson()).toList()) !=
              jsonEncode(draft.lines.map((l) => l.toJson()).toList()) ||
          jsonEncode(r.originalDocumentIds) !=
              jsonEncode(attachments.map((a) => a.originalId).toList())) {
        throw const FormatException(
          'Recognition rows differ from the submitted Expense.',
        );
      }
    }
  }

  void _validateReceiptFacts() {
    if (receipts.isEmpty) {
      return; // Historic v1/v2 remains explicitly unrecorded.
    }
    final receiptIds = <String>{};
    final lineIds = <String>{};
    final documents = {for (final a in attachments) a.originalId};
    var total = Money.zero(amount.currency);
    for (final receipt in receipts) {
      if (!receiptIds.add(receipt.id) ||
          receipt.currency != amount.currency ||
          receipt.originalDocumentIds.any((id) => !documents.contains(id)) ||
          receipt.lines.any((line) => !lineIds.add(line.item.id))) {
        throw const FormatException(
          'Claim receipts require distinct identities, matching currency and linked original documents.',
        );
      }
      total += receipt.totals.total;
    }
    if (total != amount) {
      throw const FormatException(
        'Receipt totals must equal the exact claim amount.',
      );
    }
  }

  /// Nonrecoverable purchase tax belongs in expense/asset cost, not a new
  /// output-tax liability or an assumed refundable input-tax account.
  Map<EntityId, Money> get receiptCostAllocations {
    final result = <EntityId, Money>{};
    for (final receipt in receipts) {
      for (final line in receipt.lines) {
        final gross = line.item
            .calculation(receipt.currency, receipt.taxMode)
            .total;
        result.update(
          line.expenseAccountId,
          (old) => old + gross,
          ifAbsent: () => gross,
        );
      }
    }
    return Map.unmodifiable(result);
  }

  String? get mappedExpenseCategoryCode => expenseCategoryCode;
  String? get mappedExpenseAccountCode => expenseAccountCode;

  bool get hasReviewableAttachment => attachments.any(
    (attachment) =>
        !attachment.reviewSkipped &&
        attachment.originalBytes.isNotEmpty &&
        attachment.status == AttachmentProcessingStatus.ready,
  );

  List<String> get submissionErrors => _submissionErrors();

  List<String> _submissionErrors({bool allowArchivedReceipt = false}) {
    final errors = <String>[];
    if (expenseDraft != null &&
        !const {'Inclusive', 'Exclusive'}.contains(expenseDraft!.taxMode)) {
      errors.add('Review Tax Inclusive or Tax Exclusive before submitting.');
    }
    if (claimantName.isEmpty) errors.add('Claimant is required.');
    if (vendorName.isEmpty) errors.add('Merchant or supplier is required.');
    if (amount.minorUnits <= 0) {
      errors.add('Amount must be greater than zero.');
    }
    if (incurredOn == null) errors.add('Date is required.');
    if (category.isEmpty) errors.add('Category is required.');
    if (expenseDraft == null &&
        (claimCategoryCode == null || claimCategoryCode!.isEmpty)) {
      errors.add('Claim category mapping is required.');
    }
    if (expenseDraft == null &&
        expenseCategoryCode == null &&
        expenseAccountCode == null) {
      errors.add('Claim category mapping needs review before submitting.');
    }
    if (businessPurpose.isEmpty) {
      errors.add('Business purpose is required to submit.');
    }
    if (!personallyPaid) {
      errors.add('Personal payment must be confirmed for a claim.');
    }
    final archivedReceipt =
        allowArchivedReceipt &&
        attachments.any(
          (attachment) =>
              !attachment.reviewSkipped &&
              attachment.originalBytes.isEmpty &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(attachment.originalSha256),
        );
    for (final receipt in receipts) {
      if (receipt.originalDocumentIds.any((id) {
        final a = attachments.where((a) => a.originalId == id).first;
        return a.reviewSkipped ||
            (a.originalBytes.isNotEmpty
                ? a.status != AttachmentProcessingStatus.ready
                : !allowArchivedReceipt ||
                      !RegExp(r'^[a-f0-9]{64}$').hasMatch(a.originalSha256));
      })) {
        errors.add(
          'Each recorded receipt requires its linked reviewable original document.',
        );
      }
    }
    if (!hasReviewableAttachment && !archivedReceipt) {
      errors.add('Receipt or document is required to submit.');
    }
    return List<String>.unmodifiable(errors);
  }

  Claim submit() {
    if (status != ClaimStatus.draft && status != ClaimStatus.returned) {
      throw StateError('Only draft or returned claims can be submitted.');
    }
    final errors = submissionErrors;
    if (errors.isNotEmpty) throw ClaimValidationException(errors);
    return _copyWith(status: ClaimStatus.submitted);
  }

  Claim approve() {
    if (status != ClaimStatus.submitted) {
      throw StateError('Only submitted claims can be approved.');
    }
    if (submissionErrors.isNotEmpty) {
      throw ClaimValidationException(submissionErrors);
    }
    return _copyWith(status: ClaimStatus.approved);
  }

  Claim returnForCorrection() {
    if (status != ClaimStatus.submitted && status != ClaimStatus.approved) {
      throw StateError('Only submitted claims can be returned.');
    }
    return _copyWith(status: ClaimStatus.returned);
  }

  Claim decline() {
    if (status != ClaimStatus.submitted && status != ClaimStatus.approved) {
      throw StateError('Only submitted claims can be declined.');
    }
    return _copyWith(status: ClaimStatus.declined);
  }

  Claim voidClaim() {
    if (status == ClaimStatus.paid) {
      throw StateError('A paid claim cannot be voided.');
    }
    if (status == ClaimStatus.voided) return this;
    return _copyWith(status: ClaimStatus.voided);
  }

  Claim markPaid({
    required EntityId paymentBatchId,
    required DateTime paidAt,
    String? paymentReference,
  }) {
    if (status == ClaimStatus.paid) {
      throw StateError('A claim can only be paid once.');
    }
    if (status == ClaimStatus.voided) {
      throw StateError('A voided claim cannot be paid.');
    }
    if (status != ClaimStatus.submitted && status != ClaimStatus.approved) {
      throw StateError('Only submitted or approved claims can be paid.');
    }
    final reference = paymentReference?.trim();
    if (reference != null && (reference.isEmpty || reference.length > 120)) {
      throw ArgumentError.value(
        paymentReference,
        'paymentReference',
        'Use 1 to 120 characters.',
      );
    }
    return _copyWith(
      status: ClaimStatus.paid,
      paymentBatchId: paymentBatchId,
      paymentReference: reference,
      paidAt: paidAt.toUtc(),
    );
  }

  Claim _copyWith({
    ClaimStatus? status,
    EntityId? paymentBatchId,
    String? paymentReference,
    DateTime? paidAt,
  }) {
    return Claim._(
      id: id,
      vendorName: vendorName,
      amount: amount,
      status: status ?? this.status,
      paymentBatchId: paymentBatchId ?? this.paymentBatchId,
      paymentReference: paymentReference ?? this.paymentReference,
      paidAt: paidAt ?? this.paidAt,
      claimantName: claimantName,
      claimantIdentity: claimantIdentity,
      incurredOn: incurredOn,
      category: category,
      claimCategoryCode: claimCategoryCode,
      expenseCategoryCode: expenseCategoryCode,
      expenseAccountCode: expenseAccountCode,
      businessPurpose: businessPurpose,
      personallyPaid: personallyPaid,
      receiptDocumentNames: receiptDocumentNames,
      attachments: attachments,
      receipts: receipts,
      expenseDraft: expenseDraft,
      legacySource: legacySource,
    );
  }
}
