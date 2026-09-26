import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test('edited submission commits once and preserves old draft on failure', () {
    final original = ClaimStore.demo().all.first;
    final edited = Claim.fromJson({
      ...original.toJson(),
      'businessPurpose': 'Revised purpose',
    });
    var calls = 0;
    final store = ClaimStore(
      claims: [original],
      persistChanges: (changes) {
        calls++;
        expect(changes.single.status, ClaimStatus.submitted);
        throw StateError('Storage unavailable');
      },
    );
    expect(() => store.saveAndSubmit(edited), throwsStateError);
    expect(calls, 1);
    expect(store.byId(original.id), same(original));
  });
  test('failed batch commit leaves every claim in its prior state', () {
    final source = ClaimStore.demo();
    final submitted = source.all.singleWhere(
      (c) => c.status == ClaimStatus.submitted,
    );
    final first = source.all
        .singleWhere((c) => c.status == ClaimStatus.draft)
        .submit();
    List<Claim>? attempted;
    final store = ClaimStore(
      claims: [first, submitted],
      persistChanges: (changes) {
        attempted = changes;
        throw StateError('Storage unavailable');
      },
    );
    expect(
      () => store.markPaidBatch(
        claimIds: [first.id, submitted.id],
        paymentBatchId: EntityId.random(),
        paidAt: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(attempted, hasLength(2));
    expect(attempted!.every((c) => c.status == ClaimStatus.paid), isTrue);
    expect(store.all.every((c) => c.status == ClaimStatus.submitted), isTrue);
  });
  test(
    'paid claims cannot be replaced by a draft or paid from an invalid state',
    () {
      final store = ClaimStore.demo();
      final paid = store.all.singleWhere((c) => c.status == ClaimStatus.paid);
      final replacement = Claim.draft(
        id: paid.id,
        vendorName: paid.vendorName,
        amount: paid.amount,
      );
      expect(() => store.saveDraft(replacement), throwsStateError);
      expect(store.byId(paid.id), same(paid));
      expect(
        () => replacement.markPaid(
          paymentBatchId: EntityId.random(),
          paidAt: DateTime.now(),
        ),
        throwsStateError,
      );
    },
  );
}
