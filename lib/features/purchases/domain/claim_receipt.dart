import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../../accounting/domain/expense_draft.dart';

/// One supplier receipt inside a reimbursement claim. Each original receipt
/// owns its own amount-entry basis; rows share that basis and select their own
/// company purchase-tax code. This does not assert tax recovery entitlement.
final class ClaimReceiptLine {
  const ClaimReceiptLine({required this.expenseAccountId, required this.item});
  final EntityId expenseAccountId;
  final ExpenseDraftLine item;
  Map<String, Object?> toJson() => {
    'expenseAccountId': expenseAccountId.value,
    'item': item.toJson(),
  };
  factory ClaimReceiptLine.fromJson(Map<String, dynamic> json) =>
      ClaimReceiptLine(
        expenseAccountId: EntityId.parse(json['expenseAccountId'] as String),
        item: ExpenseDraftLine.fromJson(
          Map<String, dynamic>.from(json['item'] as Map),
        ),
      );
}

final class ClaimReceipt {
  ClaimReceipt({
    required this.id,
    required this.merchant,
    required DateTime date,
    required this.currency,
    required this.taxMode,
    required List<ClaimReceiptLine> lines,
    required List<String> originalDocumentIds,
  }) : date = DateTime.utc(date.year, date.month, date.day),
       lines = List.unmodifiable(lines),
       originalDocumentIds = List.unmodifiable(originalDocumentIds) {
    if (id.isEmpty ||
        id != id.trim() ||
        merchant.trim().isEmpty ||
        !const {'Exclusive', 'Inclusive'}.contains(taxMode) ||
        currency != Money.zero(currency).currency ||
        lines.isEmpty ||
        originalDocumentIds.isEmpty ||
        originalDocumentIds.any((id) => id.isEmpty || id != id.trim()) ||
        originalDocumentIds.toSet().length != originalDocumentIds.length) {
      throw const FormatException(
        'Receipt identity, merchant, basis, rows and original evidence are required.',
      );
    }
    final ids = <String>{};
    for (final line in lines) {
      if (line.item.id.isEmpty ||
          line.item.id != line.item.id.trim() ||
          !ids.add(line.item.id) ||
          line.item.category.trim().isEmpty ||
          !Money.fromDecimal(line.item.amount, currency).isPositive) {
        throw const FormatException(
          'Claim receipt rows need distinct identities, categories and positive amounts.',
        );
      }
    }
    // Reuse the actual Expense pricing and inclusive/exclusive owner, including
    // its quantity/rate/adjustment checks rather than a parallel calculator.
    final expense = RecordExpenseDraft(
      amount: totals.total.toDecimalString(),
      date: '',
      payee: merchant,
      paymentAccount: '',
      category: '',
      tax: '',
      customer: '',
      billable: false,
      dimensions: '',
      itemOrSplitDetails: '',
      notes: '',
      currencyCode: currency,
      taxMode: taxMode,
      lines: [for (final line in lines) line.item],
    );
    expense.validateLines();
  }

  final String id, merchant, currency, taxMode;
  final DateTime date;
  final List<ClaimReceiptLine> lines;
  final List<String> originalDocumentIds;

  ({Money net, Money tax, Money total}) get totals {
    var net = Money.zero(currency);
    var tax = Money.zero(currency);
    var total = Money.zero(currency);
    for (final line in lines) {
      final amounts = line.item.calculation(currency, taxMode);
      net += amounts.net;
      tax += amounts.tax;
      total += amounts.total;
    }
    return (net: net, tax: tax, total: total);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'merchant': merchant,
    'date': date.toIso8601String(),
    'currency': currency,
    'taxMode': taxMode,
    'originalDocumentIds': originalDocumentIds,
    'lines': lines.map((line) => line.toJson()).toList(),
  };
  factory ClaimReceipt.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date'] as String);
    if (json['date'] !=
        DateTime.utc(date.year, date.month, date.day).toIso8601String()) {
      throw const FormatException(
        'Receipt date must be a canonical calendar date.',
      );
    }
    return ClaimReceipt(
      id: json['id'] as String,
      merchant: json['merchant'] as String,
      date: date,
      currency: json['currency'] as String,
      taxMode: json['taxMode'] as String,
      originalDocumentIds: (json['originalDocumentIds'] as List).cast<String>(),
      lines: [
        for (final line in json['lines'] as List)
          ClaimReceiptLine.fromJson(Map<String, dynamic>.from(line as Map)),
      ],
    );
  }
}
