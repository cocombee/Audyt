import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter/material.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('next voucher refreshes accounts from the persistence owner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final accounts = <PaymentAccount>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentVouchersPage(
            store: PaymentVoucherStore(),
            accounts: const [],
            loadAccounts: () => List.of(accounts),
            onPaymentAccountSave: accounts.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voucher-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voucher-add-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-account-bank')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment-account-bank-option-maybank')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-account-name')),
      'Persistent Bank',
    );
    await tester.tap(find.byKey(const ValueKey('payment-account-create')));
    await tester.pumpAndSettle();
    expect(accounts.single.name, 'Persistent Bank');
    await tester.tap(find.byKey(const ValueKey('voucher-editor-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voucher-discard-changes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Persistent Bank'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final fail in [false, true]) {
    testWidgets('voucher account creation persistence failure=$fail', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <PaymentAccount>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentVoucherEditorDialog(
              id: 'test-voucher',
              onSaveDraft: (_) {},
              onSubmit: (_) {},
              onPaymentAccountSave: (account) {
                if (fail) throw StateError('Unavailable');
                saved.add(account);
              },
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('voucher-account')));
      await tester.tap(find.byKey(const ValueKey('voucher-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voucher-add-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-account-bank')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment-account-bank-option-maybank')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment-account-name')),
        'Voucher Bank',
      );
      await tester.tap(find.byKey(const ValueKey('payment-account-create')));
      await tester.pumpAndSettle();
      if (fail) {
        expect(saved, isEmpty);
        expect(find.textContaining('Voucher Bank'), findsNothing);
        expect(
          find.text(
            'Payment account could not be saved. Check storage and try again.',
          ),
          findsOneWidget,
        );
      } else {
        expect(saved.single.name, 'Voucher Bank');
        expect(find.textContaining('Voucher Bank'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
