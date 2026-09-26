import 'package:audyt/core/ids/entity_id.dart';

final class RecordMetadata {
  const RecordMetadata._({
    required this.recordId,
    required this.businessId,
    required this.originDeviceId,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.deletedAt,
  });

  factory RecordMetadata.initial({
    required EntityId recordId,
    required EntityId businessId,
    required EntityId originDeviceId,
    required DateTime createdAt,
  }) {
    final normalizedCreatedAt = createdAt.toUtc();
    return RecordMetadata._(
      recordId: recordId,
      businessId: businessId,
      originDeviceId: originDeviceId,
      createdAt: normalizedCreatedAt,
      updatedAt: normalizedCreatedAt,
      revision: 1,
      deletedAt: null,
    );
  }

  factory RecordMetadata.restore({
    required EntityId recordId,
    required EntityId businessId,
    required EntityId originDeviceId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int revision,
    required DateTime? deletedAt,
  }) {
    final normalizedCreatedAt = createdAt.toUtc();
    final normalizedUpdatedAt = updatedAt.toUtc();
    final normalizedDeletedAt = deletedAt?.toUtc();
    if (revision < 1) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Revision must be positive.',
      );
    }
    if (normalizedUpdatedAt.isBefore(normalizedCreatedAt)) {
      throw ArgumentError.value(
        updatedAt,
        'updatedAt',
        'Updated time cannot be before created time.',
      );
    }
    if (normalizedDeletedAt != null &&
        normalizedDeletedAt != normalizedUpdatedAt) {
      throw ArgumentError.value(
        deletedAt,
        'deletedAt',
        'A tombstone time must equal the stored update time.',
      );
    }
    return RecordMetadata._(
      recordId: recordId,
      businessId: businessId,
      originDeviceId: originDeviceId,
      createdAt: normalizedCreatedAt,
      updatedAt: normalizedUpdatedAt,
      revision: revision,
      deletedAt: normalizedDeletedAt,
    );
  }

  final EntityId recordId;
  final EntityId businessId;
  final EntityId originDeviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final DateTime? deletedAt;

  bool get isTombstone => deletedAt != null;

  RecordMetadata nextRevision({required DateTime updatedAt}) {
    if (isTombstone) {
      throw StateError('A tombstone cannot be updated.');
    }
    final normalizedUpdatedAt = updatedAt.toUtc();
    if (!normalizedUpdatedAt.isAfter(this.updatedAt)) {
      throw ArgumentError.value(
        updatedAt,
        'updatedAt',
        'A revision timestamp must be later than the current update.',
      );
    }
    return RecordMetadata._(
      recordId: recordId,
      businessId: businessId,
      originDeviceId: originDeviceId,
      createdAt: createdAt,
      updatedAt: normalizedUpdatedAt,
      revision: revision + 1,
      deletedAt: null,
    );
  }

  RecordMetadata delete({required DateTime deletedAt}) {
    if (isTombstone) {
      throw StateError('A record can only be tombstoned once.');
    }
    final normalizedDeletedAt = deletedAt.toUtc();
    if (!normalizedDeletedAt.isAfter(updatedAt)) {
      throw ArgumentError.value(
        deletedAt,
        'deletedAt',
        'A tombstone timestamp must be later than the current update.',
      );
    }
    return RecordMetadata._(
      recordId: recordId,
      businessId: businessId,
      originDeviceId: originDeviceId,
      createdAt: createdAt,
      updatedAt: normalizedDeletedAt,
      revision: revision + 1,
      deletedAt: normalizedDeletedAt,
    );
  }
}
