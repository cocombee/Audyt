import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores persisted revision metadata without inventing timestamps', () {
    final metadata = RecordMetadata.restore(
      recordId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a64'),
      businessId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a65'),
      originDeviceId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a66'),
      createdAt: DateTime.utc(2026, 8, 30, 1),
      updatedAt: DateTime.utc(2026, 8, 30, 3),
      revision: 3,
      deletedAt: DateTime.utc(2026, 8, 30, 3),
    );

    expect(metadata.revision, 3);
    expect(metadata.updatedAt, DateTime.utc(2026, 8, 30, 3));
    expect(metadata.deletedAt, DateTime.utc(2026, 8, 30, 3));
    expect(metadata.isTombstone, isTrue);
  });

  test('advances revisions and preserves identity through a tombstone', () {
    final recordId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a61');
    final businessId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a62');
    final deviceId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a63');
    final createdAt = DateTime.utc(2026, 8, 30, 1);

    final initial = RecordMetadata.initial(
      recordId: recordId,
      businessId: businessId,
      originDeviceId: deviceId,
      createdAt: createdAt,
    );
    final updated = initial.nextRevision(
      updatedAt: DateTime.utc(2026, 8, 30, 2),
    );
    final tombstone = updated.delete(deletedAt: DateTime.utc(2026, 8, 30, 3));

    expect(initial.revision, 1);
    expect(updated.revision, 2);
    expect(tombstone.revision, 3);
    expect(tombstone.recordId, recordId);
    expect(tombstone.businessId, businessId);
    expect(tombstone.originDeviceId, deviceId);
    expect(tombstone.isTombstone, isTrue);
    expect(tombstone.createdAt, createdAt);
  });
}
