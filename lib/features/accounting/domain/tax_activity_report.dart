import '../../../core/ids/entity_id.dart';
import 'company_tax_rate.dart';
import 'company_tax_agency.dart';
import 'ledger_report.dart';
import 'journal_entry.dart';
import 'tax_remittance.dart';

enum TaxActivityKind { invoice, credit, bill, expense, claim }

/// Original posted source facts, not a statutory return or recovery entitlement.
final class TaxActivityRow {
  const TaxActivityRow({
    required this.sourceId,
    required this.journalId,
    required this.lineId,
    required this.date,
    required this.kind,
    required this.documentNumber,
    required this.description,
    required this.basis,
    required this.netMinor,
    required this.taxMinor,
    required this.grossMinor,
    this.code,
    this.ratePercent,
    this.taxAccountId,
    this.unresolvedReason,
    this.isReversal = false,
  });
  final EntityId sourceId, journalId;
  final String lineId, documentNumber, description, basis;
  final DateTime date;
  final TaxActivityKind kind;
  final BigInt? netMinor, taxMinor;
  final BigInt grossMinor;
  final CompanyTaxRate? code;
  final String? ratePercent, unresolvedReason;
  final EntityId? taxAccountId;
  final bool isReversal;
  bool get isPurchase => const {
    TaxActivityKind.bill,
    TaxActivityKind.expense,
    TaxActivityKind.claim,
  }.contains(kind);
  bool get isResolved => netMinor != null && taxMinor != null;
  String get sourceLabel =>
      '${switch (kind) {
        TaxActivityKind.invoice => 'Invoice',
        TaxActivityKind.credit => 'Invoice Credit',
        TaxActivityKind.bill => 'Bill',
        TaxActivityKind.expense => 'Expense',
        TaxActivityKind.claim => 'Claim',
      }}${isReversal ? ' Reversal' : ''}';
  String get taxLabel => !isResolved
      ? 'Tax Facts Unavailable'
      : code?.label ??
            (taxMinor == BigInt.zero &&
                    (ratePercent == null || ratePercent == '0')
                ? 'No Tax'
                : 'Unconfigured Tax${ratePercent == null ? '' : ' · $ratePercent%'}');
}

/// Recorded book attribution, distinct from bank reconciliation and filing.
final class TaxRemittanceActivity {
  TaxRemittanceActivity({
    required this.source,
    required this.allocation,
    this.reversal,
  }) {
    if (!source.allocations.contains(allocation) ||
        reversal != null &&
            (reversal!.kind != TaxRemittanceCorrectionKind.reversal ||
                reversal!.sourceId != source.id)) {
      throw StateError('Remittance activity lost its source allocation.');
    }
  }
  final TaxRemittance source;
  final TaxRemittanceAllocation allocation;
  final TaxRemittanceCorrection? reversal;
  EntityId get journalId => reversal?.journalId ?? source.journalId;
  DateTime get date => reversal?.on ?? source.paidOn;
  BigInt get remittedTax =>
      BigInt.from(allocation.amount.minorUnits) *
      (reversal == null ? BigInt.one : -BigInt.one);
  BigInt get movementCredit => -remittedTax;
}

/// Ledger evidence is not automatically a payment or an agency remittance.
final class TaxAccountMovement {
  TaxAccountMovement({
    required this.journal,
    required this.accountId,
    required Iterable<TaxActivityRow> sourceRows,
    Iterable<TaxRemittanceActivity> remittances = const [],
  }) : sourceRows = List.unmodifiable(sourceRows),
       remittances = List.unmodifiable(remittances) {
    if (this.sourceRows.any(
      (row) =>
          row.isPurchase ||
          row.journalId != journal.id ||
          row.taxAccountId != accountId,
    )) {
      throw StateError('Tax source attribution differs from its journal.');
    }
    if (this.remittances.any(
          (r) =>
              r.journalId != journal.id ||
              r.allocation.liabilityAccountId != accountId,
        ) ||
        this.remittances.isNotEmpty &&
            (this.sourceRows.isNotEmpty ||
                remittanceCredit.sign != movementCredit.sign ||
                remittanceCredit.abs() > movementCredit.abs())) {
      throw StateError(
        'Remittance attribution exceeds its own tax ledger movement.',
      );
    }
    if (this.sourceRows.isNotEmpty && sourceSalesTax != movementCredit) {
      throw StateError(
        'Source sales tax differs from its posted ledger amount.',
      );
    }
  }
  final JournalEntry journal;
  final EntityId accountId;
  final List<TaxActivityRow> sourceRows;
  final List<TaxRemittanceActivity> remittances;
  BigInt get remittanceCredit =>
      remittances.fold(BigInt.zero, (v, r) => v + r.movementCredit);
  BigInt get unattributedMovementCredit =>
      otherMovementCredit - remittanceCredit;
  BigInt _total(bool debit) => journal.lines
      .where((line) => line.accountId == accountId && line.isDebit == debit)
      .fold(
        BigInt.zero,
        (sum, line) => sum + BigInt.from(line.amount.minorUnits),
      );
  BigInt get debits => _total(true);
  BigInt get credits => _total(false);
  BigInt get movementCredit => credits - debits;
  BigInt get sourceSalesTax => sourceRows.fold(
    BigInt.zero,
    (sum, row) => sum + (row.taxMinor ?? BigInt.zero),
  );
  BigInt get otherMovementCredit => movementCredit - sourceSalesTax;
  bool get hasSourceTax => sourceRows.isNotEmpty;
}

final class TaxAccountActivity {
  TaxAccountActivity({
    required this.balance,
    required this.sourceSalesTax,
    required Iterable<TaxAccountMovement> movements,
  }) : movements = List.unmodifiable(movements) {
    BigInt total(BigInt Function(TaxAccountMovement) amount) => this.movements
        .fold(BigInt.zero, (sum, movement) => sum + amount(movement));
    if (this.movements.any((m) => m.accountId != balance.account.id) ||
        total((m) => m.debits) != balance.periodDebits ||
        total((m) => m.credits) != balance.periodCredits ||
        total((m) => m.sourceSalesTax) != sourceSalesTax ||
        openingCredit + total((m) => m.movementCredit) != closingCredit) {
      throw StateError('Tax movement trace does not reconcile to the ledger.');
    }
  }
  final LedgerAccountBalance balance;
  final BigInt sourceSalesTax;
  final List<TaxAccountMovement> movements;
  BigInt get openingCredit => -balance.openingNetDebit;
  BigInt get movementCredit => balance.periodCredits - balance.periodDebits;
  BigInt get otherMovementCredit => movementCredit - sourceSalesTax;
  BigInt get closingCredit => -balance.endingNetDebit;
  BigInt get remittanceCredit =>
      movements.fold(BigInt.zero, (v, m) => v + m.remittanceCredit);
  BigInt get unattributedMovementCredit =>
      otherMovementCredit - remittanceCredit;
}

/// Separate registration revisions never silently merge after master edits.
final class TaxAgencyActivity {
  TaxAgencyActivity({
    required this.agency,
    required Iterable<TaxActivityRow> activity,
    Iterable<TaxRemittanceActivity> remittances = const [],
  }) : rows = List.unmodifiable(activity),
       remittances = List.unmodifiable(remittances);
  final CompanyTaxAgency? agency;
  final List<TaxActivityRow> rows;
  final List<TaxRemittanceActivity> remittances;
  BigInt get remittedTax =>
      remittances.fold(BigInt.zero, (v, r) => v + r.remittedTax);
  String get label => agency?.name ?? 'Unassigned Agency';
  BigInt get salesTax => _tax(false);
  BigInt get purchaseTaxInCost => _tax(true);
  BigInt _tax(bool purchase) => rows
      .where((r) => r.isPurchase == purchase)
      .fold(BigInt.zero, (v, r) => v + (r.taxMinor ?? BigInt.zero));
  int get unresolvedCount => rows.where((r) => !r.isResolved).length;
}

final class TaxActivityReport {
  TaxActivityReport.build({
    required this.ledger,
    required Iterable<TaxActivityRow> activity,
    required Set<EntityId> taxAccountIds,
    Iterable<TaxRemittanceActivity> remittanceActivity = const [],
  }) : rows = List.unmodifiable(activity),
       remittances = List.unmodifiable(remittanceActivity) {
    final seen = <String>{};
    final sourceIndex = <(EntityId, EntityId), List<TaxActivityRow>>{};
    final posted = {for (final entry in ledger.postedEntries) entry.id: entry};
    for (final row in rows) {
      final day = DateTime.utc(row.date.year, row.date.month, row.date.day);
      final journal = posted[row.journalId];
      if (journal == null ||
          day !=
              DateTime.utc(
                journal.date.year,
                journal.date.month,
                journal.date.day,
              ) ||
          row.isReversal != (journal.reversesId != null) ||
          (row.netMinor == null) != (row.taxMinor == null) ||
          (!row.isPurchase &&
              row.taxAccountId != null &&
              !taxAccountIds.contains(row.taxAccountId)) ||
          day.isBefore(ledger.from) ||
          day.isAfter(ledger.through) ||
          !ledger.postedJournalIds.contains(row.journalId) ||
          !seen.add(
            '${row.journalId.value}:${row.sourceId.value}:${row.lineId}',
          ) ||
          (row.isResolved && row.netMinor! + row.taxMinor! != row.grossMinor) ||
          (!row.isPurchase &&
              row.taxMinor != null &&
              row.taxMinor != BigInt.zero &&
              row.taxAccountId == null)) {
        throw StateError('Tax activity does not match its posted source.');
      }
      if (!row.isPurchase && row.taxAccountId != null) {
        sourceIndex
            .putIfAbsent((row.taxAccountId!, row.journalId), () => [])
            .add(row);
      }
    }
    final remittanceIndex =
        <(EntityId, EntityId), List<TaxRemittanceActivity>>{};
    final remittanceGroups = <String, List<TaxRemittanceActivity>>{};
    final remittanceSeen = <String>{};
    for (final r in remittances) {
      final journal = posted[r.journalId];
      if (r.source.businessId != ledger.businessId ||
          r.source.total.currency != ledger.currency ||
          journal == null ||
          r.date.isBefore(ledger.from) ||
          r.date.isAfter(ledger.through) ||
          r.date !=
              DateTime.utc(
                journal.date.year,
                journal.date.month,
                journal.date.day,
              ) ||
          (r.reversal == null
              ? journal.reversesId != null
              : journal.reversesId != r.source.journalId) ||
          !taxAccountIds.contains(r.allocation.liabilityAccountId) ||
          !remittanceSeen.add(
            '${r.source.id.value}/${r.journalId.value}/${r.allocation.key}',
          )) {
        throw StateError('Remittance activity differs from its posted source.');
      }
      remittanceIndex
          .putIfAbsent((r.allocation.liabilityAccountId, r.journalId), () => [])
          .add(r);
      remittanceGroups.putIfAbsent(r.allocation.agency.choice, () => []).add(r);
    }
    final groups = <String, List<TaxActivityRow>>{};
    for (final row in rows) {
      groups
          .putIfAbsent(row.code?.agencySnapshot?.choice ?? '', () => [])
          .add(row);
    }
    agencyGroups = List.unmodifiable([
      for (final key in {...groups.keys, ...remittanceGroups.keys})
        TaxAgencyActivity(
          agency:
              groups[key]?.first.code?.agencySnapshot ??
              remittanceGroups[key]?.first.allocation.agency,
          activity: groups[key] ?? const [],
          remittances: remittanceGroups[key] ?? const [],
        ),
    ]);
    accounts = List.unmodifiable([
      for (final balance in ledger.rows)
        if (taxAccountIds.contains(balance.account.id))
          TaxAccountActivity(
            balance: balance,
            movements: [
              for (final journal in ledger.activityFor(balance.account.id))
                TaxAccountMovement(
                  journal: journal,
                  accountId: balance.account.id,
                  remittances:
                      remittanceIndex[(balance.account.id, journal.id)] ??
                      const [],
                  sourceRows:
                      sourceIndex[(balance.account.id, journal.id)] ?? const [],
                ),
            ],
            sourceSalesTax: rows
                .where(
                  (r) => !r.isPurchase && r.taxAccountId == balance.account.id,
                )
                .fold(
                  BigInt.zero,
                  (sum, row) => sum + (row.taxMinor ?? BigInt.zero),
                ),
          ),
    ]);
    if (accounts.length != taxAccountIds.length) {
      throw StateError('A tax account is missing from the company ledger.');
    }
  }
  final LedgerReport ledger;
  final List<TaxActivityRow> rows;
  final List<TaxRemittanceActivity> remittances;
  BigInt get remittedTax =>
      remittances.fold(BigInt.zero, (v, r) => v + r.remittedTax);
  late final List<TaxAccountActivity> accounts;
  late final List<TaxAgencyActivity> agencyGroups;
  BigInt get salesTax => _tax(false);
  BigInt get purchaseTaxInCost => _tax(true);
  BigInt _tax(bool purchase) => rows
      .where((r) => r.isPurchase == purchase)
      .fold(BigInt.zero, (sum, row) => sum + (row.taxMinor ?? BigInt.zero));
  List<TaxActivityRow> get unresolved =>
      List.unmodifiable(rows.where((r) => !r.isResolved));
}
