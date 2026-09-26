// Isolated receipt-entry proposal. Domain and persistence remain canonical owners.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/accounting_description_field.dart';
import '../../../app/responsive.dart';
import '../../../app/transaction_form_layout.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/documents/receipt_document.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/currency_presentation.dart';
import '../../../core/money/money.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/company_tax_rate.dart';
import '../../accounting/domain/expense_draft.dart';
import '../../accounting/presentation/widgets/accounting_formatters.dart';
import '../../sales/domain/sales_line_item.dart';
import '../domain/claim_receipt.dart';

class ClaimReceiptLineInput {
  ClaimReceiptLineInput({ClaimReceiptLine? initial})
    : id = initial?.item.id ?? EntityId.random().value,
      saved = initial,
      accountId = initial?.expenseAccountId,
      category = initial?.item.category ?? '',
      tax = initial?.item.tax ?? '0',
      snapshot = initial?.item.taxSnapshot,
      adjustment = initial?.item.pricingAdjustment,
      description = TextEditingController(
        text: initial?.item.description ?? '',
      ),
      amount = TextEditingController(text: initial?.item.amount ?? ''),
      quantity = TextEditingController(text: initial?.item.quantity ?? ''),
      rate = TextEditingController(text: initial?.item.rate ?? '');
  final String id;
  final ClaimReceiptLine? saved;
  EntityId? accountId;
  String category, tax;
  CompanyTaxRate? snapshot;
  String? adjustment;
  final TextEditingController description, amount, quantity, rate;
  void dispose() {
    for (final c in [description, amount, quantity, rate]) {
      c.dispose();
    }
  }
}

class ClaimReceiptInput {
  ClaimReceiptInput({ClaimReceipt? initial, required DateTime date})
    : id = initial?.id ?? EntityId.random().value,
      merchant = TextEditingController(text: initial?.merchant ?? ''),
      date = TextEditingController(
        text: formatAccountingInputDate(initial?.date ?? date),
      ),
      basis = initial?.taxMode ?? 'Exclusive',
      originals = [...?initial?.originalDocumentIds],
      lines = initial == null
          ? [ClaimReceiptLineInput()]
          : [for (final l in initial.lines) ClaimReceiptLineInput(initial: l)];
  final String id;
  final TextEditingController merchant, date;
  String basis;
  final List<String> originals;
  final List<ClaimReceiptLineInput> lines;
  void dispose() {
    merchant.dispose();
    date.dispose();
    for (final l in lines) {
      l.dispose();
    }
  }
}

/// Unsaved controller state never masquerades as a valid stored ClaimReceipt.
/// Build delegates all financial/pricing validation to the domain owners.
class ClaimReceiptsDraft extends ChangeNotifier {
  ClaimReceiptsDraft({
    required this.currency,
    required DateTime date,
    List<ClaimReceipt> initial = const [],
  }) : defaultDate = date,
       receipts = [
         for (final r in initial) ClaimReceiptInput(initial: r, date: date),
       ] {
    for (final r in receipts) {
      _listen(r);
    }
  }
  final String currency;
  final DateTime defaultDate;
  final List<ClaimReceiptInput> receipts;
  void changed() => notifyListeners();
  void _listen(ClaimReceiptInput r) {
    r.merchant.addListener(changed);
    r.date.addListener(changed);
    for (final l in r.lines) {
      _listenLine(l);
    }
  }

  void _listenLine(ClaimReceiptLineInput l) {
    for (final c in [l.description, l.amount, l.quantity, l.rate]) {
      c.addListener(changed);
    }
  }

  void addReceipt({String? originalId}) {
    final r = ClaimReceiptInput(date: defaultDate);
    if (originalId != null) r.originals.add(originalId);
    _listen(r);
    receipts.add(r);
    changed();
  }

  void removeReceipt(ClaimReceiptInput r) {
    receipts.remove(r);
    r.dispose();
    changed();
  }

  void addLine(ClaimReceiptInput r) {
    final l = ClaimReceiptLineInput();
    _listenLine(l);
    r.lines.add(l);
    changed();
  }

  void removeLine(ClaimReceiptInput r, ClaimReceiptLineInput l) {
    r.lines.remove(l);
    l.dispose();
    changed();
  }

  String get merchantSummary {
    final values = receipts
        .map((r) => r.merchant.text.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return values.isEmpty
        ? ''
        : values.length == 1
        ? values.single
        : 'Multiple Merchants';
  }

  ExpenseDraftLine item(
    ClaimReceiptInput r,
    ClaimReceiptLineInput l,
    List<CompanyTaxRate> codes,
  ) {
    final date = parseAccountingInputDate(r.date.text);
    if (date == null) throw const FormatException('Enter the receipt date.');
    final snapshot = resolveTaxChoice(
      l.tax,
      codes: codes,
      date: date,
      purpose: TaxApplication.purchases,
      saved: l.saved?.item.taxSnapshot,
    );
    if (l.tax != '0' && l.tax != 'No tax' && snapshot == null) {
      throw const FormatException('Select the row tax.');
    }
    return ExpenseDraftLine(
      id: l.id,
      category: l.category,
      description: l.description.text,
      tax: l.tax,
      taxSnapshot: snapshot,
      amount: l.amount.text.replaceAll(',', ''),
      quantity: l.quantity.text.isEmpty ? null : l.quantity.text,
      rate: l.rate.text.isEmpty ? null : l.rate.text.replaceAll(',', ''),
      pricingAdjustment: l.adjustment,
    );
  }

  ({Money net, Money tax, Money total})? totals(
    ClaimReceiptInput r,
    List<CompanyTaxRate> codes,
  ) {
    try {
      var net = Money.zero(currency),
          tax = Money.zero(currency),
          total = Money.zero(currency);
      for (final l in r.lines) {
        final a = item(r, l, codes).calculation(currency, r.basis);
        net += a.net;
        tax += a.tax;
        total += a.total;
      }
      return (net: net, tax: tax, total: total);
    } on Object {
      return null;
    }
  }

  Money? gross(List<CompanyTaxRate> codes) {
    var total = Money.zero(currency);
    for (final r in receipts) {
      final t = totals(r, codes);
      if (t == null) return null;
      total += t.total;
    }
    return total;
  }

  List<ClaimReceipt> build(
    List<Account> accounts,
    List<CompanyTaxRate> codes,
    List<ReceiptAttachment> evidence,
  ) {
    if (receipts.isEmpty) {
      throw const FormatException('Add at least one receipt.');
    }
    return [for (final r in receipts) _build(r, accounts, codes, evidence)];
  }

  ClaimReceipt _build(
    ClaimReceiptInput r,
    List<Account> accounts,
    List<CompanyTaxRate> codes,
    List<ReceiptAttachment> evidence,
  ) {
    final date = parseAccountingInputDate(r.date.text);
    if (date == null) throw const FormatException('Enter the receipt date.');
    if (r.originals.any(
      (id) => !evidence.any((e) => e.originalId == id && !e.reviewSkipped),
    )) {
      throw const FormatException(
        'Link each receipt to an available original document.',
      );
    }
    return ClaimReceipt(
      id: r.id,
      merchant: r.merchant.text,
      date: date,
      currency: currency,
      taxMode: r.basis,
      originalDocumentIds: r.originals,
      lines: [
        for (final l in r.lines)
          () {
            final a = accounts.where((a) => a.id == l.accountId).firstOrNull;
            if (a == null ||
                a.isParent ||
                ![AccountType.expense, AccountType.asset].contains(a.type) ||
                (a.status != AccountStatus.active &&
                    l.saved?.expenseAccountId != a.id)) {
              throw const FormatException(
                'Choose an expense or asset category for each row.',
              );
            }
            return ClaimReceiptLine(
              expenseAccountId: a.id,
              item: item(r, l, codes),
            );
          }(),
      ],
    );
  }

  void reprice(ClaimReceiptLineInput l, String edited) {
    if (l.rate.text.isEmpty && edited == 'Amount') {
      changed();
      return;
    }
    try {
      if (l.quantity.text.isEmpty && edited == 'Rate') l.quantity.text = '1';
      final quantity = SalesQuantity.fromDecimal(l.quantity.text);
      if (edited == 'Amount') {
        final amount = Money.fromDecimal(
          l.amount.text.replaceAll(',', ''),
          currency,
        );
        final rate = quantity.rateFor(amount);
        l.rate.text = rate.toDecimalString();
        l.adjustment = (amount - quantity.multiply(rate)).toDecimalString();
      } else {
        final rate = Money.fromDecimal(
          l.rate.text.replaceAll(',', ''),
          currency,
        );
        l.amount.text = quantity.multiply(rate).toDecimalString();
        l.adjustment = null;
      }
    } on Object {
      /* Keep incomplete edits; the existing domain validates Save. */
    }
    changed();
  }

  @override
  void dispose() {
    for (final r in receipts) {
      r.dispose();
    }
    super.dispose();
  }
}

class ClaimReceiptsEditor extends StatelessWidget {
  const ClaimReceiptsEditor({
    super.key,
    required this.draft,
    required this.accounts,
    required this.codes,
    required this.evidence,
    this.readOnly = false,
    required this.onAddReceipt,
    required this.onLinkOriginal,
    required this.evidenceSection,
  });
  final VoidCallback? onAddReceipt;
  final void Function(ClaimReceiptInput)? onLinkOriginal;
  final Widget evidenceSection;
  final ClaimReceiptsDraft draft;
  final List<Account> accounts;
  final List<CompanyTaxRate> codes;
  final List<ReceiptAttachment> evidence;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => AccountingButtonSizeScope(
    child: Builder(
      builder: (context) => ListenableBuilder(
        listenable: draft,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      accountingSectionTitle(context, 'Receipts'),
                      const SizedBox(width: 4),
                      const AccountingFieldHelp(
                        label: 'Receipts',
                        message: 'Each receipt has its own amount basis and row tax codes. Link its original document before saving.',
                      ),
                    ],
                  ),
                ),
                if (!readOnly && draft.receipts.isNotEmpty)
                  AccountingButton.iconOnly(
                    context,
                    key: const ValueKey('claim-add-receipt'),
                    tooltip: 'Add Receipt',
                    icon: Icons.file_upload_outlined,
                    onPressed: onAddReceipt,
                  ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            evidenceSection,
            for (var i = 0; i < draft.receipts.length; i++) ...[
              const SizedBox(height: AccountingResponsive.sectionGap),
              _receipt(context, draft.receipts[i], i),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _labelled(BuildContext context, String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(context, label),
      const SizedBox(height: accountingFieldLabelGap),
      child,
    ],
  );
  Widget _receipt(BuildContext context, ClaimReceiptInput r, int index) =>
      Column(
        key: ValueKey('claim-receipt-${r.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: accountingContentInset),
          Row(
            key: ValueKey('receipt-heading-${r.id}'),
            children: [
              Expanded(
                child: accountingSectionTitle(context, 'Receipt ${index + 1}'),
              ),
              if (!readOnly && r.originals.isNotEmpty) ...[
                AccountingButton.iconOnly(
                  context,
                  key: ValueKey('receipt-add-original-${r.id}'),
                  tooltip: 'Link Another Original',
                  icon: Icons.file_upload_outlined,
                  onPressed: onLinkOriginal == null
                      ? null
                      : () => onLinkOriginal!(r),
                ),
                const SizedBox(width: AccountingResponsive.actionGap),
              ],
              if (!readOnly)
                AccountingButton.iconOnly(
                  context,
                  key: ValueKey('claim-remove-receipt-${r.id}'),
                  tooltip: 'Remove Receipt ${index + 1}',
                  icon: Icons.delete_outline,
                  onPressed: () => draft.removeReceipt(r),
                ),
            ],
          ),
          const SizedBox(height: accountingFieldLabelGap),
          _labelled(
            context,
            'Merchant',
            TextFormField(
              key: ValueKey('receipt-merchant-${r.id}'),
              controller: r.merchant,
              readOnly: readOnly,
              decoration: accountingInputDecoration(
                context,
                hintText: 'Merchant or supplier',
              ),
            ),
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labelled(
                  context,
                  'Receipt Date',
                  accountingDateFieldFrame(
                    child: TextFormField(
                      key: ValueKey('receipt-date-${r.id}'),
                      controller: r.date,
                      readOnly: readOnly,
                      inputFormatters: const [DateInputFormatter()],
                      keyboardType: TextInputType.number,
                      decoration: accountingInputDecoration(
                        context,
                        hintText: 'DD-MM-YYYY',
                        suffixIcon: accountingCalendarButton(
                          context,
                          controller: r.date,
                          label: 'Receipt Date',
                          enabled: !readOnly,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          onPicked: draft.changed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AccountingResponsive.groupGap),
              Expanded(
                child: _labelled(
                  context,
                  'Amounts Are',
                  AccountingSelector<String>(
                    assignedWidth: double.infinity,
                    triggerKey: ValueKey('receipt-basis-${r.id}'),
                    menuKey: ValueKey('receipt-basis-menu-${r.id}'),
                    value: r.basis,
                    hintText: 'Select amount basis',
                    enabled: !readOnly,
                    options: const [
                      AccountingSelectorOption(
                        value: 'Exclusive',
                        label: 'Tax Exclusive',
                      ),
                      AccountingSelectorOption(
                        value: 'Inclusive',
                        label: 'Tax Inclusive',
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        r.basis = v;
                        draft.changed();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          if (!readOnly &&
              (r.originals.isEmpty ||
                  r.originals.any(
                    (id) => !evidence.any((e) => e.originalId == id),
                  )))
            _labelled(
              context,
              'Original Document',
              AccountingSelector<String>(
                assignedWidth: double.infinity,
                triggerKey: ValueKey('receipt-original-${r.id}-missing'),
                menuKey: ValueKey('receipt-original-menu-${r.id}-missing'),
                hintText: 'Select original document',
                value: null,
                enabled: !readOnly,
                options: [
                  for (final e in evidence.where((e) => !e.reviewSkipped))
                    AccountingSelectorOption(
                      value: e.originalId,
                      label: e.filename,
                      preserveLabelCase: true,
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  r.originals.removeWhere(
                    (id) => !evidence.any((e) => e.originalId == id),
                  );
                  if (!r.originals.contains(v)) r.originals.add(v);
                  draft.changed();
                },
              ),
            ),
          const SizedBox(height: AccountingResponsive.sectionGap),
          _grid(context, r),
          const SizedBox(height: AccountingResponsive.sectionGap),
          AccountingMemoSummary(
            key: ValueKey('receipt-summary-${r.id}'),
            summaryLabelInset: accountingContentInset,
            rows: [
              for (final pair in [
                ('Subtotal', draft.totals(r, codes)?.net),
                ('Tax', draft.totals(r, codes)?.tax),
                ('Receipt Total', draft.totals(r, codes)?.total),
              ])
                (
                  pair.$1,
                  pair.$2 == null
                      ? '—'
                      : formatAccountingMoney(context, pair.$2!),
                ),
            ],
            valueKeys: [
              for (final label in ['Subtotal', 'Tax', 'Receipt Total'])
                ValueKey('receipt-$label-${r.id}'),
            ],
          ),
        ],
      );
  Widget _grid(BuildContext context, ClaimReceiptInput r) => LayoutBuilder(
    builder: (context, constraints) {
      final categoryWidth = AccountingTransactionGridTokens.selectionWidth(
        context,
        'Select Category',
        selectedLabels: r.lines.map(
          (line) => accounts
              .where((account) => account.id == line.accountId)
              .firstOrNull
              ?.displayName,
        ),
      );
      final taxWidth = AccountingTransactionGridTokens.selectionWidth(
        context,
        'Select Tax',
        selectedLabels: r.lines.map(
          (line) => line.tax == '0' || line.tax == 'No tax'
              ? 'No Tax'
              : codes
                        .where((code) => code.choice == line.tax)
                        .firstOrNull
                        ?.label ??
                    line.snapshot?.label,
        ),
      );
      final amountWidth = AccountingTransactionGridTokens.numericWidth(
        context,
        'Amount',
        r.lines.map((l) => l.amount.text),
        title:
            'Amount (${CurrencyPresentation.fromCode(draft.currency).amountSymbol})',
      );
      final showRate = r.lines.any(
        (l) => l.rate.text.isNotEmpty || l.saved?.item.rate != null,
      );
      final showQuantity =
          showRate ||
          r.lines.any(
            (l) => l.quantity.text.isNotEmpty || l.saved?.item.quantity != null,
          );
      final quantityWidth = showQuantity
          ? AccountingTransactionGridTokens.numericWidth(
              context,
              'Quantity',
              r.lines.map((l) => l.quantity.text),
              title: 'Quantity',
            )
          : 0.0;
      final rateWidth = showRate
          ? AccountingTransactionGridTokens.numericWidth(
              context,
              'Rate',
              r.lines.map((l) => l.rate.text),
              title: 'Rate',
            )
          : 0.0;
      final fixed =
          categoryWidth + taxWidth + amountWidth + quantityWidth + rateWidth;
      final number = AccountingResponsive.measuredTextWidth(
        context,
        '${r.lines.length}',
        AccountingTypography.controlValue(context),
      );
      final boundary =
          number +
          AccountingTransactionGridTokens.numberGap(context, r.lines.length) +
          (readOnly
              ? 0
              : accountingContentInset + accountingSmallControlHeight);
      final peers =
          (3 + (showQuantity ? 1 : 0) + (showRate ? 1 : 0)) *
          AccountingTransactionGridTokens.peerGap;
      final width = math.max(
        constraints.maxWidth,
        fixed + boundary + peers + 160,
      );
      Widget numeric(
        ClaimReceiptLineInput l,
        String field,
        TextEditingController controller,
      ) => TextFormField(
        key: ValueKey('receipt-${field.toLowerCase()}-${l.id}'),
        controller: controller,
        readOnly: readOnly,
        style: AccountingTypography.controlValue(context),
        textAlign: field == 'Quantity' ? TextAlign.center : TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          AccountingMoneyInputFormatter(
            field == 'Quantity'
                ? 3
                : Currency.parse(draft.currency).fractionDigits,
          ),
        ],
        decoration: accountingSingleLineInputDecoration(context),
        onChanged: (_) => draft.reprice(l, field),
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: AccountingTransactionGrid(
            columns: [
              AccountingTransactionColumn(
                title: 'Category',
                width: categoryWidth,
                cell: (i, _) {
                  final l = r.lines[i];
                  final eligible = accounts.where(
                    (a) =>
                        !a.isParent &&
                        [
                          AccountType.expense,
                          AccountType.asset,
                        ].contains(a.type) &&
                        (a.status == AccountStatus.active ||
                            a.id == l.saved?.expenseAccountId),
                  );
                  return AccountingSelector<EntityId>(
                    assignedWidth: double.infinity,
                    triggerKey: ValueKey('receipt-category-${l.id}'),
                    menuKey: ValueKey('receipt-category-menu-${l.id}'),
                    value: l.accountId,
                    hintText: 'Select Category',
                    enabled: !readOnly,
                    searchable: true,
                    options: [
                      for (final a in eligible)
                        AccountingSelectorOption(
                          value: a.id,
                          label: a.displayName,
                          preserveLabelCase: true,
                          group: a.type.name,
                          enabled: a.status == AccountStatus.active,
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        final a = accounts.singleWhere((a) => a.id == v);
                        l.accountId = v;
                        l.category = a.name;
                        draft.changed();
                      }
                    },
                  );
                },
              ),
              AccountingTransactionColumn(
                title: 'Description',
                width: width - fixed - boundary - peers,
                cell: (i, _) => AccountingDescriptionField(
                  key: ValueKey('receipt-description-${r.lines[i].id}'),
                  controller: r.lines[i].description,
                  role: AccountingDescriptionRole.transactionItem,
                  fixedLines: null,
                  enabled: !readOnly,
                  decoration: accountingSingleLineInputDecoration(context),
                ),
              ),
              if (showQuantity)
                AccountingTransactionColumn(
                  title: 'Quantity',
                  width: quantityWidth,
                  cell: (i, _) =>
                      numeric(r.lines[i], 'Quantity', r.lines[i].quantity),
                ),
              if (showRate)
                AccountingTransactionColumn(
                  title: 'Rate',
                  width: rateWidth,
                  headerAlignment: Alignment.centerRight,
                  naturalHeaderWidth: true,
                  cell: (i, _) => numeric(r.lines[i], 'Rate', r.lines[i].rate),
                ),
              AccountingTransactionColumn(
                title: 'Tax',
                width: taxWidth,
                cell: (i, _) {
                  final l = r.lines[i],
                      date = parseAccountingInputDate(r.date.text);
                  final available = codes
                      .where(
                        (c) =>
                            date != null &&
                            c.applies(date, TaxApplication.purchases),
                      )
                      .toList();
                  final saved = l.saved?.item.taxSnapshot;
                  if (saved != null &&
                      date != null &&
                      saved.applies(
                        date,
                        TaxApplication.purchases,
                        requireActive: false,
                      ) &&
                      !available.any((c) => c.choice == saved.choice)) {
                    available.add(saved);
                  }
                  final selected =
                      l.tax == '0' ||
                          l.tax == 'No tax' ||
                          available.any((c) => c.choice == l.tax)
                      ? l.tax
                      : null;
                  return AccountingSelector<String>(
                    assignedWidth: double.infinity,
                    triggerKey: ValueKey('receipt-tax-${l.id}'),
                    menuKey: ValueKey('receipt-tax-menu-${l.id}'),
                    value: selected,
                    hintText: 'Select Tax',
                    enabled: !readOnly,
                    helperText: selected == null
                        ? 'Select the row tax for this receipt date.'
                        : null,
                    options: [
                      const AccountingSelectorOption(
                        value: '0',
                        label: 'No Tax',
                      ),
                      if (l.tax == 'No tax')
                        const AccountingSelectorOption(
                          value: 'No tax',
                          label: 'No Tax',
                          enabled: false,
                        ),
                      for (final c in available)
                        AccountingSelectorOption(
                          value: c.choice,
                          label: c.label,
                          preserveLabelCase: true,
                          enabled: codes.any(
                            (current) =>
                                current.choice == c.choice &&
                                current.applies(
                                  date!,
                                  TaxApplication.purchases,
                                ),
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        l.tax = v;
                        l.snapshot = available
                            .where((c) => c.choice == v)
                            .firstOrNull;
                        draft.changed();
                      }
                    },
                  );
                },
              ),
              AccountingTransactionColumn(
                title:
                    'Amount (${CurrencyPresentation.fromCode(draft.currency).amountSymbol})',
                width: amountWidth,
                headerAlignment: Alignment.centerRight,
                naturalHeaderWidth: true,
                cell: (i, _) =>
                    numeric(r.lines[i], 'Amount', r.lines[i].amount),
              ),
            ],
            rowCount: r.lines.length,
            showActions: !readOnly,
            rowKey: (i) => ValueKey('receipt-row-${r.lines[i].id}'),
            action: (i) => readOnly
                ? const SizedBox.shrink()
                : (i == 0 ? accountingCompactAdd : accountingCompactRemove)(
                    context,
                    key: ValueKey('receipt-action-${r.lines[i].id}'),
                    onPressed: i == 0
                        ? () => draft.addLine(r)
                        : () => draft.removeLine(r, r.lines[i]),
                  ),
          ),
        ),
      );
    },
  );
}
