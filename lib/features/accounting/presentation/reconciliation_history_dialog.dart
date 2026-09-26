import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../application/reconciliation_report.dart';
import '../data/accounting_database.dart';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_description_field.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/ids/entity_id.dart';
import 'attachment_preview_dialog.dart';
import '../application/accounting_workspace.dart';
import '../domain/statement_reconciliation.dart';
import 'widgets/accounting_formatters.dart';

class ReconciliationHistoryDialog extends StatefulWidget {
  const ReconciliationHistoryDialog({
    super.key,
    required this.workspace,
    required this.statementId,
  }) : paymentAccountId = null;
  const ReconciliationHistoryDialog.account({
    super.key,
    required this.workspace,
    required String this.paymentAccountId,
  }) : statementId = null;
  final AccountingWorkspace workspace;
  final EntityId? statementId;
  final String? paymentAccountId;
  @override
  State<ReconciliationHistoryDialog> createState() =>
      _ReconciliationHistoryDialogState();
}

class _ReconciliationHistoryDialogState
    extends State<ReconciliationHistoryDialog> {
  Future<void> _reopen(StatementReconciliationHistory item) async {
    var reason = '';
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          title: 'Reopen Reconciliation',
          maxContentWidth: 420,
          fixedContentWidth: 420,
          description: 'The approval remains in history. Reopening permits corrections to its matches. Later reconciliations must be reopened first.',
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reopening Reason',
                  style: AccountingTypography.fieldLabel(context),
                ),
                const SizedBox(height: 8),
                AccountingDescriptionField(
                  key: const ValueKey('reconciliation-reopening-reason'),
                  fixedLines: 3,
                  onChanged: (value) => reason = value,
                  decoration: accountingInputDecoration(
                    context,
                    hintText: 'Explain the correction',
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
            AccountingButton.primary(
              context,
              key: const ValueKey('confirm-reconciliation-reopening'),
              onPressed: () {
                if (reason.trim().isEmpty) {
                  update(() => error = 'Enter a reopening reason.');
                  return;
                }
                try {
                  widget.workspace.database.reopenStatementReconciliation(
                    businessId: widget.workspace.identity.businessId,
                    completionId: item.id,
                    actorId: widget.workspace.identity.ownerId,
                    reopenedAt: DateTime.now(),
                    reason: reason,
                  );
                  Navigator.pop(dialogContext, true);
                } catch (failure) {
                  update(
                    () => error = failure is StateError
                        ? failure.message
                        : 'Reconciliation could not be reopened.',
                  );
                }
              },
              child: const Text('Reopen'),
            ),
          ],
        ),
      ),
    );
    if (done == true && mounted) {
      widget.workspace.refreshBankStatementReview();
      setState(() {});
    }
  }

  Future<void> _export(StatementReconciliationHistory approval) async {
    try {
      final database = widget.workspace.database;
      final business = widget.workspace.identity.businessId;
      final snapshot = database.reconciliationReportSnapshot(
        business,
        approval.id,
      );
      final report = reconciliationReportHtml(
        businessId: business.value,
        generatedAt: snapshot.generatedAt,
        approval: snapshot.approval,
        evidence: snapshot.evidence,
        ledger: snapshot.ledger,
        classification: snapshot.classification,
        changes: snapshot.changes,
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Reconciliation Report',
        fileName: 'Reconciliation ${approval.id}.html',
        bytes: Uint8List.fromList(utf8.encode(report)),
        mimeType: 'text/html',
        type: FileType.custom,
        allowedExtensions: ['html'],
      );
      if (path == null) return;
      final file = File.fromUri(path);
      if (await file.readAsString() != report) {
        throw StateError('Report verification failed.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reconciliation report saved. Open it in a browser to print.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reconciliation report could not be saved.'),
          ),
        );
      }
    }
  }

  Future<void> _evidence(String completionId) async {
    try {
      final snapshot = widget.workspace.database.reconciliationReportSnapshot(
        widget.workspace.identity.businessId,
        completionId,
      );
      final evidence = snapshot.evidence;
      final ledger = snapshot.ledger;
      final changes = snapshot.changes;
      final classification = snapshot.classification;
      final clearedIds =
          classification?.cleared.map((m) => m.id).toSet() ?? <String>{};
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, _) => AccountingDialog.alert(
            context,
            title: 'Approved Transaction Evidence',
            description: evidence.isAccountPeriod
                ? 'The account ledger, selected transactions and supporting files preserved when this reconciliation was approved.'
                : 'The statement, ledger and connections preserved when this reconciliation was approved.',
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: AccountingCard.surface(
                  context,
                  child: Padding(
                    padding: accountingContentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!evidence.isAccountPeriod) ...[
                          Text(
                            evidence.filename,
                            style: AccountingTypography.value(context)
                                .copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: accountingRecordInfoLineGap),
                          SelectableText(
                            'Source SHA-256: ${evidence.sourceDigest}',
                            style: AccountingTypography.helper(context),
                          ),
                        ],
                        if (evidence.attachments.isNotEmpty) ...[
                          const SizedBox(height: accountingContentInset),
                          accountingFieldLabel(
                            context,
                            'Supporting Files',
                            alignToField: true,
                          ),
                          const SizedBox(height: accountingFieldLabelGap),
                          AccountingAttachmentList(
                            paginationKey:
                                'reconciliation-approved-supporting-files',
                            children: [
                              for (final file in evidence.attachments)
                                ReadonlyAttachmentRow(
                                  attachment: file,
                                  keyPrefix: 'reconciliation-history',
                                ),
                            ],
                          ),
                        ],
                        if (evidence.openingOutstanding.isNotEmpty) ...[
                          const SizedBox(height: accountingContentInset),
                          Text(
                            'Opening Outstanding Items',
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          const SizedBox(height: 8),
                          for (final item in evidence.openingOutstanding)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${formatAccountingInputDate(item.date)} · ${item.memo}',
                                          style:
                                              AccountingTypography.value(
                                                context,
                                              ).copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(
                                          height: accountingRecordInfoLineGap,
                                        ),
                                        SelectableText(
                                          'Ledger Movement: ${item.id}',
                                          style: AccountingTypography.helper(
                                            context,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: accountingContentInset),
                                  Text(
                                    formatAccountingMoney(context, item.amount),
                                    style: AccountingTypography.value(context)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],

                        if (ledger == null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: accountingContentInset,
                            ),
                            child: Text(
                              'Ledger snapshot unavailable for this older approval.',
                              style: AccountingTypography.helper(context),
                            ),
                          )
                        else ...[
                          const SizedBox(height: accountingContentInset),
                          Text(
                            'Ledger Balance at Approval: ${formatAccountingMoney(context, ledger.balance)}',
                            style: AccountingTypography.value(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Recorded Ledger Movements',
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          const SizedBox(height: 8),
                          for (final item in ledger.movements)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${formatAccountingInputDate(item.date)} · ${item.memo}',
                                          style:
                                              AccountingTypography.value(
                                                context,
                                              ).copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(
                                          height: accountingRecordInfoLineGap,
                                        ),
                                        SelectableText(
                                          'Ledger Movement: ${item.id}${evidence.isAccountPeriod && evidence.selectedMovements.any((m) => m.id == item.id) ? ' · Selected This Period' : ''}${classification == null
                                              ? ''
                                              : clearedIds.contains(item.id)
                                              ? ' · Cleared'
                                              : ' · Outstanding'}',
                                          style: AccountingTypography.helper(
                                            context,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: accountingContentInset),
                                  Text(
                                    formatAccountingMoney(context, item.amount),
                                    style: AccountingTypography.value(context)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],

                        if (changes.snapshotAvailable) ...[
                          const SizedBox(height: accountingContentInset),
                          Text(
                            'Changes Since Approval',
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            changes.unchanged
                                ? 'No ledger changes detected.'
                                : '${changes.added.length} added, ${changes.missing.length} missing, ${changes.changed.length} changed movements.',
                          ),
                          for (final item in changes.added)
                            Text(
                              'Added: ${formatAccountingInputDate(item.date)} · ${item.memo} · ${formatAccountingMoney(context, item.amount)}',
                            ),
                          for (final item in changes.missing)
                            SelectableText('Missing: ${item.id}'),
                          for (final id in changes.changed)
                            SelectableText('Changed: $id'),
                        ],

                        if (classification == null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: accountingContentInset,
                            ),
                            child: Text(
                              'Cleared and outstanding classification unavailable for this older approval.',
                              style: AccountingTypography.helper(context),
                            ),
                          )
                        else ...[
                          const SizedBox(height: accountingContentInset),
                          AccountingInformationRows(
                            key: const ValueKey(
                              'reconciliation-approved-balances',
                            ),
                            rows: [
                              (
                                'Cleared Balance',
                                formatAccountingMoney(
                                  context,
                                  classification.clearedBalance,
                                ),
                              ),
                              (
                                'Outstanding Balance',
                                formatAccountingMoney(
                                  context,
                                  classification.outstandingBalance,
                                ),
                              ),
                              (
                                'Closing Difference',
                                formatAccountingMoney(
                                  context,
                                  classification.closingDifference,
                                ),
                              ),
                              if (classification.unresolved.isNotEmpty)
                                (
                                  'Unresolved Movements',
                                  '${classification.unresolved.length}',
                                ),
                            ],
                          ),
                        ],
                        if (!evidence.isAccountPeriod) ...[
                          const SizedBox(height: accountingContentInset),
                          Text(
                            'Approved Statement Matches',
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          const SizedBox(height: 8),
                          for (final match in evidence.matches) ...[
                            const Divider(height: 1, thickness: 1),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        match.statementRow.description,
                                        style: AccountingTypography.value(
                                          context,
                                        ).copyWith(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(
                                        height: accountingRecordInfoLineGap,
                                      ),
                                      Text(
                                        '${formatAccountingInputDate(match.statementRow.date)} · Row ${match.statementRow.sourceRow}${match.statementRow.reference.isEmpty ? '' : ' · ${match.statementRow.reference}'}',
                                        style: AccountingTypography.helper(
                                          context,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: accountingContentInset),
                                Text(
                                  formatAccountingMoney(
                                    context,
                                    match.statementRow.amount,
                                  ),
                                  style: AccountingTypography.value(context)
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SelectionArea(
                              child: AccountingInformationRows(
                                rows: [
                                  if (match.combinedMovements.isEmpty) ...[
                                    ('Journal', match.journalId),
                                    ('Journal Line', '${match.lineIndex + 1}'),
                                    (
                                      'Date',
                                      formatAccountingInputDate(
                                        match.journalDate,
                                      ),
                                    ),
                                    ('Memo', match.journalMemo),
                                  ] else
                                    for (
                                      var i = 0;
                                      i < match.combinedMovements.length;
                                      i++
                                    ) ...[
                                      (
                                        'Journal ${i + 1}',
                                        match
                                            .combinedMovements[i]
                                            .candidate
                                            .journalId
                                            .value,
                                      ),
                                      (
                                        'Journal Line',
                                        '${match.combinedMovements[i].candidate.lineIndex + 1}',
                                      ),
                                      (
                                        'Date',
                                        formatAccountingInputDate(
                                          match
                                              .combinedMovements[i]
                                              .candidate
                                              .date,
                                        ),
                                      ),
                                      (
                                        'Memo',
                                        match
                                            .combinedMovements[i]
                                            .candidate
                                            .memo,
                                      ),
                                      (
                                        'Amount',
                                        formatAccountingMoney(
                                          context,
                                          match.combinedMovements[i].amount,
                                        ),
                                      ),
                                    ],
                                  ('Acceptance', match.acceptanceId),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Approved transaction evidence could not be loaded.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.paymentAccountId == null
        ? widget.workspace.database.reconciliationHistory(
            widget.workspace.identity.businessId,
            widget.statementId!,
          )
        : widget.workspace.database.accountReconciliationHistory(
            widget.workspace.identity.businessId,
            widget.paymentAccountId!,
          );
    return AccountingDialog.alert(
      context,
      title: 'Reconciliation History',
      description: 'Review approvals, their evidence and any later reopening.',
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: AccountingRecordList(
            paginationKey: 'reconciliation-history',
            totalCount: history.length,
            emptyState: Padding(
              padding: accountingContentPadding,
              child: Text(
                'No reconciliation approvals yet.',
                style: AccountingTypography.helper(context),
              ),
            ),
            children: [
              for (var index = 0; index < history.length; index++)
                Padding(
                  key: ValueKey('reconciliation-history-${history[index].id}'),
                  padding: accountingContentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        history[index].reopenedAt == null
                            ? 'Approved'
                            : 'Reopened',
                        style: AccountingTypography.value(context)
                            .copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: accountingRecordInfoLineGap),
                      Text(
                        '${formatAccountingInputDate(history[index].startsOn)} – ${formatAccountingInputDate(history[index].endsOn)}',
                        style: AccountingTypography.helper(context),
                      ),
                      const SizedBox(height: 12),
                      SelectionArea(
                        child: AccountingInformationRows(
                          rows: [
                            (
                              'Opening Balance',
                              formatAccountingMoney(
                                context,
                                history[index].openingBalance,
                              ),
                            ),
                            (
                              'Closing Balance',
                              formatAccountingMoney(
                                context,
                                history[index].closingBalance,
                              ),
                            ),
                            ('Approval ID', history[index].id),
                            (
                              'Approval Date',
                              '${history[index].approvedAt.toLocal()}',
                            ),
                            ('Approved By', history[index].actorId),
                            if (history[index].previousId != null)
                              (
                                'Previous Approval',
                                '${history[index].previousId}',
                              ),
                            if (history[index].openingEvidence.isNotEmpty)
                              (
                                'Opening Evidence',
                                history[index].openingEvidence,
                              ),
                            if (history[index].reopenedAt != null) ...[
                              (
                                'Reopened On',
                                '${history[index].reopenedAt!.toLocal()}',
                              ),
                              ('Reopened By', '${history[index].reopenedBy}'),
                              ('Reason', history[index].reopeningReason!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AccountingButtonSizeScope(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AccountingButton.outline(
                              context,
                              key: ValueKey(
                                'export-reconciliation-${history[index].id}',
                              ),
                              onPressed: () => _export(history[index]),
                              child: const Text('Export Report'),
                            ),
                            AccountingButton.outline(
                              context,
                              key: ValueKey(
                                'reconciliation-evidence-${history[index].id}',
                              ),
                              onPressed: () => _evidence(history[index].id),
                              child: const Text('Transaction Evidence'),
                            ),
                            if (history[index].reopenedAt == null)
                              AccountingButton.outline(
                                context,
                                key: ValueKey(
                                  'reopen-reconciliation-${history[index].id}',
                                ),
                                onPressed:
                                    widget.workspace.database
                                            .latestReconciliationId(
                                              widget
                                                  .workspace
                                                  .identity
                                                  .businessId,
                                              history[index].paymentAccountId,
                                            ) ==
                                        history[index].id
                                    ? () => _reopen(history[index])
                                    : null,
                                child: const Text('Reopen Reconciliation'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [],
    );
  }
}
