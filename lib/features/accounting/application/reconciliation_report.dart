import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';
import '../../../../core/money/money.dart';
import '../domain/statement_reconciliation.dart';

/// Standalone, printable evidence export. No remote resources or executable data.
String reconciliationReportHtml({
  required String businessId,
  required DateTime generatedAt,
  required StatementReconciliationHistory approval,
  required ReconciliationEvidence evidence,
  required ReconciliationLedgerSnapshot? ledger,
  required ReconciliationClassification? classification,
  required ReconciliationLedgerChanges changes,
}) {
  String escape(Object? value) => (value?.toString() ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  String money(Money value) {
    final digits = Currency.parse(value.currency).fractionDigits;
    final integer = BigInt.from(value.minorUnits);
    final raw = integer.abs().toString().padLeft(digits + 1, '0');
    final number = digits == 0
        ? raw
        : '${raw.substring(0, raw.length - digits)}.${raw.substring(raw.length - digits)}';
    return currencyAmountLabel(
      value.currency,
      '${integer.isNegative ? '-' : ''}$number',
    );
  }

  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final body = StringBuffer();
  void paragraph(Object text) => body.write('<p>${escape(text)}</p>');
  void heading(String text) => body.write('<h2>${escape(text)}</h2>');
  void table(List<String> headers, Iterable<List<Object?>> rows) {
    body.write('<table><thead><tr>');
    for (final header in headers) {
      body.write('<th>${escape(header)}</th>');
    }
    body.write('</tr></thead><tbody>');
    for (final row in rows) {
      body.write('<tr>');
      for (final cell in row) {
        body.write('<td>${escape(cell)}</td>');
      }
      body.write('</tr>');
    }
    body.write('</tbody></table>');
  }

  paragraph('Business: $businessId');
  paragraph(
    'Approval: ${approval.id} · ${approval.reopenedAt == null ? 'Approved' : 'Reopened'}',
  );
  paragraph(
    '${evidence.isAccountPeriod ? 'Period' : 'Statement'}: ${date(approval.startsOn)} to ${date(approval.endsOn)}',
  );
  paragraph('Payment Account: ${approval.paymentAccountId}');
  paragraph(
    'Approved by ${approval.actorId} at ${approval.approvedAt.toUtc().toIso8601String()}',
  );
  if (approval.previousId != null) {
    paragraph('Previous Approval: ${approval.previousId}');
  }
  if (approval.reopenedAt != null) {
    paragraph(
      'Reopened by ${approval.reopenedBy} at ${approval.reopenedAt!.toUtc().toIso8601String()}: ${approval.reopeningReason}',
    );
  }
  heading('Balances');
  table(
    ['Measure', 'Amount'],
    [
      ['Statement Opening', money(approval.openingBalance)],
      ['Statement Closing', money(approval.closingBalance)],
      [
        'Ledger at Approval',
        ledger == null
            ? 'Unavailable for this older approval'
            : money(ledger.balance),
      ],
      [
        'Cleared at Approval',
        classification == null
            ? 'Unavailable'
            : money(classification.clearedBalance),
      ],
      [
        'Outstanding at Approval',
        classification == null
            ? 'Unavailable'
            : money(classification.outstandingBalance),
      ],
      [
        'Closing Difference',
        classification == null
            ? 'Unavailable'
            : money(classification.closingDifference),
      ],
    ],
  );
  if (classification != null && classification.unresolved.isNotEmpty) {
    paragraph(
      'Unresolved ledger identities: ${classification.unresolved.join(', ')}',
    );
  }
  heading('Source and Opening Evidence');
  if (!evidence.isAccountPeriod) {
    paragraph('Original File: ${evidence.filename}');
    paragraph('SHA-256: ${evidence.sourceDigest}');
  }
  paragraph(approval.openingEvidence);
  table(
    ['Opening Outstanding Movement', 'Date', 'Description', 'Signed Amount'],
    [
      for (final row in evidence.openingOutstanding)
        [row.id, date(row.date), row.memo, money(row.amount)],
    ],
  );
  if (evidence.isAccountPeriod) {
    heading('Approved Cleared Transactions');
    table(
      ['Ledger Movement', 'Date', 'Description', 'Signed Amount'],
      [
        for (final m in evidence.selectedMovements)
          [m.id, date(m.date), m.memo, money(m.amount)],
      ],
    );
  }
  if (!evidence.isAccountPeriod) {
    heading('Approved Statement Matches');
    table(
      [
        'Row',
        'Statement Date',
        'Description / Reference',
        'Amount',
        'Ledger Evidence',
      ],
      [
        for (final row in evidence.matches)
          [
            row.statementRow.sourceRow,
            date(row.statementRow.date),
            '${row.statementRow.description}\n${row.statementRow.reference}',
            money(row.statementRow.amount),
            row.combinedMovements.isEmpty
                ? '${row.journalId} / ${row.lineIndex + 1}\n${date(row.journalDate)} · ${row.journalMemo}\nAcceptance: ${row.acceptanceId}'
                : '${row.combinedMovements.map((part) => '${part.candidate.journalId.value} / ${part.candidate.lineIndex + 1}\n${date(part.candidate.date)} · ${part.candidate.memo} · ${money(part.amount)}').join('\n')}\nAcceptance: ${row.acceptanceId}',
          ],
      ],
    );
  }
  heading('Ledger at Approval');
  if (ledger == null) {
    paragraph(
      'No ledger snapshot was captured for this older approval. Current entries have not been substituted.',
    );
  } else {
    final cleared = classification?.cleared.map((row) => row.id).toSet();
    table(
      ['Movement', 'Date', 'Description', 'Signed Amount', 'Status'],
      [
        for (final row in ledger.movements)
          [
            row.id,
            date(row.date),
            row.memo,
            money(row.amount),
            cleared == null
                ? 'Unavailable'
                : cleared.contains(row.id)
                ? 'Cleared'
                : 'Outstanding',
          ],
      ],
    );
  }
  heading('Changes Detected at Export');
  paragraph(
    'Checked at ${generatedAt.toUtc().toIso8601String()}. These changes are separate from the saved approval.',
  );
  if (!changes.snapshotAvailable) {
    paragraph(
      'Comparison unavailable because this approval has no ledger snapshot.',
    );
  } else if (changes.unchanged) {
    paragraph('No ledger changes detected through the approved statement end.');
  } else {
    table(
      ['Change', 'Movement', 'Date', 'Description', 'Signed Amount'],
      [
        for (final row in changes.added)
          ['Added', row.id, date(row.date), row.memo, money(row.amount)],
        for (final row in changes.missing)
          ['Missing', row.id, date(row.date), row.memo, money(row.amount)],
        for (final id in changes.changed)
          ['Changed', id, '', '', 'Review ledger evidence'],
      ],
    );
  }
  return '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Reconciliation Report</title><style>
body{font:12px/1.5 system-ui,sans-serif;color:#222;max-width:1100px;margin:32px auto;padding:0 24px}h1{font-size:24px}h2{font-size:16px;margin-top:28px}p{white-space:pre-wrap;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;margin:12px 0;table-layout:fixed}th,td{text-align:left;vertical-align:top;border:1px solid #ddd;padding:8px;overflow-wrap:anywhere;white-space:pre-wrap}th{background:#f4f4f4}thead{display:table-header-group}tr{break-inside:avoid}@media print{body{margin:0;padding:0;font-size:9px}h2{break-after:avoid}@page{size:A4 landscape;margin:14mm}}
</style></head><body><h1>Reconciliation Report</h1>$body</body></html>''';
}
