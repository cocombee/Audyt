import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  test('data-only history retains submitted claim but cannot submit or approve absent evidence', () {
    final claim = ClaimStore.demo().all.singleWhere(
      (c) => c.status == ClaimStatus.submitted,
    );
    final payload =
        jsonDecode(jsonEncode(claim.toJson())) as Map<String, dynamic>;
    for (final attachment in payload['attachments'] as List) {
      attachment['originalBytes'] = null;
      attachment['derivativeBytes'] = null;
      attachment['pdfBytes'] = null;
      attachment['_evidenceUnavailable'] = true;
    }
    final restored = Claim.fromJson(payload);
    expect(restored.id, claim.id);
    expect(restored.status, ClaimStatus.submitted);
    expect(
      restored.attachments.single.originalSha256,
      claim.attachments.single.originalSha256,
    );
    expect(
      restored.attachments.single.failureMessage,
      contains('Reconnect the original file'),
    );
    expect(restored.hasReviewableAttachment, false);
    expect(() => restored.approve(), throwsA(isA<ClaimValidationException>()));
    expect(
      () => restored.returnForCorrection().submit(),
      throwsA(isA<ClaimValidationException>()),
    );
    final reopened = Claim.fromJson(
      jsonDecode(jsonEncode(restored.toJson())) as Map<String, dynamic>,
    );
    expect(reopened.status, restored.status);
    expect(reopened.hasReviewableAttachment, false);
    expect(
      () => Claim.fromJson({...payload, 'claimantName': ''}),
      throwsA(isA<ClaimValidationException>()),
    );
    final invalid = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    (invalid['attachments'] as List).single.remove('_evidenceUnavailable');
    expect(() => Claim.fromJson(invalid), throwsFormatException);
  });
  test(
    'claim lifecycle and receipt bytes round trip without changing evidence',
    () {
      final samples = ClaimStore.demo().all;
      final submitted = samples.singleWhere(
        (c) => c.status == ClaimStatus.submitted,
      );
      for (final claim in [
        ...samples,
        submitted.approve(),
        submitted.returnForCorrection(),
        submitted.decline(),
        samples.first.voidClaim(),
      ]) {
        final payload =
            jsonDecode(jsonEncode(claim.toJson())) as Map<String, dynamic>;
        final restored = Claim.fromJson(payload);
        expect(restored.toJson(), claim.toJson());
        expect(
          restored.attachments.single.originalBytes,
          claim.attachments.single.originalBytes,
        );
        expect(
          restored.attachments.single.originalSha256,
          claim.attachments.single.originalSha256,
        );
      }
    },
  );
  test('inconsistent paid records and duplicate receipts are rejected', () {
    final paid = ClaimStore.demo().all.singleWhere(
      (c) => c.status == ClaimStatus.paid,
    );
    expect(
      () => Claim.fromJson({...paid.toJson(), 'paymentBatchId': null}),
      throwsFormatException,
    );
    expect(
      () => Claim.fromJson({...paid.toJson(), 'status': 'draft'}),
      throwsFormatException,
    );
    final payload = paid.toJson();
    payload['attachments'] = [
      paid.attachments.single.toJson(),
      paid.attachments.single.toJson(),
    ];
    expect(() => Claim.fromJson(payload), throwsFormatException);
  });
}
