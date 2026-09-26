import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'aggregate report totals remain exact beyond stored Money range',
    (tester) async {
      final results = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              results.add(
                formatAccountingMinor(
                  context,
                  BigInt.parse('12000000000000000000'),
                  'MYR',
                ),
              );
              results.add(
                formatAccountingMinor(
                  context,
                  BigInt.parse('-12000000000000000000'),
                  'MYR',
                ),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(results, [
        'RM 120,000,000,000,000,000.00',
        '-RM 120,000,000,000,000,000.00',
      ]);
    },
  );
  testWidgets(
    'minimum signed amount displays exactly without magnitude overflow',
    (tester) async {
      final results = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              results.add(
                formatAccountingMoney(
                  context,
                  Money.fromMinor(-9223372036854775808, 'MYR'),
                ),
              );
              results.add(
                formatAccountingMoney(
                  context,
                  Money.fromMinor(-9223372036854775808, 'JPY'),
                ),
              );
              results.add(
                formatAccountingMoney(context, Money.fromMinor(-12345, 'MYR')),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(results, [
        '-RM 92,233,720,368,547,758.08',
        '-¥9223372036854775808',
        '-RM 123.45',
      ]);
    },
  );
}
