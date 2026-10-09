import 'package:audyt/app/field_row_trial.dart';

import '../../accounting/presentation/widgets/payee_autocomplete_menu.dart';
import '../domain/payment_voucher_source.dart';
import '../domain/payment_voucher_evidence.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/data/accounting_database.dart';
import '../../accounting/domain/transaction_removal.dart';
import '../../accounting/presentation/transaction_removal_controls.dart';

import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_catalog.dart' show paymentMethods;
import 'package:audyt/app/responsive.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:audyt/features/accounting/presentation/payment_account_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:flutter/material.dart';

import '../../../../app/accounting_icons.dart';

import 'package:flutter/services.dart';

class PaymentVouchersPage extends StatefulWidget {
  const PaymentVouchersPage({
    required this.store,
    this.workspace,
    super.key,
    this.compact = false,
    this.defaultCurrencyCode = 'MYR',
    this.accounts,
    this.paymentAccounts,
    this.loadAccounts,
    this.payeeStore,
    this.onAttachmentsPick,
    this.onPaymentAccountSave,
    this.beforeCreate,
  });

  final PaymentVoucherStore store;
  final AccountingWorkspace? workspace;
  final Future<bool> Function()? beforeCreate;
  final bool compact;
  final String defaultCurrencyCode;
  final List<PaymentAccount>? accounts;
  final List<String>? paymentAccounts;
  final List<PaymentAccount> Function()? loadAccounts;
  final PayeeStore? payeeStore;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  final void Function(PaymentAccount)? onPaymentAccountSave;

  @override
  State<PaymentVouchersPage> createState() => _PaymentVouchersPageState();
}

class _PaymentVouchersPageState extends State<PaymentVouchersPage> {
  PaymentVoucherStatus? _filter;
  String? _firstFilter, _secondFilter;
  String? _feedback;
  bool _feedbackIsError = false;

  List<PaymentVoucher> get _visibleVouchers =>
      !AccountingRecordControlsPolicy.visible(widget.store.all.length)
      ? widget.store.all
      : widget.store.all
            .where(
              (voucher) =>
                  _filter == null ||
                  widget.store.verification(voucher).status == _filter,
            )
            .where(
              (voucher) =>
                  _firstFilter == null || voucher.payee == _firstFilter,
            )
            .where(
              (voucher) =>
                  _secondFilter == null ||
                  voucher.paymentAccount == _secondFilter,
            )
            .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return AccountingPageShell(
      includeTopSafeArea: !widget.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AccountingPageHeader(
            routeLabel: 'Payment Vouchers',
            title: 'Payment Vouchers',
            titleKey: 'page-title-payment-vouchers',
            eyebrow: 'Money Out · Control',
            description: 'Review and confirm an existing source payment, then link its completed bank review.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('payment-voucher-create'),
              onPressed: _openCreate,
              leadingIcon: Icons.add_rounded,
              child: const Text('New Voucher'),
            ),
            secondaryActions: [
              if (widget.workspace != null &&
                  widget.workspace!
                          .removedTransactionPage(
                            TransactionRecordKind.paymentVoucher,
                            limit: 1,
                          )
                          .total >
                      0)
                RemovedTransactionsButton(
                  workspace: widget.workspace!,
                  kind: TransactionRecordKind.paymentVoucher,
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                  onView: (record) => _openVoucher(
                    widget.workspace!.database.readRetainedVoucher(
                      widget.workspace!.identity.businessId,
                      record.recordId,
                    ),
                    forceReadOnly: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_feedback != null)
            Semantics(
              liveRegion: true,
              child: AccountingAlert.build(
                context,
                key: const ValueKey('payment-voucher-feedback'),
                title: _feedbackIsError
                    ? 'Voucher Action Failed'
                    : 'Voucher Updated',
                description: _feedback!,
                tone: _feedbackIsError
                    ? AccountingAlertTone.critical
                    : AccountingAlertTone.positive,
                bottomGap: accountingContentInset,
              ),
            ),
          AccountingAlert.build(
            context,
            key: const ValueKey('payment-voucher-source-banner'),
            title: 'Source-linked payments',
            description: 'Confirm the source payment and bank review without another payment or expense posting.',
          ),
          const SizedBox(height: 20),
          AccountingRecordControls(
            recordCount: widget.store.all.length,
            child: _buildFilter(context),
          ),
          if (AccountingRecordControlsPolicy.visible(widget.store.all.length))
            const SizedBox(height: 16),
          if (_visibleVouchers.isEmpty)
            _buildEmptyState(context)
          else
            AccountingRecordList(
              paginationKey: 'payment-vouchers',
              totalCount: widget.store.all.length,
              defaultPageSize: 5,
              children: [
                for (final voucher in _visibleVouchers)
                  _buildVoucherCard(context, voucher),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilter(BuildContext context) => Wrap(
    spacing: accountingContentInset,
    runSpacing: AccountingPageControlScope.runGapOf(context),
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      AccountingRecordFilter(
        label: 'Status',
        options: PaymentVoucherStatus.values.map((s) => s.label),
        value: _filter?.label,
        controlKey: const ValueKey('payment-voucher-filter'),
        onChanged: (value) => setState(
          () => _filter = value == null
              ? null
              : PaymentVoucherStatus.values.firstWhere((s) => s.label == value),
        ),
      ),
      AccountingRecordFilter(
        label: 'Payee',
        options: widget.store.all.map((r) => r.payee),
        value: _firstFilter,
        controlKey: const ValueKey('payment-voucher-first-filter'),
        onChanged: (value) => setState(() => _firstFilter = value),
      ),
      AccountingRecordFilter(
        label: 'Account',
        options: widget.store.all.map((r) => r.paymentAccount),
        value: _secondFilter,
        controlKey: const ValueKey('payment-voucher-second-filter'),
        onChanged: (value) => setState(() => _secondFilter = value),
      ),
      if (_filter != null || _firstFilter != null || _secondFilter != null)
        AccountingButton.outline(
          context,
          key: const ValueKey('payment-voucher-clear-filters'),
          onPressed: () => setState(() {
            _filter = null;
            _firstFilter = null;
            _secondFilter = null;
          }),
          leadingIcon: Icons.filter_alt_off_outlined,
          child: const Text('Clear'),
        ),
    ],
  );

  Widget _buildEmptyState(BuildContext context) {
    return AccountingEmptyState.card(
      context,
      key: const ValueKey('payment-voucher-empty-state'),
      title: 'No vouchers in this state',
      description: 'Create one only when an existing source is ready for payment control.',
      icon: Icons.payments_outlined,
    );
  }

  Widget _buildVoucherCard(BuildContext context, PaymentVoucher voucher) {
    final current = widget.store.verification(voucher);
    final workflow = _actionsFor(voucher, current.status);
    final evidence = <Widget>[
      AccountingButton.outline(
        context,
        key: ValueKey('voucher-view-${voucher.id}'),
        onPressed: () => _openVoucher(voucher),
        child: Text(_currentEditingLocked(voucher) ? 'View' : 'Edit'),
      ),
      if (widget.workspace != null)
        TransactionRemoveButton(
          key: ValueKey('voucher-delete-${voucher.id}'),
          workspace: widget.workspace!,
          kind: TransactionRecordKind.paymentVoucher,
          recordId: voucher.id,
          onChanged: () {
            if (mounted) setState(() {});
          },
        )
      else
        AccountingButton.iconOnly(
          context,
          key: ValueKey('voucher-delete-${voucher.id}'),
          onPressed: null,
          icon: Icons.delete_outline,
          tooltip: 'Deletion unavailable for this record in this workspace',
        ),
    ];
    return KeyedSubtree(
      key: ValueKey<String>('voucher-row-${voucher.id}'),
      child: Padding(
        padding: accountingContentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AccountingRecordRow(
              topRightInfo: true,
              padding: EdgeInsets.zero,
              title: voucher.payee,
              status: AccountingBadge.build(
                context,
                key: ValueKey<String>('voucher-status-${voucher.id}'),
                label: current.status.label,
              ),
              statusWidth: AccountingBadge.measuredWidth(
                context,
                current.status.label,
              ),
              compactStatus: Tooltip(
                message: current.explanation ?? current.status.label,
                child: AccountingBadge.build(
                  context,
                  key: ValueKey<String>('voucher-status-${voucher.id}'),
                  label: current.status.compactLabel,
                ),
              ),
              details: Tooltip(
                message: 'Source ID: ${voucher.sourceId}',
                child: Text(
                  '${voucher.reference} · ${voucher.sourceType.label} · ${_dateText(voucher.paymentDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AccountingTypography.helper(context),
                ),
              ),
              trailing: Text(
                formatAccountingMoney(context, voucher.amount),
                style: AccountingTypography.fieldLabel(context),
              ),
              trailingBelow: AccountingRecordActions(
                actions: [
                  AccountingOverflowMenu(
                    triggerKey: ValueKey('voucher-more-${voucher.id}'),
                    actions: [
                      ...workflow,
                      for (final attachment in voucher.attachments)
                        AccountingOverflowAction(
                          key: ValueKey(
                            'voucher-preview-${attachment.originalId}',
                          ),
                          label: 'View ${attachment.filename}',
                          icon: attachment.originalMimeType.startsWith('image/')
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                          onPressed: () =>
                              showAttachmentPreview(context, attachment),
                        ),
                    ],
                  ),
                ],
                trailing: evidence,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<AccountingOverflowAction> _actionsFor(
    PaymentVoucher voucher,
    PaymentVoucherStatus status,
  ) {
    switch (status) {
      case PaymentVoucherStatus.draft:
        return <AccountingOverflowAction>[
          AccountingOverflowAction(
            key: ValueKey<String>('voucher-submit-${voucher.id}'),
            label: 'Submit For Approval',
            icon: Icons.checklist_outlined,
            onPressed: () => _submit(voucher),
          ),
        ];
      case PaymentVoucherStatus.pendingApproval:
        return <AccountingOverflowAction>[
          AccountingOverflowAction(
            key: ValueKey<String>('voucher-approve-${voucher.id}'),
            label: 'Approve',
            icon: Icons.check_circle_outline,
            onPressed: () => _approve(voucher),
          ),
        ];
      case PaymentVoucherStatus.approved:
      case PaymentVoucherStatus.paymentOrdered:
        return <AccountingOverflowAction>[
          AccountingOverflowAction(
            key: ValueKey<String>('voucher-pay-${voucher.id}'),
            label: 'Record Payment',
            icon: Icons.payment_outlined,
            onPressed: () => _confirmPayment(voucher),
          ),
        ];
      case PaymentVoucherStatus.paid:
      case PaymentVoucherStatus.processed:
        return <AccountingOverflowAction>[
          AccountingOverflowAction(
            key: ValueKey<String>('voucher-reconcile-${voucher.id}'),
            label: 'Reconcile',
            icon: Icons.checklist_outlined,
            onPressed: () => _reconcile(voucher),
          ),
        ];
      case PaymentVoucherStatus.reconciled:
      case PaymentVoucherStatus.onHold:
      case PaymentVoucherStatus.cancelled:
        return const <AccountingOverflowAction>[];
    }
  }

  Future<void> _openCreate() async {
    if (widget.beforeCreate != null && !await widget.beforeCreate!()) return;
    if (!mounted) return;
    await _openVoucher(null);
  }

  Future<void> _openVoucher(
    PaymentVoucher? initial, {
    bool forceReadOnly = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => PaymentVoucherEditorDialog(
        id: initial?.id ?? _newId(),
        initial: initial,
        verification: initial == null
            ? null
            : widget.store.verification(initial),
        sources: widget.store.hasSourceProvider ? widget.store.sources : null,
        readOnly:
            forceReadOnly ||
            (initial != null && _currentEditingLocked(initial)),
        defaultCurrencyCode: widget.defaultCurrencyCode,
        accounts: _configuredAccounts,
        payeeStore: widget.payeeStore,
        onAttachmentsPick: widget.onAttachmentsPick,
        onPaymentAccountSave: widget.onPaymentAccountSave,
        onSaveDraft: (voucher) {
          widget.store.save(voucher, expectedCurrent: initial);
          if (mounted) setState(() {});
        },
        onSubmit: (voucher) {
          widget.store.saveAndSubmit(voucher, expectedCurrent: initial);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  bool _currentEditingLocked(PaymentVoucher voucher) {
    // A lifecycle label or saved acknowledgement is not a current lock.
    // Resolve the source payment and the existing completed-review authority;
    // reopening releases that authority while historical evidence is retained.
    if (!widget.store.hasFinancialEvidence) return false;
    try {
      final payment = widget.store.loadPaymentEvidence!(voucher);
      final workspace = widget.workspace;
      if (workspace != null) {
        return workspace.database.isJournalReconciled(
          workspace.identity.businessId,
          payment.journalId,
        );
      }
      widget.store.loadReconciliationEvidence!(voucher, payment);
      return true;
    } on StateError {
      return false;
    }
  }

  List<PaymentAccount> get _configuredAccounts {
    final supplied = widget.loadAccounts?.call() ?? widget.accounts;
    if (supplied != null) return List<PaymentAccount>.unmodifiable(supplied);
    final names = widget.paymentAccounts ?? const <String>[];
    final accounts = <PaymentAccount>[];
    for (var index = 0; index < names.length; index++) {
      try {
        accounts.add(
          PaymentAccount.create(
            id: 'payment-voucher-account-${index + 1}',
            name: names[index],
            type: PaymentAccountType.other,
            currencyCode: widget.defaultCurrencyCode,
          ),
        );
      } on Object {
        // Invalid injected account settings remain unavailable; currency is
        // never silently substituted for a malformed account context.
      }
    }
    return List<PaymentAccount>.unmodifiable(accounts);
  }

  void _submit(PaymentVoucher voucher) {
    try {
      widget.store.submit(voucher.id);
      setState(() {});
    } on Object catch (exception) {
      _error('Voucher could not be submitted: $exception');
    }
  }

  void _approve(PaymentVoucher voucher) {
    try {
      widget.store.approve(voucher.id);
      setState(() {});
    } on Object catch (exception) {
      _error('Voucher could not be approved: $exception');
    }
  }

  Future<void> _confirmPayment(PaymentVoucher voucher) async {
    PaymentVoucherPaymentEvidence? reviewed;
    var sourceDescription = '${voucher.sourceType.label} · ${voucher.sourceId}';
    try {
      reviewed = widget.store.loadPaymentEvidence?.call(voucher);
      if (voucher.sourceType == PaymentVoucherSourceType.billSettlement) {
        final source = widget.store.sources
            .where(
              (s) => s.type == voucher.sourceType && s.id == voucher.sourceId,
            )
            .firstOrNull;
        if (source?.detail != null) {
          sourceDescription = '${voucher.sourceType.label} · ${source!.detail}';
        }
      }
    } on Object catch (exception) {
      _error('Payment could not be recorded: $exception');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        key: ValueKey<String>('voucher-payment-confirmation-${voucher.id}'),
        title: 'Record payment?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountingInformationRows(
              rows: [
                ('Source', sourceDescription),
                ('Payee', voucher.payee),
                (
                  'Amount',
                  formatAccountingMoney(dialogContext, voucher.amount),
                ),
                ('Payment Account', voucher.paymentAccount),
                if (reviewed != null)
                  (
                    'Posted Date',
                    formatAccountingInputDate(reviewed.paymentDate),
                  ),
                if (reviewed != null &&
                    reviewed.movementAmount != voucher.amount)
                  (
                    'Bank Movement',
                    formatAccountingMoney(
                      dialogContext,
                      reviewed.movementAmount,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            Text(
              reviewed == null
                  ? 'This records payment for the linked source. No second expense will be posted.'
                  : 'Confirm this existing source payment and use its actual date on the voucher. No additional payment or expense will be posted.',
            ),
          ],
        ),
        actions: <Widget>[
          AccountingButton.ghost(
            dialogContext,
            key: null,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AccountingButton.primary(
            dialogContext,
            key: ValueKey<String>('voucher-confirm-pay-${voucher.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      widget.store.recordPayment(
        voucher.id,
        paidAt: reviewed == null ? DateTime.now().toUtc() : null,
        expectedCurrent: voucher,
        expectedPaymentEvidence: reviewed,
      );
      setState(() => _feedback = 'Payment recorded');
      _message('Payment recorded');
    } on Object catch (exception) {
      _error('Payment could not be recorded: $exception');
    }
  }

  void _reconcile(PaymentVoucher voucher) {
    try {
      widget.store.reconcile(
        voucher.id,
        reconciledAt: widget.store.hasFinancialEvidence
            ? null
            : DateTime.now().toUtc(),
        expectedCurrent: voucher,
      );
      setState(() => _feedback = 'Voucher reconciled');
      _message('Voucher reconciled');
    } on Object catch (exception) {
      _error('Voucher could not be reconciled: $exception');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = false;
    });
  }

  void _error(String message) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = true;
    });
  }

  String _newId() => 'voucher-${DateTime.now().microsecondsSinceEpoch}';
}

typedef PaymentVoucherPersistHandler = FutureOr<void> Function(
  PaymentVoucher voucher,
);

class PaymentVoucherEditorDialog extends StatefulWidget {
  const PaymentVoucherEditorDialog({
    required this.id,
    required this.onSaveDraft,
    required this.onSubmit,
    super.key,
    this.initial,
    this.verification,
    this.sources,
    this.readOnly = false,
    this.defaultCurrencyCode = 'MYR',
    this.accounts = const <PaymentAccount>[],
    this.payeeStore,
    this.onAttachmentsPick,
    this.onPaymentAccountSave,
    this.initialStatementAmount,
    this.initialStatementDate,
    this.initialStatementReference,
    this.initialStatementAccount,
  });

  final String id;
  final PaymentVoucherPersistHandler onSaveDraft;
  final PaymentVoucherPersistHandler onSubmit;
  final PaymentVoucher? initial;
  final PaymentVoucherVerification? verification;
  final List<PaymentVoucherSource>? sources;
  final bool readOnly;
  final String defaultCurrencyCode;
  final List<PaymentAccount> accounts;
  final PayeeStore? payeeStore;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  final void Function(PaymentAccount)? onPaymentAccountSave;
  final Money? initialStatementAmount;
  final DateTime? initialStatementDate;
  final String? initialStatementReference;
  final PaymentAccount? initialStatementAccount;

  @override
  State<PaymentVoucherEditorDialog> createState() =>
      _PaymentVoucherEditorDialogState();
}

class _PaymentVoucherEditorDialogState
    extends State<PaymentVoucherEditorDialog> {
  bool get _currentEdit =>
      widget.initial != null &&
      widget.initial!.status != PaymentVoucherStatus.draft;
  String? get _saveUnavailableReason => _currentEdit
      ? 'Saving changes to this Payment Voucher is unavailable. Your saved voucher is unchanged.'
      : null;
  final _formKey = GlobalKey<FormState>();
  final _editorScroll = ScrollController();
  final _editingFocus = FocusScopeNode();
  late final String _openingInput;
  bool _closePromptOpen = false;
  final _sourceId = TextEditingController();
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _method = TextEditingController();
  final _date = TextEditingController();
  final _reference = TextEditingController();
  final _allocation = TextEditingController();
  late final List<PaymentAccount> _accounts;
  late final PayeeStore _payeeStore;
  final _payeeFieldAnchor = GlobalKey();
  TextEditingController? _payeeAutocompleteController;
  PaymentAccount? _paymentAccount;
  CurrencyPresentation? _currency;
  late String _currencyCode;
  String _payeeValue = '';
  PaymentVoucherSourceType _sourceType = PaymentVoucherSourceType.directExpense;
  List<ReceiptAttachment> _attachments = <ReceiptAttachment>[];
  final _pipeline = const ReceiptDocumentPipeline();
  final ReceiptArtifactStore _artifactStore = InMemoryReceiptArtifactStore();
  ReceiptReviewQueue? _receiptReviewQueue;
  bool _reviewActive = false;
  bool _isDragOver = false;
  String? _attachmentMessage;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _accounts = List<PaymentAccount>.of(widget.accounts);
    _payeeStore = widget.payeeStore ?? PayeeStore(payees: PayeeCatalog.demo);
    _sourceType =
        initial?.sourceType ??
        widget.sources?.firstOrNull?.type ??
        PaymentVoucherSourceType.directExpense;
    _sourceId.text = initial?.sourceId ?? '';
    _payeeValue = initial?.payee ?? '';
    _amount.text = initial == null
        ? (widget.initialStatementAmount == null
              ? ''
              : _amountText(widget.initialStatementAmount!))
        : _amountText(initial.amount);
    _account.text = initial?.paymentAccount ?? '';
    _method.text = initial?.paymentMethod ?? '';
    _date.text = formatAccountingInputDate(
      initial?.paymentDate ?? widget.initialStatementDate ?? DateTime.now(),
    );
    _reference.text =
        initial?.reference ?? widget.initialStatementReference ?? '';
    _allocation.text = initial?.allocations.join(', ') ?? '';
    _attachments = List<ReceiptAttachment>.from(
      initial?.attachments ?? const <ReceiptAttachment>[],
    );
    if (initial?.paymentAccountId != null) {
      for (final account in _accounts) {
        if (account.id == initial!.paymentAccountId) _paymentAccount = account;
      }
    } else {
      _paymentAccount = _findAccount(_account.text);
    }
    if (_paymentAccount == null && initial == null && _accounts.isNotEmpty) {
      _paymentAccount =
          _accounts
              .where(
                (account) => account.id == widget.initialStatementAccount?.id,
              )
              .firstOrNull ??
          _accounts.first;
      _account.text = _paymentAccount!.name;
    }
    _currencyCode =
        initial?.amount.currency ??
        _paymentAccount?.currency.code ??
        widget.defaultCurrencyCode.trim();
    _initializeCurrency();
    _amount.text = formatAccountingMoneyInputText(
      _amount.text,
      Currency.parse(_currencyCode).fractionDigits,
    );
    _openingInput = _inputSnapshot();
  }

  @override
  void dispose() {
    _editorScroll.dispose();
    _editingFocus.dispose();
    _sourceId.dispose();
    _amount.dispose();
    _account.dispose();
    _method.dispose();
    _date.dispose();
    _reference.dispose();
    _allocation.dispose();
    _receiptReviewQueue?.dispose();
    super.dispose();
  }

  PaymentAccount? _findAccount(String name) {
    for (final account in _accounts) {
      if (account.name == name) return account;
    }
    return null;
  }

  void _initializeCurrency() {
    try {
      _currency = CurrencyPresentation.fromCode(_currencyCode);
      _currencyCode = _currency!.code;
    } on FormatException {
      _currency = null;
    }
  }

  String _amountText(Money amount) {
    final currency = Currency.parse(amount.currency);
    final magnitude = BigInt.from(amount.minorUnits)
        .abs()
        .toString()
        .padLeft(currency.fractionDigits + 1, '0');
    final split = magnitude.length - currency.fractionDigits;
    final value = currency.fractionDigits == 0
        ? magnitude
        : '${magnitude.substring(0, split)}.${magnitude.substring(split)}';
    return amount.minorUnits < 0 ? '-$value' : value;
  }

  String _inputSnapshot() => jsonEncode([
    _sourceType.name,
    _sourceId.text,
    _payeeAutocompleteController?.text ?? _payeeValue,
    _amount.text,
    _account.text,
    _paymentAccount?.id,
    _currencyCode,
    _method.text,
    _date.text,
    _reference.text,
    _allocation.text,
    if (_receiptReviewQueue?.hasUnresolved == true)
      [
        for (final item in _receiptReviewQueue!.items.where(
          (item) => !item.isResolved,
        ))
          [
            item.workingAttachment.originalId,
            item.workingAttachment.derivativeSha256,
            item.state.name,
          ],
      ],
    [
      for (final attachment in _attachments)
        [
          attachment.originalId,
          attachment.filename,
          attachment.originalSha256,
          attachment.derivativeId,
          attachment.derivativeSha256,
          attachment.pdfSha256,
          attachment.status.name,
          attachment.reviewSkipped,
          attachment.optimizationRecipe,
        ],
    ],
  ]);

  Future<void> _handleClose() async {
    if (_busy || _reviewActive || _closePromptOpen) return;
    if (widget.readOnly || _inputSnapshot() == _openingInput) {
      Navigator.of(context).pop();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('voucher-discard-close'),
        keepEditingKey: const ValueKey('voucher-keep-editing'),
        discardKey: const ValueKey('voucher-discard-changes'),
      );
      if (!mounted) return;
      if (discard) {
        Navigator.of(context).pop();
      } else {
        _editingFocus.requestFocus();
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Widget _guardInput(Widget child) => FocusScope(
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
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    const width = AccountingPopoutTokens.widerContentWidth;
    final maxHeight = math.min(720.0, math.max(280.0, viewport.height - 240));
    return _guardInput(
      AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.wider,
        key: const ValueKey('payment-voucher-editor-dialog'),
        onClose: _handleClose,
        closeKey: const ValueKey('voucher-editor-close'),
        canClose: !_busy && !_reviewActive,
        title: widget.initial == null
            ? 'New Payment Voucher'
            : widget.readOnly
            ? 'View Payment Voucher'
            : 'Edit Payment Voucher',
        formFooter: !widget.readOnly,
        description: widget.readOnly
            ? 'Saved source and payment control details.'
            : _currentEdit
            ? 'Edit current source and payment control details.'
            : 'Attach supporting documents before submission.',
        scrollable: false,
        content: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              controller: _editorScroll,
              child: Form(key: _formKey, child: _buildFormFields(context)),
            ),
          ),
        ),
        actions: <Widget>[
          if (!widget.readOnly)
            AccountingButton.ghost(
              context,
              key: null,
              onPressed: _busy || _reviewActive ? null : _handleClose,
              child: const Text('Cancel'),
            ),
          if (!widget.readOnly && !_currentEdit)
            AccountingButton.outline(
              context,
              key: const ValueKey('voucher-save-draft'),
              onPressed: _busy ? null : () => _persist(submit: false),
              child: const Text('Save Draft'),
            ),
          if (!widget.readOnly)
            Tooltip(
              message: _saveUnavailableReason ?? '',
              child: AccountingButton.primary(
                context,
                key: ValueKey(
                  _currentEdit ? 'voucher-save-current' : 'voucher-submit',
                ),
                onPressed: _busy || _saveUnavailableReason != null
                    ? null
                    : () => _persist(submit: true),
                child: Text(_currentEdit ? 'Save Changes' : 'Submit'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFormFields(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canPair = AccountingResponsive.fitsWithContentGap(
          constraints.maxWidth,
          const [
            AccountingResponsive.fieldMinWidth,
            AccountingResponsive.fieldMinWidth,
          ],
        );
        final fields = <Widget>[
          AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Linked source type',
                choices: [
                  'Select linked source type',
                  for (final type
                      in widget.sources == null
                          ? PaymentVoucherSourceType.values
                          : {
                              _sourceType,
                              ...widget.sources!.map((s) => s.type),
                            })
                    type.label,
                ],
                builder: (assignedWidth) =>
                    _buildSourceTypeField(context, width: assignedWidth),
              ),
              if (widget.sources == null)
                AccountingOrdinaryFieldSlot(
                  label: 'Source ID',
                  builder: (_) => _field(
                    _sourceId,
                    'Source ID',
                    'voucher-source-id',
                    required: true,
                    helperText:
                        'Existing expense, claim payment, or bill link.',
                  ),
                )
              else
                AccountingOrdinaryFieldSlot(
                  label: 'Saved source',
                  choices: [
                    widget.sources!.where((s) => s.type == _sourceType).isEmpty
                        ? 'No saved sources available'
                        : 'Select saved source',
                    for (final source in widget.sources!.where(
                      (s) => s.type == _sourceType,
                    ))
                      _savedSourceLabel(context, source),
                  ],
                  builder: (assignedWidth) =>
                      _buildSavedSourceField(context, width: assignedWidth),
                ),
              AccountingOrdinaryFieldSlot(
                label: 'Payee *',
                contentSample: 'Search or enter payee',
                builder: (_) => _buildPayeeField(context),
              ),
              AccountingOrdinaryFieldSlot(
                label: 'Payment Account *',
                headerActionLabel:
                    widget.readOnly || widget.onPaymentAccountSave == null
                    ? null
                    : 'Add Account',
                choices: _accounts.isEmpty || widget.readOnly
                    ? const []
                    : [
                        'Select payment account',
                        if (_paymentAccount == null &&
                            _account.text.trim().isNotEmpty)
                          'Unavailable: ${_account.text.trim()}',
                        for (final account in _accounts) account.displayLabel,
                      ],
                builder: (assignedWidth) =>
                    _buildAccountField(context, width: assignedWidth),
              ),
            ],
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          _buildResponsivePair(
            _field(
              _amount,
              'Amount (${_currency?.amountSymbol ?? CurrencyPresentation.fromCode(_currencyCode).amountSymbol})',
              'voucher-amount',
              required: true,
              decimal: true,
              inputFormatters: [
                AccountingMoneyInputFormatter(
                  Currency.parse(_currencyCode).fractionDigits,
                ),
              ],
              helperText: 'Currency follows the linked account or configured workspace currency.',
            ),
            _field(
              _date,
              'Payment date',
              'voucher-date',
              compactDate: true,
              required: true,
              helperText: 'Enter numbers as DD-MM-YYYY.',
              inputFormatters: const <TextInputFormatter>[DateInputFormatter()],
              keyboardType: TextInputType.number,
              suffixIcon: accountingCalendarButton(
                context,
                controller: _date,
                label: 'Payment Date',
                enabled: !_busy,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                onPicked: () => setState(() {}),
              ),
            ),
            canPair: canPair,
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Payment Method',
                choices: [
                  'Select payment method',
                  ...paymentMethods,
                  if (_method.text.trim().isNotEmpty) _method.text.trim(),
                ],
                builder: (assignedWidth) =>
                    _buildPaymentMethodField(context, width: assignedWidth),
              ),
              AccountingOrdinaryFieldSlot(
                label: 'Reference',
                builder: (_) => _field(
                  _reference,
                  'Reference',
                  'voucher-reference',
                  required: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          _field(
            _allocation,
            'Related Records',
            'voucher-allocation',
            helperText: 'Enter related claim, bill or expense references, separated by commas.',
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          _buildAttachmentField(context),
        ];
        return KeyedSubtree(
          key: ValueKey<String>(
            canPair ? 'voucher-editor-two-column' : 'voucher-editor-stacked',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                AccountingAlert.build(
                  context,
                  key: const ValueKey('voucher-editor-error'),
                  title: 'Could Not Save Voucher',
                  description: _error!,
                  tone: AccountingAlertTone.critical,
                  bottomGap: accountingContentInset,
                ),
              if (widget.verification != null &&
                  (widget.verification!.explanation != null ||
                      widget.initial!.paymentEvidence != null ||
                      widget.initial!.reconciliationEvidence != null)) ...[
                AccountingAlert.build(
                  context,
                  key: const ValueKey('voucher-current-verification'),
                  title: 'Current Status: ${widget.verification!.status.label}',
                  description:
                      widget.verification!.explanation ??
                      (widget.verification!.reconciliationVerified
                          ? 'The linked payment and current completed bank review have been verified.'
                          : widget.verification!.paymentVerified
                          ? 'The linked posted payment has been verified.'
                          : 'Current payment and bank review verification is unavailable.'),
                  tone:
                      widget.verification!.explanation == null &&
                          widget.verification!.paymentVerified
                      ? AccountingAlertTone.positive
                      : AccountingAlertTone.warning,
                  bottomGap: accountingContentInset,
                ),
                SelectionArea(
                  child: AccountingInformationRows(
                    rows: [
                      if (widget.initial!.paymentEvidence
                          case final payment?) ...[
                        (
                          'Posted Payment',
                          formatAccountingInputDate(payment.paymentDate),
                        ),
                        ('Journal', payment.journalId.value),
                        ('Journal Line', '${payment.lineIndex + 1}'),
                      ],
                      if (widget.initial!.reconciliationEvidence
                          case final bank?) ...[
                        (
                          'Saved Bank Review',
                          formatAccountingInputDate(bank.approvedAt),
                        ),
                        ('Reconciliation', bank.completionId.value),
                        ('Match', bank.acceptanceId.value),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: accountingContentInset),
              ],
              for (var i = 0; i < fields.length; i++)
                IgnorePointer(
                  ignoring: widget.readOnly && i < fields.length - 1,
                  child: ExcludeFocus(
                    excluding: widget.readOnly && i < fields.length - 1,
                    child: fields[i],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResponsivePair(
    Widget first,
    Widget second, {
    required bool canPair,
  }) {
    if (!canPair) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          first,
          const SizedBox(height: AccountingResponsive.groupGap),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: first),
        const SizedBox(width: AccountingResponsive.groupGap),
        Expanded(child: second),
      ],
    );
  }

  Widget _buildSourceTypeField(BuildContext context, {required double width}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(
          context,
          'Linked source type',
          required: true,
          guidance: 'Links one existing expense, claim payment, or bill to this voucher. Record Payment confirms its posted movement; Reconcile confirms the completed bank review.',
        ),
        const SizedBox(height: 8),
        AccountingSelector<PaymentVoucherSourceType>(
          assignedWidth: width,
          options: <AccountingSelectorOption<PaymentVoucherSourceType>>[
            for (final sourceType
                in widget.sources == null
                    ? PaymentVoucherSourceType.values
                    : {_sourceType, ...widget.sources!.map((s) => s.type)})
              AccountingSelectorOption<PaymentVoucherSourceType>(
                value: sourceType,
                label: sourceType.label,
              ),
          ],
          value: _sourceType,
          onChanged: _busy
              ? (_) {}
              : (value) {
                  if (value != null) {
                    setState(() {
                      if (_sourceType != value) _sourceId.clear();
                      _sourceType = value;
                    });
                  }
                },
          hintText: 'Select linked source type',
          controlKey: const ValueKey('voucher-source-type-control'),
          triggerKey: const ValueKey('voucher-source-type'),
          menuKey: const ValueKey('voucher-source-type-menu'),
          semanticsLabel: 'Linked source type, required',
          enabled: !_busy,
        ),
      ],
    );
  }

  String _savedSourceLabel(BuildContext context, PaymentVoucherSource source) =>
      '${source.payee} · ${formatAccountingMoney(context, source.amount)} · ${source.detail ?? source.id.substring(source.id.length > 6 ? source.id.length - 6 : 0)}';

  Widget _buildSavedSourceField(BuildContext context, {required double width}) {
    final sources = widget.sources!
        .where((s) => s.type == _sourceType)
        .toList();
    final selected = sources.where((s) => s.id == _sourceId.text).firstOrNull;
    final retainedId = _sourceId.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          context,
          'Saved source',
          required: true,
          guidance:
              'The saved source supplies the payee, amount, account and date.',
        ),
        const SizedBox(height: 8),
        AccountingSelector<PaymentVoucherSource>(
          assignedWidth: width,
          options: [
            for (final s in sources)
              AccountingSelectorOption(
                value: s,
                preserveLabelCase: true,
                label: _savedSourceLabel(context, s),
              ),
          ],
          value: selected,
          onChanged: (source) {
            if (source == null) return;
            setState(() {
              _sourceId.text = source.id;
              _payeeValue = source.payee;
              _payeeAutocompleteController?.text = source.payee;
              _amount.text = formatAccountingMoneyInputText(
                _amountText(source.amount),
                Currency.parse(source.amount.currency).fractionDigits,
              );
              _paymentAccount = _accounts
                  .where((a) => a.id == source.paymentAccountId)
                  .firstOrNull;
              _account.text = _paymentAccount?.name ?? '';
              _currencyCode = source.amount.currency;
              _initializeCurrency();
              _date.text = formatAccountingInputDate(source.date);
            });
          },
          enabled: !_busy && !widget.readOnly && sources.isNotEmpty,
          hintText: sources.isEmpty
              ? 'No saved sources available'
              : 'Select saved source',
          controlKey: const ValueKey('voucher-source-control'),
          triggerKey: const ValueKey('voucher-source-selector'),
          menuKey: const ValueKey('voucher-source-menu'),
          semanticsLabel: 'Saved source, required',
          helperText: selected == null && retainedId.isNotEmpty
              ? widget.readOnly
                    ? 'Retained source: $retainedId. The saved source is unavailable.'
                    : 'Retained source: $retainedId. Choose an available source before saving.'
              : null,
        ),
      ],
    );
  }

  Widget _buildPayeeField(BuildContext context) {
    final candidates = _payeeStore.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(
          context,
          'Payee',
          required: true,
          guidance: 'Use the shared payee directory when available.',
        ),
        const SizedBox(height: 8),
        Autocomplete<Payee>(
          key: const ValueKey('voucher-payee-autocomplete'),
          displayStringForOption: (payee) => payee.name,
          optionsBuilder: (value) => [
            if (!widget.readOnly)
              Payee(
                id: '__add-payee__',
                name: 'Add Payee',
                type: PayeeType.other,
              ),
            ...filterPayees(candidates, value.text),
          ],
          onSelected: (payee) {
            if (payee.id == '__add-payee__') {
              FocusScope.of(context).unfocus();
              _payeeAutocompleteController?.value = TextEditingValue(
                text: _payeeValue,
                selection: TextSelection.collapsed(offset: _payeeValue.length),
              );
              _addPayee();
            } else {
              _payeeValue = payee.name;
            }
          },
          optionsViewBuilder: (context, onSelected, options) {
            final optionList = options.toList(growable: false);
            return PayeeAutocompleteMenu(
              triggerKey: _payeeFieldAnchor,
              surfaceKey: const ValueKey('voucher-payee-menu'),
              contentWidth: payeeAutocompleteMenuWidth(
                context,
                candidates,
                rowHorizontalInset: 10,
                extraLabels: const ['Add Payee'],
              ),
              itemCount: optionList.length,
              itemBuilder: (context, index) {
                final payee = optionList[index];
                if (payee.id == '__add-payee__') {
                  return accountingSelectorCreationAction(
                    context,
                    key: const ValueKey('voucher-add-payee'),
                    label: 'Add Payee',
                    onPressed: _busy
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            _addPayee();
                          },
                  );
                }
                return InkWell(
                  key: ValueKey<String>('voucher-payee-option-${payee.id}'),
                  onTap: () => onSelected(payee),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            payee.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(
                          width: AccountingSelectionLabel.minimumTextGap,
                        ),
                        AccountingSelectionLabel.build(
                          context,
                          label: payee.typeLabel,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _payeeAutocompleteController = controller;
            if (controller.text.isEmpty && _payeeValue.isNotEmpty) {
              controller.value = TextEditingValue(
                text: _payeeValue,
                selection: TextSelection.collapsed(offset: _payeeValue.length),
              );
            }
            return KeyedSubtree(
              key: _payeeFieldAnchor,
              child: TextFormField(
                key: const ValueKey('voucher-payee'),
                controller: controller,
                focusNode: focusNode,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                onChanged: (value) => _payeeValue = value,
                onFieldSubmitted: (_) => onFieldSubmitted(),
                decoration: accountingInputDecoration(
                  context,
                  hintText: 'Search or enter payee',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _addAccount() async {
    final account = await showPaymentAccountDialog(
      context,
      preferredCurrencyCode: _currencyCode,
      newId: () => 'account-${DateTime.now().microsecondsSinceEpoch}',
      buildLabel: (context, label, required) =>
          _label(context, label, required: required),
    );
    if (account == null || !mounted) return;
    try {
      widget.onPaymentAccountSave?.call(account);
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
    setState(() => _accounts.add(account));
    _selectAccount(account);
  }

  Widget _buildAccountField(BuildContext context, {required double width}) {
    if (widget.readOnly) {
      return _field(
        _account,
        'Payment Account',
        'voucher-account',
        required: true,
        helperText: 'Payment account saved with this voucher.',
      );
    }
    if (_accounts.isEmpty && widget.onPaymentAccountSave == null) {
      return _field(
        _account,
        'Payment account',
        'voucher-account',
        required: true,
        helperText: 'Currency uses the configured workspace account currency.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(
          context,
          'Payment Account',
          required: true,
          guidance: _paymentAccount == null && _account.text.trim().isNotEmpty
              ? 'The saved payment account is unavailable. Its retained name and currency are unchanged until another account is selected.'
              : 'The selected account supplies the voucher currency.',
        ),
        const SizedBox(height: 8),
        AccountingSelector<PaymentAccount>(
          assignedWidth: width,
          options: <AccountingSelectorOption<PaymentAccount>>[
            if (widget.onPaymentAccountSave != null)
              AccountingSelectorOption(
                value: PaymentAccount.create(
                  id: '__add-account__',
                  name: 'Add Account',
                  type: PaymentAccountType.other,
                  currencyCode: _currencyCode,
                ),
                label: 'Add Account',
                leading: const AccountingIcon(Icons.add),
                key: const ValueKey('voucher-add-account'),
                onPressed: _busy ? null : _addAccount,
              ),
            for (final account in _accounts)
              AccountingSelectorOption<PaymentAccount>(
                value: account,
                label: account.displayLabel,
                preserveLabelCase: true,
              ),
          ],
          value: _paymentAccount,
          onChanged: _busy ? (_) {} : _selectAccount,
          hintText: _paymentAccount == null && _account.text.trim().isNotEmpty
              ? 'Unavailable: ${_account.text.trim()}'
              : 'Select payment account',
          controlKey: const ValueKey('voucher-account-control'),
          triggerKey: const ValueKey('voucher-account'),
          menuKey: const ValueKey('voucher-account-menu'),
          semanticsLabel: 'Payment account, required',
          enabled: !_busy,
          menuWidth: 360,
        ),
      ],
    );
  }

  Widget _buildPaymentMethodField(
    BuildContext context, {
    required double width,
  }) {
    final selected = _method.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(context, 'Payment Method', required: true),
        const SizedBox(height: 8),
        AccountingSelector<String>(
          assignedWidth: width,
          options: <AccountingSelectorOption<String>>[
            for (final method in paymentMethods)
              AccountingSelectorOption<String>(value: method, label: method),
            if (selected.isNotEmpty && !paymentMethods.contains(selected))
              AccountingSelectorOption<String>(
                value: selected,
                label: selected,
                preserveLabelCase: true,
              ),
          ],
          value: selected.isEmpty ? null : selected,
          onChanged: (method) => setState(() => _method.text = method ?? ''),
          hintText: 'Select payment method',
          controlKey: const ValueKey('voucher-method-control'),
          triggerKey: const ValueKey('voucher-method'),
          menuKey: const ValueKey('voucher-method-menu'),
          semanticsLabel: 'Payment method, required',
          enabled: !_busy,
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String fieldKey, {
    bool decimal = false,
    bool compactDate = false,
    bool required = false,
    String? helperText,
    String? errorText,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    final input = TextFormField(
      key: ValueKey<String>(fieldKey),
      controller: controller,
      enabled: !_busy,
      keyboardType:
          keyboardType ??
          (decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : null),
      inputFormatters: inputFormatters,
      enableInteractiveSelection: true,
      maxLines: 1,
      decoration: accountingInputDecoration(
        context,
        hintText: decimal
            ? formatAccountingInputAmount(Money.zero(_currencyCode))
            : label,
        helperText: null,
        errorText: errorText,
        suffixIcon: suffixIcon,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(context, label, required: required, guidance: helperText),
        const SizedBox(height: accountingFieldLabelGap),
        compactDate ? accountingDateFieldFrame(child: input) : input,
      ],
    );
  }

  Widget _label(
    BuildContext context,
    String label, {
    required bool required,
    String? guidance,
  }) {
    final tokens = AccountingTheme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: <Widget>[
        accountingFieldLabel(
          context,
          label,
          alignToField: true,
          guidance: guidance,
        ),
        if (required)
          Text(
            '*',
            style: AccountingTypography.fieldLabel(context)
                .copyWith(color: tokens.destructive),
          ),
      ],
    );
  }

  Widget _buildAttachmentField(BuildContext context) {
    if (widget.readOnly) {
      return AccountingAttachmentList(
        paginationKey: 'voucher-attachments',
        children: [
          for (final attachment in _attachments)
            _buildAttachmentRow(context, attachment),
        ],
      );
    }
    Widget dropzone = InkWell(
      key: const ValueKey('voucher-attachment-dropzone'),
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : _chooseAttachments,
      child: AccountingAttachmentDropzone(
        surfaceKey: const ValueKey('voucher-attachment-surface'),
        actionKey: const ValueKey('voucher-upload-file-action'),
        dragOver: _isDragOver,
        onChoose: _busy ? null : _chooseAttachments,
        prompt: 'Drop receipts here or choose files',
        formats:
            'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      dropzone = DropTarget(
        enable: !_busy,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(
          context,
          'Supporting documents',
          required: false,
          guidance: 'Optional for drafts. Attach an image or PDF.',
        ),
        const SizedBox(height: accountingFieldLabelGap),
        dropzone,
        if (_receiptReviewQueue?.hasUnresolved == true) ...<Widget>[
          const SizedBox(height: 8),
          AccountingButton.outline(
            context,
            key: const ValueKey('voucher-review-attachments'),
            onPressed: _busy || _reviewActive
                ? null
                : () => _openReceiptReview(_receiptReviewQueue!),
            leadingIcon: Icons.rate_review_outlined,
            child: Text(
              'Review ${_receiptReviewQueue!.remainingCount} staged attachment${_receiptReviewQueue!.remainingCount == 1 ? '' : 's'}',
            ),
          ),
        ],
        if (_attachments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          AccountingAttachmentList(
            paginationKey: 'voucher-attachments',
            children: [
              for (final attachment in _attachments)
                _buildAttachmentRow(context, attachment),
            ],
          ),
        ],
        if (_attachmentMessage != null)
          Text(
            _attachmentMessage!,
            key: const ValueKey('voucher-attachment-message'),
            softWrap: true,
            style: AccountingTypography.helper(context),
          ),
      ],
    );
  }

  Widget _buildAttachmentRow(
    BuildContext context,
    ReceiptAttachment attachment,
  ) {
    if (widget.readOnly) {
      return ReadonlyAttachmentRow(
        key: ValueKey('voucher-attachment-row-${attachment.originalId}'),
        attachment: attachment,
        keyPrefix: 'voucher',
      );
    }
    return AccountingAttachmentRecordRow(
      key: ValueKey<String>('voucher-attachment-row-${attachment.originalId}'),
      attachment: attachment,
      statusKey: ValueKey('voucher-attachment-status-${attachment.originalId}'),
      actions: <Widget>[
        AccountingButton.iconOnly(
          context,
          key: ValueKey('voucher-attachment-view-${attachment.originalId}'),
          onPressed: () => showAttachmentPreview(context, attachment),
          icon: Icons.visibility_outlined,
          tooltip: 'View Attachment',
        ),
        AccountingButton.iconOnly(
          context,
          key: ValueKey<String>(
            'voucher-attachment-remove-${attachment.originalId}',
          ),
          onPressed: _busy
              ? null
              : () async {
                  if (!await confirmAttachmentDeletion(context) || !mounted) {
                    return;
                  }
                  setState(() {
                    _attachments = _attachments
                        .where(
                          (item) => item.originalId != attachment.originalId,
                        )
                        .toList();
                  });
                },
          icon: Icons.delete_outline,
          tooltip: 'Remove Attachment',
        ),
      ],
    );
  }

  void _selectAccount(PaymentAccount? account) {
    if (account == null) return;
    if (_amount.text.trim().isNotEmpty &&
        account.currency.code != _currencyCode) {
      setState(
        () => _error =
            'The entered amount is in $_currencyCode. Choose an account in that currency or clear the amount before changing accounts.',
      );
      return;
    }
    setState(() {
      _paymentAccount = account;
      _account.text = account.name;
      _currencyCode = account.currency.code;
      _currency = CurrencyPresentation.fromCode(_currencyCode);
      _error = null;
    });
  }

  Future<void> _addPayee() async {
    final nameController = TextEditingController();
    final route = DialogRoute<Payee>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.normal,
        title: 'Add Payee',
        formFooter: true,
        content: SizedBox(
          width: AccountingPopoutTokens.normalContentWidth,
          child: AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Payee name',
                builder: (_) => TextField(
                  key: const ValueKey('voucher-add-payee-name'),
                  controller: nameController,
                  autofocus: true,
                  decoration: accountingInputDecoration(
                    dialogContext,
                    hintText: 'Payee name',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          AccountingButton.ghost(
            dialogContext,
            key: const ValueKey('voucher-add-payee-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          AccountingButton.primary(
            dialogContext,
            key: const ValueKey('voucher-add-payee-save'),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(
                Payee(
                  id: 'payee-${DateTime.now().microsecondsSinceEpoch}',
                  name: name,
                  type: PayeeType.other,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    // Keep the controller alive until the departing dialog has unmounted.
    await route.completed;
    nameController.dispose();
    if (result == null || !mounted) return;
    late final Payee payee;
    try {
      payee = _payeeStore.save(result);
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
      _payeeValue = payee.name;
      _payeeAutocompleteController?.value = TextEditingValue(
        text: payee.name,
        selection: TextSelection.collapsed(offset: payee.name.length),
      );
    });
  }

  Future<void> _chooseAttachments() async {
    if (_busy) return;
    try {
      final selected = widget.onAttachmentsPick != null
          ? await widget.onAttachmentsPick!(context)
          : await const NativeExpenseAttachmentPicker().pick(context);
      await _processAttachments(selected);
    } on Object catch (exception) {
      if (mounted) {
        setState(
          () =>
              _attachmentMessage = 'Attachment could not be added: $exception',
        );
      }
    }
  }

  Future<void> _onDragDone(DropDoneDetails details) async {
    if (mounted) setState(() => _isDragOver = false);
    final selected = <PickedExpenseAttachment>[];
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
          selected.add(
            PickedExpenseAttachment(
              name: item.name,
              mimeType:
                  item.mimeType ??
                  NativeExpenseAttachmentPicker.mimeTypeForFilename(item.name),
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
    await _processAttachments(selected);
  }

  Future<void> _processAttachments(
    List<PickedExpenseAttachment> selected,
  ) async {
    if (selected.isEmpty || !mounted) return;
    try {
      final batchId =
          'voucher-attachments-${DateTime.now().microsecondsSinceEpoch}';
      final processed = await _pipeline.processBatch(<ReceiptAttachmentInput>[
        for (var index = 0; index < selected.length; index++)
          ReceiptAttachmentInput(
            originalId: '$batchId-$index',
            batchId: batchId,
            filename: selected[index].name,
            mimeType: selected[index].mimeType,
            bytes: selected[index].bytes,
          ),
      ], batchId: batchId);
      if (!mounted) return;
      setState(() => _attachmentMessage = null);
      await _openReceiptReview(ReceiptReviewQueue(processed.attachments));
    } on Object catch (exception) {
      if (mounted) {
        setState(
          () =>
              _attachmentMessage = 'Attachment could not be added: $exception',
        );
      }
    }
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
        setupKind: SetupKind.voucher,
        destinationDate: parseAccountingInputDate(_date.text),
        categoryCode: '',
        onSave: _artifactStore.put,
        onRetry: _retryProcessedAttachment,
        onApplyCropWithRect: _pipeline.crop,
        onConvertToPdf: _pipeline.convertToPdf,
      ),
    );
    if (!mounted) return;
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

  Future<void> _persist({required bool submit}) async {
    if (_saveUnavailableReason case final reason?) {
      setState(() => _error = reason);
      _revealError();
      return;
    }
    final errors = _validate(submit: submit);
    if (errors.isNotEmpty) {
      setState(
        () => _error = submit
            ? 'Please fix the highlighted source and payment fields before submitting.'
            : 'Please provide the source and payment fields for this draft.',
      );
      _revealError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final voucher = _buildVoucher(submit: submit);
      if (submit) {
        await widget.onSubmit(voucher);
      } else {
        await widget.onSaveDraft(voucher);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Voucher could not be saved. Your entries are still here: $exception';
      });
      _revealError();
    }
  }

  void _revealError() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editorScroll.hasClients) _editorScroll.jumpTo(0);
    });
  }

  List<String> _validate({required bool submit}) {
    final errors = <String>[];
    if (_sourceId.text.trim().isEmpty ||
        widget.sources != null &&
            !widget.sources!.any(
              (s) => s.type == _sourceType && s.id == _sourceId.text.trim(),
            )) {
      errors.add('source');
    }
    final payee = _payeeValue.trim().isEmpty
        ? (_payeeAutocompleteController?.text.trim() ?? '')
        : _payeeValue.trim();
    if (payee.isEmpty) errors.add('payee');
    try {
      final amount = Money.fromDecimal(_amount.text.trim(), _currencyCode);
      if (amount.minorUnits <= 0) errors.add('amount');
    } on Object {
      errors.add('amount');
    }
    if (_accounts.isEmpty
        ? _account.text.trim().isEmpty
        : _paymentAccount == null) {
      errors.add('account');
    }
    if (_method.text.trim().isEmpty) errors.add('method');
    if (parseAccountingInputDate(_date.text.trim()) == null) errors.add('date');
    if (_reference.text.trim().isEmpty) errors.add('reference');
    if (_currency == null) errors.add('currency');
    if (_attachments.any(
      (attachment) =>
          attachment.status == AttachmentProcessingStatus.failed &&
          (submit || !_isRetainedUnavailable(attachment)),
    )) {
      errors.add('attachments');
    }
    if (submit && _receiptReviewQueue?.hasUnresolved == true) {
      errors.add('review');
    }
    return errors;
  }

  bool _isRetainedUnavailable(ReceiptAttachment attachment) =>
      attachment.originalBytes.isEmpty &&
      attachment.status == AttachmentProcessingStatus.failed &&
      (widget.initial?.attachments.any(
            (original) =>
                jsonEncode(original.toJson()) ==
                jsonEncode(attachment.toJson()),
          ) ??
          false);

  PaymentVoucher _buildVoucher({required bool submit}) {
    final allocations = _allocation.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final payee = _payeeValue.trim().isEmpty
        ? (_payeeAutocompleteController?.text.trim() ?? '')
        : _payeeValue.trim();
    final date = parseAccountingInputDate(_date.text.trim());
    if (date == null) throw StateError('Payment date is not numeric or valid.');
    final existingDate = widget.initial?.paymentDate;
    final paymentDate =
        existingDate != null &&
            _date.text.trim() == formatAccountingInputDate(existingDate)
        ? existingDate
        : accountingCalendarDate(date);
    return PaymentVoucher.create(
      id: widget.id,
      sourceType: _sourceType,
      sourceId: _sourceId.text.trim(),
      payee: payee,
      amount: Money.fromDecimal(_amount.text.trim(), _currencyCode),
      paymentAccount: _paymentAccount?.name ?? _account.text.trim(),
      paymentAccountId: _paymentAccount?.id,
      paymentMethod: _method.text.trim(),
      paymentDate: paymentDate,
      reference: _reference.text.trim(),
      allocations: allocations,
      attachments: _attachments
          .where(
            (attachment) =>
                !attachment.reviewSkipped &&
                (attachment.status != AttachmentProcessingStatus.failed ||
                    (!submit && _isRetainedUnavailable(attachment))),
          )
          .toList(growable: false),
    );
  }
}

String _dateText(DateTime date) => formatAccountingInputDate(date);
