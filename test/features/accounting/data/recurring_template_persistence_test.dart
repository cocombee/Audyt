import 'package:sqlite3/sqlite3.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  test('template restart, exact retry and stale revision protection', () async {
    final dir = Directory.systemTemp.createTempSync('recurring-storage-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final source = await workspace.saveExpenseIntake(draft());
    final template = RecurringExpenseTemplate(
      id: 'template',
      revision: 1,
      sourceExpenseId: source.value,
      schedule: RecurrenceRule(
        startsOn: DateTime.utc(2026, 9, 30),
        unit: RecurrenceUnit.months,
      ),
      defaults: draft(),
    );
    workspace.database.saveRecurringExpenseTemplate(
      workspace.identity.businessId,
      template,
    );
    workspace.database.saveRecurringExpenseTemplate(
      workspace.identity.businessId,
      template,
    );
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(
      workspace.database
          .recurringExpenseTemplates(workspace.identity.businessId)
          .single
          .toJson(),
      template.toJson(),
    );
    final paused = RecurringExpenseTemplate.fromJson({
      ...template.toJson(),
      'revision': 2,
      'paused': true,
    });
    workspace.database.saveRecurringExpenseTemplate(
      workspace.identity.businessId,
      paused,
    );
    final history = workspace.database.recurringExpenseTemplateHistory(
      workspace.identity.businessId,
      template.id,
    );
    expect(history.map((item) => item.revision), [1, 2]);
    expect(history.first.paused, isFalse);
    expect(history.last.paused, isTrue);
    final raw = sqlite3.open(path);
    addTearDown(raw.dispose);
    expect(
      () => raw.execute('DELETE FROM recurring_expense_template_history'),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => raw.execute(
        "UPDATE recurring_expense_template_history SET payload = '{}'",
      ),
      throwsA(isA<SqliteException>()),
    );
    raw.execute(
      "CREATE TRIGGER fail_template_history BEFORE INSERT ON recurring_expense_template_history BEGIN SELECT RAISE(ABORT, 'Storage failure'); END",
    );
    final resumed = RecurringExpenseTemplate.fromJson({
      ...paused.toJson(),
      'revision': 3,
      'paused': false,
    });
    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        workspace.identity.businessId,
        resumed,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      workspace.database
          .recurringExpenseTemplates(workspace.identity.businessId)
          .single
          .revision,
      2,
    );
    expect(
      workspace.database
          .recurringExpenseTemplateHistory(
            workspace.identity.businessId,
            template.id,
          )
          .length,
      2,
    );

    expect(
      () => workspace.database.saveRecurringExpenseTemplate(
        workspace.identity.businessId,
        template,
      ),
      throwsStateError,
    );
    expect(
      workspace.database
          .recurringExpenseTemplates(workspace.identity.businessId)
          .single
          .paused,
      isTrue,
    );
  });
}
