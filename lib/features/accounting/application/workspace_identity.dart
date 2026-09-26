import 'package:audyt/core/ids/entity_id.dart';

final class WorkspaceIdentity {
  const WorkspaceIdentity({
    required this.businessId,
    required this.deviceId,
    required this.ownerId,
    required this.currency,
  });
  final EntityId businessId;
  final EntityId deviceId;
  final EntityId ownerId;
  final String currency;
}
