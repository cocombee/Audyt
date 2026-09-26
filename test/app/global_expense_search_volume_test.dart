import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_global_search.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final count = int.parse(
    Platform.environment['AUDYT_EXPENSE_SEARCH_ROWS'] ?? '1000',
  );
  test('global expense search bounds a source-rich company and keeps matches', () async {
    final root = Directory.systemTemp.createTempSync('audyt-expense-search-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/books.sqlite';
    var workspace = await createDemoWorkspace(databasePath: path);
    final businessId = workspace.identity.businessId;
    final baseQuality = workspace.database.readReportQualityCounts(
      businessId: businessId,
      from: DateTime.utc(2000),
      through: DateTime.utc(2100),
    );
    final baseDayQuality = workspace.database.readReportQualityCounts(
      businessId: businessId,
      from: DateTime.utc(2026, 9, 29),
      through: DateTime.utc(2026, 9, 29),
    );
    final baseExpenses = await workspace.expenses();
    var fullReceiptCount = 0;
    for (final summary in baseExpenses) {
      if ((await workspace.expense(summary.id))!.draft.attachments.isNotEmpty) {
        fullReceiptCount++;
      }
    }
    expect(baseQuality.expensesInRange, baseExpenses.length);
    expect(baseQuality.expensesWithReceipts, fullReceiptCount);
    workspace.dispose();

    final raw = sqlite3.open(path);
    final insert = raw.prepare(
      'INSERT INTO expense_intakes('
      'id,business_id,request_id,created_at,occurred_on,amount_minor,currency,'
      'payee,category,payload,journal_id) VALUES(?,?,?,?,?,?,?,?,?,?,NULL)',
    );
    try {
      raw.execute('BEGIN');
      for (var index = 0; index < count; index++) {
        final id =
            '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
        final payee = index == count - 1
            ? 'Needle_% Supplier'
            : index == count - 2
            ? 'Étoile Supplier'
            : 'Volume Supplier';
        insert.execute([
          id,
          businessId.value,
          id,
          index == 0 ? '2030-01-01T00:00:00.000Z' : '2026-09-29T00:00:00.000Z',
          index == 0 ? '2020-01-01T00:00:00.000Z' : '2026-09-29T00:00:00.000Z',
          2500,
          'MYR',
          payee,
          'Search Category',
          jsonEncode(
            RecordExpenseDraft(
              amount: '25.00',
              date: '29-09-2026',
              payee: payee,
              paymentAccount: 'Demo Bank',
              paymentAccountId: 'demo-bank',
              category: 'Search Category',
              tax: 'Out Of Scope',
              customer: '',
              billable: false,
              dimensions: '',
              itemOrSplitDetails: '',
              notes: '',
              submissionId: id,
            ).toJson(),
          ),
        ]);
      }
      raw.execute('COMMIT');
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.dispose();
      raw.dispose();
    }

    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    final qualityRead = Stopwatch()..start();
    final quality = workspace.database.readReportQualityCounts(
      businessId: businessId,
      from: DateTime.utc(2000),
      through: DateTime.utc(2100),
    );
    qualityRead.stop();
    expect(quality.expensesInRange, baseQuality.expensesInRange + count);
    expect(quality.expensesWithReceipts, baseQuality.expensesWithReceipts);
    expect(quality.pendingExpenses, baseQuality.pendingExpenses + count);
    expect(quality.journalsInRange, baseQuality.journalsInRange);
    expect(quality.postedJournalsInRange, baseQuality.postedJournalsInRange);
    expect(quality.pendingJournals, baseQuality.pendingJournals);
    final dayQuality = workspace.database.readReportQualityCounts(
      businessId: businessId,
      from: DateTime.utc(2026, 9, 29),
      through: DateTime.utc(2026, 9, 29),
    );
    expect(
      dayQuality.expensesInRange,
      baseDayQuality.expensesInRange + count - 1,
    );
    expect(
      dayQuality.expensesWithReceipts,
      baseDayQuality.expensesWithReceipts,
    );
    final foreignQuality = workspace.database.readReportQualityCounts(
      businessId: EntityId.random(),
      from: DateTime.utc(2000),
      through: DateTime.utc(2100),
    );
    expect(foreignQuality.expensesInRange, 0);
    expect(foreignQuality.expensesWithReceipts, 0);
    expect(foreignQuality.pendingExpenses, 0);
    expect(foreignQuality.journalsInRange, 0);
    final pageRead = Stopwatch()..start();
    final page = workspace.database.readExpenseIntakePage(
      businessId: businessId,
    );
    final options = workspace.database.expenseIntakeFilterOptions(businessId);
    pageRead.stop();
    expect(page.records, hasLength(10));
    expect(page.total, greaterThanOrEqualTo(count));
    expect(options.payees, contains('Needle_% Supplier'));
    final pendingRead = Stopwatch()..start();
    final pending = workspace.database.readPendingExpenseIntakes(
      businessId: businessId,
    );
    pendingRead.stop();
    expect(pending.count, greaterThanOrEqualTo(count));
    expect(pending.recent, hasLength(50));
    expect(
      pending.recent.first.id.value,
      '00000000-0000-4000-8000-000000000000',
    );
    expect(
      workspace.database
          .readPendingExpenseIntakes(businessId: EntityId.random())
          .count,
      0,
    );
    expect(
      workspace.database
          .readRecentPostedExpenseIntakes(
            businessId: businessId,
            through: DateTime.utc(2100),
          )
          .length,
      lessThanOrEqualTo(6),
    );
    expect(
      workspace.database
          .readExpenseIntakePage(
            businessId: businessId,
            payee: 'Needle_% Supplier',
          )
          .records
          .single
          .payee,
      'Needle_% Supplier',
    );
    expect(
      workspace.database
          .readExpenseIntakePage(businessId: EntityId.random())
          .total,
      0,
    );
    expect(
      workspace.database
          .readExpenseIntakePage(
            businessId: businessId,
            posted: false,
            limit: 10,
            offset: count + 100,
          )
          .records,
      isNotEmpty,
    );
    final newSearch = Stopwatch()..start();
    final needle = searchExpenseResults(
      workspace: workspace,
      query: 'needle_% MYR:2500',
    );
    newSearch.stop();
    expect(needle, hasLength(1));
    expect(needle.single.title, 'Needle_% Supplier');
    expect(needle.single.type, 'Expense');
    expect(needle.single.tab, 'Expenses');
    expect(
      workspace.database.searchExpenseIntakes(
        businessId: EntityId.random(),
        query: 'needle_%',
      ),
      isEmpty,
    );
    expect(
      searchExpenseResults(workspace: workspace, query: 'Volume', limit: 12),
      hasLength(12),
    );
    expect(
      searchExpenseResults(workspace: workspace, query: 'étoile'),
      hasLength(1),
    );
    expect(
      () => workspace.database.searchExpenseIntakes(
        businessId: businessId,
        query: 'Volume',
        limit: 51,
      ),
      throwsArgumentError,
    );

    final cached = await loadNonJournalSearchResults(
      claims: workspace.claims,
      vouchers: workspace.vouchers,
      workspace: workspace,
      includeExpenses: false,
    );
    expect(cached.where((item) => item.type == 'Expense'), isEmpty);
    final oldSearch = Stopwatch()..start();
    final oldResults = await loadNonJournalSearchResults(
      claims: workspace.claims,
      vouchers: workspace.vouchers,
      workspace: workspace,
    );
    oldSearch.stop();
    expect(
      oldResults.where(
        (item) => item.type == 'Expense' && item.matches('needle_% MYR:2500'),
      ),
      hasLength(1),
    );
    expect(
      oldResults.where((item) => item.type == 'Expense').length,
      greaterThanOrEqualTo(count),
    );
    debugPrint(
      'Expense search $count rows: page=${pageRead.elapsedMilliseconds}ms, '
      'reportQuality=${qualityRead.elapsedMilliseconds}ms, '
      'pending=${pendingRead.elapsedMilliseconds}ms, '
      'bounded=${newSearch.elapsedMilliseconds}ms, '
      'full=${oldSearch.elapsedMilliseconds}ms, database=${File(path).lengthSync()} bytes',
    );
    final damaged = sqlite3.open(path);
    try {
      damaged.execute('UPDATE expense_intakes SET payload=? WHERE id=?', [
        jsonEncode({'attachments': <String, Object?>{}}),
        '00000000-0000-4000-8000-000000000000',
      ]);
    } finally {
      damaged.dispose();
    }
    expect(
      () => workspace.database.readReportQualityCounts(
        businessId: businessId,
        from: DateTime.utc(2000),
        through: DateTime.utc(2100),
      ),
      throwsStateError,
    );
  });
}
