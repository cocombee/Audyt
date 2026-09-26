import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

enum BillStatus { draft, open, partiallyPaid, paid, overdue, voided }

final class Bill {
  Bill._({
    required this.id,
    required this.vendorId,
    required this.total,
    required this.issueDate,
    required this.dueDate,
    required this.terms,
    required this.status,
    required this.amountPaid,
    required this.unappliedCredit,
    required List<EntityId> paymentIds,
  }) : paymentIds = List.unmodifiable(paymentIds);

  factory Bill.draft({
    required EntityId id,
    required EntityId vendorId,
    required Money total,
    required DateTime issueDate,
    DateTime? dueDate,
    PaymentTerms? terms,
  }) {
    if (!total.isPositive) {
      throw ArgumentError.value(
        total,
        'total',
        'A bill total must be positive.',
      );
    }
    final normalizedIssueDate = accountingCalendarDate(issueDate);
    if (dueDate == null && terms == null) {
      throw ArgumentError('A bill requires a due date or payment terms.');
    }
    final normalizedDueDate = dueDate == null
        ? terms!.dueOn(normalizedIssueDate)
        : accountingCalendarDate(dueDate);
    if (terms != null &&
        terms.kind != PaymentTermKind.custom &&
        terms.dueOn(normalizedIssueDate) != normalizedDueDate) {
      throw ArgumentError('Bill terms must agree with the due date.');
    }
    if (normalizedDueDate.isBefore(normalizedIssueDate)) {
      throw ArgumentError.value(
        dueDate,
        'dueDate',
        'A bill cannot be due before it is issued.',
      );
    }
    return Bill._(
      id: id,
      vendorId: vendorId,
      total: total,
      issueDate: normalizedIssueDate,
      dueDate: normalizedDueDate,
      terms:
          terms ??
          PaymentTerms.daysAfterIssue(
            normalizedDueDate.difference(normalizedIssueDate).inDays,
          ),
      status: BillStatus.draft,
      amountPaid: Money.zero(total.currency),
      unappliedCredit: Money.zero(total.currency),
      paymentIds: const [],
    );
  }

  Map<String, Object?> draftSnapshot() {
    if (status != BillStatus.draft ||
        !amountPaid.isZero ||
        paymentIds.isNotEmpty) {
      throw StateError('Only an unposted bill draft can use draft storage.');
    }
    return {
      'version': 1,
      'id': id.value,
      'vendorId': vendorId.value,
      'amountMinor': total.minorUnits,
      'currency': total.currency,
      'issueDate': formatAccountingInputDate(issueDate),
      'dueDate': formatAccountingInputDate(dueDate),
      'terms': terms.toJson(),
    };
  }

  factory Bill.restoreDraft(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['amountMinor'] is! int ||
        json['issueDate'] is! String ||
        json['dueDate'] is! String ||
        json['terms'] is! Map<String, dynamic> ||
        json.keys.any(
          (key) => !const {
            'version',
            'id',
            'vendorId',
            'amountMinor',
            'currency',
            'issueDate',
            'dueDate',
            'terms',
          }.contains(key),
        )) {
      throw const FormatException('Invalid bill draft snapshot.');
    }
    final issued = parseAccountingInputDate(json['issueDate'] as String);
    final due = parseAccountingInputDate(json['dueDate'] as String);
    if (issued == null || due == null) {
      throw const FormatException('Invalid bill calendar dates.');
    }
    return Bill.draft(
      id: EntityId.parse(json['id'] as String),
      vendorId: EntityId.parse(json['vendorId'] as String),
      total: Money.fromMinor(
        json['amountMinor'] as int,
        json['currency'] as String,
      ),
      issueDate: issued,
      dueDate: due,
      terms: PaymentTerms.fromJson(json['terms'] as Map<String, dynamic>),
    );
  }

  final EntityId id;
  final EntityId vendorId;
  final Money total;
  final DateTime issueDate;
  final DateTime dueDate;
  final PaymentTerms terms;
  final BillStatus status;
  final Money amountPaid;
  final Money unappliedCredit;
  final List<EntityId> paymentIds;

  Money get remaining => total - amountPaid;

  Bill review() {
    if (status != BillStatus.draft) {
      throw StateError('Only draft bills can be reviewed.');
    }
    return _copyWith(status: BillStatus.open);
  }

  Bill recordPayment({
    required EntityId paymentId,
    required Money amount,
    required DateTime paidAt,
  }) {
    if (status != BillStatus.open &&
        status != BillStatus.partiallyPaid &&
        status != BillStatus.overdue) {
      throw StateError('Only open bills can receive payments.');
    }
    if (paymentIds.contains(paymentId)) {
      throw StateError('A bill payment cannot be applied twice.');
    }
    if (!amount.isPositive) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A payment must be positive.',
      );
    }
    if (amount.currency != total.currency) {
      throw StateError('A payment must use the bill currency.');
    }
    final amountToApply = amount.minorUnits > remaining.minorUnits
        ? remaining
        : amount;
    final excess = amount - amountToApply;
    final newAmountPaid = amountPaid + amountToApply;
    final isPaid = newAmountPaid == total;
    return _copyWith(
      status: isPaid ? BillStatus.paid : BillStatus.partiallyPaid,
      amountPaid: newAmountPaid,
      unappliedCredit: unappliedCredit + excess,
      paymentIds: [...paymentIds, paymentId],
    );
  }

  Bill markOverdue({required DateTime asOf}) {
    final normalizedAsOf = accountingCalendarDate(asOf);
    if (remaining.isZero ||
        !normalizedAsOf.isAfter(accountingCalendarDate(dueDate))) {
      return this;
    }
    if (status != BillStatus.open &&
        status != BillStatus.partiallyPaid &&
        status != BillStatus.overdue) {
      return this;
    }
    return _copyWith(status: BillStatus.overdue);
  }

  Bill _copyWith({
    BillStatus? status,
    Money? amountPaid,
    Money? unappliedCredit,
    List<EntityId>? paymentIds,
  }) {
    return Bill._(
      id: id,
      vendorId: vendorId,
      total: total,
      issueDate: issueDate,
      dueDate: dueDate,
      terms: terms,
      status: status ?? this.status,
      amountPaid: amountPaid ?? this.amountPaid,
      unappliedCredit: unappliedCredit ?? this.unappliedCredit,
      paymentIds: paymentIds ?? this.paymentIds,
    );
  }
}
