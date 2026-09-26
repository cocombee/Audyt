import 'package:audyt/features/accounting/domain/expense_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'separates accounting categories from LHDN treatment and review flags',
    () {
      final catalog = ExpenseCategoryCatalog.seeded;
      final codes = catalog.map((category) => category.code).toSet();

      expect(
        codes,
        containsAll([
          'personnel',
          'premises',
          'utilities',
          'entertainment',
          'travel',
          'repairs',
          'bad-debts',
          'capital-assets',
          'taxes-penalties',
          'withholding-tax',
        ]),
      );
      expect(codes.length, catalog.length);
      expect(
        catalog.any(
          (category) =>
              category.displayName.toLowerCase().contains('lhdn approved'),
        ),
        isFalse,
      );

      final entertainment = ExpenseCategoryCatalog.byCode('entertainment');
      expect(entertainment?.taxTreatment, TaxTreatment.percentageLimited);
      expect(entertainment?.deductibleBasisPoints, isNull);
      expect(entertainment?.reviewRequired, isTrue);
    },
  );

  test(
    'groups and searches the complete seeded catalog from accounting metadata',
    () {
      final grouped = ExpenseCategoryCatalog.grouped();

      expect(ExpenseCategoryCatalog.seeded, hasLength(57));
      expect(
        grouped.keys,
        containsAll(<String>[
          'Personnel',
          'Operations',
          'Finance',
          'Sales',
          'Administration',
          'Capital',
          'Tax',
          'Special Deductions',
        ]),
      );
      expect(
        grouped.values.expand((items) => items),
        hasLength(ExpenseCategoryCatalog.seeded.length),
      );

      final filtered = ExpenseCategoryCatalog.search('withholding');
      expect(filtered.map((category) => category.displayName), <String>[
        'Non-Resident and Withholding-Tax Payments',
      ]);
    },
  );
  test('includes the practical purchase taxonomy exactly once', () {
    const requested = <String>[
      'Petrol / Fuel',
      'Parking, Tolls & Local Transport',
      'Motor Vehicle Repairs & Maintenance',
      'Business Travel & Accommodation',
      'Meals & Refreshments',
      'Client Entertainment',
      'Staff Welfare & Team Events',
      'Employee Travel / Leave Passage',
      'Rent & Premises',
      'Utilities, Phone & Internet',
      'Repairs & Maintenance',
      'Office Supplies & Small Equipment',
      'Software & Subscriptions',
      'Domain, Hosting & Online Services',
      'Accounting, Legal & Professional Fees',
      'Bank & Merchant Charges',
      'Business Insurance',
      'Advertising & Marketing',
      'Donations & Contributions',
      'Equipment, Computers & Furniture',
      'Motor Vehicles',
      'Premises Improvements / Other Capital Items',
    ];
    final names = ExpenseCategoryCatalog.seeded
        .map((category) => category.displayName)
        .toList();
    for (final name in requested) {
      expect(
        names.where((candidate) => candidate == name),
        hasLength(1),
        reason: name,
      );
    }
    expect(
      ExpenseCategoryCatalog.byCode('petrol-fuel')?.taxTreatment,
      isNotNull,
    );
    expect(
      ExpenseCategoryCatalog.search('holiday').single.displayName,
      'Employee Travel / Leave Passage',
    );
    expect(
      ExpenseCategoryCatalog.byCode('petrol-fuel')?.reviewRequired,
      isTrue,
    );
  });
}
