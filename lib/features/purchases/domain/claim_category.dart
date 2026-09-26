import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/expense_category.dart';

/// A claim-facing category is intentionally separate from the direct-expense
/// category catalog. It carries the accounting mapping chosen for review.
final class ClaimCategory {
  ClaimCategory._({
    required this.id,
    required this.code,
    required this.displayName,
    required this.expenseCategoryCode,
    required this.expenseAccountCode,
    required this.reviewNeededMapping,
    required List<String> searchKeywords,
  }) : searchKeywords = List<String>.unmodifiable(searchKeywords);

  factory ClaimCategory.create({
    required EntityId id,
    required String code,
    required String displayName,
    String? expenseCategoryCode,
    String? expenseAccountCode,
    bool reviewNeededMapping = false,
    List<String> searchKeywords = const <String>[],
  }) {
    final normalizedCode = code.trim();
    final normalizedName = displayName.trim();
    final normalizedExpenseCategory = expenseCategoryCode?.trim();
    final normalizedExpenseAccount = expenseAccountCode?.trim();
    if (normalizedCode.isEmpty || normalizedName.isEmpty) {
      throw ArgumentError('Claim category code and name are required.');
    }
    if (!reviewNeededMapping &&
        (normalizedExpenseCategory == null ||
            normalizedExpenseCategory.isEmpty) &&
        (normalizedExpenseAccount == null ||
            normalizedExpenseAccount.isEmpty)) {
      throw ArgumentError(
        'A claim category needs an explicit expense or GL mapping, or review-needed state.',
      );
    }
    return ClaimCategory._(
      id: id,
      code: normalizedCode,
      displayName: normalizedName,
      expenseCategoryCode: normalizedExpenseCategory,
      expenseAccountCode: normalizedExpenseAccount,
      reviewNeededMapping: reviewNeededMapping,
      searchKeywords: searchKeywords,
    );
  }

  final EntityId id;
  final String code;
  final String displayName;
  final String? expenseCategoryCode;
  final String? expenseAccountCode;
  final bool reviewNeededMapping;
  final List<String> searchKeywords;

  bool get hasExplicitMapping =>
      (expenseCategoryCode?.isNotEmpty ?? false) ||
      (expenseAccountCode?.isNotEmpty ?? false);

  bool get mappingNeedsReview => reviewNeededMapping || !hasExplicitMapping;

  ExpenseCategory? get mappedExpenseCategory {
    final code = expenseCategoryCode;
    return code == null ? null : ExpenseCategoryCatalog.byCode(code);
  }

  String get mappingLabel {
    final expense = mappedExpenseCategory;
    final expenseLabel = expense?.displayName ?? expenseCategoryCode;
    final accountLabel = expenseAccountCode;
    final parts = <String>[
      if (expenseLabel != null && expenseLabel.isNotEmpty)
        'Expense: $expenseLabel',
      if (accountLabel != null && accountLabel.isNotEmpty) 'GL: $accountLabel',
    ];
    if (parts.isEmpty || mappingNeedsReview) {
      return 'Review needed: no verified expense or GL mapping';
    }
    return parts.join(' · ');
  }
}

final class ClaimCategoryCatalog {
  ClaimCategoryCatalog._();

  static const catalogId = 'claim-category-catalog';

  static final List<ClaimCategory> seeded = List.unmodifiable(<ClaimCategory>[
    ClaimCategory.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c6c01'),
      code: 'office-supplies',
      displayName: 'Office Supplies & Small Equipment',
      expenseCategoryCode: 'office-supplies-small-equipment',
      searchKeywords: <String>['stationery', 'equipment'],
    ),
    ClaimCategory.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c6c02'),
      code: 'meals-refreshments',
      displayName: 'Meals & Refreshments',
      expenseCategoryCode: 'meals-refreshments',
      searchKeywords: <String>['food', 'client meal'],
    ),
    ClaimCategory.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c6c03'),
      code: 'business-travel',
      displayName: 'Business Travel',
      expenseCategoryCode: 'travel',
      searchKeywords: <String>['transport', 'accommodation'],
    ),
    ClaimCategory.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c6c04'),
      code: 'professional-services',
      displayName: 'Professional Services',
      expenseCategoryCode: 'professional-services',
    ),
    ClaimCategory.create(
      id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c6c05'),
      code: 'advertising-marketing',
      displayName: 'Advertising & Marketing',
      expenseCategoryCode: 'advertising-marketing',
    ),
  ]);

  static ClaimCategory? byCode(String code) {
    for (final category in seeded) {
      if (category.code == code) return category;
    }
    return null;
  }

  static List<ClaimCategory> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return List<ClaimCategory>.unmodifiable(seeded);
    return List<ClaimCategory>.unmodifiable(
      seeded.where(
        (category) =>
            category.displayName.toLowerCase().contains(needle) ||
            category.code.toLowerCase().contains(needle) ||
            (category.expenseAccountCode?.toLowerCase().contains(needle) ??
                false) ||
            category.searchKeywords.any(
              (keyword) => keyword.toLowerCase().contains(needle),
            ),
      ),
    );
  }
}
