import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim_payment_batch.dart';

final class ClaimFilingChange {
  const ClaimFilingChange({
    required this.claimId,
    required this.sourceRelativePath,
    required this.destinationRelativePath,
    required this.paidStamp,
    required this.batchId,
    required this.paidAt,
  });

  final EntityId claimId;
  final String sourceRelativePath;
  final String destinationRelativePath;
  final String paidStamp;
  final EntityId batchId;
  final DateTime paidAt;
}

final class PaidClaimFilingPlan {
  PaidClaimFilingPlan._({
    required this.batchId,
    required this.paidAt,
    required List<ClaimFilingChange> changes,
  }) : changes = List.unmodifiable(changes);

  factory PaidClaimFilingPlan.build({
    required ClaimPaymentBatch batch,
    required Map<EntityId, String> sourcePaths,
    required Map<EntityId, String> destinationPaths,
    required String paidStamp,
  }) {
    final normalizedStamp = paidStamp.trim();
    if (normalizedStamp.isEmpty) {
      throw ArgumentError.value(
        paidStamp,
        'paidStamp',
        'A paid stamp is required.',
      );
    }

    final changes = <ClaimFilingChange>[];
    for (final claim in batch.claims) {
      final sourcePath = sourcePaths[claim.id];
      final destinationPath = destinationPaths[claim.id];
      if (sourcePath == null || destinationPath == null) {
        throw ArgumentError.value(
          claim.id,
          'paths',
          'Every paid claim needs a source and destination path.',
        );
      }
      _validateRelativePath(sourcePath);
      _validateRelativePath(destinationPath);
      if (sourcePath == destinationPath) {
        throw ArgumentError.value(
          destinationPath,
          'destinationPaths',
          'A paid filing destination must differ from its source.',
        );
      }
      changes.add(
        ClaimFilingChange(
          claimId: claim.id,
          sourceRelativePath: sourcePath,
          destinationRelativePath: destinationPath,
          paidStamp: normalizedStamp,
          batchId: batch.id,
          paidAt: batch.paidAt,
        ),
      );
    }
    return PaidClaimFilingPlan._(
      batchId: batch.id,
      paidAt: batch.paidAt,
      changes: changes,
    );
  }

  final EntityId batchId;
  final DateTime paidAt;
  final List<ClaimFilingChange> changes;

  static void _validateRelativePath(String path) {
    if (path.trim().isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').contains('..')) {
      throw ArgumentError.value(
        path,
        'path',
        'Filing paths must be relative and path-safe.',
      );
    }
  }
}
