import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';

import 'journal_approval_test.dart' show id, draft, approval;
import 'ledger_fixture.dart';

void main() {
  test(
    'audit pages retain identity across new events and isolate filters',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await seedLedger(db, draft());
      await db.save(draft());
      await db.approve(approval());
      final first = await db.auditEventPage(id(4), limit: 1);
      final anchor = first.single['sequence'] as int;
      await db.closeThrough(
        businessId: id(4),
        date: DateTime.utc(2026, 9, 13),
        actorId: id(5),
        changedAt: DateTime.utc(2026, 9, 14),
        reason: 'Reviewed',
      );
      final newest = await db.auditEventPage(id(4), limit: 1);
      expect(newest.single['kind'], 'period_closed');
      final older = await db.auditEventPage(
        id(4),
        beforeSequence: newest.single['sequence'] as int,
      );
      expect(older.single['sequence'], anchor);
      expect(
        (await db.auditEventPage(
          id(4),
          throughSequence: anchor,
        )).single['sequence'],
        anchor,
      );
      expect(await db.auditEventPage(id(99)), isEmpty);
      expect(await db.auditEventPage(id(4), actorId: id(99)), isEmpty);
      expect(
        (await db.auditEventPage(id(4), subjectId: id(1))).single['kind'],
        'journal_posted',
      );
      expect(await db.auditEventPage(id(4), kind: "' OR 1=1 --"), isEmpty);
      expect(await db.auditEventCount(id(4)), 2);
      expect(await db.auditEventCount(id(4), throughSequence: anchor), 1);
      expect(await db.auditEventCount(id(99)), 0);
      expect(await db.auditEventCount(id(4), actorId: id(99)), 0);
      expect(await db.auditEventCount(id(4), kind: 'period_closed'), 1);
      expect(await db.auditEventCount(id(4), kind: "' OR 1=1 --"), 0);
      expect(db.auditEventKinds(id(4)), ['journal_posted', 'period_closed']);
      expect(db.auditEventKinds(id(99)), isEmpty);

      final eventTime = DateTime.parse(first.single['occurred_at'] as String);
      expect(
        await db.auditEventPage(
          id(4),
          occurredFrom: eventTime,
          occurredBefore: eventTime.add(const Duration(microseconds: 1)),
        ),
        hasLength(1),
      );
      expect(
        await db.auditEventPage(
          id(4),
          occurredFrom: eventTime.subtract(const Duration(microseconds: 1)),
          occurredBefore: eventTime,
        ),
        isEmpty,
      );
      expect(
        await db.auditEventPage(
          id(4),
          occurredFrom: eventTime.add(const Duration(microseconds: 1)),
          occurredBefore: DateTime.utc(2026, 9, 14),
        ),
        isEmpty,
      );
      await expectLater(
        db.auditEventPage(
          id(4),
          occurredFrom: eventTime,
          occurredBefore: eventTime,
        ),
        throwsArgumentError,
      );
      expect(() => first.clear(), throwsUnsupportedError);
      expect(() => first.single.clear(), throwsUnsupportedError);
      await expectLater(
        db.auditEventPage(id(4), limit: 201),
        throwsArgumentError,
      );
    },
  );
}
