import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/pay_bills_proposal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Pay Bills proposal totals custom allocations and only fits ordinary headers at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: const Scaffold(body: PayBillsProposal()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-field-Payment Account')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-field-Payment Date')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('design-field-Reference')),
          findsOneWidget,
        );
        for (final removed in [
          'Counterparty',
          'Amount',
          'Amount Applied to Document',
          'Credit To Apply',
          'Payment Not Applied',
          'How to Match Payment',
          'Payment Method',
        ]) {
          expect(find.byKey(ValueKey('design-field-$removed')), findsNothing);
        }
        final payment = find.byKey(const ValueKey('pay-bills-payment-0'));
        expect(
          tester.widget<TextField>(payment).decoration!.prefixIcon,
          isNull,
        );
        expect(tester.getSize(payment).width, lessThan(240));
        expect(find.text('1000.00'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('pay-bills-credit-0')),
          '100.00',
        );
        await tester.pumpAndSettle();
        expect(find.text('Check Allocations'), findsOneWidget);
        await tester.enterText(payment, '500.00');
        await tester.pumpAndSettle();
        expect(find.text('900.00'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('pay-bills-select-1')),
        );
        await tester.tap(find.byKey(const ValueKey('pay-bills-select-1')));
        await tester.pumpAndSettle();
        expect(find.text('500.00'), findsWidgets);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('pay-bills-payment-1')),
              )
              .enabled,
          isFalse,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('design-field-Payment Account')),
        );
        await tester.tap(
          find.byKey(const ValueKey('design-field-Payment Account')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fictional Credit Card'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-field-Reference')),
          findsNothing,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pay-bills-payment-0')), findsNothing);
        expect(find.text('Total Payment (RM)'), findsOneWidget);
        expect(find.text('Keep Preview'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('accounting-form-dialog-footer')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
