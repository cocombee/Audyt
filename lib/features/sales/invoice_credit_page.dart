import '../accounting/presentation/attachment_preview_dialog.dart';
import '../accounting/domain/transaction_removal.dart';
import '../accounting/presentation/transaction_removal_controls.dart';

import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/frontend_review.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/dates/accounting_date.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/domain/account.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import 'invoice_form.dart';
import 'invoice_credit_editor.dart';
import '../../core/ids/entity_id.dart';

/// Saved credit proposals and their separately reviewed, durable posting.
class InvoiceCreditPage extends StatelessWidget {
  const InvoiceCreditPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;

  Future<void> _reviewPosting(BuildContext context, EntityId id) async {
    try {
      final review = workspace.reviewCreditDraft(id);
      final draft = review.draft;
      if (draft.attachments.isEmpty ||
          draft.attachments.any(
            (a) => a.status != AttachmentProcessingStatus.ready,
          )) {
        throw StateError(
          'Add ready supporting evidence in Edit before posting this credit.',
        );
      }
      final invoice = workspace.postedInvoices().singleWhere(
        (row) => row.sourceDraft.id == draft.invoiceId,
      );
      final original = workspace.database.invoicePostingAccounts(
        workspace.identity.businessId,
        draft.invoiceId,
      )!;
      final accounts = (await workspace.accounts())
          .map((row) => row.account)
          .toList();
      // Verify original mappings before offering approval; excess credit adds
      // a selected liability which is revalidated in the posting transaction.
      final choices = accounts
          .where(
            (a) =>
                a.status == AccountStatus.active &&
                !a.isParent &&
                a.type == AccountType.liability &&
                a.id != original.tax,
          )
          .toList();
      final excess = review.allocation.customerCredit.isPositive;
      await workspace.creditDraftJournal(
        id,
        customerCreditAccount: excess ? choices.firstOrNull?.id : null,
      );
      if (!context.mounted) return;
      final names = {for (final a in accounts) a.id: '${a.code} · ${a.name}'};
      final net = review.lines.values
          .map((line) => line.net)
          .reduce((a, b) => a + b);
      final tax = review.lines.values
          .map((line) => line.tax)
          .reduce((a, b) => a + b);
      final requestId = EntityId.random();
      final approvedAt = DateTime.now().toUtc();
      await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => FrontendFormDialog(
          key: ValueKey('credit-posting-review-${id.value}'),
          form: DesignForm(
            'Post Credit',
            [
              if (excess)
                DesignField(
                  'Customer Credit Account',
                  required: true,
                  choiceLabels: {
                    for (final a in choices)
                      a.id.value: '${a.code} · ${a.name}',
                  },
                ),
            ],
            actionLabel: 'Post Credit',
            description: 'Review the saved credit and its original invoice accounts before posting. Customer credit is held for the customer; no cash refund is sent.',
          ),
          informationRows: [
            ('Invoice', invoice.documentNumber),
            ('Customer', invoice.customerSnapshot.displayName),
            ('Reason', draft.reason),
            ('Revision', '${draft.revision}'),
            ('Credit Date', formatAccountingInputDate(draft.date)),
            ('Net', invoiceMoney(net)),
            ('Tax', invoiceMoney(tax)),
            ('Total Credit', invoiceMoney(draft.total)),
            (
              'Invoice Balance Reduction',
              invoiceMoney(review.allocation.receivableReduction),
            ),
            ('Customer Credit', invoiceMoney(review.allocation.customerCredit)),
            (
              'Remaining Invoice Balance',
              invoiceMoney(review.allocation.remainingReceivable),
            ),
            ('Receivables', names[original.receivable]!),
            (
              'Original Income',
              review.lines.keys
                  .map(
                    (line) =>
                        names[original.lineIncome[line] ?? original.income],
                  )
                  .toSet()
                  .join(', '),
            ),
            if (tax.isPositive) ('Original Tax', names[original.tax]!),
          ],
          footerContent: Padding(
            padding: const EdgeInsets.only(top: accountingContentInset),
            child: AccountingAttachmentList(
              paginationKey: 'credit-posting-attachments-${id.value}',
              children: [
                for (final attachment in draft.attachments)
                  AccountingAttachmentRecordRow(
                    attachment: attachment,
                    actions: [
                      AccountingButton.iconOnly(
                        context,
                        key: ValueKey(
                          'credit-posting-evidence-${attachment.originalId}',
                        ),
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Attachment',
                        onPressed: () =>
                            showAttachmentPreview(context, attachment),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          onCommit: (values) async {
            try {
              workspace.postInvoiceCredit(
                requestId: requestId,
                draftId: id,
                expectedRevision: draft.revision,
                expectedPaidMinor: review.paidMinor,
                expectedPriorCreditMinor: review.priorCreditMinor,
                approvedAt: approvedAt,
                customerCreditAccount: excess
                    ? EntityId.parse(
                        values['Customer Credit Account'] as String,
                      )
                    : null,
              );
            } on StateError {
              rethrow;
            } catch (_) {
              throw StateError(
                'Credit could not be posted. Reopen the review or try again.',
              );
            }
          },
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: 'Credit Review Unavailable',
          content: Text(
            error is StateError ? error.message : 'Credit could not be reviewed. Reopen the saved draft and check its supporting evidence and accounts.',
          ),
          actions: [],
        ),
      );
    }
  }

  bool _canEdit(EntityId id, bool invoiceExists) =>
      invoiceExists &&
      workspace.database.invoiceCreditPosting(
            workspace.identity.businessId,
            id,
          ) ==
          null;

  void _history(BuildContext context, EntityId id) {
    var revisions = workspace.creditDraftHistory(id);
    String? restoreError;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: 'Credit Draft History',
          content: SizedBox(
            width: AccountingPopoutTokens.widerContentWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (restoreError != null)
                    AccountingAlert.build(
                      context,
                      key: const ValueKey('credit-history-error'),
                      title: 'Could Not Restore Credit',
                      description: restoreError!,
                      tone: AccountingAlertTone.critical,
                      bottomGap: accountingContentInset,
                      action: AccountingButton.ghost(
                        context,
                        key: const ValueKey('reload-credit-history'),
                        onPressed: () => setDialogState(() {
                          revisions = workspace.creditDraftHistory(id);
                          restoreError = null;
                        }),
                        child: const Text('Reload History'),
                      ),
                    ),
                  AccountingRecordList(
                    paginationKey: 'credit-history-${id.value}',
                    children: [
                      for (final revision in revisions)
                        Column(
                          key: ValueKey(
                            'credit-history-revision-${revision.revision}',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AccountingRecordRow(
                              title: 'Revision ${revision.revision}',
                              topRightInfo: true,
                              trailing: Text(invoiceMoney(revision.total)),
                              details: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: revision.reason,
                                    child: Text(
                                      revision.reason,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'Saved ${formatAccountingInputDate(revision.savedAt.toLocal())} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(revision.savedAt.toLocal()))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              actions: [
                                if (revision.revision !=
                                        revisions.first.revision &&
                                    workspace.database.invoiceCreditPosting(
                                          workspace.identity.businessId,
                                          id,
                                        ) ==
                                        null)
                                  AccountingRecordActions(
                                    trailing: [
                                      AccountingButton.iconOnly(
                                        context,
                                        key: ValueKey(
                                          'restore-credit-${revision.revision}',
                                        ),
                                        icon: Icons.restore,
                                        tooltip: 'Restore As New Revision',
                                        onPressed: () {
                                          try {
                                            workspace
                                                .restoreCreditDraftRevision(
                                                  draftId: id,
                                                  sourceRevision:
                                                      revision.revision,
                                                  expectedRevision:
                                                      revisions.first.revision,
                                                  restoredAt: DateTime.now(),
                                                );
                                            Navigator.pop(context);
                                          } catch (error) {
                                            setDialogState(
                                              () => restoreError = error
                                                  .toString(),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (revision.attachments.isNotEmpty)
                              Padding(
                                padding: accountingContentPadding.copyWith(
                                  top: 0,
                                ),
                                child: AccountingAttachmentList(
                                  paginationKey:
                                      'credit-history-attachments-${id.value}-${revision.revision}',
                                  children: [
                                    for (final attachment
                                        in revision.attachments)
                                      AccountingAttachmentRecordRow(
                                        attachment: attachment,
                                        actions: [
                                          AccountingButton.iconOnly(
                                            context,
                                            key: ValueKey(
                                              'history-${revision.revision}-${attachment.originalId}',
                                            ),
                                            icon: Icons.visibility_outlined,
                                            tooltip: 'View Attachment',
                                            onPressed: () =>
                                                showAttachmentPreview(
                                                  context,
                                                  attachment,
                                                ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [],
        ),
      ),
    );
  }

  Future<void> _view(
    BuildContext context,
    EntityId id, {
    bool removed = false,
  }) async {
    try {
      final posted = workspace.database.invoiceCreditPosting(
        workspace.identity.businessId,
        id,
      );
      final draft = workspace
          .creditDrafts(includeRemoved: removed)
          .singleWhere((d) => d.id == id);
      final review = posted == null && !removed
          ? workspace.reviewCreditDraft(id)
          : null;
      final originalInvoice = workspace.postedInvoices().singleWhere(
        (invoice) => invoice.sourceDraft.id == draft.invoiceId,
      );
      final rows = <(String, String)>[
        ('Reason', draft.reason),
        ('Revision', '${posted?.revision ?? draft.revision}'),
        ('Credit Date', formatAccountingInputDate(draft.date)),
        if (review != null) ...[
          (
            'Net',
            invoiceMoney(
              review.lines.values.map((l) => l.net).reduce((a, b) => a + b),
            ),
          ),
          (
            'Tax',
            invoiceMoney(
              review.lines.values.map((l) => l.tax).reduce((a, b) => a + b),
            ),
          ),
        ],
        ('Total Credit', invoiceMoney(draft.total)),
        ('Invoice', originalInvoice.documentNumber),
        if (removed) ...[
          for (var i = 0; i < draft.lineCredits.length; i++) ...[
            (
              'Line ${i + 1}',
              originalInvoice.sourceDraft.lines
                  .singleWhere(
                    (line) => line.id == draft.lineCredits.keys.elementAt(i),
                  )
                  .description,
            ),
            (
              'Line ${i + 1} Credit',
              invoiceMoney(draft.lineCredits.values.elementAt(i)),
            ),
            (
              'Line ${i + 1} Tax',
              '${originalInvoice.sourceDraft.taxMode} · ${originalInvoice.sourceDraft.lines.singleWhere((line) => line.id == draft.lineCredits.keys.elementAt(i)).taxRatePercent}%',
            ),
          ],
        ] else ...[
          (
            'Invoice Balance Reduction',
            invoiceMoney(
              posted?.receivableReduction ??
                  review!.allocation.receivableReduction,
            ),
          ),
          (
            'Customer Credit',
            invoiceMoney(
              posted?.customerCredit ?? review!.allocation.customerCredit,
            ),
          ),
          if (posted != null)
            ('Posted Journal', posted.journalId.value)
          else
            (
              'Remaining Invoice Balance',
              invoiceMoney(review!.allocation.remainingReceivable),
            ),
        ],
      ];
      await showDialog<void>(
        context: context,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: removed
              ? 'Removed Credit Draft'
              : posted == null
              ? 'Credit Draft'
              : 'Posted Credit',
          description: posted == null
              ? 'Draft only. No credit or refund has been posted.'
              : null,
          fixedContentWidth: AccountingPopoutTokens.widerContentWidth,
          maxContentWidth: AccountingPopoutTokens.widerContentWidth,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountingInformationRows(rows: rows),
              if (draft.attachments.isNotEmpty) ...[
                const SizedBox(height: accountingContentInset),
                AccountingAttachmentList(
                  paginationKey: 'credit-view-attachments-${id.value}',
                  children: [
                    for (final attachment in draft.attachments)
                      AccountingAttachmentRecordRow(
                        attachment: attachment,
                        actions: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              '${removed ? 'removed-credit-file' : 'credit-view-file'}-${id.value}-${attachment.originalId}',
                            ),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View Attachment',
                            onPressed: () =>
                                showAttachmentPreview(context, attachment),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: 'Credit Review Unavailable',
          content: Text(
            error is StateError
                ? error.message
                : 'Reopen the saved credit and check its source invoice.',
          ),
          actions: [],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final drafts = workspace.creditDrafts();
      final invoices = {
        for (final row in workspace.postedInvoices()) row.sourceDraft.id: row,
      };
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Credit Notes',
              title: 'Credit Notes',
              description: 'Review credit drafts and post approved adjustments to invoice balances.',
              action:
                  workspace
                          .removedTransactionPage(
                            TransactionRecordKind.invoiceCredit,
                            limit: 1,
                          )
                          .total ==
                      0
                  ? null
                  : RemovedTransactionsButton(
                      workspace: workspace,
                      kind: TransactionRecordKind.invoiceCredit,
                      onView: (record) => _view(
                        context,
                        EntityId.parse(record.recordId),
                        removed: true,
                      ),
                    ),
            ),
            const SizedBox(height: accountingPageTitleOuterGap),
            AccountingSelector<EntityId>(
              options: [
                for (final row in invoices.values)
                  if (row.sourceDraft.lines.isNotEmpty)
                    AccountingSelectorOption(
                      value: row.sourceDraft.id,
                      label:
                          '${row.documentNumber} · ${row.customerSnapshot.displayName}',
                    ),
              ],
              value: null,
              hintText: 'Choose Invoice To Credit',
              searchable: true,
              onChanged: (value) {
                if (value != null) {
                  showDialog<bool>(
                    context: context,
                    builder: (context) => InvoiceCreditEditor(
                      workspace: workspace,
                      invoice: invoices[value]!.sourceDraft,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            if (drafts.isEmpty)
              const AccountingPageText('No saved credit drafts.'),
            AccountingRecordList(
              paginationKey: 'invoice-credit-1',
              children: [
                for (final draft in drafts)
                  AccountingRecordRow(
                    topRightInfo: true,
                    title:
                        invoices[draft.invoiceId]?.documentNumber ??
                        draft.invoiceId.value,
                    status: AccountingBadge.build(
                      context,
                      label:
                          workspace.database.invoiceCreditPosting(
                                workspace.identity.businessId,
                                draft.id,
                              ) ==
                              null
                          ? 'Draft'
                          : 'Posted',
                    ),
                    details: Text(draft.reason),
                    trailing: Text(
                      invoiceMoney(draft.total),
                      style: AccountingTypography.value(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      AccountingRecordActions(
                        actions: [
                          TransactionRemoveButton(
                            key: ValueKey('delete-credit-${draft.id.value}'),
                            workspace: workspace,
                            kind: TransactionRecordKind.invoiceCredit,
                            recordId: draft.id.value,
                          ),
                          if (_canEdit(
                            draft.id,
                            invoices.containsKey(draft.invoiceId),
                          ))
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey('post-credit-${draft.id.value}'),
                              icon: Icons.preview_outlined,
                              tooltip: 'Review Posting',
                              onPressed: () =>
                                  _reviewPosting(context, draft.id),
                            ),
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('history-${draft.id}'),
                            onPressed: () => _history(context, draft.id),
                            icon: Icons.history_outlined,
                            tooltip: 'History',
                          ),
                        ],
                        trailing: [
                          for (final attachment in draft.attachments)
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'credit-file-${draft.id}-${attachment.originalId}',
                              ),
                              onPressed: () =>
                                  showAttachmentPreview(context, attachment),
                              icon:
                                  attachment.originalMimeType.startsWith(
                                    'image/',
                                  )
                                  ? Icons.image_outlined
                                  : Icons.description_outlined,
                              tooltip: 'View ${attachment.filename}',
                            ),
                          AccountingButton.outline(
                            context,
                            key: ValueKey(draft.id),
                            child: Text(
                              _canEdit(
                                    draft.id,
                                    invoices.containsKey(draft.invoiceId),
                                  )
                                  ? 'Edit'
                                  : 'View',
                            ),
                            onPressed: () {
                              if (_canEdit(
                                draft.id,
                                invoices.containsKey(draft.invoiceId),
                              )) {
                                showDialog<bool>(
                                  context: context,
                                  builder: (context) => InvoiceCreditEditor(
                                    workspace: workspace,
                                    invoice:
                                        invoices[draft.invoiceId]!.sourceDraft,
                                    draft: draft,
                                  ),
                                );
                              } else {
                                _view(context, draft.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
