import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines a distinct shadcn typography and surface hierarchy', () {
    final theme = AccountingTheme.light();
    final textTheme = theme.textTheme;

    expect(
      textTheme.headlineMedium!.fontSize,
      greaterThan(textTheme.titleLarge!.fontSize!),
    );
    expect(
      textTheme.titleLarge!.fontSize,
      greaterThan(textTheme.labelLarge!.fontSize!),
    );
    expect(
      textTheme.labelLarge!.fontSize,
      lessThan(textTheme.bodySmall!.fontSize!),
    );
    expect(
      theme.inputDecorationTheme.helperStyle!.fontSize,
      lessThanOrEqualTo(textTheme.labelLarge!.fontSize!),
    );
    expect(theme.cardTheme.elevation, 0);
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    expect(
      (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(accountingSectionRadius),
    );
  });

  testWidgets(
    'Record Expense uses the shared add action and selector primitives',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      final addPayee = find.byKey(const ValueKey('expense-add-payee'));
      final addAccount = find.byKey(const ValueKey('expense-add-account'));
      expect(addPayee, findsNothing);
      await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
      await tester.pumpAndSettle();
      expect(tester.widget<MenuItemButton>(addPayee).onPressed, isNotNull);
      expect(tester.getSize(addPayee).height, greaterThanOrEqualTo(44));
      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      expect(addAccount, findsOneWidget);
      expect(find.byType(MenuAnchor), findsWidgets);
      expect(
        find.byKey(const ValueKey('expense-category-control')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('expense-tax-control')), findsOneWidget);
    },
  );

  testWidgets(
    'selector menu is attached, inset, rounded, selected, and keyboard-safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      final trigger = find.byKey(const ValueKey('expense-tax-control'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey('expense-tax-menu'));
      expect(menu, findsOneWidget);
      expect(find.byType(MenuItemButton), findsWidgets);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(
        find.descendant(
          of: menu,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
        ),
        findsWidgets,
      );

      final triggerRect = tester.getRect(trigger);
      final menuRect = tester.getRect(menu);
      expect(menuRect.left, greaterThanOrEqualTo(0));
      expect(menuRect.right, lessThanOrEqualTo(960));
      expect((menuRect.top - triggerRect.bottom).abs(), lessThanOrEqualTo(8));
      expect(menuRect.width, closeTo(triggerRect.width, 12));

      final anchor = tester.widget<MenuAnchor>(
        find.ancestor(of: trigger, matching: find.byType(MenuAnchor)).first,
      );
      final menuStyle = anchor.style!;
      expect(
        menuStyle.shape!.resolve(<WidgetState>{}),
        isA<RoundedRectangleBorder>(),
      );
      expect(
        (menuStyle.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(10),
      );
      expect(
        menuStyle.padding!.resolve(<WidgetState>{}),
        const EdgeInsets.all(4),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
    },
  );

  testWidgets('Claims and Payment Vouchers reuse the same selector contract', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ClaimsPage(
          store: ClaimStore(
            claims: [
              for (var n = 0; n < 6; n++)
                Claim.fromJson({
                  ...ClaimStore.demo().all.first.toJson(),
                  'id':
                      '00000000-0000-4000-8000-${(n + 1).toString().padLeft(12, '0')}',
                }),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MenuAnchor), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('claims-filter')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-selector-menu-scroll')),
      findsOneWidget,
    );
    expect(find.byType(MenuItemButton), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentVouchersPage(
          store: PaymentVoucherStore(
            vouchers: [
              for (var n = 0; n < 6; n++)
                PaymentVoucher.fromJson({
                  ...PaymentVoucherStore.demo().all.first.toJson(),
                  'id': 'voucher-test-$n',
                }),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuAnchor), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('payment-voucher-filter')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-selector-menu-scroll')),
      findsOneWidget,
    );
    expect(find.byType(MenuItemButton), findsWidgets);
  });

  testWidgets(
    'selector surfaces stay inside a narrow viewport and preserve targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const AudytApp(initialPath: '/record-expense'));
      await tester.pumpAndSettle();

      for (final key in <String>[
        'expense-tax-control',
        'expense-category-control',
        'record-expense-save',
        'record-expense-cancel',
      ]) {
        expect(
          tester.getSize(find.byKey(ValueKey<String>(key))).height,
          greaterThanOrEqualTo(44),
        );
      }

      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-tax-control')),
      );
      await tester.tap(find.byKey(const ValueKey('expense-tax-control')));
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('expense-tax-menu'));
      expect(menu, findsOneWidget);
      expect(tester.getRect(menu).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );
}
