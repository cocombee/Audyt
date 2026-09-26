import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'accounting_workspace.dart';
import 'restored_workspaces.dart';

/// Device grants and successful backup times belong to the native adapter.
/// This scheduler runs while Audyt is open and catches up at next launch.
final class WorkspaceBackup {
  WorkspaceBackup(this.workspace);
  static const channel = MethodChannel('audyt/workspace-backup');
  final AccountingWorkspace workspace;
  Timer? _timer;
  bool _busy = false;
  String get businessId => workspace.identity.businessId.value;
  Map<String, Object?> get _identityArguments => {
    'businessId': businessId,
    if (workspace.restoredCopyId != null)
      'workspaceId': workspace.restoredCopyId,
  };
  Future<Map<String, dynamic>> info() async => Map<String, dynamic>.from(
    await channel.invokeMethod<Map>('info', _identityArguments) ?? {},
  );
  Future<String?> chooseFolder() =>
      channel.invokeMethod<String>('chooseFolder', _identityArguments);
  static bool due(String frequency, DateTime now, DateTime? last) {
    if (frequency == 'Manual') return false;
    if (last == null) return true;
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    return switch (frequency) {
      'Daily' => today.isAfter(day),
      'Weekly' => today.difference(day).inDays >= 7,
      'Monthly' => (now.year * 12 + now.month) > (last.year * 12 + last.month),
      _ => false,
    };
  }

  Future<String?> backup({bool scheduled = false}) async {
    if (_busy) return null;
    _busy = true;
    try {
      final frequency = workspace.preferences.text(
        'Backup & Export Preferences',
        'Backup Frequency',
      );
      if (scheduled && frequency == 'Manual') return null;
      final state = await info();
      final now = DateTime.now();
      if (scheduled &&
          !due(
            frequency,
            now,
            DateTime.tryParse(state['lastSuccess'] as String? ?? '')?.toLocal(),
          )) {
        return null;
      }
      if (state['folder'] == null) {
        throw StateError(
          scheduled
              ? 'Choose a backup destination for scheduled backups.'
              : 'Choose a backup destination first.',
        );
      }
      final data = workspace.database.exportDataArchive(
        workspace.identity.businessId,
        now,
      );
      return await channel.invokeMethod<String>('write', {
        ..._identityArguments,
        'data': data,
        'extension': 'audyt.json',
        'backup': true,
        'createdAt': now.toUtc().toIso8601String(),
      });
    } catch (error) {
      if (scheduled) {
        try {
          await channel.invokeMethod<void>('recordFailure', {
            ..._identityArguments,
            'message': error is StateError ? error.message : '$error',
          });
        } catch (_) {
          /* An unavailable native adapter must not replace the original error. */
        }
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<String?> export() {
    final csv =
        workspace.preferences.text(
          'Backup & Export Preferences',
          'Export Format',
        ) ==
        'CSV';
    final data = csv
        ? workspace.database.exportLedgerCsv(workspace.identity.businessId)
        : workspace.database.exportDataArchive(
            workspace.identity.businessId,
            DateTime.now(),
          );
    return channel.invokeMethod<String>('export', {
      ..._identityArguments,
      'data': data,
      'extension': csv ? 'csv' : 'audyt.json',
    });
  }

  Future<String?> import() async {
    final picked = await channel.invokeMethod<Map>('import', {
      ..._identityArguments,
    });
    if (picked == null) return null;
    final archive = picked['data'] as String;
    // Reject malformed JSON before preparing a copy. Deeper validation runs in
    // the isolated destination and must discard that copy on failure.
    jsonDecode(archive);
    final database = await channel.invokeMethod<String>('newWorkspace', {
      ..._identityArguments,
    });
    if (database == null) {
      throw StateError('The restored workspace location is unavailable.');
    }
    try {
      final restored = await AccountingWorkspace.emptyRestore(
        database,
        archive,
      );
      try {
        await const RestoredWorkspaces().register(database, restored);
      } finally {
        restored.dispose();
      }
      return database;
    } on Object catch (error, stack) {
      try {
        await channel.invokeMethod<void>('discardPreparedWorkspace', {
          ..._identityArguments,
          'path': database,
        });
      } on Object {
        throw StateError(
          'The import failed and its incomplete copy could not be removed. Review recovery storage.',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  void start() {
    _timer?.cancel();
    unawaited(_scheduled());
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_scheduled()),
    );
  }

  Future<void> _scheduled() async {
    try {
      await backup(scheduled: true);
    } on Object {
      /* The native adapter retains failure details for Backup Settings. */
    }
  }

  void dispose() => _timer?.cancel();
}
