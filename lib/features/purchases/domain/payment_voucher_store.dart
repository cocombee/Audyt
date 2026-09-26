import 'payment_voucher_source.dart';
import 'payment_voucher_evidence.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';

final class PaymentVoucherStore extends ChangeNotifier {
  PaymentVoucherStore({
    this.persist,
    this.loadVouchers,
    this.loadSources,
    this.loadPaymentEvidence,
    this.loadReconciliationEvidence,
    this.approverIdentity,
    Iterable<PaymentVoucher> vouchers = const <PaymentVoucher>[],
  }) : _vouchers = vouchers.toList() {
    if ((loadPaymentEvidence == null) != (loadReconciliationEvidence == null)) {
      throw ArgumentError(
        'Payment and reconciliation evidence providers belong together.',
      );
    }
  }

  factory PaymentVoucherStore.demo() {
    return PaymentVoucherStore(
      vouchers: <PaymentVoucher>[
        PaymentVoucher.create(
          id: 'voucher-direct-2026-0001',
          sourceType: PaymentVoucherSourceType.directExpense,
          sourceId: 'expense-demo-office-supplies',
          payee: 'Northwind Office Supplies',
          amount: Money.fromMinor(18500, 'MYR'),
          paymentAccount: 'Maybank Current',
          paymentMethod: 'Bank transfer',
          paymentDate: DateTime.utc(2026, 8, 20),
          reference: 'PV-2026-0001',
          status: PaymentVoucherStatus.paid,
          preparer: 'Finance Demo User',
          approver: 'Finance Demo Approver',
          paidAt: DateTime.utc(2026, 8, 20, 11),
          allocations: const <String>['Office Supplies · RM 185.00'],
          attachmentNames: const <String>['northwind-invoice.pdf'],
        ),
        PaymentVoucher.create(
          id: 'voucher-claim-2026-0002',
          sourceType: PaymentVoucherSourceType.claimPayment,
          sourceId: '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a91',
          payee: 'Daniel Wong',
          amount: Money.fromMinor(230000, 'MYR'),
          paymentAccount: 'Maybank Current',
          paymentMethod: 'Bank transfer',
          paymentDate: DateTime.utc(2026, 8, 31),
          reference: 'PV-2026-0002',
          status: PaymentVoucherStatus.approved,
          preparer: 'Finance Demo User',
          approver: 'Finance Demo Approver',
          allocations: const <String>['Business Travel · RM 2,300.00'],
          attachmentNames: const <String>['daniel-hotel-receipt.pdf'],
        ),
        PaymentVoucher.create(
          id: 'voucher-bill-2026-0003',
          sourceType: PaymentVoucherSourceType.billSettlement,
          sourceId: 'bill-demo-2026-0003',
          payee: 'Cerah Internet Sdn Bhd',
          amount: Money.fromMinor(12900, 'MYR'),
          paymentAccount: 'Maybank Current',
          paymentMethod: 'Online transfer',
          paymentDate: DateTime.utc(2026, 9, 1),
          reference: 'PV-2026-0003',
          status: PaymentVoucherStatus.pendingApproval,
          preparer: 'Finance Demo User',
          allocations: const <String>['Utilities · RM 129.00'],
          attachmentNames: const <String>['cerah-internet-bill.pdf'],
        ),
      ],
    );
  }

  final List<PaymentVoucher> _vouchers;
  final void Function(PaymentVoucher)? persist;
  final List<PaymentVoucher> Function()? loadVouchers;
  final List<PaymentVoucherSource> Function()? loadSources;
  final PaymentVoucherPaymentEvidence Function(PaymentVoucher)?
  loadPaymentEvidence;
  final PaymentVoucherReconciliationEvidence Function(
    PaymentVoucher,
    PaymentVoucherPaymentEvidence,
  )?
  loadReconciliationEvidence;
  final String? approverIdentity;
  bool get hasFinancialEvidence => loadPaymentEvidence != null;
  bool get hasSourceProvider => loadSources != null;
  List<PaymentVoucherSource> get sources =>
      List.unmodifiable(loadSources?.call() ?? const <PaymentVoucherSource>[]);

  List<PaymentVoucher> get all => List<PaymentVoucher>.unmodifiable(_vouchers);

  void reload() {
    final loaded = loadVouchers?.call();
    if (loaded == null) return;
    _vouchers
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  PaymentVoucher? byId(String id) {
    for (final voucher in _vouchers) {
      if (voucher.id == id) return voucher;
    }
    return null;
  }

  void _requireEditable(PaymentVoucher voucher) {
    final existing = byId(voucher.id);
    if (voucher.status != PaymentVoucherStatus.draft ||
        (existing != null && existing.status != PaymentVoucherStatus.draft)) {
      throw StateError(
        'Only draft payment vouchers can be saved or submitted.',
      );
    }
  }

  void _requireCurrent(
    PaymentVoucher voucher,
    PaymentVoucher? expectedCurrent,
  ) {
    if (expectedCurrent != null && expectedCurrent.id != voucher.id) {
      throw ArgumentError(
        'The reviewed voucher must match the edited voucher.',
      );
    }
    if (expectedCurrent != null &&
        jsonEncode(byId(expectedCurrent.id)?.toJson()) !=
            jsonEncode(expectedCurrent.toJson())) {
      throw StateError(
        'Voucher changed since it was opened. Reopen before saving.',
      );
    }
  }

  PaymentVoucher save(
    PaymentVoucher voucher, {
    PaymentVoucher? expectedCurrent,
  }) {
    _requireCurrent(voucher, expectedCurrent);
    _requireEditable(voucher);
    return _commit(voucher);
  }

  PaymentVoucher saveAndSubmit(
    PaymentVoucher voucher, {
    PaymentVoucher? expectedCurrent,
  }) {
    _requireCurrent(voucher, expectedCurrent);
    _requireEditable(voucher);
    return _commit(voucher.submitForApproval());
  }

  PaymentVoucher _commit(PaymentVoucher voucher) {
    persist?.call(voucher);
    final index = _vouchers.indexWhere((item) => item.id == voucher.id);
    if (index < 0) {
      _vouchers.add(voucher);
    } else {
      _vouchers[index] = voucher;
    }
    notifyListeners();
    return voucher;
  }

  PaymentVoucher submit(String id) =>
      _update(id, (voucher) => voucher.submitForApproval());

  PaymentVoucher approve(String id, {String? approver}) => _update(
    id,
    (voucher) => voucher.approve(approver: approverIdentity ?? approver),
  );

  PaymentVoucher orderPayment(String id) =>
      _update(id, (voucher) => voucher.orderPayment());

  PaymentVoucher recordPayment(
    String id, {
    DateTime? paidAt,
    PaymentVoucher? expectedCurrent,
    PaymentVoucherPaymentEvidence? expectedPaymentEvidence,
  }) => _update(id, (voucher) {
    _requireCurrent(voucher, expectedCurrent);
    final evidence = loadPaymentEvidence?.call(voucher);
    if (expectedPaymentEvidence != null &&
        evidence != expectedPaymentEvidence) {
      throw StateError(
        'The reviewed payment changed. Reopen before confirming.',
      );
    }
    final date = evidence?.paymentDate ?? paidAt;
    if (date == null) throw ArgumentError('A payment date is required.');
    if (evidence != null && paidAt != null && !paidAt.isAtSameMomentAs(date)) {
      throw StateError(
        'Payment date must match the actual posted source payment.',
      );
    }
    if (evidence != null &&
        voucher.paymentEvidence == evidence &&
        {
          PaymentVoucherStatus.paid,
          PaymentVoucherStatus.processed,
          PaymentVoucherStatus.reconciled,
        }.contains(voucher.status)) {
      return voucher;
    }
    return voucher.recordPayment(paidAt: date, evidence: evidence);
  });

  PaymentVoucher reconcile(
    String id, {
    DateTime? reconciledAt,
    PaymentVoucher? expectedCurrent,
  }) => _update(id, (voucher) {
    _requireCurrent(voucher, expectedCurrent);
    final payment = loadPaymentEvidence?.call(voucher);
    if (voucher.paymentEvidence != null && voucher.paymentEvidence != payment) {
      throw StateError(
        'The acknowledged source payment changed. Review its correction.',
      );
    }
    final evidence = payment == null
        ? null
        : loadReconciliationEvidence?.call(voucher, payment);
    final date = evidence?.approvedAt ?? reconciledAt;
    if (date == null) throw ArgumentError('A reconciliation date is required.');
    if (evidence != null &&
        reconciledAt != null &&
        !reconciledAt.isAtSameMomentAs(date)) {
      throw StateError(
        'Reconciliation date must match the completed bank review.',
      );
    }
    if (evidence != null &&
        voucher.status == PaymentVoucherStatus.reconciled &&
        voucher.paymentEvidence == payment &&
        voucher.reconciliationEvidence == evidence) {
      return voucher;
    }
    return voucher.reconcile(
      reconciledAt: date,
      paymentEvidence: payment,
      evidence: evidence,
    );
  });

  /// Live status can change after a linked payment reversal or bank reopening.
  /// Historical acknowledgement IDs and timestamps remain in the saved voucher.
  PaymentVoucherVerification verification(PaymentVoucher voucher) {
    if (!hasFinancialEvidence ||
        !{
          PaymentVoucherStatus.paid,
          PaymentVoucherStatus.processed,
          PaymentVoucherStatus.reconciled,
        }.contains(voucher.status)) {
      return PaymentVoucherVerification(voucher.status);
    }
    late PaymentVoucherPaymentEvidence payment;
    try {
      payment = loadPaymentEvidence!(voucher);
      if (voucher.paymentEvidence != null &&
          voucher.paymentEvidence != payment) {
        throw StateError(
          'The linked posted payment changed. Review its accounting correction.',
        );
      }
    } on StateError catch (error) {
      return PaymentVoucherVerification(
        PaymentVoucherStatus.onHold,
        explanation: error.message.toString(),
      );
    }
    if (voucher.status == PaymentVoucherStatus.reconciled) {
      try {
        final current = loadReconciliationEvidence!(voucher, payment);
        if (voucher.reconciliationEvidence == current) {
          return const PaymentVoucherVerification(
            PaymentVoucherStatus.reconciled,
            paymentVerified: true,
            reconciliationVerified: true,
          );
        }
        return const PaymentVoucherVerification(
          PaymentVoucherStatus.paid,
          paymentVerified: true,
          explanation: 'The bank reconciliation changed. Confirm the current completed review.',
        );
      } on StateError catch (error) {
        return PaymentVoucherVerification(
          PaymentVoucherStatus.paid,
          paymentVerified: true,
          explanation: error.message.toString(),
        );
      }
    }
    return PaymentVoucherVerification(voucher.status, paymentVerified: true);
  }

  PaymentVoucher cancel(String id) =>
      _update(id, (voucher) => voucher.cancel());

  PaymentVoucher _update(
    String id,
    PaymentVoucher Function(PaymentVoucher) update,
  ) {
    final current = byId(id);
    if (current == null) throw StateError('Payment voucher $id was not found.');
    return _commit(update(current));
  }
}

final class PaymentVoucherVerification {
  const PaymentVoucherVerification(
    this.status, {
    this.explanation,
    this.paymentVerified = false,
    this.reconciliationVerified = false,
  });
  final PaymentVoucherStatus status;
  final String? explanation;
  // Fresh loader results only. Retained IDs and a status label do not grant
  // either proof, and reopening preserves payment proof without review proof.
  final bool paymentVerified;
  final bool reconciliationVerified;
}
