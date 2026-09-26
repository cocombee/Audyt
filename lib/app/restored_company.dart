import 'package:flutter/material.dart';

import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/application/restored_workspaces.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'app.dart';
import 'routing.dart';

class RestoredCompany extends InheritedWidget {
  const RestoredCompany({super.key, required this.entry, required super.child});
  final RestoredWorkspaceEntry entry;
  static RestoredWorkspaceEntry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RestoredCompany>()?.entry;
  @override
  bool updateShouldNotify(RestoredCompany oldWidget) =>
      entry != oldWidget.entry;
}

/// Owns the reopened database until this route closes, including failed opens
/// and an asynchronous open that completes after the user has already returned.
class RestoredCompanyPage extends StatefulWidget {
  const RestoredCompanyPage({super.key, required this.path});
  final String path;
  @override
  State<RestoredCompanyPage> createState() => _RestoredCompanyPageState();
}

class _RestoredCompanyPageState extends State<RestoredCompanyPage> {
  AccountingWorkspace? _workspace;
  RestoredWorkspaceEntry? _entry;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _failed = false);
    try {
      final entry = await const RestoredWorkspaces().lookup(widget.path);
      final workspace = await AccountingWorkspace.openExisting(
        entry.path,
        businessId: entry.businessId,
        restoredCopyId: entry.id,
      );
      if (!mounted) {
        workspace.dispose();
        return;
      }
      setState(() {
        _entry = entry;
        _workspace = workspace;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _workspace?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    if (workspace != null) {
      return RestoredCompany(
        entry: _entry!,
        child: AccountingShell(
          initialRoute: AccountingRouting.forFeature('home')!,
          workspace: workspace,
          accountCurrencyCode: workspace.identity.currency,
          showInitialSetup: false,
        ),
      );
    }
    return Scaffold(
      backgroundColor: AccountingTheme.of(context).background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AccountingCard.surface(
              context,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _failed
                          ? 'Restored Company Could Not Be Opened'
                          : 'Opening Restored Company…',
                      style: AccountingTypography.sectionTitle(context),
                    ),
                    const SizedBox(height: 20),
                    if (_failed)
                      accountingHelperText(
                        context,
                        'The saved copy is unavailable or needs recovery. An empty company has not been created. Your original company remains separate.',
                      ),
                    if (!_failed) const LinearProgressIndicator(),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 20,
                      runSpacing: 10,
                      children: [
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('return-from-restored'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Return'),
                        ),
                        if (_failed)
                          AccountingButton.primary(
                            context,
                            key: const ValueKey('retry-restored'),
                            onPressed: _open,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
