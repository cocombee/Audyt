import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/accounting_icons.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
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
}) => AccountingDialog.showFixed<void>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  builder: (_) => PaymentTermsDirectoryDialog(
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

DesignForm _termForm(Map<String, Object?> values) => DesignForm(
  'New Term',
  [
    const DesignField('Name', required: true),
    const DesignField(
      'Due Rule',
      required: true,
      choiceLabels: {'fixed': 'Days After Issue', 'monthly': 'Day Of Month'},
    ),
    if (values['Due Rule'] == 'monthly') ...[
      const DesignField('Monthly Due Day', required: true),
      const DesignField('Rollover Within Days', required: true),
    ] else
      const DesignField('Due In Days', required: true),
  ],
  description: 'Term setup preview. Saving terms is not connected yet.',
  actionLabel: 'Save Term',
);

List<(String, String)> _reviewTerm(Map<String, Object?> values) {
  int wholeNumber(String label) {
    final text = '${values[label] ?? ''}'.trim();
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      throw FormatException('$label must be a whole number.');
    }
    return int.parse(text);
  }

  final name = '${values['Name'] ?? ''}'.trim();
  if (name.isEmpty) throw const FormatException('Enter a term name.');
  final rule = values['Due Rule'];
  if (rule == 'fixed') {
    final days = wholeNumber('Due In Days');
    return [
      ('Name', name),
      ('Due Rule', rule == 'fixed' ? 'Days After Issue' : 'Day Of Month'),
      ('Due In Days', '$days'),
    ];
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
  return [
    ('Name', name),
    ('Due Rule', rule == 'fixed' ? 'Days After Issue' : 'Day Of Month'),
    ('Monthly Due Day', '$day'),
    ('Rollover Within Days', '$rollover'),
  ];
}

/// Shares the accepted setup form, conditional ordinary fields and draft warning.
/// Review never returns a saved master or changes a counterparty's terms.
Future<void> showAccountingTermPreview(BuildContext context) =>
    AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      builder: (_) => FrontendFormDialog(
        contentWidth: AccountingPopoutTokens.normalContentWidth,
        form: _termForm(const {'Due Rule': 'fixed'}),
        initial: const {
          'Name': '',
          'Due Rule': 'fixed',
          'Due In Days': '',
          'Monthly Due Day': '',
          'Rollover Within Days': '0',
        },
        valuesFormBuilder: _termForm,
        previewConfirmationEnabled: false,
        reviewInformationRowsBuilder: _reviewTerm,
        leadingContentBuilder: (context, values, reviewing) => Padding(
          padding: const EdgeInsets.only(bottom: accountingContentInset),
          child: accountingHelperText(
            context,
            'Saving terms is not connected yet.',
          ),
        ),
      ),
    );

/// Opt in only at reference-proven creation callers. A preview is never a
/// selected term, and closing it leaves the parent's existing facts untouched.
List<AccountingSelectorOption<String>> accountingTermSetupActions(
  BuildContext context,
) => [
  AccountingSelectorOption(
    value: '__add_term__',
    label: 'Add Term',
    leading: const AccountingAddIcon(),
    leadingWidth: AccountingDismissIcon.canvasSize,
    onPressed: () => showAccountingTermPreview(context),
  ),
];

/// The existing Settings master-list pattern. Unwired reports stay unavailable;
/// their unseen fields and commands are not fabricated from another report.
class PaymentTermsDirectoryDialog extends StatefulWidget {
  const PaymentTermsDirectoryDialog({super.key, this.entries = const []});
  final List<PaymentTermDirectoryPreviewEntry> entries;

  @override
  State<PaymentTermsDirectoryDialog> createState() =>
      _PaymentTermsDirectoryDialogState();
}

class _PaymentTermsDirectoryDialogState
    extends State<PaymentTermsDirectoryDialog> {
  bool _includeInactive = false;
  String _query = '';

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
              onPressed: () => showAccountingTermPreview(context),
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
    final entries = widget.entries
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
      description: 'Design preview · Terms are not saved. Existing due dates and defaults are unchanged.',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const SizedBox(height: accountingContentInset),
          if (widget.entries.isNotEmpty) ...[
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
              widget.entries.isEmpty
                  ? 'The maintained terms list is not connected yet.'
                  : 'No matching terms in this preview.',
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
