import 'field_row_trial.dart' show AccountingFieldLayoutOwner;
import '../features/sales/invoice_page.dart';
import '../features/accounting/presentation/record_expense_page.dart';
import '../features/accounting/application/workspace_backup.dart';
import '../features/accounting/presentation/payment_method_directory_dialog.dart';
import '../features/accounting/presentation/payment_terms_directory_dialog.dart';
import '../features/sales/statement_settings_dialog.dart';
import '../features/sales/sales_email_settings_dialog.dart';
import 'workspace_backup_controls.dart';

import 'package:audyt/core/documents/folder_placement_plan.dart';

import 'demo_company.dart';
import 'design_samples.dart' show demoFolderRoot;
import '../features/accounting/application/accounting_workspace.dart';
import '../features/accounting/domain/company_preferences.dart';
import '../features/accounting/domain/account.dart';
import 'live_settings_catalog.dart';
import 'google_account_session.dart';
import 'frontend_review.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accounting_components.dart';
import 'accounting_icons.dart';
import 'accounting_theme.dart';
import 'audyt_date_picker.dart';
import 'transaction_form_layout.dart';

enum NamingValue {
  custom('Custom Text'),
  codeName('Code Name'),
  day('DD'),
  month('MM'),
  shortYear('YY'),
  year('YYYY'),
  category('Category Code'),
  receiptDate('Receipt DDMM'),
  separator('Separator');

  const NamingValue(this.label);
  final String label;
}

class NamingBlock {
  NamingBlock({this.type, this.text = ''});
  NamingValue? type;
  String text;
  Map<String, dynamic> toJson() => {'type': type?.name, 'text': text};
  factory NamingBlock.fromJson(Map<String, dynamic> json) => NamingBlock(
    type: NamingValue.values.where((v) => v.name == json['type']).firstOrNull,
    text: json['text'] as String? ?? '',
  );
  String render(
    DateTime date,
    String category, {
    DateTime? receiptDate,
    String? codeName,
  }) => switch (type) {
    NamingValue.custom => text.toUpperCase(),
    NamingValue.codeName =>
      codeName?.trim().toUpperCase() ??
          (throw StateError('Document Code Name is required.')),
    NamingValue.separator => text,
    NamingValue.day => date.day.toString().padLeft(2, '0'),
    NamingValue.month => date.month.toString().padLeft(2, '0'),
    NamingValue.shortYear => (date.year % 100).toString().padLeft(2, '0'),
    NamingValue.year => date.year.toString().padLeft(4, '0'),
    NamingValue.category => category.toUpperCase(),
    NamingValue.receiptDate =>
      receiptDate == null
          ? throw StateError('Original receipt date is required.')
          : '${receiptDate.day.toString().padLeft(2, '0')}${receiptDate.month.toString().padLeft(2, '0')}',
    null => '',
  };
}

String namingPreview(
  List<NamingBlock> blocks,
  DateTime date,
  String category, {
  String? codeName,
}) => blocks
    .map((b) => b.render(date, category, receiptDate: date, codeName: codeName))
    .join();

/// Convert the persisted editor format without inventing missing tokens.
DocumentNamingPlan namingPlanFromBlocks(
  List<NamingBlock> blocks,
) => DocumentNamingPlan(
  blocks
      .map(
        (block) => switch (block.type) {
          NamingValue.custom => NamingColumn.custom(block.text.toUpperCase()),
          NamingValue.codeName => NamingColumn.field('documentCodeName'),
          NamingValue.day => NamingColumn.day(),
          NamingValue.month => NamingColumn.monthNumber(),
          NamingValue.shortYear => NamingColumn.yearShort(),
          NamingValue.year => NamingColumn.year(),
          NamingValue.category => NamingColumn.field('categoryCode'),
          NamingValue.receiptDate => NamingColumn.field('receiptDate'),
          NamingValue.separator => NamingColumn.custom(block.text),
          null => throw StateError('Choose a value for every naming block.'),
        },
      )
      .toList(),
);

const namingMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String namingFolderSuffix(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}. ${namingMonths[date.month - 1]} ${date.year}';

const namingSettingsChannel = MethodChannel('audyt/naming-settings');

enum SetupKind {
  expense('expense', 'Expense Setup'),
  invoice('invoice', 'Invoice Setup'),
  voucher('voucher', 'Payment Voucher Setup'),
  claims('claims', 'Claims Setup');

  const SetupKind(this.id, this.label);
  final String id;
  final String label;
}

Future<bool> openNamingSetup(
  BuildContext context, {
  SetupKind kind = SetupKind.expense,
  bool onlyIfMissing = false,
}) async {
  String? saved;
  String? folder;
  try {
    saved = await namingSettingsChannel.invokeMethod<String>('load', {
      'kind': kind.id,
    });
    folder = await namingSettingsChannel.invokeMethod<String>('loadFolder', {
      'kind': kind.id,
    });
  } on MissingPluginException {
    /* Native persistence is available in the macOS host. */
  } on PlatformException {
    /* Let the user repair the setup through the picker. */
  }
  if (!context.mounted) return false;
  if (onlyIfMissing && saved != null && folder != null) return true;
  return await showDialog<bool>(
        context: context,
        builder: (_) => NamingSetupDialog(
          saved: saved,
          kind: kind,
          setupRequired: onlyIfMissing,
        ),
      ) ??
      false;
}

Future<void> openAccountingSettings(
  BuildContext context, {
  VoidCallback? onAuditLog,
  VoidCallback? onManageUsers,
  AccountingWorkspace? workspace,
  Future<void> Function(String)? onOpenRestored,
  Future<List<String>> Function()? loadAccountNames,
  Map<String, Set<String>>? fields,
  Set<SetupKind>? setupKinds,
  String title = 'Settings',
  Map<SetupKind, String>? proposalCodeNames,
  bool proposalOnly = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AccountingSettingsDialog(
    demo: DemoCompany.active(context),
    workspace: workspace,
    onOpenRestored: onOpenRestored,
    onAuditLog: onAuditLog,
    onManageUsers: onManageUsers,
    loadAccountNames: loadAccountNames,
    fields: fields,
    setupKinds: setupKinds,
    title: title,
    proposalCodeNames: proposalCodeNames,
    proposalOnly: proposalOnly,
  ),
);

/// Verified Accounting Settings subset using the existing catalogue and form
/// owner. Local preview choices have no preference, reporting or posting command.
Future<void> showAccountingPreferencesPreview(BuildContext context) {
  final original = settingsForms.firstWhere(
    (form) => form.title == 'Accounting Preferences',
  );
  final fields = <DesignField>[
    original.fields.firstWhere(
      (field) => field.label == 'Financial Year Starts',
    ),
    const DesignField(
      'Tax Year Starts',
      options: ['January', 'Same As Financial Year'],
    ),
    original.fields.firstWhere((field) => field.label == 'Reporting Basis'),
    const DesignField(
      'Date Format',
      options: [
        'MM/DD/YYYY',
        'DD/MM/YYYY',
        'DD-MM-YYYY',
        'YYYY-MM-DD',
        'YYYY/MM/DD',
        'MM-DD-YYYY',
        'DD.MM.YYYY',
        'MM.DD.YYYY',
        'YYYY.MM.DD',
      ],
    ),
    const DesignField(
      'Currency Format',
      options: [
        r'$123,456.00',
        r'123.456,00 $',
        r'123 456,00 $',
        r'$1,23,456.00',
        r'$ 123.456,00',
      ],
    ),
    const DesignField('Duplicate Cheque Warning', toggle: true),
    const DesignField('Duplicate Supplier Bill Warning', toggle: true),
    const DesignField('Duplicate Journal Warning', toggle: true),
  ];
  return AccountingDialog.showFixed<void>(
    context: context,
    contentWidth: AccountingPopoutTokens.normalContentWidth,
    builder: (_) => FrontendFormDialog(
      contentWidth: AccountingPopoutTokens.normalContentWidth,
      previewConfirmationEnabled: false,
      initial: const {
        'Duplicate Cheque Warning': false,
        'Duplicate Supplier Bill Warning': false,
        'Duplicate Journal Warning': false,
      },
      leadingContentBuilder: (context, values, reviewing) => Padding(
        padding: const EdgeInsets.only(bottom: accountingContentInset),
        child: accountingHelperText(
          context,
          'Saving accounting preferences is not connected yet. '
          'Preview choices do not change company settings, reports or posting rules.',
        ),
      ),
      form: DesignForm(
        original.title,
        fields,
        description:
            'Accounting preferences preview. Saving is not connected yet.',
        actionLabel: 'Save Accounting Preferences',
      ),
      reviewInformationRowsBuilder: (values) => [
        for (final field in fields)
          (
            field.label,
            field.toggle
                ? values[field.label] == true
                      ? 'Yes'
                      : 'No'
                : '${values[field.label] ?? ''}'.isEmpty
                ? 'Not Set'
                : '${values[field.label]}',
          ),
      ],
    ),
  );
}

class _AccountingSettingsDialog extends StatefulWidget {
  const _AccountingSettingsDialog({
    this.onAuditLog,
    this.onManageUsers,
    this.workspace,
    this.onOpenRestored,
    this.loadAccountNames,
    this.demo = false,
    this.fields,
    this.setupKinds,
    this.title = 'Settings',
    this.proposalCodeNames,
    this.proposalOnly = false,
  });
  final bool demo;

  /// Explicit proposal boundary; DemoCompany alone still supports live settings.
  final bool proposalOnly;
  final Map<SetupKind, String>? proposalCodeNames;
  final Map<String, Set<String>>? fields;
  final Set<SetupKind>? setupKinds;
  final String title;
  final AccountingWorkspace? workspace;
  final Future<void> Function(String)? onOpenRestored;
  final VoidCallback? onAuditLog;
  final VoidCallback? onManageUsers;
  final Future<List<String>> Function()? loadAccountNames;
  @override
  State<_AccountingSettingsDialog> createState() =>
      _AccountingSettingsDialogState();
}

class _AccountingSettingsDialogState extends State<_AccountingSettingsDialog> {
  final Map<SetupKind, String?> _formats = {};
  bool _loading = true;
  List<String> _accountNames = [];
  final Map<String, Map<String, String>> _accountChoices = {};
  late CompanyPreferences _preferences =
      widget.workspace?.preferences ?? CompanyPreferences.defaults();
  List<DesignForm> get _liveForms => [
    for (final form in liveSettingsForms(_accountChoices))
      if (widget.fields == null || widget.fields!.containsKey(form.title))
        DesignForm(form.title, [
          for (final field in form.fields)
            if (widget.fields == null ||
                widget.fields![form.title]!.contains(field.label))
              field,
        ], actionLabel: form.actionLabel),
  ];
  bool _includesSection(String title) =>
      widget.fields == null || widget.fields!.containsKey(title);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.workspace != null) {
      final accounts = (await widget.workspace!.accounts())
          .map((entry) => entry.account)
          .where(
            (account) =>
                account.status == AccountStatus.active && !account.isParent,
          )
          .toList();
      for (final spec in {
        'Receivables Account': AccountType.asset,
        'Payables Account': AccountType.liability,
        'Income Account': AccountType.income,
        'Sales Tax Liability Account': AccountType.liability,
      }.entries) {
        _accountChoices[spec.key] = {
          for (final account in accounts.where(
            (account) => account.type == spec.value,
          ))
            account.id.value: '${account.code} · ${account.name}',
        };
      }
    }
    if (widget.demo || widget.proposalOnly) {
      _accountNames = ["Demo Bank", "Operating Expenses"];
      setState(() => _loading = false);
      return;
    }
    for (final kind in SetupKind.values.where(
      (kind) => widget.setupKinds == null || widget.setupKinds!.contains(kind),
    )) {
      try {
        _formats[kind] = await namingSettingsChannel.invokeMethod<String>(
          'load',
          {'kind': kind.id},
        );
      } on MissingPluginException {
        _formats[kind] = null;
      } on PlatformException {
        _formats[kind] = null;
      }
    }
    _accountNames = await widget.loadAccountNames?.call() ?? [];
    if (mounted) setState(() => _loading = false);
  }

  Widget _card(BuildContext context, String title, List<Widget> rows) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: AccountingCard.surface(
          context,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: accountingContentPadding,
                child: accountingSectionTitle(context, title),
              ),
              for (final row in rows) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AccountingTheme.of(context).border,
                ),
                row,
              ],
            ],
          ),
        ),
      );

  static const _icons = <String, IconData>{
    'Business Profile': Icons.business_outlined,
    'Accounting Preferences': Icons.account_tree_outlined,
    'Default Accounts': Icons.account_balance_outlined,
    'Sales Preferences': Icons.receipt_outlined,
    'Purchase Preferences': Icons.shopping_bag_outlined,
    'Payment Methods': Icons.payment_outlined,
    'Terms': Icons.calendar_today_outlined,
    'Statements': Icons.receipt_outlined,
    'Messages': Icons.fact_check_outlined,
    'Online Delivery': Icons.fact_check_outlined,
    'Numbering & Document Appearance': Icons.description_outlined,
    'Document & Upload Preferences': Icons.file_upload_outlined,
    'Reminders & Approvals': Icons.notifications_none,
    'Tax Settings': Icons.percent_outlined,
    'E-Invoice Profile': Icons.note_add_outlined,
    'Sign-In & Sessions': Icons.person_outline,
    'Users & Accountant Access': Icons.badge_outlined,
    'Backup & Export Preferences': Icons.download_outlined,
  };

  @override
  Widget build(BuildContext context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.wider,
    title: widget.title,
    description: widget.proposalOnly
        ? 'Design preview · Changes stay in this review session. No company settings, files or account access are changed.'
        : widget.fields == null
        ? 'Manage your business, documents and access.'
        : null,
    titleTextInset: accountingContentInset,
    contentInset: 20,
    backgroundColor: AccountingTheme.of(context).background,
    content: SizedBox(
      width: AccountingPopoutTokens.widerContentWidth,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final group in const <String, List<String>>{
                  'Business & Accounting': [
                    'Business Profile',
                    'Accounting Preferences',
                    'Default Accounts',
                  ],
                  'Transactions': [
                    'Sales Preferences',
                    'Purchase Preferences',
                    'Payment Methods',
                    'Terms',
                    'Statements',
                    'Messages',
                    'Online Delivery',
                  ],
                  'Documents & Automation': [
                    'Numbering & Document Appearance',
                    'Reminders & Approvals',
                  ],
                  'Records & Access': [
                    'Sign-In & Sessions',
                    'Users & Accountant Access',
                    'Backup & Export Preferences',
                  ],
                }.entries.where((group) => group.value.any(_includesSection)))
                  _card(context, group.key, [
                    for (final title in group.value.where(_includesSection))
                      AccountingSettingsSection(
                        key: ValueKey('settings-editor-$title'),
                        title: title,
                        icon: _icons[title],
                        inCard: true,
                        child: title == 'Sign-In & Sessions'
                            ? ListenableBuilder(
                                listenable: GoogleAccountSession.shared,
                                builder: (context, _) {
                                  final google = GoogleAccountSession.shared;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        google.account?.email ??
                                            'No Google account connected.',
                                        style:
                                            AccountingTypography.controlValue(
                                              context,
                                            ),
                                      ),
                                      const SizedBox(height: 20),
                                      if (google.error != null)
                                        Text(google.error!),
                                      AccountingButton.primary(
                                        context,
                                        key: const ValueKey(
                                          'settings-google-account',
                                        ),
                                        onPressed:
                                            widget.proposalOnly || google.busy
                                            ? null
                                            : google.account == null
                                            ? google.signIn
                                            : google.signOut,
                                        child: Text(
                                          google.busy
                                              ? 'Please Wait…'
                                              : google.account == null
                                              ? 'Sign In With Google'
                                              : 'Sign Out',
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              )
                            : title == 'Accounting Preferences'
                            ? AccountingSettingsActionBody(
                                description: 'Configure financial periods and report presentation.',
                                actionLabel: 'Manage Accounting Preferences',
                                actionKey: const ValueKey(
                                  'settings-manage-accounting-preferences',
                                ),
                                onPressed: () =>
                                    showAccountingPreferencesPreview(context),
                              )
                            : title == 'Payment Methods'
                            ? AccountingSettingsActionBody(
                                description: 'Manage reusable payment methods.',
                                actionLabel: 'Manage Payment Methods',
                                actionKey: const ValueKey(
                                  'settings-manage-payment-methods',
                                ),
                                onPressed: () =>
                                    showPaymentMethodDirectoryPreview(
                                      context,
                                      demo: widget.demo,
                                      currencyCode:
                                          widget.workspace?.identity.currency ??
                                          'MYR',
                                      workspace: widget.workspace,
                                    ),
                              )
                            : title == 'Terms'
                            ? AccountingSettingsActionBody(
                                description: 'Manage named payment terms.',
                                actionLabel: 'Manage Terms',
                                actionKey: const ValueKey(
                                  'settings-manage-terms',
                                ),
                                onPressed: () =>
                                    showPaymentTermsDirectoryPreview(
                                      context,
                                      demo: widget.demo,
                                      workspace: widget.workspace,
                                    ),
                              )
                            : title == 'Statements'
                            ? AccountingSettingsActionBody(
                                description: 'Configure transaction detail and the ageing table.',
                                actionLabel: 'Manage Statements',
                                actionKey: const ValueKey(
                                  'settings-manage-statements',
                                ),
                                onPressed: () =>
                                    showStatementSettingsPreview(context),
                              )
                            : title == 'Messages' || title == 'Online Delivery'
                            ? AccountingSettingsActionBody(
                                description: title == 'Messages'
                                    ? 'Configure email greetings and messages.'
                                    : 'Configure sales email content and PDF attachments.',
                                actionLabel: title == 'Messages'
                                    ? 'Manage Messages'
                                    : 'Manage Online Delivery',
                                actionKey: ValueKey(
                                  title == 'Messages'
                                      ? 'settings-manage-messages'
                                      : 'settings-manage-online-delivery',
                                ),
                                onPressed: () => title == 'Messages'
                                    ? showSalesMessagesPreview(context)
                                    : showOnlineDeliveryPreview(context),
                              )
                            : title == 'Users & Accountant Access'
                            ? AccountingSettingsActionBody(
                                description: 'Manage invitations, approvals and roles on the Users page.',
                                actionLabel: 'Manage Users',
                                actionKey: const ValueKey(
                                  'settings-manage-users',
                                ),
                                onPressed:
                                    widget.proposalOnly ||
                                        widget.onManageUsers == null
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        widget.onManageUsers!();
                                      },
                              )
                            : widget.workspace == null
                            ? accountingHelperText(
                                context,
                                'Open a company workspace to configure its settings.',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FrontendFormDialog(
                                    form: _liveForms.firstWhere(
                                      (form) => form.title == title,
                                    ),
                                    initial: _preferences.values(title),
                                    onCommit:
                                        widget.proposalOnly ||
                                            widget.workspace == null
                                        ? null
                                        : (values) async {
                                            final next = _preferences.change(
                                              title,
                                              values,
                                            );
                                            widget.workspace!.savePreferences(
                                              next,
                                            );
                                            _preferences =
                                                widget.workspace!.preferences;
                                          },
                                    onPreview:
                                        [
                                          'Business Profile',
                                          'Sales Preferences',
                                          'Numbering & Document Appearance',
                                        ].contains(title)
                                        ? (values) async {
                                            try {
                                              await showInvoicePreferencesPreview(
                                                context,
                                                widget.workspace!,
                                                _preferences.change(
                                                  title,
                                                  values,
                                                ),
                                              );
                                            } catch (error) {
                                              if (context.mounted) {
                                                await showDialog<void>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AccountingDialog.alert(
                                                        context,
                                                        widthFamily:
                                                            AccountingPopoutWidthFamily
                                                                .dialog,
                                                        title: 'Preview Unavailable',
                                                        content: Text('$error'),
                                                        actions: [],
                                                      ),
                                                );
                                              }
                                            }
                                          }
                                        : title == 'Purchase Preferences'
                                        ? (values) async {
                                            await showDialog<void>(
                                              context: context,
                                              builder: (previewContext) =>
                                                  RecordExpensePage(
                                                    preferences: _preferences
                                                        .change(title, values),
                                                    readOnly: true,
                                                    includeTopSafeArea: false,
                                                    onCancel: () =>
                                                        Navigator.pop(
                                                          previewContext,
                                                        ),
                                                    defaultCurrencyCode: widget
                                                        .workspace!
                                                        .identity
                                                        .currency,
                                                  ),
                                            );
                                          }
                                        : null,
                                    embeddedContentBuilder:
                                        title ==
                                                'Backup & Export Preferences' &&
                                            !widget.proposalOnly
                                        ? (content, fields, fieldWidth) =>
                                              WorkspaceBackupControls(
                                                preferenceFields: fields,
                                                preferenceFieldsWidth:
                                                    fieldWidth,
                                                leadingContent: fields == null
                                                    ? content
                                                    : null,
                                                backup: WorkspaceBackup(
                                                  widget.workspace!,
                                                ),
                                                onOpenRestored:
                                                    widget.onOpenRestored ??
                                                    (_) async {},
                                              )
                                        : null,
                                    accountOptions: _accountNames,
                                    embedded: true,
                                    fieldLayoutOwner:
                                        AccountingFieldLayoutOwner.sharedPopup,
                                    contentWidth:
                                        (MediaQuery.sizeOf(context).width - 160)
                                            .clamp(160.0, 680.0),
                                  ),
                                ],
                              ),
                      ),
                  ]),
                if (widget.setupKinds == null || widget.setupKinds!.isNotEmpty)
                  _card(context, 'File Setup', [
                    for (final kind in SetupKind.values.where(
                      (kind) =>
                          widget.setupKinds == null ||
                          widget.setupKinds!.contains(kind),
                    ))
                      AccountingSettingsSection(
                        key: ValueKey('settings-section-${kind.id}'),
                        title: kind.label,
                        icon: switch (kind) {
                          SetupKind.expense => Icons.receipt_long,
                          SetupKind.invoice => Icons.note_add_outlined,
                          SetupKind.voucher =>
                            Icons.assignment_turned_in_outlined,
                          SetupKind.claims => Icons.checklist_outlined,
                        },
                        inCard: true,
                        child: NamingSetupDialog(
                          demo:
                              widget.demo ||
                              widget.proposalOnly ||
                              widget.proposalCodeNames != null,
                          proposalCodeName: widget.proposalCodeNames?[kind],
                          kind: kind,
                          saved: _formats[kind],
                          embedded: true,
                        ),
                      ),
                  ]),
                if (widget.onAuditLog != null && !widget.proposalOnly)
                  AccountingCard.surface(
                    context,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      shape: const RoundedRectangleBorder(),
                      horizontalTitleGap: accountingContentInset,
                      minLeadingWidth: 0,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      leading: const AccountingSettingsIcon(
                        Icons.history_outlined,
                      ),
                      title: const Text('Audit Log'),
                      subtitle: const Text(
                        'Review recorded accounting changes.',
                      ),
                      trailing: const AccountingSettingsIcon(
                        Icons.chevron_right,
                      ),
                      onTap: widget.onAuditLog,
                    ),
                  ),
              ],
            ),
    ),
    actions: [],
  );
}

class NamingSetupDialog extends StatefulWidget {
  final bool demo;
  const NamingSetupDialog({
    super.key,
    this.saved,
    this.demo = false,
    this.kind = SetupKind.expense,
    this.embedded = false,
    this.setupRequired = false,
    this.proposalCodeName,
    this.proposalTitle,
  }) : assert(proposalCodeName == null || demo);
  final String? saved;
  final SetupKind kind;
  final bool embedded;
  final bool setupRequired;
  // Isolated design preview; no document-code persistence is implemented.
  final String? proposalCodeName;
  final String? proposalTitle;
  @override
  State<NamingSetupDialog> createState() => _NamingSetupDialogState();
}

class _NamingSetupDialogState extends State<NamingSetupDialog> {
  List<NamingBlock> _blocks = [NamingBlock()];
  DateTime _date = DateTime.now();
  String _category = 'GAS';
  late final TextEditingController _codeName = TextEditingController(
    text: widget.proposalCodeName ?? '',
  );
  String? get _proposalCode =>
      widget.proposalCodeName == null ? null : _codeName.text;
  late final TextEditingController _previewDate = TextEditingController(
    text: _dateLabel,
  );
  String get _dateLabel =>
      '${_date.day.toString().padLeft(2, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.year}';

  @override
  void dispose() {
    _previewDate.dispose();
    _codeName.dispose();
    super.dispose();
  }

  String? _error;
  bool _saving = false;
  bool _saved = false;
  String? _folder;
  bool _choosingFolder = false;

  Future<void> _loadFolder() async {
    if (widget.demo) {
      final kindName = switch (widget.kind) {
        SetupKind.expense => 'Expenses',
        SetupKind.invoice => 'Invoices',
        SetupKind.voucher => 'Payment Vouchers',
        SetupKind.claims => 'Claims',
      };
      setState(() => _folder = '$demoFolderRoot/$kindName');
      return;
    }
    try {
      final folder = await namingSettingsChannel.invokeMethod<String>(
        'loadFolder',
        {'kind': widget.kind.id},
      );
      if (mounted && folder != null) setState(() => _folder = folder);
    } on MissingPluginException {
      /* Native folder picking is macOS-only. */
    } on PlatformException {
      if (mounted) {
        setState(() => _error = 'Please choose your destination folder again.');
      }
    }
  }

  Future<void> _chooseFolder() async {
    if (widget.demo) return;
    setState(() {
      _choosingFolder = true;
      _error = null;
    });
    try {
      final folder = await namingSettingsChannel.invokeMethod<String>(
        'chooseFolder',
        {'kind': widget.kind.id},
      );
      if (folder != null && mounted) setState(() => _folder = folder);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the folder picker. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _choosingFolder = false);
    }
  }

  final GlobalKey _sequenceKey = GlobalKey();
  NamingBlock? _dragging;
  List<NamingBlock>? _originalOrder;
  bool _dragInside = true;
  List<Rect> _slots = [];

  void _dragMove(DragUpdateDetails details) {
    final box = _sequenceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _dragging == null) return;
    final point = box.globalToLocal(details.globalPosition);
    _dragInside = (Offset.zero & box.size).inflate(12).contains(point);
    if (!_dragInside) return;
    if (_slots.isEmpty) return;
    var target = 0;
    var distance = double.infinity;
    for (var i = 0; i < _slots.length; i++) {
      final d = (_slots[i].center - point).distanceSquared;
      if (d < distance) {
        distance = d;
        target = i;
      }
    }
    final from = _blocks.indexOf(_dragging!);
    if (from != target) {
      setState(() {
        final block = _blocks.removeAt(from);
        _blocks.insert(target, block);
      });
    }
  }

  void _finishDrag() {
    if (!mounted) return;
    setState(() {
      if (!_dragInside && _originalOrder != null) _blocks = _originalOrder!;
      _dragging = null;
      _originalOrder = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFolder();
    if (widget.proposalCodeName != null && widget.saved == null) {
      _blocks = [NamingBlock(type: NamingValue.codeName)];
    }
    if (widget.saved != null) {
      try {
        final list = jsonDecode(widget.saved!) as List<dynamic>;
        if (list.isNotEmpty) {
          _blocks = list
              .map((v) => NamingBlock.fromJson(v as Map<String, dynamic>))
              .toList();
        }
      } on Object {
        _error = 'The saved format could not be read. Build a new format to replace it.';
      }
    }
  }

  Future<void> _save() async {
    if (widget.proposalCodeName != null &&
        (_codeName.text.trim().isEmpty ||
            RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(_codeName.text) ||
            _codeName.text.trim().endsWith('.'))) {
      setState(() => _error = 'Enter a filename-safe Code Name.');
      return;
    }
    if (widget.demo) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Demo setup reviewed; no files or settings were written.",
          ),
        ),
      );
      return;
    }
    if (_blocks.any(
      (b) =>
          b.type == null ||
          (b.type == NamingValue.separator &&
              !const ['.', '-', '_'].contains(b.text)) ||
          ((b.type == NamingValue.custom || b.type == NamingValue.separator) &&
              b.text.isEmpty),
    )) {
      setState(() => _error = 'Choose a type and complete each value first.');
      return;
    }
    final preview = namingPreview(
      _blocks,
      _date,
      _category,
      codeName: _proposalCode,
    );
    if (preview.trim().isEmpty ||
        preview.endsWith('.') ||
        RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(preview)) {
      setState(
        () => _error =
            'Use filename-safe text, without slashes or a trailing dot.',
      );
      return;
    }
    if (_folder == null) {
      setState(() => _error = 'Choose a destination folder first.');
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await namingSettingsChannel.invokeMethod<String>('commitSetup', {
        'kind': widget.kind.id,
        'folderPath': _folder,
        'year': _date.year,
        'month': _date.month,
        'format': jsonEncode(_blocks.map((b) => b.toJson()).toList()),
      });
      if (mounted) {
        if (widget.embedded) {
          setState(() => _saved = true);
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformException
              ? (error.message ?? 'Could not save the setup.')
              : 'Could not save the format. Your edits are still here; please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final preview = namingPreview(
      _blocks,
      _date,
      _category,
      codeName: _proposalCode,
    );
    final contentWidth = math.min(
      680.0,
      math.max(200.0, MediaQuery.sizeOf(context).width - 128),
    );
    final folderField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountingFieldLabel(context, 'Save Location', alignToField: true),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: AccountingButton.outline(
            context,
            key: const ValueKey('naming-folder-picker'),
            leadingIcon: Icons.folder_open_outlined,
            onPressed: _choosingFolder || _saving ? null : _chooseFolder,
            child: Text(
              _folder ?? 'Choose Folder',
              // Selected path is regular field text, but its colour belongs
              // to the button's idle/hover/disabled state.
              style: const TextStyle(
                fontSize: accountingControlFontSize,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
    final content = SizedBox(
      width: contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.setupRequired) ...[
            AccountingAlert.build(
              context,
              key: const ValueKey('naming-setup-required-alert'),
              title: 'Setup Required',
              description: 'Set up a destination folder and naming format before saving. Your edit will stay open until setup is complete.',
              tone: AccountingAlertTone.warning,
              bottomGap: accountingContentInset,
            ),
          ],
          if (widget.proposalCodeName != null)
            Row(
              key: const ValueKey('naming-code-location-row'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Code Name *',
                        alignToField: true,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const ValueKey('naming-code-name'),
                        controller: _codeName,
                        style: AccountingTypography.value(context),
                        decoration: accountingInputDecoration(context),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: accountingContentInset),
                Expanded(flex: 7, child: folderField),
              ],
            )
          else
            folderField,
          const SizedBox(height: 20),
          accountingFieldLabel(context, 'Filename Format', alignToField: true),
          Builder(
            builder: (context) {
              final widths = [
                for (final block in _blocks)
                  _namingBlockWidth(context, block, codeName: _proposalCode),
              ];
              _slots = [];
              var x = 0.0;
              var y = 0.0;
              for (final width in widths) {
                if (x > 0 && x + width + 8 > contentWidth) {
                  x = 0;
                  y += 64;
                }
                _slots.add(Rect.fromLTWH(x, y, width, 52));
                x += width + 12;
              }
              if (x + 44 > contentWidth) {
                x = 0;
                y += 64;
              }
              // Preserve the add glyph's centre while making its frame 44².
              final plusLeft = math.max(0.0, x - 10);
              final plusTop = y + 8;
              final count = _blocks.length;
              return SizedBox(
                key: _sequenceKey,
                height: y + 64,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedPositioned(
                        key: ObjectKey(_blocks[i]),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        left: _slots[i].left,
                        top: _slots[i].top,
                        height: 52,
                        // Text growth is immediate; animate only the token's
                        // position during reordering/reflow. Animating width
                        // made normal typing scroll before the frame caught up.
                        child: SizedBox(
                          width: widths[i] + 8,
                          child: Stack(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 100),
                                opacity: _dragging == _blocks[i] ? 0 : 1,
                                child: _block(i),
                              ),
                              if (_dragging == _blocks[i])
                                Positioned(
                                  left: 0,
                                  top: 8,
                                  width: widths[i],
                                  height: 44,
                                  child: IgnorePointer(
                                    child: AccountingDashedBorder(
                                      color: tokens.ring,
                                      backgroundColor: tokens.muted,
                                      child: const SizedBox.expand(
                                        key: ValueKey(
                                          'naming-drag-placeholder',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      left: plusLeft,
                      top: plusTop,
                      child: IconButton(
                        key: const ValueKey('naming-add'),
                        tooltip: 'Add Value',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          maximumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _dragging != null
                            ? null
                            : () => setState(() => _blocks.add(NamingBlock())),
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          accountingFieldLabel(context, 'Filename Preview', alignToField: true),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('naming-preview-frame'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: tokens.card,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              preview.isEmpty ? 'Your filename will appear here' : preview,
              key: const ValueKey('naming-preview'),
              style: AccountingTypography.value(context).copyWith(
                color: preview.isEmpty
                    ? tokens.mutedForeground
                    : tokens.foreground,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountingFieldLabel(
                      context,
                      'Preview Date',
                      alignToField: true,
                      guidance: 'Use sample values to check your format before saving.',
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('naming-date'),
                      controller: _previewDate,
                      readOnly: true,
                      style: AccountingTypography.value(context),
                      decoration: accountingInputDecoration(context).copyWith(
                        constraints: const BoxConstraints.tightFor(height: 44),
                        suffixIcon: AccountingMinorHoverRegion(
                          builder: (context, highlighted) => SizedBox.square(
                            dimension: 44,
                            child: Center(
                              child: Transform.translate(
                                offset: const Offset(-4.8, 0),
                                child: AccountingMinorHoverHalo(
                                  highlighted: highlighted,
                                  child: AccountingIcon(
                                    Icons.calendar_today_outlined,
                                    size: 13.6,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      onTap: () async {
                        final date = await showAudytDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(9999),
                          helpText: accountingDatePickerHelpText(context, null),
                        );
                        if (date != null && mounted) {
                          setState(() {
                            _date = date;
                            _previewDate.text = _dateLabel;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountingFieldLabel(
                      context,
                      'Preview Category',
                      alignToField: true,
                      guidance: 'Use sample values to check your format before saving.',
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('naming-category'),
                      initialValue: _category,
                      style: AccountingTypography.value(context),
                      decoration:
                          accountingInputDecoration(
                            context,
                            hintText: 'Category Code',
                          ).copyWith(
                            suffixIcon: const SizedBox(width: 44, height: 44),
                            constraints: const BoxConstraints.tightFor(
                              height: 44,
                            ),
                          ),
                      inputFormatters: [_UppercaseFormatter()],
                      onChanged: (value) => setState(() => _category = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: AccountingTypography.helper(context)
                    .copyWith(color: tokens.destructive),
              ),
            ),
        ],
      ),
    );
    final actions = [
      if (!widget.embedded)
        AccountingButton.outline(
          context,
          key: const ValueKey('naming-cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      AccountingButton.primary(
        context,
        key: const ValueKey('naming-save'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save Setup'),
      ),
    ];
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_saved)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: accountingHelperText(context, 'Saved'),
                ),
              ...actions,
            ],
          ),
        ],
      );
    }
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.wider,
      title: widget.proposalTitle ?? widget.kind.label,
      formFooter: true,
      description: 'Build your filename one value at a time.',
      content: content,
      actions: actions,
    );
  }

  Widget _block(int index) {
    final block = _blocks[index];
    return _NamingValueControl(
      key: ObjectKey(block),
      block: block,
      index: index,
      proposalCodeName: _proposalCode,
      onChanged: () => setState(() {}),
      onDragStart: () => setState(() {
        _originalOrder = List.of(_blocks);
        _dragging = block;
        _dragInside = true;
      }),
      onDragUpdate: _dragMove,
      onDragEnd: _finishDrag,
      onRemove: () => setState(() {
        if (index != 0) _blocks.remove(block);
      }),
    );
  }
}

double _namingBlockWidth(
  BuildContext context,
  NamingBlock block, {
  String? codeName,
}) {
  final text = block.type == NamingValue.custom
      ? (block.text.isEmpty ? 'Custom Text' : block.text)
      : block.type == NamingValue.separator
      ? block.text
      : block.type == NamingValue.codeName
      ? (codeName?.trim().toUpperCase().isNotEmpty == true
            ? codeName!.trim().toUpperCase()
            : 'Code Name')
      : block.type?.label ?? 'Select Type';
  if (block.type == NamingValue.custom) {
    // Reuse the Amount field's value growth and input insets. Only the
    // existing selector affordance is added to its single-line input frame.
    return AccountingTransactionGridTokens.numericWidth(context, 'Amount', [
          text,
        ], minimumText: text) +
        accountingSelectorLabelGap +
        accountingSelectorChevronHoverExtent +
        accountingSelectorTriggerRightInset -
        accountingContentInset;
  }
  return accountingSelectorMinimumWidth(context, [
    text,
  ], textStyle: AccountingTypography.value(context));
}

double _namingControlWidth(BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  double longest = 0;
  for (final label in [
    'Select Type',
    ...NamingValue.values.map((v) => v.label),
  ]) {
    painter.text = TextSpan(
      text: label,
      style: AccountingTypography.value(context),
    );
    painter.layout();
    longest = math.max(longest, painter.width);
  }
  painter.dispose();
  // Popup inset (8), option padding (24), checkmark and its gap (20).
  return longest + 52;
}

class _NamingValueControl extends StatefulWidget {
  const _NamingValueControl({
    super.key,
    required this.block,
    required this.index,
    required this.onChanged,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.proposalCodeName,
  });
  final String? proposalCodeName;
  final NamingBlock block;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  @override
  State<_NamingValueControl> createState() => _NamingValueControlState();
}

class _NamingValueControlState extends State<_NamingValueControl> {
  late final TextEditingController _text = TextEditingController(
    text: widget.block.text,
  );
  final MenuController _menu = MenuController();
  final FocusNode _focus = FocusNode();
  bool _hover = false;
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _editableControl(BuildContext context, MenuController menu) {
    final arrowWidth =
        accountingSelectorChevronHoverExtent +
        accountingSelectorTriggerRightInset;
    return SizedBox(
      key: ValueKey('naming-block-frame-${widget.index}'),
      height: accountingControlHeight,
      child: Stack(
        children: [
          TextField(
            key: ValueKey('naming-inline-${widget.index}'),
            controller: _text,
            focusNode: _focus,
            textAlign: TextAlign.left,
            textAlignVertical: TextAlignVertical.center,
            maxLines: 1,
            style: AccountingTypography.controlValue(context),
            inputFormatters: [_UppercaseFormatter()],
            decoration:
                accountingSingleLineInputDecoration(
                  context,
                  hintText: 'Custom Text',
                ).copyWith(
                  suffixIconConstraints: BoxConstraints.tightFor(
                    width: arrowWidth,
                    height: accountingControlHeight,
                  ),
                  suffixIcon: SizedBox(width: arrowWidth),
                ),
            onChanged: (value) {
              widget.block.text = value;
              widget.onChanged();
            },
          ),
          Positioned(
            right: accountingSelectorTriggerRightInset,
            top: 0,
            bottom: 0,
            width: accountingSelectorChevronHoverExtent,
            child: Opacity(
              opacity: _hover || _focus.hasFocus || menu.isOpen ? 1 : 0,
              child: IconButton(
                key: ValueKey('naming-arrow-${widget.index}'),
                tooltip: 'Change Value Type',
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  overlayColor: Colors.transparent,
                ).copyWith(splashFactory: NoSplash.splashFactory),
                padding: EdgeInsets.zero,
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const AccountingSelectorChevron(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final style = AccountingTypography.value(context);
    final typeWidth = _namingControlWidth(context);
    final separator = widget.block.type == NamingValue.separator;
    final width = _namingBlockWidth(
      context,
      widget.block,
      codeName: widget.proposalCodeName,
    );
    final editable = widget.block.type == NamingValue.custom;
    final control = Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: SizedBox(
          width: width,
          height: 44,
          child: accountingSelectionMenuScrollbarHidden(
            context,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AccountingMenuAnchor(
                  menuWidth: typeWidth,
                  controller: _menu,
                  style: accountingSelectorMenuStyle(context, typeWidth, 360),
                  menuChildren: [
                    for (final value in NamingValue.values.where(
                      (value) =>
                          value != NamingValue.codeName ||
                          widget.proposalCodeName != null,
                    ))
                      MenuItemButton(
                        key: ValueKey('naming-option-${value.name}'),
                        style: accountingSelectorOptionStyle(
                          context,
                          selected: widget.block.type == value,
                        ),
                        onPressed: () {
                          setState(() {
                            widget.block.type = value;
                            widget.block.text = value == NamingValue.separator
                                ? '-'
                                : '';
                            _text.clear();
                          });
                          widget.onChanged();
                          if (value == NamingValue.custom) {
                            _focus.requestFocus();
                          }
                        },
                        child: SizedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: Text(
                                  value.label,
                                  style: style,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  builder: (context, controller, child) => editable
                      ? _editableControl(context, controller)
                      : Container(
                          key: ValueKey('naming-block-frame-${widget.index}'),
                          decoration: BoxDecoration(
                            color: tokens.card,
                            border: Border.all(color: tokens.input),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: accountingContentInset),
                              Expanded(
                                child: separator
                                    ? AccountingMenuAnchor(
                                        menuWidth: accountingMenuContentWidth(
                                          context,
                                          [
                                            for (final symbol in const [
                                              '.',
                                              '-',
                                              '_',
                                            ])
                                              (
                                                label: symbol,
                                                adornmentWidth: 0.0,
                                              ),
                                          ],
                                        ),
                                        menuChildren: [
                                          for (final symbol in const [
                                            '.',
                                            '-',
                                            '_',
                                          ])
                                            MenuItemButton(
                                              style:
                                                  accountingSelectorOptionStyle(
                                                    context,
                                                    selected:
                                                        widget.block.text ==
                                                        symbol,
                                                  ),
                                              key: ValueKey(
                                                'separator-option-$symbol',
                                              ),
                                              onPressed: () {
                                                setState(
                                                  () => widget.block.text =
                                                      symbol,
                                                );
                                                widget.onChanged();
                                              },
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(symbol, style: style),
                                                ],
                                              ),
                                            ),
                                        ],
                                        builder: (context, choices, child) =>
                                            InkWell(
                                              key: ValueKey(
                                                'naming-separator-${widget.index}',
                                              ),
                                              onTap: () => choices.isOpen
                                                  ? choices.close()
                                                  : choices.open(),
                                              child: SizedBox(
                                                height: 42,
                                                child: Center(
                                                  child: Text(
                                                    const [
                                                          '.',
                                                          '-',
                                                          '_',
                                                        ].contains(
                                                          widget.block.text,
                                                        )
                                                        ? widget.block.text
                                                        : '…',
                                                    style: style,
                                                  ),
                                                ),
                                              ),
                                            ),
                                      )
                                    : InkWell(
                                        key: ValueKey(
                                          'naming-type-${widget.index}',
                                        ),
                                        onTap: () => controller.isOpen
                                            ? controller.close()
                                            : controller.open(),
                                        child: SizedBox(
                                          height: 42,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              widget.block.type ==
                                                      NamingValue.codeName
                                                  ? (widget.proposalCodeName!
                                                            .trim()
                                                            .isEmpty
                                                        ? 'Code Name'
                                                        : widget
                                                              .proposalCodeName!
                                                              .trim()
                                                              .toUpperCase())
                                                  : widget.block.type?.label ??
                                                        'Select Type',
                                              style: style,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: accountingSelectorLabelGap),
                              Opacity(
                                opacity:
                                    !editable ||
                                        _hover ||
                                        _focus.hasFocus ||
                                        controller.isOpen
                                    ? 1
                                    : 0,
                                child: IconButton(
                                  key: ValueKey('naming-arrow-${widget.index}'),
                                  tooltip: 'Change Value Type',
                                  style:
                                      IconButton.styleFrom(
                                        minimumSize: const Size(
                                          accountingSelectorChevronHoverExtent,
                                          42,
                                        ),
                                        maximumSize: const Size(
                                          accountingSelectorChevronHoverExtent,
                                          42,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        overlayColor: Colors.transparent,
                                      ).copyWith(
                                        splashFactory: NoSplash.splashFactory,
                                      ),
                                  onPressed: () => controller.isOpen
                                      ? controller.close()
                                      : controller.open(),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: accountingSelectorChevronHoverExtent,
                                    height: 42,
                                  ),
                                  icon: const AccountingSelectorChevron(),
                                ),
                              ),
                              const SizedBox(
                                width: accountingSelectorTriggerRightInset,
                              ),
                            ],
                          ),
                        ),
                ),
                if (widget.index > 0)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Material(
                      color: tokens.card,
                      shape: CircleBorder(
                        side: BorderSide(color: tokens.border),
                      ),
                      child: IconButton(
                        tooltip: 'Remove value ${widget.index + 1}',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(20, 20),
                          maximumSize: const Size(20, 20),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onRemove,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 20,
                          height: 20,
                        ),
                        icon: Icon(
                          Icons.close,
                          size: 12,
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Draggable<NamingBlock>(
      data: widget.block,
      onDragStarted: () {
        _menu.close();
        widget.onDragStart();
      },
      onDragUpdate: widget.onDragUpdate,
      onDragEnd: (_) => widget.onDragEnd(),
      dragAnchorStrategy: (draggable, context, position) {
        final local = (context.findRenderObject()! as RenderBox).globalToLocal(
          position,
        );
        return Offset(local.dx, local.dy - 8);
      },
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          key: const ValueKey('naming-drag-feedback'),
          width: width,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: width,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.card,
                  border: Border.all(color: tokens.input),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: accountingContentInset),
                    Expanded(
                      child: Text(
                        widget.block.text.isNotEmpty
                            ? widget.block.text
                            : widget.block.type?.label ?? 'Select Type',
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                    const SizedBox(width: accountingSelectorLabelGap),
                    const AccountingSelectorChevron(),
                    const SizedBox(width: accountingSelectorTriggerRightInset),
                  ],
                ),
              ),
              if (widget.index > 0)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: tokens.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.border),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: tokens.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: control),
    );
  }
}

class _UppercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
