import '../../accounting/domain/company_tax_rate.dart';
import '../domain/bill_tax_selection.dart';
import '../../../app/frontend_review.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/documents/receipt_document.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../../core/storage/record_metadata.dart';
import '../../accounting/domain/payment_terms.dart';
import '../../accounting/domain/company_payment_term.dart';
import '../../accounting/domain/company_preferences.dart';
import '../../accounting/presentation/company_payment_term_selection.dart';
import '../../sales/domain/invoice_tax.dart';
import '../../sales/domain/sales_line_item.dart';
import '../../sales/invoice_form.dart' show invoiceDecimal, invoiceMoney;
import '../domain/purchase_bill_draft.dart';
import '../domain/vendor.dart';

/// A transient Bill selector value. Bills persist the rule, never this ID.
String billPaymentTermChoice(CompanyPaymentTerm template) =>
    companyPaymentTermChoice(template);

DesignForm billForm(
  Map<String, String> vendors,
  Map<String, String> accounts, {
  Set<String> currencyCodes = const {},
  Map<String, String> counterpartyCurrencies = const {},
  Map<String, String> counterpartyCustomTerms = const {},
  List<CompanyPaymentTerm> paymentTermTemplates = const [],
  String defaultCurrencyCode = 'MYR',
  CompanyPreferences? preferences,
  PurchaseBillDraft? existing,
  Map<String, String> taxChoices = const {'0': 'No Tax'},
}) => DesignForm(
  'Bills',
  [
    for (final field in transactionFields)
      if (field.label == 'Counterparty')
        DesignField('Counterparty', required: true, choiceLabels: vendors)
      else if (field.label == 'Payment Terms')
        DesignField(
          'Payment Terms',
          choiceLabels: {
            for (final choice in const ['Use Vendor Default', ...termsChoices])
              choice: choice,
            ...companyPaymentTermChoiceLabels(
              paymentTermTemplates,
              reservedChoices: const ['Use Vendor Default', ...termsChoices],
            ),
          },
        )
      else if (field.label == 'Tax Mode')
        DesignField(
          'Tax Mode',
          options: const ['Exclusive', 'Inclusive'],
          choiceLabels: {
            'Exclusive': 'Tax Exclusive',
            'Inclusive': 'Tax Inclusive',
            if (const {'Exempt', 'Out Of Scope'}.contains(existing?.taxMode))
              existing!.taxMode!: 'Saved ${existing.taxMode}',
          },
          disabledOptions: {
            if (const {'Exempt', 'Out Of Scope'}.contains(existing?.taxMode))
              existing!.taxMode!,
          },
        )
      else if (field.label == 'Document Number')
        DesignField('Document Number', required: true)
      else if (field.label == 'Currency')
        DesignField(
          'Currency',
          options: [
            'Use Counterparty Default',
            ...{...currencies, ...currencyCodes},
          ],
        )
      else
        field,
  ],
  lines: true,
  recurring: true,
  evidence: true,
  actionLabel: 'Save Draft',
  lineFields: [
    'Account',
    'Description',
    'Tax Rate (%)',
    if ((preferences?.enabled('Purchase Preferences', 'Show Quantity') ??
            true) ||
        (existing?.lines.any(
              (line) => line.quantity != SalesQuantity.fromInt(1),
            ) ??
            false))
      'Quantity',
    if ((preferences?.enabled('Purchase Preferences', 'Show Rate') ?? true) ||
        (existing?.lines.any(
              (line) =>
                  line.rateEnabled && line.quantity != SalesQuantity.fromInt(1),
            ) ??
            false))
      'Rate'
    else
      'Amount',
    if ((preferences?.enabled('Purchase Preferences', 'Enable Discounts') ??
            true) ||
        (existing?.lines.any((line) => line.discount.isPositive) ?? false))
      'Discount',
  ],
  lineChoiceLabels: {'Account': accounts, 'Tax Rate (%)': taxChoices},
  counterpartyCurrencies: counterpartyCurrencies,
  counterpartyCustomTerms: counterpartyCustomTerms,
  defaultCurrencyCode: defaultCurrencyCode,
);

Map<String, Object?> billFormValues(PurchaseBillDraft bill) => {
  'Counterparty': bill.vendorSnapshot.id.value,
  'Date': formatAccountingInputDate(bill.bill.issueDate),
  'Due Date': formatAccountingInputDate(bill.bill.dueDate),
  'Document Number': bill.documentNumber,
  'Reference': bill.supplierReference,
  'Currency': bill.total.currency,
  'Payment Terms': bill.bill.terms.formChoice,
  'Custom Payment Terms': bill.bill.terms.customText ?? '',
  'Number Of Days': '${bill.bill.terms.days ?? 0}',
  'Monthly Due Day': '${bill.bill.terms.dayOfMonth ?? 1}',
  'Rollover Within Days': '${bill.bill.terms.rolloverWithinDays}',
  'Tax Mode': bill.taxMode ?? '',
  '_billTaxSnapshots': {
    for (final line in bill.lines)
      if (line.taxSnapshot != null) line.id.value: line.taxSnapshot,
  },
  'Class': bill.classification,
  'Location': bill.location,
  'Memo': bill.memo,
  '_lines': [
    for (final line in bill.lines)
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
        'Account': line.categoryId!.value,
      },
  ],
  '_files': bill.attachments.map((a) => a.filename).toList(),
  '_attachments': bill.attachments,
};

PurchaseBillDraft billFromForm(
  Map<String, Object?> values, {
  required RecordMetadata metadata,
  required Vendor vendor,
  required Set<String> purchaseAccountIds,
  List<CompanyTaxRate> taxCodes = const [],
  List<CompanyPaymentTerm> paymentTermTemplates = const [],
  PurchaseBillDraft? existing,
}) {
  String text(String key) => (values[key] as String? ?? '').trim();
  if (text('Counterparty') != vendor.id.value) {
    throw StateError('Choose the saved supplier.');
  }
  final issue = parseAccountingInputDate(text('Date'));
  if (issue == null) throw const FormatException('Enter a valid bill date.');
  final currency =
      text('Currency').isEmpty || text('Currency') == 'Use Counterparty Default'
      ? vendor.currency.code
      : text('Currency');
  if (existing != null &&
      (existing.id != metadata.recordId ||
          existing.metadata.businessId != metadata.businessId)) {
    throw StateError(
      'Saved Bill tax facts must belong to this bill and company.',
    );
  }
  final mode = text('Tax Mode');
  final retainedMode =
      existing?.taxMode == mode &&
      const {'Exempt', 'Out Of Scope'}.contains(mode);
  if (!const {'Exclusive', 'Inclusive'}.contains(mode) && !retainedMode) {
    throw const FormatException(
      'Select Exclusive or Inclusive for bill amounts.',
    );
  }
  int integer(String key) =>
      int.tryParse(text(key)) ??
      (throw FormatException('Enter $key as a whole number.'));
  final term = text('Payment Terms');
  final namedTemplate = isCompanyPaymentTermChoice(term)
      ? paymentTermTemplates
            .where(
              (template) =>
                  template.active && billPaymentTermChoice(template) == term,
            )
            .firstOrNull
      : null;
  if (isCompanyPaymentTermChoice(term) && namedTemplate == null) {
    throw StateError('The selected company payment term is unavailable.');
  }
  final terms =
      namedTemplate?.rule ??
      (switch (term) {
        '' || 'Use Vendor Default' => vendor.terms,
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
          term.startsWith('Net ') && int.tryParse(term.substring(4)) != null
              ? PaymentTerms.netDays(int.parse(term.substring(4)))
              : throw const FormatException('Choose valid bill terms.'),
      }).retainingCustomText(
        values.containsKey('Custom Payment Terms')
            ? text('Custom Payment Terms')
            : existing?.bill.terms.customText,
      );
  final due = namedTemplate != null || text('Due Date').isEmpty
      ? terms.dueDateFor(issue)
      : parseAccountingInputDate(text('Due Date'));
  if (due == null) throw const FormatException('Enter a valid bill due date.');
  final lines = <SalesLineItem>[];
  for (final raw in values['_lines'] as List? ?? const []) {
    final line = Map<String, String>.from(raw as Map);
    final account = line['Account'] ?? '';
    if (!purchaseAccountIds.contains(account)) {
      throw StateError(
        'Choose an active expense or asset account for each line.',
      );
    }
    final description = line['Description'] ?? '';
    if (description.trim().isEmpty) {
      throw FormatException(
        'Enter a description for bill line ${lines.length + 1}.',
      );
    }
    final choice = (line['Tax Rate (%)'] ?? '').trim();
    final original = existing?.lines
        .where((s) => s.id.value == line['_lineId'])
        .firstOrNull;
    final selectedTax = resolveBillTaxSelection(
      choice,
      codes: taxCodes,
      date: issue,
      originalChoice: original?.taxSnapshot?.choice ?? original?.taxRatePercent,
      saved: original?.taxSnapshot,
    );
    final rate = taxPercent(choice);
    if ((mode == 'Exclusive' || mode == 'Inclusive') && rate.isEmpty) {
      throw const FormatException('Enter an explicit tax rate for each line.');
    }
    final taxRate = rate.isEmpty ? '0' : rate;
    if ((mode == 'Exempt' || mode == 'Out Of Scope') &&
        InvoiceTaxRate.fromPercent(taxRate).units != 0) {
      throw const FormatException(
        'Exempt/out-of-scope lines cannot carry a tax rate.',
      );
    }
    lines.add(
      SalesLineItem.category(
        id: EntityId.parse(line['_lineId']!),
        categoryId: EntityId.parse(account),
        description: description,
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
        taxRatePercent: taxRate,
        taxSnapshot: selectedTax,
      ),
    );
  }
  final files = values['_files'] as List? ?? const [];
  final attachments = values['_attachments'] as List? ?? const [];
  if (files.length != attachments.length ||
      attachments.any((a) => a is! ReceiptAttachment)) {
    throw StateError('Every attachment must contain actual document evidence.');
  }
  for (var i = 0; i < files.length; i++) {
    if (files[i] != (attachments[i] as ReceiptAttachment).filename) {
      throw StateError('Attachment names must match their saved evidence.');
    }
  }
  return PurchaseBillDraft(
    metadata: metadata,
    vendorSnapshot: vendor,
    documentNumber: text('Document Number'),
    supplierReference: text('Reference'),
    issueDate: issue,
    dueDate: due,
    terms: terms,
    taxMode: mode,
    lines: lines,
    memo: text('Memo'),
    classification: text('Class'),
    location: text('Location'),
    attachments: attachments.cast<ReceiptAttachment>(),
  );
}

List<(String, String)> billInformationRows(
  PurchaseBillDraft bill, {
  Map<EntityId, String> accountNames = const {},
}) => [
  ('Bill', bill.documentNumber),
  ('Vendor (Saved)', bill.vendorSnapshot.name),
  ('Supplier Reference', bill.supplierReference),
  ('Date', formatAccountingInputDate(bill.bill.issueDate)),
  ('Due Date', formatAccountingInputDate(bill.bill.dueDate)),
  ('Payment Terms', bill.bill.terms.label),
  ('Tax Mode', bill.taxMode ?? 'Per Line (Legacy)'),
  ('Total', invoiceMoney(bill.total)),
  if (bill.classification.isNotEmpty) ('Class', bill.classification),
  if (bill.location.isNotEmpty) ('Location', bill.location),
  if (bill.memo.isNotEmpty) ('Memo', bill.memo),
  for (var i = 0; i < bill.lines.length; i++) ...[
    ('Line ${i + 1}', bill.lines[i].description),
    (
      'Account ${i + 1}',
      accountNames[bill.lines[i].categoryId] ?? bill.lines[i].categoryId!.value,
    ),
    ('Quantity ${i + 1}', bill.lines[i].quantity.toString()),
    ('Rate ${i + 1}', invoiceMoney(bill.lines[i].rate)),
    ('Discount ${i + 1}', invoiceMoney(bill.lines[i].discount)),
    ('Tax ${i + 1}', invoiceMoney(bill.lines[i].tax)),
    ('Line Total ${i + 1}', invoiceMoney(bill.lines[i].total)),
  ],
  ('Revision', '${bill.metadata.revision}'),
];
