import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_reconciliation_test.dart' show Fixture;
import 'account_reconciliation_persistence_test.dart' show approve, save;
import 'archive_upgrade_test.dart' show body;
import 'journal_editability_test.dart' show importPayment, reopen;

void main() {
  for (final imported in [false, true]) {
    for (final card in [false, true]) {
      test(
        '${imported ? 'imported' : 'account'} ${card ? 'card' : 'bank'} root cleared opening locks at actual commit, restores and reopens',
        () async {
          final f = Fixture();
          await f.open(liability: card);
          final opening = await f.post(8, 30, card ? -10000 : 10000);
          final outstanding = await f.post(8, 31, card ? 500 : -500);
          final payment = await f.post(9, 2, card ? 1000 : -1000);
          final source = (await f.w.database.getById(opening))!;
          final correction = EntityId.random();
          await f.w.database.save(
            StoredJournalEntry(
              entry: source.entry.reversal(
                id: correction,
                date: DateTime.utc(2026, 10, 2),
                memo: 'Fictional opening correction',
              ),
              metadata: RecordMetadata.initial(
                recordId: correction,
                businessId: f.business,
                originDeviceId: f.w.identity.deviceId,
                createdAt: DateTime.now(),
              ),
            ),
          );
          f.w.database.requireJournalUnreconciled(f.business, opening);
          final outstandingIds = {'${outstanding.value}:0'};
          final EntityId completion;
          if (imported) {
            final statement = importPayment(f);
            f.w.database.acceptStatementMatch(
              businessId: f.business,
              statementId: statement,
              sourceRow: 2,
              journalId: payment,
              lineIndex: 0,
              actorId: f.w.identity.ownerId,
              acceptedAt: DateTime.now(),
            );
            completion = EntityId.random();
            f.w.database.approveStatementReconciliation(
              requestId: completion,
              businessId: f.business,
              statementId: statement,
              actorId: f.w.identity.ownerId,
              approvedAt: DateTime.now(),
              startsOn: DateTime.utc(2026, 9, 1),
              endsOn: DateTime.utc(2026, 9, 30),
              openingBalance: Money.fromMinor(10000, 'MYR'),
              closingBalance: Money.fromMinor(9000, 'MYR'),
              expectedAcceptanceIds: {
                2: f.w.database.statementMatchAcceptanceId(
                  f.business,
                  statement,
                  2,
                )!,
              },
              expectedPreviousId: null,
              firstOpeningEvidence: 'Fictional opening verified',
              openingOutstandingIds: outstandingIds,
            );
          } else {
            final review = f.review(
              selected: {'${payment.value}:0'},
              outstanding: outstandingIds,
            );
            final draft = save(f, review);
            completion = approve(f, review, revision: draft.revision);
          }
          final classification = f.w.database.reconciliationClassification(
            f.business,
            completion.value,
          )!;
          expect(classification.agrees, isTrue);
          expect(
            classification.cleared.any((m) => m.id == '${opening.value}:0'),
            isTrue,
          );
          expect(
            f.w.database.journalReconciliationId(f.business, opening),
            completion,
          );
          f.w.database.requireJournalUnreconciled(f.business, outstanding);
          final command = JournalApproval(
            requestId: EntityId.random(),
            businessId: f.business,
            journalId: correction,
            expectedRevision: 1,
            actorId: f.w.identity.ownerId,
            approvedAt: DateTime.now(),
          );
          final before = f.w.database.exportDataArchive(
            f.business,
            DateTime.utc(2027),
          );
          await expectLater(
            f.w.database.approve(command),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'fresh reconciled opening guard',
                contains('Reopen its reconciliation'),
              ),
            ),
          );
          expect(
            f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
            before,
          );
          f.w.dispose();
          f.w = await AccountingWorkspace.open(f.path);
          expect(
            f.w.database.journalReconciliationId(f.business, opening),
            completion,
          );
          f.w.database.requireJournalUnreconciled(f.business, outstanding);
          final restored = LocalAccountingDatabase.inMemory();
          addTearDown(restored.close);
          restored.restoreDataArchive(before);
          expect(
            restored.journalReconciliationId(f.business, opening),
            completion,
          );
          restored.requireJournalUnreconciled(f.business, outstanding);
          restored.reopenStatementReconciliation(
            businessId: f.business,
            completionId: completion.value,
            actorId: f.w.identity.ownerId,
            reopenedAt: DateTime.now(),
            reason: 'Fictional correction',
          );
          restored.requireJournalUnreconciled(f.business, opening);
          reopen(f, completion);
          f.w.database.requireJournalUnreconciled(f.business, opening);
          expect(
            (await f.w.database.approve(command)).entry.state,
            JournalEntryState.posted,
          );
          final after = body(
            f.w.database.exportDataArchive(f.business, DateTime.utc(2027)),
          );
          expect(
            after['tables']['bank_reconciliations'],
            body(before)['tables']['bank_reconciliations'],
          );
          final retained = (await f.w.database.getById(opening))!;
          expect(retained.entry.id, source.entry.id);
          expect(retained.entry.date, source.entry.date);
          expect(retained.entry.memo, source.entry.memo);
          expect(retained.metadata.revision, source.metadata.revision);
          expect(
            retained.entry.lines.map(
              (line) => (line.accountId, line.kind, line.amount),
            ),
            source.entry.lines.map(
              (line) => (line.accountId, line.kind, line.amount),
            ),
          );
          expect(retained.entry.state, JournalEntryState.posted);
        },
      );
    }
  }
}
