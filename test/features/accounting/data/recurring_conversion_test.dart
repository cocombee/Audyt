import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  test(
    'conversion is atomic, immutable and idempotent across restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('recurring-conversion-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.saveExpenseIntake(
        draft(
          recurrence: RecurrenceRule(
            startsOn: DateTime.utc(2026, 9, 13),
            unit: RecurrenceUnit.months,
          ),
        ),
      );
      final business = workspace.identity.businessId;
      final template = workspace.database
          .recurringExpenseTemplates(business)
          .single;
      final suggestion = workspace.database.prepareRecurringExpenseOccurrence(
        business,
        template.id,
        expectedRevision: 1,
        index: 1,
      );
      final identity = template.occurrenceAt(1)!.identity;
      RecordExpenseDraft reviewed(String request) =>
          RecordExpenseDraft.fromJson({
            ...suggestion.toJson(),
            'submissionId': request,
            'amount': '28.00',
          });
      final raw = sqlite3.open(path);
      raw.execute(
        "CREATE TRIGGER fail_conversion BEFORE INSERT ON recurring_expense_conversions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        workspace.saveExpenseIntake(
          reviewed('conversion'),
          recurringOccurrenceIdentity: identity,
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(await workspace.expenses(), hasLength(1));
      raw.execute('DROP TRIGGER fail_conversion');
      final saved = await workspace.saveExpenseIntake(
        reviewed('conversion'),
        recurringOccurrenceIdentity: identity,
      );
      expect(await workspace.expenses(), hasLength(2));
      expect(
        () => raw.execute('DELETE FROM recurring_expense_conversions'),
        throwsA(isA<SqliteException>()),
      );
      raw.dispose();
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        await workspace.saveExpenseIntake(
          reviewed('conversion'),
          recurringOccurrenceIdentity: identity,
        ),
        saved,
      );
      await expectLater(
        workspace.saveExpenseIntake(
          reviewed('different-request'),
          recurringOccurrenceIdentity: identity,
        ),
        throwsStateError,
      );
      await expectLater(
        workspace.saveExpenseIntake(reviewed('conversion')),
        throwsStateError,
      );
      await expectLater(
        workspace.saveExpenseIntake(
          reviewed('missing'),
          recurringOccurrenceIdentity: 'not-prepared',
        ),
        throwsStateError,
      );
      expect(await workspace.expenses(), hasLength(2));
      workspace.dispose();
    },
  );
}
