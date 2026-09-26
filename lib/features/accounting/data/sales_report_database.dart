part of 'accounting_database.dart';

extension _SalesReportReads on LocalAccountingDatabase {
  List<SalesIncomeAllocation> _readSalesIncomeAllocations(LedgerReport report) {
    final business = report.businessId.value;
    String day(DateTime date) => date.toIso8601String().substring(0, 10);
    final range = [business, day(report.from), day(report.through)];
    final allocations = <SalesIncomeAllocation>[];
    for (final row in _database.select('''
      SELECT d.payload,p.invoice_id,p.journal_id,p.document_number
      FROM invoice_postings p
      JOIN invoice_drafts d ON d.business_id=p.business_id AND d.id=p.invoice_id
      JOIN journal_entries j ON j.business_id=p.business_id AND j.id=p.journal_id
      WHERE p.business_id=? AND j.state='posted' AND j.deleted_at IS NULL
        AND substr(j.entry_date,1,10)>=? AND substr(j.entry_date,1,10)<=?
      ORDER BY j.entry_date,p.journal_id
    ''', range)) {
      final invoice = Invoice.fromDraftSnapshot(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      if (invoice.total.currency != report.currency) {
        throw StateError('Sales source currency differs from the report.');
      }
      final journalId = EntityId.parse(row['journal_id'] as String);
      final number = row['document_number'] as String;
      if (invoice.lines.isEmpty) {
        allocations.add(
          SalesIncomeAllocation(
            journalId: journalId,
            sourceId: invoice.id,
            kind: SalesSourceKind.invoice,
            documentNumber: number,
            netMinor: BigInt.from(invoice.total.minorUnits),
          ),
        );
      }
      for (final line in invoice.lines) {
        allocations.add(
          SalesIncomeAllocation(
            journalId: journalId,
            sourceId: invoice.id,
            lineId: line.id,
            kind: SalesSourceKind.invoice,
            documentNumber: number,
            netMinor: BigInt.from(line.subtotal.minorUnits),
            catalogue: line.catalogue,
          ),
        );
      }
    }
    for (final row in _database.select('''
      SELECT c.journal_id,c.draft_id,l.line_id,l.net_minor,l.currency,
        p.document_number,d.payload
      FROM invoice_credit_postings c
      JOIN invoice_credit_lines l ON l.business_id=c.business_id AND l.draft_id=c.draft_id
      JOIN invoice_postings p ON p.business_id=c.business_id AND p.invoice_id=c.invoice_id
      JOIN invoice_drafts d ON d.business_id=p.business_id AND d.id=p.invoice_id
      JOIN journal_entries j ON j.business_id=c.business_id AND j.id=c.journal_id
      WHERE c.business_id=? AND j.state='posted' AND j.deleted_at IS NULL
        AND substr(j.entry_date,1,10)>=? AND substr(j.entry_date,1,10)<=?
      ORDER BY j.entry_date,c.journal_id,l.line_id
    ''', range)) {
      if (row['currency'] != report.currency) {
        throw StateError('Sales credit currency differs from the report.');
      }
      final invoice = Invoice.fromDraftSnapshot(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      final lineId = EntityId.parse(row['line_id'] as String);
      final original = invoice.lines
          .where((line) => line.id == lineId)
          .firstOrNull;
      if (original == null) {
        throw StateError('A posted sales credit has no original invoice line.');
      }
      allocations.add(
        SalesIncomeAllocation(
          journalId: EntityId.parse(row['journal_id'] as String),
          sourceId: EntityId.parse(row['draft_id'] as String),
          lineId: lineId,
          kind: SalesSourceKind.credit,
          documentNumber: row['document_number'] as String,
          netMinor: -BigInt.from(row['net_minor'] as int),
          catalogue: original.catalogue,
        ),
      );
    }
    return allocations;
  }
}
