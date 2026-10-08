import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/core/money/currency_presentation.dart';

import '../domain/bank_catalog.dart';
import '../domain/payment_account.dart';

Future<PaymentAccount?> showPaymentAccountDialog(
  BuildContext context, {
  required String preferredCurrencyCode,
  required String Function() newId,
  required Widget Function(BuildContext, String, bool) buildLabel,
  PaymentAccount? initial,
}) async {
  final accountNumberController = TextEditingController(
    text: initial?.accountNumber,
  );
  final holderNameController = TextEditingController(
    text: initial?.accountHolderName,
  );
  final nameController = TextEditingController(text: initial?.name);
  BankProfile? selectedBank = initial?.bankId == null
      ? null
      : BankCatalog.malaysian
            .where((bank) => bank.id == initial!.bankId)
            .firstOrNull;
  CurrencyPresentation? selectedCurrency = initial == null
      ? null
      : CurrencyPresentation.fromCode(initial.currency.code);
  final fieldChanges = Listenable.merge([
    accountNumberController,
    holderNameController,
    nameController,
  ]);
  final bankFieldKey = GlobalKey();
  final typeFieldKey = GlobalKey();
  final currencyFieldKey = GlobalKey();
  var type = initial?.type ?? PaymentAccountType.bank;
  String? error;
  var errorField = 'bank';

  final route = DialogRoute<PaymentAccount>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final supportedCurrencies = <CurrencyPresentation>[];
          if (selectedBank != null) {
            for (final code in selectedBank!.supportedCurrencyCodes) {
              final presentation = CurrencyPresentation.byCurrency[code];
              if (presentation != null) supportedCurrencies.add(presentation);
            }
          }

          void setError(String field, String message) {
            setDialogState(() {
              errorField = field;
              error = message;
            });
          }

          return CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(dialogContext).pop(),
            },
            child: AccountingDialog.alert(
              dialogContext,
              widthFamily: AccountingPopoutWidthFamily.normal,
              title: initial == null ? 'Add Account' : 'Edit Account',
              formFooter: true,
              description: initial == null
                  ? 'Choose the bank and enter the details used to validate statements.'
                  : 'Review the bank details used to validate imported statements.',
              content: SizedBox(
                width: AccountingPopoutTokens.normalContentWidth,
                child: AnimatedBuilder(
                  animation: fieldChanges,
                  builder: (context, _) => SingleChildScrollView(
                    child: AccountingOrdinaryFields(
                      fields: [
                        AccountingOrdinaryFieldSlot(
                          label: 'Bank *',
                          hasGuidance: true,
                          choices: [
                            'Select bank',
                            for (final bank in BankCatalog.malaysian)
                              bank.displayName,
                          ],
                          builder: (width) => Column(
                            key: bankFieldKey,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              accountingFieldLabel(
                                context,
                                'Bank *',
                                alignToField: true,
                                guidance: 'Choose a bank from the local Malaysian bank catalogue; no live connection.',
                              ),
                              const SizedBox(height: 8),
                              AccountingSelector<BankProfile>(
                                assignedWidth: width,
                                options: <AccountingSelectorOption<BankProfile>>[
                                  for (final bank in BankCatalog.malaysian)
                                    AccountingSelectorOption<BankProfile>(
                                      value: bank,
                                      label: bank.displayName,
                                      key: ValueKey<String>(
                                        'payment-account-bank-option-${bank.id}',
                                      ),
                                    ),
                                ],
                                value: selectedBank,
                                onChanged: (bank) {
                                  if (bank == null) return;
                                  setDialogState(() {
                                    selectedBank = bank;
                                    final preferredCode =
                                        selectedCurrency?.code ??
                                        preferredCurrencyCode;
                                    selectedCurrency =
                                        bank.supportsCurrency(preferredCode)
                                        ? CurrencyPresentation.fromCode(
                                            preferredCode,
                                          )
                                        : null;
                                    error = null;
                                  });
                                },
                                hintText: 'Select bank',
                                controlKey: const ValueKey(
                                  'payment-account-bank-control',
                                ),
                                triggerKey: const ValueKey(
                                  'payment-account-bank',
                                ),
                                menuKey: const ValueKey(
                                  'payment-account-bank-menu',
                                ),
                                menuTitle: 'Choose a bank',
                                menuTitleKey: const ValueKey(
                                  'payment-account-bank-menu-title',
                                ),
                                searchable: true,
                                searchKey: const ValueKey(
                                  'payment-account-bank-search',
                                ),
                                searchHintText: 'Search Malaysian banks',
                                emptyText: 'No matching Malaysian banks',
                                errorText: errorField == 'bank' ? error : null,
                                semanticsLabel: 'Bank, required',
                              ),
                            ],
                          ),
                        ),
                        if (selectedBank != null) ...[
                          AccountingOrdinaryFieldSlot(
                            label: 'Account type',
                            choices: [
                              'Select account type',
                              for (final value in PaymentAccountType.values)
                                value.label,
                            ],
                            builder: (width) => Column(
                              key: typeFieldKey,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                buildLabel(context, 'Account type', false),
                                const SizedBox(height: 8),
                                AccountingSelector<PaymentAccountType>(
                                  assignedWidth: width,
                                  options:
                                      <
                                        AccountingSelectorOption<
                                          PaymentAccountType
                                        >
                                      >[
                                        for (final value
                                            in PaymentAccountType.values)
                                          AccountingSelectorOption<
                                            PaymentAccountType
                                          >(value: value, label: value.label),
                                      ],
                                  value: type,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() => type = value);
                                  },
                                  hintText: 'Select account type',
                                  controlKey: const ValueKey(
                                    'payment-account-type-control',
                                  ),
                                  triggerKey: const ValueKey(
                                    'payment-account-type',
                                  ),
                                  menuKey: const ValueKey(
                                    'payment-account-type-menu',
                                  ),
                                  semanticsLabel: 'Account type',
                                ),
                              ],
                            ),
                          ),
                          AccountingOrdinaryFieldSlot(
                            label: 'Account currency *',
                            hasGuidance: true,
                            choices: [
                              if (selectedCurrency == null)
                                'Select account currency',
                              for (final option in supportedCurrencies)
                                option.amountSymbol,
                            ],
                            builder: (width) => Column(
                              key: currencyFieldKey,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                accountingFieldLabel(
                                  context,
                                  'Account currency *',
                                  alignToField: true,
                                  guidance:
                                      'Supported by ${selectedBank!.displayName}.',
                                ),
                                const SizedBox(height: 8),
                                AccountingSelector<CurrencyPresentation>(
                                  assignedWidth: width,
                                  options:
                                      <
                                        AccountingSelectorOption<
                                          CurrencyPresentation
                                        >
                                      >[
                                        for (final option
                                            in supportedCurrencies)
                                          AccountingSelectorOption<
                                            CurrencyPresentation
                                          >(
                                            value: option,
                                            label: option.label,
                                            selectedLabel: option.amountSymbol,
                                            preserveLabelCase: true,
                                            key: ValueKey<String>(
                                              'payment-account-currency-option-${option.code}',
                                            ),
                                          ),
                                      ],
                                  value: selectedCurrency,
                                  onChanged: (currency) {
                                    setDialogState(() {
                                      selectedCurrency = currency;
                                      error = null;
                                    });
                                  },
                                  hintText: 'Select account currency',
                                  controlKey: const ValueKey(
                                    'payment-account-currency-control',
                                  ),
                                  triggerKey: const ValueKey(
                                    'payment-account-currency',
                                  ),
                                  menuKey: const ValueKey(
                                    'payment-account-currency-menu',
                                  ),
                                  menuTitle: 'Choose account currency',
                                  searchable: true,
                                  searchKey: const ValueKey(
                                    'payment-account-currency-search',
                                  ),
                                  searchHintText: 'Search currencies',
                                  emptyText: 'No supported currencies',
                                  errorText: errorField == 'currency'
                                      ? error
                                      : null,
                                  semanticsLabel: 'Account currency, required',
                                ),
                              ],
                            ),
                          ),
                          AccountingOrdinaryFieldSlot(
                            label: 'Account number',
                            hasGuidance: true,
                            contentSample: accountNumberController.text.isEmpty
                                ? '000000000000'
                                : accountNumberController.text,
                            builder: (width) => Column(
                              key: GlobalObjectKey(accountNumberController),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                accountingFieldLabel(
                                  context,
                                  'Account number',
                                  alignToField: true,
                                  guidance: 'Optional. Keep the local account reference with this account.',
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  container: true,
                                  label: 'Account number',
                                  child: TextField(
                                    key: const ValueKey(
                                      'payment-account-number',
                                    ),
                                    controller: accountNumberController,
                                    textInputAction: TextInputAction.next,
                                    decoration: accountingInputDecoration(
                                      context,
                                      hintText: 'Account number',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AccountingOrdinaryFieldSlot(
                            label: 'Account holder name',
                            hasGuidance: true,
                            minimumRowFraction: 0.5,
                            contentSample: holderNameController.text.isEmpty
                                ? 'Fictional Customer'
                                : holderNameController.text,
                            builder: (width) => Column(
                              key: GlobalObjectKey(holderNameController),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                accountingFieldLabel(
                                  context,
                                  'Account holder name',
                                  alignToField: true,
                                  guidance: 'Used with the account number to validate PDF statements.',
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  key: const ValueKey('payment-account-holder'),
                                  controller: holderNameController,
                                  decoration: accountingInputDecoration(
                                    context,
                                    hintText:
                                        'Name printed on the bank statement',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AccountingOrdinaryFieldSlot(
                            label: 'Account name',
                            hasGuidance: true,
                            minimumRowFraction: 0.5,
                            contentSample: nameController.text.isEmpty
                                ? 'Operating Account'
                                : nameController.text,
                            builder: (width) => Column(
                              key: GlobalObjectKey(nameController),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                accountingFieldLabel(
                                  context,
                                  'Account name *',
                                  alignToField: true,
                                  guidance: 'The first letter is capitalized without changing the rest.',
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  container: true,
                                  label: 'Account name, required',
                                  child: TextField(
                                    key: const ValueKey('payment-account-name'),
                                    controller: nameController,
                                    inputFormatters: const <TextInputFormatter>[
                                      _AccountNameTextInputFormatter(),
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onChanged: (_) {
                                      if (errorField == 'name') {
                                        setDialogState(() => error = null);
                                      }
                                    },
                                    decoration: accountingInputDecoration(
                                      context,
                                      errorText: errorField == 'name'
                                          ? error
                                          : null,
                                      hintText: 'Account name',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                AccountingButton.ghost(
                  context,
                  key: null,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                AccountingButton.primary(
                  context,
                  key: const ValueKey('payment-account-create'),
                  onPressed: () {
                    if (selectedBank == null) {
                      setError('bank', 'Choose a bank to continue.');
                      return;
                    }
                    if (selectedCurrency == null) {
                      setError(
                        'currency',
                        'Choose a currency supported by ${selectedBank!.displayName}.',
                      );
                      return;
                    }
                    try {
                      final account = PaymentAccount.create(
                        id: initial?.id ?? newId(),
                        name: nameController.text,
                        type: type,
                        currencyCode: selectedCurrency!.code,
                        accountNumber: accountNumberController.text,
                        accountHolderName: holderNameController.text,
                        bankId: selectedBank!.id,
                        bankName: selectedBank!.displayName,
                      );
                      Navigator.of(dialogContext).pop(account);
                    } on FormatException {
                      setError(
                        'currency',
                        'Enter a valid three-letter currency code.',
                      );
                    } on ArgumentError catch (exception) {
                      setError('name', exception.message.toString());
                    }
                  },
                  child: Text(
                    initial == null ? 'Create Account' : 'Save Account',
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  // A popped dialog can still build during its exit animation. Its text fields
  // must release these controllers only after the route has left the tree.
  await route.completed;
  accountNumberController.dispose();
  holderNameController.dispose();
  nameController.dispose();
  return result;
}

final class _AccountNameTextInputFormatter extends TextInputFormatter {
  const _AccountNameTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = capitalizeAccountNameFirstLetter(newValue.text);
    return normalized == newValue.text
        ? newValue
        : newValue.copyWith(text: normalized);
  }
}
