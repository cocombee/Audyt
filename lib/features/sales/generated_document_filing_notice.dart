import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../core/documents/generated_document.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/data/accounting_database.dart';
import 'generated_sales_document_service.dart';

/// A committed draft and a filed output are distinct outcomes. Pending delivery
/// stays visible after reopen and retries the exact committed revision.
class GeneratedDocumentFilingNotice extends StatefulWidget {
  const GeneratedDocumentFilingNotice({
    super.key,
    required this.workspace,
    required this.kind,
  });
  final AccountingWorkspace workspace;
  final GeneratedDocumentKind kind;
  @override
  State<GeneratedDocumentFilingNotice> createState() =>
      _GeneratedDocumentFilingNoticeState();
}

class _GeneratedDocumentFilingNoticeState
    extends State<GeneratedDocumentFilingNotice> {
  bool _retrying = false;
  String? _failure;
  int _generation = 0;
  @override
  void didUpdateWidget(covariant GeneratedDocumentFilingNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace ||
        oldWidget.kind != widget.kind) {
      _generation++;
      _retrying = false;
      _failure = null;
    }
  }

  List<GeneratedDocumentDelivery> pending() =>
      widget.workspace.database.generatedDocumentDeliveries(
        widget.workspace.identity.businessId,
        pendingOnly: true,
        latestOnly: true,
        kind: widget.kind,
      );

  Future<void> _retry() async {
    final workspace = widget.workspace;
    final company = workspace.identity.businessId;
    final queue = pending();
    final generation = _generation;
    String? deliveryFailure;
    setState(() {
      _retrying = true;
      _failure = null;
    });
    try {
      for (final delivery in queue) {
        if (widget.workspace != workspace ||
            widget.workspace.identity.businessId != company) {
          break;
        }
        final failure = await const GeneratedSalesDocumentService().retry(
          workspace: workspace,
          kind: delivery.kind,
          recordId: delivery.recordId,
          revision: delivery.revision,
        );
        if (failure != null) {
          deliveryFailure = failure;
          break;
        }
      }
    } catch (error) {
      deliveryFailure = error.toString();
    }
    if (mounted && generation == _generation) {
      setState(() {
        _retrying = false;
        _failure = deliveryFailure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = pending();
    if (queue.isEmpty) return const SizedBox.shrink();
    return AccountingAlert.build(
      context,
      key: ValueKey('generated-filing-${widget.kind.name}'),
      title: 'PDF Filing Pending',
      tone: AccountingAlertTone.warning,
      bottomGap: accountingContentInset,
      description:
          '${queue.length} saved ${queue.length == 1 ? 'draft needs' : 'drafts need'} PDF filing. '
          'Reconnect the saved destination and retry. The drafts are saved.'
          '${_failure == null ? '' : '\n$_failure'}',
      action: AccountingButton.outline(
        context,
        key: ValueKey('retry-generated-filing-${widget.kind.name}'),
        onPressed: _retrying ? null : _retry,
        child: Text(_retrying ? 'Retrying…' : 'Retry Filing'),
      ),
    );
  }
}
