import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';

enum AccountType { asset, liability, equity, income, expense }

enum AccountStatus { active, locked, archived }

// Malaysia account classifications and dependent details inspected in the
// signed-in working QuickBooks account form on 5 October 2026. These are
// reporting classifications; the five ledger types remain posting authority.
enum ReportingAccountType {
  cashAndCashEquivalents('Cash and cash equivalents', AccountType.asset, [
    'Cash and cash equivalents',
    'Cash on hand',
    'Client trust account',
    'Current',
    'Money Market',
    'Rents Held in Trust',
    'Savings',
  ]),
  tradeAndOtherReceivables('Trade and other receivables', AccountType.asset, [
    'Trade and other receivables',
  ]),
  currentAssets('Current assets', AccountType.asset, [
    'Allowance for bad debts',
    'Assets available for sale',
    'Development Costs',
    'Employee Cash Advances',
    'Inventory',
    'Investments - Other',
    'Loans To Officers',
    'Loans to Others',
    'Loans to Shareholders',
    'Other current assets',
    'Prepaid Expenses',
    'Retainage',
    'Undeposited Funds',
  ]),
  propertyPlantAndEquipment(
    'Property, plant and equipment',
    AccountType.asset,
    [
      'Accumulated depletion',
      'Accumulated depreciation on property, plant and equipment',
      'Buildings',
      'Depletable Assets',
      'Furniture and Fixtures',
      'Land',
      'Leasehold Improvements',
      'Machinery and equipment',
      'Other fixed assets',
      'Vehicles',
    ],
  ),
  nonCurrentAssets('Non-current assets', AccountType.asset, [
    'Accumulated amortisation of non-current assets',
    'Assets held for sale',
    'Deferred tax',
    'Goodwill',
    'Intangible Assets',
    'Lease Buyout',
    'Licences',
    'Long-term investments',
    'Organisational Costs',
    'Other non-current assets',
    'Security Deposits',
  ]),
  creditCard('Credit card', AccountType.liability, ['Credit Card']),
  tradeAndOtherPayables('Trade and other payables', AccountType.liability, [
    'Trade and other payables',
  ]),
  currentLiabilities('Current liabilities', AccountType.liability, [
    'Accrued liabilities',
    'Client Trust Accounts - Liabilities',
    'Current portion of obligations under finance leases',
    'Current Tax Liability',
    'Dividends payable',
    'GST Payable',
    'Income tax payable',
    'Insurance payable',
    'Line of Credit',
    'Other current liabilities',
    'Other loans and similar liabilities',
    'Payroll Clearing',
    'Payroll liabilities',
    'Prepaid Expenses Payable',
    'Rents in trust - Liability',
  ]),
  nonCurrentLiabilities('Non-current liabilities', AccountType.liability, [
    'Accrued holiday payable',
    'Accrued non-current liabilities',
    'Liabilities related to assets held for sale',
    'Long-term debt',
    'Notes Payable',
    'Other non-current liabilities',
    'Shareholder Notes Payable',
  ]),
  ownersEquity('Owner\'s equity', AccountType.equity, [
    'Accumulated adjustment',
    'Dividend disbursed',
    'Equity in earnings of subsidiaries',
    'Opening Balance Equity',
    'Ordinary shares',
    'Other comprehensive income',
    'Owner\'s Equity',
    'Paid-in capital or surplus',
    'Partner Contributions',
    'Partner Distributions',
    'Partner\'s Equity',
    'Preferred shares',
    'Retained Earnings',
    'Share capital',
    'Treasury Shares',
  ]),
  income('Income', AccountType.income, [
    'Discounts/Refunds Given',
    'Non-Profit Income',
    'Other Primary Income',
    'Revenue - General',
    'Sales - retail',
    'Sales - wholesale',
    'Sales of Product Income',
    'Service/Fee Income',
    'Unapplied Cash Payment Income',
  ]),
  otherIncome('Other income', AccountType.income, [
    'Dividend income',
    'Interest earned',
    'Loss on disposal of assets',
    'Other Investment Income',
    'Other Miscellaneous Income',
    'Other operating income',
    'Tax-Exempt Interest',
    'Unrealised loss on securities, net of tax',
  ]),
  costOfSales('Cost of sales', AccountType.expense, [
    'Cost of Labour - COS',
    'Equipment rental - COS',
    'Freight and delivery - COS',
    'Other costs of sales - COS',
    'Supplies and materials - COS',
  ]),
  expenses('Expenses', AccountType.expense, [
    'Advertising/Promotional',
    'Amortisation expense',
    'Auto',
    'Bad debts',
    'Bank charges',
    'Charitable Contributions',
    'Commissions and fees',
    'Cost of Labour',
    'Dues and Subscriptions',
    'Equipment rental',
    'Finance costs',
    'Income tax expense',
    'Insurance',
    'Interest paid',
    'Legal and professional fees',
    'Loss on discontinued operations, net of tax',
    'Management compensation',
    'Meals and entertainment',
    'Office/General Administrative Expenses',
    'Other Miscellaneous Service Cost',
    'Other selling expenses',
    'Payroll Expenses',
    'Rent or Lease of Buildings',
    'Repair and maintenance',
    'Shipping and delivery expense',
    'Supplies',
    'Taxes Paid',
    'Travel expenses - general and admin expenses',
    'Travel expenses - selling expense',
    'Unapplied Cash Bill Payment Expense',
    'Utilities',
  ]),
  otherExpense('Other expense', AccountType.expense, [
    'Amortisation',
    'Depreciation',
    'Exchange Gain or Loss',
    'Other Expense',
    'Penalties and settlements',
  ]);

  const ReportingAccountType(this.label, this.ledgerType, this.details);
  final String label;
  final AccountType ledgerType;
  final List<String> details;
  bool get hasOpeningBalance =>
      ledgerType == AccountType.asset ||
      ledgerType == AccountType.liability ||
      ledgerType == AccountType.equity;
}

/// Optional facts for legacy accounts. Exact detail and tax IDs are retained;
/// reporting labels never replace the ledger's posting type or tax calculations.
final class AccountProfile {
  const AccountProfile({
    this.reportingType,
    this.detailType,
    this.description = '',
    this.defaultTaxCodeId,
  });
  final ReportingAccountType? reportingType;
  final String? detailType;
  final String description;
  final EntityId? defaultTaxCodeId;

  List<String> errorsFor(AccountType ledgerType) => [
    if (reportingType != null && reportingType!.ledgerType != ledgerType)
      'The reporting classification must match the ledger type.',
    if ((reportingType == null) != (detailType == null) ||
        reportingType != null && !reportingType!.details.contains(detailType))
      'Choose a detail type belonging to the selected account type.',
    if (description.length > 4000) 'Account description is too long.',
  ];

  Map<String, Object?> toJson() => {
    'version': 1,
    'reportingType': reportingType?.name,
    'detailType': detailType,
    'description': description,
    'defaultTaxCodeId': defaultTaxCodeId?.value,
  };

  factory AccountProfile.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['description'] is! String ||
        value['reportingType'] != null && value['reportingType'] is! String ||
        value['detailType'] != null && value['detailType'] is! String ||
        value['defaultTaxCodeId'] != null &&
            value['defaultTaxCodeId'] is! String) {
      throw const FormatException('Account profile is invalid.');
    }
    return AccountProfile(
      reportingType: value['reportingType'] == null
          ? null
          : ReportingAccountType.values.byName(
              value['reportingType'] as String,
            ),
      detailType: value['detailType'] as String?,
      description: value['description'] as String,
      defaultTaxCodeId: value['defaultTaxCodeId'] == null
          ? null
          : EntityId.parse(value['defaultTaxCodeId'] as String),
    );
  }
}

final class Account {
  Account._({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.isParent,
    required this.isSystem,
    required this.parentId,
    required this.openingBalance,
    required this.profile,
  });

  factory Account.create({
    required EntityId id,
    required String code,
    required String name,
    required AccountType type,
    AccountStatus status = AccountStatus.active,
    bool isParent = false,
    bool isSystem = false,
    EntityId? parentId,
    Money? openingBalance,
    AccountProfile? profile,
  }) {
    return Account._(
      id: id,
      code: code.trim(),
      name: name.trim(),
      type: type,
      status: status,
      isParent: isParent,
      isSystem: isSystem,
      parentId: parentId,
      openingBalance: openingBalance,
      profile: profile,
    );
  }

  final EntityId id;
  final String code;
  final String name;
  final AccountType type;
  final AccountStatus status;
  final bool isParent;
  final bool isSystem;
  final EntityId? parentId;
  final Money? openingBalance;
  final AccountProfile? profile;

  String get displayName => '$code · $name';

  List<String> get validationErrors {
    final errors = <String>[...?profile?.errorsFor(type)];
    if (code.isEmpty) {
      errors.add('An account code is required.');
    }
    if (name.isEmpty) {
      errors.add('An account name is required.');
    }
    if (parentId == id) {
      errors.add('An account cannot be its own parent.');
    }
    return List.unmodifiable(errors);
  }

  static List<String> validateParent({
    required Account child,
    required Account parent,
  }) {
    final errors = <String>[];
    if (child.parentId != parent.id) {
      errors.add('The parent relationship does not match the child.');
    }
    if (child.id == parent.id) {
      errors.add('An account cannot be its own parent.');
    }
    if (!parent.isParent) {
      errors.add('Only parent accounts can contain subaccounts.');
    }
    if (parent.type != child.type) {
      errors.add('Parent and child accounts must use the same type.');
    }
    if (parent.status != AccountStatus.active) {
      errors.add('A locked or archived account cannot be a parent.');
    }
    return List.unmodifiable(errors);
  }
}
