import 'package:audyt/core/ids/entity_id.dart';

enum TaxTreatment {
  deductible,
  conditional,
  percentageLimited,
  nonDeductible,
  capitalAllowance,
  specificDeduction,
  complianceGated,
  reviewRequired,
}

final class ExpenseCategory {
  ExpenseCategory._({
    required this.id,
    required this.code,
    required this.displayName,
    required this.normalAccountingGroup,
    required this.taxTreatment,
    required this.deductibleBasisPoints,
    required this.legalBasis,
    required this.evidenceProfile,
    required this.effectiveYearFrom,
    required this.effectiveYearTo,
    required this.privateApportionmentRequired,
    required this.withholdingTaxRequired,
    required this.approvalRequired,
    required this.reviewRequired,
    required this.searchKeywords,
  });

  factory ExpenseCategory.create({
    required EntityId id,
    required String code,
    required String displayName,
    required String normalAccountingGroup,
    required TaxTreatment taxTreatment,
    int? deductibleBasisPoints,
    String? legalBasis,
    required String evidenceProfile,
    int? effectiveYearFrom,
    int? effectiveYearTo,
    bool privateApportionmentRequired = false,
    bool withholdingTaxRequired = false,
    bool approvalRequired = false,
    bool reviewRequired = false,
    List<String> searchKeywords = const <String>[],
  }) {
    if (code.trim().isEmpty || displayName.trim().isEmpty) {
      throw ArgumentError('Expense category code and name are required.');
    }
    if (deductibleBasisPoints != null &&
        (deductibleBasisPoints < 0 || deductibleBasisPoints > 10000)) {
      throw ArgumentError.value(
        deductibleBasisPoints,
        'deductibleBasisPoints',
        'Deductible percentage must be between 0 and 10000 basis points.',
      );
    }
    if (effectiveYearFrom != null &&
        effectiveYearTo != null &&
        effectiveYearTo < effectiveYearFrom) {
      throw ArgumentError('Effective end year cannot precede the start year.');
    }
    return ExpenseCategory._(
      id: id,
      code: code.trim(),
      displayName: displayName.trim(),
      normalAccountingGroup: normalAccountingGroup.trim(),
      taxTreatment: taxTreatment,
      deductibleBasisPoints: deductibleBasisPoints,
      legalBasis: legalBasis?.trim(),
      evidenceProfile: evidenceProfile.trim(),
      effectiveYearFrom: effectiveYearFrom,
      effectiveYearTo: effectiveYearTo,
      privateApportionmentRequired: privateApportionmentRequired,
      withholdingTaxRequired: withholdingTaxRequired,
      approvalRequired: approvalRequired,
      reviewRequired: reviewRequired,
      searchKeywords: List<String>.unmodifiable(searchKeywords),
    );
  }

  final EntityId id;
  final String code;
  final String displayName;
  final String normalAccountingGroup;
  final TaxTreatment taxTreatment;
  final int? deductibleBasisPoints;
  final String? legalBasis;
  final String evidenceProfile;
  final int? effectiveYearFrom;
  final int? effectiveYearTo;
  final bool privateApportionmentRequired;
  final bool withholdingTaxRequired;
  final bool approvalRequired;
  final bool reviewRequired;
  final List<String> searchKeywords;
}

final class ExpenseCategoryCatalog {
  ExpenseCategoryCatalog._();

  static var _seedIndex = 0;

  static final List<ExpenseCategory> seeded = List.unmodifiable([
    _category('personnel', 'Personnel', TaxTreatment.deductible, 'Personnel'),
    _category(
      'employee-contributions',
      'Statutory Employee Contributions',
      TaxTreatment.conditional,
      'Personnel',
      reviewRequired: true,
    ),
    _category(
      'staff-welfare',
      'Staff Welfare',
      TaxTreatment.conditional,
      'Personnel',
      reviewRequired: true,
    ),
    _category(
      'staff-development',
      'Staff Development',
      TaxTreatment.specificDeduction,
      'Personnel',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category('premises', 'Premises', TaxTreatment.deductible, 'Operations'),
    _category(
      'utilities',
      'Utilities',
      TaxTreatment.conditional,
      'Operations',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'digital-services',
      'Digital Operations',
      TaxTreatment.conditional,
      'Operations',
      reviewRequired: true,
    ),
    _category(
      'business-insurance',
      'Business Insurance',
      TaxTreatment.deductible,
      'Operations',
    ),
    _category(
      'financing',
      'Financing Costs',
      TaxTreatment.conditional,
      'Finance',
      reviewRequired: true,
    ),
    _category(
      'operating-rentals',
      'Operating Rentals',
      TaxTreatment.conditional,
      'Operations',
      reviewRequired: true,
    ),
    _category('advertising', 'Advertising', TaxTreatment.deductible, 'Sales'),
    _category(
      'promotional-items',
      'Promotional Items',
      TaxTreatment.specificDeduction,
      'Sales',
      reviewRequired: true,
    ),
    _category(
      'entertainment',
      'Entertainment',
      TaxTreatment.percentageLimited,
      'Sales',
      reviewRequired: true,
    ),
    _category(
      'travel',
      'Business Travel',
      TaxTreatment.conditional,
      'Operations',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'transport',
      'Transport',
      TaxTreatment.conditional,
      'Operations',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'repairs',
      'Repairs and Restoration',
      TaxTreatment.conditional,
      'Operations',
      reviewRequired: true,
    ),
    _category(
      'initial-repairs',
      'Initial Repairs',
      TaxTreatment.nonDeductible,
      'Capital',
      reviewRequired: true,
    ),
    _category(
      'improvements',
      'Improvements and Renovation',
      TaxTreatment.capitalAllowance,
      'Capital',
      reviewRequired: true,
    ),
    _category(
      'office-operations',
      'Office Operations',
      TaxTreatment.deductible,
      'Operations',
    ),
    _category(
      'short-life-replacements',
      'Short-Life Replacements',
      TaxTreatment.conditional,
      'Operations',
      reviewRequired: true,
    ),
    _category(
      'professional-services',
      'Professional Services',
      TaxTreatment.conditional,
      'Administration',
      reviewRequired: true,
    ),
    _category(
      'legal-fees',
      'Legal Fees',
      TaxTreatment.conditional,
      'Administration',
      reviewRequired: true,
    ),
    _category(
      'bad-debts',
      'Trade Bad Debts',
      TaxTreatment.conditional,
      'Sales',
      reviewRequired: true,
    ),
    _category(
      'debt-recoveries',
      'Debt Recoveries',
      TaxTreatment.conditional,
      'Sales',
      reviewRequired: true,
    ),
    _category(
      'foreign-exchange',
      'Foreign Exchange',
      TaxTreatment.conditional,
      'Finance',
      reviewRequired: true,
    ),
    _category(
      'taxes-penalties',
      'Taxes and Penalties',
      TaxTreatment.nonDeductible,
      'Tax',
      reviewRequired: true,
    ),
    _category(
      'donations',
      'Donations',
      TaxTreatment.specificDeduction,
      'Administration',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'sponsorship',
      'Sponsorship',
      TaxTreatment.specificDeduction,
      'Sales',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'withholding-tax',
      'Non-Resident and Withholding-Tax Payments',
      TaxTreatment.complianceGated,
      'Tax',
      withholdingTaxRequired: true,
      reviewRequired: true,
    ),
    _category(
      'pre-commencement',
      'Pre-Commencement Expenses',
      TaxTreatment.nonDeductible,
      'Administration',
      reviewRequired: true,
    ),
    _category(
      'capital-assets',
      'Capital Assets',
      TaxTreatment.capitalAllowance,
      'Capital',
      reviewRequired: true,
    ),
    _category(
      'vehicles',
      'Vehicles',
      TaxTreatment.capitalAllowance,
      'Capital',
      reviewRequired: true,
    ),
    _category(
      'buildings',
      'Buildings and Structural Works',
      TaxTreatment.capitalAllowance,
      'Capital',
      reviewRequired: true,
    ),
    _category(
      'research-development',
      'Research and Development',
      TaxTreatment.specificDeduction,
      'Special Deductions',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'disabled-worker-support',
      'Disabled-Worker Support',
      TaxTreatment.specificDeduction,
      'Special Deductions',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'public-cultural-community',
      'Public, Cultural, and Community Activities',
      TaxTreatment.specificDeduction,
      'Special Deductions',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'petrol-fuel',
      'Petrol / Fuel',
      TaxTreatment.conditional,
      'Transport & Travel',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'parking-tolls-local-transport',
      'Parking, Tolls & Local Transport',
      TaxTreatment.conditional,
      'Transport & Travel',
      reviewRequired: true,
    ),
    _category(
      'motor-vehicle-repairs-maintenance',
      'Motor Vehicle Repairs & Maintenance',
      TaxTreatment.conditional,
      'Transport & Travel',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'business-travel-accommodation',
      'Business Travel & Accommodation',
      TaxTreatment.conditional,
      'Transport & Travel',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'meals-refreshments',
      'Meals & Refreshments',
      TaxTreatment.conditional,
      'Meals & People',
      reviewRequired: true,
    ),
    _category(
      'client-entertainment',
      'Client Entertainment',
      TaxTreatment.percentageLimited,
      'Meals & People',
      reviewRequired: true,
    ),
    _category(
      'staff-welfare-team-events',
      'Staff Welfare & Team Events',
      TaxTreatment.conditional,
      'Meals & People',
      reviewRequired: true,
    ),
    _category(
      'employee-travel-leave-passage',
      'Employee Travel / Leave Passage',
      TaxTreatment.conditional,
      'Meals & People',
      reviewRequired: true,
      searchKeywords: <String>['holiday', 'leave', 'passage'],
    ),
    _category(
      'rent-premises',
      'Rent & Premises',
      TaxTreatment.conditional,
      'Premises & Operations',
      reviewRequired: true,
    ),
    _category(
      'utilities-phone-internet',
      'Utilities, Phone & Internet',
      TaxTreatment.conditional,
      'Premises & Operations',
      privateApportionmentRequired: true,
      reviewRequired: true,
    ),
    _category(
      'repairs-maintenance',
      'Repairs & Maintenance',
      TaxTreatment.conditional,
      'Premises & Operations',
      reviewRequired: true,
    ),
    _category(
      'office-supplies-small-equipment',
      'Office Supplies & Small Equipment',
      TaxTreatment.conditional,
      'Premises & Operations',
      reviewRequired: true,
    ),
    _category(
      'software-subscriptions',
      'Software & Subscriptions',
      TaxTreatment.conditional,
      'Technology',
      reviewRequired: true,
    ),
    _category(
      'domain-hosting-online-services',
      'Domain, Hosting & Online Services',
      TaxTreatment.conditional,
      'Technology',
      reviewRequired: true,
    ),
    _category(
      'accounting-legal-professional-fees',
      'Accounting, Legal & Professional Fees',
      TaxTreatment.conditional,
      'Professional & Finance',
      reviewRequired: true,
    ),
    _category(
      'bank-merchant-charges',
      'Bank & Merchant Charges',
      TaxTreatment.conditional,
      'Professional & Finance',
      reviewRequired: true,
    ),
    _category(
      'advertising-marketing',
      'Advertising & Marketing',
      TaxTreatment.conditional,
      'Sales & Community',
      reviewRequired: true,
    ),
    _category(
      'donations-contributions',
      'Donations & Contributions',
      TaxTreatment.specificDeduction,
      'Sales & Community',
      approvalRequired: true,
      reviewRequired: true,
    ),
    _category(
      'equipment-computers-furniture',
      'Equipment, Computers & Furniture',
      TaxTreatment.capitalAllowance,
      'Assets / Capital Items',
      reviewRequired: true,
    ),
    _category(
      'motor-vehicles',
      'Motor Vehicles',
      TaxTreatment.capitalAllowance,
      'Assets / Capital Items',
      reviewRequired: true,
    ),
    _category(
      'premises-improvements-other-capital-items',
      'Premises Improvements / Other Capital Items',
      TaxTreatment.capitalAllowance,
      'Assets / Capital Items',
      reviewRequired: true,
    ),
  ]);

  static ExpenseCategory? byCode(String code) {
    for (final category in seeded) {
      if (category.code == code) {
        return category;
      }
    }
    return null;
  }

  static List<ExpenseCategory> search(
    String query, {
    Iterable<ExpenseCategory>? source,
  }) {
    final needle = query.trim().toLowerCase();
    final categories = source ?? seeded;
    if (needle.isEmpty) {
      return List<ExpenseCategory>.unmodifiable(categories);
    }
    return List<ExpenseCategory>.unmodifiable(
      categories.where(
        (category) =>
            category.displayName.toLowerCase().contains(needle) ||
            category.code.toLowerCase().contains(needle) ||
            category.normalAccountingGroup.toLowerCase().contains(needle) ||
            category.searchKeywords.any(
              (keyword) => keyword.toLowerCase().contains(needle),
            ),
      ),
    );
  }

  static Map<String, List<ExpenseCategory>> grouped({
    String query = '',
    Iterable<ExpenseCategory>? source,
  }) {
    final groups = <String, List<ExpenseCategory>>{};
    for (final category in search(query, source: source)) {
      groups
          .putIfAbsent(
            category.normalAccountingGroup,
            () => <ExpenseCategory>[],
          )
          .add(category);
    }
    return Map<String, List<ExpenseCategory>>.unmodifiable(
      <String, List<ExpenseCategory>>{
        for (final entry in groups.entries)
          entry.key: List<ExpenseCategory>.unmodifiable(entry.value),
      },
    );
  }

  static ExpenseCategory _category(
    String code,
    String displayName,
    TaxTreatment taxTreatment,
    String normalAccountingGroup, {
    bool privateApportionmentRequired = false,
    bool withholdingTaxRequired = false,
    bool approvalRequired = false,
    bool reviewRequired = false,
    List<String> searchKeywords = const <String>[],
  }) {
    final seedIndex = ++_seedIndex;
    return ExpenseCategory.create(
      id: EntityId.parse(
        '018f0c4e-56f1-7d4a-b9bb-6e2d6b8c${seedIndex.toRadixString(16).padLeft(4, '0')}',
      ),
      code: code,
      displayName: displayName,
      normalAccountingGroup: normalAccountingGroup,
      taxTreatment: taxTreatment,
      deductibleBasisPoints: taxTreatment == TaxTreatment.deductible
          ? 10000
          : null,
      legalBasis: 'LHDN rule pack; current-year review required',
      evidenceProfile: 'ordinary-expense',
      privateApportionmentRequired: privateApportionmentRequired,
      withholdingTaxRequired: withholdingTaxRequired,
      approvalRequired: approvalRequired,
      reviewRequired: reviewRequired || taxTreatment != TaxTreatment.deductible,
      searchKeywords: searchKeywords,
    );
  }
}
