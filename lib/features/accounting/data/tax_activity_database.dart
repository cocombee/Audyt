part of 'accounting_database.dart';

extension _TaxActivityReads on LocalAccountingDatabase {
  TaxActivityReport _buildTaxActivityReport(LedgerReport ledger) {
    final business = ledger.businessId;
    final journals = {for (final j in ledger.postedEntries) j.id: j};
    final reversals = <EntityId, List<JournalEntry>>{};
    for (final journal in journals.values) {
      if (journal.reversesId != null) {
        reversals.putIfAbsent(journal.reversesId!, () => []).add(journal);
      }
    }
    final rows = <TaxActivityRow>[];
    final accounts = <EntityId>{};
    // Include retired account mappings, so master edits cannot hide liabilities.
    for (final row in _database.select(
      'SELECT payload FROM company_tax_rate_history WHERE business_id=?',
      [business.value],
    )) {
      final code = CompanyTaxRate.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      if (code.application != TaxApplication.purchases) {
        accounts.add(code.salesAccountId);
      }
    }

    void add({
      required EntityId journalId,
      required EntityId sourceId,
      required String lineId,
      required TaxActivityKind kind,
      required String number,
      required String description,
      required String basis,
      required Money gross,
      Money? net,
      Money? tax,
      CompanyTaxRate? code,
      String? percent,
      EntityId? taxAccount,
      String? unresolved,
    }) {
      if (gross.currency != ledger.currency ||
          net != null && net.currency != ledger.currency ||
          tax != null && tax.currency != ledger.currency) {
        throw StateError('Tax source currency differs from the report.');
      }
      final original = journals[journalId];
      if (original == null) return;
      if (taxAccount != null) accounts.add(taxAccount);
      for (final journal in [original, ...?reversals[journalId]]) {
        final day = accountingCalendarDate(journal.date);
        if (day.isBefore(ledger.from) || day.isAfter(ledger.through)) continue;
        final reversed = journal.id != journalId;
        final sign = reversed ? -BigInt.one : BigInt.one;
        rows.add(
          TaxActivityRow(
            sourceId: sourceId,
            journalId: journal.id,
            lineId: lineId,
            date: day,
            kind: kind,
            documentNumber: number,
            description: description,
            basis: basis,
            code: code,
            ratePercent: percent,
            taxAccountId: taxAccount,
            netMinor: net == null ? null : BigInt.from(net.minorUnits) * sign,
            taxMinor: tax == null ? null : BigInt.from(tax.minorUnits) * sign,
            grossMinor: BigInt.from(gross.minorUnits) * sign,
            unresolvedReason: unresolved,
            isReversal: reversed,
          ),
        );
      }
    }

    // Read original recognition sources even before From: their reversal may be
    // in this period. Journal snapshot membership bounds Through consistently.
    final invoices = <EntityId, Invoice>{};
    final invoiceAccounts = <EntityId, EntityId?>{};
    for (final row in _database.select(
      '''
      SELECT p.invoice_id,p.journal_id,p.document_number,d.payload
      FROM invoice_postings p JOIN invoice_drafts d
        ON d.business_id=p.business_id AND d.id=p.invoice_id
      WHERE p.business_id=?
    ''',
      [business.value],
    )) {
      final invoice = Invoice.fromDraftSnapshot(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      invoices[invoice.id] = invoice;
      final taxAccount = invoicePostingAccounts(business, invoice.id)!.tax;
      invoiceAccounts[invoice.id] = taxAccount;
      final journalId = EntityId.parse(row['journal_id'] as String);
      if (invoice.lines.isEmpty) {
        add(
          journalId: journalId,
          sourceId: invoice.id,
          lineId: '',
          kind: TaxActivityKind.invoice,
          number: row['document_number'] as String,
          description: '',
          basis: invoice.taxMode,
          gross: invoice.total,
          taxAccount: taxAccount,
          unresolved: 'This historical invoice has no saved line tax facts.',
        );
      }
      for (final line in invoice.lines) {
        add(
          journalId: journalId,
          sourceId: invoice.id,
          lineId: line.id.value,
          kind: TaxActivityKind.invoice,
          number: row['document_number'] as String,
          description: line.description,
          basis: invoice.taxMode,
          net: line.subtotal,
          tax: line.tax,
          gross: line.total,
          code: line.taxSnapshot,
          percent: line.taxRatePercent,
          taxAccount: taxAccount,
        );
      }
    }
    for (final row in _database.select(
      '''
      SELECT c.journal_id,c.draft_id,c.invoice_id,l.line_id,
        l.net_minor,l.tax_minor,l.gross_minor,l.currency
      FROM invoice_credit_postings c JOIN invoice_credit_lines l
        ON l.business_id=c.business_id AND l.draft_id=c.draft_id
      WHERE c.business_id=?
    ''',
      [business.value],
    )) {
      final invoiceId = EntityId.parse(row['invoice_id'] as String);
      final invoice = invoices[invoiceId];
      final lineId = EntityId.parse(row['line_id'] as String);
      final line = invoice?.lines.where((l) => l.id == lineId).firstOrNull;
      if (line == null) {
        throw StateError('A posted tax credit has no original line.');
      }
      Money negative(String key) =>
          Money.fromMinor(-(row[key] as int), row['currency'] as String);
      add(
        journalId: EntityId.parse(row['journal_id'] as String),
        sourceId: EntityId.parse(row['draft_id'] as String),
        lineId: lineId.value,
        kind: TaxActivityKind.credit,
        number: invoice!.documentNumber,
        description: line.description,
        basis: invoice.taxMode,
        net: negative('net_minor'),
        tax: negative('tax_minor'),
        gross: negative('gross_minor'),
        code: line.taxSnapshot,
        percent: line.taxRatePercent,
        taxAccount: invoiceAccounts[invoiceId],
      );
    }
    for (final row in _database.select(
      '''
      SELECT p.bill_id,p.journal_id FROM bill_postings p WHERE p.business_id=?
    ''',
      [business.value],
    )) {
      final bill = readBillDraft(
        business,
        EntityId.parse(row['bill_id'] as String),
      )!;
      for (final line in bill.lines) {
        add(
          journalId: EntityId.parse(row['journal_id'] as String),
          sourceId: bill.id,
          lineId: line.id.value,
          kind: TaxActivityKind.bill,
          number: bill.documentNumber,
          description: line.description,
          basis:
              bill.taxMode ?? (line.taxInclusive ? 'Inclusive' : 'Exclusive'),
          net: line.subtotal,
          tax: line.tax,
          gross: line.total,
          code: line.taxSnapshot,
          percent: line.taxRatePercent,
        );
      }
    }
    // Retain each posted version. The journal index below supplies its signed
    // reversal, so revisions affect tax reports only after actual approval.
    final expenseTaxSources = [
      ..._database.select(
        'SELECT * FROM expense_intakes WHERE business_id=? AND journal_id IS NOT NULL',
        [business.value],
      ),
      if (_hasExpenseRevisionViews)
        ..._database.select(
          'SELECT p.expense_id AS id,p.journal_id,d.payload,d.amount_minor,d.currency '
          'FROM expense_revision_postings p JOIN expense_revision_drafts d '
          'ON d.business_id=p.business_id AND d.expense_id=p.expense_id AND d.revision=p.revision '
          'WHERE p.business_id=?',
          [business.value],
        ),
    ];
    for (final row in expenseTaxSources) {
      final draft = RecordExpenseDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      if (draft.claimSource != null) {
        if (row['journal_id'] == draft.claimSource!.recognitionId.value) {
          _validateClaimExpenseRow(row);
          continue; // Original Claim below owns its tax facts exactly once.
        }
        final source = draft.claimSource!;
        for (final line in draft.lines) {
          final basis = source.lineBases[line.id]!;
          final amounts = line.calculation(draft.currencyCode, basis);
          add(
            journalId: EntityId.parse(row['journal_id'] as String),
            sourceId: source.claimId,
            lineId: line.id,
            kind: TaxActivityKind.claim,
            number: draft.payee,
            description: line.description,
            basis: basis,
            net: amounts.net,
            tax: amounts.tax,
            gross: amounts.total,
            code: line.taxSnapshot,
            percent: line.taxSnapshot?.percent,
          );
        }
        continue;
      }
      final id = EntityId.parse(row['id'] as String);
      final journalId = EntityId.parse(row['journal_id'] as String);
      if (draft.taxMode == null || draft.lines.isEmpty) {
        add(
          journalId: journalId,
          sourceId: id,
          lineId: '',
          kind: TaxActivityKind.expense,
          number: draft.documentNumber,
          description: draft.notes,
          basis: 'Not Recorded',
          gross: Money.fromMinor(
            row['amount_minor'] as int,
            row['currency'] as String,
          ),
          unresolved:
              'This historical expense has no saved tax basis and line rates.',
        );
      } else {
        for (final line in draft.lines) {
          final amounts = line.calculation(draft.currencyCode, draft.taxMode!);
          add(
            journalId: journalId,
            sourceId: id,
            lineId: line.id,
            kind: TaxActivityKind.expense,
            number: draft.documentNumber,
            description: line.description,
            basis: draft.taxMode!,
            net: amounts.net,
            tax: amounts.tax,
            gross: amounts.total,
            code: line.taxSnapshot,
            percent: line.taxSnapshot?.percent,
          );
        }
      }
    }
    for (final row in _database.select(
      'SELECT * FROM all_claim_postings WHERE business_id=?',
      [business.value],
    )) {
      // A returned/corrected claim may have newer mutable facts; use the exact
      // immutable payload from this recognition cycle, including its reversals.
      final claim = Claim.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(row['claim_payload'] as String) as Map,
        ),
      );
      if (claim.receipts.isEmpty) {
        add(
          journalId: EntityId.parse(row['journal_id'] as String),
          sourceId: claim.id,
          lineId: '',
          kind: TaxActivityKind.claim,
          number: claim.vendorName,
          description: claim.businessPurpose,
          basis: 'Not Recorded',
          gross: claim.amount,
          unresolved:
              'Receipt-level tax facts have not been recorded for this claim.',
        );
      } else {
        for (final receipt in claim.receipts) {
          for (final line in receipt.lines) {
            final amounts = line.item.calculation(
              receipt.currency,
              receipt.taxMode,
            );
            add(
              journalId: EntityId.parse(row['journal_id'] as String),
              sourceId: claim.id,
              lineId: line.item.id,
              kind: TaxActivityKind.claim,
              number: receipt.merchant,
              description: line.item.description,
              basis: receipt.taxMode,
              gross: amounts.total,
              net: amounts.net,
              tax: amounts.tax,
              code: line.item.taxSnapshot,
              percent: line.item.taxSnapshot?.percent,
            );
          }
        }
      }
    }
    rows.sort((a, b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      return '${a.journalId.value}:${a.lineId}'.compareTo(
        '${b.journalId.value}:${b.lineId}',
      );
    });
    final remittanceActivity = <TaxRemittanceActivity>[];
    for (final payment in readTaxRemittances(
      business,
      includeCorrected: true,
    )) {
      final correction = readTaxRemittanceCorrection(business, payment.id);
      if (correction?.kind == TaxRemittanceCorrectionKind.unlink) continue;
      for (final reversal in [null, ?correction]) {
        final date = reversal?.on ?? payment.paidOn;
        if (date.isBefore(ledger.from) || date.isAfter(ledger.through)) {
          continue;
        }
        for (final allocation in payment.allocations) {
          accounts.add(allocation.liabilityAccountId);
          remittanceActivity.add(
            TaxRemittanceActivity(
              source: payment,
              allocation: allocation,
              reversal: reversal,
            ),
          );
        }
      }
    }
    return TaxActivityReport.build(
      remittanceActivity: remittanceActivity,
      ledger: ledger,
      activity: rows,
      taxAccountIds: accounts,
    );
  }
}
