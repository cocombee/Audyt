import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'voucher links to exactly one supported source and never posts an expense',
    () {
      final voucher = PaymentVoucher.create(
        id: 'voucher-direct-1',
        sourceType: PaymentVoucherSourceType.directExpense,
        sourceId: 'expense-local-1',
        payee: 'Acme Office Supplies',
        amount: Money.fromMinor(1250, 'MYR'),
        paymentAccount: 'Maybank Current',
        paymentMethod: 'Bank transfer',
        paymentDate: DateTime.utc(2026, 8, 31),
        reference: 'PV-2026-0001',
      );
      expect(voucher.sourceType, PaymentVoucherSourceType.directExpense);
      expect(voucher.sourceId, 'expense-local-1');
      expect(voucher.postsExpense, isFalse);
      expect(voucher.status, PaymentVoucherStatus.draft);
      expect(
        () => PaymentVoucher.create(
          id: 'invalid',
          sourceType: PaymentVoucherSourceType.claimPayment,
          sourceId: '',
          payee: 'Aina Rahman',
          amount: Money.fromMinor(100, 'MYR'),
          paymentAccount: 'Cash',
          paymentMethod: 'Cash',
          paymentDate: DateTime.utc(2026, 8, 31),
          reference: 'PV-INVALID',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'approved for payment remains distinct from paid until payment is recorded',
    () {
      final store = PaymentVoucherStore.demo();
      final approved = store.all.singleWhere(
        (voucher) => voucher.status == PaymentVoucherStatus.approved,
      );
      expect(approved.status.label, 'Approved for payment');
      expect(approved.sourceType, PaymentVoucherSourceType.claimPayment);
      expect(approved.postsExpense, isFalse);

      final paid = store.recordPayment(
        approved.id,
        paidAt: DateTime.utc(2026, 8, 31, 14),
      );
      expect(paid.status, PaymentVoucherStatus.paid);
      expect(store.byId(approved.id)?.status, PaymentVoucherStatus.paid);
      expect(
        () => store.recordPayment(
          approved.id,
          paidAt: DateTime.utc(2026, 8, 31, 15),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'demo vouchers expose direct expense and claim-payment source links',
    () {
      final store = PaymentVoucherStore.demo();
      expect(
        store.all.map((voucher) => voucher.sourceType),
        containsAll(<PaymentVoucherSourceType>[
          PaymentVoucherSourceType.directExpense,
          PaymentVoucherSourceType.claimPayment,
        ]),
      );
      expect(store.all.every((voucher) => voucher.sourceId.isNotEmpty), isTrue);
    },
  );

  test(
    'keeps foreign currency and real attachment bytes through workflow copies',
    () {
      final originalBytes = Uint8List.fromList('%PDF-1.7\nforeign'.codeUnits);
      final attachment = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'voucher-attachment-1',
          batchId: 'voucher-batch-1',
          filename: 'foreign-invoice.pdf',
          mimeType: 'application/pdf',
          bytes: originalBytes,
        ),
      ).withStatus(AttachmentProcessingStatus.ready);
      final voucher = PaymentVoucher.create(
        id: 'voucher-foreign-1',
        sourceType: PaymentVoucherSourceType.billSettlement,
        sourceId: 'bill-foreign-1',
        payee: 'Foreign Supplier',
        amount: Money.fromDecimal('123.45', 'USD'),
        paymentAccount: 'USD Current',
        paymentMethod: 'Bank transfer',
        paymentDate: DateTime.utc(2026, 9, 7),
        reference: 'PV-USD-1',
        attachments: <ReceiptAttachment>[attachment],
      );

      expect(voucher.amount.currency, 'USD');
      expect(voucher.attachmentNames, <String>['foreign-invoice.pdf']);
      expect(voucher.attachments.single.originalBytes, originalBytes);
      expect(
        voucher.approve(approver: 'Reviewer').attachments.single.originalBytes,
        originalBytes,
      );
    },
  );
}
