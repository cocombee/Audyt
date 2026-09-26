import '../../../core/ids/entity_id.dart';

/// Company-owned authority/registration metadata, not a statutory tax policy.
/// A saved code freezes the exact agency revision used for that configuration.
final class CompanyTaxAgency {
  CompanyTaxAgency({
    required this.id,
    required String name,
    String registrationNumber = '',
    String countryCode = 'MY',
    String notes = '',
    this.revision = 0,
  }) : name = name.trim(),
       registrationNumber = registrationNumber.trim(),
       countryCode = countryCode.trim().toUpperCase(),
       notes = notes.trim() {
    if (this.name.isEmpty ||
        this.name.length > 200 ||
        this.registrationNumber.length > 200 ||
        this.notes.length > 4000 ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(this.countryCode) ||
        revision < 0) {
      throw const FormatException('Enter a valid tax agency and country code.');
    }
  }
  final EntityId id;
  final String name, registrationNumber, countryCode, notes;
  final int revision;
  String get choice => '${id.value}:$revision';
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id.value,
    'name': name,
    'registrationNumber': registrationNumber,
    'countryCode': countryCode,
    'notes': notes,
    'revision': revision,
  };
  factory CompanyTaxAgency.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported tax agency version.');
    }
    return CompanyTaxAgency(
      id: EntityId.parse(j['id'] as String),
      name: j['name'] as String,
      registrationNumber: j['registrationNumber'] as String,
      countryCode: j['countryCode'] as String,
      notes: j['notes'] as String,
      revision: j['revision'] as int,
    );
  }
}
