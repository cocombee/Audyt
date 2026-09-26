part of 'accounting_database.dart';

final class PayableAgeingRecord {
  const PayableAgeingRecord(this.posting, this.remaining, this.bucket);
  final StoredPostedBill posting;
  final Money remaining;
  final String bucket;
}

final class PayableControlBalance {
  const PayableControlBalance({
    required this.accountId,
    required this.code,
    required this.name,
    required this.billMinor,
    required this.ledgerMinor,
  });
  final EntityId accountId;
  final String code, name;
  final BigInt billMinor, ledgerMinor;
  BigInt get differenceMinor => ledgerMinor - billMinor;
}

final class PayablesAgeingSnapshot {
  PayablesAgeingSnapshot({
    required this.businessId,
    required this.currency,
    required this.asOf,
    required Map<String, BigInt> buckets,
    required List<PayableControlBalance> controls,
    required List<PayableAgeingRecord> records,
    required this.total,
    required this.offset,
    required this.limit,
  }) : buckets = Map.unmodifiable(buckets),
       controls = List.unmodifiable(controls),
       records = List.unmodifiable(records);
  final EntityId businessId;
  final String currency;
  final DateTime asOf;
  final Map<String, BigInt> buckets;
  final List<PayableControlBalance> controls;
  final List<PayableAgeingRecord> records;
  final int total, offset, limit;
  BigInt get outstandingMinor =>
      buckets.values.fold(BigInt.zero, (a, b) => a + b);
}

extension BillAgeingPersistence on LocalAccountingDatabase {
  /// One read snapshot, scalar batches rather than full-book document payloads,
  /// exact BigInt aggregates and only the requested page of complete sources.
  /// Recognition/payment dates are accounting dates, not approval timestamps.
  PayablesAgeingSnapshot payablesAgeing({
    required EntityId businessId,
    required String currency,
    required DateTime asOf,
    int offset = 0,
    int limit = 5,
  }) {
    _ensureOpen();
    currency = Currency.parse(currency).code;
    if (offset < 0 || limit < 1 || limit > 50) {
      throw ArgumentError('Invalid payables ageing page range.');
    }
    final date = accountingCalendarDate(asOf);
    final day = date.toIso8601String();
    final calendarDay = day.substring(0, 10);
    final ownsSnapshot = _database.autocommit;
    if (ownsSnapshot) _database.execute('BEGIN');
    try {
      if (_database
          .select(
            '''
        SELECT a.subject_id FROM ledger_audit a LEFT JOIN bill_postings p
          ON p.business_id=a.business_id AND p.bill_id=a.subject_id
        WHERE a.business_id=? AND a.kind='bill.posted' AND p.bill_id IS NULL
        UNION ALL
        SELECT s.request_id FROM bill_settlements s WHERE s.business_id=?
          AND NOT EXISTS (SELECT 1 FROM bill_settlement_allocations a
            WHERE a.business_id=s.business_id AND a.request_id=s.request_id)
        LIMIT 1
      ''',
            [businessId.value, businessId.value],
          )
          .isNotEmpty) {
        throw const FormatException(
          'A recognized Bill or payment is missing its saved links.',
        );
      }
      // Do not silently lose allocations whose saved parent/journal is missing,
      // moved to another company, voided, deleted or dated differently.
      if (_database
          .select(
            '''
        SELECT a.request_id FROM bill_settlement_allocations a
        LEFT JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id
        LEFT JOIN bill_postings p ON p.business_id=a.business_id AND p.bill_id=a.bill_id
        LEFT JOIN journal_entries j ON j.id=s.journal_id
        WHERE a.business_id=? AND (s.request_id IS NULL OR p.bill_id IS NULL
          OR j.id IS NULL OR j.business_id<>a.business_id OR j.state<>'posted'
          OR j.deleted_at IS NOT NULL OR j.entry_date<>s.paid_on
          OR s.currency<>? OR a.currency<>s.currency OR a.revision<>p.revision
          OR a.amount_minor<=0 OR a.amount_minor>a.expected_remaining_minor)
        LIMIT 1
      ''',
            [businessId.value, currency],
          )
          .isNotEmpty) {
        throw const FormatException(
          'A Bill payment has invalid source or ledger links.',
        );
      }
      final buckets = {for (final b in accountingAgeBuckets) b: BigInt.zero};
      final byAccount = <String, BigInt>{};
      var cursor = '', total = 0;
      while (true) {
        final facts = _database.select(
          '''
          SELECT p.bill_id,p.payable_account_id,p.revision,d.revision AS source_revision,
            r.reversed_on,
            j.business_id AS journal_company,j.state,j.deleted_at,j.entry_date,
            json_extract(d.payload,'\$.bill.amountMinor') AS original_minor,
            json_extract(d.payload,'\$.bill.currency') AS currency,
            json_extract(d.payload,'\$.bill.issueDate') AS issue_date,
            json_extract(d.payload,'\$.bill.dueDate') AS due_date,
            (SELECT COUNT(*) FROM journal_lines l WHERE l.journal_id=p.journal_id AND l.kind='credit') AS credit_count,
            (SELECT SUM(amount_minor) FROM journal_lines l WHERE l.journal_id=p.journal_id AND l.kind='debit' AND l.currency=?) AS debit_minor,
            (SELECT amount_minor FROM journal_lines l WHERE l.journal_id=p.journal_id AND l.kind='credit' AND l.account_id=p.payable_account_id AND l.currency=?) AS credit_minor,
            COALESCE((SELECT SUM(a.amount_minor) FROM bill_settlement_allocations a
              JOIN bill_settlements s ON s.business_id=a.business_id AND s.request_id=a.request_id
              LEFT JOIN bill_settlement_reversals sr ON sr.business_id=s.business_id AND sr.source_request_id=s.request_id
              WHERE a.business_id=p.business_id AND a.bill_id=p.bill_id AND s.paid_on<=?
                AND (sr.source_request_id IS NULL OR sr.reversed_on>?)),0) AS paid_minor
          FROM bill_postings p
          LEFT JOIN bill_drafts d ON d.business_id=p.business_id AND d.id=p.bill_id
          LEFT JOIN journal_entries j ON j.id=p.journal_id
          LEFT JOIN bill_posting_reversals r ON r.business_id=p.business_id AND r.bill_id=p.bill_id
          WHERE p.business_id=? AND p.bill_id>? ORDER BY p.bill_id LIMIT 512
        ''',
          [currency, currency, day, day, businessId.value, cursor],
        );
        if (facts.isEmpty) break;
        for (final f in facts) {
          final issue = parseAccountingInputDate(
            f['issue_date'] as String? ?? '',
          );
          final due = parseAccountingInputDate(f['due_date'] as String? ?? '');
          final original = f['original_minor'];
          if (issue == null ||
              due == null ||
              due.isBefore(issue) ||
              original is! int ||
              original <= 0 ||
              f['currency'] != currency ||
              f['revision'] != f['source_revision'] ||
              f['journal_company'] != businessId.value ||
              f['state'] != 'posted' ||
              f['deleted_at'] != null ||
              f['credit_count'] != 1 ||
              f['credit_minor'] != original ||
              f['debit_minor'] != original ||
              f['entry_date'] !=
                  accountingCalendarDate(issue).toIso8601String()) {
            throw const FormatException(
              'A Bill balance differs from its recognized source.',
            );
          }
          final account = f['payable_account_id'] as String;
          byAccount.putIfAbsent(account, () => BigInt.zero);
          final reversedOn = f['reversed_on'] as String?;
          if (reversedOn != null && reversedOn.compareTo(day) <= 0) continue;
          if (accountingCalendarDate(issue).isAfter(date)) continue;
          final paid = f['paid_minor'] as int;
          if (paid < 0 || paid > original) {
            throw const FormatException(
              'Bill allocations exceed the recognized payable.',
            );
          }
          final remaining = BigInt.from(original) - BigInt.from(paid);
          if (remaining == BigInt.zero) continue;
          total++;
          final bucket = accountingAgeBucket(dueDate: due, asOf: date);
          buckets[bucket] = buckets[bucket]! + remaining;
          byAccount[account] = byAccount[account]! + remaining;
        }
        cursor = facts.last['bill_id'] as String;
      }
      final defaultAccount = readCompanyPreferences(businessId)
          .text('Default Accounts', 'Payables Account');
      if (defaultAccount.isNotEmpty) {
        byAccount.putIfAbsent(defaultAccount, () => BigInt.zero);
      }
      final controls = <PayableControlBalance>[];
      for (final account in byAccount.entries) {
        final saved = _database.select(
          'SELECT code,name,type FROM accounts WHERE business_id=? AND id=?',
          [businessId.value, account.key],
        );
        if (saved.length != 1 || saved.single['type'] != 'liability') {
          throw const FormatException(
            'A Bill payable control account is unavailable.',
          );
        }
        var ledger = BigInt.zero, lastRow = 0;
        while (true) {
          // journal_lines_account includes rowid as its tie-breaker. Keyset
          // scanning avoids repeated OFFSET scans or complete journal hydration.
          final lines = _database.select(
            '''
            SELECT l.rowid AS scan_id,l.kind,l.amount_minor,l.currency,j.deleted_at
            FROM journal_lines l JOIN journal_entries j ON j.id=l.journal_id
            WHERE l.account_id=? AND l.rowid>? AND j.business_id=?
              AND j.state='posted' AND substr(j.entry_date,1,10)<=?
            ORDER BY l.rowid LIMIT 512
          ''',
            [account.key, lastRow, businessId.value, calendarDay],
          );
          if (lines.isEmpty) break;
          for (final l in lines) {
            if (l['currency'] != currency ||
                l['deleted_at'] != null ||
                (l['amount_minor'] as int) <= 0) {
              throw const FormatException(
                'A posted payable movement is invalid.',
              );
            }
            final amount = BigInt.from(l['amount_minor'] as int);
            ledger += l['kind'] == 'credit' ? amount : -amount;
          }
          lastRow = lines.last['scan_id'] as int;
        }
        controls.add(
          PayableControlBalance(
            accountId: EntityId.parse(account.key),
            code: saved.single['code'] as String,
            name: saved.single['name'] as String,
            billMinor: account.value,
            ledgerMinor: ledger,
          ),
        );
      }
      controls.sort((a, b) => a.code.compareTo(b.code));
      final lastOffset = total == 0 ? 0 : ((total - 1) ~/ limit) * limit;
      final actualOffset = offset > lastOffset ? lastOffset : offset;
      final rows = _database.select(
        '''
        WITH paid AS (
          SELECT a.bill_id,SUM(a.amount_minor) AS amount_minor
          FROM bill_settlement_allocations a JOIN bill_settlements s
            ON s.business_id=a.business_id AND s.request_id=a.request_id
          LEFT JOIN bill_settlement_reversals sr ON sr.business_id=s.business_id AND sr.source_request_id=s.request_id
          WHERE a.business_id=? AND s.paid_on<=?
            AND (sr.source_request_id IS NULL OR sr.reversed_on>?) GROUP BY a.bill_id
        )
        SELECT p.*,COALESCE(paid.amount_minor,0) AS paid_minor
        FROM bill_postings p JOIN bill_drafts d ON d.business_id=p.business_id AND d.id=p.bill_id
        JOIN journal_entries j ON j.id=p.journal_id LEFT JOIN paid ON paid.bill_id=p.bill_id
        LEFT JOIN bill_posting_reversals r ON r.business_id=p.business_id AND r.bill_id=p.bill_id
        WHERE p.business_id=? AND j.entry_date<=?
          AND (r.bill_id IS NULL OR r.reversed_on>?)
          AND COALESCE(paid.amount_minor,0)<json_extract(d.payload,'\$.bill.amountMinor')
        ORDER BY substr(json_extract(d.payload,'\$.bill.dueDate'),7,4),
          substr(json_extract(d.payload,'\$.bill.dueDate'),4,2),
          substr(json_extract(d.payload,'\$.bill.dueDate'),1,2),p.bill_id
        LIMIT ? OFFSET ?
      ''',
        [
          businessId.value,
          day,
          day,
          businessId.value,
          day,
          day,
          limit,
          actualOffset,
        ],
      );
      final records = [
        for (final row in rows)
          () {
            final posting = _billPostingFromRow(row);
            final remaining =
                posting.source.total -
                Money.fromMinor(row['paid_minor'] as int, currency);
            return PayableAgeingRecord(
              posting,
              remaining,
              accountingAgeBucket(
                dueDate: posting.source.bill.dueDate,
                asOf: date,
              ),
            );
          }(),
      ];
      final result = PayablesAgeingSnapshot(
        businessId: businessId,
        currency: currency,
        asOf: date,
        buckets: buckets,
        controls: controls,
        records: records,
        total: total,
        offset: actualOffset,
        limit: limit,
      );
      if (ownsSnapshot) _database.execute('COMMIT');
      return result;
    } catch (_) {
      if (ownsSnapshot) _database.execute('ROLLBACK');
      rethrow;
    }
  }
}
