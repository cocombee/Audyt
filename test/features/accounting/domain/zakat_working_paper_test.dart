import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/ledger_report.dart';
import 'package:audyt/features/accounting/domain/zakat_working_paper.dart';
import 'package:flutter_test/flutter_test.dart';

EntityId _id(int n) =>
    EntityId.parse('018f0c4e-56f1-7d4a-b9bb-${n.toString().padLeft(12, '0')}');
final _date = DateTime.utc(2026, 12, 31);
RecordMetadata _metadata(int n) => RecordMetadata.initial(
  recordId: _id(n),
  businessId: _id(90),
  originDeviceId: _id(91),
  createdAt: _date,
);

// Fictional arithmetic inputs, deliberately not an enabled authority policy.
ZakatWorkingCapitalRule _rule({
  int nisab = 100,
  String currency = 'MYR',
  int ownerNumerator = 1,
  int ownerDenominator = 1,
  int rateNumerator = 1,
  int rateDenominator = 40,
  ZakatNisabBasis basis = ZakatNisabBasis.businessBase,
  ZakatRounding rounding = ZakatRounding.halfUp,
  DateTime? effectiveThrough,
}) => ZakatWorkingCapitalRule(
  authority: 'Fictional Review Authority',
  policyVersion: 'Fictional 2026',
  source: Uri.parse('https://example.org/fictional-policy'),
  effectiveFrom: DateTime.utc(2026),
  effectiveThrough: effectiveThrough ?? _date,
  nisab: Money.fromMinor(nisab, currency),
  rateNumerator: rateNumerator,
  rateDenominator: rateDenominator,
  ownershipNumerator: ownerNumerator,
  ownershipDenominator: ownerDenominator,
  nisabBasis: basis,
  rounding: rounding,
);

List<StoredAccount> _accounts() => [
  for (final (n, type) in [
    (1, AccountType.asset),
    (2, AccountType.liability),
    (3, AccountType.equity),
    (4, AccountType.asset),
    (5, AccountType.income),
    (6, AccountType.expense),
  ])
    StoredAccount(
      account: Account.create(
        id: _id(n),
        code: '$n',
        name: 'Fictional $n',
        type: type,
      ),
      metadata: _metadata(n),
    ),
];

StoredJournalEntry _posting(int n, int debit, int credit, int amount) =>
    StoredJournalEntry(
      entry: JournalEntry.draft(
        id: _id(n),
        date: _date,
        memo: 'Fictional $n',
        lines: [
          JournalLine.debit(
            accountId: _id(debit),
            amount: Money.fromMinor(amount, 'MYR'),
          ),
          JournalLine.credit(
            accountId: _id(credit),
            amount: Money.fromMinor(amount, 'MYR'),
          ),
        ],
      ).post(),
      metadata: _metadata(n),
    );

LedgerReport _ledger({
  int asset = 10000,
  int liability = 2000,
  int fixed = 3000,
}) => LedgerReport.build(
  businessId: _id(90),
  currency: 'MYR',
  from: DateTime.utc(2026),
  through: _date,
  accounts: _accounts(),
  journals: [
    _posting(10, 1, 3, asset),
    if (liability > 0) _posting(11, 4, 2, liability),
    if (fixed > 0) _posting(12, 4, 3, fixed),
  ],
);

List<ZakatAccountReview> _reviews() => [
  ZakatAccountReview(
    accountId: _id(1),
    treatment: ZakatAccountTreatment.qualifyingAsset,
    reason: 'Fictional reviewed qualifying cash',
  ),
  ZakatAccountReview(
    accountId: _id(2),
    treatment: ZakatAccountTreatment.allowableLiability,
    reason: 'Fictional reviewed allowable liability',
  ),
  ZakatAccountReview(
    accountId: _id(4),
    treatment: ZakatAccountTreatment.excluded,
    reason: 'Fictional fixed assets explicitly excluded',
  ),
];

ZakatAdjustment _adjustment({
  int n = 20,
  int company = 90,
  int amount = 500,
  String currency = 'MYR',
  DateTime? date,
  String reason = 'Fictional adjustment',
  String reference = 'Review A',
}) => ZakatAdjustment(
  id: _id(n),
  businessId: _id(company),
  date: date ?? _date,
  amount: Money.fromMinor(amount, currency),
  reason: reason,
  supportingReference: reference,
);

ZakatWorkingPaper _paper({
  LedgerReport? ledger,
  ZakatWorkingCapitalRule? rule,
  List<ZakatAccountReview>? reviews,
  List<ZakatAdjustment> adjustments = const [],
  int company = 90,
  String eligibility = 'Fictional documented haul review',
}) => ZakatWorkingPaper.buildDraft(
  businessId: _id(company),
  ledger: ledger ?? _ledger(),
  rule: rule ?? _rule(),
  accountReviews: reviews ?? _reviews(),
  adjustments: adjustments,
  eligibilityReviewReference: eligibility,
);

void main() {
  test('working capital uses actual balances, explicit exclusions and signed adjustments', () {
    final ledger = _ledger();
    final paper = _paper(
      ledger: ledger,
      adjustments: [_adjustment(), _adjustment(n: 21, amount: -100)],
    );
    expect(paper.businessBase, BigInt.from(8400));
    expect(paper.amount, Money.fromMinor(210, 'MYR'));
    expect(
      paper.accounts.singleWhere((a) => a.account.id == _id(4)).endingNetDebit,
      BigInt.from(5000),
    );
    expect(
      paper.accounts
          .singleWhere((a) => a.account.id == _id(4))
          .baseContribution,
      BigInt.zero,
    );
    expect(paper.matchesLedger(ledger), isTrue);
    // Assessment arithmetic is never a posting or an automatic tax rebate.
    expect(ledger.postedJournalIds, hasLength(3));
    expect(ledger.periodProfit, BigInt.zero);
    expect(ledger.isBalanced, isTrue);
    expect(() => paper.accounts.clear(), throwsUnsupportedError);
    expect(() => paper.adjustments.clear(), throwsUnsupportedError);
  });

  test('nisab equality qualifies; exact ownership comparison does not round up eligibility', () {
    final ledger = _ledger(asset: 100, liability: 0, fixed: 0);
    expect(_paper(ledger: ledger, rule: _rule(nisab: 100)).meetsNisab, isTrue);
    expect(
      _paper(ledger: ledger, rule: _rule(nisab: 101)).amount.isZero,
      isTrue,
    );
    final fractional = _ledger(asset: 199, liability: 0, fixed: 0);
    final owned = _paper(
      ledger: fractional,
      rule: _rule(
        nisab: 100,
        ownerNumerator: 1,
        ownerDenominator: 2,
        basis: ZakatNisabBasis.ownedShare,
      ),
    );
    expect(
      owned.meetsNisab,
      isFalse,
    ); // 99.5, not rounded to 100 before comparison.
    expect(owned.amount.isZero, isTrue);
    final business = _paper(
      ledger: fractional,
      rule: _rule(
        nisab: 100,
        ownerNumerator: 1,
        ownerDenominator: 2,
        basis: ZakatNisabBasis.businessBase,
      ),
    );
    expect(business.meetsNisab, isTrue);
    expect(business.amount.minorUnits, 2);
  });

  for (final (rounding, expected) in [
    (ZakatRounding.halfUp, 3),
    (ZakatRounding.down, 2),
    (ZakatRounding.up, 3),
  ]) {
    test('explicit $rounding policy rounds only the final payable amount', () {
      final paper = _paper(
        ledger: _ledger(asset: 201, liability: 0, fixed: 0),
        rule: _rule(ownerNumerator: 1, ownerDenominator: 2, rounding: rounding),
      );
      expect(paper.amount.minorUnits, expected); // 201 / 2 / 40 = 2.5125
    });
  }

  test('contra assets and liabilities preserve their sign', () {
    final ledger = LedgerReport.build(
      businessId: _id(90),
      currency: 'MYR',
      from: DateTime.utc(2026),
      through: _date,
      accounts: _accounts(),
      journals: [
        _posting(10, 1, 3, 10000),
        _posting(11, 3, 4, 2000),
        _posting(12, 2, 3, 500),
      ],
    );
    final reviews = _reviews();
    reviews[2] = ZakatAccountReview(
      accountId: _id(4),
      treatment: ZakatAccountTreatment.qualifyingAsset,
      reason: 'Reviewed contra asset',
    );
    final paper = _paper(ledger: ledger, reviews: reviews);
    expect(paper.businessBase, BigInt.from(8500));
    expect(paper.amount.minorUnits, 213);
  });

  test('negative adjusted base remains visible and has no payable amount', () {
    final paper = _paper(adjustments: [_adjustment(amount: -9000)]);
    expect(paper.businessBase, BigInt.from(-1000));
    expect(paper.meetsNisab, isFalse);
    expect(paper.amount.isZero, isTrue);
  });

  test('arithmetic retains values above double precision', () {
    final paper = _paper(
      ledger: _ledger(asset: 9007199254741019, liability: 0, fixed: 0),
      rule: _rule(nisab: 1),
    );
    expect(paper.businessBase.toString(), '9007199254741019');
    expect(paper.amount.minorUnits, 225179981368525);
  });

  test('final Money range is checked before BigInt conversion', () {
    final ledger = LedgerReport.build(
      businessId: _id(90),
      currency: 'MYR',
      from: DateTime.utc(2026),
      through: _date,
      accounts: _accounts(),
      journals: [
        _posting(10, 1, 3, 9223372036854775807),
        _posting(11, 1, 3, 9223372036854775807),
      ],
    );
    expect(
      () => _paper(ledger: ledger, rule: _rule(nisab: 1, rateDenominator: 1)),
      throwsRangeError,
    );
  });

  final invalidInputs = <String, ZakatWorkingPaper Function()>{
    'foreign company': () => _paper(company: 99),
    'different nisab currency': () => _paper(rule: _rule(currency: 'USD')),
    'expired policy': () =>
        _paper(rule: _rule(effectiveThrough: DateTime.utc(2026, 12, 30))),
    'missing haul review': () => _paper(eligibility: ' '),
    'missing account classification': () =>
        _paper(reviews: _reviews().take(2).toList()),
    'duplicate account': () =>
        _paper(reviews: [..._reviews(), _reviews().first]),
    'unknown account': () => _paper(
      reviews: [
        ..._reviews(),
        ZakatAccountReview(
          accountId: _id(99),
          treatment: ZakatAccountTreatment.excluded,
          reason: 'Unknown',
        ),
      ],
    ),
    'wrong asset/liability type': () => _paper(
      reviews: [
        ZakatAccountReview(
          accountId: _id(1),
          treatment: ZakatAccountTreatment.allowableLiability,
          reason: 'Incorrect',
        ),
        ..._reviews().skip(1),
      ],
    ),
    'income classification': () => _paper(
      reviews: [
        ..._reviews(),
        ZakatAccountReview(
          accountId: _id(5),
          treatment: ZakatAccountTreatment.qualifyingAsset,
          reason: 'Incorrect',
        ),
      ],
    ),
    'missing exclusion reason': () => _paper(
      reviews: [
        ..._reviews().take(2),
        ZakatAccountReview(
          accountId: _id(4),
          treatment: ZakatAccountTreatment.excluded,
          reason: '',
        ),
      ],
    ),
    'duplicate adjustment': () =>
        _paper(adjustments: [_adjustment(), _adjustment()]),
    'foreign adjustment company': () =>
        _paper(adjustments: [_adjustment(company: 99)]),
    'foreign adjustment currency': () =>
        _paper(adjustments: [_adjustment(currency: 'USD')]),
    'future adjustment': () =>
        _paper(adjustments: [_adjustment(date: DateTime.utc(2027))]),
    'missing adjustment evidence reference': () =>
        _paper(adjustments: [_adjustment(reference: ' ')]),
    'zero nisab': () => _paper(rule: _rule(nisab: 0)),
    'negative nisab': () => _paper(rule: _rule(nisab: -1)),
    'zero rate': () => _paper(rule: _rule(rateNumerator: 0)),
    'zero rate denominator': () => _paper(rule: _rule(rateDenominator: 0)),
    'rate above one': () => _paper(rule: _rule(rateNumerator: 41)),
    'missing ownership': () => _paper(rule: _rule(ownerNumerator: 0)),
    'ownership above one': () => _paper(rule: _rule(ownerNumerator: 2)),
  };
  for (final entry in invalidInputs.entries) {
    test('rejects ${entry.key} rather than silently inventing eligibility', () {
      expect(entry.value, throwsA(anyOf(isArgumentError, isStateError)));
    });
  }

  test('ledger review survives real SQLite restart and detects balanced later postings', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-zakat-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var db = LocalAccountingDatabase.open(path);
    await db.configureLedger(businessId: _id(90), currencyCode: 'MYR');
    for (final account in _accounts()) {
      await db.saveAccount(account);
    }
    Future<void> post(StoredJournalEntry record) async {
      await db.save(
        StoredJournalEntry(
          entry: JournalEntry.draft(
            id: record.entry.id,
            date: record.entry.date,
            memo: record.entry.memo,
            lines: record.entry.lines,
          ),
          metadata: record.metadata,
        ),
      );
      await db.approve(
        JournalApproval(
          requestId: _id(int.parse(record.entry.id.value.substring(24)) + 100),
          businessId: _id(90),
          journalId: record.entry.id,
          expectedRevision: 1,
          actorId: _id(91),
          approvedAt: _date.add(const Duration(hours: 1)),
        ),
      );
    }

    await post(_posting(10, 1, 3, 10000));
    await post(_posting(11, 4, 2, 2000));
    await post(_posting(12, 4, 3, 3000));
    final before = await db.report(
      businessId: _id(90),
      from: DateTime.utc(2026),
      through: _date,
    );
    final paper = _paper(ledger: before);
    db.close();
    db = LocalAccountingDatabase.open(path);
    addTearDown(db.close);
    final restored = await db.report(
      businessId: _id(90),
      from: DateTime.utc(2026),
      through: _date,
    );
    expect(paper.matchesLedger(restored), isTrue);
    expect(_paper(ledger: restored).amount, paper.amount);
    await post(_posting(13, 1, 5, 1000));
    await post(
      _posting(14, 6, 1, 1000),
    ); // Same balance and profit, different real source.
    final changed = await db.report(
      businessId: _id(90),
      from: DateTime.utc(2026),
      through: _date,
    );
    expect(changed.assets, before.assets);
    expect(changed.periodProfit, before.periodProfit);
    expect(changed.isBalanced, isTrue);
    expect(paper.matchesLedger(changed), isFalse);
    expect(_paper(ledger: changed).amount, paper.amount);
  });
}
