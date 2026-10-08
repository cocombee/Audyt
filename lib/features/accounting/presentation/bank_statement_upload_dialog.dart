import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/field_row_trial.dart';
import '../../../../core/documents/receipt_document.dart';
import '../domain/bank_statement_import.dart';
import '../domain/payment_account.dart';
import 'attachment_preview_dialog.dart';

typedef BankStatementFile = ({String name, Uint8List bytes});
typedef ReviewedBankStatement = ({
  PaymentAccount account,
  BankStatementImport statement,
});

/// Stages a file and parses it for review. No import or matching command runs
/// here; the Banking owner retains its separate confirmation and commit.
class BankStatementUploadDialog extends StatefulWidget {
  const BankStatementUploadDialog({
    super.key,
    required this.initialAccount,
    required this.accounts,
    required this.pickFile,
    required this.parseFile,
  });

  final PaymentAccount initialAccount;
  final List<PaymentAccount> accounts;
  final Future<BankStatementFile?> Function() pickFile;
  final Future<BankStatementImport> Function(
    BankStatementFile file,
    PaymentAccount account,
  )
  parseFile;

  @override
  State<BankStatementUploadDialog> createState() =>
      _BankStatementUploadDialogState();
}

class _BankStatementUploadDialogState extends State<BankStatementUploadDialog> {
  late PaymentAccount _account = widget.initialAccount;
  ReceiptAttachment? _file;
  String? _error;
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await widget.pickFile();
      if (!mounted || picked == null) return;
      final pdf = picked.name.toLowerCase().endsWith('.pdf');
      if (!pdf && !picked.name.toLowerCase().endsWith('.csv')) {
        throw const FormatException('Choose a CSV or supported bank PDF.');
      }
      if (picked.bytes.isEmpty) {
        throw const FormatException('The selected statement file is empty.');
      }
      setState(
        () => _file = ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'staged-bank-statement',
            batchId: 'bank-statement',
            filename: picked.name,
            mimeType: pdf ? 'application/pdf' : 'text/csv',
            bytes: picked.bytes,
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : 'The file could not be selected. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final file = _file;
    if (_busy || file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final statement = await widget.parseFile((
        name: file.filename,
        bytes: file.originalBytes,
      ), _account);
      if (mounted) {
        Navigator.pop<ReviewedBankStatement>(context, (
          account: _account,
          statement: statement,
        ));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is FormatException ? error.message.toString() : 'The statement could not be read. Choose another file or retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AccountingDialog.alert(
    context,
    widthFamily: AccountingPopoutWidthFamily.normal,
    title: 'Import Bank Statement',
    closeKey: const ValueKey('bank-statement-upload-close'),
    canClose: !_busy,
    formFooter: true,
    content: SizedBox(
      width: AccountingPopoutTokens.normalContentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountingOrdinaryFields(
            key: const ValueKey('bank-statement-upload-fields'),
            fields: [
              AccountingOrdinaryFieldSlot(
                label: 'Account *',
                hasGuidance: true,
                choices: [
                  for (final account in widget.accounts) account.displayLabel,
                ],
                builder: (width) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    accountingFieldLabel(
                      context,
                      'Account *',
                      alignToField: true,
                      guidance: 'Choose the account these statement transactions belong to. The account determines the currency. Importing does not reconcile its balance.',
                    ),
                    const SizedBox(height: accountingFieldLabelGap),
                    AccountingSelector<String>(
                      controlKey: const ValueKey(
                        'bank-statement-upload-account',
                      ),
                      assignedWidth: width,
                      hintText: 'Select Account',
                      value: _account.id,
                      enabled: !_busy,
                      options: [
                        for (final account in widget.accounts)
                          AccountingSelectorOption(
                            value: account.id,
                            key: ValueKey(
                              'bank-statement-upload-option-${account.id}',
                            ),
                            label: account.displayLabel,
                            preserveLabelCase: true,
                          ),
                      ],
                      onChanged: (value) {
                        if (_busy || value == null) return;
                        setState(() {
                          _account = widget.accounts.singleWhere(
                            (a) => a.id == value,
                          );
                          _error = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          accountingFieldLabel(
            context,
            'Statement File',
            alignToField: true,
            guidance: 'CSV requires Date, Description and Amount columns; Reference is optional. Use a Maybank PDF statement when choosing PDF.',
          ),
          const SizedBox(height: accountingFieldLabelGap),
          AccountingAttachmentDropzone(
            surfaceKey: const ValueKey('bank-statement-upload-dropzone'),
            actionKey: const ValueKey('bank-statement-upload-choose'),
            onChoose: _busy ? null : _choose,
            prompt: 'Choose a bank statement file',
            formats: 'CSV or Maybank PDF. One file at a time.',
          ),
          if (_file case final file?) ...[
            const SizedBox(height: accountingContentInset),
            AccountingAttachmentRecordRow(
              key: const ValueKey('bank-statement-upload-file'),
              attachment: file,
              showProcessingStatus: false,
              actions: [
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('bank-statement-upload-remove'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _file = null;
                          _error = null;
                        }),
                  icon: Icons.delete_outline,
                  tooltip: 'Remove Statement File',
                ),
              ],
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: accountingContentInset),
            AccountingAlert.build(
              context,
              key: const ValueKey('bank-statement-upload-error'),
              title: 'Statement File',
              description: error,
              tone: AccountingAlertTone.critical,
              bottomGap: 0,
            ),
          ],
        ],
      ),
    ),
    actions: [
      AccountingButton.primary(
        context,
        key: const ValueKey('bank-statement-upload-review'),
        onPressed: _busy || _file == null ? null : _review,
        child: Text(_busy ? 'Reading Statement…' : 'Review Statement'),
      ),
    ],
  );
}
