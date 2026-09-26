import '../../../support/historical_sqlite_fixture.dart';

import '../../../support/historical_expense_schema.dart';

import 'dart:io';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_document_template.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final kind in RecurringDocumentKind.values) {
    test(
      '${kind.name}: draft and schedule commit together; retry and failed schedule are atomic',
      () async {
        final w = await createDemoWorkspace(includeRowReview: true);
        addTearDown(w.dispose);
        final before = w.database
            .documentSchedules(w.identity.businessId)
            .length;
        final journalCount = (await w.journals()).length;
        final at = DateTime.utc(2026, 10, 2);
        final id = EntityId.random();
        final number = w.database.allocateDocumentNumber(
          businessId: w.identity.businessId,
          actorId: w.identity.ownerId,
          recordId: id,
          documentType: kind.name,
          allocatedAt: at,
        );
        final invoiceSource = w.invoiceDrafts().first.invoice;
        final quoteSource = w.quotations().first.quotation;
        final billSource = w.database
            .billDraftPage(businessId: w.identity.businessId, limit: 50)
            .records
            .first;
        final invoice = Invoice.draft(
          id: id,
          customerId: invoiceSource.customerId,
          documentNumber: number,
          issueDate: at,
          terms: invoiceSource.terms,
          lines: invoiceSource.lines,
          taxMode: invoiceSource.taxMode,
        );
        final quotation = Estimate.draft(
          id: id,
          customerId: quoteSource.customerId,
          documentNumber: number,
          issueDate: at,
          validUntil: DateTime.utc(2026, 11, 2),
          terms: quoteSource.terms,
          lines: quoteSource.lines,
          taxMode: quoteSource.taxMode,
        );
        final bill = PurchaseBillDraft(
          metadata: RecordMetadata.initial(
            recordId: id,
            businessId: w.identity.businessId,
            originDeviceId: w.identity.deviceId,
            createdAt: at,
          ),
          vendorSnapshot: billSource.vendorSnapshot,
          documentNumber: number,
          issueDate: at,
          dueDate: billSource.bill.terms.dueDateFor(at),
          terms: billSource.bill.terms,
          lines: billSource.lines,
          taxMode: billSource.taxMode,
        );
        void save(DocumentRecurrenceRequest request, {EntityId? actor}) {
          final database = w.database;
          switch (kind) {
            case RecurringDocumentKind.invoice:
              database.saveInvoiceDraft(
                businessId: w.identity.businessId,
                actorId: actor ?? w.identity.ownerId,
                invoice: invoice,
                expectedRevision: 0,
                savedAt: at,
                recurrence: request,
              );
            case RecurringDocumentKind.quotation:
              database.saveQuotationDraft(
                businessId: w.identity.businessId,
                actorId: actor ?? w.identity.ownerId,
                quotation: quotation,
                expectedRevision: 0,
                savedAt: at,
                recurrence: request,
              );
            case RecurringDocumentKind.bill:
              database.saveBillDraft(
                businessId: w.identity.businessId,
                actorId: actor ?? w.identity.ownerId,
                bill: bill,
                expectedRevision: 0,
                recurrence: request,
              );
          }
        }

        bool sourceExists() => switch (kind) {
          RecurringDocumentKind.invoice => w.invoiceDrafts().any(
            (r) => r.invoice.id == id,
          ),
          RecurringDocumentKind.quotation => w.quotations().any(
            (r) => r.quotation.id == id,
          ),
          RecurringDocumentKind.bill =>
            w.database
                .billDraftPage(businessId: w.identity.businessId, limit: 50)
                .records
                .any((r) => r.id == id),
        };
        final rule = RecurrenceRule(
          startsOn: at,
          unit: RecurrenceUnit.months,
          occurrenceCount: 3,
        );
        // The schedule owner rejects an invalid identity after draft validation.
        // Neither the draft, its history, nor its pending output may survive.
        expect(
          () => save(
            DocumentRecurrenceRequest(
              id: 'invalid identity',
              name: number,
              schedule: rule,
            ),
          ),
          throwsFormatException,
        );
        expect(sourceExists(), false);
        expect(
          w.database.documentSchedules(w.identity.businessId),
          hasLength(before),
        );
        final request = DocumentRecurrenceRequest(
          id: EntityId.random().value,
          name: number,
          schedule: rule,
        );
        expect(() => save(request, actor: EntityId.random()), throwsStateError);
        expect(sourceExists(), false);
        save(request);
        save(request);
        expect(sourceExists(), true);
        expect(
          w.database.documentSchedules(w.identity.businessId),
          hasLength(before + 1),
        );
        final saved = w.database
            .documentSchedules(w.identity.businessId)
            .singleWhere((s) => s.id == request.id);
        expect(saved.kind, kind);
        expect(saved.sourceId, id.value);
        expect(saved.sourceRevision, 1);
        expect(saved.schedule.occurrenceAt(2), DateTime.utc(2026, 12, 2));
        expect((await w.journals()).length, journalCount);
        final restored = LocalAccountingDatabase.inMemory();
        addTearDown(restored.close);
        restored.restoreDataArchive(
          w.database.exportDataArchive(w.identity.businessId, at),
        );
        expect(
          restored
              .documentSchedules(w.identity.businessId)
              .singleWhere((s) => s.id == request.id)
              .toJson(),
          saved.toJson(),
        );
      },
    );
  }

  test(
    'schema 47 upgrade preserves occurrence identity and immutable history',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-recurrence-upgrade-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/books.sqlite';
      final w = await createDemoWorkspace(
        databasePath: path,
        includeRowReview: true,
      );
      final identity = w.identity;
      final schedule = w.database
          .documentSchedules(identity.businessId)
          .firstWhere(
            (s) => s.kind == RecurringDocumentKind.invoice && !s.paused,
          );
      final preparedAt = schedule.schedule.occurrenceAt(0)!;
      final draft = w.database.prepareDocumentOccurrence(
        businessId: identity.businessId,
        actorId: identity.ownerId,
        templateId: schedule.id,
        expectedRevision: schedule.revision,
        index: 0,
        preparedAt: preparedAt,
      );
      w.dispose();
      final raw = sqlite3.open(path);
      dropCurrentQuotationFixtureOwner(raw);
      removeExpenseRemovalSchema(raw);
      raw.execute('DROP TRIGGER recurring_document_occurrences_no_update');
      raw.execute('DROP TRIGGER recurring_document_occurrences_no_delete');
      raw.execute(
        'ALTER TABLE recurring_document_occurrences RENAME TO occurrences_fixture',
      );
      raw.execute(
        "CREATE TABLE recurring_document_occurrences(business_id TEXT NOT NULL,template_id TEXT NOT NULL,template_revision INTEGER NOT NULL,occurs_on TEXT NOT NULL,occurrence_index INTEGER NOT NULL CHECK(occurrence_index>=0),draft_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('invoice','bill')),PRIMARY KEY(business_id,template_id,occurs_on),UNIQUE(business_id,kind,draft_id),FOREIGN KEY(business_id,template_id,template_revision) REFERENCES recurring_document_template_history(business_id,id,revision))",
      );
      raw.execute(
        'INSERT INTO recurring_document_occurrences SELECT * FROM occurrences_fixture',
      );
      raw.execute('DROP TABLE occurrences_fixture');
      raw.execute('DROP TABLE IF EXISTS tax_remittance_corrections');
      raw.execute('DROP TABLE IF EXISTS tax_remittances');
      raw.execute('DROP TABLE IF EXISTS company_tax_agency_history');
      raw.execute('DROP TABLE IF EXISTS company_tax_agencies');
      raw.execute('DROP TABLE IF EXISTS bank_reconciliation_drafts');
      raw.execute('DROP VIEW IF EXISTS current_expense_intakes');
      raw.execute('DROP VIEW IF EXISTS financial_expense_intakes');
      raw.execute('DROP TABLE IF EXISTS expense_revision_postings');
      raw.execute('DROP TABLE IF EXISTS expense_revision_drafts');
      raw.execute('PRAGMA user_version = 47');
      raw.dispose();
      final migrated = LocalAccountingDatabase.open(path);
      expect(
        migrated
            .documentOccurrences(identity.businessId, schedule.id)
            .single
            .draftId,
        draft,
      );
      expect(
        migrated.prepareDocumentOccurrence(
          businessId: identity.businessId,
          actorId: identity.ownerId,
          templateId: schedule.id,
          expectedRevision: schedule.revision,
          index: 0,
          preparedAt: preparedAt,
        ),
        draft,
      );
      migrated.close();
      final verified = sqlite3.open(path);
      addTearDown(verified.dispose);
      expect(
        verified.select('PRAGMA user_version').single.values.single,
        LocalAccountingDatabase.schemaVersion,
      );
      expect(verified.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        () => verified.execute('DELETE FROM recurring_document_occurrences'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => verified.execute(
          'UPDATE recurring_document_occurrences SET occurrence_index=4',
        ),
        throwsA(isA<SqliteException>()),
      );
    },
  );
}
