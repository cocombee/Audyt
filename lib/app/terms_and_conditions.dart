import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';

/// Review copy, not a published agreement. Registration is enabled only after
/// the operator has supplied a reviewed version in client/server configuration.
const audytTermsDraft = <(String, String)>[
  (
    'Licence And Use',
    'Audyt is licensed software for managing permitted business records. Keep access credentials private. Do not copy, resell, reverse engineer where prohibited by law, interfere with the service, or use it unlawfully. Ownership of the software remains with its rights holders.',
  ),
  (
    'Your Business And Records',
    'You retain ownership of your business data and documents. You are responsible for accurate entries, authorised access, supporting evidence, appropriate backups and any statutory retention duties. Originals and document destinations remain under your configured local or connected storage.',
  ),
  (
    'Accounting And Tax Decisions',
    'Audyt assists record keeping. It does not replace professional accounting, tax or legal advice and does not guarantee certification, compliance or acceptance by an authority. Review calculations, deadlines and submissions against the rules that apply to your business.',
  ),
  (
    'Account Security',
    'Use strong unique passwords, protect your email account and review unexpected login alerts. Access to a business depends on its permissions, not merely signing in. Report suspected compromise promptly. Recovery verifies identity and does not restore revoked business permissions.',
  ),
  (
    'Email And Third Parties',
    'Google, hosting, email and connected-storage providers have their own terms and availability. Mail can be delayed, filtered or rejected. Server acceptance of a message does not guarantee receipt. Confirm recipients and attachments before sending business records.',
  ),
  (
    'Backups And Availability',
    'Keep recoverable independent backups of records and document files. Data exports may not include original documents. Test recovery before relying on it. Service maintenance and connectivity failures can affect online features; a failed operation must not be treated as completed.',
  ),
  (
    'Privacy And Confidentiality',
    'The published Privacy Notice must explain the operator, information collected, purposes, recipients, retention, rights and contact details. Security messages must not contain financial documents or passwords. Do not submit another person’s data without lawful authority.',
  ),
  (
    'Changes And Ending Use',
    'Published terms must explain notice of material changes, support, suspension, termination and available export/recovery periods. Ending a session does not delete business records. Cancellation, archival and deletion are separate actions with their own permissions.',
  ),
  (
    'Warranties And Liability',
    'Any warranty exclusions, liability limits and indemnities must be proportionate, clear and subject to applicable law. Nothing should exclude rights or duties that cannot legally be excluded. Final commercial limits, governing law and dispute process require the operator’s legal review.',
  ),
  (
    'Publication Details',
    'The legal operator, contact, effective date, version, pricing terms and retention policy must be confirmed before this draft becomes a registration agreement. This review copy is not recorded as accepted terms.',
  ),
];
Future<void> showTermsAndConditions(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.custom,
    title: 'Terms & Conditions',
    description:
        'Review draft — publication details and legal review are pending.',
    contentInset: 20,
    maxContentWidth: AccountingPopoutTokens.widerContentWidth,
    content: SizedBox(
      width: AccountingPopoutTokens.widerContentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in audytTermsDraft) ...[
            Text(section.$1, style: AccountingTypography.fieldLabel(context)),
            const SizedBox(height: 8),
            SelectableText(
              section.$2,
              style: AccountingTypography.helper(context),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    ),
    actions: [
      AccountingButton.outline(
        context,
        key: const ValueKey('terms-close'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
