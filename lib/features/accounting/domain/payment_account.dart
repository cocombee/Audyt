import '../../../../core/money/currency.dart';
import '../../../../core/money/currency_presentation.dart';

String normalizeAccountName(String value) {
  final trimmed = value.trim();
  return capitalizeAccountNameFirstLetter(trimmed);
}

String capitalizeAccountNameFirstLetter(String value) {
  final firstLetter = RegExp(r'[A-Za-z]').firstMatch(value);
  if (firstLetter == null) return value;
  final letter = firstLetter.group(0)!;
  if (letter == letter.toUpperCase()) return value;
  return value.replaceRange(
    firstLetter.start,
    firstLetter.end,
    letter.toUpperCase(),
  );
}

enum PaymentAccountType { cash, bank, card, wallet, other }

extension PaymentAccountTypeLabel on PaymentAccountType {
  String get label => switch (this) {
    PaymentAccountType.cash => 'Cash',
    PaymentAccountType.bank => 'Bank',
    PaymentAccountType.card => 'Card',
    PaymentAccountType.wallet => 'Wallet',
    PaymentAccountType.other => 'Other',
  };
}

final class PaymentAccount {
  PaymentAccount._({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.accountNumber,
    required this.accountHolderName,
    required this.bankId,
    required this.bankName,
  });

  factory PaymentAccount.create({
    required String id,
    required String name,
    required PaymentAccountType type,
    required String currencyCode,
    String accountNumber = '',
    String accountHolderName = '',
    String? bankId,
    String? bankName,
  }) {
    final normalizedName = normalizeAccountName(name);
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'An account name is required.');
    }
    return PaymentAccount._(
      id: id,
      name: normalizedName,
      type: type,
      currency: Currency.parse(currencyCode.trim()),
      accountNumber: accountNumber.trim(),
      accountHolderName: accountHolderName.trim(),
      bankId: bankId?.trim().isEmpty == true ? null : bankId?.trim(),
      bankName: bankName?.trim().isEmpty == true ? null : bankName?.trim(),
    );
  }

  final String id;
  final String name;
  final PaymentAccountType type;
  final Currency currency;
  final String accountNumber;
  final String accountHolderName;
  final String? bankId;
  final String? bankName;

  String get shortName => name.replaceFirst(
    RegExp(r'\s+(?:Sdn\.?\s*Bhd\.?|Pte\.?\s*Ltd\.?)$', caseSensitive: false),
    '',
  );

  String get displayLabel =>
      '$name · ${type.label} · ${CurrencyPresentation.fromCode(currency.code).amountSymbol}';
}
