import 'package:audyt/app/field_row_trial.dart';

import '../../../../app/accounting_theme.dart';
import '../../../../app/accounting_description_field.dart';
import '../../../../app/accounting_color_library.dart';
import 'reconciliation_history_dialog.dart';
import 'bank_statement_upload_dialog.dart';
import 'statement_reconciliation_dialog.dart';
import 'widgets/accounting_formatters.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../../../../core/dates/accounting_date.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/currency_presentation.dart';
import '../domain/bank_statement_import.dart';
import '../domain/bank_statement_match.dart';
import '../domain/maybank_pdf_statement.dart';
import '../../../../core/documents/receipt_document.dart';
import 'attachment_preview_dialog.dart';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_icons.dart';
import '../../../../app/responsive.dart';
import '../../../../core/ids/entity_id.dart';
import '../application/accounting_workspace.dart';
import '../domain/account.dart';
import '../domain/payment_account.dart';
import 'payment_account_dialog.dart';
import 'widgets/accounting_layout.dart';

class BankingPage extends StatefulWidget {
  const BankingPage({
    super.key,
    required this.workspace,
    required this.compact,
    this.selectedStatementId,
    this.statementPicker,
    this.onRecordExpense,
    this.onReceivePayment,
    this.onPaymentVoucher,
    this.onCreateInvoice,
    this.onReconciliationExpense,
    this.onReconciliationPayment,
  });
  final AccountingWorkspace workspace;
  final bool compact;
  final ValueNotifier<String?>? selectedStatementId;
  final Future<({String name, Uint8List bytes})?> Function()? statementPicker;
  final Future<void> Function(BankStatementRow row, PaymentAccount account)?
  onRecordExpense;
  final Future<void> Function(BankStatementRow row, PaymentAccount account)?
  onReceivePayment;
  final Future<void> Function(BankStatementRow row, PaymentAccount account)?
  onPaymentVoucher;
  final Future<void> Function(BankStatementRow row, PaymentAccount account)?
  onCreateInvoice;
  final Future<void> Function(PaymentAccount account, DateTime date)?
  onReconciliationExpense;
  final Future<void> Function(PaymentAccount account, DateTime date)?
  onReconciliationPayment;
  @override
  State<BankingPage> createState() => _BankingPageState();
}

class _BankingPageState extends State<BankingPage> {
  List<PaymentAccount>? _payments;
  // This page's filter is intentionally independent of Home's balance menu.
  String? _selectedPaymentId;
  String _documentQuery = '';
  DateTime? _documentFrom;
  DateTime? _documentThrough;

  List<PaymentAccount> get _bankAccounts =>
      (_payments ?? const <PaymentAccount>[])
          .where((account) => account.type == PaymentAccountType.bank)
          .toList(growable: false);

  String? get _displayPaymentId {
    final payments = _payments ?? const <PaymentAccount>[];
    if (payments.isEmpty) return null;
    if (payments.any((account) => account.id == _selectedPaymentId)) {
      return _selectedPaymentId;
    }
    for (final account in payments) {
      if (account.type == PaymentAccountType.bank) return account.id;
    }
    return payments.first.id;
  }

  List<PaymentAccount> get _visiblePayments {
    final payments = _payments ?? const <PaymentAccount>[];
    final selected = _displayPaymentId;
    if (selected == null) return const <PaymentAccount>[];
    return payments.where((account) => account.id == selected).toList();
  }

  Map<EntityId, Account> _chart = {};
  Map<String, EntityId?> _links = {};
  Map<String, Money> _ledgerBalances = {};
  Map<String, int> _unresolved = {};
  Map<String, int> _awaitingApproval = {};
  Map<String, List<({EntityId id, BankStatementImport statement})>>
  _statementsByPayment = {};
  Map<String, Map<int, String>> _acceptedByStatement = {};

  void _selectStatement(String paymentId, String statementId) {
    _selectedPaymentId = paymentId;
    _selectedStatementIds[paymentId] = statementId;
    widget.selectedStatementId?.value = statementId;
  }

  final Map<String, String> _selectedStatementIds = {};
  final Set<String> _expandedStatementAccounts = {};
  ({EntityId id, String currency, String paymentId})? _activeReconciliation;
  Widget? _activeMatchReview;
  bool _reconciliationReturnsToReview = false;
  final Map<String, StatementMatchWindow> _matchingWindows = {};
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_load);
    widget.selectedStatementId?.addListener(_followSelectedStatement);
    _load();
  }

  void _followSelectedStatement() {
    final statementId = widget.selectedStatementId?.value;
    if (statementId == null) return;
    for (final entry in _statementsByPayment.entries) {
      if (entry.value.any((item) => item.id.value == statementId) &&
          entry.key != _displayPaymentId) {
        setState(() => _selectedPaymentId = entry.key);
        return;
      }
    }
  }

  @override
  void didUpdateWidget(covariant BankingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStatementId != widget.selectedStatementId) {
      oldWidget.selectedStatementId?.removeListener(_followSelectedStatement);
      widget.selectedStatementId?.addListener(_followSelectedStatement);
      _followSelectedStatement();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.workspace.removeListener(_load);
    widget.selectedStatementId?.removeListener(_followSelectedStatement);
    super.dispose();
  }

  void _openReconciliation(EntityId id, PaymentAccount payment) => setState(() {
    if (_activeReconciliation == null) {
      _reconciliationReturnsToReview = _activeMatchReview != null;
    }
    _activeMatchReview = null;
    _selectStatement(payment.id, id.value);
    _activeReconciliation = (
      id: id,
      currency: payment.currency.code,
      paymentId: payment.id,
    );
  });

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final chart = await widget.workspace.accounts();
      final payments = widget.workspace.paymentAccounts;
      final links = {
        for (final p in payments)
          p.id: widget.workspace.database.paymentLedgerAccount(
            widget.workspace.identity.businessId,
            p.id,
          ),
      };
      final balances = <String, Money>{};
      final unresolved = <String, int>{};
      final awaitingApproval = <String, int>{};
      final statementsByPayment =
          <String, List<({EntityId id, BankStatementImport statement})>>{};
      final acceptedByStatement = <String, Map<int, String>>{};
      final suggestedByStatement = <String, Map<int, int>>{};
      var autoConnected = 0;
      for (final payment in payments) {
        unresolved[payment.id] = 0;
        awaitingApproval[payment.id] = 0;
        statementsByPayment[payment.id] = [];
        for (final item in widget.workspace.database.bankStatements(
          widget.workspace.identity.businessId,
          payment.id,
        )) {
          autoConnected += widget.workspace.database
              .autoConnectStatementMatches(
                businessId: widget.workspace.identity.businessId,
                statementId: item.id,
                actorId: widget.workspace.identity.ownerId,
                connectedAt: DateTime.now(),
              );
          final statement = widget.workspace.database.bankStatement(
            widget.workspace.identity.businessId,
            item.id,
          );
          if (statement == null) continue;
          statementsByPayment[payment.id]!.add((
            id: item.id,
            statement: statement,
          ));
          if (!widget.workspace.database.isStatementReconciled(
            widget.workspace.identity.businessId,
            item.id,
          )) {
            awaitingApproval[payment.id] = awaitingApproval[payment.id]! + 1;
          }
          final accepted = widget.workspace.database.acceptedStatementMatches(
            widget.workspace.identity.businessId,
            item.id,
          );
          acceptedByStatement[item.id.value] = accepted;
          if (links[payment.id] != null) {
            try {
              suggestedByStatement[item.id.value] = {
                for (final suggestion
                    in widget.workspace.database.statementMatchSuggestions(
                      widget.workspace.identity.businessId,
                      item.id,
                    ))
                  if (!accepted.containsKey(suggestion.row.sourceRow) &&
                      suggestion.candidates.isNotEmpty)
                    suggestion.row.sourceRow: suggestion.candidates.length,
              };
            } catch (_) {
              // Matching may be temporarily unavailable; keep the imported
              // rows and their disconnected state visible.
            }
          }
          unresolved[payment.id] =
              unresolved[payment.id]! +
              statement.rows
                  .where((row) => !accepted.containsKey(row.sourceRow))
                  .length;
        }
      }
      try {
        final report = await widget.workspace.report(
          from: DateTime.utc(1),
          through: DateTime.now(),
        );
        for (final entry in links.entries) {
          if (entry.value == null) continue;
          final row = report.rows
              .where((item) => item.account.id == entry.value)
              .firstOrNull;
          if (row != null && row.endingNetDebit.isValidInt) {
            balances[entry.key] = Money.fromMinor(
              row.endingNetDebit.toInt(),
              report.currency,
            );
          }
        }
      } catch (_) {
        // Account management remains usable if ledger reporting needs review.
      }
      if (!mounted || generation != _generation) return;
      final focusedStatementId = widget.selectedStatementId?.value;
      final focusedAccountId = focusedStatementId == null
          ? null
          : statementsByPayment.entries
                .where(
                  (entry) => entry.value.any(
                    (item) => item.id.value == focusedStatementId,
                  ),
                )
                .map((entry) => entry.key)
                .firstOrNull;
      setState(() {
        _chart = {
          for (final record in chart) record.account.id: record.account,
        };
        _payments = payments;
        _links = links;
        _ledgerBalances = balances;
        _unresolved = unresolved;
        _awaitingApproval = awaitingApproval;
        _statementsByPayment = statementsByPayment;
        if (focusedAccountId != null && _selectedPaymentId == null) {
          _selectedPaymentId = focusedAccountId;
        }
        _acceptedByStatement = acceptedByStatement;
        _error = null;
      });
      if (autoConnected > 0) widget.workspace.refreshBankStatementReview();
      final selectedPayment = _paymentById(_displayPaymentId);
      final selectedStatement = selectedPayment == null
          ? null
          : _selectedStatement(selectedPayment);
      if (selectedPayment != null &&
          selectedStatement != null &&
          _activeMatchReview == null &&
          _activeReconciliation == null &&
          widget.selectedStatementId?.value != null &&
          !_expandedStatementAccounts.contains(selectedPayment.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _activeMatchReview != null ||
              _activeReconciliation != null ||
              _expandedStatementAccounts.contains(selectedPayment.id)) {
            return;
          }
          _matches(selectedStatement.id, selectedPayment);
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _payments = null;
          _error = 'Banking accounts could not be loaded. Retry to continue.';
        });
      }
    }
  }

  Future<bool> _previewStatement(
    BankStatementImport statement, {
    required bool importing,
    PaymentAccount? payment,
  }) async {
    var offset = 0;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AccountingDialog.alert(
              context,
              widthFamily: AccountingPopoutWidthFamily.normal,
              title: importing
                  ? 'Review Statement Import'
                  : 'Imported Statement',
              formFooter: true,
              description: 'Importing preserves evidence. Exact outgoing matches may connect; reconciliation still needs statement-balance review.',
              content: SizedBox(
                width: AccountingPopoutTokens.normalContentWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AccountingInformationRows(
                        key: const ValueKey('statement-import-details'),
                        rows: [
                          ('Filename', statement.filename),
                          (
                            'Currency',
                            CurrencyPresentation.fromCode(statement.currency)
                                .amountSymbol,
                          ),
                          ('Statement Rows', '${statement.rows.length}'),
                          if (statement.statementDate case final date?) ...[
                            (
                              'Account Holder',
                              statement.accountHolderName ?? '',
                            ),
                            ('Account Number', statement.accountNumber ?? ''),
                            ('Statement Date', formatAccountingInputDate(date)),
                            (
                              'Opening Balance',
                              formatAccountingMoney(
                                context,
                                statement.openingBalance!,
                              ),
                            ),
                            (
                              'Closing Balance',
                              formatAccountingMoney(
                                context,
                                statement.closingBalance!,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (statement.statementDate == null) ...[
                        const SizedBox(height: accountingContentInset),
                        Text(
                          payment?.type == PaymentAccountType.card
                              ? 'Positive amounts increase the card balance owed; negative amounts reduce it.'
                              : 'Positive amounts increase the bank balance; negative amounts reduce it.',
                          style: AccountingTypography.helper(context),
                        ),
                      ],
                      const SizedBox(height: accountingContentInset),
                      AccountingCard.surface(
                        context,
                        child: Column(
                          children: [
                            for (final row
                                in statement.rows.skip(offset).take(50)) ...[
                              if (row.sourceRow !=
                                  statement.rows[offset].sourceRow)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: accountingContentInset,
                                  endIndent: accountingContentInset,
                                ),
                              Padding(
                                padding: accountingContentPadding,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            row.description,
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
                                          Text(
                                            '${formatAccountingInputDate(row.date)}${row.reference.isEmpty ? '' : ' · ${row.reference}'}${row.sourcePage == null ? '' : ' · Page ${row.sourcePage}'}',
                                            style: AccountingTypography.helper(
                                              context,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: accountingContentInset,
                                    ),
                                    Text(
                                      formatAccountingMoney(
                                        context,
                                        row.amount,
                                      ),
                                      style: AccountingTypography.value(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (offset > 0 ||
                          offset + 50 < statement.rows.length) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (offset > 0)
                              AccountingButton.outline(
                                context,
                                key: null,
                                onPressed: () => update(() => offset -= 50),
                                child: const Text('Previous'),
                              ),
                            if (offset + 50 < statement.rows.length)
                              AccountingButton.outline(
                                context,
                                key: null,
                                onPressed: () => update(() => offset += 50),
                                child: const Text('Next'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (importing)
                  AccountingButton.ghost(
                    context,
                    key: null,
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                if (importing)
                  AccountingButton.primary(
                    context,
                    key: const ValueKey('banking-save-import'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Import Statement'),
                  ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _explainMissingStatement() => showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.dialog,
      title: 'Original File Unavailable',
      content: const Text(
        'This data-only restore retains the statement rows and checksum. The original document remains in its original folder and must be reconnected before it can be viewed or exported.',
      ),
      actions: [],
    ),
  );
  Future<void> _viewOriginalStatement(BankStatementImport statement) async {
    if (!statement.sourceAvailable) {
      await _explainMissingStatement();
      return;
    }
    if (statement.filename.toLowerCase().endsWith('.pdf')) {
      await showAttachmentPreview(
        context,
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: statement.digest,
            batchId: 'bank-statement',
            filename: statement.filename,
            mimeType: 'application/pdf',
            bytes: statement.sourceBytes,
          ),
        ),
      );
      return;
    }
    final lines = const LineSplitter().convert(
      utf8.decode(statement.sourceBytes),
    );
    var offset = 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: 'Original Statement · ${statement.filename}',
          description: 'The original imported file is preserved for review.',
          content: SizedBox(
            width: AccountingPopoutTokens.widerContentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountingCard.surface(
                  context,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: accountingContentPadding,
                        child: SelectableText(
                          lines.skip(offset).take(100).join('\n'),
                          style: AccountingTypography.helper(context)
                              .copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: accountingContentInset),
                Text(
                  'Lines ${offset + 1}–${(offset + 100).clamp(0, lines.length)} of ${lines.length}',
                  style: AccountingTypography.helper(context),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('bank-source-previous'),
                      onPressed: offset == 0
                          ? null
                          : () => update(() => offset -= 100),
                      child: const Text('Previous'),
                    ),
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('bank-source-next'),
                      onPressed: offset + 100 >= lines.length
                          ? null
                          : () => update(() => offset += 100),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [],
        ),
      ),
    );
  }

  Future<void> _saveOriginalStatement(BankStatementImport statement) async {
    if (!statement.sourceAvailable) {
      await _explainMissingStatement();
      return;
    }
    try {
      final pdf = statement.filename.toLowerCase().endsWith('.pdf');
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Original Bank Statement',
        fileName: statement.filename,
        bytes: statement.sourceBytes,
        mimeType: pdf ? 'application/pdf' : 'text/csv',
        type: FileType.custom,
        allowedExtensions: [pdf ? 'pdf' : 'csv'],
      );
      if (path == null) return;
      final savedDigest = sha256
          .convert(await File.fromUri(path).readAsBytes())
          .toString();
      if (savedDigest != statement.digest) {
        throw StateError('Statement export failed verification.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Original statement saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original statement could not be saved.'),
          ),
        );
      }
    }
  }

  Future<BankStatementFile?> _pickStatement() async {
    if (widget.statementPicker != null) return widget.statementPicker!();
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose Bank Statement',
      type: FileType.custom,
      allowedExtensions: ['csv', 'pdf'],
    );
    if (files.isEmpty) return null;
    return (name: files.first.name, bytes: await files.first.readAsBytes());
  }

  Future<BankStatementImport> _parseStatement(
    BankStatementFile selected,
    PaymentAccount account,
  ) async {
    if (selected.name.toLowerCase().endsWith('.pdf')) {
      final pages = await const MethodChannel('audyt/statement-text')
          .invokeMethod<List<dynamic>>('positionedGlyphs', {
            'bytes': selected.bytes,
          });
      if (pages == null) {
        throw const FormatException('The PDF text could not be extracted.');
      }
      return MaybankPdfStatement.parse(
        filename: selected.name,
        currency: account.currency.code,
        bytes: selected.bytes,
        pages: pages.cast<Object?>(),
        expectedAccountNumber: account.accountNumber,
        expectedHolderName: account.accountHolderName,
      );
    }
    return BankStatementImport.csv(
      filename: selected.name,
      currency: account.currency.code,
      bytes: selected.bytes,
    );
  }

  Future<void> _importStatement(PaymentAccount initialAccount) async {
    try {
      final accounts = List<PaymentAccount>.of(_payments ?? [initialAccount])
        ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
      final reviewed = await showDialog<ReviewedBankStatement>(
        context: context,
        builder: (_) => BankStatementUploadDialog(
          initialAccount: initialAccount,
          accounts: accounts,
          pickFile: _pickStatement,
          parseFile: _parseStatement,
        ),
      );
      if (reviewed == null || !mounted) return;
      final account = reviewed.account;
      final statement = reviewed.statement;
      final alreadyImported = widget.workspace.database
          .bankStatements(widget.workspace.identity.businessId, account.id)
          .any(
            (item) =>
                widget.workspace.database
                    .bankStatement(
                      widget.workspace.identity.businessId,
                      item.id,
                    )
                    ?.digest ==
                statement.digest,
          );
      if (alreadyImported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This statement is already imported for this account.',
              ),
            ),
          );
        }
        return;
      }
      if (!await _previewStatement(
            statement,
            importing: true,
            payment: account,
          ) ||
          !mounted) {
        return;
      }
      final importedId = widget.workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: widget.workspace.identity.businessId,
        paymentAccountId: account.id,
        statement: statement,
        importedAt: DateTime.now(),
      );
      _selectedPaymentId = account.id;
      _selectedStatementIds[account.id] = importedId.value;
      _returnToDocuments();
      final autoConnected = widget.workspace.database
          .autoConnectStatementMatches(
            businessId: widget.workspace.identity.businessId,
            statementId: importedId,
            actorId: widget.workspace.identity.ownerId,
            connectedAt: DateTime.now(),
          );
      widget.workspace.refreshBankStatementReview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              autoConnected == 0
                  ? 'Statement imported. Unmatched rows need review in Imported Statements.'
                  : '$autoConnected outgoing transaction${autoConnected == 1 ? '' : 's'} matched by nearby date, reference and amount. Review remaining rows in Imported Statements.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : 'Statement could not be imported. Your original file is unchanged.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _matchHistory(EntityId statementId) async {
    final history = widget.workspace.database.statementMatchHistory(
      widget.workspace.identity.businessId,
      statementId,
    );
    var offset = 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.custom,
          title: 'Match History',
          description: 'Review accepted connections and any later corrections.',
          content: SizedBox(
            width: AccountingPopoutTokens.widerContentWidth,
            child: SingleChildScrollView(
              child: AccountingCard.surface(
                context,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (history.isEmpty)
                      Padding(
                        padding: accountingContentPadding,
                        child: Text(
                          'No matches accepted yet.',
                          style: AccountingTypography.helper(context),
                        ),
                      ),
                    for (
                      var index = offset;
                      index < math.min(offset + 25, history.length);
                      index++
                    ) ...[
                      if (index > offset)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: accountingContentInset,
                          endIndent: accountingContentInset,
                        ),
                      Padding(
                        padding: accountingContentPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statement Row ${history[index].sourceRow} · ${history[index].reason == null ? 'Accepted' : 'Retracted'}',
                              style: AccountingTypography.value(context)
                                  .copyWith(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: accountingRecordInfoLineGap),
                            SelectionArea(
                              child: AccountingInformationRows(
                                rows: [
                                  (
                                    'Journal Movement',
                                    history[index].movementIds.join(', '),
                                  ),
                                  (
                                    'Accepted',
                                    '${history[index].acceptedAt.toLocal()}',
                                  ),
                                  ('Accepted By', history[index].actorId),
                                  if (history[index].reason != null) ...[
                                    (
                                      'Retracted',
                                      '${history[index].retractedAt!.toLocal()}',
                                    ),
                                    (
                                      'Retracted By',
                                      '${history[index].correctionActorId}',
                                    ),
                                    ('Reason', history[index].reason!),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (history.length > 25) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: accountingContentPadding,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (offset > 0)
                              AccountingButton.outline(
                                context,
                                key: null,
                                onPressed: () => update(() => offset -= 25),
                                child: const Text('Previous'),
                              ),
                            if (offset + 25 < history.length)
                              AccountingButton.outline(
                                context,
                                key: null,
                                onPressed: () => update(() => offset += 25),
                                child: const Text('Next'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [],
        ),
      ),
    );
  }

  Future<bool> _retractMatch(String acceptanceId) async {
    var reason = '';
    String? error;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AccountingDialog.alert(
              context,
              widthFamily: AccountingPopoutWidthFamily.dialog,
              title: 'Retract Match',
              description: 'The original acceptance and your correction reason remain in the audit history. Ledger transactions are unchanged.',
              content: SizedBox(
                width: AccountingPopoutTokens.dialogContentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Correction Reason',
                      style: AccountingTypography.fieldLabel(context),
                    ),
                    const SizedBox(height: 8),
                    AccountingDescriptionField(
                      key: const ValueKey('match-correction-reason'),
                      autofocus: true,
                      fixedLines: 3,
                      onChanged: (value) => reason = value,
                      decoration: accountingInputDecoration(
                        context,
                        hintText: 'Describe why this connection is wrong',
                      ).copyWith(errorText: error),
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
                AccountingButton.outline(
                  context,
                  key: const ValueKey('confirm-match-retraction'),
                  onPressed: () {
                    if (reason.trim().isEmpty) {
                      update(() => error = 'Enter a correction reason.');
                      return;
                    }
                    try {
                      widget.workspace.database.retractStatementMatch(
                        businessId: widget.workspace.identity.businessId,
                        acceptanceId: acceptanceId,
                        actorId: widget.workspace.identity.ownerId,
                        retractedAt: DateTime.now(),
                        reason: reason,
                      );
                      Navigator.pop(dialogContext, true);
                    } catch (failure) {
                      update(
                        () => error = failure is StateError ? failure.message : 'The match could not be retracted. Close and review its current state.',
                      );
                    }
                  },
                  child: const Text('Retract Match'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Widget _acceptedMatch(
    EntityId statementId,
    int sourceRow,
    List<(String, String)> informationRows,
    VoidCallback refresh,
  ) {
    final acceptanceId = widget.workspace.database.statementMatchAcceptanceId(
      widget.workspace.identity.businessId,
      statementId,
      sourceRow,
    );
    return Row(
      key: ValueKey('accepted-match-row-$sourceRow'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            key: ValueKey('accepted-match-details-$sourceRow'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Linked Ledger Movement',
                style: AccountingTypography.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              SelectionArea(
                child: AccountingInformationRows(rows: informationRows),
              ),
              if (widget.workspace.database.isStatementReconciled(
                widget.workspace.identity.businessId,
                statementId,
              )) ...[
                const SizedBox(height: 8),
                Text(
                  'Reopen the approved reconciliation before changing this connection.',
                  style: AccountingTypography.helper(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: accountingContentInset),
        AccountingButton.iconOnly(
          context,
          key: ValueKey('retract-match-$sourceRow'),
          compact: true,
          icon: Icons.link_outlined,
          tone: AccountingTheme.of(context).primary,
          tooltip: 'Retract Match',
          onPressed:
              acceptanceId == null ||
                  widget.workspace.database.isStatementReconciled(
                    widget.workspace.identity.businessId,
                    statementId,
                  )
              ? null
              : () async {
                  if (await _retractMatch(acceptanceId) && mounted) {
                    refresh();
                    widget.workspace.refreshBankStatementReview();
                  }
                },
        ),
      ],
    );
  }

  List<Widget> _createRecordActions(
    BuildContext context,
    BankStatementRow row,
    PaymentAccount account,
    VoidCallback refresh,
  ) => [
    if (row.amount.minorUnits < 0 && widget.onRecordExpense != null)
      AccountingButton.iconOnly(
        context,
        key: ValueKey('missing-record-expense-${row.sourceRow}'),
        onPressed: () async {
          await widget.onRecordExpense!(row, account);
          if (context.mounted) refresh();
        },
        icon: Icons.receipt_long,
        tooltip: 'Record Expense',
      ),
    if (row.amount.minorUnits < 0 && widget.onPaymentVoucher != null)
      AccountingButton.iconOnly(
        context,
        key: ValueKey('missing-payment-voucher-${row.sourceRow}'),
        onPressed: () => widget.onPaymentVoucher!(row, account),
        icon: Icons.assignment_turned_in_outlined,
        tooltip: 'Payment Voucher',
      ),
    if (row.amount.minorUnits > 0 && widget.onReceivePayment != null)
      AccountingButton.iconOnly(
        context,
        key: ValueKey('missing-receive-payment-${row.sourceRow}'),
        onPressed: () async {
          await widget.onReceivePayment!(row, account);
          if (context.mounted) refresh();
        },
        icon: Icons.attach_money,
        tooltip: 'Receive Payment',
      ),
    if (row.amount.minorUnits > 0 && widget.onCreateInvoice != null)
      AccountingButton.iconOnly(
        context,
        key: ValueKey('missing-create-invoice-${row.sourceRow}'),
        onPressed: () => widget.onCreateInvoice!(row, account),
        icon: Icons.note_add_outlined,
        tooltip: 'Create Invoice',
      ),
  ];

  Widget _matchCandidateRow(
    BuildContext context,
    StatementMatchCandidate candidate,
    Money amount,
    int sourceRow,
    VoidCallback onAccept,
    List<Widget> createActions,
  ) => Row(
    key: ValueKey('match-candidate-$sourceRow-${candidate.movementId}'),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: accountingRecordTitleLabelGap,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  candidate.memo,
                  key: ValueKey(
                    'candidate-title-$sourceRow-${candidate.movementId}',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AccountingTypography.value(context)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
                AccountingBadge.build(
                  context,
                  label: 'Suggested',
                  key: ValueKey(
                    'candidate-status-$sourceRow-${candidate.movementId}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: accountingRecordInfoLineGap),
            Text(
              '${formatAccountingInputDate(candidate.date)} · Posted bank movement',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AccountingTypography.helper(context),
            ),
          ],
        ),
      ),
      const SizedBox(width: accountingContentInset),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatAccountingMoney(context, amount),
            style: AccountingTypography.value(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: accountingRecordPriceActionGap),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              ...createActions,
              AccountingButton.iconOnly(
                context,
                key: ValueKey(
                  'accept-match-$sourceRow-${candidate.movementId}',
                ),
                onPressed: onAccept,
                icon: Icons.link_outlined,
                tooltip: 'Accept Match',
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Widget _candidateArrow(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return _BankingCandidateArrow(
      buttonKey: key,
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Future<void> _searchOrCombine(
    EntityId statementId,
    PaymentAccount account,
    BankStatementRow anchor,
    StatementMatchWindow window,
  ) async {
    final statement = widget.workspace.database.bankStatement(
      widget.workspace.identity.businessId,
      statementId,
    )!;
    var from = window == StatementMatchWindow.statement
        ? statement.period.start
        : anchor.date.subtract(
            Duration(days: window == StatementMatchWindow.seven ? 7 : 30),
          );
    var through = window == StatementMatchWindow.statement
        ? statement.period.end
        : anchor.date.add(
            Duration(days: window == StatementMatchWindow.seven ? 7 : 30),
          );
    var query = '';
    final selected = <String>{};
    String? error;
    var warningRevision = 0;
    final controlCount = widget.workspace.database
        .statementMatchSearchCandidates(
          businessId: widget.workspace.identity.businessId,
          statementId: statementId,
          sourceRow: anchor.sourceRow,
        )
        .length;
    final showControls = AccountingRecordControlsPolicy.visible(controlCount);
    List<StatementPostedMovement> search() =>
        widget.workspace.database.statementMatchSearchCandidates(
          businessId: widget.workspace.identity.businessId,
          statementId: statementId,
          sourceRow: anchor.sourceRow,
          query: showControls ? query : '',
          from: showControls ? from : null,
          through: showControls ? through : null,
        );
    var candidates = search();
    BigInt total() => candidates
        .where((record) => selected.contains(record.candidate.movementId))
        .fold<BigInt>(
          BigInt.zero,
          (sum, record) => sum + BigInt.from(record.amount.minorUnits),
        );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final selectedTotal = total();
          final exact =
              selected.isNotEmpty &&
              selectedTotal == BigInt.from(anchor.amount.minorUnits);
          void runSearch() => update(() {
            candidates = search();
            selected.clear();
            error = null;
          });
          return AccountingDialog.alert(
            context,
            widthFamily: AccountingPopoutWidthFamily.normal,
            key: ValueKey('transaction-search-dialog-${anchor.sourceRow}'),
            title: 'Search or Combine',
            preserveTitleCase: true,
            description:
                '${anchor.description} · ${formatAccountingMoney(context, anchor.amount)}',
            maxContentWidth: AccountingPopoutTokens.normalContentWidth,
            formFooter: true,
            content: SizedBox(
              width: AccountingPopoutTokens.normalContentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountingRecordControls(
                    recordCount: controlCount,
                    child: _MatchDateRangeBar(
                      key: ValueKey(
                        'transaction-search-filters-${anchor.sourceRow}',
                      ),
                      keyPrefix: 'transaction-search',
                      alignLabelsToField: true,
                      searchHint: 'Search posted records',
                      from: from,
                      through: through,
                      searchQuery: query,
                      onQueryChanged: (value) {
                        query = value;
                        runSearch();
                      },
                      onRun: (start, end) {
                        from = start;
                        through = end;
                        runSearch();
                      },
                    ),
                  ),
                  if (showControls)
                    const SizedBox(height: accountingContentInset),
                  AccountingRecordList(
                    paginationKey: 'banking-transaction-search',
                    totalCount: controlCount,
                    key: const ValueKey('transaction-search-list'),
                    children: [
                      if (candidates.isEmpty)
                        Padding(
                          padding: accountingContentPadding,
                          child: Text(
                            'No posted records match these filters.',
                            style: AccountingTypography.helper(context),
                          ),
                        ),
                      for (final record in candidates)
                        AccountingRecordRow(
                          key: ValueKey(
                            'transaction-search-record-${record.candidate.movementId}',
                          ),
                          leading: AccountingLeadingCheckbox(
                            checkboxKey: ValueKey(
                              'transaction-select-${anchor.sourceRow}-${record.candidate.movementId}',
                            ),
                            value: selected.contains(
                              record.candidate.movementId,
                            ),
                            onChanged: (value) => update(() {
                              if (value == true) {
                                selected.add(record.candidate.movementId);
                              } else {
                                selected.remove(record.candidate.movementId);
                              }
                            }),
                            semanticLabel: 'Select ${record.candidate.memo}',
                          ),
                          leadingOverlaysTitle: true,
                          title: record.candidate.memo,
                          details: Text(
                            '${formatAccountingInputDate(record.candidate.date)} · Posted bank movement',
                          ),
                          trailing: Text(
                            formatAccountingMoney(context, record.amount),
                            style: AccountingTypography.value(context),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: accountingContentInset),
                  const SizedBox(height: accountingContentInset),
                  Text(
                    '${selected.length} selected · ${(selectedTotal.abs() > BigInt.parse('9223372036854775807') ? 'Total exceeds supported amount' : formatAccountingMoney(context, Money.fromMinor(selectedTotal.toInt(), anchor.amount.currency)))} of ${formatAccountingMoney(context, anchor.amount)}',
                    key: const ValueKey('transaction-search-total'),
                    style: AccountingTypography.helper(context),
                  ),
                  if (error != null)
                    AccountingAlert.build(
                      context,
                      key: ValueKey(
                        'transaction-search-warning-$warningRevision',
                      ),
                      title: 'Check Selected Records',
                      description: error!,
                      tone: AccountingAlertTone.warning,
                      topGap: accountingContentInset,
                    ),
                ],
              ),
            ),
            actions: [
              AccountingButton.ghost(
                context,
                key: const ValueKey('cancel-transaction-search'),
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              AccountingButton.primary(
                context,
                key: const ValueKey('confirm-transaction-match'),
                onPressed: !exact
                    ? null
                    : () {
                        try {
                          widget.workspace.database
                              .acceptStatementCombinedMatch(
                                businessId:
                                    widget.workspace.identity.businessId,
                                statementId: statementId,
                                sourceRow: anchor.sourceRow,
                                movementIds: selected,
                                actorId: widget.workspace.identity.ownerId,
                                acceptedAt: DateTime.now(),
                              );
                          widget.workspace.refreshBankStatementReview();
                          Navigator.pop(dialogContext);
                        } catch (caught) {
                          update(() {
                            warningRevision++;
                            error = caught is StateError ? caught.message : 'The selected records could not be matched. Reload and check their total.';
                          });
                        }
                      },
                child: Text(
                  selected.length > 1 ? 'Combine and Match' : 'Match',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _matches(
    EntityId statementId,
    PaymentAccount account, {
    int? onlySourceRow,
  }) async {
    try {
      final statement = widget.workspace.database.bankStatement(
        widget.workspace.identity.businessId,
        statementId,
      )!;
      var window =
          _matchingWindows[statementId.value] ?? StatementMatchWindow.seven;
      List<StatementRowSuggestions> suggestions() =>
          widget.workspace.database.statementMatchSuggestions(
            widget.workspace.identity.businessId,
            statementId,
            window: window,
          );
      var rows = suggestions();
      var accepted = widget.workspace.database.acceptedStatementMatches(
        widget.workspace.identity.businessId,
        statementId,
      );
      var journals = widget.workspace.database.journalMatchHeaders(
        widget.workspace.identity.businessId,
        statementId,
      );
      if (!mounted) return;
      var query = '';
      DateTime? from;
      DateTime? through;
      var offset = 0;
      var pageSize = AccountingRecordPageSizes.read('match');
      String? error;
      final candidateOffsets = <int, int>{};
      DateTime day(DateTime date) =>
          DateTime.utc(date.year, date.month, date.day);
      setState(() {
        _selectStatement(account.id, statementId.value);
        _activeReconciliation = null;
        _activeMatchReview = StatefulBuilder(
          builder: (context, update) {
            bool matchesText(StatementRowSuggestions item) {
              final needle = query.trim().toLowerCase();
              if (needle.isEmpty ||
                  '${item.row.description} ${item.row.reference}'
                      .toLowerCase()
                      .contains(needle) ||
                  item.candidates.any(
                    (candidate) =>
                        candidate.memo.toLowerCase().contains(needle),
                  )) {
                return true;
              }
              final acceptance = widget.workspace.database
                  .statementMatchAcceptanceId(
                    widget.workspace.identity.businessId,
                    statementId,
                    item.row.sourceRow,
                  );
              if (acceptance == null) return false;
              return widget.workspace.database
                  .statementMatchLedgerMembers(
                    widget.workspace.identity.businessId,
                    acceptance,
                  )
                  .any(
                    (id) =>
                        journals[id.split(':').first]?.memo
                            .toLowerCase()
                            .contains(needle) ??
                        false,
                  );
            }

            final visible = rows
                .where(
                  (item) =>
                      (onlySourceRow == null ||
                          item.row.sourceRow == onlySourceRow) &&
                      (!AccountingRecordControlsPolicy.visible(rows.length) ||
                          matchesText(item)) &&
                      (!AccountingRecordControlsPolicy.visible(rows.length) ||
                          from == null ||
                          !day(item.row.date).isBefore(day(from!))) &&
                      (!AccountingRecordControlsPolicy.visible(rows.length) ||
                          through == null ||
                          !day(item.row.date).isAfter(day(through!))),
                )
                .toList();
            Future<void> refresh() async {
              final latest = widget.workspace.database.journalMatchHeaders(
                widget.workspace.identity.businessId,
                statementId,
              );
              if (!context.mounted) return;
              update(() {
                journals = latest;
                rows = suggestions();
                accepted = widget.workspace.database.acceptedStatementMatches(
                  widget.workspace.identity.businessId,
                  statementId,
                );
                candidateOffsets.clear();
                error = null;
              });
            }

            void cycleWindow() => update(() {
              window = window.next;
              _matchingWindows[statementId.value] = window;
              rows = suggestions();
              candidateOffsets.clear();
              offset = 0;
              error = null;
            });
            final headerSourceRow =
                onlySourceRow ?? statement.rows.first.sourceRow;
            final headerActions = Wrap(
              spacing: accountingRecordIconGap,
              runSpacing: accountingRecordIconGap,
              children: [
                _moreMenu(context, 'review-more', [
                  _menuItem(context, 'Refresh Matches', Icons.restore, refresh),
                  _menuItem(
                    context,
                    'Match History',
                    Icons.preview_outlined,
                    () => _matchHistory(statementId),
                  ),
                  _menuItem(
                    context,
                    'Imported Statements',
                    Icons.folder_open_outlined,
                    _returnToDocuments,
                  ),
                  _menuItem(
                    context,
                    'View Original',
                    Icons.visibility_outlined,
                    () => _viewOriginalStatement(statement),
                  ),
                  _menuItem(
                    context,
                    'Download Original',
                    Icons.download_outlined,
                    () => _saveOriginalStatement(statement),
                  ),
                  AccountingOverflowAction(
                    key: const ValueKey('review-open-reconciliation'),
                    label: 'Reconciliation',
                    icon: Icons.sync,
                    iconAsset: '080-sync.svg',
                    onPressed: () => _openReconciliation(statementId, account),
                  ),
                  _menuItem(
                    context,
                    'Add Bank Account',
                    Icons.savings_outlined,
                    _add,
                  ),
                  _menuItem(
                    context,
                    'Account Settings',
                    Icons.settings_outlined,
                    () => _editAccount(account),
                  ),
                  if (_links[account.id] == null)
                    _menuItem(
                      context,
                      'Link Ledger Account',
                      Icons.link_off_outlined,
                      () => _link(account),
                    ),
                ]),
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('matching-window-switch'),
                  compact: true,
                  onPressed: cycleWindow,
                  icon: Icons.calendar_today_outlined,
                  iconAsset: window.iconAsset,
                  iconPaintedSizeAdjustment: 1,
                  tooltip: window.nextTooltip,
                ),
                AccountingCompactChoiceMenu<String>(
                  triggerKey: const ValueKey('review-account-switcher'),
                  tooltip: 'Change Account',
                  iconAsset: '086-change-account-normalized.svg',
                  value: account.id,
                  options: [
                    for (final bank in _bankAccounts)
                      AccountingSelectorOption(
                        value: bank.id,
                        label: bank.shortName,
                        key: ValueKey('review-account-option-${bank.id}'),
                        preserveLabelCase: true,
                      ),
                  ],
                  onChanged: (value) =>
                      _switchReviewAccount(value, reconciliation: false),
                ),
                AccountingCompactChoiceMenu<String>(
                  triggerKey: ValueKey(
                    'review-statement-switcher-$headerSourceRow',
                  ),
                  tooltip: 'Change Statement',
                  iconAsset: '077-change-statement.svg',
                  value: statementId.value,
                  options: [
                    for (final item in _statementsByPayment[account.id] ?? [])
                      AccountingSelectorOption(
                        value: item.id.value,
                        label: item.statement.filename,
                        key: ValueKey(
                          'review-statement-option-${item.id.value}',
                        ),
                        preserveLabelCase: true,
                      ),
                  ],
                  onChanged: (value) =>
                      _matches(EntityId.parse(value), account),
                ),
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('review-back-to-documents'),
                  compact: true,
                  onPressed: _returnToDocuments,
                  icon: Icons.undo,
                  tooltip: 'Back to Imported Statements',
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountingRecordControls(
                  recordCount: rows.length,
                  child: _MatchDateRangeBar(
                    key: ValueKey('match-date-range-${statementId.value}'),
                    from: from ?? statement.period.start,
                    through: through ?? statement.period.end,
                    searchQuery: query,
                    onQueryChanged: (value) => update(() {
                      query = value;
                      offset = 0;
                    }),
                    onRun: (start, end) => update(() {
                      from = start;
                      through = end;
                      offset = 0;
                    }),
                  ),
                ),
                if (AccountingRecordControlsPolicy.visible(rows.length))
                  const SizedBox(height: accountingContentInset),
                AccountingCard.surface(
                  context,
                  key: const ValueKey('statement-match-file-header'),
                  child: Padding(
                    padding: accountingContentPadding,
                    child: accountingHeaderBody(
                      minimumTitleWidth: AccountingResponsive.measuredTextWidth(
                        context,
                        statement.filename,
                        AccountingTypography.sectionTitle(context),
                      ),
                      centerInline: true,
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statement.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AccountingTypography.sectionTitle(context),
                          ),
                          const SizedBox(height: accountingRecordInfoLineGap),
                          Text(
                            account.name,
                            style: AccountingTypography.helper(context),
                          ),
                        ],
                      ),
                      actions: headerActions,
                    ),
                  ),
                ),
                if (error != null)
                  AccountingAlert.build(
                    context,
                    title: 'Match Review',
                    description: error!,
                    tone: AccountingAlertTone.warning,
                    topGap: accountingContentInset,
                  ),
                for (final item in visible.skip(offset).take(pageSize)) ...[
                  const SizedBox(height: 10),
                  AccountingCard.surface(
                    context,
                    key: ValueKey('statement-match-card-${item.row.sourceRow}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: accountingContentPadding,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  key: ValueKey(
                                    'statement-match-info-${item.row.sourceRow}',
                                  ),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: accountingRecordTitleLabelGap,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          item.row.description,
                                          key: ValueKey(
                                            'statement-match-title-${item.row.sourceRow}',
                                          ),
                                          style:
                                              AccountingTypography.value(
                                                context,
                                              ).copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        AccountingBadge.build(
                                          context,
                                          key: ValueKey(
                                            'statement-match-status-${item.row.sourceRow}',
                                          ),
                                          label:
                                              accepted.containsKey(
                                                item.row.sourceRow,
                                              )
                                              ? 'Matched'
                                              : 'Unmatched',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                      height: accountingRecordInfoLineGap,
                                    ),
                                    Text(
                                      '${formatAccountingInputDate(item.row.date)}${item.row.reference.isEmpty ? '' : ' · ${item.row.reference}'}${!accepted.containsKey(item.row.sourceRow) && item.candidates.length > 1 ? ' — ${(candidateOffsets[item.row.sourceRow] ?? 0) + 1} of ${item.candidates.length} suggested matches' : ''}',
                                      style: AccountingTypography.helper(
                                        context,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: accountingContentInset),
                              Text(
                                formatAccountingMoney(context, item.row.amount),
                                key: ValueKey(
                                  'statement-match-amount-${item.row.sourceRow}',
                                ),
                                style: AccountingTypography.value(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: accountingContentInset,
                          endIndent: accountingContentInset,
                        ),
                        AccountingButtonSizeScope(
                          child: Padding(
                            key: ValueKey(
                              'match-detail-padding-${item.row.sourceRow}',
                            ),
                            padding: accountingContentPadding,
                            child: Builder(
                              builder: (context) {
                                final row = item.row;
                                if (accepted.containsKey(row.sourceRow)) {
                                  final acceptance = widget.workspace.database
                                      .statementMatchAcceptanceId(
                                        widget.workspace.identity.businessId,
                                        statementId,
                                        row.sourceRow,
                                      )!;
                                  final members = widget.workspace.database
                                      .statementMatchLedgerMembers(
                                        widget.workspace.identity.businessId,
                                        acceptance,
                                      );
                                  return _acceptedMatch(
                                    statementId,
                                    row.sourceRow,
                                    [
                                      for (final id in members) ...[
                                        ('Journal Movement', id),
                                        if (journals[id.split(':').first]
                                            case final journal?) ...[
                                          (
                                            'Posting Date',
                                            formatAccountingInputDate(
                                              journal.date,
                                            ),
                                          ),
                                          ('Memo', journal.memo),
                                        ],
                                      ],
                                      (
                                        'Amount',
                                        formatAccountingMoney(
                                          context,
                                          row.amount,
                                        ),
                                      ),
                                    ],
                                    () => refresh(),
                                  );
                                }
                                final createActions = [
                                  AccountingButton.iconOnly(
                                    context,
                                    key: ValueKey(
                                      'search-or-combine-${row.sourceRow}',
                                    ),
                                    onPressed: () async {
                                      await _searchOrCombine(
                                        statementId,
                                        account,
                                        row,
                                        window,
                                      );
                                      await refresh();
                                    },
                                    icon: Icons.preview_outlined,
                                    iconAsset: '072-preview.svg',
                                    iconPaintedSizeAdjustment: 1,
                                    tooltip: 'Search or Combine',
                                  ),
                                  ..._createRecordActions(
                                    context,
                                    row,
                                    account,
                                    () => refresh(),
                                  ),
                                ];
                                if (item.candidates.isEmpty) {
                                  return Row(
                                    key: ValueKey(
                                      'no-suggestion-row-${row.sourceRow}',
                                    ),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'No Suggested Match',
                                          style:
                                              AccountingTypography.fieldLabel(
                                                context,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: accountingContentInset,
                                      ),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: createActions,
                                      ),
                                    ],
                                  );
                                }
                                final index = math.min(
                                  candidateOffsets[row.sourceRow] ?? 0,
                                  item.candidates.length - 1,
                                );
                                final candidate = item.candidates[index];
                                return Row(
                                  children: [
                                    if (item.candidates.length > 1)
                                      _candidateArrow(
                                        context,
                                        key: ValueKey(
                                          'previous-candidates-${row.sourceRow}',
                                        ),
                                        icon: Icons.chevron_left_rounded,
                                        tooltip: 'Previous Suggested Match',
                                        onPressed: index == 0
                                            ? null
                                            : () => update(
                                                () =>
                                                    candidateOffsets[row
                                                            .sourceRow] =
                                                        index - 1,
                                              ),
                                      ),
                                    Expanded(
                                      child: _matchCandidateRow(
                                        context,
                                        candidate,
                                        row.amount,
                                        row.sourceRow,
                                        () {
                                          try {
                                            widget.workspace.database
                                                .acceptStatementMatch(
                                                  businessId: widget
                                                      .workspace
                                                      .identity
                                                      .businessId,
                                                  statementId: statementId,
                                                  sourceRow: row.sourceRow,
                                                  journalId:
                                                      candidate.journalId,
                                                  lineIndex:
                                                      candidate.lineIndex,
                                                  actorId: widget
                                                      .workspace
                                                      .identity
                                                      .ownerId,
                                                  acceptedAt: DateTime.now(),
                                                );
                                            refresh();
                                            widget.workspace
                                                .refreshBankStatementReview();
                                          } catch (caught) {
                                            update(
                                              () => error = caught is StateError
                                                  ? caught.message
                                                  : 'This match could not be accepted.',
                                            );
                                          }
                                        },
                                        createActions,
                                      ),
                                    ),
                                    if (item.candidates.length > 1)
                                      _candidateArrow(
                                        context,
                                        key: ValueKey(
                                          'next-candidates-${row.sourceRow}',
                                        ),
                                        icon: Icons.chevron_right_rounded,
                                        tooltip: 'Next Suggested Match',
                                        onPressed:
                                            index + 1 >= item.candidates.length
                                            ? null
                                            : () => update(
                                                () =>
                                                    candidateOffsets[row
                                                            .sourceRow] =
                                                        index + 1,
                                              ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (visible.isEmpty)
                  Padding(
                    padding: accountingContentPadding,
                    child: Text(
                      'No bank transactions match these filters.',
                      style: AccountingTypography.helper(context),
                    ),
                  ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: accountingContentInset),
                  child: AccountingRecordPagination(
                    keyPrefix: 'match',
                    unfilteredTotal: rows.length,
                    total: visible.length,
                    offset: offset,
                    pageSize: pageSize,
                    onPageSizeChanged: (value) => update(() {
                      pageSize = value;
                      offset = 0;
                    }),
                    onPrevious: offset == 0
                        ? null
                        : () => update(
                            () => offset = math.max(0, offset - pageSize),
                          ),
                    onNext: offset + pageSize >= visible.length
                        ? null
                        : () => update(() => offset += pageSize),
                  ),
                ),
              ],
            );
          },
        );
      });
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              caught is StateError ? caught.message : 'Matches could not be opened. Check the statement and ledger link.',
            ),
          ),
        );
      }
    }
  }

  Widget _importedStatements(BuildContext context, PaymentAccount account) {
    final all = [...?_statementsByPayment[account.id]]
      ..sort((a, b) {
        final start = a.statement.period.start.compareTo(
          b.statement.period.start,
        );
        if (start != 0) return start;
        final end = a.statement.period.end.compareTo(b.statement.period.end);
        if (end != 0) return end;
        final name = a.statement.filename.compareTo(b.statement.filename);
        return name != 0 ? name : a.id.value.compareTo(b.id.value);
      });
    final showControls = AccountingRecordControlsPolicy.visible(all.length);
    final imports = all.where((item) {
      if (!showControls) return true;
      final period = item.statement.period;
      return item.statement.filename.toLowerCase().contains(
            _documentQuery.trim().toLowerCase(),
          ) &&
          (_documentFrom == null || !period.end.isBefore(_documentFrom!)) &&
          (_documentThrough == null ||
              !period.start.isAfter(_documentThrough!));
    }).toList();
    final from = all.isEmpty
        ? DateTime.now()
        : all.first.statement.period.start;
    final through = all.isEmpty
        ? from
        : all
              .map((item) => item.statement.period.end)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingRecordControls(
          recordCount: all.length,
          child: _MatchDateRangeBar(
            key: ValueKey('document-filters-${account.id}'),
            searchHint: 'Search imported statements',
            from: _documentFrom ?? from,
            through: _documentThrough ?? through,
            searchQuery: _documentQuery,
            onQueryChanged: (query) => setState(() => _documentQuery = query),
            onRun: (from, through) => setState(() {
              _documentFrom = from;
              _documentThrough = through;
            }),
          ),
        ),
        if (showControls) const SizedBox(height: accountingContentInset),
        AccountingCard.surface(
          context,
          key: const ValueKey('imported-statements-header'),
          child: AccountingRecordRow(
            title: 'Imported Statements',
            titleStyle: AccountingTypography.sectionTitle(context),
            details: Text(account.name),
            trailing: AccountingRecordActions(
              trailing: [
                _accountMoreMenu(context, account),
                _bankChoice(
                  context,
                  account,
                  keyPrefix: 'documents',
                  onChanged: (id) => _switchDocumentAccount(id),
                ),
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('documents-add-bank'),
                  compact: true,
                  onPressed: _add,
                  icon: Icons.savings_outlined,
                  iconAsset: '075-account-grouping.svg',
                  iconPaintedSizeAdjustment: 1,
                  tooltip: 'Add Bank Account',
                ),
                AccountingButton.iconOnly(
                  context,
                  key: const ValueKey('documents-account-settings'),
                  compact: true,
                  onPressed: () => _editAccount(account),
                  icon: Icons.settings_outlined,
                  iconAsset: '082-banking-setting.svg',
                  tooltip: 'Account Settings',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        AccountingRecordList(
          paginationKey: 'imported-statements-${account.id}',
          totalCount: all.length,
          key: ValueKey('imported-statements-${account.id}'),
          children: [
            if (imports.isEmpty)
              Padding(
                padding: accountingContentPadding,
                child: Text(
                  all.isEmpty
                      ? 'No statements imported yet.'
                      : 'No statements match these filters.',
                  style: AccountingTypography.helper(context),
                ),
              ),
            for (final item in imports)
              AccountingRecordRow(
                title: item.statement.filename,
                minimumDetailsWidth: 240,
                titleKey: ValueKey('statement-filename-${item.id.value}'),
                status: AccountingBadge.build(
                  context,
                  label:
                      widget.workspace.database.isStatementReconciled(
                        widget.workspace.identity.businessId,
                        item.id,
                      )
                      ? 'Reconciled'
                      : 'Awaiting Approval',
                ),
                details: Text(
                  '${formatAccountingInputDate(item.statement.period.start)} – ${formatAccountingInputDate(item.statement.period.end)}',
                  key: ValueKey('statement-period-${item.id.value}'),
                ),
                trailing: AccountingRecordActions(
                  trailing: [
                    _documentMoreMenu(
                      context,
                      item.id,
                      item.statement,
                      includeMatchHistory: false,
                    ),
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey('statement-matches-${item.id.value}'),
                      onPressed: () => _matches(item.id, account),
                      icon: Icons.link_outlined,
                      tooltip: 'Review Statement Connections',
                    ),
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey('statement-history-${item.id.value}'),
                      onPressed: () => _matchHistory(item.id),
                      icon: Icons.preview_outlined,
                      iconAsset: '078-match-history.svg',
                      tooltip: 'Match History',
                    ),
                    AccountingButton.iconOnly(
                      context,
                      key: ValueKey('reconcile-statement-${item.id.value}'),
                      onPressed: () => _openReconciliation(item.id, account),
                      iconAsset: '080-sync.svg',
                      icon: Icons.sync,
                      tooltip: 'Reconcile Statement',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openAccountReconciliation(PaymentAccount account) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StatementReconciliationDialog.account(
        workspace: widget.workspace,
        paymentAccountId: account.id,
        currency: account.currency.code,
        sourceLabel: account.shortName,
        onRecordExpense: widget.onReconciliationExpense == null
            ? null
            : (date) => widget.onReconciliationExpense!(account, date),
        onReceivePayment:
            widget.onReconciliationPayment == null ||
                account.type == PaymentAccountType.card
            ? null
            : (date) => widget.onReconciliationPayment!(account, date),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _accountReconciliationHistory(PaymentAccount account) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ReconciliationHistoryDialog.account(
        workspace: widget.workspace,
        paymentAccountId: account.id,
      ),
    );
    if (mounted) await _load();
  }

  Widget _accountMoreMenu(BuildContext context, PaymentAccount account) =>
      _moreMenu(context, 'imported-account-more', [
        if (_links[account.id] != null)
          _menuItem(
            context,
            'Reconcile Account',
            Icons.sync,
            () => _openAccountReconciliation(account),
          ),
        _menuItem(
          context,
          'Reconciliation History',
          Icons.history_outlined,
          () => _accountReconciliationHistory(account),
        ),
        _menuItem(context, 'Refresh Documents', Icons.restore, _load),
        if (_links[account.id] == null)
          _menuItem(
            context,
            'Link Ledger Account',
            Icons.link_off_outlined,
            () => _link(account),
          ),
      ]);

  Widget _documentMoreMenu(
    BuildContext context,
    EntityId id,
    BankStatementImport statement, {
    bool includeMatchHistory = true,
  }) => _moreMenu(context, 'document-more-${id.value}', [
    _menuItem(
      context,
      'View Original',
      Icons.visibility_outlined,
      () => _viewOriginalStatement(statement),
    ),
    _menuItem(
      context,
      'Download Original',
      Icons.download_outlined,
      () => _saveOriginalStatement(statement),
    ),
    if (includeMatchHistory)
      _menuItem(
        context,
        'Match History',
        Icons.preview_outlined,
        () => _matchHistory(id),
      ),
    _menuItem(
      context,
      'Reconciliation History',
      Icons.history_outlined,
      () => showDialog<void>(
        context: context,
        builder: (_) => ReconciliationHistoryDialog(
          workspace: widget.workspace,
          statementId: id,
        ),
      ),
    ),
  ]);

  Widget _moreMenu(
    BuildContext context,
    String key,
    List<AccountingOverflowAction> items,
  ) => AccountingOverflowMenu(
    triggerKey: ValueKey(key),
    actions: items,
    compact: true,
    tooltip: 'More Options',
    maxHeight: 520,
    bordered: true,
  );

  AccountingOverflowAction _menuItem(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) => AccountingOverflowAction(
    key: ValueKey(switch (label) {
      'Match History' => 'show-match-history',
      'Imported Statements' => 'review-imported-statements',
      'View Original' => 'review-view-statement',
      'Download Original' => 'review-download-statement',
      'Add Bank Account' => 'review-add-bank-account',
      'Account Settings' => 'review-edit-bank-account',
      _ => 'menu-$label',
    }),
    label: label,
    icon: icon,
    onPressed: onPressed,
    iconAsset: switch (label) {
      'Match History' => '078-match-history.svg',
      'Imported Statements' => '079-import-export.svg',
      'View Original' => '036-eye.svg',
      'Add Bank Account' => '075-account-grouping.svg',
      'Account Settings' => '082-banking-setting.svg',
      _ => null,
    },
    iconPaintedSizeAdjustment: switch (label) {
      'Imported Statements' || 'View Original' || 'Add Bank Account' => 1,
      _ => 0,
    },
  );

  void _returnToDocuments() => setState(() {
    _activeMatchReview = null;
    _activeReconciliation = null;
    widget.selectedStatementId?.value = null;
  });

  Future<void> _add() async {
    final account = await showPaymentAccountDialog(
      context,
      preferredCurrencyCode: widget.workspace.identity.currency,
      newId: () => EntityId.random().value,
      buildLabel: (context, label, required) =>
          accountingFieldLabel(context, label, alignToField: true),
    );
    if (account == null || !mounted) return;
    try {
      widget.workspace.savePaymentAccount(account);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account could not be saved. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _editAccount(PaymentAccount payment) async {
    final updated = await showPaymentAccountDialog(
      context,
      preferredCurrencyCode: payment.currency.code,
      newId: () => payment.id,
      initial: payment,
      buildLabel: (context, label, required) =>
          accountingFieldLabel(context, label, alignToField: true),
    );
    if (updated == null || !mounted) return;
    try {
      widget.workspace.savePaymentAccount(updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account details could not be saved.')),
        );
      }
    }
  }

  Future<void> _link(PaymentAccount payment) async {
    final expected = payment.type == PaymentAccountType.card
        ? AccountType.liability
        : AccountType.asset;
    final options =
        _chart.values
            .where(
              (a) =>
                  a.type == expected &&
                  a.status == AccountStatus.active &&
                  !a.isParent &&
                  !_links.values.contains(a.id),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    EntityId? selected;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.normal,
          title: 'Link Ledger Account',
          maxContentWidth: AccountingPopoutTokens.normalContentWidth,
          fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
          formFooter: true,
          description:
              '${payment.displayLabel}. Choose the dedicated ledger account for these bank or card movements.',
          content: SizedBox(
            width: AccountingPopoutTokens.normalContentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (payment.currency.code != widget.workspace.identity.currency)
                  Text(
                    'Foreign-currency linking requires an exchange-rate policy and is not available yet.',
                    style: AccountingTypography.helper(context),
                  )
                else if (options.isEmpty)
                  Text(
                    'Create an active posting account of the appropriate type in Accounting first.',
                    style: AccountingTypography.helper(context),
                  )
                else ...[
                  AccountingOrdinaryFields(
                    key: const ValueKey('banking-ledger-fields'),
                    fields: [
                      AccountingOrdinaryFieldSlot(
                        label: 'Ledger Account',
                        hasGuidance: true,
                        choices: [
                          'Select Ledger Account',
                          for (final a in options) a.displayName,
                        ],
                        builder: (assignedWidth) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            accountingFieldLabel(
                              context,
                              'Ledger Account',
                              alignToField: true,
                              guidance: 'Confirm this account carefully. The link is retained for accounting history and cannot be reassigned here.',
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            AccountingSelector<EntityId>(
                              assignedWidth: assignedWidth,
                              options: [
                                for (final a in options)
                                  AccountingSelectorOption(
                                    value: a.id,
                                    label: a.displayName,
                                    preserveLabelCase: true,
                                  ),
                              ],
                              value: selected,
                              onChanged: (value) =>
                                  update(() => selected = value),
                              hintText: 'Select Ledger Account',
                              triggerKey: const ValueKey(
                                'banking-ledger-selector',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: AccountingTypography.helper(context)),
                ],
              ],
            ),
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: null,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('banking-confirm-link'),
              onPressed:
                  selected == null ||
                      payment.currency.code !=
                          widget.workspace.identity.currency
                  ? null
                  : () {
                      try {
                        widget.workspace.database.linkPaymentLedgerAccount(
                          widget.workspace.identity.businessId,
                          payment.id,
                          selected!,
                        );
                        Navigator.pop(dialogContext);
                        _load();
                      } catch (_) {
                        update(
                          () => error = 'The link could not be saved. Check that both accounts are still available and unlinked.',
                        );
                      }
                    },
              child: const Text('Confirm Link'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountSummary(BuildContext context, PaymentAccount payment) {
    final tokens = AccountingTheme.of(context);
    final balance = _ledgerBalances[payment.id];
    final amount = balance == null
        ? 'Unavailable'
        : formatAccountingMoney(context, balance);
    final balanceLabel = switch (payment.type) {
      PaymentAccountType.bank => 'Bank Balance',
      PaymentAccountType.other => 'Account Balance',
      _ => '${payment.type.label} Balance',
    };
    final labels = [balanceLabel, 'Unmatched', 'Awaiting Approval'];
    final values = [
      amount,
      '${_unresolved[payment.id] ?? 0} transaction${_unresolved[payment.id] == 1 ? '' : 's'}',
      '${_awaitingApproval[payment.id] ?? 0} statement${_awaitingApproval[payment.id] == 1 ? '' : 's'}',
    ];
    final icons = [
      Icons.account_balance_outlined,
      Icons.link_off_outlined,
      Icons.fact_check_outlined,
    ];
    final valueFontSize = amount.length > 15 ? 16.0 : 17.0;
    final labelStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: tokens.mutedForeground, height: 1);
    final valueStyle = AccountingTypography.value(
      context,
    ).copyWith(fontSize: valueFontSize, fontWeight: FontWeight.w600, height: 1);
    VoidCallback? metricAction(int index) {
      if (index == 0) return null;
      for (final item in _statementsByPayment[payment.id] ?? []) {
        if (index == 1 &&
            item.statement.rows.length >
                (_acceptedByStatement[item.id.value]?.length ?? 0)) {
          return () => _matches(item.id, payment);
        }
        if (index == 2 &&
            !widget.workspace.database.isStatementReconciled(
              widget.workspace.identity.businessId,
              item.id,
            )) {
          return () => _openReconciliation(item.id, payment);
        }
      }
      return null;
    }

    final widths = [
      for (var i = 0; i < labels.length; i++)
        accountingMetricIconExtent +
            12 +
            math.min(
              160,
              math.max(
                AccountingResponsive.measuredTextWidth(
                  context,
                  labels[i],
                  labelStyle,
                ),
                AccountingResponsive.measuredTextWidth(
                  context,
                  values[i],
                  valueStyle,
                ),
              ),
            ) +
            (i == 0 && _bankAccounts.length > 1 ? 40 : 0),
    ];
    Widget metric(int index) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountingMetricIconBox(
          icons[index],
          iconSize: switch (icons[index]) {
            Icons.account_balance_outlined || Icons.link_off_outlined => 19,
            _ => 21,
          },
          onPressed: metricAction(index),
          tooltip: 'Open ${labels[index]}',
          fillColor: switch (index) {
            1 => AccountingColorLibrary.grapefruit,
            2 => AccountingColorLibrary.sunflowerDeep,
            _ => null,
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: metricAction(index),
            behavior: HitTestBehavior.opaque,
            child: AccountingMetricTextGroup(
              label: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
              value: Text(
                values[index],
                key: index == 1
                    ? ValueKey('banking-unresolved-${payment.id}')
                    : index == 2
                    ? ValueKey('banking-awaiting-approval-${payment.id}')
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
            ),
          ),
        ),
        if (index == 0 && _bankAccounts.length > 1) ...[
          const SizedBox(width: 8),
          AccountingCompactChoiceMenu<String>(
            triggerKey: const ValueKey('banking-account-switcher'),
            tooltip: 'Select bank account',
            value: payment.id,
            options: [
              for (final account in _bankAccounts)
                AccountingSelectorOption(
                  value: account.id,
                  label: account.shortName,
                  key: ValueKey('banking-account-option-${account.id}'),
                  preserveLabelCase: true,
                ),
            ],
            onChanged: (id) {
              if (_activeReconciliation != null) {
                _switchReviewAccount(id, reconciliation: true);
              } else if (_activeMatchReview != null) {
                _switchReviewAccount(id, reconciliation: false);
              } else {
                setState(() {
                  _selectedPaymentId = id;
                  _documentQuery = '';
                  _documentFrom = null;
                  _documentThrough = null;
                });
              }
            },
          ),
        ],
      ],
    );
    final minimumWidth =
        widths.reduce((a, b) => a + b) +
        accountingContentInset * 6 +
        AccountingResponsive.groupGap * 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minimumWidth) {
          final columns = AccountingResponsive.balancedColumnCount(
            constraints.maxWidth,
            2,
            minItemWidth:
                math.max(widths[0], widths[1]) + accountingContentInset * 2,
          );
          final cardWidth =
              (constraints.maxWidth -
                  (columns - 1) * AccountingResponsive.groupGap) /
              columns;
          return Wrap(
            spacing: AccountingResponsive.groupGap,
            runSpacing: AccountingResponsive.groupGap,
            children: [
              // Banking retains the two primary metrics when the full row
              // cannot fit. Approval remains available on each statement.
              for (var index = 0; index < 2; index++)
                SizedBox(
                  width: cardWidth,
                  child: AccountingCard.surface(
                    context,
                    key: ValueKey('banking-account-${payment.id}-$index'),
                    child: Padding(
                      padding: accountingContentPadding,
                      child: metric(index),
                    ),
                  ),
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              if (index > 0)
                const SizedBox(width: AccountingResponsive.groupGap),
              Expanded(
                flex: (widths[index] + accountingContentInset * 2).ceil(),
                child: AccountingCard.surface(
                  context,
                  key: ValueKey('banking-account-${payment.id}-$index'),
                  child: Padding(
                    padding: accountingContentPadding,
                    child: metric(index),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  ({EntityId id, BankStatementImport statement})? _selectedStatement(
    PaymentAccount payment,
  ) {
    final imports = _statementsByPayment[payment.id];
    if (imports == null || imports.isEmpty) return null;
    for (final item in imports) {
      if (item.id.value ==
          (_selectedStatementIds[payment.id] ??
              widget.selectedStatementId?.value)) {
        return item;
      }
    }
    return imports.first;
  }

  PaymentAccount? _paymentById(String? id) {
    for (final payment in _payments ?? <PaymentAccount>[]) {
      if (payment.id == id) return payment;
    }
    return null;
  }

  void _switchReviewAccount(String accountId, {required bool reconciliation}) {
    final payment = _paymentById(accountId);
    if (payment == null) return;
    final selected = _selectedStatement(payment);
    if (selected == null) {
      setState(() {
        _selectedPaymentId = accountId;
        _activeMatchReview = null;
        _activeReconciliation = null;
        _documentQuery = '';
        _documentFrom = null;
        _documentThrough = null;
        widget.selectedStatementId?.value = null;
      });
      return;
    }
    if (reconciliation) {
      _openReconciliation(selected.id, payment);
    } else {
      _matches(selected.id, payment);
    }
  }

  void _switchDocumentAccount(String id) => setState(() {
    _selectedPaymentId = id;
    _documentQuery = '';
    _documentFrom = null;
    _documentThrough = null;
    widget.selectedStatementId?.value = null;
  });

  Widget _bankChoice(
    BuildContext context,
    PaymentAccount payment, {
    required String keyPrefix,
    required ValueChanged<String> onChanged,
  }) => AccountingCompactChoiceMenu<String>(
    triggerKey: ValueKey('$keyPrefix-account-switcher'),
    tooltip: 'Switch Bank',
    iconAsset: '086-change-account-normalized.svg',
    value: payment.id,
    options: [
      for (final bank in _bankAccounts)
        AccountingSelectorOption(
          value: bank.id,
          label: bank.shortName,
          key: ValueKey('$keyPrefix-account-option-${bank.id}'),
          preserveLabelCase: true,
        ),
    ],
    onChanged: onChanged,
  );

  List<Widget> _reconciliationStatementActions(
    BuildContext context,
    PaymentAccount payment,
    EntityId statementId,
  ) {
    final statement = widget.workspace.database.bankStatement(
      widget.workspace.identity.businessId,
      statementId,
    );
    if (statement == null) return const [];
    return [
      _documentMoreMenu(context, statementId, statement),
      _bankChoice(
        context,
        payment,
        keyPrefix: 'reconciliation',
        onChanged: (id) => _switchReviewAccount(id, reconciliation: true),
      ),
      AccountingCompactChoiceMenu<String>(
        triggerKey: const ValueKey('reconciliation-statement-switcher'),
        tooltip: 'Switch Document',
        iconAsset: '077-change-statement.svg',
        value: statementId.value,
        options: [
          for (final item in _statementsByPayment[payment.id] ?? [])
            AccountingSelectorOption(
              value: item.id.value,
              label: item.statement.filename,
              key: ValueKey('reconciliation-statement-option-${item.id.value}'),
              preserveLabelCase: true,
            ),
        ],
        onChanged: (value) =>
            _openReconciliation(EntityId.parse(value), payment),
      ),
      AccountingButton.iconOnly(
        context,
        key: const ValueKey('reconciliation-review-connections'),
        compact: true,
        onPressed: () => _matches(statementId, payment),
        icon: Icons.link_outlined,
        tooltip: 'Review Statement Connections',
      ),
    ];
  }

  Widget _bankingHeader(BuildContext context, PaymentAccount? currentPayment) {
    return AccountingPageHeader(
      routeLabel: 'Banking',
      title: 'Banking',
      titleKey: 'page-title-banking',
      description: 'Connect bank transactions to posted records, then reconcile your statement.',
      action: AccountingButton.primary(
        context,
        key: const ValueKey('banking-primary-action'),
        onPressed: currentPayment == null
            ? _add
            : () => _importStatement(currentPayment),
        child: Text(
          currentPayment == null ? 'Add Bank Account' : 'Import Statement',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPayment = _paymentById(_displayPaymentId);
    if (_activeMatchReview case final review?) {
      return AccountingPageShell(
        key: const ValueKey('banking-match-shell'),
        includeTopSafeArea: !widget.compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bankingHeader(context, currentPayment),
            const SizedBox(height: accountingPageTitleOuterGap),
            if (currentPayment != null) ...[
              _accountSummary(context, currentPayment),
              const SizedBox(height: accountingContentInset),
            ],
            review,
          ],
        ),
      );
    }
    final reconciliation = _activeReconciliation;
    if (reconciliation != null) {
      final payment = _paymentById(reconciliation.paymentId);
      return AccountingPageShell(
        key: const ValueKey('banking-reconciliation-shell'),
        includeTopSafeArea: !widget.compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bankingHeader(context, payment),
            const SizedBox(height: accountingPageTitleOuterGap),
            if (payment != null) ...[
              _accountSummary(context, payment),
              const SizedBox(height: accountingContentInset),
            ],
            StatementReconciliationDialog(
              key: ValueKey(
                'reconciliation-workspace-${reconciliation.id.value}',
              ),
              workspace: widget.workspace,
              statementId: reconciliation.id,
              currency: reconciliation.currency,
              embedded: true,
              compactEmbedded: true,
              formActions: payment == null
                  ? const []
                  : _reconciliationStatementActions(
                      context,
                      payment,
                      reconciliation.id,
                    ),
              onBack: () {
                setState(() => _activeReconciliation = null);
                if (_reconciliationReturnsToReview && payment != null) {
                  _matches(reconciliation.id, payment);
                } else {
                  _returnToDocuments();
                }
              },
            ),
          ],
        ),
      );
    }
    return AccountingPageShell(
      key: const ValueKey('banking-main-shell'),
      includeTopSafeArea: !widget.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bankingHeader(context, currentPayment),
          const SizedBox(height: accountingPageTitleOuterGap),
          if (_error != null) ...[
            AccountingPageText(_error!),
            AccountingButton.outline(
              context,
              key: null,
              onPressed: _load,
              leadingIcon: Icons.refresh_outlined,
              child: const Text('Retry'),
            ),
          ] else if (_payments == null)
            const LinearProgressIndicator()
          else if (_payments!.isEmpty)
            const AccountingPageText('No payment accounts yet.')
          else
            for (final payment in _visiblePayments) ...[
              if (_visiblePayments.length > 1) ...[
                Text(
                  payment.name,
                  style: AccountingTypography.sectionTitle(context),
                ),
                const SizedBox(height: accountingContentInset),
              ],
              _accountSummary(context, payment),
              const SizedBox(height: accountingContentInset),
              _importedStatements(context, payment),
              const SizedBox(height: accountingContentInset),
            ],
        ],
      ),
    );
  }
}

class _MatchDateRangeBar extends StatefulWidget {
  const _MatchDateRangeBar({
    super.key,
    required this.from,
    required this.through,
    required this.searchQuery,
    required this.onQueryChanged,
    required this.onRun,
    this.searchHint = 'Search bank transactions',
    this.keyPrefix = 'match',
    this.alignLabelsToField = false,
  });

  final String searchHint;
  final String keyPrefix;
  final bool alignLabelsToField;
  final DateTime from;
  final DateTime through;
  final String searchQuery;
  final ValueChanged<String> onQueryChanged;
  final void Function(DateTime from, DateTime through) onRun;

  @override
  State<_MatchDateRangeBar> createState() => _MatchDateRangeBarState();
}

class _MatchDateRangeBarState extends State<_MatchDateRangeBar> {
  late final TextEditingController _search;
  late final TextEditingController _from;
  late final TextEditingController _through;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.searchQuery);
    _from = TextEditingController(text: formatAccountingInputDate(widget.from));
    _through = TextEditingController(
      text: formatAccountingInputDate(widget.through),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  void _run() {
    final from = parseAccountingInputDate(_from.text);
    final through = parseAccountingInputDate(_through.text);
    if (from == null || through == null || from.isAfter(through)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid date range.')),
      );
      return;
    }
    widget.onRun(from, through);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dateWidth = math.min(
        accountingCompactDateFieldWidth,
        constraints.maxWidth,
      );
      return Wrap(
        spacing: accountingContentInset,
        runSpacing: AccountingPageControlScope.runGapOf(context),
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: math.min(240, constraints.maxWidth),
            child: AccountingLabelledSearch(
              labelKey: ValueKey('${widget.keyPrefix}-search-label'),
              alignToField: widget.alignLabelsToField,
              child: TextField(
                key: ValueKey('${widget.keyPrefix}-search'),
                controller: _search,
                onChanged: widget.onQueryChanged,
                decoration: accountingSingleLineInputDecoration(
                  context,
                  hintText: widget.searchHint,
                ),
              ),
            ),
          ),
          for (final field in [
            ('From', _from, '${widget.keyPrefix}-from'),
            ('Through', _through, '${widget.keyPrefix}-through'),
          ])
            SizedBox(
              width: dateWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  accountingFieldLabel(
                    context,
                    field.$1,
                    key: ValueKey('${field.$3}-label'),
                    alignToField: widget.alignLabelsToField,
                  ),
                  const SizedBox(height: accountingFieldLabelGap),
                  TextField(
                    key: ValueKey(field.$3),
                    controller: field.$2,
                    inputFormatters: const [DateInputFormatter()],
                    textAlignVertical: TextAlignVertical.center,
                    decoration:
                        accountingSingleLineInputDecoration(
                          context,
                          hintText: 'DD-MM-YYYY',
                        ).copyWith(
                          suffixIcon: accountingCalendarButton(
                            context,
                            controller: field.$2,
                            label: field.$1,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          AccountingButtonGroup(
            compact: false,
            child: AccountingButton.primary(
              context,
              key: ValueKey('run-${widget.keyPrefix}-date-range'),
              onPressed: _run,
              child: const Text('Run'),
            ),
          ),
        ],
      );
    },
  );
}

/// The existing painted chevron remains on its original card-content axis.
/// Only the circular selector-style highlight follows that translated mark.
class _BankingCandidateArrow extends StatefulWidget {
  const _BankingCandidateArrow({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_BankingCandidateArrow> createState() => _BankingCandidateArrowState();
}

class _BankingCandidateArrowState extends State<_BankingCandidateArrow> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountingMinorHoverRegion(
    builder: (context, hovered) => IconButton(
      key: widget.buttonKey,
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      statesController: _states,
      icon: Transform.translate(
        offset: Offset(widget.icon == Icons.chevron_left_rounded ? -10 : 10, 0),
        child: ListenableBuilder(
          listenable: _states,
          builder: (context, child) => AccountingMinorHoverHalo(
            // Both directions keep the same hover surface, including at the
            // navigation limits; disabled clicks still cannot change candidates.
            dimension: 25,
            highlighted: hovered || _states.value.contains(WidgetState.focused),
            child: AccountingIcon.smallAction(widget.icon),
          ),
        ),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28.5, height: 32),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}
