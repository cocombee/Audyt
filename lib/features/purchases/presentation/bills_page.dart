import 'dart:convert';

import 'vendors_page.dart' show showAccountingVendorDialog;
import '../../accounting/presentation/recurring_transactions_dialog.dart';
import '../../accounting/domain/recurring_document_template.dart';

import 'package:flutter/material.dart';

import '../../accounting/domain/transaction_removal.dart';
import '../../accounting/presentation/transaction_removal_controls.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/demo_company.dart';
import '../../../app/frontend_review.dart';
import '../../../app/responsive.dart';
import '../../../app/naming_setup.dart' show SetupKind;
import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/storage/record_metadata.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/data/accounting_database.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/company_payment_term.dart';
import '../../accounting/domain/payment_terms.dart';
import '../../accounting/presentation/payment_terms_directory_dialog.dart';
import '../../accounting/presentation/attachment_preview_dialog.dart';
import '../../accounting/presentation/widgets/accounting_layout.dart';
import '../../sales/invoice_form.dart' show invoiceMoney;
import '../domain/purchase_bill_draft.dart';
import '../domain/vendor.dart';
import 'bill_form.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({
    super.key,
    required this.workspace,
    this.initialSearch = '',
  });
  final AccountingWorkspace workspace;
  final String initialSearch;
  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  AccountingWorkspace get workspace => widget.workspace;
  final _search = TextEditingController();
  String? _status, _error;
  int _offset = 0;
  int _pageSize = AccountingRecordPageSizes.read('bill');
  @override
  void initState() {
    super.initState();
    _search.text = widget.initialSearch;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _purchaseAccount(Account account) =>
      account.status == AccountStatus.active &&
      !account.isParent &&
      const [AccountType.expense, AccountType.asset].contains(account.type);

  Future<void> _edit([PurchaseBillDraft? existing]) async {
    final allAccounts = (await workspace.accounts())
        .map((a) => a.account)
        .toList();
    if (!mounted) return;
    final accounts = allAccounts.where(_purchaseAccount).toList();
    final vendors = <EntityId, Vendor>{};
    // Fetch complete choices in bounded directory reads; never omit suppliers
    // merely because the first page of the directory is full.
    var offset = 0;
    while (true) {
      final page = workspace.database.vendorDirectory(
        businessId: workspace.identity.businessId,
        offset: offset,
        limit: 100,
      );
      for (final entry in page.entries) {
        if (entry.vendor != null) vendors[entry.vendor!.id] = entry.vendor!;
      }
      offset = page.offset + page.entries.length;
      if (offset >= page.total || page.entries.isEmpty) break;
    }
    if (existing != null) {
      vendors[existing.vendorSnapshot.id] = existing.vendorSnapshot;
    }
    if (vendors.isEmpty || accounts.isEmpty) {
      setState(
        () => _error = 'Add a vendor profile and an active expense or asset account before saving bills.',
      );
      return;
    }
    final id = existing?.id ?? EntityId.random();
    final demo = DemoCompany.active(context);
    var paymentTermTemplates = demo
        ? <CompanyPaymentTerm>[]
        : workspace.paymentTerms.where((term) => term.active).toList();
    BuildContext? editorContext;
    StateSetter? refreshEditor;

    void refreshPaymentTermChoices() {
      if (editorContext?.mounted != true || refreshEditor == null) return;
      refreshEditor!(() {
        paymentTermTemplates = demo
            ? <CompanyPaymentTerm>[]
            : workspace.paymentTerms.where((term) => term.active).toList();
      });
    }

    void validateSelectedPaymentTerm(Map<String, Object?> values) {
      final choice = '${values['Payment Terms'] ?? ''}';
      final selected = paymentTermTemplates
          .where((term) => billPaymentTermChoice(term) == choice)
          .firstOrNull;
      if (selected == null) return; // billFromForm rejects unknown opaque IDs.
      final current = workspace.paymentTerms
          .where((term) => term.id == selected.id)
          .firstOrNull;
      if (current == null ||
          !current.active ||
          current.revision != selected.revision ||
          jsonEncode(current.rule.toJson()) !=
              jsonEncode(selected.rule.toJson())) {
        throw StateError(
          'The selected company payment term changed. Reopen the bill.',
        );
      }
    }

    final initial = existing == null
        ? <String, Object?>{
            'Date': formatAccountingInputDate(
              accountingCalendarDate(DateTime.now()),
            ),
            'Due Date': '',
            'Document Number': workspace.database.allocateDocumentNumber(
              businessId: workspace.identity.businessId,
              actorId: workspace.identity.ownerId,
              recordId: id,
              documentType: 'bill',
              allocatedAt: DateTime.now().toUtc(),
            ),
            'Currency': 'Use Counterparty Default',
            'Payment Terms': 'Use Vendor Default',
            'Tax Mode': 'Exclusive',
          }
        : {
            ...billFormValues(existing),
            ...documentRecurrenceInitial(
              workspace,
              RecurringDocumentKind.bill,
              existing.id,
            ),
          };
    DesignForm currentForm() => billForm(
      {
        for (final v in vendors.values)
          v.id.value:
              '${v.name}${vendors.values.where((other) => other.name == v.name).length > 1 ? ' · ${v.id.value.substring(0, 8)}' : ''}',
      },
      {
        for (final a in allAccounts.where(
          (a) =>
              _purchaseAccount(a) ||
              existing?.lines.any((l) => l.categoryId == a.id) == true,
        ))
          a.id.value:
              '${a.name}${allAccounts.where((other) => other.name == a.name).length > 1 ? ' · ${a.code}' : ''}${_purchaseAccount(a) ? '' : ' · Unavailable'}',
      },
      currencyCodes: {
        for (final v in vendors.values) v.currency.code,
        if (existing != null) existing.total.currency,
      },
      counterpartyCurrencies: {
        for (final v in vendors.values) v.id.value: v.currency.code,
      },
      counterpartyCustomTerms: {
        for (final v in vendors.values)
          if (v.terms.kind == PaymentTermKind.custom)
            v.id.value: v.terms.customText!,
      },
      paymentTermTemplates: paymentTermTemplates,
      defaultCurrencyCode: workspace.identity.currency,
      preferences: workspace.preferences,
      existing: existing,
      taxChoices: {
        for (final code in workspace.taxRates) code.choice: code.label,
        '0': 'No Tax',
        for (final line in existing?.lines ?? const [])
          if (line.taxSnapshot != null)
            line.taxSnapshot!.choice: line.taxSnapshot!.label,
        for (final line in existing?.lines ?? const [])
          if (line.taxSnapshot == null &&
              (line.taxRatePercent ?? '').isNotEmpty)
            line.taxRatePercent!: line.taxRatePercent == '0'
                ? 'No Tax'
                : 'Saved ${line.taxRatePercent}%',
      },
    );
    final form = currentForm();
    final contentWidth = frontendTransactionContentWidth(
      context,
      form,
      lines: [
        for (final line in initial['_lines'] as List? ?? const [])
          Map<String, String>.from(line as Map),
      ],
    );
    await AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: contentWidth,
      contentInset: accountingContentInset,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          editorContext = dialogContext;
          refreshEditor = setDialogState;
          return FrontendFormDialog(
            contentWidth: contentWidth,
            form: form,
            formBuilder: currentForm,
            selectorActions: {
              'Payment Terms': accountingTermSetupActions(
                context,
                workspace: demo ? null : workspace,
                onReturn: refreshPaymentTermChoices,
              ),
            },
            onAddCounterparty: () async {
              final vendor = await showAccountingVendorDialog(
                context,
                workspace,
              );
              if (vendor == null) return null;
              vendors[vendor.id] = vendor;
              return vendor.id.value;
            },
            settingsWorkspace: workspace,
            initial: initial,
            attachmentSetupKind: SetupKind.expense,
            attachmentCategoryCode: (lines) {
              final ids = lines
                  .map((line) => line['Account'])
                  .whereType<String>()
                  .where((id) => id.isNotEmpty)
                  .toSet();
              return ids.length == 1
                  ? accounts
                            .where((a) => a.id.value == ids.single)
                            .firstOrNull
                            ?.code ??
                        ''
                  : '';
            },
            lineDefaults: const {
              'Quantity': '1',
              'Discount': '0',
              'Tax Rate (%)': '0',
            },
            reviewInformationRowsBuilder: (values) {
              validateSelectedPaymentTerm(values);
              final vendor =
                  vendors[EntityId.parse(values['Counterparty'] as String)];
              if (vendor == null) {
                throw StateError('Choose an available vendor.');
              }
              final at = DateTime.now().toUtc();
              final preview = billFromForm(
                values,
                metadata:
                    existing?.metadata.nextRevision(updatedAt: at) ??
                    RecordMetadata.initial(
                      recordId: id,
                      businessId: workspace.identity.businessId,
                      originDeviceId: workspace.identity.deviceId,
                      createdAt: at,
                    ),
                vendor: vendor,
                taxCodes: workspace.taxRates,
                paymentTermTemplates: paymentTermTemplates,
                existing: existing,
                purchaseAccountIds: accounts.map((a) => a.id.value).toSet(),
              );
              return [
                ...billInformationRows(
                  preview,
                  accountNames: {
                    for (final a in allAccounts) a.id: '${a.code} · ${a.name}',
                  },
                ),
                if (preview.attachments.isNotEmpty)
                  (
                    'Supporting Documents',
                    preview.attachments.map((a) => a.filename).join(', '),
                  ),
              ];
            },
            onCommit: (values) async {
              final vendorId = EntityId.parse(values['Counterparty'] as String);
              final vendor = vendors[vendorId];
              if (vendor == null) {
                throw StateError('The chosen vendor is unavailable.');
              }
              if (existing?.vendorSnapshot.id != vendorId) {
                final currentVendor = workspace.database.readVendor(
                  workspace.identity.businessId,
                  vendorId,
                );
                if (currentVendor == null ||
                    currentVendor.metadata.revision !=
                        vendor.metadata.revision) {
                  throw StateError(
                    'Vendor defaults changed. Reopen the bill before saving.',
                  );
                }
              }
              final currentAccounts = await workspace.accounts();
              validateSelectedPaymentTerm(values);
              final at = DateTime.now().toUtc();
              final metadata =
                  existing?.metadata.nextRevision(updatedAt: at) ??
                  RecordMetadata.initial(
                    recordId: id,
                    businessId: workspace.identity.businessId,
                    originDeviceId: workspace.identity.deviceId,
                    createdAt: at,
                  );
              workspace.saveBillDraft(
                billFromForm(
                  values,
                  metadata: metadata,
                  vendor: vendor,
                  taxCodes: workspace.taxRates,
                  paymentTermTemplates: paymentTermTemplates,
                  existing: existing,
                  purchaseAccountIds: currentAccounts
                      .map((a) => a.account)
                      .where(_purchaseAccount)
                      .map((a) => a.id.value)
                      .toSet(),
                ),
                expectedRevision: existing?.metadata.revision ?? 0,
                recurrence:
                    values['_documentRecurrence'] as DocumentRecurrenceRequest?,
              );
            },
          );
        },
      ),
    );
    if (mounted) {
      setState(() {
        _error = null;
        _offset = 0;
      });
    }
  }

  Future<void> _view(PurchaseBillDraft bill, {bool historical = false}) async {
    final accounts = {
      for (final a in await workspace.accounts())
        a.account.id: '${a.account.code} · ${a.account.name}',
    };
    if (!mounted) return;
    final posting = historical
        ? null
        : workspace.database.readBillPosting(
            workspace.identity.businessId,
            bill.id,
          );
    final reversal = historical
        ? null
        : workspace.database.readBillReversal(
            workspace.identity.businessId,
            bill.id,
          );
    await showDialog<void>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.custom,
        title: historical
            ? 'Bill Revision ${bill.metadata.revision}'
            : 'View Bill',
        maxContentWidth: AccountingPopoutTokens.widerContentWidth,
        content: SizedBox(
          width: AccountingPopoutTokens.widerContentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountingInformationRows(
                rows: [
                  (
                    'Status',
                    historical
                        ? 'Historical Revision'
                        : reversal != null
                        ? 'Reversed'
                        : posting == null
                        ? 'Draft'
                        : 'Posted',
                  ),
                  ...billInformationRows(bill, accountNames: accounts),
                  if (posting != null) ...[
                    (
                      'Payable Account',
                      accounts[posting.payableAccountId] ??
                          posting.payableAccountId.value,
                    ),
                    ('Posting Journal', posting.journalId.value),
                  ],
                  if (reversal != null) ...[
                    (
                      'Reversed On',
                      formatAccountingInputDate(reversal.reversedOn),
                    ),
                    ('Reversal Reason', reversal.reason),
                    ('Reversal Journal', reversal.journalId.value),
                  ],
                ],
              ),
              if (bill.attachments.isNotEmpty) ...[
                const SizedBox(height: accountingContentInset),
                AccountingAttachmentList(
                  paginationKey: 'bill-view-attachments',
                  children: [
                    for (final attachment in bill.attachments)
                      AccountingAttachmentRecordRow(
                        attachment: attachment,
                        actions: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'bill-attachment-${bill.id}-${attachment.originalId}',
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
        ),
        actions: const [],
      ),
    );
  }

  Future<void> _history(PurchaseBillDraft bill) => showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.custom,
      title: 'Bill History',
      maxContentWidth: AccountingPopoutTokens.widerContentWidth,
      content: SizedBox(
        width: AccountingPopoutTokens.widerContentWidth,
        child: AccountingRecordList(
          paginationKey: 'bills-1',
          children: [
            for (final revision in workspace.database.billDraftHistory(
              workspace.identity.businessId,
              bill.id,
            ))
              AccountingRecordRow(
                title: 'Revision ${revision.metadata.revision}',
                details: Text(
                  '${revision.documentNumber} · ${formatAccountingInputDate(revision.bill.issueDate)}',
                ),
                topRightInfo: true,
                trailing: Text(invoiceMoney(revision.total)),
                actions: [
                  AccountingRecordActions(
                    trailing: [
                      AccountingButton.iconOnly(
                        context,
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Bill Revision',
                        key: ValueKey(
                          'view-bill-revision-${bill.id}-${revision.metadata.revision}',
                        ),
                        onPressed: () => _view(revision, historical: true),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: const [],
    ),
  );

  Future<void> _post(PurchaseBillDraft bill) async {
    final accounts = (await workspace.accounts())
        .map((a) => a.account)
        .toList();
    if (!mounted) return;
    final choices = {
      for (final a in accounts.where(
        (a) =>
            a.type == AccountType.liability &&
            a.status == AccountStatus.active &&
            !a.isParent,
      ))
        a.id.value: '${a.code} · ${a.name}',
    };
    if (choices.isEmpty) {
      setState(
        () =>
            _error = 'Add an active payable liability account before posting.',
      );
      return;
    }
    final request = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    await showDialog<void>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: DesignForm(
          'Post Bill',
          [
            DesignField(
              'Payable Account',
              required: true,
              choiceLabels: choices,
            ),
          ],
          actionLabel: 'Post Bill',
          description: 'Record this bill as a purchase and a payable. Tax is included in purchase cost; payment is a separate step.',
        ),
        informationRows: billInformationRows(
          bill,
          accountNames: {
            for (final a in accounts) a.id: '${a.code} · ${a.name}',
          },
        ),
        initial: {
          'Payable Account': workspace.preferences.text(
            'Default Accounts',
            'Payables Account',
          ),
        },
        onCommit: (values) async => workspace.postBill(
          requestId: request,
          billId: bill.id,
          expectedRevision: bill.metadata.revision,
          payableAccountId: EntityId.parse(values['Payable Account'] as String),
          approvedAt: approvedAt,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _error = null;
        _offset = 0;
      });
    }
  }

  Future<void> _reverse(PurchaseBillDraft bill) async {
    final posting = workspace.database.readBillPosting(
      workspace.identity.businessId,
      bill.id,
    );
    if (posting == null) return;
    final source = await workspace.database.getJournal(posting.journalId);
    if (!mounted || source == null) return;
    final request = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    final today = accountingCalendarDate(DateTime.now());
    final initialDate = today.isBefore(source.entry.date)
        ? source.entry.date
        : today;
    List<(String, String)> review(Map<String, Object?> values) {
      final date = parseAccountingInputDate(values['Date'] as String);
      if (date == null ||
          accountingCalendarDate(date).isBefore(source.entry.date)) {
        throw const FormatException(
          'Choose a reversal date on or after the Bill posting date.',
        );
      }
      final reason = (values['Reason'] as String).trim();
      if (reason.isEmpty || reason.length > 500) {
        throw const FormatException('Enter a reason of 1–500 characters.');
      }
      return [
        ('Original Journal', posting.journalId.value),
        ('Reversal Date', formatAccountingInputDate(date)),
        ('Reversal Reason', reason),
        ('Purchase and Payable Reversed', invoiceMoney(bill.total)),
      ];
    }

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: const DesignForm(
          'Reverse Bill',
          [
            DesignField('Date', required: true),
            DesignField('Reason', required: true, multiline: true),
          ],
          actionLabel: 'Reverse Bill',
          description: 'Correct an unpaid posted Bill. The original purchase stays in history and a reversing journal removes its purchase and payable.',
        ),
        initial: {'Date': formatAccountingInputDate(initialDate)},
        informationRows: [
          ('Bill', '${bill.documentNumber} · ${bill.vendorSnapshot.name}'),
          ('Posted Amount', invoiceMoney(bill.total)),
        ],
        reviewInformationRowsBuilder: review,
        onCommit: (values) async {
          review(values);
          workspace.reverseBillRecognition(
            requestId: request,
            reviewedBill: bill,
            expectedRecognitionJournalId: posting.journalId,
            reversedOn: parseAccountingInputDate(values['Date'] as String)!,
            reason: (values['Reason'] as String).trim(),
            approvedAt: approvedAt,
          );
        },
      ),
    );
    if (mounted && result != null) {
      setState(() {
        _error = null;
        _offset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final controlCount = workspace.database
          .billDraftPage(businessId: workspace.identity.businessId, limit: 1)
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = workspace.database.billDraftPage(
        businessId: workspace.identity.businessId,
        search: showControls ? _search.text : '',
        offset: showControls ? _offset : 0,
        limit: _pageSize,
        posted: !showControls || _status == null ? null : _status != 'Draft',
        reversed: !showControls || _status == null || _status == 'Draft'
            ? null
            : _status == 'Reversed',
      );
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Bills',
              title: 'Bills',
              description: 'Save supplier bills and review their purchase and payable entries.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('new-bill'),
                onPressed: () => _edit(),
                child: const Text('Record Bill'),
              ),
              secondaryActions: [
                if (workspace
                        .removedTransactionPage(
                          TransactionRecordKind.bill,
                          limit: 1,
                        )
                        .total >
                    0)
                  RemovedTransactionsButton(
                    workspace: workspace,
                    kind: TransactionRecordKind.bill,
                    onView: (record) => _view(
                      workspace.database.readBillDraft(
                        workspace.identity.businessId,
                        EntityId.parse(record.recordId),
                        includeRemoved: true,
                      )!,
                    ),
                  ),
                AccountingButton.outline(
                  context,
                  key: const ValueKey('open-recurring-transactions'),
                  onPressed: () => showRecurringTransactions(
                    context,
                    workspace,
                    initialKind: RecurringDocumentKind.bill,
                  ),
                  child: const Text('Recurring'),
                ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            if (_error != null) ...[
              AccountingAlert.build(
                context,
                title: 'Bill',
                description: _error!,
                tone: AccountingAlertTone.critical,
              ),
              const SizedBox(height: accountingContentInset),
            ],
            AccountingRecordControls(
              recordCount: controlCount,
              child: AccountingControlFlow(
                spacing: accountingContentInset,
                runSpacing: AccountingPageControlScope.runGapOf(context),
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        accountingFieldLabel(context, 'Search'),
                        const SizedBox(height: accountingFieldLabelGap),
                        SizedBox(
                          height: 44,
                          child: TextField(
                            key: const ValueKey('bill-search'),
                            controller: _search,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Vendor, number or reference',
                            ),
                            onChanged: (_) => setState(() => _offset = 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    controlKey: const ValueKey('bill-status-filter'),
                    options: const ['Draft', 'Posted', 'Reversed'],
                    value: _status,
                    onChanged: (value) => setState(() {
                      _status = value;
                      _offset = 0;
                    }),
                  ),
                  if (_search.text.isNotEmpty || _status != null)
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('clear-bill-filter'),
                      onPressed: () => setState(() {
                        _search.clear();
                        _status = null;
                        _offset = 0;
                      }),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            if (showControls) const SizedBox(height: accountingContentInset),
            if (page.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: accountingContentInset,
                ),
                child: Text('No matching bills.'),
              ),
            AccountingRecordList(
              totalCount: controlCount,
              paginationKey: 'bills-2',
              externalPagination: page.total == 0
                  ? null
                  : Padding(
                      padding: accountingContentPadding,
                      child: AccountingRecordPagination(
                        total: page.total,
                        unfilteredTotal: controlCount,
                        offset: page.offset,
                        pageSize: _pageSize,
                        keyPrefix: 'bill',
                        onPageSizeChanged: (size) => setState(() {
                          _pageSize = size;
                          _offset = 0;
                        }),
                        onPrevious: page.offset == 0
                            ? null
                            : () => setState(
                                () => _offset = (page.offset - _pageSize).clamp(
                                  0,
                                  page.total,
                                ),
                              ),
                        onNext: page.offset + _pageSize >= page.total
                            ? null
                            : () => setState(
                                () => _offset = page.offset + _pageSize,
                              ),
                      ),
                    ),
              children: [for (final bill in page.records) _row(context, bill)],
            ),
          ],
        ),
      );
    },
  );

  Widget _row(BuildContext context, PurchaseBillDraft bill) {
    final posted =
        workspace.database.readBillPosting(
          workspace.identity.businessId,
          bill.id,
        ) !=
        null;
    final reversal = posted
        ? workspace.database.readBillReversal(
            workspace.identity.businessId,
            bill.id,
          )
        : null;
    final hasPayments =
        posted &&
        workspace.database.activeBillSettlementCount(
              workspace.identity.businessId,
              bill.id,
            ) !=
            0;
    return AccountingRecordRow(
      key: ValueKey('bill-row-${bill.id}'),
      topRightInfo: true,
      title: bill.vendorSnapshot.name,
      status: AccountingBadge.build(
        context,
        label: reversal != null
            ? 'Reversed'
            : posted
            ? 'Posted'
            : 'Draft',
      ),
      details: Text(
        '${bill.documentNumber} · ${formatAccountingInputDate(bill.bill.issueDate)}',
      ),
      trailing: Text(
        invoiceMoney(bill.total),
        style: AccountingTypography.value(context)
            .copyWith(fontWeight: FontWeight.w600),
      ),
      actions: [
        AccountingRecordActions(
          trailing: [
            AccountingButton.iconOnly(
              context,
              key: ValueKey('view-bill-${bill.id}'),
              icon: Icons.visibility_outlined,
              tooltip: 'View Bill',
              onPressed: () => _view(bill),
            ),
            TransactionRemoveButton(
              key: ValueKey('delete-bill-${bill.id}'),
              workspace: workspace,
              kind: TransactionRecordKind.bill,
              recordId: bill.id.value,
            ),
            if (!posted)
              AccountingButton.iconOnly(
                context,
                key: ValueKey('edit-bill-${bill.id}'),
                icon: Icons.edit_outlined,
                tooltip: 'Edit Bill',
                onPressed: () => _edit(bill),
              ),
            AccountingOverflowMenu(
              triggerKey: ValueKey('bill-more-${bill.id}'),
              actions: [
                if (!posted)
                  AccountingOverflowAction(
                    key: ValueKey('post-bill-${bill.id}'),
                    label: 'Post Bill',
                    icon: Icons.check,
                    onPressed: () => _post(bill),
                  ),
                if (posted && reversal == null && !hasPayments)
                  AccountingOverflowAction(
                    key: ValueKey('reverse-bill-${bill.id}'),
                    label: 'Reverse Bill',
                    icon: Icons.undo,
                    onPressed: () => _reverse(bill),
                  ),
                AccountingOverflowAction(
                  key: ValueKey('bill-history-${bill.id}'),
                  label: 'History',
                  icon: Icons.history_outlined,
                  onPressed: () => _history(bill),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
