import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';

EntityId id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native storage location is used and persisted identity is stable',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-native-path-');
      addTearDown(() => dir.deleteSync(recursive: true));
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AccountingWorkspace.storageChannel, (
            call,
          ) async {
            expect(call.method, 'databasePath');
            calls++;
            return '${dir.path}/ledger.sqlite';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AccountingWorkspace.storageChannel, null),
      );
      var workspace = await AccountingWorkspace.openDefault();
      final identity = workspace.identity;
      workspace.dispose();
      workspace = await AccountingWorkspace.openDefault();
      addTearDown(workspace.dispose);
      expect(calls, 2);
      expect(workspace.identity.businessId, identity.businessId);
      expect(workspace.identity.deviceId, identity.deviceId);
      expect(workspace.identity.ownerId, identity.ownerId);
      expect(workspace.identity.currency, 'MYR');
    },
  );
  test(
    'existing single-business policy is adopted without a new hidden business',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'audyt-existing-business-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      final db = LocalAccountingDatabase.open(path);
      await db.configureLedger(businessId: id(1), currencyCode: 'USD');
      db.close();
      final workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(workspace.identity.businessId, id(1));
      expect(workspace.identity.currency, 'USD');
    },
  );
  test('ambiguous existing businesses do not get silently replaced', () async {
    final dir = Directory.systemTemp.createTempSync(
      'audyt-ambiguous-business-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    final db = LocalAccountingDatabase.open(path);
    await db.configureLedger(businessId: id(1), currencyCode: 'MYR');
    await db.configureLedger(businessId: id(2), currencyCode: 'USD');
    db.close();
    await expectLater(AccountingWorkspace.open(path), throwsStateError);
    final reopened = LocalAccountingDatabase.open(path);
    addTearDown(reopened.close);
    await reopened.configureLedger(businessId: id(1), currencyCode: 'MYR');
    await reopened.configureLedger(businessId: id(2), currencyCode: 'USD');
  });
  test(
    'missing native storage adapter is a failure, not an in-memory fallback',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AccountingWorkspace.storageChannel,
            (call) async => throw PlatformException(code: 'unavailable'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AccountingWorkspace.storageChannel, null),
      );
      await expectLater(
        AccountingWorkspace.openDefault(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
