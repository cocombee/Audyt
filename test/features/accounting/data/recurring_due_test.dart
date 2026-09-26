import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  test(
    'due catch-up respects date, pause, end and batches across restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('recurring-due-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.saveExpenseIntake(
        draft(
          recurrence: RecurrenceRule(
            startsOn: DateTime.utc(2026, 9, 13),
            unit: RecurrenceUnit.days,
            occurrenceCount: 6,
          ),
        ),
      );
      final business = workspace.identity.businessId;
      var template = workspace.database
          .recurringExpenseTemplates(business)
          .single;
      // Preparing a future date manually must not skip earlier missing dates.
      workspace.database.prepareRecurringExpenseOccurrence(
        business,
        template.id,
        expectedRevision: 1,
        index: 5,
      );
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2026, 9, 13),
        ),
        (prepared: 0, hasMore: false),
      );
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2026, 9, 16),
          limit: 2,
        ),
        (prepared: 2, hasMore: true),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2026, 9, 16),
          limit: 2,
        ),
        (prepared: 1, hasMore: false),
      );
      template = template.withPaused(true);
      workspace.database.saveRecurringExpenseTemplate(business, template);
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2027),
        ),
        (prepared: 0, hasMore: false),
      );
      template = template.withPaused(false);
      workspace.database.saveRecurringExpenseTemplate(business, template);
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2027),
        ),
        (prepared: 1, hasMore: false),
      );
      final suggestions = workspace.database.recurringExpenseSuggestions(
        business,
      );
      expect(suggestions, hasLength(5));
      expect(suggestions.map((s) => s.occursOn.day), [14, 15, 16, 17, 18]);
      expect(await workspace.expenses(), hasLength(1));
      expect(await workspace.journals(), isEmpty);
      expect(
        await workspace.database.prepareDueRecurringExpenses(
          business,
          through: DateTime.utc(2027),
        ),
        (prepared: 0, hasMore: false),
      );
      workspace.dispose();
    },
  );
}
