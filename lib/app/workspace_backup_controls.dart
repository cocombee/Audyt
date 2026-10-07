import 'package:flutter/material.dart';

import '../features/accounting/application/workspace_backup.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'field_row_trial.dart';

class WorkspaceBackupControls extends StatefulWidget {
  const WorkspaceBackupControls({
    super.key,
    required this.backup,
    required this.onOpenRestored,
    this.preferenceFields,
    this.preferenceFieldsWidth,
    this.leadingContent,
  });
  final WorkspaceBackup backup;
  final List<AccountingOrdinaryFieldSlot>? preferenceFields;
  final double? preferenceFieldsWidth;
  final Widget? leadingContent;
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

  Widget _destination(BuildContext context) => Column(
    key: const ValueKey('backup-destination-slot'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(context, 'Backup Destination', alignToField: true),
      const SizedBox(height: accountingFieldLabelGap),
      Align(
        alignment: Alignment.centerLeft,
        child: AccountingButton.outline(
          context,
          key: const ValueKey('backup-destination'),
          leadingIcon: Icons.folder_open_outlined,
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final folder = await widget.backup.chooseFolder();
                  if (folder != null && mounted) {
                    setState(() => _folder = folder);
                  }
                }),
          child: Text(
            _folder ?? 'Choose Folder',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.leadingContent != null) ...[
        widget.leadingContent!,
        const SizedBox(height: accountingContentInset),
      ],
      if (widget.preferenceFields != null)
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: widget.preferenceFieldsWidth,
            child: AccountingOrdinaryFields(
              fields: [
                ...widget.preferenceFields!,
                AccountingOrdinaryFieldSlot(
                  label: 'Backup Destination',
                  hasGuidance: true,
                  minimumControlWidth: AccountingButton.normalIconLabelWidth(
                    context,
                    _folder ?? 'Choose Folder',
                    icon: Icons.folder_open_outlined,
                  ),
                  builder: (_) => _destination(context),
                ),
              ],
            ),
          ),
        )
      else
        _destination(context),
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
