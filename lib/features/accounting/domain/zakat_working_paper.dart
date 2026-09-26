import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import 'account.dart';
import 'ledger_report.dart';

enum ZakatAccountTreatment { qualifyingAsset, allowableLiability, excluded }

enum ZakatNisabBasis { businessBase, ownedShare }

enum ZakatRounding { halfUp, down, up }

/// An explicitly reviewed working-capital rule, not a built-in state policy.
/// No authority, nisab, ownership, rate or eligibility is inferred by this type.
final class ZakatWorkingCapitalRule {
  ZakatWorkingCapitalRule({
    required this.authority,
    required this.policyVersion,
    required this.source,
    required DateTime effectiveFrom,
    required DateTime effectiveThrough,
    required this.nisab,
    required this.rateNumerator,
    required this.rateDenominator,
    required this.ownershipNumerator,
    required this.ownershipDenominator,
    required this.nisabBasis,
    required this.rounding,
  }) : effectiveFrom = _day(effectiveFrom),
       effectiveThrough = _day(effectiveThrough) {
    if (authority.trim().isEmpty || policyVersion.trim().isEmpty) {
      throw ArgumentError('The authority and policy version are required.');
    }
    if (source.scheme != 'https' || source.host.isEmpty) {
      throw ArgumentError('An official policy source is required.');
    }
    if (this.effectiveFrom.isAfter(this.effectiveThrough)) {
      throw ArgumentError('The policy effective dates are reversed.');
    }
    if (!nisab.isPositive) {
      throw ArgumentError('A positive, dated nisab is required.');
    }
    if (rateNumerator <= 0 ||
        rateDenominator <= 0 ||
        rateNumerator > rateDenominator) {
      throw ArgumentError('The rate must be a positive fraction up to one.');
    }
    if (ownershipNumerator <= 0 ||
        ownershipDenominator <= 0 ||
        ownershipNumerator > ownershipDenominator) {
      throw ArgumentError('Ownership must be a positive fraction up to one.');
    }
  }

  final String authority;
  final String policyVersion;
  final Uri source;
  final DateTime effectiveFrom;
  final DateTime effectiveThrough;
  final Money nisab;
  final int rateNumerator;
  final int rateDenominator;
  final int ownershipNumerator;
  final int ownershipDenominator;
  final ZakatNisabBasis nisabBasis;
  final ZakatRounding rounding;
}

final class ZakatAccountReview {
  const ZakatAccountReview({
    required this.accountId,
    required this.treatment,
    required this.reason,
  });

  final EntityId accountId;
  final ZakatAccountTreatment treatment;
  final String reason;
}

final class ZakatAdjustment {
  ZakatAdjustment({
    required this.id,
    required this.businessId,
    required DateTime date,
    required this.amount,
    required this.reason,
    required this.supportingReference,
  }) : date = _day(date);

  final EntityId id;
  final EntityId businessId;
  final DateTime date;
  final Money amount;
  final String reason;

  /// A review reference, not proof that an attachment is present or verified.
  final String supportingReference;
}

final class ZakatAccountBalance {
  const ZakatAccountBalance({
    required this.account,
    required this.endingNetDebit,
    required this.treatment,
    required this.reason,
  });

  final Account account;
  final BigInt endingNetDebit;
  final ZakatAccountTreatment treatment;
  final String reason;

  /// Retain contra balances; never turn them into positive assets/liabilities.
  BigInt get baseContribution => treatment == ZakatAccountTreatment.excluded
      ? BigInt.zero
      : endingNetDebit;
}

/// Draft arithmetic and source review only. This does not approve an assessment,
/// post a journal, verify haul/authority eligibility, or calculate a tax claim.
final class ZakatWorkingPaper {
  ZakatWorkingPaper._({
    required this.businessId,
    required this.asOf,
    required this.rule,
    required this.eligibilityReviewReference,
    required this.accounts,
    required this.adjustments,
    required this.businessBase,
    required this.meetsNisab,
    required this.amount,
    required this.pendingDrafts,
    required this.ledgerFingerprint,
  });

  factory ZakatWorkingPaper.buildDraft({
    required EntityId businessId,
    required LedgerReport ledger,
    required ZakatWorkingCapitalRule rule,
    required Iterable<ZakatAccountReview> accountReviews,
    required Iterable<ZakatAdjustment> adjustments,
    required String eligibilityReviewReference,
  }) {
    if (businessId != ledger.businessId) {
      throw StateError('The working paper belongs to another business.');
    }
    if (!ledger.isBalanced) {
      throw StateError('The ledger must reconcile before zakat review.');
    }
    if (eligibilityReviewReference.trim().isEmpty) {
      throw ArgumentError(
        'A haul and eligibility review reference is required.',
      );
    }
    if (ledger.currency != rule.nisab.currency) {
      throw StateError('Nisab and ledger currencies must match.');
    }
    if (ledger.through.isBefore(rule.effectiveFrom) ||
        ledger.through.isAfter(rule.effectiveThrough)) {
      throw StateError('The policy does not apply on the assessment date.');
    }
    final balances = {for (final row in ledger.rows) row.account.id: row};
    final reviewed = <EntityId, ZakatAccountBalance>{};
    for (final review in accountReviews) {
      final row = balances[review.accountId];
      if (row == null || reviewed.containsKey(review.accountId)) {
        throw StateError('An account is unmapped or reviewed more than once.');
      }
      if (review.reason.trim().isEmpty) {
        throw ArgumentError('Every account treatment needs a review reason.');
      }
      if (row.account.type != AccountType.asset &&
          row.account.type != AccountType.liability) {
        throw StateError(
          'Working capital reviews only assets and liabilities.',
        );
      }
      if ((review.treatment == ZakatAccountTreatment.qualifyingAsset &&
              row.account.type != AccountType.asset) ||
          (review.treatment == ZakatAccountTreatment.allowableLiability &&
              row.account.type != AccountType.liability)) {
        throw StateError('The treatment does not match the account type.');
      }
      reviewed[review.accountId] = ZakatAccountBalance(
        account: row.account,
        endingNetDebit: row.endingNetDebit,
        treatment: review.treatment,
        reason: review.reason.trim(),
      );
    }
    for (final row in ledger.rows) {
      if ((row.account.type == AccountType.asset ||
              row.account.type == AccountType.liability) &&
          row.endingNetDebit != BigInt.zero &&
          !reviewed.containsKey(row.account.id)) {
        throw StateError(
          'Every nonzero asset/liability needs explicit review.',
        );
      }
    }
    final accountRows = reviewed.values.toList()
      ..sort((a, b) => a.account.id.value.compareTo(b.account.id.value));
    final adjustmentRows = adjustments.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final adjustmentIds = <EntityId>{};
    var base = accountRows.fold(
      BigInt.zero,
      (sum, row) => sum + row.baseContribution,
    );
    for (final adjustment in adjustmentRows) {
      if (!adjustmentIds.add(adjustment.id)) {
        throw StateError('An adjustment appears more than once.');
      }
      if (adjustment.businessId != businessId ||
          adjustment.amount.currency != ledger.currency) {
        throw StateError('Adjustment business and currency must match.');
      }
      if (adjustment.date.isAfter(ledger.through)) {
        throw StateError('A future adjustment cannot change this assessment.');
      }
      if (adjustment.reason.trim().isEmpty ||
          adjustment.supportingReference.trim().isEmpty) {
        throw ArgumentError(
          'Adjustments require a reason and supporting reference.',
        );
      }
      base += BigInt.from(adjustment.amount.minorUnits);
    }
    final ownedNumerator = base * BigInt.from(rule.ownershipNumerator);
    final ownedDenominator = BigInt.from(rule.ownershipDenominator);
    // Compare exact fractions, without first rounding the owned share.
    final meetsNisab = rule.nisabBasis == ZakatNisabBasis.businessBase
        ? base >= BigInt.from(rule.nisab.minorUnits)
        : ownedNumerator >=
              BigInt.from(rule.nisab.minorUnits) * ownedDenominator;
    final due = meetsNisab
        ? _roundPositive(
            ownedNumerator * BigInt.from(rule.rateNumerator),
            ownedDenominator * BigInt.from(rule.rateDenominator),
            rule.rounding,
          )
        : BigInt.zero;
    if (due > BigInt.parse('9223372036854775807')) {
      throw RangeError('Zakat exceeds the supported exact monetary range.');
    }
    return ZakatWorkingPaper._(
      businessId: businessId,
      asOf: ledger.through,
      rule: rule,
      eligibilityReviewReference: eligibilityReviewReference.trim(),
      accounts: List.unmodifiable(accountRows),
      adjustments: List.unmodifiable(adjustmentRows),
      businessBase: base,
      meetsNisab: meetsNisab,
      amount: Money.fromMinor(due.toInt(), ledger.currency),
      pendingDrafts: ledger.pendingDrafts,
      ledgerFingerprint: _ledgerFingerprint(ledger),
    );
  }

  final EntityId businessId;
  final DateTime asOf;
  final ZakatWorkingCapitalRule rule;
  final String eligibilityReviewReference;
  final List<ZakatAccountBalance> accounts;
  final List<ZakatAdjustment> adjustments;
  final BigInt businessBase;
  final bool meetsNisab;
  final Money amount;
  final int pendingDrafts;
  final String ledgerFingerprint;

  /// An approval service must independently recheck policy, evidence, permission
  /// and record revisions. Equal balances alone do not establish an equal ledger.
  bool matchesLedger(LedgerReport ledger) =>
      ledgerFingerprint == _ledgerFingerprint(ledger);
}

BigInt _roundPositive(
  BigInt numerator,
  BigInt denominator,
  ZakatRounding rule,
) {
  final whole = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator);
  return switch (rule) {
    ZakatRounding.down => whole,
    ZakatRounding.up =>
      whole + (remainder == BigInt.zero ? BigInt.zero : BigInt.one),
    ZakatRounding.halfUp =>
      whole +
          (remainder * BigInt.two >= denominator ? BigInt.one : BigInt.zero),
  };
}

DateTime _day(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _ledgerFingerprint(LedgerReport ledger) {
  final rows = ledger.rows.toList()
    ..sort((a, b) => a.account.id.value.compareTo(b.account.id.value));
  final entries = ledger.postedEntries.toList()
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'business': ledger.businessId.value,
            'currency': ledger.currency,
            'from': ledger.from.toIso8601String(),
            'through': ledger.through.toIso8601String(),
            'pending': ledger.pendingDrafts,
            'accounts': [
              for (final row in rows)
                {
                  'id': row.account.id.value,
                  'code': row.account.code,
                  'name': row.account.name,
                  'type': row.account.type.name,
                  'status': row.account.status.name,
                  'parent': row.account.parentId?.value,
                  'isParent': row.account.isParent,
                  'balance': row.endingNetDebit.toString(),
                },
            ],
            'entries': [
              for (final entry in entries)
                {
                  'id': entry.id.value,
                  'date': entry.date.toIso8601String(),
                  'memo': entry.memo,
                  'reverses': entry.reversesId?.value,
                  'closing': entry.closingEquityAccountId?.value,
                  'lines': [
                    for (final line in entry.lines)
                      [
                        line.accountId.value,
                        line.kind.name,
                        line.amount.currency,
                        line.amount.minorUnits.toString(),
                      ],
                  ],
                },
            ],
          }),
        ),
      )
      .toString();
}
