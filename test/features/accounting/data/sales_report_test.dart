import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/domain/sales_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/sales_report_fixture.dart';
import '../../../support/credit_posting_fixture.dart';

void main() {
  test('category and item totals use the Home ledger owner, excluding drafts and tax', () async {
    final f = await salesReportFixture();
    addTearDown(f.workspace.dispose);
    final item = f.workspace.catalogueItems.first;
    final category = f.workspace.catalogueCategories.singleWhere(
      (c) => c.id == item.categoryId,
    );
    f.addInvoice(
      item: item,
      category: category,
      minor: 99900,
      date: DateTime.utc(2026, 9, 30, 23, 59),
      post: false,
    );
    final taxed = f.addInvoice(
      item: item,
      category: category,
      minor: 10800,
      discount: 1080,
      taxRate: '8',
      inclusive: true,
      date: DateTime.utc(2026, 9, 30, 23, 59),
    );
    f.addInvoice(
      item: item,
      category: category,
      minor: 10000,
      date: DateTime.utc(2026, 10, 1),
    );
    final report = await f.workspace.reportWithSales(
      from: DateTime(2026, 9, 1),
      through: DateTime(2026, 9, 30),
    );
    final home = await f.workspace.report(
      from: DateTime(2026, 9, 1),
      through: DateTime(2026, 9, 30),
    );
    expect(report.sales.netMinor, home.revenue);
    expect(
      report.sales.netMinor,
      BigInt.from(2250000 + taxed.lines.single.subtotal.minorUnits),
    );
    expect(
      report.sales.categories.fold(BigInt.zero, (sum, c) => sum + c.netMinor),
      home.revenue,
    );
    expect(
      report.sales.categories
          .expand((c) => c.items)
          .fold(BigInt.zero, (sum, i) => sum + i.netMinor),
      home.revenue,
    );
    expect(
      report.sales.categories.expand((c) => c.items).expand((i) => i.sources),
      hasLength(4),
    );
    expect(f.workspace.invoiceDrafts(), hasLength(1));
  });

  test('historical snapshot grouping survives rename, archive, reopen and data restore', () async {
    final root = Directory.systemTemp.createTempSync('audyt-sales-report-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    final f = await salesReportFixture(path: path);
    var w = f.workspace;
    final item = w.catalogueItems.singleWhere(
      (i) => i.name == 'Corporate Video',
    );
    final category = w.catalogueCategories.singleWhere(
      (c) => c.id == item.categoryId,
    );
    w.saveCatalogueCategory(
      CatalogueCategory(
        id: category.id,
        name: 'Renamed Category',
        revision: category.revision,
      ),
    );
    w.saveCatalogueItem(
      CatalogueItem(
        id: item.id,
        categoryId: category.id,
        name: 'Archived Renamed Video',
        type: item.type,
        incomeAccountId: item.incomeAccountId,
        revision: item.revision,
        active: false,
      ),
    );
    final archive = w.database.exportDataArchive(
      w.identity.businessId,
      DateTime.utc(2026, 10, 1),
    );
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    addTearDown(restored.dispose);
    for (final workspace in [w, restored]) {
      final report = await workspace.reportWithSales(
        from: DateTime(2026),
        through: DateTime(2026, 9, 30),
      );
      final video = report.sales.categories.singleWhere(
        (c) => c.id == category.id,
      );
      expect(video.name, 'Video');
      expect(
        video.items.singleWhere((i) => i.id == item.id).name,
        'Corporate Video',
      );
      expect(video.netMinor, BigInt.from(1650000));
      expect(report.sales.netMinor, BigInt.from(2250000));
    }
    final other = await salesReportFixture();
    addTearDown(other.workspace.dispose);
    final otherReport = await other.workspace.reportWithSales(
      from: DateTime(2026),
      through: DateTime(2026, 9, 30),
    );
    expect(
      otherReport.sales.categories.map((c) => c.id),
      isNot(contains(category.id)),
    );
  });

  test('credits reduce net sales on their own date without turning income accounts into categories', () async {
    final f = await creditPostingFixture(paidMinor: 8000);
    final review = f.w.reviewCreditDraft(f.creditId);
    f.w.postInvoiceCredit(
      requestId: EntityId.random(),
      draftId: f.creditId,
      expectedRevision: review.draft.revision,
      expectedPaidMinor: review.paidMinor,
      expectedPriorCreditMinor: review.priorCreditMinor,
      approvedAt: DateTime.utc(2026, 9, 7),
      customerCreditAccount: f.liability,
    );
    final all = await f.w.reportWithSales(
      from: DateTime(2026, 9, 1),
      through: DateTime(2026, 9, 6),
    );
    final creditsOnly = await f.w.reportWithSales(
      from: DateTime(2026, 9, 6),
      through: DateTime(2026, 9, 6),
    );
    expect(all.sales.netMinor, BigInt.from(5000));
    expect(creditsOnly.sales.netMinor, BigInt.from(-5000));
    expect(all.sales.categories.single.id, isNull);
    expect(all.sales.categories.single.name, 'Unclassified');
    final source =
        creditsOnly.sales.categories.single.items.single.sources.single;
    expect(source.allocation.kind, SalesSourceKind.credit);
    expect(source.allocation.sourceId, f.creditId);
    expect(source.allocation.netMinor, BigInt.from(-5000));
    expect(source.journal.date, DateTime.utc(2026, 9, 6));
  });

  test('sales attribution rejects duplicate lines, inconsistent amounts and a foreign snapshot', () async {
    final f = await salesReportFixture();
    addTearDown(f.workspace.dispose);
    final report = await f.workspace.reportWithSales(
      from: DateTime(2026),
      through: DateTime(2026, 9, 30),
    );
    final allocations = report.sales.categories
        .expand((c) => c.items)
        .expand((i) => i.sources)
        .map((s) => s.allocation)
        .toList();
    expect(
      () => SalesReport.build(
        ledger: report.ledger,
        allocations: [...allocations, allocations.first],
      ),
      throwsStateError,
    );
    final original = allocations.first;
    final wrong = SalesIncomeAllocation(
      journalId: original.journalId,
      sourceId: original.sourceId,
      lineId: original.lineId,
      kind: original.kind,
      netMinor: original.netMinor + BigInt.one,
      catalogue: original.catalogue,
    );
    expect(
      () => SalesReport.build(
        ledger: report.ledger,
        allocations: [wrong, ...allocations.skip(1)],
      ),
      throwsStateError,
    );
    final other = await f.workspace.report(
      from: DateTime(2026, 10, 1),
      through: DateTime(2026, 10, 1),
    );
    expect(
      () => SalesReport.build(ledger: other, allocations: allocations),
      throwsStateError,
    );
  });
}
