import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/routing.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';

void main() {
  testWidgets('expanded notifications stay below the bell in a short window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: DemoCompany(
          child: AccountingShell(
            initialRoute: AccountingRouting.forFeature('home')!,
            workspace: workspace,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bell = find.byKey(const ValueKey('global-notifications'));
    await tester.tap(bell);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notifications-read-more')));
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const ValueKey('notification-panel')),
    );
    final notification = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('notification-') &&
          !key.value.startsWith('notification-divider-') &&
          key.value != 'notification-panel';
    }).first;
    final readMore = tester.getRect(
      find.byKey(const ValueKey('notifications-read-more')),
    );
    // Notification information retains its 8px content inset.
    expect(readMore.width, closeTo(tester.getRect(notification).width, 0.1));
    final title = tester.getRect(find.text('Notifications'));
    expect(title.top - (panel.top - 8), closeTo(22, 0.1));
    expect((panel.bottom + 8) - readMore.bottom, closeTo(8, 0.1));
    expect(tester.getRect(bell).right - panel.right, closeTo(8, 0.1));
    expect(panel.top, greaterThan(tester.getRect(bell).bottom));
    expect(panel.bottom, lessThanOrEqualTo(760));
    await tester.tap(find.byKey(const ValueKey('notifications-read-more')));
    await tester.pumpAndSettle();
    final rows = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('notification-') &&
          !key.value.startsWith('notification-divider-') &&
          key.value != 'notification-panel';
    });
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    final third = tester.getRect(rows.at(2));
    final footer = tester.getRect(
      find.byKey(const ValueKey('notifications-read-more')),
    );
    final greenToGreen = (second.top + 2) - (first.bottom - 2);
    expect(greenToGreen, closeTo(4, 0.1));
    expect((third.top + 2) - (second.bottom - 2), closeTo(greenToGreen, 0.1));
    expect(footer.top - (third.bottom - 2), closeTo(greenToGreen, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification dividers appear only between opened items', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: DemoCompany(
          child: AccountingShell(
            initialRoute: AccountingRouting.forFeature('home')!,
            workspace: workspace,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder dividers() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('notification-divider-');
    });
    Finder notifications() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('notification-') &&
          !key.value.startsWith('notification-divider-') &&
          key.value != 'notification-panel';
    });
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('global-notifications')));
      await tester.pumpAndSettle();
      expect(dividers(), findsNWidgets(i == 2 ? 1 : 0));
      if (i == 2) break;
      await tester.tap(notifications().at(i));
      await tester.pumpAndSettle();
    }
  });

  test(
    'demo workspace has linked posted expenses and balanced ledger',
    () async {
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      final expenses = await w.expenses();
      expect(expenses.length, 16);
      expect(expenses.where((e) => e.isPosted).length, 6);
      final journals = await w.journals();
      expect(journals.length, greaterThan(14));
      final report = await w.report(
        from: DateTime(2000),
        through: DateTime(2200),
      );
      expect(report.expenses, greaterThan(BigInt.from(220500)));
      final today = DateTime.now();
      final monthSales = await w.report(
        from: DateTime.utc(today.year, today.month),
        through: DateTime.utc(today.year, today.month, today.day),
      );
      final yearSales = await w.report(
        from: DateTime.utc(today.year),
        through: DateTime.utc(today.year, today.month, today.day),
      );
      expect(monthSales.revenue, greaterThanOrEqualTo(BigInt.from(68291473)));
      expect(
        yearSales.revenue,
        greaterThanOrEqualTo(
          BigInt.from(today.month == 1 ? 68291473 : 429736518),
        ),
      );
      expect(report.balanceSheetDifference, BigInt.zero);
      expect(report.trialBalanceDebits, report.trialBalanceCredits);
      expect(w.claims.all.length, 16);
      expect(w.vouchers.all.length, 15);
      expect(
        w.claims.all.where((c) => c.status == ClaimStatus.submitted).length,
        10,
      );
      expect(
        w.vouchers.all
            .where((v) => v.status == PaymentVoucherStatus.pendingApproval)
            .length,
        10,
      );
      expect(w.customers().length, 3);
      expect(w.invoiceDrafts().length, 1);
      expect(w.postedInvoices().length, 2);
    },
  );
  testWidgets('demo renders every actual navigation section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final w = await createDemoWorkspace();
    addTearDown(w.dispose);
    for (final id in [
      'home',
      'expenses-vendors',
      'claims',
      'payment-vouchers',
      'sales-customers',
      'banking',
      'reports',
      'accounting',
      'taxes',
      'documents',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: DemoCompany(
            child: AccountingShell(
              key: ValueKey(id),
              initialRoute: AccountingRouting.forFeature(id)!,
              workspace: w,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: id);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expense filters stay inline as the sidebar yields space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: DemoCompany(
          child: AccountingShell(
            initialRoute: AccountingRouting.forFeature('expenses-vendors')!,
            workspace: workspace,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('accounting-navigation-extended-rail')),
      findsOneWidget,
    );
    final filters = [
      for (final name in ['status', 'category', 'payee'])
        tester.getRect(find.byKey(ValueKey('expense-$name-filter'))),
    ];
    for (var i = 1; i < filters.length; i++) {
      if ((filters[i].top - filters[i - 1].top).abs() < 0.1) {
        expect(filters[i].left - filters[i - 1].right, closeTo(20, 0.1));
      } else {
        expect(filters[i].top, greaterThan(filters[i - 1].bottom));
      }
    }
  });

  testWidgets('real demo reviews roll up from tabs to sidebar and bell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final w = await createDemoWorkspace();
    addTearDown(w.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: DemoCompany(
          child: AccountingShell(
            initialRoute: AccountingRouting.forFeature('expenses-vendors')!,
            workspace: w,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = find.byKey(const ValueKey('area-tabs-expenses-vendors'));
    expect(
      find.descendant(of: tabs, matching: find.text('10')),
      findsNWidgets(3),
    );
    final expenses = find.byKey(
      const ValueKey('navigation-item-expenses-vendors'),
    );
    expect(
      find.descendant(of: expenses, matching: find.text('30')),
      findsOneWidget,
    );
    final bell = find.byKey(const ValueKey('global-notification-badge'));
    expect(
      find.descendant(
        of: bell,
        matching: find.text('${40 + w.bankReviewNotificationCount}'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: tabs, matching: find.text('Claims')));
    await tester.pumpAndSettle();
    expect(find.text('1–5 of 16'), findsOneWidget);
    final voucherTab = find.descendant(
      of: tabs,
      matching: find.text('Payment Vouchers'),
    );
    await tester.ensureVisible(voucherTab);
    await tester.tap(voucherTab);
    await tester.pumpAndSettle();
    expect(find.text('1–5 of 15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('global-notifications')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notifications-read-more')),
      findsOneWidget,
    );
    expect(find.text('Claims needing review (10)'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notifications-read-more')));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    await tester.tapAt(const Offset(900, 700));
    await tester.pumpAndSettle();

    final claimAccounts = {
      for (final item in await w.accounts()) item.account.code: item.account.id,
    };
    w.approveClaim(
      reviewedClaim: w.claims.all.firstWhere(
        (claim) => claim.status == ClaimStatus.submitted,
      ),
      requestId: EntityId.random(),
      expenseAccountId: claimAccounts['6000']!,
      liabilityAccountId: claimAccounts['2100']!,
      approvedAt: DateTime.now().toUtc(),
    );
    await tester.pumpAndSettle();
    expect(find.descendant(of: tabs, matching: find.text('9')), findsOneWidget);
    expect(
      find.descendant(of: expenses, matching: find.text('29')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bell,
        matching: find.text('${39 + w.bankReviewNotificationCount}'),
      ),
      findsOneWidget,
    );
    w.vouchers.approve(
      w.vouchers.all
          .firstWhere(
            (voucher) => voucher.status == PaymentVoucherStatus.pendingApproval,
          )
          .id,
      approver: 'Demo Approver',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: tabs, matching: find.text('9')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: expenses, matching: find.text('28')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bell,
        matching: find.text('${38 + w.bankReviewNotificationCount}'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
