import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:audyt/core/money/money.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money editor groups thousands without changing the decimal value', () {
    const formatter = AccountingMoneyInputFormatter(2);
    const entered = TextEditingValue(
      text: '1234.56',
      selection: TextSelection.collapsed(offset: 7),
    );
    final result = formatter.formatEditUpdate(
      const TextEditingValue(),
      entered,
    );
    expect(result.text, '1,234.56');
    expect(result.selection.baseOffset, result.text.length);
    expect(Money.fromDecimal(result.text, 'MYR').minorUnits, 123456);
  });

  test('money editor respects zero and three decimal currencies', () {
    expect(
      const AccountingMoneyInputFormatter(0)
          .formatEditUpdate(
            const TextEditingValue(text: '123'),
            const TextEditingValue(text: '123.4'),
          )
          .text,
      '123',
    );
    expect(formatAccountingMoneyInputText('1234.567', 3), '1,234.567');
  });
}
