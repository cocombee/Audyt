import 'package:flutter/material.dart';

import '../features/accounting/application/accounting_workspace.dart';
import 'app.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'google_account_session.dart';
import 'authentication_page.dart';

class WorkspaceBootstrap extends StatefulWidget {
  const WorkspaceBootstrap({super.key, this.openWorkspace});
  final Future<AccountingWorkspace> Function()? openWorkspace;
  @override
  State<WorkspaceBootstrap> createState() => _WorkspaceBootstrapState();
}

class _WorkspaceBootstrapState extends State<WorkspaceBootstrap> {
  AccountingWorkspace? _workspace;
  Object? _error;
  @override
  void initState() {
    super.initState();
    GoogleAccountSession.shared.initialize();
    _open();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final workspace =
          await (widget.openWorkspace ?? AccountingWorkspace.openDefault)();
      if (!mounted) {
        workspace.dispose();
        return;
      }
      setState(() => _workspace = workspace);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _workspace?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_workspace != null) {
      final app = AudytApp(
        showInitialSetup: true,
        startInDemoCompany: true,
        workspace: _workspace,
        accountCurrencyCode: _workspace!.identity.currency,
      );
      final session = GoogleAccountSession.shared;
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) => session.supported && !session.signedIn
            ? MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: AudytSignInPage(session: session),
              )
            : app,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AccountingTheme.light(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error == null) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text('Opening Accounting Workspace…'),
                    ] else ...[
                      Text(
                        'Accounting Data Could Not Be Opened',
                        style: AccountingTypography.sectionTitle(context),
                      ),
                      const SizedBox(height: 6),
                      accountingHelperText(
                        context,
                        'Your saved data has not been replaced. Retry after checking local storage access.',
                      ),
                      const SizedBox(height: 16),
                      AccountingButton.outline(
                        context,
                        key: const ValueKey('retry-workspace'),
                        onPressed: _open,
                        child: const Text('Retry'),
                      ),
                    ],
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
