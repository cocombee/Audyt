import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/accounting_icons.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
import '../../../core/ids/entity_id.dart';
import '../application/accounting_workspace.dart';
import '../domain/company_payment_term.dart';
import '../domain/payment_terms.dart';

/// Geometry fixtures only. Names never determine contractual timing or defaults.
class PaymentTermDirectoryPreviewEntry {
  const PaymentTermDirectoryPreviewEntry({
    required this.id,
    required this.name,
    required this.terms,
    this.active = true,
  });
  final String id, name;
  final PaymentTerms terms;
  final bool active;
}

Future<void> showPaymentTermsDirectoryPreview(
  BuildContext context, {
  bool demo = false,
  AccountingWorkspace? workspace,
}) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => PaymentTermsDirectoryDialog(
    workspace: demo ? null : workspace,
    entries: demo
        ? [
            PaymentTermDirectoryPreviewEntry(
              id: 'demo-receipt',
              name: 'Due On Receipt',
              terms: PaymentTerms.netDays(0),
            ),
            for (final days in [15, 30, 60, 90])
              PaymentTermDirectoryPreviewEntry(
                id: 'demo-net-$days',
                name: 'Net $days',
                terms: PaymentTerms.netDays(days),
              ),
          ]
        : const [],
  ),
);

DesignForm _termForm(Map<String, Object?> values, {required bool preview}) =>
    DesignForm(
      'New Term',
      [
        const DesignField('Name', required: true),
        const DesignField(
          'Due Rule',
          required: true,
          choiceLabels: {
            'fixed': 'Days After Issue',
            'monthly': 'Day Of Month',
          },
        ),
        if (values['Due Rule'] == 'monthly') ...[
          const DesignField('Monthly Due Day', required: true),
          const DesignField('Rollover Within Days', required: true),
        ] else
          const DesignField('Due In Days', required: true),
      ],
      description: preview
          ? 'Term setup preview. Saving terms is not connected yet.'
          : 'Set up a named payment term for this company.',
      actionLabel: 'Save Term',
    );

({String name, PaymentTerms rule}) _validatedTerm(Map<String, Object?> values) {
  int wholeNumber(String label) {
    final text = '${values[label] ?? ''}'.trim();
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      throw FormatException('$label must be a whole number.');
    }
    return int.parse(text);
  }

  final name = '${values['Name'] ?? ''}'.trim();
  if (name.isEmpty) throw const FormatException('Enter a term name.');
  if (name.length > 200) {
    throw const FormatException('Term name must be 200 characters or fewer.');
  }
  final rule = values['Due Rule'];
  if (rule == 'fixed') {
    final days = wholeNumber('Due In Days');
    return (name: name, rule: PaymentTerms.daysAfterIssue(days));
  }
  if (rule != 'monthly') {
    throw const FormatException('Choose a due rule.');
  }
  final day = wholeNumber('Monthly Due Day');
  final rollover = wholeNumber('Rollover Within Days');
  if (day < 1 || day > 31) {
    throw const FormatException('Day Of Month must be between 1 and 31.');
  }
  if (rollover > 31) {
    throw const FormatException(
      'Rollover Within Days must be between 0 and 31.',
    );
  }
  return (
    name: name,
    rule: PaymentTerms.dayOfMonth(day, rolloverWithinDays: rollover),
  );
}

List<(String, String)> _reviewTerm(Map<String, Object?> values) {
  final term = _validatedTerm(values);
  return [
    ('Name', term.name),
    ('Due Rule', term.rule.formChoice),
    if (term.rule.kind == PaymentTermKind.daysAfterIssue)
      ('Due In Days', '${term.rule.days}')
    else ...[
      ('Monthly Due Day', '${term.rule.dayOfMonth}'),
      ('Rollover Within Days', '${term.rule.rolloverWithinDays}'),
    ],
  ];
}

/// Shares the accepted setup form, conditional ordinary fields and draft warning.
/// Creating a term never selects it on a parent transaction.
Future<void> showAccountingTermPreview(
  BuildContext context, {
  AccountingWorkspace? workspace,
}) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => FrontendFormDialog(
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    form: _termForm(const {'Due Rule': 'fixed'}, preview: workspace == null),
    initial: const {
      'Name': '',
      'Due Rule': 'fixed',
      'Due In Days': '',
      'Monthly Due Day': '',
      'Rollover Within Days': '0',
    },
    valuesFormBuilder: (values) =>
        _termForm(values, preview: workspace == null),
    previewConfirmationEnabled: false,
    reviewInformationRowsBuilder: _reviewTerm,
    onCommit: workspace == null
        ? null
        : (values) async {
            final term = _validatedTerm(values);
            workspace.createPaymentTerm(
              CompanyPaymentTerm(
                id: EntityId.random(),
                name: term.name,
                rule: term.rule,
                active: true,
                revision: 0,
              ),
            );
          },
    leadingContentBuilder: workspace == null
        ? (context, values, reviewing) => Padding(
            padding: const EdgeInsets.only(bottom: accountingContentInset),
            child: accountingHelperText(
              context,
              'Saving terms is not connected yet.',
            ),
          )
        : null,
  ),
);

/// Opt in only at reference-proven creation callers. Inline creation does not
/// select a transaction value; the caller may refresh choices after return.
List<AccountingSelectorOption<String>> accountingTermSetupActions(
  BuildContext context, {
  AccountingWorkspace? workspace,
  VoidCallback? onReturn,
}) => [
  AccountingSelectorOption(
    value: '__add_term__',
    label: 'Add Term',
    leading: const AccountingAddIcon(),
    leadingWidth: AccountingDismissIcon.canvasSize,
    onPressed: () async {
      await showAccountingTermPreview(context, workspace: workspace);
      onReturn?.call();
    },
  ),
];

/// The existing Settings master-list pattern. Unwired reports stay unavailable;
/// their unseen fields and commands are not fabricated from another report.
class PaymentTermsDirectoryDialog extends StatefulWidget {
  const PaymentTermsDirectoryDialog({
    super.key,
    this.entries = const [],
    this.workspace,
  });
  final List<PaymentTermDirectoryPreviewEntry> entries;
  final AccountingWorkspace? workspace;

  @override
  State<PaymentTermsDirectoryDialog> createState() =>
      _PaymentTermsDirectoryDialogState();
}

class _PaymentTermsDirectoryDialogState
    extends State<PaymentTermsDirectoryDialog> {
  bool _includeInactive = false;
  String _query = '';

  List<PaymentTermDirectoryPreviewEntry> get _entries =>
      widget.workspace == null
      ? widget.entries
      : [
          for (final term in widget.workspace!.paymentTerms)
            PaymentTermDirectoryPreviewEntry(
              id: term.id.value,
              name: term.name,
              terms: term.rule,
              active: term.active,
            ),
        ];

  Widget _toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final style = AccountingTypography.value(context);
      final buttonStyle = AccountingTypography.button(context)
          .copyWith(fontSize: accountingControlFontSize);
      final checkboxWidth =
          18 +
          accountingContentInset +
          AccountingResponsive.measuredTextWidth(
            context,
            'Include Inactive',
            style,
          );
      final actionsWidth =
          5 * accountingContentInset +
          AccountingResponsive.measuredTextWidth(
            context,
            'Run Report',
            buttonStyle,
          ) +
          AccountingResponsive.measuredTextWidth(
            context,
            'New Term',
            buttonStyle,
          );
      final checkbox = SizedBox(
        width: checkboxWidth,
        child: Row(
          children: [
            AccountingLeadingCheckbox(
              checkboxKey: const ValueKey('terms-include-inactive'),
              undividedRow: true,
              semanticLabel: 'Include Inactive',
              value: _includeInactive,
              onChanged: (value) => setState(() {
                _includeInactive = value ?? false;
              }),
            ),
            Text('Include Inactive', style: style),
          ],
        ),
      );
      final actions = AccountingButtonGroup(
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: accountingContentInset,
          runSpacing: accountingContentInset,
          children: [
            Tooltip(
              message: 'The terms report is not connected yet.',
              child: AccountingButton.outline(
                context,
                key: const ValueKey('terms-run-report'),
                onPressed: null,
                child: const Text('Run Report'),
              ),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('terms-new'),
              onPressed: () => showAccountingTermPreview(
                context,
                workspace: widget.workspace,
              ),
              child: const Text('New Term'),
            ),
          ],
        ),
      );
      if (checkboxWidth + accountingContentInset + actionsWidth <=
          constraints.maxWidth) {
        return Row(children: [checkbox, const Spacer(), actions]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: checkbox),
          const SizedBox(height: accountingContentInset),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.workspace != null) {
      return ListenableBuilder(
        listenable: widget.workspace!,
        builder: (context, _) => _buildDirectory(context),
      );
    }
    return _buildDirectory(context);
  }

  Widget _buildDirectory(BuildContext context) {
    final source = _entries;
    final entries = source
        .where(
          (entry) =>
              (_includeInactive || entry.active) &&
              entry.name.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: 'Terms',
      description: widget.workspace == null
          ? 'Design preview · Terms are not saved. Existing due dates and defaults are unchanged.'
          : 'Manage named payment terms for this company.',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const SizedBox(height: accountingContentInset),
          if (source.isNotEmpty) ...[
            TextField(
              key: const ValueKey('terms-search'),
              style: AccountingTypography.controlValue(context),
              decoration: accountingSingleLineInputDecoration(
                context,
                hintText: 'Search Terms',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: accountingContentInset),
          ],
          if (entries.isEmpty)
            accountingHelperText(
              context,
              source.isEmpty
                  ? widget.workspace == null
                        ? 'The maintained terms list is not connected yet.'
                        : 'No terms have been saved yet.'
                  : widget.workspace == null
                  ? 'No matching terms in this preview.'
                  : 'No matching terms.',
            )
          else
            AccountingRecordList(
              paginationKey: 'terms-directory',
              totalCount: entries.length,
              children: [
                for (final entry in entries)
                  AccountingRecordRow(
                    key: ValueKey('terms-row-${entry.id}'),
                    title: entry.name,
                    details: const SizedBox.shrink(),
                    trailing: AccountingRecordActions(
                      trailing: [
                        Tooltip(
                          message: 'The terms report is not connected yet.',
                          child: AccountingButton.outline(
                            context,
                            key: ValueKey('terms-report-${entry.id}'),
                            onPressed: null,
                            child: const Text('Run Report'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      actions: [],
    );
  }
}
