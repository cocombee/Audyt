import '../domain/expense_claim_source.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/frontend_review.dart'
    show showAccountingPaymentMethodPreview;

import 'widgets/payee_autocomplete_menu.dart';

import 'package:audyt/app/accounting_description_field.dart';

import 'dart:math' as math;
import 'dart:convert';

import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';

import '../domain/company_preferences.dart';
import '../domain/company_tax_rate.dart';
import '../application/accounting_workspace.dart';
import '../../../../app/live_settings_catalog.dart';
import '../../../../app/sidebar_settings_icon.dart';

import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';

import '../../../../app/asset_purchase_fields.dart';
import 'expense_recurrence_dialog.dart';
import '../domain/recurrence_rule.dart';
import '../domain/expense_draft.dart';
export '../domain/expense_draft.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../core/documents/receipt_document.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/dates/accounting_date.dart';
import 'payment_account_dialog.dart';
import '../domain/expense_category.dart';
import '../domain/payee.dart';
import '../domain/payment_account.dart';
import 'receipt_attachment_picker.dart';
import 'receipt_review_dialog.dart';
import 'receipt_review_queue.dart';
import 'widgets/accounting_formatters.dart';
import 'widgets/accounting_layout.dart';

export 'receipt_attachment_picker.dart';
export 'receipt_review_dialog.dart';
export 'receipt_review_queue.dart';

/// Identity returned by the existing inline creator. Customers remain in their
/// maintained master; they must never be copied into the local Payee store.
final class AccountingPayeeCreation {
  const AccountingPayeeCreation.payee(Payee value)
    : payee = value,
      customerId = null;
  const AccountingPayeeCreation.customer(String id)
    : payee = null,
      customerId = id;
  final Payee? payee;
  final String? customerId;
}

/// The existing Expense inline owner, shared by other payee callers.
/// Employee creation remains exclusive to registration. Only callers with a
/// verified Customer scope supply the canonical Customer creation callback.
Future<AccountingPayeeCreation?> showAccountingPayeeDialog(
  BuildContext context, {
  required String Function() newId,
  Future<String?> Function(String initialName)? onAddCustomer,
}) async {
  final nameController = TextEditingController();
  var type = PayeeType.other.name;
  var openingCustomer = false;
  var closing = false;
  Future<void> close() async {
    if (closing || openingCustomer) return;
    closing = true;
    try {
      final changed =
          nameController.text.isNotEmpty || type != PayeeType.other.name;
      final discard =
          !changed || await AccountingDialog.confirmDiscardChanges(context);
      if (context.mounted && discard) Navigator.of(context).pop();
    } finally {
      closing = false;
    }
  }

  final route = DialogRoute<AccountingPayeeCreation>(
    context: context,
    builder: (dialogContext) {
      String? error;
      return StatefulBuilder(
        builder: (context, setDialogState) => CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () => close(),
          },
          child: PopScope<AccountingPayeeCreation>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close();
            },
            child: AccountingDialog.alert(
              dialogContext,
              widthFamily: AccountingPopoutWidthFamily.normal,
              title: 'Add Payee',
              onClose: close,
              closeKey: const ValueKey('payee-close'),
              formFooter: true,
              content: SizedBox(
                width: (MediaQuery.sizeOf(context).width - 96).clamp(
                  180.0,
                  360.0,
                ),
                child: AccountingOrdinaryFields(
                  fields: [
                    AccountingOrdinaryFieldSlot(
                      label: 'Payee Name',
                      contentSample: 'Payee Name',
                      minimumRowFraction: .5,
                      builder: (_) => Column(
                        key: const ValueKey('payee-name-field-group'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accountingFieldLabel(
                            context,
                            'Payee Name *',
                            key: const ValueKey('payee-name-label'),
                            alignToField: true,
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          TextField(
                            key: const ValueKey('payee-name-field'),
                            controller: nameController,
                            enabled: !openingCustomer,
                            autofocus: true,
                            onChanged: (value) {
                              if (error != null && value.trim().isNotEmpty) {
                                setDialogState(() => error = null);
                              }
                            },
                            decoration: accountingInputDecoration(
                              context,
                              errorText: error,
                              hintText: 'Payee Name',
                            ),
                          ),
                        ],
                      ),
                    ),
                    AccountingOrdinaryFieldSlot(
                      label: 'Type',
                      choices: [
                        'Select Type',
                        if (onAddCustomer != null) 'Customer',
                        for (final value in PayeeType.values)
                          if (value.canQuickCreate) value.label,
                      ],
                      builder: (width) => Column(
                        key: const ValueKey('payee-type-field-group'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accountingFieldLabel(
                            context,
                            'Type',
                            alignToField: true,
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          AccountingSelector<String>(
                            assignedWidth: width,
                            enabled: !openingCustomer,
                            options: <AccountingSelectorOption<String>>[
                              if (onAddCustomer != null)
                                const AccountingSelectorOption(
                                  value: 'customer',
                                  label: 'Customer',
                                ),
                              for (final value in PayeeType.values)
                                if (value.canQuickCreate)
                                  AccountingSelectorOption<String>(
                                    value: value.name,
                                    label: value.label,
                                  ),
                            ],
                            value: type,
                            onChanged: (value) async {
                              final previousType = type;
                              if (value != 'customer') {
                                setDialogState(
                                  () => type = value ?? PayeeType.other.name,
                                );
                                return;
                              }
                              setDialogState(() {
                                type = 'customer';
                                openingCustomer = true;
                              });
                              try {
                                final id = await onAddCustomer!(
                                  nameController.text.trim(),
                                );
                                if (!dialogContext.mounted) return;
                                if (id != null) {
                                  Navigator.of(
                                    dialogContext,
                                  ).pop(AccountingPayeeCreation.customer(id));
                                }
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(dialogContext)
                                      .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Customer form could not be opened. Try again.',
                                          ),
                                        ),
                                      );
                                }
                              } finally {
                                openingCustomer = false;
                                if (dialogContext.mounted) {
                                  setDialogState(() => type = previousType);
                                }
                              }
                            },
                            hintText: 'Select Type',
                            controlKey: const ValueKey('payee-type-control'),
                            triggerKey: const ValueKey('payee-type-field'),
                            menuKey: const ValueKey('payee-type-menu'),
                            semanticsLabel: 'Payee type',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                AccountingButton.ghost(
                  context,
                  key: null,
                  onPressed: openingCustomer ? null : close,
                  child: const Text('Cancel'),
                ),
                AccountingButton.primary(
                  context,
                  key: const ValueKey('payee-create-action'),
                  onPressed: openingCustomer
                      ? null
                      : () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            setDialogState(
                              () => error = 'Payee name is required.',
                            );
                            return;
                          }
                          Navigator.of(dialogContext).pop(
                            AccountingPayeeCreation.payee(
                              Payee(
                                id: newId(),
                                name: name,
                                type: PayeeType.values.byName(type),
                              ),
                            ),
                          );
                        },
                  child: const Text('Add Payee'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  nameController.dispose();
  return result;
}

enum AccountingReferenceStatus { loading, ready, unavailable }

typedef RecordExpenseSaver = Future<void> Function(RecordExpenseDraft draft);
typedef ExpenseAttachmentPicker = Future<String?> Function(
  BuildContext context,
);

/// Explicit command context for the existing Expense body. The caller owns
/// registered claimant identity, revision checks and Claim persistence.
/// A claimant display widget alone never changes an Expense into a Claim.
class RecordExpenseClaimContext {
  const RecordExpenseClaimContext({
    required this.claimantField,
    this.saveDraft,
    this.submitForReview,
    this.submissionErrors,
    this.showSettingsShortcut = true,
    this.personallyPaid = true,
    this.unavailableReason,
  });
  final Widget claimantField;
  final RecordExpenseSaver? saveDraft;
  final RecordExpenseSaver? submitForReview;
  final List<String> Function(RecordExpenseDraft)? submissionErrors;
  final bool showSettingsShortcut;
  final bool personallyPaid;

  /// A disconnected design may be displayed, but cannot create or submit data.
  final String? unavailableReason;

  bool get commandsUnavailable => unavailableReason != null;
}

class RecordExpensePage extends StatefulWidget {
  const RecordExpensePage({
    super.key,
    this.currencyCode,
    this.preferences,
    this.settingsWorkspace,
    this.recurringSuggestion,
    this.savedDraft,
    this.initialStatementDraft,
    this.readOnly = false,
    this.recordActions = const [],
    this.defaultCurrencyCode = 'MYR',
    this.categories,
    this.expenseCategories,
    this.paymentAccounts,
    this.accounts,
    this.onPaymentAccountSave,
    this.payees = PayeeCatalog.demo,
    this.payeeStore,
    this.initialDimensions = '',
    this.initialItemOrSplitDetails = '',
    this.referenceStatus = AccountingReferenceStatus.ready,
    this.onSave,
    this.onSaved,
    this.onSavedReview,
    this.onCancel,
    this.onAttachmentsPick,
    this.onAttachmentPick,
    this.includeTopSafeArea = true,
    this.claimantField,
    this.claimContext,
    this.employeePayeeSearch,
  });

  static const defaultExpenseCategories = <String>[];
  static const defaultPaymentAccounts = <String>[];

  /// Claim layout proposal: extend the actual Expense body with one field.
  /// Financial validation and persistence retain the Expense owner until the
  /// separate claim submission contract is connected.
  final Widget? claimantField;
  final RecordExpenseClaimContext? claimContext;
  final Future<List<Payee>> Function(String)? employeePayeeSearch;

  final CompanyPreferences? preferences;
  final AccountingWorkspace? settingsWorkspace;
  final String? currencyCode;
  final RecordExpenseDraft? recurringSuggestion;
  final RecordExpenseDraft? savedDraft;
  final RecordExpenseDraft? initialStatementDraft;
  final bool readOnly;
  final List<Widget> recordActions;
  final String defaultCurrencyCode;
  final List<String>? categories;
  final List<ExpenseCategory>? expenseCategories;
  final List<String>? paymentAccounts;
  final List<PaymentAccount>? accounts;
  final void Function(PaymentAccount)? onPaymentAccountSave;
  final List<Payee> payees;
  final PayeeStore? payeeStore;
  final String initialDimensions;
  final String initialItemOrSplitDetails;
  final AccountingReferenceStatus referenceStatus;
  final RecordExpenseSaver? onSave;
  final VoidCallback? onSaved;
  final Future<void> Function()? onSavedReview;
  final VoidCallback? onCancel;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  @Deprecated('Use onAttachmentsPick so the selected bytes can be processed.')
  final ExpenseAttachmentPicker? onAttachmentPick;
  final bool includeTopSafeArea;

  @override
  State<RecordExpensePage> createState() => _RecordExpensePageState();
}

class _ExpenseLineInput {
  _ExpenseLineInput({ExpenseDraftLine? saved})
    : id = saved?.id ?? EntityId.random().value {
    category = saved?.category;
    tax = saved?.tax;
    taxSnapshot = saved?.taxSnapshot;
    description.text = saved?.description ?? '';
    amount.text = saved?.amount ?? '';
    quantity.text = saved?.quantity ?? '1';
    rate.text = saved?.rate ?? '';
    retainedQuantity = saved?.quantity != null;
    retainedRate = saved?.rate != null;
    adjustment = saved?.pricingAdjustment;
  }
  final String id;
  String? category;
  String? tax;
  CompanyTaxRate? taxSnapshot;
  String? adjustment;
  bool retainedQuantity = false;
  bool retainedRate = false;
  final description = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final rate = TextEditingController();
  void dispose() {
    description.dispose();
    amount.dispose();
    quantity.dispose();
    rate.dispose();
  }
}

class _RecordExpensePageState extends State<RecordExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _editingFocus = FocusScopeNode();
  late final String _openingInput;
  bool _closePromptOpen = false;
  late final String _submissionId;
  final Map<String, Map<String, dynamic>> _receiptHistories = {};
  final _lines = [_ExpenseLineInput()];
  TextEditingController get _amountController => _lines.first.amount;
  final _dateController = TextEditingController();
  final _dimensionsController = TextEditingController();
  String _retainedItemOrSplitDetails = '';
  final _documentNumber = TextEditingController();
  final _notesController = TextEditingController();

  final _amountFocusNode = FocusNode();
  final _dateFocusNode = FocusNode();
  final _paymentAccountFocusNode = FocusNode();
  final _categoryFocusNode = FocusNode();
  final _taxFocusNode = FocusNode();
  final _customerFocusNode = FocusNode();
  final _dimensionsFocusNode = FocusNode();
  final _itemOrSplitFocusNode = FocusNode();
  final _notesFocusNode = FocusNode();
  final _receiptFocusNode = FocusNode();

  final _pipeline = const ReceiptDocumentPipeline();
  final ReceiptArtifactStore _artifactStore = InMemoryReceiptArtifactStore();
  late List<PaymentAccount> _accounts;
  late final PayeeStore _payeeStore;
  late List<ExpenseCategory> _categoryCatalog;
  final _payeeFieldAnchor = GlobalKey();
  TextEditingController? _payeeAutocompleteController;
  FocusNode? _payeeAutocompleteFocusNode;
  String? _payeeHoveredId;

  PaymentAccount? _paymentAccount;
  String? get _category => _lines.first.category;
  set _category(String? value) => _lines.first.category = value;
  String? get _tax => _lines.first.tax;
  set _tax(String? value) => _lines.first.tax = value;
  String? _taxMode = 'Exclusive';
  String _customer = '';
  String _payeeValue = '';
  bool _billable = false;
  RecurrenceRule? _recurrence;
  bool _recurrenceEnabled = false;
  String _recurrencePeriod = 'Monthly';
  List<ReceiptAttachment> _attachments = <ReceiptAttachment>[];
  String? _attachmentMessage;
  String? _saveError;
  bool _isSaving = false;
  bool _retryClaimSubmit = false;
  bool get _isClaim => widget.claimContext != null;
  bool _showValidationSummary = false;
  late String _currencyCode;
  CurrencyPresentation? _currencyPresentation;
  String? _currencyError;
  ReceiptReviewQueue? _receiptReviewQueue;
  bool _reviewActive = false;
  bool _isDragOver = false;
  bool _advancedExpanded = false;
  double _contentWidth = 728;
  late final _widthOwner = 'expense-${identityHashCode(this)}';
  bool _ownsWidth = false;
  double? _requestedWidth;
  CompanyPreferences get _preferences =>
      widget.settingsWorkspace?.preferences ??
      widget.preferences ??
      CompanyPreferences.defaults();
  bool get _showRate =>
      _preferences.enabled('Purchase Preferences', 'Show Rate') ||
      _lines.any((line) => line.retainedRate);
  bool get _showQuantity =>
      _showRate ||
      _preferences.enabled('Purchase Preferences', 'Show Quantity') ||
      _lines.any((line) => line.retainedQuantity);

  @override
  void initState() {
    super.initState();
    final claim = widget.claimContext;
    if (claim != null &&
        claim.commandsUnavailable &&
        (claim.unavailableReason!.trim().isEmpty ||
            claim.saveDraft != null ||
            claim.submitForReview != null ||
            claim.submissionErrors != null)) {
      throw ArgumentError(
        'Unavailable Claim commands must not retain callbacks.',
      );
    }
    if (claim != null &&
        (widget.claimantField != null ||
            widget.onSave != null ||
            widget.onSavedReview != null ||
            widget.recurringSuggestion != null ||
            widget.initialStatementDraft != null ||
            widget.savedDraft?.claimSource != null ||
            (!widget.readOnly &&
                !claim.commandsUnavailable &&
                (claim.saveDraft == null ||
                    claim.submitForReview == null ||
                    claim.submissionErrors == null)))) {
      throw ArgumentError('Claim commands require their own complete context.');
    }
    if (claim != null &&
        widget.savedDraft != null &&
        (widget.savedDraft!.paymentAccountId != null ||
            widget.savedDraft!.paymentAccount.isNotEmpty)) {
      throw ArgumentError('A Claim cannot retain a company payment account.');
    }
    if (widget.savedDraft != null && widget.recurringSuggestion != null) {
      throw ArgumentError(
        'Saved intake and recurring suggestion are distinct modes.',
      );
    }
    _submissionId = widget.savedDraft?.submissionId ?? EntityId.random().value;
    _dimensionsController.text = widget.initialDimensions;
    _retainedItemOrSplitDetails = widget.initialItemOrSplitDetails;
    _lines.first.description.text = widget.initialItemOrSplitDetails;
    _advancedExpanded = widget.initialDimensions.trim().isNotEmpty;
    _dateController.text = formatAccountingInputDate(DateTime.now());
    _currencyCode =
        (widget.savedDraft?.currencyCode ??
                widget.currencyCode ??
                widget.defaultCurrencyCode)
            .trim();
    _initializeCurrency();
    _payeeStore = widget.payeeStore ?? PayeeStore(payees: widget.payees);
    _categoryCatalog = widget.expenseCategories ?? _legacyCategories();
    _accounts = widget.accounts != null
        ? List<PaymentAccount>.from(widget.accounts!)
        : _legacyAccounts();
    final suggestion =
        widget.savedDraft ??
        widget.recurringSuggestion ??
        widget.initialStatementDraft;
    if (suggestion == null) {
      _tax = '0';
    } else {
      _taxMode = suggestion.taxMode;
    }
    if (suggestion != null) {
      _amountController.text = formatAccountingMoneyInputText(
        suggestion.amount,
        _currencyPresentation?.currency.fractionDigits ?? 2,
      );
      _dateController.text = suggestion.date;
      _payeeValue = suggestion.payee;
      _customer = suggestion.customer;
      _billable = suggestion.billable;
      _dimensionsController.text = suggestion.dimensions;
      _retainedItemOrSplitDetails = suggestion.itemOrSplitDetails;
      _lines.first.description.text = suggestion.itemOrSplitDetails;
      _notesController.text = suggestion.notes;
      _advancedExpanded =
          suggestion.dimensions.isNotEmpty ||
          suggestion.customer.isNotEmpty ||
          suggestion.billable;
      if (_categoryCatalog.any((c) => c.displayName == suggestion.category)) {
        _category = suggestion.category;
      }
      if (widget.initialStatementDraft != null) {
        for (final account in _accounts) {
          if (account.id == suggestion.paymentAccountId &&
              account.currency.code == suggestion.currencyCode) {
            _paymentAccount = account;
          }
        }
      }
      if (widget.savedDraft != null) {
        final restored = RecordExpenseDraft.fromJson(suggestion.toJson());
        _attachments = List.of(restored.attachments);
        _recurrence = restored.recurrence;
        _recurrenceEnabled = _recurrence != null;
        if (_recurrence != null) {
          _recurrencePeriod = _periodForRule(_recurrence!);
        }
        _tax = restored.tax;
        _category = restored.category;
        for (final account in _accounts) {
          if (account.id == restored.paymentAccountId &&
              account.currency.code == restored.currencyCode) {
            _paymentAccount = account;
          }
        }
        for (final snapshot in restored.reviewSnapshots) {
          final item = ReceiptReviewItem.fromJson(snapshot);
          try {
            _receiptHistories[item.attachment.originalId] = snapshot;
          } finally {
            item.dispose();
          }
        }
      }
      _documentNumber.text = suggestion.documentNumber;
      if (suggestion.lines.isNotEmpty) {
        for (final line in _lines) {
          line.dispose();
        }
        _lines.clear();
        _lines.addAll(
          suggestion.lines.map((line) => _ExpenseLineInput(saved: line)),
        );
        if (widget.recurringSuggestion != null) {
          for (final line in _lines) {
            line.tax = null;
          }
        }
      }
      if (_showRate) {
        for (final line in _lines) {
          if (line.rate.text.isEmpty && line.amount.text.isNotEmpty) {
            _initializeRateFromAmount(line);
          }
        }
      }
      // Each occurrence requires a fresh payment selection, tax review and
      // receipt evidence. Never inherit the prior occurrence's receipt history.
    }
    _openingInput = _inputSnapshot();
  }

  List<ExpenseCategory> _legacyCategories() {
    final names = widget.categories;
    if (names == null) {
      return ExpenseCategoryCatalog.seeded;
    }
    return <ExpenseCategory>[
      for (var index = 0; index < names.length; index++)
        ExpenseCategory.create(
          id: EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c${(index + 1).toRadixString(16).padLeft(4, '0')}',
          ),
          code: 'legacy-${index + 1}',
          displayName: names[index],
          normalAccountingGroup: 'Imported categories',
          taxTreatment: TaxTreatment.conditional,
          evidenceProfile: 'ordinary-expense',
        ),
    ];
  }

  List<PaymentAccount> _legacyAccounts() {
    final names = widget.paymentAccounts ?? const <String>[];
    final currency = _currencyPresentation?.code ?? _currencyCode;
    final accounts = <PaymentAccount>[];
    for (var index = 0; index < names.length; index++) {
      try {
        accounts.add(
          PaymentAccount.create(
            id: 'injected-account-${index + 1}',
            name: names[index],
            type: PaymentAccountType.other,
            currencyCode: currency,
          ),
        );
      } on Object {
        // An invalid settings currency keeps the account unavailable rather than
        // silently changing the account's currency.
      }
    }
    return accounts;
  }

  void _initializeCurrency() {
    try {
      _currencyPresentation = CurrencyPresentation.fromCode(_currencyCode);
      _currencyCode = _currencyPresentation!.code;
      _currencyError = null;
    } on FormatException {
      _currencyPresentation = null;
      _currencyError =
          'Invalid currency "$_currencyCode". Enter a valid three-letter code.';
    }
  }

  @override
  void didUpdateWidget(covariant RecordExpensePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCurrency = oldWidget.currencyCode ?? oldWidget.defaultCurrencyCode;
    final newCurrency = widget.currencyCode ?? widget.defaultCurrencyCode;
    if (oldCurrency != newCurrency) {
      _currencyCode = newCurrency.trim();
      _initializeCurrency();
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _documentNumber.dispose();
    _editingFocus.dispose();
    if (_ownsWidth) AccountingDialog.releaseFixedWidth(_widthOwner);
    _dateController.dispose();
    _dimensionsController.dispose();
    _notesController.dispose();
    _amountFocusNode.dispose();
    _dateFocusNode.dispose();
    _paymentAccountFocusNode.dispose();
    _categoryFocusNode.dispose();
    _taxFocusNode.dispose();
    _customerFocusNode.dispose();
    _dimensionsFocusNode.dispose();
    _itemOrSplitFocusNode.dispose();
    _notesFocusNode.dispose();
    _receiptFocusNode.dispose();
    _payeeAutocompleteFocusNode?.removeListener(
      _handlePayeeAutocompleteFocusChanged,
    );
    super.dispose();
  }

  String _inputSnapshot() => jsonEncode([
    _documentNumber.text,
    _dateController.text,
    _notesController.text,
    _dimensionsController.text,
    _customer,
    _billable,
    _payeeAutocompleteController?.text ?? _payeeValue,
    _paymentAccount?.id,
    _currencyCode,
    _taxMode,
    _recurrenceEnabled,
    _recurrencePeriod,
    _recurrence?.toJson(),
    _assetPurchase,
    [
      for (final line in _lines)
        [
          line.id,
          line.category,
          line.tax,
          line.description.text,
          line.amount.text,
          line.quantity.text,
          line.rate.text,
          line.adjustment,
        ],
    ],
    [
      for (final file in _attachments)
        [
          file.originalId,
          file.filename,
          file.originalSha256,
          file.derivativeId,
          file.derivativeSha256,
          file.pdfSha256,
        ],
    ],
  ]);

  void _finishClose() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleClose() async {
    if (_isSaving || _reviewActive || _closePromptOpen) return;
    if (widget.readOnly || _inputSnapshot() == _openingInput) {
      _finishClose();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('expense-discard-close'),
        keepEditingKey: const ValueKey('expense-keep-editing'),
        discardKey: const ValueKey('expense-discard-changes'),
      );
      if (mounted) {
        if (discard) {
          _finishClose();
        } else {
          _editingFocus.requestFocus();
        }
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = _requiredContentWidth(context);
    _contentWidth = math.max(_contentWidth, width);
    if (!widget.includeTopSafeArea) {
      if (_requestedWidth != _contentWidth) {
        _requestedWidth = _contentWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final owns = await AccountingDialog.acquireFixedWidth(
            _widthOwner,
            _contentWidth,
            contentInset: AccountingPopoutTokens.contentInset,
          );
          if (!mounted) {
            if (owns) await AccountingDialog.releaseFixedWidth(_widthOwner);
            return;
          }
          _ownsWidth = owns;
        });
      }
      return FocusScope(
        node: _editingFocus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _handleClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _handleClose();
          },
          child: AccountingDialog.alert(
            context,
            widthFamily: AccountingPopoutWidthFamily.custom,
            key: const ValueKey('expense-live-dialog'),
            title: _isClaim ? 'Claim' : 'Expense',
            onClose: _handleClose,
            closeKey: const ValueKey('record-expense-cancel'),
            canClose: !_isSaving,
            fixedContentWidth: _contentWidth,
            contentScrollKey: const ValueKey('accounting-main-scroll'),
            formFooter: !widget.readOnly || widget.recordActions.isNotEmpty,
            content: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _contentWidth,
                child: _buildFormBody(context, _contentWidth),
              ),
            ),
            actions: widget.readOnly && widget.recordActions.isEmpty
                ? const []
                : [
                    SizedBox(
                      width: _contentWidth,
                      child: _buildCardFooter(context, surface: false),
                    ),
                  ],
          ),
        ),
      );
    }
    return AccountingPageShell(
      includeTopSafeArea: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountingPageHeader(
            routeLabel: _isClaim ? 'Claims' : 'Expenses',
            title: _isClaim ? 'Claim' : 'Expense',
            titleKey: 'page-title-record-expense',
            description: _isClaim
                ? 'Submit a personally paid expense for review.'
                : 'Record an expense and retain its receipt evidence.',
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          AccountingCard.surface(
            context,
            key: const ValueKey('record-expense-form-card'),
            child: Column(
              children: [
                Padding(
                  padding: accountingContentPadding,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(_contentWidth, constraints.maxWidth),
                        child: _buildFormBody(
                          context,
                          math.max(_contentWidth, constraints.maxWidth),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!widget.readOnly || widget.recordActions.isNotEmpty)
                  _buildCardFooter(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormBody(BuildContext context, double width) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currencyError != null)
          AccountingAlert.build(
            context,
            title: 'Currency Needs Review',
            description: _currencyError!,
            destructive: true,
          ),
        IgnorePointer(
          ignoring: widget.readOnly,
          child: ExcludeFocus(
            excluding: widget.readOnly,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.claimContext != null ||
                    widget.claimantField != null ||
                    widget.savedDraft?.claimSource != null) ...[
                  widget.claimContext?.claimantField ??
                      widget.claimantField ??
                      _buildClaimantSnapshot(context),
                  const SizedBox(height: accountingContentInset),
                ],
                _responsivePair(
                  _buildPayeeField(context),
                  _buildTextField(
                    key: const ValueKey('expense-document-number'),
                    controller: _documentNumber,
                    focusNode: null,
                    label: 'Document Number',
                  ),
                ),
                const SizedBox(height: accountingContentInset),
                _responsivePair(
                  _buildDateField(context),
                  _buildPaymentAccountField(context),
                ),
                const SizedBox(height: accountingContentInset),
                if (!_isClaim) ...[
                  _responsivePair(_buildPaymentMethodField(context), null),
                  const SizedBox(height: accountingFieldLabelGap),
                  accountingHelperText(
                    context,
                    'Payment-method choices and saving are not connected yet.',
                  ),
                  const SizedBox(height: accountingContentInset),
                ],
                _buildCompactHeader(context, width),
                const SizedBox(height: accountingContentInset),
                if (!widget.readOnly && _unresolvedTaxRows.isNotEmpty) ...[
                  AccountingAlert.build(
                    context,
                    key: const ValueKey('expense-tax-selection-warning'),
                    title: 'Tax Selection Required',
                    description:
                        'Select the applicable tax code for ${_unresolvedTaxRows.length == 1 ? 'row' : 'rows'} ${_unresolvedTaxRows.join(', ')}.',
                    tone: AccountingAlertTone.warning,
                  ),
                  const SizedBox(height: accountingContentInset),
                ],
                accountingFieldLabel(
                  context,
                  'Items',
                  key: const ValueKey('expense-items-label'),
                ),
                const SizedBox(height: accountingFieldLabelGap),
                Divider(
                  key: const ValueKey('expense-items-divider'),
                  height: 1,
                  color: AccountingTheme.of(context).border,
                ),
                const SizedBox(height: accountingContentInset),
                _buildLineGrid(context, width),
                const SizedBox(height: accountingContentInset),
                Divider(height: 1, color: AccountingTheme.of(context).border),
                const SizedBox(height: accountingContentInset),
                _buildMemoTotals(context),
                const SizedBox(height: accountingContentInset),
                _buildAdvancedAccountingDetails(context),
                const SizedBox(height: accountingContentInset),
              ],
            ),
          ),
        ),
        _buildAttachmentField(context),
      ],
    ),
  );

  Widget _buildClaimantSnapshot(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(
        context,
        'Claimant',
        alignToField: true,
        guidance: 'Retained from the original Claim submission.',
      ),
      const SizedBox(height: accountingFieldLabelGap),
      InputDecorator(
        key: const ValueKey('expense-approved-claimant'),
        decoration: accountingSingleLineInputDecoration(context),
        child: accountingValueText(
          context,
          widget.savedDraft!.claimSource!.claimantName.isEmpty
              ? 'Not Recorded'
              : widget.savedDraft!.claimSource!.claimantName,
        ),
      ),
    ],
  );

  Widget _buildPaymentMethodField(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingFieldLabel(context, 'Payment Method', alignToField: true),
        const SizedBox(height: accountingFieldLabelGap),
        AccountingSelector<String>(
          controlKey: const ValueKey('expense-field-payment-method'),
          assignedWidth: constraints.maxWidth,
          hintText: 'Select Payment Method',
          value: null,
          enabled: !_isSaving && !widget.readOnly,
          options: [
            AccountingSelectorOption(
              value: '__add_payment_method__',
              label: 'Add Payment Method',
              key: const ValueKey('expense-add-payment-method'),
              leading: const AccountingAddIcon(),
              leadingWidth: AccountingDismissIcon.canvasSize,
              onPressed: () => showAccountingPaymentMethodPreview(context),
            ),
          ],
          onChanged: (_) {},
        ),
      ],
    ),
  );

  Widget _buildDateField(BuildContext context) => _buildTextField(
    key: const ValueKey('expense-field-date'),
    controller: _dateController,
    focusNode: _dateFocusNode,
    label: 'Date',
    required: true,
    keyboardType: TextInputType.number,
    inputFormatters: const [DateInputFormatter()],
    compactDate: true,
    validator: _requiredDate,
    onChanged: (_) => setState(() => _saveError = null),
    suffixIcon: accountingCalendarButton(
      context,
      controller: _dateController,
      label: 'Date',
      enabled: !_isSaving && !widget.readOnly,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose expense date',
      onPicked: () => setState(() {}),
    ),
  );

  Widget _buildCompactHeader(BuildContext context, double width) {
    Widget field(String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountingFieldLabel(context, label, alignToField: true),
        const SizedBox(height: accountingFieldLabelGap),
        control,
      ],
    );
    final slots = [
      AccountingOrdinaryFieldSlot(
        label: 'Currency',
        contentSample: _currencyPresentation?.amountSymbol ?? _currencyCode,
        builder: (_) => field(
          'Currency',
          InputDecorator(
            decoration: accountingSingleLineInputDecoration(context),
            child: accountingValueText(
              context,
              _currencyPresentation?.amountSymbol ?? _currencyCode,
            ),
          ),
        ),
      ),
      AccountingOrdinaryFieldSlot(
        label: 'Amounts Are',
        choices: [
          'Tax Exclusive',
          'Tax Inclusive',
          if (_taxMode == null) 'Saved Basis · Review',
          if (_taxMode == ExpenseClaimSource.mixedBasis)
            ExpenseClaimSource.mixedBasis,
        ],
        builder: (allocatedWidth) => field(
          'Amounts Are',
          AccountingSelector<String>(
            assignedWidth: allocatedWidth,
            triggerKey: const ValueKey('expense-tax-treatment'),
            hintText: 'Amounts Are',
            value: _taxMode ?? '__saved_basis__',
            options: [
              if (_taxMode == ExpenseClaimSource.mixedBasis)
                const AccountingSelectorOption(
                  value: ExpenseClaimSource.mixedBasis,
                  label: ExpenseClaimSource.mixedBasis,
                  enabled: false,
                ),
              if (_taxMode == null)
                const AccountingSelectorOption(
                  value: '__saved_basis__',
                  label: 'Saved Basis · Review',
                  enabled: false,
                ),
              const AccountingSelectorOption(
                value: 'Exclusive',
                label: 'Tax Exclusive',
              ),
              const AccountingSelectorOption(
                value: 'Inclusive',
                label: 'Tax Inclusive',
              ),
            ],
            enabled: !_isSaving && !widget.readOnly,
            onChanged: (value) => setState(() {
              _taxMode = value;
              _saveError = null;
            }),
          ),
        ),
      ),
      AccountingOrdinaryFieldSlot(
        label: 'Make Recurring',
        choices: const ['Yes', 'No'],
        builder: (allocatedWidth) => field(
          'Make Recurring',
          AccountingSelector<bool>(
            assignedWidth: allocatedWidth,
            triggerKey: const ValueKey('expense-recurring-control'),
            hintText: 'Make Recurring',
            value: _recurrenceEnabled,
            options: const [
              AccountingSelectorOption(value: false, label: 'No'),
              AccountingSelectorOption(value: true, label: 'Yes'),
            ],
            enabled:
                !_isSaving && !widget.readOnly && widget.savedDraft == null,
            onChanged: (value) =>
                setState(() => _recurrenceEnabled = value ?? false),
          ),
        ),
      ),
    ];
    final taxWidth = math.max(
      (width - accountingContentInset * 2) / 3,
      _taxHeaderMinimumWidth(context),
    );
    final sideWidth = (width - accountingContentInset * 2 - taxWidth) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.includeTopSafeArea)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: sideWidth, child: slots[0].builder(sideWidth)),
              const SizedBox(width: accountingContentInset),
              SizedBox(width: taxWidth, child: slots[1].builder(taxWidth)),
              const SizedBox(width: accountingContentInset),
              SizedBox(width: sideWidth, child: slots[2].builder(sideWidth)),
            ],
          )
        else
          AccountingOrdinaryFields(fields: slots),
        if (_recurrenceEnabled) ...[
          const SizedBox(height: accountingContentInset),
          _buildRecurrenceFields(context, showToggle: false),
        ],
      ],
    );
  }

  double _taxHeaderMinimumWidth(BuildContext context) =>
      accountingSelectorMinimumWidth(context, [
        'Tax Exclusive',
        'Tax Inclusive',
        if (_taxMode == null) 'Saved Basis · Review',
        if (_taxMode == ExpenseClaimSource.mixedBasis)
          ExpenseClaimSource.mixedBasis,
      ]);

  String? get _moneyZeroHint => widget.readOnly || _currencyPresentation == null
      ? null
      : formatAccountingInputAmount(Money.zero(_currencyPresentation!.code));

  Map<String, double> _lineWidths(BuildContext context) => {
    'Category': AccountingTransactionGridTokens.selectionWidth(
      context,
      'Select Category',
      title: 'Category',
      selectedLabels: _lines.map((line) => line.category),
    ),
    'Tax': AccountingTransactionGridTokens.selectionWidth(
      context,
      'Select Tax',
      title: 'Tax',
      selectedLabels: _lines.map(
        (line) => _taxChoiceResolved(line) ? _taxLabels(line)[line.tax] : null,
      ),
    ),
    if (_showQuantity)
      'Quantity': AccountingTransactionGridTokens.numericWidth(
        context,
        'Quantity',
        _lines.map((line) => line.quantity.text),
        title: 'Quantity',
      ),
    if (_showRate)
      'Rate': AccountingTransactionGridTokens.numericWidth(
        context,
        'Rate',
        _lines.map(
          (line) =>
              line.rate.text.isEmpty ? _moneyZeroHint ?? '' : line.rate.text,
        ),
        title: 'Rate (${_currencyPresentation?.amountSymbol ?? _currencyCode})',
      ),
    'Amount': AccountingTransactionGridTokens.numericWidth(
      context,
      'Amount',
      _lines.map(
        (line) =>
            line.amount.text.isEmpty ? _moneyZeroHint ?? '' : line.amount.text,
      ),
      title: 'Amount (${_currencyPresentation?.amountSymbol ?? _currencyCode})',
    ),
  };
  double _lineBoundaryWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${_lines.length}',
        style: AccountingTypography.controlValue(context),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width =
        painter.width +
        AccountingTransactionGridTokens.numberGap(context, _lines.length) +
        (widget.readOnly ? 0 : accountingContentInset + 20);
    painter.dispose();
    return width;
  }

  double _requiredContentWidth(BuildContext context) {
    final widths = _lineWidths(context);
    final optional = [
      if (_showQuantity) widths['Quantity']!,
      if (_showRate) widths['Rate']!,
    ];
    final baseline =
        728 +
        optional.fold<double>(
          0.0,
          (a, b) => a + b + AccountingTransactionGridTokens.peerGap,
        );
    return math.max(
      math.max(
        baseline,
        _taxHeaderMinimumWidth(context) + 320 + accountingContentInset * 2,
      ),
      widths.values.fold(0.0, (a, b) => a + b) +
          AccountingTransactionGridTokens.descriptionMinimumWidth +
          widths.length * AccountingTransactionGridTokens.peerGap +
          _lineBoundaryWidth(context),
    );
  }

  Widget _buildLineGrid(BuildContext context, double width) {
    final widths = _lineWidths(context);
    final descriptionWidth =
        width -
        widths.values.fold(0.0, (a, b) => a + b) -
        widths.length * AccountingTransactionGridTokens.peerGap -
        _lineBoundaryWidth(context);
    final currency = _currencyPresentation?.amountSymbol ?? _currencyCode;
    Widget numeric(int index, String field) {
      final line = _lines[index];
      final controller = switch (field) {
        'Quantity' => line.quantity,
        'Rate' => line.rate,
        _ => line.amount,
      };
      return TextFormField(
        key: ValueKey(
          index == 0 && field == 'Amount'
              ? 'expense-field-amount'
              : 'expense-line-$index-${field.toLowerCase()}',
        ),
        controller: controller,
        focusNode: index == 0 && field == 'Amount' ? _amountFocusNode : null,
        maxLines: 1,
        textAlign: field == 'Quantity' ? TextAlign.center : TextAlign.right,
        style: AccountingTypography.controlValue(context),
        enabled: !_isSaving && !widget.readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: field == 'Quantity'
            ? const []
            : [
                AccountingMoneyInputFormatter(
                  _currencyPresentation?.currency.fractionDigits ?? 2,
                ),
              ],
        decoration: accountingSingleLineInputDecoration(
          context,
          hintText: field == 'Quantity' ? null : _moneyZeroHint,
        ),
        validator: field == 'Amount'
            ? _requiredAmount
            : (value) {
                try {
                  if (field == 'Quantity') {
                    SalesQuantity.fromDecimal(value ?? '');
                  } else if (Money.fromDecimal(
                    (value ?? '').replaceAll(',', ''),
                    _currencyCode,
                  ).isNegative) {
                    return 'Rate cannot be negative.';
                  }
                } on Object {
                  return 'Enter a valid ${field.toLowerCase()}.';
                }
                return null;
              },
        onChanged: (_) => _reprice(line, field),
      );
    }

    return AccountingTransactionGrid(
      key: const ValueKey('expense-transaction-lines'),
      rowCount: _lines.length,
      showActions: !widget.readOnly,
      rowKey: (row) => ValueKey('expense-line-${_lines[row].id}'),
      columns: [
        AccountingTransactionColumn(
          title: 'Category',
          width: widths['Category']!,
          cell: (row, _) => _categoryControl(context, row),
        ),
        if (_showItems)
          AccountingTransactionColumn(
            title: 'Description',
            width: descriptionWidth,
            cell: (row, _) => AccountingDescriptionField(
              onEscape: widget.includeTopSafeArea ? null : _handleClose,
              role: AccountingDescriptionRole.transactionItem,
              key: ValueKey(
                row == 0
                    ? 'expense-field-item-or-split'
                    : 'expense-line-$row-description',
              ),
              controller: _lines[row].description,
              fixedLines: null,
              focusNode: row == 0 ? _itemOrSplitFocusNode : null,
              enabled: !_isSaving && !widget.readOnly,
              decoration: accountingSingleLineInputDecoration(context),
            ),
          ),
        if (_showQuantity)
          AccountingTransactionColumn(
            title: 'Quantity',
            width: widths['Quantity']!,
            naturalHeaderWidth: true,
            headerAlignment: Alignment.centerRight,
            cell: (row, _) => numeric(row, 'Quantity'),
          ),
        if (_showRate)
          AccountingTransactionColumn(
            title: 'Rate ($currency)',
            width: widths['Rate']!,
            naturalHeaderWidth: true,
            headerAlignment: Alignment.centerRight,
            cell: (row, _) => numeric(row, 'Rate'),
          ),
        AccountingTransactionColumn(
          title: 'Tax',
          width: widths['Tax']!,
          cell: (row, _) => _taxControl(context, _lines[row]),
        ),
        AccountingTransactionColumn(
          title: 'Amount ($currency)',
          width: widths['Amount']!,
          naturalHeaderWidth: true,
          headerAlignment: Alignment.centerRight,
          cell: (row, _) => numeric(row, 'Amount'),
        ),
      ],
      action: (row) => widget.readOnly
          ? const SizedBox.shrink()
          : (row == 0 ? accountingCompactAdd : accountingCompactRemove)(
              context,
              key: ValueKey(
                row == 0 ? 'expense-add-line' : 'expense-remove-line-$row',
              ),
              onPressed: _isSaving
                  ? null
                  : () => setState(() {
                      if (row == 0) {
                        _lines.add(_ExpenseLineInput()..tax = '0');
                      } else {
                        _lines.removeAt(row).dispose();
                        if (_taxMode == ExpenseClaimSource.mixedBasis) {
                          final bases = _lines.map(_lineBasis).toSet();
                          if (bases.length == 1 && !bases.contains(null)) {
                            _taxMode = bases.single;
                          }
                        }
                      }
                    }),
            ),
    );
  }

  bool _retainsCategory(_ExpenseLineInput line) =>
      line.category?.trim().isNotEmpty == true &&
      (widget.savedDraft?.lines.any(
            (saved) => saved.id == line.id && saved.category == line.category,
          ) ??
          false);

  Widget _categoryControl(BuildContext context, int row) {
    final line = _lines[row];
    return KeyedSubtree(
      key:
          widget.referenceStatus == AccountingReferenceStatus.loading &&
              row == 0
          ? const ValueKey('expense-category-loading')
          : null,
      child: FormField<String>(
        validator: (_) {
          if (_retainsCategory(line)) return null;
          if (widget.referenceStatus != AccountingReferenceStatus.ready ||
              _categoryCatalog.isEmpty) {
            return 'No categories are available.';
          }
          if (!_categoryCatalog.any(
            (category) => category.displayName == line.category,
          )) {
            return line.category == null
                ? 'Category is required.'
                : 'Selected category is no longer available.';
          }
          return null;
        },
        builder: (state) => AccountingSelector<String>(
          assignedWidth: double.infinity,
          value: line.category,
          hintText: 'Select Category',
          triggerKey: ValueKey(
            row == 0 ? 'expense-field-category' : 'expense-line-$row-category',
          ),
          controlKey: ValueKey(
            row == 0
                ? 'expense-category-control'
                : 'expense-category-control-$row',
          ),
          menuKey: const ValueKey('expense-category-menu'),
          searchable: true,
          searchKey: const ValueKey('expense-category-search'),
          searchHintText: 'Search categories',
          enabled: _categoryEnabled && !widget.readOnly,
          focusNode: row == 0 ? _categoryFocusNode : null,
          errorText: state.errorText,
          helperText:
              widget.referenceStatus == AccountingReferenceStatus.loading
              ? 'Loading categories…'
              : (!_categoryEnabled && !_isSaving
                    ? 'No categories are available.'
                    : null),
          options: [
            if (line.category != null &&
                !_categoryCatalog.any(
                  (category) => category.displayName == line.category,
                ))
              AccountingSelectorOption(
                value: line.category!,
                label: line.category!,
                enabled: false,
              ),
            for (final category in _categoryCatalog)
              AccountingSelectorOption(
                value: category.displayName,
                label: category.displayName,
                group: category.normalAccountingGroup,
                key: ValueKey('expense-category-option-${category.code}'),
              ),
          ],
          onChanged: (value) {
            setState(() => line.category = value);
            state.didChange(value);
          },
        ),
      ),
    );
  }

  Map<String, String> _taxLabels(_ExpenseLineInput line) {
    final date =
        parseAccountingInputDate(_dateController.text) ?? DateTime.now();
    final labels = <String, String>{
      '0': 'No Tax',
      for (final code
          in widget.settingsWorkspace?.taxRates ?? <CompanyTaxRate>[])
        if (code.applies(date, TaxApplication.purchases))
          code.choice: code.label,
    };
    if (line.tax != null &&
        !labels.containsKey(line.tax) &&
        _taxChoiceResolved(line)) {
      labels[line.tax!] = line.taxSnapshot?.choice == line.tax
          ? line.taxSnapshot!.label
          : line.tax == 'No tax'
          ? 'No Tax'
          : line.tax!;
    }
    return labels;
  }

  bool _taxChoiceResolved(_ExpenseLineInput line) {
    if (const {'0', 'No tax'}.contains(line.tax)) return true;
    try {
      return _resolvedTax(line) != null;
    } on StateError {
      return false;
    } on FormatException {
      return false;
    }
  }

  List<int> get _unresolvedTaxRows => [
    for (var i = 0; i < _lines.length; i++)
      if (!_taxChoiceResolved(_lines[i])) i + 1,
  ];

  String? _lineBasis(_ExpenseLineInput line) =>
      _taxMode == ExpenseClaimSource.mixedBasis
      ? widget.savedDraft?.claimSource?.lineBases[line.id] ??
            widget.savedDraft?.receiptLineBases[line.id]
      : _taxMode;

  CompanyTaxRate? _resolvedTax(_ExpenseLineInput line) => resolveTaxChoice(
    line.tax ?? '',
    codes: widget.settingsWorkspace?.taxRates ?? const [],
    date: parseAccountingInputDate(_dateController.text) ?? DateTime.now(),
    purpose: TaxApplication.purchases,
    saved: widget.savedDraft?.lines
        .where((saved) => saved.id == line.id)
        .firstOrNull
        ?.taxSnapshot,
  );

  ExpenseDraftLine _retainedLine(_ExpenseLineInput line) => ExpenseDraftLine(
    id: line.id,
    category: line.category ?? '',
    description: line.description.text,
    tax: line.tax ?? 'Unknown / Review Needed',
    amount: line.amount.text.replaceAll(',', '').trim().isEmpty
        ? '0'
        : line.amount.text.replaceAll(',', '').trim(),
    quantity: _showQuantity ? line.quantity.text.trim() : null,
    rate: _showRate ? line.rate.text.replaceAll(',', '').trim() : null,
    pricingAdjustment: _showRate ? line.adjustment : null,
    taxSnapshot: _taxMode == null ? null : _resolvedTax(line),
  );

  Widget _taxControl(BuildContext context, _ExpenseLineInput line) =>
      AccountingSelector<String>(
        assignedWidth: double.infinity,
        hintText: 'Select Tax',
        controlKey: ValueKey(
          identical(line, _lines.first)
              ? 'expense-tax-control'
              : 'expense-tax-control-${line.id}',
        ),
        menuKey: ValueKey(
          identical(line, _lines.first)
              ? 'expense-tax-menu'
              : 'expense-tax-menu-${line.id}',
        ),
        value: _taxChoiceResolved(line) ? line.tax : null,
        triggerKey: ValueKey(
          identical(line, _lines.first)
              ? 'expense-field-tax'
              : 'expense-line-${line.id}-tax',
        ),
        options: [
          for (final choice in _taxLabels(line).entries)
            AccountingSelectorOption(
              value: choice.key,
              label: choice.value,
              preserveLabelCase: true,
              enabled:
                  choice.key == '0' ||
                  choice.key.contains(':') ||
                  choice.key == 'No tax',
            ),
        ],
        enabled: !_isSaving && !widget.readOnly,
        focusNode: identical(line, _lines.first) ? _taxFocusNode : null,
        onChanged: (value) => setState(() {
          line.tax = value;
          line.taxSnapshot =
              widget.settingsWorkspace?.taxRates
                  .where((code) => code.choice == value)
                  .firstOrNull ??
              widget.savedDraft?.lines
                  .where(
                    (saved) =>
                        saved.id == line.id &&
                        saved.taxSnapshot?.choice == value,
                  )
                  .firstOrNull
                  ?.taxSnapshot;
          _saveError = null;
        }),
      );

  void _initializeRateFromAmount(_ExpenseLineInput line) {
    try {
      final quantity = SalesQuantity.fromDecimal(line.quantity.text);
      final amount = Money.fromDecimal(
        line.amount.text.replaceAll(',', ''),
        _currencyCode,
      );
      final rate = quantity.rateFor(amount);
      line.rate.text = formatAccountingInputAmount(rate);
      line.adjustment = formatAccountingInputAmount(
        amount - quantity.multiply(rate),
      );
    } on Object {
      // Leave incomplete input visible for the existing Save validation.
    }
  }

  void _reprice(_ExpenseLineInput line, String edited) {
    if (_showRate) {
      try {
        final quantity = SalesQuantity.fromDecimal(line.quantity.text);
        if (edited == 'Amount') {
          _initializeRateFromAmount(line);
        } else {
          final rate = Money.fromDecimal(
            line.rate.text.replaceAll(',', ''),
            _currencyCode,
          );
          line.amount.text = formatAccountingMoneyInputText(
            formatAccountingInputAmount(quantity.multiply(rate)),
            _currencyPresentation?.currency.fractionDigits ?? 2,
          );
          line.adjustment = null;
        }
      } on Object {
        /* Incomplete edits remain visible; Save validates. */
      }
    }
    setState(() {});
  }

  Money? get _enteredTotal {
    try {
      return _lines.fold<Money>(
        Money.zero(_currencyCode),
        (sum, line) =>
            sum +
            Money.fromDecimal(
              line.amount.text.trim().isEmpty
                  ? '0'
                  : line.amount.text.replaceAll(',', ''),
              _currencyCode,
            ),
      );
    } on Object {
      return null;
    }
  }

  ({Money net, Money tax, Money total})? get _taxTotals {
    final entered = _enteredTotal;
    if (entered == null) return null;
    if (entered.minorUnits == 0 ||
        (_taxMode == null &&
            _lines.every((line) => const {'0', 'No tax'}.contains(line.tax)))) {
      return (net: entered, tax: Money.zero(_currencyCode), total: entered);
    }
    if (_taxMode == null) return null;
    try {
      var net = Money.zero(_currencyCode);
      var tax = Money.zero(_currencyCode);
      var total = Money.zero(_currencyCode);
      for (final line in _lines) {
        final result = _retainedLine(line).calculation(
          _currencyCode,
          _lineBasis(line) ??
              (throw const FormatException(
                'Choose Tax Inclusive or Tax Exclusive for the new rows.',
              )),
        );
        net += result.net;
        tax += result.tax;
        total += result.total;
      }
      return (net: net, tax: tax, total: total);
    } on Object {
      return null;
    }
  }

  Money? get _total =>
      _taxTotals?.total ??
      (_taxMode == null || _taxMode == 'Inclusive' ? _enteredTotal : null);

  Widget _buildMemoTotals(BuildContext context) {
    final totals = _taxTotals;
    String amount(Money? value) => value == null
        ? '—'
        : formatAccountingMoneyInputText(
            formatAccountingInputAmount(value),
            _currencyPresentation?.currency.fractionDigits ?? 2,
          );
    return AccountingMemoSummary(
      summaryLabelInset: widget.includeTopSafeArea ? 0 : accountingContentInset,
      rows: [
        ('Subtotal', amount(totals?.net)),
        ('Tax', amount(totals?.tax)),
        (
          'Total (${_currencyPresentation?.amountSymbol ?? _currencyCode})',
          amount(_total),
        ),
      ],
      memo: (height) => AccountingDescriptionField(
        onEscape: widget.includeTopSafeArea ? null : _handleClose,
        role: AccountingDescriptionRole.memo,
        key: const ValueKey('expense-field-notes'),
        controller: _notesController,
        focusNode: _notesFocusNode,
        fixedHeight: height,
        enabled: !_isSaving && !widget.readOnly,
        decoration: accountingSingleLineInputDecoration(context),
      ),
    );
  }

  Widget _buildCardFooter(BuildContext context, {bool surface = true}) {
    final tokens = AccountingTheme.of(context);
    return Container(
      key: const ValueKey('record-expense-card-footer'),
      width: double.infinity,
      padding: surface ? accountingContentPadding : EdgeInsets.zero,
      decoration: surface
          ? BoxDecoration(
              color: tokens.muted,
              border: Border(top: BorderSide(color: tokens.border)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_showValidationSummary) _buildValidationSummary(context),
          if (_saveError != null) ...<Widget>[
            if (_showValidationSummary) const SizedBox(height: 12),
            _buildSaveError(context),
          ],
          if (_showValidationSummary || _saveError != null)
            const SizedBox(height: 16),
          _buildActions(context),
        ],
      ),
    );
  }

  void _setPayeeHoveredId(String? id) {
    if (!mounted || _payeeHoveredId == id) return;
    setState(() => _payeeHoveredId = id);
  }

  void _clearPayeeHoveredId(String id) {
    if (_payeeHoveredId == id) _setPayeeHoveredId(null);
  }

  void _clearPayeeHover() {
    if (_payeeHoveredId != null) _setPayeeHoveredId(null);
  }

  void _handlePayeeAutocompleteFocusChanged() {
    if (!(_payeeAutocompleteFocusNode?.hasFocus ?? false)) {
      _clearPayeeHover();
    }
  }

  void _bindPayeeAutocompleteFocusNode(FocusNode focusNode) {
    if (_payeeAutocompleteFocusNode == focusNode) return;
    _payeeAutocompleteFocusNode?.removeListener(
      _handlePayeeAutocompleteFocusChanged,
    );
    _payeeAutocompleteFocusNode = focusNode;
    focusNode.addListener(_handlePayeeAutocompleteFocusChanged);
  }

  Widget _buildPayeeField(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildFieldLabel(
          context,
          'Payee',
          false,
          guidance: 'Optional. Choose a payee.',
        ),
        const SizedBox(height: accountingFieldLabelGap),
        Autocomplete<Payee>(
          key: const ValueKey('expense-payee-autocomplete'),
          initialValue: TextEditingValue(text: _payeeValue),
          displayStringForOption: (payee) => payee.name,
          optionsBuilder: (value) async {
            final matches = filterPayees(_payeeStore.all, value.text).toList();
            final source = widget.employeePayeeSearch;
            if (source != null) {
              matches.removeWhere((payee) => payee.type == PayeeType.staff);
              try {
                final registered = await source(value.text);
                // Keep directory identity; retire duplicate legacy name/type choices.
                for (final employee in registered) {
                  matches.removeWhere(
                    (p) => p.type == PayeeType.staff && p.name == employee.name,
                  );
                  matches.add(employee);
                }
              } catch (_) {
                matches.add(
                  const Payee(
                    id: '__employee-source-error__',
                    name: 'Employee choices could not be loaded. Try again.',
                    type: PayeeType.other,
                  ),
                );
              }
            }
            matches.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            if (matches.isEmpty && value.text.trim().isNotEmpty) {
              return <Payee>[
                if (!widget.readOnly)
                  const Payee(
                    id: '__add-payee__',
                    name: 'Add Payee',
                    type: PayeeType.other,
                  ),
                const Payee(
                  id: '__no-matching-payees__',
                  name: 'No matching payees',
                  type: PayeeType.other,
                ),
              ];
            }
            return [
              if (!widget.readOnly)
                const Payee(
                  id: '__add-payee__',
                  name: 'Add Payee',
                  type: PayeeType.other,
                ),
              ...matches,
            ];
          },
          onSelected: (payee) {
            if (payee.id == '__add-payee__') {
              _payeeAutocompleteFocusNode?.unfocus();
              _payeeAutocompleteController?.value = TextEditingValue(
                text: _payeeValue,
                selection: TextSelection.collapsed(offset: _payeeValue.length),
              );
              _addPayee();
              return;
            }
            if (payee.id == '__no-matching-payees__' ||
                payee.id == '__employee-source-error__') {
              return;
            }
            setState(() {
              _payeeValue = payee.name;
              _payeeHoveredId = null;
            });
          },

          optionsViewBuilder: (context, onSelected, options) {
            final optionList = options.toList(growable: false);
            return PayeeAutocompleteMenu(
              triggerKey: _payeeFieldAnchor,
              surfaceKey: const ValueKey('expense-payee-menu'),
              contentWidth: payeeAutocompleteMenuWidth(
                context,
                [..._payeeStore.all, ...optionList],
                badged: true,
                extraLabels: ['Add Payee', 'No matching payees'],
              ),
              itemCount: optionList.length,
              itemBuilder: (context, index) {
                final payee = optionList[index];
                if (payee.id == '__add-payee__') {
                  return accountingSelectorCreationAction(
                    context,
                    key: const ValueKey('expense-add-payee'),
                    label: 'Add Payee',
                    onPressed: _isSaving
                        ? null
                        : () {
                            _payeeAutocompleteFocusNode?.unfocus();
                            _addPayee();
                          },
                  );
                }
                if (payee.id == '__no-matching-payees__' ||
                    payee.id == '__employee-source-error__') {
                  return Padding(
                    key: const ValueKey('expense-payee-no-results'),
                    padding: EdgeInsets.all(12),
                    child: Text(
                      payee.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                final isHovered = _payeeHoveredId == payee.id;
                return MouseRegion(
                  onEnter: (_) => _setPayeeHoveredId(payee.id),
                  onExit: (_) => _clearPayeeHoveredId(payee.id),
                  child: Semantics(
                    label: '${payee.name}, ${payee.typeLabel}',
                    button: true,
                    child: Material(
                      color: isHovered ? tokens.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey<String>(
                          'expense-payee-option-${payee.id}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelected(payee),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    payee.name,
                                    softWrap: false,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(
                                  width:
                                      AccountingSelectionLabel.minimumTextGap,
                                ),
                                AccountingSelectionLabel.build(
                                  context,
                                  label: payee.typeLabel,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _bindPayeeAutocompleteFocusNode(focusNode);
            _payeeAutocompleteController = controller;
            return KeyedSubtree(
              key: _payeeFieldAnchor,
              child: Semantics(
                container: true,
                label: 'Who was paid?, optional',
                child: TextFormField(
                  key: const ValueKey('expense-field-payee'),
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_isSaving && !widget.readOnly,
                  textInputAction: TextInputAction.next,
                  onTap: _clearPayeeHover,
                  onChanged: (value) {
                    _clearPayeeHover();
                    _payeeValue = value;
                  },
                  onFieldSubmitted: (_) {
                    onFieldSubmitted();
                    _paymentAccountFocusNode.requestFocus();
                  },
                  decoration: _inputDecoration(
                    context,
                    hintText: 'Search payee',
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaymentAccountField(BuildContext context) {
    if (_isClaim) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          accountingFieldLabel(
            context,
            'Payment Account',
            alignToField: true,
            guidance: widget.claimContext!.personallyPaid
                ? 'Paid personally by the claimant. Approval records the reimbursement liability; reimbursement selects the company bank account separately.'
                : 'The original Claim does not confirm personal payment. Retain that original evidence for review.',
          ),
          const SizedBox(height: accountingFieldLabelGap),
          InputDecorator(
            key: const ValueKey('expense-field-payment-account'),
            decoration: accountingSingleLineInputDecoration(context),
            child: accountingValueText(
              context,
              widget.claimContext!.personallyPaid
                  ? 'Personally Paid'
                  : 'Not Confirmed',
            ),
          ),
        ],
      );
    }
    if (widget.savedDraft?.claimSource != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          accountingFieldLabel(
            context,
            'Payment Account',
            alignToField: true,
            guidance: 'This approved Claim recognizes the reimbursement liability here. Reimbursement records the paying bank account separately.',
          ),
          const SizedBox(height: accountingFieldLabelGap),
          InputDecorator(
            key: const ValueKey('expense-claim-liability-account'),
            decoration: accountingSingleLineInputDecoration(context),
            child: accountingValueText(
              context,
              widget.savedDraft!.paymentAccount,
            ),
          ),
        ],
      );
    }
    final errorText = _showValidationSummary && _paymentAccount == null
        ? 'Payment account is required.'
        : null;
    final options = <AccountingSelectorOption<PaymentAccount>>[
      for (final account in _accounts)
        AccountingSelectorOption<PaymentAccount>(
          value: account,
          label: account.displayLabel,
          preserveLabelCase: true,
        ),
    ];
    return Semantics(
      container: true,
      label: 'Payment account, required',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldLabel(context, 'Payment Account', true),
          const SizedBox(height: accountingFieldLabelGap),
          AccountingSelector<PaymentAccount?>(
            assignedWidth: double.infinity,
            options: [
              if (!widget.readOnly)
                AccountingSelectorOption<PaymentAccount?>(
                  value: null,
                  label: 'Add Account',
                  key: const ValueKey('expense-add-account'),
                  onPressed: _isSaving ? null : _addAccount,
                ),
              ...options,
            ],
            value: _paymentAccount,
            onChanged: (value) {
              if (value == null || !mounted) return;
              setState(() {
                _paymentAccount = value;
                _currencyPresentation = CurrencyPresentation.fromCode(
                  value.currency.code,
                );
                _currencyCode = _currencyPresentation!.code;
                _currencyError = null;
              });
            },
            hintText: _accounts.isEmpty
                ? 'No payment accounts yet'
                : 'Select Payment Account',
            controlKey: const ValueKey('expense-payment-account-dropdown'),
            triggerKey: const ValueKey('expense-field-payment-account'),
            menuKey: const ValueKey('expense-payment-account-menu'),
            searchable: true,
            searchKey: const ValueKey('payment-account-search'),
            searchHintText: 'Search accounts',
            errorText: errorText,
            enabled: !_isSaving && !widget.readOnly,
            focusNode: _paymentAccountFocusNode,
            semanticsLabel: 'Payment account, required',
          ),
        ],
      ),
    );
  }

  bool get _showCustomer =>
      ((widget.settingsWorkspace?.preferences ?? widget.preferences)?.enabled(
            'Purchase Preferences',
            'Link To Customer',
          ) ??
          true) ||
      _customer.isNotEmpty;
  bool get _showBillable =>
      ((widget.settingsWorkspace?.preferences ?? widget.preferences)?.enabled(
            'Purchase Preferences',
            'Billable Expenses',
          ) ??
          true) ||
      _billable;
  bool get _showItems =>
      ((widget.settingsWorkspace?.preferences ?? widget.preferences)?.enabled(
            'Purchase Preferences',
            'Track Items',
          ) ??
          true) ||
      _lines.any((line) => line.description.text.isNotEmpty);
  Widget _buildCustomerAndBillable(BuildContext context) {
    final customer = _buildTextField(
      key: const ValueKey('expense-field-customer'),
      initialValue: _customer,
      focusNode: _customerFocusNode,
      label: 'Customer / billable',
      helperText: 'Optional. Link to a customer.',
      textInputAction: TextInputAction.next,
      onChanged: (value) => _customer = value,
      onFieldSubmitted: (_) => _dimensionsFocusNode.requestFocus(),
    );
    if (_showCustomer && _showBillable) {
      return _responsivePair(customer, _buildBillableField(context));
    }
    return _showCustomer ? customer : _buildBillableField(context);
  }

  Widget _buildBillableField(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Billable expense',
      child: InkWell(
        key: const ValueKey('expense-field-billable'),
        borderRadius: BorderRadius.circular(10),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onTap: _isSaving ? null : () => setState(() => _billable = !_billable),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: widget.includeTopSafeArea
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: <Widget>[
              AccountingLeadingCheckbox(
                undividedRow: !widget.includeTopSafeArea,
                value: _billable,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _billable = value ?? false),
                semanticLabel: 'Billable expense',
              ),
              if (widget.includeTopSafeArea) const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      accountingFieldLabel(
                        context,
                        'Billable expense',
                        alignToField: !widget.includeTopSafeArea,
                        guidance: 'Optional customer linkage.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedAccountingDetails(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final guidance = [
      'Optional project, cost centre, department, location, or split details.',
      for (final category in _categoryCatalog.where(
        (category) =>
            _lines.any((line) => line.category == category.displayName),
      ))
        '${category.displayName}: ${_categoryMetadata(category)}',
    ].join('\n');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        key: const ValueKey('expense-advanced-details'),
        initiallyExpanded: _advancedExpanded,
        onExpansionChanged: (expanded) {
          if (mounted) setState(() => _advancedExpanded = expanded);
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Advanced Accounting Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: tokens.cardForeground,
              ),
            ),
            AccountingFieldHelp(
              label: 'Advanced Accounting Details',
              message: guidance,
            ),
          ],
        ),
        children: _advancedExpanded
            ? <Widget>[
                _buildDimensionsField(context),
                if (_showCustomer || _showBillable) ...[
                  const SizedBox(height: accountingContentInset),
                  _buildCustomerAndBillable(context),
                ],
                const SizedBox(height: accountingContentInset),
                AssetPurchaseFields(
                  ordinaryPopup: !widget.includeTopSafeArea,
                  currencyCode:
                      _currencyPresentation?.code ?? widget.defaultCurrencyCode,
                  onChanged: (value) => setState(() => _assetPurchase = value),
                ),
              ]
            : const <Widget>[],
      ),
    );
  }

  Widget _buildDimensionsField(BuildContext context) {
    return _buildTextField(
      key: const ValueKey('expense-field-dimensions'),
      controller: _dimensionsController,
      focusNode: _dimensionsFocusNode,
      label: 'Dimensions',
      helperText: 'Optional. Add class, location, department, or tag.',
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _itemOrSplitFocusNode.requestFocus(),
    );
  }

  Widget _buildAttachmentField(BuildContext context) {
    if (widget.readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          accountingFieldLabel(context, 'Receipts'),
          if (_attachments.isEmpty) const Text('No receipts attached.'),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: accountingFieldLabelGap),
            AccountingAttachmentList(
              paginationKey: 'expense-attachments',
              children: [
                for (final attachment in _attachments)
                  _buildAttachmentRow(context, attachment),
              ],
            ),
          ],
        ],
      );
    }
    final tokens = AccountingTheme.of(context);
    Widget dropzone = Semantics(
      container: true,
      button: true,
      label: _isDragOver
          ? 'Drop receipt files here'
          : 'Drop receipts here or choose files',
      child: Focus(
        focusNode: _receiptFocusNode,
        canRequestFocus: !_isSaving,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _chooseAttachments();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          key: const ValueKey('expense-receipt-dropzone'),
          borderRadius: BorderRadius.circular(10),
          onTap: _isSaving ? null : _chooseAttachments,
          child: AccountingAttachmentDropzone(
            surfaceKey: const ValueKey('expense-receipt-surface'),
            contentKey: const ValueKey('expense-receipt-content'),
            promptKey: const ValueKey('expense-upload-prompt'),
            actionKey: const ValueKey('expense-add-receipt-action'),
            dragOver: _isDragOver,
            onChoose: _isSaving ? null : _chooseAttachments,
            prompt: 'Drop receipts here or choose files',
            formats:
                'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
          ),
        ),
      ),
    );
    if (_supportsFileDrop) {
      dropzone = DropTarget(
        enable: !_isSaving,
        onDragEntered: (_) {
          if (mounted) setState(() => _isDragOver = true);
        },
        onDragExited: (_) {
          if (mounted) setState(() => _isDragOver = false);
        },
        onDragDone: _onDragDone,
        child: dropzone,
      );
    }

    return Semantics(
      container: true,
      label: 'Receipt or document, optional',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldLabel(context, 'Receipts', false),
          const SizedBox(height: 8),
          dropzone,
          if (_receiptReviewQueue?.hasUnresolved == true) ...<Widget>[
            const SizedBox(height: 8),
            AccountingButton.outline(
              context,
              key: const ValueKey('expense-review-receipts'),
              onPressed: _isSaving || _reviewActive
                  ? null
                  : () => _openReceiptReview(_receiptReviewQueue!),
              leadingIcon: Icons.rate_review_outlined,
              child: Text(
                'Review ${_receiptReviewQueue!.remainingCount} staged receipt${_receiptReviewQueue!.remainingCount == 1 ? '' : 's'}',
              ),
            ),
          ],
          if (_attachmentMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _attachmentMessage!,
                key: const ValueKey('expense-attachment-message'),
                softWrap: true,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ),
          ],
          if (_attachments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            AccountingAttachmentList(
              paginationKey: 'expense-attachments',
              children: [
                for (final attachment in _attachments)
                  _buildAttachmentRow(context, attachment),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentRow(
    BuildContext context,
    ReceiptAttachment attachment,
  ) {
    if (widget.readOnly) {
      return ReadonlyAttachmentRow(
        key: ValueKey('expense-attachment-row-${attachment.originalId}'),
        attachment: attachment,
        keyPrefix: 'expense',
      );
    }

    return AccountingAttachmentRecordRow(
      key: ValueKey<String>('expense-attachment-row-${attachment.originalId}'),
      attachment: attachment,
      statusKey: ValueKey('expense-attachment-status-${attachment.originalId}'),
      actions: [
        AccountingButton.iconOnly(
          context,
          key: ValueKey('expense-attachment-view-${attachment.originalId}'),
          onPressed: () => showAttachmentPreview(context, attachment),
          icon: Icons.visibility_outlined,
          tooltip: 'View Attachment',
        ),
        if (!widget.readOnly && !_reviewActive && attachment.canConvertToPdf)
          AccountingButton.iconOnly(
            context,
            key: ValueKey<String>(
              'expense-attachment-crop-${attachment.originalId}',
            ),
            onPressed: _isSaving
                ? null
                : () =>
                      _openReceiptReview(_reviewQueueForAttachment(attachment)),
            icon: Icons.edit_outlined,
            tooltip: 'Edit Attachment',
          ),
        if (!widget.readOnly &&
            !_reviewActive &&
            attachment.canConvertToPdf &&
            attachment.pdfBytes == null)
          AccountingButton.outline(
            context,
            key: ValueKey<String>(
              'expense-attachment-convert-${attachment.originalId}',
            ),
            onPressed: _isSaving ? null : () => _convertAttachment(attachment),
            child: const Text('Convert to PDF'),
          ),
        if (!widget.readOnly)
          AccountingButton.iconOnly(
            context,
            key: ValueKey<String>(
              'expense-attachment-remove-${attachment.originalId}',
            ),
            onPressed: _isSaving
                ? null
                : () => _removeAttachment(attachment.originalId),
            icon: Icons.delete_outline,
            tooltip: 'Remove Attachment',
          ),
        if (!widget.readOnly &&
            attachment.status == AttachmentProcessingStatus.failed)
          AccountingButton.outline(
            context,
            key: ValueKey<String>(
              'expense-attachment-retry-${attachment.originalId}',
            ),
            onPressed: _isSaving ? null : () => _retryAttachment(attachment),
            child: const Text('Retry'),
          ),
      ],
    );
  }

  Widget _buildValidationSummary(BuildContext context) {
    return AccountingAlert.build(
      context,
      key: const ValueKey('record-expense-validation-summary'),
      title: 'Please correct the highlighted fields before saving.',
      description: 'Required fields still need attention.',
      destructive: true,
    );
  }

  Widget _buildSaveError(BuildContext context) {
    return AccountingAlert.build(
      context,
      key: const ValueKey('record-expense-save-error'),
      title: _isClaim ? 'Review Claim' : 'Review Expense',
      description: _saveError ?? 'Review the expense and try saving again.',
      destructive: true,
      action: AccountingButton.outline(
        context,
        key: const ValueKey('record-expense-retry-save'),
        onPressed: _isSaving
            ? null
            : () => _submit(claimSubmit: _retryClaimSubmit),
        child: const Text('Retry Save'),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (widget.readOnly) {
      return Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [...widget.recordActions],
        ),
      );
    }
    final tokens = AccountingTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final saveButton = AccountingButton.primary(
          context,
          key: const ValueKey('record-expense-save'),
          onPressed: _isSaving || !_canSubmit ? null : _submit,
          child: _isSaving
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.primaryForeground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Saving…'),
                  ],
                )
              : Text(
                  _assetPurchase['Purchase Treatment'] == 'Expense'
                      ? 'Save Expense'
                      : 'Review Asset Purchase',
                ),
        );
        final cancelButton = AccountingButton.ghost(
          context,
          key: const ValueKey('record-expense-cancel'),
          onPressed: _isSaving || widget.onCancel == null ? null : _handleClose,
          child: const Text('Cancel'),
        );
        return Row(
          children: [
            if (widget.settingsWorkspace != null &&
                widget.claimContext?.showSettingsShortcut != false)
              AccountingSettingsShortcut(
                key: const ValueKey('expense-settings-shortcut'),
                onPressed: _isSaving
                    ? null
                    : () async {
                        await openAccountingSettings(
                          context,
                          workspace: widget.settingsWorkspace,
                          fields: transactionSettingsFields('Record Expense'),
                          setupKinds: _isClaim
                              ? const {SetupKind.expense, SetupKind.claims}
                              : const {SetupKind.expense},
                          title: _isClaim
                              ? 'Claim Settings'
                              : 'Expense Settings',
                        );
                        if (mounted) {
                          for (final line in _lines) {
                            if (_showRate && line.rate.text.isEmpty) {
                              _reprice(line, 'Amount');
                            }
                          }
                          setState(
                            () =>
                                _contentWidth = _requiredContentWidth(context),
                          );
                        }
                      },
              ),
            Expanded(
              child: Wrap(
                spacing: AccountingResponsive.actionGap,
                runSpacing: AccountingResponsive.actionGap,
                alignment: WrapAlignment.end,
                children: [
                  ...widget.recordActions,
                  if (widget.includeTopSafeArea) cancelButton,
                  if (widget.onSavedReview != null)
                    AccountingButton.workflow(
                      context,
                      key: const ValueKey('expense-save-review'),
                      onPressed: _isSaving || !_canSubmit
                          ? null
                          : () => _submit(review: true),
                      child: const Text('Save And Review Posting'),
                    ),
                  if (_isClaim) ...[
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('record-claim-save-draft'),
                      onPressed:
                          _isSaving ||
                              !_canSubmit ||
                              widget.claimContext!.commandsUnavailable
                          ? null
                          : () => _submit(),
                      child: Tooltip(
                        message: widget.claimContext!.unavailableReason ?? '',
                        child: const Text('Save Draft'),
                      ),
                    ),
                    AccountingButton.primary(
                      context,
                      key: const ValueKey('record-claim-submit'),
                      onPressed:
                          _isSaving ||
                              !_canSubmit ||
                              widget.claimContext!.commandsUnavailable
                          ? null
                          : () => _submit(claimSubmit: true),
                      child: Tooltip(
                        message: widget.claimContext!.unavailableReason ?? '',
                        child: Text(
                          _isSaving ? 'Saving…' : 'Submit For Review',
                        ),
                      ),
                    ),
                  ] else
                    saveButton,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required Key key,
    required String label,
    TextEditingController? controller,
    String? initialValue,
    FocusNode? focusNode,
    String? helperText,
    String? errorText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    void Function(String)? onFieldSubmitted,
    Widget? suffixIcon,
    String? prefixText,
    Key? prefixKey,
    int? narrativeLines,
    bool required = false,
    bool compactDate = false,
  }) {
    assert(controller == null || initialValue == null);
    assert(narrativeLines == null || narrativeLines > 1);
    final field = Semantics(
      container: true,
      label: required ? '$label, required' : label,
      child: narrativeLines != null
          ? AccountingDescriptionField(
              onEscape: widget.includeTopSafeArea ? null : _handleClose,
              key: key,
              fixedLines: narrativeLines,
              controller: controller,
              initialValue: initialValue,
              focusNode: focusNode,
              enabled: !_isSaving && !widget.readOnly,
              onChanged: onChanged,
              validator: validator,
              decoration: _inputDecoration(
                context,
                helperText: null,
                errorText: errorText,
                hintText: _hintFor(label),
              ),
            )
          : TextFormField(
              key: key,
              controller: controller,
              initialValue: initialValue,
              focusNode: focusNode,
              enabled: !_isSaving && !widget.readOnly,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
              enableInteractiveSelection: true,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              style: AccountingTypography.value(context),
              onChanged: onChanged,
              onFieldSubmitted: onFieldSubmitted,
              validator: validator,
              decoration:
                  _inputDecoration(
                    context,
                    helperText: null,
                    errorText: errorText,
                    prefixText: prefixText,
                    prefixKey: prefixKey,
                    suffixIcon: suffixIcon,
                    hintText: _hintFor(label),
                  ).copyWith(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: accountingFieldContentInset,
                      vertical: 12,
                    ),
                  ),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildFieldLabel(context, label, required, guidance: helperText),
        const SizedBox(height: accountingFieldLabelGap),
        compactDate ? accountingDateFieldFrame(child: field) : field,
      ],
    );
  }

  Widget _buildFieldLabel(
    BuildContext context,
    String label,
    bool required, {
    String? guidance,
  }) {
    final tokens = AccountingTheme.of(context);
    final fieldSlug = _fieldSlug(label);
    final labelStyle = AccountingTypography.fieldLabel(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Semantics(
        container: true,
        label: required ? '$label, required' : label,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: <Widget>[
            Text(
              label,
              key: ValueKey<String>('expense-label-$fieldSlug'),
              softWrap: true,
              style: labelStyle,
            ),
            if (required)
              Text(
                '*',
                key: ValueKey<String>('expense-required-$fieldSlug'),
                style: labelStyle.copyWith(color: tokens.destructive),
              ),
            if (guidance != null)
              AccountingFieldHelp(label: label, message: guidance),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    String? helperText,
    String? errorText,
    String? hintText,
    String? prefixText,
    Key? prefixKey,
    Widget? suffixIcon,
    bool alignLabelWithHint = false,
  }) {
    return accountingInputDecoration(
      context,
      helperText: helperText,
      errorText: errorText,
      hintText: hintText,
      prefixText: prefixText,
      prefixKey: prefixKey,
      suffixIcon: suffixIcon,
      alignLabelWithHint: alignLabelWithHint,
    );
  }

  String _fieldSlug(String label) {
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String? _hintFor(String label) {
    switch (label) {
      case 'Amount':
        return '0.00';
      case 'Date':
        return 'DD-MM-YYYY';
      case 'Customer / billable':
        return 'Customer name (optional)';
      case 'Dimensions':
        return 'Class, location, department, or tag';
      case 'Item or service / split-line details':
        return 'Add item, service, or split-line detail';
      case 'Notes / memo':
        return 'Add context for yourself or your accountant';
      default:
        return null;
    }
  }

  Widget _responsivePair(Widget first, Widget? second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canPair = AccountingResponsive.fitsWithContentGap(
          constraints.maxWidth,
          const [
            AccountingResponsive.fieldMinWidth,
            AccountingResponsive.fieldMinWidth,
          ],
        );
        if (!canPair) {
          if (second == null) return first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              first,
              SizedBox(height: AccountingPageControlScope.runGapOf(context)),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: AccountingResponsive.groupGap),
            if (second != null) Expanded(child: second) else const Spacer(),
          ],
        );
      },
    );
  }

  bool get _categoryEnabled =>
      widget.referenceStatus == AccountingReferenceStatus.ready &&
      _categoryCatalog.isNotEmpty &&
      !_isSaving;

  bool get _canSubmit =>
      widget.referenceStatus == AccountingReferenceStatus.ready &&
      (_categoryCatalog.isNotEmpty || _lines.every(_retainsCategory)) &&
      _currencyPresentation != null &&
      _receiptReviewQueue?.hasUnresolved != true;

  String? _requiredAmount(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Amount is required.';
    final parsed = double.tryParse(trimmed.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return 'Enter an amount greater than zero.';
    }

    final decimalMatch = RegExp(r'^[+-]?\d+(?:,\d{3})*(?:\.(\d+))?$')
        .firstMatch(trimmed);
    if (decimalMatch == null) return 'Enter a valid decimal amount.';
    final fractionDigits = _currencyPresentation?.currency.fractionDigits;
    final enteredFraction = decimalMatch.group(1)?.length ?? 0;
    if (fractionDigits != null && enteredFraction > fractionDigits) {
      return 'Enter an amount with no more than $fractionDigits decimal ${fractionDigits == 1 ? 'place' : 'places'}.';
    }
    return null;
  }

  String? _requiredDate(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Date is required.';
    if (parseAccountingInputDate(trimmed) == null) {
      return 'Enter a valid local date.';
    }
    return null;
  }

  static const _recurrencePeriods = <String>[
    'Monthly',
    'Quarterly',
    'Yearly',
    'Every 2 Years',
    'Every 3 Years',
    'Every 4 Years',
    'Every 5 Years',
  ];

  String _periodForRule(RecurrenceRule rule) {
    if (rule.unit == RecurrenceUnit.months && rule.every == 1) {
      return 'Monthly';
    }
    if (rule.unit == RecurrenceUnit.months && rule.every == 3) {
      return 'Quarterly';
    }
    if (rule.unit == RecurrenceUnit.years && rule.every == 1) {
      return 'Yearly';
    }
    if (rule.unit == RecurrenceUnit.years &&
        rule.every >= 2 &&
        rule.every <= 5) {
      return 'Every ${rule.every} Years';
    }
    return 'Custom Schedule';
  }

  RecurrenceRule? get _selectedRecurrence {
    if (!_recurrenceEnabled) return null;
    if (_recurrencePeriod == 'Custom Schedule') return _recurrence;
    final startsOn = parseAccountingInputDate(_dateController.text);
    if (startsOn == null) return null;
    final (unit, every) = switch (_recurrencePeriod) {
      'Monthly' => (RecurrenceUnit.months, 1),
      'Quarterly' => (RecurrenceUnit.months, 3),
      'Yearly' => (RecurrenceUnit.years, 1),
      'Every 2 Years' => (RecurrenceUnit.years, 2),
      'Every 3 Years' => (RecurrenceUnit.years, 3),
      'Every 4 Years' => (RecurrenceUnit.years, 4),
      'Every 5 Years' => (RecurrenceUnit.years, 5),
      _ => (RecurrenceUnit.months, 1),
    };
    return RecurrenceRule(
      startsOn: startsOn,
      unit: unit,
      every: every,
      endsOn: _recurrence?.endsOn?.isBefore(startsOn) == true
          ? null
          : _recurrence?.endsOn,
      occurrenceCount: _recurrence?.occurrenceCount,
      preserveMonthEnd: _recurrence?.preserveMonthEnd ?? true,
    );
  }

  Widget _buildRecurrenceFields(
    BuildContext context, {
    bool showToggle = true,
  }) {
    final enabled = !_isSaving && !widget.readOnly;
    final selected = _selectedRecurrence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showToggle)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountingLeadingCheckbox(
                checkboxKey: const ValueKey('expense-recurring-checkbox'),
                value: _recurrenceEnabled,
                onChanged: enabled
                    ? (value) => setState(() {
                        _recurrenceEnabled = value ?? false;
                        if (_recurrenceEnabled &&
                            _recurrencePeriod == 'Custom Schedule' &&
                            _recurrence == null) {
                          _recurrencePeriod = 'Monthly';
                        }
                      })
                    : null,
                semanticLabel: 'Recurring expense',
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Recurring expense',
                  style: AccountingTypography.fieldLabel(context),
                ),
              ),
            ],
          ),
        if (_recurrenceEnabled) ...[
          if (showToggle) const SizedBox(height: 12),
          AccountingOrdinaryFields(
            crossAxisAlignment: CrossAxisAlignment.end,
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Repeat',
                choices: _recurrencePeriods,
                hasGuidance: true,
                builder: (assignedWidth) {
                  final width = math.min(assignedWidth, 360.0);
                  return SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Repeat',
                          key: const ValueKey('expense-recurrence-label'),
                          alignToField: true,
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        AccountingSelector<String>(
                          triggerKey: const ValueKey(
                            'expense-recurrence-period',
                          ),
                          hintText: 'Select recurrence',
                          assignedWidth: width,
                          value: _recurrencePeriod,
                          enabled: enabled,
                          options: [
                            for (final period in _recurrencePeriods)
                              AccountingSelectorOption(
                                value: period,
                                label: period,
                              ),
                            if (_recurrencePeriod == 'Custom Schedule')
                              const AccountingSelectorOption(
                                value: 'Custom Schedule',
                                label: 'Custom Schedule',
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _recurrencePeriod = value);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (enabled)
                AccountingOrdinaryFieldSlot(
                  label: 'Schedule Options',
                  minimumControlWidth: math.max(
                    accountingControlHeight,
                    AccountingResponsive.measuredTextWidth(
                          context,
                          'Schedule Options',
                          AccountingTypography.button(context)
                              .copyWith(fontSize: accountingControlFontSize),
                        ) +
                        accountingContentInset * 2,
                  ),
                  builder: (_) => AccountingButton.outline(
                    context,
                    key: const ValueKey('expense-recurrence-options'),
                    onPressed: _editRecurrence,
                    fullWidth: !widget.includeTopSafeArea,
                    child: const Text('Schedule Options'),
                  ),
                ),
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: accountingFieldLabelGap),
            AccountingInformationRows(
              key: const ValueKey('expense-recurrence-information'),
              rows: [
                ('Interval', '${selected.every} ${selected.unit.name}'),
                (
                  'Ends',
                  selected.occurrenceCount != null
                      ? 'After ${selected.occurrenceCount} occurrences'
                      : selected.endsOn != null
                      ? formatAccountingInputDate(selected.endsOn!)
                      : 'No End Date',
                ),
                (
                  'Next Dates',
                  selected
                      .preview(count: 3)
                      .map(formatAccountingInputDate)
                      .join(' · '),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _editRecurrence() async {
    final date = parseAccountingInputDate(_dateController.text);
    if (date == null) {
      setState(
        () => _saveError =
            'Enter a valid expense date before setting recurrence.',
      );
      return;
    }
    final selected = await showExpenseRecurrenceDialog(
      context,
      startsOn: date,
      initial: _recurrence,
    );
    if (selected != null && mounted) {
      setState(() {
        _recurrence = selected;
        _recurrenceEnabled = true;
        _recurrencePeriod = _periodForRule(selected);
      });
    }
  }

  Map<String, String> _assetPurchase = {'Purchase Treatment': 'Expense'};

  List<(String, String)> _assetPurchaseReviewRows() {
    const monetary = {'Acquisition Cost', 'Expense Portion', 'Residual Value'};
    final currency = CurrencyPresentation.fromCode(_currencyCode);
    return [
      for (final entry in _assetPurchase.entries)
        (
          monetary.contains(entry.key)
              ? '${entry.key} (${currency.amountSymbol})'
              : entry.key,
          _assetPurchaseReviewValue(
            entry.value,
            monetary: monetary.contains(entry.key),
          ),
        ),
    ];
  }

  String _assetPurchaseReviewValue(String value, {required bool monetary}) {
    if (value.trim().isEmpty) return 'Not Set';
    if (!monetary) return value;
    try {
      return formatAccountingMoney(
        context,
        Money.fromDecimal(value, _currencyCode),
        includeCurrency: false,
      );
    } on FormatException {
      return value;
    } on RangeError {
      return value;
    }
  }

  Future<void> _submit({bool review = false, bool claimSubmit = false}) async {
    if (widget.claimContext?.commandsUnavailable == true) return;
    if (widget.readOnly || _isSaving) return;
    _retryClaimSubmit = _isClaim && claimSubmit;
    if (_assetPurchase['Purchase Treatment'] != 'Expense') {
      await showDialog<void>(
        context: context,
        builder: (c) => AccountingDialog.alert(
          c,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: 'Review Asset Purchase',
          description: 'Expense and asset posting is unavailable here. Return to the purchase to keep editing.',
          content: SelectionArea(
            child: AccountingInformationRows(rows: _assetPurchaseReviewRows()),
          ),
          actions: [
            AccountingButton.primary(
              c,
              key: const ValueKey('asset-purchase-review-back'),
              onPressed: () => Navigator.pop(c),
              child: const Text('Back To Purchase'),
            ),
          ],
        ),
      );
      return;
    }

    if (_isSaving) return;
    if (widget.recurringSuggestion != null &&
        _lines.any((line) => line.tax == null)) {
      setState(
        () => _saveError = 'Review the tax code on each recurring expense row.',
      );
      _taxFocusNode.requestFocus();
      return;
    }
    try {
      if (_taxMode != null) {
        for (final line in _lines) {
          _retainedLine(line).calculation(
            _currencyCode,
            _lineBasis(line) ??
                (throw const FormatException(
                  'Choose Tax Inclusive or Tax Exclusive for the new rows.',
                )),
          );
        }
      } else if (_lines.any((line) => line.tax?.contains(':') == true)) {
        throw const FormatException('Choose Inclusive or Exclusive amounts.');
      }
    } on Object catch (error) {
      final reason = error is FormatException
          ? error.message
          : error is StateError
          ? error.message
          : 'Review the date, row amount and tax code.';
      setState(() => _saveError = 'Review expense tax: $reason');
      _taxFocusNode.requestFocus();
      return;
    }
    final valid =
        (_formKey.currentState?.validate() ?? false) &&
        (_isClaim ||
            widget.savedDraft?.claimSource != null ||
            _paymentAccount != null) &&
        _total?.isPositive == true;
    if (_receiptReviewQueue?.hasUnresolved == true) {
      setState(() {
        _showValidationSummary = true;
        _saveError =
            'Review or explicitly leave the staged receipts before saving.';
      });
      return;
    }
    if (!valid || _currencyPresentation == null) {
      setState(() => _showValidationSummary = true);
      _focusFirstInvalidField();
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
      _showValidationSummary = false;
    });
    final persistableAttachments = _attachments
        .where((attachment) => !attachment.reviewSkipped)
        .toList(growable: false);
    final draft = RecordExpenseDraft(
      submissionId: _submissionId,
      recurrence: _selectedRecurrence,
      reviewSnapshots: [
        for (final attachment in persistableAttachments)
          if (_receiptHistories.containsKey(attachment.originalId))
            _receiptHistories[attachment.originalId]!,
      ],
      amount: formatAccountingInputAmount(_total!),
      documentNumber: _documentNumber.text.trim(),
      taxMode: _taxMode,
      receiptLineBases:
          _taxMode == ExpenseClaimSource.mixedBasis &&
              widget.savedDraft?.receiptLineBases.isNotEmpty == true
          ? {for (final line in _lines) line.id: _lineBasis(line)!}
          : const {},
      lines: [for (final line in _lines) _retainedLine(line)],
      date: _dateController.text.trim(),
      payee: _payeeValue.trim(),
      paymentAccount: _isClaim
          ? ''
          : widget.savedDraft?.claimSource != null
          ? widget.savedDraft!.paymentAccount
          : _paymentAccount!.name,
      paymentAccountId: (_isClaim || widget.savedDraft?.claimSource != null)
          ? null
          : _paymentAccount!.id,
      claimSource: widget.savedDraft?.claimSource == null
          ? null
          : ExpenseClaimSource.fromJson({
              ...widget.savedDraft!.claimSource!.toJson(),
              'lineBases': {
                for (final line in _lines) line.id: _lineBasis(line)!,
              },
            }),
      category: _lines.map((line) => line.category).toSet().length == 1
          ? _category!
          : 'Multiple Categories',
      tax: _taxMode == null
          ? _tax ?? 'Unknown / Review Needed'
          : _lines.map((line) => _taxLabels(line)[line.tax]).toSet().length == 1
          ? _taxLabels(_lines.first)[_tax]!
          : 'Multiple Taxes',
      customer: _customer.trim(),
      billable: _billable,
      dimensions: _dimensionsController.text.trim(),
      itemOrSplitDetails: _retainedItemOrSplitDetails,
      notes: _notesController.text.trim(),
      attachmentName: persistableAttachments.isEmpty
          ? (widget.savedDraft?.attachments.isEmpty == true
                ? widget.savedDraft?.attachmentName
                : null)
          : (widget.savedDraft?.attachments.isNotEmpty == true &&
                    widget.savedDraft!.attachments.first.originalId ==
                        persistableAttachments.first.originalId &&
                    widget.savedDraft!.attachments.first.filename ==
                        persistableAttachments.first.filename
                ? widget.savedDraft!.attachmentName
                : persistableAttachments.first.filename),
      attachments: List<ReceiptAttachment>.unmodifiable(persistableAttachments),
      currencyCode: _currencyPresentation!.code,
    );
    try {
      if (_isClaim) {
        if (claimSubmit) {
          final errors = widget.claimContext!.submissionErrors!(draft);
          if (errors.isNotEmpty) {
            setState(() {
              _isSaving = false;
              _saveError = errors.join(' ');
            });
            return;
          }
          await widget.claimContext!.submitForReview!(draft);
        } else {
          await widget.claimContext!.saveDraft!(draft);
        }
      } else {
        await widget.onSave?.call(draft);
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (review && widget.onSavedReview != null) {
        await widget.onSavedReview!();
      } else {
        widget.onSaved?.call();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = error is StateError
            ? error.message
            : _isClaim
            ? "Claim couldn't be ${claimSubmit ? 'submitted' : 'saved'}. Your entries are still here."
            : "Expense couldn't be saved. Your entries are still here.";
      });
    }
  }

  void _focusFirstInvalidField() {
    if (_requiredAmount(_amountController.text) != null) {
      _amountFocusNode.requestFocus();
    } else if (_requiredDate(_dateController.text) != null) {
      _dateFocusNode.requestFocus();
    } else if (!_isClaim && _paymentAccount == null) {
      _paymentAccountFocusNode.requestFocus();
    } else {
      _categoryFocusNode.requestFocus();
    }
  }

  Future<void> _addPayee() async {
    final creation = await showAccountingPayeeDialog(
      context,
      newId: () => _newLocalId('payee'),
    );
    final result = creation?.payee;
    if (result != null && mounted) {
      try {
        _payeeStore.save(result);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payee could not be saved. Check storage and try again.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _payeeValue = result.name;
        _payeeAutocompleteController?.text = result.name;
      });
    }
  }

  Future<void> _addAccount() async {
    final result = await showPaymentAccountDialog(
      context,
      preferredCurrencyCode: _currencyPresentation?.code ?? _currencyCode,
      newId: () => _newLocalId('account'),
      buildLabel: _buildFieldLabel,
    );
    if (result != null && mounted) {
      try {
        widget.onPaymentAccountSave?.call(result);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment account could not be saved. Check storage and try again.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _accounts.add(result);
        _paymentAccount = result;
        _currencyPresentation = CurrencyPresentation.fromCode(
          result.currency.code,
        );
        _currencyCode = _currencyPresentation!.code;
        _currencyError = null;
      });
    }
  }

  Future<void> _chooseAttachments() async {
    try {
      List<PickedExpenseAttachment> picked;
      if (widget.onAttachmentsPick != null) {
        picked = await widget.onAttachmentsPick!(context);
      } else if (widget.onAttachmentPick != null) {
        final legacyName = await widget.onAttachmentPick!(context);
        picked = legacyName == null
            ? const <PickedExpenseAttachment>[]
            : <PickedExpenseAttachment>[
                PickedExpenseAttachment(
                  name: legacyName,
                  mimeType: 'application/octet-stream',
                  bytes: Uint8List(0),
                ),
              ];
      } else {
        picked = await const NativeExpenseAttachmentPicker().pick(context);
      }
      await _processPickedAttachments(picked);
    } on Object catch (exception) {
      if (mounted) {
        setState(
          () => _attachmentMessage =
              'The file chooser could not be opened: $exception',
        );
      }
    }
  }

  Future<void> _onDragDone(DropDoneDetails details) async {
    if (mounted) setState(() => _isDragOver = false);
    final picked = <PickedExpenseAttachment>[];
    for (final item in details.files) {
      if (item is DropItemDirectory) continue;
      try {
        final bookmark = item.extraAppleBookmark;
        var accessed = false;
        if (bookmark != null && bookmark.isNotEmpty) {
          accessed = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        }
        try {
          picked.add(
            PickedExpenseAttachment(
              name: item.name,
              mimeType: item.mimeType ?? _mimeTypeForName(item.name),
              bytes: await item.readAsBytes(),
              path: item.path,
            ),
          );
        } finally {
          if (accessed) {
            await DesktopDrop.instance.stopAccessingSecurityScopedResource(
              bookmark: bookmark!,
            );
          }
        }
      } on Object catch (exception) {
        if (mounted) {
          setState(
            () =>
                _attachmentMessage = 'Could not read ${item.name}: $exception',
          );
        }
      }
    }
    await _processPickedAttachments(picked);
  }

  Future<void> _processPickedAttachments(
    List<PickedExpenseAttachment> picked,
  ) async {
    if (picked.isEmpty) return;
    final batchId = _newLocalId('batch');
    final inputs = <ReceiptAttachmentInput>[];
    final queued = <ReceiptAttachment>[];
    for (final item in picked) {
      final input = ReceiptAttachmentInput(
        originalId: _newLocalId('original'),
        batchId: batchId,
        filename: item.name,
        mimeType: item.mimeType,
        bytes: item.bytes,
      );
      inputs.add(input);
      queued.add(ReceiptAttachment.queued(input));
    }
    setState(() {
      _attachmentMessage = null;
      _attachments = <ReceiptAttachment>[..._attachments, ...queued];
    });
    final processed = <ReceiptAttachment>[];
    for (final input in inputs) {
      if (!mounted) return;
      _replaceAttachment(
        input.originalId,
        (item) => item.withStatus(AttachmentProcessingStatus.uploading),
      );
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      _replaceAttachment(
        input.originalId,
        (item) => item.withStatus(AttachmentProcessingStatus.processing),
      );
      ReceiptAttachment result;
      try {
        result = await _pipeline.process(input);
      } on Object catch (exception) {
        result = ReceiptAttachment.queued(input)
            .withFailure('Receipt processing failed: $exception');
      }
      if (!mounted) return;
      processed.add(result);
      _replaceAttachment(input.originalId, (_) => result);
    }
    if (!mounted) return;
    await _openReceiptReview(ReceiptReviewQueue(processed));
  }

  ReceiptReviewQueue _reviewQueueForAttachment(ReceiptAttachment attachment) {
    // Saved pixels are the new crop baseline; history belongs to this session.
    return ReceiptReviewQueue([attachment], retainAttachmentsOnDiscard: true);
  }

  Future<void> _openReceiptReview(ReceiptReviewQueue queue) async {
    if (!mounted || _reviewActive) return;
    setState(() {
      _reviewActive = true;
      _receiptReviewQueue = queue;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptReviewDialog(
        queue: queue,
        // Claim originals go through the hosted staging/command bridge before
        // filing. Local review retains draft bytes and never chooses or writes
        // a company Drive destination on an employee's behalf.
        setupKind: _isClaim ? null : SetupKind.expense,
        destinationDate: parseAccountingInputDate(_dateController.text),
        categoryCode:
            _categoryCatalog
                .where((item) => item.displayName == _category)
                .firstOrNull
                ?.code ??
            '',
        onSave: _artifactStore.put,
        onRetry: _retryProcessedAttachment,
        onApplyCropWithRect: _pipeline.crop,
        onConvertToPdf: _pipeline.convertToPdf,
      ),
    );
    if (!mounted) return;
    for (final item in queue.items) {
      _receiptHistories[item.attachment.originalId] = Map<String, dynamic>.from(
        item.toJson(),
      );
    }
    final reviewedIds = queue.items
        .map((item) => item.attachment.originalId)
        .toSet();
    final retained = _attachments
        .where((item) => !reviewedIds.contains(item.originalId))
        .toList();
    final reviewed = <ReceiptAttachment>[
      for (final item in queue.items)
        if (item.state == ReceiptReviewItemState.discarded &&
            queue.retainAttachmentsOnDiscard)
          item.attachment
        else if (item.state == ReceiptReviewItemState.skipped)
          item.workingAttachment.withReviewSkipped()
        else if (!item.isResolved || item.state == ReceiptReviewItemState.saved)
          item.workingAttachment,
    ];
    setState(() {
      _reviewActive = false;
      _attachments = <ReceiptAttachment>[...retained, ...reviewed];
      _receiptReviewQueue = queue.hasUnresolved ? queue : null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _receiptFocusNode.requestFocus();
    });
  }

  Future<ReceiptAttachment> _retryProcessedAttachment(
    ReceiptAttachment attachment,
  ) {
    return _pipeline.process(
      ReceiptAttachmentInput(
        originalId: attachment.originalId,
        batchId: attachment.batchId,
        filename: attachment.filename,
        mimeType: attachment.originalMimeType,
        bytes: attachment.originalBytes,
      ),
    );
  }

  Future<void> _retryAttachment(ReceiptAttachment attachment) async {
    _replaceAttachment(
      attachment.originalId,
      (item) => item.withStatus(AttachmentProcessingStatus.processing),
    );
    final processed = await _pipeline.process(
      ReceiptAttachmentInput(
        originalId: attachment.originalId,
        batchId: attachment.batchId,
        filename: attachment.filename,
        mimeType: attachment.originalMimeType,
        bytes: attachment.originalBytes,
      ),
    );
    await _artifactStore.put(processed);
    if (mounted) _replaceAttachment(attachment.originalId, (_) => processed);
  }

  Future<void> _convertAttachment(ReceiptAttachment attachment) async {
    final converted = await _pipeline.convertToPdf(attachment);
    if (mounted) {
      await _artifactStore.put(converted);
      _replaceAttachment(attachment.originalId, (_) => converted);
    }
  }

  Future<void> _removeAttachment(String originalId) async {
    if (!await confirmAttachmentDeletion(context) || !mounted) return;
    setState(
      () => _attachments = _attachments
          .where((item) => item.originalId != originalId)
          .toList(),
    );
  }

  void _replaceAttachment(
    String originalId,
    ReceiptAttachment Function(ReceiptAttachment item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _attachments = <ReceiptAttachment>[
        for (final item in _attachments)
          item.originalId == originalId ? transform(item) : item,
      ];
    });
  }

  String _categoryMetadata(ExpenseCategory category) {
    final flags = <String>[];
    if (category.reviewRequired) flags.add('Review');
    if (category.approvalRequired) flags.add('Approval');
    if (category.withholdingTaxRequired) flags.add('Withholding');
    if (category.privateApportionmentRequired) {
      flags.add('Private apportionment');
    }
    return flags.isEmpty
        ? category.taxTreatment.name
        : '${category.taxTreatment.name} · ${flags.join(' · ')}';
  }

  String _newLocalId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_attachments.length}';

  String _mimeTypeForName(String name) =>
      NativeExpenseAttachmentPicker.mimeTypeForFilename(name);

  bool get _supportsFileDrop => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
  };
}
