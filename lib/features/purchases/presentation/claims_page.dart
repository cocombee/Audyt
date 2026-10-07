import '../../accounting/presentation/record_expense_page.dart'
    show RecordExpensePage, RecordExpenseClaimContext;
import '../../accounting/presentation/expense_intake_page.dart'
    show showCurrentExpenseEditor;
import '../../accounting/domain/expense_intake.dart';
import '../../accounting/application/legacy_claim_expense_view.dart';

import 'package:audyt/app/field_row_trial.dart';

import 'claim_receipt_approval_dialog.dart';
import 'claim_expense_creation_dialog.dart';
import '../domain/claim_expense_creation.dart';
import 'claim_receipts_editor.dart';
import '../../accounting/domain/company_tax_rate.dart';

import '../../accounting/presentation/widgets/payee_autocomplete_menu.dart';

import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/naming_setup.dart';

import '../../accounting/domain/payment_account.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/journal_entry.dart';

import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/core/documents/paid_claim_filing.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/dates/accounting_date.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_category.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'claimant_statements_dialog.dart';
import '../../accounting/domain/transaction_removal.dart';
import '../../accounting/data/accounting_database.dart';
import '../../accounting/presentation/transaction_removal_controls.dart';

import 'package:flutter/material.dart';

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({
    required this.store,
    this.workspace,
    this.receiptTaxProposal = true,
    super.key,
    this.compact = false,
    this.payees = PayeeCatalog.demo,
    this.payeeStore,
    this.claimCategories,
    this.defaultCurrencyCode = 'MYR',
    this.onAttachmentsPick,
    this.paidClaimFilingService,
    this.beforeCreate,
    this.claimCreationGateway,
  });

  final bool receiptTaxProposal;
  final ClaimStore store;
  final AccountingWorkspace? workspace;
  final Future<bool> Function()? beforeCreate;
  final ClaimExpenseCreationGateway? claimCreationGateway;
  final bool compact;
  final List<Payee> payees;
  final PayeeStore? payeeStore;
  final List<ClaimCategory>? claimCategories;
  final String defaultCurrencyCode;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  final PaidClaimFilingCoordinator? paidClaimFilingService;

  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage> {
  @override
  void initState() {
    super.initState();
    widget.workspace?.addListener(_workspaceChanged);
  }

  @override
  void didUpdateWidget(covariant ClaimsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace?.removeListener(_workspaceChanged);
      widget.workspace?.addListener(_workspaceChanged);
    }
  }

  void _workspaceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.workspace?.removeListener(_workspaceChanged);
    super.dispose();
  }

  ClaimStatus? _filter;
  String? _firstFilter, _secondFilter;
  String? _feedback;
  bool _feedbackIsError = false;
  bool _creatingClaim = false;
  final Set<EntityId> _selectedClaims = {};
  bool _selectingClaims = false, _payingBatch = false;
  bool get _canPaySelection =>
      _selectedClaims.isNotEmpty &&
      _selectedClaims.every(
        (id) => widget.store.byId(id)?.status == ClaimStatus.approved,
      );

  List<Claim> get _visibleClaims =>
      !AccountingRecordControlsPolicy.visible(widget.store.all.length)
      ? widget.store.all
      : widget.store.all
            .where((claim) => _filter == null || claim.status == _filter)
            .where(
              (claim) =>
                  _firstFilter == null || claim.claimantName == _firstFilter,
            )
            .where(
              (claim) =>
                  _secondFilter == null ||
                  (_currentExpense(claim)?.category ?? claim.category) ==
                      _secondFilter,
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
            routeLabel: 'Claims',
            title: 'Claims',
            titleKey: 'page-title-claims',
            eyebrow: 'Money Out · Expenses & Vendors',
            description: 'Track staff-paid expenses separately from direct company expenses, then submit, review, and reimburse them once.',
            action: AccountingButton.primary(
              context,
              key: const ValueKey('claims-create'),
              onPressed: _creatingClaim ? null : _openCreateClaim,
              leadingIcon: Icons.add_rounded,
              child: const Text('New Claim'),
            ),
            secondaryActions: [
              if (widget.workspace != null &&
                  widget.workspace!
                          .removedTransactionPage(
                            TransactionRecordKind.claim,
                            limit: 1,
                          )
                          .total >
                      0)
                RemovedTransactionsButton(
                  workspace: widget.workspace!,
                  kind: TransactionRecordKind.claim,
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                  onView: (record) => _openEditor(
                    widget.workspace!.database.readRetainedClaim(
                      widget.workspace!.identity.businessId,
                      EntityId.parse(record.recordId),
                    ),
                    forceReadOnly: true,
                  ),
                ),
              if (widget.workspace != null)
                AccountingButton.ghost(
                  context,
                  key: const ValueKey('claims-balances'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        ClaimantStatementsDialog(workspace: widget.workspace!),
                  ),
                  child: const Text('Claimant Balances'),
                ),
            ],
          ),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_feedback != null)
            Semantics(
              liveRegion: true,
              child: AccountingAlert.build(
                context,
                key: const ValueKey('claims-feedback'),
                title: _feedbackIsError
                    ? 'Claim Action Failed'
                    : 'Claim Updated',
                description: _feedback!,
                tone: _feedbackIsError
                    ? AccountingAlertTone.critical
                    : AccountingAlertTone.positive,
                bottomGap: accountingContentInset,
              ),
            ),
          if (widget.workspace == null)
            AccountingAlert.build(
              context,
              key: const ValueKey('claims-local-demo-banner'),
              title: 'Offline workspace',
              description: 'Local demo claims are included for this offline workspace. A claim means the claimant paid personally; it is not a second direct expense posting.',
              tone: AccountingAlertTone.warning,
              bottomGap: accountingContentInset,
            ),
          AccountingRecordControls(
            recordCount: widget.store.all.length,
            child: _buildFilter(context),
          ),
          if (_selectingClaims &&
              _selectedClaims.isNotEmpty &&
              !_canPaySelection)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Only approved claims can be paid.',
                style: AccountingTypography.helper(context),
              ),
            ),
          if (AccountingRecordControlsPolicy.visible(widget.store.all.length))
            const SizedBox(height: 16),
          if (_visibleClaims.isEmpty)
            _buildEmptyState(context)
          else
            AccountingRecordList(
              paginationKey: 'claims',
              totalCount: widget.store.all.length,
              defaultPageSize: 5,
              children: [
                for (final claim in _visibleClaims)
                  _buildClaimCard(context, claim),
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
        options: ClaimStatus.values.map((s) => s.label),
        value: _filter?.label,
        controlKey: const ValueKey('claims-filter'),
        onChanged: (value) => setState(
          () => _filter = value == null
              ? null
              : ClaimStatus.values.firstWhere((s) => s.label == value),
        ),
      ),
      AccountingRecordFilter(
        label: 'Claimant',
        options: widget.store.all.map((r) => r.claimantName),
        value: _firstFilter,
        controlKey: const ValueKey('claims-first-filter'),
        onChanged: (value) => setState(() => _firstFilter = value),
      ),
      AccountingRecordFilter(
        label: 'Category',
        options: widget.store.all.map(
          (r) => _currentExpense(r)?.category ?? r.category,
        ),
        value: _secondFilter,
        controlKey: const ValueKey('claims-second-filter'),
        onChanged: (value) => setState(() => _secondFilter = value),
      ),
      if (_filter != null || _firstFilter != null || _secondFilter != null)
        AccountingButton.outline(
          context,
          key: const ValueKey('claims-clear-filters'),
          onPressed: () => setState(() {
            _filter = null;
            _firstFilter = null;
            _secondFilter = null;
          }),
          leadingIcon: Icons.filter_alt_off_outlined,
          child: const Text('Clear'),
        ),
      AccountingButton.outline(
        context,
        key: const ValueKey('claims-select-payment'),
        onPressed: _payingBatch
            ? null
            : () => setState(() {
                _selectingClaims = !_selectingClaims;
                _selectedClaims.clear();
              }),
        child: Text(_selectingClaims ? 'Cancel' : 'Select'),
      ),
      if (_selectingClaims) ...[
        AccountingButton.outline(
          context,
          key: const ValueKey('claims-select-matching'),
          onPressed: _payingBatch
              ? null
              : () => setState(
                  () => _selectedClaims.addAll(_visibleClaims.map((c) => c.id)),
                ),
          child: const Text('Select All Matching Claims'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('claims-pay-selected'),
          onPressed: _payingBatch || !_canPaySelection
              ? null
              : _paySelectedClaims,
          child: Text('Record Payment (${_selectedClaims.length})'),
        ),
      ],
    ],
  );

  Widget _buildEmptyState(BuildContext context) {
    return AccountingEmptyState.card(
      context,
      key: const ValueKey('claims-empty-state'),
      title: _filter == null ? 'No claims yet' : 'No claims in this state',
      description: 'Create a draft claim when a staff member, worker, or director has paid personally.',
      icon: Icons.receipt_long_outlined,
    );
  }

  Widget _buildClaimCard(BuildContext context, Claim claim) {
    final current = _currentExpense(claim);
    final editable = current == null || !_currentExpenseLocked(current);
    final evidence = <Widget>[
      AccountingButton.outline(
        context,
        key: ValueKey('${editable ? 'claim-edit' : 'claim-view'}-${claim.id}'),
        onPressed: () => _viewClaim(claim),
        child: Text(editable ? 'Edit' : 'View'),
      ),
      if (widget.workspace != null)
        TransactionRemoveButton(
          key: ValueKey('claim-delete-${claim.id}'),
          workspace: widget.workspace!,
          kind: TransactionRecordKind.claim,
          recordId: claim.id.value,
          onChanged: () {
            if (mounted) setState(() => _selectedClaims.remove(claim.id));
          },
        )
      else
        AccountingButton.iconOnly(
          context,
          key: ValueKey('claim-delete-${claim.id}'),
          onPressed: widget.store.canDeleteDemo(claim)
              ? () => _deleteDemoClaim(claim)
              : null,
          icon: Icons.delete_outline,
          tooltip: widget.store.canDeleteDemo(claim)
              ? 'Delete Draft'
              : 'Deletion unavailable for this record in this workspace',
        ),
    ];
    return KeyedSubtree(
      key: ValueKey<String>('claim-row-${claim.id}'),
      child: Padding(
        padding: accountingContentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AccountingRecordRow(
              topRightInfo: true,
              padding: EdgeInsets.zero,
              title: current?.payee ?? claim.vendorName,
              status: AccountingBadge.build(
                context,
                key: ValueKey<String>('claim-status-${claim.id}'),
                label: claim.status.label,
              ),
              statusWidth: AccountingBadge.measuredWidth(
                context,
                claim.status.label,
              ),
              compactStatus: Tooltip(
                message: claim.status.label,
                child: AccountingBadge.build(
                  context,
                  key: ValueKey<String>('claim-status-${claim.id}'),
                  label: claim.status.compactLabel,
                ),
              ),
              leading: !_selectingClaims ? null : _selectionCheckbox(claim),
              leadingOverlaysTitle: _selectingClaims,
              titleKey: ValueKey<String>('claim-payee-${claim.id}'),
              details: Text(
                'Claimant: ${claim.claimantName.isEmpty ? 'Unassigned' : claim.claimantName}\nCategory: ${current?.category ?? (claim.category.isEmpty ? 'Unassigned' : claim.category)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AccountingTypography.helper(context),
              ),
              trailing: Text(
                formatAccountingMoney(context, current?.amount ?? claim.amount),
                style: AccountingTypography.fieldLabel(context),
              ),
              trailingBelow: AccountingRecordActions(
                actions: [_moreActions(context, claim)],
                trailing: evidence,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionCheckbox(Claim claim) {
    void select(bool selected) => setState(() {
      if (selected) {
        _selectedClaims.add(claim.id);
      } else {
        _selectedClaims.remove(claim.id);
      }
    });

    return AccountingLeadingCheckbox(
      hitKey: ValueKey('claim-selection-hit-${claim.id}'),
      checkboxKey: ValueKey('claim-payment-select-${claim.id}'),
      value: _selectedClaims.contains(claim.id),
      semanticLabel: 'Select ${claim.vendorName}',
      onChanged: _payingBatch ? null : (value) => select(value ?? false),
    );
  }

  Future<void> _deleteDemoClaim(Claim claim) async {
    final password = TextEditingController();
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          title: 'Delete Demo Draft',
          formFooter: true,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This removes this unposted demo draft. No ledger entry or original file is deleted. Demo password: 1234.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Demo Password',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: null,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            AccountingButton.destructive(
              context,
              key: null,
              onPressed: () {
                if (password.text != '1234') {
                  update(() => error = 'Incorrect demo password.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete Draft'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    if (confirmed != true || !mounted) return;
    try {
      widget.store.deleteDemoDraft(claim.id);
      setState(() {});
    } catch (error) {
      _showError('$error');
    }
  }

  ExpenseIntakeSummary? _currentExpense(Claim claim) =>
      widget.workspace?.database.currentClaimExpenseSummary(
        widget.workspace!.identity.businessId,
        claim.id,
      );

  bool _currentExpenseLocked(ExpenseIntakeSummary summary) =>
      summary.isArchived ||
      (summary.journalId != null &&
          widget.workspace!.database.isJournalReconciled(
            widget.workspace!.identity.businessId,
            summary.journalId!,
          ));

  Future<void> _viewClaim(Claim claim) async {
    try {
      await _openEditor(claim);
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) _showError('Claim could not be opened: $error');
    }
  }

  Widget _moreActions(BuildContext context, Claim claim) {
    final actions = switch (claim.status) {
      ClaimStatus.draft ||
      ClaimStatus.returned => <(String, String, IconData, VoidCallback)>[
        (
          'submit',
          'Submit For Review',
          Icons.checklist_outlined,
          () => _submitClaim(claim),
        ),
        ('void', 'Void', Icons.block, () => _confirmVoid(claim)),
      ],
      ClaimStatus.submitted => <(String, String, IconData, VoidCallback)>[
        (
          'approve',
          'Approve',
          Icons.check_circle_outline,
          () => _approveClaim(claim),
        ),
        ('return', 'Return', Icons.undo, () => _returnClaim(claim)),
        ('decline', 'Decline', Icons.close, () => _declineClaim(claim)),
        ('void', 'Void', Icons.block, () => _confirmVoid(claim)),
      ],
      ClaimStatus.approved => <(String, String, IconData, VoidCallback)>[
        (
          'pay',
          'Mark Paid',
          Icons.payment_outlined,
          () => _confirmPayment(claim),
        ),
        ('return', 'Return', Icons.undo, () => _returnClaim(claim)),
        ('void', 'Void', Icons.block, () => _confirmVoid(claim)),
      ],
      ClaimStatus.declined ||
      ClaimStatus.paid ||
      ClaimStatus.voided => <(String, String, IconData, VoidCallback)>[],
    };
    return AccountingOverflowMenu(
      triggerKey: ValueKey<String>('claim-more-${claim.id}'),
      actions: [
        if (_currentExpense(claim) != null || claim.legacySource != null)
          AccountingOverflowAction(
            key: ValueKey<String>('claim-original-${claim.id}'),
            label: 'Original Submission',
            icon: Icons.history_outlined,
            onPressed: () => _openEditor(claim, forceReadOnly: true),
          ),
        for (final action in actions)
          AccountingOverflowAction(
            key: ValueKey<String>('claim-${action.$1}-${claim.id}'),
            label: action.$2,
            icon: action.$3,
            onPressed: action.$4,
          ),
      ],
    );
  }

  Future<void> _openCreateClaim() async {
    if (_creatingClaim) return;
    setState(() => _creatingClaim = true);
    try {
      if (widget.beforeCreate != null && !await widget.beforeCreate!()) return;
      if (!mounted) return;
      final gateway = widget.claimCreationGateway;
      if (gateway == null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => RecordExpensePage(
            includeTopSafeArea: false,
            preferences: widget.workspace?.preferences,
            settingsWorkspace: widget.workspace,
            payeeStore: widget.payeeStore,
            payees: widget.payees,
            defaultCurrencyCode: widget.defaultCurrencyCode,
            onAttachmentsPick: widget.onAttachmentsPick,
            onCancel: () => Navigator.pop(dialogContext),
            claimContext: RecordExpenseClaimContext(
              unavailableReason: 'Claim creation is currently unavailable.',
              claimantField: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  accountingFieldLabel(
                    dialogContext,
                    'Claimant',
                    alignToField: true,
                    guidance: 'Employees come from company registration. Registered claimant information is currently unavailable.',
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  InputDecorator(
                    key: const ValueKey('claim-expense-registration-required'),
                    decoration: accountingSingleLineInputDecoration(
                      dialogContext,
                    ),
                    child: accountingValueText(dialogContext, 'Unavailable'),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      final registration = await gateway.claimants('');
      if (!mounted || !identical(gateway, widget.claimCreationGateway)) return;
      if (registration.businessId != gateway.businessId ||
          (widget.workspace != null &&
              registration.businessId !=
                  widget.workspace!.identity.businessId.value)) {
        throw StateError('Claim registration belongs to another company.');
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ClaimExpenseCreationDialog(
          gateway: gateway,
          initialContext: registration,
          workspace: widget.workspace,
          payeeStore: widget.payeeStore,
          payees: widget.payees,
          defaultCurrencyCode: widget.defaultCurrencyCode,
          onAttachmentsPick: widget.onAttachmentsPick,
          onCancel: () => Navigator.pop(dialogContext),
          onSaved: () {
            Navigator.pop(dialogContext);
            if (mounted) setState(() {});
          },
        ),
      );
    } on Object {
      if (mounted) {
        _showError('Claim creation is unavailable. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _creatingClaim = false);
    }
  }

  Future<void> _openEditor(Claim? initial, {bool forceReadOnly = false}) async {
    if (initial == null) {
      await _openCreateClaim();
      return;
    }
    if (!forceReadOnly && widget.workspace != null) {
      final current = _currentExpense(initial);
      if (current != null) {
        final record = await widget.workspace!.expense(current.id);
        if (!mounted) return;
        if (record == null || record.draft.claimSource?.claimId != initial.id) {
          throw StateError('The current Claim Expense is unavailable.');
        }
        await showCurrentExpenseEditor(
          context,
          widget.workspace!,
          record,
          onAttachmentsPick: widget.onAttachmentsPick,
        );
        return;
      }
    }
    await _openExpenseClaim(initial, forceReadOnly: forceReadOnly);
  }

  Future<void> _openExpenseClaim(
    Claim initial, {
    required bool forceReadOnly,
  }) async {
    final canSave = const {
      ClaimStatus.draft,
      ClaimStatus.returned,
    }.contains(initial.status);
    final displayed = forceReadOnly ? initial.legacySource ?? initial : initial;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RecordExpensePage(
        includeTopSafeArea: false,
        readOnly: forceReadOnly,
        savedDraft: legacyClaimExpenseView(displayed),
        preferences: widget.workspace?.preferences,
        settingsWorkspace: widget.workspace,
        payeeStore: widget.payeeStore,
        payees: widget.payees,
        defaultCurrencyCode: widget.defaultCurrencyCode,
        onAttachmentsPick: widget.onAttachmentsPick,
        onCancel: () => Navigator.pop(dialogContext),
        onSaved: () => Navigator.pop(dialogContext),
        claimContext: RecordExpenseClaimContext(
          personallyPaid: displayed.personallyPaid,
          unavailableReason: !forceReadOnly && !canSave
              ? 'Saving changes to this Claim is unavailable. Your saved Claim is unchanged.'
              : null,
          claimantField: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountingFieldLabel(
                dialogContext,
                'Claimant',
                alignToField: true,
                guidance: 'Retained from the original Claim. An existing claimant cannot be replaced.',
              ),
              const SizedBox(height: accountingFieldLabelGap),
              InputDecorator(
                key: const ValueKey('claim-expense-claimant'),
                decoration: accountingSingleLineInputDecoration(dialogContext),
                child: accountingValueText(dialogContext, initial.claimantName),
              ),
            ],
          ),
          submissionErrors: canSave
              ? (draft) => initial.reviseExpense(draft).submissionErrors
              : null,
          saveDraft: !canSave
              ? null
              : (draft) async {
                  widget.store.saveDraft(
                    initial.reviseExpense(draft),
                    expectedCurrent: initial,
                  );
                  if (mounted) setState(() {});
                },
          submitForReview: !canSave
              ? null
              : (draft) async {
                  widget.store.saveAndSubmit(
                    initial.reviseExpense(draft),
                    expectedCurrent: initial,
                  );
                  if (mounted) setState(() {});
                },
        ),
      ),
    );
  }

  void _submitClaim(Claim claim) {
    try {
      widget.store.submit(claim.id, expectedCurrent: claim);
      setState(() {});
    } on Object catch (exception) {
      _showError('Claim could not be submitted: $exception');
    }
  }

  Future<List<EntityId>?> _reviewPostingAccounts(
    String title,
    List<(String, AccountType)> fields,
  ) async {
    final accounts = (await widget.workspace!.accounts())
        .map((r) => r.account)
        .where((a) => a.status == AccountStatus.active && !a.isParent)
        .toList();
    if (!mounted) return null;
    final selected = List<EntityId?>.filled(fields.length, null);
    var closing = false;
    Future<void> closeReview(BuildContext dialogContext) async {
      if (closing) return;
      closing = true;
      try {
        final discard =
            selected.every((id) => id == null) ||
            await AccountingDialog.confirmDiscardChanges(dialogContext);
        if (dialogContext.mounted && discard) {
          Navigator.of(dialogContext).pop();
        }
      } finally {
        closing = false;
      }
    }

    return showDialog<List<EntityId>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                closeReview(context),
          },
          child: PopScope<List<EntityId>>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) closeReview(context);
            },
            child: AccountingDialog.alert(
              context,
              title: title,
              formFooter: true,
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AccountingOrdinaryFields(
                        key: const ValueKey('claim-posting-ordinary-fields'),
                        fields: [
                          for (var i = 0; i < fields.length; i++)
                            AccountingOrdinaryFieldSlot(
                              label: fields[i].$1,
                              hasGuidance: true,
                              choices: [
                                if (selected[i] == null)
                                  'Select ${fields[i].$1}',
                                for (final account in accounts.where(
                                  (a) => a.type == fields[i].$2,
                                ))
                                  account.displayName,
                              ],
                              builder: (width) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  accountingFieldLabel(
                                    context,
                                    fields[i].$1,
                                    alignToField: true,
                                    guidance: 'Review the ledger account before posting. Create missing accounts in Chart of Accounts.',
                                  ),
                                  const SizedBox(
                                    height: accountingFieldLabelGap,
                                  ),
                                  AccountingSelector<EntityId>(
                                    controlKey: ValueKey(
                                      'claim-posting-account-$i',
                                    ),
                                    assignedWidth: width,
                                    options: [
                                      for (final account in accounts.where(
                                        (a) => a.type == fields[i].$2,
                                      ))
                                        AccountingSelectorOption(
                                          value: account.id,
                                          label: account.displayName,
                                        ),
                                    ],
                                    value: selected[i],
                                    hintText: 'Select ${fields[i].$1}',
                                    onChanged: (value) =>
                                        refresh(() => selected[i] = value),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                AccountingButton.outline(
                  context,
                  key: null,
                  onPressed: () => closeReview(dialogContext),
                  child: const Text('Cancel'),
                ),
                AccountingButton.primary(
                  context,
                  key: null,
                  onPressed: selected.any((v) => v == null)
                      ? null
                      : () => Navigator.pop(
                          dialogContext,
                          selected.cast<EntityId>(),
                        ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _approveClaim(Claim claim) async {
    try {
      final workspace = widget.workspace;
      if (workspace == null) {
        widget.store.approve(claim.id);
      } else {
        final List<EntityId>? selected;
        Map<String, EntityId>? expenseLineAccounts;
        final structured =
            widget.receiptTaxProposal && claim.receipts.isNotEmpty;
        if (claim.expenseDraft != null) {
          final accounts = (await workspace.accounts())
              .map((a) => a.account)
              .toList();
          if (!mounted) return;
          final reviewed = await showDialog<ClaimExpenseApprovalSelection>(
            context: context,
            builder: (_) =>
                ClaimReceiptApprovalDialog(claim: claim, accounts: accounts),
          );
          selected = reviewed == null ? null : [reviewed.payableAccountId];
          expenseLineAccounts = reviewed?.lineAccounts;
        } else if (structured) {
          final accounts = (await workspace.accounts())
              .map((a) => a.account)
              .toList();
          if (!mounted) return;
          final payable = await showDialog<EntityId>(
            context: context,
            builder: (_) =>
                ClaimReceiptApprovalDialog(claim: claim, accounts: accounts),
          );
          selected = payable == null ? null : [payable];
        } else {
          selected = await _reviewPostingAccounts('Approve Claim', [
            ('Expense Account', AccountType.expense),
            ('Claims Payable Account', AccountType.liability),
          ]);
        }
        if (selected == null || !mounted) return;
        workspace.approveClaim(
          reviewedClaim: claim,
          requestId: EntityId.random(),
          expenseAccountId: structured || claim.expenseDraft != null
              ? null
              : selected[0],
          expenseLineAccounts: expenseLineAccounts,
          liabilityAccountId: structured || claim.expenseDraft != null
              ? selected[0]
              : selected[1],
          approvedAt: DateTime.now().toUtc(),
        );
      }
      if (mounted) setState(() {});
    } on Object catch (exception) {
      _showError('Claim could not be approved: $exception');
    }
  }

  Future<void> _returnClaim(Claim claim) async {
    if (claim.status == ClaimStatus.approved && widget.workspace != null) {
      await _reviewApprovedClaimCorrection(
        claim,
        ClaimRecognitionDecision.returnForCorrection,
      );
      return;
    }
    try {
      widget.store.returnForCorrection(claim.id, expectedCurrent: claim);
      setState(() {});
    } on Object catch (exception) {
      _showError('Claim could not be returned: $exception');
    }
  }

  void _declineClaim(Claim claim) {
    try {
      widget.store.decline(claim.id, expectedCurrent: claim);
      setState(() {});
    } on Object catch (exception) {
      _showError('Claim could not be declined: $exception');
    }
  }

  Future<void> _reviewApprovedClaimCorrection(
    Claim claim,
    ClaimRecognitionDecision decision,
  ) async {
    final workspace = widget.workspace!;
    final recognition = workspace.activeClaimRecognitionId(claim.id);
    if (recognition == null) {
      _showError(
        'The claim recognition is unavailable. Reopen before correcting.',
      );
      return;
    }
    final returning = decision == ClaimRecognitionDecision.returnForCorrection;
    final date = TextEditingController(
      text: formatAccountingInputDate(DateTime.now()),
    );
    final reason = TextEditingController();
    final requestId = EntityId.random();
    String? error;
    var committing = false;
    var closing = false;
    final openingDate = date.text;
    Future<void> closeCorrection(BuildContext dialogContext) async {
      if (committing || closing) return;
      closing = true;
      try {
        final dirty = date.text != openingDate || reason.text.isNotEmpty;
        final discard =
            !dirty ||
            await AccountingDialog.confirmDiscardChanges(dialogContext);
        if (dialogContext.mounted && discard) {
          Navigator.of(dialogContext).pop(false);
        }
      } finally {
        closing = false;
      }
    }

    DialogRoute<bool>? route;
    try {
      final original = await workspace.database.getJournal(recognition);
      final accounts = {
        for (final record in await workspace.accounts())
          record.account.id: record.account,
      };
      if (!mounted) return;
      if (original == null ||
          original.metadata.businessId != workspace.identity.businessId ||
          original.metadata.isTombstone ||
          original.entry.state != JournalEntryState.posted ||
          original.entry.lines.any(
            (line) => !accounts.containsKey(line.accountId),
          )) {
        throw StateError(
          'The recognized journal or its accounts are unavailable.',
        );
      }
      route = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  closeCorrection(context),
            },
            child: PopScope<bool>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) closeCorrection(context);
              },
              child: AccountingDialog.alert(
                context,
                key: ValueKey('claim-recognition-correction-${claim.id}'),
                title: returning
                    ? 'Return Approved Claim'
                    : 'Void Approved Claim',
                formFooter: true,
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectionArea(
                          child: AccountingInformationRows(
                            rows: [
                              ('Claimant', claim.claimantName),
                              ('Payee', claim.vendorName),
                              (
                                'Claim Amount',
                                formatAccountingMoney(context, claim.amount),
                              ),
                              ('Business Purpose', claim.businessPurpose),
                              ('Original Journal', recognition.value),
                              (
                                'Original Posting Date',
                                formatAccountingInputDate(original.entry.date),
                              ),
                              for (final line in original.entry.lines)
                                (
                                  'Reversal ${line.isDebit ? 'Credit' : 'Debit'} · ${accounts[line.accountId]!.displayName}',
                                  formatAccountingMoney(context, line.amount),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        AccountingOrdinaryFields(
                          key: const ValueKey('claim-reversal-ordinary-fields'),
                          fields: [
                            AccountingOrdinaryFieldSlot(
                              label: 'Reversal Date',
                              contentSample: date.text,
                              date: true,
                              hasGuidance: true,
                              builder: (_) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  accountingFieldLabel(
                                    context,
                                    'Reversal Date',
                                    alignToField: true,
                                    guidance: 'Reverse the posted expense and unpaid liability on this date. The original posting stays in history.',
                                  ),
                                  const SizedBox(
                                    height: accountingFieldLabelGap,
                                  ),
                                  TextField(
                                    key: const ValueKey('claim-reversal-date'),
                                    controller: date,
                                    enabled: !committing,
                                    inputFormatters: const [
                                      DateInputFormatter(),
                                    ],
                                    decoration:
                                        accountingSingleLineInputDecoration(
                                          context,
                                        ).copyWith(
                                          suffixIcon: accountingCalendarButton(
                                            context,
                                            controller: date,
                                            label: 'Reversal Date',
                                            enabled: !committing,
                                            firstDate: claim.incurredOn!,
                                            lastDate: DateTime(
                                              DateTime.now().year + 10,
                                              12,
                                              31,
                                            ),
                                            onPicked: () =>
                                                refresh(() => error = null),
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AccountingResponsive.groupGap),
                        accountingFieldLabel(
                          context,
                          'Reason',
                          alignToField: true,
                          guidance: returning
                              ? 'Explain the correction before returning this claim. Its expense and unpaid liability will be reversed; the original posting stays in history.'
                              : 'Explain why this claim is void. Its expense and unpaid liability will be reversed, and it cannot be reimbursed. The original posting stays in history.',
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        AccountingDescriptionField(
                          key: const ValueKey('claim-reversal-reason'),
                          controller: reason,
                          onEscape: () => closeCorrection(context),
                          enabled: !committing,
                          maxLength: 500,
                          fixedLines: 2,
                          decoration: accountingSingleLineInputDecoration(
                            context,
                          ).copyWith(counterText: ''),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: TextStyle(
                              color: AccountingTheme.of(context).destructive,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  AccountingButton.ghost(
                    context,
                    key: const ValueKey('claim-reversal-cancel'),
                    onPressed: committing
                        ? null
                        : () => closeCorrection(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  AccountingButton.destructive(
                    context,
                    key: const ValueKey('claim-reversal-confirm'),
                    onPressed: committing
                        ? null
                        : () {
                            final parsed = parseAccountingInputDate(date.text);
                            if (parsed == null || reason.text.trim().isEmpty) {
                              refresh(
                                () => error =
                                    'Enter a valid reversal date and a reason.',
                              );
                              return;
                            }
                            refresh(() {
                              committing = true;
                              error = null;
                            });
                            try {
                              workspace.reverseClaimRecognition(
                                reviewedClaim: claim,
                                requestId: requestId,
                                expectedRecognitionJournalId: recognition,
                                decision: decision,
                                reversedOn: accountingCalendarDate(parsed),
                                reason: reason.text,
                                changedAt: DateTime.now().toUtc(),
                              );
                              Navigator.pop(dialogContext, true);
                            } on Object catch (exception) {
                              refresh(() {
                                committing = false;
                                error =
                                    'Claim could not be corrected: $exception';
                              });
                            }
                          },
                    child: Text(returning ? 'Return Claim' : 'Void Claim'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final changed = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      if (changed == true && mounted) {
        setState(() => _selectedClaims.remove(claim.id));
        _showMessage(
          returning
              ? 'Claim returned with its posting reversed'
              : 'Claim voided with its posting reversed',
        );
      }
    } on Object catch (exception) {
      if (mounted) {
        _showError('Claim correction review could not be opened: $exception');
      }
    } finally {
      // A popped dialog remains mounted during its exit animation.
      // Keep its field controllers alive until the route removes the overlay.
      if (route != null) await route.completed;
      date.dispose();
      reason.dispose();
    }
  }

  Future<void> _confirmVoid(Claim claim) async {
    if (claim.status == ClaimStatus.approved && widget.workspace != null) {
      await _reviewApprovedClaimCorrection(
        claim,
        ClaimRecognitionDecision.voidClaim,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        key: ValueKey<String>('claim-void-confirmation-${claim.id}'),
        title: 'Void this claim?',
        description: 'Voiding keeps the record for audit but prevents it from being reimbursed.',
        content: AccountingInformationRows(
          rows: [
            if (claim.claimantName.isNotEmpty) ('Claimant', claim.claimantName),
            if (claim.vendorName.isNotEmpty) ('Payee', claim.vendorName),
            ('Amount', formatAccountingMoney(dialogContext, claim.amount)),
          ],
        ),
        actions: <Widget>[
          AccountingButton.ghost(
            dialogContext,
            key: null,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AccountingButton.destructive(
            dialogContext,
            key: ValueKey<String>('claim-confirm-void-${claim.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Void Claim'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      widget.store.voidClaim(claim.id, expectedCurrent: claim);
      setState(() => _feedback = 'Claim voided');
      _showMessage('Claim voided');
    } on Object catch (exception) {
      _showError('Claim could not be voided: $exception');
    }
  }

  Future<void> _paySelectedClaims() async {
    if (_payingBatch) return;
    final claims = _selectedClaims
        .map(widget.store.byId)
        .whereType<Claim>()
        .toList();
    if (claims.length != _selectedClaims.length ||
        claims.any((c) => c.status != ClaimStatus.approved)) {
      _showError('Selection changed. Select approved, unpaid claims again.');
      return;
    }
    if (claims.map((c) => c.amount.currency).toSet().length != 1) {
      _showError('Select claims in one currency for each payment batch.');
      return;
    }
    final reviewed = {for (final c in claims) c.id: jsonEncode(c.toJson())};
    final total = claims.fold(
      Money.zero(claims.first.amount.currency),
      (sum, c) => sum + c.amount,
    );
    var reference = '';
    setState(() => _payingBatch = true);
    try {
      EntityId? bankAccount;
      String? paymentAccountId;
      if (widget.workspace != null) {
        final workspace = widget.workspace!;
        final accounts = (await workspace.accounts())
            .map((r) => r.account)
            .where(
              (a) =>
                  a.type == AccountType.asset &&
                  a.status == AccountStatus.active &&
                  !a.isParent,
            )
            .toList();
        final payments = workspace.paymentAccounts
            .where(
              (p) =>
                  p.type != PaymentAccountType.card &&
                  p.currency.code == total.currency &&
                  accounts.any(
                    (a) =>
                        a.id ==
                        workspace.database.paymentLedgerAccount(
                          workspace.identity.businessId,
                          p.id,
                        ),
                  ),
            )
            .toList();
        if (!mounted) return;
        String? selected;
        var closingAccount = false;
        Future<void> closeAccount(BuildContext dialogContext) async {
          if (closingAccount) return;
          closingAccount = true;
          try {
            final discard =
                selected == null ||
                await AccountingDialog.confirmDiscardChanges(dialogContext);
            if (dialogContext.mounted && discard) {
              Navigator.of(dialogContext).pop();
            }
          } finally {
            closingAccount = false;
          }
        }

        paymentAccountId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, refresh) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    closeAccount(context),
              },
              child: PopScope<String>(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) closeAccount(context);
                },
                child: AccountingDialog.alert(
                  context,
                  title: 'Claim Payment Account',
                  formFooter: true,
                  content: payments.isEmpty
                      ? const Text(
                          'In Banking, link a bank or cash payment account to an active ledger account in the claim currency.',
                        )
                      : SizedBox(
                          width: accountingSelectorMinimumWidth(context, [
                            if (selected == null)
                              accountingSelectorHintText(
                                'Select Payment Account',
                              ),
                            for (final p in payments) p.displayLabel,
                          ]),
                          child: AccountingOrdinaryFields(
                            key: const ValueKey(
                              'claim-payment-ordinary-fields',
                            ),
                            fields: [
                              AccountingOrdinaryFieldSlot(
                                label: 'Payment Account',
                                hasGuidance: true,
                                choices: [
                                  if (selected == null)
                                    accountingSelectorHintText(
                                      'Select Payment Account',
                                    ),
                                  for (final p in payments) p.displayLabel,
                                ],
                                builder: (width) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    accountingFieldLabel(
                                      context,
                                      'Payment Account',
                                      alignToField: true,
                                      guidance: 'Choose a bank or cash account in the claim currency, linked to an active ledger account in Banking. Card accounts are excluded.',
                                    ),
                                    const SizedBox(
                                      height: accountingFieldLabelGap,
                                    ),
                                    AccountingSelector<String>(
                                      controlKey: const ValueKey(
                                        'claim-payment-account',
                                      ),
                                      assignedWidth: width,
                                      options: [
                                        for (final p in payments)
                                          AccountingSelectorOption(
                                            value: p.id,
                                            label: p.displayLabel,
                                          ),
                                      ],
                                      value: selected,
                                      hintText: accountingSelectorHintText(
                                        'Select Payment Account',
                                      ),
                                      onChanged: (value) =>
                                          refresh(() => selected = value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  actions: [
                    AccountingButton.secondary(
                      context,
                      key: const ValueKey('cancel-claim-account'),
                      child: const Text('Cancel'),
                      onPressed: () => closeAccount(dialogContext),
                    ),
                    AccountingButton.primary(
                      context,
                      key: const ValueKey('confirm-claim-account'),
                      child: const Text('Continue'),
                      onPressed: selected == null
                          ? null
                          : () => Navigator.pop(dialogContext, selected),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (paymentAccountId == null || !mounted) return;
        bankAccount = workspace.database.paymentLedgerAccount(
          workspace.identity.businessId,
          paymentAccountId,
        );
        if (bankAccount == null) {
          throw StateError('The payment account needs a ledger link.');
        }
      }
      var closingReference = false;
      Future<void> closeReference(BuildContext dialogContext) async {
        if (closingReference) return;
        closingReference = true;
        try {
          final discard =
              reference.isEmpty ||
              await AccountingDialog.confirmDiscardChanges(dialogContext);
          if (dialogContext.mounted && discard) {
            Navigator.of(dialogContext).pop(false);
          }
        } finally {
          closingReference = false;
        }
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  closeReference(context),
            },
            child: PopScope<bool>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) closeReference(context);
              },
              child: AccountingDialog.alert(
                context,
                key: const ValueKey('claims-batch-confirmation'),
                title: 'Record selected claim payments',
                formFooter: true,
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${claims.length} claims · ${formatAccountingMoney(context, total)}',
                        ),
                        const SizedBox(height: 12),
                        for (final claim in claims)
                          AccountingRecordRow(
                            key: ValueKey('claim-allocation-${claim.id.value}'),
                            topRightInfo: true,
                            title: claim.claimantName,
                            details: Text(
                              '${claim.vendorName} · ${claim.category}${claim.businessPurpose.isEmpty ? '' : '\n${claim.businessPurpose}'}',
                              style: AccountingTypography.helper(context),
                            ),
                            trailing: Text(
                              formatAccountingMoney(context, claim.amount),
                            ),
                          ),
                        const SizedBox(height: 12),
                        AccountingOrdinaryFields(
                          key: const ValueKey('claims-batch-ordinary-fields'),
                          fields: [
                            AccountingOrdinaryFieldSlot(
                              label: 'Payment Reference',
                              hasGuidance: true,
                              contentSample: reference.isEmpty
                                  ? '0000000000'
                                  : reference,
                              builder: (_) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  accountingFieldLabel(
                                    context,
                                    'Payment Reference *',
                                    alignToField: true,
                                    guidance: 'Record reimbursements already made. Each claim retains its category and receipt. Different recipients remain separate; no bank transfer is sent.',
                                  ),
                                  const SizedBox(
                                    height: accountingFieldLabelGap,
                                  ),
                                  TextField(
                                    key: const ValueKey(
                                      'claims-batch-reference',
                                    ),
                                    maxLength: 120,
                                    decoration: accountingInputDecoration(
                                      context,
                                      hintText: 'Payment Reference',
                                    ).copyWith(counterText: ''),
                                    onChanged: (value) =>
                                        refresh(() => reference = value),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  AccountingButton.outline(
                    context,
                    key: null,
                    onPressed: () => closeReference(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  AccountingButton.primary(
                    context,
                    key: const ValueKey('claims-batch-confirm'),
                    onPressed: reference.trim().isEmpty
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: const Text('Record Payments'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      for (final c in claims) {
        final latest = widget.store.byId(c.id);
        if (latest == null ||
            latest.status != ClaimStatus.approved ||
            jsonEncode(latest.toJson()) != reviewed[c.id]) {
          throw StateError(
            'A selected claim changed during review. Review the selection again.',
          );
        }
      }
      final batch = widget.workspace != null
          ? widget.workspace!.settleClaims(
              reviewedClaims: claims,
              requestId: EntityId.random(),
              bankAccountId: bankAccount!,
              paymentAccountId: paymentAccountId,
              paymentReference: reference.trim(),
              paidAt: DateTime.now().toUtc(),
            )
          : widget.store.markPaidBatch(
              claimIds: claims.map((c) => c.id).toList(),
              paymentBatchId: EntityId.random(),
              paidAt: DateTime.now().toUtc(),
              paymentReference: reference.trim(),
            );
      var message =
          '${claims.length} claim payments recorded · ${reference.trim()}';
      final filing = widget.paidClaimFilingService;
      if (filing is PaidClaimBatchFilingCoordinator) {
        try {
          final result = await (filing as PaidClaimBatchFilingCoordinator)
              .filePaidBatch(batch);
          if (result.status != PaidClaimFilingStatus.completed) {
            message += ' · Filing pending';
          }
        } catch (_) {
          message += ' · Filing pending';
        }
      } else if (claims.any((claim) => claim.attachments.isNotEmpty)) {
        message += ' · Filing pending';
      }
      if (!mounted) return;
      setState(() {
        _selectedClaims.clear();
        _selectingClaims = false;
        _feedback = message;
      });
      _showMessage(message);
    } catch (error) {
      _showError('Claim payments could not be recorded: $error');
    } finally {
      if (mounted) setState(() => _payingBatch = false);
    }
  }

  Future<void> _confirmPayment(Claim claim) async {
    if (widget.workspace != null) {
      _selectedClaims
        ..clear()
        ..add(claim.id);
      await _paySelectedClaims();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        key: ValueKey<String>('claim-payment-confirmation-${claim.id}'),
        title: 'Record claim payment?',
        content: Text(
          'This records the reimbursement through ClaimPaymentBatch for ${claim.claimantName}. It does not create a second expense.',
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
            key: ValueKey<String>('claim-confirm-pay-${claim.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final paymentBatchId = _newEntityId('claim-payment');
      final paidAt = DateTime.now().toUtc();
      final filingService = widget.paidClaimFilingService;
      final filingResult = filingService == null
          ? null
          : await filingService.markPaidAndFile(
              claimId: claim.id,
              paymentBatchId: paymentBatchId,
              paidAt: paidAt,
            );
      if (filingService == null) {
        widget.store.markPaid(
          claim.id,
          paymentBatchId: paymentBatchId,
          paidAt: paidAt,
        );
      }
      if (!mounted) return;
      final feedback = switch (filingResult?.status) {
        PaidClaimFilingStatus.completed => 'Payment recorded and filed',
        PaidClaimFilingStatus.failed =>
          'Payment recorded; filing pending (${filingResult?.failureCode})',
        PaidClaimFilingStatus.pending => 'Payment recorded; filing pending',
        null => 'Payment recorded',
      };
      setState(() {
        _feedback = feedback;
      });
      _showMessage(feedback);
    } on Object catch (exception) {
      _showError('Claim payment could not be recorded: $exception');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = true;
    });
  }

  EntityId _newEntityId(String prefix) {
    final suffix = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    return EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-${suffix.substring(suffix.length - 12)}',
    );
  }
}

typedef ClaimPersistHandler = FutureOr<void> Function(Claim claim);

class ClaimEditorDialog extends StatefulWidget {
  const ClaimEditorDialog({
    required this.id,
    required this.onSaveDraft,
    required this.onSubmit,
    super.key,
    this.initial,
    this.readOnly = false,
    this.payees = PayeeCatalog.demo,
    this.payeeStore,
    this.claimCategories,
    this.defaultCurrencyCode = 'MYR',
    this.onAttachmentsPick,
    this.receiptTaxProposal = false,
    this.receiptAccounts = const [],
    this.receiptTaxCodes = const [],
  });

  final bool receiptTaxProposal;
  final List<Account> receiptAccounts;
  final List<CompanyTaxRate> receiptTaxCodes;
  final EntityId id;
  final Claim? initial;
  final bool readOnly;
  final ClaimPersistHandler onSaveDraft;
  final ClaimPersistHandler onSubmit;
  final List<Payee> payees;
  final PayeeStore? payeeStore;
  final List<ClaimCategory>? claimCategories;
  final String defaultCurrencyCode;
  final ExpenseAttachmentsPicker? onAttachmentsPick;

  @override
  State<ClaimEditorDialog> createState() => _ClaimEditorDialogState();
}

class _ClaimEditorDialogState extends State<ClaimEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _editorScroll = ScrollController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _purposeController = TextEditingController();
  final _receiptMerchantController = TextEditingController();
  ClaimReceiptsDraft? _receiptDraft;
  final _pendingReceiptOriginals = <String, String?>{};
  final _amountFocusNode = FocusNode();
  final _dateFocusNode = FocusNode();
  final _categoryFocusNode = FocusNode();

  final _pipeline = const ReceiptDocumentPipeline();
  final ReceiptArtifactStore _artifactStore = InMemoryReceiptArtifactStore();
  late final PayeeStore _payeeStore;
  late final List<ClaimCategory> _claimCategories;
  late CurrencyPresentation? _currency;
  ClaimCategory? _category;
  String _claimantValue = '';
  ClaimantIdentity? _claimantIdentity;
  String _merchantValue = '';
  final _claimantFieldAnchor = GlobalKey();
  final _merchantFieldAnchor = GlobalKey();
  TextEditingController? _claimantAutocompleteController;
  TextEditingController? _merchantAutocompleteController;
  bool _personallyPaid = true;
  List<ReceiptAttachment> _attachments = <ReceiptAttachment>[];
  String? _attachmentMessage;
  String? _error;
  bool _busy = false;
  bool _submitAttempt = false;
  ReceiptReviewQueue? _receiptReviewQueue;
  bool _reviewActive = false;
  bool _isDragOver = false;
  String? _payeeHoveredId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _payeeStore = widget.payeeStore ?? PayeeStore(payees: widget.payees);
    _claimCategories = List<ClaimCategory>.from(
      widget.claimCategories ?? ClaimCategoryCatalog.seeded,
    );
    final initialCurrencyCode =
        initial?.amount.currency ?? widget.defaultCurrencyCode;
    try {
      _currency = CurrencyPresentation.fromCode(initialCurrencyCode);
    } on FormatException {
      _currency = null;
    }
    _amountController.text = initial == null
        ? ''
        : formatAccountingMoneyInputText(
            _amountText(initial.amount),
            Currency.parse(initial.amount.currency).fractionDigits,
          );
    _dateController.text = formatAccountingInputDate(
      initial?.incurredOn ?? DateTime.now(),
    );
    _purposeController.text = initial?.businessPurpose ?? '';
    _claimantValue = initial?.claimantName ?? '';
    _claimantIdentity = initial?.claimantIdentity;
    _merchantValue = initial?.vendorName ?? '';
    _personallyPaid = initial?.personallyPaid ?? true;
    _attachments = List<ReceiptAttachment>.from(
      initial?.attachments ?? const <ReceiptAttachment>[],
    );
    if (initial != null) {
      for (final category in _claimCategories) {
        if (category.code == initial.claimCategoryCode ||
            category.displayName == initial.category ||
            category.expenseCategoryCode == initial.expenseCategoryCode) {
          _category = category;
          break;
        }
      }
    }
    if (widget.receiptTaxProposal && _currency != null) {
      _receiptDraft = ClaimReceiptsDraft(
        currency: _currency!.code,
        date: initial?.incurredOn ?? DateTime.now(),
        initial: initial?.receipts ?? const [],
      );
      _syncReceiptHeader();
      _receiptDraft!.addListener(_receiptChanged);
    }
  }

  void _syncReceiptHeader() {
    final draft = _receiptDraft;
    if (draft == null) return;
    _amountController.text =
        draft.gross(widget.receiptTaxCodes)?.toDecimalString() ?? '';
    _merchantValue = draft.merchantSummary;
    _receiptMerchantController.text = _merchantValue;
  }

  void _receiptChanged() {
    if (mounted) {
      setState(() {
        _syncReceiptHeader();
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _editorScroll.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _purposeController.dispose();
    _receiptMerchantController.dispose();
    _receiptDraft?.dispose();
    _amountFocusNode.dispose();
    _dateFocusNode.dispose();
    _categoryFocusNode.dispose();
    _receiptReviewQueue?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(880.0, math.max(280.0, viewport.width - 32));
    final height = math.min(760.0, math.max(280.0, viewport.height - 32));
    return Dialog(
      key: const ValueKey('claim-editor-dialog'),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: height,
        child: AccountingCard.surface(
          context,
          key: const ValueKey('claim-editor-form-card'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              _buildHeader(context),
              Expanded(
                child: AccountingPopoutScrollBody(
                  scrollKey: const ValueKey('claim-editor-scroll'),
                  controller: _editorScroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: accountingContentInset,
                  ),
                  child: Form(key: _formKey, child: _buildFormFields(context)),
                ),
              ),
              _buildCardFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Stack(
      children: [
        Container(
          key: const ValueKey('claim-editor-card-header'),
          width: double.infinity,
          padding: accountingContentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: [
                  Expanded(
                    child: accountingSectionTitle(
                      context,
                      widget.initial == null
                          ? 'New Expense Claim'
                          : widget.readOnly
                          ? 'View Expense Claim'
                          : 'Edit Expense Claim',
                      key: const ValueKey('claim-editor-title'),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 6),
              accountingHelperText(
                context,
                'Submit for Review keeps personal reimbursement separate from direct company expenses.',
              ),
            ],
          ),
        ),
        Positioned(
          top: AccountingPopoutTokens.closeInset,
          right: AccountingPopoutTokens.closeInset,
          child: accountingCompactClose(
            context,
            key: const ValueKey('claim-cancel'),
            enabled: !_busy,
          ),
        ),
      ],
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
        final pairedFields = <Widget>[
          AccountingOrdinaryFields(
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Claimant *',
                contentSample: 'Search claimant',
                minimumRowFraction: 0.5,
                builder: (_) => _buildClaimantField(context),
              ),
              AccountingOrdinaryFieldSlot(
                label: 'Claim category',
                minimumRowFraction: 0.5,
                choices: [
                  'Select Claim Category',
                  for (final category in _claimCategories) category.displayName,
                ],
                builder: (assignedWidth) =>
                    _buildCategoryField(context, width: assignedWidth),
              ),
            ],
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          AccountingOrdinaryFields(
            fields: [
              if (_receiptDraft == null)
                AccountingOrdinaryFieldSlot(
                  label: 'Merchant or supplier *',
                  contentSample: 'Search merchant or supplier',
                  builder: (_) => _buildMerchantField(context),
                )
              else
                AccountingOrdinaryFieldSlot(
                  label: 'Merchants',
                  contentSample: _receiptMerchantController.text.isEmpty
                      ? 'Multiple Merchants'
                      : _receiptMerchantController.text,
                  builder: (_) => _buildTextField(
                    context,
                    key: const ValueKey('claim-payee'),
                    label: 'Merchants',
                    controller: _receiptMerchantController,
                    readOnly: true,
                    helperText: 'Named separately on each receipt.',
                  ),
                ),
              AccountingOrdinaryFieldSlot(
                label: 'Date *',
                contentSample: '00-00-0000',
                date: true,
                hasGuidance: true,
                builder: (_) => _buildDateField(context),
              ),
              AccountingOrdinaryFieldSlot(
                label:
                    'Amount (${_currency?.amountSymbol ?? CurrencyPresentation.fromCode(widget.defaultCurrencyCode).amountSymbol}) *',
                contentSample: _amountController.text,
                hasGuidance: true,
                builder: (_) => _buildAmountField(context),
              ),
            ],
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          if (_receiptDraft != null) ...[
            ClaimReceiptsEditor(
              draft: _receiptDraft!,
              accounts: widget.receiptAccounts,
              codes: widget.receiptTaxCodes,
              evidence: _attachments,
              readOnly: widget.readOnly || _busy,
              onAddReceipt: _reviewActive ? null : () => _addReceiptOriginal(),
              onLinkOriginal: _reviewActive
                  ? null
                  : (r) => _addReceiptOriginal(receipt: r),
              evidenceSection: _buildAttachmentField(context),
            ),
            const SizedBox(height: AccountingResponsive.sectionGap),
          ],
          _buildPurposeField(context),
          const SizedBox(height: 16),
          _buildPersonallyPaidField(context),
          const SizedBox(height: AccountingResponsive.sectionGap),
          if (_receiptDraft == null) _buildAttachmentField(context),
        ];
        return KeyedSubtree(
          key: ValueKey<String>(
            canPair ? 'claim-editor-two-column' : 'claim-editor-stacked',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                AccountingAlert.build(
                  context,
                  key: const ValueKey('claim-editor-error'),
                  title: 'Could Not Save Claim',
                  description: _error!,
                  tone: AccountingAlertTone.critical,
                  bottomGap: accountingContentInset,
                ),
              for (var i = 0; i < pairedFields.length; i++)
                IgnorePointer(
                  ignoring:
                      widget.readOnly &&
                      pairedFields[i] is! ClaimReceiptsEditor &&
                      i < pairedFields.length - 1,
                  child: ExcludeFocus(
                    excluding:
                        widget.readOnly &&
                        pairedFields[i] is! ClaimReceiptsEditor &&
                        i < pairedFields.length - 1,
                    child: pairedFields[i],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAmountField(BuildContext context) {
    return _buildTextField(
      context,
      key: const ValueKey('claim-amount'),
      controller: _amountController,
      focusNode: _amountFocusNode,
      label:
          'Amount (${_currency?.amountSymbol ?? CurrencyPresentation.fromCode(widget.defaultCurrencyCode).amountSymbol})',
      isRequired: true,
      helperText: _receiptDraft == null
          ? _amountHelperText
          : 'Calculated from receipt totals.',
      readOnly: _receiptDraft != null,
      errorText: _fieldError('Amount must be greater than zero.'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        AccountingMoneyInputFormatter(
          _currency?.currency.fractionDigits ??
              Currency.parse(widget.defaultCurrencyCode).fractionDigits,
        ),
      ],
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _dateFocusNode.requestFocus(),
    );
  }

  Widget _buildDateField(BuildContext context) {
    return _buildTextField(
      context,
      key: const ValueKey('claim-date'),
      controller: _dateController,
      focusNode: _dateFocusNode,
      label: 'Date',
      isRequired: true,
      helperText: 'Local claim date.',
      errorText: _fieldError(_dateError),
      keyboardType: TextInputType.number,
      inputFormatters: const <TextInputFormatter>[DateInputFormatter()],
      compactDate: true,
      suffixIcon: accountingCalendarButton(
        context,
        controller: _dateController,
        label: 'Date',
        enabled: !_busy,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose claim date',
        onPicked: () => setState(() {}),
      ),
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _categoryFocusNode.requestFocus(),
    );
  }

  Widget _buildClaimantField(BuildContext context) {
    final initial = widget.initial;
    if (initial != null &&
        (initial.claimantName.isNotEmpty || initial.claimantIdentity != null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          accountingFieldLabel(
            context,
            'Claimant',
            alignToField: true,
            guidance: 'Retained from the original Claim. An existing claimant cannot be replaced.',
          ),
          const SizedBox(height: accountingFieldLabelGap),
          InputDecorator(
            key: const ValueKey('claim-claimant'),
            decoration: accountingSingleLineInputDecoration(context),
            child: accountingValueText(context, initial.claimantName),
          ),
        ],
      );
    }
    return _buildPayeeAutocomplete(
      context,
      claimant: true,
      label: 'Claimant',
      isRequired: true,
      fieldKey: const ValueKey('claim-claimant'),
      autocompleteKey: const ValueKey('claim-claimant-autocomplete'),
      menuKey: const ValueKey('claim-claimant-menu'),
      optionKeyPrefix: 'claim-claimant-option',
    );
  }

  Widget _buildMerchantField(BuildContext context) {
    return _buildPayeeAutocomplete(
      context,
      claimant: false,
      label: 'Merchant or supplier',
      isRequired: true,
      fieldKey: const ValueKey('claim-payee'),
      autocompleteKey: const ValueKey('claim-merchant-autocomplete'),
      menuKey: const ValueKey('claim-merchant-menu'),
      optionKeyPrefix: 'claim-merchant-option',
    );
  }

  Widget _buildPayeeAutocomplete(
    BuildContext context, {
    required bool claimant,
    required String label,
    required bool isRequired,
    required Key fieldKey,
    required Key autocompleteKey,
    required Key menuKey,
    required String optionKeyPrefix,
  }) {
    final candidates = _payeeStore.all
        .where(
          (payee) => claimant
              ? payee.type == PayeeType.staff ||
                    payee.type == PayeeType.director
              : payee.type == PayeeType.supplier ||
                    payee.type == PayeeType.vendor ||
                    payee.type == PayeeType.smallProvider,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildFieldLabel(
          context,
          label,
          isRequired,
          guidance: claimant
              ? 'Select employee/director; typed names stay unlinked.'
              : 'Supplier, vendor, or small provider who was paid.',
        ),
        const SizedBox(height: 8),
        Autocomplete<Payee>(
          key: autocompleteKey,
          displayStringForOption: (payee) => payee.name,
          optionsBuilder: (value) {
            final matches = filterPayees(candidates, value.text);
            final add = <Payee>[
              if (!widget.readOnly)
                Payee(
                  id: '__add-payee__',
                  name: claimant ? 'Add Claimant' : 'Add Merchant',
                  type: PayeeType.other,
                ),
            ];
            if (matches.isEmpty && value.text.trim().isNotEmpty) {
              return <Payee>[
                ...add,
                Payee(
                  id: '__no-matching-${claimant ? 'claimants' : 'merchants'}__',
                  name: 'No matching ${claimant ? 'claimants' : 'merchants'}',
                  type: PayeeType.other,
                ),
              ];
            }
            return [...add, ...matches];
          },
          onSelected: (payee) {
            if (payee.id == '__add-payee__') {
              FocusScope.of(context).unfocus();
              final previous = claimant ? _claimantValue : _merchantValue;
              final controller = claimant
                  ? _claimantAutocompleteController
                  : _merchantAutocompleteController;
              controller?.value = TextEditingValue(
                text: previous,
                selection: TextSelection.collapsed(offset: previous.length),
              );
              _addPayee(claimant: claimant);
              return;
            }
            if (payee.id.startsWith('__no-matching-')) return;
            if (claimant) {
              _claimantValue = payee.name;
              _claimantIdentity = ClaimantIdentity(
                payeeId: payee.id,
                type: payee.type == PayeeType.director
                    ? ClaimantType.director
                    : ClaimantType.staff,
              );
            } else {
              _merchantValue = payee.name;
            }
            _payeeHoveredId = null;
          },
          optionsViewBuilder: (context, onSelected, options) {
            final optionList = options.toList(growable: false);
            return PayeeAutocompleteMenu(
              triggerKey: claimant
                  ? _claimantFieldAnchor
                  : _merchantFieldAnchor,
              surfaceKey: menuKey,
              contentWidth: payeeAutocompleteMenuWidth(
                context,
                candidates,
                badged: true,
                extraLabels: [
                  claimant ? 'Add Claimant' : 'Add Merchant',
                  'No matching ${claimant ? 'claimants' : 'merchants'}',
                ],
              ),
              itemCount: optionList.length,
              itemBuilder: (context, index) {
                final payee = optionList[index];
                if (payee.id == '__add-payee__') {
                  return accountingSelectorCreationAction(
                    context,
                    key: ValueKey(
                      'claim-add-${claimant ? 'claimant' : 'merchant'}',
                    ),
                    label: payee.name,
                    onPressed: _busy
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            _addPayee(claimant: claimant);
                          },
                  );
                }
                if (payee.id.startsWith('__no-matching-')) {
                  return Padding(
                    key: ValueKey<String>('$optionKeyPrefix-no-results'),
                    padding: const EdgeInsets.all(12),
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
                      color: isHovered
                          ? AccountingTheme.of(context).accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey<String>('$optionKeyPrefix-${payee.id}'),
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
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    payee.name,
                                    softWrap: false,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AccountingTheme.of(context).muted,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AccountingTheme.of(context).border,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      payee.typeLabel,
                                      softWrap: false,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AccountingTheme.of(context)
                                                .mutedForeground,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
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
            final initialValue = claimant ? _claimantValue : _merchantValue;
            if (claimant) {
              _claimantAutocompleteController = controller;
            } else {
              _merchantAutocompleteController = controller;
            }
            if (controller.text.isEmpty && initialValue.isNotEmpty) {
              controller.value = TextEditingValue(
                text: initialValue,
                selection: TextSelection.collapsed(offset: initialValue.length),
              );
            }
            return KeyedSubtree(
              key: claimant ? _claimantFieldAnchor : _merchantFieldAnchor,
              child: Semantics(
                container: true,
                label: '$label, ${isRequired ? 'required' : 'optional'}',
                child: TextFormField(
                  key: fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  onTap: _clearPayeeHover,
                  onChanged: (value) {
                    _clearPayeeHover();
                    if (claimant) {
                      if (value != _claimantValue) _claimantIdentity = null;
                      _claimantValue = value;
                    } else {
                      _merchantValue = value;
                    }
                  },
                  onFieldSubmitted: (_) {
                    onFieldSubmitted();
                    _dateFocusNode.requestFocus();
                  },
                  decoration: accountingInputDecoration(
                    context,
                    hintText: claimant
                        ? 'Search claimant'
                        : 'Search merchant or supplier',
                    errorText: _fieldError(
                      claimant
                          ? 'Claimant is required.'
                          : 'Merchant or supplier is required.',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _addPayee({required bool claimant}) async {
    final nameController = TextEditingController();
    final allowedTypes = claimant
        ? <PayeeType>[
            for (final value in const [PayeeType.staff, PayeeType.director])
              if (value.canQuickCreate) value,
          ]
        : const <PayeeType>[
            PayeeType.supplier,
            PayeeType.vendor,
            PayeeType.smallProvider,
          ];
    var type = allowedTypes.first;
    String? error;
    final route = DialogRoute<Payee>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AccountingDialog.alert(
          dialogContext,
          title: claimant ? 'Add Claimant' : 'Add Merchant',
          formFooter: true,
          content: SizedBox(
            width: 232, // Existing acquired content width, measured at both desktop starts.
            child: AccountingOrdinaryFields(
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: claimant ? 'Claimant name' : 'Merchant name',
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(
                        context,
                        claimant ? 'Claimant name' : 'Merchant name',
                        alignToField: true,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: ValueKey<String>(
                          'claim-add-${claimant ? 'claimant' : 'merchant'}-name',
                        ),
                        controller: nameController,
                        autofocus: true,
                        decoration: accountingInputDecoration(
                          context,
                          hintText: claimant
                              ? 'Name'
                              : 'Business or supplier name',
                          errorText: error,
                        ),
                      ),
                    ],
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Payee type',
                  choices: [
                    'Select payee type',
                    for (final option in allowedTypes) option.label,
                  ],
                  builder: (assignedWidth) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Payee type',
                        alignToField: true,
                      ),
                      const SizedBox(height: 8),
                      AccountingSelector<PayeeType>(
                        assignedWidth: assignedWidth,
                        options: <AccountingSelectorOption<PayeeType>>[
                          for (final option in allowedTypes)
                            AccountingSelectorOption<PayeeType>(
                              value: option,
                              label: option.label,
                            ),
                        ],
                        value: type,
                        onChanged: (value) {
                          if (value != null) setDialogState(() => type = value);
                        },
                        hintText: 'Select payee type',
                        controlKey: const ValueKey('claim-add-payee-type'),
                        menuKey: const ValueKey('claim-add-payee-type-menu'),
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
              dialogContext,
              key: const ValueKey('claim-add-payee-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            AccountingButton.primary(
              dialogContext,
              key: const ValueKey('claim-add-payee-save'),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'A payee name is required.');
                  return;
                }
                Navigator.of(dialogContext).pop(
                  Payee(
                    id: 'payee-${DateTime.now().microsecondsSinceEpoch}',
                    name: name,
                    type: type,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
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
      final value = TextEditingValue(
        text: payee.name,
        selection: TextSelection.collapsed(offset: payee.name.length),
      );
      if (claimant) {
        _claimantValue = payee.name;
        _claimantIdentity = ClaimantIdentity(
          payeeId: payee.id,
          type: payee.type == PayeeType.director
              ? ClaimantType.director
              : ClaimantType.staff,
        );
        _claimantAutocompleteController?.value = value;
      } else {
        _merchantValue = payee.name;
        _merchantAutocompleteController?.value = value;
      }
    });
  }

  Widget _buildCategoryField(BuildContext context, {required double width}) {
    return FormField<ClaimCategory>(
      validator: (_) => _categoryError,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldLabel(
            context,
            'Claim category',
            true,
            guidance:
                '$_categoryHelperText ${_receiptDraft == null ? 'Maps to expense/GL for the selected category.' : 'Used for the claim reference; receipt rows choose the expense or asset account.'}',
          ),
          const SizedBox(height: 8),
          AccountingSelector<ClaimCategory>(
            assignedWidth: width,
            options: <AccountingSelectorOption<ClaimCategory>>[
              for (final category in _claimCategories)
                AccountingSelectorOption<ClaimCategory>(
                  value: category,
                  label: category.displayName,
                  key: ValueKey<String>(
                    'claim-category-option-${category.code}',
                  ),
                ),
            ],
            value: _category,
            onChanged: (value) {
              if (!mounted) return;
              setState(() => _category = value);
              state.didChange(value);
            },
            hintText: 'Select Claim Category',
            controlKey: const ValueKey('claim-category-control'),
            triggerKey: const ValueKey('claim-category'),
            menuKey: const ValueKey('claim-category-menu'),
            searchable: true,
            searchKey: const ValueKey('claim-category-search'),
            searchHintText: 'Search claim categories',
            emptyText: 'No claim categories available',
            helperText: _claimCategories.isEmpty ? _categoryHelperText : null,
            errorText: state.errorText,
            enabled: !_busy && _claimCategories.isNotEmpty,
            focusNode: _categoryFocusNode,
            semanticsLabel: 'Claim category, required',
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeField(BuildContext context) {
    return _buildTextField(
      context,
      key: const ValueKey('claim-purpose'),
      controller: _purposeController,
      label: 'Business purpose',
      helperText:
          'Required to submit for review. Keep the reimbursement context.',
      errorText: _fieldError('Business purpose is required to submit.'),
      keyboardType: TextInputType.multiline,
      narrativeLines: 3,
    );
  }

  Widget _buildPersonallyPaidField(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Paid personally by the claimant, required for submission',
      child: InkWell(
        key: const ValueKey('claim-personal-payment'),
        borderRadius: BorderRadius.circular(10),
        onTap: _busy
            ? null
            : () => setState(() => _personallyPaid = !_personallyPaid),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AccountingSwitch(
                alignment: Alignment.centerLeft,
                value: _personallyPaid,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _personallyPaid = value),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: accountingFieldLabel(
                    context,
                    'Paid personally by the claimant',
                    alignToField: true,
                    guidance: 'Required for reimbursement. Use Record Expense when a company account paid the merchant.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentField(BuildContext context) {
    if (widget.readOnly) {
      return AccountingAttachmentList(
        paginationKey: 'claim-attachments',
        children: [
          for (final attachment in _attachments)
            _buildAttachmentRow(context, attachment),
        ],
      );
    }
    final tokens = AccountingTheme.of(context);
    final attachmentError = _submitAttempt && !_hasReviewableAttachment
        ? 'Receipt or document is required to submit.'
        : null;
    Widget dropzone = Semantics(
      container: true,
      button: true,
      label: 'Add receipt or upload an image or PDF',
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _receiptDraft == null
                ? _chooseAttachments()
                : _addReceiptOriginal();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          key: const ValueKey('claim-receipt-dropzone'),
          borderRadius: BorderRadius.circular(10),
          onTap: _busy
              ? null
              : _receiptDraft == null
              ? _chooseAttachments
              : _addReceiptOriginal,
          child: AccountingAttachmentDropzone(
            surfaceKey: const ValueKey('claim-receipt-surface'),
            contentKey: const ValueKey('claim-receipt-content'),
            promptKey: const ValueKey('claim-upload-prompt'),
            actionKey: const ValueKey('claim-upload-file-action'),
            dragOver: _isDragOver,
            onChoose: _busy
                ? null
                : _receiptDraft == null
                ? _chooseAttachments
                : _addReceiptOriginal,
            prompt: 'Drop receipts here or choose files',
            formats: 'JPEG, PNG, HEIC, or PDF. Multiple files supported.',
          ),
        ),
      ),
    );
    if (_supportsFileDrop) {
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

    return Semantics(
      container: true,
      label: 'Receipt or document, required for submission',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldLabel(
            context,
            'Receipt or document',
            false,
            guidance: 'Optional for drafts. Required for review.',
          ),
          const SizedBox(height: 8),

          dropzone,
          if (attachmentError != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              attachmentError,
              key: const ValueKey('claim-attachment-error'),
              softWrap: true,
              style: AccountingTypography.helper(context)
                  .copyWith(color: tokens.destructive),
            ),
          ],
          if (_receiptReviewQueue?.hasUnresolved == true) ...<Widget>[
            const SizedBox(height: 8),
            AccountingButton.outline(
              context,
              key: const ValueKey('claim-review-receipts'),
              onPressed: _busy || _reviewActive
                  ? null
                  : () => _openReceiptReview(_receiptReviewQueue!),
              leadingIcon: Icons.rate_review_outlined,
              child: Text(
                'Review ${_receiptReviewQueue!.remainingCount} staged attachment${_receiptReviewQueue!.remainingCount == 1 ? '' : 's'}',
              ),
            ),
          ],
          if (_attachmentMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _attachmentMessage!,
                key: const ValueKey('claim-attachment-message'),
                softWrap: true,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ),
          ],
          if (_attachments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            AccountingAttachmentList(
              paginationKey: 'claim-attachments',
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
    const keyPrefix = 'claim';
    if (widget.readOnly) {
      return ReadonlyAttachmentRow(
        key: ValueKey('$keyPrefix-attachment-row-${attachment.originalId}'),
        attachment: attachment,
        keyPrefix: keyPrefix,
      );
    }
    return AccountingAttachmentRecordRow(
      key: ValueKey<String>(
        '$keyPrefix-attachment-row-${attachment.originalId}',
      ),
      attachment: attachment,
      statusKey: ValueKey(
        '$keyPrefix-attachment-status-${attachment.originalId}',
      ),
      actions: <Widget>[
        AccountingButton.iconOnly(
          context,
          key: ValueKey('$keyPrefix-attachment-view-${attachment.originalId}'),
          onPressed: () => showAttachmentPreview(context, attachment),
          icon: Icons.visibility_outlined,
          tooltip: 'View Attachment',
        ),
        if (!_reviewActive && attachment.canConvertToPdf)
          AccountingButton.iconOnly(
            context,
            key: ValueKey<String>(
              '$keyPrefix-attachment-crop-${attachment.originalId}',
            ),
            onPressed: _busy
                ? null
                : () => _openReceiptReview(
                    ReceiptReviewQueue(<ReceiptAttachment>[
                      attachment,
                    ], retainAttachmentsOnDiscard: true),
                  ),
            icon: Icons.edit_outlined,
            tooltip: 'Edit Attachment',
          ),
        if (!_reviewActive &&
            attachment.canConvertToPdf &&
            attachment.pdfBytes == null)
          AccountingButton.outline(
            context,
            key: ValueKey<String>(
              '$keyPrefix-attachment-convert-${attachment.originalId}',
            ),
            onPressed: _busy ? null : () => _convertAttachment(attachment),
            child: const Text('Convert to PDF'),
          ),
        AccountingButton.iconOnly(
          context,
          key: ValueKey<String>(
            '$keyPrefix-attachment-remove-${attachment.originalId}',
          ),
          onPressed: _busy
              ? null
              : () => _removeAttachment(attachment.originalId),
          icon: Icons.delete_outline,
          tooltip: 'Remove Attachment',
        ),
        if (attachment.status == AttachmentProcessingStatus.failed)
          AccountingButton.outline(
            context,
            key: ValueKey<String>(
              '$keyPrefix-attachment-retry-${attachment.originalId}',
            ),
            onPressed: _busy ? null : () => _retryAttachment(attachment),
            child: const Text('Retry'),
          ),
      ],
    );
  }

  Widget _buildCardFooter(BuildContext context) {
    if (widget.readOnly) return const SizedBox.shrink();
    return accountingFormFooter(
      context,
      key: const ValueKey('claim-editor-card-footer'),
      actions: [
        AccountingButton.outline(
          context,
          key: const ValueKey('claim-save-draft'),
          onPressed: _busy ? null : () => _persist(submit: false),
          child: const Text('Save Draft'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('claim-submit'),
          onPressed: _busy ? null : () => _persist(submit: true),
          child: _busy
              ? const Text('Saving…')
              : const Text('Submit For Review'),
        ),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required Key key,
    required String label,
    TextEditingController? controller,
    FocusNode? focusNode,
    String? helperText,
    String? errorText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    String? prefixText,
    Key? prefixKey,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    int? narrativeLines,
    bool isRequired = false,
    bool compactDate = false,
    bool readOnly = false,
  }) {
    assert(narrativeLines == null || narrativeLines > 1);
    final field = Semantics(
      container: true,
      label: isRequired ? '$label, required' : label,
      child: narrativeLines != null
          ? AccountingDescriptionField(
              key: key,
              fixedLines: narrativeLines,
              controller: controller,
              focusNode: focusNode,
              enabled: !_busy,
              decoration: accountingInputDecoration(
                context,
                errorText: errorText,
                hintText: _hintFor(label),
              ),
            )
          : TextFormField(
              key: key,
              controller: controller,
              focusNode: focusNode,
              enabled: !_busy,
              readOnly: readOnly,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              enableInteractiveSelection: true,
              textAlignVertical: TextAlignVertical.center,
              style: AccountingTypography.value(context),
              maxLines: 1,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              decoration: accountingInputDecoration(
                context,
                helperText: null,
                errorText: errorText,
                prefixText: prefixText,
                prefixKey: prefixKey,
                suffixIcon: suffixIcon,
                hintText: _hintFor(label),
              ),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildFieldLabel(context, label, isRequired, guidance: helperText),
        const SizedBox(height: accountingFieldLabelGap),
        compactDate ? accountingDateFieldFrame(child: field) : field,
      ],
    );
  }

  Widget _buildFieldLabel(
    BuildContext context,
    String label,
    bool isRequired, {
    String? guidance,
  }) {
    final tokens = AccountingTheme.of(context);
    final labelStyle = AccountingTypography.fieldLabel(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Semantics(
        container: true,
        label: isRequired ? '$label, required' : label,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: <Widget>[
            Text(
              label,
              key: ValueKey<String>('claim-label-${_slug(label)}'),
              softWrap: true,
              style: labelStyle,
            ),
            if (isRequired)
              Text(
                '*',
                key: ValueKey<String>('claim-required-${_slug(label)}'),
                style: labelStyle.copyWith(color: tokens.destructive),
              ),
            if (guidance != null)
              AccountingFieldHelp(label: label, message: guidance),
          ],
        ),
      ),
    );
  }

  String? _fieldError(String? message) {
    if (_error == null || message == null) return null;
    return _validationErrors(submit: _submitAttempt).contains(message)
        ? message
        : null;
  }

  String? get _dateError {
    if (_dateController.text.trim().isEmpty) return 'Date is required.';
    if (parseAccountingInputDate(_dateController.text) == null) {
      return 'Enter a valid local date.';
    }
    return null;
  }

  String? get _categoryError {
    if (_claimCategories.isEmpty) return 'No claim categories are available.';
    if (_category == null) return 'Category is required.';
    if (!_claimCategories.any((item) => item.code == _category!.code)) {
      return 'Selected claim category is no longer available.';
    }
    if (_category!.mappingNeedsReview) {
      return 'Claim category mapping needs review before submitting.';
    }
    return null;
  }

  String get _categoryHelperText => _claimCategories.isEmpty
      ? 'No claim categories are available.'
      : 'Choose a populated Claim Category.';

  String get _amountHelperText {
    final fractionDigits = _currency?.currency.fractionDigits;
    if (fractionDigits == null) return 'Enter an amount.';
    if (fractionDigits == 0) return 'Whole-number amount.';
    return 'Up to $fractionDigits decimal ${fractionDigits == 1 ? 'place' : 'places'}.';
  }

  List<String> _validationErrors({required bool submit}) {
    final errors = <String>[];
    if (_claimantValue.trim().isEmpty) errors.add('Claimant is required.');
    if (_merchantValue.trim().isEmpty) {
      errors.add('Merchant or supplier is required.');
    }
    final amountError = _amountError;
    if (amountError != null) errors.add(amountError);
    final dateError = _dateError;
    if (dateError != null) errors.add(dateError);
    if (_currency == null) errors.add('Currency is required.');
    final categoryError = _categoryError;
    if (categoryError != null) errors.add(categoryError);
    if (submit) {
      if (_purposeController.text.trim().isEmpty) {
        errors.add('Business purpose is required to submit.');
      }
      if (!_personallyPaid) {
        errors.add('Personal payment must be confirmed for a claim.');
      }
      if (!_hasReviewableAttachment) {
        errors.add('Receipt or document is required to submit.');
      }
      if (_receiptReviewQueue?.hasUnresolved == true) {
        errors.add(
          'Review or explicitly leave staged attachments before submitting.',
        );
      }
    }
    return errors;
  }

  String? get _amountError {
    final trimmed = _amountController.text.trim();
    if (trimmed.isEmpty) return 'Amount must be greater than zero.';
    final parsed = double.tryParse(trimmed.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return 'Amount must be greater than zero.';
    }
    final match = RegExp(r'^[0-9]+(?:,[0-9]{3})*(?:\.(\d+))?$')
        .firstMatch(trimmed);
    if (match == null) return 'Amount must be greater than zero.';
    final fractionDigits = _currency?.currency.fractionDigits;
    if (fractionDigits != null &&
        (match.group(1)?.length ?? 0) > fractionDigits) {
      return 'Amount must be greater than zero.';
    }
    return null;
  }

  bool get _hasReviewableAttachment => _attachments.any(
    (attachment) =>
        !attachment.reviewSkipped &&
        attachment.status == AttachmentProcessingStatus.ready,
  );

  Future<void> _persist({required bool submit}) async {
    final errors = _validationErrors(submit: submit);
    if (errors.isNotEmpty) {
      setState(() {
        _submitAttempt = submit;
        _error = submit
            ? 'Please fix the highlighted fields before submitting.'
            : 'Please provide the claimant, merchant, amount, date, and category for this draft.';
      });
      _revealError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _submitAttempt = submit;
    });
    try {
      final claim = _buildClaim();
      if (submit) {
        await widget.onSubmit(claim);
      } else {
        await widget.onSaveDraft(claim);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Claim could not be saved. Your entries are still here: $exception';
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

  Claim _buildClaim() {
    final category = _category!;
    final existingDate = widget.initial?.incurredOn;
    final date =
        existingDate != null &&
            _dateController.text == formatAccountingInputDate(existingDate)
        ? existingDate
        : accountingCalendarDate(
            parseAccountingInputDate(_dateController.text)!,
          );
    final attachments = _attachments
        .where((attachment) => !attachment.reviewSkipped)
        .toList(growable: false);
    return Claim.draft(
      id: widget.id,
      vendorName: _merchantValue,
      amount: Money.fromDecimal(_amountController.text, _currency!.code),
      claimantName: _claimantValue,
      claimantIdentity: _claimantIdentity,
      incurredOn: date,
      category: category.displayName,
      claimCategoryCode: category.code,
      expenseCategoryCode: category.expenseCategoryCode,
      expenseAccountCode: category.expenseAccountCode,
      businessPurpose: _purposeController.text,
      personallyPaid: _personallyPaid,
      attachments: attachments,
      // Receipt-aware records must never lose retained details through the
      // existing single-amount editor while its new layout is under review.
      receipts:
          _receiptDraft?.build(
            widget.receiptAccounts,
            widget.receiptTaxCodes,
            attachments,
          ) ??
          widget.initial?.receipts ??
          const [],
    );
  }

  Future<void> _addReceiptOriginal({ClaimReceiptInput? receipt}) async {
    final draft = _receiptDraft;
    if (draft == null || _busy || _reviewActive) return;
    final linked = draft.receipts.expand((r) => r.originals).toSet();
    final available = _attachments
        .where(
          (a) =>
              !a.reviewSkipped &&
              a.status == AttachmentProcessingStatus.ready &&
              !linked.contains(a.originalId),
        )
        .firstOrNull;
    if (available != null) {
      if (receipt == null) {
        draft.addReceipt(originalId: available.originalId);
      } else {
        receipt.originals.add(available.originalId);
        draft.changed();
      }
      return;
    }
    try {
      final picked = widget.onAttachmentsPick == null
          ? await const NativeExpenseAttachmentPicker().pick(context)
          : await widget.onAttachmentsPick!(context);
      await _processPickedAttachments(
        picked,
        receiptId: receipt?.id,
        linkReceipts: true,
      );
    } on Object catch (exception) {
      if (mounted) {
        setState(
          () => _attachmentMessage =
              'The file chooser could not be opened: $exception',
        );
      }
    }
  }

  Future<void> _chooseAttachments() async {
    try {
      final picked = widget.onAttachmentsPick == null
          ? await const NativeExpenseAttachmentPicker().pick(context)
          : await widget.onAttachmentsPick!(context);
      await _processPickedAttachments(picked);
    } on Object catch (exception) {
      if (mounted) {
        setState(() {
          _attachmentMessage =
              'The file chooser could not be opened: $exception';
        });
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
    List<PickedExpenseAttachment> picked, {
    String? receiptId,
    bool linkReceipts = false,
  }) async {
    if (picked.isEmpty) return;
    final batchId = _newLocalId('claim-batch');
    final inputs = <ReceiptAttachmentInput>[];
    final queued = <ReceiptAttachment>[];
    for (final item in picked) {
      final input = ReceiptAttachmentInput(
        originalId: _newLocalId('claim-original'),
        batchId: batchId,
        filename: item.name,
        mimeType: item.mimeType,
        bytes: item.bytes,
      );
      inputs.add(input);
      if (linkReceipts ||
          _receiptDraft != null && _receiptDraft!.receipts.isEmpty) {
        _pendingReceiptOriginals[input.originalId] = receiptId;
      }
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
        setupKind: SetupKind.claims,
        destinationDate: parseAccountingInputDate(_dateController.text),
        categoryCode: _category?.code ?? '',
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
      final draft = _receiptDraft;
      if (draft != null) {
        for (final item in queue.items) {
          final originalId = item.attachment.originalId;
          if (!_pendingReceiptOriginals.containsKey(originalId)) continue;
          if (item.state == ReceiptReviewItemState.saved) {
            final receiptId = _pendingReceiptOriginals.remove(originalId);
            if (receiptId == null) {
              draft.addReceipt(originalId: originalId);
            } else {
              final receipt = draft.receipts
                  .where((r) => r.id == receiptId)
                  .firstOrNull;
              if (receipt != null && !receipt.originals.contains(originalId)) {
                receipt.originals.add(originalId);
                draft.changed();
              }
            }
          } else if (item.state == ReceiptReviewItemState.skipped ||
              item.state == ReceiptReviewItemState.discarded) {
            _pendingReceiptOriginals.remove(originalId);
          }
        }
      }
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
    setState(() {
      _attachments = _attachments
          .where((item) => item.originalId != originalId)
          .toList();
    });
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

  String _hintFor(String label) {
    switch (label) {
      case 'Amount':
        return '0.00';
      case 'Date':
        return 'DD-MM-YYYY';
      case 'Business purpose':
        return 'Describe the business reason';
      default:
        return '';
    }
  }

  String _slug(String label) {
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _amountText(Money amount) {
    final currency = Currency.parse(amount.currency);
    final magnitude = BigInt.from(amount.minorUnits)
        .abs()
        .toString()
        .padLeft(currency.fractionDigits + 1, '0');
    final split = magnitude.length - currency.fractionDigits;
    final text = currency.fractionDigits == 0
        ? magnitude
        : '${magnitude.substring(0, split)}.${magnitude.substring(split)}';
    return amount.minorUnits < 0 ? '-$text' : text;
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
