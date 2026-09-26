import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/domain/account.dart';

final class StoredAccount {
  const StoredAccount({required this.account, required this.metadata});
  final Account account;
  final RecordMetadata metadata;
}

abstract interface class AccountRepository {
  Future<StoredAccount?> getAccount(EntityId id);
  Future<List<StoredAccount>> listAccounts(EntityId businessId);
  Future<void> saveAccount(StoredAccount record);
}
