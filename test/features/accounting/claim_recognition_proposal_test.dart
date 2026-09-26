import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/claim_recognition_proposal.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test(
    'recognition allocates exact claim once to a liability, without cash',
    () {
      final claim = ClaimStore.demo().all.first.submit();
      Account account(String code, AccountType type) => Account.create(
        id: EntityId.random(),
        code: code,
        name: code,
        type: type,
      );
      final expense = account('6000', AccountType.expense);
      final asset = account('1500', AccountType.asset);
      final liability = account('2100', AccountType.liability);
      final chart = [expense, asset, liability];
      ClaimRecognitionProposal build(List<JournalLine> lines) =>
          ClaimRecognitionProposal.create(
            claim: claim,
            liabilityAccount: liability,
            allocations: lines,
            accounts: chart,
          );
      final lines = [
        JournalLine.debit(
          accountId: expense.id,
          amount: Money.fromMinor(1000, 'MYR'),
        ),
        JournalLine.debit(
          accountId: asset.id,
          amount: Money.fromMinor(250, 'MYR'),
        ),
      ];
      final proposal = build(lines);
      lines.clear();
      expect(proposal.lines, hasLength(3));
      expect(proposal.lines.last.accountId, liability.id);
      expect(proposal.lines.last.isCredit, isTrue);
      expect(proposal.lines.last.amount, claim.amount);
      expect(proposal.date, claim.incurredOn);
      expect(() => proposal.lines.clear(), throwsUnsupportedError);
      expect(
        () => build([
          JournalLine.debit(
            accountId: expense.id,
            amount: Money.fromMinor(1249, 'MYR'),
          ),
        ]),
        throwsStateError,
      );
      expect(
        () => build([
          JournalLine.debit(
            accountId: expense.id,
            amount: Money.fromMinor(1250, 'USD'),
          ),
        ]),
        throwsStateError,
      );
      expect(
        () => build([
          JournalLine.debit(accountId: liability.id, amount: claim.amount),
        ]),
        throwsStateError,
      );
      expect(
        () => build([
          JournalLine.credit(accountId: expense.id, amount: claim.amount),
        ]),
        throwsStateError,
      );
    },
  );
}
