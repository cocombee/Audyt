import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/core/ids/entity_id.dart';

import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/domain/expense_draft.dart';
import '../../accounting/domain/payee.dart';
import '../../accounting/presentation/record_expense_page.dart'
    show RecordExpensePage, RecordExpenseClaimContext;
import '../../accounting/presentation/receipt_attachment_picker.dart';
import '../domain/claim_expense_creation.dart';

/// New Claim entry is the existing Expense owner with one claimant field.
/// Historical Claim details use their existing adapters, never this creator.
class ClaimExpenseCreationDialog extends StatefulWidget {
  const ClaimExpenseCreationDialog({
    required this.gateway,
    required this.initialContext,
    required this.onSaved,
    required this.onCancel,
    this.workspace,
    this.payeeStore,
    this.payees = PayeeCatalog.demo,
    this.defaultCurrencyCode = 'MYR',
    this.onAttachmentsPick,
    super.key,
  });
  final ClaimExpenseCreationGateway gateway;
  final ServiceClaimantContext initialContext;
  final VoidCallback onSaved, onCancel;
  final AccountingWorkspace? workspace;
  final PayeeStore? payeeStore;
  final List<Payee> payees;
  final String defaultCurrencyCode;
  final ExpenseAttachmentsPicker? onAttachmentsPick;

  @override
  State<ClaimExpenseCreationDialog> createState() =>
      _ClaimExpenseCreationDialogState();
}

class _ClaimExpenseCreationDialogState
    extends State<ClaimExpenseCreationDialog> {
  final _claimId = EntityId.random();
  String? _lastRequestKey;
  EntityId? _lastRequestId;
  late ServiceClaimantContext _context;
  late ServiceClaimantContext _selectionContext;
  late ServiceClaimant _selected;
  String? _lookupError;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _context = widget.initialContext;
    _selectionContext = _context;
    _selected = _context.actor;
    if (widget.gateway.businessId != _context.businessId ||
        (widget.workspace != null &&
            widget.workspace!.identity.businessId.value !=
                _context.businessId)) {
      throw ArgumentError('Claim entry belongs to another company.');
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchGeneration++;
    super.dispose();
  }

  void _search(String query) {
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _lookupError = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final next = await widget.gateway.claimants(query);
        if (!mounted || generation != _searchGeneration) return;
        if (!sameClaimActor(_context, next)) {
          throw StateError('Claim access changed.');
        }
        setState(() {
          _context = next;
          for (final choice in [next.actor, ...next.claimants]) {
            if (choice.identityId == _selected.identityId) {
              _selected = choice;
              _selectionContext = next;
              break;
            }
          }
          _searching = false;
        });
      } on Object {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _searching = false;
          _lookupError =
              'Claimant lookup failed. Reopen the claim and try again.';
        });
      }
    });
  }

  ClaimExpenseCreationCommand _command(
    RecordExpenseDraft draft,
    ClaimCreationIntent intent,
  ) {
    if (_searching || _lookupError != null) {
      throw StateError('Wait for the registered claimant lookup.');
    }
    // The request identity survives identical retries; the claim identity also
    // survives changed drafts. The gateway must reject conflicting creates and
    // resolve uncertain outcomes before acknowledging a different command.
    final key = jsonEncode([
      intent.name,
      _context.actor.identityId,
      _context.actor.revision,
      _selected.identityId,
      _selected.revision,
      draft.toJson(),
    ]);
    if (key != _lastRequestKey) {
      _lastRequestKey = key;
      _lastRequestId = EntityId.random();
    }
    return ClaimExpenseCreationCommand(
      requestId: _lastRequestId!,
      claimId: _claimId,
      intent: intent,
      context: _selectionContext,
      claimant: _selected,
      draft: draft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = <String, ServiceClaimant>{
      _context.actor.identityId: _context.actor,
      for (final claimant in _context.claimants) claimant.identityId: claimant,
      // A filtered search must not lose the current choice. Its authoritative
      // membership/revision is still rechecked by the command gateway.
      _selected.identityId: _selected,
    };
    return RecordExpensePage(
      includeTopSafeArea: false,
      preferences: widget.workspace?.preferences,
      settingsWorkspace: widget.workspace,
      payeeStore: widget.payeeStore,
      payees: widget.payees,
      defaultCurrencyCode: widget.defaultCurrencyCode,
      onAttachmentsPick: widget.onAttachmentsPick,
      onCancel: widget.onCancel,
      onSaved: widget.onSaved,
      claimContext: RecordExpenseClaimContext(
        showSettingsShortcut: _context.canChooseOnBehalf,
        claimantField: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountingFieldLabel(
              context,
              'Claimant',
              alignToField: true,
              guidance: _context.canChooseOnBehalf
                  ? 'Choose the registered person who paid personally. An existing Claim keeps its original claimant.'
                  : 'Your registered identity is retained as claimant. You can submit only your own claim.',
            ),
            const SizedBox(height: accountingFieldLabelGap),
            if (_context.canChooseOnBehalf)
              AccountingSelector<String>(
                assignedWidth: double.infinity,
                controlKey: const ValueKey('claim-create-claimant'),
                menuKey: const ValueKey('claim-create-claimant-menu'),
                searchKey: const ValueKey('claim-create-claimant-search'),
                alwaysSearchable: true,
                hintText: 'Select Claimant',
                searchHintText: 'Search registered claimant',
                value: _selected.identityId,
                options: [
                  for (final claimant in choices.values)
                    AccountingSelectorOption(
                      value: claimant.identityId,
                      label: claimant.name,
                      key: ValueKey(
                        'claim-create-option-${claimant.identityId}',
                      ),
                    ),
                ],
                onQueryChanged: _search,
                onChanged: (id) {
                  if (id == null || !choices.containsKey(id)) return;
                  setState(() {
                    _selected = choices[id]!;
                    if ([
                      _context.actor,
                      ..._context.claimants,
                    ].any((choice) => choice.identityId == id)) {
                      _selectionContext = _context;
                    }
                  });
                },
              )
            else
              InputDecorator(
                key: const ValueKey('claim-create-claimant'),
                decoration: accountingSingleLineInputDecoration(context),
                child: accountingValueText(context, _selected.name),
              ),
            if (_lookupError != null)
              AccountingAlert.build(
                context,
                title: 'Claimant Lookup Failed',
                description: _lookupError!,
                tone: AccountingAlertTone.critical,
              ),
          ],
        ),
        submissionErrors: (draft) => _command(
          draft,
          ClaimCreationIntent.submitForReview,
        ).validationClaim.submissionErrors,
        saveDraft: (draft) => widget.gateway.execute(
          _command(draft, ClaimCreationIntent.saveDraft),
        ),
        submitForReview: (draft) => widget.gateway.execute(
          _command(draft, ClaimCreationIntent.submitForReview),
        ),
      ),
    );
  }
}
