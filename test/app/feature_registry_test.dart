import 'package:audyt/app/feature_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers every included accounting navigation family', () {
    final ids = FeatureRegistry.all.map((feature) => feature.id).toSet();

    expect(
      ids,
      containsAll(<String>{
        'home',
        'banking',
        'sales-customers',
        'expenses-vendors',
        'accounting',
        'taxes',
        'reports',
        'documents',
        'contacts-items',
        'accountant-review',
      }),
    );
    expect(FeatureRegistry.navigationGroups, hasLength(4));
  });

  test('keeps route labels in Title Case', () {
    expect(
      FeatureRegistry.all.map((feature) => feature.label),
      containsAll(<String>[
        'Home',
        'Banking',
        'Sales',
        'Expenses',
        'Accounting',
        'Taxes',
        'Reports',
        'Documents',
        'Contacts & Items',
        'Accountant Review',
      ]),
    );
    expect(
      FeatureRegistry.navigationGroups.map((group) => group.label),
      containsAll(<String>[
        'Overview',
        'Daily Work',
        'Review & Reports',
        'Records',
      ]),
    );
  });

  test('does not register excluded product surfaces', () {
    for (final excludedId in <String>[
      'payroll',
      'projects',
      'time-tracking',
      'crm',
      'warehouse',
      'team',
      'integrations',
      'pos',
      'ecommerce',
      'mileage',
    ]) {
      expect(FeatureRegistry.byId(excludedId), isNull);
      expect(FeatureRegistry.canNavigate('/$excludedId'), isFalse);
    }
  });

  test('resolves only registered paths', () {
    expect(FeatureRegistry.byPath('/banking')?.id, 'banking');
    expect(FeatureRegistry.byPath('/sales-customers')?.id, 'sales-customers');
    expect(FeatureRegistry.byPath('/not-a-feature'), isNull);
  });
}
