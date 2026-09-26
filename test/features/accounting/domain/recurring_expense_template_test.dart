import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';

import '../data/expense_intake_test.dart' show draft;

void main() {
  test('occurrence is a fresh review suggestion with stable identity across revisions', () {
    final original = RecordExpenseDraft.fromJson({
      ...draft().toJson(),
      'tax': 'Confirmed Tax',
      'attachmentName': 'Prior Receipt.pdf',
    });
    final template = RecurringExpenseTemplate(
      id: 'rent',
      revision: 1,
      sourceExpenseId: 'source',
      schedule: RecurrenceRule(
        startsOn: DateTime.utc(2026, 9, 30),
        unit: RecurrenceUnit.months,
        occurrenceCount: 3,
      ),
      defaults: original,
    );
    final occurrence = template.occurrenceAt(1)!;
    expect(occurrence.suggestion.date, '31-10-2026');
    expect(occurrence.suggestion.submissionId, isNull);
    expect(occurrence.suggestion.attachmentName, isNull);
    expect(occurrence.suggestion.tax, 'Unknown / Review Needed');
    expect(occurrence.suggestion.attachments, isEmpty);
    expect(occurrence.suggestion.reviewSnapshots, isEmpty);
    expect(occurrence.suggestion.recurrence, isNull);
    final revised = RecurringExpenseTemplate.fromJson({
      ...template.toJson(),
      'revision': 2,
    });
    expect(revised.occurrenceAt(1)!.identity, occurrence.identity);
    expect(revised.occurrenceAt(1)!.templateRevision, 2);
    expect(template.occurrenceAt(3), isNull);
    expect(
      RecurringExpenseTemplate.fromJson({...template.toJson(), 'paused': true})
          .occurrenceAt(1),
      isNull,
    );
    expect(original.attachmentName, 'Prior Receipt.pdf');
    expect(original.tax, 'Confirmed Tax');
  });
}
