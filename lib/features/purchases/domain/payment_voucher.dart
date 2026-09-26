import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/money/money.dart';

import 'payment_voucher_evidence.dart';

/// The one domain record a payment voucher is allowed to settle.
enum PaymentVoucherSourceType { directExpense, claimPayment, billSettlement }

extension PaymentVoucherSourceTypeLabel on PaymentVoucherSourceType {
  String get label => switch (this) {
    PaymentVoucherSourceType.directExpense => 'Direct Expense',
    PaymentVoucherSourceType.claimPayment => 'Claim Payment',
    PaymentVoucherSourceType.billSettlement => 'Bill Settlement',
  };
}

enum PaymentVoucherStatus {
  draft,
  pendingApproval,
  approved,
  paymentOrdered,
  paid,
  processed,
  reconciled,
  onHold,
  cancelled,
}

extension PaymentVoucherStatusLabel on PaymentVoucherStatus {
  String get label => switch (this) {
    PaymentVoucherStatus.draft => 'Draft',
    PaymentVoucherStatus.pendingApproval => 'Pending approval',
    PaymentVoucherStatus.approved => 'Approved for payment',
    PaymentVoucherStatus.paymentOrdered => 'Payment ordered',
    PaymentVoucherStatus.paid => 'Paid',
    PaymentVoucherStatus.processed => 'Processed',
    PaymentVoucherStatus.reconciled => 'Reconciled',
    PaymentVoucherStatus.onHold => 'On hold',
    PaymentVoucherStatus.cancelled => 'Cancelled',
  };

  String get compactLabel => switch (this) {
    PaymentVoucherStatus.pendingApproval => 'Pending',
    PaymentVoucherStatus.approved => 'Approved',
    PaymentVoucherStatus.paymentOrdered => 'Ordered',
    _ => label,
  };
}

final class PaymentVoucher {
  PaymentVoucher._({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.payee,
    required this.amount,
    required this.paymentAccount,
    this.paymentAccountId,
    required this.paymentMethod,
    required this.paymentDate,
    required this.reference,
    required this.status,
    required this.allocations,
    required this.attachmentNames,
    required this.attachments,
    this.preparer,
    this.approver,
    this.paidAt,
    this.reconciledAt,
    this.paymentEvidence,
    this.reconciliationEvidence,
  });

  factory PaymentVoucher.create({
    required String id,
    required PaymentVoucherSourceType sourceType,
    required String sourceId,
    required String payee,
    required Money amount,
    required String paymentAccount,
    String? paymentAccountId,
    required String paymentMethod,
    required DateTime paymentDate,
    required String reference,
    PaymentVoucherStatus status = PaymentVoucherStatus.draft,
    Iterable<String> allocations = const <String>[],
    Iterable<String> attachmentNames = const <String>[],
    Iterable<ReceiptAttachment> attachments = const <ReceiptAttachment>[],
    String? preparer,
    String? approver,
    DateTime? paidAt,
    DateTime? reconciledAt,
    PaymentVoucherPaymentEvidence? paymentEvidence,
    PaymentVoucherReconciliationEvidence? reconciliationEvidence,
  }) {
    _requireText(id, 'id');
    _requireText(sourceId, 'sourceId');
    _requireText(payee, 'payee');
    _requireText(paymentAccount, 'paymentAccount');
    if (paymentAccountId != null) {
      _requireText(paymentAccountId, 'paymentAccountId');
    }
    _requireText(paymentMethod, 'paymentMethod');
    _requireText(reference, 'reference');
    if (amount.minorUnits <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be greater than zero');
    }
    final settled =
        status == PaymentVoucherStatus.paid ||
        status == PaymentVoucherStatus.processed ||
        status == PaymentVoucherStatus.reconciled;
    if (settled != (paidAt != null)) {
      throw ArgumentError('Payment status and payment timestamp must agree.');
    }
    if ((status == PaymentVoucherStatus.reconciled) != (reconciledAt != null)) {
      throw ArgumentError('Reconciliation status and timestamp must agree.');
    }
    if (reconciledAt != null &&
        paidAt != null &&
        reconciledAt.isBefore(paidAt)) {
      throw ArgumentError('Reconciliation cannot precede payment.');
    }
    if (paymentEvidence != null &&
        (!settled ||
            paymentEvidence.movementAmount.currency != amount.currency ||
            !paidAt!.isAtSameMomentAs(paymentEvidence.paymentDate) ||
            paymentDate.year != paymentEvidence.paymentDate.year ||
            paymentDate.month != paymentEvidence.paymentDate.month ||
            paymentDate.day != paymentEvidence.paymentDate.day)) {
      throw ArgumentError('Voucher payment must match its posted evidence.');
    }
    if (reconciliationEvidence != null &&
        (status != PaymentVoucherStatus.reconciled ||
            paymentEvidence == null ||
            !reconciledAt!.isAtSameMomentAs(
              reconciliationEvidence.approvedAt,
            ))) {
      throw ArgumentError(
        'Voucher reconciliation must match its completed review.',
      );
    }
    final attachmentList = List<ReceiptAttachment>.unmodifiable(attachments);
    final resolvedAttachmentNames = attachmentNames.isEmpty
        ? attachmentList.map((attachment) => attachment.filename)
        : attachmentNames;
    return PaymentVoucher._(
      id: id,
      sourceType: sourceType,
      sourceId: sourceId,
      payee: payee,
      amount: amount,
      paymentAccount: paymentAccount,
      paymentAccountId: paymentAccountId,
      paymentMethod: paymentMethod,
      paymentDate: paymentDate,
      reference: reference,
      status: status,
      allocations: List<String>.unmodifiable(allocations),
      attachmentNames: List<String>.unmodifiable(resolvedAttachmentNames),
      attachments: attachmentList,
      preparer: preparer,
      approver: approver,
      paidAt: paidAt,
      reconciledAt: reconciledAt,
      paymentEvidence: paymentEvidence,
      reconciliationEvidence: reconciliationEvidence,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'sourceType': sourceType.name,
    'sourceId': sourceId,
    'payee': payee,
    'amountMinor': amount.minorUnits,
    'currency': amount.currency,
    'paymentAccount': paymentAccount,
    if (paymentAccountId != null) 'paymentAccountId': paymentAccountId,
    'paymentMethod': paymentMethod,
    'paymentDate': paymentDate.toIso8601String(),
    'reference': reference,
    'status': status.name,
    'allocations': allocations,
    'attachmentNames': attachmentNames,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'preparer': preparer,
    'approver': approver,
    'paidAt': paidAt?.toIso8601String(),
    'reconciledAt': reconciledAt?.toIso8601String(),
    if (paymentEvidence != null) 'paymentEvidence': paymentEvidence!.toJson(),
    if (reconciliationEvidence != null)
      'reconciliationEvidence': reconciliationEvidence!.toJson(),
  };

  factory PaymentVoucher.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported voucher version.');
    }
    final attachments = (json['attachments'] as List)
        .map(
          (a) =>
              ReceiptAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        )
        .toList();
    if (attachments.map((a) => a.originalId).toSet().length !=
        attachments.length) {
      throw const FormatException('Duplicate voucher receipt identity.');
    }
    return PaymentVoucher.create(
      id: json['id'] as String,
      sourceType: PaymentVoucherSourceType.values.byName(
        json['sourceType'] as String,
      ),
      sourceId: json['sourceId'] as String,
      payee: json['payee'] as String,
      amount: Money.fromMinor(
        json['amountMinor'] as int,
        json['currency'] as String,
      ),
      paymentAccount: json['paymentAccount'] as String,
      paymentAccountId: json['paymentAccountId'] as String?,
      paymentMethod: json['paymentMethod'] as String,
      paymentDate: DateTime.parse(json['paymentDate'] as String),
      reference: json['reference'] as String,
      status: PaymentVoucherStatus.values.byName(json['status'] as String),
      allocations: (json['allocations'] as List).cast<String>(),
      attachmentNames: (json['attachmentNames'] as List).cast<String>(),
      attachments: attachments,
      preparer: json['preparer'] as String?,
      approver: json['approver'] as String?,
      paidAt: json['paidAt'] == null
          ? null
          : DateTime.parse(json['paidAt'] as String),
      reconciledAt: json['reconciledAt'] == null
          ? null
          : DateTime.parse(json['reconciledAt'] as String),
      paymentEvidence: json['paymentEvidence'] == null
          ? null
          : PaymentVoucherPaymentEvidence.fromJson(
              Map<String, dynamic>.from(json['paymentEvidence'] as Map),
            ),
      reconciliationEvidence: json['reconciliationEvidence'] == null
          ? null
          : PaymentVoucherReconciliationEvidence.fromJson(
              Map<String, dynamic>.from(json['reconciliationEvidence'] as Map),
            ),
    );
  }

  final String id;
  final PaymentVoucherSourceType sourceType;
  final String sourceId;
  final String payee;
  final Money amount;
  final String paymentAccount;
  final String? paymentAccountId;
  final String paymentMethod;
  final DateTime paymentDate;
  final String reference;
  final PaymentVoucherStatus status;
  final List<String> allocations;
  final List<String> attachmentNames;
  final List<ReceiptAttachment> attachments;
  final String? preparer;
  final String? approver;
  final DateTime? paidAt;
  final DateTime? reconciledAt;
  final PaymentVoucherPaymentEvidence? paymentEvidence;
  final PaymentVoucherReconciliationEvidence? reconciliationEvidence;

  /// Payment vouchers settle an existing source; they never create another expense.
  bool get postsExpense => false;

  void _requireAvailableAttachments() {
    if (attachments.any(
      (attachment) => attachment.status == AttachmentProcessingStatus.failed,
    )) {
      throw StateError(
        'Reconnect or review unavailable supporting documents before submitting or approving this voucher.',
      );
    }
  }

  PaymentVoucher submitForApproval() {
    if (status != PaymentVoucherStatus.draft) {
      throw StateError('Only a draft voucher can be submitted for approval.');
    }
    _requireAvailableAttachments();
    return _copyWith(status: PaymentVoucherStatus.pendingApproval);
  }

  PaymentVoucher approve({String? approver}) {
    if (status != PaymentVoucherStatus.draft &&
        status != PaymentVoucherStatus.pendingApproval) {
      throw StateError('Only a draft or pending voucher can be approved.');
    }
    _requireAvailableAttachments();
    return _copyWith(
      status: PaymentVoucherStatus.approved,
      approver: approver ?? this.approver,
    );
  }

  PaymentVoucher orderPayment() {
    if (status != PaymentVoucherStatus.approved) {
      throw StateError('Only an approved voucher can order payment.');
    }
    return _copyWith(status: PaymentVoucherStatus.paymentOrdered);
  }

  PaymentVoucher recordPayment({
    required DateTime paidAt,
    PaymentVoucherPaymentEvidence? evidence,
  }) {
    if (status != PaymentVoucherStatus.approved &&
        status != PaymentVoucherStatus.paymentOrdered) {
      throw StateError('Only an approved or ordered voucher can be paid.');
    }
    return _copyWith(
      status: PaymentVoucherStatus.paid,
      paidAt: paidAt,
      paymentDate: evidence?.paymentDate,
      paymentEvidence: evidence,
    );
  }

  PaymentVoucher reconcile({
    required DateTime reconciledAt,
    PaymentVoucherPaymentEvidence? paymentEvidence,
    PaymentVoucherReconciliationEvidence? evidence,
  }) {
    if (status != PaymentVoucherStatus.paid &&
        status != PaymentVoucherStatus.processed &&
        !(status == PaymentVoucherStatus.reconciled &&
            evidence != null &&
            evidence != reconciliationEvidence)) {
      throw StateError('Only a paid voucher can be reconciled.');
    }
    return _copyWith(
      status: PaymentVoucherStatus.reconciled,
      reconciledAt: reconciledAt,
      paidAt: paymentEvidence?.paymentDate,
      paymentDate: paymentEvidence?.paymentDate,
      paymentEvidence: paymentEvidence,
      reconciliationEvidence: evidence,
    );
  }

  PaymentVoucher cancel() {
    if (status == PaymentVoucherStatus.paid ||
        status == PaymentVoucherStatus.processed ||
        status == PaymentVoucherStatus.reconciled) {
      throw StateError('A paid voucher must be reversed through accounting.');
    }
    return _copyWith(status: PaymentVoucherStatus.cancelled);
  }

  PaymentVoucher _copyWith({
    PaymentVoucherStatus? status,
    String? approver,
    DateTime? paidAt,
    DateTime? reconciledAt,
    DateTime? paymentDate,
    PaymentVoucherPaymentEvidence? paymentEvidence,
    PaymentVoucherReconciliationEvidence? reconciliationEvidence,
  }) {
    return PaymentVoucher.create(
      id: id,
      sourceType: sourceType,
      sourceId: sourceId,
      payee: payee,
      amount: amount,
      paymentAccount: paymentAccount,
      paymentAccountId: paymentAccountId,
      paymentMethod: paymentMethod,
      paymentDate: paymentDate ?? this.paymentDate,
      reference: reference,
      status: status ?? this.status,
      allocations: allocations,
      attachmentNames: attachmentNames,
      attachments: attachments,
      preparer: preparer,
      approver: approver ?? this.approver,
      paidAt: paidAt ?? this.paidAt,
      reconciledAt: reconciledAt ?? this.reconciledAt,
      paymentEvidence: paymentEvidence ?? this.paymentEvidence,
      reconciliationEvidence:
          reconciliationEvidence ?? this.reconciliationEvidence,
    );
  }

  static void _requireText(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }
}
