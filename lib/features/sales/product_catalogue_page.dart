import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_description_field.dart';
import '../../app/accounting_icons.dart';
import '../../app/accounting_theme.dart';
import '../../app/field_row_trial.dart';
import '../../app/frontend_review.dart';
import '../../app/transaction_form_layout.dart';
import '../../core/money/money.dart';
import '../../core/money/currency.dart';
import '../../core/money/currency_presentation.dart';
import '../accounting/domain/account.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';
import '../../app/sidebar_settings_icon.dart';
import '../../app/naming_setup.dart' show openAccountingSettings;
import '../../app/live_settings_catalog.dart';
import '../../core/ids/entity_id.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import 'domain/product_catalogue.dart';

Future<String?> _manualCatalogueName(BuildContext context, String title) =>
    AccountingDialog.showFixed<String>(
      context: context,
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      contentInset: accountingContentInset,
      builder: (context) => CatalogueNameDialog(title: title),
    );

class CatalogueNameDialog extends StatefulWidget {
  const CatalogueNameDialog({
    super.key,
    required this.title,
    this.preview = false,
    this.initialName = '',
    this.initialCode = '',
    this.hierarchyPreview = false,
    this.categoryId,
    this.initialParentId,
    this.parentChoices = const [],
  });
  final String title;
  final bool preview;
  final String initialName, initialCode;

  /// Managed-category proposal only; inline creation retains its simple owner.
  final bool hierarchyPreview;
  final String? categoryId, initialParentId;
  final List<CatalogueCategoryBranch> parentChoices;
  @override
  State<CatalogueNameDialog> createState() => CatalogueNameDialogState();
}

class CatalogueNameDialogState extends State<CatalogueNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);
  late final code = TextEditingController(text: widget.initialCode);
  late bool subcategory = widget.initialParentId != null;
  late String? parentId = widget.initialParentId;
  String? error;

  Map<String, String> get eligibleParents => {
    for (final branch in widget.parentChoices)
      if (catalogueCategoryPath(
            branch.id,
            widget.parentChoices,
            excluding: widget.categoryId,
          )
          case final String path)
        branch.id: path,
  };

  double _contentWidth(BuildContext context) =>
      widget.preview && widget.hierarchyPreview
      ? accountingSelectorMinimumWidth(context, [
          accountingSelectorHintText('Select Parent Category'),
          ...eligibleParents.values,
        ]).clamp(320.0, double.infinity)
      : 320;
  @override
  void dispose() {
    controller.dispose();
    code.dispose();
    super.dispose();
  }

  Widget _previewField(
    BuildContext context,
    String label,
    TextEditingController value,
    String key,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(context, label, alignToField: true),
      const SizedBox(height: accountingFieldLabelGap),
      TextField(
        key: ValueKey(key),
        controller: value,
        style: AccountingTypography.controlValue(context),
        decoration: accountingSingleLineInputDecoration(context),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.custom,
    title: widget.preview ? '${widget.title} · Proposed' : widget.title,
    description: widget.preview
        ? 'Design preview · No catalogue records are saved.'
        : null,
    fixedContentWidth: _contentWidth(context),
    contentInset: accountingContentInset,
    formFooter: true,
    content: widget.preview
        ? SizedBox(
            width: _contentWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  AccountingAlert.build(
                    context,
                    title: 'Could Not Keep Preview',
                    description: error!,
                    tone: AccountingAlertTone.critical,
                  ),
                  const SizedBox(height: accountingContentInset),
                ],
                AccountingOrdinaryFields(
                  fields: [
                    AccountingOrdinaryFieldSlot(
                      label: 'Category *',
                      builder: (_) => _previewField(
                        context,
                        'Category *',
                        controller,
                        'catalogue-manual-name',
                      ),
                    ),
                    AccountingOrdinaryFieldSlot(
                      label: 'Code Name *',
                      builder: (_) => _previewField(
                        context,
                        'Code Name *',
                        code,
                        'catalogue-category-code',
                      ),
                    ),
                  ],
                ),
                if (widget.hierarchyPreview) ...[
                  const SizedBox(height: accountingContentInset),
                  MergeSemantics(
                    child: InkWell(
                      key: const ValueKey('catalogue-category-subcategory'),
                      onTap: () => setState(() => subcategory = !subcategory),
                      child: Row(
                        children: [
                          AccountingLeadingCheckbox(
                            value: subcategory,
                            undividedRow: true,
                            onChanged: (value) =>
                                setState(() => subcategory = value ?? false),
                            semanticLabel: 'This category is a sub-category',
                          ),
                          Expanded(
                            child: Text(
                              'This category is a sub-category',
                              style: AccountingTypography.controlValue(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (subcategory) ...[
                    const SizedBox(height: accountingContentInset),
                    AccountingOrdinaryFields(
                      fields: [
                        AccountingOrdinaryFieldSlot(
                          label: 'Parent Category *',
                          choices: [
                            accountingSelectorHintText(
                              'Select Parent Category',
                            ),
                            ...eligibleParents.values,
                          ],
                          builder: (assignedWidth) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              accountingFieldLabel(
                                context,
                                'Parent Category *',
                                alignToField: true,
                              ),
                              const SizedBox(height: accountingFieldLabelGap),
                              AccountingSelector<String>(
                                triggerKey: const ValueKey(
                                  'catalogue-category-parent',
                                ),
                                assignedWidth: assignedWidth,
                                hintText: accountingSelectorHintText(
                                  'Select Parent Category',
                                ),
                                value: parentId,
                                options: [
                                  for (final entry in eligibleParents.entries)
                                    AccountingSelectorOption(
                                      value: entry.key,
                                      label: entry.value,
                                      preserveLabelCase: true,
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => parentId = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              accountingFieldLabel(
                context,
                widget.title == 'Add Category' ? 'Category' : 'Item Name',
                alignToField: true,
              ),
              const SizedBox(height: accountingFieldLabelGap),
              TextField(
                key: const ValueKey('catalogue-manual-name'),
                controller: controller,
                autofocus: true,
                style: AccountingTypography.controlValue(context),
                decoration: accountingSingleLineInputDecoration(context)
                    .copyWith(errorText: error),
              ),
            ],
          ),
    actions: [
      AccountingButton.ghost(
        context,
        key: const ValueKey('catalogue-cancel-name'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      AccountingButton.primary(
        context,
        key: const ValueKey('catalogue-save-name'),
        onPressed: () {
          try {
            final name = catalogueName(controller.text);
            if (widget.preview) {
              final message = catalogueFilingCodeError(code.text);
              if (message != null) throw FormatException(message);
              if (widget.hierarchyPreview &&
                  subcategory &&
                  !eligibleParents.containsKey(parentId)) {
                throw const FormatException('Choose a valid Parent Category.');
              }
              Navigator.pop(
                context,
                CatalogueNamePreview(
                  name,
                  code.text.trim().toUpperCase(),
                  categoryId: widget.categoryId,
                  parentId: widget.hierarchyPreview && subcategory
                      ? parentId
                      : null,
                ),
              );
            } else {
              Navigator.pop(context, name);
            }
          } on FormatException catch (e) {
            setState(() => error = e.message);
          }
        },
        child: Text(widget.preview ? 'Keep Preview' : 'Save'),
      ),
    ],
  );
}

/// Preview-session values only. These are not catalogue or filename persistence.
final class CatalogueNamePreview {
  const CatalogueNamePreview(
    this.name,
    this.code, {
    this.categoryId,
    this.parentId,
  });
  final String name, code;
  final String? categoryId, parentId;
}

/// Session tree used only to review managed-category fields. No storage model.
final class CatalogueCategoryBranch {
  const CatalogueCategoryBranch({
    required this.id,
    required this.name,
    this.parentId,
  });
  final String id, name;
  final String? parentId;
}

/// A usable parent has a complete, unique ancestry and never contains the edited
/// category. Invalid/missing/cyclic branches cannot be selected as parents.
String? catalogueCategoryPath(
  String id,
  List<CatalogueCategoryBranch> branches, {
  String? excluding,
}) {
  final byId = {for (final branch in branches) branch.id: branch};
  if (byId.length != branches.length) return null;
  final visited = <String>{};
  final names = <String>[];
  String? current = id;
  while (current != null) {
    if (current == excluding || !visited.add(current)) return null;
    final branch = byId[current];
    if (branch == null || branch.name.trim().isEmpty) return null;
    names.add(branch.name);
    current = branch.parentId;
  }
  return names.reversed.join(' / ');
}

String? catalogueFilingCodeError(String value) {
  final code = value.trim();
  if (code.isEmpty) return 'Enter a Code Name.';
  if (RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(code) || code.endsWith('.')) {
    return 'Enter a filename-safe Code Name.';
  }
  return null;
}

final class CatalogueItemPreview {
  const CatalogueItemPreview({this.code = '', this.sku = '', this.rate});
  final String code, sku;
  final String? rate;
}

Future<CatalogueItem?> showCatalogueItemDialog(
  BuildContext context,
  AccountingWorkspace workspace, {
  CatalogueItem? initial,
}) => AccountingDialog.showFixed<CatalogueItem>(
  context: context,
  contentWidth: AccountingPopoutTokens.normalContentWidth,
  contentInset: accountingContentInset,
  builder: (_) => CatalogueItemDialog(workspace: workspace, initial: initial),
);

class CatalogueItemDialog extends StatefulWidget {
  const CatalogueItemDialog({
    super.key,
    required this.workspace,
    this.initial,
    this.preview,
  });
  final AccountingWorkspace workspace;
  final CatalogueItem? initial;
  final CatalogueItemPreview? preview;
  @override
  State<CatalogueItemDialog> createState() => _CatalogueItemDialogState();
}

class _CatalogueItemDialogState extends State<CatalogueItemDialog> {
  late EntityId id = widget.initial?.id ?? EntityId.random();
  late int revision = widget.initial?.revision ?? 0;
  late CatalogueItemType type =
      widget.initial?.type ?? CatalogueItemType.service;
  late EntityId? categoryId = widget.initial?.categoryId;
  late String? name = widget.initial?.name;
  late String tax = widget.initial?.taxRatePercent ?? '0';
  late EntityId? accountId = widget.initial?.incomeAccountId;
  late final description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final previewName = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final previewCode = TextEditingController(
    text: widget.preview?.code ?? '',
  );
  late final previewSku = TextEditingController(
    text: widget.preview?.sku ?? '',
  );
  late final previewRate = TextEditingController(
    text:
        widget.preview?.rate ??
        Money.zero(widget.workspace.identity.currency).toDecimalString(),
  );
  final previewCategories = <CatalogueCategory>[];
  final previewCategoryCodes = <String, String>{};
  List<Account> previewAccounts = const [];
  bool previewKept = false;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      widget.workspace.accounts().then((stored) {
        if (!mounted) return;
        setState(() {
          previewAccounts = stored
              .map((r) => r.account)
              .where(
                (a) =>
                    a.type == AccountType.income &&
                    a.status == AccountStatus.active &&
                    !a.isParent,
              )
              .toList();
          final configured = widget.workspace.preferences.text(
            'Default Accounts',
            'Income Account',
          );
          accountId ??= previewAccounts
              .where((a) => a.id.value == configured)
              .firstOrNull
              ?.id;
        });
      });
    }
  }

  String? error;
  @override
  void dispose() {
    description.dispose();
    previewName.dispose();
    previewCode.dispose();
    previewSku.dispose();
    previewRate.dispose();
    super.dispose();
  }

  Future<void> addCategory() async {
    final name = await _manualCatalogueName(context, 'Add Category');
    if (name == null || !mounted) return;
    try {
      final saved = widget.workspace.saveCatalogueCategory(
        CatalogueCategory(id: EntityId.random(), name: name),
      );
      setState(() => categoryId = saved.id);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> addName() async {
    final entered = await _manualCatalogueName(context, 'Add Item');
    if (entered == null || !mounted) return;
    final duplicate = widget.workspace.catalogueItems
        .where((i) => i.name.toLowerCase() == entered.toLowerCase())
        .firstOrNull;
    if (duplicate != null) {
      setState(
        () => error = 'This item already exists. Select its saved name.',
      );
      return;
    }
    setState(() {
      id = EntityId.random();
      revision = 0;
      name = entered;
      error = null;
    });
  }

  void selectItem(String? value) {
    if (value == null) return;
    final item = widget.workspace.catalogueItems
        .where((i) => i.id.value == value)
        .firstOrNull;
    if (item == null) return;
    setState(() {
      id = item.id;
      revision = item.revision;
      name = item.name;
      type = item.type;
      categoryId = item.categoryId;
      accountId = item.incomeAccountId;
      tax = item.taxRatePercent;
      description.text = item.description;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preview != null) return _buildPreview(context);
    final categories = widget.workspace.catalogueCategories;
    final items = widget.workspace.catalogueItems;
    final taxes = {'0', tax, ...items.map((i) => i.taxRatePercent)};
    Widget field(String label, Widget child) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingFieldLabel(context, label, alignToField: true),
          const SizedBox(height: accountingFieldLabelGap),
          child,
        ],
      ),
    );
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: revision == 0 ? 'Add Item' : 'Edit Item',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      contentInset: accountingContentInset,
      formFooter: true,
      footerLeading: AccountingSettingsShortcut(
        key: const ValueKey('catalogue-settings-shortcut'),
        onPressed: () async {
          await openAccountingSettings(
            context,
            workspace: widget.workspace,
            fields: transactionSettingsFields('Products & Services'),
            setupKinds: const {},
            title: 'Product / Service Settings',
          );
          if (mounted) setState(() {});
        },
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            AccountingAlert.build(
              context,
              title: 'Could Not Save',
              description: error!,
              tone: AccountingAlertTone.critical,
            ),
            const SizedBox(height: accountingContentInset),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              field(
                'Type',
                AccountingSelector<CatalogueItemType>(
                  assignedWidth: (600 - accountingContentInset) / 2,
                  triggerKey: const ValueKey('catalogue-type'),
                  hintText: 'Select Type',
                  value: type,
                  options: [
                    for (final t in CatalogueItemType.values)
                      AccountingSelectorOption(
                        value: t,
                        label: t == CatalogueItemType.service
                            ? 'Service'
                            : 'Product',
                      ),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
              ),
              const SizedBox(width: accountingContentInset),
              field(
                'Tax',
                AccountingSelector<String>(
                  assignedWidth: (600 - accountingContentInset) / 2,
                  triggerKey: const ValueKey('catalogue-tax'),
                  hintText: 'Select Tax',
                  value: tax,
                  options: [
                    for (final t in taxes)
                      AccountingSelectorOption(
                        value: t,
                        label: t == '0' ? 'No tax' : '$t%',
                      ),
                  ],
                  onChanged: (v) => setState(() => tax = v ?? tax),
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              field(
                'Category',
                AccountingSelector<String>(
                  assignedWidth: (600 - accountingContentInset) / 2,
                  triggerKey: const ValueKey('catalogue-category'),
                  value: categoryId?.value,
                  options: [
                    AccountingSelectorOption(
                      value: '__add_category',
                      label: 'Add Category',
                      leading: const AccountingIcon(Icons.add),
                      onPressed: addCategory,
                    ),
                    for (final c in categories)
                      AccountingSelectorOption(
                        value: c.id.value,
                        label: c.name,
                        preserveLabelCase: true,
                      ),
                  ],
                  hintText: 'Select Category',
                  onChanged: (v) => setState(
                    () => categoryId = v == null ? null : EntityId.parse(v),
                  ),
                ),
              ),
              const SizedBox(width: accountingContentInset),
              field(
                'Item Name',
                AccountingSelector<String>(
                  assignedWidth: (600 - accountingContentInset) / 2,
                  triggerKey: const ValueKey('catalogue-item-name'),
                  value: name == null ? null : id.value,
                  options: [
                    AccountingSelectorOption(
                      value: '__add_item',
                      label: 'Add Item',
                      leading: const AccountingIcon(Icons.add),
                      onPressed: addName,
                    ),
                    if (name != null && !items.any((i) => i.id == id))
                      AccountingSelectorOption(
                        value: id.value,
                        label: name!,
                        preserveLabelCase: true,
                      ),
                    for (final i in items)
                      AccountingSelectorOption(
                        value: i.id.value,
                        label: i.name,
                        preserveLabelCase: true,
                      ),
                  ],
                  hintText: 'Select Item',
                  onChanged: selectItem,
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          accountingFieldLabel(context, 'Description', alignToField: true),
          const SizedBox(height: accountingFieldLabelGap),
          AccountingDescriptionField(
            key: const ValueKey('catalogue-description'),
            controller: description,
            decoration: accountingInputDecoration(context),
          ),
        ],
      ),
      actions: [
        AccountingButton.ghost(
          context,
          key: const ValueKey('catalogue-cancel-item'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('catalogue-save-item'),
          onPressed: () {
            try {
              if (categoryId == null) throw StateError('Choose a category.');
              if (name == null) throw StateError('Add or select an item name.');
              final mapping =
                  accountId?.value ??
                  widget.workspace.preferences.text(
                    'Default Accounts',
                    'Income Account',
                  );
              if (mapping.isEmpty) {
                throw StateError(
                  'Set an Income Account in company Settings before saving an item.',
                );
              }
              final saved = widget.workspace.saveCatalogueItem(
                CatalogueItem(
                  id: id,
                  categoryId: categoryId!,
                  name: name!,
                  type: type,
                  incomeAccountId: EntityId.parse(mapping),
                  description: description.text.trim(),
                  taxRatePercent: tax,
                  revision: revision,
                ),
              );
              Navigator.pop(context, saved);
            } catch (e) {
              setState(() => error = '$e');
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _addPreviewCategory() async {
    final value = await showDialog<CatalogueNamePreview>(
      context: context,
      builder: (_) =>
          const CatalogueNameDialog(title: 'Add Category', preview: true),
    );
    if (value == null || !mounted) return;
    final all = [...widget.workspace.catalogueCategories, ...previewCategories];
    if (all.any((c) => c.name.toLowerCase() == value.name.toLowerCase()) ||
        previewCategoryCodes.values.contains(value.code)) {
      setState(
        () => error = 'That category name or preview Code Name already exists.',
      );
      return;
    }
    final added = CatalogueCategory(id: EntityId.random(), name: value.name);
    setState(() {
      previewCategories.add(added);
      previewCategoryCodes[added.id.value] = value.code;
      categoryId = added.id;
      error = null;
      previewKept = false;
    });
  }

  void _keepPreview() {
    try {
      catalogueName(previewName.text);
      final codeError = catalogueFilingCodeError(previewCode.text);
      if (codeError != null) throw FormatException(codeError);
      if (categoryId == null) throw const FormatException('Choose a category.');
      if (!previewAccounts.any((a) => a.id == accountId)) {
        throw const FormatException('Choose an active Income Account.');
      }
      final rate = Money.fromDecimal(
        previewRate.text.replaceAll(',', ''),
        widget.workspace.identity.currency,
      );
      if (rate.isNegative) {
        throw const FormatException('Price / Rate cannot be negative.');
      }
      setState(() {
        error = null;
        previewKept = true;
      });
    } catch (e) {
      setState(() {
        error = e is FormatException ? e.message.toString() : '$e';
        previewKept = false;
      });
    }
  }

  Widget _previewLabelled(
    BuildContext context,
    String label,
    Widget control, {
    String? guidance,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(
        context,
        label,
        alignToField: true,
        guidance: guidance,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      control,
    ],
  );

  Widget _previewText(
    BuildContext context,
    String label,
    String key,
    TextEditingController controller,
  ) => _previewLabelled(
    context,
    label,
    TextField(
      key: ValueKey(key),
      controller: controller,
      style: AccountingTypography.controlValue(context),
      decoration: accountingSingleLineInputDecoration(context),
      onChanged: (_) => setState(() => previewKept = false),
    ),
  );

  Future<void> _openPreviewSettings() async {
    final incomeChoices = {
      for (final a in previewAccounts) a.id.value: a.displayName,
    };
    final form = liveSettingsForms({'Income Account': incomeChoices})
        .firstWhere((f) => f.title == 'Default Accounts');
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        contentWidth: AccountingPopoutTokens.normalContentWidth,
        form: DesignForm(
          'Product / Service Settings',
          form.fields.where((f) => f.label == 'Income Account').toList(),
        ),
        initial: {
          'Income Account': widget.workspace.preferences.text(
            'Default Accounts',
            'Income Account',
          ),
        },
      ),
    );
    if (values == null || !mounted || widget.initial != null) return;
    // A kept default affects this unsaved preview only. Existing item mappings
    // and durable company defaults remain owned by their original save routes.
    final value = values['Income Account'];
    if (value is String) {
      setState(() {
        accountId = previewAccounts
            .where((a) => a.id.value == value)
            .firstOrNull
            ?.id;
        previewKept = false;
      });
    }
  }

  Widget _buildPreview(BuildContext context) {
    final categories = [
      ...widget.workspace.catalogueCategories,
      ...previewCategories,
    ];
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: '${widget.initial == null ? 'Add' : 'Edit'} Item · Proposed',
      description: 'Design preview · Changes stay in this review session.',
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      contentInset: accountingContentInset,
      formFooter: true,
      footerLeading: AccountingSettingsShortcut(
        key: const ValueKey('catalogue-preview-settings-shortcut'),
        onPressed: _openPreviewSettings,
      ),
      content: SizedBox(
        width: AccountingPopoutTokens.normalContentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              AccountingAlert.build(
                context,
                title: 'Check Item',
                description: error!,
                tone: AccountingAlertTone.critical,
              ),
              const SizedBox(height: accountingContentInset),
            ],
            AccountingOrdinaryFields(
              key: const ValueKey('catalogue-preview-ordinary'),
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: 'Item Name *',
                  builder: (_) => _previewText(
                    context,
                    'Item Name *',
                    'catalogue-preview-name',
                    previewName,
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Type',
                  hasGuidance: true,
                  choices: const ['Service', 'Non-inventory Product'],
                  builder: (width) => _previewLabelled(
                    context,
                    'Type',
                    AccountingSelector<CatalogueItemType>(
                      assignedWidth: width,
                      hintText: 'Select Type',
                      triggerKey: const ValueKey('catalogue-preview-type'),
                      value: type,
                      options: [
                        for (final t in CatalogueItemType.values)
                          AccountingSelectorOption(
                            value: t,
                            label: t == CatalogueItemType.service
                                ? 'Service'
                                : 'Non-inventory Product',
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        type = value ?? type;
                        previewKept = false;
                      }),
                    ),
                    guidance: 'Sales tax is selected once on the Invoice or Quotation.',
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Code Name *',
                  builder: (_) => _previewText(
                    context,
                    'Code Name *',
                    'catalogue-preview-code',
                    previewCode,
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Category *',
                  choices: [
                    'Select Category',
                    'Add Category',
                    for (final c in categories) c.name,
                  ],
                  builder: (width) => _previewLabelled(
                    context,
                    'Category *',
                    AccountingSelector<String>(
                      assignedWidth: width,
                      triggerKey: const ValueKey('catalogue-preview-category'),
                      hintText: 'Select Category',
                      value: categoryId?.value,
                      options: [
                        AccountingSelectorOption(
                          value: '__add_category',
                          label: 'Add Category',
                          leading: const AccountingIcon(Icons.add),
                          onPressed: _addPreviewCategory,
                        ),
                        for (final c in categories)
                          AccountingSelectorOption(
                            value: c.id.value,
                            label: c.name,
                            preserveLabelCase: true,
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        categoryId = value == null
                            ? null
                            : EntityId.parse(value);
                        previewKept = false;
                      }),
                    ),
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'SKU',
                  builder: (_) => _previewText(
                    context,
                    'SKU',
                    'catalogue-preview-sku',
                    previewSku,
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Income Account *',
                  choices: [
                    'Select Income Account',
                    for (final a in previewAccounts) a.displayName,
                  ],
                  builder: (width) => _previewLabelled(
                    context,
                    'Income Account *',
                    AccountingSelector<String>(
                      assignedWidth: width,
                      triggerKey: const ValueKey('catalogue-preview-income'),
                      hintText: 'Select Income Account',
                      value: accountId?.value,
                      options: [
                        for (final a in previewAccounts)
                          AccountingSelectorOption(
                            value: a.id.value,
                            label: a.displayName,
                            preserveLabelCase: true,
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        accountId = value == null
                            ? null
                            : EntityId.parse(value);
                        previewKept = false;
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: AccountingTransactionGridTokens.numericWidth(
                  context,
                  'Price / Rate',
                  [previewRate.text],
                  title:
                      'Price / Rate (${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol})',
                  minimumText:
                      'Price / Rate (${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol})',
                ),
                child: _previewLabelled(
                  context,
                  'Price / Rate (${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol})',
                  TextField(
                    key: const ValueKey('catalogue-preview-rate'),
                    controller: previewRate,
                    inputFormatters: [
                      AccountingMoneyInputFormatter(
                        Currency.parse(widget.workspace.identity.currency)
                            .fractionDigits,
                      ),
                    ],
                    textAlign: TextAlign.right,
                    style: AccountingTypography.controlValue(context),
                    decoration: accountingSingleLineInputDecoration(context),
                    onChanged: (_) => setState(() => previewKept = false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            _previewLabelled(
              context,
              'Description',
              AccountingDescriptionField(
                key: const ValueKey('catalogue-description'),
                controller: description,
                decoration: accountingInputDecoration(context),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            if (previewKept) ...[
              const SizedBox(height: accountingContentInset),
              accountingHelperText(
                context,
                'Preview kept · No catalogue records saved.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        AccountingButton.ghost(
          context,
          key: const ValueKey('catalogue-preview-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('catalogue-preview-keep'),
          onPressed: _keepPreview,
          child: const Text('Keep Preview'),
        ),
      ],
    );
  }
}

class ProductCataloguePage extends StatelessWidget {
  const ProductCataloguePage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final items = workspace.catalogueItems;
      final categories = {
        for (final c in workspace.catalogueCategories) c.id: c.name,
      };
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'products-services',
              title: 'Products & Services',
              description: 'Manage items and their reporting categories.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('catalogue-add-item'),
                onPressed: () => showCatalogueItemDialog(context, workspace),
                child: const Text('Add Item'),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            AccountingRecordList(
              paginationKey: 'product-catalogue-1',
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(accountingContentInset),
                    child: Text(
                      'No items registered yet.',
                      style: AccountingTypography.value(context),
                    ),
                  ),
                for (final item in items)
                  AccountingRecordRow(
                    title: item.name,
                    details: Text(
                      '${categories[item.categoryId] ?? 'Saved Category'} · ${item.type == CatalogueItemType.service ? 'Service' : 'Product'}',
                      style: AccountingTypography.value(context),
                    ),
                    trailing: AccountingRecordActions(
                      trailing: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('catalogue-edit-${item.id}'),
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit Item',
                          onPressed: () => showCatalogueItemDialog(
                            context,
                            workspace,
                            initial: item,
                          ),
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
