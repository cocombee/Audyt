import '../accounting/presentation/customer_page.dart'
    show showAccountingCustomerDialog;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../accounting/domain/transaction_removal.dart';
import '../accounting/presentation/transaction_removal_controls.dart';

import '../../app/accounting_components.dart';
import '../../app/accounting_theme.dart';
import '../../app/responsive.dart';
import '../../app/frontend_review.dart';
import '../../app/naming_setup.dart' show SetupKind;
import '../../app/receipt_destination.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/documents/generated_document.dart';
import '../accounting/domain/customer.dart';
import '../accounting/domain/recurring_document_template.dart';
import '../accounting/presentation/recurring_transactions_dialog.dart';
import 'sales_document.dart';
import 'generated_sales_document_service.dart';
import 'generated_document_filing_notice.dart';
import '../../core/dates/accounting_date.dart';
import '../../core/ids/entity_id.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/data/accounting_database.dart';
import '../accounting/domain/account.dart';
import '../accounting/presentation/attachment_preview_dialog.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import 'domain/estimate.dart';
import 'domain/sales_line_item.dart';
import 'invoice_form.dart';
import 'invoice_page.dart';

String quotationStateLabel(EstimateStatus status) => switch (status) {
  EstimateStatus.draft => 'Draft',
  EstimateStatus.sent => 'Shared',
  EstimateStatus.viewed => 'Viewed',
  EstimateStatus.accepted => 'Accepted',
  EstimateStatus.declined => 'Declined',
  EstimateStatus.closed => 'Closed',
  EstimateStatus.converted => 'Converted',
  EstimateStatus.expired => 'Expired',
};

String quotationStatus(Estimate quote, DateTime asOf) =>
    quotationStateLabel(quote.expire(asOf: asOf).status);

class QuotationPage extends StatefulWidget {
  const QuotationPage({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<QuotationPage> createState() => _QuotationPageState();
}

class _QuotationPageState extends State<QuotationPage> {
  AccountingWorkspace get workspace => widget.workspace;
  final _searchController = TextEditingController();
  String? _status, _currency, _error;
  int _offset = 0;
  int _pageSize = AccountingRecordPageSizes.read('quotation');
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _edit({StoredQuotation? record}) async {
    final existing = record?.quotation;
    final currentEdit =
        existing != null && existing.status != EstimateStatus.draft;
    final allAccounts = (await workspace.accounts())
        .map((r) => r.account)
        .toList();
    if (!mounted) return;
    final activeAccounts = allAccounts
        .where(
          (a) =>
              a.type == AccountType.income &&
              a.status == AccountStatus.active &&
              !a.isParent,
        )
        .toList();
    final activeIds = activeAccounts.map((a) => a.id).toSet();
    final customers = workspace.customers();
    if (!currentEdit &&
        (activeAccounts.isEmpty || !customers.any((c) => c.isActive))) {
      setState(
        () => _error = 'Add an active customer and an active income account before saving quotations.',
      );
      return;
    }
    final pricing = existing?.pricingSnapshot();
    final customerChoices = customers
        .where((c) => c.isActive || c.id == existing?.customerId)
        .toList();
    DesignForm currentForm() {
      final base = invoiceForm(
        {
          for (final c in customerChoices)
            c.id.value:
                '${c.displayName}${customerChoices.where((other) => other.displayName == c.displayName).length > 1 ? ' · ${c.id.value.substring(0, 8)}' : ''}${c.isActive ? '' : ' · Inactive'}',
        },
        {
          for (final a in allAccounts.where(
            (a) =>
                activeIds.contains(a.id) ||
                existing?.lines.any((line) => line.categoryId == a.id) == true,
          ))
            a.id.value:
                '${a.code} · ${a.name}${activeIds.contains(a.id) ? '' : ' · Unavailable'}',
        },
        preferences: workspace.preferences,
        existing: pricing,
        counterpartyCurrencies: {
          for (final c in customerChoices) c.id.value: c.currency.code,
        },
        counterpartyCustomTerms: {
          for (final c in customerChoices)
            if (c.paymentTerms.kind == PaymentTermKind.custom)
              c.id.value: c.paymentTerms.customText!,
        },
        defaultCurrencyCode: workspace.identity.currency,
        itemChoices: {
          for (final item in workspace.catalogueItems) item.id.value: item.name,
          for (final line in pricing?.lines ?? <SalesLineItem>[])
            if (line.catalogue != null)
              line.catalogue!.itemId.value: line.catalogue!.itemName,
        },
        taxChoices: {
          for (final code in workspace.taxRates) code.choice: code.label,
          for (final rate in {
            '0',
            ...workspace.catalogueItems.map((i) => i.taxRatePercent),
            for (final line in pricing?.lines ?? <SalesLineItem>[])
              if (line.taxRatePercent != null) line.taxRatePercent!,
          })
            rate: rate == '0' ? 'No Tax' : '$rate%',
        },
      );
      return DesignForm(
        'Quotations',
        [
          for (final field in base.fields)
            if (field.label == 'Due Date')
              const DesignField('Expiry Date', required: true)
            else
              field,
        ],
        lines: true,
        recurring: true,
        evidence: true,
        lineFields: base.lineFields,
        lineChoiceLabels: base.lineChoiceLabels,
        counterpartyCurrencies: base.counterpartyCurrencies,
        counterpartyCustomTerms: base.counterpartyCustomTerms,
        defaultCurrencyCode: base.defaultCurrencyCode,
        actionLabel: currentEdit ? 'Save Changes' : 'Save Draft',
      );
    }

    final id = existing?.id ?? EntityId.random();
    final now = accountingCalendarDate(DateTime.now());
    final initial = existing == null
        ? <String, Object?>{
            'Date': formatAccountingInputDate(now),
            'Expiry Date': formatAccountingInputDate(
              now.add(const Duration(days: 30)),
            ),
            'Document Number': workspace.database.allocateDocumentNumber(
              businessId: workspace.identity.businessId,
              actorId: workspace.identity.ownerId,
              recordId: id,
              documentType: 'quotation',
              allocatedAt: DateTime.now().toUtc(),
            ),
            'Currency': 'Use Counterparty Default',
            'Payment Terms': 'Use Customer Default',
            'Tax Mode': 'Review Needed',
          }
        : {
            ...invoiceFormValues(pricing!),
            'Expiry Date': formatAccountingInputDate(existing.validUntil),
            ...documentRecurrenceInitial(
              workspace,
              RecurringDocumentKind.quotation,
              existing.id,
            ),
          };
    final editorCompany = workspace.identity.businessId;
    Future<(Estimate, Customer, String)> resolveDocument(
      Map<String, Object?> values,
    ) async {
      if (workspace.identity.businessId != editorCompany) {
        throw StateError('Company changed. Reopen the document.');
      }
      final current = await workspace.accounts();
      var customer = workspace
          .customers()
          .where((c) => c.id.value == values['Counterparty'])
          .firstOrNull;
      if (currentEdit &&
          customer?.id == existing.customerId &&
          customer?.isActive == false) {
        customer = record!.customerSnapshot;
      }
      if (customer == null || !customer.isActive) {
        throw StateError('Choose an active customer.');
      }
      final expiry = parseAccountingInputDate(
        values['Expiry Date'] as String? ?? '',
      );
      if (expiry == null) {
        throw const FormatException('Enter a valid quotation expiry date.');
      }
      final draft = invoiceFromForm(
        {
          ...values,
          'Due Date':
              values['Payment Terms'] == 'Custom' ||
                  (values['Payment Terms'] == 'Use Customer Default' &&
                      customer.paymentTerms.kind == PaymentTermKind.custom)
              ? formatAccountingInputDate(expiry)
              : '',
        },
        id: id,
        existing: pricing,
        allowRetainedUnavailableAccounts: currentEdit,
        taxCodes: workspace.taxRates,
        catalogueItems: workspace.catalogueItems,
        catalogueCategories: workspace.catalogueCategories,
        requireCatalogueItem: invoiceUsesCatalogueItems(pricing),
        customer: customer,
        incomeAccountIds: current
            .map((r) => r.account)
            .where(
              (a) =>
                  a.type == AccountType.income &&
                  a.status == AccountStatus.active &&
                  !a.isParent,
            )
            .map((a) => a.id.value)
            .toSet(),
      );
      if (workspace.identity.businessId != editorCompany) {
        throw StateError('Company changed. Reopen the document.');
      }
      final quotation = Estimate.draft(
        id: id,
        customerId: draft.customerId,
        lines: draft.lines,
        issueDate: draft.issueDate,
        validUntil: expiry,
        terms: draft.terms,
        documentNumber: draft.documentNumber,
        reference: draft.reference,
        memo: draft.memo,
        classification: draft.classification,
        location: draft.location,
        taxMode: draft.taxMode,
        attachments: draft.attachments,
      );
      final ids = quotation.lines
          .map((line) => line.categoryId)
          .whereType<EntityId>()
          .toSet();
      final categoryCode = ids.length == 1
          ? current
                    .where((a) => a.account.id == ids.single)
                    .firstOrNull
                    ?.account
                    .code ??
                ''
          : '';
      return (quotation, customer, categoryCode);
    }

    EntityId? currentRequest;
    DateTime? currentSavedAt;
    String? currentFingerprint;
    final contentWidth = frontendTransactionContentWidth(
      context,
      currentForm(),
      lines: List<Map<String, String>>.from(initial['_lines'] as List? ?? []),
    );
    await AccountingDialog.showFixed<void>(
      context: context,
      contentWidth: contentWidth,
      contentInset: accountingContentInset,
      builder: (_) => FrontendFormDialog(
        form: currentForm(),
        formBuilder: currentForm,
        onAddCounterparty: () async {
          final customer = await showAccountingCustomerDialog(
            context,
            workspace,
          );
          if (customer == null) return null;
          customerChoices.add(customer);
          return customer.id.value;
        },
        settingsWorkspace: workspace,
        contentWidth: contentWidth,
        initial: initial,
        attachmentSetupKind: SetupKind.invoice,
        attachmentCategoryCode: (lines) {
          final ids = lines
              .map((line) => line['Account'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet();
          return ids.length == 1
              ? activeAccounts
                        .where((a) => a.id.value == ids.single)
                        .firstOrNull
                        ?.code ??
                    ''
              : '';
        },
        lineDefaults: {
          'Quantity': '1',
          'Discount': '0',
          'Account':
              activeAccounts.any(
                (a) =>
                    a.id.value ==
                    workspace.preferences.text(
                      'Default Accounts',
                      'Income Account',
                    ),
              )
              ? workspace.preferences.text('Default Accounts', 'Income Account')
              : '',
        },
        reviewDocumentsBuilder: (values) async {
          final (quotation, customer, _) = await resolveDocument(values);
          final manual = quotation.attachments
              .where((a) => !a.isGenerated)
              .toList();
          if (manual.isNotEmpty) return manual;
          return [
            await const SalesDocumentRenderer().render(
              SalesDocumentSnapshot.quotation(
                businessId: editorCompany,
                quotation: quotation,
                customer: customer,
                preferences: workspace.preferences,
              ),
              filename: 'Quotation.pdf',
              previouslySaved:
                  (values['_reviewedDocuments'] as List?)
                      ?.cast<ReceiptAttachment>() ??
                  quotation.attachments,
            ),
          ];
        },
        onCommit: (values) async {
          final (quotation, customer, categoryCode) = await resolveDocument(
            values,
          );
          final filename = await documentDestinationFilename(
            kind: SetupKind.invoice,
            date: quotation.issueDate,
            categoryCode: categoryCode,
            mimeType: 'application/pdf',
          );
          await const GeneratedSalesDocumentService().saveQuotation(
            workspace: workspace,
            quotation: quotation,
            customer: customer,
            filename: filename,
            expectedRevision: record?.revision ?? 0,
            savedAt: (() {
              if (!currentEdit) return DateTime.now().toUtc();
              final fingerprint = jsonEncode([
                quotation.snapshot(),
                customer.id.value,
                customer.metadata.revision,
                (values['_documentRecurrence'] as DocumentRecurrenceRequest?)
                    ?.toJson(),
              ]);
              if (currentFingerprint != fingerprint) {
                currentFingerprint = fingerprint;
                currentRequest = EntityId.random();
                final now = DateTime.now().toUtc();
                currentSavedAt = now.isAfter(record!.savedAt)
                    ? now
                    : record.savedAt.add(const Duration(microseconds: 1));
              }
              return currentSavedAt!;
            })(),
            expectedCurrent: currentEdit ? record : null,
            currentRequestId: currentRequest,
            recurrence:
                values['_documentRecurrence'] as DocumentRecurrenceRequest?,
            renderedForReview:
                (values['_reviewedDocuments'] as List?)
                    ?.cast<ReceiptAttachment>() ??
                const [],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _view(StoredQuotation record) {
    final invoiceId = record.quotation.convertedInvoiceId;
    final invoice = invoiceId == null
        ? null
        : workspace.database.quotationInvoice(
            workspace.identity.businessId,
            invoiceId,
          );
    return showDialog<void>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.custom,
        title: 'View Quotation',
        maxContentWidth: AccountingPopoutTokens.widerContentWidth,
        content: SizedBox(
          key: ValueKey('quotation-details-${record.quotation.id}'),
          width: AccountingPopoutTokens.widerContentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountingInformationRows(
                rows: [
                  ('Quotation', record.quotation.documentNumber),
                  ('Customer (Saved)', record.customerSnapshot.displayName),
                  ('Status', quotationStatus(record.quotation, DateTime.now())),
                  ...quotationInformationRows(
                    record.quotation,
                    preferences: workspace.preferences,
                  ),
                  if (invoice != null) ('Invoice', invoice.documentNumber),
                  if (invoiceId != null) ('Invoice ID', invoiceId.value),
                ],
              ),
              if (invoice != null) ...[
                const SizedBox(height: accountingContentInset),
                Align(
                  alignment: Alignment.centerRight,
                  child: AccountingButton.iconOnly(
                    context,
                    icon: Icons.visibility_outlined,
                    tooltip: 'Preview Invoice',
                    compact: true,
                    key: ValueKey(
                      'quotation-invoice-preview-${record.quotation.id}',
                    ),
                    onPressed: () => showInvoiceDocumentPreview(
                      context,
                      workspace: workspace,
                      invoice: invoice,
                      number: invoice.documentNumber,
                      customerName: record.customerSnapshot.displayName,
                    ),
                  ),
                ),
              ],
              if (record.quotation.attachments.isNotEmpty) ...[
                const SizedBox(height: accountingContentInset),
                Wrap(
                  spacing: accountingRecordIconGap,
                  runSpacing: accountingRecordIconGap,
                  children: [
                    for (final attachment in record.quotation.attachments)
                      AccountingButton.outline(
                        context,
                        key: ValueKey(
                          'quotation-attachment-${record.quotation.id}-${attachment.originalId}',
                        ),
                        onPressed: () =>
                            showAttachmentPreview(context, attachment),
                        child: Text(attachment.filename),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [],
      ),
    );
  }

  Future<void> _change(StoredQuotation record, QuotationAction action) async {
    final label = switch (action) {
      QuotationAction.shared => 'Record Shared Quotation',
      QuotationAction.accepted => 'Record Acceptance',
      QuotationAction.declined => 'Record Decline',
      QuotationAction.closed => 'Close Quotation',
      QuotationAction.reopened => 'Reopen Quotation',
      QuotationAction.revised => 'Revise Quotation',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AccountingDialog.alert(
        context,
        widthFamily: AccountingPopoutWidthFamily.normal,
        title: label,
        content: AccountingInformationRows(
          rows: [
            ('Quotation', record.quotation.documentNumber),
            ('Customer', record.customerSnapshot.displayName),
            ('Total', invoiceMoney(record.quotation.total)),
          ],
        ),
        description: action == QuotationAction.shared
            ? 'Record that you shared this quotation. This does not send email.'
            : action == QuotationAction.revised
            ? 'Return to Draft for editing. The previous quoted version remains in history.'
            : null,
        actions: [
          AccountingButton.secondary(
            context,
            key: const ValueKey('cancel-quotation-state'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          AccountingButton.primary(
            context,
            key: const ValueKey('confirm-quotation-state'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      workspace.changeQuotationState(
        record.quotation.id,
        expectedRevision: record.revision,
        action: action,
        changedAt: DateTime.now().toUtc(),
      );
      setState(() {
        _error = null;
        _offset = 0;
      });
    } catch (error) {
      setState(
        () => _error = error is StateError
            ? error.message
            : 'Failed - review the quotation and try again.',
      );
    }
  }

  Future<void> _convert(StoredQuotation record) async {
    final id = EntityId.random();
    final number = workspace.database.allocateDocumentNumber(
      businessId: workspace.identity.businessId,
      actorId: workspace.identity.ownerId,
      recordId: id,
      documentType: 'invoice',
      allocatedAt: DateTime.now().toUtc(),
    );
    final issue = accountingCalendarDate(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: DesignForm(
          'Convert Quotation',
          [
            const DesignField('Date', required: true),
            if (record.quotation.terms.kind == PaymentTermKind.custom)
              const DesignField('Due Date', required: true),
            const DesignField('Document Number', required: true),
          ],
          description: 'Create an invoice draft with the quoted lines and payment terms. Posting requires a separate review.',
          actionLabel: 'Create Invoice Draft',
        ),
        informationRows: [
          ('Quotation', record.quotation.documentNumber),
          ('Customer', record.customerSnapshot.displayName),
          ('Total', invoiceMoney(record.quotation.total)),
          ('Quoted Terms', record.quotation.terms.label),
        ],
        initial: {
          'Date': formatAccountingInputDate(issue),
          'Document Number': number,
        },
        onCommit: (values) async {
          final date = parseAccountingInputDate(
            values['Date'] as String? ?? '',
          );
          if (date == null) {
            throw const FormatException('Enter a valid invoice issue date.');
          }
          workspace.convertQuotationToInvoice(
            record.quotation.id,
            expectedRevision: record.revision,
            invoiceId: id,
            documentNumber: (values['Document Number'] as String? ?? '').trim(),
            issueDate: date,
            dueDate: record.quotation.terms.kind == PaymentTermKind.custom
                ? parseAccountingInputDate(
                        values['Due Date'] as String? ?? '',
                      ) ??
                      (throw const FormatException(
                        'Enter an explicit invoice due date.',
                      ))
                : record.quotation.terms.dueDateFor(date),
            convertedAt: DateTime.now().toUtc(),
          );
        },
      ),
    );
  }

  List<AccountingOverflowAction> _actions(StoredQuotation record) {
    final quote = record.quotation;
    final status = quote.status;
    final expired = quotationStatus(quote, DateTime.now()) == 'Expired';
    AccountingOverflowAction action(
      QuotationAction action,
      String label,
      IconData icon,
    ) => AccountingOverflowAction(
      key: ValueKey('quotation-${action.name}-${quote.id}'),
      label: label,
      icon: icon,
      onPressed: () => _change(record, action),
    );
    return [
      if (status == EstimateStatus.draft &&
          !accountingCalendarDate(DateTime.now()).isAfter(quote.validUntil))
        action(QuotationAction.shared, 'Record Shared', Icons.link_outlined),
      if ([EstimateStatus.sent, EstimateStatus.viewed].contains(status) &&
          !expired) ...[
        action(QuotationAction.accepted, 'Record Acceptance', Icons.check),
        action(QuotationAction.declined, 'Record Decline', Icons.close),
      ],
      if (status == EstimateStatus.accepted)
        AccountingOverflowAction(
          key: ValueKey('convert-quotation-${quote.id}'),
          label: 'Convert To Invoice',
          icon: Icons.description_outlined,
          onPressed: () => _convert(record),
        ),
      if (![
        EstimateStatus.accepted,
        EstimateStatus.converted,
        EstimateStatus.draft,
      ].contains(status))
        action(
          QuotationAction.revised,
          'Revise Quotation',
          Icons.edit_outlined,
        ),
      if ([
        EstimateStatus.draft,
        EstimateStatus.sent,
        EstimateStatus.viewed,
        EstimateStatus.declined,
      ].contains(status))
        action(QuotationAction.closed, 'Close Quotation', Icons.block),
      if ([
        EstimateStatus.closed,
        EstimateStatus.declined,
        EstimateStatus.expired,
      ].contains(status))
        action(QuotationAction.reopened, 'Reopen Quotation', Icons.restore),
    ];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final date = DateTime.now();
      final status = _status == null
          ? null
          : EstimateStatus.values.singleWhere(
              (s) => quotationStateLabel(s) == _status,
            );
      final controlCount = workspace.database
          .quotationPage(
            workspace.identity.businessId,
            offset: 0,
            pageSize: 1,
            asOf: date,
          )
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = workspace.database.quotationPage(
        workspace.identity.businessId,
        offset: showControls ? _offset : 0,
        pageSize: _pageSize,
        search: showControls ? _searchController.text : '',
        status: showControls ? status : null,
        currency: showControls ? _currency : null,
        asOf: date,
      );
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Quotations',
              title: 'Quotations',
              description: 'Save quotations and convert accepted prices into invoice drafts.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('new-quotation'),
                onPressed: () => _edit(),
                child: const Text('Create Quotation'),
              ),
              secondaryActions: [
                if (workspace
                        .removedTransactionPage(
                          TransactionRecordKind.quotation,
                          limit: 1,
                        )
                        .total >
                    0)
                  RemovedTransactionsButton(
                    workspace: workspace,
                    kind: TransactionRecordKind.quotation,
                    onView: (record) => _view(
                      workspace.database.readQuotation(
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
                    initialKind: RecurringDocumentKind.quotation,
                  ),
                  child: const Text('Recurring'),
                ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            GeneratedDocumentFilingNotice(
              workspace: workspace,
              kind: GeneratedDocumentKind.quotation,
            ),
            if (_error != null)
              AccountingAlert.build(
                context,
                title: 'Quotation',
                description: _error!,
                tone: AccountingAlertTone.critical,
              ),
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
                            key: const ValueKey('quotation-search'),
                            controller: _searchController,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Name, number or reference',
                            ),
                            onChanged: (_) => setState(() => _offset = 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    options: const [
                      'Draft',
                      'Shared',
                      'Viewed',
                      'Accepted',
                      'Declined',
                      'Closed',
                      'Converted',
                      'Expired',
                    ],
                    controlKey: const ValueKey('quotation-status-filter'),
                    value: _status,
                    onChanged: (value) => setState(() {
                      _status = value;
                      _offset = 0;
                    }),
                  ),
                  AccountingRecordFilter(
                    label: 'Currency',
                    controlKey: const ValueKey('quotation-currency-filter'),
                    options: page.currencies,
                    value: _currency,
                    onChanged: (value) => setState(() {
                      _currency = value;
                      _offset = 0;
                    }),
                  ),
                  if (_searchController.text.isNotEmpty ||
                      _status != null ||
                      _currency != null)
                    AccountingButton.outline(
                      context,
                      key: const ValueKey('clear-quotation-filter'),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _status = null;
                        _currency = null;
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
                child: Text('No matching quotations.'),
              ),
            AccountingRecordList(
              totalCount: controlCount,
              paginationKey: 'quotation-1',
              externalPagination: page.total > 0
                  ? Padding(
                      padding: accountingContentPadding,
                      child: AccountingRecordPagination(
                        total: page.total,
                        unfilteredTotal: controlCount,
                        offset: _offset,
                        pageSize: _pageSize,
                        keyPrefix: 'quotation',
                        onPageSizeChanged: (size) => setState(() {
                          _pageSize = size;
                          _offset = 0;
                        }),
                        onPrevious: _offset == 0
                            ? null
                            : () => setState(
                                () => _offset = (_offset - _pageSize).clamp(
                                  0,
                                  page.total,
                                ),
                              ),
                        onNext: _offset + _pageSize >= page.total
                            ? null
                            : () => setState(() => _offset += _pageSize),
                      ),
                    )
                  : null,
              children: [
                for (final record in page.records)
                  AccountingRecordRow(
                    key: ValueKey('quotation-row-${record.quotation.id}'),
                    topRightInfo: true,
                    title: record.customerSnapshot.displayName,
                    status: AccountingBadge.build(
                      context,
                      label: quotationStatus(record.quotation, date),
                    ),
                    details: Text(
                      '${record.quotation.documentNumber} · ${formatAccountingInputDate(record.quotation.issueDate)}',
                    ),
                    trailing: Text(
                      invoiceMoney(record.quotation.total),
                      style: AccountingTypography.value(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            icon: Icons.visibility_outlined,
                            tooltip: 'View Quotation',
                            key: ValueKey(
                              'view-quotation-${record.quotation.id}',
                            ),
                            onPressed: () => _view(record),
                          ),
                          AccountingButton.iconOnly(
                            context,
                            icon: Icons.preview_outlined,
                            tooltip: 'Preview',
                            key: ValueKey(
                              'preview-quotation-${record.quotation.id}',
                            ),
                            onPressed: () => showQuotationDocumentPreview(
                              context,
                              record.quotation,
                              preferences: workspace.preferences,
                              customerName: record.customerSnapshot.displayName,
                            ),
                          ),
                          AccountingButton.outline(
                            context,
                            key: ValueKey(
                              'edit-quotation-${record.quotation.id}',
                            ),
                            onPressed: () => _edit(record: record),
                            child: const Text('Edit'),
                          ),
                          TransactionRemoveButton(
                            key: ValueKey(
                              'delete-quotation-${record.quotation.id}',
                            ),
                            workspace: workspace,
                            kind: TransactionRecordKind.quotation,
                            recordId: record.quotation.id.value,
                          ),
                          if (_actions(record).isNotEmpty)
                            AccountingOverflowMenu(
                              triggerKey: ValueKey(
                                'quotation-more-${record.quotation.id}',
                              ),
                              actions: _actions(record),
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
