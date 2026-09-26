import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../application/accounting_workspace.dart';
import '../domain/account.dart';
import '../domain/company_tax_rate.dart';
import 'tax_agencies_dialog.dart';
import 'widgets/accounting_layout.dart';

Future<FrontendFormDialog> taxRateEditor(
  AccountingWorkspace w, [
  CompanyTaxRate? original,
]) => _taxRateEditor(w, original, purchaseCostProposal: false);

Future<FrontendFormDialog> proposedTaxRateEditor(
  AccountingWorkspace w, [
  CompanyTaxRate? original,
  bool includeAgency = false,
]) => _taxRateEditor(
  w,
  original,
  purchaseCostProposal: true,
  includeAgency: includeAgency,
);

Future<FrontendFormDialog> _taxRateEditor(
  AccountingWorkspace w,
  CompanyTaxRate? original, {
  required bool purchaseCostProposal,
  bool includeAgency = false,
}) async {
  final accounts = {
    for (final r in await w.accounts())
      if (r.account.type == AccountType.liability &&
          r.account.status == AccountStatus.active &&
          !r.account.isParent)
        r.account.id.value: r.account.displayName,
  };
  final agencies = w.taxAgencies;
  final agencyChoices = {
    'unassigned': 'Unassigned Agency',
    for (final agency in agencies) agency.choice: agency.name,
    if (original?.agencySnapshot != null &&
        !agencies.any((a) => a.choice == original!.agencySnapshot!.choice))
      original!.agencySnapshot!.choice:
          '${original.agencySnapshot!.name} · Saved Revision ${original.agencySnapshot!.revision}',
  };
  DesignForm specification({bool purchases = false}) => DesignForm(
    original == null ? 'Add Tax Rate' : 'Edit Tax Rate',
    [
      if (includeAgency) DesignField('Tax Agency', choiceLabels: agencyChoices),
      const DesignField('Name', required: true),
      const DesignField('Rate (%)', required: true),
      const DesignField('Effective From', required: true),
      const DesignField('Effective Through'),
      DesignField(
        'Applies To',
        options: ['Sales', 'Purchases', 'Sales & Purchases'],
        required: true,
      ),
      if (!purchaseCostProposal || !purchases)
        DesignField('Tax Account', choiceLabels: accounts, required: true),
      const DesignField('Description', multiline: true),
      const DesignField('Active', toggle: true),
    ],
    description: purchaseCostProposal
        ? (purchases
              ? 'Purchase tax stays in expense or asset cost. No separate tax account is posted.${original?.accountId != null ? ' Saved account mapping is retained in the code history.' : ''}'
              : 'Sales tax uses the selected liability account. Purchase tax stays in cost.')
        : null,
    actionLabel: 'Save',
  );
  return FrontendFormDialog(
    form: specification(),
    valuesFormBuilder: purchaseCostProposal
        ? (values) =>
              specification(purchases: values['Applies To'] == 'Purchases')
        : null,
    initial: {
      if (includeAgency)
        'Tax Agency': original?.agencySnapshot?.choice ?? 'unassigned',
      'Name': original?.name ?? '',
      'Rate (%)': original?.percent ?? '',
      'Effective From': formatAccountingInputDate(
        original?.effectiveFrom ?? DateTime.now(),
      ),
      'Effective Through': original?.effectiveThrough == null
          ? ''
          : formatAccountingInputDate(original!.effectiveThrough!),
      'Applies To': switch (original?.application) {
        TaxApplication.sales => 'Sales',
        TaxApplication.purchases => 'Purchases',
        _ => 'Sales & Purchases',
      },
      'Tax Account':
          original?.accountId?.value ??
          w.preferences.text('Default Accounts', 'Sales Tax Liability Account'),
      'Description': original?.description ?? '',
      'Active': original?.active ?? true,
    },
    onCommit: (values) async {
      String text(String key) => (values[key] as String? ?? '').trim();
      final from = parseAccountingInputDate(text('Effective From'));
      final through = text('Effective Through').isEmpty
          ? null
          : parseAccountingInputDate(text('Effective Through'));
      if (from == null ||
          text('Effective Through').isNotEmpty && through == null) {
        throw const FormatException('Enter valid effective dates.');
      }
      final agencyChoice = text('Tax Agency');
      final selectedAgency = !includeAgency
          ? original?.agencySnapshot
          : (agencyChoice == 'unassigned'
                ? null
                : (agencyChoice == original?.agencySnapshot?.choice
                      ? original!.agencySnapshot
                      : agencies
                            .where((a) => a.choice == agencyChoice)
                            .firstOrNull));
      if (includeAgency &&
          agencyChoice != 'unassigned' &&
          selectedAgency == null) {
        throw StateError('Choose an available Tax Agency.');
      }
      w.saveTaxRate(
        CompanyTaxRate(
          id: original?.id ?? EntityId.random(),
          agencySnapshot: selectedAgency,
          name: text('Name'),
          percent: text('Rate (%)'),
          effectiveFrom: from,
          effectiveThrough: through,
          application: switch (text('Applies To')) {
            'Sales' => TaxApplication.sales,
            'Purchases' => TaxApplication.purchases,
            'Sales & Purchases' => TaxApplication.both,
            _ => throw const FormatException('Choose where the tax applies.'),
          },
          accountId: purchaseCostProposal && text('Applies To') == 'Purchases'
              ? original?.accountId
              : EntityId.parse(text('Tax Account')),
          description: text('Description'),
          active: values['Active'] as bool? ?? true,
          revision: original?.revision ?? 0,
        ),
      );
    },
  );
}

class TaxRatesPage extends StatefulWidget {
  const TaxRatesPage({
    super.key,
    required this.workspace,
    this.purchaseCostProposal = true,
    this.taxAgencyProposal = true,
  });
  final bool purchaseCostProposal, taxAgencyProposal;
  final AccountingWorkspace workspace;
  @override
  State<TaxRatesPage> createState() => _TaxRatesPageState();
}

class _TaxRatesPageState extends State<TaxRatesPage> {
  String? status;
  Future<void> edit([CompanyTaxRate? original]) async {
    final editor = await (widget.purchaseCostProposal
        ? proposedTaxRateEditor(
            widget.workspace,
            original,
            widget.taxAgencyProposal,
          )
        : taxRateEditor(widget.workspace, original));
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => editor);
  }

  Future<void> view(CompanyTaxRate rate) => AccountingDialog.showFixed<void>(
    context: context,
    contentWidth: 600,
    builder: (context) => AccountingDialog.alert(
      context,
      title: rate.name,
      content: AccountingInformationRows(
        rows: [
          ('Rate', '${rate.percent}%'),
          ('Effective From', formatAccountingInputDate(rate.effectiveFrom)),
          (
            'Effective Through',
            rate.effectiveThrough == null
                ? '—'
                : formatAccountingInputDate(rate.effectiveThrough!),
          ),
          (
            'Applies To',
            switch (rate.application) {
              TaxApplication.sales => 'Sales',
              TaxApplication.purchases => 'Purchases',
              TaxApplication.both => 'Sales & Purchases',
            },
          ),
          if (widget.taxAgencyProposal) ...[
            ('Tax Agency', rate.agencySnapshot?.name ?? 'Unassigned Agency'),
            if (rate.agencySnapshot != null) ...[
              ('Agency Revision', '${rate.agencySnapshot!.revision}'),
              ('Registration Number', rate.agencySnapshot!.registrationNumber),
              ('Country Code', rate.agencySnapshot!.countryCode),
            ],
          ],
          ('Revision', '${rate.revision}'),
          if (rate.description.isNotEmpty) ('Description', rate.description),
        ],
      ),
      actions: [],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final all = widget.workspace.taxRates;
      final controls = AccountingRecordControlsPolicy.visible(all.length);
      final rows = all
          .where(
            (r) =>
                !controls || status == null || r.active == (status == 'Active'),
          )
          .toList();
      return AccountingPageShell(
        includeTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Tax',
              title: 'Tax Codes',
              description: 'Manage reusable rates and preserve the rates on saved transactions.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('tax-rate-add'),
                onPressed: edit,
                child: const Text('Add Tax Rate'),
              ),
              secondaryActions: [
                if (widget.taxAgencyProposal)
                  AccountingButton.secondary(
                    context,
                    key: const ValueKey('tax-agencies-open'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          TaxAgenciesDialog(workspace: widget.workspace),
                    ),
                    child: const Text('Tax Agencies'),
                  ),
              ],
            ),
            const SizedBox(height: accountingPageTitleOuterGap),
            AccountingRecordControls(
              recordCount: all.length,
              child: Padding(
                padding: const EdgeInsets.only(bottom: accountingContentInset),
                child: AccountingRecordFilter(
                  label: 'Status',
                  options: const ['Active', 'Inactive'],
                  value: status,
                  onChanged: (v) => setState(() => status = v),
                ),
              ),
            ),
            AccountingRecordList(
              paginationKey: 'tax-codes',
              totalCount: all.length,
              children: [
                for (final r in rows)
                  AccountingRecordRow(
                    title: r.name,
                    status: AccountingBadge.build(
                      context,
                      label: r.active ? 'Active' : 'Inactive',
                    ),
                    details: Text(
                      '${r.percent}% · Effective ${formatAccountingInputDate(r.effectiveFrom)}',
                      style: AccountingTypography.value(context),
                    ),
                    trailing: AccountingRecordActions(
                      trailing: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('tax-rate-view-${r.id.value}'),
                          onPressed: () => view(r),
                          icon: Icons.visibility_outlined,
                          tooltip: 'View ${r.name}',
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('tax-rate-edit-${r.id.value}'),
                          onPressed: () => edit(r),
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit ${r.name}',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
