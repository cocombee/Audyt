import '../../../core/documents/receipt_document.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';

/// An editable credit proposal, never evidence that a credit was posted.
final class InvoiceCreditDraft {
  InvoiceCreditDraft.fromSnapshot({
    required this.id,
    required this.invoiceId,
    required this.revision,
    required this.savedAt,
    required Map<String, dynamic> snapshot,
  }) : attachments = List.unmodifiable(
         (snapshot['attachments'] as List? ?? const []).map(
           (a) =>
               ReceiptAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
         ),
       ),
       reason = snapshot['reason'] as String,
       date = DateTime.parse(snapshot['date'] as String),
       lineCredits = _readLines(snapshot['lines'] as List<dynamic>) {
    if (snapshot['invoiceId'] != invoiceId.value ||
        revision < 1 ||
        reason.trim().isEmpty) {
      throw FormatException('Invalid saved credit draft.');
    }
  }

  final List<ReceiptAttachment> attachments;
  final EntityId id;
  final EntityId invoiceId;
  final int revision;
  final DateTime savedAt;
  final String reason;
  final DateTime date;
  final Map<EntityId, Money> lineCredits;

  Money get total => lineCredits.values.reduce((a, b) => a + b);

  static Map<EntityId, Money> _readLines(List<dynamic> rows) {
    final lines = <EntityId, Money>{};
    String? currency;
    for (final row in rows) {
      final id = EntityId.parse(row['id'] as String);
      final amount = Money.fromMinor(
        row['minor'] as int,
        row['currency'] as String,
      );
      if (lines.containsKey(id) ||
          amount.minorUnits <= 0 ||
          (currency != null && amount.currency != currency)) {
        throw FormatException('Invalid saved credit lines.');
      }
      currency = amount.currency;
      lines[id] = amount;
    }
    if (lines.isEmpty) throw FormatException('Credit draft has no lines.');
    return Map.unmodifiable(lines);
  }
}
