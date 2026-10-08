import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../core/ids/entity_id.dart';
import '../application/accounting_workspace.dart';
import '../domain/company_tax_agency.dart';

class TaxAgenciesDialog extends StatelessWidget {
  const TaxAgenciesDialog({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  Future<void> edit(BuildContext context, [CompanyTaxAgency? original]) =>
      showDialog<void>(
        context: context,
        builder: (_) => FrontendFormDialog(
          form: DesignForm(
            original == null ? 'Add Tax Agency' : 'Edit Tax Agency',
            [
              const DesignField('Name', required: true),
              const DesignField('Country Code', required: true),
              const DesignField('Registration Number'),
              const DesignField('Notes', multiline: true),
            ],
            description: 'Agency and registration details identify saved tax activity. They do not calculate a statutory return.',
            actionLabel: 'Save',
          ),
          initial: {
            'Name': original?.name ?? '',
            'Country Code': original?.countryCode ?? 'MY',
            'Registration Number': original?.registrationNumber ?? '',
            'Notes': original?.notes ?? '',
          },
          onCommit: (v) async {
            workspace.saveTaxAgency(
              CompanyTaxAgency(
                id: original?.id ?? EntityId.random(),
                name: v['Name'] as String,
                countryCode: v['Country Code'] as String,
                registrationNumber: v['Registration Number'] as String,
                notes: v['Notes'] as String,
                revision: original?.revision ?? 0,
              ),
            );
          },
        ),
      );
  Future<void> view(BuildContext context, CompanyTaxAgency agency) =>
      showDialog<void>(
        context: context,
        builder: (c) => AccountingDialog.alert(
          c,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: agency.name,
          fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
          maxContentWidth: AccountingPopoutTokens.normalContentWidth,
          content: SelectionArea(
            child: AccountingInformationRows(
              rows: [
                ('Registration Number', agency.registrationNumber),
                ('Country Code', agency.countryCode),
                ('Notes', agency.notes),
                ('Revision', '${agency.revision}'),
                ('Agency ID', agency.id.value),
              ],
            ),
          ),
          actions: [],
        ),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) => AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: 'Tax Agencies',
      description:
          'Tax codes retain the agency revision selected when they are saved.',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AccountingButton.primary(
              context,
              key: const ValueKey('tax-agency-add'),
              onPressed: () => edit(context),
              child: const Text('Add Tax Agency'),
            ),
          ),
          const SizedBox(height: accountingContentInset),
          AccountingRecordList(
            paginationKey: 'tax-agencies',
            totalCount: workspace.taxAgencies.length,
            children: [
              for (final agency in workspace.taxAgencies)
                AccountingRecordRow(
                  title: agency.name,
                  details: Text(
                    '${agency.countryCode} · ${agency.registrationNumber.isEmpty ? 'Registration not recorded' : agency.registrationNumber}',
                    style: AccountingTypography.value(context),
                  ),
                  trailing: AccountingRecordActions(
                    trailing: [
                      AccountingButton.iconOnly(
                        context,
                        key: ValueKey('tax-agency-view-${agency.id.value}'),
                        onPressed: () => view(context, agency),
                        icon: Icons.visibility_outlined,
                        tooltip: 'View ${agency.name}',
                      ),
                      AccountingButton.iconOnly(
                        context,
                        key: ValueKey('tax-agency-edit-${agency.id.value}'),
                        onPressed: () => edit(context, agency),
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit ${agency.name}',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [],
    ),
  );
}
