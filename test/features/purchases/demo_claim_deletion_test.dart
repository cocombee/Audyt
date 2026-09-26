import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo deletion accepts only drafts and rejects persistent stores', () {
    final demo = ClaimStore.demo();
    final draft = demo.all.firstWhere((c) => c.status == ClaimStatus.draft);
    final paid = demo.all.firstWhere((c) => c.status == ClaimStatus.paid);
    final submitted = demo.all.firstWhere((c) => c.status == ClaimStatus.submitted);
    expect(() => demo.deleteDemoDraft(paid.id), throwsStateError);
    expect(() => demo.deleteDemoDraft(submitted.id), throwsStateError);
    final persistent = ClaimStore(claims: [draft], allowDemoDeletion: true,
      persistChanges: (_) => fail('No persistence write is allowed'));
    expect(() => persistent.deleteDemoDraft(draft.id), throwsStateError);
    final ordinary = ClaimStore(claims: [draft]);
    expect(() => ordinary.deleteDemoDraft(draft.id), throwsStateError);
    demo.deleteDemoDraft(draft.id);
    expect(demo.byId(draft.id), isNull);
    expect(demo.byId(paid.id), same(paid));
    expect(demo.byId(submitted.id), same(submitted));
  });
}
