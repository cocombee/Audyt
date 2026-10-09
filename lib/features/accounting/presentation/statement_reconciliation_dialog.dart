import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/documents/receipt_document.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/money/money.dart';
import '../application/accounting_workspace.dart';
import '../data/accounting_database.dart';
import '../domain/statement_reconciliation.dart';
import '../domain/account_reconciliation.dart';
import 'widgets/accounting_formatters.dart';
import 'widgets/accounting_layout.dart';
import 'attachment_preview_dialog.dart';
import 'receipt_attachment_picker.dart';
import 'journal_workspace_page.dart';
import 'reconciliation_adjustment_dialog.dart';

typedef ReconciliationNavigationGuard = Future<void> Function(
  VoidCallback navigate,
);

class StatementReconciliationDialog extends StatefulWidget {
  const StatementReconciliationDialog({
    super.key,
    required this.workspace,
    required this.statementId,
    required this.currency,
    this.embedded = false,
    this.compactEmbedded = false,
    this.contextSection,
    this.formActions = const [],
    this.onBack,
    this.onAttachmentsPick,
    this.onNavigationGuardChanged,
  }) : paymentAccountId = null,
       sourceLabel = null,
       onRecordExpense = null,
       onReceivePayment = null;

  const StatementReconciliationDialog.account({
    super.key,
    required this.workspace,
    required String this.paymentAccountId,
    required this.currency,
    required this.sourceLabel,
    this.embedded = false,
    this.compactEmbedded = false,
    this.contextSection,
    this.formActions = const [],
    this.onBack,
    this.onAttachmentsPick,
    this.onNavigationGuardChanged,
    this.onRecordExpense,
    this.onReceivePayment,
  }) : statementId = null;
  final AccountingWorkspace workspace;
  final EntityId? statementId;
  final String? paymentAccountId;
  final String? sourceLabel;
  final String currency;
  final bool embedded;
  final bool compactEmbedded;
  final Widget? contextSection;
  final List<Widget> formActions;
  final VoidCallback? onBack;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  final void Function(Object owner, ReconciliationNavigationGuard? guard)?
  onNavigationGuardChanged;
  final Future<void> Function(DateTime date)? onRecordExpense;
  final Future<void> Function(DateTime date)? onReceivePayment;
  @override
  State<StatementReconciliationDialog> createState() =>
      _StatementReconciliationDialogState();
}

class _StatementReconciliationDialogState
    extends State<StatementReconciliationDialog> {
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _opening = TextEditingController();
  final _closing = TextEditingController();
  final _evidence = TextEditingController();
  StatementReconciliationSnapshot? _snapshot;
  AccountReconciliationSnapshot? _accountSnapshot;
  final _selected = <String>{};
  String? _expectedPreviousId;
  bool _transactionBusy = false;
  int _accountOffset = 0;
  int _accountPageSize = AccountingRecordPageSizes.read(
    'reconciliation-account-items',
    fallback: AccountingRecordControlsPolicy.defaultPageSize,
  );
  bool get _accountMode => widget.paymentAccountId != null;
  bool get _hasReview => _snapshot != null || _accountSnapshot != null;
  bool get _ready =>
      _accountSnapshot?.reviewAgrees ?? _snapshot?.readyForApproval ?? false;
  String? get _previousId =>
      _accountMode ? _accountSnapshot?.previousId : _snapshot?.previousId;
  bool get _previousUnchanged =>
      _accountSnapshot?.previousLedgerUnchanged ??
      _snapshot?.previousLedgerUnchanged ??
      true;
  Money get _recordedOpening =>
      _accountSnapshot?.recordedOpening ?? _snapshot!.recordedOpening;
  Money get _openingDifference => _accountSnapshot == null
      ? _snapshot!.openingDifference
      : _accountSnapshot!.openingBalance - _accountSnapshot!.recordedOpening;
  bool get _periodContinues =>
      _accountSnapshot?.periodContinues ?? _snapshot!.periodContinues;
  DateTime? get _requiredStart =>
      _accountSnapshot?.requiredStart ?? _snapshot?.requiredStart;
  List<OpeningLedgerMovement> get _openingMovements => _accountSnapshot == null
      ? _snapshot!.openingMovements
      : _accountSnapshot!.ledgerMovements
            .where((m) => m.date.isBefore(_accountSnapshot!.startsOn))
            .toList();
  EntityId? _requestId;
  bool _approved = false;
  final _outstanding = <String>{};
  int _openingOffset = 0;
  int _openingPageSize = AccountingRecordPageSizes.read(
    'reconciliation-opening-items',
    fallback: AccountingRecordControlsPolicy.defaultPageSize,
  );
  StatementReconciliationReview? get _review => _snapshot?.review;
  String? _error;
  int _warningRevision = 0;
  int _draftRevision = 0;
  bool _draftSaved = false;
  bool _filesBusy = false;
  List<ReceiptAttachment> _attachments = [];
  final _editingFocus = FocusScopeNode();
  bool _closePromptOpen = false;
  late String _savedInput;

  @override
  void initState() {
    super.initState();
    widget.onNavigationGuardChanged?.call(this, _guardNavigation);
    if (_accountMode) {
      _loadAccountInputs();
      _savedInput = _inputSnapshot();
      return;
    }
    final statement = widget.workspace.database.bankStatement(
      widget.workspace.identity.businessId,
      widget.statementId!,
    );
    if (statement != null && statement.rows.isNotEmpty) {
      final dates = statement.rows.map((row) => row.date).toList()..sort();
      _start.text = formatAccountingInputDate(dates.first);
      _end.text = formatAccountingInputDate(dates.last);
    }
    if (statement?.statementDate case final date?) {
      _start.text = formatAccountingInputDate(
        DateTime.utc(date.year, date.month),
      );
      _end.text = formatAccountingInputDate(date);
      _opening.text = _inputAmount(statement!.openingBalance!);
      _closing.text = _inputAmount(statement.closingBalance!);
    }
    try {
      final draft = widget.workspace.database.readReconciliationDraft(
        widget.workspace.identity.businessId,
        widget.statementId!,
      );
      if (draft != null) {
        _start.text = formatAccountingInputDate(draft.startsOn);
        _end.text = formatAccountingInputDate(draft.endsOn);
        _opening.text = _inputAmount(draft.openingBalance);
        _closing.text = _inputAmount(draft.closingBalance);
        _evidence.text = draft.openingEvidence;
        _outstanding.addAll(draft.openingOutstandingIds);
        _draftRevision = draft.revision;
        _attachments = draft.attachments.toList();
      }
    } catch (_) {
      _error = 'The saved draft could not be loaded. Reopen the statement before continuing.';
    }
    _savedInput = _inputSnapshot();
  }

  @override
  void didUpdateWidget(covariant StatementReconciliationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onNavigationGuardChanged != widget.onNavigationGuardChanged) {
      oldWidget.onNavigationGuardChanged?.call(this, null);
      widget.onNavigationGuardChanged?.call(this, _guardNavigation);
    }
  }

  void _loadAccountInputs() {
    try {
      final database = widget.workspace.database;
      final business = widget.workspace.identity.businessId;
      final account = widget.paymentAccountId!;
      final today = DateTime.now();
      final currentDay = DateTime.utc(today.year, today.month, today.day);
      final previousId = database.latestReconciliationId(business, account);
      _expectedPreviousId = previousId;
      final previous = previousId == null
          ? null
          : database
                .accountReconciliationHistory(business, account)
                .firstWhere((row) => row.id == previousId);
      final start = previous == null
          ? DateTime.utc(today.year, today.month)
          : previous.endsOn.add(const Duration(days: 1));
      _start.text = formatAccountingInputDate(start);
      _end.text = formatAccountingInputDate(
        currentDay.isBefore(start) ? start : currentDay,
      );
      final position = database.prepareAccountReconciliation(
        businessId: business,
        paymentAccountId: account,
        startsOn: start,
        endsOn: parseAccountingInputDate(_end.text)!,
        openingBalance: previous?.closingBalance ?? Money.zero(widget.currency),
        closingBalance: Money.zero(widget.currency),
      );
      _opening.text = _inputAmount(position.recordedOpening);
      final draft = database.readAccountReconciliationDraft(business, account);
      if (draft != null) {
        _start.text = formatAccountingInputDate(draft.startsOn);
        _end.text = formatAccountingInputDate(draft.endsOn);
        _opening.text = _inputAmount(draft.openingBalance);
        _closing.text = _inputAmount(draft.closingBalance);
        _evidence.text = draft.openingEvidence;
        _outstanding.addAll(draft.openingOutstandingIds);
        _selected.addAll(draft.selectedIds);
        _expectedPreviousId = draft.expectedPreviousId;
        _draftRevision = draft.revision;
        _attachments = draft.attachments.toList();
      }
    } catch (_) {
      _error = 'The account inputs could not be loaded. Check the ledger link before continuing.';
    }
  }

  @override
  void dispose() {
    widget.onNavigationGuardChanged?.call(this, null);
    _editingFocus.dispose();
    for (final controller in [_start, _end, _opening, _closing, _evidence]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _inputSnapshot() => jsonEncode([
    _start.text,
    _end.text,
    _opening.text,
    _closing.text,
    _evidence.text,
    _outstanding.toList()..sort(),
    _selected.toList()..sort(),
    [
      for (final file in _attachments)
        [file.originalId, file.originalSha256, file.derivativeSha256],
    ],
  ]);

  Future<void> _guardNavigation(VoidCallback navigate) async {
    if (_filesBusy || _transactionBusy || _closePromptOpen) return;
    if (!_approved && _inputSnapshot() != _savedInput) {
      _closePromptOpen = true;
      try {
        final discard = await AccountingDialog.confirmDiscardChanges(
          context,
          closeKey: const ValueKey('reconciliation-discard-close'),
          keepEditingKey: const ValueKey('reconciliation-keep-editing'),
          discardKey: const ValueKey('reconciliation-discard-changes'),
        );
        if (!mounted) return;
        if (!discard) {
          _editingFocus.requestFocus();
          return;
        }
      } finally {
        _closePromptOpen = false;
      }
    }
    if (!mounted) return;
    navigate();
  }

  Future<void> _handleClose() async {
    await _guardNavigation(() {
      if (widget.embedded) {
        widget.onBack?.call();
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  Widget _guardInput(Widget child) => FocusScope(
    node: _editingFocus,
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _handleClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );

  String _inputAmount(Money amount) => formatAccountingMoneyInputText(
    formatAccountingInputAmount(amount),
    Currency.parse(amount.currency).fractionDigits,
  );

  Money _amount(String value) {
    final text = value.trim();
    final match = RegExp(r'^[+-]?\d+(?:,\d{3})*(?:\.(\d+))?$').firstMatch(text);
    if (match == null ||
        (match.group(1)?.length ?? 0) >
            Currency.parse(widget.currency).fractionDigits) {
      throw const FormatException('Enter balances as exact decimal amounts.');
    }
    return Money.fromDecimal(text, widget.currency);
  }

  void _calculate() {
    try {
      final start = parseAccountingInputDate(_start.text);
      final end = parseAccountingInputDate(_end.text);
      if (start == null || end == null) {
        throw const FormatException('Enter valid statement dates.');
      }
      if (_accountMode) {
        final result = widget.workspace.database.prepareAccountReconciliation(
          businessId: widget.workspace.identity.businessId,
          paymentAccountId: widget.paymentAccountId!,
          startsOn: start,
          endsOn: end,
          openingBalance: _amount(_opening.text),
          closingBalance: _amount(_closing.text),
          selectedMovementIds: _selected,
          openingOutstandingIds: _outstanding,
        );
        setState(() {
          _accountSnapshot = result;
          _expectedPreviousId = result.previousId;
          _requestId = EntityId.random();
          _error = null;
        });
        return;
      }
      final result = widget.workspace.database.prepareStatementReconciliation(
        businessId: widget.workspace.identity.businessId,
        statementId: widget.statementId!,
        startsOn: start,
        endsOn: end,
        openingBalance: _amount(_opening.text),
        closingBalance: _amount(_closing.text),
        openingOutstandingIds: _outstanding,
      );
      setState(() {
        _snapshot = result;
        _requestId = EntityId.random();
        _error = null;
      });
    } catch (error) {
      setState(() {
        _snapshot = null;
        _accountSnapshot = null;
        _warningRevision++;
        _error = error is FormatException
            ? error.message
            : error is ArgumentError
            ? '${error.message}'
            : 'The statement could not be reviewed. Check the dates, balances and ledger link.';
      });
    }
  }

  void _approve() {
    if (_filesBusy) return;
    final snapshot = _snapshot;
    final request = _requestId;
    if (request == null || !_ready) {
      return;
    }
    try {
      if (_accountMode) {
        final reviewed = _accountSnapshot!;
        widget.workspace.database.approveAccountReconciliation(
          requestId: request,
          businessId: widget.workspace.identity.businessId,
          paymentAccountId: widget.paymentAccountId!,
          actorId: widget.workspace.identity.ownerId,
          approvedAt: DateTime.now(),
          startsOn: reviewed.startsOn,
          endsOn: reviewed.endsOn,
          openingBalance: reviewed.openingBalance,
          closingBalance: reviewed.closingBalance,
          selectedMovementIds: _selected,
          expectedLedgerFingerprint: reviewed.ledgerFingerprint,
          expectedPreviousId: reviewed.previousId,
          expectedDraftRevision: _draftRevision == 0 ? null : _draftRevision,
          firstOpeningEvidence: _evidence.text,
          openingOutstandingIds: reviewed.openingOutstandingIds,
          attachments: _attachments,
        );
      } else {
        widget.workspace.database.approveStatementReconciliation(
          requestId: request,
          businessId: widget.workspace.identity.businessId,
          statementId: widget.statementId!,
          actorId: widget.workspace.identity.ownerId,
          approvedAt: DateTime.now(),
          startsOn: snapshot!.startsOn,
          endsOn: snapshot.endsOn,
          openingBalance: snapshot.openingBalance,
          closingBalance: snapshot.closingBalance,
          expectedAcceptanceIds: snapshot.acceptanceIds,
          expectedPreviousId: snapshot.previousId,
          firstOpeningEvidence: _evidence.text,
          openingOutstandingIds: snapshot.openingOutstandingIds,
          attachments: _attachments,
        );
      }
      widget.workspace.refreshBankStatementReview();
      setState(() {
        _approved = true;
        _draftSaved = false;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _warningRevision++;
        _error = error is StateError
            ? error.message
            : error is ArgumentError
            ? '${error.message}'
            : 'Approval could not be saved. Review the statement again.';
      });
    }
  }

  void _saveDraft() {
    if (_filesBusy) return;
    try {
      final start = parseAccountingInputDate(_start.text);
      final end = parseAccountingInputDate(_end.text);
      if (start == null || end == null) {
        throw const FormatException('Enter valid statement dates.');
      }
      if (_accountMode) {
        final draft = widget.workspace.database.saveAccountReconciliationDraft(
          businessId: widget.workspace.identity.businessId,
          paymentAccountId: widget.paymentAccountId!,
          actorId: widget.workspace.identity.ownerId,
          expectedRevision: _draftRevision,
          expectedPreviousId: _expectedPreviousId,
          startsOn: start,
          endsOn: end,
          openingBalance: _amount(_opening.text),
          closingBalance: _amount(_closing.text),
          openingEvidence: _evidence.text,
          selectedIds: _selected,
          openingOutstandingIds: _outstanding,
          savedAt: DateTime.now(),
          attachments: _attachments,
        );
        setState(() {
          _draftRevision = draft.revision;
          _draftSaved = true;
          _error = null;
          _savedInput = _inputSnapshot();
        });
        return;
      }
      final draft = widget.workspace.database.saveReconciliationDraft(
        businessId: widget.workspace.identity.businessId,
        statementId: widget.statementId!,
        actorId: widget.workspace.identity.ownerId,
        expectedRevision: _draftRevision,
        startsOn: start,
        endsOn: end,
        openingBalance: _amount(_opening.text),
        closingBalance: _amount(_closing.text),
        openingEvidence: _evidence.text,
        openingOutstandingIds: _outstanding,
        savedAt: DateTime.now(),
        attachments: _attachments,
      );
      setState(() {
        _draftRevision = draft.revision;
        _draftSaved = true;
        _error = null;
        _savedInput = _inputSnapshot();
      });
    } catch (error) {
      setState(() {
        _draftSaved = false;
        _warningRevision++;
        _error = error is FormatException
            ? error.message
            : error is ArgumentError
            ? '${error.message}'
            : error is StateError
            ? error.message
            : 'The draft could not be saved. Reopen and review the statement.';
      });
    }
  }

  Future<void> _chooseSupportingFiles() async {
    if (_approved || _filesBusy) return;
    setState(() => _filesBusy = true);
    try {
      final files =
          await (widget.onAttachmentsPick ??
              const NativeExpenseAttachmentPicker().pick)(context);
      if (!mounted || files.isEmpty) return;
      final batch = EntityId.random().value;
      final picked = <ReceiptAttachment>[];
      for (final file in files) {
        final extension = file.name.split('.').last.toLowerCase();
        if (file.bytes.isEmpty ||
            !NativeExpenseAttachmentPicker.supportedExtensions.contains(
              extension,
            )) {
          throw const FormatException('Choose a supported, nonempty document.');
        }
        picked.add(
          ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: EntityId.random().value,
              batchId: batch,
              filename: file.name,
              mimeType: file.mimeType,
              bytes: file.bytes,
            ),
          ).withStatus(AttachmentProcessingStatus.ready),
        );
      }
      setState(() {
        _attachments = [..._attachments, ...picked];
        _draftSaved = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _warningRevision++;
          _error = error is FormatException
              ? error.message
              : 'The supporting files could not be read. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Widget _supportingFiles(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(
        context,
        'Supporting Files',
        alignToField: true,
        guidance: 'Optional additional evidence, preserved with this reconciliation approval.',
      ),
      const SizedBox(height: accountingFieldLabelGap),
      if (!_approved)
        AccountingAttachmentDropzone(
          surfaceKey: const ValueKey('reconciliation-file-uploader'),
          actionKey: const ValueKey('reconciliation-file-choose'),
          onChoose: _filesBusy ? null : _chooseSupportingFiles,
          prompt: 'Choose supporting files',
          formats:
              'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
        ),
      if (_attachments.isNotEmpty) ...[
        if (!_approved) const SizedBox(height: accountingContentInset),
        AccountingAttachmentList(
          paginationKey: 'reconciliation-supporting-files',
          children: [
            for (final file in _attachments)
              if (_approved)
                ReadonlyAttachmentRow(
                  attachment: file,
                  keyPrefix: 'reconciliation',
                )
              else
                AccountingAttachmentRecordRow(
                  attachment: file,
                  showProcessingStatus: false,
                  actions: [
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey(
                        'reconciliation-attachment-view-${file.originalId}',
                      ),
                      onPressed: () => showAttachmentPreview(context, file),
                      icon: Icons.visibility_outlined,
                      tooltip: 'View Attachment',
                    ),
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey(
                        'reconciliation-attachment-remove-${file.originalId}',
                      ),
                      onPressed: _filesBusy
                          ? null
                          : () => setState(() {
                              _attachments = _attachments
                                  .where(
                                    (item) =>
                                        item.originalId != file.originalId,
                                  )
                                  .toList();
                              _draftSaved = false;
                            }),
                      icon: Icons.delete_outline,
                      tooltip: 'Remove Attachment',
                    ),
                  ],
                ),
          ],
        ),
      ],
    ],
  );

  Widget _field(
    String label,
    String keyName,
    TextEditingController controller, {
    bool date = false,
    bool evidence = false,
    bool ordinary = false,
    String? guidance,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(
        context,
        label,
        alignToField: true,
        guidance: guidance,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      Builder(
        builder: (context) {
          final field = TextField(
            key: ValueKey(keyName),
            controller: controller,
            enableInteractiveSelection: true,
            readOnly: _approved,
            inputFormatters: date
                ? [const DateInputFormatter()]
                : evidence
                ? null
                : [
                    AccountingMoneyInputFormatter(
                      Currency.parse(widget.currency).fractionDigits,
                    ),
                  ],
            decoration: accountingSingleLineInputDecoration(context).copyWith(
              suffixIcon: date
                  ? accountingCalendarButton(
                      context,
                      controller: controller,
                      label: label,
                      enabled: !_approved,
                      onPicked: () => setState(() {
                        _draftSaved = false;
                        _snapshot = null;
                        _accountSnapshot = null;
                        _outstanding.clear();
                        _selected.clear();
                        _accountOffset = 0;
                        _openingOffset = 0;
                        _error = null;
                      }),
                    )
                  : null,
              hintText: date
                  ? 'DD-MM-YYYY'
                  : evidence
                  ? 'Opening evidence and outstanding items'
                  : _inputAmount(Money.zero(widget.currency)),
            ),
            onChanged: (_) => setState(() {
              _draftSaved = false;
              if (!evidence) {
                _snapshot = null;
                _accountSnapshot = null;
                if (!_accountMode || date) _outstanding.clear();
                if (date) {
                  _selected.clear();
                  _accountOffset = 0;
                }
                _openingOffset = 0;
              }
              _error = null;
            }),
          );
          return date ? accountingDateFieldFrame(child: field) : field;
        },
      ),
      if (!ordinary) const SizedBox(height: accountingContentInset),
    ],
  );

  List<OpeningLedgerMovement> _eligibleAccountMovements(
    AccountReconciliationSnapshot snapshot,
  ) {
    final ids = {
      ...snapshot.review.selected.map((m) => m.id),
      ...snapshot.review.outstanding.map((m) => m.id),
    };
    return snapshot.ledgerMovements.where((m) => ids.contains(m.id)).toList();
  }

  Widget _movementSelection({
    required String title,
    required String guidance,
    required String cardKey,
    required String keyPrefix,
    required String paginationKey,
    required List<OpeningLedgerMovement> rows,
    required Set<String> selectedIds,
    required int offset,
    required int pageSize,
    required ValueChanged<int> onPageSizeChanged,
    required ValueChanged<int> onOffsetChanged,
  }) => AccountingCard.surface(
    context,
    key: ValueKey(cardKey),
    child: Padding(
      padding: accountingContentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingFieldLabel(
            context,
            title,
            alignToField: true,
            guidance: guidance,
          ),
          const SizedBox(height: accountingContentInset),
          if (rows.isEmpty)
            Text(
              'No Eligible Transactions',
              style: AccountingTypography.value(context),
            ),
          for (final (index, item) in rows.skip(offset).take(pageSize).indexed)
            Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 0 : accountingUndividedRowVerticalInset,
                bottom:
                    index == pageSize - 1 || offset + index == rows.length - 1
                    ? 0
                    : accountingUndividedRowVerticalInset,
              ),
              child: Row(
                children: [
                  AccountingLeadingCheckbox(
                    undividedRow: true,
                    checkboxKey: ValueKey('$keyPrefix-${item.id}'),
                    value: selectedIds.contains(item.id),
                    onChanged: _approved
                        ? null
                        : (selected) {
                            _draftSaved = false;
                            if (selected == true) {
                              selectedIds.add(item.id);
                            } else {
                              selectedIds.remove(item.id);
                            }
                            _calculate();
                          },
                    semanticLabel: '$title ${item.memo}',
                  ),
                  Expanded(
                    child: Text(
                      '${formatAccountingInputDate(item.date)} · ${item.memo} · ${formatAccountingMoney(context, item.amount)}',
                      style: AccountingTypography.value(context),
                    ),
                  ),
                ],
              ),
            ),
          if (AccountingRecordControlsPolicy.visible(rows.length)) ...[
            const SizedBox(height: accountingContentInset),
            AccountingRecordPagination(
              keyPrefix: paginationKey,
              total: rows.length,
              offset: offset,
              pageSize: pageSize,
              onPageSizeChanged: (value) => setState(() {
                onPageSizeChanged(value);
              }),
              onPrevious: offset == 0
                  ? null
                  : () => setState(() => onOffsetChanged(offset - pageSize)),
              onNext: offset + pageSize >= rows.length
                  ? null
                  : () => setState(() => onOffsetChanged(offset + pageSize)),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _transaction(Future<void> Function(DateTime) open) async {
    if (_transactionBusy || _approved) return;
    final date = parseAccountingInputDate(_end.text);
    if (date == null) {
      setState(() {
        _warningRevision++;
        _error =
            'Enter a valid statement end date before adding a transaction.';
      });
      return;
    }
    final hadReview = _hasReview;
    setState(() {
      _transactionBusy = true;
      _accountSnapshot = null;
      _snapshot = null;
      _error = null;
    });
    try {
      await open(date);
      if (mounted && hadReview) _calculate();
    } catch (error) {
      if (mounted) {
        setState(() {
          _warningRevision++;
          _error = error is StateError ? error.message : 'The transaction could not be opened. Your reconciliation inputs are retained.';
        });
      }
    } finally {
      if (mounted) setState(() => _transactionBusy = false);
    }
  }

  Future<void> _newJournal(DateTime date) async {
    final workspace = widget.workspace;
    final linked = workspace.database.paymentLedgerAccount(
      workspace.identity.businessId,
      widget.paymentAccountId!,
    );
    final accounts = await workspace.accounts();
    if (!mounted) return;
    final id = await showJournalEditor(
      context,
      workspace,
      accounts,
      initialDate: date,
      initialAccountId: linked,
      showSavedNotice: false,
    );
    if (id != null && mounted) {
      await showDraftJournalReview(context, workspace, id);
    }
  }

  Future<void> _newAdjustment(DateTime date) async {
    final workspace = widget.workspace;
    final linked = workspace.database.paymentLedgerAccount(
      workspace.identity.businessId,
      widget.paymentAccountId!,
    );
    if (linked == null) {
      throw StateError('Link the bank account before adding an adjustment.');
    }
    final payment = workspace.database
        .readPaymentAccounts(workspace.identity.businessId)
        .singleWhere((account) => account.id == widget.paymentAccountId);
    final accounts = await workspace.accounts();
    if (!mounted) return;
    await showReconciliationAdjustment(
      context,
      accounts: accounts,
      bankLedgerId: linked,
      paymentAccountType: payment.type,
      bankLabel: widget.sourceLabel!,
      currency: widget.currency,
      initialDate: date,
    );
  }

  Widget _addTransactionMenu() {
    final entries =
        <({String key, String label, Future<void> Function(DateTime) open})>[
          if (widget.onRecordExpense != null)
            (
              key: 'record-expense',
              label: 'Record Expense',
              open: widget.onRecordExpense!,
            ),
          if (widget.onReceivePayment != null)
            (
              key: 'receive-payment',
              label: 'Receive Customer Payment',
              open: widget.onReceivePayment!,
            ),
          if (widget.currency == widget.workspace.identity.currency)
            (key: 'new-journal', label: 'New Journal', open: _newJournal),
        ];
    final width = accountingMenuContentWidth(
      context,
      entries.map((e) => (label: e.label, adornmentWidth: 0.0)),
    );
    final otherTransactions = AccountingMenuAnchor(
      menuWidth: width,
      style: accountingSelectorMenuStyle(context, width, 360),
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            key: ValueKey('reconciliation-add-${entry.key}'),
            style: accountingActionMenuItemStyle(context),
            onPressed: _transactionBusy ? null : () => _transaction(entry.open),
            child: Text(entry.label),
          ),
      ],
      builder: (context, controller, child) => AccountingButton.iconOnly(
        context,
        key: const ValueKey('reconciliation-other-transactions'),
        onPressed: _transactionBusy
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: Icons.more_horiz,
        tooltip: 'Other Transactions',
      ),
    );
    return AccountingRecordActions(
      trailing: [
        AccountingButton.outline(
          context,
          key: const ValueKey('reconciliation-add-transaction'),
          onPressed: _transactionBusy
              ? null
              : () => _transaction(_newAdjustment),
          child: const Text('Add Transaction'),
        ),
        if (entries.isNotEmpty) otherTransactions,
      ],
    );
  }

  Widget _fieldPair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 500
        ? Column(children: [first, second])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: accountingContentInset),
              Expanded(child: second),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final statement = widget.statementId == null
        ? null
        : widget.workspace.database.bankStatement(
            widget.workspace.identity.businessId,
            widget.statementId!,
          );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draftSaved)
          AccountingAlert.build(
            context,
            key: const ValueKey('reconciliation-draft-saved'),
            title: 'Draft Saved',
            description: 'Your statement inputs are saved. Review the current matches and balances before approval.',
            bottomGap: accountingContentInset,
          ),
        if (widget.embedded)
          _fieldPair(
            _field(
              'Statement Start',
              'reconciliation-start',
              _start,
              date: true,
            ),
            _field('Statement End', 'reconciliation-end', _end, date: true),
          )
        else ...[
          AccountingOrdinaryFields(
            key: const ValueKey('reconciliation-date-fields'),
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Statement Start',
                hasGuidance: true,
                date: true,
                contentSample: '00-00-0000',
                builder: (_) => _field(
                  'Statement Start',
                  'reconciliation-start',
                  _start,
                  date: true,
                  ordinary: true,
                  guidance: _accountMode
                      ? 'Use the first day of this period. Continue from the preceding approved reconciliation. Changing dates clears selections for review.'
                      : 'Use the first day covered by this statement. The period must continue from the preceding approved reconciliation.',
                ),
              ),
              AccountingOrdinaryFieldSlot(
                label: 'Statement End',
                hasGuidance: true,
                date: true,
                contentSample: '00-00-0000',
                builder: (_) => _field(
                  'Statement End',
                  'reconciliation-end',
                  _end,
                  date: true,
                  ordinary: true,
                  guidance: _accountMode
                      ? 'Use the statement ending date. Review recorded account transactions through this date. Changing dates clears selections for review.'
                      : 'Use the statement ending date. Imported rows and accepted matches must fall within the reviewed period.',
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
        ],
        AccountingOrdinaryFields(
          key: const ValueKey('reconciliation-balance-fields'),
          fields: [
            AccountingOrdinaryFieldSlot(
              label:
                  'Opening Balance (${CurrencyPresentation.fromCode(widget.currency).amountSymbol})',
              contentSample: _opening.text.isEmpty
                  ? '100000.00'
                  : _opening.text,
              builder: (_) => _field(
                'Opening Balance (${CurrencyPresentation.fromCode(widget.currency).amountSymbol})',
                'reconciliation-opening',
                _opening,
                ordinary: true,
              ),
            ),
            AccountingOrdinaryFieldSlot(
              label:
                  'Closing Balance (${CurrencyPresentation.fromCode(widget.currency).amountSymbol})',
              contentSample: _closing.text.isEmpty
                  ? '100000.00'
                  : _closing.text,
              builder: (_) => _field(
                'Closing Balance (${CurrencyPresentation.fromCode(widget.currency).amountSymbol})',
                'reconciliation-closing',
                _closing,
                ordinary: true,
              ),
            ),
          ],
        ),
        if (_approved || _hasReview)
          const SizedBox(height: accountingContentInset),
        if (_hasReview && _previousId == null && !_approved)
          _field(
            'Opening Evidence',
            'reconciliation-evidence',
            _evidence,
            evidence: true,
          ),
        if (_approved)
          Text(
            'Reconciliation Approved',
            style: AccountingTypography.fieldLabel(context),
          ),
        if (_hasReview) ...[
          AccountingInformationRows(
            key: const ValueKey('reconciliation-balance-check'),
            rows: [
              (
                'Balance Check Target',
                formatAccountingMoney(context, Money.zero(widget.currency)),
              ),
              if (_accountMode) ...[
                (
                  'Cleared Balance',
                  formatAccountingMoney(
                    context,
                    _accountSnapshot!.review.clearedBalance,
                  ),
                ),
                (
                  'Closing Difference',
                  formatAccountingMoney(
                    context,
                    _accountSnapshot!.review.closingDifference,
                  ),
                ),
                (
                  'Selected Transactions',
                  '${_accountSnapshot!.review.selected.length}',
                ),
              ] else ...[
                (
                  'Statement Difference',
                  formatAccountingMoney(context, review!.statementDifference),
                ),
                (
                  'Match Difference',
                  formatAccountingMoney(context, review.matchDifference),
                ),
                ('Unmatched Rows', '${review.unmatchedRows.length}'),
              ],
            ],
          ),
          const SizedBox(height: accountingContentInset),
          if (!_previousUnchanged) ...[
            Text(
              'The previous reconciliation ledger changed or lacks a snapshot. Reopen and review it before continuing.',
              style: AccountingTypography.helper(context),
            ),
            const SizedBox(height: accountingContentInset),
          ],
          if (_previousId == null && _openingMovements.isNotEmpty) ...[
            _movementSelection(
              title: 'Opening Outstanding Items',
              guidance: 'Select recorded movements that had not cleared at the statement start.',
              cardKey: 'reconciliation-opening-outstanding-card',
              keyPrefix: 'opening-outstanding',
              paginationKey: 'reconciliation-opening-items',
              rows: _openingMovements,
              selectedIds: _outstanding,
              offset: _openingOffset,
              pageSize: _openingPageSize,
              onPageSizeChanged: (value) {
                _openingPageSize = value;
                _openingOffset = 0;
              },
              onOffsetChanged: (value) => _openingOffset = value,
            ),
            const SizedBox(height: accountingContentInset),
          ],
          if (_accountSnapshot case final account?) ...[
            _movementSelection(
              title: 'Account Transactions',
              guidance: 'Select the recorded transactions cleared during this statement period. Unselected transactions remain outstanding.',
              cardKey: 'reconciliation-account-transactions',
              keyPrefix: 'account-cleared',
              paginationKey: 'reconciliation-account-items',
              rows: _eligibleAccountMovements(account),
              selectedIds: _selected,
              offset: _accountOffset,
              pageSize: _accountPageSize,
              onPageSizeChanged: (value) {
                _accountPageSize = value;
                _accountOffset = 0;
              },
              onOffsetChanged: (value) => _accountOffset = value,
            ),
            if (!_approved) ...[
              const SizedBox(height: accountingContentInset),
              Align(
                alignment: Alignment.centerRight,
                child: _addTransactionMenu(),
              ),
            ],
            const SizedBox(height: accountingContentInset),
          ],
          AccountingInformationRows(
            key: const ValueKey('reconciliation-opening-position'),
            rows: [
              (
                'Recorded Opening',
                formatAccountingMoney(context, _recordedOpening),
              ),
              (
                'Opening Difference',
                formatAccountingMoney(context, _openingDifference),
              ),
              if (!_periodContinues)
                (
                  'Required Statement Start',
                  formatAccountingInputDate(_requiredStart!),
                ),
              if (_accountSnapshot != null &&
                  _accountSnapshot!.review.unresolved.isNotEmpty)
                (
                  'Unresolved Selections',
                  _accountSnapshot!.review.unresolved.join(', '),
                ),
              if (review != null && review.invalidMatchRows.isNotEmpty)
                ('Invalid Matches', review.invalidMatchRows.join(', ')),
              if (review != null && review.outsidePeriodRows.isNotEmpty)
                ('Rows Outside Period', review.outsidePeriodRows.join(', ')),
            ],
          ),
          if (!_openingDifference.isZero) ...[
            const SizedBox(height: accountingContentInset),
            Text(
              'Review recorded opening entries and outstanding items. Approval requires a supported opening position.',
              style: AccountingTypography.helper(context),
            ),
          ],
          const SizedBox(height: accountingContentInset),
          Text(
            _ready
                ? 'Rows and balances agree. Approval records your verification of the statement and opening position.'
                : 'Resolve the differences and row issues before completing reconciliation.',
            style: AccountingTypography.helper(context),
          ),
        ],
        if (!_approved || _attachments.isNotEmpty) ...[
          const SizedBox(height: accountingContentInset),
          _supportingFiles(context),
        ],
      ],
    );
    final actions = <Widget>[
      if (!_approved)
        AccountingButton.outline(
          context,
          key: const ValueKey('review-reconciliation'),
          onPressed: _transactionBusy ? null : _calculate,
          child: const Text('Review'),
        ),
      if (!_approved)
        AccountingButton.outline(
          context,
          key: const ValueKey('save-reconciliation-draft'),
          onPressed: _filesBusy || _transactionBusy ? null : _saveDraft,
          child: const Text('Save Draft'),
        ),
      if (!_approved)
        AccountingButton.primary(
          context,
          key: const ValueKey('approve-reconciliation'),
          onPressed: !_filesBusy && !_transactionBusy && _ready
              ? _approve
              : null,
          child: const Text('Approve Reconciliation'),
        ),
    ];
    if (widget.embedded) {
      return _guardInput(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.compactEmbedded)
              Padding(
                padding: const EdgeInsets.only(left: accountingContentInset),
                child: AccountingPageHeader(
                  routeLabel: 'Banking',
                  title: _accountMode
                      ? 'Account Reconciliation'
                      : 'Statement Reconciliation',
                  description:
                      '${widget.sourceLabel ?? statement?.filename ?? 'Statement'} · Check the period, balances and linked transactions before approval.',
                  action: AccountingButton.primary(
                    context,
                    key: const ValueKey('back-to-banking'),
                    onPressed: widget.onBack == null ? null : _handleClose,
                    child: const Text('Back to Banking'),
                  ),
                ),
              ),
            if (!widget.compactEmbedded)
              const SizedBox(height: accountingPageTitleOuterGap),
            if (!widget.compactEmbedded && widget.contextSection != null)
              widget.contextSection!,
            AccountingCard.surface(
              context,
              key: const ValueKey('reconciliation-header-card'),
              child: AccountingRecordRow(
                title: widget.compactEmbedded
                    ? 'Reconciliation'
                    : 'Statement Details',
                titleStyle: AccountingTypography.sectionTitle(context),
                details: Text(
                  widget.sourceLabel ??
                      statement?.filename ??
                      'Imported statement',
                ),
                trailing: AccountingRecordActions(
                  trailing: [
                    ...widget.formActions,
                    if (widget.onBack != null)
                      AccountingButton.iconOnly(
                        context,
                        key: const ValueKey('back-to-matches'),
                        compact: true,
                        onPressed: _handleClose,
                        icon: Icons.undo,
                        tooltip: 'Back',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            AccountingCard.surface(
              context,
              key: const ValueKey('reconciliation-form-card'),
              child: Padding(
                padding: accountingContentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: accountingContentInset),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              AccountingAlert.build(
                context,
                key: ValueKey('reconciliation-warning-$_warningRevision'),
                title: 'Check Statement Details',
                description: _error!,
                tone: AccountingAlertTone.warning,
                topGap: accountingContentInset,
              ),
          ],
        ),
      );
    }
    return _guardInput(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _handleClose();
        },
        child: AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.wider,
          onClose: _handleClose,
          closeKey: const ValueKey('reconciliation-editor-close'),
          canClose: !_filesBusy && !_transactionBusy,
          title: _accountMode
              ? 'Account Reconciliation'
              : 'Statement Reconciliation',
          maxContentWidth: AccountingPopoutTokens.widerContentWidth,
          fixedContentWidth: AccountingPopoutTokens.widerContentWidth,
          formFooter: true,
          description: _accountMode
              ? '${widget.sourceLabel} · Check the period, balances and selected account transactions before approval.'
              : 'Check the statement period, balances and linked transactions before approval.',
          content: SizedBox(
            width: AccountingPopoutTokens.widerContentWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  body,
                  if (_error != null)
                    AccountingAlert.build(
                      context,
                      key: ValueKey('reconciliation-warning-$_warningRevision'),
                      title: 'Check Statement Details',
                      description: _error!,
                      tone: AccountingAlertTone.warning,
                      topGap: accountingContentInset,
                    ),
                ],
              ),
            ),
          ),
          actions: actions,
        ),
      ),
    );
  }
}
