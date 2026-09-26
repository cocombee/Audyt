import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../core/dates/accounting_date.dart';
import '../application/accounting_workspace.dart';
import '../domain/transaction_removal.dart';
import 'widgets/accounting_formatters.dart';

String removalFamilyLabel(TransactionRecordKind kind, {bool plural = false}) =>
    switch (kind) {
      TransactionRecordKind.claim => plural ? 'Claims' : 'Claim',
      TransactionRecordKind.paymentVoucher => plural ? 'Vouchers' : 'Voucher',
      TransactionRecordKind.bill => plural ? 'Bills' : 'Bill',
      TransactionRecordKind.quotation => plural ? 'Quotations' : 'Quotation',
      TransactionRecordKind.invoiceCredit => plural ? 'Credits' : 'Credit',
    };

/// Shared confirmation binds to the exact review token captured before opening.
/// The command revalidates it after confirmation; no source/file is deleted.
Future<bool> confirmTransactionRemoval(
  BuildContext context,
  AccountingWorkspace workspace,
  TransactionRemovalReview reviewed,
) async {
  final restore = reviewed.removed;
  final label = removalFamilyLabel(reviewed.kind);
  final confirmed = await AccountingDialog.showFixed<bool>(
    context: context,
    contentWidth: 400,
    builder: (dialogContext) => AccountingDialog.alert(
      dialogContext,
      title: '${restore ? 'Restore' : 'Remove'} $label',
      content: Text(
        restore
            ? 'Restore this record to the active list with its original status?'
            : 'Remove this unposted record from the active list? Its details and receipts are retained in Removed ${removalFamilyLabel(reviewed.kind, plural: true)}, where you can restore it.',
      ),
      actions: [
        AccountingButton.ghost(
          dialogContext,
          key: const ValueKey('transaction-cancel-removal'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        if (restore)
          AccountingButton.primary(
            dialogContext,
            key: const ValueKey('transaction-confirm-removal'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          )
        else
          AccountingButton.destructive(
            dialogContext,
            key: const ValueKey('transaction-confirm-removal'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  workspace.setTransactionRemoved(
    reviewed: reviewed,
    removed: !restore,
    changedAt: DateTime.now().toUtc(),
  );
  return true;
}

Future<void> _showRemovalError(BuildContext context, Object error) =>
    showDialog<void>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        title: 'Record Action Failed',
        content: Text(
          error is StateError
              ? error.message.toString()
              : 'The record could not be changed. Reload and try again.',
        ),
        actions: const [],
      ),
    );

class TransactionRemoveButton extends StatefulWidget {
  const TransactionRemoveButton({
    super.key,
    required this.workspace,
    required this.kind,
    required this.recordId,
    this.onChanged,
  });
  final AccountingWorkspace workspace;
  final TransactionRecordKind kind;
  final String recordId;
  final VoidCallback? onChanged;
  @override
  State<TransactionRemoveButton> createState() =>
      _TransactionRemoveButtonState();
}

class _TransactionRemoveButtonState extends State<TransactionRemoveButton> {
  bool _busy = false;
  Future<void> _remove(TransactionRemovalReview reviewed) async {
    setState(() => _busy = true);
    try {
      if (await confirmTransactionRemoval(
        context,
        widget.workspace,
        reviewed,
      )) {
        widget.onChanged?.call();
      }
    } catch (error) {
      if (mounted) await _showRemovalError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewed = widget.workspace.reviewTransactionRemoval(
      widget.kind,
      widget.recordId,
    );
    return AccountingButton.iconOnly(
      context,
      key: ValueKey('remove-${widget.kind.name}-${widget.recordId}'),
      onPressed: !_busy && reviewed.canRemove ? () => _remove(reviewed) : null,
      icon: Icons.delete_outline,
      tooltip:
          reviewed.restriction ?? 'Remove ${removalFamilyLabel(widget.kind)}',
    );
  }
}

class RemovedTransactionsButton extends StatelessWidget {
  const RemovedTransactionsButton({
    super.key,
    required this.workspace,
    required this.kind,
    required this.onView,
    this.onChanged,
  });
  final AccountingWorkspace workspace;
  final TransactionRecordKind kind;
  final Future<void> Function(TransactionRemovalReview) onView;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final total = workspace.removedTransactionPage(kind, limit: 1).total;
      if (total == 0) return const SizedBox.shrink();
      return AccountingButton.ghost(
        context,
        key: ValueKey('removed-${kind.name}-open'),
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (_) => RemovedTransactionsDialog(
              workspace: workspace,
              kind: kind,
              onView: onView,
            ),
          );
          onChanged?.call();
        },
        child: Text(
          'Removed ${removalFamilyLabel(kind, plural: true)} ($total)',
        ),
      );
    },
  );
}

class RemovedTransactionsDialog extends StatefulWidget {
  const RemovedTransactionsDialog({
    super.key,
    required this.workspace,
    required this.kind,
    required this.onView,
  });
  final AccountingWorkspace workspace;
  final TransactionRecordKind kind;
  final Future<void> Function(TransactionRemovalReview) onView;
  @override
  State<RemovedTransactionsDialog> createState() =>
      _RemovedTransactionsDialogState();
}

class _RemovedTransactionsDialogState extends State<RemovedTransactionsDialog> {
  int _offset = 0;
  late int _pageSize = AccountingRecordPageSizes.read(
    'removed-${widget.kind.name}',
  );
  String? _changing, _error;
  Future<void> _restore(TransactionRemovalReview reviewed) async {
    setState(() {
      _changing = reviewed.recordId;
      _error = null;
    });
    try {
      await confirmTransactionRemoval(context, widget.workspace, reviewed);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'The record could not be restored. Reload and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _changing = null);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final count = widget.workspace
          .removedTransactionPage(widget.kind, limit: 1)
          .total;
      final lastOffset = count == 0
          ? 0
          : ((count - 1) ~/ _pageSize) * _pageSize;
      final offset = _offset > lastOffset ? lastOffset : _offset;
      final page = widget.workspace.removedTransactionPage(
        widget.kind,
        offset: offset,
        limit: _pageSize,
      );
      return AccountingDialog.alert(
        context,
        title: 'Removed ${removalFamilyLabel(widget.kind, plural: true)}',
        description: 'Details and receipts are retained. Restore a record to return it to the active list.',
        fixedContentWidth: 680,
        maxContentWidth: 680,
        actions: const [],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AccountingAlert.build(
                context,
                title: 'Restore Failed',
                description: _error!,
                tone: AccountingAlertTone.critical,
              ),
              const SizedBox(height: accountingContentInset),
            ],
            if (page.total == 0)
              AccountingEmptyState.card(
                context,
                title:
                    'No Removed ${removalFamilyLabel(widget.kind, plural: true)}',
                description: 'Restored records appear in the active list.',
                icon: Icons.restore,
              )
            else
              AccountingCard.surface(
                context,
                child: Column(
                  children: [
                    for (var i = 0; i < page.records.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      AccountingRecordRow(
                        key: ValueKey(
                          'removed-${widget.kind.name}-${page.records[i].recordId}',
                        ),
                        topRightInfo: true,
                        title: page.records[i].label,
                        details: Text(
                          'Removed ${formatAccountingInputDate(page.records[i].changedAt!)}',
                        ),
                        status: AccountingBadge.build(
                          context,
                          label: page.records[i].status,
                        ),
                        trailing: Text(
                          formatAccountingMoney(
                            context,
                            page.records[i].amount,
                          ),
                          style: AccountingTypography.value(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        actions: [
                          AccountingRecordActions(
                            trailing: const [],
                            actions: [
                              AccountingButton.iconOnly(
                                context,
                                key: ValueKey(
                                  'removed-view-${page.records[i].recordId}',
                                ),
                                icon: Icons.visibility_outlined,
                                tooltip: 'View',
                                onPressed: () async {
                                  try {
                                    await widget.onView(page.records[i]);
                                  } catch (error) {
                                    if (context.mounted) {
                                      await _showRemovalError(context, error);
                                    }
                                  }
                                },
                              ),
                              AccountingButton.iconOnly(
                                context,
                                key: ValueKey(
                                  'removed-restore-${page.records[i].recordId}',
                                ),
                                icon: Icons.restore,
                                tooltip:
                                    page.records[i].restriction ?? 'Restore',
                                onPressed:
                                    _changing == null &&
                                        page.records[i].canRestore
                                    ? () => _restore(page.records[i])
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (AccountingRecordControlsPolicy.visible(page.total)) ...[
              const SizedBox(height: accountingContentInset),
              AccountingRecordPagination(
                total: page.total,
                offset: offset,
                pageSize: _pageSize,
                keyPrefix: 'removed-${widget.kind.name}',
                onPageSizeChanged: (v) => setState(() {
                  _pageSize = v;
                  _offset = 0;
                }),
                onPrevious: offset == 0
                    ? null
                    : () => setState(() => _offset = offset - _pageSize),
                onNext: offset + _pageSize >= page.total
                    ? null
                    : () => setState(() => _offset = offset + _pageSize),
              ),
            ],
          ],
        ),
      );
    },
  );
}
