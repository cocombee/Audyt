final class BankProfile {
  const BankProfile({
    required this.id,
    required this.displayName,
    required this.supportedCurrencyCodes,
  });

  final String id;
  final String displayName;
  final List<String> supportedCurrencyCodes;

  bool supportsCurrency(String code) =>
      supportedCurrencyCodes.contains(code.trim().toUpperCase());
}

final class BankCatalog {
  const BankCatalog._();

  static const List<BankProfile> malaysian = <BankProfile>[
    BankProfile(
      id: 'maybank',
      displayName: 'Maybank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD'],
    ),
    BankProfile(
      id: 'cimb-bank',
      displayName: 'CIMB Bank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD', 'AUD'],
    ),
    BankProfile(
      id: 'public-bank',
      displayName: 'Public Bank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD', 'HKD'],
    ),
    BankProfile(
      id: 'rhb-bank',
      displayName: 'RHB Bank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD'],
    ),
    BankProfile(
      id: 'hong-leong-bank',
      displayName: 'Hong Leong Bank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD'],
    ),
    BankProfile(
      id: 'ambank',
      displayName: 'AmBank',
      supportedCurrencyCodes: <String>['MYR', 'USD', 'SGD'],
    ),
    BankProfile(
      id: 'bank-islam',
      displayName: 'Bank Islam',
      supportedCurrencyCodes: <String>['MYR'],
    ),
    BankProfile(
      id: 'bank-rakyat',
      displayName: 'Bank Rakyat',
      supportedCurrencyCodes: <String>['MYR'],
    ),
  ];

  static BankProfile? byId(String id) {
    for (final bank in malaysian) {
      if (bank.id == id) return bank;
    }
    return null;
  }
}
