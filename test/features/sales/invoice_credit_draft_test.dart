import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/sales/domain/invoice_credit_draft.dart';

void main() {
  test('credit draft restores exact amounts and rejects malformed saved lines', () {
    final invoice = EntityId.random();
    final line = EntityId.random();
    final id = EntityId.random();
    Map<String,dynamic> item({int minor=123, String currency='MYR'}) =>
      {'id':line.value,'minor':minor,'currency':currency};
    InvoiceCreditDraft restore(List<dynamic> lines, {String? source, int revision=1}) =>
      InvoiceCreditDraft.fromSnapshot(id:id,invoiceId:invoice,revision:revision,
        savedAt:DateTime.utc(2026,1,2),snapshot:{'invoiceId':source ?? invoice.value,
          'reason':'Returned goods','date':'2026-01-02T00:00:00.000Z','lines':lines});
    final restored = restore([item()]);
    expect(restored.total.minorUnits,123);
    expect(restored.total.currency,'MYR');
    expect(() => restore([]),throwsFormatException);
    expect(() => restore([item(),item()]),throwsFormatException);
    expect(() => restore([item(minor:0)]),throwsFormatException);
    expect(() => restore([item(minor:-1)]),throwsFormatException);
    expect(() => restore([item(),{'id':EntityId.random().value,'minor':100,'currency':'USD'}]),throwsFormatException);
    expect(() => restore([item()],source:EntityId.random().value),throwsFormatException);
    expect(() => restore([item()],revision:0),throwsFormatException);
  });
}
