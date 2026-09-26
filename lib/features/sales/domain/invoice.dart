import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';

enum InvoiceStatus {
  draft,
  sent,
  viewed,
  partiallyPaid,
  paid,
  overdue,
  voided,
  writtenOff,
  disputed,
}

enum ReceivableAgeBand { current, days1To30, days31To60, days61To90, over90 }

enum InvoiceSettlementStatus {
  posted('Posted', 'Posted'),
  partiallyPaid('Partially Paid', 'Part Paid'),
  paid('Paid', 'Paid'),
  partiallyCredited('Partially Credited', 'Part Credit'),
  credited('Credited', 'Credited'),
  partiallySettled('Partially Settled', 'Part Settled'),
  settled('Settled', 'Settled');

  const InvoiceSettlementStatus(this.label, this.compactLabel);
  final String label;
  final String compactLabel;
}

final class Invoice {
  /// Current settlement follows receipt and receivable-credit allocations.
  /// Excess customer credit is held separately and is not a cash refund.
  InvoiceSettlementStatus settlementStatus({
    required int paidMinor,
    required int creditedMinor,
  }) {
    if (paidMinor + creditedMinor >= total.minorUnits) {
      if (creditedMinor == 0) return InvoiceSettlementStatus.paid;
      if (paidMinor == 0) return InvoiceSettlementStatus.credited;
      return InvoiceSettlementStatus.settled;
    }
    if (paidMinor > 0 && creditedMinor > 0) {
      return InvoiceSettlementStatus.partiallySettled;
    }
    if (creditedMinor > 0) return InvoiceSettlementStatus.partiallyCredited;
    if (paidMinor > 0) return InvoiceSettlementStatus.partiallyPaid;
    return InvoiceSettlementStatus.posted;
  }

  Invoice._({
    required this.id,
    required this.customerId,
    required this.total,
    required List<SalesLineItem> lines,
    required List<ReceiptAttachment> attachments,
    required this.reference,
    required this.memo,
    required this.documentNumber,
    required this.classification,
    required this.location,
    required this.taxMode,
    required this.issueDate,
    required this.dueDate,
    required this.terms,
    this.sourceEstimateId,
    required this.status,
    this.statusBeforeDispute,
    required this.amountPaid,
    required this.unappliedCredit,
    required List<EntityId> paymentIds,
  }) : lines = List.unmodifiable(lines),
       attachments = List.unmodifiable(attachments),
       paymentIds = List.unmodifiable(paymentIds);

  factory Invoice.draft({
    required EntityId id,
    required EntityId customerId,
    Money? total,
    List<SalesLineItem> lines = const [],
    List<ReceiptAttachment> attachments = const [],
    String reference = '',
    String memo = '',
    String documentNumber = '',
    String classification = '',
    String location = '',
    String taxMode = '',
    required DateTime issueDate,
    DateTime? dueDate,
    PaymentTerms? terms,
    EntityId? sourceEstimateId,
  }) {
    if (attachments.map((a) => a.originalId).toSet().length !=
        attachments.length) {
      throw ArgumentError(
        'Invoice attachments must have unique source identities.',
      );
    }
    final normalizedIssueDate = accountingCalendarDate(issueDate);
    final normalizedDueDate = dueDate == null
        ? null
        : accountingCalendarDate(dueDate);
    if (normalizedDueDate != null &&
        normalizedDueDate.isBefore(normalizedIssueDate)) {
      throw ArgumentError.value(
        dueDate,
        'dueDate',
        'An invoice cannot be due before it is issued.',
      );
    }

    final resolvedTotal = lines.isEmpty ? total : SalesLineItem.totalFor(lines);
    if (resolvedTotal == null) {
      throw ArgumentError.value(
        total,
        'total',
        'An invoice requires a total or at least one line.',
      );
    }
    if (lines.isNotEmpty && total != null && total != resolvedTotal) {
      throw ArgumentError.value(
        total,
        'total',
        'An invoice total must equal the sum of its lines.',
      );
    }
    if (!resolvedTotal.isPositive) {
      throw ArgumentError.value(
        resolvedTotal,
        'total',
        'An invoice total must be positive.',
      );
    }

    final resolvedTerms =
        terms ??
        PaymentTerms.netDays(
          normalizedDueDate == null
              ? 0
              : normalizedDueDate.difference(normalizedIssueDate).inDays,
        );
    final resolvedInvoiceDueDate =
        normalizedDueDate ?? resolvedTerms.dueDateFor(normalizedIssueDate);
    if (terms != null &&
        terms.kind != PaymentTermKind.custom &&
        normalizedDueDate != null &&
        resolvedTerms.dueDateFor(normalizedIssueDate) != normalizedDueDate) {
      throw ArgumentError.value(
        terms,
        'terms',
        'Invoice terms must agree with the due date.',
      );
    }

    return Invoice._(
      id: id,
      customerId: customerId,
      total: resolvedTotal,
      lines: lines,
      attachments: attachments,
      reference: reference.trim(),
      memo: memo,
      documentNumber: documentNumber.trim(),
      classification: classification,
      location: location,
      taxMode: taxMode,
      issueDate: normalizedIssueDate,
      dueDate: resolvedInvoiceDueDate,
      terms: resolvedTerms,
      sourceEstimateId: sourceEstimateId,
      status: InvoiceStatus.draft,
      amountPaid: Money.zero(resolvedTotal.currency),
      unappliedCredit: Money.zero(resolvedTotal.currency),
      paymentIds: const [],
    );
  }

  Map<String, Object?> draftSnapshot() {
    if (status != InvoiceStatus.draft) {
      throw StateError('Only a draft can be saved through draft storage.');
    }
    return {
      'version': 1,
      'id': id.value,
      'customer': customerId.value,
      'total': total.minorUnits,
      'currency': total.currency,
      'lines': lines.map((l) => l.toJson()).toList(),
      'issue': issueDate.toIso8601String(),
      'due': dueDate.toIso8601String(),
      'terms': terms.toJson(),
      'estimate': sourceEstimateId?.value,
      if (reference.isNotEmpty) 'reference': reference,
      if (memo.isNotEmpty) 'memo': memo,
      if (documentNumber.isNotEmpty) 'documentNumber': documentNumber,
      if (classification.isNotEmpty) 'classification': classification,
      if (location.isNotEmpty) 'location': location,
      if (taxMode.isNotEmpty) 'taxMode': taxMode,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }

  factory Invoice.fromDraftSnapshot(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported invoice draft version.');
    }
    return Invoice.draft(
      id: EntityId.parse(j['id'] as String),
      customerId: EntityId.parse(j['customer'] as String),
      total: Money.fromMinor(j['total'] as int, j['currency'] as String),
      lines: (j['lines'] as List)
          .map((l) => SalesLineItem.fromJson(l as Map<String, dynamic>))
          .toList(),
      attachments: (j['attachments'] as List? ?? const [])
          .map(
            (a) =>
                ReceiptAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
          )
          .toList(),
      reference: j['reference'] as String? ?? '',
      memo: j['memo'] as String? ?? '',
      documentNumber: j['documentNumber'] as String? ?? '',
      classification: j['classification'] as String? ?? '',
      location: j['location'] as String? ?? '',
      taxMode: j['taxMode'] as String? ?? '',
      issueDate: DateTime.parse(j['issue'] as String),
      dueDate: DateTime.parse(j['due'] as String),
      terms: PaymentTerms.fromJson(j['terms'] as Map<String, dynamic>),
      sourceEstimateId: j['estimate'] == null
          ? null
          : EntityId.parse(j['estimate'] as String),
    );
  }

  final EntityId id;
  final EntityId customerId;
  final Money total;
  final List<SalesLineItem> lines;
  final List<ReceiptAttachment> attachments;
  final String reference, memo;
  final String documentNumber, classification, location, taxMode;
  final DateTime issueDate;
  final DateTime dueDate;
  final PaymentTerms terms;
  final EntityId? sourceEstimateId;
  final InvoiceStatus status;
  final InvoiceStatus? statusBeforeDispute;
  final Money amountPaid;
  final Money unappliedCredit;
  final List<EntityId> paymentIds;

  Money get remaining => total - amountPaid;

  /// Collection age is derived, never a reason to remove revenue or write off.
  /// Callers pass the company's calendar date rather than a device timestamp.
  int daysOverdue({required DateTime asOf}) {
    if (remaining.isZero ||
        status == InvoiceStatus.draft ||
        status == InvoiceStatus.voided ||
        status == InvoiceStatus.writtenOff) {
      return 0;
    }
    final days = accountingCalendarDate(asOf).difference(dueDate).inDays;
    return days > 0 ? days : 0;
  }

  ReceivableAgeBand ageBand({required DateTime asOf}) {
    final days = daysOverdue(asOf: asOf);
    if (days == 0) return ReceivableAgeBand.current;
    if (days <= 30) return ReceivableAgeBand.days1To30;
    if (days <= 60) return ReceivableAgeBand.days31To60;
    if (days <= 90) return ReceivableAgeBand.days61To90;
    return ReceivableAgeBand.over90;
  }

  Invoice send() {
    if (status != InvoiceStatus.draft) {
      throw StateError('Only draft invoices can be sent.');
    }
    return _copyWith(status: InvoiceStatus.sent);
  }

  Invoice view() {
    if (status != InvoiceStatus.sent) {
      throw StateError('Only sent invoices can be viewed.');
    }
    return _copyWith(status: InvoiceStatus.viewed);
  }

  Invoice dispute() {
    if (status != InvoiceStatus.sent &&
        status != InvoiceStatus.viewed &&
        status != InvoiceStatus.partiallyPaid &&
        status != InvoiceStatus.overdue) {
      throw StateError('Only open invoices can be disputed.');
    }
    return _copyWith(
      status: InvoiceStatus.disputed,
      statusBeforeDispute: status,
    );
  }

  Invoice resolveDispute({required DateTime asOf}) {
    if (status != InvoiceStatus.disputed) {
      throw StateError('Only disputed invoices can be resolved.');
    }
    final normalizedAsOf = accountingCalendarDate(asOf);
    final resolvedStatus = remaining.isZero
        ? InvoiceStatus.paid
        : !normalizedAsOf.isAfter(accountingCalendarDate(dueDate))
        ? (amountPaid.isZero
              ? (statusBeforeDispute == InvoiceStatus.viewed
                    ? InvoiceStatus.viewed
                    : InvoiceStatus.sent)
              : InvoiceStatus.partiallyPaid)
        : InvoiceStatus.overdue;
    return _copyWith(status: resolvedStatus);
  }

  Invoice voidInvoice() {
    if (status == InvoiceStatus.paid ||
        status == InvoiceStatus.voided ||
        status == InvoiceStatus.writtenOff) {
      throw StateError('A paid or closed invoice cannot be voided.');
    }
    return _copyWith(status: InvoiceStatus.voided);
  }

  Invoice writeOff() {
    if (status != InvoiceStatus.sent &&
        status != InvoiceStatus.viewed &&
        status != InvoiceStatus.partiallyPaid &&
        status != InvoiceStatus.overdue) {
      throw StateError('Only an open invoice can be written off.');
    }
    return _copyWith(status: InvoiceStatus.writtenOff);
  }

  Invoice recordPayment({
    required EntityId paymentId,
    required Money amount,
    required DateTime paidAt,
  }) {
    if (status != InvoiceStatus.sent &&
        status != InvoiceStatus.viewed &&
        status != InvoiceStatus.partiallyPaid &&
        status != InvoiceStatus.overdue) {
      throw StateError('Only open invoices can receive payments.');
    }
    if (paymentIds.contains(paymentId)) {
      throw StateError('A payment cannot be applied twice.');
    }
    if (!amount.isPositive) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A payment must be positive.',
      );
    }
    if (amount.currency != total.currency) {
      throw StateError('A payment must use the invoice currency.');
    }
    final amountToApply = amount.minorUnits > remaining.minorUnits
        ? remaining
        : amount;
    final excess = amount - amountToApply;
    final newAmountPaid = amountPaid + amountToApply;
    final isPaid = newAmountPaid == total;
    return _copyWith(
      status: isPaid
          ? InvoiceStatus.paid
          : accountingCalendarDate(paidAt).isAfter(dueDate)
          ? InvoiceStatus.overdue
          : InvoiceStatus.partiallyPaid,
      amountPaid: newAmountPaid,
      unappliedCredit: unappliedCredit + excess,
      paymentIds: [...paymentIds, paymentId],
    );
  }

  Invoice markOverdue({required DateTime asOf}) {
    final normalizedAsOf = accountingCalendarDate(asOf);
    if (remaining.isZero ||
        !normalizedAsOf.isAfter(accountingCalendarDate(dueDate))) {
      return this;
    }
    if (status != InvoiceStatus.sent &&
        status != InvoiceStatus.viewed &&
        status != InvoiceStatus.partiallyPaid &&
        status != InvoiceStatus.overdue) {
      return this;
    }
    return _copyWith(status: InvoiceStatus.overdue);
  }

  Invoice _copyWith({
    List<ReceiptAttachment>? attachments,
    InvoiceStatus? status,
    Money? amountPaid,
    Money? unappliedCredit,
    List<EntityId>? paymentIds,
    InvoiceStatus? statusBeforeDispute,
  }) {
    return Invoice._(
      id: id,
      customerId: customerId,
      total: total,
      lines: lines,
      attachments: attachments ?? this.attachments,
      reference: reference.trim(),
      memo: memo,
      documentNumber: documentNumber.trim(),
      classification: classification,
      location: location,
      taxMode: taxMode,
      issueDate: issueDate,
      dueDate: dueDate,
      terms: terms,
      sourceEstimateId: sourceEstimateId,
      status: status ?? this.status,
      statusBeforeDispute: statusBeforeDispute ?? this.statusBeforeDispute,
      amountPaid: amountPaid ?? this.amountPaid,
      unappliedCredit: unappliedCredit ?? this.unappliedCredit,
      paymentIds: paymentIds ?? this.paymentIds,
    );
  }

  Invoice withAttachments(List<ReceiptAttachment> values) =>
      _copyWith(attachments: List.unmodifiable(values));
}
