import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters payees to case-insensitive related matches only', () {
    final payees = <Payee>[
      Payee(id: 'staff-1', name: 'Aina Staff', type: PayeeType.staff),
      Payee(id: 'supplier-1', name: 'Aina Supplies', type: PayeeType.supplier),
      Payee(
        id: 'director-1',
        name: 'Badrul Director',
        type: PayeeType.director,
      ),
    ];

    expect(
      filterPayees(payees, 'AINA').map((payee) => payee.name),
      containsAll(<String>['Aina Staff', 'Aina Supplies']),
    );
    expect(filterPayees(payees, 'AINA'), hasLength(2));
    expect(filterPayees(payees, 'nobody'), isEmpty);
  });

  test('exposes separate worker, vendor, and small-provider labels', () {
    expect(PayeeType.values, hasLength(6));
    expect(PayeeType.staff.label, 'Employee');
    expect(PayeeType.director.label, 'Director');
    expect(PayeeType.supplier.label, 'Supplier');
    expect(PayeeType.vendor.label, 'Vendor');
    expect(PayeeType.smallProvider.label, 'Small Provider');
    expect(PayeeType.other.label, 'Other');
  });

  test('provides clearly identified local demo payees', () {
    expect(PayeeCatalog.demo.map((payee) => payee.name), <String>[
      'Aina Rahman',
      'Daniel Lim',
      'Acme Office Supplies',
      'Northwind Services',
      'Kecil Studio',
    ]);
    expect(PayeeCatalog.demo.map((payee) => payee.type), <PayeeType>[
      PayeeType.staff,
      PayeeType.director,
      PayeeType.supplier,
      PayeeType.vendor,
      PayeeType.smallProvider,
    ]);
    expect(PayeeCatalog.isDemo, isTrue);
  });

  test('owns payee additions and updates in one shared directory', () {
    final store = PayeeStore(payees: PayeeCatalog.demo);

    final created = store.add(name: 'Local Cafe', type: PayeeType.vendor);
    expect(store.all, contains(created));
    expect(created.name, 'Local Cafe');
    expect(created.type, PayeeType.vendor);

    final updated = Payee(
      id: created.id,
      name: 'Local Cafe Sdn Bhd',
      type: PayeeType.supplier,
    );
    store.save(updated);
    expect(store.byId(created.id), same(updated));
    expect(store.all.where((payee) => payee.id == created.id), hasLength(1));
  });
}
