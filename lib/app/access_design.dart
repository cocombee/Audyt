import 'package:flutter/material.dart';

import 'accounting_components.dart';

/// Isolated design walkthrough. It never authenticates or changes real access.
class AccessDesignPanel extends StatefulWidget {
  const AccessDesignPanel({super.key});
  @override
  State<AccessDesignPanel> createState() => _AccessDesignPanelState();
}

class _AccessDesignPanelState extends State<AccessDesignPanel> {
  String _stage = 'Signed Out';
  String _role = 'Owner';
  final _stages = const [
    'Signed Out',
    'Waiting For Google',
    'Choose Business',
    'Signed In',
    'No Access',
    'Session Expired',
    'Offline',
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingHelperText(
        context,
        'Design walkthrough · No Google account is connected and no access is changed.',
      ),
      const SizedBox(height: 16),
      accountingFieldLabel(context, 'Preview State'),
      const SizedBox(height: 8),
      AccountingSelector<String>(
        triggerKey: const ValueKey('access-preview-state'),
        value: _stage,
        hintText: 'Select State',
        options: [
          for (final stage in _stages)
            AccountingSelectorOption(value: stage, label: stage),
        ],
        onChanged: (value) => setState(() => _stage = value ?? _stage),
      ),
      const SizedBox(height: 20),
      AccountingCard.surface(
        context,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (_stage) {
                'Signed Out' => 'Sign In To Audyt',
                'Waiting For Google' => 'Continue In Your Browser',
                'Choose Business' => 'Choose Your Business',
                'Signed In' => 'Your Session',
                'No Access' => 'Business Access Required',
                'Session Expired' => 'Sign In Again',
                _ => 'You Are Offline',
              }, style: AccountingTypography.sectionTitle(context)),
              const SizedBox(height: 6),
              if (_stage == 'Signed In')
                AccountingInformationRows(
                  rows: [
                    ('User', 'Preview User'),
                    ('Email', 'preview@example.com'),
                    ('Business', 'Example Business'),
                    ('Role', _role),
                    ('Device', 'This Mac'),
                    ('Session', 'Current Session (Preview)'),
                  ],
                )
              else
                Text(switch (_stage) {
                  'Signed Out' => 'Use your Google account. Your business owner assigns your accounting role.',
                  'Waiting For Google' => 'Complete Google sign-in in your browser, then return to Audyt. This preview does not open Google.',
                  'Choose Business' => 'Only businesses that have granted you access will appear here.',
                  'No Access' => 'Ask the business owner to invite the Google email address you signed in with.',
                  'Session Expired' => 'Your session needs to be renewed before you can continue shared work.',
                  _ => 'Previously authorised local work follows the saved offline policy. Shared approvals and access changes need a connection.',
                }),
              const SizedBox(height: 16),
              if (_stage == 'Choose Business') ...[
                ListTile(
                  key: const ValueKey('access-example-business'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: const Text('Example Business'),
                  subtitle: Text('Design Example · $_role'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => setState(() => _stage = 'Signed In'),
                ),
              ] else
                AccountingButton.outline(
                  context,
                  key: const ValueKey('access-next'),
                  onPressed: () => setState(
                    () => _stage = switch (_stage) {
                      'Signed Out' || 'Session Expired' => 'Waiting For Google',
                      'Waiting For Google' => 'Choose Business',
                      _ => 'Signed Out',
                    },
                  ),
                  child: Text(switch (_stage) {
                    'Signed Out' ||
                    'Session Expired' => 'Preview Google Sign-In',
                    'Waiting For Google' => 'Preview Successful Sign-In',
                    'Signed In' => 'Sign Out Of Preview',
                    _ => 'Back To Sign-In',
                  }),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      accountingFieldLabel(context, 'Preview Role'),
      const SizedBox(height: 8),
      AccountingSelector<String>(
        triggerKey: const ValueKey('access-preview-role'),
        value: _role,
        hintText: 'Select Role',
        options: [
          for (final role in roleDescriptions.keys)
            AccountingSelectorOption(value: role, label: role),
        ],
        onChanged: (value) => setState(() => _role = value ?? _role),
      ),
      const SizedBox(height: 8),
      Text(roleDescriptions[_role]!),
      const SizedBox(height: 8),
      accountingHelperText(
        context,
        'This selector demonstrates roles. In the connected app, members cannot choose or elevate their own role.',
      ),
    ],
  );
}

const roleDescriptions = <String, String>{
  'Owner': 'Manage the business, members, settings and accounting approvals. Ownership transfer requires a separate confirmation.',
  'Accountant': 'Review accounts, propose adjustments and prepare reports. Posting and exports follow permissions granted by the owner.',
  'Bookkeeper': 'Prepare transactions and attach documents. Approval and changes to closed periods require an authorised reviewer.',
  'Read Only': 'View permitted records and reports. No transaction edits or approvals; export requires a separate permission.',
};
