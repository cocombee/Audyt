import '../../../core/ids/entity_id.dart';

/// Immutable provenance for an Expense presented from an approved Claim.
/// Claim approval originates this identity. Current Expense revisions retain
/// its identity and their own line bases; the original approval stays intact.
final class ExpenseClaimSource {
  ExpenseClaimSource({
    required this.claimId,
    required this.recognitionId,
    required this.liabilityAccountId,
    required this.claimantName,
    required this.approvedAt,
    this.claimantId,
    this.claimantType,
    Map<String, String> lineBases = const {},
  }) : lineBases = Map.unmodifiable(
         Map.fromEntries(
           lineBases.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
         ),
       ) {
    if ((claimantId == null) != (claimantType == null) ||
        (claimantId != null && claimantId!.trim().isEmpty) ||
        (claimantType != null &&
            !const {'staff', 'director'}.contains(claimantType)) ||
        lineBases.entries.any(
          (e) =>
              e.key.isEmpty ||
              !const {'Exclusive', 'Inclusive'}.contains(e.value),
        )) {
      throw const FormatException('Invalid approved Claim provenance.');
    }
  }

  static const mixedBasis = 'Mixed Receipt Bases';
  final EntityId claimId, recognitionId, liabilityAccountId;
  final String claimantName;
  final String? claimantId, claimantType;
  final DateTime approvedAt;
  final Map<String, String> lineBases;

  Map<String, Object?> toJson() => {
    'claimId': claimId.value,
    'recognitionId': recognitionId.value,
    'liabilityAccountId': liabilityAccountId.value,
    'claimantName': claimantName,
    'claimantId': claimantId,
    'claimantType': claimantType,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
    'lineBases': lineBases,
  };

  factory ExpenseClaimSource.fromJson(Map<String, dynamic> json) =>
      ExpenseClaimSource(
        claimId: EntityId.parse(json['claimId'] as String),
        recognitionId: EntityId.parse(json['recognitionId'] as String),
        liabilityAccountId: EntityId.parse(
          json['liabilityAccountId'] as String,
        ),
        claimantName: json['claimantName'] as String,
        claimantId: json['claimantId'] as String?,
        claimantType: json['claimantType'] as String?,
        approvedAt: DateTime.parse(json['approvedAt'] as String),
        lineBases: Map<String, String>.from(json['lineBases'] as Map),
      );
}
