/// Typed route inventory for the Accounting Core release.
///
/// This registry is the only source used by the first-release navigation and
/// deep-link resolver. Unregistered paths intentionally resolve to null.
class AccountingFeature {
  const AccountingFeature({
    required this.id,
    required this.label,
    required this.path,
    required this.groupId,
  });

  final String id;
  final String label;
  final String path;
  final String groupId;
}

class AccountingNavigationGroup {
  const AccountingNavigationGroup({
    required this.id,
    required this.label,
    required this.features,
  });

  final String id;
  final String label;
  final List<AccountingFeature> features;
}

class FeatureRegistry {
  FeatureRegistry._();

  static const _groups = <AccountingNavigationGroup>[
    AccountingNavigationGroup(
      id: 'overview',
      label: 'Overview',
      features: <AccountingFeature>[
        AccountingFeature(
          id: 'home',
          label: 'Home',
          path: '/home',
          groupId: 'overview',
        ),
      ],
    ),
    AccountingNavigationGroup(
      id: 'money-in',
      label: 'Money In',
      features: <AccountingFeature>[
        AccountingFeature(
          id: 'sales-customers',
          label: 'Sales',
          path: '/sales-customers',
          groupId: 'money-in',
        ),
        AccountingFeature(
          id: 'contacts-items',
          label: 'Contacts & Items',
          path: '/contacts-items',
          groupId: 'money-in',
        ),
      ],
    ),
    AccountingNavigationGroup(
      id: 'money-out',
      label: 'Money Out',
      features: <AccountingFeature>[
        AccountingFeature(
          id: 'expenses-vendors',
          label: 'Expenses',
          path: '/expenses-vendors',
          groupId: 'money-out',
        ),
        AccountingFeature(
          id: 'claims',
          label: 'Claims',
          path: '/claims',
          groupId: 'money-out',
        ),
        AccountingFeature(
          id: 'payment-vouchers',
          label: 'Payment Vouchers',
          path: '/payment-vouchers',
          groupId: 'money-out',
        ),
        AccountingFeature(
          id: 'record-expense',
          label: 'Record Expense',
          path: '/record-expense',
          groupId: 'money-out',
        ),
      ],
    ),
    AccountingNavigationGroup(
      id: 'control',
      label: 'Control',
      features: <AccountingFeature>[
        AccountingFeature(
          id: 'banking',
          label: 'Banking',
          path: '/banking',
          groupId: 'control',
        ),
        AccountingFeature(
          id: 'accounting',
          label: 'Accounting',
          path: '/accounting',
          groupId: 'control',
        ),
        AccountingFeature(
          id: 'taxes',
          label: 'Taxes',
          path: '/taxes',
          groupId: 'control',
        ),
        AccountingFeature(
          id: 'reports',
          label: 'Reports',
          path: '/reports',
          groupId: 'control',
        ),
      ],
    ),
    AccountingNavigationGroup(
      id: 'records',
      label: 'Records',
      features: <AccountingFeature>[
        AccountingFeature(
          id: 'documents',
          label: 'Documents',
          path: '/documents',
          groupId: 'records',
        ),
        AccountingFeature(
          id: 'users',
          label: 'Employees',
          path: '/users',
          groupId: 'records',
        ),
        AccountingFeature(
          id: 'accountant-review',
          label: 'Accountant Review',
          path: '/accountant-review',
          groupId: 'records',
        ),
      ],
    ),
  ];

  static String sidebarId(String id) => switch (id) {
    'claims' || 'payment-vouchers' || 'record-expense' => 'expenses-vendors',
    'accountant-review' => 'accounting',
    'contacts-items' => 'sales-customers',
    _ => id,
  };

  static List<AccountingNavigationGroup> get navigationGroups => [
    for (final group in const <String, List<String>>{
      'Overview': ['home'],
      'Daily Work': ['expenses-vendors', 'sales-customers', 'banking'],
      'Review & Reports': ['reports', 'taxes', 'accounting'],
      'Records': ['documents', 'users'],
    }.entries)
      AccountingNavigationGroup(
        id: group.key,
        label: group.key,
        features: [for (final id in group.value) byId(id)!],
      ),
  ];

  static List<AccountingFeature> get all =>
      List<AccountingFeature>.unmodifiable(
        _groups.expand((group) => group.features),
      );

  static AccountingFeature? byId(String id) {
    for (final feature in all) {
      if (feature.id == id) {
        return feature;
      }
    }
    return null;
  }

  static AccountingFeature? byPath(String path) {
    final normalized = _normalizePath(path);
    for (final feature in all) {
      if (feature.path == normalized) {
        return feature;
      }
    }
    return null;
  }

  static bool canNavigate(String path) => byPath(path) != null;

  static String _normalizePath(String path) {
    if (path.isEmpty || path == '/') {
      return '/home';
    }
    final withoutTrailingSlash = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return withoutTrailingSlash.startsWith('/')
        ? withoutTrailingSlash
        : '/$withoutTrailingSlash';
  }
}
