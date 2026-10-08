import 'dart:math' as math;
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';

import '../../../../core/documents/receipt_document.dart';
import 'attachment_preview_dialog.dart';
import 'receipt_attachment_picker.dart';

import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/app/field_guidance.dart';

import '../domain/expense_intake.dart';
import '../domain/expense_revision.dart';
import '../../purchases/presentation/claim_receipt_approval_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/ids/entity_id.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../application/account_repository.dart';
import '../application/accounting_workspace.dart';
import '../application/journal_entry_repository.dart';
import '../domain/account.dart';
import '../domain/journal_entry.dart';
import '../data/accounting_database.dart';
import 'widgets/accounting_layout.dart';
import 'widgets/accounting_formatters.dart';
import 'chart_of_accounts_page.dart' show showLedgerAccountDialog;

Future<void> showPostedJournal(
  BuildContext context,
  AccountingWorkspace workspace,
  EntityId journalId,
) async {
  final record = await workspace.database.getById(journalId);
  if (record == null ||
      record.metadata.businessId != workspace.identity.businessId ||
      record.metadata.isTombstone ||
      record.entry.state != JournalEntryState.posted) {
    throw StateError('The posted journal is unavailable in this business.');
  }
  final accounts = await workspace.accounts();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _JournalReviewDialog(
      workspace: workspace,
      record: record,
      accounts: accounts,
    ),
  );
}

Future<void> showExpenseJournalReview(
  BuildContext context,
  AccountingWorkspace workspace,
  ExpenseIntakeRecord expense,
) async {
  final claimSource = expense.draft.claimSource;
  if (claimSource != null && !expense.summary.hasPendingRevision) {
    await showPostedJournal(context, workspace, expense.summary.journalId!);
    return;
  }
  final accounts = await workspace.accounts();
  final journals = await workspace.journals();
  final candidates = journals.where((record) {
    final entry = record.entry;
    return entry.state == JournalEntryState.draft &&
        !record.metadata.isTombstone &&
        !entry.isClosing &&
        entry.reversesId == null &&
        formatAccountingInputDate(entry.date) ==
            formatAccountingInputDate(expense.summary.occurredOn) &&
        entry.lines.isNotEmpty &&
        entry.lines.every(
          (line) => line.amount.currency == expense.summary.amount.currency,
        ) &&
        entry.lines
                .where((line) => line.isDebit)
                .fold<BigInt>(
                  BigInt.zero,
                  (sum, line) => sum + BigInt.from(line.amount.minorUnits),
                ) ==
            BigInt.from(expense.summary.amount.minorUnits);
  }).toList();
  if (!context.mounted) return;
  final selected = await showDialog<StoredJournalEntry>(
    context: context,
    builder: (dialogContext) => AccountingDialog.alert(
      dialogContext,
      widthFamily: AccountingPopoutWidthFamily.custom,
      title: 'Expense Posting',
      formFooter: true,
      titleGuidance: 'Select the journal prepared for this expense, then review its accounts and tax treatment before approval.',
      content: SizedBox(
        width: AccountingPopoutTokens.widerContentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${expense.draft.payee} · ${formatAccountingMoney(dialogContext, expense.summary.amount)}',
            ),
            const SizedBox(height: 12),
            if (candidates.isEmpty)
              const Text(
                'No matching draft journal. Prepare a journal in Accounting with this expense date, currency and total.',
              ),
            for (final record in candidates)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AccountingButton.outline(
                  dialogContext,
                  key: ValueKey('expense-journal-${record.entry.id.value}'),
                  onPressed: () => Navigator.of(dialogContext).pop(record),
                  child: Text(record.entry.memo),
                ),
              ),
          ],
        ),
      ),
      actions: [
        AccountingButton.ghost(
          dialogContext,
          key: null,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  ClaimExpenseApprovalSelection? claimReview;
  if (claimSource != null) {
    final claim = workspace.claims.byId(claimSource.claimId);
    if (claim == null) {
      throw StateError('The original Claim is unavailable in this company.');
    }
    claimReview = await showDialog<ClaimExpenseApprovalSelection>(
      context: context,
      builder: (_) => ClaimReceiptApprovalDialog(
        claim: claim,
        accounts: accounts.map((stored) => stored.account).toList(),
        currentExpense: expense.draft,
      ),
    );
    if (claimReview == null || !context.mounted) return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _JournalReviewDialog(
      workspace: workspace,
      record: selected,
      accounts: accounts,
      expense: expense,
      claimReview: claimReview,
    ),
  );
}

Future<EntityId?> showJournalEditor(
  BuildContext context,
  AccountingWorkspace workspace,
  List<StoredAccount> accounts, {
  DateTime? initialDate,
  EntityId? initialAccountId,
  bool showSavedNotice = true,
  StoredJournalEntry? existing,
  ExpenseAttachmentsPicker? onAttachmentsPick,
}) async {
  EntityId? manualRoot;
  StoredJournalEntry? expectedSource;
  var expectedManualRevision = 0;
  var editorRecord = existing;
  if (existing != null) {
    final business = workspace.identity.businessId;
    if (workspace.database.isManualJournalDraft(business, existing.entry.id)) {
      workspace.database.requireJournalUnreconciled(
        business,
        existing.entry.id,
      );
    } else {
      manualRoot = workspace.database.manualJournalCurrentRootForEntry(
        business,
        existing.entry.id,
      );
      if (manualRoot == null) {
        throw StateError(
          'Use the current transaction owner to revise this Journal.',
        );
      }
      expectedSource = await workspace.database.getById(
        workspace.database.manualJournalCurrentPostingId(business, manualRoot),
      );
      if (expectedSource == null) {
        throw StateError('The current Journal is unavailable.');
      }
      workspace.database.requireJournalUnreconciled(
        business,
        expectedSource.entry.id,
      );
      final revision = workspace.database.manualJournalCurrentRevision(
        business,
        manualRoot,
      );
      expectedManualRevision = revision?.revision ?? 0;
      editorRecord = revision?.draft ?? expectedSource;
    }
    if (editorRecord!.entry.lines.any(
      (line) => line.amount.currency != workspace.identity.currency,
    )) {
      throw StateError(
        'Retain the saved currency; foreign amounts require reviewed conversion.',
      );
    }
  }
  if (!context.mounted) return null;
  final saved = await showDialog<EntityId>(
    context: context,
    builder: (context) => _JournalEditor(
      workspace: workspace,
      existing: editorRecord,
      manualRootId: manualRoot,
      expectedSource: expectedSource,
      expectedManualRevision: expectedManualRevision,
      initialDate: initialDate,
      initialAccountId: initialAccountId,
      accounts: accounts
          .where(
            (r) =>
                !r.account.isParent &&
                (r.account.status == AccountStatus.active ||
                    (editorRecord?.entry.lines.any(
                          (line) => line.accountId == r.account.id,
                        ) ??
                        false)),
          )
          .toList(),
      onAttachmentsPick: onAttachmentsPick,
    ),
  );
  if (saved != null && showSavedNotice && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Journal saved for review')));
  }
  return saved;
}

/// Reuses the actual journal approval owner for a known draft, not a
/// synthetic transaction or an inferred "latest" journal.
Future<void> showDraftJournalReview(
  BuildContext context,
  AccountingWorkspace workspace,
  EntityId journalId,
) async {
  final record = await workspace.database.getById(journalId);
  if (record == null ||
      record.metadata.businessId != workspace.identity.businessId ||
      record.metadata.isTombstone ||
      record.entry.state != JournalEntryState.draft) {
    throw StateError('The journal draft is unavailable in this business.');
  }
  final accounts = await workspace.accounts();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _JournalReviewDialog(
      workspace: workspace,
      record: record,
      accounts: accounts,
    ),
  );
}

class _JournalLineInput {
  EntityId? account;
  final debit = TextEditingController();
  final credit = TextEditingController();
  final description = TextEditingController();
  void dispose() {
    debit.dispose();
    credit.dispose();
    description.dispose();
  }
}

class _JournalEditor extends StatefulWidget {
  const _JournalEditor({
    required this.workspace,
    required this.accounts,
    this.initialDate,
    this.initialAccountId,
    this.existing,
    this.manualRootId,
    this.expectedSource,
    this.expectedManualRevision = 0,
    this.onAttachmentsPick,
  });
  final DateTime? initialDate;
  final EntityId? initialAccountId;
  final StoredJournalEntry? existing;
  final EntityId? manualRootId;
  final StoredJournalEntry? expectedSource;
  final int expectedManualRevision;
  final AccountingWorkspace workspace;
  final List<StoredAccount> accounts;
  final ExpenseAttachmentsPicker? onAttachmentsPick;
  @override
  State<_JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends State<_JournalEditor> {
  final _editingFocus = FocusScopeNode();
  final _date = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  final _memo = TextEditingController();
  final _number = TextEditingController();
  final _attachments = <ReceiptAttachment>[];
  final _lines = [_JournalLineInput(), _JournalLineInput()];
  late List<StoredAccount> _accounts;
  bool _busy = false;
  bool _closePromptOpen = false;
  late final String _openingInput;
  String? _error;
  EntityId? _revisionRequest;
  DateTime? _revisionSavedAt;
  String? _revisionInput;
  bool _attachmentBusy = false, _dragOver = false;
  double _contentWidth = 720;
  double? _requestedWidth;
  bool _ownsWidth = false;
  late final _widthOwner = 'journal-${identityHashCode(this)}';

  static const _numberGuidance =
      'Journal number saving and duplicate-number checking are not connected yet. Leave this blank to save the current draft.';
  static const _descriptionGuidance =
      'Per-line Description saving is not connected yet. Leave these blank to save the current draft; Memo remains available.';
  static const _nameGuidance =
      'Journal Name selection is unavailable until the maintained contact choices and line allocation are verified and connected.';
  static const _taxGuidance =
      'Journal tax selection is unavailable until the tax-code direction and posting calculation are verified and connected.';
  static const _attachmentGuidance =
      'Journal attachment saving is not connected yet. Files remain in this editing session; remove them to save the current draft.';
  @override
  void initState() {
    super.initState();
    _accounts = List.of(widget.accounts);
    final existing = widget.existing;
    if (existing != null) {
      _date.text = formatAccountingInputDate(existing.entry.date);
      _memo.text = existing.entry.memo;
      for (final line in _lines) {
        line.dispose();
      }
      _lines.clear();
      for (final line in existing.entry.lines) {
        final input = _JournalLineInput()..account = line.accountId;
        (line.isDebit ? input.debit : input.credit).text =
            formatAccountingMoneyInputText(
              line.amount.toDecimalString(),
              Currency.parse(line.amount.currency).fractionDigits,
            );
        _lines.add(input);
      }
    }
    if (widget.initialDate != null) {
      _date.text = formatAccountingInputDate(widget.initialDate!);
    }
    if (widget.accounts.any((r) => r.account.id == widget.initialAccountId)) {
      _lines.first.account = widget.initialAccountId;
    }
    _openingInput = _inputSnapshot();
  }

  Future<void> _addAccount(_JournalLineInput line) async {
    if (_busy) return;
    try {
      final accounts = await widget.workspace.accounts();
      if (!mounted) return;
      final savedId = await showLedgerAccountDialog(
        context,
        widget.workspace,
        accounts,
      );
      if (savedId == null || !mounted) return;
      final current = await widget.workspace.accounts();
      if (!mounted) return;
      setState(() {
        _accounts = current
            .where(
              (record) =>
                  !record.account.isParent &&
                  (record.account.status == AccountStatus.active ||
                      _lines.any(
                        (input) => input.account == record.account.id,
                      )),
            )
            .toList();
        if (_accounts.any((record) => record.account.id == savedId)) {
          if (_lines.contains(line)) line.account = savedId;
          _error = null;
        } else {
          final saved = current.where((record) => record.account.id == savedId);
          _error = saved.isNotEmpty && saved.single.account.isParent
              ? 'Group accounts cannot be used in journal lines. Choose a posting account.'
              : 'The saved account is locked or unavailable. Choose an active posting account.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Accounts could not be loaded. Your journal inputs have been retained.',
        );
      }
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _memo.dispose();
    _number.dispose();
    _editingFocus.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    if (_ownsWidth) AccountingDialog.releaseFixedWidth(_widthOwner);
    super.dispose();
  }

  String _inputSnapshot() => jsonEncode([
    _date.text,
    _memo.text,
    _number.text,
    [
      for (final line in _lines)
        [
          line.account?.value,
          line.debit.text,
          line.credit.text,
          line.description.text,
        ],
    ],
    [
      for (final file in _attachments) [file.originalId, file.originalSha256],
    ],
  ]);

  void _clearResolvedStagedError() {
    final resolved =
        (_error == _numberGuidance && _number.text.trim().isEmpty) ||
        (_error == _descriptionGuidance &&
            _lines.every((line) => line.description.text.trim().isEmpty)) ||
        (_error == _attachmentGuidance && _attachments.isEmpty);
    if (resolved) setState(() => _error = null);
  }

  Future<void> _handleClose() async {
    if (_busy || _attachmentBusy || _closePromptOpen) return;
    if (_inputSnapshot() == _openingInput) {
      Navigator.of(context).pop();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('journal-discard-close'),
        keepEditingKey: const ValueKey('journal-keep-editing'),
        discardKey: const ValueKey('journal-discard-changes'),
      );
      if (mounted) {
        if (discard) {
          Navigator.of(context).pop();
        } else {
          _editingFocus.requestFocus();
        }
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Physical design is staged on this same owner. Never let the current
      // command discard facts it does not yet persist.
      if (_number.text.trim().isNotEmpty) {
        throw const FormatException(_numberGuidance);
      }
      if (_lines.any((line) => line.description.text.trim().isNotEmpty)) {
        throw const FormatException(_descriptionGuidance);
      }
      if (_attachments.isNotEmpty) {
        throw const FormatException(_attachmentGuidance);
      }
      final date = parseAccountingInputDate(_date.text);
      if (date == null) {
        throw const FormatException('Enter a valid DD-MM-YYYY date.');
      }
      final lines = <JournalLine>[];
      for (final line in _lines) {
        if (line.account == null ||
            (line.debit.text.trim().isEmpty ==
                line.credit.text.trim().isEmpty)) {
          throw const FormatException(
            'Choose an account and enter either a debit or a credit on every line.',
          );
        }
        final debit = line.debit.text.trim().isNotEmpty;
        final amount = Money.fromDecimal(
          debit ? line.debit.text : line.credit.text,
          widget.workspace.identity.currency,
        );
        lines.add(
          debit
              ? JournalLine.debit(accountId: line.account!, amount: amount)
              : JournalLine.credit(accountId: line.account!, amount: amount),
        );
      }
      final EntityId savedId;
      final existing = widget.existing;
      if (existing == null) {
        savedId = await widget.workspace.saveJournal(
          date: date,
          memo: _memo.text,
          lines: lines,
        );
      } else {
        final input =
            '${_date.text}\u0000${_memo.text}\u0000${_lines.map((line) => '${line.account?.value}/${line.debit.text}/${line.credit.text}').join('\u0000')}';
        if (_revisionInput != input) {
          _revisionInput = input;
          _revisionRequest = AccountingWorkspace.newId();
          final now = DateTime.now().toUtc();
          _revisionSavedAt = now.isAfter(existing.metadata.updatedAt)
              ? now
              : existing.metadata.updatedAt.add(
                  const Duration(microseconds: 1),
                );
        }
        if (widget.manualRootId != null) {
          final sourceAt = widget.expectedSource!.metadata.updatedAt;
          if (!_revisionSavedAt!.isAfter(sourceAt)) {
            _revisionSavedAt = sourceAt.add(const Duration(microseconds: 1));
          }
          savedId = widget.workspace
              .saveManualJournalRevision(
                rootId: widget.manualRootId!,
                expectedSource: widget.expectedSource!,
                expectedCurrentRevision: widget.expectedManualRevision,
                date: date,
                memo: _memo.text,
                lines: lines,
                requestId: _revisionRequest!,
                savedAt: _revisionSavedAt!,
              )
              .draft
              .entry
              .id;
        } else {
          savedId = widget.workspace
              .reviseJournalDraft(
                expected: existing,
                date: date,
                memo: _memo.text,
                lines: lines,
                requestId: _revisionRequest!,
                savedAt: _revisionSavedAt!,
              )
              .entry
              .id;
        }
      }
      if (mounted) {
        Navigator.of(context).pop(savedId);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is JournalValidationException
              ? error.errors.join(' ')
              : error is FormatException
              ? error.message
              : error is StateError
              ? error.message
              : 'The journal could not be saved. Retry after checking storage.';
        });
      }
    }
  }

  Widget _field(String label, Widget child, {String? guidance}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(
        context,
        label,
        alignToField: true,
        guidance: guidance,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      SizedBox(
        height: accountingControlHeight,
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final widths = _lineWidths(context);
    _contentWidth = math.max(
      _contentWidth,
      math.max(
        720 +
            widths['Name']! +
            widths['Tax']! +
            2 * AccountingTransactionGridTokens.peerGap,
        widths.values.fold(0.0, (sum, width) => sum + width) +
            AccountingTransactionGridTokens.descriptionMinimumWidth +
            5 * AccountingTransactionGridTokens.peerGap,
      ),
    );
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
      onKeyEvent: (node, event) {
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
          title: widget.existing == null ? 'New Journal' : 'Edit Journal',
          onClose: _handleClose,
          closeKey: const ValueKey('journal-editor-close'),
          canClose: !_busy && !_attachmentBusy,
          formFooter: true,
          fixedContentWidth: _contentWidth,
          titleGuidance:
              'Save a balanced ${CurrencyPresentation.fromCode(widget.workspace.identity.currency).amountSymbol} draft, then approve the exact entries in Accounting Review.',
          content: SingleChildScrollView(
            key: const ValueKey('journal-editor-horizontal-scroll'),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountingOrdinaryFields(
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Date',
                        date: true,
                        hasGuidance: true,
                        contentSample: '00-00-0000',
                        builder: (_) => _field(
                          'Date',
                          accountingDateFieldFrame(
                            child: TextField(
                              key: const ValueKey('journal-date'),
                              controller: _date,
                              enableInteractiveSelection: true,
                              enabled: !_busy,
                              inputFormatters: [const DateInputFormatter()],
                              decoration:
                                  accountingSingleLineInputDecoration(
                                    context,
                                    hintText: 'DD-MM-YYYY',
                                  ).copyWith(
                                    suffixIcon: accountingCalendarButton(
                                      context,
                                      controller: _date,
                                      label: 'Date',
                                      enabled: !_busy,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                      AccountingOrdinaryFieldSlot(
                        label: 'Journal Number',
                        hasGuidance: true,
                        contentSample: 'Journal Number',
                        builder: (_) => _field(
                          'Journal Number',
                          TextField(
                            key: const ValueKey('journal-number'),
                            controller: _number,
                            onChanged: (_) => _clearResolvedStagedError(),
                            enabled: !_busy,
                            style: AccountingTypography.controlValue(context),
                            decoration: accountingSingleLineInputDecoration(
                              context,
                            ),
                          ),
                          guidance: _numberGuidance,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _lineGrid(context),
                  const SizedBox(height: accountingContentInset),
                  _memoAndTotals(context),
                  const SizedBox(height: accountingContentInset),
                  _attachmentField(context),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: AccountingTypography.helper(context).copyWith(
                        color: AccountingTheme.of(context).destructive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            AccountingButton.primary(
              context,
              key: const ValueKey('save-journal-draft'),
              onPressed: _busy || _attachmentBusy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save Draft'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseAttachments() async {
    if (_busy || _attachmentBusy) return;
    setState(() => _attachmentBusy = true);
    try {
      final files =
          await (widget.onAttachmentsPick ??
              const NativeExpenseAttachmentPicker().pick)(context);
      _appendAttachments(files);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The file chooser could not be opened. Your journal inputs have been retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  void _appendAttachments(List<PickedExpenseAttachment> files) {
    if (!mounted || files.isEmpty) return;
    final staged = <ReceiptAttachment>[];
    for (final file in files) {
      if (!NativeExpenseAttachmentPicker.supportedExtensions.contains(
        file.name.split('.').last.toLowerCase(),
      )) {
        setState(() => _error = 'Choose a supported image or document file.');
        continue;
      }
      staged.add(
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: AccountingWorkspace.newId().value,
            batchId: _widthOwner,
            filename: file.name,
            mimeType: file.mimeType,
            bytes: file.bytes,
          ),
        ),
      );
    }
    setState(() => _attachments.addAll(staged));
  }

  Future<void> _dropAttachments(DropDoneDetails details) async {
    if (_busy || _attachmentBusy) return;
    setState(() {
      _dragOver = false;
      _attachmentBusy = true;
    });
    final files = <PickedExpenseAttachment>[];
    try {
      for (final file in details.files) {
        if (file is DropItemDirectory) continue;
        final bookmark = file.extraAppleBookmark;
        var accessed = false;
        try {
          if (bookmark != null && bookmark.isNotEmpty) {
            accessed = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
          }
          files.add(
            PickedExpenseAttachment(
              name: file.name,
              mimeType: NativeExpenseAttachmentPicker.mimeTypeForFilename(
                file.name,
              ),
              bytes: await file.readAsBytes(),
              path: file.path,
            ),
          );
        } catch (_) {
          if (mounted) {
            setState(
              () => _error =
                  'Could not read ${file.name}. Your journal inputs have been retained.',
            );
          }
        } finally {
          if (accessed) {
            await DesktopDrop.instance.stopAccessingSecurityScopedResource(
              bookmark: bookmark!,
            );
          }
        }
      }
      _appendAttachments(files);
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Widget _attachmentField(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      accountingFieldLabel(
        context,
        'Attachments',
        guidance: _attachmentGuidance,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      DropTarget(
        enable: !_busy && !_attachmentBusy,
        onDragEntered: (_) => setState(() => _dragOver = true),
        onDragExited: (_) => setState(() => _dragOver = false),
        onDragDone: _dropAttachments,
        child: InkWell(
          onTap: _busy || _attachmentBusy ? null : _chooseAttachments,
          borderRadius: BorderRadius.circular(accountingControlRadius),
          child: AccountingAttachmentDropzone(
            key: const ValueKey('journal-attachment-dropzone'),
            actionKey: const ValueKey('journal-choose-files'),
            onChoose: _busy || _attachmentBusy ? null : _chooseAttachments,
            dragOver: _dragOver,
            prompt: 'Drop documents here or choose files',
            formats:
                'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
          ),
        ),
      ),
      if (_attachments.isNotEmpty) ...[
        const SizedBox(height: 12),
        AccountingAttachmentList(
          paginationKey: 'journal-attachments',
          children: [
            for (final file in _attachments)
              AccountingAttachmentRecordRow(
                key: ValueKey('journal-attachment-${file.originalId}'),
                attachment: file,
                showProcessingStatus: false,
                actions: [
                  AccountingButton.iconOnly(
                    context,
                    key: ValueKey('journal-attachment-view-${file.originalId}'),
                    onPressed: () => showAttachmentPreview(context, file),
                    icon: Icons.visibility_outlined,
                    tooltip: 'View Attachment',
                  ),
                  AccountingButton.iconOnly(
                    context,
                    key: ValueKey(
                      'journal-attachment-remove-${file.originalId}',
                    ),
                    onPressed: _busy || _attachmentBusy
                        ? null
                        : () async {
                            if (!await confirmAttachmentDeletion(context) ||
                                !mounted) {
                              return;
                            }
                            setState(
                              () => _attachments.removeWhere(
                                (item) => item.originalId == file.originalId,
                              ),
                            );
                            _clearResolvedStagedError();
                          },
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

  Widget _memoAndTotals(BuildContext context) {
    final code = widget.workspace.identity.currency;
    final symbol = CurrencyPresentation.fromCode(code).amountSymbol;
    String total(bool debit) {
      try {
        var sum = Money.zero(code);
        for (final line in _lines) {
          final text = (debit ? line.debit : line.credit).text.trim();
          if (text.isNotEmpty) sum += Money.fromDecimal(text, code);
        }
        return formatAccountingMoneyInputText(
          sum.toDecimalString(),
          Currency.parse(code).fractionDigits,
        );
      } on FormatException {
        return '—';
      } on RangeError {
        return '—';
      }
    }

    final rows = [
      ('Total Debit ($symbol)', total(true)),
      ('Total Credit ($symbol)', total(false)),
    ];
    Widget memo() => AccountingDescriptionField(
      key: const ValueKey('journal-memo'),
      role: AccountingDescriptionRole.memo,
      controller: _memo,
      onEscape: _handleClose,
      enabled: !_busy,
      decoration: accountingSingleLineInputDecoration(
        context,
        hintText: 'Explain The Transaction',
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Retain the custom Memo/summary owner at the supported desktop widths.
        // The older narrow-window journey stacks these same owners before they
        // would receive a negative width; ordinary planning never sees them.
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountingFieldLabel(context, 'Memo', alignToField: true),
              const SizedBox(height: accountingFieldLabelGap),
              memo(),
              const SizedBox(height: accountingContentInset),
              AccountingMemoSummary(rows: rows),
            ],
          );
        }
        return AccountingMemoSummary(rows: rows, memo: (_) => memo());
      },
    );
  }

  Map<String, double> _lineWidths(BuildContext context) {
    final symbol = CurrencyPresentation.fromCode(
      widget.workspace.identity.currency,
    ).amountSymbol;
    final zero = formatAccountingInputAmount(
      Money.zero(widget.workspace.identity.currency),
    );
    double numericWidth(String label, Iterable<String> values) =>
        AccountingTransactionGridTokens.numericWidth(
          context,
          'Amount',
          values.map((value) => value.isEmpty ? zero : value),
          title: '$label ($symbol)',
          guidance: accountingFieldGuidance(label),
        );
    final debitWidth = numericWidth('Debit', _lines.map((l) => l.debit.text));
    final creditWidth = numericWidth(
      'Credit',
      _lines.map((l) => l.credit.text),
    );
    final accountMinimum = AccountingTransactionGridTokens.selectionWidth(
      context,
      'Select Account',
      title: 'Account',
    );
    final number = TextPainter(
      text: TextSpan(
        text: '${_lines.length}',
        style: AccountingTypography.controlValue(context),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final boundaryWidth =
        number.width +
        AccountingTransactionGridTokens.numberGap(context, _lines.length) +
        accountingContentInset +
        20;
    number.dispose();
    return {
      'Account': accountMinimum,
      'Debit': debitWidth,
      'Credit': creditWidth,
      'Name': AccountingTransactionGridTokens.selectionWidth(
        context,
        'Select Name',
        title: 'Name',
      ),
      'Tax': AccountingTransactionGridTokens.selectionWidth(
        context,
        'Select Tax',
        title: 'Tax',
      ),
      'Boundary': boundaryWidth,
    };
  }

  Widget _lineGrid(BuildContext context) {
    final widths = _lineWidths(context);
    final symbol = CurrencyPresentation.fromCode(
      widget.workspace.identity.currency,
    ).amountSymbol;
    final fractionDigits = Currency.parse(widget.workspace.identity.currency)
        .fractionDigits;
    final zero = formatAccountingInputAmount(
      Money.zero(widget.workspace.identity.currency),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = math.max(
          constraints.maxWidth,
          widths.values.fold(0.0, (sum, width) => sum + width) +
              AccountingTransactionGridTokens.descriptionMinimumWidth +
              5 * AccountingTransactionGridTokens.peerGap,
        );
        final descriptionWidth =
            gridWidth -
            widths.values.fold(0.0, (sum, width) => sum + width) -
            5 * AccountingTransactionGridTokens.peerGap;
        Widget numeric(int row, String label) => TextField(
          key: ValueKey('journal-${label.toLowerCase()}-$row'),
          controller: label == 'Debit' ? _lines[row].debit : _lines[row].credit,
          enabled: !_busy,
          textAlign: TextAlign.right,
          style: AccountingTypography.controlValue(context),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AccountingMoneyInputFormatter(fractionDigits)],
          decoration: accountingSingleLineInputDecoration(
            context,
            hintText: zero,
          ),
          onChanged: (_) => setState(() {}),
        );
        return SingleChildScrollView(
          key: const ValueKey('journal-line-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: AccountingTransactionGrid(
              key: const ValueKey('journal-transaction-lines'),
              rowCount: _lines.length,
              rowKey: (row) => ValueKey('journal-line-$row'),
              columns: [
                AccountingTransactionColumn(
                  title: 'Account',
                  width: widths['Account']!,
                  cell: (row, width) => AccountingSelector<EntityId?>(
                    triggerKey: ValueKey('journal-account-$row'),
                    assignedWidth: width,
                    value: _lines[row].account,
                    onChanged: (value) =>
                        setState(() => _lines[row].account = value),
                    enabled: !_busy,
                    searchable: true,
                    hintText: 'Select Account',
                    options: [
                      AccountingSelectorOption<EntityId?>(
                        value: null,
                        key: ValueKey('journal-add-account-$row'),
                        label: 'Add Account',
                        leading: const AccountingIcon(Icons.add),
                        onPressed: () => _addAccount(_lines[row]),
                      ),
                      for (final record in _accounts)
                        AccountingSelectorOption(
                          value: record.account.id,
                          label: record.account.displayName,
                          preserveLabelCase: true,
                        ),
                    ],
                  ),
                ),
                AccountingTransactionColumn(
                  title: 'Debit ($symbol)',
                  headerAlignment: Alignment.centerRight,
                  naturalHeaderWidth: true,
                  guidance: accountingFieldGuidance('Debit'),
                  width: widths['Debit']!,
                  cell: (row, _) => numeric(row, 'Debit'),
                ),
                AccountingTransactionColumn(
                  title: 'Credit ($symbol)',
                  headerAlignment: Alignment.centerRight,
                  naturalHeaderWidth: true,
                  guidance: accountingFieldGuidance('Credit'),
                  width: widths['Credit']!,
                  cell: (row, _) => numeric(row, 'Credit'),
                ),
                AccountingTransactionColumn(
                  title: 'Description',
                  guidance: _descriptionGuidance,
                  width: descriptionWidth,
                  cell: (row, _) => AccountingDescriptionField(
                    key: ValueKey('journal-description-$row'),
                    role: AccountingDescriptionRole.transactionItem,
                    fixedLines: null,
                    controller: _lines[row].description,
                    onChanged: (_) => _clearResolvedStagedError(),
                    onEscape: _handleClose,
                    enabled: !_busy,
                    decoration: accountingSingleLineInputDecoration(context),
                  ),
                ),
                AccountingTransactionColumn(
                  title: 'Name',
                  guidance: _nameGuidance,
                  width: widths['Name']!,
                  cell: (row, width) => Tooltip(
                    message: _nameGuidance,
                    child: AccountingSelector<String?>(
                      triggerKey: ValueKey('journal-name-$row'),
                      assignedWidth: width,
                      value: null,
                      onChanged: (_) {},
                      enabled: false,
                      hintText: 'Select Name',
                      options: const [],
                    ),
                  ),
                ),
                AccountingTransactionColumn(
                  title: 'Tax',
                  guidance: _taxGuidance,
                  width: widths['Tax']!,
                  cell: (row, width) => Tooltip(
                    message: _taxGuidance,
                    child: AccountingSelector<String?>(
                      triggerKey: ValueKey('journal-tax-$row'),
                      assignedWidth: width,
                      value: null,
                      onChanged: (_) {},
                      enabled: false,
                      hintText: 'Select Tax',
                      options: const [],
                    ),
                  ),
                ),
              ],
              action: (row) => row == 0
                  ? accountingCompactAdd(
                      context,
                      key: const ValueKey('add-journal-line'),
                      onPressed: _busy
                          ? null
                          : () =>
                                setState(() => _lines.add(_JournalLineInput())),
                    )
                  : accountingCompactRemove(
                      context,
                      key: ValueKey('remove-journal-line-$row'),
                      tooltip: 'Remove Line ${row + 1}',
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _lines.removeAt(row).dispose());
                              _clearResolvedStagedError();
                            },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class JournalReviewPage extends StatefulWidget {
  const JournalReviewPage({
    super.key,
    required this.workspace,
    this.compact = false,
    this.initialPosted = false,
    this.through,
  });
  final AccountingWorkspace workspace;
  final bool compact;
  final bool initialPosted;
  final DateTime? through;
  @override
  State<JournalReviewPage> createState() => _JournalReviewPageState();
}

class _JournalReviewPageState extends State<JournalReviewPage> {
  StoredJournalPage? _page;
  List<StoredAccount> _accounts = [];
  final _search = TextEditingController();
  late bool _posted = widget.initialPosted;
  late DateTime? _through = widget.through;
  int _offset = 0;
  int _controlCount = 0;
  int _limit = AccountingRecordPageSizes.read('journal');
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant JournalReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _page = null;
      _accounts = [];
      _search.clear();
      _error = null;
      _limit = AccountingRecordPageSizes.read('journal');
    }
    if (oldWidget.workspace != widget.workspace ||
        oldWidget.initialPosted != widget.initialPosted ||
        oldWidget.through != widget.through) {
      _posted = widget.initialPosted;
      _through = widget.through;
      _offset = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.workspace.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final workspace = widget.workspace;
    final posted = _posted;
    final through = _through;
    final search = _search.text;
    final offset = _offset;
    final limit = _limit;
    try {
      final accounts = await workspace.accounts();
      if (!mounted ||
          generation != _generation ||
          workspace != widget.workspace) {
        return;
      }
      final controlCount = workspace.database
          .readJournalPage(businessId: workspace.identity.businessId, limit: 1)
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = workspace.database.readJournalPage(
        businessId: workspace.identity.businessId,
        state: showControls
            ? (posted ? JournalEntryState.posted : JournalEntryState.draft)
            : null,
        through: showControls ? through : null,
        search: showControls ? search : '',
        offset: showControls ? offset : 0,
        limit: limit,
      );
      setState(() {
        _controlCount = controlCount;
        _accounts = accounts;
        _page = page;
        _offset = page.offset;
        _error = null;
      });
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          workspace == widget.workspace) {
        setState(() {
          _page = null;
          _error = 'Accounting entries could not be loaded. Retry without changing your records.';
        });
      }
    }
  }

  void _filter(VoidCallback update) {
    setState(() {
      update();
      _offset = 0;
      _page = null;
    });
    _load();
  }

  String _recordDetails(StoredJournalEntry record) {
    final entry = record.entry;
    final details =
        '${formatAccountingInputDate(entry.date)} · ${entry.lines.length} Lines';
    if (entry.isClosing) {
      return '$details · ${entry.reversesId == null ? 'Closing Entry' : 'Closing Reversal'}';
    }
    final database = widget.workspace.database;
    final businessId = widget.workspace.identity.businessId;
    final correction = database.manualJournalRevisionForDraft(
      businessId,
      entry.id,
    );
    if (correction != null) {
      final role = entry.state == JournalEntryState.draft
          ? 'Journal Correction'
          : 'Replacement Posting';
      return '$details · $role · Revision ${correction.revision}';
    }
    if (database.manualJournalCurrentRevision(businessId, entry.id) != null) {
      return '$details · Original Posting';
    }
    return details;
  }

  @override
  Widget build(BuildContext context) => AccountingPageShell(
    includeTopSafeArea: !widget.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingPageHeader(
          routeLabel: 'Accounting Review',
          title: 'Accounting Review',
          titleKey: 'page-title-accountant-review',
          description: 'Review journal details before posting. Balanced records can still need supporting evidence.',
          action: AccountingButton.primary(
            context,
            key: const ValueKey('prepare-closing'),
            onPressed: _page == null || _error != null
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _ClosingEditor(
                      workspace: widget.workspace,
                      accounts: _accounts,
                    ),
                  ),
            child: const Text('Prepare Closing'),
          ),
        ),
        const SizedBox(height: accountingContentInset),
        AccountingRecordControls(
          recordCount: _controlCount,
          child: Padding(
            padding: const EdgeInsets.only(bottom: accountingContentInset),
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: accountingContentInset,
                runSpacing: AccountingPageControlScope.runGapOf(context),
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: AccountingPageControlScope.runGapOf(context),
                    children: [
                      if (_through != null) ...[
                        Text(
                          'Through ${formatAccountingInputDate(_through!)}',
                          key: const ValueKey('journal-summary-through'),
                          style: AccountingTypography.control(context),
                        ),
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('clear-journal-summary-filter'),
                          onPressed: () => _filter(() => _through = null),
                          child: const Text('Clear'),
                        ),
                      ],
                      AccountingButton.outline(
                        context,
                        key: const ValueKey('review-drafts'),
                        onPressed: () => _filter(() => _posted = false),
                        leadingIcon: _posted
                            ? Icons.edit_note_outlined
                            : Icons.check_rounded,
                        child: const Text('Drafts'),
                      ),
                      AccountingButton.outline(
                        context,
                        key: const ValueKey('review-posted'),
                        onPressed: () => _filter(() => _posted = true),
                        leadingIcon: _posted
                            ? Icons.check_rounded
                            : Icons.inventory_2_outlined,
                        child: const Text('Posted'),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: constraints.maxWidth.clamp(0.0, 280.0),
                    child: TextField(
                      key: const ValueKey('journal-search'),
                      controller: _search,
                      onChanged: (_) => _filter(() {}),
                      decoration: accountingSingleLineInputDecoration(
                        context,
                        hintText: 'Memo Or Journal ID',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          AccountingAlert.build(
            context,
            title: 'Failed',
            description: _error!,
            destructive: true,
          ),
          AccountingButton.outline(
            context,
            key: const ValueKey('retry-journal-page'),
            onPressed: _load,
            leadingIcon: Icons.refresh_outlined,
            child: const Text('Retry'),
          ),
        ] else if (_page == null)
          const LinearProgressIndicator()
        else
          AccountingRecordList(
            totalCount: _controlCount,
            paginationKey: 'journal-workspace-1',
            externalPagination: Padding(
              padding: accountingContentPadding,
              child: AccountingRecordPagination(
                unfilteredTotal: _controlCount,
                total: _page!.total,
                offset: _page!.offset,
                pageSize: _limit,
                keyPrefix: 'journal',
                onPageSizeChanged: (size) => _filter(() => _limit = size),
                onPrevious: _page!.offset == 0
                    ? null
                    : () {
                        _offset = (_page!.offset - _limit).clamp(
                          0,
                          _page!.total,
                        );
                        _load();
                      },
                onNext: _page!.offset + _limit >= _page!.total
                    ? null
                    : () {
                        _offset = _page!.offset + _limit;
                        _load();
                      },
              ),
            ),
            children: [
              if (_page!.records.isEmpty)
                Padding(
                  padding: accountingContentPadding,
                  child: Text(
                    _search.text.trim().isNotEmpty
                        ? 'No Matching Journals'
                        : _posted
                        ? 'No Posted Journals'
                        : 'No Journal Drafts',
                    style: AccountingTypography.value(context),
                  ),
                ),
              for (final record in _page!.records)
                AccountingRecordRow(
                  key: ValueKey('journal-row-${record.entry.id.value}'),
                  title: record.entry.memo,
                  details: Text(_recordDetails(record)),
                  trailing: AccountingRecordActions(
                    trailing: [
                      if (widget.workspace.database.isManualJournalDraft(
                            widget.workspace.identity.businessId,
                            record.entry.id,
                          ) ||
                          widget.workspace.database
                                  .manualJournalCurrentRootForEntry(
                                    widget.workspace.identity.businessId,
                                    record.entry.id,
                                  ) !=
                              null)
                        AccountingButton.iconOnly(
                          context,
                          compact: true,
                          key: ValueKey(
                            'edit-journal-${record.entry.id.value}',
                          ),
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit Journal',
                          onPressed: () async {
                            try {
                              await showJournalEditor(
                                context,
                                widget.workspace,
                                _accounts,
                                existing: record,
                                showSavedNotice: false,
                              );
                            } catch (error) {
                              if (mounted) {
                                setState(
                                  () => _error = error is StateError
                                      ? error.message
                                      : 'The Journal could not be opened. Reload and retry.',
                                );
                              }
                            }
                          },
                        ),
                      AccountingButton.iconOnly(
                        context,
                        compact: true,
                        key: ValueKey(
                          'review-journal-${record.entry.id.value}',
                        ),
                        icon: record.entry.state == JournalEntryState.posted
                            ? Icons.visibility_outlined
                            : Icons.checklist_outlined,
                        tooltip: record.entry.state == JournalEntryState.posted
                            ? 'View Journal'
                            : 'Review Journal',
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _JournalReviewDialog(
                            workspace: widget.workspace,
                            record: record,
                            accounts: _accounts,
                          ),
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
}

class _JournalReviewDialog extends StatefulWidget {
  const _JournalReviewDialog({
    required this.workspace,
    required this.record,
    required this.accounts,
    this.expense,
    this.claimReview,
  });
  final ExpenseIntakeRecord? expense;
  final ClaimExpenseApprovalSelection? claimReview;
  final AccountingWorkspace workspace;
  final StoredJournalEntry record;
  final List<StoredAccount> accounts;
  @override
  State<_JournalReviewDialog> createState() => _JournalReviewDialogState();
}

class _JournalReviewDialogState extends State<_JournalReviewDialog> {
  bool _busy = false;
  String? _error;
  JournalApproval? _command;
  ExpenseRevisionApproval? _expenseRevisionCommand;
  ClaimExpenseRevisionApproval? _claimExpenseRevisionCommand;
  Future<void> _approve() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _command ??= JournalApproval(
      requestId: AccountingWorkspace.newId(),
      businessId: widget.workspace.identity.businessId,
      journalId: widget.record.entry.id,
      expectedRevision: widget.record.metadata.revision,
      actorId: widget.workspace.identity.ownerId,
      approvedAt: DateTime.now().toUtc(),
      expenseIntakeId: widget.expense?.summary.id,
    );
    try {
      final expense = widget.expense;
      if (expense != null && expense.summary.hasPendingRevision) {
        _expenseRevisionCommand ??= ExpenseRevisionApproval(
          requestId: _command!.requestId,
          businessId: _command!.businessId,
          expenseId: expense.summary.id,
          expectedRevision: expense.currentRevision!.revision,
          expectedSourceJournalId: expense.summary.journalId!,
          journalId: _command!.journalId,
          expectedJournalRevision: _command!.expectedRevision,
          actorId: _command!.actorId,
          approvedAt: _command!.approvedAt,
        );
        if (expense.draft.claimSource == null) {
          widget.workspace.approveExpenseRevision(_expenseRevisionCommand!);
        } else {
          final reviewed = widget.claimReview;
          if (reviewed == null ||
              reviewed.payableAccountId !=
                  expense.draft.claimSource!.liabilityAccountId) {
            throw StateError(
              'Review the current Claim rows and retained liability.',
            );
          }
          _claimExpenseRevisionCommand ??= ClaimExpenseRevisionApproval(
            approval: _expenseRevisionCommand!,
            lineAccounts: reviewed.lineAccounts,
          );
          widget.workspace.approveClaimExpenseRevision(
            _claimExpenseRevisionCommand!,
          );
        }
      } else if (widget.workspace.database.manualJournalRevisionForDraft(
            widget.workspace.identity.businessId,
            widget.record.entry.id,
          ) !=
          null) {
        widget.workspace.approveManualJournalRevision(_command!);
      } else {
        await widget.workspace.approveJournal(_command!);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError
              ? error.message
              : error is JournalValidationException
              ? error.errors.join(' ')
              : 'Approval could not finish. Retry this request or reopen the updated draft.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.record.entry;
    final correction = entry.state == JournalEntryState.draft
        ? widget.workspace.database.manualJournalRevisionForDraft(
            widget.workspace.identity.businessId,
            entry.id,
          )
        : null;
    final names = {
      for (final r in widget.accounts) r.account.id: r.account.displayName,
    };
    final guidance = [
      if (correction != null) 'Approval preserves the original posting and posts its reversal together with the proposed replacement. Review both sets of accounts and amounts.',
      if (entry.isClosing) 'This transfers earnings between nominal accounts and equity; it does not change operating profit.',
      if (entry.state == JournalEntryState.draft && correction == null) 'Approve only when the accounts, amounts, date and supporting evidence are correct. Posting preserves this revision.',
    ];
    return PopScope(
      canPop: !_busy,
      child: AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.custom,
        title: entry.state == JournalEntryState.posted
            ? 'Posted Journal'
            : correction == null
            ? 'Review Journal'
            : 'Review Journal Correction',
        formFooter: entry.state == JournalEntryState.draft,
        titleGuidance: guidance.isEmpty ? null : guidance.join(' '),
        description: entry.memo,
        content: SizedBox(
          width: AccountingPopoutTokens.widerContentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectionArea(
                child: AccountingInformationRows(
                  rows: [
                    ('Date', formatAccountingInputDate(entry.date)),
                    if (correction != null) ...[
                      ('Entry Type', 'Journal Correction'),
                      (
                        'Original Date',
                        formatAccountingInputDate(correction.source.entry.date),
                      ),
                      ('Original Memo', correction.source.entry.memo),
                    ],
                    if (widget.expense != null) ...[
                      ('Expense', widget.expense!.draft.payee),
                      ('Payment Account', widget.expense!.draft.paymentAccount),
                      ('Tax', widget.expense!.draft.taxDescription),
                    ],
                    if (entry.isClosing) ...[
                      (
                        'Entry Type',
                        entry.reversesId == null
                            ? 'Closing Entry'
                            : 'Closing Reversal',
                      ),
                      (
                        'Equity Account',
                        names[entry.closingEquityAccountId] ??
                            'Unmapped Account',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: accountingContentInset),
              if (correction != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: accountingContentInset),
                  child: accountingSectionTitle(context, 'Original Posting'),
                ),
                const SizedBox(height: accountingContentInset),
                SelectionArea(
                  child: _JournalLinesReview(
                    lines: correction.source.entry.lines,
                    names: names,
                    keyPrefix: 'journal-original-review',
                  ),
                ),
                const SizedBox(height: accountingContentInset),
                Padding(
                  padding: const EdgeInsets.only(left: accountingContentInset),
                  child: accountingSectionTitle(
                    context,
                    'Proposed Replacement',
                  ),
                ),
                const SizedBox(height: accountingContentInset),
              ],
              SelectionArea(
                child: _JournalLinesReview(lines: entry.lines, names: names),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AccountingTypography.helper(context)
                      .copyWith(color: AccountingTheme.of(context).destructive),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (entry.state == JournalEntryState.draft)
            AccountingButton.primary(
              context,
              key: const ValueKey('approve-journal'),
              onPressed: _busy ? null : _approve,
              child: Text(
                _busy
                    ? 'Posting…'
                    : correction == null
                    ? 'Approve & Post'
                    : 'Approve & Post Correction',
              ),
            ),
        ],
      ),
    );
  }
}

/// Uses Home's accepted table cells/header rhythm inside the shared record card.
/// These are retained journal facts, not a second transaction editor.
class _JournalLinesReview extends StatelessWidget {
  const _JournalLinesReview({
    required this.lines,
    required this.names,
    this.keyPrefix = 'journal-review',
  });
  final List<JournalLine> lines;
  final Map<EntityId, String> names;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final currencies = lines.map((line) => line.amount.currency).toSet();
    final currency = currencies.length == 1 ? currencies.single : null;
    final symbol = currency == null
        ? null
        : CurrencyPresentation.fromCode(currency).amountSymbol;
    final headers = [
      'Account',
      symbol == null ? 'Debit' : 'Debit ($symbol)',
      symbol == null ? 'Credit' : 'Credit ($symbol)',
    ];
    String value(JournalLine line, bool debit) {
      final amount = line.isDebit == debit
          ? line.amount
          : Money.fromMinor(0, line.amount.currency);
      return formatAccountingMoney(
        context,
        amount,
        includeCurrency: currency == null,
      );
    }

    final rows = [
      for (final line in lines)
        [
          names[line.accountId] ?? 'Unmapped Account',
          value(line, true),
          value(line, false),
        ],
    ];
    final headerStyle = AccountingTypography.tableHeader(context);
    final valueStyle = AccountingTypography.value(context);
    return AccountingCard.surface(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: accountingContentInset)
            .copyWith(
              bottom:
                  accountingContentInset - accountingUndividedRowVerticalInset,
            ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            double measure(String text, TextStyle style) =>
                AccountingResponsive.measuredTextWidth(context, text, style);
            double numericWidth(int column) =>
                math.max(
                  measure(headers[column], headerStyle),
                  rows.fold<double>(
                    0,
                    (width, row) =>
                        math.max(width, measure(row[column], valueStyle)),
                  ),
                ) +
                (column == 1 ? accountingContentInset : 0);
            final debitWidth = numericWidth(1);
            final creditWidth = numericWidth(2);
            final accountMinimum = rows.fold<double>(
              measure(headers.first, headerStyle),
              (width, row) => row.first
                  .split(RegExp(r'\s+'))
                  .fold<double>(
                    width,
                    (width, word) => math.max(width, measure(word, valueStyle)),
                  ),
            );
            final minimum =
                accountMinimum +
                accountingContentInset +
                debitWidth +
                creditWidth;
            return SingleChildScrollView(
              key: ValueKey('$keyPrefix-lines-scroll'),
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(constraints.maxWidth, minimum),
                child: Table(
                  key: ValueKey('$keyPrefix-lines-table'),
                  columnWidths: {
                    0: const FlexColumnWidth(),
                    1: FixedColumnWidth(debitWidth),
                    2: FixedColumnWidth(creditWidth),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AccountingTheme.of(context).border,
                          ),
                        ),
                      ),
                      children: [
                        for (var column = 0; column < headers.length; column++)
                          accountingCompactTableCell(
                            headers[column],
                            style: headerStyle,
                            textAlign: column == 0
                                ? TextAlign.left
                                : TextAlign.right,
                            rightInset: column == 2
                                ? 0
                                : accountingContentInset,
                            verticalInset: accountingContentInset,
                          ),
                      ],
                    ),
                    for (var index = 0; index < rows.length; index++)
                      TableRow(
                        children: [
                          for (
                            var column = 0;
                            column < headers.length;
                            column++
                          )
                            accountingCompactTableCell(
                              rows[index][column],
                              style: valueStyle,
                              textAlign: column == 0
                                  ? TextAlign.left
                                  : TextAlign.right,
                              rightInset: column == 2
                                  ? 0
                                  : accountingContentInset,
                              firstDataRow: index == 0,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClosingEditor extends StatefulWidget {
  const _ClosingEditor({required this.workspace, required this.accounts});
  final AccountingWorkspace workspace;
  final List<StoredAccount> accounts;
  @override
  State<_ClosingEditor> createState() => _ClosingEditorState();
}

class _ClosingEditorState extends State<_ClosingEditor> {
  final _date = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  EntityId? _equity;
  final _editingFocus = FocusScopeNode();
  late final String _openingInput;
  bool _closePromptOpen = false;
  bool _busy = false;
  String? _error;
  String _inputSnapshot() => jsonEncode([_date.text, _equity?.value]);

  @override
  void initState() {
    super.initState();
    _openingInput = _inputSnapshot();
  }

  Future<void> _handleClose() async {
    if (_busy || _closePromptOpen) return;
    if (_inputSnapshot() == _openingInput) {
      Navigator.of(context).pop();
      return;
    }
    _closePromptOpen = true;
    try {
      final discard = await AccountingDialog.confirmDiscardChanges(
        context,
        closeKey: const ValueKey('closing-discard-close'),
        keepEditingKey: const ValueKey('closing-keep-editing'),
        discardKey: const ValueKey('closing-discard-changes'),
      );
      if (mounted) {
        if (discard) {
          Navigator.of(context).pop();
        } else {
          _editingFocus.requestFocus();
        }
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  @override
  void dispose() {
    _editingFocus.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final date = parseAccountingInputDate(_date.text);
      if (date == null || _equity == null) {
        throw StateError('Enter a valid date and choose an equity account.');
      }
      await widget.workspace.prepareClosing(
        through: date,
        equityAccountId: _equity!,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : 'The closing draft could not be saved. Check your records and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FocusScope(
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
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleClose();
      },
      child: AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        title: 'Prepare Closing',
        onClose: _handleClose,
        closeKey: const ValueKey('closing-editor-close'),
        canClose: !_busy,
        formFooter: true,
        titleGuidance: 'Transfer remaining income and expense balances through this date to equity. Review and approve the draft separately. This does not lock the period.',
        content: SizedBox(
          width: AccountingPopoutTokens.normalContentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountingOrdinaryFields(
                fields: [
                  AccountingOrdinaryFieldSlot(
                    label: 'Through Date',
                    date: true,
                    contentSample: '00-00-0000',
                    builder: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Through Date',
                          alignToField: true,
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        SizedBox(
                          key: const ValueKey('closing-date-frame'),
                          height: accountingControlHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: accountingDateFieldFrame(
                              child: TextField(
                                key: const ValueKey('closing-date'),
                                controller: _date,
                                enableInteractiveSelection: true,
                                enabled: !_busy,
                                inputFormatters: [const DateInputFormatter()],
                                decoration:
                                    accountingSingleLineInputDecoration(
                                      context,
                                      hintText: 'DD-MM-YYYY',
                                    ).copyWith(
                                      suffixIcon: accountingCalendarButton(
                                        context,
                                        controller: _date,
                                        label: 'Through Date',
                                        enabled: !_busy,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingOrdinaryFieldSlot(
                    label: 'Equity Account',
                    choices: [
                      'Select Account',
                      for (final record in widget.accounts)
                        if (record.account.type == AccountType.equity &&
                            record.account.status == AccountStatus.active &&
                            !record.account.isParent)
                          record.account.displayName,
                    ],
                    builder: (assignedWidth) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Equity Account',
                          alignToField: true,
                        ),
                        const SizedBox(height: 8),
                        AccountingSelector<EntityId>(
                          assignedWidth: assignedWidth,
                          triggerKey: const ValueKey('closing-equity'),
                          value: _equity,
                          enabled: !_busy,
                          searchable: true,
                          hintText: 'Select Account',
                          onChanged: (value) => setState(() => _equity = value),
                          options: [
                            for (final record in widget.accounts)
                              if (record.account.type == AccountType.equity &&
                                  record.account.status ==
                                      AccountStatus.active &&
                                  !record.account.isParent)
                                AccountingSelectorOption(
                                  value: record.account.id,
                                  label: record.account.displayName,
                                  preserveLabelCase: true,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AccountingTypography.helper(context)
                      .copyWith(color: AccountingTheme.of(context).destructive),
                ),
              ],
            ],
          ),
        ),
        actions: [
          AccountingButton.ghost(
            context,
            key: null,
            onPressed: _busy ? null : _handleClose,
            child: const Text('Cancel'),
          ),
          AccountingButton.primary(
            context,
            key: const ValueKey('save-closing-draft'),
            onPressed: _busy ? null : _prepare,
            child: Text(_busy ? 'Preparing…' : 'Save Draft'),
          ),
        ],
      ),
    ),
  );
}
