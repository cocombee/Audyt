import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_document_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AccountingWorkspace w;
  setUp(
    () async => w = await createDemoWorkspace(
      asOf: DateTime(2026, 9, 30),
      includeRowReview: true,
    ),
  );
  tearDown(() => w.dispose());
  for (final kind in RecurringDocumentKind.values) {
    test(
      '${kind.name} occurrence creates one unposted evidence-free draft and survives restore',
      () async {
        final id = EntityId.random().value;
        final invoice = w.invoiceDrafts().first;
        final bill = w.database
            .billDraftPage(businessId: w.identity.businessId, limit: 50)
            .records
            .first;
        final quotation = w.quotations().first;
        final before = (await w.journals()).length;
        final schedule = w.saveDocumentSchedule(
          id: id,
          name: 'Explicit monthly example',
          kind: kind,
          sourceId: switch (kind) {
            RecurringDocumentKind.invoice => invoice.invoice.id,
            RecurringDocumentKind.bill => bill.id,
            RecurringDocumentKind.quotation => quotation.quotation.id,
          },
          sourceRevision: switch (kind) {
            RecurringDocumentKind.invoice => invoice.revision,
            RecurringDocumentKind.bill => bill.metadata.revision,
            RecurringDocumentKind.quotation => quotation.revision,
          },
          expectedRevision: 0,
          schedule: RecurrenceRule(
            startsOn: DateTime(2026, 10, 1),
            unit: RecurrenceUnit.months,
            occurrenceCount: 3,
          ),
        );
        final draft = w.database.prepareDocumentOccurrence(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          templateId: id,
          expectedRevision: schedule.revision,
          index: 0,
          preparedAt: DateTime.utc(2026, 10, 1, 12),
        );
        expect(
          w.database.prepareDocumentOccurrence(
            businessId: w.identity.businessId,
            actorId: w.identity.ownerId,
            templateId: id,
            expectedRevision: schedule.revision,
            index: 0,
            preparedAt: DateTime.utc(2026, 10, 1, 12),
          ),
          draft,
        );
        expect((await w.journals()).length, before);
        final records = switch (kind) {
          RecurringDocumentKind.invoice => w.invoiceDrafts().map(
            (r) => r.invoice.id.value,
          ),
          RecurringDocumentKind.quotation => w.quotations().map(
            (r) => r.quotation.id.value,
          ),
          RecurringDocumentKind.bill =>
            w.database
                .billDraftPage(businessId: w.identity.businessId, limit: 50)
                .records
                .map((r) => r.id.value),
        };
        expect(records.where((r) => r == draft), hasLength(1));
        if (kind == RecurringDocumentKind.invoice) {
          final value = w
              .invoiceDrafts()
              .singleWhere((r) => r.invoice.id.value == draft)
              .invoice;
          expect(value.attachments, isEmpty);
          expect(value.issueDate, DateTime.utc(2026, 10, 1));
          expect(value.documentNumber, isNot(invoice.invoice.documentNumber));
          expect(value.total, invoice.invoice.total);
        } else if (kind == RecurringDocumentKind.quotation) {
          final value = w
              .quotations()
              .singleWhere((r) => r.quotation.id.value == draft)
              .quotation;
          expect(value.attachments, isEmpty);
          expect(value.issueDate, DateTime.utc(2026, 10, 1));
          expect(
            value.documentNumber,
            isNot(quotation.quotation.documentNumber),
          );
          expect(value.total, quotation.quotation.total);
          expect(
            value.validUntil.difference(value.issueDate),
            quotation.quotation.validUntil.difference(
              quotation.quotation.issueDate,
            ),
          );
        } else {
          final value = w.database
              .billDraftPage(businessId: w.identity.businessId, limit: 50)
              .records
              .singleWhere((r) => r.id.value == draft);
          expect(value.attachments, isEmpty);
          expect(value.bill.issueDate, DateTime.utc(2026, 10, 1));
          expect(value.documentNumber, isNot(bill.documentNumber));
          expect(value.total, bill.total);
        }
        final archive = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.now(),
        );
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(archive);
        expect(
          restored
              .documentOccurrences(w.identity.businessId, id)
              .single
              .draftId,
          draft,
        );
        expect(
          restored.prepareDocumentOccurrence(
            businessId: w.identity.businessId,
            actorId: w.identity.ownerId,
            templateId: id,
            expectedRevision: schedule.revision,
            index: 0,
            preparedAt: DateTime.utc(2026, 10, 1, 12),
          ),
          draft,
        );
      },
    );
  }
  test(
    'pause, cancel, stale revision and not-due checks never create drafts',
    () {
      final source = w.invoiceDrafts().first;
      final schedule = w.saveDocumentSchedule(
        id: EntityId.random().value,
        name: 'Example',
        kind: RecurringDocumentKind.invoice,
        sourceId: source.invoice.id,
        sourceRevision: source.revision,
        expectedRevision: 0,
        schedule: RecurrenceRule(
          startsOn: DateTime(2026, 10, 1),
          unit: RecurrenceUnit.months,
        ),
      );
      expect(
        () => w.database.prepareDocumentOccurrence(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          templateId: schedule.id,
          expectedRevision: 1,
          index: 1,
          preparedAt: DateTime.utc(2026, 10, 1),
        ),
        throwsStateError,
      );
      w.changeDocumentScheduleState(schedule, paused: true);
      expect(() => w.prepareDocumentOccurrence(schedule, 0), throwsStateError);
      final paused = w.database
          .documentSchedules(w.identity.businessId)
          .singleWhere((s) => s.id == schedule.id);
      w.changeDocumentScheduleState(paused, cancel: true);
      final cancelled = w.database
          .documentSchedules(w.identity.businessId)
          .singleWhere((s) => s.id == schedule.id);
      expect(
        () => w.changeDocumentScheduleState(cancelled, paused: false),
        throwsStateError,
      );
      expect(
        w.database.documentOccurrences(w.identity.businessId, schedule.id),
        isEmpty,
      );
    },
  );
  test(
    'foreign actor/source and stale source revisions are rejected atomically',
    () {
      final source = w.invoiceDrafts().first;
      void save(EntityId actor, EntityId sourceId, int rev) =>
          w.database.saveDocumentSchedule(
            businessId: w.identity.businessId,
            actorId: actor,
            id: EntityId.random().value,
            name: 'Example',
            kind: RecurringDocumentKind.invoice,
            sourceId: sourceId,
            sourceRevision: rev,
            expectedRevision: 0,
            schedule: RecurrenceRule(
              startsOn: DateTime(2026, 10, 1),
              unit: RecurrenceUnit.months,
            ),
            savedAt: DateTime.now(),
          );
      expect(
        () => save(EntityId.random(), source.invoice.id, source.revision),
        throwsStateError,
      );
      expect(
        () => save(w.identity.ownerId, EntityId.random(), 1),
        throwsStateError,
      );
      expect(
        () => save(w.identity.ownerId, source.invoice.id, source.revision + 1),
        throwsStateError,
      );
      expect(w.database.documentSchedules(w.identity.businessId), hasLength(6));
    },
  );
}
