import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim.dart';

import 'account.dart';
import 'journal_entry.dart';

/// Reviewed recognition input; persistence must bind it to the claim revision
/// and revalidate account ownership and posting policy in the commit transaction.
final class ClaimRecognitionProposal {
  ClaimRecognitionProposal._(this.claimId, this.date, this.lines);

  factory ClaimRecognitionProposal.create({
    required Claim claim,
    required Account liabilityAccount,
    required List<JournalLine> allocations,
    required Iterable<Account> accounts,
  }) {
    if (claim.status != ClaimStatus.submitted &&
        claim.status != ClaimStatus.approved) {
      throw StateError('Only submitted or approved claims can be recognized.');
    }
    if (claim.incurredOn == null) {
      throw StateError('Claim date is required.');
    }
    final chart = <EntityId, Account>{};
    for (final account in accounts) {
      if (chart.containsKey(account.id)) {
        throw ArgumentError('Duplicate account identity.');
      }
      chart[account.id] = account;
    }
    bool usable(Account account) =>
        account.status == AccountStatus.active &&
        !account.isParent &&
        account.validationErrors.isEmpty;
    final liability = chart[liabilityAccount.id];
    if (liability == null ||
        !usable(liability) ||
        liability.type != AccountType.liability) {
      throw StateError('Select an active posting liability account.');
    }
    if (allocations.isEmpty || claim.amount.minorUnits <= 0) {
      throw StateError('Positive claim allocations are required.');
    }
    var total = BigInt.zero;
    for (final line in allocations) {
      final account = chart[line.accountId];
      if (!line.isDebit ||
          line.amount.minorUnits <= 0 ||
          line.amount.currency != claim.amount.currency ||
          account == null ||
          !usable(account) ||
          (account.type != AccountType.expense &&
              account.type != AccountType.asset)) {
        throw StateError(
          'Allocations must debit active expense or asset accounts in the claim currency.',
        );
      }
      total += BigInt.from(line.amount.minorUnits);
    }
    if (total != BigInt.from(claim.amount.minorUnits)) {
      throw StateError('Allocations must equal the exact claim amount.');
    }
    if (claim.receipts.isNotEmpty) {
      final actual = <EntityId, BigInt>{};
      for (final line in allocations) {
        actual.update(
          line.accountId,
          (old) => old + BigInt.from(line.amount.minorUnits),
          ifAbsent: () => BigInt.from(line.amount.minorUnits),
        );
      }
      final expected = claim.receiptCostAllocations;
      if (actual.length != expected.length ||
          expected.entries.any(
            (e) => actual[e.key] != BigInt.from(e.value.minorUnits),
          )) {
        throw StateError(
          'Posting allocations must match the exact reviewed receipt costs.',
        );
      }
    }
    return ClaimRecognitionProposal._(
      claim.id,
      claim.incurredOn!,
      List.unmodifiable([
        ...allocations,
        JournalLine.credit(accountId: liability.id, amount: claim.amount),
      ]),
    );
  }

  final EntityId claimId;
  final DateTime date;
  final List<JournalLine> lines;
}
