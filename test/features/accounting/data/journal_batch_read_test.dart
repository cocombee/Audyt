import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_fixture.dart';

Map<String, List<List<Object?>>> _allTables(String path) {
  final sql = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final names = sql
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map((r) => r['name'] as String);
    return {
      for (final name in names)
        name: [
          for (final row in sql.select(
            'SELECT * FROM "${name.replaceAll('"', '""')}" ORDER BY rowid',
          ))
            [
              for (final value in row.values)
                value is Uint8List ? base64Encode(value) : value,
            ],
        ],
    };
  } finally {
    sql.dispose();
  }
}

EntityId _id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');

// Compare the durable contract, including fields invisible in dashboard totals.
Map<String, Object?> _snapshot(StoredJournalEntry record) => {
  'id': record.entry.id.value,
  'date': record.entry.date.toUtc().toIso8601String(),
  'memo': record.entry.memo,
  'state': record.entry.state.name,
  'reversesId': record.entry.reversesId?.value,
  'closingEquityId': record.entry.closingEquityAccountId?.value,
  'lines': [
    for (final line in record.entry.lines)
      [
        line.accountId.value,
        line.kind.name,
        line.amount.minorUnits,
        line.amount.currency,
      ],
  ],
  'recordId': record.metadata.recordId.value,
  'businessId': record.metadata.businessId.value,
  'deviceId': record.metadata.originDeviceId.value,
  'createdAt': record.metadata.createdAt.toIso8601String(),
  'updatedAt': record.metadata.updatedAt.toIso8601String(),
  'revision': record.metadata.revision,
  'deletedAt': record.metadata.deletedAt?.toIso8601String(),
};

StoredJournalEntry _draft(int n, {int business = 90, bool empty = false}) =>
    StoredJournalEntry(
      entry: JournalEntry.draft(
        id: _id(n),
        date: DateTime.utc(2026, 9, n == 10 ? 1 : 2),
        memo: 'Fictional entry $n · ordered split',
        lines: empty
            ? []
            : [
                JournalLine.credit(
                  accountId: _id(business + 20),
                  amount: Money.fromMinor(1400, 'MYR'),
                ),
                JournalLine.debit(
                  accountId: _id(business + 21),
                  amount: Money.fromMinor(900, 'MYR'),
                ),
                JournalLine.debit(
                  accountId: _id(business + 21),
                  amount: Money.fromMinor(500, 'MYR'),
                ),
              ],
      ),
      metadata: RecordMetadata.initial(
        recordId: _id(n),
        businessId: _id(business),
        originDeviceId: _id(business + 1),
        createdAt: DateTime.utc(2026, 9, 3),
      ),
    );

void main() {
  test('company journal list preserves complete records, ordering and tombstones after reopen', () async {
    final root = Directory.systemTemp.createTempSync('audyt-journal-batch-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    var db = LocalAccountingDatabase.open(path);
    addTearDown(() => db.close());
    final posted = await approveFixture(db, _draft(10));
    final reversal = StoredJournalEntry(
      entry: posted.entry.reversal(
        id: _id(11),
        date: DateTime.utc(2026, 9, 2),
        memo: 'Fictional reversal',
      ),
      metadata: _draft(11).metadata,
    );
    final reversed = await approveFixture(db, reversal);
    final empty = _draft(12, empty: true);
    await db.save(empty);
    await db.saveAccount(
      StoredAccount(
        account: Account.create(
          id: _id(120),
          code: '3000',
          name: 'Fictional retained equity',
          type: AccountType.equity,
        ),
        metadata: RecordMetadata.initial(
          recordId: _id(120),
          businessId: _id(90),
          originDeviceId: _id(91),
          createdAt: DateTime.utc(2026, 9, 3),
        ),
      ),
    );
    final closing = StoredJournalEntry(
      entry: JournalEntry.draft(
        id: _id(13),
        date: DateTime.utc(2026, 9, 2),
        memo: 'Closing proposal',
        lines: [],
        closingEquityAccountId: _id(120),
      ),
      metadata: _draft(13).metadata,
    );
    await db.save(closing);
    final revised = StoredJournalEntry(
      entry: closing.entry,
      metadata: closing.metadata.nextRevision(
        updatedAt: DateTime.utc(2026, 9, 4),
      ),
    );
    await db.save(revised);
    final deleted = _draft(14);
    await db.save(deleted);
    final tombstone = StoredJournalEntry(
      entry: deleted.entry,
      metadata: deleted.metadata.delete(deletedAt: DateTime.utc(2026, 9, 5)),
    );
    await db.save(tombstone);
    final otherCompany = await approveFixture(db, _draft(15, business: 190));
    db.close();
    db = LocalAccountingDatabase.open(path);
    final expected = [reversed, empty, revised, posted].map(_snapshot).toList();
    final listed = await db.listJournals(_id(90));
    expect(listed.map(_snapshot).toList(), expected);
    for (final record in [
      posted,
      reversed,
      empty,
      revised,
      tombstone,
      otherCompany,
    ]) {
      expect(
        _snapshot((await db.getById(record.entry.id))!),
        _snapshot(record),
      );
    }
    expect((await db.listJournals(_id(190))).map(_snapshot), [
      _snapshot(otherCompany),
    ]);
    expect(await db.listJournals(_id(290)), isEmpty);
    expect(() => listed.clear(), throwsUnsupportedError);
    expect(() => listed.first.entry.lines.clear(), throwsUnsupportedError);
  });

  test('bounded pages retain complete records, literal search, calendar filters and read-only reopen', () async {
    final root = Directory.systemTemp.createTempSync('audyt-journal-pages-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/book.sqlite';
    var db = LocalAccountingDatabase.open(path);
    await db.openWorkspace(
      newBusinessId: _id(90),
      newDeviceId: _id(91),
      newOwnerId: _id(99),
      defaultCurrency: 'MYR',
    );
    addTearDown(() => db.close());
    final expected = <StoredJournalEntry>[];
    expected.add(await approveFixture(db, _draft(10)));
    for (var n = 500; n < 540; n++) {
      if (n < 520) {
        expected.add(await approveFixture(db, _draft(n)));
      } else {
        await db.save(_draft(n));
      }
    }
    final removed = _draft(540);
    await db.save(removed);
    await db.save(
      StoredJournalEntry(
        entry: removed.entry,
        metadata: removed.metadata.delete(deletedAt: DateTime.utc(2026, 9, 5)),
      ),
    );
    await approveFixture(db, _draft(541, business: 190));
    final special = _draft(542);
    await db.save(
      StoredJournalEntry(
        entry: JournalEntry.draft(
          id: special.entry.id,
          date: DateTime.utc(2026, 9, 2, 23, 59),
          memo: r'Fictional 100% _ \',
          lines: special.entry.lines,
        ),
        metadata: special.metadata,
      ),
    );
    // Put the Unicode match beyond the first summary batch. Global search
    // must retain Dart's case folding without loading journal lines.
    for (var n = 600; n < 805; n++) {
      await db.save(_draft(n));
    }
    final unicode = _draft(900);
    await db.save(
      StoredJournalEntry(
        entry: JournalEntry.draft(
          id: unicode.entry.id,
          date: unicode.entry.date,
          memo: 'Fictional März 📄',
          lines: unicode.entry.lines,
        ),
        metadata: unicode.metadata,
      ),
    );
    expect(
      () => db.exportDataArchive(_id(90), DateTime.utc(2026, 9, 4)),
      throwsStateError,
    );
    final before = _allTables(path);
    StoredJournalPage page({
      int offset = 0,
      int limit = 5,
      String search = '',
      DateTime? through,
      JournalEntryState state = JournalEntryState.posted,
    }) => db.readJournalPage(
      businessId: _id(90),
      state: state,
      offset: offset,
      limit: limit,
      search: search,
      through: through,
    );
    final all = <StoredJournalEntry>[];
    for (var offset = 0; offset < 21; offset += 5) {
      final result = page(offset: offset);
      expect(result.total, 21);
      expect(result.records.length, lessThanOrEqualTo(5));
      all.addAll(result.records);
      for (final record in result.records) {
        expect(
          _snapshot(record),
          _snapshot((await db.getById(record.entry.id))!),
        );
      }
    }
    expected.sort((a, b) {
      final date = b.entry.date.compareTo(a.entry.date);
      return date != 0 ? date : a.entry.id.value.compareTo(b.entry.id.value);
    });
    expect(all.map(_snapshot), expected.map(_snapshot));
    expect(page(offset: 900).offset, 20);
    expect(
      page(through: DateTime.utc(2026, 9, 1, 23, 59)).records
          .map((r) => r.entry.id),
      [_id(10)],
    );
    expect(page(search: '000000000510').records.single.entry.id, _id(510));
    List<({String id, String memo, String state})> suggestions(
      String query, {
      int limit = 12,
    }) => db.searchJournalSummaries(
      businessId: _id(90),
      query: query,
      limit: limit,
    );
    expect(suggestions('journal'), hasLength(12));
    expect(suggestions('posted').map((r) => r.state).toSet(), {'posted'});
    expect(
      suggestions('posted journal 000000000510').single.id,
      _id(510).value,
    );
    expect(suggestions('draft 100%').single.id, special.entry.id.value);
    expect(suggestions('MÄRZ').single.id, unicode.entry.id.value);
    expect(suggestions('journal 📄').single.id, unicode.entry.id.value);
    expect(suggestions('000000000540'), isEmpty);
    expect(suggestions('000000000541'), isEmpty);
    expect(suggestions('unknown'), isEmpty);
    expect(() => suggestions('journal', limit: 0), throwsArgumentError);
    for (final term in ['100%', '_', r'\']) {
      expect(
        page(
          state: JournalEntryState.draft,
          search: term,
          through: DateTime.utc(2026, 9, 2),
        ).records.single.entry.id,
        special.entry.id,
      );
      expect(suggestions(term).single.id, special.entry.id.value);
    }
    expect(page(search: 'unknown').offset, 0);
    expect(page(search: 'unknown').total, 0);
    expect(() => page().records.clear(), throwsUnsupportedError);
    for (final size in [0, 51]) {
      expect(() => page(limit: size), throwsArgumentError);
    }
    expect(() => page(offset: -1), throwsArgumentError);
    expect(_allTables(path), before);
    final first = page().records.map(_snapshot).toList();
    db.close();
    db = LocalAccountingDatabase.open(path);
    expect(page().records.map(_snapshot).toList(), first);
    expect(_allTables(path), before);
  });

  test(
    'both report entry points exclude deleted drafts and other companies',
    () async {
      final db = LocalAccountingDatabase.inMemory();
      addTearDown(db.close);
      await approveFixture(db, _draft(10));
      final draft = _draft(12);
      await db.save(draft);
      final removed = _draft(14);
      await db.save(removed);
      await db.save(
        StoredJournalEntry(
          entry: removed.entry,
          metadata: removed.metadata.delete(
            deletedAt: DateTime.utc(2026, 9, 5),
          ),
        ),
      );
      await approveFixture(db, _draft(15, business: 190));
      for (final report in [
        await db.report(
          businessId: _id(90),
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        ),
        await db.readReport(
          businessId: _id(90),
          currency: 'MYR',
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        ),
      ]) {
        expect(report.postedJournalIds, [_id(10)]);
        expect(report.pendingDrafts, 1);
        expect(report.trialBalanceDebits, BigInt.from(1400));
        expect(report.trialBalanceCredits, BigInt.from(1400));
        expect(report.isBalanced, isTrue);
      }
    },
  );
}
