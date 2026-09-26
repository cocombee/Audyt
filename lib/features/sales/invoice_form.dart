import '../accounting/domain/company_tax_rate.dart';
import '../accounting/domain/company_preferences.dart';
import '../accounting/domain/account.dart';
import '../../app/accounting_description_field.dart';
import '../../app/frontend_review.dart';
import '../../core/dates/accounting_date.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/ids/entity_id.dart';
import '../../core/money/currency.dart';
import '../../core/money/currency_presentation.dart';
import '../../core/money/money.dart';
import '../accounting/domain/customer.dart';
import 'domain/invoice.dart';
import 'domain/sales_line_item.dart';
import 'domain/product_catalogue.dart';

String invoiceDecimal(Money money) {
  final digits = Currency.parse(money.currency).fractionDigits;
  final sign = money.isNegative ? '-' : '';
  final value = money.minorUnits.abs().toString().padLeft(digits + 1, '0');
  return digits == 0
      ? '$sign$value'
      : '$sign${value.substring(0, value.length - digits)}.${value.substring(value.length - digits)}';
}

String invoiceMoney(Money money) {
  final decimal = invoiceDecimal(money);
  final point = decimal.indexOf('.');
  final whole = point < 0 ? decimal : decimal.substring(0, point);
  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return currencyAmountLabel(
    money.currency,
    '$grouped${point < 0 ? '' : decimal.substring(point)}',
  );
}

/// Retained account-based documents keep their actual account selector. New
/// catalogue documents require an item; presentation and validation agree.
bool invoiceUsesCatalogueItems(Invoice? existing) =>
    existing == null ||
    existing.lines.isEmpty ||
    existing.lines.any((line) => line.catalogue != null);

/// The invoice shortcut's actual form definition. Proposed fields are isolated
/// review inputs; the live payment command still consumes the original keys.
DesignForm invoicePaymentReviewForm({
  required Invoice invoice,
  required Map<String, String> paymentAccounts,
  required int paidMinor,
  required int creditedMinor,
  bool proposal = false,
}) => DesignForm(
  'Receive Invoice Payment',
  [
    if (!proposal)
      DesignField(
        'Amount',
        required: true,
        currencyCode: invoice.total.currency,
      ),
    DesignField(proposal ? 'Payment Date' : 'Date', required: true),
    const DesignField('Reference', required: true),
    if (proposal) const DesignField('Payment Method', options: paymentMethods),
    DesignField(
      proposal ? 'Deposit To' : 'Bank Account',
      required: true,
      choiceLabels: paymentAccounts,
    ),
    if (proposal) ...[
      DesignField(
        'Amount Received',
        required: true,
        currencyCode: invoice.total.currency,
      ),
      const DesignField(
        'Memo',
        multiline: true,
        fullWidth: true,
        descriptionRole: AccountingDescriptionRole.memo,
      ),
    ],
  ],
  actionLabel: 'Record Payment',
  evidence: proposal,
  defaultCurrencyCode: invoice.total.currency,
  description:
      'Record money received against this invoice. Outstanding: ${invoiceMoney(Money.fromMinor(invoice.total.minorUnits - paidMinor - creditedMinor, invoice.total.currency))}',
);

/// Shared source for the actual posting review and no-commit proposal captures.
/// Broad account types preserve the current contract; detail-type eligibility
/// and a default-first redesign remain separate audited work.
DesignForm invoicePostingReviewForm({
  required bool hasTax,
  required List<Account> accounts,
}) => DesignForm(
  'Post Invoice',
  [
    const DesignField('Document Number', required: true),
    DesignField(
      'Receivable Account',
      required: true,
      choiceLabels: {
        for (final a in accounts.where((a) => a.type == AccountType.asset))
          a.id.value: '${a.code} · ${a.name}',
      },
    ),
    if (hasTax)
      DesignField(
        'Tax Account',
        required: true,
        choiceLabels: {
          for (final a in accounts.where(
            (a) => a.type == AccountType.liability,
          ))
            a.id.value: '${a.code} · ${a.name}',
        },
      ),
  ],
  actionLabel: 'Post Invoice',
  description: 'Review the saved invoice and its posting accounts.',
);

DesignForm invoiceForm(
  Map<String, String> customers,
  Map<String, String> accounts, {
  CompanyPreferences? preferences,
  Invoice? existing,
  Map<String, String> counterpartyCurrencies = const {},
  Map<String, String> counterpartyCustomTerms = const {},
  String defaultCurrencyCode = 'MYR',
  Map<String, String>? itemChoices,
  Map<String, String> taxChoices = const {'0': 'No Tax'},
}) => DesignForm(
  'Invoices',
  [
    for (final field in transactionFields)
      if (field.label == 'Counterparty')
        DesignField('Counterparty', required: true, choiceLabels: customers)
      else if (field.label == 'Payment Terms')
        const DesignField(
          'Payment Terms',
          options: ['Use Customer Default', ...termsChoices],
        )
      else
        field,
  ],
  lines: true,
  recurring: true,
  evidence: true,
  actionLabel: 'Save Draft',
  lineFields: [
    if (itemChoices != null && invoiceUsesCatalogueItems(existing))
      'Product / Service',
    'Description',
    if ((preferences?.enabled('Sales Preferences', 'Show Quantity') ?? true) ||
        (existing?.lines.any(
              (line) => line.quantity != SalesQuantity.fromInt(1),
            ) ??
            false))
      'Quantity',
    if ((preferences?.enabled('Sales Preferences', 'Show Rate') ?? true) ||
        (existing?.lines.any(
              (line) =>
                  line.rateEnabled && line.quantity != SalesQuantity.fromInt(1),
            ) ??
            false))
      'Rate'
    else
      'Amount',
    if ((preferences?.enabled('Sales Preferences', 'Enable Discounts') ??
            true) ||
        (existing?.lines.any((line) => line.discount.isPositive) ?? false))
      'Discount',
    'Tax Rate (%)',
    'Account',
  ],
  lineChoiceLabels: {
    'Product / Service': ?(invoiceUsesCatalogueItems(existing)
        ? itemChoices
        : null),
    if (itemChoices != null) 'Tax Rate (%)': taxChoices,
    'Account': accounts,
  },
  counterpartyCurrencies: counterpartyCurrencies,
  counterpartyCustomTerms: counterpartyCustomTerms,
  defaultCurrencyCode: defaultCurrencyCode,
);

Map<String, Object?> invoiceFormValues(Invoice invoice) => {
  '_savedSalesTaxFacts': true,
  '_savedTaxCodeLabels': {
    for (final line in invoice.lines)
      if (line.taxSnapshot != null)
        line.taxSnapshot!.choice: line.taxSnapshot!.label,
  },
  'Counterparty': invoice.customerId.value,
  'Date': formatAccountingInputDate(invoice.issueDate),
  'Due Date': formatAccountingInputDate(invoice.dueDate),
  'Document Number': invoice.documentNumber,
  'Reference': invoice.reference,
  'Currency': invoice.total.currency,
  'Payment Terms': invoice.terms.formChoice,
  'Custom Payment Terms': invoice.terms.customText ?? '',
  'Number Of Days': '${invoice.terms.days ?? 0}',
  'Monthly Due Day': '${invoice.terms.dayOfMonth ?? 1}',
  'Rollover Within Days': '${invoice.terms.rolloverWithinDays}',
  'Tax Mode': invoice.taxMode,
  'Class': invoice.classification,
  'Location': invoice.location,
  'Memo': invoice.memo,
  '_lines': [
    for (final line in invoice.lines)
      {
        '_lineId': line.id.value,
        'Description': line.description,
        'Quantity': line.quantity.toString(),
        'Rate': invoiceDecimal(line.rate),
        if (line.manualAmount != null ||
            line.quantity == SalesQuantity.fromInt(1))
          'Amount': invoiceDecimal(line.manualAmount ?? line.rate),
        if (line.manualAmount != null && line.rateEnabled)
          '_manualAmount': invoiceDecimal(line.manualAmount!),
        'Discount': invoiceDecimal(line.discount),
        'Tax Rate (%)': line.taxSnapshot?.choice ?? line.taxRatePercent ?? '',
        'Account': line.categoryId?.value ?? '',
        if (line.catalogue != null)
          'Product / Service': line.catalogue!.itemId.value,
      },
  ],
  '_files': invoice.attachments.map((a) => a.filename).toList(),
  '_attachments': invoice.attachments,
};

Invoice invoiceFromForm(
  Map<String, Object?> values, {
  required EntityId id,
  required Customer customer,
  required Set<String> incomeAccountIds,
  Invoice? existing,
  List<CompanyTaxRate> taxCodes = const [],
  List<CatalogueItem> catalogueItems = const [],
  List<CatalogueCategory> catalogueCategories = const [],
  bool requireCatalogueItem = false,
  bool allowRetainedUnavailableAccounts = false,
}) {
  if (existing != null && existing.id != id) {
    throw StateError('Edit the same saved invoice identity.');
  }
  String text(String key) => (values[key] as String? ?? '').trim();
  if (text('Counterparty') != customer.id.value || !customer.isActive) {
    throw StateError('Choose an active customer.');
  }
  final issue = parseAccountingInputDate(text('Date'));
  if (issue == null) throw const FormatException('Enter a valid invoice date.');
  final currency =
      text('Currency').isEmpty || text('Currency') == 'Use Counterparty Default'
      ? customer.currency.code
      : text('Currency');
  final mode = text('Tax Mode');
  if (!['Exclusive', 'Inclusive', 'Out Of Scope', 'Exempt'].contains(mode)) {
    throw const FormatException('Review the invoice tax mode before saving.');
  }
  int integer(String key) =>
      int.tryParse(text(key)) ??
      (throw FormatException('Enter $key as a whole number.'));
  final termLabel = text('Payment Terms');
  final terms =
      (switch (termLabel) {
        '' || 'Use Customer Default' => customer.paymentTerms,
        'Due On Receipt' => PaymentTerms.netDays(0),
        'Custom' => PaymentTerms.custom(text('Custom Payment Terms')),
        'Days After Issue' => PaymentTerms.netDays(integer('Number Of Days')),
        'Day Of Month' => PaymentTerms.dayOfMonth(
          integer('Monthly Due Day'),
          rolloverWithinDays: text('Rollover Within Days').isEmpty
              ? 0
              : integer('Rollover Within Days'),
        ),
        _ =>
          termLabel.startsWith('Net ') &&
                  int.tryParse(termLabel.substring(4)) != null
              ? PaymentTerms.netDays(int.parse(termLabel.substring(4)))
              : throw const FormatException('Choose valid payment terms.'),
      }).retainingCustomText(
        values.containsKey('Custom Payment Terms')
            ? text('Custom Payment Terms')
            : existing?.terms.customText,
      );
  final due = text('Due Date').isEmpty
      ? null
      : parseAccountingInputDate(text('Due Date'));
  if (text('Due Date').isNotEmpty && due == null) {
    throw const FormatException('Enter a valid due date.');
  }
  final lines = <SalesLineItem>[];
  for (final raw in values['_lines'] as List? ?? const []) {
    final line = Map<String, String>.from(raw as Map);
    final savedLine = existing?.lines
        .where((saved) => saved.id.value == line['_lineId'])
        .firstOrNull;
    var account = line['Account'] ?? '';
    CatalogueLineSnapshot? snapshot;
    final selectedItem = line['Product / Service'] ?? '';
    if (selectedItem.isEmpty && requireCatalogueItem && savedLine == null) {
      throw StateError('Choose a registered item for each new sales line.');
    }
    if (selectedItem.isNotEmpty) {
      if (savedLine?.catalogue?.itemId.value == selectedItem) {
        // A rename or regroup must not rewrite this document's history.
        snapshot = savedLine!.catalogue;
        account = savedLine.categoryId!.value;
      } else {
        final item = catalogueItems
            .where((item) => item.active && item.id.value == selectedItem)
            .firstOrNull;
        if (item == null) {
          throw StateError('Choose an active item in this company.');
        }
        final category = catalogueCategories
            .where((category) => category.id == item.categoryId)
            .firstOrNull;
        if (category == null) throw StateError('Review the item’s category.');
        snapshot = item.snapshot(category);
        account = item.incomeAccountId.value;
      }
    } else if (savedLine?.catalogue != null) {
      throw StateError(
        'Choose an item before replacing its saved catalogue link.',
      );
    }
    if (!incomeAccountIds.contains(account) &&
        !(allowRetainedUnavailableAccounts &&
            savedLine?.categoryId?.value == account)) {
      throw StateError('Choose an active income account for each line.');
    }
    final taxChoice = (line['Tax Rate (%)'] ?? '').trim();
    if (values.containsKey('_documentTaxChoice')) {
      final documentChoice = values['_documentTaxChoice'];
      if (documentChoice == null) {
        if (savedLine == null ||
            taxChoice !=
                (savedLine.taxSnapshot?.choice ??
                    savedLine.taxRatePercent ??
                    '')) {
          throw const FormatException(
            'Choose one document tax before saving new items or replacing item tax.',
          );
        }
      } else if (documentChoice is! String || documentChoice != taxChoice) {
        throw const FormatException(
          'Every item must use the selected document tax.',
        );
      }
    }
    final selectedTax = resolveTaxChoice(
      taxChoice,
      codes: taxCodes,
      date: issue,
      purpose: TaxApplication.sales,
      saved: savedLine?.taxSnapshot,
    );
    final rateText = taxPercent(taxChoice);
    if ((mode == 'Exclusive' || mode == 'Inclusive') && rateText.isEmpty) {
      throw const FormatException('Enter an explicit tax rate for each line.');
    }
    if ((mode == 'Out Of Scope' || mode == 'Exempt') &&
        rateText.isNotEmpty &&
        double.tryParse(rateText) != 0) {
      throw const FormatException(
        'Exempt/out-of-scope lines cannot carry a tax rate.',
      );
    }
    lines.add(
      SalesLineItem.category(
        id: EntityId.parse(line['_lineId']!),
        sourceLineId: existing?.lines
            .where((saved) => saved.id.value == line['_lineId'])
            .firstOrNull
            ?.sourceLineId,
        categoryId: EntityId.parse(account),
        description: line['Description'] ?? '',
        quantity: SalesQuantity.fromDecimal(line['Quantity'] ?? '1'),
        rate: Money.fromDecimal(line['Rate'] ?? line['Amount'] ?? '', currency),
        rateEnabled: line['Rate'] != null || !line.containsKey('Quantity'),
        manualAmount:
            (line['Rate'] == null && line.containsKey('Quantity')) ||
                line['_manualAmount'] != null
            ? Money.fromDecimal(
                line['_manualAmount'] ?? line['Amount'] ?? '',
                currency,
              )
            : null,
        discount: Money.fromDecimal(
          (line['Discount'] ?? '').isEmpty ? '0' : line['Discount']!,
          currency,
        ),
        taxInclusive: mode == 'Inclusive',
        taxRatePercent: rateText.isEmpty ? '0' : rateText,
        taxSnapshot: selectedTax,
        catalogue: snapshot,
      ),
    );
  }
  final files = values['_files'] as List? ?? const [];
  final attachments = values['_attachments'] as List? ?? const [];
  if (files.length != attachments.length ||
      attachments.any((a) => a is! ReceiptAttachment)) {
    throw StateError('All attachments must contain actual document evidence.');
  }
  return Invoice.draft(
    id: id,
    customerId: customer.id,
    sourceEstimateId: existing?.sourceEstimateId,
    lines: lines,
    issueDate: issue,
    dueDate: due,
    terms: terms,
    reference: text('Reference'),
    memo: text('Memo'),
    documentNumber: text('Document Number'),
    classification: text('Class'),
    location: text('Location'),
    taxMode: mode,
    attachments: attachments.cast<ReceiptAttachment>(),
  );
}
