import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_color_library.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../app/field_row_trial.dart';

/// Customer-owned setup surface. Definition persistence and applying values to
/// contacts/documents remain pending; this route never reports a saved field.
Future<void> showCustomerCustomFieldSetup(BuildContext context) =>
    AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      builder: (_) => const CustomerCustomFieldSetup(),
    );

class CustomerCustomFieldSetup extends StatefulWidget {
  const CustomerCustomFieldSetup({super.key});

  static const forms = [
    'Sales Receipt',
    'Invoice',
    'Quotation',
    'Credit Note',
    'Refund Receipt',
    'Expense',
    'Bill',
    'Cheque',
    'Supplier Credit',
    'Credit Card Credit',
  ];

  // Audyt's existing palette, not copied QuickBooks colour values.
  static const colours = <String, Color>{
    'Green': AccountingColorLibrary.primaryGreen,
    'Grapefruit': AccountingColorLibrary.grapefruit,
    'Grapefruit Deep': AccountingColorLibrary.grapefruitDeep,
    'Bittersweet': AccountingColorLibrary.bittersweet,
    'Bittersweet Deep': AccountingColorLibrary.bittersweetDeep,
    'Sunflower': AccountingColorLibrary.sunflower,
    'Sunflower Deep': AccountingColorLibrary.sunflowerDeep,
    'Mint': AccountingColorLibrary.mint,
    'Mint Deep': AccountingColorLibrary.mintDeep,
    'Aqua': AccountingColorLibrary.aqua,
    'Aqua Deep': AccountingColorLibrary.aquaDeep,
    'Blue Jeans': AccountingColorLibrary.blueJeans,
    'Blue Jeans Deep': AccountingColorLibrary.blueJeansDeep,
    'Lavender': AccountingColorLibrary.lavender,
    'Lavender Deep': AccountingColorLibrary.lavenderDeep,
    'Pink Rose': AccountingColorLibrary.pinkRose,
    'Pink Rose Deep': AccountingColorLibrary.pinkRoseDeep,
  };

  @override
  State<CustomerCustomFieldSetup> createState() =>
      _CustomerCustomFieldSetupState();
}

class _CustomFieldItem {
  _CustomFieldItem(this.id, {this.initial = false});
  final int id;
  final bool initial;
  final text = TextEditingController();
  bool active = true;
}

class _CustomerCustomFieldSetupState extends State<CustomerCustomFieldSetup> {
  final _items = [
    _CustomFieldItem(0, initial: true),
    _CustomFieldItem(1, initial: true),
  ];
  final _retiredItems = <_CustomFieldItem>[];
  final _forms = <String>{};
  String _colour = 'Green';
  int _nextId = 2;

  @override
  void dispose() {
    for (final item in [..._items, ..._retiredItems]) {
      item.text.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _inputs(Map<String, Object?> values) => {
    ...values,
    '_definitionColour': _colour,
    '_definitionItems': [
      for (final item in _items) [item.text.text, item.active],
    ],
    '_definitionForms': CustomerCustomFieldSetup.forms
        .where(_forms.contains)
        .toList(),
  };

  List<(String, String)> _review(Map<String, Object?> values) {
    final name = '${values['Name'] ?? ''}'.trim();
    final type = '${values['Data Type'] ?? ''}';
    if (name.isEmpty || type.isEmpty) {
      throw const FormatException('Enter a name and choose a data type.');
    }
    // Review staged facts; durable definition validation is not wired yet.
    return [
      ('Name', name),
      ('Data Type', type),
      ('Category', 'Customer'),
      if (type == 'Dropdown List') ('Colour', _colour),
      if (type == 'Dropdown List')
        for (final (index, item) in _items.indexed)
          (
            'List Item ${index + 1}',
            '${item.text.text.trim().isEmpty ? 'Not Set' : item.text.text.trim()} · ${item.active ? 'Active' : 'Inactive'}',
          ),
      (
        'Forms',
        _forms.isEmpty
            ? 'Not Set'
            : CustomerCustomFieldSetup.forms.where(_forms.contains).join(', '),
      ),
      ('Saving', 'Not Connected Yet'),
    ];
  }

  Widget _checkbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged, {
    Key? key,
  }) => SizedBox(
    height: accountingControlHeight,
    child: Row(
      children: [
        AccountingLeadingCheckbox(
          hitKey: key,
          value: value,
          onChanged: onChanged,
          semanticLabel: label,
          undividedRow: true,
        ),
        Expanded(
          child: Text(label, style: AccountingTypography.value(context)),
        ),
      ],
    ),
  );

  Widget _content(
    BuildContext context,
    Map<String, Object?> values,
    bool reviewing,
  ) {
    if (reviewing) return const SizedBox.shrink();
    const activeGuidance = 'Keep at least one list item active.';
    final activeWidth = accountingFieldLabelMinimumWidth(
      context,
      'Active',
      alignToField: true,
      guidance: activeGuidance,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (values['Data Type'] == 'Dropdown List') ...[
          const SizedBox(height: accountingContentInset),
          AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Colour',
                choices: CustomerCustomFieldSetup.colours.keys.toList(),
                builder: (width) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accountingFieldLabel(context, 'Colour', alignToField: true),
                    const SizedBox(height: accountingFieldLabelGap),
                    AccountingSelector<String>(
                      triggerKey: const ValueKey('design-field-Colour'),
                      hintText: 'Select Colour',
                      assignedWidth: width,
                      value: _colour,
                      onChanged: (value) {
                        if (value != null) setState(() => _colour = value);
                      },
                      options: [
                        for (final entry
                            in CustomerCustomFieldSetup.colours.entries)
                          AccountingSelectorOption(
                            value: entry.key,
                            label: entry.key,
                            leadingWidth: accountingColourIndicatorExtent(
                              context,
                            ),
                            leading: AccountingColourIndicator(
                              key: ValueKey(
                                'customer-custom-colour-${entry.key}',
                              ),
                              color: entry.value,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          Row(
            children: [
              Expanded(
                child: accountingFieldLabel(
                  context,
                  'Dropdown List Item',
                  alignToField: true,
                ),
              ),
              const SizedBox(width: accountingContentInset),
              SizedBox(
                width: activeWidth,
                child: accountingFieldLabel(
                  context,
                  'Active',
                  alignToField: true,
                  guidance: activeGuidance,
                ),
              ),
              const SizedBox(width: accountingContentInset),
              const SizedBox(width: accountingControlHeight),
            ],
          ),
          const SizedBox(height: accountingFieldLabelGap),
          for (final item in _items) ...[
            Row(
              key: ValueKey('customer-custom-item-${item.id}'),
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('customer-custom-item-text-${item.id}'),
                    controller: item.text,
                    enabled: item.active,
                    style: AccountingTypography.controlValue(context).copyWith(
                      color: item.active
                          ? AccountingTheme.of(context).foreground
                          : AccountingTheme.of(context).mutedForeground,
                    ),
                    decoration: accountingSingleLineInputDecoration(context),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: accountingContentInset),
                SizedBox(
                  width: activeWidth,
                  height: accountingControlHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: !item.initial && item.text.text.trim().isEmpty
                        ? const SizedBox.shrink()
                        : AccountingLeadingCheckbox(
                            hitKey: ValueKey(
                              'customer-custom-item-active-${item.id}',
                            ),
                            value: item.active,
                            semanticLabel: 'Active List Item ${item.id + 1}',
                            undividedRow: true,
                            onChanged: (value) {
                              final activeItems = _items
                                  .where(
                                    (candidate) =>
                                        candidate.active &&
                                        (candidate.initial ||
                                            candidate.text.text
                                                .trim()
                                                .isNotEmpty),
                                  )
                                  .length;
                              if (value != true && activeItems <= 1) return;
                              setState(() => item.active = value == true);
                            },
                          ),
                  ),
                ),
                const SizedBox(width: accountingContentInset),
                SizedBox(
                  width: accountingControlHeight,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: item.initial || item.text.text.trim().isNotEmpty
                        ? const SizedBox.shrink()
                        : accountingCompactRemove(
                            context,
                            key: ValueKey(
                              'customer-custom-item-remove-${item.id}',
                            ),
                            tooltip: 'Remove List Item',
                            onPressed: () {
                              setState(() => _items.remove(item));
                              _retiredItems.add(item);
                            },
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
          ],
          Row(
            children: [
              Expanded(
                child: accountingHelperText(context, '${_items.length} of 100'),
              ),
              accountingCompactAdd(
                context,
                key: const ValueKey('customer-custom-item-add'),
                tooltip: 'Add List Item',
                onPressed: _items.length >= 100
                    ? null
                    : () => setState(
                        () => _items.add(_CustomFieldItem(_nextId++)),
                      ),
              ),
            ],
          ),
        ],
        const SizedBox(height: accountingContentInset),
        AccountingOrdinaryFields(
          fields: [
            AccountingOrdinaryFieldSlot(
              label: 'Category',
              choices: const ['Customer', 'Transaction'],
              builder: (width) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountingFieldLabel(context, 'Category', alignToField: true),
                  const SizedBox(height: accountingFieldLabelGap),
                  AccountingSelector<String>(
                    triggerKey: const ValueKey('customer-custom-category'),
                    hintText: 'Category',
                    assignedWidth: width,
                    value: 'Customer',
                    onChanged: (_) {},
                    options: const [
                      AccountingSelectorOption(
                        value: 'Customer',
                        label: 'Customer',
                      ),
                      AccountingSelectorOption(
                        value: 'Transaction',
                        label: 'Transaction',
                        enabled: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: accountingContentInset),
        Text('Select Forms', style: AccountingTypography.sectionTitle(context)),
        const SizedBox(height: accountingFieldLabelGap),
        for (final form in CustomerCustomFieldSetup.forms)
          _checkbox(
            form,
            _forms.contains(form),
            (value) => setState(() {
              if (value == true) {
                _forms.add(form);
              } else {
                _forms.remove(form);
              }
            }),
            key: ValueKey('customer-custom-form-$form'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FrontendFormDialog(
    form: const DesignForm('Add Custom Field', [
      DesignField('Name', required: true),
      DesignField(
        'Data Type',
        required: true,
        options: ['Text And Number', 'Dropdown List'],
      ),
    ], actionLabel: 'Save Custom Field'),
    valuesFormBuilder: (values) => DesignForm('Add Custom Field', [
      const DesignField('Name', required: true),
      const DesignField(
        'Data Type',
        required: true,
        options: ['Text And Number', 'Dropdown List'],
      ),
    ], actionLabel: 'Save Custom Field'),
    previewConfirmationEnabled: false,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    leadingContentBuilder: (context, values, reviewing) => Padding(
      padding: const EdgeInsets.only(bottom: accountingContentInset),
      child: accountingHelperText(
        context,
        'Saving custom fields and applying their values is not connected yet.',
      ),
    ),
    additionalContentBuilder: _content,
    inputValuesForComparison: _inputs,
    reviewInformationRowsBuilder: _review,
  );
}
