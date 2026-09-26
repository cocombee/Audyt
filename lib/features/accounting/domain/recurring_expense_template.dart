import 'dart:convert';

import '../../../../core/dates/accounting_date.dart';
import 'expense_draft.dart';
import 'recurrence_rule.dart';

/// A versioned source of review suggestions, never a payment or ledger entry.
final class RecurringExpenseTemplate {
  RecurringExpenseTemplate({
    required this.id,
    required this.revision,
    required this.sourceExpenseId,
    required this.schedule,
    required RecordExpenseDraft defaults,
    this.paused = false,
  }) : _defaults = jsonEncode(defaults.toJson()) {
    if (id.trim().isEmpty || sourceExpenseId.trim().isEmpty || revision < 1) {
      throw ArgumentError(
        'Template identity, source and positive revision are required.',
      );
    }
  }

  final String id;
  final int revision;
  final String sourceExpenseId;
  final RecurrenceRule schedule;
  final bool paused;
  final String _defaults;

  String get payee =>
      (jsonDecode(_defaults) as Map<String, dynamic>)['payee'] as String;

  RecurringExpenseTemplate withPaused(bool value) =>
      RecurringExpenseTemplate.fromJson({
        ...toJson(),
        'revision': revision + 1,
        'paused': value,
      });

  RecurringExpenseOccurrence? occurrenceAt(int index) {
    if (paused) return null;
    final date = schedule.occurrenceAt(index);
    if (date == null) return null;
    // Revision is deliberately excluded: editing a template must not generate
    // the same business-date occurrence twice. Persistence enforces uniqueness.
    final identity = jsonEncode([id, date.toIso8601String()]);
    final values = jsonDecode(_defaults) as Map<String, dynamic>;
    values.remove('recurrence');
    if (values['taxMode'] != null) {
      values['taxReviewRequired'] = true;
    } else if (values['lines'] case final List<dynamic> lines) {
      values['lines'] = [
        for (final line in lines)
          {...line as Map<String, dynamic>, 'tax': 'Unknown / Review Needed'},
      ];
    }
    values.addAll({
      'date': formatAccountingInputDate(date),
      'submissionId': null,
      'attachmentName': null,
      'attachments': <Object>[],
      'reviewSnapshots': <Object>[],
      'tax': 'Unknown / Review Needed',
    });
    return RecurringExpenseOccurrence(
      identity: identity,
      templateId: id,
      templateRevision: revision,
      sourceExpenseId: sourceExpenseId,
      occursOn: date,
      suggestion: RecordExpenseDraft.fromJson(values),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'revision': revision,
    'sourceExpenseId': sourceExpenseId,
    'schedule': schedule.toJson(),
    'defaults': jsonDecode(_defaults),
    'paused': paused,
  };

  factory RecurringExpenseTemplate.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported recurring template version.');
    }
    return RecurringExpenseTemplate(
      id: json['id'] as String,
      revision: json['revision'] as int,
      sourceExpenseId: json['sourceExpenseId'] as String,
      schedule: RecurrenceRule.fromJson(
        Map<String, Object?>.from(json['schedule'] as Map),
      ),
      defaults: RecordExpenseDraft.fromJson(
        Map<String, dynamic>.from(json['defaults'] as Map),
      ),
      paused: json['paused'] as bool,
    );
  }
}

final class RecurringExpenseOccurrence {
  const RecurringExpenseOccurrence({
    required this.identity,
    required this.templateId,
    required this.templateRevision,
    required this.sourceExpenseId,
    required this.occursOn,
    required this.suggestion,
    this.savedExpenseId,
  });
  final String identity;
  final String templateId;
  final int templateRevision;
  final String sourceExpenseId;
  final DateTime occursOn;
  final RecordExpenseDraft suggestion;
  final String? savedExpenseId;
}
