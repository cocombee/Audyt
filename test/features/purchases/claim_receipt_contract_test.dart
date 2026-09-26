import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../accounting/data/claim_receipt_tax_test.dart' show fixture;

Map<String, dynamic> copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map receipt(Map value, [int index = 0]) =>
    (value['receipts'] as List)[index] as Map;
Map item(Map value, [int index = 0]) =>
    ((receipt(value, index)['lines'] as List).first as Map)['item'] as Map;

void main() {
  test('receipt identity, basis, evidence, currency and exact aggregate are enforced', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final claim = f.claim();
    final changes = <String, void Function(Map<String, dynamic>)>{
      'empty v3 receipt list': (j) => j['receipts'] = [],
      'v1 receipt injection': (j) => j['version'] = 1,
      'one-cent aggregate discrepancy': (j) => j['amountMinor'] = 18201,
      'different receipt currency': (j) => receipt(j)['currency'] = 'USD',
      'unknown original': (j) =>
          receipt(j)['originalDocumentIds'] = ['missing'],
      'duplicate receipt': (j) => receipt(j, 1)['id'] = receipt(j)['id'],
      'duplicate row across receipts': (j) => item(j, 1)['id'] = item(j)['id'],
      'space-only row identity': (j) => item(j)['id'] = ' ',
      'duplicate original link': (j) => receipt(j)['originalDocumentIds'] = [
        claim.attachments.single.originalId,
        claim.attachments.single.originalId,
      ],
      'no rows': (j) => receipt(j)['lines'] = [],
      'unresolved basis': (j) => receipt(j)['taxMode'] = 'Review Needed',
      'noncalendar saved date': (j) =>
          receipt(j)['date'] = '2026-09-10T12:00:00.000Z',
      'missing merchant': (j) => receipt(j)['merchant'] = ' ',
      'zero amount': (j) => item(j)['amount'] = '0',
      'unknown legacy tax': (j) {
        item(j).remove('taxSnapshot');
        item(j)['tax'] = 'Review Needed';
      },
      'mismatched tax choice': (j) => item(j)['tax'] = '0',
      'sales-only code': (j) =>
          (item(j)['taxSnapshot'] as Map)['application'] = 'sales',
      'rate without quantity': (j) => item(j)['rate'] = '100',
      'pricing mismatch': (j) {
        item(j)['rate'] = '99';
        item(j)['quantity'] = '1';
      },
    };
    for (final change in changes.entries) {
      final payload = copy(claim.toJson());
      change.value(payload);
      expect(
        () => Claim.fromJson(payload),
        throwsFormatException,
        reason: change.key,
      );
    }
    final exact = copy(claim.toJson());
    item(exact)['quantity'] = '3';
    item(exact)['rate'] = '33.33';
    item(exact)['pricingAdjustment'] = '0.01';
    expect(Claim.fromJson(exact).amount, claim.amount);
    expect(Claim.fromJson(exact).toJson(), exact);
    final roundTrip = ClaimReceipt.fromJson(
      copy(claim.receipts.first.toJson()),
    );
    expect(roundTrip.toJson(), claim.receipts.first.toJson());
    expect(() => roundTrip.lines.clear(), throwsUnsupportedError);
    expect(() => roundTrip.originalDocumentIds.clear(), throwsUnsupportedError);
  });

  test(
    'unrelated ready evidence cannot substitute a skipped linked receipt',
    () async {
      final f = await fixture();
      addTearDown(f.w.dispose);
      final payload = copy(f.claim().toJson());
      final attachments = payload['attachments'] as List;
      final other = copy(Map<String, Object?>.from(attachments.single as Map));
      other['originalId'] = EntityId.random().value;
      other['derivativeId'] = '${other['originalId']}-derivative';
      (attachments.single as Map)['reviewSkipped'] = true;
      attachments.add(other);
      final claim = Claim.fromJson(payload);
      expect(claim.hasReviewableAttachment, true);
      expect(
        claim.submissionErrors,
        contains(
          'Each recorded receipt requires its linked reviewable original document.',
        ),
      );
      expect(() => claim.submit(), throwsA(isA<ClaimValidationException>()));
    },
  );

  test(
    'exact decimal inputs round trip currency precision and int64 endpoints',
    () {
      for (final currency in ['MYR', 'JPY', 'KWD']) {
        for (final minor in [
          0,
          1,
          -1,
          12345,
          -12345,
          9223372036854775807,
          -9223372036854775808,
        ]) {
          final value = Money.fromMinor(minor, currency);
          expect(Money.fromDecimal(value.toDecimalString(), currency), value);
        }
      }
      expect(Money.fromMinor(-1, 'MYR').toDecimalString(), '-0.01');
      expect(Money.fromMinor(1, 'KWD').toDecimalString(), '0.001');
    },
  );
}
