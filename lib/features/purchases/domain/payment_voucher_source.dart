import '../../../core/money/money.dart';
import 'payment_voucher.dart';

/// A current saved source owned by the voucher's accounting company.
/// This is derived data, not another financial posting or persisted snapshot.
final class PaymentVoucherSource {
  const PaymentVoucherSource({
    required this.type,
    required this.id,
    required this.payee,
    required this.amount,
    required this.paymentAccountId,
    required this.date,
    this.detail,
  });

  final PaymentVoucherSourceType type;
  final String id;
  final String payee;
  final Money amount;
  final String paymentAccountId;
  final DateTime date;

  /// Derived picker context; the persisted source identity remains authoritative.
  final String? detail;
}
