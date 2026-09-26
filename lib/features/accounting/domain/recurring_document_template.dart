import 'dart:convert';

import 'recurrence_rule.dart';

enum RecurringDocumentKind { invoice, bill, quotation }

extension RecurringDocumentKindLabel on RecurringDocumentKind {
  String get label => switch (this) {
    RecurringDocumentKind.invoice => 'Invoice',
    RecurringDocumentKind.bill => 'Bill',
    RecurringDocumentKind.quotation => 'Quotation',
  };
}

/// A schedule requested by the transaction editor. Its saved source revision
/// is resolved inside the same database transaction as the draft save.
final class DocumentRecurrenceRequest {
  DocumentRecurrenceRequest({
    required this.id,
    required this.name,
    required this.schedule,
  }) {
    if (id.isEmpty || name.trim().isEmpty || name.length > 200) {
      throw const FormatException(
        'Enter a schedule name of at most 200 characters.',
      );
    }
  }
  final String id, name;
  final RecurrenceRule schedule;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'schedule': schedule.toJson(),
  };
}

final class RecurringDocumentTemplate {
  RecurringDocumentTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.sourceId,
    required this.sourceRevision,
    required this.revision,
    required this.schedule,
    required Map<String, Object?> source,
    this.paused = false,
    this.cancelled = false,
  }) : _source = jsonEncode(source) {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 200 ||
        sourceId.isEmpty ||
        revision < 1 ||
        sourceRevision < 1) {
      throw const FormatException(
        'Schedule identity, name and saved source are required.',
      );
    }
  }
  final String id, name, sourceId;
  final int sourceRevision, revision;
  final RecurringDocumentKind kind;
  final RecurrenceRule schedule;
  final bool paused, cancelled;
  final String _source;
  Map<String, dynamic> get source =>
      jsonDecode(_source) as Map<String, dynamic>;
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'kind': kind.name,
    'sourceId': sourceId,
    'sourceRevision': sourceRevision,
    'revision': revision,
    'schedule': schedule.toJson(),
    'source': source,
    'paused': paused,
    'cancelled': cancelled,
  };
  factory RecurringDocumentTemplate.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported document schedule.');
    }
    return RecurringDocumentTemplate(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: RecurringDocumentKind.values.byName(j['kind'] as String),
      sourceId: j['sourceId'] as String,
      sourceRevision: j['sourceRevision'] as int,
      revision: j['revision'] as int,
      schedule: RecurrenceRule.fromJson(
        Map<String, Object?>.from(j['schedule'] as Map),
      ),
      source: Map<String, Object?>.from(j['source'] as Map),
      paused: j['paused'] as bool,
      cancelled: j['cancelled'] as bool,
    );
  }
}

final class RecurringDocumentOccurrence {
  const RecurringDocumentOccurrence({
    required this.templateId,
    required this.templateRevision,
    required this.index,
    required this.date,
    required this.draftId,
    required this.kind,
  });
  final String templateId, draftId;
  final int templateRevision, index;
  final DateTime date;
  final RecurringDocumentKind kind;
}
