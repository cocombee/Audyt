import '../../../core/ids/entity_id.dart';

/// Company-owned Expense payment-method metadata. This is not a bank account,
/// ledger posting choice, or a historical voucher payment-method string.
final class CompanyPaymentMethod {
  CompanyPaymentMethod({
    required this.id,
    required String name,
    this.cardPayment = false,
    this.active = true,
    this.revision = 0,
  }) : name = name.trim() {
    if (this.name.isEmpty || this.name.length > 200 || revision < 0) {
      throw const FormatException('Enter a valid payment method name.');
    }
  }

  final EntityId id;
  final String name;
  final bool cardPayment;
  final bool active;
  final int revision;

  String get choice => '${id.value}:$revision';

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id.value,
    'name': name,
    'cardPayment': cardPayment,
    'active': active,
    'revision': revision,
  };

  factory CompanyPaymentMethod.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported payment method version.');
    }
    return CompanyPaymentMethod(
      id: EntityId.parse(json['id'] as String),
      name: json['name'] as String,
      cardPayment: json['cardPayment'] as bool,
      active: json['active'] as bool,
      revision: json['revision'] as int,
    );
  }
}
