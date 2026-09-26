import '../../../core/ids/entity_id.dart';
import '../../accounting/domain/account.dart';
import '../../accounting/domain/journal_entry.dart';
import '../../accounting/domain/ledger_report.dart';
import 'product_catalogue.dart';

enum SalesSourceKind { invoice, credit, journal }

/// Attribution of existing posted income, never another revenue calculation.
final class SalesIncomeAllocation {
  const SalesIncomeAllocation({
    required this.journalId,
    required this.sourceId,
    required this.kind,
    required this.netMinor,
    this.lineId,
    this.documentNumber = '',
    this.catalogue,
  });
  final EntityId journalId, sourceId;
  final EntityId? lineId;
  final SalesSourceKind kind;
  final BigInt netMinor;
  final String documentNumber;
  final CatalogueLineSnapshot? catalogue;
}

final class SalesReportSource {
  const SalesReportSource({required this.allocation, required this.journal});
  final SalesIncomeAllocation allocation;
  final JournalEntry journal;
}

final class SalesReportItem {
  SalesReportItem({
    required this.id,
    required this.name,
    required List<SalesReportSource> sources,
  }) : sources = List.unmodifiable(sources);
  final EntityId? id;
  final String name;
  final List<SalesReportSource> sources;
  BigInt get netMinor => sources.fold(
    BigInt.zero,
    (sum, source) => sum + source.allocation.netMinor,
  );
}

final class SalesReportCategory {
  SalesReportCategory({
    required this.id,
    required this.name,
    required List<SalesReportItem> items,
  }) : items = List.unmodifiable(items);
  final EntityId? id;
  final String name;
  final List<SalesReportItem> items;
  BigInt get netMinor =>
      items.fold(BigInt.zero, (sum, item) => sum + item.netMinor);
}

/// Shares LedgerReport.revenue with Home. Saved catalogue snapshots allocate
/// that same total; historical/manual income remains visible as Unclassified.
final class SalesReport {
  SalesReport._(this.ledger, List<SalesReportCategory> categories)
    : categories = List.unmodifiable(categories);

  factory SalesReport.build({
    required LedgerReport ledger,
    required List<SalesIncomeAllocation> allocations,
  }) {
    final incomeAccounts = ledger.rows
        .where((row) => row.account.type == AccountType.income)
        .map((row) => row.account.id)
        .toSet();
    final entries =
        ledger.postedEntries
            .where(
              (entry) =>
                  !entry.isClosing &&
                  !DateTime.utc(
                    entry.date.year,
                    entry.date.month,
                    entry.date.day,
                  ).isBefore(ledger.from),
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            return byDate == 0 ? a.id.value.compareTo(b.id.value) : byDate;
          });
    final byJournal = <EntityId, List<SalesIncomeAllocation>>{};
    final seen = <String>{};
    final entryIds = entries.map((entry) => entry.id).toSet();
    for (final allocation in allocations) {
      if (!entryIds.contains(allocation.journalId)) {
        throw StateError(
          'Sales attribution is outside the posted report snapshot.',
        );
      }
      if (!seen.add(
        '${allocation.journalId}:${allocation.lineId ?? allocation.sourceId}',
      )) {
        throw StateError('A sales source line appears twice.');
      }
      byJournal.putIfAbsent(allocation.journalId, () => []).add(allocation);
    }
    final grouped = <EntityId?, Map<EntityId?, List<SalesReportSource>>>{};
    final categoryNames = <EntityId?, String>{null: 'Unclassified'};
    final itemNames = <(EntityId?, EntityId?), String>{};
    for (final entry in entries) {
      final net = entry.lines
          .where((line) => incomeAccounts.contains(line.accountId))
          .fold(
            BigInt.zero,
            (sum, line) =>
                sum +
                BigInt.from(line.amount.minorUnits) *
                    (line.isCredit ? BigInt.one : -BigInt.one),
          );
      var sources = byJournal[entry.id];
      if (sources == null) {
        if (net == BigInt.zero) continue;
        sources = [
          SalesIncomeAllocation(
            journalId: entry.id,
            sourceId: entry.id,
            kind: SalesSourceKind.journal,
            netMinor: net,
          ),
        ];
      } else if (sources.fold(BigInt.zero, (sum, row) => sum + row.netMinor) !=
          net) {
        throw StateError(
          'Saved sales sources do not reconcile to their posted income.',
        );
      }
      for (final source in sources) {
        final snapshot = source.catalogue;
        final categoryId = snapshot?.categoryId;
        final itemId = snapshot?.itemId;
        categoryNames[categoryId] = snapshot?.categoryName ?? 'Unclassified';
        itemNames[(categoryId, itemId)] =
            snapshot?.itemName ?? 'Unclassified Sales';
        grouped
            .putIfAbsent(categoryId, () => {})
            .putIfAbsent(itemId, () => [])
            .add(SalesReportSource(allocation: source, journal: entry));
      }
    }
    final categories =
        [
          for (final category in grouped.entries)
            SalesReportCategory(
              id: category.key,
              name: categoryNames[category.key]!,
              items: [
                for (final item in category.value.entries)
                  SalesReportItem(
                    id: item.key,
                    name: itemNames[(category.key, item.key)]!,
                    sources: item.value,
                  ),
              ]..sort((a, b) => a.name.compareTo(b.name)),
            ),
        ]..sort((a, b) {
          final bySales = b.netMinor.compareTo(a.netMinor);
          return bySales == 0 ? a.name.compareTo(b.name) : bySales;
        });
    if (categories.fold(
          BigInt.zero,
          (sum, category) => sum + category.netMinor,
        ) !=
        ledger.revenue) {
      throw StateError(
        'Sales categories do not reconcile to the existing ledger revenue.',
      );
    }
    return SalesReport._(ledger, categories);
  }

  final LedgerReport ledger;
  final List<SalesReportCategory> categories;
  BigInt get netMinor => ledger.revenue;
}
