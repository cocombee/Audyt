import '../../core/documents/receipt_document.dart';
import '../accounting/presentation/receipt_attachment_picker.dart';
import '../accounting/presentation/attachment_preview_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/field_row_trial.dart';
import '../../app/transaction_form_layout.dart';
import '../../core/dates/accounting_date.dart';
import '../../core/ids/entity_id.dart';
import '../../core/money/money.dart';
import '../../core/money/currency.dart';
import '../../core/money/currency_presentation.dart';
import '../accounting/application/accounting_workspace.dart';
import 'domain/invoice.dart';
import 'domain/invoice_credit_draft.dart';
import 'invoice_form.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';

class InvoiceCreditEditor extends StatefulWidget {
  const InvoiceCreditEditor({
    super.key,
    required this.workspace,
    required this.invoice,
    this.draft,
    this.attachmentPicker,
  });
  final AccountingWorkspace workspace;
  final Invoice invoice;
  final ExpenseAttachmentsPicker? attachmentPicker;
  final InvoiceCreditDraft? draft;
  @override
  State<InvoiceCreditEditor> createState() => _InvoiceCreditEditorState();
}

class _InvoiceCreditEditorState extends State<InvoiceCreditEditor> {
  late final id = widget.draft?.id ?? EntityId.random();
  late final reason = TextEditingController(text: widget.draft?.reason ?? '');
  late final date = TextEditingController(
    text: formatAccountingInputDate(widget.draft?.date ?? DateTime.now()),
  );
  late final amounts = {
    for (final line in widget.invoice.lines)
      line.id: TextEditingController(
        text: widget.draft?.lineCredits[line.id] == null
            ? ''
            : formatAccountingMoneyInputText(
                invoiceDecimal(widget.draft!.lineCredits[line.id]!),
                Currency.parse(line.total.currency).fractionDigits,
              ),
      ),
  };
  late final attachments = [...?widget.draft?.attachments];
  bool picking = false;
  bool dragOver = false;
  String? error;
  Future<void> pick() async {
    setState(() => picking = true);
    try {
      final files =
          await (widget.attachmentPicker ??
              const NativeExpenseAttachmentPicker().pick)(context);
      await _addFiles(files);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _onFilesDropped(DropDoneDetails details) async {
    if (mounted) setState(() => dragOver = false);
    final files = <PickedExpenseAttachment>[];
    for (final item in details.files) {
      if (item is DropItemDirectory) continue;
      final bookmark = item.extraAppleBookmark;
      var accessed = false;
      try {
        if (bookmark != null && bookmark.isNotEmpty) {
          accessed = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        }
        files.add(
          PickedExpenseAttachment(
            name: item.name,
            mimeType:
                item.mimeType ??
                NativeExpenseAttachmentPicker.mimeTypeForFilename(item.name),
            bytes: await item.readAsBytes(),
            path: item.path,
          ),
        );
      } catch (e) {
        if (mounted) setState(() => error = 'Could not read ${item.name}: $e');
      } finally {
        if (accessed) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark!,
          );
        }
      }
    }
    await _addFiles(files);
  }

  Future<void> _addFiles(List<PickedExpenseAttachment> files) async {
    if (files.isEmpty) return;
    if (mounted) setState(() => picking = true);
    try {
      for (final file in files) {
        if (!NativeExpenseAttachmentPicker.supportedExtensions.contains(
          file.name.split('.').last.toLowerCase(),
        )) {
          if (mounted) setState(() => error = 'Unsupported file: ${file.name}');
          continue;
        }
        final attachment = await const ReceiptDocumentPipeline().process(
          ReceiptAttachmentInput(
            originalId: EntityId.random().value,
            batchId: id.value,
            filename: file.name,
            mimeType: file.mimeType,
            bytes: file.bytes,
          ),
        );
        if (!mounted) return;
        setState(() => attachments.add(attachment));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  void dispose() {
    reason.dispose();
    date.dispose();
    for (final c in amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    try {
      final parsed = parseAccountingInputDate(date.text);
      if (parsed == null) throw ArgumentError('Enter a valid credit date.');
      widget.workspace.saveInvoiceCreditDraft(
        attachments: attachments,
        draftId: id,
        invoiceId: widget.invoice.id,
        lineCredits: {
          for (final e in amounts.entries)
            if (e.value.text.trim().isNotEmpty)
              e.key: Money.fromDecimal(
                e.value.text.trim(),
                widget.invoice.total.currency,
              ),
        },
        reason: reason.text,
        creditDate: parsed,
        expectedRevision: widget.draft?.revision ?? 0,
        savedAt: DateTime.now(),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.custom,
    title: 'Credit Draft',
    formFooter: true,
    description: 'Enter gross credit amounts for returned lines. Leave other lines blank.',
    content: SizedBox(
      width: AccountingPopoutTokens.widerContentWidth,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingInformationRows(
              rows: [
                for (final source in widget.workspace.postedInvoices().where(
                  (row) => row.sourceDraft.id == widget.invoice.id,
                ))
                  ('Customer', source.customerSnapshot.displayName),
                ('Invoice', widget.invoice.documentNumber),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            AccountingOrdinaryFields(
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: 'Credit Date',
                  date: true,
                  contentSample: '00-00-0000',
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Credit Date',
                        key: const ValueKey('credit-date-label'),
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      accountingDateFieldFrame(
                        child: TextField(
                          key: const ValueKey('credit-date'),
                          controller: date,
                          style: AccountingTypography.controlValue(context),
                          enableInteractiveSelection: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [DateInputFormatter()],
                          decoration:
                              accountingSingleLineInputDecoration(
                                context,
                                hintText: 'DD-MM-YYYY',
                              ).copyWith(
                                suffixIcon: accountingCalendarButton(
                                  context,
                                  controller: date,
                                  label: 'Credit Date',
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Reason',
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(
                        context,
                        'Reason',
                        alignToField: true,
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        key: const ValueKey('credit-reason'),
                        controller: reason,
                        style: AccountingTypography.controlValue(context),
                        decoration: accountingSingleLineInputDecoration(
                          context,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final line in widget.invoice.lines) ...[
              const SizedBox(height: accountingContentInset),
              LayoutBuilder(
                builder: (context, constraints) {
                  final amountLabel =
                      'Amount (${CurrencyPresentation.fromCode(line.total.currency).amountSymbol})';
                  final amountWidth =
                      AccountingTransactionGridTokens.numericWidth(
                        context,
                        'Amount',
                        amounts.values.map((value) => value.text),
                        title: amountLabel,
                        minimumText: amountLabel,
                      ).clamp(0.0, constraints.maxWidth);
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.description,
                        style: AccountingTypography.fieldLabel(context),
                      ),
                      const SizedBox(height: accountingFieldLabelGap),
                      accountingHelperText(
                        context,
                        'Original: ${invoiceMoney(line.total)}',
                      ),
                    ],
                  );
                  final amount = SizedBox(
                    width: amountWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accountingFieldLabel(
                          context,
                          amountLabel,
                          alignToField: true,
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        TextField(
                          key: ValueKey('credit-amount-${line.id}'),
                          controller: amounts[line.id],
                          style: AccountingTypography.controlValue(context),
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            AccountingMoneyInputFormatter(
                              Currency.parse(line.total.currency)
                                  .fractionDigits,
                            ),
                          ],
                          decoration: accountingSingleLineInputDecoration(
                            context,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  );
                  final widestWord = line.description
                      .split(RegExp(r'\s+'))
                      .fold<double>(0, (width, word) {
                        final painter = TextPainter(
                          text: TextSpan(
                            text: word,
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        final measured = painter.width;
                        painter.dispose();
                        return measured > width ? measured : width;
                      });
                  if (constraints.maxWidth -
                          amountWidth -
                          accountingContentInset <
                      widestWord) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: accountingContentInset),
                        Align(alignment: Alignment.centerRight, child: amount),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(height: accountingContentInset),
                      amount,
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            DropTarget(
              enable:
                  !picking &&
                  (defaultTargetPlatform == TargetPlatform.macOS ||
                      defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.linux),
              onDragEntered: (_) {
                if (mounted) setState(() => dragOver = true);
              },
              onDragExited: (_) {
                if (mounted) setState(() => dragOver = false);
              },
              onDragDone: _onFilesDropped,
              child: InkWell(
                onTap: picking ? null : pick,
                borderRadius: BorderRadius.circular(accountingControlRadius),
                child: AccountingAttachmentDropzone(
                  dragOver: dragOver,
                  actionKey: const ValueKey('credit-attachments'),
                  onChoose: picking ? null : pick,
                  prompt: 'Drop documents here or choose files',
                  formats: 'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
                ),
              ),
            ),
            if (picking) const Text('Processing…'),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: accountingContentInset),
              AccountingAttachmentList(
                paginationKey: 'credit-attachments',
                children: [
                  for (final attachment in attachments)
                    AccountingAttachmentRecordRow(
                      attachment: attachment,
                      actions: [
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('preview-${attachment.originalId}'),
                          onPressed: () =>
                              showAttachmentPreview(context, attachment),
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Attachment',
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: ValueKey('remove-${attachment.originalId}'),
                          onPressed: picking
                              ? null
                              : () => setState(
                                  () => attachments.remove(attachment),
                                ),
                          icon: Icons.delete_outline,
                          tooltip: 'Remove from this draft',
                        ),
                      ],
                    ),
                ],
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      AccountingButton.secondary(
        context,
        key: const ValueKey('cancel-credit'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      AccountingButton.primary(
        context,
        key: const ValueKey('save-credit'),
        onPressed: picking ? null : save,
        child: const Text('Save Draft'),
      ),
    ],
  );
}
