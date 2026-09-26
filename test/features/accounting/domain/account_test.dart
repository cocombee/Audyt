import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps UUID identity while validating parent account relationships', () {
    final parent = Account.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a21'),
      code: '1000',
      name: 'Cash',
      type: AccountType.asset,
      isParent: true,
    );
    final child = Account.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c4a22'),
      code: '1010',
      name: 'Operating Cash',
      type: AccountType.asset,
      parentId: parent.id,
    );

    expect(child.validationErrors, isEmpty);
    expect(Account.validateParent(child: child, parent: parent), isEmpty);
    expect(child.id, isNot(parent.id));
    expect(child.displayName, '1010 · Operating Cash');
  });
}
