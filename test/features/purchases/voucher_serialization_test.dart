import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';

void main() {
  test('settlement timestamps are consistent and retain the reviewer', () {
    final approved = PaymentVoucherStore.demo().all[1];
    final paidAt = DateTime.utc(2026, 9, 1, 12);
    final paid = approved.recordPayment(paidAt: paidAt);
    expect(paid.approver, approved.approver);
    expect(
      () => paid.reconcile(
        reconciledAt: paidAt.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    final reconciled = paid.reconcile(reconciledAt: paidAt);
    expect(reconciled.approver, approved.approver);
    expect(reconciled.paidAt, paidAt);
    expect(
      () => PaymentVoucher.fromJson({...paid.toJson(), 'paidAt': null}),
      throwsArgumentError,
    );
    expect(
      () => PaymentVoucher.fromJson({...paid.toJson(), 'status': 'draft'}),
      throwsArgumentError,
    );
    final processed = PaymentVoucher.fromJson({
      ...paid.toJson(),
      'status': 'processed',
    });
    expect(processed.cancel, throwsStateError);
  });
  test(
    'submission commits once and approved vouchers resist draft overwrite',
    () {
      final draft = PaymentVoucher.fromJson({
        ...PaymentVoucherStore.demo().all.last.toJson(),
        'status': 'draft',
      });
      final writes = <PaymentVoucher>[];
      final store = PaymentVoucherStore(persist: writes.add);
      store.saveAndSubmit(draft);
      expect(writes.single.status, PaymentVoucherStatus.pendingApproval);
      store.approve(draft.id);
      expect(() => store.save(draft), throwsStateError);
      expect(() => store.saveAndSubmit(draft), throwsStateError);
      expect(writes.length, 2);
      expect(store.byId(draft.id)!.status, PaymentVoucherStatus.approved);
    },
  );
  test('failed first submission leaves no partial draft', () {
    final draft = PaymentVoucher.fromJson({
      ...PaymentVoucherStore.demo().all.last.toJson(),
      'status': 'draft',
    });
    final store = PaymentVoucherStore(
      persist: (_) => throw StateError('Storage unavailable'),
    );
    expect(() => store.saveAndSubmit(draft), throwsStateError);
    expect(store.all, isEmpty);
  });
  test('voucher source and lifecycle details survive JSON roundtrip', () {
    for (final voucher in PaymentVoucherStore.demo().all) {
      final restored = PaymentVoucher.fromJson(
        jsonDecode(jsonEncode(voucher.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), voucher.toJson());
    }
  });
  test('failed persistence leaves voucher unchanged', () {
    final voucher = PaymentVoucherStore.demo().all.last;
    final store = PaymentVoucherStore(
      vouchers: [voucher],
      persist: (_) => throw StateError('Storage unavailable'),
    );
    expect(() => store.approve(voucher.id), throwsStateError);
    expect(store.byId(voucher.id), same(voucher));
  });
}
