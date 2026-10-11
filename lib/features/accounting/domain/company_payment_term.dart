import '../../../core/ids/entity_id.dart';
import 'payment_terms.dart';

/// A company-maintained name for one exact due-date calculation rule.
final class CompanyPaymentTerm {
  CompanyPaymentTerm({
    required this.id,
    required String name,
    required this.rule,
    this.active = true,
    this.revision = 0,
    this.createdAt,
  }) : name = name.trim() {
    if (this.name.isEmpty || this.name.length > 200 || revision < 0) {
      throw const FormatException('Enter a valid payment term name.');
    }
    if (rule.kind == PaymentTermKind.custom || rule.customText != null) {
      throw const FormatException(
        'Choose a fixed-days or monthly payment rule.',
      );
    }
    if (createdAt != null && !createdAt!.isUtc) {
      throw const FormatException('Payment term creation time must be UTC.');
    }
  }

  final EntityId id;
  final String name;
  final PaymentTerms rule;
  final bool active;
  final int revision;
  final DateTime? createdAt;

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id.value,
    'name': name,
    'rule': rule.toJson(),
    'active': active,
    'revision': revision,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory CompanyPaymentTerm.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['rule'] is! Map<String, dynamic> ||
        json['active'] is! bool ||
        json['revision'] is! int) {
      throw const FormatException('Invalid company payment term.');
    }
    final createdAt = json['createdAt'];
    if (createdAt != null && createdAt is! String) {
      throw const FormatException('Invalid payment term creation time.');
    }
    final parsedAt = createdAt == null ? null : DateTime.tryParse(createdAt);
    if (createdAt != null &&
        (parsedAt == null ||
            !parsedAt.isUtc ||
            parsedAt.toIso8601String() != createdAt)) {
      throw const FormatException('Invalid payment term creation time.');
    }
    return CompanyPaymentTerm(
      id: EntityId.parse(json['id'] as String),
      name: json['name'] as String,
      rule: PaymentTerms.fromJson(json['rule'] as Map<String, dynamic>),
      active: json['active'] as bool,
      revision: json['revision'] as int,
      createdAt: parsedAt,
    );
  }
}
