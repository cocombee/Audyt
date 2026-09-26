import 'expense_claim_source.dart';
import 'recurrence_rule.dart';
import 'company_tax_rate.dart';
import '../../sales/domain/invoice_tax.dart';

import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';

import 'package:audyt/core/documents/receipt_review_queue.dart';
import 'package:audyt/core/documents/receipt_document.dart';

/// Retained intake facts. Posting still requires the existing journal review;
/// a category or a tax label is never treated as a posting account or tax rate.
final class ExpenseDraftLine {
  const ExpenseDraftLine({
    required this.id,
    required this.category,
    required this.description,
    required this.tax,
    required this.amount,
    this.quantity,
    this.rate,
    this.pricingAdjustment,
    this.taxSnapshot,
  });
  final String id;
  final String category;
  final String description;
  final String tax;
  final String amount;
  final String? quantity;
  final String? rate;
  final String? pricingAdjustment;
  final CompanyTaxRate? taxSnapshot;

  InvoiceTaxCalculation calculation(String currency, String basis) {
    if (!const {'Exclusive', 'Inclusive'}.contains(basis)) {
      throw const FormatException('Choose Inclusive or Exclusive amounts.');
    }
    final code = taxSnapshot;
    if (code == null
        ? !const {'0', 'No tax'}.contains(tax)
        : code.choice != tax || code.application == TaxApplication.sales) {
      throw const FormatException('Review the purchase tax code on this row.');
    }
    return InvoiceTaxCalculation.calculate(
      amount: Money.fromDecimal(amount, currency),
      rate: InvoiceTaxRate.fromPercent(code?.percent ?? '0'),
      inclusive: basis == 'Inclusive',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category,
    'description': description,
    'tax': tax,
    'amount': amount,
    if (quantity != null) 'quantity': quantity,
    if (rate != null) 'rate': rate,
    if (pricingAdjustment != null) 'pricingAdjustment': pricingAdjustment,
    if (taxSnapshot != null) 'taxSnapshot': taxSnapshot!.toJson(),
  };
  factory ExpenseDraftLine.fromJson(Map<String, dynamic> json) =>
      ExpenseDraftLine(
        id: json['id'] as String,
        category: json['category'] as String,
        description: json['description'] as String,
        tax: json['tax'] as String,
        amount: json['amount'] as String,
        quantity: json['quantity'] as String?,
        rate: json['rate'] as String?,
        pricingAdjustment: json['pricingAdjustment'] as String?,
        taxSnapshot: json['taxSnapshot'] == null
            ? null
            : CompanyTaxRate.fromJson(
                Map<String, dynamic>.from(json['taxSnapshot'] as Map),
              ),
      );
}

class RecordExpenseDraft {
  const RecordExpenseDraft({
    required this.amount,
    required this.date,
    required this.payee,
    required this.paymentAccount,
    this.paymentAccountId,
    this.recurrence,
    required this.category,
    required this.tax,
    required this.customer,
    required this.billable,
    required this.dimensions,
    required this.itemOrSplitDetails,
    required this.notes,
    this.attachmentName,
    this.attachments = const <ReceiptAttachment>[],
    this.currencyCode = 'MYR',
    this.submissionId,
    this.reviewSnapshots = const [],
    this.documentNumber = '',
    this.lines = const [],
    this.taxMode,
    this.taxReviewRequired = false,
    this.claimSource,
    this.receiptLineBases = const {},
  });

  final String amount;
  final String date;
  final String payee;
  final String paymentAccount;
  final String? paymentAccountId;
  final RecurrenceRule? recurrence;
  final String category;
  final String tax;
  final String customer;
  final bool billable;
  final String dimensions;
  final String itemOrSplitDetails;
  final String notes;
  final String? attachmentName;
  final List<ReceiptAttachment> attachments;
  final String currencyCode;
  final String? submissionId;
  final List<Map<String, dynamic>> reviewSnapshots;
  final String documentNumber;
  final List<ExpenseDraftLine> lines;
  // Null is the untouched historic intake classification, never inferred tax.
  final String? taxMode;
  // Frozen recurring defaults require new date/code review before intake save.
  final bool taxReviewRequired;
  final ExpenseClaimSource? claimSource;

  /// Original receipt bases in an unrecognized legacy Claim display adapter.
  /// This is receipt evidence, never a ledger recognition or payment source.
  final Map<String, String> receiptLineBases;

  InvoiceTaxCalculation lineCalculation(ExpenseDraftLine line) =>
      line.calculation(
        currencyCode,
        claimSource?.lineBases[line.id] ??
            receiptLineBases[line.id] ??
            taxMode!,
      );
  String get taxDescription {
    if (taxMode == null) return tax;
    if (taxReviewRequired) return 'Review Needed';
    final labels = lines
        .map((line) => line.taxSnapshot?.label ?? 'No Tax')
        .toSet();
    return labels.length == 1 ? labels.single : 'Multiple Taxes';
  }

  ({Money net, Money tax, Money total})? get taxTotals {
    if (taxMode == null) return null;
    var net = Money.zero(currencyCode);
    var tax = Money.zero(currencyCode);
    var gross = Money.zero(currencyCode);
    for (final line in lines) {
      final calculated = lineCalculation(line);
      net += calculated.net;
      tax += calculated.tax;
      gross += calculated.total;
    }
    return (net: net, tax: tax, total: gross);
  }

  void validateLines() {
    if (taxMode != null &&
        (!const {'Exclusive', 'Inclusive'}.contains(taxMode) &&
                !(taxMode == ExpenseClaimSource.mixedBasis &&
                    (claimSource != null || receiptLineBases.isNotEmpty)) ||
            lines.isEmpty)) {
      throw const FormatException('Expense tax needs a basis and item rows.');
    }
    if (taxMode == null && lines.any((line) => line.taxSnapshot != null)) {
      throw const FormatException('A tax snapshot requires an explicit basis.');
    }
    if (receiptLineBases.isNotEmpty &&
        (claimSource != null ||
            taxMode != ExpenseClaimSource.mixedBasis ||
            receiptLineBases.length != lines.length ||
            receiptLineBases.values.toSet().length < 2 ||
            receiptLineBases.values.any(
              (basis) => !const {'Inclusive', 'Exclusive'}.contains(basis),
            ) ||
            lines.any((line) => !receiptLineBases.containsKey(line.id)))) {
      throw const FormatException(
        'Receipt bases must retain every mixed-basis Claim row.',
      );
    }
    if (claimSource != null) {
      final bases = claimSource!.lineBases;
      if (bases.length != lines.length ||
          lines.any((line) => !bases.containsKey(line.id)) ||
          (taxMode != null &&
              taxMode != ExpenseClaimSource.mixedBasis &&
              bases.values.any((basis) => basis != taxMode)) ||
          (taxMode == ExpenseClaimSource.mixedBasis &&
              bases.values.toSet().length < 2)) {
        throw const FormatException(
          'Claim Expense lines do not match their retained tax bases.',
        );
      }
    }
    if (lines.isEmpty) return; // Version-one intake remains readable unchanged.
    final identities = <String>{};
    var total = Money.zero(currencyCode);
    for (final line in lines) {
      if (line.id.isEmpty ||
          !identities.add(line.id) ||
          line.category.trim().isEmpty) {
        throw const FormatException(
          'Expense lines need distinct identities and categories.',
        );
      }
      final amount = Money.fromDecimal(line.amount, currencyCode);
      if (!amount.isPositive) {
        throw const FormatException('Expense line amounts must be positive.');
      }
      final quantity = line.quantity == null
          ? null
          : SalesQuantity.fromDecimal(line.quantity!);
      if (line.rate != null) {
        if (quantity == null) {
          throw const FormatException('A rate requires quantity.');
        }
        final rate = Money.fromDecimal(line.rate!, currencyCode);
        final adjustment = Money.fromDecimal(
          line.pricingAdjustment ?? '0',
          currencyCode,
        );
        if (rate.isNegative || quantity.multiply(rate) + adjustment != amount) {
          throw const FormatException(
            'Expense line pricing does not match its amount.',
          );
        }
      } else if (line.pricingAdjustment != null) {
        throw const FormatException('A pricing adjustment requires a rate.');
      }
      total += taxMode == null ? amount : lineCalculation(line).total;
    }
    if (total != Money.fromDecimal(amount, currencyCode)) {
      throw const FormatException(
        'Expense lines must equal the retained expense total.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'version': receiptLineBases.isNotEmpty
        ? 4
        : claimSource != null
        ? 3
        : taxMode == null
        ? 1
        : 2,
    if (claimSource != null) 'claimSource': claimSource!.toJson(),
    if (receiptLineBases.isNotEmpty) 'receiptLineBases': receiptLineBases,
    if (taxMode != null) 'taxMode': taxMode,
    if (taxReviewRequired) 'taxReviewRequired': true,
    'amount': amount,
    'date': date,
    'payee': payee,
    'paymentAccount': paymentAccount,
    if (paymentAccountId != null) 'paymentAccountId': paymentAccountId,
    if (recurrence != null) 'recurrence': recurrence!.toJson(),
    'category': category,
    'tax': taxDescription,
    'customer': customer,
    'billable': billable,
    'dimensions': dimensions,
    'itemOrSplitDetails': itemOrSplitDetails,
    'notes': notes,
    'attachmentName': attachmentName,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'currencyCode': currencyCode,
    'submissionId': submissionId,
    'reviewSnapshots': reviewSnapshots,
    if (documentNumber.isNotEmpty) 'documentNumber': documentNumber,
    if (lines.isNotEmpty) 'lines': lines.map((line) => line.toJson()).toList(),
  };

  factory RecordExpenseDraft.fromJson(Map<String, dynamic> json) {
    if (!const {1, 2, 3, 4}.contains(json['version'])) {
      throw const FormatException('Unsupported expense intake version.');
    }
    if ((json['version'] == 3) != (json['claimSource'] != null)) {
      throw const FormatException('Expense source version mismatch.');
    }
    if ((json['version'] == 4) !=
            (json['receiptLineBases'] is Map &&
                (json['receiptLineBases'] as Map).isNotEmpty) ||
        (json['version'] != 4 && json.containsKey('receiptLineBases'))) {
      throw const FormatException('Receipt basis version mismatch.');
    }
    final attachments = (json['attachments'] as List)
        .map((a) => ReceiptAttachment.fromJson(a as Map<String, dynamic>))
        .toList();
    final byId = {for (final a in attachments) a.originalId: a};
    if (byId.length != attachments.length) {
      throw const FormatException(
        'Duplicate receipt identity in expense intake.',
      );
    }
    final reviews = (json['reviewSnapshots'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final reviewedIds = <String>{};
    for (final snapshot in reviews) {
      final item = ReceiptReviewItem.fromJson(snapshot);
      try {
        final original = byId[item.attachment.originalId];
        if (original == null ||
            original.originalSha256 != item.attachment.originalSha256 ||
            !reviewedIds.add(original.originalId)) {
          throw const FormatException(
            'Receipt history does not match the expense originals.',
          );
        }
      } finally {
        item.dispose();
      }
    }
    final draft = RecordExpenseDraft(
      amount: json['amount'] as String,
      date: json['date'] as String,
      payee: json['payee'] as String,
      paymentAccount: json['paymentAccount'] as String,
      paymentAccountId: json['paymentAccountId'] as String?,
      recurrence: json['recurrence'] == null
          ? null
          : RecurrenceRule.fromJson(
              Map<String, Object?>.from(json['recurrence'] as Map),
            ),
      category: json['category'] as String,
      tax: json['tax'] as String,
      customer: json['customer'] as String,
      billable: json['billable'] as bool,
      dimensions: json['dimensions'] as String,
      itemOrSplitDetails: json['itemOrSplitDetails'] as String,
      notes: json['notes'] as String,
      attachmentName: json['attachmentName'] as String?,
      currencyCode: json['currencyCode'] as String,
      submissionId: json['submissionId'] as String?,
      attachments: List.unmodifiable(attachments),
      reviewSnapshots: List.unmodifiable(reviews),
      documentNumber: json['documentNumber'] as String? ?? '',
      lines: List.unmodifiable([
        for (final line in json['lines'] as List? ?? const [])
          ExpenseDraftLine.fromJson(Map<String, dynamic>.from(line as Map)),
      ]),
      taxMode: json['version'] == 1 ? null : json['taxMode'] as String?,
      claimSource: json['claimSource'] == null
          ? null
          : ExpenseClaimSource.fromJson(
              Map<String, dynamic>.from(json['claimSource'] as Map),
            ),
      taxReviewRequired: json['taxReviewRequired'] as bool? ?? false,
      receiptLineBases: Map.unmodifiable(
        Map<String, String>.from(json['receiptLineBases'] as Map? ?? const {}),
      ),
    );
    draft.validateLines();
    return draft;
  }
}
