import 'dart:async';
import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scheduled backup reports a missing destination for saved Daily choice',
    () async {
      final root = Directory.systemTemp.createTempSync('audyt-backup-missing-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${root.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      workspace.savePreferences(
        workspace.preferences.change('Backup & Export Preferences', {
          'Backup Frequency': 'Daily',
        }),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final failures = <String>[];
      String? lastSuccess;
      messenger.setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
        if (call.method == 'info') {
          return <String, Object?>{'lastSuccess': lastSuccess};
        }
        if (call.method == 'recordFailure') {
          failures.add((call.arguments as Map)['message'] as String);
          return null;
        }
        fail('Unexpected native backup call: ${call.method}');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(WorkspaceBackup.channel, null),
      );

      final backup = WorkspaceBackup(workspace);
      await expectLater(backup.backup(scheduled: true), throwsStateError);
      expect(failures.single, contains('backup destination'));
      expect(failures.single, isNot(contains('Bad state:')));
      lastSuccess = DateTime.now().toUtc().toIso8601String();
      expect(await backup.backup(scheduled: true), isNull);
      expect(failures, hasLength(1));
      await expectLater(backup.backup(), throwsStateError);
      expect(failures, hasLength(1));
      workspace.savePreferences(
        workspace.preferences.change('Backup & Export Preferences', {
          'Backup Frequency': 'Manual',
        }),
      );
      expect(await backup.backup(scheduled: true), isNull);
      expect(failures, hasLength(1));
    },
  );

  test('saved Daily schedule catches up on start and avoids a second same-day backup', () async {
    final root = Directory.systemTemp.createTempSync('audyt-backup-catchup-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    workspace.savePreferences(
      workspace.preferences.change('Backup & Export Preferences', {
        'Backup Frequency': 'Daily',
        'Export Format': 'CSV',
      }),
    );
    final businessId = workspace.identity.businessId.value;
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(
      workspace.preferences.text(
        'Backup & Export Preferences',
        'Backup Frequency',
      ),
      'Daily',
    );

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final writes = <Map<String, Object?>>[];
    final wrote = Completer<void>();
    String? lastSuccess;
    messenger.setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
      if (call.method == 'info') {
        return {'folder': '${root.path}/backups', 'lastSuccess': lastSuccess};
      }
      if (call.method == 'write') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        writes.add(args);
        lastSuccess = args['createdAt'] as String;
        if (!wrote.isCompleted) wrote.complete();
        return '${root.path}/backups/saved.audyt.json';
      }
      fail('Unexpected native backup call: ${call.method}');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(WorkspaceBackup.channel, null),
    );

    final backup = WorkspaceBackup(workspace)..start();
    addTearDown(backup.dispose);
    await wrote.future.timeout(const Duration(seconds: 5));
    expect(writes, hasLength(1));
    expect(writes.single['businessId'], businessId);
    expect(writes.single['extension'], 'audyt.json');
    expect(writes.single['backup'], true);
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      writes.single['data'] as String,
    );
    addTearDown(restored.dispose);
    expect(
      restored.preferences.text(
        'Backup & Export Preferences',
        'Backup Frequency',
      ),
      'Daily',
    );
    expect(
      restored.preferences.text('Backup & Export Preferences', 'Export Format'),
      'CSV',
    );
    expect(await backup.backup(scheduled: true), isNull);
    expect(writes, hasLength(1));
  });
}
