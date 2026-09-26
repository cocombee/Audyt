import 'package:flutter/material.dart';

import '../features/accounting/application/workspace_backup.dart';
import 'accounting_components.dart';

class WorkspaceBackupControls extends StatefulWidget {
  const WorkspaceBackupControls({
    super.key,
    required this.backup,
    required this.onOpenRestored,
  });
  final WorkspaceBackup backup;
  final Future<void> Function(String) onOpenRestored;
  @override
  State<WorkspaceBackupControls> createState() =>
      _WorkspaceBackupControlsState();
}

class _WorkspaceBackupControlsState extends State<WorkspaceBackupControls> {
  String? _folder, _message;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.backup.info();
      if (mounted) {
        setState(() {
          _folder = info['folder'] as String?;
          if (info['lastFailure'] != null) {
            _message = 'Last scheduled backup failed: ${info['lastFailure']}';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not load backup destination: $error');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not complete: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 20),
      accountingFieldLabel(context, 'Backup Destination', alignToField: true),
      const SizedBox(height: 8),
      AccountingButton.outline(
        context,
        key: const ValueKey('backup-destination'),
        leadingIcon: Icons.folder_open_outlined,
        onPressed: _busy
            ? null
            : () => _run(() async {
                final folder = await widget.backup.chooseFolder();
                if (folder != null && mounted) setState(() => _folder = folder);
              }),
        child: Text(
          _folder ?? 'Choose Folder',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(height: 20),
      accountingHelperText(
        context,
        'Scheduled backups run while Audyt is open and catch up next launch. Data archives retain accounting records and file references; original documents remain in their folders. CSV exports posted ledger rows; JSON imports create a separate copy that you can reopen from the company selector. Each restored copy needs its own backup destination.',
      ),
      if (_message != null) ...[
        const SizedBox(height: 20),
        Text(_message!, style: AccountingTypography.helper(context)),
      ],
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            AccountingButton.outline(
              context,
              key: const ValueKey('import-data'),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final path = await widget.backup.import();
                      if (path != null && context.mounted) {
                        Navigator.pop(context);
                        await widget.onOpenRestored(path);
                      }
                    }),
              child: const Text('Import Data'),
            ),
            AccountingButton.outline(
              context,
              key: const ValueKey('export-data'),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final path = await widget.backup.export();
                      if (path != null && mounted) {
                        setState(() => _message = 'Exported to $path');
                      }
                    }),
              child: const Text('Export Data'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('backup-now'),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final path = await widget.backup.backup();
                      if (path != null && mounted) {
                        setState(() => _message = 'Backup verified at $path');
                      }
                    }),
              child: Text(_busy ? 'Working…' : 'Back Up Now'),
            ),
          ],
        ),
      ),
    ],
  );
}
