import '../accounting/presentation/customer_page.dart'
    show showAccountingCustomerDialog;
import '../accounting/presentation/recurring_transactions_dialog.dart';
import '../accounting/domain/recurring_document_template.dart';
import 'domain/estimate.dart';
import '../../app/naming_setup.dart' show SetupKind;
import '../../app/demo_company.dart' show DemoCompany;
import '../../app/receipt_destination.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/documents/generated_document.dart';
import '../accounting/domain/customer.dart';
import '../accounting/domain/company_payment_term.dart';
import '../accounting/presentation/company_payment_term_selection.dart';
import 'sales_document.dart';
import 'generated_sales_document_service.dart';
import 'generated_document_filing_notice.dart';

import 'dart:typed_data';
import 'dart:convert';

import '../accounting/domain/company_preferences.dart';

import 'dart:math' as math;

import '../../app/accounting_theme.dart';
import '../../app/accounting_image_zoom.dart';
import '../accounting/domain/payment_account.dart';
import '../../core/money/money.dart';
import '../accounting/presentation/attachment_preview_dialog.dart';

import 'package:flutter/material.dart';

import '../../app/accounting_components.dart';
import '../../app/frontend_review.dart';
import '../../core/ids/entity_id.dart';
import '../../core/dates/accounting_date.dart';
import '../accounting/application/accounting_workspace.dart';
import '../accounting/domain/account.dart';
import '../accounting/presentation/widgets/accounting_layout.dart';
import 'domain/invoice.dart';
import 'domain/sales_line_item.dart';
import 'invoice_form.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({
    super.key,
    required this.workspace,
    this.createDraftOnOpen = false,
  });
  final AccountingWorkspace workspace;
  final bool createDraftOnOpen;
  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  AccountingWorkspace get workspace => widget.workspace;
  String _search = '';
  String? _status, _currency;
  @override
  void initState() {
    super.initState();
    if (widget.createDraftOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _edit(context);
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _explain(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AccountingDialog.alert(
          dialogContext,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: 'Invoice Review Required',
          content: Text(message),
          actions: [],
        ),
      );
  List<Widget> _attachments(BuildContext context, Invoice invoice) => [
    for (final attachment in invoice.attachments)
      AccountingButton.iconOnly(
        context,
        key: ValueKey(
          'invoice-attachment-${invoice.id.value}-${attachment.originalId}',
        ),
        icon: attachment.originalMimeType.startsWith('image/')
            ? Icons.image_outlined
            : Icons.description_outlined,
        tooltip: 'View ${attachment.filename}',
        onPressed: () => showAttachmentPreview(context, attachment),
      ),
  ];

  Future<void> _archive(
    BuildContext context,
    Invoice invoice,
    int revision,
    bool archived,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        title: archived ? 'Archive Invoice Draft' : 'Restore Invoice Draft',
        content: Text(
          archived
              ? 'Move this draft to Archived? Its details and original attachments remain available for recovery.'
              : 'Return this invoice to the draft list?',
        ),
        actions: [
          AccountingButton.secondary(
            dialogContext,
            key: const ValueKey('cancel-invoice-archive'),
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          if (archived)
            AccountingButton.destructive(
              dialogContext,
              key: const ValueKey('confirm-invoice-archive'),
              child: const Text('Archive'),
              onPressed: () => Navigator.pop(dialogContext, true),
            )
          else
            AccountingButton.primary(
              dialogContext,
              key: const ValueKey('confirm-invoice-archive'),
              child: const Text('Restore'),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      workspace.setInvoiceDraftArchived(
        invoiceId: invoice.id,
        expectedRevision: revision,
        archived: archived,
        changedAt: DateTime.now().toUtc(),
      );
    } catch (error) {
      if (context.mounted) await _explain(context, error.toString());
    }
  }

  Future<void> _edit(
    BuildContext context, {
    Invoice? invoice,
    int revision = 0,
  }) async {
    final allAccounts = (await workspace.accounts())
        .map((a) => a.account)
        .toList();
    final accounts = allAccounts
        .where(
          (a) =>
              a.type == AccountType.income &&
              a.status == AccountStatus.active &&
              !a.isParent,
        )
        .toList();
    final allCustomers = workspace.customers();
    final customers = allCustomers.where((c) => c.isActive).toList();
    final activeAccountIds = accounts.map((a) => a.id).toSet();
    if (!context.mounted) return;
    if (customers.isEmpty || accounts.isEmpty) {
      await _explain(
        context,
        'Before creating or editing an invoice, add an active customer in Sales → Customers and an active income account in Accounting → Chart Of Accounts.',
      );
      return;
    }
    if (invoice != null &&
        (invoice.lines.isEmpty ||
            invoice.lines.any((line) => line.categoryId == null))) {
      await _explain(
        context,
        'This older invoice uses an amount-only or product line format. Its saved data is retained. Line conversion is required before editing with this form.',
      );
      return;
    }
    // Keep saved master references readable after status changes. These extra
    // choices are display context only: commit still uses the active lists.
    final customerChoices = allCustomers
        .where((c) => c.isActive || c.id == invoice?.customerId)
        .toList();
    final savedAccountIds =
        invoice?.lines.map((line) => line.categoryId).toSet() ??
        const <EntityId?>{};
    final accountChoices = allAccounts.where(
      (a) => activeAccountIds.contains(a.id) || savedAccountIds.contains(a.id),
    );
    final id = invoice?.id ?? EntityId.random();
    final paymentTermTemplates = DemoCompany.active(context)
        ? <CompanyPaymentTerm>[]
        : workspace.paymentTerms.where((term) => term.active).toList();

    CompanyPaymentTerm? selectedPaymentTerm(Map<String, Object?> values) {
      final choice = '${values['Payment Terms'] ?? ''}';
      if (!isCompanyPaymentTermChoice(choice)) return null;
      final selected = paymentTermTemplates
          .where((term) => companyPaymentTermChoice(term) == choice)
          .firstOrNull;
      if (selected == null) {
        throw StateError('The selected company payment term is unavailable.');
      }
      final current = workspace.paymentTerms
          .where((term) => term.id == selected.id)
          .firstOrNull;
      if (current == null ||
          !current.active ||
          current.revision != selected.revision ||
          jsonEncode(current.rule.toJson()) !=
              jsonEncode(selected.rule.toJson())) {
        throw StateError(
          'The selected company payment term changed. Reopen the invoice.',
        );
      }
      return selected;
    }

    DesignForm currentForm() => invoiceForm(
      {
        for (final c in customerChoices)
          c.id.value:
              '${c.displayName}${customerChoices.where((other) => other.displayName == c.displayName).length > 1 ? ' · ${c.id.value.substring(0, 8)}' : ''}${c.isActive ? '' : ' · Inactive'}',
      },
      {
        for (final a in accountChoices)
          a.id.value:
              '${a.code} · ${a.name}${activeAccountIds.contains(a.id) ? '' : switch (a.status) {
                      AccountStatus.locked => ' · Locked',
                      AccountStatus.archived => ' · Archived',
                      AccountStatus.active => ' · Unavailable',
                    }}',
      },
      preferences: workspace.preferences,
      existing: invoice,
      paymentTermTemplates: paymentTermTemplates,
      counterpartyCurrencies: {
        for (final c in customerChoices) c.id.value: c.currency.code,
      },
      counterpartyCustomTerms: {
        for (final c in customers)
          if (c.paymentTerms.kind == PaymentTermKind.custom)
            c.id.value: c.paymentTerms.customText!,
      },
      defaultCurrencyCode: workspace.identity.currency,
      itemChoices: {
        for (final item in workspace.catalogueItems) item.id.value: item.name,
        for (final line in invoice?.lines ?? <SalesLineItem>[])
          if (line.catalogue != null)
            line.catalogue!.itemId.value: line.catalogue!.itemName,
      },
      taxChoices: {
        for (final code in workspace.taxRates) code.choice: code.label,
        for (final rate in {
          '0',
          ...workspace.catalogueItems.map((i) => i.taxRatePercent),
          for (final line in invoice?.lines ?? <SalesLineItem>[])
            if (line.taxRatePercent != null) line.taxRatePercent!,
        })
          rate: rate == '0' ? 'No Tax' : '$rate%',
      },
    );
    final editorCompany = workspace.identity.businessId;
    Future<(Invoice, Customer, String)> resolveDocument(
      Map<String, Object?> values,
    ) async {
      if (workspace.identity.businessId != editorCompany) {
        throw StateError('Company changed. Reopen the document.');
      }
      final currentAccounts = await workspace.accounts();
      final customer = workspace
          .customers()
          .where((c) => c.isActive && c.id.value == values['Counterparty'])
          .firstOrNull;
      if (customer == null) throw StateError('Choose an active customer.');
      final draft = invoiceFromForm(
        values,
        existing: invoice,
        paymentTermTemplates: paymentTermTemplates,
        taxCodes: workspace.taxRates,
        catalogueItems: workspace.catalogueItems,
        catalogueCategories: workspace.catalogueCategories,
        requireCatalogueItem: invoiceUsesCatalogueItems(invoice),
        id: id,
        customer: customer,
        incomeAccountIds: currentAccounts
            .map((stored) => stored.account)
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
      final ids = draft.lines
          .map((line) => line.categoryId)
          .whereType<EntityId>()
          .toSet();
      final categoryCode = ids.length == 1
          ? currentAccounts
                    .where((a) => a.account.id == ids.single)
                    .firstOrNull
                    ?.account
                    .code ??
                ''
          : '';
      return (draft, customer, categoryCode);
    }

    final contentWidth = frontendTransactionContentWidth(
      context,
      currentForm(),
      lines: List<Map<String, String>>.from(
        invoice == null ? [] : invoiceFormValues(invoice)['_lines'] as List,
      ),
    );
    await AccountingDialog.showFixed<Map<String, Object?>>(
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
        attachmentSetupKind: SetupKind.invoice,
        attachmentCategoryCode: (lines) {
          final ids = lines
              .map((line) => line['Account'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet();
          return ids.length == 1
              ? accounts
                        .where((account) => account.id.value == ids.single)
                        .firstOrNull
                        ?.code ??
                    ''
              : '';
        },
        lineDefaults: {
          'Quantity': '1',
          'Discount': '0',
          'Account':
              accounts.any(
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
        initial: invoice == null
            ? {
                'Document Number': workspace.database.allocateDocumentNumber(
                  businessId: workspace.identity.businessId,
                  actorId: workspace.identity.ownerId,
                  recordId: id,
                  documentType: 'invoice',
                  allocatedAt: DateTime.now().toUtc(),
                ),
                'Date': formatAccountingInputDate(DateTime.now()),
                // An omitted due date is derived from the selected customer's
                // payment terms when the draft is saved.
                'Due Date': '',
                'Currency': 'Use Counterparty Default',
                'Payment Terms': 'Use Customer Default',
                'Tax Mode': 'Review Needed',
              }
            : {
                ...invoiceFormValues(invoice),
                ...documentRecurrenceInitial(
                  workspace,
                  RecurringDocumentKind.invoice,
                  invoice.id,
                ),
              },
        reviewDocumentsBuilder: (values) async {
          final (draft, customer, _) = await resolveDocument(values);
          selectedPaymentTerm(values);
          final manual = draft.attachments
              .where((a) => !a.isGenerated)
              .toList();
          if (manual.isNotEmpty) return manual;
          final rendered = await const SalesDocumentRenderer().render(
            SalesDocumentSnapshot.invoice(
              businessId: editorCompany,
              invoice: draft,
              customer: customer,
              preferences: workspace.preferences,
            ),
            filename: 'Invoice.pdf',
            previouslySaved:
                (values['_reviewedDocuments'] as List?)
                    ?.cast<ReceiptAttachment>() ??
                draft.attachments,
          );
          selectedPaymentTerm(values);
          return [rendered];
        },
        onCommit: (values) async {
          final (draft, customer, categoryCode) = await resolveDocument(values);
          selectedPaymentTerm(values);
          final filename = await documentDestinationFilename(
            kind: SetupKind.invoice,
            date: draft.issueDate,
            categoryCode: categoryCode,
            mimeType: 'application/pdf',
          );
          final selectedTerm = selectedPaymentTerm(values);
          await const GeneratedSalesDocumentService().saveInvoice(
            workspace: workspace,
            invoice: draft,
            customer: customer,
            filename: filename,
            expectedRevision: revision,
            savedAt: DateTime.now().toUtc(),
            recurrence:
                values['_documentRecurrence'] as DocumentRecurrenceRequest?,
            renderedForReview:
                (values['_reviewedDocuments'] as List?)
                    ?.cast<ReceiptAttachment>() ??
                const [],
            selectedPaymentTerm: selectedTerm,
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _receive(
    BuildContext context,
    Invoice invoice,
    int paidMinor,
    int creditedMinor,
  ) async {
    final accounts = (await workspace.accounts())
        .map((r) => r.account)
        .where(
          (a) =>
              a.type == AccountType.asset &&
              a.status == AccountStatus.active &&
              !a.isParent,
        )
        .toList();
    final payments = workspace.paymentAccounts
        .where(
          (p) =>
              p.type != PaymentAccountType.card &&
              p.currency.code == invoice.total.currency &&
              accounts.any(
                (a) =>
                    a.id ==
                    workspace.database.paymentLedgerAccount(
                      workspace.identity.businessId,
                      p.id,
                    ),
              ),
        )
        .toList();
    if (!context.mounted) return;
    if (payments.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AccountingDialog.alert(
          dialogContext,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: 'Set Up A Payment Account',
          content: const Text(
            'In Banking, link a bank or cash payment account to an active ledger account in the invoice currency, then return to receive payment.',
          ),
          actions: [],
        ),
      );
      return;
    }
    final requestId = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: invoicePaymentReviewForm(
          invoice: invoice,
          paymentAccounts: {for (final p in payments) p.id: p.displayLabel},
          paidMinor: paidMinor,
          creditedMinor: creditedMinor,
        ),
        initial: {
          'Amount': invoiceDecimal(
            Money.fromMinor(
              invoice.total.minorUnits - paidMinor - creditedMinor,
              invoice.total.currency,
            ),
          ),
          'Date': formatAccountingInputDate(DateTime.now()),
        },
        onCommit: (values) async => workspace.receiveInvoicePayment(
          requestId: requestId,
          approvedAt: approvedAt,
          customerId: invoice.customerId,
          paymentAccountId: values['Bank Account'] as String,
          bankAccountId:
              workspace.database.paymentLedgerAccount(
                workspace.identity.businessId,
                values['Bank Account'] as String,
              ) ??
              (throw StateError('Link this payment account in Banking.')),
          allocations: {
            invoice.id: Money.fromDecimal(
              values['Amount'] as String,
              invoice.total.currency,
            ),
          },
          reference: values['Reference'] as String,
          receivedAt:
              parseAccountingInputDate(values['Date'] as String) ??
              (throw const FormatException('Enter a valid payment date.')),
        ),
      ),
    );
  }

  Future<void> _view(
    BuildContext context,
    Invoice invoice,
    String number,
    String customerName,
  ) => showInvoiceDocumentPreview(
    context,
    workspace: workspace,
    invoice: invoice,
    number: number,
    customerName: customerName,
  );

  Future<void> _post(
    BuildContext context,
    Invoice invoice,
    int revision,
  ) async {
    final accounts = (await workspace.accounts())
        .map((a) => a.account)
        .where((a) => a.status == AccountStatus.active && !a.isParent)
        .toList();
    final customer = workspace
        .customers()
        .where((c) => c.id == invoice.customerId)
        .firstOrNull;
    if (!context.mounted) return;
    if (customer == null || !customer.isActive) {
      await _explain(
        context,
        'The customer is unavailable or inactive. Review the customer before posting.',
      );
      return;
    }
    final incomeIds = accounts
        .where((a) => a.type == AccountType.income)
        .map((a) => a.id)
        .toSet();
    if (invoice.lines.isEmpty ||
        invoice.lines.any((line) => !incomeIds.contains(line.categoryId))) {
      await _explain(
        context,
        'Each invoice line needs a current income-account mapping before posting. The saved draft is unchanged.',
      );
      return;
    }
    final hasTax = invoice.lines.any((line) => line.tax.isPositive);
    final requestId = EntityId.random();
    final approvedAt = DateTime.now().toUtc();
    await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: invoicePostingReviewForm(hasTax: hasTax, accounts: accounts),
        informationRows: [
          ('Customer', customer.displayName),
          ...invoiceInformationRows(
            invoice,
            accountNames: {
              for (final a in accounts) a.id: '${a.code} · ${a.name}',
            },
          ),
        ],
        initial: {
          'Document Number': invoice.documentNumber,
          'Receivable Account': workspace.preferences.text(
            'Default Accounts',
            'Receivables Account',
          ),
          'Tax Account':
              invoice.lines
                  .where(
                    (line) => line.tax.isPositive && line.taxSnapshot != null,
                  )
                  .map((line) => line.taxSnapshot!.salesAccountId.value)
                  .firstOrNull ??
              workspace.preferences.text(
                'Default Accounts',
                'Sales Tax Liability Account',
              ),
        },
        onCommit: (values) async => workspace.postInvoice(
          requestId: requestId,
          invoiceId: invoice.id,
          expectedRevision: revision,
          expectedCustomerRevision: customer.metadata.revision,
          documentNumber: values['Document Number'] as String,
          receivableAccountId: EntityId.parse(
            values['Receivable Account'] as String,
          ),
          incomeAccountId: invoice.lines.first.categoryId!,
          lineIncomeAccounts: {
            for (final line in invoice.lines) line.id: line.categoryId!,
          },
          taxAccountId: hasTax
              ? EntityId.parse(values['Tax Account'] as String)
              : null,
          approvedAt: approvedAt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
      final activeDrafts = workspace.invoiceDrafts();
      final archivedDrafts = workspace.invoiceDrafts(archived: true);
      final allPosted = workspace.postedInvoices();
      final controlCount = {
        ...activeDrafts.map((r) => r.invoice.id),
        ...archivedDrafts.map((r) => r.invoice.id),
        ...allPosted.map((r) => r.sourceDraft.id),
      }.length;
      final hasInvoices = AccountingRecordControlsPolicy.visible(controlCount);
      final status = hasInvoices ? _status : null;
      final archivedIds = archivedDrafts.map((r) => r.invoice.id).toSet();
      final allDrafts = !hasInvoices
          ? [...activeDrafts, ...archivedDrafts]
          : status == 'Archived'
          ? archivedDrafts
          : activeDrafts;
      final names = {
        for (final c in workspace.customers()) c.id: c.displayName,
      };
      bool matches(Invoice invoice, String name, String number) =>
          (!hasInvoices ||
              _currency == null ||
              invoice.total.currency == _currency) &&
          '$name $number ${invoice.reference} ${invoice.memo}'
              .toLowerCase()
              .contains(hasInvoices ? _search.toLowerCase() : '');
      final drafts = allDrafts
          .where(
            (r) =>
                (status == null || status == 'Draft' || status == 'Archived') &&
                matches(
                  r.invoice,
                  names[r.invoice.customerId] ?? '',
                  r.invoice.documentNumber,
                ),
          )
          .toList();
      final posted = allPosted
          .where(
            (r) =>
                status != 'Draft' &&
                status != 'Archived' &&
                (status == null ||
                    status ==
                        r.sourceDraft
                            .settlementStatus(
                              paidMinor: r.paidMinor,
                              creditedMinor: r.creditedMinor,
                            )
                            .label) &&
                matches(
                  r.sourceDraft,
                  r.customerSnapshot.displayName,
                  r.documentNumber,
                ),
          )
          .toList();
      return AccountingPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingPageHeader(
              routeLabel: 'Invoices',
              title: 'Invoices',
              description:
                  'Save invoice drafts and review their ledger posting.',
              action: AccountingButton.primary(
                context,
                key: const ValueKey('new-invoice'),
                child: const Text('Create Invoice'),
                onPressed: () => _edit(context),
              ),
            ),
            const SizedBox(height: accountingContentInset),
            GeneratedDocumentFilingNotice(
              workspace: workspace,
              kind: GeneratedDocumentKind.invoice,
            ),
            AccountingPageFilterBar(
              actions: [
                AccountingButton.outline(
                  context,
                  key: const ValueKey('open-recurring-transactions'),
                  onPressed: () =>
                      showRecurringTransactions(context, workspace),
                  child: const Text('Recurring'),
                ),
              ],
              children: [
                if (hasInvoices) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        accountingFieldLabel(
                          context,
                          'Search',
                          key: const ValueKey('invoice-search-label'),
                        ),
                        const SizedBox(height: accountingFieldLabelGap),
                        SizedBox(
                          height: 44,
                          child: TextField(
                            key: const ValueKey('invoice-search'),
                            textAlignVertical: TextAlignVertical.center,
                            decoration: accountingSingleLineInputDecoration(
                              context,
                              hintText: 'Name, number or reference',
                            ),
                            onChanged: (value) =>
                                setState(() => _search = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordFilter(
                    label: 'Status',
                    controlKey: const ValueKey('invoice-status-filter'),
                    options: [
                      'Draft',
                      for (final status in InvoiceSettlementStatus.values)
                        status.label,
                      'Archived',
                    ],
                    value: _status,
                    onChanged: (value) => setState(() => _status = value),
                  ),
                  AccountingRecordFilter(
                    label: 'Currency',
                    options: {
                      ...activeDrafts.map((r) => r.invoice.total.currency),
                      ...archivedDrafts.map((r) => r.invoice.total.currency),
                      ...allPosted.map((r) => r.sourceDraft.total.currency),
                    },
                    value: _currency,
                    onChanged: (value) => setState(() => _currency = value),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (drafts.isEmpty && posted.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: accountingContentInset,
                ),
                child: Text('No matching invoices.'),
              ),
            AccountingRecordList(
              paginationKey: 'invoices',
              totalCount: controlCount,
              children: [
                for (final record in drafts)
                  AccountingRecordRow(
                    key: ValueKey(record.invoice.id.value),
                    topRightInfo: true,
                    title: record.invoice.documentNumber.isEmpty
                        ? 'Invoice Draft'
                        : record.invoice.documentNumber,
                    status: AccountingBadge.build(
                      context,
                      label: archivedIds.contains(record.invoice.id)
                          ? 'Archived'
                          : 'Draft',
                    ),
                    details: Text(
                      formatAccountingInputDate(record.invoice.issueDate),
                    ),
                    trailing: Text(
                      invoiceMoney(record.invoice.total),
                      style: AccountingTypography.value(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      AccountingRecordActions(
                        actions: [
                          if (!archivedIds.contains(record.invoice.id))
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'post-invoice-${record.invoice.id.value}',
                              ),
                              icon: Icons.preview_outlined,
                              tooltip: 'Review Posting',
                              onPressed: () => _post(
                                context,
                                record.invoice,
                                record.revision,
                              ),
                            ),
                        ],
                        trailing: [
                          ..._attachments(context, record.invoice),
                          if (!archivedIds.contains(record.invoice.id))
                            AccountingButton.outline(
                              context,
                              key: ValueKey(
                                'edit-invoice-${record.invoice.id.value}',
                              ),
                              child: const Text('Edit'),
                              onPressed: () => _edit(
                                context,
                                invoice: record.invoice,
                                revision: record.revision,
                              ),
                            ),
                          if (archivedIds.contains(record.invoice.id))
                            AccountingButton.outline(
                              context,
                              key: ValueKey(
                                'view-archived-invoice-${record.invoice.id.value}',
                              ),
                              child: const Text('View'),
                              onPressed: () => _view(
                                context,
                                record.invoice,
                                record.invoice.documentNumber,
                                names[record.invoice.customerId] ?? '',
                              ),
                            ),
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'archive-invoice-${record.invoice.id.value}',
                            ),
                            icon: archivedIds.contains(record.invoice.id)
                                ? Icons.restore
                                : Icons.delete_outline,
                            tooltip: archivedIds.contains(record.invoice.id)
                                ? 'Restore invoice draft'
                                : 'Archive invoice draft',
                            onPressed: () => _archive(
                              context,
                              record.invoice,
                              record.revision,
                              !archivedIds.contains(record.invoice.id),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                for (final record in posted)
                  AccountingRecordRow(
                    key: ValueKey(record.sourceDraft.id.value),
                    topRightInfo: true,
                    title: record.documentNumber,
                    status: AccountingBadge.build(
                      context,
                      label: record.sourceDraft
                          .settlementStatus(
                            paidMinor: record.paidMinor,
                            creditedMinor: record.creditedMinor,
                          )
                          .label,
                    ),
                    statusWidth: AccountingBadge.measuredWidth(
                      context,
                      record.sourceDraft
                          .settlementStatus(
                            paidMinor: record.paidMinor,
                            creditedMinor: record.creditedMinor,
                          )
                          .label,
                    ),
                    compactStatus:
                        record.sourceDraft
                            .settlementStatus(
                              paidMinor: record.paidMinor,
                              creditedMinor: record.creditedMinor,
                            )
                            .label
                            .startsWith('Partially')
                        ? Tooltip(
                            message: record.sourceDraft
                                .settlementStatus(
                                  paidMinor: record.paidMinor,
                                  creditedMinor: record.creditedMinor,
                                )
                                .label,
                            child: AccountingBadge.build(
                              context,
                              label: record.sourceDraft
                                  .settlementStatus(
                                    paidMinor: record.paidMinor,
                                    creditedMinor: record.creditedMinor,
                                  )
                                  .compactLabel,
                            ),
                          )
                        : null,
                    details: Text(record.customerSnapshot.displayName),
                    trailing: Text(
                      invoiceMoney(record.sourceDraft.total),
                      style: AccountingTypography.value(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      AccountingRecordActions(
                        actions: [
                          if (record.paidMinor + record.creditedMinor <
                              record.sourceDraft.total.minorUnits)
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'receive-invoice-${record.sourceDraft.id.value}',
                              ),
                              icon: Icons.attach_money,
                              tooltip: 'Receive Payment',
                              onPressed: () => _receive(
                                context,
                                record.sourceDraft,
                                record.paidMinor,
                                record.creditedMinor,
                              ),
                            ),
                        ],
                        trailing: [
                          ..._attachments(context, record.sourceDraft),
                          AccountingButton.outline(
                            context,
                            key: ValueKey(
                              'view-invoice-${record.sourceDraft.id.value}',
                            ),
                            child: const Text('View'),
                            onPressed: () => _view(
                              context,
                              record.sourceDraft,
                              record.documentNumber,
                              record.customerSnapshot.displayName,
                            ),
                          ),
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'locked-invoice-${record.sourceDraft.id.value}',
                            ),
                            onPressed: null,
                            icon: Icons.delete_outline,
                            tooltip: 'Posted invoices cannot be deleted. A reversal workflow is required.',
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

class _InvoiceDocumentPreview extends StatelessWidget {
  const _InvoiceDocumentPreview({
    required this.number,
    required this.heading,
    required this.rows,
    required this.footer,
    this.logo,
  });
  final String number, heading, footer;
  final List<(String, String)> rows;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    const baseWidth = 960.0;
    const contentWidth = baseWidth;
    final bodyStyle = AccountingTypography.value(context);
    final labelStyle = AccountingTypography.sidewaysDetailsLabel(context);
    Size textSize(
      String text,
      TextStyle? style, {
      double maxWidth = double.infinity,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: maxWidth);
      return painter.size;
    }

    final labelWidth = rows.fold<double>(
      0,
      (width, row) => math.max(
        width,
        math.min(
          AccountingSidewaysDetailsTokens.maximumLabelWidth,
          textSize(row.$1, labelStyle).width,
        ),
      ),
    );
    final valueWidth =
        contentWidth -
        2 * AccountingSidewaysDetailsTokens.horizontalInset -
        labelWidth -
        AccountingSidewaysDetailsTokens.columnGap -
        textSize(AccountingSidewaysDetailsTokens.separator, bodyStyle).width -
        AccountingSidewaysDetailsTokens.columnGap;
    final rowHeight = rows.fold<double>(
      0,
      (height, row) =>
          height +
          math.max(
            textSize(row.$1, labelStyle, maxWidth: labelWidth).height,
            textSize(row.$2, bodyStyle, maxWidth: valueWidth).height,
          ) +
          2 * AccountingSidewaysDetailsTokens.rowVerticalInset,
    );
    final baseHeight =
        (logo == null ? 0 : 64) +
        rowHeight +
        (rows.isEmpty
            ? 0
            : 2 *
                  (AccountingSidewaysDetailsTokens.edgeVerticalInset -
                      AccountingSidewaysDetailsTokens.rowVerticalInset)) +
        (footer.isEmpty
            ? 0
            : 20 + textSize(footer, bodyStyle, maxWidth: contentWidth).height);
    return AccountingDialog.fitted(
      context,
      key: const ValueKey('invoice-document-dialog'),
      title: number,
      description: heading.isEmpty ? null : heading,
      preserveTitleCase: true,
      contentBuilder: (context, available) {
        final scale = math.min(
          math.min(baseWidth, available.width) / baseWidth,
          available.height / baseHeight,
        );
        final width = baseWidth * scale;
        final pageHeight = baseHeight * scale;
        return SizedBox(
          width: available.width,
          height: pageHeight,
          child: AccountingImageZoom(
            child: Center(
              child: SizedBox(
                key: const ValueKey('invoice-document-page'),
                width: width,
                height: pageHeight,
                child: FittedBox(
                  child: SizedBox(
                    width: baseWidth,
                    height: baseHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (logo != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Image.memory(
                              logo!,
                              height: 48,
                              semanticLabel: 'Business logo',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        AccountingInformationRows(rows: rows),
                        if (footer.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(footer, style: bodyStyle),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String invoiceBusinessHeading(CompanyPreferences preferences) =>
    preferences.text('Business Profile', 'Business Name').isNotEmpty
    ? preferences.text('Business Profile', 'Business Name')
    : preferences.text('Business Profile', 'Legal Name');

List<(String, String)> invoiceBusinessInformationRows(
  CompanyPreferences preferences,
) => [
  for (final key in [
    'Legal Name',
    'Address Line 1',
    'Address Line 2',
    'City',
    'State / Region',
    'Postcode',
    'Country',
    'Country Name',
    'Email',
    'Telephone',
    'Website',
  ])
    if (preferences.text('Business Profile', key).isNotEmpty &&
        (key != 'Country Name' ||
            preferences.text('Business Profile', 'Country') ==
                'Other Country') &&
        (key != 'Legal Name' ||
            preferences.text('Business Profile', key) !=
                invoiceBusinessHeading(preferences)))
      (key, preferences.text('Business Profile', key)),
  if (preferences.enabled(
        'Numbering & Document Appearance',
        'Show Registration',
      ) &&
      preferences.text('Business Profile', 'Registration Number').isNotEmpty)
    (
      'Registration',
      preferences.text('Business Profile', 'Registration Number'),
    ),
];

List<(String, String)> invoiceInformationRows(
  Invoice invoice, {
  Map<EntityId, String> accountNames = const {},
  CompanyPreferences? preferences,
  bool document = false,
}) => [
  ('Total', invoiceMoney(invoice.total)),
  ('Issued', formatAccountingInputDate(invoice.issueDate)),
  ('Due', formatAccountingInputDate(invoice.dueDate)),
  ('Terms', invoice.terms.label),
  if (invoice.reference.isNotEmpty) ('Reference', invoice.reference),
  if (invoice.classification.isNotEmpty) ('Class', invoice.classification),
  if (invoice.location.isNotEmpty) ('Location', invoice.location),
  if (invoice.memo.isNotEmpty) ('Memo', invoice.memo),
  (
    'Tax Mode',
    invoice.taxMode.isEmpty ? 'Legacy / Review Required' : invoice.taxMode,
  ),
  for (var i = 0; i < invoice.lines.length; i++) ...[
    ('Line ${i + 1}', invoice.lines[i].description),
    if (invoice.lines[i].rateEnabled)
      (
        'Quantity × Rate',
        '${invoice.lines[i].quantity} × ${invoiceMoney(invoice.lines[i].rate)}',
      )
    else
      ('Quantity', '${invoice.lines[i].quantity}'),
    if (invoice.lines[i].pricingAdjustment.minorUnits != 0)
      ('Pricing Adjustment', invoiceMoney(invoice.lines[i].pricingAdjustment)),
    ('Discount', invoiceMoney(invoice.lines[i].discount)),
    (
      'Tax Rate',
      '${invoice.lines[i].taxInclusive ? 'Inclusive' : 'Exclusive'} · ${invoice.lines[i].taxRatePercent == null ? 'Not Retained' : '${invoice.lines[i].taxRatePercent}%'}',
    ),
    ('Net', invoiceMoney(invoice.lines[i].subtotal)),
    ('Tax', invoiceMoney(invoice.lines[i].tax)),
    ('Line Total', invoiceMoney(invoice.lines[i].total)),
    if (accountNames.isNotEmpty)
      (
        'Income Account (Current Name)',
        accountNames[invoice.lines[i].categoryId] ?? 'Unavailable',
      ),
  ],
];

String invoiceDisplaySummary(
  Invoice invoice, {
  required CompanyPreferences preferences,
  Map<EntityId, String> accountNames = const {},
  bool document = false,
}) => [
  'Total: ${invoiceMoney(invoice.total)}',
  'Issued: ${formatAccountingInputDate(invoice.issueDate)} · Due: ${formatAccountingInputDate(invoice.dueDate)}',
  'Terms: ${invoice.terms.label}',
  if (invoice.reference.isNotEmpty) 'Reference: ${invoice.reference}',
  if (invoice.classification.isNotEmpty) 'Class: ${invoice.classification}',
  if (invoice.location.isNotEmpty) 'Location: ${invoice.location}',
  if (invoice.memo.isNotEmpty) 'Memo: ${invoice.memo}',
  'Tax Mode: ${invoice.taxMode.isEmpty ? 'Legacy / Review Required' : invoice.taxMode}',
  for (final line in invoice.lines) ...[
    '\n${line.description}',
    line.rateEnabled
        ? 'Quantity ${line.quantity} × ${invoiceDecimal(line.rate)}'
        : 'Quantity ${line.quantity}',
    if (line.pricingAdjustment.minorUnits != 0)
      'Pricing adjustment ${invoiceDecimal(line.pricingAdjustment)}',
    'Discount ${invoiceDecimal(line.discount)}',
    '${line.taxInclusive ? 'Inclusive' : 'Exclusive'} · Tax rate ${line.taxRatePercent == null ? 'not retained' : '${line.taxRatePercent}%'}',
    'Net ${invoiceDecimal(line.subtotal)} + tax ${invoiceDecimal(line.tax)} = ${invoiceDecimal(line.total)}',
    if (accountNames.isNotEmpty)
      'Income account (current name): ${accountNames[line.categoryId] ?? 'Unavailable'}',
  ],
].join('\n');

Future<void> showInvoicePreferencesPreview(
  BuildContext context,
  AccountingWorkspace workspace,
  CompanyPreferences preferences,
) async {
  final drafts = workspace.invoiceDrafts();
  if (drafts.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => _InvoiceDocumentPreview(
        number: 'Invoice Appearance Preview',
        logo:
            preferences.enabled(
                  'Numbering & Document Appearance',
                  'Show Logo',
                ) &&
                preferences
                    .text('Business Profile', '_businessLogoBase64')
                    .isNotEmpty
            ? base64Decode(
                preferences.text('Business Profile', '_businessLogoBase64'),
              )
            : null,
        heading: invoiceBusinessHeading(preferences),
        rows: [
          ...invoiceBusinessInformationRows(preferences),
          if (preferences.enabled('Sales Preferences', 'Show Rate'))
            ('Quantity × Rate', '1 × 100.00')
          else if (preferences.enabled('Sales Preferences', 'Show Quantity'))
            ('Quantity', '1'),
          if (preferences.enabled('Sales Preferences', 'Enable Discounts'))
            ('Discount', '0.00'),
          if (preferences.enabled(
            'Numbering & Document Appearance',
            'Show Tax Breakdown',
          )) ...[
            ('Net', '100.00'),
            ('Tax', '0.00'),
          ],
          ('Line Total', '100.00'),
        ],
        footer:
            '${preferences.text('Sales Preferences', 'Customer Message')}\n${preferences.text('Numbering & Document Appearance', 'Footer')}\nSample amounts for appearance only.',
      ),
    );
    return;
  }
  final invoice = drafts.first.invoice;
  final customer = workspace
      .customers()
      .where((customer) => customer.id == invoice.customerId)
      .firstOrNull;
  await showDialog<void>(
    context: context,
    builder: (context) => _InvoiceDocumentPreview(
      number: invoice.documentNumber,
      logo:
          preferences.enabled('Numbering & Document Appearance', 'Show Logo') &&
              preferences
                  .text('Business Profile', '_businessLogoBase64')
                  .isNotEmpty
          ? base64Decode(
              preferences.text('Business Profile', '_businessLogoBase64'),
            )
          : null,
      heading: invoiceBusinessHeading(preferences),
      rows: [
        ...invoiceBusinessInformationRows(preferences),
        ('Customer', customer?.displayName ?? 'Customer'),
        ...invoiceInformationRows(
          invoice,
          preferences: preferences,
          document: true,
        ),
      ],
      footer:
          '${preferences.text('Sales Preferences', 'Customer Message')}\n${preferences.text('Numbering & Document Appearance', 'Footer')}',
    ),
  );
}

List<(String, String)> quotationInformationRows(
  Estimate quotation, {
  required CompanyPreferences preferences,
  bool document = false,
}) => [
  for (final row in invoiceInformationRows(
    quotation.pricingSnapshot(),
    preferences: preferences,
    document: document,
  )) ...[
    if (row.$1 != 'Due') row,
    if (row.$1 == 'Issued')
      ('Valid Until', formatAccountingInputDate(quotation.validUntil)),
  ],
];

Future<void> showQuotationDocumentPreview(
  BuildContext context,
  Estimate quotation, {
  required CompanyPreferences preferences,
  required String customerName,
}) => showDialog<void>(
  context: context,
  builder: (context) => _InvoiceDocumentPreview(
    number: quotation.documentNumber,
    logo:
        preferences.enabled('Numbering & Document Appearance', 'Show Logo') &&
            preferences
                .text('Business Profile', '_businessLogoBase64')
                .isNotEmpty
        ? base64Decode(
            preferences.text('Business Profile', '_businessLogoBase64'),
          )
        : null,
    heading: invoiceBusinessHeading(preferences),
    rows: [
      ...invoiceBusinessInformationRows(preferences),
      ('Customer', customerName),
      ...quotationInformationRows(
        quotation,
        preferences: preferences,
        document: true,
      ),
    ],
    footer:
        '${preferences.text('Sales Preferences', 'Customer Message')}\n${preferences.text('Numbering & Document Appearance', 'Footer')}',
  ),
);

Future<void> showInvoiceDocumentPreview(
  BuildContext context, {
  required AccountingWorkspace workspace,
  required Invoice invoice,
  required String number,
  required String customerName,
}) async {
  final accounts = await workspace.accounts();
  final receipts = workspace.database.invoiceReceipts(
    workspace.identity.businessId,
    invoice.id,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _InvoiceDocumentPreview(
      number: number,
      logo:
          workspace.preferences.enabled(
                'Numbering & Document Appearance',
                'Show Logo',
              ) &&
              workspace.preferences
                  .text('Business Profile', '_businessLogoBase64')
                  .isNotEmpty
          ? base64Decode(
              workspace.preferences.text(
                'Business Profile',
                '_businessLogoBase64',
              ),
            )
          : null,
      heading: invoiceBusinessHeading(workspace.preferences),
      rows: [
        ...invoiceBusinessInformationRows(workspace.preferences),
        ('Customer', customerName),
        ...invoiceInformationRows(
          invoice,
          preferences: workspace.preferences,
          document: true,
          accountNames: {
            for (final a in accounts)
              a.account.id: '${a.account.code} · ${a.account.name}',
          },
        ),
        for (var i = 0; i < receipts.length; i++) ...[
          ('Payment ${i + 1}', formatAccountingInputDate(receipts[i].date)),
          ('Payment Reference', receipts[i].reference),
          ('Payment Amount', invoiceMoney(receipts[i].amount)),
        ],
      ],
      footer: [
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        workspace.preferences.text('Numbering & Document Appearance', 'Footer'),
      ].where((text) => text.isNotEmpty).join('\n'),
    ),
  );
}
